#!/usr/bin/perl
###########################################################################
# aerohivescraper.pl - Aerohive Scraper Plugin
# Author: Benoit Capelle <capelle@labri.fr>
# Copyright (C) 2013 Benoit Capelle
###########################################################################
# 
# Grabs the Aerohive client table from HiveAPs to insert in to the
# switchports table.
# To use this scraper, create a Read-Only Admin account on your APs
# Tested on hive AP330 firmware 6.1r1
#
# Device Option Hash:
#  $$devref is a hash reference that keeps all the variable passed from
#  the config file to your scraper.  You can choose to implement some or
#  all of these options.  These options are loaded via the -d option,
#  and will be called by 
#
#  $$devref{host}:        scalar - hostname of the device (no domain name)
#  $$devref{fqdn}:        scalar - Fully Qualified Domain Name
#  $$devref{mac}:         bool - gather the mac table
#  $$devref{arp}:         bool - gather the arp table
#  $$devref{v6nt}:        bool - gather IPv6 Neighbor Table
#  $$devref{forcessh}:    bool - force SSH as connection method
#  $$devref{forcetelnet}: bool - force telnet
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
use NetDB;
use Net::SSH::Expect;
use Getopt::Long;
use AppConfig;
use English qw( -no_match_vars );
use Carp;
use strict;
use warnings;

# no nonsense
no warnings 'uninitialized';

my $VERSION     = 1;
my $DEBUG       = 0;
my $scriptName;

# Default Config File
my $config_file = "/etc/netdb.conf";

# Config File Options (Overridden by netdb.conf, optional to implement)
my $use_telnet  = 0;
my $use_ssh     = 1;
my $ipv6_maxage = 10;
my $telnet_timeout = 20;
my $login_timeout = 5;
my $ssh_timeout = 30;

# Device Option Hash
my $devref;

# Channel Usage Ref
my $chanref;

my ( $session, $username, $password );

# CLI Input Variables
my ( $optDevice, $optMacFile, $optInterfacesFile, $optArpFile, $optv6File, $prependNew, $debug_level );

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


############################
# Initialize program state #
############################

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
$scriptName = "$$devref{devtype}scraper.pl";


############################
# Capture Data from Device #
############################

# References to arrays of data to write to files
my ( $mac_ref, $int_ref, $arp_ref, $v6_ref );

print "$scriptName($PID): Connecting to device $$devref{fqdn}\n" if $DEBUG;
connectDevice();


# Get the MAC Table if requested
if ( $$devref{mac} && ( $optMacFile || $optInterfacesFile ) ) {
    print "$scriptName($PID): Getting the WiFi Client Table on $$devref{fqdn}\n" if $DEBUG>1;
    $mac_ref = getMacTable();

    print "$scriptName($PID): Getting the Interface Status Table on $$devref{fqdn}\n" if $DEBUG>1;
    $int_ref = getInterfaceTable();
}

# Get the ARP Table
if ( $$devref{arp} ) {
    print "$scriptName($PID): Getting the ARP Table on $$devref{fqdn}\n" if $DEBUG>1;
    $arp_ref = getARPTable();
}

# Get the IPv6 Table (optional)
if (  $$devref{v6nt} ) {
    print "$scriptName($PID): Getting the IPv6 Neighbor Table on $$devref{fqdn}\n" if $DEBUG>1;
    $v6_ref = getIPV6Table();
}

# terminate session corretly
if ($session){
    $session->close();
}

################################################
# Clean Trunk Data and Save everything to disk #
################################################

print "$scriptName($PID): Writing Data to Disk on $$devref{fqdn}\n" if $DEBUG>1;

# Write data to disk
if ( $int_ref ) {
    writeINT( $int_ref, $optInterfacesFile );
}
if ( $mac_ref ) {
    writeMAC( $mac_ref, $optMacFile );
}
if ( $arp_ref ) {
# Not implemented
#    writeARP( $arp_ref, $optArpFile );
}
if ( $v6_ref ) {
# Not implemented
#    writeIPV6( $v6_ref, $optv6File );
}


## Sample Connect to Device method that obeys the $use_ssh and $use_telnet options
sub connectDevice {

    # connect if ssh option is defined
    if ( !$$devref{forcetelnet} && ( $use_ssh || $$devref{forcessh} ) ) {
	
	# try to connect
	$EVAL_ERROR = undef;
	eval {
	    # Get credentials
	    my ( $user, $pass, $enable ) = getCredentials( $devref );

	    print "SSH: Logging in to $$devref{fqdn}\n" if $DEBUG>3;

	    $session = Net::SSH::Expect->new(
						 host => $$devref{fqdn},
						 password => $pass,
						 user => $user,
						 raw_pty => 1,
						 timeout => $login_timeout,
						);
	    
	    # Login Aerohive
	    $session->login();

	};

	if ($EVAL_ERROR) {
            die "$scriptName($PID): |ERROR|: Could not open SSH session to $$devref{fqdn}: $EVAL_ERROR\n";
        }
	
    }
    
    # connect if telnet method is defined
    elsif ( $use_telnet || $$devref{forcetelnet} ) {
	die "$scriptName($PID): |ERROR|: No telnet handler for this scrapper, please use SSH.\n";
    }
}

