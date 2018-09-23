#!/usr/bin/perl
###########################################################################
# iosscraper.pl - IOS SSHv1 Scraper Plugin
# Author: Jonathan Yantis <yantisj@gmail.com>
# Copyright (C) 2013 Jonathan Yantis
###########################################################################
#
# IOS Scraper to pull mac, arp and neighbor discovery data from Cisco IOS
# devices.  It is based on the older ciscoscraper, but no longer has support for
# Nexus or ASA devices.
# 
# How to run in standalone mode:
#  ./iosscraper.pl -om /tmp/mac.txt -oi /tmp/int.txt -oa /tmp/arp.txt \
#  -debug 3 -d switch,arp
#
# Where -d "switch,arp" is a line from your config file
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
my $use_telnet  = 1;
my $use_ssh     = 1;
my $ipv6_maxage = 0;
my $telnet_timeout = 20;
my $ssh_timeout = 10;
my $username;
my $password;

# Other Data
my $session; # SSH Session?

# Device Option Hash
my $devref;

# Other Options
my ( $ssh_session, $maxMacs );

# CLI Input Variables
my ( $optDevice, $optMacFile, $optInterfacesFile, $optArpFile, $prependNew, $debug_level );
my ( $optv6File, $optNDFile );

# References to arrays of data to write to files
my ( $mac_ref, $int_ref, $arp_ref, $v6_ref, $desc_ref, $nd_ref );

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
$scriptName = "iosscraper.pl";

############################
# Capture Data from Device #
############################

# Connect to device and define the $session object
print "$scriptName($PID): Connecting to device $$devref{fqdn}\n" if $DEBUG;
$session = connectDevice( $devref );

if ( $session ) {

    # Get the hostname from the switch if requested
    if ( $$devref{gethost} ) {
        print "$scriptName($PID): Getting hostname on $$devref{fqdn}\n" if $DEBUG>1;
    $$devref{host} = getHost( $devref, $session );
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
# Custom Methods to gather data from devices #
##############################################

#---------------------------------------------------------------------------------------------
# Connect to cisco device with either SSH or telnet
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
    print "$scriptName($PID): DNS Lookup returned $hostip for $fqdn\n" if $DEBUG>4;
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

            # Login SSHv1
            $session->login();

	    my @output = SSHCommand( $session, "terminal length 0" );

	    print "Login Debug: @output" if $DEBUG>4;

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
            $session = get_cisco_session_auto($fqdn);
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
        else {
            #print "host results: $line\n";
        }
    }

    # Check for errors
    if ( $EVAL_ERROR || !$switchhost ) {
        print STDERR "$scriptName($PID): |Warning|: Could not gather hostname from $$devref{host}, using devicelist.csv name\n";
        
        return $host;
    }

    # Return switch's hostname
    else {
    return $switchhost;
    }
}

