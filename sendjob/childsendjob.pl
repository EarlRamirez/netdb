#!/usr/bin/perl
###########################################################################
# childscraper.pl
# Author: Jonathan Yantis <yantisj@gmail.com>
# Copyright (C) 2013 Jonathan Yantis
###########################################################################
#
# Based on the skeleton scraper to specially send commands to devices 
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
use Net::DNS;
use IO::Socket::INET;
use File::Flock;
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
my $versionfile;

# Config File Options (Overridden by netdb.conf, optional to implement)
my $use_telnet  = 1;
my $use_ssh     = 1;
my $ipv6_maxage = 10;
my $telnet_timeout = 20;
my $ssh_timeout = 10;
my $ssh_session;
my $username;
my $password;

# Other Data
my $session; 

# Device Option Hash
my $devref;

# CLI Input Variables
my ( $optDevice, $optMacFile, $optInterfacesFile, $optArpFile, $optv6File, $prependNew, $debug_level );
my ( $optCmdFile, $optVlanString, $optLogFile, $optConfFile, $optWriMem, $optStatus, $optInterfaces );

# References to arrays of data to write to files
my ( $mac_ref, $int_ref, $arp_ref, $v6_ref );

# Input Options
if ( $ARGV[0] eq "" ) { &usage(); }

GetOptions(
    'd=s'      => \$optDevice,
    'cf=s'     => \$optCmdFile,
    'vs=s'     => \$optVlanString,
    'lf=s'     => \$optLogFile,
    'cnf=s'    => \$optConfFile,
    'sd=s'     => \$optStatus,
    'id=s'     => \$optInterfaces,
    'wm'       => \$optWriMem,
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
if ( !$optDevice && !$optVlanString ) {
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
if ( $optDevice ) {
    $devref = processDevConfig( $optDevice );
}
elsif ( $optVlanString ) {
    $devref = processDevConfig( $optVlanString );
}

# Make sure host was passed in correctly
if ( !$$devref{host} ) {
    print "$scriptName($PID): Error: No host found in device config string\n\n";
    usage();
}

# Save the script name
$scriptName = "childsendjob.pl";
$versionfile = "$optStatus/versions.txt";


############################
# Capture Data from Device #
############################

# Connect to device and define the $session object

my $date = localtime;

if ( $$devref{nobackup} ) {
    print "$scriptName($PID): Skipping device $$devref{fqdn} due to nobackup flag in configuration file\n" if $DEBUG;
}

# Connect to device and process requested options
else {
    logMessage( "$scriptName($PID): Connecting to device $$devref{fqdn} on $date\n");
    connectDevice();
    
    
    # Send Commands
    if ( $optCmdFile ) {
	sendCommandFile( $optCmdFile );
    }
    
    # Vlan Change Script
    elsif ( $optVlanString ) {
	sendVlanChanges( $optVlanString );
    }
    
    # Backup Configuration
    if ( $optConfFile ) {
	backupConfig();
    }
    
    # Get status info
    if ( $optStatus ) {
	getStatus( $optStatus );
    }
    
    # Get Interface Statistics
    if ( $optInterfaces ) {
	getInterfaces( $optInterfaces );
    }
    
    # wri mem
    if ( $optWriMem ) {
	wriMem();
    }
}

##############################################
# Custom Methods to gather data from devices #
#                                            #
#          **Edit This Section**             #
##############################################

sub connectDevice {
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
	wriVersionFile( "$$devref{fqdn},unknown model,DNS Lookup Failed,unknown version,," );
        die "$scriptName($PID): |ERROR|: DNS lookup failure on $fqdn: $EVAL_ERROR\n";
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

	    wriVersionFile( "$$devref{fqdn},unknown model,SSH Connection Failed,unknown version,," );

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
            wriVersionFile( "$$devref{fqdn},unknown version,Telnet Connection Failed,unknown model,," );

            die "$scriptName($PID): |ERROR|: Could not open a telnet session to $fqdn: $EVAL_ERROR";
        }

        return $session;
    }

    # Failed to get a session, report back
    else {
	wriVersionFile( "$$devref{fqdn},unknown version,Connection Failed,unknown model,," );
        die "$scriptName($PID): |ERROR|: Failed to get a session on $fqdn, no available connection methods\n";
    }
}

