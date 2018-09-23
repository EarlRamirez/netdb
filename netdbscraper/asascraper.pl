#!/usr/bin/perl
###########################################################################
# asascraper.pl - Cisco ASA Scraper Plugin
# Author: Jonathan Yantis <yantisj@gmail.com>
# Copyright (C) 2013 Jonathan Yantis
###########################################################################
# 
# This script grabs the ARP table from an ASA based device.  It will also match
# up the name interfaces and map to VLAN IDs if they exist. It only supports
# SSH, Telnet support has been dropped.
#
# This script accepts the configuration for a single device from the command
# line.  It is launched on a per device basis by netdbscraper.pl, which is a
# multi-process forking script.  You can also launch it as a stand-alone script
# to do all of your development.
#
# The default NetDB device type is "cisco", and netdbscraper will call
# ciscoscraper.pl on all devices.  If you change the default dev_type variable
# in netdb.conf to "hp" for example, or you add ",devtype=hp" to a specific
# device in the devicelist.csv file, the scraper will call hpscraper.pl instead
# of the default ciscoscraper.pl in those cases.  For all non-default dev_type
# devices, you need to specify the platform in the devicelist.csv file.
#
# This script mainly accepts the -d string which is used to configure all the
# scraper options that are found in devices.csv.  This script also checks with
# the config file netdb.conf for any options, and obeys the -debug and -conf
# variables.  You can implement your own netdb.conf variables on the
# parseConfig() method below.
#
# You can test this as a standalone script with a line from your devicelist like
# this:
#
# asascraper.pl -d switch.domain.com,arp -conf ./netdb_dev.conf -debug 5
#
#
#
## Device Option Hash:
#   $$devref is a hash reference that keeps all the variable passed from
#   the config file to your scraper.  You can choose to implement some or
#   all of these options.  These options are loaded via the -d option,
#   and will be called by 
#
#  $$devref{host}:        scalar - hostname of the device (no domain name)
#  $$devref{fqdn}:        scalar - Fully Qualified Domain Name
#  $$devref{mac}:         bool - gather the mac table
#  $$devref{arp}:         bool - gather the arp table
#  $$devref{v6nt}:        bool - gather IPv6 Neighbor Table
#  $$devref{forcessh}:    bool - force SSH as connection method
#  $$devref{forcetelnet}: bool - force telnet
#  $$devref{vrfs}:        scalar - list of CSV separated VRFs to pull ARP on
#
###########################################################################
# License:
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details:
# http://www.gnu.org/licenses/gpl.txt
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
###########################################################################
use lib ".";
use NetDBHelper;
use Net::SSH::Expect;
use Net::DNS;
use IO::Socket::INET;
use Getopt::Long;
use AppConfig;
use English qw( -no_match_vars );
use Carp;
use strict;
use warnings;

# no nonsense
no warnings 'uninitialized';

my $VERSION     = 2;
my $DEBUG       = 0;
my $scriptName;

# Default Config File
my $config_file = "/etc/netdb.conf";

# Config File Options (Overridden by netdb.conf, optional to implement)
my $use_telnet  = 1;
my $use_ssh     = 1;
my $ipv6_maxage = 10;
my $telnet_timeout = 20;
my $ssh_timeout = 10;
my $username;
my $password;
my $enablepass;

# Other Data
my $session; # SSH Session?

# Device Option Hash
my $devref;

# CLI Input Variables
my ( $optDevice, $optMacFile, $optInterfacesFile, $optArpFile, $optv6File, $prependNew, $debug_level );

# References to arrays of data to write to files
my ( $mac_ref, $int_ref, $arp_ref, $v6_ref );

# Input Options
if ( $ARGV[0] eq "" ) { &usage(); }

GetOptions(
    'd=s'      => \$optDevice,
    'om=s'     => \$optMacFile,
    'oi=s'     => \$optInterfacesFile,
    'oa=s'     => \$optArpFile,
    'o6=s'     => \$optv6File,
    'pn'       => \$prependNew,
    'v'        => \$DEBUG,
    'debug=s'  => \$debug_level,
    'conf=s'   => \$config_file,
          )