#---------------------------------------------------------------------------------------------
# Get the MAC address table of the device (mac address format does not matter)
# parses based on which train of IOS
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
    my $host = $$devref{host};
    my $totalcount;
    my $switchtype;
    my $count = 0;
    my $line;
    my $mac;
    my $port;

    my @cmdresults;
    my @splitResults;
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
    #
    $EVAL_ERROR = undef;
    eval {
        # SSH Command
        if ( $ssh_session ) {
            @cmdresults = SSHCommand( $session, "show mac address-table", );
            # mac-address-table inconsistency fix, rare
            if ( $cmdresults[0] =~ /Invalid/i | $cmdresults[1] =~ /Invalid/i ) {
                print "$scriptName($PID): DEBUG: Caught bad mac-address-table command\n" if $DEBUG>2;
                @cmdresults = SSHCommand( $session, "show mac-address-table", );
            }
        }
        # Telnet Command
        else {
            @cmdresults = $session->cmd( String => "show mac address-table | exclude drop" );
        }
    };
    # Catch telnet bad mac-address command for older NX-OS
    if ( $EVAL_ERROR =~ /show mac address-table/ | $EVAL_ERROR =~ /Invalid/i ) {
        print "$scriptName($PID): DEBUG: Caught bad mac-address-table command\n" if $DEBUG>2;
    
        $EVAL_ERROR = undef;
        eval {
            @cmdresults = $session->cmd( String => "show mac-address-table | exclude drop" );
        };
    } # END if telnet error
    
    # Bad telnet command
    # 
    # Note: SSH doesn't throw eval errors, catch no-data errors below for SSH
    if ($EVAL_ERROR) {
        print STDERR "$scriptName($PID): |Warning|: Could not get mac-address-table on $host (use -debug 3 for more info): $EVAL_ERROR.\n";
    
        print "$scriptName($PID): DEBUG: Bad mac-table-data: @cmdresults\n" if $DEBUG>2;
        return 0;
    }

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
    #
    foreach my $results (@cmdresults) {
        # Cleanup bad line endings, continue interating entries
        @splitResults = split( /\n/, $results );
        foreach my $line (@splitResults) {
            # Strip stray \r command returns
            $line =~ s/\r//g;
            # Strip out leading asterisk from 6500/nexus output
            $line =~ s/^\*/ /;
            # Add leading space for consistency on split results
            $line = " $line";
        
            # Found a line with a mac address, split it and match based on split
            # results.
            if ( $line =~ /\s\w+\.\w+\.\w+\s/ ) {
                # Reset variables
                $port = undef;
                $mac = undef;

                # Split mac data in to fields by spaces
                @macd = split( /\s+/, $line );
        
                # Extreme DEBUG, print all mac-address fields for bad matched data on all rows
                print "DEBUG Mac Table Fields:\n1: $macd[1]\n2: $macd[2]\n3: $macd[2]\n3: $macd[3]\n4: " .
                "$macd[4]\n5: $macd[5]\n6: $macd[6]\n7: $macd[7]\n8: $macd[8]\n" if $DEBUG>5;

                # 6500 12.2SR style IOS, match dynamic or static entries that
                # have a single port listed with them.
                # - Stripped out leading asterisk above.
                # - Strip out mac lines that have multiple ports associated
                #   (igmp etc)
                #
                # Matched Fields: 2=mac, 3=dyn/s, 6=port
                if ( ( $macd[3] eq "dynamic" || $macd[3] eq "static" ) 
                    && $macd[6] =~ /\w+\/\w+|Po/ && $macd[6] !~ /\,/ ) {
            
                    $switchtype = 'c6500';
                    $port = $macd[6];
                    $mac = $macd[2];
                    ($port) = split(/\,/, $port);

                    if ( $mac =~ /^\w+\.\w+\.\w+$/ && $port =~ /\d+$/ ) {                            
                        print "$host $mac $port\n" if $DEBUG>5;
                        $totalcount++;
                        push( @mactable, "$host,$mac,$port");
                    }
                } # END if 6500 12.2SR style

                # 3750 12.2S style IOS, match dynamic or static entries that
                # have a single port associated with them
                #
                # Matched Fields: 2=mac, 3=dyn/s, 4=port
                elsif ( ( $macd[3] eq "DYNAMIC" || $macd[3] eq "STATIC" ) && 
                    ( $macd[4] =~ /\d+\/\d+/ || $macd[4] =~ /Po\d+/ ) ) {

                    $switchtype = 'c3750';
                    $port = $macd[4];
                    $mac = $macd[2];
                    ($port) = split(/\,/, $port);
                    if ( $mac =~ /^\w+\.\w+\.\w+$/ && $port =~ /\d+$/ ) {
                        print "$host $mac $port\n" if $DEBUG>5;
                        $totalcount++;
                        push( @mactable, "$host,$mac,$port");
                    }
                } # END elsif 3750 12.25 style

                # 4500 and older Nexus 5000 style mac-tables
                #
                # Mac tables are the same except that 4500s use Port-channel and
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
                } # END elsif Mx 4500 style

                # 2900/3500XL Format (supposedly it works, EOL)
                # Matched Fields: 1=mac, 2=s/d, 4=port
                elsif ( ( $macd[2] eq "Dynamic" || $macd[2] eq "Static" ) 
                    && $macd[4] =~ /\d+\/\d+/ ) {

                    $switchtype = 'c3500xl';
                    $port = $macd[4];
                    $mac = $macd[1];
                    # Get everything in to the short port format
                    $port = normalizePort($port);

                    if ( $mac =~ /^\w+\.\w+\.\w+$/ && $port =~ /\d+$/ ) {
                        print "$host $mac $port\n" if $DEBUG>5;
                        $totalcount++;
                        push( @mactable, "$host,$mac,$port");
                    }
                } # END elsif 2900/3500XL style

                # Ignore junk mac data in error reporting
                elsif ( $line =~ /(STATIC\s+CPU)|ffff.ffff.ffff|(other\sDrop)|igmp/ ) {
                    # Junk mac data, ignore
                    print "Debug: ignoring junk: @macd\n" if $DEBUG>4;
                }
                # All others unmatched data reports under debug
                # Set debug to 3 to get bad table output as fields
                else {
                    print "DEBUG Unmatched Mac Table Fields:\n1: $macd[1]\n2: $macd[2]\n3: $macd[3]\n4: " .
                        "$macd[4]\n5: $macd[5]\n6: $macd[6]\n7: $macd[7]\n8: $macd[8]\n" if $DEBUG>3;

                    print "Debug: unparsed MAC data on $host: @macd\n" if $DEBUG>2;
                }
            } # END if mac per line
        } # END foreach line by line
    } # foreach split results
    
    # Catch no-data error
    if ( !$mactable[0] ) {
        print STDERR "$scriptName($PID): |Warning|: No mac-address table data received from $host: Use netdbctl -debug 2 for more info, " . 
            "or disable mac-address tables on $host in the devicelist.csv with netdbnomac if unsupported on this device.\n";
        if ( $DEBUG>1 ) {
            print "DEBUG: Bad mac-table-data: @cmdresults\n";
        }
        return 0;
    } # END catch no-data
    
    return \@mactable;
} # END sub getMacTable

