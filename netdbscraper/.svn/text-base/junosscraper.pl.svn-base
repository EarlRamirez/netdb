#!/usr/bin/perl
##############################################################################
# junosscraper.pl - JunOS Scraper Plugin
# Author: Jonathan Yantis <yantisj@gmail.com>
#         and Andrew Loss <aterribleloss@gmail.com>
# Copyright (C) 2013 Jonathan Yantis
##############################################################################
# 
# Written to fully support EX switches, and gather ARP tables from routers.
# Only support SSH, no telnet support.  Does not support VLAN names yet, only
# VLAN IDs.
#
# You can test it as a standalone script with a line from your devicelist like
# this:
# 
# junosscraper.pl -d switch.domain.com[,arp,vrf-dmz,forcessh] \
# -conf netdb_dev.conf -debug 5
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
##############################################################################
# Versions:
#
#   v1.0 - 2012-05-12 - Fist released
#   v1.2 - 2012-05-18 - Improved debuging
#   v1.3 - 2012-10-01 - Juniper SRX support and IPv6 support
#   v2.0 - 2013-11-05 - Function centralization, new connection methods
#                       formating cleanup, router taging
#
##############################################################################
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
##############################################################################
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

# Other Data
my $session;

# Device Option Hash
my $devref;

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
$scriptName = "junosscraper.pl";

############################
# Capture Data from Device #
############################

# References to arrays of data to write to files
my ( $mac_ref, $int_ref, $arp_ref, $v6_ref );

print "$scriptName($PID): Connecting to device $$devref{fqdn}\n" if $DEBUG;

# Connect to device and define the $session object
connectDevice();

# Get the MAC Table if requested
if ( $$devref{mac} ) {
    print "$scriptName($PID): Getting the MAC Table on $$devref{fqdn}\n" if $DEBUG>1;
    $mac_ref = getMacTable( $devref, $session );

    print "$scriptName($PID): Getting the Interface Status Table on $$devref{fqdn}\n" if $DEBUG>1;
    $int_ref = getInterfaceTable( $devref, $session );
}
# Get the ARP Table
if ( $$devref{arp} ) {
    print "$scriptName($PID): Getting the ARP Table on $$devref{fqdn}\n" if $DEBUG>1;
    $arp_ref = getARPTable( $devref, $session );
}
# Get the IPv6 Table (optional)
if ( $$devref{v6nt} ) {
    print "$scriptName($PID): Getting the IPv6 Neighbor Table on $$devref{fqdn}\n" if $DEBUG>1;
    $v6_ref = getIPv6Table( $devref, $session );
}

################################################
# Clean Trunk Data and Save everything to disk #
################################################

# Use Helper Method to strip out trunk ports
print "$scriptName($PID): Cleaning Trunk Data on $$devref{fqdn}\n" if $DEBUG>1;
$mac_ref = cleanTrunks( $mac_ref, $int_ref );

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
#    running the junOS operating system      #
##############################################

#---------------------------------------------------------------------------------------------
# Connect to Device method that obeys the $use_ssh and $use_telnet options
#---------------------------------------------------------------------------------------------
sub connectDevice {
    # connect if ssh option is defined
    if ( !$$devref{forcetelnet} && ( $use_ssh || $$devref{forcessh} ) ) {
        # Get credentials
        #my ( $user, $pass, $enable ) = getCredentials( $devref );

        my $fqdn = $$devref{fqdn};
        ## DNS Check, Get IP Address, prefer IPv6, croaks if no answer
        my $hostip = getIPfromName( $fqdn );
        print "$scriptName($PID): |DEBUG|: DNS Lookup returned $hostip for $fqdn\n" if $DEBUG>4;
        # Needed for all versions of perl earlier then 5.14 as Net::Telnet does not support v6
        if ( $hostip =~ /:/ ) {
            $use_telnet = undef;
        }
        # Check SSH port
        if ( $use_ssh && testSSH($hostip) ) {
            $EVAL_ERROR = undef;
            eval {
                $session = get_SSH_session($fqdn,"none",$devref);
            };
	        if ($EVAL_ERROR) {
                die "$scriptName($PID): |ERROR|: Could not open SSH session to $$devref{fqdn}: $EVAL_ERROR\n";
            }
        }
    }   
    # connect if telnet method is defined
    elsif ( $use_telnet || $$devref{forcetelnet} ) {
        die "$scriptName($PID): |ERROR|: Telnet is not handleing is not in place for this scrapper, please use SSH.\n";
    }
}

