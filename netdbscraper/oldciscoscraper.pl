#!/usr/bin/perl
###############################################################################
# ciscoscraper.pl - Cisco IOS/ASA/NX-OS Scraper
# Author: Jonathan Yantis <yantisj@gmail.com> 
#         and Andrew Loss <aterribleloss@gmail.com>
# Copyright (C) 2012 Jonathan Yantis
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
use Net::DNS;
use IO::Socket::INET;
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
my $ipv6_maxage = 10;

# Device Option Hash
my $devref;

my ( $ssh_session, $maxMacs );

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

$scriptName = "$$devref{devtype}scraper.pl";


############################
# Capture Data from Device #
############################

# References to arrays of data to write to files
my ( $mac_ref, $int_ref, $arp_ref, $v6_ref, $desc_ref );

print "$scriptName($PID): Connecting to device $$devref{fqdn}\n" if $DEBUG;

my $cisco = connectDevice( $devref );

if ( $cisco ) {

    # Get the ARP Table
    if ( $$devref{arp} ) {
        print "$scriptName($PID): Getting the ARP Table on $$devref{fqdn}\n" if $DEBUG>1;
        $arp_ref = getARPTable( $devref, $cisco );
    }

    # Get the MAC Table if requested
    if ( $$devref{mac} ) {

	print "$scriptName($PID): Getting the Interface Descriptions on $$devref{fqdn}\n" if $DEBUG>1;
	$desc_ref = getDescriptions( $devref, $cisco );	

        print "$scriptName($PID): Getting the Interface Status Table on $$devref{fqdn}\n" if $DEBUG>1;
        $int_ref = getInterfaceTable( $devref, $cisco, $desc_ref );

	print "$scriptName($PID): Getting the MAC Table on $$devref{fqdn}\n" if $DEBUG>1;
	$mac_ref = getMacTable( $devref, $cisco );
	
    }
    
    # Get the IPv6 Table (optional)
    if ( $$devref{v6nt} ) {
	print "$scriptName($PID): Getting the IPv6 Neighbor Table on $$devref{fqdn}\n" if $DEBUG>1;
	$v6_ref = getv6Table( $devref, $cisco );
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

# Output a summary
if ( $DEBUG ) {
    my $p = "$scriptName($PID): Completed ( ";
    $p = $p . "mac " if $$devref{mac};
    $p = $p . "arp " if $$devref{arp};
    chop( $$devref{vrfs} ) if $$devref{vrfs};
    $p = $p . "vrf-$$devref{vrfs} " if $$devref{vrfs};
    $p = $p . "ipv6 " if $$devref{v6nt};
    $p = $p . ") via ";
    $p = $p . "telnet " if !$ssh_session && $use_telnet;
    $p = $p . "ssh " if $ssh_session;
    $p = $p . "on $$devref{fqdn}\n";
    print $p;
}

##############################################
# Custom Methods to gather data from devices #
##############################################



# Get a session on a device
# Checks to see if telnet or ssh is enabled, tries to login and get a $session
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

    # DNS Check, Get IP Address
    eval {
	$hostip = inet_ntoa(inet_aton($fqdn));
	print "IP for $fqdn:\t$hostip\n\n" if $DEBUG>2;
    };
    
    # DNS Failure
    if ( !$hostip ) {
	die "$scriptName($PID): |ERROR|: DNS lookup failure on $fqdn\n";
    }

    ## Test to see if SSH port is open
    if ( $use_ssh ) {
        print "$scriptName($PID): Testing port 22 on $fqdn for open state\n" if $DEBUG>2;
	
	# Create a Socket Connection
	my $remote = IO::Socket::INET -> new (
             Proto => "tcp",
					           Timeout => 2,
             PeerAddr => $hostip,
             PeerPort => "22" );

	# Set $ssh_enabled if port is open
	if ($remote) { 
	        close $remote;
		    $ssh_enabled = 1;
		    print "$scriptName($PID): $fqdn SSH port open\n" if $DEBUG>2;
	    }
	else {
	        print "$scriptName($PID): $fqdn SSH port closed\n" if $DEBUG>2;
	    }
    }

    # Attempt SSH Session if port is open, return 0 if failure and print to stderr
    if ( $ssh_enabled ) {

        $EVAL_ERROR = undef;
        eval {
            $session = get_cisco_ssh_auto( $fqdn );

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


################################################################################
# Get the mac address table from a switch and throw out any ports with more than
# $maxMacs or that is a known trunk port.
# 
# Note: There are five styles of IOS mac address tables that I have found.  This
# script captures single entry static or dynamic entries found on a single port
# (no multicast etc).  See below for troubleshooting.
################################################################################
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


	        # NX-OS Inconsistency Fix for N7k, resolved in recent NX-OS releases
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
    }

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
			
			
			# Nexus 7000 style mac-tables
			#
			# - Leading asterisk stripped out above
			# - Always leading space
			#
			# Matched Fields: 3=mac, 4=dyn/s, 8=port

			if ( ( $macd[4] eq "dynamic" || $macd[4] eq "static" ) &&
			          ( $macd[8] =~ /\d+\/\d+/ || $macd[8] =~ /Po\d+/ ) ) {

			        $switchtype = 'c7000';
				    $port = $macd[8];
				    $mac = $macd[3];
				    ($port) = split(/\,/, $port);

				    # Get everything in to the short port format
				    $port =~ s/Port-channel(\d+)$/Po$1/;
				    $port =~ s/Ethernet(\d+\/\d+)$/Eth$1/;        

				    if ( $mac =~ /^\w+\.\w+\.\w+$/ && $port =~ /\d+$/ ) {
					print "$host $mac $port\n" if $DEBUG>5;
					$totalcount++;
					push( @mactable, "$host,$mac,$port");
				    }
			    }
			
			# Nexus 5000 4.2+ style, similar to 7000
			#
			# - Leading asterisk stripped out above
			# - Always leading space
			#
			# Matched Fields: 2=mac, 3=dyn/s, 7=port

			elsif ( ( $macd[3] eq "dynamic" || $macd[3] eq "static" ) && 
				( $macd[7] =~ /\d+\/\d+/ || $macd[7] =~ /Po\d+/ ) ) {

			        $switchtype = 'c5000';
				    $port = $macd[7];
				    $mac = $macd[2];
				    ($port) = split(/\,/, $port);

				    # Get everything in to the short port format
				    $port =~ s/Ethernet(\d+\/\d+)$/Eth$1/;
				    $port =~ s/Port-channel(\d+)$/Po$1/;

				    if ( $mac =~ /^\w+\.\w+\.\w+$/ && $port =~ /\d+$/ ) {
					print "$host $mac $port\n" if $DEBUG>5;
					$totalcount++;
					push( @mactable, "$host,$mac,$port");
				    }
			    }

			# Cisco Nexus 4000 Series Switches for IBM BladeCenter - NX-OS
			# Cisco Nexus 4000 version 4.1 + style
			# 20/7/2012
			# Matched Fields: 2=mac, 5=port
			elsif ( ( $macd[3] eq "dynamic" || $macd[3] eq "static" ) && $macd[4] =~ /\d+/ && 
				( $macd[5] =~ /Po\d+/ || $macd[5] =~ /Eth\d\/\d+/ ) ) {

			    $switchtype = 'n4000i';
			    $port = $macd[5];
			    $mac = $macd[2];

			    if ( $mac =~ /^\w+\.\w+\.\w+$/ && $port =~ /\d+$/ )
			    {
				print "$host $mac $port\n" if $DEBUG>5;
				$totalcount++;
				push( @mactable, "$host,$mac,$port");
			    }
			}
			

			# 6500 12.2SR style IOS, match dynamic or static entries that
			# have a single port listed with them.
			#
			# - Stripped out leading asterisk above.
			# - Strip out mac lines that have multiple ports associated
			#   (igmp etc)
			#
			# Matched Fields: 2=mac, 3=dyn/s, 6=port

			elsif ( ( $macd[3] eq "dynamic" || $macd[3] eq "static" ) 
				     && $macd[6] =~ /\w+\/\w+|Po/ && $macd[6] !~ /\,/ ) {

			        $switchtype = 'c6500';
				    $port = $macd[6];
				    $mac = $macd[2];
				    ($port) = split(/\,/, $port);

				    if ( $mac =~ /^\w+\.\w+\.\w+$/ && $port =~ /\d+$/ )
				    {                            
					print "$host $mac $port\n" if $DEBUG>5;
					$totalcount++;
					push( @mactable, "$host,$mac,$port");
				    }

			    }

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
				    if ( $mac =~ /^\w+\.\w+\.\w+$/ && $port =~ /\d+$/ )
				    {
					print "$host $mac $port\n" if $DEBUG>5;
					$totalcount++;
					push( @mactable, "$host,$mac,$port");
				    }
			    }

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
				    $port =~ s/GigabitEthernet(\d+\/\d+)$/Gi$1/;
				    $port =~ s/FastEthernet(\d+\/\d+)$/Fa$1/;
				    $port =~ s/Ethernet(\d+\/\d+)$/Eth$1/;
				    $port =~ s/Port-channel(\d+)$/Po$1/;

				    if ( $mac =~ /^\w+\.\w+\.\w+$/ && $port =~ /\d+$/ ) {
					print "$host $mac $port\n" if $DEBUG>5;
					$totalcount++;
					push( @mactable, "$host,$mac,$port");
				    }
			    }


			# 2900/3500XL Format (supposedly it works, EOL)
			# Matched Fields: 1=mac, 2=s/d, 4=port

			elsif ( ( $macd[2] eq "Dynamic" || $macd[2] eq "Static" ) 
				&& $macd[4] =~ /\d+\/\d+/ ) {

			        $switchtype = 'c3500xl';
				    $port = $macd[4];
				    $mac = $macd[1];

				    # Get everything in to the short port format
				    $port =~ s/GigabitEthernet(\d+\/\d+)$/Gi$1/;
				    $port =~ s/FastEthernet(\d+\/\d+)$/Fa$1/;

				    if ( $mac =~ /^\w+\.\w+\.\w+$/ && $port =~ /\d+$/ ) {
					print "$host $mac $port\n" if $DEBUG>5;
					$totalcount++;
					push( @mactable, "$host,$mac,$port");
				    }
			    }

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
		    } # mac per line loop
	    }
    }  # foreach

    # Catch no-data error
    if ( !$mactable[0] ) {
        print STDERR "$scriptName($PID): |Warning|: No mac-address table data received from $host: Use netdbctl -debug 2 for more info, " . 
	             "or disable mac-address tables on $host in the devicelist.csv with netdbnomac if unsupported on this device.\n";
	if ( $DEBUG>1 ) {
	        print "DEBUG: Bad mac-table-data: @cmdresults\n";
	    }
        return 0;
    }
    
    return \@mactable;
    
}


