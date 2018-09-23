#!/usr/bin/perl
###########################################################################
# arubascraper.pl - Aruba Scraper Plugin
# Author: Jonathan Yantis <yantisj@gmail.com>
# Copyright (C) 2012 Jonathan Yantis
###########################################################################
# 
# Grabs the Aruba client table to insert in to the switchports table.  Does not
# add the access points as switchstatus entries.
#
# Tries to enter enable mode with the default devpass, unless arubaenablepass is
# defined in netdb.conf
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
use NetDB;
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
my $login_timeout = 5;
my $ssh_timeout = 30;
my $aruba_enable_pass;
my $hostprompt = '\w+\)\s(>|#)';

# Device Option Hash
my $devref;

my ( $session, $username, $password );

# CLI Input Variables
my ( $optDevice, $optMacFile, $optInterfacesFile, $optArpFile, $optv6File, $prependNew, $debug_level );
my ( $optIntDir, $optConf, $optStatusDir, $optWM );

# Input Options
if ( $ARGV[0] eq "" ) { &usage(); }

GetOptions(
    'd=s'      => \$optDevice,
    'om=s'     => \$optMacFile,
    'oi=s'     => \$optInterfacesFile,
    'oa=s'     => \$optArpFile,
    'o6=s'     => \$optv6File,
    'id=s'     => \$optIntDir,
    'cnf=s'    => \$optConf,
    'sd=s'     => \$optStatusDir,      
    'pn'       => \$prependNew,
    'wm'       => \$optWM,
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


connectDevice();

# Inventory Mode
if ( $optIntDir || $optStatusDir || $optConf ) {
    # Gather interface status info
    if ( $optIntDir ) {
	getInterfaces( $optIntDir );
    }
    
    # Exit when done with inventory
    exit;
}


# Get the MAC Table if requested
if ( $$devref{mac} && ( $optMacFile || $optInterfacesFile ) ) {
    print "$scriptName($PID): Getting the WiFi Client Table on $$devref{fqdn}\n" if $DEBUG>1;
    $mac_ref = getMacTable();

    print "$scriptName($PID): Getting the Interface Status Table on $$devref{fqdn}\n" if $DEBUG>1;
    $int_ref = getInterfaceTable();
}

# Get the ARP Table
if ( $$devref{arp} ) {
    print "$scriptName($PID): Getting the ARP Table on $$devref{fqdn}\n" if $DEBUG>1;
    $arp_ref = getARPTable();
}

# Get the IPv6 Table (optional)
#if ( $optV6 ) {
#    print "$scriptName($PID): Getting the IPv6 Neighbor Table on $$devref{fqdn}\n" if $DEBUG>1;
#    $v6_ref = getIPV6Table();
#}


################################################
# Clean Trunk Data and Save everything to disk #
################################################

# Use Helper Method to strip out trunk ports
#print "$scriptName($PID): Cleaning Trunk Data on $$devref{fqdn}\n" if $DEBUG>1;
#$mac_ref = cleanTrunks( $mac_ref, $int_ref );


#croak "Remove Me: don't write to files yet\n";

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
#          **Edit this section**             #
##############################################


## Sample Connect to Device method that obeys the $use_ssh and $use_telnet options
sub connectDevice {

    # connect if ssh option is defined
    if ( !$$devref{forcetelnet} && ( $use_ssh || $$devref{forcessh} ) ) {
	
	# try to connect
	$EVAL_ERROR = undef;
	eval {

	    # Get credentials
	    my ( $user, $pass, $enable ) = getCredentials( $devref );

	    
	    # Get a new cisco session object
	    print "SSH: Logging in to $$devref{fqdn}\n" if $DEBUG>3;
	    
	    $session = Net::SSH::Expect->new(
						 host => $$devref{fqdn},
						 password => $pass,
						 user => $user,
						 raw_pty => 1,
						 timeout => $login_timeout,
						);
	    
	    # Login Aruba
	    $session->login();

	    # Enable
	    my @output = SSHcmd( "enable", "Password" );

	    # Use specific Aruba Enable Password if defined
	    if ( $aruba_enable_pass ) {
		@output = SSHcmd( "$aruba_enable_pass" );
	    }
	    else {
                @output = SSHcmd( "$enable" );
	    }

	    # Turn off paging
            @output = SSHcmd( "no paging" );
	    
	};

	if ($EVAL_ERROR) {
            die "$scriptName($PID): |ERROR|: Could not open SSH session to $$devref{fqdn}: $EVAL_ERROR\n";
        }
	
    }
    
    # connect if telnet method is defined
    elsif ( $use_telnet || $$devref{forcetelnet} ) {
	
    }
}

# Aruba Client/AP mapping
#
# Array CSV Format: host,mac,port
sub getMacTable {
    my @mactable;
    my @entry;
    my %assoc;

    # First grab association table for speed details etc
    my @assoc = SSHcmd( "show ap association" );

    # Split out lines, results returned on one line
    @assoc = split(/\n/, $assoc[0] );

    foreach my $line ( @assoc ) {
        @entry = split( /\s+/, $line );
        print "entry: $entry[2]\n" if $DEBUG>5;

        if ( $entry[2] =~ /[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}/ ) {
            my $mac = $entry[2];
            $entry[13] =~ s/A//;
            $entry[13] =~ s/W//;

            $assoc{$mac} = { speed => $entry[10], 
                 flags => $entry[13], 
                 vlan  => $entry[8],
                 ssid  => $entry[7],
                 ap    => $entry[0], };
        }
    }

    # User Table
    my @output = SSHcmd( "show user-table" ); 
    #@output = $session->exec( "show user-table" );

    # Split out lines, results returned on one line
    @output = split(/\n/, $output[0] );

    foreach my $line ( @output ) {
	@entry = split( /\s+/, $line );
	my $mac = $entry[1];
	my $ap  = "$assoc{$mac}{ap}";
	
	my @devtype = split( /\stunnel\s+/, $line );
	my $devtype = $devtype[1];

	my $subint = "$assoc{$mac}{ssid}-$assoc{$mac}{vlan}";
	my $speed  = "$assoc{$mac}{speed}";
	$speed = "$speed-$assoc{$mac}{flags}" if $assoc{$mac}{flags};
	my $actualip = $entry[0];

	$speed =~ s/^(a|b|g)/11$1/;

	print "DEBUG: mac:$entry[1] ap:$ap ssid:$subint devtype:devtype[1]\n" if $DEBUG>5;

	$entry[1] = getCiscoMac( $entry[1] );

	# Match MAC Address and authenticated flag
	if ( $ap && $entry[1] && ( $entry[5] =~ /802\.1x|Web/ || $entry[2] =~ /voice/ ) ) {
	
	    print "ACCEPTED: $$devref{host},$entry[1],$ap,wifi,$subint,$actualip,$speed,$devtype\n" if $DEBUG>4;	    
	    push( @mactable, "$$devref{host},$entry[1],$ap,wifi,$subint,$actualip,$speed,$devtype" );
	}
	
	# Guest Portal Login
	elsif ( $ap && $entry[3] =~ /cp\-logon/) {
	    print "ACCEPTED: $$devref{host},$entry[1],$ap,wifi,$subint-unauth,$actualip,$speed,$devtype\n" if $DEBUG>4;
	    push( @mactable, "$$devref{host},$entry[1],$ap,wifi,$subint-unauth,$actualip,$speed,$devtype" );
	}
	else {
	    print "DEBUG Discarded Entry: mac:$entry[1] role:$entry[3] ap:$entry[6]\n" if $DEBUG>3;
	}
	

    }

    # Catch Bad Data
    if ( !$mactable[0] ) {

	# Catch an empty but valid client table
	foreach my $line ( @output ) {
	    #print "line: $line\n";
	    if ( $line =~ /User Entries\:\s+0\/0/ ) {
		print "$scriptName($PID): Client Table Empty on $$devref{host}: $line\n" if $DEBUG>1;
		return 0;
	    }
	}

        print STDERR "$scriptName($PID): |Warning|: No Wifi client data received from $$devref{host}: Use netdbctl -debug 2 for more info\n";
        
        if ( $DEBUG>1 ) {
	    
            print "DEBUG: Bad mac-table-data:\n";

	    foreach my $line ( @output ) {
		print "Bad Aruba Data: $line\n";
	    }
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

   # User Table
    my @output = SSHcmd( "show ap radio-database" );

    # Split out lines, results returned on one line
    @output = split(/\n/, $output[0] );

    foreach my $line ( @output ) {
        my @entry = split( /\s+/, $line );
	my ( $devstr, $rad_a, $rad_g );

	my @g = split(/\//, $entry[6] );
	my @a = split(/\//, $entry[7] );

	# APM vs Clients
	if ( $a[0] eq 'APM' ) {
	    $rad_a = 'APM';
	}
	else {
	    $rad_a = "Ch$a[1] $a[3]clients";
	}

	if ( $g[0] eq 'APM' ) {
	    $rad_g = 'APM';
        }
        else {
            $rad_g = "Ch$g[1] $g[3]clients";
        }

	$devstr = "$rad_g / $rad_a";

	# Make sure matches good data
	if ( $a[0] eq 'APM' || $a[2] ) {	    
	    push( @intstatus, "$$devref{host},$entry[0],wifi,wifi,AP$entry[2],$devstr," );
	    print "Accepted  ap: $line\n$$devref{host},$entry[0],wifi,wifi,AP$entry[2],$devstr\n" if $DEBUG>4;
	}
	else {
	    print "Discarded ap: $line\n" if $DEBUG>3;
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

    # Sample entries
    #$arptable[0] = "1.1.1.1,1111.2222.3333,0,20";
    #$arptable[1] = "2.2.2.2,11:11:22:22:33:44,0,Vlan50";

    # Run command twice due to SSH bug?
    my @output = $session->exec( "show arp" );
    @output = $session->exec( "show arp" );

    # Split out lines, results returned on one line
    @output = split(/\n/, $output[0] );

    foreach my $line ( @output ) {
        my @entry = split( /\s+/, $line );

	# If IP in field 1
	if ( $entry[1] =~ /(\d+)(\.\d+){3}/ && $entry[3] ) {
	    print "DEBUG: arp:$entry[1] mac:$entry[2] int:$entry[3]\n" if $DEBUG>4;
	    push( @arptable, "$entry[1],$entry[2],0,$entry[3]" );
	}
    }
    
    if ( !$arptable[0] ) {
        print STDERR "$scriptName($PID): |ERROR|: No ARP table data received from $$devref{host} (use netdbctl -debug 2 for more info)\n";
	
        if ( $DEBUG>1 ) {
            print "DEBUG: Bad ARP Table Data Received: @output\n";
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


# Get individual interface statistics
sub getInterfaces {

    my ( $curInt, $curFile );
    my @int;

    my $hostdir = "$optIntDir/$$devref{host}";
    print "Debug: Getting interfaces data from $$devref{host}\n"  if $DEBUG>1;

    # Check for host directory in interfaces, create if none
    unless( -d $hostdir ) {
        mkdir $hostdir or die "Could not create directory $hostdir\n";
    }

    my @shap = SSHcmd( "show ap radio-database" );
    @shap = split( /\n|\r/, $shap[0] );

    foreach my $line (@shap) {
	
	$line =~ s/\r|\n//;
	my $line2 = $line;
	
	my @entry = split( /\s+/, $line2 );

	# Found beginning of new port
	if ( $entry[4] =~ /(Up|Down)/i ) {
	    #print "Got AP: $entry[0],";

	    my @ap = SSHcmd( "show ap details ap-name $entry[0]" );
	    wriInt( $entry[0], @ap );
	}
    }
    return;
}


sub wriInt {
    my $port = shift;
    my @int = shift;

    print "AP DETAILS:@int\n";

    open( my $INT, '>', "$optIntDir/$$devref{host}/$port.txt" ) or die "$optIntDir/$$devref{host}/$port.txt";

    my $date = localtime;

    print $INT "$date\n";

    foreach my $line ( @int ) {
        print $INT "$line\n";
    }

    close $INT;
}


## SSH Command
sub SSHcmd {
    my $command = shift;
    my $prompt = shift;
    
    if ( !$prompt ) {
	$prompt = $hostprompt;
    }

    my @output = SSHCommand( $session, $command, $ssh_timeout, $prompt );

    return @output;
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
    $config->define( "ipv6_file=s", "datadir=s", "devuser=s", "devpass=s", "ssh_timeout=s", "telnet_timeout=s" );
    $config->define( "arubaenablepass=s" );
    $config->file( "$config_file" );

    # Credentials
    $username = $config->devuser();
    $password = $config->devpass();    

    $aruba_enable_pass = $config->arubaenablepass() if $config->arubaenablepass();

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
    Usage: arubascraper.pl [options] 

    Required:
      -d  string       NetDB Devicefile config line

    Note: You can test with just the hostname or something like:
          arubascraper.pl -d switch1.local,arp,forcessh 

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