or &usage();


#####################################
# Initialize program state (ignore) #
#####################################

# Must submit a device config string
if ( !$optDevice ) {
    print "$scriptName($PID): Error: Device configuration string required\n";
    usage();
}

# Parse Configuration File
parseConfig();

# Set the debug level if specified
if ( $debug_level ) {
    $DEBUG = $debug_level;
}

# Pass config file to NetDBHelper and set debug level
altHelperConfig( $config_file, $DEBUG );

# Prepend option for netdbctl.pl (calls NetDBHelper)
if ( $prependNew ) {
    setPrependNew();
}


# Process the device configuration string
$devref = processDevConfig( $optDevice );

# Make sure host was passed in correctly
if ( !$$devref{host} ) {
    print "$scriptName($PID): Error: No host found in device config string\n\n";
    usage();
}

# Save the script name
$scriptName = "asascraper.pl";



############################
# Capture Data from Device #
############################

# Connect to device and define the $session object
print "$scriptName($PID): Connecting to device $$devref{fqdn}\n" if $DEBUG;
$session = connectDevice( $devref );


# Get the ARP Table
if ( $$devref{arp} ) {
    print "$scriptName($PID): Getting the ARP Table on $$devref{fqdn}\n" if $DEBUG>1;
    $arp_ref = getARPTable( $devref, $session );
}

# Get the IPv6 Table (optional)
#if ( $optV6 ) {
#    print "$scriptName($PID): Getting the IPv6 Neighbor Table on $$devref{fqdn}\n" if $DEBUG>1;
#    $v6_ref = getIPV6Table();
#}



################################################
# Clean Trunk Data and Save everything to disk #
################################################

print "$scriptName($PID): Writing Data to Disk on $$devref{fqdn}\n" if $DEBUG>1;
# Write data to disk
if ( $arp_ref ) {
    writeARP( $arp_ref, $optArpFile );
}


##############################################
# Custom Methods to gather data from devices #
##############################################


## Use the NetDBHelper to handle logins to ASA device via auto ssh method
sub connectDevice {
    
    my $session;
    my $devref = shift;
    my $fqdn   = $$devref{fqdn};
    my $hostip;

    print "$scriptName($PID): Connecting to $fqdn using SSH...\n" if $DEBUG>1;

    my ( $user, $pass, $enable ) = getCredentials( $devref );

    eval {
        $hostip = inet_ntoa(inet_aton($fqdn));
        print "IP for $fqdn:\t$hostip\n\n" if $DEBUG>2;
    };
    
    # DNS Failure
    if ( !$hostip ) {
        die "$scriptName($PID): |ERROR|: DNS lookup failure on $fqdn\n";
    }

    $EVAL_ERROR = undef;
    eval {
	# New SSH method currently broken on ASA devices
        $session = get_SSH_session( $fqdn, "none", $devref );
	#$session = get_cisco_ssh_auto( $fqdn );
    };

    if ($EVAL_ERROR || !$session) {
	die "$scriptName($PID): |ERROR|: Could not open SSH session to $fqdn: $EVAL_ERROR\n";
    }

    # Enable if enable mode
    if ( $enable ) {
        print "$scriptName($PID): Entering enable mode on $fqdn...\n" if $DEBUG>2;
        enable_ssh( $session, $enable );
    }

    # Attempt to turn off paging (old and new version?)
    print "$scriptName($PID): Disable Paging on $fqdn...\n" if $DEBUG>2;
    my @cmdresults = SSHCommand( $session, "terminal pager lines 0" );
    @cmdresults = SSHCommand( $session, "terminal pager 0" );

    # Troubleshooting
    #@cmdresults = SSHCommand( $session, "sh ver" );
    #print "results: @cmdresults";
    #die;

    return $session;
}


