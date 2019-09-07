#!/usr/bin/perl
###########################################################################
# procurvehpscraper.pl - HP Procurve Scraper Plugin
# Author: Benoit Capelle <capelle@labri.fr>
# Copyright (C) 2013 Benoit Capelle
###########################################################################
# 
# HP Procurve Scraper script for implementing NetDB with HP Procurve devices
#
# How to use:
# 
# procurvehpscraper.pl -d switch.domain.com[,arp,ipv6,nd] \
# -conf netdb_dev.conf -debug 5
#
#
## IF YOU MANAGE TO SUPPORT A THIRD-PARTY DEVICE, please send me your code so I
## can include it for others, even if it's unsupported by you - Thanks.       
#
# Scroll halfway down to ** Edit This Section **
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

my $VERSION     = 2;
my $DEBUG       = 0;
my $scriptName;

# Default Config File
my $config_file = "/etc/netdb.conf";

# Config File Options (Overridden by netdb.conf, optional to implement)
my $use_telnet  = 0;
my $use_ssh     = 1;
my $ipv6_maxage = 10;
my $telnet_timeout = 20;
my $ssh_timeout = 10;
my $username;
my $password;

# Other Data
my $session; # SSH Session?

# Device Option Hash
my $devref;

# CLI Input Variables
my ( $optDevice, $optMacFile, $optInterfacesFile, $optArpFile, $optv6File, $optNDFile, $prependNew, $debug_level );

# References to arrays of data to write to files
my ( $mac_ref, $int_ref, $arp_ref, $v6_ref, $nd_ref );

# Input Options
if ( $ARGV[0] eq "" ) { &usage(); }