# Interface Status Table
# 
# Array CSV Format: host,port,status,vlan,description (opt),speed (opt),duplex (opt)
#
# Valid "status" Field States (expandable, recommend connect/notconnect over up/down): 
#     connected,notconnect,sfpAbsent,disabled,err-disabled,monitor,faulty,up,down
#
# Valid "vlan" Field Format: 1-4096,trunk,name
# Note: If you can detect a trunk port, put "trunk" in the vlan field
#
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
                }
            }
        }
    };

    if ($EVAL_ERROR) {
        print STDERR "PID($PID): |Warning|: Could not get interface status on $host\n";
    }

    return \@intStatus;
}


# Get full length descriptions and save for later to include with port status info
#
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
		    }

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
		    }

		## Nexus Port Channel Style Description
		elsif ( $line =~ /^Po\d+\s+/ ) {
		        ($port) = split( /\s+/, $line );

			    $line =~ s/^Po\d+\s+//;
			    $desc = $line;

                    # Strip commas
                    $desc =~ s/\,//g;

                    chomp( $desc );
		    }

		# Strip stray \r command returns
		$desc =~ s/\r//g;
		
		# Strip trailing spaces
		$desc =~ s/\s+$//;

		## Store the description for later reference
		if ( $desc && $port ) {
		    print "DEBUG DESC: $$devref{host} $port $desc\n" if $DEBUG>4;
		        $desc{"$$devref{host},$port"} = "$desc";
		}
            }
        }
    };

    if ($EVAL_ERROR) {
        print STDERR "PID($PID): |Warning|: Could not get descriptions on $host\n";
    }

    return \%desc;
}


