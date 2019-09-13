#!/usr/bin/perl
##########################################################################
# Change the vlan on a switchport
# Author: Jonathan Yantis <yantisj@gmail.com>
# Copyright (C) 2013 Jonathan Yantis
##########################################################################
# 
# About: This script takes in a switchname, port, data vlan and an optional
# voice vlan and makes this change on a cisco switch.
#
# Note: If you want to use this from the web interface, make sure the apache
# user has access to this script and can write to /var/log/netdb/vlanchange.log
#
##########################################################################
# License:
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
use NetDB;
use NetDBHelper;
use Getopt::Long;
use English qw( -no_match_vars );
use Net::DNS;
use IO::Socket::INET;
use strict;
use warnings;

# no nonsense
no warnings 'uninitialized';

my $config_file = "/etc/netdb.conf";
my $DEBUG          = 0;

# Program Variables
my ( $logfile, $ssh_session, $use_ssh, $use_telnet, $user );

$user = "CLI";

# Options
my ( $optVlan, $optDesc, $optShutNoShut );

# Input Options
if ( $ARGV[0] eq "" ) { &usage(); }

GetOptions(
    'vl=s'   => \$optVlan,
    'ds=s'   => \$optDesc,
    'u=s'    => \$user,
    'sns=s'  => \$optShutNoShut,
    'conf=s' => \$config_file,
    'v'      => \$DEBUG,
    	   
          )
or &usage();

&parseConfig();

#$DEBUG = 5;

# Load config file
altHelperConfig( $config_file, $DEBUG );

# VLAN Switch Option
if ( $optVlan ) {
    vlanSwitch( $optVlan );
}
elsif ( $optDesc ) {
    changeDesc( $optDesc );
}
elsif ( $optShutNoShut ) {
    shutNoShut( $optShutNoShut );
}

# Shut no shut by default, if switch,port,status where status is:
# status = shut, skip no shut
# status = noshut, skip shut
sub shutNoShut {
    my $input = shift;
    my $session;
    my $success = 1;
    my @results;
    my @cmdresults;

    my ( $host, $port, $status ) = split( /\,/, $input );

    # Check for port, if no description remove description from port
    if ( $port =~ /\// ) {
	
        logMessage( "Getting Session on $host" ) if $DEBUG;
        $session = connectDevice( $host );
	
        logMessage( "$status on $host,$port" ) if $DEBUG;

	# SSH
        if ( $ssh_session ) {
            @cmdresults = SSHCommand( $session, "configure terminal" );
            @cmdresults = SSHCommand( $session, "interface $port" );
	    
	    # Skip when noshut is issued
	    if ( $status ne 'noshut' ) {
		@cmdresults = SSHCommand( $session, "shut" );
		sleep 5;
	    }

	    # 
	    if ( $status ne 'shut' ) {
		@cmdresults = SSHCommand( $session, "no shut" );
	    }

	    logMessage( "Successfully $status $host $port" );
	}
	
	# Telnet
	else {
	    @cmdresults = $session->cmd( String => "configure terminal" );
            @cmdresults = $session->cmd( String => "interface $port" );
            @cmdresults = $session->cmd( String => "shut" );
	    sleep 5;
            @cmdresults = $session->cmd( String => "shut" );

            if ( $cmdresults[0] =~ /Invalid/i ) {
                logErr( "Shut no Shut Error on $host $port: @cmdresults" );
                $success = undef;
            }

            if ( $success ) {
                logMessage( "Successfully shut no shut $host $port" );
            }

	}
    }
}


