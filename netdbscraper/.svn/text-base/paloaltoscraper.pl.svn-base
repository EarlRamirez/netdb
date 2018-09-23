#!/usr/bin/perl
###########################################################################
# paloaltoscraper.pl - Skeleton Scraper Plugin
# Copyright (C) 2015 Max Caines
###########################################################################
# 
# Palo Alto scraper: only does ARP
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
use Expect;
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
my $ipv6_maxage = 10;
my $telnet_timeout = 20;
my $ssh_timeout = 10;
my $username;
my $password;

# Other Data
my $exp; # Expect session

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
$scriptName = "$$devref{devtype}scraper.pl";



############################
# Capture Data from Device #
############################

# Connect to device
print "$scriptName($PID): Connecting to device $$devref{fqdn}\n" if $DEBUG;
connectDevice();

# Get the ARP Table
if ( $$devref{arp} ) {
    print "$scriptName($PID): Getting the ARP Table on $$devref{fqdn}\n" if $DEBUG>1;
    $arp_ref = getARPTable();
}

################################################
# Clean Trunk Data and Save everything to disk #
################################################

# Use Helper Method to strip out trunk ports
print "$scriptName($PID): Cleaning Trunk Data on $$devref{fqdn}\n" if $DEBUG>1;
$mac_ref = cleanTrunks( $mac_ref, $int_ref );


# Development: Die before writing to files
# die "Remove Me: don't write to files yet\n";


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

    # Get credentials from config file, use authgroup if specified for device
    my ( $user, $pass, $enable ) = getCredentials( $devref );

    # connect if telnet method is defined
    if ( $use_telnet || $$devref{forcetelnet} ) {
        $exp = new Expect;
        $exp->raw_pty(1);
        $exp->slave->stty(qw(raw -echo));
        $exp->log_stdout(0);
        $exp->spawn("telnet $$devref{fqdn}", ()) or
            die "$scriptName($PID): |ERROR|: Could not open Telnet session to $$devref{fqdn}: $!\n";
        while (1) {
            my $match = $exp->expect(10, 'login:', 'assword:');
            if ($match == 1) {
                $exp->send("$user\n");
            } elsif ($match == 2) {
                $exp->send("$pass\n");
                last;
            } else {
                my $got = $exp->before();
                die "$scriptName($PID): |ERROR|: Could not open Telnet session to $$devref{fqdn}: expecting prompt, got $got\n";
            }
        }    
        unless ($exp->expect(10, '(active)> ')) {
            my $got = $exp->before();
            die "$scriptName($PID): |ERROR|: Could not open Telnet session to $$devref{fqdn}: Sent password, got $got\n";
        }
        $exp->send("set cli scripting-mode on\n");  # now echoes as typed
        do {} while (getline());
        expsend("set cli pager off");
    }
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

    expsend("show arp all");
    while (getline()) {
        if (my ($vlan, $ip, $mac) = /^\S+\.(\d+)\s+(\S+)\s+([0-9A-Fa-f:]{17})/) {
            push @arptable, "$ip,$mac,0,Vlan$vlan,,$$devref{host}";
        }
    }
    return \@arptable;
}
 
sub expsend {
    # Send a command and wait for it to be echoed, to avoid getting
    # out of sync with the firewall

    my $cmd = shift;

    sleep 1;
    $exp->clear_accum();
    $exp->send($cmd,"\n");
    print "DEBUG: Sent: $cmd\n" if $DEBUG > 1;
    do {
        getline();
    } until ($_ eq $cmd);
}

sub getline {
    my $match = $exp->expect(10, -re => '.*?\r\n', '(active)> ');
    if ($match == 2) {
        return 0;
    }
    if ($match != 1) {
        my $got = $exp->before();
        print "DEBUG: expected line, got $got\n" if $DEBUG > 1;
        finish();
    }
    $_ = $exp->match();
    s/[^ -~]//g;
    s/\s*$//;
    print "DEBUG: Read: $_\n" if $DEBUG > 1;
    return 1;
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
    Usage: paloaltoscraper.pl [options] 

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

