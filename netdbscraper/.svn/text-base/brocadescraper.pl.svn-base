#!/usr/bin/perl
###########################################################################
# brocadescraper.pl - Brocade Scraper Plugin
# Author: Andrew Loss <aterribleloss@gmail.com>
# Copyright (C) 2014 Andrew Loss
###########################################################################
# 
# Brocade (formerly Foundry) Scraper script for implementing NetDB with
# Brocede devices
#
# How to use:
# 
# This is a template file for implementing your own scraper for use with an
# unsupported device.  I tried to make it as simple as possible so you don't
# have to understand the rest of the program.  All you need to do is get the
# data off of your device and put it in the right format (arrays of CSV
# entries explained below).  
#
# This script accepts the configuration for a single device from the command
# line.  It is launched on a per device basis by netdbscraper.pl, which is a
# multi-process forking script.  You can also launch it as a stand-alone script
# to do all of your development.
#
# The default NetDB device type is "ios", and netdbscraper will call
# iosscraper.pl on all devices.  This scrapper is written for a dev_type of
# foundry.
#
# This script mainly accepts the -d string which is used to configure all the
# scraper options that are found in devices.csv.  It also checks with the config
# file netdb.conf for any options, and obeys the -debug and -conf variables.
#
# You are expected to configure the methods in the custom methods section below
# to connect to your device and pull the mac address table and/or the ARP table
# from it.  You have to put the data in to a certain CSV format detailed in the
# custom methods section below, which includes examples.  Then the script will
# clean up your trunk ports for you to obey the maxMacs, use_trunks and other
# options in netdb.conf. It will then write your data to disk worrying about the
# multi-process problems.
#
# This script uses the NetDBHelper module, which provides a lot of the modular
# code to handle writing of files, parsing of the configuration and connecting
# to devices for you.
#
# A hash table is provided that has all the options passed in via the
# devicelist.csv file that you can access as a global variable.  The $$devref
# hash is explained below.
#
# You can test it as a standalone script with a line from your devicelist like this:
#
# brocadescraper.pl -d switch.domain.com[,arp,ipv6,nd,forcessh] \
# -conf netdb_dev.conf -debug 5
#
#
## IF YOU MANAGE TO SUPPORT A THIRD-PARTY DEVICE, please send me your code so I
## can include it for others, even if it's unsupported by you - Thanks.       
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
###########################################################################
# Versions:
#
#  v1.0 - 2014-03-17 - forked from foundry scraper
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

# Used for development, work against the non-production NetDB library in 
# the current directory if available
use lib ".";
use NetDBHelper;
use Getopt::Long;
use AppConfig;
use Net::Telnet;
use English qw( -no_match_vars );
use Carp;
use strict;
use warnings;

# no nonsense
no warnings 'uninitialized';

my $scriptName;
my $DEBUG       = 0;

# Default Config File
my $config_file = "/etc/netdb.conf";

# Config File Options (Overridden by netdb.conf, optional to implement)
my $use_telnet  = 0;
my $use_ssh     = 1;
my $ipv6_maxage = 0;

### These are in here until the NetDBHelper library either gets cleaned up, 
### or includes Brocade connection, and general connection handeling functions

## Username and password option for get_brocade_session_auto
# Gets data from /etc/netdb.conf
my $user;
my $passwd;
my $user2;     # Try this if the first username/password fails
my $passwd2;
my $enableuser;    # The second passwd always tries to enable
my $enablepasswd;  # The second passwd always tries to enable

my $telnet_timeout = 20;
my $default_timeout = 14;
my $ssh_timeout = 10;
### END Brocade variables for connecting

# Device Option Hash
my $devref;

my ( $ssh_session, $maxMacs );

# CLI Input Variables
my ( $optDevice, $optMacFile, $optInterfacesFile, $optArpFile, $optv6File );
my ( $optNDFile, $prependNew, $debug_level );

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

# Must submit a device config string
if ( !$optDevice ) {
    print "$scriptName($PID): |ERROR|: Device configuration string required\n";
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
    print "$scriptName($PID): |ERROR|: No host found in dev config string\n\n";
    usage();
}

# Save the script name
$scriptName = "brocadescraper.pl";

############################
# Capture Data from Device #
############################

# References to arrays of data to write to files
my ( $mac_ref, $int_ref, $arp_ref, $v6_ref, $nd_ref );

my $brocade = connectDevice( $devref );
print "$scriptName($PID): Connecting to device $$devref{fqdn}\n" if $DEBUG;

if ( $brocade ){
    # Get the MAC Table if requested
    if ( $$devref{mac} ) {
        print "$scriptName($PID): Getting MAC Table on $$devref{fqdn}\n" if $DEBUG>1;
        $mac_ref = getMacTable( $devref, $brocade );

        print "$scriptName($PID): Getting Interface Status Table on $$devref{fqdn}\n" if $DEBUG>1;
        $int_ref = getInterfaceTable( $devref, $brocade );
    }
    # Get the ARP Table
    if ( $$devref{arp} ) {
        print "$scriptName($PID): Getting ARP Table on $$devref{fqdn}\n" if $DEBUG>1;
        $arp_ref = getARPTable( $devref, $brocade );
    }
    # Get the IPv6 Table (optional)
    if ( $$devref{v6nt} ) {
        print "$scriptName($PID): Getting IPv6 Neighbor Table on $$devref{fqdn}\n" if $DEBUG>1;
        $v6_ref = getIPv6Table( $devref, $brocade );
    }
    # Get the Neighbors
    if ( $$devref{nd} ) {
        print "$scriptName($PID): Getting Neighbor Discovery Table on $$devref{fqdn}\n" if $DEBUG>1;
        $nd_ref = getNeighbors( $devref, $brocade );
    }
} # END session check