# Get the ARP table off te device
sub getARPTable {
    my $devref = shift;
    my $session = shift;
    my $asa_arp;
    my $tmpref;
    my @cmdresults;
    my @tmpResults;
    my @ARPTable;
    my %ASAVlan;
    my %ASAIPs;

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

		    $tmpref = &cleanARP( \@cmdresults, undef, undef, undef, "$vrf" );
		    @tmpResults = @$tmpref;
		    @ARPTable = ( @ARPTable, @tmpResults );
	    }
    }
    

    ## Get Primary ARP Table

    # SSH Method
    if ( $ssh_session ) {
	@cmdresults = SSHCommand( $session, "show ip arp" );
	
	# ASA Fix, must use "show arp"
	if ( $cmdresults[0] =~ /Invalid input/ ) {
            print "DEBUG: Caught bad show ip arp command, trying alternative\n" if $DEBUG>1;

	        @cmdresults = SSHCommand( $session, "show arp" );
	        $asa_arp = 1;
	}
    }
    
    # Telnet Method, fails on ASA
    else {
	@cmdresults = $session->cmd( String => "show ip arp" );

	# ASA Fix, must use "show arp"
	if ( $cmdresults[1] =~ /Invalid input/ ) {
	        print "$scriptName($PID): |ERROR|: No Telnet support for ASA devices on $$devref{host}\n";
		    return;
	    }
    }

    # Check for ASA type, try to get VLAN Mappings from names
    if ( $asa_arp ) {
	getASAVlans( $session, \%ASAVlan );
	getASAIPs( $session, \%ASAIPs );
    }

    ## Parse standard ARP table styles
    $tmpref = &cleanARP( \@cmdresults, $asa_arp, \%ASAVlan, \%ASAIPs );
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