########################################
##                                    ##
## Interface Status table subroutines ##
##                                    ##
########################################
#---------------------------------------------------------------------------------------------
# Get the interface descriptions and port status information on IOS device
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
    my ( $port, $state, $vlan, $speed, $duplex, $desc, $tmp );

    my @cmdresults;
    my @splitResults;
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

        foreach my $results ( @cmdresults ) {
            @splitResults = split( /\n/, $results );
            foreach my $line ( @splitResults ) {
                # Strip stray \r command returns
                $line =~ s/\r//g;

                # If line contains int status
                if ( $line =~ /(connected|disabled|notconnect|notconnec|faulty|monitor|up|down|sfpAbsent)/ ) {
                    $state = 'connected'    if $line =~ /\sconnected\s/;
                    $state = 'notconnect'   if $line =~ /\snotconnect\s/;
                    $state = 'notconnec'    if $line =~ /\snotconnec\s/;
                    $state = 'sfpAbsent'   if $line =~ /\ssfpAbsent\s/;
                    $state = 'disabled'     if $line =~ /\sdisabled\s/;
                    $state = 'err-disabled' if $line =~ /err\-disabled/;
                    $state = 'monitor'      if $line =~ /\smonitoring\s/;
                    $state = 'faulty'       if $line =~ /\sfaulty\s/;
                    $state = 'up'           if $line =~ /\sup\s/;
                    $state = 'down'       if $line =~ /\sdown\s/;

                    # Parse it out, nasty but works on all devices
                    ($desc, $line) = split( /\s+$state/, $line);
                    ($port) = split( /\s+/, $desc);
                    $desc =~ s/$port\s+//;
                    $desc =~ s/$port//;
                    $desc =~ s/\,//g;

                    ( undef, $vlan, $duplex, $speed ) = split( /\s+/, $line );

                    # Check for extended description
                    if ( $$descref{"$host,$port"} ) {
                        $desc = $$descref{"$host,$port"};
                    }
                    # Fix short notconnect
                    $state = "notconnect" if $state eq "notconnec";

                    # If there's a proper match
                    if ( $vlan ) {
                        push( @intStatus, "$host,$port,$state,$vlan,$desc,$speed,$duplex" );
                        #print "INTOUTPUT: $host,$port,$state,$vlan,$desc,$speed,$duplex\n";
                    }
                } # END if int status
            } # END foreach line by line
        } # END foreach split results
    }; # END eval
    if ($EVAL_ERROR) {
        print STDERR "PID($PID): |Warning|: Could not get interface status on $host\n";
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
    my ( $port, $desc, $tmp );

    my @cmdresults;
    my @splitResults;
    my @desc;
    my %desc;

    $EVAL_ERROR = undef;
    
    # Get descriptions
    eval {
        if ( $ssh_session ) {
            @cmdresults = SSHCommand( $session, "show interface description" );
        }
        else {
            @cmdresults = $session->cmd( String => "show interface description" );
        }

        ## Parse results
        foreach my $results ( @cmdresults ) {    
            @splitResults = split( /\n/, $results );
            foreach my $line ( @splitResults ) {
                ## Classic IOS Style Descriptions
                if ( $line =~ /(up|down)\s+(up|down)/ ) {
                    # Split based on port status
                    @desc = split( /up\s+up|down\s+down/, $line );
                    # Strip leading spaces and get description
                    $desc[1] =~ s/^\s+//;
                    # Strip commas
                    $desc[1] =~ s/\,//g;
                    $desc = $desc[1];
                    chomp( $desc );  

                    # Get the port
                    @desc = split(/\s+/, $desc[0] );
                    $port = $desc[0];
                } # END if IOS style

                ## Nexus Eth Style
                elsif ( $line =~ /eth\s+10G|eth\s+1000/ ) {
                    # Split based on port status
                    @desc = split( /eth\s+10G|eth\s+1000/, $line );
                    # Strip leading spaces and get description
                    $desc[1] =~ s/^\s+//;
                    # Strip commas
                    $desc[1] =~ s/\,//g;
                    $desc = $desc[1];
                    chomp( $desc );

                    # Get the port
                    @desc = split(/\s+/, $desc[0] );
                    $port = $desc[0];
                } # END elsif Nexus Eth style

                ## Nexus Port Channel Style Description
                elsif ( $line =~ /^Po\d+\s+/ ) {
                    # Split the line
                    ($port) = split( /\s+/, $line );
                    $line =~ s/^Po\d+\s+//;
                    $desc = $line;
                    # Strip commas
                    $desc =~ s/\,//g;
                    chomp( $desc );
                } # END elsif Nexus port channel style

                # Strip stray \r command returns
                $desc =~ s/\r//g;
                # Strip trailing spaces
                $desc =~ s/\s+$//;

                ## Store the description for later reference
                if ( $desc && $port ) {
                    print "DEBUG DESC: $$devref{host} $port $desc\n" if $DEBUG>4;
                        $desc{"$$devref{host},$port"} = "$desc";
                }
            } # END foreach line by line
        } # END foeach split results
    }; # END eval
    if ($EVAL_ERROR) {
        print STDERR "PID($PID): |Warning|: Could not get descriptions on $host\n";
    }

    return \%desc;
} # END sub getDescriptions