# terminate session correctly
if ($brocade){
    $brocade->close();
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
if ( $nd_ref ) {
     writeND( $nd_ref, $optNDFile );
}

if ( $DEBUG ) {
    my $p = "$scriptName($PID): Completed ( ";
    $p = $p . "mac " if $$devref{mac};
    $p = $p . "arp " if $$devref{arp};
    $p = $p . "ipv6 " if $$devref{v6nt};
    $p = $p . "ND " if $$devref{nd};
    $p = $p . ") via ";
    $p = $p . "telnet " if !$ssh_session && $use_telnet;
    $p = $p . "ssh " if $ssh_session;
    $p = $p . "on $$devref{fqdn}\n";
    print $p;
}

##############################################
# Custom Methods to gather data from Brocade #
#   formerly Foundry devices.                #
#                                            #
#          **A work in progrss**             #
##############################################
#---------------------------------------------------------------------------------------------
# Connect to Device method that obeys the $use_ssh and $use_telnet options
#---------------------------------------------------------------------------------------------
sub connectDevice {
    my $devref = shift;
    my ( $session,$type );

    ( $session,$type ) = getSessionBrocade( $devref );
    if ($type =~ /ssh/) {
        $ssh_session = 1;
    }
    else{
        $ssh_session = 0;
    }

    return $session;
} # end connectDevice

#---------------------------------------------------------------------------------------------
# Get the MAC address table of the device (mac address format does not matter)
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
    my $mac;
    my $port;

    my @cmdresults;
    my @macd;
    my @mactable;

    # Check for local max_macs settings, override
    if ( $$devref{maxmacs} ) {
        $maxMacs = $$devref{macmacs};
    }
    ## Capture MAC address table
    # Run mac-address commad and catch issues
    $EVAL_ERROR = undef;
    eval {
        # SSH Command
        if ( $ssh_session ) { 
            @cmdresults = SSHCommand( $session, "show mac-address" );
        }
        # Telnet Command
        else {
            @cmdresults = $session->cmd( String => "show mac-address" );
        }
    }; # END eval
    # Bad telnet command 
    # Note: SSH doesn't throw eval errors, catch no-data errors below for SSH
    if ($EVAL_ERROR) {
        print STDERR "$scriptName($PID): |Warning|: Could not get mac-address-table on $host (use -debug 3 for more info): $EVAL_ERROR.\n";
        print "$scriptName($PID): |DEBUG|: Bad mac-table-data: @cmdresults\n" if $DEBUG>2;
        return 0;
    }
    my $tmp_ref = compactResults( \@cmdresults );

    ## Process mac-table results
    # Iterate through all mac table entries, splits line on spaces and matches
    # switch specific mac formats based on split data fields
    foreach my $result ( @$tmp_ref ) {
        print "$scriptName($PID): |DEBUG|: line: $result\n" if $DEBUG>4;
        # Check if MAC and not headers
        next if $result !~ /^[0-9a-fA-F]{4}(\.[0-9a-fA-F]{4}){2}/;
        # Split mac data in to fields by spaces
        @macd = split( /\s+/, $result );
        # 0=mac, 1=port, 2=s/d, 4=vlan
        # Extreme DEBUG, print all mac-address fields for bad matched data on all rows
        print "$scriptName($PID): |DEBUG|: Mac Table Fields:\n\t1: $macd[0]\t2: $macd[1]\t3: $macd[2]\t3: $macd[3]\t4: $macd[4]\n" if $DEBUG>5;

        # Save mac and port
        $mac = $macd[0];
        $port = $macd[1];
        
        print "$scriptName($PID): |DEBUG|: Saving: $host,$mac,$port\n" if $DEBUG>4;
        push ( @mactable, "$host,$mac,$port");
    } # END foreach line by line

    return \@mactable;
} # END sub getMacTable