sub sendCommandFile {
    my $cmdfile = shift;
    my @log;

    logMessage( "$scriptName($PID): Sending Commands to $$devref{fqdn}:" );

    open( my $CMDFILE, '<', $cmdfile ) or die "Can't open Command File $cmdfile: $!\n";

    while ( my $line = <$CMDFILE> ) {
	chomp( $line );

	my @output = sendCommand( $session, "$line\n" );

	$output[0] = "[SENT COMMAND TO $$devref{fqdn}]\n$$devref{host}# $output[0]";
	
	push( @log, @output );

	push( @log, "\n--------------------------------------------------------\n\n" );
    }
    logMessage( @log );
    
}

# Change multiple vlans
sub sendVlanChanges {
    my $vlanstring = shift;
    my $voicevlan;

    my ( $switch, $vlan, @ports ) = split( /\,/, $vlanstring );

    ( $vlan, $voicevlan ) = split( /\//, $vlan );
    
    logMessage( "$scriptName($PID): Changing VLANs: $switch:$vlan/$voicevlan on @ports") if $DEBUG;
    
    # config mode
    sendCommand( $session, "configure terminal" );

    # Change VLAN on each port
    foreach my $port ( @ports ) {
	logMessage( "$scriptName($PID): Changing port $port to VLAN $vlan on $switch ") if $DEBUG>1;
	
	# Change to port
	sendCommand( $session, "interface $port" );

	# Change VLAN
	sendCommand( $session, "switchport access vlan $vlan" );

	# Voice VLAN (optional)
	if ( $voicevlan ) {
	    logMessage( "$scriptName($PID): Changing voice vlan on $port to $voicevlan on $switch" ) if $DEBUG>1;

	    sendCommand( $session, "switchport voice vlan $voicevlan" );
	}
    }
    
    # End
    sendCommand( $session, "end" );
}

# Backup config to $optConfFile
sub backupConfig {

    logMessage( "$scriptName($PID): Saving copy of config on server from $$devref{fqdn}" );

    my $date = localtime;

    my @output = sendCommand( $session, "show run" );
    @output = split( /\n/, $output[0] );

    my $sanity_check;

    # Check for hostname|switchname in config
    foreach my $line ( @output ) {
	if ( $line =~ /hostname|switchname/ ) {
	    $sanity_check = 1;
	}
    }

    # Try Running command again if config not backed up
    if ( !$sanity_check ) {
	logMessage( "$scriptName($PID): Initial Config Save failed on $$devref{fqdn}, trying again" );

	my @output = sendCommand( $session, "show run" );
	@output = split( /\n/, $output[0] );
    }

    # Check for hostname again
    foreach my $line ( @output ) {
        if ( $line =~ /hostname/ ) {
            $sanity_check = 1;
        }
    }

    # If config save fails twice, error out
    if ( !$sanity_check ) {
	@output = undef;
    }
    
    if ( $output[10] ) {
	

	open(CONFIG, ">$optConfFile") or die "Can't open $optConfFile: $!";
	
	$output[0] = "\n!!";
	$output[1] = "\n!!";
#        $output[2] = "\n!!";
#        $output[3] = "\n!!";


	print CONFIG "!! $date";
	
#	print CONFIG @output;
	
	foreach my $line ( @output ) {

            $line =~ s/\r//g;
	    $line =~ s/\n//g;

	    if ( $line ) {
		print CONFIG "$line\n";
	    }
	}

    }
    else {
	print "$scriptName($PID) |ERROR|: no config received from $$devref{fqdn}: @output\n";
	print STDERR "$scriptName($PID) |ERROR|: no config received from $$devref{fqdn}: @output\n";
    }

}

# Wri mem and watch for errors
sub wriMem {

    logMessage( "$scriptName($PID): Saving configuration to NVRAM on $$devref{fqdn}" ) if $DEBUG>1;

    my @output = sendCommand( $session, "wr" );

    # Successful write
    if ( $output[0] =~ /(\[OK\])|(\[\#\#\#\#)|Building/ ) {
	logMessage( "$scriptName($PID): Wri Mem Successful on $$devref{fqdn}\n" );
    }
    else {
	logMessage( "$scriptName($PID): |ERROR|: Write Mem Failed on $$devref{fqdn}: @output\n" );
    }

#    print "wri mem out:\n@output" if $DEBUG;
}

# Get Status info (old code)
sub getStatus {

    my ( $foundver, $tmp, $model, $stackcount, $modelprint, $model2, $model3 );
    my $softver = "Cisco";
    my $shortsoftver = "";
    my $serial;
    my $nxos;
    my $hostname = $$devref{host};
    my @tmp;
    my $uptime;

    my $currentdate = `date`;

    logMessage( "Debug: Getting status info from $$devref{host}\n" ) if $DEBUG>1;
    
    my @shver = sendCommand( $session, "show version" );
    @shver = split( /\n|\r/, $shver[0] );

    foreach my $line (@shver) {
	
	my @output2 = split(/\n/, $line);
	
	if ($foundver) {
	    last;
	}
	
	# Process Device Version
	foreach my $line2 (@output2) {
	    $line2 =~ s/\r|\n//;
	    
	    # IOS Software
	    if ( $line2 =~ /Cisco IOS Software\,/ ) {
		$line2 =~ s/Cisco IOS Software\,//;

		# short version
		@tmp = split( /\,\sVersion\s/i, $line2 );
		$shortsoftver = $tmp[1];
		@tmp = split( /\,/, $tmp[1] );
		$shortsoftver = $tmp[0];

		$line2 =~ s/\,//g;
		$softver = $line2;
	    }

	    # NX-OS Software
	    elsif( $line2 =~ /Cisco Nexus Operating System/ ) {
		$softver = $line2;
		$nxos = 1;
	    }
	    elsif ( $nxos && $line2 =~ /^\s+system\:\s/ ) {
		$line2 =~ s/\s+/ /g;
		$line2 =~ s/^\s+system\:\s//;
		$line2 =~ s/version/Version/;
		$softver = "$softver $line2";
		$shortsoftver = $line2;
	    }
	    elsif ( $line2 =~ /$hostname\suptime/ ) {
		my @uptime = split( /uptime\sis\s/, $line2 );
		$uptime[1] =~ s/\,\s/\//g;
		$uptime = $uptime[1]; # IOS
	    }

	    # NXOS Fix
	    elsif ( $line2 =~ /Kernel\suptime/ ) {
		my @uptime = split( /uptime\sis\s/, $line2 );
                $uptime[1] =~ s/\,\s/\//g;
		$modelprint = "$modelprint" . "$uptime[1]";
	    }
	    
	    # 3750s model
	    elsif ( $line2 =~ /Model number/ ) {
		if ( $line2 =~ /3750/ ) {
		    ($tmp, $model) = split(/\s\:\s/, $line2);
		    if ( !$modelprint ) {
			$stackcount = 1;
			$modelprint = "$$devref{fqdn},$model,$softver,$shortsoftver,$uptime\n";
		    }
		    else {
			$stackcount++;
		    }
		}
	    }
	    # Everything else
	    elsif ($line2 =~ /cisco (WS-|Cat|MSFC|72|AIR|Nexus)/) {
		if ( $line2 !~ /3750/ ) {
		    ($tmp, $model, $model2, $model3) = split(/\s+/, $line2);
		    $model = $model2 if $model eq "cisco";
		    $model = "$model $model3" if $model3 =~ /^C/; #Nexus
		    $modelprint = "$$devref{fqdn},$model,$softver,$shortsoftver,$uptime\n";
		    $foundver = 1;
		    last;
		}
	    }
	    elsif ($line2 =~ /WS-X6K/) {
		($tmp, $tmp, $model) = split(/\s+/, $line2);
		$modelprint = "$$devref{fqdn},$model,$softver,$shortsoftver,$uptime\n";
		$foundver = 1;
		last;
	    }
	}
    }

    logMessage( "Model Debug: $modelprint\n" ) if $DEBUG>1;

    # Save Version info if it exists
    if ( $stackcount ) {
	$modelprint = "$modelprint,$stackcount";
    }
    else {
	$modelprint = "$modelprint,1";
    }
    wriVersionFile( $modelprint );
    

    open( STATUS, ">$optStatus/$$devref{host}.txt" ) or die "Can't open $optStatus/$$devref{host}.txt";
    open( my $MODEL, '>', "$optStatus/$$devref{host}-model.txt" ) or die "Can't open $optStatus/$$devref{host}-model.txt";
    open( my $VER, '>', "$optStatus/$$devref{host}-ver.txt" ) or die "Can't open $optStatus/$$devref{host}-ver.txt";
    open( my $CDP, '>', "$optStatus/$$devref{host}-cdp.txt" ) or die "Can't open $optStatus/$$devref{host}-cdp.txt";
    open( my $INT, '>', "$optStatus/$$devref{host}-int.txt" ) or die "Can't open $optStatus/$$devref{host}-int.txt";
    open( my $VLAN, '>', "$optStatus/$$devref{host}-vlan.txt" ) or die "Can't open $optStatus/$$devref{host}-vlan.txt";
    
    
    # insert date
    print STATUS "!! $currentdate";
    print STATUS "!! $hostname Status Information\n\n";
    
    # sh ver
    my @output = sendCommand( $session, "show version" );
    
    print STATUS "\n\nshow version:\n";
    print STATUS "------------------------------------------------------------\n\n";
    print STATUS @output;
    print $VER @output;

    # sh mod
    @output = sendCommand( $session, "show module" );
    
    print STATUS "\n\nshow module:\n";
    print STATUS "------------------------------------------------------------\n\n";
    print STATUS @output;
    print $MODEL @output;

    # Inventory
    @output = sendCommand( $session, "show inventory" );
    print $MODEL "\n------------------------------------------------------------\n";
    print $MODEL @output;

    
    # CDP
    print STATUS "show cdp neighbor:\n";
    print STATUS "------------------------------------------------------------\n\n";
    
    @output = sendCommand( $session, "show cdp neighbor" );
    
    print STATUS @output;
    print $CDP @output;

    # sh vlan
    @output = sendCommand( $session, "sh vlan" );
    
    print STATUS "\n\nshow vlan:\n";
    print STATUS "------------------------------------------------------------\n\n";
    print STATUS @output;
    print $VLAN @output;
    
    @output = sendCommand( $session, "sh spanning-tree root" );
    print $VLAN "\n------------------------------------------------------------\n\n";
    print $VLAN @output;

    @output = sendCommand( $session, "sh spanning-tree root priority system-id" );
    print $VLAN "\n------------------------------------------------------------\n\n";
    print $VLAN @output;

    @output = sendCommand( $session, "sh spanning-tree detail | i changes|exec|from" );
    print $VLAN "\n------------------------------------------------------------\n\n";
    print $VLAN @output;

    @output = sendCommand( $session, "sh interface status" );
    
    print STATUS "\n\nshow interface status:\n";
    print STATUS "------------------------------------------------------------\n";
        
    print STATUS @output;
    print $INT @output;

    @output = sendCommand( $session, "sh interface" );
    print $INT "\n------------------------------------------------------------\n\n";
    print $INT @output;


    # CDP Detail
    @output = sendCommand( $session, "show cdp neighbor detail" );
    
    print $CDP "\n------------------------------------------------------------\n\n";
    print $CDP @output;

    close STATUS;
    close $MODEL;
    close $VER;
    close $VLAN;
    close $INT;
    close $CDP;
}

sub wriVersionFile {
    my $verinfo = shift;

    $verinfo =~ s/\n//g;
    $verinfo = "$verinfo\n";

    if ( $optStatus ) {

	logMessage( "|LOCK| $versionfile...\n" ) if $DEBUG>1;
	
	lock( $versionfile );
	
	open(VERSION, ">>$versionfile") or die "Can't open $versionfile";
        
	print VERSION $verinfo;    
	
	close VERSION;
	unlock( $versionfile );
    }
}


# Get individual interface statistics
sub getInterfaces {

    my ( $curInt, $curFile );
    my @int;

    my $hostdir = "$optInterfaces/$$devref{host}";
    logMessage( "Debug: Getting interfaces data from $$devref{host}\n" ) if $DEBUG>1;
    
    # Check for host directory in interfaces, create if none
    unless( -d $hostdir ) {
	mkdir $hostdir or die "Could not create directory $hostdir\n";
    }

    my @shint = sendCommand( $session, "show interface" );
    @shint = split( /\n|\r/, $shint[0] );

    foreach my $line (@shint) {
        
        my @output2 = split(/\n/, $line);
        
        # Process Line by Line
        foreach my $line2 (@output2) {
            $line2 =~ s/\r|\n//;
	    
	    # Found beginning of new port
	    if ( $line2 =~ /(^Gig|Fast|Ether|Ten|10Gi|port-channel|Port-channel|Vlan)\w*\d/ ) {

		# Finish current port out
		if ( $curInt ) {
		    writeInt( $curInt, \@int );
		    @int = undef;
		}
		
		push( @int, $line2 );

		#print "$line2\n";
		( $curInt ) = split( /\s+/, $line2 );

		# Normalize port in NetDB Style
		$curInt = normalizePort( $curInt );
		$curInt =~ s/\//\-/g;

		#print "port: $curInt\n";
	    }

	    # Save whatever line we're on to the current port array
	    else {
		#print "line: $line2\n";
		push( @int, $line2 );
	    }	    
	}
    }    
    # Finish out Current Port
    if ( $curInt ) {
	writeInt( $curInt, \@int );
	@int = undef;
    }

    return;
}


sub writeInt {
    my $port = shift;
    my $int = shift;
    my @int = @$int;
    
    open( my $INT, '>', "$optInterfaces/$$devref{host}/$port.txt" ) or die "$optInterfaces/$$devref{host}/$port.txt";    

    print $INT "$date\n";
    
    foreach my $line ( @int ) {
	print $INT "$line\n";
    }
    
    close $INT;
}

sub normalizePortOld {
    my $port = shift;

    $port =~ s/TenGigabitEthernet(\d+\/\d+\/?\d*)$/Te$1/;
    $port =~ s/10GigabitEthernet(\d+\/\d+\/?\d*)$/$1/;
    $port =~ s/^GigabitEthernet(\d+\/\d+\/?\d*)$/Gi$1/;
    $port =~ s/^FastEthernet(\d+\/\d+\/?\d*)$/Fa$1/;
    $port =~ s/^Ethernet(\d+\/\d+\/?\d*)$/Eth$1/;
    $port =~ s/^ethernet(\d+\/\d+\/?\d*)$/$1/;
    $port =~ s/^Port-channel(\d+)$/Po$1/;
    $port =~ s/^port-channel(\d+)$/Po$1/;
    
    #print "$port\n" if $port =~ /Ethernet/;
    
    return $port;
}

# Print to the logfile
sub logMessage {

    my @message = @_;
    my @log;
    my $date = localtime;

    foreach my $line (@message) {
        chomp( $line );

        push( @log, "$line" );

	# Print All error to parent
	if ( $line =~ /ERROR/ ) {
	    print "$line\n";
	}
        # Print results only if not logging to file
        elsif ( !$optLogFile || $DEBUG>2 ) {
            print "$line\n";
        }
    }

    if ( $optLogFile ) {
        writeFile( \@log, $optLogFile );
    }
}

# Send command to device, ssh or telnet
sub sendCommand {
    my $session = shift;
    my $cmd = shift;
    my @output;

    if ( $ssh_session ) {
	@output = SSHCommand( $session, "$cmd" );
	return @output;
    }

    # Telnet session, disable error handling
    elsif ( $session ) {

	$EVAL_ERROR = undef;
	eval {
	    @output = $session->cmd( String => "$cmd" );

	    my $tmp;
	    foreach my $line ( @output ) {
		$tmp = "$tmp$line";
	    }
	    @output = undef;
	    $output[0] = $tmp;

#	    print "out: @output\n";

	};
	if ($EVAL_ERROR) {
	    print "$scriptName($PID) |ERROR|: Telnet command failed on $$devref{fqdn}: $cmd\n" if $DEBUG;
	}
	else {
	    print "returning output: @output\n" if $DEBUG>1;
	    return @output;
	}
    }
    
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
    Usage: childsendjob.pl [options] 

    Required:
      -d  string       NetDB Devicefile config line
      -cf file         List of Commands
      -vs strng        Vlan Changes on a device

    Options:
      -wm              Save config on devices
      -cnf file        Save local copy of config to file
      -sd              Save status to directory
      -lf file         File to log results to, otherwise print to screen


    Development Options:
      -v               Verbose output
      -debug #         Manually set debug level (1-6)
      -conf            Alternate netdb.conf file

USAGE
    exit;
}

