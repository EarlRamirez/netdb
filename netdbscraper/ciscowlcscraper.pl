#!/usr/bin/perl
###########################################################################
# ciscowlcscraper.pl - Cisco WLC Client Scraper Plugin
# Author: Jonathan Yantis <yantisj@gmail.com>
# Copyright (C) 2014 Jonathan Yantis
###########################################################################
# 
# Grabs the client list and associated AP from a Cisco WLC.  Does not
# populate the switch status table.
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
#  v1.0 - 2012-05-11 - Initial scraper written
#  v1.1 - 2012-09-07 - New connection handeling and paging parseing (aloss)
#  v1.2 - 2013-10-14 - general function to handle paging
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
#use lib ".";
use NetDBHelper;
#use NetDB;
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

# Other Data
my $telnet_timeout = 20;
my $ssh_timeout = 7;

# Device Option Hash
my $devref;
my $session;

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
$session = connectDevice( $devref );

if ( $session ){
    # Get the MAC Table if requested
    if ( $$devref{mac} ) {
        print "$scriptName($PID): Getting the WiFi Client Table on $$devref{fqdn}\n" if $DEBUG>1;
        $mac_ref = getMacTable( $session );

#        print "$scriptName($PID): Getting the Interface Status Table on $$devref{fqdn}\n" if $DEBUG>1;
#        $int_ref = getInterfaceTable();
    }

    # Get the ARP Table (optional)
    if ( $$devref{arp} ) {
        print "$scriptName($PID): Getting the ARP Table on $$devref{fqdn}\n" if $DEBUG>1;
        $arp_ref = getARPTable( $session );
    }

    # Get the IPv6 Table (optional)
    if ( $$devref{v6nt} ) {
        print "$scriptName($PID): Getting the IPv6 Neighbor Table on $$devref{fqdn}\n" if $DEBUG>1;
        $v6_ref = getIPv6Table( $session );
    }
} # END session check

# terminate session correctly
if ($session){
    $session->close();
}

################################################
# Clean Trunk Data and Save everything to disk #
################################################
# Use Helper Method to strip out trunk ports
#print "$scriptName($PID): Cleaning Trunk Data on $$devref{fqdn}\n" if $DEBUG>1;
#$mac_ref = cleanTrunks( $mac_ref, $int_ref );

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
#        Cisco Wireless Controller           #
##############################################
#---------------------------------------------------------------------------------------------
# Connect to Device method that obeys the $use_ssh and $use_telnet options
#---------------------------------------------------------------------------------------------
sub connectDevice {
    my $devref = shift;
    my $session;
    # connect if ssh option is defined
    if ( !$$devref{forcetelnet} && ( $use_ssh || $$devref{forcessh} ) ) {

        # Get credentials
        my ( $user, $pass, $enable ) = getCredentials( $devref );

        # try to connect
        $EVAL_ERROR = undef;
        eval {

            # Get a new SSH session object
            print "SSH: Logging in to $$devref{fqdn}\n" if $DEBUG>3;

            $session = Net::SSH::Expect->new(
                            host => $$devref{fqdn},
                            password => $pass,
                            user => $user,
                            raw_pty => 1,
                    	    timeout => $ssh_timeout,
                            );

            # WLC and WISM Login prompt format
            my @output = $session->login("User: ","Password:");
            #@output = $session->exec( "config paging disable" );
            if ( $output[0] =~ /assword/ ) {
                die "Login Failed for $user";
            }
            print "Login Output:$output[0]\n" if $DEBUG>3;
        }; # END eval

        if ($EVAL_ERROR) {
            die "$scriptName($PID): |ERROR|: Could not open SSH session to $$devref{fqdn}:\n\t$EVAL_ERROR\n";
        }
    } # END check to use only ssh
    # connect if telnet method is defined
    elsif ( $use_telnet || $$devref{forcetelnet} ) {
	    # not yet implimented
        return undef;
    }
    return $session;
} # END sub connect device