########################################
##                                    ##
## Interface Status table subroutines ##
##                                    ##
########################################
#---------------------------------------------------------------------------------------------
# Get the full interface descriptions and port status information on Brocade device
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
#       desc - hash of the long descriptions for each interface
#---------------------------------------------------------------------------------------------
sub getInterfaceTable {
    my $devref = shift;
    my $session = shift;
    my $host = $$devref{host};
    my ( $port, $state, $vlan, $speed, $duplex, $desc, $tmp );

    my @cmdresults_init;     # Results of the show interfaces brief
    my @cmdresults_name;    # Results of a query to get non trunkacted desc
    my @intLine;
    my %names;
    my @intstatus;
    
    ## Capture interface table
    # Run show interfaces brief commad and catch issues
    $EVAL_ERROR = undef;
    # Get int
    eval {
        # SSH Command
        if ( $ssh_session ) {
            @cmdresults_init = SSHCommand( $session, "show interfaces brief" );
            @cmdresults_name = SSHCommand( $session, "show int | in line|name" );
        }
        # Telnet Command
        else {
            @cmdresults_init = $session->cmd( String => "show interfaces brief" );
            @cmdresults_name = $session->cmd( String => "show int | in line|name" );
        }
        my $tmp_init_ref = compactResults( \@cmdresults_init );
        my $tmp_name_ref = compactResults( \@cmdresults_name );

        # Get interface descriptions
        my $fport;
        foreach my $line ( @$tmp_name_ref ) {
            # on the name line
            print "$scriptName($PID): |DEBUG|: desc line: $line\n" if $DEBUG>5;
            if ( $line =~ /^[0-9]*[A-Za-z]+net(\d+\/?\d*\/?\d*)\s+/ ) {
                $fport = $1;
                #print "$scriptName($PID): |DEBUG|: Port: $fport\n" if $DEBUG>5;
            }
            # Save the port description in hash with portname
            elsif ( $line =~ /^\s+[Pp]ort\sname\sis\s([0-9|A-Z|a-z|\-|\s|\(|\)]*)/ ) {
                $names{"$fport"} = $1;
                print "$scriptName($PID): |DEBUG|: have iface info: $fport, $names{$fport}\n" if $DEBUG>4;
            }
            else {
                next;
            }
        } # END foreach line by line of descriptions

        # Parse interface table
        foreach my $result ( @$tmp_init_ref ) {
            # Make sure this is a port and not a header
            next if $result !~ /^\d+\/?\d*\/?\d*/;
            $result =~ s/\r|\n//; # remove stray newlines

            # Break up line into array
            @intLine = split( /\s+/,$result );
            ( $port, $state, $duplex, $speed, $vlan ) = @intLine[0,1,3,4,7];
            
            # Determine if this port contains multiple vlans
            $vlan =~ s/N\/A/trunk/;
            # Correcting values for ports offline
            $speed =~ s/None/auto/;
            $duplex =~ s/None/auto/;

            # add port to intstats list
            $result = "$host,$port,$state,$vlan,$names{$port},$speed,$duplex";
            print "$scriptName($PID): |DEBUG|: Int status: $result\n" if $DEBUG > 4;
            push( @intstatus, $result );
        } # END foreach line by line of MAC table
    }; # END eval
    if ($EVAL_ERROR) {
        print STDERR "$scriptName($PID): |Warning|: Could not get interface status on $host\n";
    }

    return \@intstatus;
} # END sub getInterfaceTable

###########################
##                       ##
## ARP table subroutines ##
##                       ##
###########################
#---------------------------------------------------------------------------------------------
# Get the ARP table of the device
# Note: Age is not implemented, leave blank or set to 0. Text "Vlan" will be stripped if
# included in Vlan field, VLAN must be a number for now (I may implement VLAN names later)
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
    my ( $ip, $mac, $age, $vlan );
    
    my @cmdresults;
    my @arptable;

    ## Get Primary ARP Table

    # SSH Method
    if ( $ssh_session ) {
        @cmdresults = SSHCommand( $session, "show arp" );
    }
    # Telnet Method
    else {
        @cmdresults = $session->cmd( String => "show arp" );
    }
    my $tmp_ref = compactResults( \@cmdresults );

    foreach my $result ( @$tmp_ref ) {
        # Strip headers
        next if $result =~ /All\sARP\w+/;
        next if $result =~ /No\.\w+/;
        print "$scriptName($PID): |DEBUG|: ARP line: $result\n" if $DEBUG>5;
        ( $ip, $mac, $age, $vlan ) = undef;
        ( undef, $ip, $mac, undef, $age, undef, undef, $vlan ) = split( /\s+/,$result );

        # Check if it a valid IPv4
        next if $ip !~ /^[0-9]{1,3}(\.[0-9]{1,3}){3}/;
        # Check if it is a valid MAC
        next if $mac !~ /[0-9a-fA-F]{4}(\.[0-9a-fA-F]{4}){2}/;
        # correct null VLAN
        $vlan =~ s/----//;
        
        if ( $ip && $mac ){
            print "$scriptName($PID): |DEBUG|: Saving ARP: $ip,$mac,$age,$vlan,,$$devref{host}\n" if $DEBUG>4;
            push( @arptable, "$ip,$mac,$age,$vlan,,$$devref{host}") ;
        }
    } # END foreach line by line
    
    if ( !$arptable[0] ){
        print STDERR "$scriptName($PID): |Warning|: No ARP table data received from $$devref{host} (use netdbctl -debug 2 for more info)\n";
        if ( $DEBUG>1 ) {
            print "$scriptName($PID): |DEBUG|: Bad ARP Table Data Received: @cmdresults\n";
        }
        return 0;
    }

    return \@arptable;
} # END sub getARPTable