sub changeDesc {
    my $input = shift;
    my $session;
    my $success = 1;
    my @results;
    my @cmdresults;

    my ( $host, $port, $desc ) = split( /\,/, $input );

    $desc =~ s/^\"(.*)\"$/$1/g;

    print "Sanitized Description: $desc\n" if $DEBUG;

    # Check for port, if no description remove description from port
    if ( $port =~ /\// ) {
	
	logMessage( "Getting Session on $host" ) if $DEBUG;
        $session = connectDevice( $host );

	logMessage( "Changing Description on $host,$port" ) if $DEBUG;
	
	if ( $ssh_session ) {
	    @cmdresults = SSHCommand( $session, "configure terminal" );
	    @cmdresults = SSHCommand( $session, "interface $port" );

	    # Add a description
	    if ( $desc ) {
		@cmdresults = SSHCommand( $session, "description $desc" );
	    }
 
	    # Remove existing description
	    else {
		@cmdresults = SSHCommand( $session, "no description" );
	    }


	    if ( $cmdresults[0] =~ /Invalid/i ) {
		logErr( "Description Change Error on $host $port $desc: @cmdresults" );
		$success = undef;
	    }
	    # Save Config
	    @cmdresults = SSHCommand( $session, "end" );
	    @cmdresults = SSHCommand( $session, "copy running-config startup-config\n\n" );
	    
	    if ( $cmdresults[0] =~ /Invalid/i ) {
		logErr( "Error saving configuration on $host: @cmdresults" );
		$success = undef;
	    }
	    
	    if ( $success ) {
		logMessage( "Successfully changed $host $port description to $desc" );
	    }
	}
	
	# Telnet
	else {
	    @cmdresults = $session->cmd( String => "configure terminal" );
            @cmdresults = $session->cmd( String => "interface $port" );
            @cmdresults = $session->cmd( String => "description $desc" );
	    
            if ( $cmdresults[0] =~ /Invalid/i ) {
                logErr( "Description Change Error on $host $port: @cmdresults" );
                $success = undef;
            }
            # Save Config                                                                                                                                                                          
            @cmdresults = $session->cmd( String => "end" );
            @cmdresults = $session->cmd( String => "copy running-config startup-config\n\n" );
	    

            if ( $success ) {
                logMessage( "Successfully changed $host $port description to $desc" );
            }
	}
    }
}

## Change VLAN on switchport string "switch,port,vlan_id";
sub vlanSwitch {
    my $input = shift;
    my $session;
    my $success = 1;
    my @results;
    my @cmdresults;

    my ( $host, $port, $dVlan, $vVlan ) = split( /\,/, $input );

    # Input sanity check
    if ( $host && $port && $dVlan =~ /\d+/ ) {
	
	# Get a session on device
	logMessage( "Getting Session on $host" ) if $DEBUG;
	$session = connectDevice( $host );
	
	if ( $session ) {
	    
	    logMessage( "Changing VLAN on $host" ) if $DEBUG;

	    if ( $ssh_session ) {
		@cmdresults = SSHCommand( $session,  "configure terminal" );
		@cmdresults = SSHCommand( $session,  "interface $port" );
		@cmdresults = SSHCommand( $session,  "switchport access vlan $dVlan" );

		if ( $cmdresults[0] =~ /Invalid/i ) {
		    logErr( "Vlan Change Error on $host $port $dVlan: @cmdresults" );
		    $success = undef;
		}
		
		# Voice Vlan Option
		if ( $vVlan ) {
		    @cmdresults = SSHCommand( $session,  "switchport voice vlan $vVlan" );
		}

		logMessage( "Saving Config on $host" ) if $DEBUG;

		# Save Config
		@cmdresults = SSHCommand( $session,  "end" );
		@cmdresults = SSHCommand( $session,  "copy running-config startup-config\n\n" );
		
		if ( $cmdresults[0] =~ /Invalid/i ) {
                    logErr( "Error saving configuration on $host: @cmdresults" );
		    $success = undef;
                }

		if ( $success ) {
		    logMessage( "Success: Changed $host $port to VLAN $dVlan,$vVlan for $user" );
		}

	    }
	    else {

		logMessage( "Changing VLAN on $host" ) if $DEBUG;
		
                @cmdresults = $session->cmd( String => "configure terminal" );
                @cmdresults = $session->cmd( String => "interface $port" );
                @cmdresults = $session->cmd( String => "switchport access vlan $dVlan" );
		
		# Voice Vlan Option
                if ( $vVlan ) {
                    @cmdresults = $session->cmd( String => "switchport voice vlan $vVlan" );
                }
		
		logMessage( "Saving Config on $host" ) if $DEBUG;


		# Save Config
		@cmdresults = $session->cmd( String => "end" );
                @cmdresults = $session->cmd( String => "copy running-config startup-config\n\n" );


                if ( $success ) {
                    logMessage( "Successfully changed $host $port to VLAN $dVlan,$vVlan for $user" );
                }

	    }
	    
	}

	# No session returned
	else {
	    logErr( "Failed to get session on $host for vlan change" ); 
	}
	
    }
    else {
	logErr( "Input Error for VLAN Change: $input\n" );
    }

}

