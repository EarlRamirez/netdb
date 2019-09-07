#!/usr/bin/perl
###########################################################################
# catosscraper.pl - CatOS Scraper
# Author: Jonathan Yantis <yantisj@gmail.com>
# Copyright (C) 2013 Jonathan Yantis
###########################################################################
# 
# SSHv1 Support Only
#
# You can test this as a standalone script with a line from your devicelist like
# this:
#
# catosscraper.pl -d switch.domain.com[,arp,vrf-dmz,forcessh] \
# -conf netdb_dev.conf -debug 5
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
use Getopt::Long;
use AppConfig;
use English qw( -no_match_vars );
use Carp;
use strict;
use warnings;

# no nonsense
no warnings 'uninitialized';

my $VERSION     = 3;
my $DEBUG       = 0;
my $scriptName;

# Default Config File
my $config_file = "/etc/netdb.conf";

# Config File Options (Overridden by netdb.conf, optional to implement)
my $use_telnet  = 1;
my $use_ssh     = 1;
my $ssh_session;
my $ipv6_maxage = 10;
my $telnet_timeout = 20;
my $ssh_timeout = 10;
my $username;
my $password;

# Other Data
my $session; # SSH Session

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
$scriptName = "catosscraper.pl";



############################
# Capture Data from Device #
############################

# Connect to device and define the $session object
print "$scriptName($PID): Connecting to device $$devref{fqdn}\n" if $DEBUG;
connectDevice();

# Get the MAC Table if requested
if ( $$devref{mac} ) {
    print "$scriptName($PID): Getting the MAC Table on $$devref{fqdn}\n" if $DEBUG>1;
    $mac_ref = getMacTable();

    print "$scriptName($PID): Getting the Interface Status Table on $$devref{fqdn}\n" if $DEBUG>1;
    $int_ref = getInterfaceTable();
}

# Get the ARP Table
#if ( $$devref{arp} ) {
#    print "$scriptName($PID): Getting the ARP Table on $$devref{fqdn}\n" if $DEBUG>1;
#    $arp_ref = getARPTable();
#}

# Get the IPv6 Table (optional)
#if ( $optV6 ) {
#    print "$scriptName($PID): Getting the IPv6 Neighbor Table on $$devref{fqdn}\n" if $DEBUG>1;
#    $v6_ref = getIPV6Table();
#}



################################################
# Clean Trunk Data and Save everything to disk #
################################################

# Use Helper Method to strip out trunk ports
print "$scriptName($PID): Cleaning Trunk Data on $$devref{fqdn}\n" if $DEBUG>1;
$mac_ref = cleanTrunks( $mac_ref, $int_ref );


# Development: Die before writing to files
#die "Remove Me: don't write to files yet\n";


print "$scriptName($PID): Writing Data to Disk on $$devref{fqdn}\n" if $DEBUG>1;
# Write data to disk
if ( $int_ref ) {
    writeINT( $int_ref, $optInterfacesFile );
}
if ( $mac_ref ) {
    writeMAC( $mac_ref, $optMacFile );
}
if ( $arp_ref ) {
    writeARP( $arp_ref, $optArpFile );
}
if ( $v6_ref ) {
    writeIPV6( $v6_ref, $optv6File );
}


##############################################
# Custom Methods to gather data from devices #
#                                            #
#          **Edit This Section**             #
##############################################