################################
##                            ##
## IPv6 Neighbors subroutines ##
##                            ##
################################
#---------------------------------------------------------------------------------------------
##
## THIS FUNCTION HAS NOT BEEN TESTED YET!
##
# Get the IPv6 Neighbors table of the device
# Age is optional here, throw out $ipv6_maxage if desired before adding to array
# Sample IPv6 Neighbor Table Array CSV Format: IPv6,mac,age,vlan
#
#   Input: ($devref,$session)
#       Device Refrence - refrence to a hash of device information
#       Session - session varaible (SSH or Telnet) for the connection to a device
#   Output:
#       v6Table - array containing the IPv6 Neighbors table
#           Format: (ip,mac,age,vlan)
#---------------------------------------------------------------------------------------------
sub getIPv6Table {
    my $devref = shift;
    my $session = shift;
    my ( $ip, $mac, $age, $vlan, $port, $state, $line );
    
    my @cmdresults;
    my @v6table;

    ## Get IPv6 Table
    # SSH Method
    if ( $ssh_session ) {
        @cmdresults = SSHCommand( $session, "show ipv6 neighbor" );
    }
    # Telnet Method
    else {
        @cmdresults = $session->cmd( String => "show ipv6 neighbor" );
    }
    my $tmp_ref = compactResults( \@cmdresults );

    foreach my $result ( @$tmp_ref ) {
        print "$scriptName($PID): |DEBUG|: v6 line: $result\n" if $DEBUG>5;
        # Strip headers and link-local addresses
        next if $result =~ /fe80\:\:?\w+/;
        next if $result =~ /Total\snum\w+/;
        next if $result =~ /\sIPv6\sAdd\w+/;
        ( $ip, $mac, $age, $vlan, $port, $line ) = undef;
        # Breaks out into: IPv6, MAC, State, Age, port type, Port, IsR
        (undef, $ip, $mac, $state, $age, undef, $port, $vlan, undef ) = split( /\s+/,$result );
        #print "$scriptName($PID): |DEBUG|: IP: $ip, MAC: $mac, vlan: $vlan\n" if $DEBUG>5;

        # Check if it is a semi valid IPv6
        next if $ip !~ /^\w+\:\w*\:/;
        # Check if it is a valid MAC
        next if $mac !~ /[0-9a-fA-F]{4}(\.[0-9a-fA-F]{4}){2}/;
        
        # Check age timer if defined
        if ( $ipv6_maxage && $ipv6_maxage > $age ) {
            $line = "$ip,$mac,$age,$vlan";
            print "$scriptName($PID): |DEBUG|: Saving v6: $line\n" if $DEBUG>4;
        }
        elsif ( !$ipv6_maxage ) {
            $line = "$ip,$mac,$age,$vlan";
            print "$scriptName($PID): |DEBUG|: Saving v6: $line\n" if $DEBUG>4;
        }
        else {
            $line = undef;
        }
        push( @v6table, "$line,,$$devref{host}") if ( $line );
    } # END foreach line by line
    
    if ( !$v6table[0] ){
        print STDERR "$scriptName($PID): |Warning|: No IPv6 table data received from $$devref{host} (use netdbctl -debug 2 for more info)\n";
        if ( $DEBUG>1 ) {
            print "$scriptName($PID): |DEBUG|: Bad IPv6 Table Data Received: @cmdresults\n";
        }
        return 0;
    }

    return \@v6table;
} # END sub getIPv6Table

