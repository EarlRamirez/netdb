#!/usr/bin/perl
###############################################################################
# nxosscraper.pl - Cisco NX-OS Scraper Based on IOS Scraper
# Author: Jonathan Yantis <yantisj@gmail.com> 
#         and Andrew Loss <aterribleloss@gmail.com>
# Copyright (C) 2014 Jonathan Yantis
###############################################################################
# 
# This code was originally part of netdbscraper.pl before it was broken out to
# support multiple vendors.  It's designed to be called by netdbscraper.pl, but
# also can run as a standalone script to gather the data for a single device.
# Look at skeletonscraper.pl for general understanding of how device modules
# work, and refer to this one for anything cisco specific.
#
###############################################################################
#
# How to run in standalone mode:
#  ./ciscoscraper.pl -om /tmp/mac.txt -oi /tmp/int.txt -oa /tmp/arp.txt \
#  -debug 3 -d switch,arp
#
# Where -d "switch,arp" is a line from your config file
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
#  $$devref{vrfs}:        scalar - list of CSV separated VRFs to pull ARP on
#
###############################################################################
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
###############################################################################
# Used for development, work against the non-production NetDB library in 
# the current directory if available
use lib ".";
use NetDBHelper;
use Getopt::Long;
use AppConfig;
use English qw( -no_match_vars );
use strict;
use warnings;

# no nonsense
no warnings 'uninitialized';

my $scriptName;
my $DEBUG      = 0;

# Default Config File
my $config_file = "/etc/netdb.conf";

# Config File Options (Overridden by netdb.conf, optional to implement)
my $use_telnet  = 0;
my $use_ssh     = 0;
my $telnet_timeout = 20;
my $ssh_timeout = 10;
#my $ipv6_maxage = 10;
my $ipv6_maxage = 0;
my $enablepasswd;  # The enable passwd

# Device Option Hash
my $devref;

my ( $ssh_session, $maxMacs );

# CLI Input Variables
my ( $optDevice, $optMacFile, $optInterfacesFile, $optArpFile, $optv6File, $optNDFile, $prependNew, $debug_level );

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

############################
# Initialize program state #
############################

if ( !$optDevice ) {
    print "Error: Device configuration string required\n";
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
    print "Error: No host found in device config string\n\n";
    usage();
}

$scriptName = "nxosscraper.pl";

############################
# Capture Data from Device #
############################

# References to arrays of data to write to files
my ( $mac_ref, $int_ref, $arp_ref, $v6_ref, $desc_ref, $nd_ref );

print "$scriptName($PID): Connecting to device $$devref{fqdn}\n" if $DEBUG;
my $session = connectDevice( $devref );

if ( $session ) {
    # Get the hostname from the switch if requested
    if ( $$devref{gethost} ) {
        print "$scriptName($PID): Getting hostname on $$devref{fqdn}\n" if $DEBUG>1;
        $$devref{host} = getHost( $devref, $session );
    }
    # Get the ARP Table
    if ( $$devref{arp} ) {
        print "$scriptName($PID): Getting the ARP Table on $$devref{fqdn}\n" if $DEBUG>1;
        $arp_ref = getARPTable( $devref, $session );
    }
    # Get the MAC Table if requested
    if ( $$devref{mac} ) {
        print "$scriptName($PID): Getting the Interface Descriptions on $$devref{fqdn}\n" if $DEBUG>1;
        $desc_ref = getDescriptions( $devref, $session );    

        print "$scriptName($PID): Getting the Interface Status Table on $$devref{fqdn}\n" if $DEBUG>1;
        $int_ref = getInterfaceTable( $devref, $session, $desc_ref );

        print "$scriptName($PID): Getting the MAC Table on $$devref{fqdn}\n" if $DEBUG>1;
        $mac_ref = getMacTable( $devref, $session );
    }
    # Get the IPv6 Table (optional)
    if ( $$devref{v6nt} ) {
        print "$scriptName($PID): Getting the IPv6 Neighbor Table on $$devref{fqdn}\n" if $DEBUG>1;
        $v6_ref = getv6Table( $devref, $session );
    }
    # Get the Neighbors
    if ( $$devref{nd} ) {
        print "$scriptName($PID): Getting the Neighbor Discovery Table on $$devref{fqdn}\n" if $DEBUG>1;
        $nd_ref = getNeighbors( $devref, $session );
    }
}
else {
    print "$scriptName($PID): Could not get session on $$devref{fqdn}\n";
    exit;
}
# terminate session correctly before going on to other tasks
if ($session){
    $session->close();
}

################################################
# Clean Trunk Data and Save everything to disk #
################################################

# Use Helper Method to strip out trunk ports

