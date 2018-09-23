#!/usr/bin/perl
###########################################################################
# ipsoscraper.pl - IPSO Scraper Plugin
# Author: targuan <targuan@gmail.com>
#
# Copyright 2014 targuan
###########################################################################
# Derivated from:
# skeletonscraper.pl - Skeleton Scraper Plugin
# Author: Jonathan Yantis <yantisj@gmail.com>
# Copyright (C) 2013 Jonathan Yantis
###########################################################################
#
# IPSO Scraper script for implementing NetDB with Checkpoint IPSO device
#
# IPSO Scraper pull arp data from Checkpoint IPSO devices. It is based on the
# skeletonscraper.
#
#
# You can test this as a standalone script with a line from your devicelist 
# like this:
#
# ipsoscraper.pl -d switch.domain.com[,arp,vrf-dmz,forcessh] \
# -conf netdb_dev.conf -debug 5
#
#
## IF YOU MANAGE TO SUPPORT A THIRD-PARTY DEVICE, please send me your code so I
## can include it for others, even if it's unsupported by you - Thanks.
#
#
## Device Option Hash:
# $$devref is a hash reference that keeps all the variable passed from
# the config file to your scraper. You can choose to implement some or
# all of these options. These options are loaded via the -d option,
# and will be called by
#
# $$devref{host}: scalar - hostname of the device (no domain name)
# $$devref{fqdn}: scalar - Fully Qualified Domain Name
# $$devref{mac}: bool - gather the mac table - Not yet implemented
# $$devref{arp}: bool - gather the arp table
# $$devref{v6nt}: bool - gather IPv6 Neighbor Table - Not yet implemented
# $$devref{forcessh}: bool - force SSH as connection method
# $$devref{forcetelnet}: bool - force telnet - Not yet implemented
# $$devref{vrfs}: scalar - list of CSV separated VRFs to pull ARP on 
#                                                   - Not yet implemented
#
###########################################################################
# License:
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details:
# http://www.gnu.org/licenses/gpl.txt
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
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
my $ipv6_maxage = 10;
my $telnet_timeout = 20;
my $ssh_timeout = 10;
my $username;
my $password;
my $port;
my $login_timeout;

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
$scriptName = "$$devref{devtype}scraper.pl";



############################
# Capture Data from Device #
############################

# Connect to device and define the $session object
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

print "$scriptName($PID): Writing Data to Disk on $$devref{fqdn}\n" if $DEBUG>1;
# Write data to disk
if ( $arp_ref ) {
    writeARP( $arp_ref, $optArpFile );
}

############################
# Gather data from devices #
############################

## Connect to Device method that obeys the $use_ssh and $use_telnet options
sub connectDevice {

    # Get credentials from config file, use authgroup if specified for device
    my ( $user, $pass, $enable ) = getCredentials( $devref );

    # connect if ssh option is defined
    if ( !$$devref{forcetelnet} && ( $use_ssh || $$devref{forcessh} ) ) {

        ## Try to connect to a device
        #
        $EVAL_ERROR = undef;
        eval {
            # Alternate session method direct
            # 
            $session = Net::SSH::Expect->new(
                                                 host => $$devref{fqdn},
                                                 password => $pass,
                                                 user => $user,
                                                 raw_pty => 1,
                                                 timeout => $login_timeout,
                                                 no_terminal => 1,
                                               );
            $session->login();

        };
        if ($EVAL_ERROR) {
            die "$scriptName($PID): |ERROR|: Could not open SSH session to $$devref{fqdn}: $EVAL_ERROR\n";
        }

    }
    
    # connect if telnet method is defined
    elsif ( $use_telnet || $$devref{forcetelnet} ) {
		 die "$scriptName($PID): |ERROR|: telnet is not implemented\n";
    }
}

# ARP Table
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
    my @cmdresults;
    my $mac;
    my $tmp_ref;
    
    print "$scriptName($PID): getARPTable is not implemented\n" if $DEBUG>1;
    
    $session->read_all( 1 );
    $session->send( "show arpdynamic all" );
    @cmdresults = $session->read_all( 1 );
    $tmp_ref = compactResults( \@cmdresults );
 
	foreach(@$tmp_ref) {
		if($_ =~ m/(([0-9]{1,3}\.?){4}) +(([0-9a-fA-F]{1,2}:?){6})/) {
			my @parts = split(':', $3);
			foreach(@parts) {
				if(length($_)<2) {
					$_ = '0'.$_;
				}
			}
			$mac = join(':',@parts);
			push @arptable, $1 . "," . $mac . ",0,0";
		}
	}
    
    $session->read_all( 1 );
    $session->send( "show arpstatic all" );
    @cmdresults = $session->read_all( 1 );
    
    $tmp_ref = compactResults( \@cmdresults );
 
	foreach(@$tmp_ref) {
		if($_ =~ m/(([0-9]{1,3}\.?){4}) +(([0-9a-fA-F]{1,2}:?){6})/) {
			my @parts = split(':', $3);
			foreach(@parts) {
				if(length($_)<2) {
					$_ = '0'.$_;
				}
			}
			$mac = join(':',@parts);
			push @arptable, $1 . "," . $mac . ",0,0";
		}
	}
    
    $session->read_all( 1 );
    $session->send( "show arpproxy all" );
    @cmdresults = $session->read_all( 1 );
    $tmp_ref = compactResults( \@cmdresults );
 
	foreach(@$tmp_ref) {
		if($_ =~ m/(([0-9]{1,3}\.?){4}) +[a-zA-Z0-9 ]+ +(([0-9a-fA-F]{1,2}:?){6})/) {
			my @parts = split(':', $3);
			foreach(@parts) {
				if(length($_)<2) {
					$_ = '0'.$_;
				}
			}
			$mac = join(':',@parts);
			push @arptable, $1 . "," . $mac . ",0,0";
		}
	}
    
    print "$scriptName($PID): getARPTable is not implemented\n" if $DEBUG>4;

    return \@arptable;
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
    Usage: ipsoscraper.pl [options] 

    Required:
      -d  string       NetDB Devicefile config line

    Note: You can test with just the hostname or something like:
          ipsoscraper.pl -d firewall1.local,arp,forcessh 

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