## Sample Connect to Device method that obeys the $use_ssh and $use_telnet options
sub connectDevice {

    # connect if ssh option is defined
    if ( !$$devref{forcetelnet} && ( $use_ssh || $$devref{forcessh} ) ) {
	
        # try to connect
        $EVAL_ERROR = undef;
        eval {
	    
	    
            # Get a new cisco session object
            print "SSH: Logging in to $$devref{fqdn}\n" if $DEBUG>3;
	    
            $session = Net::SSH::Expect->new(
					     host => $$devref{fqdn},
					     password => $password,
					     user => $username,
					     raw_pty => 1,
					     timeout => $ssh_timeout,
					     ssh_option => "-1",
					    );
	    
            # Login CatOS
            $session->login();
	    
	    
            # Turn off paging
            my @output = SSHCommand( $session, "set length 0" );
	    
	    $ssh_session = 1;

        };
	
        if ($EVAL_ERROR) {
            die "$scriptName($PID): |ERROR|: Could not open SSH session to $$devref{fqdn}: $EVAL_ERROR\n";
        }
	
    }
    
    # connect if telnet method is defined
    elsif ( $use_telnet || $$devref{forcetelnet} ) {
        print "$scriptName($PID): Could not SSH to $$devref{fqdn} on port 22, trying telnet\n" if $DEBUG && $use_ssh;
	
	eval {
	    $session = Net::Telnet::Cisco->new( Host => $$devref{fqdn},
						Timeout => $ssh_timeout,
						  );
	    
	};
	
	if ( $EVAL_ERROR ) {
	    croak("\nNetwork Error: Failed to connect to $$devref{fqdn}");
	}
	
	my $myprompt = '/(?m:[\w.-]+\s?(?:\(config[^\)]*\))?\s?[\$#>]\s?(?:\(enable\))?\s*$)/';
	
	$session->prompt( $myprompt );
	
	# Log in to the router
	$session->login(
			Name     => $username,
			Password => $password,
			Timeout  => $ssh_timeout,
		       );
	
	my @output = $session->cmd( String => "set length 0" ); # no-more
	print "Debug terminal length: @output" if $DEBUG>1;
        return $session;
    }
}