if ( $mac_ref ) {
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

# Output a summary
if ( $DEBUG ) {
    my $p = "$scriptName($PID): Completed ( ";
    $p = $p . "mac " if $$devref{mac};
    $p = $p . "arp " if $$devref{arp};
    chop( $$devref{vrfs} ) if $$devref{vrfs};
    $p = $p . "vrf-$$devref{vrfs} " if $$devref{vrfs};
    $p = $p . "ipv6 " if $$devref{v6nt};
    $p = $p . "ND " if $$devref{nd};
    $p = $p . ") via ";
    $p = $p . "telnet " if !$ssh_session && $use_telnet;
    $p = $p . "ssh " if $ssh_session;
    $p = $p . "on $$devref{fqdn}\n";
    print $p;
}

##############################################
# Methods to gather data from NX-OS devices  #
##############################################

#---------------------------------------------------------------------------------------------
# Get a session on a device
# Checks to see if telnet or ssh is enabled, tries to login and get a $session
#---------------------------------------------------------------------------------------------
sub connectDevice {
    my $session;
    my $devref = shift;
    my $fqdn   = $$devref{fqdn};
    my $hostip;
    my $ssh_enabled;
    my @netcatout;

    # Check for connection type override from config file, ssh or telnet
    if ( $devref ) {
        if ( $$devref{forcessh} ) {
            print "$scriptName($PID): Forcing ssh connection on $fqdn\n" if $DEBUG>1;
            $use_ssh = 1;
            $use_telnet = undef;
        }
        elsif ( $$devref{forcetelnet} ) {
            print "$scriptName($PID): Forcing telnet connection on $fqdn\n" if $DEBUG>1;
            $use_telnet = 1;
            $use_ssh = undef;
        }
    }

    print "$scriptName($PID): Connecting to $fqdn using SSH($use_ssh) Telnet($use_telnet)...\n" if $DEBUG>1;

    ## DNS Check, Get IP Address, prefer IPv6, croaks if no answer
    $hostip = getIPfromName( $fqdn );
    print "$scriptName($PID): |DEBUG|: DNS Lookup returned $hostip for $fqdn\n" if $DEBUG>4;

    # Needed for all versions of perl earlier then 5.14 as Net::Telnet does not support v6
    if ( $hostip =~ /:/ ) {
        $use_telnet = undef;
    }
    # Check SSH port
    if ( $use_ssh && testSSH($hostip) ) {
        $ssh_enabled = 1;
    } 

    # Attempt SSH Session if port is open, return 0 if failure and print to stderr
    if ( $ssh_enabled ) {
        $EVAL_ERROR = undef;
        eval {
            #$session = get_cisco_ssh_auto( $fqdn );
            $session = get_SSH_session( $fqdn, undef, $devref );
            # Attempt to enter enable mode if defined
	        if ( $enablepasswd ) {
                &enable_ssh( $session, $enablepasswd );
            }
            $ssh_session = 1
        };

        if ($EVAL_ERROR || !$session) {
            die "$scriptName($PID): |ERROR|: Could not open SSH session to $fqdn: $EVAL_ERROR\n";
        }
        return $session;
    }
    # Fallback to Telnet if allowed
    elsif ( $use_telnet )  {
        print "$scriptName($PID): Could not SSH to $fqdn on port 22, trying telnet\n" if $DEBUG && $use_ssh;

        # Attempt Session, return 0 if failure and print to stderr
        $EVAL_ERROR = undef;
        eval {
            $session = get_cisco_session_auto( $fqdn, $devref );
        };

        if ($EVAL_ERROR || !$session) {
            $EVAL_ERROR =~ s/\n//g;
            die "$scriptName($PID): |ERROR|: Could not open a telnet session to $fqdn: $EVAL_ERROR";
        }
        return $session;
    }
    # Failed to get a session, report back
    else {
        die "$scriptName($PID): |ERROR|: Failed to get a session on $fqdn, no available connection methods\n";
    }
}

#---------------------------------------------------------------------------------------------
# Get the hosname from the device rather than the devicelist.csv file
#---------------------------------------------------------------------------------------------
sub getHost {
    my $devref = shift;
    my $session = shift;
    my $host = $$devref{host};
    my $switchhost;

    my @cmdresults;

    $EVAL_ERROR = undef;
    eval {
        # SSH Command
        if ( $ssh_session ) {
            @cmdresults = SSHCommand( $session, "show startup-config | include hostname" );
            @cmdresults = split( /\n/, $cmdresults[0] );
        }
        # Telnet
        else {
            @cmdresults = $session->cmd( String => "show startup-config | include hostname" );
        }
    };

    # Get the hostname
    foreach my $line ( @cmdresults ) {
        if ( $line =~ /^hostname\s\w+/ ) {
            chomp( $line );
            $line =~ s/\r//g;
            $line =~ s/^hostname\s//;
            $switchhost = $line;
        }
    } # END foeeach

    # Check for errors
    if ( $EVAL_ERROR || !$switchhost ) {
        print STDERR "$scriptName($PID): |Warning|: Could not gather hostname from $$devref{host}, using devicelist.csv name\n";        
        return $host;
    }
    # Return switch's hostname
    else {
        return $switchhost;
    }
} # END sub getHost

#---------------------------------------------------------------------------------------------
# Get the MAC address table of the device (mac address format does not matter)
# throw out any ports with more than $maxMacs or that is a known trunk port.
# Array CSV Format: host,mac_address,port,,vlan
#   Input: ($devref,$session)
#       Device Refrence - refrence to a hash of device information
#       Session - session varaible for the connection to a device
#   Output:
#       mactable - array containing the MAC address table
#---------------------------------------------------------------------------------------------
sub getMacTable {
    my $devref = shift;
    my $session = shift;
    my $host = $$devref{host};
    my $totalcount;
    my $switchtype;
    my $count = 0;
    my ( $line, $tmp_ref, $mac, $port, $vlan );

    my @cmdresults;
    my @macd;
    my @mactable;
    my @switchMacTable = undef;
    
    # Check for local max_macs settings, override
    if ( $$devref{maxmacs} ) {
        $maxMacs = $$devref{maxmacs};
    }

    ## Capture mac-table 
    #
    # Run the show mac-address-table command and catch issues or report an error
    # and return nothing
    $EVAL_ERROR = undef;
    eval {
        # SSH Command
        if ( $ssh_session ) {
            @cmdresults = SSHCommand( $session, "show mac address-table" );
            # NX-OS Inconsistency Fix for N7k, resolved in recent NX-OS releases
            if ( $cmdresults[0] =~ /Invalid/i | $cmdresults[1] =~ /Invalid/i ) {
                print "$scriptName($PID): |DEBUG|: Caught bad mac-address-table command\n" if $DEBUG>2;
                @cmdresults = SSHCommand( $session, "show mac-address-table" );
            }
        }
        # Telnet Command
        else {
            @cmdresults = $session->cmd( String => "show mac address-table | exclude drop" );
        }
    };
    # Catch telnet bad mac-address command for older NX-OS
    if ( $EVAL_ERROR =~ /show mac address-table/ | $EVAL_ERROR =~ /Invalid/i ) {
        print "$scriptName($PID): |DEBUG|: Caught bad mac-address-table command\n" if $DEBUG>2;

        $EVAL_ERROR = undef;
        eval {
            @cmdresults = $session->cmd( String => "show mac-address-table | exclude drop" );
        };
    }
    # Bad telnet command 
    # Note: SSH doesn't throw eval errors, catch no-data errors below for SSH
    if ($EVAL_ERROR) {
        print STDERR "$scriptName($PID): |Warning|: Could not get mac-address-table on $host".
        " (use -debug 3 for more info): $EVAL_ERROR.\n";
        print "$scriptName($PID): |DEBUG|: Bad mac-table-data: @cmdresults\n" if $DEBUG>2;
        return 0;
    }
    # handle misc. output
    $tmp_ref = compactResults( \@cmdresults );

    ## Process mac-table results
    #
    # Iterate through all mac table entries, splits line on spaces and matches
    # switch specific mac formats based on split data fields
    # 
    # Debug:
    # Set local $DEBUG to level 3 to get @macline array entries for unmatched mac data
    #
    # Note: If you have to write a custom parser for some reason, please email
    # me your elsif statement and device type.  Start your elsif at the bottom
    # as the last elsif switch match to be sure you don't clobber any existing
    # matches. The majority of cisco devices should be covered, but if you find
    # something new, email me at yantisj@gmail.com so I can add it.
    foreach my $line (@$tmp_ref) {
        # Strip out leading asterisk from 6500/nexus output
        $line =~ s/^\*/ /;            
        # Add leading space for consistency on split results
        $line = " $line";
        # Found a line with a mac address, split it and match based on split
        # results.
        if ( $line =~ /\s[0-9a-fA-F]{4}(\.[0-9a-fA-F]{4}){2}\s/ ) {
            # Reset variables
            $port = undef;
            $mac = undef;

            # Split mac data in to fields by spaces
            @macd = split( /\s+/, $line );

            # Extreme DEBUG, print all mac-address fields for bad matched
            # data on all rows
            print "$scriptName($PID): |DEBUG|: Mac Table Fields:\n\t1: ".
            "$macd[1]\n\t2: $macd[2]\n\t3: $macd[2]\n\t3: $macd[3]\n\t4: ".
            "$macd[4]\n\t5: $macd[5]\n\t6: $macd[6]\n\t7: $macd[7]\n\t".
            "8: $macd[8]\n" if $DEBUG>5;

            # Nexus 7000 style mac-tables
            # - Leading asterisk stripped out above
            # - Always leading space
            #
            # Matched Fields: 3=mac, 4=dyn/s, 8=port
            if ( ( $macd[4] eq "dynamic" || $macd[4] eq "static" ) &&
                ( $macd[8] =~ /\d+\/\d+/ || $macd[8] =~ /Po\d+/ ) ) {

                $switchtype = 'c7000';
                $port = $macd[8];
                $mac = $macd[3];
                $vlan = $macd[1];
                ($port) = split(/\,/, $port);
                # Get everything in to the short port format
                $port = normalizePort($port);

                if ( $mac =~ /^\w+\.\w+\.\w+$/ && $port =~ /\d+$/ ) {
                    print "$host $mac $port $vlan\n" if $DEBUG>5;
                    $totalcount++;
                    push( @mactable, "$host,$mac,$port,,$vlan");
                }
            } # END if Nx 7000 style

            # Nexus 5000 4.2+ style, similar to 7000
            # - Leading asterisk stripped out above
            # - Always leading space
            #
            # Matched Fields: 2=mac, 3=dyn/s, 7=port
            elsif ( ( $macd[3] eq "dynamic" || $macd[3] eq "static" ) && 
                ( $macd[7] =~ /\d+\/\d+/ || $macd[7] =~ /Po\d+/ ) ) {

                $switchtype = 'c5000';
                $port = $macd[7];
                $mac = $macd[2];
                $vlan = $macd[1];

                ($port) = split(/\,/, $port);
                # Get everything in to the short port format
                $port = normalizePort($port);

                if ( $mac =~ /^\w+\.\w+\.\w+$/ && $port =~ /\d+$/ ) {
                    print "$host $mac $port $vlan\n" if $DEBUG>5;
                    $totalcount++;
                    push( @mactable, "$host,$mac,$port,,$vlan");
                }
            } # END elsif Nx 5000 style

            # Cisco Nexus 4000 Series Switches for IBM BladeCenter - NX-OS
            # Cisco Nexus 4000 version 4.1 + style
            # 20/7/2012
            # Matched Fields: 2=mac, 5=port
            elsif ( ( $macd[3] eq "dynamic" || $macd[3] eq "static" ) && $macd[4] =~ /\d+/ && 
                ( $macd[5] =~ /Po\d+/ || $macd[5] =~ /Eth\d\/\d+/ ) ) {

                $switchtype = 'n4000i';
                $port = $macd[5];
                $mac = $macd[2];
                $vlan = $macd[1];

                if ( $mac =~ /^\w+\.\w+\.\w+$/ && $port =~ /\d+$/ ) {
                    print "$host $mac $port\n" if $DEBUG>5;
                    $totalcount++;
                    push( @mactable, "$host,$mac,$port,,$vlan");
                }
            } # END elsif Nx 4000 style

            # Older Nexus 5000 style mac-tables
            # Nexus 5000s use Po format for port-channel ports.
            #
            # Matched Fields: 2=mac, 3=s/d, 5=port
            elsif ( ( $macd[3] eq "dynamic" || $macd[3] eq "static" ) && 
                ( $macd[5] =~ /\d+\/\d+/ || $macd[5] =~ /Port-channel\d+/ 
                || $macd[5] =~ /Po\d+/ || $macd[5] =~ /Veth\d+/ ) ) {

                $switchtype = 'c4500';
                $port = $macd[5];
                $mac = $macd[2];
                ($port) = split(/\,/, $port);
                # Get everything in to the short port format
                $port = normalizePort($port);

                if ( $mac =~ /^\w+\.\w+\.\w+$/ && $port =~ /\d+$/ ) {
                    print "$host $mac $port\n" if $DEBUG>5;
                    $totalcount++;
                    push( @mactable, "$host,$mac,$port");
                }
            } # END elsif Older Nx 5000 style

            # Ignore junk mac data in error reporting
            elsif ( $line =~ /(STATIC\s+CPU)|ffff.ffff.ffff|(other\sDrop)|igmp/ ) {
                # Junk mac data, ignore
                print "$scriptName($PID): |DEBUG|: ignoring junk: @macd\n" if $DEBUG>4;
            } # END ignore junk

            # All others unmatched data reports under debug
            # Set debug to 3 to get bad table output as fields
            else {
                print "$scriptName($PID): |DEBUG|: Unmatched Mac Table Fields:\n\t1: $macd[1]\n".
                "\t2: $macd[2]\n\t3: $macd[3]\n\t4: $macd[4]\n\t5: $macd[5]\n\t6: $macd[6]\n".
                "\t7: $macd[7]\n\t8: $macd[8]\n" if $DEBUG>3;

                print "$scriptName($PID): |DEBUG|: unparsed MAC data on $host: @macd\n" if $DEBUG>2;
            }
        } # if MAC is on line
    } # END foreach line by line

    # Catch no-data error
    if ( !$mactable[0] ) {
        print STDERR "$scriptName($PID): |Warning|: No mac-address table data received from $host:".
        " Use netdbctl -debug 2 for more info, or disable mac-address tables on $host in the devicelist.csv".
        " with netdbnomac if unsupported on this device.\n";
        if ( $DEBUG>1 ) {
            print "$scriptName($PID): |DEBUG|: Bad mac-table-data: @cmdresults\n";
        }
        return 0;
    } # END if catach no-data
    
    return \@mactable;
} # END sub getMacTable

########################################
##                                    ##
## Interface Status table subroutines ##
##                                    ##
########################################
#---------------------------------------------------------------------------------------------
# Get the interface descriptions and port status information on NX-OS device
#  Valid "status" Field States (expandable, recommend connect/notconnect over up/down): 
#     connected,notconnect,sfpAbsent,disabled,err-disabled,monitor,faulty,up,down
#  Valid "vlan" Field Format: 1-4096,trunk,name
#  Important: If you can detect a trunk port, put "trunk" in the vlan field. This is the most
#  reliable uplink port detection method.
#
# Array CSV Format: host,port,status,vlan,description (opt),speed (opt),duplex (opt)
#   Input: ($devref,$session)
#       Device Refrence - refrence to a hash of device information
#       Session - session varaible (SSH or Telnet) for the connection to a device
#   Output:
#       intstatus - hash of interface statuses on the device
#---------------------------------------------------------------------------------------------
sub getInterfaceTable {
    my $devref = shift;
    my $session = shift;
    my $descref = shift;
    my $host = $$devref{host};
    my ( $port_desc, $port, $state, $vlan, $speed, $duplex, $desc, $tmp_ref );

    my @cmdresults;
    my @intStatus;
    my @tmp;

    $EVAL_ERROR = undef;
    # Get interface status
    eval {
        if ( $ssh_session ) {
            @cmdresults = SSHCommand( $session, "show interface status" );
        }
        else {
            @cmdresults = $session->cmd( String => "show interface status" );
        }
        # handle misc. output
        $tmp_ref = compactResults( \@cmdresults );
        foreach my $line ( @$tmp_ref ) {
            # If line contains int status
            if ( $line =~ /\s(connected|disabled|notconnect?|faulty|monitor(ing)?|up|down|sfpAbsent|channelDo|noOperMem|err\-disabled)\s/ ) {
                $state = $1;

                # Parse it out, maybe not the cleanest method
                ($port_desc, $line) = split( /\s+$state/, $line);
                # Get port and description
                ($port, $desc) = split( /\s{2,}/, $port_desc );
                $desc = cleanDesc( $desc );
                # Split out the rest
                ( undef, $vlan, $duplex, $speed ) = split( /\s+/, $line );
                # Check for extended description
                if ( $$descref{"$host,$port"} ) {
                    $desc = $$descref{"$host,$port"};
                }

                # Fix short names
                $state = "notconnect" if $state eq "notconnec";
                $state = 'channel-down'  if $state eq "channelDo";
                $state = 'no-members'  if $state eq "noOperMem";

                # If there's a proper match
                if ( $vlan ) {
                    push( @intStatus, "$host,$port,$state,$vlan,$desc,$speed,$duplex" );
                    #print "INTOUTPUT: $host,$port,$state,$vlan,$desc,$speed,$duplex\n";
                }
            } # END if int status
        } # END foreach line by line
    }; # END eval
    if ($EVAL_ERROR) {
        print STDERR "$scriptName($PID): |Warning|: Could not get interface status on $host\n";
    }

    return \@intStatus;
} # END sub getInterfaceTable
#---------------------------------------------------------------------------------------------
# Get the full interface descriptions on a device, and save to include with port status info
#   Input: ($devref,$session)
#       Device Refrence - refrence to a hash of device information
#       Session - session varaible (SSH or Telnet) for the connection to a device
#   Output:
#       desc - hash of the long descriptions for each interface
#---------------------------------------------------------------------------------------------
sub getDescriptions {
    my $devref = shift;
    my $session = shift;
    my $host = $$devref{host};
    my ( $port, $desc, $tmp_ref );

    my @cmdresults;
    my @int_desc;
    my %desc;

    $EVAL_ERROR = undef;
    # Get descriptions
    eval {
        # SSH Method
        if ( $ssh_session ) {
            @cmdresults = SSHCommand( $session, "show interface description" );
        }
        # Telnet Method
        else {
            @cmdresults = $session->cmd( String => "show interface description" );
        }
        # handle misc. output
        $tmp_ref = compactResults( \@cmdresults );
        ## Parse results
        foreach my $line ( @$tmp_ref ) {    
            $desc = undef;

            ## Nexus Eth Style
            if ( $line =~ /^([Ee]th\d+\/\d\/?\d*\.?\d*)\s+/ ) {
                # Get the port
                $port = $1;
                # Split on spacing
                @int_desc = split( /\s+/, $line );
                # Deal with spaces in description
                my $count = @int_desc;
                $count--;
                # Concat back description
                for ( my $i=3; $i <= $count; $i++ ) {
                    if ( $desc ) {
                        $desc = "$desc $int_desc[$i]";
                    }
                    else{
                        $desc = "$int_desc[$i]";
                    }
                }
                # clean the description
                $desc = cleanDesc( $desc );
            }
            ## Nexus Port Channel Style Description
            elsif ( $line =~ /^(Po\d+)/ ) {
                # Get the port
                $port = $1;
                $line =~ s/^$port\s+//;
                # clean the description
                $desc = cleanDesc( $line );
            }
            ## Nexus VLAN Description
            elsif ( $line =~ /^(Vlan\d+)/ ) {
                $port = $1;
                $line =~ s/^$port\s+//;
                # clean the description
                $desc = cleanDesc( $line );
            }
            # Save the port and description information
            if ( $desc && $port ) {
                print "$scriptName($PID): |DEBUG|: DESC: $$devref{host} $port $desc\n" if $DEBUG>4;
                $desc{"$$devref{host},$port"} = "$desc";
            }
        } # END foreach line by line
    }; # END eval
    if ($EVAL_ERROR) {
        print STDERR "$scriptName($PID): |Warning|: Could not get descriptions on $host\n";
    }

    return \%desc;
} # END sub getDescription
#---------------------------------------------------------------------------------------------
# Clean the description as needed
#   Input: (desc)
#       description - uncleaned port description
#   Output:
#       desc - cleaned and formated
#---------------------------------------------------------------------------------------------
sub cleanDesc {
    my $desc = shift;

    # Strip leading spaces
    $desc =~ s/^\s+//;
    # Strip commas and stray \r command returns
    $desc =~ s/[\,|\r]//g;
    chomp( $desc );
    # Strip trailing spaces
    $desc =~ s/\s+$//;
    # Strip -- on ports without decriptions
    $desc =~ s/^[-]{2}//;
    return $desc;
} # END sub cleanDesc

###########################
##                       ##
## ARP table subroutines ##
##                       ##
###########################
#---------------------------------------------------------------------------------------------
# Get the ARP table of the device and VRFs
# Array CSV Format: IP,mac_address,age,vlan,vrf,host
#   Input: ($devref,$session)
#       Device Refrence - refrence to a hash of device information
#       Session - session varaible (SSH or Telnet) for the connection to a device
#   Output:
#       ARPTable - array containing the ARP table
#---------------------------------------------------------------------------------------------
sub getARPTable {
    my $devref = shift;
    my $session = shift;
    my $tmp_ref;
    my @cmdresults;
    my @ARPTable;

    ## Get any VRF ARP table data
    if ( $$devref{vrfs} ) {
        my @vrfs = split( /\,/, $$devref{vrfs} );
        foreach my $vrf (@vrfs) {
            print "$scriptName($PID): Getting ARP Table for VRF $vrf on $$devref{host}\n" if $DEBUG>1;
            # SSH Method
            if ( $ssh_session ) {
                @cmdresults = SSHCommand( $session, "show ip arp vrf $vrf" );
            }
            # Telnet Method
            else {
                @cmdresults = $session->cmd( String => "show ip arp vrf $vrf" );
            }
            $tmp_ref = &cleanARP( \@cmdresults, "$vrf" );
            @ARPTable = ( @ARPTable, @$tmp_ref );
        }
    }
    ## Get Primary ARP Table
    # SSH Method
    if ( $ssh_session ) {
        @cmdresults = SSHCommand( $session, "show ip arp" );
    }    
    # Telnet Method
    else {
        @cmdresults = $session->cmd( String => "show ip arp" );
    }
    # Parse standard ARP table styles
    $tmp_ref = &cleanARP( \@cmdresults );
    @ARPTable = ( @ARPTable, @$tmp_ref );

    # Check for results, output error if no data found
    if ( !$ARPTable[0] ) {
        print STDERR "$scriptName($PID): |ERROR|: No ARP table data received from $$devref{host}".
        "(use netdbctl -debug 2 for more info)\n";
        if ( $DEBUG>1 ) {
            print "$scriptName($PID): |DEBUG|: Bad ARP Table Data Received: @cmdresults";
        }
        return 0;
    }
    return \@ARPTable;
} # END sub getARPTable
#---------------------------------------------------------------------------------------------
# Clean raw ARP table data into standardized output
#   Input: ($results_ref,$vrf)
#       Results Refrence - refrence to array of comand line output containing ARP data
#       VRF - VRF ARP output
#   Output:
#       ARPTable - array containing the ARP table
#       Format: (IP,MAC,age,VLAN,VRF,router)
#---------------------------------------------------------------------------------------------
sub cleanARP {
    my $results_ref = shift;
    my $vrf = shift;
    my $tmp_ref;

    my @arp;
    my @ARPTable;

    # handle misc. output
    $tmp_ref = compactResults( $results_ref );
    # Fix line ending issues, ARP table parse line by line
    foreach my $line ( @$tmp_ref ) {                      # parse results
        @arp = undef;
        ## Match ARP Table Format, all lines with IP addresses
        # Nexus 7000 ARP Table Format, no ARPA
        if ( $line =~ /^\d{1,3}(\.\d{1,3}){3}/ && $line !~ /Incomplete/i ) {
            $line =~ s/\r|\n//;         # Strip off any line endings
            @arp = split(/\s+/, $line);
            # create string with entries
            $line = "$arp[0],$arp[2],".convertAge_Nexus($arp[1]).",$arp[3],$vrf,$$devref{host}";
            print "$scriptName($PID): |DEBUG|: Saving ARP: $line\n" if $DEBUG>4;
            push( @ARPTable, $line ) if $line;            # save for writing to file
        } # END if match format
    } # END foreach line by line

    return \@ARPTable;
} # END sub cleanARP

################################
##                            ##
## IPv6 Neighbors subroutines ##
##                            ##
################################
#---------------------------------------------------------------------------------------------
# Get the IPv6 Neighbors table of the device and VRFs
#   Input: ($devref,$session)
#       Device Refrence - refrence to a hash of device information
#       Session - session varaible (SSH or Telnet) for the connection to a device
#   Output:
#       v6Table - array containing the IPv6 Neighbors table
#---------------------------------------------------------------------------------------------
sub getv6Table {
    my $devref = shift;
    my $session = shift;
    my $tmp_ref;
    my @cmdresults;
    my @v6Table;

    ## Get any VRF ARP table data
    if ( $$devref{vrfs} ) {
        my @vrfs = split( /\,/, $$devref{vrfs} );

        foreach my $vrf (@vrfs) {
            print "$scriptName($PID): |DEBUG|: Getting IPv6 neighbors for VRF $vrf on $$devref{host}\n" if $DEBUG>1;

            if ( $ssh_session ) {
                @cmdresults = SSHCommand( $session, "show ipv6 neighbor vrf $vrf" );
            }
            else {
                @cmdresults = $session->cmd( String => "show ipv6 neighbor vrf $vrf" );
            }
            # handle misc. output
            $tmp_ref = compactResults( \@cmdresults );
            $tmp_ref = parsev6Result( $tmp_ref, "$vrf" );
            @v6Table = ( @v6Table, @$tmp_ref );
        }
        @cmdresults = undef;
    }

    ## Get Primary V6 Neighbor Table
    # SSH Method
    if ( $ssh_session ) {
        @cmdresults = SSHCommand( $session, "show ipv6 neighbor" );
    }
    # Telnet Method
    else {
        $EVAL_ERROR = undef;
        eval { @cmdresults = $session->cmd( String => "show ipv6 neighbor" ); };
    }
    if ( $EVAL_ERROR) {
        print "$scriptName($PID): |ERROR|: show ipv6 neighbor failed on $$devref{host}\n";
        return;
    }

    # Parse NX-OS IPv6 table style
    print "$scriptName($PID): |DEBUG|: Using NX-OS parser\n" if $DEBUG>2;
    # handle misc. output
    $tmp_ref = compactResults( \@cmdresults );
    $tmp_ref = parsev6Result($tmp_ref);   # Parse v6 results
    # Add v6 results to table
    @v6Table = ( @v6Table, @$tmp_ref );
    
    # Check for results, output error if no data found
    if ( !$v6Table[0] ) {
        print STDERR "$scriptName($PID): |Warning|: No IPv6 table data received from $$devref{host} (use -vv for more info)\n";
        if ( $DEBUG>1 ) {
            print "$scriptName($PID): |DEBUG|: Bad IPv6 Table Data Received: @cmdresults";
        }
        return;
    }
    
    # v6 Table Debug (expect large results)
    if ( $DEBUG > 4 ) {
        foreach my $line (@v6Table) { print "v6table: $line\n"; }
    }

    return \@v6Table;
} # END getv6Table
#---------------------------------------------------------------------------------------------
# Parse IPv6 Neighbors data and put in IPv6 line format for storage
# Currently makes use of a rather insane regex, hopefully in the future we can do away with it
#   Input: ($results_ref)
#       Results Refrence - refrence to array of cmd output containing IPv6 Neighbors data
#       vrf - the VRF
#   Output:
#       v6Table - array containing IPv6 information
#                 Format: (ip,mac,age,vlan)
#---------------------------------------------------------------------------------------------
sub parsev6Result {
    my $results_ref = shift;
    my $vrf = shift;
    my @results = @$results_ref;
    my @v6Table;
    my $IP = undef;
    foreach my $line (@results){
        # regex verifies valid IPv6 address
        if ($line =~ /^(([A-Fa-f0-9]{1,4}:){7}[A-Fa-f0-9]{1,4})$|^([A-Fa-f0-9]{1,4}::([A-Fa-f0-9]{1,4}:){0,5}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){2}:([A-Fa-f0-9]{1,4}:){0,4}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){3}:([A-Fa-f0-9]{1,4}:){0,3}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){4}:([A-Fa-f0-9]{1,4}:){0,2}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){5}:([A-Fa-f0-9]{1,4}:){0,1}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){6}:[A-Fa-f0-9]{1,4})$/ ){
            $line =~ s/\s+//g;   # remove stray whitespace
            chomp ($line);      # shouldn't be any hidden newlines
            $IP = $line;        # Store IP
        } # END IPv6 line
        elsif ($line =~ /\s[0-9a-fA-F]{4}(\.[0-9a-fA-F]{4}){2}\s/){
            if ( $IP && $IP !~ /^FE80:/i ){
                my (undef,$age,$MAC,$Pref,$Source,$vlan) = split( /\s+/, $line );
                $vlan =~ /(\d+)/;
                $vlan = $1;
                if ($ipv6_maxage){
                    my $simple_age = convertAge_Nexus($age);
                    if ($ipv6_maxage > $simple_age){
                        print "$scriptName($PID): |SAVING|: $IP,$MAC,$simple_age,$vlan,$vrf,$$devref{host}\n" if $DEBUG>5;
                        push( @v6Table, "$IP,$MAC,$simple_age,$vlan,$vrf,$$devref{host}" );
                        $IP = undef;
                    }
                }
                else{
                    my $simple_age = convertAge_Nexus($age);
                    print "$scriptName($PID): |SAVING|: $IP,$MAC,$simple_age,$vlan,$vrf,$$devref{host}\n" if $DEBUG>5;
                    push( @v6Table, "$IP,$MAC,$simple_age,$vlan,$vrf,$$devref{host}" );
                    $IP = undef;
                }
            } # END if not local address
            else{
                next;
            } # END else was a link local address
        } # END elsif is this a MAC line
        else{
            next;
        } # END not an IPv6 or MAC line
    } # END foreach

    return \@v6Table;
} # END sub parsev6Result_Nexus