# ASA ARP Table (based on old code, somewhat messy)
#
# Array CSV Format: IP,mac_address,age,vlan
# 
# Note: Age is not implemented, leave blank or set to 0. Text "Vlan" will be
# stripped if included in Vlan field, VLAN must be a number for now (I may
# implement VLAN names later)
#
sub getARPTable {
    my $devref = shift;
    my $session = shift;
    my $tmpref;
    my @cmdresults;
    my @tmpResults;
    my @ARPTable;
    my %ASAVlan;
    my %ASAIPs;

    # Get ARP Table
    @cmdresults = SSHCommand( $session, "show arp" );

    getASAVlans( $session, \%ASAVlan );
    getASAIPs( $session, \%ASAIPs );

    $tmpref = &cleanARP( \@cmdresults, 1, \%ASAVlan, \%ASAIPs );
    @ARPTable = ( @ARPTable, @$tmpref );

    # Check for results, output error if no data found
    if ( !$ARPTable[0] ) {
        print STDERR "$scriptName($PID): |ERROR|: No ARP table data received from $$devref{host} (use netdbctl -debug 2 for more info)\n";
        if ( $DEBUG>1 ) {
            print "DEBUG: Bad ARP Table Data Received: @cmdresults";
        }
        return 0;
    }

    return \@ARPTable;
}

sub cleanARP {
    my $results_ref = shift;
    my $asa_arp = shift;
    my $ASAVlan_ref = shift;
    my $ASAIPs_ref = shift;
    my $vrf = shift;
    my @cmdresults = @$results_ref;
    my @splitresults;
    my @ARPTable;
    
    # Fix line ending issues, ARP table parse line by line
    foreach my $results ( @cmdresults ) {                            # parse results
	my @splitresults = split( /\n/, $results );            # fix line endings
	foreach my $line ( @splitresults ) {                  
	    
	    # Strip stray \r command returns
	    $line =~ s/\r//g;
	    # ASA ARP Table parsing, already caught that it's an ASA, check for mac address
	    if ( $line =~ /\s\w+\.\w+\.\w+\s/ ) {
		$line =~ s/\r|\n//;                         # Strip off any line endings
		$line = &parseASAArpResult( $line, $ASAVlan_ref, $ASAIPs_ref );        # format the results
		push( @ARPTable, $line ) if $line;          # save for writing to file
	    }
	}
    }
    return \@ARPTable;
}


# Convert ASA ARP line to netdb format
# format: (ip,mac,age,interface)
sub parseASAArpResult {
    my $line = shift;
    my $ASAVlan_ref = shift;
    my $ASAIPs_ref = shift;
    chomp( $line );
    
    my @arp = split(/\s+/, $line);
    
    # Do Vlan mapping if data is available
    if ( $$ASAVlan_ref{"$arp[1]"} ) {
        $arp[1] = $$ASAVlan_ref{"$arp[1]"};
    }
    
    # Check for name to IP resolution in ARP table
    if ( $$ASAIPs_ref{"$arp[2]"} ) {
        $arp[2] = $$ASAIPs_ref{"$arp[2]"};
    }
    
    # make sure it's an IP in field 2
    if ( $arp[2] =~ /(\d+)(\.\d+){3}/ ) {
        $line = "$arp[2],$arp[3],$arp[4],$arp[1]";
        return $line;
    }
}

# Get ASA Names to Vlan mapping (SSH Only), add to hash
sub getASAVlans {
    my $session = shift;
    my $ASAVlan_ref = shift;
    my @cmdresults;
    my @sLine;

    @cmdresults = SSHCommand( $session, "show nameif" );

    # Fix line ending issues, match name to interface
    foreach my $results (@cmdresults) {                            # parse results
        my @splitresults = split(/\n/,$results);            # fix line endings
        foreach my $line (@splitresults) {                  
	    $line =~ s/\r|\n//;                         # Strip off any line endings
	    @sLine = split( /\s+/, $line );
	    
	    if ( $sLine[0] =~ /Vlan/ ) {
		print "Debug: Matched $sLine[1] to $sLine[0]\n" if $DEBUG>1;
		$$ASAVlan_ref{"$sLine[1]"} = $sLine[0];
	    }
	    # Port Channel format
	    elsif ( $sLine[0] =~ /Port-channel/ ) {
		my @po = split( /\./, $sLine[0] );
		print "Debug: Matched $sLine[1] to $po[1]\n" if $DEBUG>1;
                $$ASAVlan_ref{"$sLine[1]"} = $po[1];
	    }
	}
    }
}