###############################################
##                                           ##
## Link-Level Neighbor Discovery subroutines ##
##                                           ##
###############################################
#---------------------------------------------------------------------------------------------
# Get the Link-Level Neighbor Discovery table of the device, for both FDP and LLDP information
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

    my $nFDPref = getFDP($host,$session);
    my $nLLDPref = getLLDP($host,$session);
    my @nFDP = @$nFDPref;
    my @nLLDP = @$nLLDPref;

    # Store the FDP/CDP data in the table
    foreach my $fdpNeighbor (@nFDP){
        $fdpNeighbor->{softStr} =~ s/[,]+/0x2C/g;
        my $neighbor = "$host,".$fdpNeighbor->{fport}.",".$fdpNeighbor->{dev}.",".$fdpNeighbor->{remIP}.","
                        .$fdpNeighbor->{softStr}.",".$fdpNeighbor->{model}.",".$fdpNeighbor->{remPort}.",fdp";
        push ( @neighborsTable, $neighbor );
    }
    # Store LLDP data unless already found in FDP data
    for(my $i=0;$i<scalar(@nLLDP);$i++){
        for my $fdpNeighbor (@nFDP) {
            if ( ($fdpNeighbor->{dev} eq $nLLDP[$i]->{dev}) && ($fdpNeighbor->{remPort} eq $nLLDP[$i]->{remPort}) ){
                print "$scriptName($PID): |DEBUG|: LLDP discovered device: ".$nLLDP[$i]->{dev}." already exists in FDP/CDP\n" if $DEBUG>4;
                last;
            }
            if (!$nLLDP[$i]->{port}){
			    last;
		    }
            $nLLDP[$i]->{softStr} =~ s/[,]+/0x2C/g;
            my $neighbor = "$host,".$nLLDP[$i]->{fport}.",".$nLLDP[$i]->{dev}.",".$nLLDP[$i]->{remIP}.","
                            .$nLLDP[$i]->{softStr}.",".$nLLDP[$i]->{model}.",".$nLLDP[$i]->{remPort}.",lldp";
            push ( @neighborsTable, $neighbor );
        } # END for fdpNeighbor
    } # END for LLDP neighbors

    if ($DEBUG>4){
        print "$scriptName($PID): |DEBUG|: Neighbor Discovery table:\n";
        foreach my $dev (@neighborsTable){
            print "\t$dev\n";
        }
        print "\n";
    }
    if ( !$neighborsTable[1] ){
        print STDERR "$scriptName($PID): |Warning|: No Neighbor Discovery table data received from $host.\n" if $DEBUG;
        return 0;
    }

    return \@neighborsTable
} # END sub getNeighbors
#---------------------------------------------------------------------------------------------
# Get the Foundry Discovery Protocol neighbor table of the device (FDP)
#   Input: ($host,$session)
#       Host - the host (device name)
#       Session - session varaible (SSH or Telnet) for the connection to a device
#   Output:
#       neighbors - array of the FDP Neighbors of the device
#---------------------------------------------------------------------------------------------
sub getFDP {
    my $host = shift;
    my $session = shift;

    my @cmdresults = undef;
    my @neighbors;
    ## Capture FDP/CDP neighbors table
    $EVAL_ERROR = undef;
    eval {
        # SSH Command
        if ( $ssh_session ) {
            @cmdresults = SSHCommand( $session, "show fdp neighbors detail" );
        }
        # Telnet Command
        else {
            @cmdresults = $session->cmd( String => "show fdp neighbors detail" );
        }
    };
    # Bad telnet command 
    # Note: SSH doesn't throw eval errors, catch no-data errors below for SSH
    if ($EVAL_ERROR) {
        print STDERR "$scriptName($PID): |Warning|: Could not get FDP/CDP neighbors on $host (use -debug 3 for more info): $EVAL_ERROR.\n";
        print "$scriptName($PID): DEBUG: FDP/CDP neighbors: @cmdresults\n" if $DEBUG>2;
        return 0;
    }
    my $tmp_ref = compactResults( \@cmdresults );

    print "$scriptName($PID): |DEBUG|: Gathering FDP/CDP data on $host\n" if $DEBUG>1;
    # Get interface descriptions
    my $fdpCount = 0;
    my ($fport,$remoteDevice,$remoteIP,$softwareString,$model,$remotePort) = undef;
    foreach my $line ( @$tmp_ref ) {
        $line =~ s/show fdp neighbors detail//;
        $line =~ s/^([Hh]oldtime)|([Ee]ntry)//;
        #chomp ($line);
        $line =~ s/\r|\n//;
        print "$scriptName($PID): |DEBUG|: LINE: $line\n" if $DEBUG>5;
        # Save remote device name
        if ( !($remoteDevice) && $line =~ /[Dd]evice\sID:\s+([A-Za-z0-9\-\.]+)/ ) {
            #(undef,$remoteDevice) = split(/:\s+/,$line);
            $remoteDevice = $1;
            print "$scriptName($PID): |DEBUG|: Remote dev: $remoteDevice\n" if $DEBUG>5;
        }
        # Save remote device IP address
        elsif ( !($remoteIP) && $line =~ /^\s+((IP)|(IPv6))\saddress(\s\(Global\))*:\s+([0-9a-fA-f\.:]+)/ ) {
            $remoteIP = "$1$5";
            $remoteIP =~ s/IPv6|IP//;
            print "$scriptName($PID): |DEBUG|: $remoteDevice IP address: $remoteIP\n" if $DEBUG>5;
        }
        # Save remote device platform
        elsif ( !($model) && $line =~ s/^Platform:\s+//) {
            ($model,undef) = split(/\s*,\s+/,$line);
            print "$scriptName($PID): |DEBUG|: $remoteDevice model: $model\n" if $DEBUG>5;
        }
        # Save ports of conected
        elsif ( !($fport) && !($remotePort) && $line =~ /^Interface:\s+\w+net([0-9\/]+)\s*,\s+Port\sID\s\(outgoing\sport\):\s+([0-9A-Za-z\/]+)/ ) {
            $fport = $1;
            $remotePort = $2;
            $fport = normalizePort($fport);
            $remotePort = normalizePort($remotePort);
            print "$scriptName($PID): |DEBUG|: $remoteDevice on local port: $fport to $remotePort\n" if $DEBUG>5;
            #next;
        }
        # Save localport connection
        elsif ( !($fport) && $line =~ /^[Ii]nterface:\s+\w+net([0-9\/]+)$/ ) {
            $fport = $1;
            $fport = normalizePort($fport);
            print "$scriptName($PID): |DEBUG|: $remoteDevice on local port: $fport\n" if $DEBUG>5;
        }
        # Save remote port connection
        elsif ( !($remotePort) && $line =~ /^Port\sID\s\(outgoing\sport\):\s+([0-9A-Za-z\/]+)/ ) {
            $remotePort = $1;
            $remotePort = normalizePort($remotePort);
            print "$scriptName($PID): |DEBUG|: $remoteDevice, remote port: $remotePort\n" if $DEBUG>5;
        }
        # Save Software String
        elsif ( !($softwareString) && $remoteDevice && $line =~ /^([A-Z|a-z|0-9][A-Z|a-z|0-9|-|\.|\s]+)/ ) {
            $softwareString = $line;
            print "$scriptName($PID): |DEBUG|: $remoteDevice software string: $softwareString\n" if $DEBUG>5;
            if ( $fport && $remoteDevice && $remotePort && $softwareString ) {
                 $neighbors[$fdpCount] = {  dev     => $remoteDevice,
                                            fport   => $fport,
                                            remIP   => $remoteIP,
                                            softStr => $softwareString,
                                            model   => $model,
                                            remPort => $remotePort, };
                print "$scriptName($PID): |DEBUG|: Saving FDP/CDP data: $host,$fport,$remoteDevice,$remoteIP,$softwareString,$model,$remotePort\n" if $DEBUG>4;
                $fdpCount++;
                ($fport,$remoteDevice,$remoteIP,$softwareString,$model,$remotePort) = undef;
            }
        }
        else {
            next;
        }
    } # foreach, line by line
    print "$scriptName($PID): |DEBUG|: Neighbors discovered via FDP: $fdpCount\n" if $DEBUG>2;
    return \@neighbors;
} # END sub getFDP
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
    my @neighbors_lldp;
    ## Capture LLDP neighbors table
    $EVAL_ERROR = undef;
    eval {
        # SSH Command
        if ( $ssh_session ) {
            @cmdresults = SSHCommand( $session, "show lldp neighbors detail" );
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

    print "$scriptName($PID): |DEBUG|: Gathering LLDP data on $host\n" if $DEBUG>1;
    # Get interface descriptions
    my $lldpCount = 0;
    my ($fport,$remoteDevice,$remoteIP,$remotePort) = undef;
    foreach my $line ( @$tmp_ref ) {
        $line =~ s/show\slldp\sneighbors\sdetail//;
        $line =~ s/\r//;
        print "$scriptName($PID): |DEBUG|: LINE: $line\n" if $DEBUG>5;
        # Save local port
        if ( !($fport) && $line =~ m/^[Ll]ocal\s[pP]ort:\s([0-9\/]+)/ ) {
            $fport = $1;
            $fport = normalizePort($fport);
            print "$scriptName($PID): |DEBUG|: LLDP Local port: $fport\n" if $DEBUG>5;
        }
        # Save remote device name
        elsif ( !($remoteDevice) && $line =~ m/^\s+\+\s+[Ss]ystem\sname/ ) {
            (undef,$remoteDevice) = split( /:\s+/, $line );
            $remoteDevice =~ s/"//g;
            chomp ($remoteDevice);
            print "$scriptName($PID): |DEBUG|: Remote dev: $remoteDevice\n" if $DEBUG>5;
        }
        # Save remote port connection
        elsif ( !($remotePort) && $line =~ m/^\s+\+\s+Port\sdescription\s+:\s+"([0-9A-Za-z|\/]+)"/ ) {
            $remotePort = $1;
            $remotePort = normalizePort($remotePort);
            print "$scriptName($PID): |DEBUG|: Remote dev, remote port: $remotePort\n" if $DEBUG>5;
        }
         # Save remote device IP address
        elsif ( !($remoteIP) && $line =~ m/^\s+\+\sManagement\saddress/ ) {
            if ($line !~ /\(MAC\saddress\)/){
                #(undef, $remoteIP) = split( /:\s+/, $line );
                if ($line =~ /:\s+([0-9a-fA-f\.:]+)/ ){
                    $remoteIP = $1;
                }
            }
            print "$scriptName($PID): |DEBUG|: Remote dev IP address: $remoteIP\n" if $DEBUG>5;
            if ( $fport && $remoteDevice && $remotePort ) {
                $neighbors_lldp[$lldpCount] = { dev     => $remoteDevice,
                                                fport   => $fport,
                                                remPort => $remotePort,
                                                remIP   => $remoteIP, };
                print "$scriptName($PID): |DEBUG|: Saving LLDP data: $host,$fport,$remoteDevice,$remoteIP,,,$remotePort\n" if $DEBUG>4;
                $lldpCount++;
                ($fport,$remoteDevice,$remoteIP,$remotePort) = undef;
            }
        }
        else {
            #print "$scriptName($PID): |DEBUG|: ignoring: $line\n";
            next;
        }
    } # foreach, line by line
    print "$scriptName($PID): |DEBUG|: Neighbors discovered via LLDP: $lldpCount\n" if $DEBUG>2;
    return \@neighbors_lldp;
} # END sub getLLDP

################################
##                            ##
## Device connection methodes ##
##                            ##
################################
#
# This is a mess and should be cleaned up.
#
#---------------------------------------------------------------------------------------------
# Generalized, try to get either a telnet or ssh session
#---------------------------------------------------------------------------------------------
sub getSessionBrocade {
    my $devref = shift;
    my ($session, $session_type);
    
    my $fqdn = $$devref{fqdn};
    #my $scriptName = "foundryscraper.pl";
    my ( $hostip, $ssh_enabled );

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
            $session = get_SSH_session($fqdn,"skip-page-display",$devref);
            # Attempt to enter enable mode if defined
	        if ($enablepasswd && $enableuser) {
                &enable_brocade_ssh($session, $enablepasswd, $enableuser);
            }
            $ssh_session = 1;
        };
        if ($EVAL_ERROR || !$session) {
            die "$scriptName($PID): |ERROR|: Could not open SSH session to $fqdn\n";
        }
        $session_type = "ssh";
        return ( $session, $session_type );
    } # END if ssh_enabled
    # Fallback to Telnet if allowed
    elsif ( $use_telnet )  {
        print "$scriptName($PID): Could not SSH to $fqdn on port 22, trying telnet\n" if $DEBUG && $use_ssh;

        # Attempt Session, return 0 if failure and print to stderr
        $EVAL_ERROR = undef;
        eval {
            $session = get_brocade_session_auto( $fqdn );
            #$session = get_telnet_session($fqdn,"skip-page-display");
            # Attempt to enter enable mode if defined
	        #if ($enablepasswd && $enableuser) {
            #    &enable_session($session, $enablepasswd, $enableuser);
            #}
        };
        if ($EVAL_ERROR || !$session) {
            die "$scriptName($PID): |ERROR|: Could not open a telnet session to $fqdn: $EVAL_ERROR\n";
        }
        $session_type = "telnet";
        return ( $session, $session_type );
    }
    # Failed to get a session, report back
    else {
        die "$scriptName($PID): |ERROR|: Failed to get a session on $fqdn, no available connection methods. $use_ssh $ssh_enabled $use_telnet\n";
    }
} # END sub getSessionBrocade
#---------------------------------------------------------------------------------------------
# Attempts to get enable privileges, brute force,
# if it asks for a user and password, send it
#---------------------------------------------------------------------------------------------
sub enable_brocade_ssh() {
    my $session_obj = shift;
    my $enablepasswd = shift;
    my $enableuser = shift;

    my @output = $session_obj->exec('enable');
    if ( $output[0] =~ /User\sName/i ) {
        @output = $session_obj->exec("$enableuser");
    }    
    if ( $output[0] =~ /Password/i ) {
        $session_obj->exec("$enablepasswd");
    }
} # END enable_ssh