#---------------------------------------------------------------------------------------------
# Get the MAC address table of the device (mac address format does not matter)
# Scrapes MAC table on Juniper switches & routers, currently does not support SRX firewalls
# Array CSV Format: IP,mac_address,age,vlan
#   Input: ($devref,$session)
#       Device Refrence - refrence to a hash of device information
#       Session - session varaible for the connection to a device
#   Output:
#       mactable - array containing the MAC address table
#---------------------------------------------------------------------------------------------
sub getMacTable {
    my $devref = shift;
    my $session = shift;
    my @mactable;
    my @entry;

    # Grab the mac table
    my @cmdresults = SSHCommand( $session, "show ethernet-switching table | no-more" );
    # clean end lines
    my $tmp_ref = compactResults( \@cmdresults );
    
    foreach my $line ( @$tmp_ref ) {
        @entry = split( /\s+/, $line );
        # Match MAC Address and "Authenticated"
        if ( $entry[2] =~ /[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}/ && $entry[5] =~ /\// ) {
            print "$scriptName($PID): |DEBUG|: Accepted MAC Entry: 2:$entry[2],5:$entry[5]\n" if $DEBUG>4;
            push( @mactable, "$$devref{host},$entry[2],$entry[5]" );
        }
        else { 
            print "$scriptName($PID): |DEBUG|: Discarded MAC Entry: 2:$entry[2],5:$entry[5]\n" if $DEBUG>3;
        }
    }
    # Catch no-data error
    if ( !$mactable[0] ) {
        print STDERR "$scriptName($PID): |Warning|: No mac-address table data received from $$devref{host}:".
                    " Use netdbctl -debug 2 for more info, or disable mac-address tables on $$devref{host} ".
                    "in the devicelist.csv with nomac if mac table unsupported on this device.\n";
        if ( $DEBUG>1 ) {
            print "$scriptName($PID): |DEBUG|: Bad mac-table-data: @$tmp_ref\n";
        }
        return 0;
    }

    return \@mactable;
}

#---------------------------------------------------------------------------------------------
# Get the full interface descriptions and port status information on Juniper device
#  Valid "status" Field States (expandable, recommend connect/notconnect over up/down): 
#     connected,notconnect,sfpAbsent,disabled,err-disabled,monitor,faulty,up,down
#  Valid "vlan" Field Format: 1-4096,trunk,name
#  Important: If you can detect a trunk port, put "trunk" in the vlan field. This is the most
#  reliable uplink port detection method.
#
# Array CSV Format: host,port,status,vlan,description (opt),speed (opt),duplex (opt)
#   Input: ($devref,$session)
#       Device Refrence - refrence to a hash of device information
#       Session - session varaible for the connection to a device
#   Output:
#       intstatus - hash of interface statuses on the device
#---------------------------------------------------------------------------------------------
sub getInterfaceTable {
    my $devref = shift;
    my $session = shift;
    my @intstatus;
    my $intref;
    my $host = $$devref{host};

    my @entry;
    my @subentry;

    # Grab the mac table
    my @cmdresults = SSHCommand( $session, "show ethernet-switching interfaces | no-more" );
    # clean end lines
    my $tmp_ref = compactResults( \@cmdresults );

    foreach my $line ( @$tmp_ref ) {
        @entry = split( /\s+/, $line );
        #print "Data: 4:$entry[4], 0:$entry[0]\n"; # s1:$subentry[1], s2:$subentry[2], s3:$subentry[3]\n";
        # Match a port
        if ( $entry[0] =~ /\d+\/\d+/ && $entry[4] ) {
	        my $port = $entry[0];
	        print "$scriptName($PID): |DEBUG|: Accepted Status Entry: 0:$entry[0], 1:$entry[1], 3:$entry[3], , 4:$entry[4]\n" if $DEBUG>3;

	        # Port State
            if ( $entry[1] eq "up" ) {
                $intref->{$port}->{status} = "connected";
            }
            elsif ( $entry[1] eq "down" ) {
                $intref->{$port}->{status} = "notconnect";
            }
            # Trunk or access
            if ( $entry[4] eq "tagged" ) {
                $intref->{$port}->{vlan} = "trunk";
            }
            # Access VLAN ID
            elsif ( $entry[3] =~ /^\d+$/ ) {
                $intref->{$port}->{vlan} = $entry[3];
            }
        }
        else { 
            print "$scriptName($PID): |DEBUG|: Discarded MAC Entry: 2:$entry[2],5:$entry[5]\n" if $DEBUG>3;
        }
    }

    $tmp_ref = undef;
    # Get Descriptions
    @cmdresults = SSHCommand( $session, "show interfaces descriptions | no-more" );
    # clean end lines
    $tmp_ref = compactResults( \@cmdresults );

    foreach my $line ( @$tmp_ref ) {
	    # Split out "port   up down  Description"
        @entry = split( /\s+(up|down)\s+(up|down)\s+/, $line );
        print "$scriptName($PID): |DEBUG|: Description Debug: $entry[0] >> $entry[3]\n" if $DEBUG>3;
        # Strip Commas
        $entry[3] =~ s/\,//g;
        # Save description to logical interface if it is only on physical interface
        if ( $intref->{"$entry[0].0"} ) {
            $intref->{"$entry[0].0"}->{"desc"} = $entry[3];
        }
        # Save logical interface description (overwrites physical on logical)
        if ( $intref->{"$entry[0]"} ) {
            $intref->{"$entry[0]"}->{"desc"} = $entry[3];
        }
    }
    for my $port ( sort keys %$intref ) {
        #print "key: $port\n";
        # Port sanity check for 0/0
        if ( $port =~ /\d+\/\d+/ ) {
            push( @intstatus, "$$devref{host},$port,$intref->{$port}->{status},$intref->{$port}->{vlan},$intref->{$port}->{desc}" );
        }
    }

    return \@intstatus;
} # END sub getInterfaceTable