###############################################
##                                           ##
## Link-Level Neighbor Discovery subroutines ##
##                                           ##
###############################################
#---------------------------------------------------------------------------------------------
# Get the Link-Level Neighbor Discovery table of the device, for both CDP and LLDP information
#   Input: ($devref,$session)
#       Device Refrence - refrence to a hash of device information
#       Session - session varaible (SSH or Telnet) for the connection to a device
#   Output:
#       neighborsTable - array of the Link-Level Neighbors of the device
#---------------------------------------------------------------------------------------------
sub getNeighbors {
    my $devref = shift;
    my $session = shift;
    my $host = $$devref{host};

    my @neighborsTable = undef;

    my $nCDPref = getCDP($host,$session);
    my $nLLDPref = getLLDP($host,$session);
    my @nCDP = @$nCDPref;
    my @nLLDP = @$nLLDPref;

    # Store the CDP data in the table
    foreach my $cdpNeighbor (@nCDP){
        $cdpNeighbor->{softStr} =~ s/[,]+/0x2C/g;
        my $neighbor = "$host,".$cdpNeighbor->{port}.",".$cdpNeighbor->{dev}.",".$cdpNeighbor->{remIP}.","
                        .$cdpNeighbor->{softStr}.",".$cdpNeighbor->{model}.",".$cdpNeighbor->{remPort}.",cdp";
        push ( @neighborsTable, $neighbor );
    }
    # Store LLDP data unless already found in CDP data
    for(my $i=0;$i<scalar(@nLLDP);$i++){
        for my $cdpNeighbor (@nCDP){
            if ( ($cdpNeighbor->{dev} eq $nLLDP[$i]->{dev}) && ($cdpNeighbor->{remPort} eq $nLLDP[$i]->{remPort}) ){
               print "$scriptName($PID): |DEBUG|: LLDP discovered device: ".$nLLDP[$i]->{dev}." already exists in CDP\n" if $DEBUG>4;
               last;
            }
        } # END for cdpNeighbor
        next if (!$nLLDP[$i]->{port});
        $nLLDP[$i]->{softStr} =~ s/[,]+/0x2C/g;
        my $neighbor = "$host,".$nLLDP[$i]->{port}.",".$nLLDP[$i]->{dev}.",".$nLLDP[$i]->{remIP}.","
                        .$nLLDP[$i]->{softStr}.",".$nLLDP[$i]->{model}.",".$nLLDP[$i]->{remPort}.",lldp";
        push ( @neighborsTable, $neighbor );
    } # END for LLDP neighbors

    if ($DEBUG>4){
        print "$scriptName($PID): |DEBUG|: Neighbor Discovery table:\n";
        foreach my $dev (@neighborsTable){
            print "\t$dev\n";
        }
        print "\n";
    }
    if ( !$neighborsTable[1] ){
        print STDERR "$scriptName($PID): |Warning|: No Neighbor Discovery table data received from $host.\n";
        return 0;
    }

    return \@neighborsTable
} # END sub getNeighbors
#---------------------------------------------------------------------------------------------
# Get the Cisco Discovery Protocol neighbor table of the device (CDP)
#   Input: ($host,$session)
#       Host - the host (device name)
#       Session - session varaible (SSH or Telnet) for the connection to a device
#   Output:
#       neighbors - array of the CDP Neighbors of the device
#---------------------------------------------------------------------------------------------
sub getCDP {
    my $host = shift;
    my $session = shift;

    my @cmdresults = undef;
    my @neighbors;
    ## Capture CDP neighbors table
    $EVAL_ERROR = undef;
    eval {
        # SSH Command
        if ( $ssh_session ) {
            @cmdresults = SSHCommand( $session, "show cdp neighbors detail" );
            #@cmdresults = split( /\n/, $cmdresults[0] );
        }
        # Telnet Command
        else {
            @cmdresults = $session->cmd( String => "show cdp neighbors detail" );
        }
    };
    # Bad telnet command 
    # Note: SSH doesn't throw eval errors, catch no-data errors below for SSH
    if ($EVAL_ERROR) {
        print STDERR "$scriptName($PID): |Warning|: Could not get CDP neighbors on $host (use -debug 3 for more info): $EVAL_ERROR.\n";
        print "$scriptName($PID): |DEBUG|: CDP neighbors: @cmdresults\n" if $DEBUG>2;
        return 0;
    }
    my $tmp_ref = compactResults( \@cmdresults );
    @cmdresults = @$tmp_ref;
    $tmp_ref = undef;

    print "$scriptName($PID): |DEBUG|: Gathering CDP data on $host\n" if $DEBUG>1;
    # append ending line to deal with output formating
    push ( @cmdresults, "-------------------------" );
    my $cdpCount = 0;
    my ($port,$remoteDevice,$remoteIP,$softwareString,$model,$remotePort,$softNext,$ipNext,$ipType) = undef;
    foreach my $line (@cmdresults) {
        print "$scriptName($PID): |DEBUG|: LINE: $line\n" if $DEBUG>5;
        # Save remote device name
        if ( !($remoteDevice) && $line =~ /^Device\sID:([A-Za-z0-9\.\-\_]+)/ ) {
            $remoteDevice = $1;
            print "$scriptName($PID): |DEBUG|: Remote dev: $remoteDevice\n" if $DEBUG>4;
        }
        # Save remote device platform
        elsif ( !($model) && $line =~ /^Platform:\s+([A-Za-z0-9\s-]+)\s*,/ ) {
            $model = $1;
            print "$scriptName($PID): |DEBUG|: $remoteDevice model: $model\n" if $DEBUG>4;
        }
        # Save ports of conected
        elsif ( !($port) && !($remotePort) && $line =~ /^Interface:\s+([A-Za-z0-9\/]+),\s+Port\sID\s\(outgoing\sport\):\s+([0-9A-Za-z\/]+)/ ) {
            $port = $1;
            $remotePort = $2;
            # Get everything in to the short port format
            $port = normalizePort($port);
            $remotePort = normalizePort($remotePort);
            print "$scriptName($PID): |DEBUG|: $remoteDevice on local port: $port to $remotePort\n" if $DEBUG>4;
        }
        # Software string will be on the following line
        elsif ( $line =~ /^Version:/ ) {
            $softNext = 1;
        }
        # Save Software String
        elsif ( $softNext && $line =~ /^([A-Z|a-z|0-9]+)/ ) {
            $softwareString = $line;
            $softwareString =~ s/\r//g;
            chomp($softwareString);
            $softNext = undef;
            print "$scriptName($PID): |DEBUG|: $remoteDevice software string: $softwareString\n" if $DEBUG>4;
        }
        # IP address will be on the following line
        elsif ( $line =~ /^Interface\saddress\(es\):/ ) {
            $ipNext = 1;
        }
        # Save remote device IP address
        elsif ( $ipNext && $line =~ /^\s+IPv([46])\sAddress:\s+([0-9a-fA-f\.:]+)/ ) {
            $ipType = $1; $remoteIP = $2;
            if ($ipType == 6 && $remoteIP !~ /^[fF][eE]880/) {
                $ipNext = undef;
                print "$scriptName($PID): |DEBUG|: $remoteDevice IP address: $remoteIP\n" if $DEBUG>4;
            }
            elsif ( $ipType ==4 ) {
                $ipNext = undef;
                print "$scriptName($PID): |DEBUG|: $remoteDevice IP address: $remoteIP\n" if $DEBUG>4;
            }
        }
        # save all the info collect on a device
        elsif ( $port && $remoteDevice && $remotePort && $softwareString && $line =~ /^----+/ ) {
            $neighbors[$cdpCount] = {  dev     => $remoteDevice,
                                       port    => $port,
                                       remIP   => $remoteIP,
                                       softStr => $softwareString,
                                       model   => $model,
                                       remPort => $remotePort, };
            print "$scriptName($PID): |DEBUG|: Saving CDP data: $host,$port,$remoteDevice,$remoteIP,$softwareString,$model,$remotePort\n" if $DEBUG>3;
            $cdpCount++; # inciment device counter
            ($port,$remoteDevice,$remoteIP,$softwareString,$model,$remotePort,$ipType) = undef;
        }
        else {
            next;
        }
    } # END foreach, line by line
    print "$scriptName($PID): |DEBUG|: Neighbors discovered via CDP: $cdpCount\n" if $DEBUG>2;
    return \@neighbors;
} # END sub getCDP
#---------------------------------------------------------------------------------------------
# Get the Link-Layer Discovery Protocol neighbor table of the device (LLDP)
#   Input: ($host,$session)
#       Host - the host (device name)
#       Session - session varaible (SSH or Telnet) for the connection to a device
#   Output:
#       neighbors - array of the LLDP Neighbors of the device
#---------------------------------------------------------------------------------------------
sub getLLDP {
    my $host = shift;
    my $session = shift;

    my @cmdresults = undef;
    my @neighbors;
    ## Capture LLDP neighbors table
    $EVAL_ERROR = undef;
    eval {
        # SSH Command
        if ( $ssh_session ) {
            @cmdresults = SSHCommand( $session, "show lldp neighbors detail" );
            #@cmdresults = split( /\n/, $cmdresults[0] );
        }
        # Telnet Command
        else {
            @cmdresults = $session->cmd( String => "show lldp neighbors detail" );
        }
    };
    # Bad telnet command 
    # Note: SSH doesn't throw eval errors, catch no-data errors below for SSH
    if ($EVAL_ERROR) {
        print STDERR "$scriptName($PID): |Warning|: Could not get LLDP neighbors on $host (use -debug 3 for more info): $EVAL_ERROR.\n";
        print "$scriptName($PID): |DEBUG|: LLDP neighbors: @cmdresults\n" if $DEBUG>2;
        return 0;
    }
    my $tmp_ref = compactResults( \@cmdresults );
    @cmdresults = @$tmp_ref;
    $tmp_ref = undef;

    print "$scriptName($PID): |DEBUG|: Gathering LLDP data on $host\n" if $DEBUG>1;
    # Get interface descriptions
    my $lldpCount = 0;
    my ($port,$remoteDevice,$remoteIP,$remotePort,$softwareString,$foundIP) = undef;
    foreach my $line (@cmdresults) {
        print "$scriptName($PID): |DEBUG|: LINE: $line\n" if $DEBUG>5;

        # Save local port
        if ( !($port) && $line =~ /^Local\sPort\sid:\s([A-Za-z0-9\/]+)/ ) {
            $port = $1;
            $port = normalizePort($port);
            print "$scriptName($PID): |DEBUG|: Local port with remote dev: $port\n" if $DEBUG>4;
        }
        # Save remote device name
        elsif ( !($remoteDevice) && $line =~ /^System\sName:\s+([A-Za-z0-9\.\-\_]+)/ ) {
            $remoteDevice = $1;
            print "$scriptName($PID): |DEBUG|: Remote dev: $remoteDevice\n" if $DEBUG>4;
        }
        # Save remote port connection
        elsif ( !($remotePort) && $line =~ /^Port\sid:/ ) {
             $line =~ s/\r//g;
             (undef,$remotePort) = split( /:\s+/, $line );
             if( $remotePort =~ /[0-9a-fA-F]{4}(\.[0-9a-fA-F]{4}){2}/ ){
                 $remotePort = undef;
                 next;
             }
            print "$scriptName($PID): |DEBUG|: Remote dev using remote port: $remotePort\n" if $DEBUG>4;
        }
        # Save remote port connection
        elsif ( !($remotePort) && $line =~ /^Port\sDescription:\s+([0-9A-Za-z|\/]+)/ ) {
            $remotePort = $1;
            $remotePort = normalizePort($remotePort);
            print "$scriptName($PID): |DEBUG|: Remote dev using remote port: $remotePort\n" if $DEBUG>4;
        }
        # Save the software string
        elsif ( !($softwareString) && $line =~ /^System\sDescription:/ ) {
            $line =~ s/\r//g;
            (undef,$softwareString) = split( /:\s+/, $line );
            print "$scriptName($PID): |DEBUG|: $remoteDevice software string: $softwareString\n" if $DEBUG>4;
        }
        # Save remote device IP address
        elsif ( !($remoteIP) && $line =~ /^Management\sAddress:\s+([0-9a-fA-F:\.]+)/ ) {
            $remoteIP = $1;
            $foundIP = 1;
            $remoteIP = undef if ($remoteIP =~ /[0-9a-fA-F]{4}(\.[0-9a-fA-F]{4}){2}/); # make sure it's not a MAC
            print "$scriptName($PID): |DEBUG|: Remote dev IP address: $remoteIP\n" if $DEBUG>4;
        }
        elsif ( $port && $remoteDevice && $remotePort && $softwareString && $foundIP ) {
            $neighbors[$lldpCount] = {  dev     => $remoteDevice,
                                        port    => $port,
                                        remPort => $remotePort,
                                        remIP   => $remoteIP,
                                        softStr => $softwareString, };
            print "$scriptName($PID): |DEBUG|: Saving LLDP data: $host,$port,$remoteDevice,$remoteIP,$softwareString,,$remotePort\n" if $DEBUG>3;
            $lldpCount++; # inciment device counter
            ($port,$remoteDevice,$remoteIP,$remotePort,$softwareString,$foundIP) = undef;
        }
        else {
            next;
        }
    } # END foreach, line by line
    print "$scriptName($PID): |DEBUG|: Neighbors discovered via LLDP: $lldpCount\n" if $DEBUG>2;
    return \@neighbors;
} # END sub getLLDP