############################
# Telnet session handeling #
############################
#---------------------------------------------------------------------------------------------
# Attempt Telnet Session, return 0 if failure and print to stderr
#   Input:
#       hostname: DNS resolveable hostname of device to establish a Telnet session with.
#       disbable_paging: the command to be executed on the device to disable paging if none is
#           needed use 'none'.
#   Output:
#       Session: a telnet session handle.
#---------------------------------------------------------------------------------------------
sub get_telnet_session {
    my $hostname = shift;
    my $disable_paging = shift;
    my $session;
    my $hostprompt;

    if ( !$hostname ){  # verify a hostname is given
        croak("Minimum set of arguments undefined in get_telnet_session\n");
        return undef;
    }
    if ( !$disable_paging ){    # check for disable paging command
        print "|TELNET|: No disable paging command specified for $hostname, using default\n" if $DEBUG;
        $disable_paging = "terminal length 0";
    }
    elsif ( $disable_paging =~ /none/i){    # no paging on this device
        $disable_paging = undef;
    }

    # Creating hostprompt for later
    ( $hostprompt, undef ) = split( /\./, $hostname );
    # Prompt telnet@hostName#
    my $myprompt = '/telnet@'."$hostprompt".'[#>]$/';
    #my $myprompt = '/(?m:[\w.-]+\s?(?:\(config[^\)]*\))?\s?[\$#>]\s?(?:\(enable\))?\s*$)/';

    &parseConfig();
    $EVAL_ERROR = undef;
    eval {
        print "$scriptName($PID): |TELNET|: Connecting to $hostname\n" if $DEBUG>2;
        # Get a new session object
        $session = Net::Telnet->new(
                                    Host => $hostname,
                                    #Prompt => $myprompt,
                                    Timeout => $telnet_timeout,
                                   );
    }; # END eval
    if ( $EVAL_ERROR ) {
        croak("\nNetwork Error: Failed to connect to $hostname");
        return undef;
    }
    $EVAL_ERROR = undef;
    eval {
        $session->prompt( $myprompt );
        print "$scriptName($PID): |TELNET|: Logging in to $hostname\n" if $DEBUG>3;
        # Log in to the router
        $session->login(Name    => $user,
                        Password => $passwd,
                        Timeout  => $telnet_timeout, );
    };
    # If primary login fails, check for backup credentials and try those
    if ( $EVAL_ERROR ) {
        print "$scriptName($PID): |TELNET|: Primary Login Failed to $hostname: $EVAL_ERROR\n" if $DEBUG;
        if(defined $user2 and defined $passwd2) {
            $EVAL_ERROR = undef;
            eval {
                print "$scriptName($PID): |TELNET|: Attempting Secondary Login Credentials to $hostname\n" if $DEBUG;
                $session->login(Name     => $user2,
                                Password => $passwd2,
                                Timeout  => $telnet_timeout );
            };
            if ( $EVAL_ERROR ) {
                croak( "\nAuthentication Error: Primary and Secondary login failed to $hostname: $EVAL_ERROR\n" );
                return undef;
            }
        }
        else {
            croak( "\nAuthentication Error: Primary login failed and no secondary login credentials provided\n" );
            return undef;
        }
    }
    if ( $disable_paging ){
        print "$scriptName($PID): |DEBUG|: Logged in to $hostname, setting $disable_paging\n" if $DEBUG>3;
        my @outputs = $session->cmd( String => $disable_paging );

        # Catch Errors
        foreach my $output ( @outputs ) {
            # Make sure the privleged disable paging command has been over-ridden
            if ( $output =~ /Invalid/ ) {
                # See above, you need to modify your switches accordingly
                print "$scriptName($PID): |ERROR|: Caught invald command for privlidge level or model\n" if $DEBUG>2;
	        }
            # These probably need to be tweaked
            if ( $output =~ /Permission/i ) {
                croak( "\nPermission Denied: to turn off paging\n" );
                return undef;
            }
            elsif ( $output =~ /Password/i ) {
	            croak( "\nAuthentication Error: Bad Login found while disabling paging\n" );
                return undef;
            }
            else {
                print "Telnet login output: $output\n" if $DEBUG>2;
            }
        } # end Error catching
	    #print "$scriptName($PID): |DEBUG|: Login: @output" if $DEBUG>3;
    }

    return $session;
} # END sub get_telnet_session
#---------------------------------------------------------------------------------------------
# Use the local username and password from library to login
#---------------------------------------------------------------------------------------------
sub get_brocade_session_auto {

    #croak("Network Error: Telnet not yet implimented for brocade! NO connection to $_[0] will be established!\n");
    &parseConfig();

    return get_brocade_session(
        {
            Host        => $_[0],
            User1       => $user,
            Pass1       => $passwd,
            EnableUser1 => $enableuser,
            EnablePass1 => $enablepasswd,
            User2       => $user2,
            Pass2       => $passwd2,
            EnableUser2 => $enableuser,
            EnablePass2 => $enablepasswd,
        }
    );
}
#---------------------------------------------------------------------------------------------
# Logs in to device(Host) using primary credentials (User1 and Pass1) and returns a session 
# object.  Optional values are Timeout and User2 and Pass2. You can also pass in EnablePass1
# and EnablePass2 if the session needs to be enabled. 
#---------------------------------------------------------------------------------------------
sub get_brocade_session {
    my $session_obj;
    my ($arg_ref) = @_;

    &parseConfig();

    # Hostname of target cisco device
    my $hostname = $arg_ref->{Host};

    # Primary username and password required
    my $user1 = $arg_ref->{User1};
    my $pass1 = $arg_ref->{Pass1};
    if (!$user1 || !$pass1 || !$hostname ) {
        croak("Minimum set of arguments undefined in brocade_get_session\n");
    }
    
    # Optional username and password if first fails
    my $user2 = $arg_ref->{User2};
    my $pass2 = $arg_ref->{Pass2};

    # Enable usernames if required    
    my $enable_user1 = $arg_ref->{EnableUser1};
    my $enable_user2 = $arg_ref->{EnableUser2};
    # Enable passwords if required
    my $enable_pass1 = $arg_ref->{EnablePass1};
    my $enable_pass2 = $arg_ref->{EnablePass2};
    
    # Set the timeout for commands
    my $foundry_timeout = $arg_ref->{Timeout};
    if (!defined $foundry_timeout) {
        $foundry_timeout = $default_timeout;
    }
    
    # Attempt primary login
    $EVAL_ERROR = undef;
    eval {
        $session_obj = 
            attempt_session( $hostname, $user1, $pass1, $foundry_timeout );

        # Enable if defined
        if ($enable_pass1 && $enable_user1 ) {
            enable_session($session_obj, $enable_pass1, $enable_user1 );
        }
    };

    # If primary login fails, check for backup credentials and try those
    if ($EVAL_ERROR) {
        if(defined $user2 and defined $pass2) {
            $session_obj =
                attempt_session( $hostname, $user2, $pass2, $foundry_timeout );

            # Enable if defined
            if ($enable_pass2 && $enable_user2) {
                enable_session($session_obj, $enable_pass2, $enable_user2 );
            }
        }
        else {
            croak( "\nAuthentication Error: Primary login failed on $hostname and no secondary login credentials provided" );
        }
    }
    
    return $session_obj;
}
#---------------------------------------------------------------------------------------------
# Accepts (hostname, username, password, timeout)
# Returns Net::Telnet ref to logged in session
# Does NOT work with IPv6
#---------------------------------------------------------------------------------------------
sub attempt_session {
    my ( $hostname, $brocade_user, $brocade_passwd, $brocade_timeout ) = @_;

    my $session_obj;
    
    # Prompt telnet@hostName#
    my $myprompt = '/telnet@.+[#>] $/';

    # Get a new foundry session object
    eval {
        $session_obj = Net::Telnet->new(
                        -Host => $hostname,
                        -Prompt => $myprompt,
                        -Timeout => $brocade_timeout,
                        );
    };
    if ( $EVAL_ERROR ) {
        croak("\nNetwork Error: Failed to connect to $hostname");
    }

    # Log in to the router
    $session_obj->login(
        Name     => $brocade_user,
        Password => $brocade_passwd,
        Timeout  => $brocade_timeout
    );

    # Brocade has made skip-page-display this a privliged command, and will need to be over-ritten
    my @outputs = $session_obj->cmd( String => "skip-page-display" );

    # Catch Errors
    foreach my $output ( @outputs ) {
        # Make sure the privleged 'skip-page-display' has been over-ridden
        if ( $output =~ /Invalid/ ) {
            # See above, you need to modify your switches accordingly
            print "Caught invald command for privlidge level or model\n" if $DEBUG>2;
	    }

        # These probably need to be tweaked
        if ( $output =~ /Permission/i ) {
            die "Permission Denied";
        }
        elsif ( $output =~ /Password/i ) {
	        die "Bad Login";
        }
        else {
            print "Telnet login output: $output\n" if $DEBUG>2;
        }
    } # end Error catching

    return $session_obj;
}
#---------------------------------------------------------------------------------------------
# Attempts to get enable privileges
#---------------------------------------------------------------------------------------------
sub enable_session {
    my ($session_obj, $enablepasswd, $enableuser) = @_;

    if ($session_obj->enable($enablepasswd)) {
        my @output = $session_obj->cmd('show privilege') if $DEBUG;
        print "My privileges: @output\n" if $DEBUG>3;
    }
    else { warn "Can't enable: " . $session_obj->errmsg }
    
}

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

    $config->define( "datadir=s", "use_nd", "arp_file=s", "mac_file=s", "int_file=s", "ipv6_file=s", "nd_file=s" );
    $config->define( "use_telnet", "use_ssh", "ssh_timeout=s", "telnet_timeout=s","ipv6_maxage=s", "max_macs=s" );
    $config->define( "devuser=s", "devpass=s", "devuser2=s", "devpass2=s", "enableuser=s", "enablepass=s" );

    $config->file( "$config_file" );

    # Username data
    $user           = $config->devuser();     # First User
    $passwd         = $config->devpass();     # First Password
    $user2          = $config->devuser2();     # fallback Read/Write User
    $passwd2        = $config->devpass2();     # fallback R/W Password
    $enableuser     = $config->enableuser();   # privledge escalaation User
    $enablepasswd   = $config->enablepass();   # privledge escalaation pass

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
    Usage: brocadescraper.pl [options] 

    Required:
      -d  string       NetDB Devicefile config line

    Note: You can test with just the hostname or something like:
          brocadescraper.pl -d switch1.local,arp,forcessh 

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