# Cleanup ARP output, fix line endings and parse results
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

		## Determine ARP Table Format, matches all lines with IP addresses

		# Standard IOS ARP Table, always includes ARPA
                if ( $line =~ /ARPA/ && $line !~ /Incomplete/ && !$asa_arp ) { # match active ARP entries only
                    $line =~ s/\r|\n//;                         # Strip off any line endings
		        $line = &parseArpResult( $line, $vrf );           # format the results
		        push( @ARPTable, $line ) if $line;          # save for writing to file
		}

		# Nexus 7000 ARP Table Format, no ARPA
		elsif ( !$asa_arp && $line =~ /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/  
			&& $line !~ /Incomplete/i ) {  # N7k does not include ARPA

		        $line =~ s/\r|\n//;                         # Strip off any line endings
			    $line = &parseN7KArpResult( $line, $vrf );        # format the results
			    push( @ARPTable, $line ) if $line;          # save for writing to file
		    }
		
		# ASA ARP Table parsing, already caught that it's an ASA, check for mac address
		elsif ( $asa_arp && $line =~ /\s\w+\.\w+\.\w+\s/ ) {
		        $line =~ s/\r|\n//;                         # Strip off any line endings
			    $line = &parseASAArpResult( $line, $ASAVlan_ref, $ASAIPs_ref );        # format the results
			    push( @ARPTable, $line ) if $line;          # save for writing to file
		    }
            }
        }

    return \@ARPTable;
}

# Convert Classic IOS ARP line to netdb format
# format: (ip,mac,age,interface)
sub parseArpResult {
    my $line = shift;
    my $vrf = shift;
    chomp( $line );

    my @arp = split( /\s+/, $line );

    # make sure it's an IP in field 1
    if( $arp[1] =~ /(\d+)(\.\d+){3}/ ) {
        $line = "$arp[1],$arp[3],$arp[2],$arp[5]";
	
	if ( $vrf ) {
	    $line = "$line,$vrf";
	}
    }

    return $line;
}