# Aerohive Client mapping
#
# Array CSV Format: host,mac,port
sub getMacTable {
    my @mactable;
    my @output;
    my ( $output_ref, $ssid );

    # Capture mac table from device
    $output_ref = ssh_paged_out( "show station" );
    @output = @$output_ref;

    # Process one line at a time
    foreach my $line ( @output ) {
	# Remove paging footers
	$line =~ s/\s--More--\s+\cH+\s+\cH+//g;

	# Match Ifname and SSID
	if ( $line =~ /Ifname=.+, Ifindex=.+, SSID=(.+):/ ) {
	    $ssid   = $1;
	}
	# Match MAC address in xxxxxx-xxxxxx format
	elsif ( $line =~ /([0-9a-fA-F]{4}):([0-9a-fA-F]{4}):([0-9a-fA-F]{4})/ ) { 
	    # Remove leading chars
	    $line = "$1$2$3$'";

	    # Split apart results by whitespace
	    my @mac = split( /\s+/, $line );
	    
	    my @hexadigits = ( $mac[0] =~ m/../g );
	    my $ieeecolon = "$hexadigits[0]:$hexadigits[1]:$hexadigits[2]:$hexadigits[3]:$hexadigits[4]:$hexadigits[5]";
            my ( $vlan_index, $radio_index);
	    my $snr_lt_10 = 0;
	    my $mode_index = 6;
	    my $crypto_index = 7;

	    # When SNR < 10, a gap appears
	    if ( $mac[5] =~ /\($/ ) {
		$snr_lt_10 = 1;
		$mode_index++;
		$crypto_index++;
	    }
            if ( $mac[$mode_index] =~ /wpa2-8021x|wpa2-psk/ ) {
                $vlan_index  = 10 + $snr_lt_10;
                $radio_index = 13 + $snr_lt_10;
            }
            elsif ( $mac[$mode_index] =~ /open/ && $mac[$crypto_index] =~ /none/ ) {
                $vlan_index  = 9 + $snr_lt_10;
                $radio_index = 12 + $snr_lt_10;
            }
            else {
                print "Unknow protocol found: $line\n" if $DEBUG>2;
            }

	    if ( $ssid && $vlan_index && $radio_index ) {
		# mac field output (set -debug 4)
		if ( $DEBUG>3 ) {
		    print "ACCEPTED: $$devref{host},$ieeecolon,$$devref{host},wifi,$ssid-$mac[$vlan_index],$mac[1],$mac[$radio_index],\n";
		}
		
		push( @mactable, "$$devref{host},$ieeecolon,$$devref{host},wifi,$ssid-$mac[$vlan_index],$mac[1],$mac[$radio_index]," );
		$chanref->{$mac[2]}++;
	    }
	}
	else {
	    print "$scriptName($PID): Unmatched mac address data: $line\n" if $DEBUG>4;
	}
    }
    
    # Catch no-data error
    if ( !$mactable[0] ) {
	# Catch an empty but valid client table
	
	# TO DO: Test Chanref
	print STDERR "$scriptName($PID): |Warning|: No Wifi client data received from $$devref{host}: Use netdbctl -debug 3 or higher for more info\n";

	if ( $DEBUG>2 ) {
	    print "DEBUG: Bad mac-table-data: \n@output\n";
	}
	return 0;
    }

    return \@mactable;
}


# Sample Interface Status Table
# 
# Array CSV Format: host,port,status,vlan,description (opt),speed (opt),duplex (opt)
#
# Valid "status" Field States (expandable, recommend connect/notconnect over up/down): 
#     connected,notconnect,sfpAbsent,disabled,err-disabled,monitor,faulty,up,down
#
# Valid "vlan" Field Format: 1-4096,trunk,name
#
# Important: If you can detect a trunk port, put "trunk" in the vlan field.
# This is the most reliable uplink port detection method.
#
sub getInterfaceTable {
    my @intstatus;
    my @output;
    my ( $output_ref, $platform, $wifi0channel, $wifi1channel );

    # Capture platform
    $output_ref = ssh_paged_out( "show version | include Platform:" );
    @output = @$output_ref;

    if ( $output[1] =~ /Platform:\s+(.*)\r$/ ) {
	$platform = $1;
    }

    # Capture radio
    $output_ref = ssh_paged_out( "show acsp | include Wifi" );
    @output = @$output_ref;

    # Process one line at a time
    foreach my $line ( @output ) {
	if ( $line =~ /Wifi0/ ) {
	    my @wifi0     = split( /\s+/, $output[1] );
	    $wifi0channel = $wifi0[2];
	    if ( !$chanref->{$wifi0channel} ) {
		$chanref->{$wifi0channel} = 0;
	    }
	}
	elsif ( $line =~ /Wifi1/ ) {
	    my @wifi1     = split( /\s+/, $output[2] );
	    $wifi1channel = $wifi1[2];
	    if ( !$chanref->{$wifi1channel} ) {
		$chanref->{$wifi1channel} = 0;
	    }
	}
    }

    if ( $platform && $wifi0channel && $wifi1channel ) {

	# int field output (set -debug 4)
	if ( $DEBUG>3 ) {
	    print "ACCEPTED: $$devref{host},$$devref{host},wifi,wifi,$platform,Ch$wifi0channel ".$chanref->{$wifi0channel}."clients / Ch$wifi1channel ".$chanref->{$wifi1channel}."clients,\n";
	}

	push( @intstatus, "$$devref{host},$$devref{host},wifi,wifi,$platform,Ch$wifi0channel ".$chanref->{$wifi0channel}."clients / Ch$wifi1channel ".$chanref->{$wifi1channel}."clients," );
    }
    else {
	print STDERR "$scriptName($PID): |Warning|: No int-status table data received from $$devref{host}: Use netdbctl -debug 3 or higher for more info";
	if ( $DEBUG>2 ) {
	    print "DEBUG: Bad int-status-data: \n@output\n";
	}
	return 0;
    }

    return \@intstatus;
}

# Sample ARP Table
#
# Array CSV Format: IP,mac_address,age,vlan
# 
# Note: Age is not implemented, leave blank or set to 0. Text "Vlan" will be
# stripped if included in Vlan field, VLAN must be a number for now (I may
# implement VLAN names later)
#
sub getARPTable {
    print STDERR "$scriptName($PID): |Warning|: ARP not implemented\n";
    return 0;
}


# Sample IPv6 Neighbor Table
#
# Array CSV Format: IPv6,mac,age,vlan
#
# Age is optional here, throw out $ipv6_maxage if desired before adding to array
#
sub getIPv6Table {
   print STDERR "$scriptName($PID): |Warning|: IPv6 not implemented\n";
   return 0;
}

#---------------------------------------------------------------------------------------------
# Handle paged output
#   Input: (comman)
#       cmd - a command to be executed that may have paged output
#   Output:
#       results - refrence to an array, each element containing a row
#---------------------------------------------------------------------------------------------
sub ssh_paged_out {
    my $cmd = shift;

    my $output;
    my $results_ref;
    my $check = 1;
    my @results;

    $session->send( "$cmd" );

    # handles paging
    while($check){
        # pulls apart each section returned by paging
        $results_ref = break_down_page(\@results);
        @results = @$results_ref;
        # check for cues, but only for 1/10 of a sec.
        $output = $session->peek(0.1);
        # This means we are at the promt
        if($output =~ /^.+#/i){
            $check = undef;
            print "$scriptName($PID): |DEBUG|: Found prompt" if $DEBUG>4;
        }
        # Submit space to continue getting results
        elsif($output =~ /--More--/){
            $session->send( " " );
            print "$scriptName($PID): |DEBUG|: sent   for next page\n" if $DEBUG>4;
            $check = 1;
        }
        # this isn't good but shouldn't break anything
        else {
            $check = 1;
            next;
        }
    }
    return \@results;
} # END sub ssh_paged_out

#---------------------------------------------------------------------------------------------
# Pulls apart each "page" returned by pagaing display
#   Input: (results_ref)
#       results_ref - refrence to an array to store the results
#   Output:
#       results: a refrence to the results array for that page.
#---------------------------------------------------------------------------------------------
sub break_down_page {
    my $results_ref = shift;
    my @results = @$results_ref;
    #my @entry;
    while(my $row = $session->read_line(0.09)){
        #$row =~ s/\r//g;
        print "$scriptName($PID): |DEBUG|: Line: $row\n" if $DEBUG>5;
        push (@results, $row);
    }
    return \@results;
} # END sub break_down_page

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
    $config->define( "ipv6_file=s", "devuser=s", "devpass=s", "datadir=s", "ssh_timeout=s", "telnet_timeout=s" );
    $config->file( "$config_file" );

    # Credentials
    $username = $config->devuser();
    $password = $config->devpass();    

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
    Usage: aerohivescraper.pl [options] 

    Required:
      -d  string       NetDB Devicefile config line

    Note: You can test with just the hostname or something like:
          aerohivescraper.pl -d switch1.local,arp,forcessh 

    Filename Options, defaults to config file settings
      -om file         Gather and output Mac Table to a file
      -oi file         Gather and output interface status data to a file
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