# Get ASA Names to IP mappings
sub getASAIPs {
    my $session = shift;
    my $ASAIP_ref = shift;
    my @cmdresults;
    my @sLine;
    
    @cmdresults = SSHCommand( $session, "show names" );
    
    # Fix line ending issues, match name to interface
    foreach my $results (@cmdresults) {                            # parse results
        my @splitresults = split(/\n/,$results);            # fix line endings
        foreach my $line (@splitresults) {                  
	    $line =~ s/\r|\n//;                         # Strip off any line endings
	    @sLine = split( /\s+/, $line );
	    
	    # If IP is in the second field
	    if ( $sLine[1] =~ /(\d+)(\.\d+){3}/ ) {
		$$ASAIP_ref{"$sLine[2]"} = $sLine[1];

		if ( $DEBUG > 2 ) {
		    print "Debug ASA name: $sLine[2] is $sLine[1]\n";
		}
	    }
	}
    }
}


#####################################
# Parse Config and print usage info #
#####################################

# Parse configuration options from $config_file
sub parseConfig {
    # Create any variables that do not exist to avoid errors
    my $config = AppConfig->new({
                                 CREATE => 1,
                                });

    $config->define( "ipv6_maxage=s", "use_telnet", "use_ssh", "arp_file=s", "mac_file=s", "int_file=s" );
    $config->define( "ipv6_file=s", "datadir=s", "ssh_timeout=s", "telnet_timeout=s" );
    $config->define( "devuser=s", "devpass=s", "enablepass=s" );
    $config->file( "$config_file" );


    # Username and Password
    $username = $config->devuser();
    $password = $config->devpass();
    $enablepass = $config->enablepass();
    
    my ( $pre );
    
    $use_ssh = 1 if $config->use_ssh();
    $use_telnet = 1 if $config->use_telnet();

    # SSH/Telnet Timeouts
    if ( $config->telnet_timeout() ) {
        $telnet_timeout = $config->telnet_timeout();
    }
    if ( $config->ssh_timeout() ) {
        $ssh_timeout = $config->ssh_timeout();
    }

    if ( $config->ipv6_maxage() ) {
        $ipv6_maxage = $config->ipv6_maxage();
    }

   # Prepend files with the keyword new if option is set
    $pre = "new" if $prependNew;

    # Files to write to
    my $datadir                = $config->datadir();

    if ( !$optArpFile && $config->arp_file() ) {
        $optArpFile                = $config->arp_file();
        $optArpFile                = "$datadir/$pre$optArpFile";
    }

    if ( !$optv6File && $config->ipv6_file() ) {
        $optv6File                 = $config->ipv6_file();
        $optv6File                 = "$datadir/$pre$optv6File";
    }

    if ( !$optMacFile && $config->mac_file() ) {
        $optMacFile                = $config->mac_file();
        $optMacFile                = "$datadir/$pre$optMacFile";
    }

    if ( !$optInterfacesFile && $config->int_file() ) {
        $optInterfacesFile                = $config->int_file();
        $optInterfacesFile                = "$datadir/$pre$optInterfacesFile";
    }

}


sub usage {
    print <<USAGE;
    Usage: asascraper.pl [options] 

    Required:
      -d  string       NetDB Devicefile config line

    Note: You can test with just the hostname or something like:
          asascraper.pl -d switch1.local,arp,forcessh 

    Filename Options, defaults to config file settings
      -oa file         Gather and output ARP table to a file
      -o6 file         Gather and output IPv6 Neighbor Table to file
      -pn              Prepend "new" to output files

    Development Options:
      -v               Verbose output
      -debug #         Manually set debug level (1-6)
      -conf            Alternate netdb.conf file

USAGE
    exit;
}