# Convert Nexus 7000 ARP line to netdb format
# format: (ip,mac,age,interface)
sub parseN7KArpResult {
    my $line = shift;
    chomp( $line );

    my @arp = split(/\s+/, $line);

    # make sure it's an IP in field 1
    if( $arp[0] =~ /(\d+)(\.\d+){3}/ ) {
        $line = "$arp[0],$arp[2],$arp[1],$arp[3]";
    }

    return $line;
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

####################################
# Get ARP table from device and VRFs
####################################
sub getv6Table {
    my $devref = shift;
    my $session = shift;
    my $tmpref;
    my @cmdresults;
    my @tmpResults;
    my @v6Table;

#    ## Get any VRF ARP table data
#    if ( $$devref{vrfs} ) {
    #my @vrfs = split( /\,/, $$devref{vrfs} );
    #
    #foreach my $vrf (@vrfs) {
    #    print "$scriptName($PID): Getting ARP Table for VRF $vrf on $$devref{host}\n" if $DEBUG>1;
    #    
    #    if ( $ssh_session ) {
    #@cmdresults = $session->exec( "show ip arp vrf $vrf" );
    #    }
    #    else {
    #@cmdresults = $session->cmd( String => "show ip arp vrf $vrf" );
    #    }
    #    $tmpref = &cleanARP( \@cmdresults );
    #    @tmpResults = @$tmpref;
    #    @ARPTable = ( @ARPTable, @tmpResults );
    #}
#    }
    

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
        ## No IPv6 Support
        #if ( $cmdresults[0] =~ /Invalid input/ ) {
        #    print "$scriptName($PID): |ERROR|: show ipv6 neighbors failed on $$devref{host}\n";
        #    return;
        #}
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
        
        #if ( $EVAL_ERROR || $cmdresults[1] =~ /Invalid input/ ) {
        #    print "$scriptName($PID): |ERROR|: show ipv6 neighbors failed on $$devref{host}\n";
        #    return;
        #}
	}

    ## Parse standard IPv6 table style
    #$tmpref = cleanv6( \@cmdresults );
    $tmpref = compactv6( \@cmdresults );
    print "|DEBUG|: Results are now compacted!\n" if $DEBUG>3;
    if(isTwolinedv6($tmpref)){
        print "Using NX-OS parser\n" if $DEBUG>2;
        $tmpref = parsev6Result_Nexus($tmpref);
    }
    else{
        print "Using IOS parser.\n" if $DEBUG>2;
        $tmpref = cleanv6( $tmpref );
    }

    @v6Table = ( @v6Table, @$tmpref );
    #@v6Table = @$tmpref;

    # Check for results, output error if no data found
    if ( !$v6Table[0] ) {
        print STDERR "$scriptName($PID): |ERROR|: No IPv6 table data received from $$devref{host} (use -vv for more info)\n";
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
} # END getv6Table

# Cleanup ARP output, fix line endings
sub compactv6 {
    my $results_ref = shift;
    my @cmdresults = @$results_ref;
    my @splitresults;
    my @results;

    # Fix line ending issues, ARP table parse line by line
    foreach my $result ( @cmdresults ) {           # parse results
        my @splitresults = split( /\n/, $result ); # fix line endings
        foreach my $line ( @splitresults ) {
            $line =~ s/[\n|\r]//g;                   # Strip stray \r command returns
            if ($line){
                push( @results, $line );   # save to a single array
            }
        }
    }

    return \@results;
} # END compactv6

sub isTwolinedv6 {
    my $result_ref = shift;
    my @results = @$result_ref;

    foreach my $result (@results){
        next if $result=~ /^FE80:/i;         # Link local address tent to play havoc with this
        my @line = split(/\s+/, $result );  # Break down line into parts
        # this is a bit insane
        next if $line[0] !~ /^(([A-Fa-f0-9]{1,4}:){7}[A-Fa-f0-9]{1,4})$|^([A-Fa-f0-9]{1,4}::([A-Fa-f0-9]{1,4}:){0,5}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){2}:([A-Fa-f0-9]{1,4}:){0,4}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){3}:([A-Fa-f0-9]{1,4}:){0,3}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){4}:([A-Fa-f0-9]{1,4}:){0,2}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){5}:([A-Fa-f0-9]{1,4}:){0,1}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){6}:[A-Fa-f0-9]{1,4})$/;

        print "|DEBUG|: Testing line: @line\n\tLooking at value: $line[1]\n" if $DEBUG>2;
        return ( !defined($line[1]) );
    }
}
sub convertAge_Nexus {
    my $age = shift;
    $age =~ s/\s+//;
    $age =~ s/[\r|\n]//;
    if ( $age =~ /:/ ){
        my($hour,$min,$sec) = split(/:/,$age);
        return ( ($hour * 60) + $min );
    }
    elsif ( $age =~ /(\d+)d(\d+)h/i ){
        my $day = $1; my $hour = $2;
        return ( ( ($day * 24) + $hour ) * 60 );
    }
    elsif ( $age =~ /(\d+)w(\d+)d/i ){
        my $week = $1; my $day = $2;
        return ( ( ($week * 7) + $day ) * 1440);
    }
    elsif ( $age =~ /(\d+)y(\d+)w/i ){
        my $year = $1; my $week = $2;
        return ( ( ($year * 365) + ($week * 7) ) * 1440);
    }
    else{
        return '-';
    }
} # END convertAge_Nexus