#---------------------------------------------------------------------------------------------
# Get the client summary on WLC
#
# Array CSV Format: host,mac,ap,wifi,ssid,portlevel_ip,speed,mac_nd
#---------------------------------------------------------------------------------------------
sub getMacTable {
    my $session = shift;
    my @mactable;
    my @entry;
    my %results;
    my $results_ref;
    my $layout = 0; # 0 being the old layout

    print "$scriptName($PID): Getting the WLANs Table on $$devref{fqdn}\n" if $DEBUG>2;
    my $wlans_ref = getWLANs( $session );
    my %wlans = %$wlans_ref;

    $results_ref = ssh_paged_out( $session, "show client summary" );
    foreach my $row (@$results_ref) {
        if ( $row =~ /^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}/ ) {
            @entry = split( /\s+/, $row );
            # Match MAC Address and not IP for AP
            if ( $entry[0] && $entry[1] !~ /(\d+)(\.\d+){3}/ ) {
                if ( $layout ) {
                    print "$scriptName($PID): |DEBUG|: Cacheing: $entry[0], $entry[1], ".$wlans{$entry[4]}{ssid}."\n" if $DEBUG>3;
                    $results{$entry[0]} = { ap=>$entry[1],
                                            ssid=>$wlans{$entry[4]}{ssid},
                                            proto=>format_proto($entry[6]), };
                }
                else { # old formating
                    print "$scriptName($PID): |DEBUG|: Cacheing: $entry[0], $entry[1], ".$wlans{$entry[3]}{ssid}."\n" if $DEBUG>3;
                    $results{$entry[0]} = { ap=>$entry[1],
                                            ssid=>$wlans{$entry[3]}{ssid},
                                            proto=>format_proto($entry[5]), };
                }
            }
            else{
                print "$scriptName($PID): |DEBUG|: Discarded Client Entry: mac: $entry[0] ap: $entry[1]\n" if $DEBUG>3;
            }
        } # END if data
        elsif ( $row =~ /^MAC\sAddress/ ) {
            @entry = split(/\s{2,}/, $row);
            if ( $entry[4] ) { # new layout
                $layout = 1;
                print "$scriptName($PID): |DEBUG|: using new layout parsing\n" if $DEBUG>2;
            }
        }
        @entry = undef;
    }

    # store values
    foreach  my $mac ( keys %results ) {
        print "$scriptName($PID): |DEBUG|: mac:$mac ap:$results{$mac}{ap} wlan: $results{$mac}{ssid},,$results{$mac}{proto},\n" if $DEBUG>4;
        push( @mactable, "$$devref{host},$mac,".$results{$mac}{ap}.",wifi,".$results{$mac}{ssid}.",,$results{$mac}{proto}," );
    }

    # Catch Bad Data
    if ( !$mactable[0] ) {
        print STDERR "$scriptName($PID): |Warning|: No Wifi client data received from $$devref{host}:".
        " Use netdbctl -debug 2 for more info\n";
        if ( $DEBUG>1 ) {
            print "$scriptName($PID): |DEBUG|: Bad mac-table-data: ".keys (%results)."\n";
        }
        return 0;
    }

    return \@mactable;
} # END sub getMacTable
#---------------------------------------------------------------------------------------------
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
#---------------------------------------------------------------------------------------------
sub getInterfaceTable {
    my $session = shift;
    my @intstatus;

    # sample entries
    $intstatus[0] = "$$devref{host},Eth1/1/1,connected,20,Sample Description,10G,Full";
    $intstatus[1] = "$$devref{host},Po100,notconnect,trunk,,,";

    return \@intstatus;
} # END sub getInterfaceTable
#---------------------------------------------------------------------------------------------
# Get IPv4 table on cisco WLC. also colects type, but is not stored, becuse there is not
# yet an implimentation.
# Array CSV Format: IP,mac_address,age,vlan
# 
# Note: Age is not implemented, leave blank or set to 0. Text "Vlan" will be
# stripped if included in Vlan field, VLAN must be a number for now (I may
# implement VLAN names later)
#---------------------------------------------------------------------------------------------
sub getARPTable {
    my $session = shift;
    my $results_ref;
    my @arptable;
    my @entry;

    $results_ref = ssh_paged_out( $session, "show arp switch" );
    foreach my $row (@$results_ref) {
        if ( $row =~ /^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}/ ) {
            @entry = split( /\s+/, $row );
            print "$scriptName($PID): |DEBUG|: Cacheing ARP: $entry[0], $entry[1], $entry[3], $entry[4]\n" if $DEBUG>3;
            push( @arptable, "$$devref{host},$entry[1],$entry[0],,$entry[3]" );
        } # END if data
        @entry = undef;
    }
	return \@arptable;
} # END sub getARPTable
#---------------------------------------------------------------------------------------------
# IPv6 Neighbor Table
# Very much still beta code, please report any issues
# Array CSV Format: IPv6,mac,age,vlan
#
# Age is optional here, throw out $ipv6_maxage if desired before adding to array
#---------------------------------------------------------------------------------------------
sub getIPv6Table {
    my $session = shift;
    my $results_ref;
    my @v6table;
    my @entry;

    $results_ref = ssh_paged_out( $session, "show ipv6 neighbor-binding summary" );
    foreach my $row (@$results_ref) {
        @entry = split( /\s+/, $row );
        if ( $entry[1] !~ /^[Ff][Ee]80:/ ) {
            if ( $entry[2] =~ /^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}/ && $entry[1] =~ /^(([A-Fa-f0-9]{1,4}:){7}[A-Fa-f0-9]{1,4})$|^([A-Fa-f0-9]{1,4}::([A-Fa-f0-9]{1,4}:){0,5}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){2}:([A-Fa-f0-9]{1,4}:){0,4}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){3}:([A-Fa-f0-9]{1,4}:){0,3}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){4}:([A-Fa-f0-9]{1,4}:){0,2}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){5}:([A-Fa-f0-9]{1,4}:){0,1}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){6}:[A-Fa-f0-9]{1,4})$/ ) {   
                print "$scriptName($PID): |DEBUG|: Cacheing IPv6: $entry[1], $entry[2], $entry[7], $entry[4]\n" if $DEBUG>3;
                push( @v6table, "$$devref{host},$entry[1],$entry[2],$entry[7],$entry[4]" );
            }
             print "$scriptName($PID): |DEBUG|: Skipping IPv6: $entry[1], $entry[2], $entry[7], $entry[4]\n" if $DEBUG>3;
        } # END if data
        @entry = undef;
    }
    return \@v6table;
} # END sub getIPv6Table
#---------------------------------------------------------------------------------------------
# Get the WLANs on WLC
#   Input: 
#   Output: hash w/keys matching that of the WLANs on the WLC
#---------------------------------------------------------------------------------------------
sub getWLANs {
    my $session = shift;
    my %wlans;
    my @entry;
    my %results;
    my $results_ref;
    my ($profile, $ssid);

    $results_ref = ssh_paged_out( $session, "show wlan summary" );

    foreach my $row (@$results_ref) {
        # stores number of WLANs on controler
        if ( $row =~ /^([0-9]+)\s+()/ ) {
            @entry = split( /\s{2,}/, $row );
            ($profile, $ssid) = split(/\s\/\s/, $entry[1]);
            # profile, ssid, status, int_name, PMIPv6 Mobility
            $wlans{$entry[0]} = { profile=>$profile,
                                  ssid=>$ssid,
                                  status=>$entry[2],
                                  int_name=>$entry[3],
                                  pmipv6=>$entry[4], };
            print "$scriptName($PID): |DEBUG|: WLAN: $entry[0],$ssid\n" if $DEBUG>4;                
        }
        ($profile, $ssid) = undef;
        @entry = undef;
    }
    return \%wlans;
} # END sub getWLANs