GetOptions(
    'd=s'      => \$optDevice,
    'om=s'     => \$optMacFile,
    'oi=s'     => \$optInterfacesFile,
    'oa=s'     => \$optArpFile,
    'o6=s'     => \$optv6File,
    'on=s'     => \$optNDFile,
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
$scriptName = "procurvehpscraper.pl";



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
if ( $$devref{arp} ) {
    print "$scriptName($PID): Getting the ARP Table on $$devref{fqdn}\n" if $DEBUG>1;
    $arp_ref = getARPTable();
}

# Get the IPv6 Table
if ( $$devref{v6nt} ) {
    print "$scriptName($PID): Getting the IPv6 Neighbor Table on $$devref{fqdn}\n" if $DEBUG>1;
    $v6_ref = getIPv6Table();
}

# Get the Neighbors
if ( $$devref{nd} ) {
    print "$scriptName($PID): Getting the Neighbor Discovery Table on $$devref{fqdn}\n" if $DEBUG>1;
    $nd_ref = getNeighbors();
}


################################################
# Clean Trunk Data and Save everything to disk #
################################################

# Use Helper Method to strip out trunk ports
if ( $$devref{mac} ) {
    print "$scriptName($PID): Cleaning Trunk Data on $$devref{fqdn}\n" if $DEBUG>1;
    $mac_ref = cleanTrunks( $mac_ref, $int_ref );
}

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
if ( $nd_ref ) {
    writeND( $nd_ref, $optNDFile );
}


## Sample Connect to Device method that obeys the $use_ssh and $use_telnet options
sub connectDevice {

    # connect if ssh option is defined
    if ( !$$devref{forcetelnet} && ( $use_ssh || $$devref{forcessh} ) ) {
	
	## Try to connect to a device
	#
	# Put your login code here, sample generic SSH connection code
	$EVAL_ERROR = undef;
	eval {
	    # connect to device via SSH only using Library Method
	    $session = attempt_ssh( $$devref{fqdn}, $username, $password );


	    # SAMPLE CODE, generic device examples, initialize connection
	    my @output;

            # Enter Enable Mode
            #@output = SSHCommand( $session, "enable" );
            #@output = SSHCommand( $session, "$password" );

            # Turn off paging
            @output = SSHCommand( $session, "no page" );

	    # Sample Command with results
	    #@output = SSHCommand( $session, "show version" );

	    # Optional manual interaction with device
	    #@output = $session->send( "show version" );
	    #$session->waitfor( 'prompt#', 20 ); #timeout 
	    #@output = $session->before();


	    ## Print Sample Output
	    #print "sample code output: @output\n\n";

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

# Sample Mac Table Scraper Method (mac address format does not matter)
#
# Array CSV Format: host,mac,port
sub getMacTable {
    my @mactable;
    my @output;

    # Capture mac table from device
    @output = SSHCommand( $session, "show mac-address" );

    # Results returned in one scalar, split out
    @output = split( /\r/, $output[0] );

    # Process one line at a time
    foreach my $line ( @output ) {

      # Match MAC address in xxxxxx-xxxxxx format
      if ( $line =~ /([0-9a-fA-F]{6})-([0-9a-fA-F]{6})/ ) {

	# Remove leading chars
	$line = "$1$2$'";

	# Split apart results by whitespace
	my @mac = split( /\s+/, $line );

	my @hexadigits = ( $mac[0] =~ m/../g );
	my $ieeecolon = "$hexadigits[0]:$hexadigits[1]:$hexadigits[2]:$hexadigits[3]:$hexadigits[4]:$hexadigits[5]";

	# mac field output (set -debug 4)
	if ( $DEBUG>3 ) {
	    print "MAC Entry Debug:\n0: $mac[0]\n1: $mac[1]\n\n"
	}

	push( @mactable, "$$devref{host},$ieeecolon,$mac[1]" );
      }
      else {
	  print "$scriptName($PID): Unmatched mac address data: $line\n" if $DEBUG>4;
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

    # Capture interfaces status
    @output = SSHCommand( $session, "show interfaces custom all status enabled port:16 vlan:5 name:32 speed:7" );

    # Results returned in one scalar, split out
    @output = split( /\r/, $output[0] );

    # Process one line at a time
    foreach my $line ( @output ) {

	# If line contains int status
	if ( $line =~ /\s(Up|Down)\s+(Yes|No)\s+(.{16})\s+(.{5})\s+(.{32})\s+(.{7})$/ ) {

	    my $status  = $1;
	    my $enabled = $2;
	    my $port    = $3;
	    my $vlan    = $4;
	    my $type    = $5;
	    my $speed   = $6;

	    # Right trim
	    $port  =~ s/\s+$//;
	    $vlan  =~ s/\s+$//;
	    $type  =~ s/\s+$//;
	    $speed =~ s/\s+$//;

	    # int field output (set -debug 4)
	    if ( $DEBUG>3 ) {
		print "Interface Entry Debug:\n0: $status\n1: $enabled\n2: $port\n3: $vlan\n4: $type\n5: $speed\n\n"
	    }
	    my $state;

	    if ( $enabled =~ /No/ ) {
		$state = 'disabled';
	    }
	    elsif ( $status =~ /Up/ ) {
		$state = 'connected';
	    }
	    elsif ( $status =~ /Down/ ) {
		$state = 'notconnect';
	    }

	    if( $state ) {
		if( $vlan =~ /multi/ ) {
		    $vlan = 'trunk';
		}
		if( $port =~ /^(.+)-(Trk\d+)$/ ) {
		    $port = $1;
		    if ( !$vlan ) {
			$vlan = 'trunk';
		    }
		    push( @intstatus, "$$devref{host},$2,$state,$vlan,$type,," );
		}

		if( $vlan ) {
		    push( @intstatus, "$$devref{host},$port,$state,$vlan,$type,$speed," );
		}
	    }
	}
	else {
	    print "$scriptName($PID): Unmatched interface data: $line\n" if $DEBUG>4;
	}
    }

    # Catch no-data error
    if ( !$intstatus[0] ) {
	print STDERR "$scriptName($PID): |Warning|: No int-status table data received from $$devref{host}: Use netdbctl -debug 3 or higher for more info, " . 
	    "or disable int-status tables on $$devref{host} in the devicelist.csv with noint if int status unsupported on this device.\n";
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
    my @arptable;
    my @vlantable;
    my @output;

    # Capture vlan table from device
    @output = SSHCommand( $session, "show vlans custom id state" );

    # Results returned in one scalar, split out
    @output = split( /\r/, $output[0] );

    # Process one line at a time
    foreach my $line ( @output ) {

	# Match active vlan number
	if ( $line =~ /\s(\d+)\s+Up/ && grep {/^$1$/} (1..4096) ) {
	    push( @vlantable, $1);
	}

    }

    foreach my $vlan ( @vlantable ) {
	# Capture vlan arp table from device
	@output = SSHCommand( $session, "show arp vlan $vlan" );

	# Results returned in one scalar, split out
	@output = split( /\r/, $output[0] );

	# Process one line at a time
	foreach my $line ( @output ) {

	    if ( $line =~ /([0-9]{1,3}\.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3})\s+([0-9a-fA-F]{6})-([0-9a-fA-F]{6})/ ) {

		my $ip = $1;
		my $mac = "$2$3";

		my @hexadigits = ( $mac =~ m/../g );
		my $ieeecolon = "$hexadigits[0]:$hexadigits[1]:$hexadigits[2]:$hexadigits[3]:$hexadigits[4]:$hexadigits[5]";

		# arp field output (set -debug 4)
		if ( $DEBUG>3 ) {
		    print "MAC Entry Debug:\n0: $ip\n1: $ieeecolon\n2: 0\n3: $vlan\n\n"
		}

		push( @arptable, "$ip,$ieeecolon,0,Vlan$vlan" );
	    }
	}
    }


    # Catch no-data error
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
    my @vlantable;
    my @output;

    # Capture vlan table from device
    @output = SSHCommand( $session, "show vlans custom id state" );

    # Results returned in one scalar, split out
    @output = split( /\r/, $output[0] );

    # Process one line at a time
    foreach my $line ( @output ) {

	# Match active vlan number
	if ( $line =~ /\s(\d+)\s+Up/ && grep {/^$1$/} (1..4096) ) {
	    push( @vlantable, $1);
	}

    }

    foreach my $vlan ( @vlantable ) {

	# Capture ipv6 table from device
	@output = SSHCommand( $session, "show ipv6 neighbors vlan $vlan" );

	# Results returned in one scalar, split out
	@output = split( /\r/, $output[0] );

	# Process one line at a time
	foreach my $line ( @output ) {

	    # Dirty IPv6 and MAC address in xxxxxx-xxxxxx format match
	    if ( $line =~ /\s+([0-9a-fA-F]{1,4}:?([0-9a-fA-F]{0,4}:?){1,7})\s+([0-9a-fA-F]{6})-([0-9a-fA-F]{6})/ ) {

		# Remove leading chars
		$line = "$1 $3$4 $'";

		# Split apart results by whitespace
		my @v6 = split( /\s+/, $line );
	
		my @hexadigits = ( $v6[1] =~ m/../g );
		my $ieeecolon = "$hexadigits[0]:$hexadigits[1]:$hexadigits[2]:$hexadigits[3]:$hexadigits[4]:$hexadigits[5]";
	
		# mac field output (set -debug 4)
		if ( $DEBUG>3 ) {
		    print "IPv6 Entry Debug:\n0: $v6[0]\n1: $v6[1]\n2: $v6[4]\n\n"
		}

		if ( $v6[4] ) {
		    push( @v6table, "$v6[0],$ieeecolon,,Vlan$vlan" );
		}

	    }
	    # Match local link address
	    elsif ( $line =~ /\s+(fe80:([0-9a-fA-F]{0,4}:?){1,7})\%vlan$vlan\s+([0-9a-fA-F]{6})-([0-9a-fA-F]{6})/ ) {

		# Remove leading chars
		$line = "$1 $3$4 $'";

		# Split apart results by whitespace
		my @v6 = split( /\s+/, $line );

		my @hexadigits = ( $v6[1] =~ m/../g );
		my $ieeecolon = "$hexadigits[0]:$hexadigits[1]:$hexadigits[2]:$hexadigits[3]:$hexadigits[4]:$hexadigits[5]";
	
		# mac field output (set -debug 4)
		if ( $DEBUG>3 ) {
		    print "IPv6 Entry Debug:\n0: $v6[0]\n1: $v6[1]\n2: $v6[4]\n\n"
		}

		if ( $v6[4] ) {
		    push( @v6table, "$v6[0],$ieeecolon,,Vlan$vlan" );
		}

	    }
	    else {
		print "$scriptName($PID): Unmatched ipv6 data: $line\n" if $DEBUG>4;
	    }
	}
    }

    # Catch no-data error
    if ( !$v6table[0] ) {
	print STDERR "$scriptName($PID): |Warning|: No ipv6 table data received from $$devref{host}: Use netdbctl -debug 3 or higher for more info, " . 
	    "or disable ipv6 tables on $$devref{host} in the devicelist.csv if ipv6 table unsupported on this device.\n";
	if ( $DEBUG>2 ) {
	    print "DEBUG: Bad ipv6-table-data: \n@output\n";
	}
	return 0;
    }

    return \@v6table;
}


# Scrape all link-level neighbor discovery data from device
sub getNeighbors {
    my @ndtable;
    my @porttable;
    my @output;

    # Capture lldp table from device
    @output = SSHCommand( $session, "show lldp info remote-device" );

    # Results returned in one scalar, split out
    @output = split( /\r/, $output[0] );

    # Process one line at a time
    foreach my $line ( @output ) {

	# Match local port
	if ( $line =~ /\s([A-Z]?\d+)\s+\|/ ) {
	    push( @porttable, $1);
	}

    }

    foreach my $port ( @porttable ) {

	# Capture more info from device
	@output = SSHCommand( $session, "show lldp info remote-device $port" );

	# Results returned in one scalar, split out
	@output = split( /\r/, $output[0] );

	my ( $remote_host, $remote_ip, $remote_soft, $remote_model, $remote_port );

	# Process one line at a time
	foreach my $line ( @output ) {
	    if ( $line =~ /SysName\s+: (.+)$/ ) {
		$remote_host = $1;
		$remote_host =~ s/\s+$//;
	    }
	    elsif ( $line =~ /Address : ([0-9]{1,3}\.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3})/ ) {
		$remote_ip = $1;
	    }
	    elsif ( $line =~ /System Descr : .+Switch (.+), revision (.+),/ ) {
		$remote_soft  = $1;
		$remote_model = $2;
	    }
	    elsif ( $line =~ /System Descr :/ ) {
		$remote_soft  = 'unknown';
		$remote_model = 'unknown';
	    }
	    # Use PortDescr over PortId if available
	    elsif ( $line =~ /PortDescr\s+: ([0-9A-Za-z|\/]+)/ ) {
		$remote_port = $1;
	    }
	    elsif ( !$remote_port && $line =~ /PortId\s+: ([0-9A-Za-z]+)/ ) {
		$remote_port = $1;
	    }

	    if ( $remote_host && $remote_ip && $remote_soft && $remote_model && $remote_port) {
		push( @ndtable, "$$devref{host},$port,$remote_host,$remote_ip,$remote_soft,$remote_model,$remote_port,lldp" );
		last;
	    }
	}
    }

    return \@ndtable;
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

    $config->define( "ipv6_maxage=s", "use_ssh", "arp_file=s", "mac_file=s", "int_file=s" );
    $config->define( "ipv6_file=s", "nd_file=s", "datadir=s", "ssh_timeout=s" );
    $config->define( "devuser=s", "devpass=s" );
    $config->file( "$config_file" );


    # Username and Password
    $username = $config->devuser();
    $password = $config->devpass();

    my ( $pre );
    
    $use_ssh = 1 if $config->use_ssh();

    # Global Neighbor Discovery Option
    $optDevice = "$optDevice,nd" if $config->use_nd();

    # SSH Timeouts
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

    if ( !$optNDFile && $config->nd_file() ) {
        $optNDFile                 = $config->nd_file();
        $optNDFile                 = "$datadir/$pre$optNDFile";
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
    Usage: procurvehpscraper.pl [options] 

    Required:
      -d  string       NetDB Devicefile config line

    Note: You can test with just the hostname or something like:
          skeletonscraper.pl -d switch1.local,arp,forcessh 

    Filename Options, defaults to config file settings
      -om file         Gather and output Mac Table to a file
      -oi file         Gather and output interface status data to a file
      -oa file         Gather and output ARP table to a file
      -o6 file         Gather and output IPv6 Neighbor Table to file
      -on file         Gather and output Neighbor Discovery data to file
      -pn              Prepend "new" to output files

    Development Options:
      -v               Verbose output
      -debug #         Manually set debug level (1-6)
      -conf            Alternate netdb.conf file

USAGE
    exit;
}