########################
##                    ##
## Helper subroutines ##
##                    ##
########################
#---------------------------------------------------------------------------------------------
# Convert IPv6 Neighbors table aga data from human readable to standard int format
#   Input: ($age)
#       age - string in humman readable form of age
#   Output:
#       standard age - standard int age format (like everything else)
#---------------------------------------------------------------------------------------------
sub convertAge_Nexus {
    my $age = shift;
    $age =~ s/\s+//;
    $age =~ s/[\r|\n]//;
    if ( $age =~ /:/ ){
        my($hour,$min,$sec) = split(/:/,$age);
        return ( ($hour * 60) + $min );
    }
    elsif ( $age =~ /(\d+)d(\d+)h/i ){  # days & hours
        my $day = $1; my $hour = $2;
        return ( ( ($day * 24) + $hour ) * 60 );
    }
    elsif ( $age =~ /(\d+)w(\d+)d/i ){  # weeks & days
        my $week = $1; my $day = $2;
        return ( ( ($week * 7) + $day ) * 1440 );
    }
    elsif ( $age =~ /(\d+)y(\d+)w/i ){  # years & weeks
        my $year = $1; my $week = $2;
        return ( ( ($year * 365) + ($week * 7) ) * 1440 );
    }
    else{
        return '-'; # no age
    }
} # END sub convertAge_Nexus

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

    $config->define( "ipv6_maxage=s", "use_telnet", "use_ssh", "ssh_timeout=s", "telnet_timeout=s" );
    $config->define( "arp_file=s", "mac_file=s", "int_file=s", "ipv6_file=s", "nd_file=s" );
    $config->define( "datadir=s", "max_macs=s", "use_nd", "enablepass=s", "gethost" );
    $config->file( "$config_file" );

    # Enable credintials
    $enablepasswd  = $config->enablepass(); # Enable passwd
    my ( $pre );
    
    $use_ssh = 1 if $config->use_ssh();
    $use_telnet = 1 if $config->use_telnet();

    # Global Neighbor Discovery Option
    $optDevice = "$optDevice,nd" if $config->use_nd();

    # SSH/Telnet Timeouts
    if ( $config->telnet_timeout() ) {
        $telnet_timeout = $config->telnet_timeout();
    }
    if ( $config->ssh_timeout() ) {
        $ssh_timeout = $config->ssh_timeout();
    }

    # Global gethost Option
    $optDevice = "$optDevice,gethost" if $config->gethost();

    if ( $config->ipv6_maxage() ) {
        $ipv6_maxage = $config->ipv6_maxage();
    }

    $maxMacs = $config->max_macs() if $config->max_macs();

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
    Usage: nxosscraper.pl [options] 

    Required:
      -d  string       NetDB Devicefile config line

    Note: You can test with just the hostname or something like:
          ciscoscraper.pl -d switch1.local,arp,forcessh 

    Filename Override Options, defaults to config file settings
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