#####################################
#                                   #
# Helper and parsing functions      #
#                                   #
#####################################
#---------------------------------------------------------------------------------------------
# format the protocol to make it consitent across layots
#   Input:
#       proto - sting with the raw input
#   Output:
#       proto - string properly formated
#---------------------------------------------------------------------------------------------
sub format_proto {
    my $proto = shift;

    if($proto =~ /\(/) {
        $proto = "$proto GHz)";
    }
    return $proto;
} # END sub format_proto
#---------------------------------------------------------------------------------------------
# Handle paged output
#   Input: (comman)
#       cmd - a command to be executed that may have paged output
#   Output:
#       results - refrence to an array, each element containing a row
#---------------------------------------------------------------------------------------------
sub ssh_paged_out {
    my $session = shift;
    my $cmd = shift;

    my $output;
    my $results_ref;
    my $check = 1;
    my @results;

    if ( !$session ){  # verify a session is passed
        print "|ERROR|: No session for ssh_paged_out\n";
        return undef;
    }

    $session->send( "$cmd" );
    # handles paging
    while($check){
        # pulls apart each section returned by paging
        $results_ref = break_down_page(\@results, $session);
        @results = @$results_ref;
        # check for cues, but only for 1/10 of a sec.
        $output = $session->peek(0.1);
        # This means we are at the promt
        if($output =~ /^\(.+\)\s>/i){
            $check = undef;
            print "$scriptName($PID): |DEBUG|: Found prompt" if $DEBUG>4;
        }
        # Submit space to continue getting results
        elsif($output =~ /^[Ww]ould\syou/i){
            $session->terminator("");
            $session->send( "y" );
            print "$scriptName($PID): |DEBUG|: sent y for next page\n" if $DEBUG>4;
            $check = 1;
            $session->terminator("\n");
        }
        # Submit space to continue getting results
        elsif($output =~ /More/i){
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
    my $session = shift;
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
    $config->file( "$config_file" );


    #$user = $config->devuser();
    #$passwd = $config->devpass();    

    my ( $pre );
    
    $use_ssh = 1 if $config->use_ssh();
    $use_telnet = 1 if $config->use_telnet();

    # SSH/Telnet Timeouts
    if ( $config->telnet_timeout() ) {
        $telnet_timeout = $config->telnet_timeout();
    }
    #if ( $config->ssh_timeout() ) {
    #    $ssh_timeout = $config->ssh_timeout();
    #}
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
    Usage: ciscowlcscraper.pl [options] 

    Required:
      -d  string       NetDB Devicefile config line

    Note: You can test with just the hostname or something like:
          ciscowlcscraper.pl -d switch1.local,arp,forcessh 

    Filename Options, defaults to config file settings
      -om file         Gather and output Mac Table to a file
      -oi file         (not yet availabe) Gather and output interface status
                        data to a file
      -oa file         (not yet availabe) Gather and output ARP table to a
                        file
      -o6 file         (not yet availabe) Gather and output IPv6 Neighbor
                        Table to file
      -pn              Prepend "new" to output files

    Development Options:
      -v               Verbose output
      -debug #         Manually set debug level (1-6)
      -conf            Alternate netdb.conf file

USAGE
    exit;
}