#---------------------------------------------------------------------------------------------
# Get the ARP table of the device
# Note: Age is not implemented, leave blank or set to 0. Text "Vlan" will be stripped if
# included in Vlan field, VLAN must be a number for now (I may implement VLAN names later)
# Array CSV Format: IP,mac_address,age,vlan
#   Input: ($devref,$session)
#       Device Refrence - refrence to a hash of device information
#       Session - session varaible for the connection to a device
#   Output:
#       ARPTable - array containing the ARP table
#---------------------------------------------------------------------------------------------
sub getARPTable {
    my $devref = shift;
    my $session = shift;
    my @arptable;
    my @entry;
    my $fwFlag;
    my $vlan;

    # Grab the arp table
    my @cmdresults = SSHCommand( $session, "show arp no-resolve | no-more" );
    # clean end lines
    my $tmp_ref = compactResults( \@cmdresults );

    foreach my $line ( @$tmp_ref ) {
        @entry = split( /\s+/, $line );

        if ($entry[4] =~ /[Ff]lags/){
            $fwFlag = 1;
            print "$scriptName($PID): |DEBUG|: Device is a firewall, using alternate parser for vlans.\n" if $DEBUG>4;
        }

        # Match MAC Address and IP Address combo
        if ( $entry[0] =~ /[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}/ && $entry[1] =~ /[0-9]{1,3}(\.[0-9]{1,3}){3}/ ) {
            if( $fwFlag ){
                 # Just grab the logical unit number on firewalls
                if ( $entry[2] =~ /[a-zA-Z]+\d+\.(\d+)/ ) {
                    $entry[2] = "$1";
                    $entry[2] = undef if $1 == 0;
                }
                $vlan = $entry[2];
            }
            else{
                if ( $entry[3] =~ /vlan/ ) {
                    $entry[3] =~ s/vlan\.//;
                }
                # Just grab the logical unit number on routers
                if ( $entry[3] =~ /\d+\/\d+\.(\d+)/ ) {
                    $entry[3] = "$1";
                    $entry[3] = undef if $1 == 0;
                }
                $vlan = $entry[3];
            }
	        print "$scriptName($PID): |DEBUG|: Accepted ARP Entry: MAC:$entry[0], IP:$entry[1], vlan:$vlan\n" if $DEBUG>4;		
            push( @arptable, "$entry[1],$entry[0],0,Vlan$vlan,,$$devref{host}" );
        }
        else { 
            print "$scriptName($PID): |DEBUG|: Discarded ARP Entry: 0:$entry[0], 1:$entry[1], 3:$entry[3]\n" if $DEBUG>3;
        }
    } # END foreach

    # Check for results, output error if no data found
    if ( !$arptable[0] ) {
        print STDERR "$scriptName($PID): |Warning|: No ARP table data received from $$devref{host} ".
                    "(use netdbctl -debug 2 for more info)\n";
        if ( $DEBUG>1 ) {
            print "$scriptName($PID): |DEBUG|: Bad ARP Table Data Received: @$tmp_ref";
        }
        return 0;
    }

    return \@arptable;
} # END sub getARPTable