###########################
##                       ##
## ARP table subroutines ##
##                       ##
###########################
#---------------------------------------------------------------------------------------------
# Get the ARP table of the device and VRFs
# Note: Age is not implemented, leave blank or set to 0. Text "Vlan" will be stripped if
# included in Vlan field, VLAN must be a number for now (I may implement VLAN names later)
# Array CSV Format: IP,mac_address,age,vlan
#   Input: ($devref,$session)
#       Device Refrence - refrence to a hash of device information
#       Session - session varaible (SSH or Telnet) for the connection to a device
#   Output:
#       ARPTable - array containing the ARP table
#---------------------------------------------------------------------------------------------
sub getARPTable {
    my $devref = shift;
    my $session = shift;
    my $tmpref;
    my @cmdresults;
    my @tmpResults;
    my @ARPTable;

    ## Get any VRF ARP table data
    if ( $$devref{vrfs} ) {
        my @vrfs = split( /\,/, $$devref{vrfs} );

        foreach my $vrf (@vrfs) {
            print "$scriptName($PID): Getting ARP Table for VRF $vrf on $$devref{host}\n" if $DEBUG>1;
            if ( $ssh_session ) {
                @cmdresults = SSHCommand( $session, "show ip arp vrf $vrf" );
            }
            else {
                @cmdresults = $session->cmd( String => "show ip arp vrf $vrf" );
            }

            $tmpref = &cleanARP( \@cmdresults, "$vrf" );
            @tmpResults = @$tmpref;
            @ARPTable = ( @ARPTable, @tmpResults );
        } # END foreach vrfs
    } # END if VRF

    ## Get Primary ARP Table

    # SSH Method
    if ( $ssh_session ) {
        print "|DEBUG|: running command via SSH: show ip arp\n" if $DEBUG>2;
        @cmdresults = SSHCommand( $session, "show ip arp" );
    }
    # Telnet Method
    else {
        print "|DEBUG|: running command via telnet: show ip arp\n" if $DEBUG>2;
        @cmdresults = $session->cmd( String => "show ip arp" );
    }

    ## Parse standard ARP table styles
    print "|DEBUG|: cleaning ARP output.\n" if $DEBUG>3;
    $tmpref = &cleanARP( \@cmdresults );
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
} # END getARPTable
#---------------------------------------------------------------------------------------------
# Clean raw ARP table data into standardized form and parse
#   Input: ($results_ref,$vrf)
#       Results Refrence - refrence to array of comand line output containing ARP data
#       VRF - VRF ARP output
#   Output:
#       ARPTable - array containing the ARP table
#---------------------------------------------------------------------------------------------
sub cleanARP {
    my $results_ref = shift;
    my $vrf = shift;
    my @cmdresults = @$results_ref;
    my @splitresults;
    my @ARPTable;

    # Fix line ending issues, ARP table parse line by line
    foreach my $results ( @cmdresults ) {           # parse results
        my @splitresults = split( /\n/, $results ); # fix line endings
        foreach my $line ( @splitresults ) {
            # Strip stray \r command returns
            $line =~ s/\r//g;
            print "|DEBUG|: Line: $line\n" if $DEBUG>5;
            ## Determine ARP Table Format, matches all lines with IP addresses
            # Standard IOS ARP Table, always includes ARPA
            if ( $line =~ /ARPA/ && $line !~ /Incomplete/ ) {    # match active ARP entries only
                $line =~ s/\r|\n//;                                # Strip off any line endings
                $line = &parseArpResult( $line, $vrf );            # format the results
                print "|DEBUG|: Saving: $line\n" if $DEBUG>4;
                push( @ARPTable, $line ) if $line;                # save for writing to file
            } # END if ARPA
        } # END foreach line by line
    } # END foreach split results
    return \@ARPTable;
} # END cleanARP
#---------------------------------------------------------------------------------------------
# Convert Classic IOS ARP line to netdb format
#   Input: ($line,$vrf)
#       Line - a line potentially containing ARP data
#       VRF - the VRF
#   Output:
#       Line - string containg 1 ARP entry, information seprated by comma
#              Format: (ip,mac,age,interface)
#---------------------------------------------------------------------------------------------
sub parseArpResult {
    my $line = shift;
    my $vrf = shift;
    chomp( $line );

    my @arp = split( /\s+/, $line );

    # make sure it's an IP in field 1
    if( $arp[1] =~ /[0-9]{1,3}(\.[0-9]{1,3}){3}/ ) {
        $line = "$arp[1],$arp[3],$arp[2],$arp[5]";
        # Add VRF and router host
        $line = "$line,$vrf,$$devref{host}";
    }
    return $line;
} # END parseArpResult