# Sample Mac Table Scraper Method (mac address format does not matter)
#
# Array CSV Format: host,mac,port
sub getMacTable {
    my @mactable;
    my @output;

    $EVAL_ERROR = undef;
    eval {

        # SSH Command
        if ( $ssh_session ) {
            @output = SSHCommand( $session, "show cam dynamic" );
            @output = split( /\n/, $output[0] );
        }
	
        # Telnet
        else {
            @output = $session->cmd( String => "show cam dynamic" );
        }
    };

    # Process one line at a time
    foreach my $line ( @output ) {

	# Match MAC address in xx:xx:xx:xx:xx:xx or cisco format
	if ( $line =~ /(\w\w\-){5}|(\w\w\w\w\.\w\w\w\w\.\w\w\w\w)/ ) {

	    # Delete any preceeding spaces
            $line =~ s/^\s+//;

	    # Split apart results by whitespace
	    my @mac = split( /\s+/, $line );

	    # mac field output (set -debug 4)
	    if ( $DEBUG>3 ) {
		print "MAC Entry Debug:\n0: $mac[0]\n1: $mac[1]\n2: $mac[2]\n3: $mac[3]\n4:$mac[4]\n5: $mac[5]\n6: $mac[6]\n\n"
	    }

	    # Add parsed mac data entry to @mactable array (switch,mac,port)
	    #
	    # Filter out system mac addresses before adding data to the table
	    # Run sanity checks on data before accepting it
	    if ( $mac[2] =~ /\d+\/\d+/ 
		 && $mac[0] =~ /\d+/
	       ) {
		print "debug: acceptable data: $$devref{host},$mac[1],$mac[2]\n" if $DEBUG>4;		
		push( @mactable, "$$devref{host},$mac[1],$mac[2]" );
	    }

	    elsif ( $mac[0] =~ /d+/ && $mac[4] =~ /^\d+\/\d+$/ ) {
		print "debug: acceptable data: $$devref{host},$mac[1],$mac[4]\n" if $DEBUG>4;
                push( @mactable, "$$devref{host},$mac[1],$mac[4]" );
	    }
	}
	else {
	    print "$scriptName($PID): Unmatched mac address data: $line\n" if $DEBUG>3;
	}
    }

    # Catch no-data error
    if ( !$mactable[0] ) {
        print STDERR "$scriptName($PID): |Warning|: No mac-address table data received from $$devref{host}: Use netdbctl -debug 3 or higher for more info, " . 
	"or disable mac-address tables on $$devref{host} in the devicelist.csv with nomac if mac table unsupported on this device.\n";
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

    $EVAL_ERROR = undef;
    eval {

        # SSH Command
        if ( $ssh_session ) {
            @output = SSHCommand( $session, "show port status" );
            @output = split( /\n/, $output[0] );
        }

        # Telnet
        else {
            @output = $session->cmd( String => "show port status" );
        }
    };
    
    # Process one line at a time
    foreach my $line ( @output ) {

	my $status = undef;

	# Sample data:
	#  2/4                     connected  99         normal a-full a-1Gb 10/100/1000
        #  2/5                     notconnect 99         normal   auto  auto 10/100/1000

        # Match keyword connect
	$status = "connected" if $line =~ /\sconnected\s/;
	$status = "notconnect" if $line =~ /\snotconnect\s/;

        if ( $status ) {

	    print "Debug: Status entry $status: $line\n";

	    # Delete any preceeding spaces
	    $line =~ s/^\s+//;

	    my @int  = split( /connected|notconnect/, $line );

	    my ( $port, $desc ) = split( /\s+/, $int[0] ); 

	    # Strip leading spaces
	    $int[1]  =~ s/^\s+//;

	    @int = split( /\s+/, $int[1] );

            # int field output (set -debug 4)
            if ( $DEBUG>3 ) {
                print "Interface Entry Debug:\nport: $port \ndesc: $desc \nstatus: $status\n0: $int[0]\n1: $int[1]\n2: $int[2]\n3: $int[3]\n4:$int[4]\n5: $int[5]\n6: $int[6]\n\n"
            }
	    
	    print "debug: acceptable int data: $$devref{host},$port,$status,$int[0],$desc,$int[3],$int[2]\n" if $DEBUG>4;
	    push( @intstatus, "$$devref{host},$port,$status,$int[0],$desc,$int[3],$int[2]" );

	}
	else {
	    print "Debug: Unmatched int data: $line\n" if $DEBUG>3;
	}
    }

    # sample entries
    #$intstatus[0] = "$$devref{host},Eth1/1/1,connected,20,Sample Description,10G,Full";
    #$intstatus[1] = "$$devref{host},Po100,notconnect,trunk,,,";

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
    my @arptable;
    my @output;

    # Sample entries
    $arptable[0] = "1.1.1.1,1111.2222.3333,0,20";
    $arptable[1] = "2.2.2.2,11:11:22:22:33:44,0,Vlan50";

    # Sample VRF gathering, process each VRF ARP table one at a time
    if ( $$devref{vrfs} ) {
	my @vrfs = split( /\,/, $$devref{vrfs} );

	foreach my $vrf ( @vrfs ) {
	    print "Sample Gather data from VRF: $vrf\n";
	    $arptable[2] = "2.2.2.5,11:11:22:22:33:55,,Vlan60";
	}
    }

    # Check for results, output error if no data found
    if ( !$arptable[0] ) {
        print STDERR "$scriptName($PID): |ERROR|: No ARP table data received from $$devref{host} (use netdbctl -debug 2 for more info)\n";
        if ( $DEBUG>1 ) {
            print "DEBUG: Bad ARP Table Data Received: @output";
        }
        return 0;
    }

    return \@arptable;
}


# Sample IPv6 Neighbor Table
#
# Array CSV Format: IPv6,mac,age,vlan
#
# Age is optional here, throw out $ipv6_maxage if desired before adding to array
#
sub getIPv6Table {
    my @v6table;

    # sample entries
    $v6table[0] = "2002:48::1,1111.2222.3333,5,20";
    $v6table[1] = "2002:48::2,11:11:22:22:33:44,5,50";

    return \@v6table;
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
    $config->define( "devuser=s", "devpass=s" );
    $config->file( "$config_file" );


    # Username and Password
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
    Usage: skeletonscraper.pl [options] 

    Required:
      -d  string       NetDB Devicefile config line

    Note: You can test with just the hostname or something like:
          skeletonscraper.pl -d switch1.local,arp,forcessh 

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