#---------------------------------------------------------------------------------------------
# Get the IPv6 Neighbors table of the device
# Age is optional here, throw out $ipv6_maxage if desired before adding to array
# Sample IPv6 Neighbor Table Array CSV Format: IPv6,mac,age,vlan
#
#   Input: ($devref,$session)
#       Device Refrence - refrence to a hash of device information
#       Session - session varaible for the connection to a device
#   Output:
#       v6Table - array containing the IPv6 Neighbors table
#---------------------------------------------------------------------------------------------
sub getIPv6Table {
    my $devref = shift;
    my $session = shift;
    my @v6table;
    my @entry;
    my $result;
    my ($ip,$mac,$age,$vlan) = undef;

    # Grab the neighbors table
    my @cmdresults = SSHCommand( $session, "show ipv6 neighbors | no-more" );
    # clean end lines
    my $tmp_ref = compactResults( \@cmdresults );

    foreach my $line ( @$tmp_ref ) {
        @entry = split( /\s+/, $line );
        # save the IP address and MAC address
        if ($entry[0] && $entry[1] =~ /[0-9a-zA-Z]{2}(:[0-9a-zA-Z]{2}){5}/){
            $ip = $entry[0];
            $mac = $entry[1];
            $age = $entry[3];
            if ( $entry[6] =~ /[a-zA-Z]+\d+\.(\d+)/ ) {
                $vlan = "$1";
                $vlan = undef if $1 == 0;
            }
            print "$scriptName($PID): |DEBUG|: Accepting: IP:$ip, MAC:$mac, age:$age, vlan:$vlan\n" if $DEBUG>4;
            $result = "$ip,$mac,$age,$vlan";
            ($ip,$mac,$age,$vlan) = undef;
        }
        # only the IP, store it
        elsif( $entry[0] && (!$entry[1]) ){
            $ip = $entry[0];
            next;
        }
        # no IP on this line, but have MAC address, using IP from other line
        elsif( (!$entry[0]) && $entry[1] =~ /[0-9a-zA-Z]{2}(:[0-9a-zA-Z]{2}){5}/ ){
            $mac = $entry[1];
            $age = $entry[3];
            if ( $entry[6] =~ /[a-zA-Z]+\d+\.(\d+)/ ) {
                $vlan = "$1";
                $vlan = undef if $1 == 0;
            }
            print "$scriptName($PID): |DEBUG|: Accepting: IP:$ip, MAC:$mac, age:$age, vlan:$vlan\n" if $DEBUG>5;
            $result = "$ip,$mac,$age,$vlan";
            ($ip,$mac,$age,$vlan) = undef; # reset all tracking vars
        }
        else{
            print "$scriptName($PID): |DEBUG|: Rejecting: 0:$entry[0], 1:$entry[1], 3:$entry[3], 6:$entry[6]\n" if $DEBUG>5;
            next;
        }
        # Discard all of the FE80 addresses.
        if($result){
            if ($result !~ /^[fF][eE]80:/){
                print "$scriptName($PID): |DEBUG|: Saving: $$devref{host},$result\n" if $DEBUG>4;
                push (@v6table, "$result,,$$devref{host}");
            }
            else{
                print "$scriptName($PID): |DEBUG|: Discarding local link: $result\n" if $DEBUG>5;
            }
            $result = undef;
        }
    } # END foreach line by line

    # Check for results, output error if no data found
    if ( !$v6table[0] ) {
        print STDERR "$scriptName($PID): |Warning|: No IPv6 table data received from $$devref{host} ".
                    "(use netdbctl -debug 2 for more info)\n";
        if ( $DEBUG>1 ) {
            print "$scriptName($PID): |DEBUG|: Bad IPv6 Table Data Received: @$tmp_ref";
        }
        return 0;
    }
    return \@v6table;
} # END sub getIPv6Table

#######################################
##                                   ##
## Parse Config and print usage info ##
##                                   ##
#######################################
#---------------------------------------------------------------------------------------------
# Parse configuration options from $config_file
#---------------------------------------------------------------------------------------------
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
    Usage: junosscraper.pl [options] 

    Required:
      -d  string       NetDB Devicefile config line

    Note: You can test with just the hostname or something like:
          junosscraper.pl -d switch1.local,arp,forcessh 

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