# Cleanup ARP output, fix line endings and parse results
sub cleanv6 {
    my $results_ref = shift;
    my @results = @$results_ref;
    my @splitresults;
    my @v6Table;

    # Fix line ending issues, ARP table parse line by line
    foreach my $result ( @results ) {# parse results
        # Standard IOS ARP Table, always includes ARPA
        if ( $result =~ /\s\w+\.\w+\.\w+\s/ ) {   # match mac addresses
            $result =~ s/\r|\n//;                 # Strip off any line endings
            my $line = &parsev6Result( $result );    # format the results
            push( @v6Table, $line ) if $line;   # save for writing to file
        }
    }

    return \@v6Table;
} # END cleanv6

# Parse an IPv6 NT Line
sub parsev6Result {
    my $line = shift;
    chomp( $line );

    my @v6 = split( /\s+/, $line );

    # make sure it's an IP in field 0 and is not link local
    if( $v6[0] =~ /\w+\:\w+\:/ && $v6[0] !~ /^FE80:/i ) {

        # Check age timer if defined
        if ( $ipv6_maxage && $ipv6_maxage > $v6[1] ) {
            $line = "$v6[0],$v6[2],$v6[1],$v6[4]";
        }
        elsif ( !$ipv6_maxage ) {
            # Format: ipv6,mac,age,vlan
            $line = "$v6[0],$v6[2],$v6[1],$v6[4]";
        }
        else {
            $line = undef;
        }
    }
    else {
        $line = undef;
    }
    return $line;
} # END parsev6Result

# Parse an IPv6 NT Line
sub parsev6Result_Nexus {
    my $results_ref = shift;
    my @results = @$results_ref;
    my @v6Table;
    my $IP = undef;
    foreach my $line (@results){
        if ($line =~ /^(([A-Fa-f0-9]{1,4}:){7}[A-Fa-f0-9]{1,4})$|^([A-Fa-f0-9]{1,4}::([A-Fa-f0-9]{1,4}:){0,5}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){2}:([A-Fa-f0-9]{1,4}:){0,4}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){3}:([A-Fa-f0-9]{1,4}:){0,3}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){4}:([A-Fa-f0-9]{1,4}:){0,2}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){5}:([A-Fa-f0-9]{1,4}:){0,1}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){6}:[A-Fa-f0-9]{1,4})$/ ){
            $line =~ s/\s+//;   # remove stray whitespace
            chomp ($line);      # shouldn't be any hidden newlines
            $IP = $line;        # Store IP
        } # END IPv6 line
        elsif ($line =~ /\s\w+\.\w+\.\w+\s/){
            if ( $IP && $IP !~ /^FE80:/i ){
                my (undef,$age,$MAC,$Pref,$Source,$vlan) = split( /\s+/, $line );
                $vlan =~ /(\d+)/;
                $vlan = $1;
                if ($ipv6_maxage){
                    my $simple_age = convertAge_Nexus($age);
                    print "|SAVING|: $IP,$MAC,$simple_age,$vlan\n" if $DEBUG>5;
                    push( @v6Table, "$IP,$MAC,$simple_age,$vlan" ) if ($ipv6_maxage > $simple_age);
                    $IP = undef;
                }
                else{
                    my $simple_age = convertAge_Nexus($age);
                    print "|SAVING|: $IP,$MAC,$simple_age,$vlan\n" if $DEBUG>5;
                    push( @v6Table, "$IP,$MAC,$simple_age,$vlan" );
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
    } # END 

    return \@v6Table;
} # END parsev6Result_Nexus




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
    $config->define( "ipv6_file=s", "datadir=s", "max_macs=s" );
    $config->file( "$config_file" );


    my ( $pre );
    
    $use_ssh = 1 if $config->use_ssh();
    $use_telnet = 1 if $config->use_telnet();

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
    Usage: ciscoscraper.pl [options] 

    Required:
      -d  string       NetDB Devicefile config line

    Note: You can test with just the hostname or something like:
          ciscoscraper.pl -d switch1.local,arp,forcessh 

    Filename Override Options, defaults to config file settings
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