################################
##                            ##
## IPv6 Neighbors subroutines ##
##                            ##
################################
#---------------------------------------------------------------------------------------------
# Get the IPv6 Neighbors table of the device
# Age is optional here, throw out $ipv6_maxage if desired before adding to array
# Sample IPv6 Neighbor Table Array CSV Format: IPv6,mac,age,vlan
#
#   Input: ($devref,$session)
#       Device Refrence - refrence to a hash of device information
#       Session - session varaible (SSH or Telnet) for the connection to a device
#   Output:
#       v6Table - array containing the IPv6 Neighbors table
#---------------------------------------------------------------------------------------------
sub getIPv6Table {
    my $devref = shift;
    my $session = shift;
    my $tmpref;
    my @cmdresults;
    my @tmpResults;
    my @v6Table;

    ## Get Primary V6 Neighbor Table
    print "$scriptName($PID): Getting IPv6 Table on $$devref{host}\n" if $DEBUG>1;
    # SSH Method
    if ( $ssh_session ) {
        @cmdresults = SSHCommand( $session, "show ipv6 neighbors" );
        # NX-OS Inconsistency Fix for N7k, resolved in recent NX-OS release
        if ( $cmdresults[0] =~ /Invalid/i | $cmdresults[1] =~ /Invalid/i ) {
            print "$scriptName($PID): DEBUG: Caught bad show ipv6 neighbors command\n" if $DEBUG>2;
            @cmdresults = SSHCommand( $session, "show ipv6 neighbor " );
        }
    }
    # Telnet Method
    else {
        $EVAL_ERROR = undef;
        eval {
            @cmdresults = $session->cmd( String => "show ipv6 neighbors" );
        };
        # Catch telnet bad mac-address command for older NX-OS
        if ( $EVAL_ERROR =~ /show ipv6 neighbors/ || $EVAL_ERROR =~ /Invalid/i ) {
            print "$scriptName($PID): DEBUG: Caught bad show ipv6 neighbors command\n" if $DEBUG>2;
            $EVAL_ERROR = undef;
            eval {
                @cmdresults = $session->cmd( String => "show ipv6 neighbor " );
            }
        }
        if ( $EVAL_ERROR) {
            print "$scriptName($PID): |ERROR|: show ipv6 neighbor failed on $$devref{host}\n";
            return;
        }
    } # END else Telnet

    ## Parse standard IPv6 table style
    $tmpref = compactv6( \@cmdresults );
    print "|DEBUG|: Results are now compacted!\n" if $DEBUG>3;
    $tmpref = cleanv6( $tmpref );
    # Add v6 results to table
    @v6Table = ( @v6Table, @$tmpref );

    # Check for results, output error if no data found
    if ( !$v6Table[0] ) {
        print STDERR "$scriptName($PID): |Warning|: No IPv6 table data received from $$devref{host} (use -vv for more info)\n";
        if ( $DEBUG>1 ) {
            print "DEBUG: Bad IPv6 Table Data Received: @cmdresults";
        }
        return;
    }

    # V6 Table Debug
    if ( $DEBUG > 4 ) {
        foreach my $line (@v6Table) { print "v6table: $line\n"; }
    }

    return \@v6Table;    
} # END sub getIPv6Table
#---------------------------------------------------------------------------------------------
# Cleanup ARP output, fix line endings
#   Input: ($results_ref)
#       Results Refrence - refrence to array of cmd output containing IPv6 Neighbors data
#   Output:
#       results - array containing IPv6 raw unparsed information
#---------------------------------------------------------------------------------------------
sub compactv6 {
    my $results_ref = shift;
    my @cmdresults = @$results_ref;
    my @splitresults;
    my @results;

    # Fix line ending issues, ARP table parse line by line
    foreach my $result ( @cmdresults ) {           # parse results
        my @splitresults = split( /\n/, $result ); # fix line endings
        foreach my $line ( @splitresults ) {
            $line =~ s/[\n|\r]//g;          # Strip stray \r command returns
            if ($line){
                push( @results, $line );    # save to a single array
            }
        } # END foreach line by line
    } # END foreach split results

    return \@results;
} # END sub compactv6
#---------------------------------------------------------------------------------------------
# Clean raw IPv6 Neighbors table data, fix line endings, and parse results
#   Input: ($results_ref)
#       Results Refrence - refrence to array of compacted cmd output containing IPv6
#           Neighbors data
#   Output:
#       v6Table - array containing IPv6 information
#                 Format: (ip,mac,age,vlan)
#---------------------------------------------------------------------------------------------
sub cleanv6 {
    my $results_ref = shift;
    my @results = @$results_ref;
    my @splitresults;
    my @v6Table;

    # Fix line ending issues, ARP table parse line by line
    foreach my $result ( @results ) {
        print "|DEBUG|: line: $result\n" if $DEBUG>4;
        if ( $result =~ /\s\w+\.\w+\.\w+\s/ ) {     # match mac addresses
            $result =~ s/\r|\n//;                   # Strip off any line endings
            my $line = &parsev6Result( $result );   # format the results
            push( @v6Table, $line ) if $line;       # save for writing to file
        }
    } # END foreach result

    return \@v6Table;
} # END sub cleanv6
#---------------------------------------------------------------------------------------------
# Parse IPv6 Neighbors data and put in IPv6 line format for storage
#   Input: ($line)
#       line - string containing one IPv6 Neighbor data
#   Output:
#       line - string in the prpoper format to save
#                 Format: (ip,mac,age,vlan)
#---------------------------------------------------------------------------------------------
sub parsev6Result {
    my $line = shift;
    chomp( $line );

    my @v6 = split( /\s+/, $line );

    # make sure it's an IP in field 0 and is not link local
    if( $v6[0] =~ /\w+\:\w+\:/ && $v6[0] !~ /^FE80:/i ) {

        # Check age timer if defined
        if ( $ipv6_maxage && $ipv6_maxage > $v6[1] ) {
            $line = "$v6[0],$v6[2],$v6[1],$v6[4]";
            print "|DEBUG|: Saving: $line\n" if $DEBUG>5;
        }
        elsif ( !$ipv6_maxage ) {
            # Format: ipv6,mac,age,vlan
            $line = "$v6[0],$v6[2],$v6[1],$v6[4]";
            print "|DEBUG|: Saving: $line\n" if $DEBUG>5;
        }
        else {
            $line = undef;
        }
    } # END if check v6 and link local
    else {
        $line = undef;
    }
    return $line;
} # END sub parsev6Result

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
    my @nCDP = @$nCDPref if ($nCDPref);
    my @nLLDP = @$nLLDPref if ($nLLDPref);

    # Store the CDP data in the table
    foreach my $cdpNeighbor (@nCDP) {
        $cdpNeighbor->{softStr} =~ s/[,]+/0x2C/g;
        my $neighbor = "$host,".$cdpNeighbor->{port}.",".$cdpNeighbor->{dev}.",".$cdpNeighbor->{remIP}.","
                        .$cdpNeighbor->{softStr}.",".$cdpNeighbor->{model}.",".$cdpNeighbor->{remPort}.",cdp";
        push ( @neighborsTable, $neighbor );
    }
    # Store LLDP data unless already found in CDP data
    for(my $i=0;$i<scalar(@nLLDP);$i++){
        for my $cdpNeighbor (@nCDP){
            if ( ($cdpNeighbor->{dev} eq $nLLDP[$i]->{dev}) && ($cdpNeighbor->{remPort} eq $nLLDP[$i]->{remPort}) ){
               print "LLDP discovered device: ".$nLLDP[$i]->{dev}." already exists in CDP\n" if $DEBUG>4;
               last;
            }
            if (!$nLLDP[$i]->{port}){
                last;
            }
            $nLLDP[$i]->{softStr} =~ s/[,]+/0x2C/g;
            my $neighbor = "$host,".$nLLDP[$i]->{port}.",".$nLLDP[$i]->{dev}.",".$nLLDP[$i]->{remIP}.","
                            .$nLLDP[$i]->{softStr}.",".$nLLDP[$i]->{model}.",".$nLLDP[$i]->{remPort}.",lldp";
            push ( @neighborsTable, $neighbor );
        } # END for cdpNeighbor
    } # END for LLDP neighbors

    if ($DEBUG>4){
        print "|DEBUG|: Neighbor Discovery table:\n";
        foreach my $dev (@neighborsTable){
            print "\t$dev\n";
        }
        print "\n";
    }
    if ( !$neighborsTable[1] ){
        print STDERR "$scriptName($PID): |Warning|: No Neighbor Discovery table data received from $host.\n" if $DEBUG;
        return 0;
    }

    return \@neighborsTable;
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
        @cmdresults = split( /\n/, $cmdresults[0] );
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

        print "$scriptName($PID): DEBUG: CDP neighbors: @cmdresults\n" if $DEBUG>2;
        return 0;
    }
    print "|DEBUG|: Gathering CDP data on $host\n" if $DEBUG>1;
    # append ending line to deal with output formating
    push ( @cmdresults, "-------------------------" );
    my $cdpCount = 0;
    my ($port,$remoteDevice,$remoteIP,$softwareString,$model,$remotePort,$softNext,$ipNext,$ipType) = undef;
    foreach my $line (@cmdresults) {
        print "|DEBUG|: LINE: $line\n" if $DEBUG>5;

        # Save remote device name
        if ( !($remoteDevice) && $line =~ /^Device\sID:\s+([A-Za-z0-9\.-]+)/ ) {
            $remoteDevice = $1;
            print "|DEBUG|: Have remote device: $remoteDevice\n" if $DEBUG>4;
        }
        # Save remote device platform
        elsif ( !($model) && $line =~ /^Platform:\s+([A-Za-z0-9\s-]+)\s*,/ ) {
            $model = $1;
            print "|DEBUG|: Have $remoteDevice model: $model\n" if $DEBUG>4;
        }
        # Save ports of conected
        elsif ( !($port) && !($remotePort) && $line =~ /^Interface:\s+([A-Za-z0-9\/]+),\s+Port\sID\s\(outgoing\sport\):\s+([0-9A-Za-z\/]+)/ ) {
            $port = $1;
            $remotePort = $2;
            # Get everything in to the short port format
            $port = normalizePort($port);
            $remotePort = normalizePort($remotePort);
            print "|DEBUG|: Have $remoteDevice on local port: $port to $remotePort\n" if $DEBUG>4;
        }
        # Software string will be on the following line
        elsif ( $line =~ /^Version\s+:/ ) {
            $softNext = 1;
        }
        # Save Software String
        elsif ( $softNext && $line =~ /^([A-Z|a-z|0-9]+)/ ) {
            $softwareString = $line;
            $softwareString =~ s/\r//g;
            chomp($softwareString);
            $softNext = undef;
            print "|DEBUG|: Have $remoteDevice software string: $softwareString\n" if $DEBUG>4;
        }
        # IP address will be on the following line
        elsif ( $line =~ /^Management\saddress\(es\):/ ) {
            $ipNext = 1;
        }
        # Save remote device IP address
        elsif ( $ipNext && $line =~ /^\s+IP([Vv]6)?\saddress:\s+([0-9a-fA-f\.:]+)/ ) {
            $ipType = $1; $remoteIP = $2;
            if ( !$remoteIP ) {
                $remoteIP = $ipType;
                $ipNext = undef;
                print "|DEBUG|: Have $remoteDevice IP address: $remoteIP\n" if $DEBUG>4;
            }
            elsif ($ipType =~ /^[Vv]6$/) {
                $ipNext = undef;
                print "|DEBUG|: Have $remoteDevice IP address: $remoteIP\n" if $DEBUG>4;
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
            print "|DEBUG|: Saving CDP data: $host,$port,$remoteDevice,$remoteIP,$softwareString,$model,$remotePort\n" if $DEBUG>3;
            $cdpCount++; # inciment device counter
            ($port,$remoteDevice,$remoteIP,$softwareString,$model,$remotePort,$ipType) = undef;
        }
        else {
            next;
        }
    } # END foreach, line by line
    print "|DEBUG|: Neighbors discovered via CDP: $cdpCount\n" if $DEBUG>2;
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
        @cmdresults = split( /\n/, $cmdresults[0] );
        }
        # Telnet Command
        else {
            @cmdresults = $session->cmd( String => "show lldp neighbors detail" );
        }
    };
    # Bad telnet command 
    # Note: SSH doesn't throw eval errors, catch no-data errors below for SSH
    if ($EVAL_ERROR) {
        if( $EVAL_ERROR =~ /show lldp neighbors/ || $EVAL_ERROR =~ /[Ii]nvalid/ ){
            print "$scriptName($PID): DEBUG: Caught bad show lldp neighbors command, LLDP not supported on $host\n" if $DEBUG>2;
            return \@neighbors;
        }
        else{
            print STDERR "$scriptName($PID): |Warning|: Could not get LLDP neighbors on $host (use -debug 3 for more info): $EVAL_ERROR.\n";
        }

        print "$scriptName($PID): DEBUG: LLDP neighbors: @cmdresults\n" if $DEBUG>2;
        return 0;
    }
    print "|DEBUG|: Gathering LLDP data on $host\n" if $DEBUG>1;
    # append ending line to deal with output formating
    push ( @cmdresults, "-------------------------" );
    # Get interface descriptions
    my $lldpCount = 0;
    my ($remoteDevice,$remoteIP,$remotePort,$softwareString,$softNext,$ipType,$ipNext) = undef;
    foreach my $line (@cmdresults) {
        print "|DEBUG|: LINE: $line\n" if $DEBUG>5;

        ## Save local port
        #if ( !($port) && $line =~ /^Local\sPort\sid:\s([A-Za-z0-9\/]+)/ ) {
        #    $port = $1;
        #    $port = normalizePort($port);
        #    print "|DEBUG|: Have local port with remote device: $port\n" if $DEBUG>4;
        #}
        # Save remote device name
        if ( !($remoteDevice) && $line =~ /^System\sName:\s+([A-Za-z0-9\.-]+)/ ) {
            $remoteDevice = $1;
            print "|DEBUG|: Have remote device: $remoteDevice\n" if $DEBUG>4;
        }
        # Save remote port connection
        elsif ( !($remotePort) && $line =~ /^Port\sid:/ ) {
            $line =~ s/\r//g;
            (undef,$remotePort) = split( /:\s+/, $line );
            if( $remotePort =~ /[0-9a-fA-F]{4}(\.[0-9a-fA-F]{4}){2}/ ){
                $remotePort = undef;
                next;
            }
            $remotePort = normalizePort($remotePort);
            print "|DEBUG|: Have remote device using remote port: $remotePort\n" if $DEBUG>4;
        }
        # Save remote port connection
        elsif ( !($remotePort) && $line =~ /^Port\sDescription:\s+([0-9A-Za-z|\/]+)/ ) {
            $remotePort = $1;
            $remotePort = normalizePort($remotePort);
            print "|DEBUG|: Have remote device using remote port: $remotePort\n" if $DEBUG>4;
        }
        # Software string is not returned
        elsif ( $line =~ /^System\sDescription\s+-\s+not\sadvertised/ ) {
            $softwareString = "not advertised";
        }
        # Software string will be on the following line
        elsif ( $line =~ /^System\sDescription:/ ) {
            $softNext = 1;
        }
        # Save the software string
        elsif ( $softNext && $line =~ /^([A-Z|a-z|0-9]+)/ ) {
            $softwareString = $line;
            $softwareString =~ s/\r//g;
            $softNext = undef;
            print "|DEBUG|: Have $remoteDevice software string: $softwareString\n" if $DEBUG>4;
        }
         # IP address will be on the following line
        elsif ( $line =~ /^Management\sAddresses:/ ) {
            $ipNext = 1;
        }
        # Save remote device IP address
        elsif ( $ipNext && $line =~ /^\s+IP([Vv]6)?:\s+([0-9a-fA-f\.:]+)/ ) {
            $ipType = $1; $remoteIP = $2;
            if ( !$remoteIP ) {
                $remoteIP = $ipType;
                $ipNext = undef;
                print "|DEBUG|: Have $remoteDevice IP address: $remoteIP\n" if $DEBUG>4;
            }
            elsif ($ipType =~ /^[Vv]6$/) {
                $ipNext = undef;
                print "|DEBUG|: Have $remoteDevice IP address: $remoteIP\n" if $DEBUG>4;
            }
        }
        elsif ( $remoteDevice && $remotePort && $softwareString && $line =~ /^----+/ ) {
            $neighbors[$lldpCount] = {  dev     => $remoteDevice,
                                        #port    => $port,
                                        remPort => $remotePort,
                                        remIP   => $remoteIP,
                                        softStr => $softwareString, };
            print "|DEBUG|: Saving LLDP data: $host,,$remoteDevice,$remoteIP,$softwareString,,$remotePort\n" if $DEBUG>3;
            $lldpCount++; # inciment device counter
            ($remoteDevice,$remoteIP,$remotePort,$softwareString,$ipType) = undef;
        }
        else {
            #print "|DEBUG|: ignoring: $line\n";
            next;
        }
    } # END foreach, line by line
    print "|DEBUG|: Neighbors discovered via LLDP: $lldpCount\n" if $DEBUG>2;
    return \@neighbors;
} # END sub getLLDP

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
    $config->define( "ipv6_file=s", "nd_file=s", "datadir=s", "ssh_timeout=s", "telnet_timeout=s" );
    $config->define( "devuser=s", "devpass=s", "gethost" );
    $config->file( "$config_file" );

    # Username and Password
    $username = $config->devuser();
    $password = $config->devpass();

    my ( $pre );
    
    $use_ssh = 1 if $config->use_ssh();
    $use_telnet = 1 if $config->use_telnet();

    # Global Neighbor Discovery Option
    $optDevice = "$optDevice,nd" if $config->use_nd();

    # Global gethost Option
    $optDevice = "$optDevice,gethost" if $config->gethost();

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
    Usage: iosscraper.pl [options] 

    Required:
      -d  string       NetDB Devicefile config line

    Note: You can test with just the hostname or something like:
          iosscraper.pl -d switch1.local,arp,forcessh 

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