# Get a session on a device
# Checks to see if telnet or ssh is enabled, tries to login and get a $session
sub connectDevice {
    my $session;
    my $fqdn = shift;
    my $ssh_enabled;
    my $pid = $$;

    print "PID($pid): Connecting to $fqdn using SSH($use_ssh) Telnet($use_telnet)...\n" if $DEBUG>1;


    ## Test to see if SSH port is open
    if ( $use_ssh ) {
        print "PID($pid): Testing port 22 on $fqdn for open state\n" if $DEBUG>1;

        my $hostip;

        # Get IP Address
        eval {
            $hostip = inet_ntoa(inet_aton($fqdn));
            print "IP for $fqdn:\t$hostip\n\n" if $DEBUG>1;
        };

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
            print "PID($pid): $fqdn SSH port open\n" if $DEBUG>1;
        }
        else {
            print "PID($pid): $fqdn SSH port closed\n" if $DEBUG>1;
        }
    }

    # Attempt SSH Session, return 0 if failure and print to stderr
    if ( $ssh_enabled ) {

        $EVAL_ERROR = undef;
        eval {
            $session = get_cisco_ssh_auto( $fqdn );
	    
            $ssh_session = 1
        };

        if ($EVAL_ERROR || !$session) {
            die "PID($pid): |ERROR|: Could not open SSH session to $fqdn: $EVAL_ERROR\n";
        }
    
        return $session;
    }
    # Fallback to Telnet if allowed
    elsif ( $use_telnet )  {
        print "PID($pid): Could not SSH to $fqdn on port 22, trying telnet\n" if $DEBUG && $use_ssh;

        # Attempt Session, return 0 if failure and print to stderr
        $EVAL_ERROR = undef;
        eval {
            $session = get_cisco_session_auto($fqdn);
            $session->cmd( String => "terminal length 0" ); # nx-os fix
        };

        if ($EVAL_ERROR || !$session) {
            die "PID($pid): |ERROR|: Could not open a telnet session to $fqdn: $EVAL_ERROR\n";
        }

        return $session;
    }

    # Failed to get a session, report back
    else {
        die "PID($pid): |ERROR|: Failed to get a session on $fqdn, no available connection methods\n";
    }
}


## Log message to STDOUT and to a logfile
#  Pass in either a single message or an array
sub logMessage {

    my $message = shift;
    my $date = localtime;

    # Open logfile
    open( my $LOG, '>>', "$logfile" ) or die "Can't log to $logfile: $!\n";

    while ( $message ) {

        chomp $message;
        print $message . "\n";
        print $LOG "$date: $message\n"; 

        # Implement file based logging here

        $message = shift; # Get next log message if array
    }

    close $LOG;
}

## Log errors differently (Still to STDOUT for now)
sub logErr {
    my $message = shift;
    my $date = localtime;

    # Open logfile
    open( my $LOG, '>>', "$logfile" ) or die "Can't log to $logfile: $!\n";

    while ( $message ) {

        chomp $message;
        print "VLAN Change ERROR: " . $message . "\n";
        print $LOG "$date: VLAN Change ERROR: $message\n";

        # Implement file based logging here

        $message = shift; # Get next log message if array
    }

    close $LOG;
}


## Parse the config file and populate script options from config file
sub parseConfig {
    # Create any variables that do not exist to avoid errors
    my $config = AppConfig->new({
                                 CREATE => 1,
                                });

    $config->define( "vlan_log=s", "use_ssh", "use_telnet" );
    $config->file( "$config_file" );

    $logfile     = $config->vlan_log();
    $use_ssh     = $config->use_ssh();
    $use_telnet  = $config->use_telnet();

    if ( !$logfile ) {
	die "Error: Could not enable logging, make sure vlan_log is defined in $config_file\n";
    }

}


## Output the usage info
sub usage {

    print <<USAGE;

  About: Changes the VLAN on switchports
  Usage: vlanchange [options]

   -vl  switch,port,vlan[,voice_vlan]  Change the vlan on a port
   -ds  switch,port,description        Change the description on a port
   -sns switch,port                    Shut/no shut port
   -conf                               Alternate Config File
   -v                                  Verbose

USAGE
    exit;
}

