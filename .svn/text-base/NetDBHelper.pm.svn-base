##############################################################################
# NetDBHelper.pm - Network Tracking Database Helper Module
# Author: Jonathan Yantis <yantisj@gmail.com>
# Copyright (C) 2013 Jonathan Yantis
##############################################################################
#
# This module handles logging in to devices, cleaning up output and writing
# files in parallel.
#
# This replaces the old CiscoHelper.pm module. There is still a lot of crusty
# old code in here, but you don't have to use the login methods for your
# custom plugins if you don't want.  You can safely remove CiscoHelper.pm and
# replace it with this one if you use any of those methods.
#
##############################################################################
# Versions:
#
#  v1.0 - 12/01/2011 - Initial Code ported from CiscoHelper.pm
#  v2.0 - 10/12/2012 - Commenting, function organization, and debuging output
#                      cleanup. Regex cleanup and optimization.
#
##############################################################################
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
##############################################################################
package NetDBHelper;
use English qw( -no_match_vars );
use AppConfig;
use File::Flock;
use Carp;
eval "use Net::Telnet::Cisco;"; # Optional unless telnet is required
use Net::SSH::Expect;
use Net::Ping;
use Net::DNS;
use NetAddr::IP;
use IO::Select;
use IO::Socket::INET6;
use List::MoreUtils;   # for any()
use strict;
use warnings;
use Exporter;

# no nonsense
no warnings 'uninitialized';

our $VERSION = 1.13;

our @ISA = qw(Exporter);
our @EXPORT = qw( cleanTrunks altHelperConfig setPrependNew writeMAC writeARP
                  writeINT writeND writeIPV6 processDevConfig whirley
                  get_cisco_ssh_auto get_cisco_session_auto writeFile
                  normalizePort getSessionCisco sendCiscoCommand SSHCommand
                  attempt_ssh ping_device getIPfromName testSSH
                  get_SSH_session enable_ssh getCredentials compactResults
                );

our @EXPORT_OK = qw( $whirley );

# DEBUG
my $DEBUG = 0;

## Username and password option for get_cisco_session_auto
# Gets data from /etc/netdb.conf
my $username;
my $passwd;
my $username2;       # Try this if the first username/password fails
my $passwd2;
my $enablepasswd;  # The second passwd always tries to enable

my $default_timeout = 20;
my $ssh_timeout     = 10;
my $ssh_port        = 22;
my $login_timeout = undef; # Uses ssh_timeout unless defined in config_file
my $WHIRLEY_COUNT=-1;
my $session_type;
my $general_session;
my $hostprompt;

my ( $whirley, $myprompt );

my @whirley;

$whirley='[>...] [.>..] [..>.] [...>] [...<] [..<.] [.<..] [<...]';@whirley=split /\s+/,$whirley;

# Configuration file to read from
my $config_file = "/etc/netdb.conf";


my ( $datadir, $arpFile, $macFile, $intFile, $v6File, $ndFile );
my ( $maxMacs, $configged, $prependNew, $useFQDN );

my %skip_port;
my %use_port;
my %useTrunkPorts;

my %authgroup;
my %authgroup_user;
my %authgroup_pass;
my %authgroup_enable;

#-----------------------------------------------------------------------------
# Load an alternate configuration file, control the debug variable
#-----------------------------------------------------------------------------
sub altHelperConfig {
    $config_file = shift;
    $DEBUG = shift;

    print "|DEBUG|: Helper Loading Alternate Config File: $config_file\n" if $DEBUG>3;

    checkConfig();
}

#-----------------------------------------------------------------------------
# Enable prependNew option for output files
#-----------------------------------------------------------------------------
sub setPrependNew {
    $prependNew = "new";
}

#-----------------------------------------------------------------------------
# Filter out trunk ports based on maxMacs and interfaces marked as trunks
#
# Input 1: mactable reference
# Input 2: intstatus reference
#-----------------------------------------------------------------------------
sub cleanTrunks {
    my $mactable_ref = shift;
    my $intstatus_ref = shift;

    my @mactable;
    my @intstatus;
    my @cleanMacTable;

    if ( $mactable_ref ) {
        @mactable = @$mactable_ref;
    }
    else {
        print "Warning: Empty mac table passed to cleanTrunks\n" if $DEBUG>1;
        return;
    }

    if ( $intstatus_ref ) {
        @intstatus = @$intstatus_ref;
    }
    else {
        print "Warning: No interface status information passed to cleanTrunks\n" if $DEBUG>1;
    }

    my %trunkports;
    # Parse Config
    checkConfig();

    # Process instatus and find trunk ports
    foreach my $line ( @intstatus ) {
        my ( $host, $port, $state, $vlan ) = split (/\,/, $line );	
        if ( $vlan eq "trunk" ) {
            $trunkports{"$host,$port"} = 1;
            print "|DEBUG|: Trunk: Found trunk port from int status: $host $port\n" if $DEBUG>3;
        }
    }

    ## Find ports with over $maxMacs
    my %portcount;
    # Count the occurances of a port
    foreach my $line ( @mactable ) {
        my ( $host, $mac, $port ) = split( /\,/, $line );
        $portcount{"$host$port"}++;
    }

#    $DEBUG = 6;

    # Add to a new final mac table if port count is below $maxMacs and no excluded, or implicitly included
    foreach my $line ( @mactable ) {
        my ( $host, $mac, $port ) = split( /\,/, $line );                     # split the results

        if ( $portcount{"$host$port"} < $maxMacs ) { # check mac count on port before proceeding
            if ( $use_port{"$host,$port"} ||    # Explicitly use this port 
                !$trunkports{"$host,$port"} || # Use port if not a trunk port
                $useTrunkPorts{$host} ||       # Trunk processing requested for this switch
                $useTrunkPorts{"DEFAULT"} ) {  # Trunk processing on all switches

                # Skip port overrides all, otherwise import data
                if ( !$skip_port{"$host,$port"} ) {
                    push( @cleanMacTable, $line );
                }
                # Skip port debug reporting
                else {
                    print "|DEBUG|: Trunk: Threw out port configured to skip: $host $port $mac\n" if $DEBUG>2;
                }
            }
            # Skip trunk debug reporting
            else {
                print "|DEBUG|: Trunk: Threw out trunk that did not exceed max MAC count: $host $port $mac\n" if $DEBUG>3;
            }
        }
        # Explicitly use port even if it exceeds max mac if requested
        elsif ( $use_port{"$host,$port"} && !$skip_port{"$host,$port"} ) {
            push( @cleanMacTable, $line );
            print "|DEBUG|: Trunk: Importing data that exceeds max mac count requested: $host,$port\n" if $DEBUG>4;
        }
    } # END foreach

    return \@cleanMacTable;
}

#-----------------------------------------------------------------------------
# Write ARP table to disk, use config file's option if filename not passed
#-----------------------------------------------------------------------------
sub writeARP {
    my $results_ref = shift;
    my $altFile = shift;
    checkConfig();

    if ( $altFile ) {
	writeFile( $results_ref, $altFile );
    }
    else {
	writeFile( $results_ref, $arpFile );
    }
}
sub writeMAC {
    my $results_ref = shift;
    my $altFile = shift;
    checkConfig();

    if ( $altFile ) {
	writeFile( $results_ref, $altFile );
    }
    else {
        writeFile( $results_ref, $macFile );
    }
}
sub writeINT {
    my $results_ref = shift;
    my $altFile = shift;
    checkConfig();

    if ( $altFile ) {
        writeFile( $results_ref, $altFile );
    }
    else {
        writeFile( $results_ref, $intFile );
    }
}
sub writeIPV6 {
    my $results_ref = shift;
    my $altFile = shift;
    checkConfig();

    if ( $altFile ) {
        writeFile( $results_ref, $altFile );
    }
    else {
        writeFile( $results_ref, $v6File );
    }
}
sub writeND {
    my $results_ref = shift;
    my $altFile = shift;
    checkConfig();

    if ( $altFile ) {
        writeFile( $results_ref, $altFile );
    }
    else {
        writeFile( $results_ref, $ndFile );
    }
}

#-----------------------------------------------------------------------------
# Write results to file, use locking mechanism to avoid clobbering
#-----------------------------------------------------------------------------
sub writeFile {
    my $results_ref = shift;
    my $results_file  = shift;
    my $pid = $$;

    if ( !$results_file ) {
	croak "Undefined file handle to write to\n";
    }

    # Lock file for writing
    print "PID($pid): |LOCK| $results_file\n" if $DEBUG>4;
    lock( $results_file );

    open( my $RESULTS, '>>', "$results_file") or die "Can't write to $results_file";
    foreach my $line ( @$results_ref ) {
        if ( $line ) {
            print $RESULTS "$line\n";
        }
    }
    close $RESULTS;
    unlock( $results_file );
}

#-----------------------------------------------------------------------------
# Saves all data in an array of hashrefs, each hash contains a device and its
# configured options.
#-----------------------------------------------------------------------------
sub processDevConfig {
    my $line = shift;
    my ( $host, $fqdn, $nmac, $narp, $vrfs, $fssh, $ftelnet, $l_max_macs );
    my ( $v6, $wifi, $sport, $l_devtype, $nd, $tmp ); 
    my ( $gethost, $nobackup, $dobackup, $authgroup );
    my ( $use_port );

    # Process Config
    checkConfig();

    # Strip out spaces, line termination and comments
    chomp($line);
    $line =~ s/\s+//g;
    ( $line ) = split(/\#/, $line );
   
    # split out the options
    my @dev = split(/\,/, $line);
    $fqdn = $dev[0];

    # Use the FQDN for the switch name if configured
    if ( $useFQDN ) {
        print "|DEBUG|: processDevConfig: Using FQDN for switch names on $fqdn\n" if $DEBUG>4;
        $host = $fqdn;
    }
    # Use hostname for switchname (default)
    else {
        ($host) = split(/\./, $fqdn ); # Strip off domain name
    }
    $nmac = 1;

    # Populate options for device
    foreach my $devopt ( @dev ) {
        $nmac = undef if ( $devopt =~ /^(netdbnomac|nomac)$/ ); # Turn off default mac capture
        $wifi = 1 if ( $devopt =~ /^wifi$/ );   # Turn on wifi client capture
        $narp = 1 if ( $devopt =~ /^(netdbarp|arp)$/ );       # Turn on ARP table capture
        $fssh = 1 if ( $devopt eq 'forcessh' );       # Force SSH Connection
        $ftelnet = 1 if ( $devopt eq 'forcetelnet' ); # Force telnet support
        $v6 = 1 if ( $devopt =~ /^(netdbv6|ipv6|v6)$/ );
        $nd = 1 if ( $devopt =~ /^(nd|cdp|lldp)$/ );
        $gethost = 1 if ( $devopt eq 'gethost' );
        $nobackup = 1 if ( $devopt eq 'nobackup' );
        $dobackup = 1 if ( $devopt eq 'dobackup' );

        #skip port entry from dev file
        if ( $devopt =~ /skip_port/ ) {
            ( $tmp, $sport ) = split( /\=/, $devopt );
            $skip_port{"$host,$sport"} = 1;
            print "SKIPPING $host,$sport\n" if $DEBUG>2;
        }
        # Always use this port
        if ( $devopt =~ /use_port/ ) {
            ( $tmp, $sport ) = split( /\=/, $devopt );
            $use_port{"$host,$sport"} = 1;
            print "USING $host,$sport\n" if $DEBUG>2;
        }
        #use trunks from this device
        if ( $devopt =~ /use_trunks/ ) {
           $useTrunkPorts{"$host"} = 1;
            print "Using Trunks on $host\n" if $DEBUG>2;
        }
        # custom max macs on a port
        if ( $devopt =~ /max_macs/ ) {
            my @tmp = split( /\s*\=\s*/, $devopt );
            $l_max_macs = $tmp[1];
        }
        # Check for VRFs
        if ( $devopt =~ /^vrf-.+$/ ) {
            $devopt =~ s/vrf-//;
            $vrfs = $vrfs . "$devopt,";
        }
        # Check for authgroup
        if ( $devopt =~ /authgroup/ ) {
            my @tmp = split( /\s*\=\s*/, $devopt );
            $authgroup = $tmp[1];
        }
        # Check device type
        if ( $line =~ /devtype/ ) {
            ( $tmp, $l_devtype ) = split(/devtype\=/, $line );
            ( $l_devtype ) = split(/\,/, $l_devtype );
        }
	# SSH Port
	if ( $line =~ /ssh_port/ ) {
            ( $tmp, $ssh_port ) = split(/ssh_port\=/, $line );
            ( $ssh_port ) = split(/\,/, $ssh_port );
        }
	# SSH Timeout
        if ( $line =~ /ssh_timeout/ ) {
            ( $tmp, $ssh_timeout ) = split(/ssh_timeout\=/, $line );
            ( $ssh_timeout ) = split(/\,/, $ssh_timeout );
        }
	# Login Timeout
        if ( $line =~ /login_timeout/ ) {
            ( $tmp, $login_timeout ) = split(/login_timeout\=/, $line );
            ( $login_timeout ) = split(/\,/, $login_timeout );
        }

    } # END for
    
    # Populate hashref entry for device
    if ( $host && ( $nmac || $narp || $v6 || $vrfs || $dobackup ) ) {
        my $dref =  { host => $host, fqdn => $fqdn, mac => $nmac, arp => $narp,
                      vrfs => $vrfs, forcessh => $fssh, forcetelnet => $ftelnet,
                      maxmacs => $l_max_macs, v6nt => $v6, nd => $nd,
                      devtype => $l_devtype, gethost => $gethost,
                      nobackup => $nobackup, dobackup => $dobackup,
                      authgroup => $authgroup, wifi => $wifi, 
		      ssh_timeout => $ssh_timeout, ssh_port => $ssh_port, 
		      login_timeout => $login_timeout };
	
        print "|DEBUG|: Device: $host, fqdn: $fqdn, mac: $nmac, wifi: $wifi, arp: $narp, vrfs: $vrfs, ipv6: $v6, devtype: $l_devtype, authgroup: $authgroup, ssh_port: $ssh_port, ssh_timeout: $ssh_timeout, login_timeout: $login_timeout\n" if $DEBUG>2;

        return $dref;
    }
}

#-----------------------------------------------------------------------------
# Get the username, password and enable from config file based on $dref
# Uses authgroup credentials if they exist, otherwise uses default
#-----------------------------------------------------------------------------
sub getCredentials {
    my $dref = shift;
    my ( $user, $pass, $enable, $group );
    parseConfig();
    
    $group = $authgroup{$$dref{host}} if $authgroup{$$dref{host}}; # From config file
    $group = $$dref{authgroup} if $$dref{authgroup};               # From devicelist

    # Check for specified authgroup
    if ( $group ) {
        print "|DEBUG|: $$dref{host} in authgroup $group\n" if $DEBUG>2;
        if ( $authgroup_user{$group} ) {
            $user = $authgroup_user{$group};
        }
        else {
            $user = $username;
        }

        if ( $authgroup_pass{$group} ) {
            $pass = $authgroup_pass{$group};
        }
        else {
            $pass = $passwd;
        }

        if ( $authgroup_enable{$group} ) {
            $enable = $authgroup_enable{$group};
        }
        else {
            $enable = $enablepasswd;
        }
        return ( $user, $pass, $enable );
    }
    # Return default credentials if no authgroup
    else {
        return ( $username, $passwd, $enablepasswd );
    }
} # END sub getCredentials

#-----------------------------------------------------------------------------
# DNS Lookup, returns IPv6 or IPv4 address if if exists,
# croaks if no DNS entry.
#   Input:
#       Fully qualified domain name: the fqdn to lookup.
#   Output:
#       Host IP: the IP address (v6 or v4) of the fqdn
#-----------------------------------------------------------------------------
sub getIPfromName {
    my $fqdn = shift;
    my $hostip;
    my $res = Net::DNS::Resolver->new;
    my $searchv6 = $res->search( $fqdn, 'AAAA' );
    my $searchv4 = $res->search( $fqdn );

    # Check for IPv6 first
    if ( $searchv6 ) {
        my @rrv6 = $searchv6->answer;
        # Check for CNAME, get AAAA record and do lookup on that instead
        if ( $rrv6[0]->type eq 'CNAME' ) {
            $searchv6 = $res->search( $rrv6[0]->cname );
            @rrv6 = $searchv6->answer;
        }
        # AAAA Lookup
        if ( $rrv6[0]->type eq 'AAAA' ) {
            $hostip = $rrv6[0]->address;
            return $hostip;
        }
    }
    # IPv4
    if ( $searchv4 ) {
        my @rrv4 = $searchv4->answer;
        # Search for CNAME, do lookup on that result if exists
        if ( $rrv4[0]->type eq 'CNAME' ) {
            $searchv4 = $res->search( $rrv4[0]->cname );
            @rrv4 = $searchv4->answer;
        }
        if ( $rrv4[0]->type eq 'A' ) {
            $hostip = $rrv4[0]->address;
            return $hostip;
        }
    }
    else {
        # Try hostfile lookup
        my $aton = inet_aton($fqdn);
        if ( $aton ) {
            $hostip = inet_ntoa($aton);
        }
        # Lookup failed
        if ( !$hostip ) {
            croak( "|ERROR|: DNS lookup failure on $fqdn\n" );
        }
        return $hostip;
    }
} # END sub getIPfromName

#-----------------------------------------------------------------------------
# Converts the port full port descriptions to the standard
# short form.
#   Input:
#       port: full port description
#   Output:
#       port: standardized short port description
#-----------------------------------------------------------------------------
sub normalizePort {
    my $port = shift;
    chomp($port);
	$port =~ s/TenGigabitEthernet(\d+\/\d+\/?\d*)$/Te$1/;
	$port =~ s/10GigabitEthernet(\d+\/\d+\/?\d*)$/$1/;
    $port =~ s/^GigabitEthernet(\d+\/\d+\/?\d*)$/Gi$1/;
    $port =~ s/^FastEthernet(\d+\/\d+)$/Fa$1/;
    $port =~ s/^Ethernet(\d+\/\d+\/?\d*)$/Eth$1/;
	$port =~ s/^ethernet(\d+\/?\d*\/?\d*)$/$1/;
    $port =~ s/^Port-channel(\d+)$/Po$1/;

    return $port;
} # END sub normalizePort
#---------------------------------------------------------------------------------------------
# Compacts results, ie removes stray line endings
#   Input:
#       results refrence - refrence to raw cmd results
#   Output:
#       results - refrence to array containg cleaner parseable output
#---------------------------------------------------------------------------------------------
sub compactResults {
    my $results_ref = shift;
    my @cmdresults = @$results_ref;
    my @splitresults;
    my @results;
    #@results = split( /\n/, $cmdresults[0] );
    # Fix line ending issues
    foreach my $result ( @cmdresults ) {           # parse results
        @splitresults = split( /\n/, $result ); # fix line endings
        foreach my $line ( @splitresults ) {
            $line =~ s/[\n|\r]//g;                 # Strip stray \r command returns
            if ($line){
                push( @results, $line );   # save to a single array
            }
        } # END foreach of split results
        @splitresults = undef;
    } # END foreach of cmd results
    return \@results;
} # END sub compactResults

############################
#                          #
# SSH connection functions #
#                          #
############################
#-----------------------------------------------------------------------------
# Test to see if there is an open port listening for SSH on port 22
#   Input: ($hostip, #$fqdn)
#       IP address: of the host to check
#       #Fully Qualified Domain Namem: the fqdn of the device to check
#   Output:
#       Boolean: true if a port is open, false if the port is closed
#-----------------------------------------------------------------------------
sub testSSH {
    my $hostip = shift;
    #my $fqdn = shift;
    ## Test to see if SSH port is open
    print "|DEBUG|: Testing port $ssh_port on $hostip for open state\n" if $DEBUG>2;

    # Create a Socket Connection
    my $remote = IO::Socket::INET6 -> new (
                    Proto => 'tcp',
                    Timeout => 4,
                    PeerAddr => $hostip,
                    PeerPort => $ssh_port );
    # Return true if port is open
    if ($remote) {
        close $remote;
        print "$hostip SSH port open\n" if $DEBUG>2;
        return 1;
    }

    print "$hostip SSH port closed\n" if $DEBUG>2;
    return undef;
} # END sub testSSH
#---------------------------------------------------------------------------------------------
# Attempt SSH Session if port is open, return 0 if failure and print to stderr
#   Input:
#       hostname: DNS resolveable hostname of device to establish an SSH session with.
#       disbable_paging: the command to be executed on the device to disable paging if none is
#           needed use 'none'.
#   Output:
#       Session: a SSH session handle.
#---------------------------------------------------------------------------------------------
sub get_SSH_session {
    my $hostname = shift;
    my $disable_paging = shift;
    my $dref = shift;
    my $session;

    parseConfig();
    my ( $user, $pass, $enable ) = getCredentials( $dref );
    $login_timeout = $$dref{login_timeout} if $$dref{login_timeout};
 
    #print "\n\n****DREF TIMEOUT****: $$dref{login_timeout}\n\n";

    $ssh_port = $$dref{ssh_port} if $$dref{ssh_port};
    
    if ( !$hostname ){  # verify a hostname is given
        croak("Minimum set of arguments undefined in get_SSH_session\n");
        return undef;
    }
    if ( !$disable_paging ){    # check for disable paging command
        print "|SSH|: No disable paging command specified for $hostname, using default\n" if $DEBUG>1;
        $disable_paging = "terminal length 0";
    }
    elsif ( $disable_paging =~ /none/i){    # no paging on this device
        $disable_paging = undef;
    }

     # Creating hostprompt for later
    ( $hostprompt ) = split( /\./, $hostname );
    $hostprompt = '((SSH|'."$user".')@)?' . "$hostprompt" . '(.config)?(\-if)?(.)?(>|#)' if $hostprompt;
    print "|DEBUG|: Host Prompt to wait for: $hostprompt\n" if $DEBUG>5;

    $EVAL_ERROR = undef;
    eval {
        # Get a new session object
        print "|SSH|: Logging in to $hostname (timeout: $login_timeout)\n" if $DEBUG>2;
        $session = Net::SSH::Expect->new(
                                        host => $hostname,
					port => $ssh_port,
                                        password => $pass,
                                        user => $user,
                                        raw_pty => 1,
                                        timeout => $login_timeout,
                                        );
        $session->login();
        my @output;

        if ( $disable_paging ){
            print "|DEBUG|: Logged in to $hostname, setting $disable_paging\n" if $DEBUG>3;
            @output = SSHCommand( $session, $disable_paging );
	        print "|DEBUG|: Login: @output\n" if $DEBUG>4;
        }
        if ( $output[0] =~ /Password/ ) {
           die "Failed to login to $hostname with primary credentials\n";
        }
    }; # END eval
    # If primary login fails, check for backup credentials and try those
    if ($EVAL_ERROR || !$session) {
        print "|SSH|: Primary Login Failed to $hostname: $EVAL_ERROR\n" if $DEBUG;
        if(defined $username2 and defined $passwd2) {
            print "|SSH|: Attempting Secondary Login Credentials to $hostname\n" if $DEBUG;
            my @output;
            $EVAL_ERROR = undef;
            eval {
                # Get a new session object
                print "|SSH|: Secondary login in to $hostname(timeout: $ssh_timeout)\n" if $DEBUG>3;
                $session = Net::SSH::Expect->new(
                                                 host => $hostname,
                                                 password => $passwd2,
						 port     => $ssh_port,
                                                 user => $username2,
                                                 raw_pty => 1,
                                                 timeout => $login_timeout,
                                                );
                $session->login();

                if ( $disable_paging ){
                    print "|DEBUG|: Logged in to $hostname, setting $disable_paging\n" if $DEBUG>3;
                    @output = SSHCommand( $session, $disable_paging );
	                print "|DEBUG|: Login: @output\n" if $DEBUG>4;
                }
            }; # END eval
            if ($EVAL_ERROR || !$session || $output[0] =~ /Password/ ) {
                croak( "\nAuthentication Error: Primary and Secondary login failed to $hostname: $EVAL_ERROR\n" );
                return undef;
            }
        }
        else {
            croak( "\nAuthentication Error: Primary login failed and no secondary login credentials provided\n" );
            return undef;
        }
    } # END if eval

    return $session;
} # END sub get_SSH_session
#-----------------------------------------------------------------------------
# Attempts to get enable privileges, brute force,
# if it asks for a password, send it
#-----------------------------------------------------------------------------
sub enable_ssh {
    my ($session_obj, $enablepasswd) = @_;

    # Try to enable
    $session_obj->send('enable');    
    my @output = $session_obj->waitfor( 'assword|\#' );

    # Look for password prompt
    if ( $output[0] ) {
        SSHCommand( $session_obj, "$enablepasswd" );
    }
    else {
        print "|SSH| Debug: Did not receive password prompt when enabling" if $DEBUG>3;
    }	
} # END sub enable_ssh
#-----------------------------------------------------------------------------
# Send an SSH command and return results as @output
# Looks for prompt to speed things up
#-----------------------------------------------------------------------------
sub SSHCommand {
    my $session = shift;
    my $command = shift;
    my $timeout = shift;
    my $prompt = shift;

    # Custom Timeout
    if ( !$timeout ) {
        $timeout = $ssh_timeout;
	#print "****Command Timeout****: $ssh_timeout\n";
    }
    # Local $prompt overrides all
    if ( !$prompt ) {
        if ( !$hostprompt ) {
            $prompt = "UNKNOWNXYZ";
        }
        else {
            $prompt = $hostprompt;
        }
    }
    print "SSHCommand (command:$command) (timeout:$timeout) (hostprompt:$prompt)\n" if $DEBUG>4;

    my @output;
    checkConfig();

    $session->read_all( 1 ); # Clear any existing input data
    $session->send( "$command" ); # Send command
    $session->waitfor( "$prompt", $timeout ); #wait for prompt or timeout
    
    @output = $session->before(); #data found before prompt
    
    return @output;
} # END sub SSHCommand

###############################
# Device Session Code (nasty) #
###############################
#-----------------------------------------------------------------------------
# SSH Auto login using credentials
#-----------------------------------------------------------------------------
sub get_cisco_ssh_auto {
    
    my $fqdn = shift;
    my $dref = shift;
    
    parseConfig();
    my ( $user, $pass, $enable ) = getCredentials( $dref );

    return get_cisco_ssh(
			 {
            Host        => $fqdn,
            User1       => $user,
            Pass1       => $pass,
            EnablePass1 => $enable,                                  
            User2       => $username2,
            Pass2       => $passwd2,                                       
            EnablePass2 => $enable,                                          
        }
    );
}

#-----------------------------------------------------------------------------
# Get an SSH Session using Net::SSH::Expect
#-----------------------------------------------------------------------------
sub get_cisco_ssh {
    my $session_obj;
    my ($arg_ref) = @_;

    &parseConfig();

    # Hostname of target cisco device
    my $hostname = $arg_ref->{Host};

    # Primary username and password required
    my $user1 = $arg_ref->{User1};
    my $pass1 = $arg_ref->{Pass1};
    if ( !$hostname ) {
        croak("Minimum set of arguments undefined in cisco_get_ssh\n");
    }

    # Optional username and password if first fails
    my $user2 = $arg_ref->{User2};
    my $pass2 = $arg_ref->{Pass2};

    # Enable passwords if required
    my $enable_pass1 = $arg_ref->{EnablePass1};
    my $enable_pass2 = $arg_ref->{EnablePass2};

    # Attempt primary login
    $EVAL_ERROR = undef;
    eval {
        $session_obj = 
        attempt_ssh( $hostname, $user1, $pass1 );
    };

    # If primary login fails, check for backup credentials and try those
    if ($EVAL_ERROR) {

        if(defined $user2 and defined $pass2) {
	    print "SSH: Primary Login Failed, Attempting Secondary Login Credentials to $hostname: $EVAL_ERROR\n" if $DEBUG;
            $session_obj =
            attempt_ssh( $hostname, $user2, $pass2 );
        }
        else {
            croak( "\nAuthentication Error: Primary login failed and no secondary login credentials provided\n" );
        }
    }
    
    # Attempt to enter enable mode if password defined
    if ( $enablepasswd ) {
	enable_ssh( $session_obj, $enablepasswd );
    }

    print "Successfully Logged in, returning login object\n" if $DEBUG>4;

    return $session_obj;    

}

sub attempt_ssh {
    my ( $hostname, $cisco_user, $cisco_passwd ) = @_;

    my $session_obj;

    # Creating hostprompt for later
    ( $hostprompt ) = split( /\./, $hostname );

    $hostprompt = "$hostprompt" . '(.config)*(\-if)*(.)*(>|#)' if $hostprompt;

    print "Host Prompt to wait for: $hostprompt\n" if $DEBUG>4;

    # Get a new cisco session object
    print "SSH: Logging in to $hostname (timeout: $ssh_timeout)\n" if $DEBUG>3;
    
    $session_obj = Net::SSH::Expect->new(
					 host => $hostname,
					 password => $cisco_passwd,
					 user => $cisco_user,
					 raw_pty => 1,
					 timeout => $ssh_timeout,
					);
    
    # Login
    $session_obj->login();
    
    print "Logged in to $hostname, setting terminal length 0\n" if $DEBUG>3;
    my @output = SSHCommand( $session_obj, "terminal length 0" );
    
    # Catch Errors
    foreach my $output ( @output ) {
	
	# ASA Term Length Error Detection
	if ( $output =~ /Invalid/ ) {
	    print "Caught bad ASA Parser trying to set term length\n" if $DEBUG>3;
	    $session_obj->exec( "terminal pager 0" );
	}
	
	# Login failure
	elsif ( $output =~ /Permission/i ) {
	    die "Permission Denied";
	}
	elsif ( $output =~ /Password/i ) {
	    die "Bad Login";
	}
	else {
	    print "SSH login output: $output\n" if $DEBUG>3;
	}
    }
    
    return $session_obj;
}

#-----------------------------------------------------------------------------
# Use the local username and password from library to login
#-----------------------------------------------------------------------------
sub get_cisco_session_auto {
    my $fqdn = shift;
    my $dref = shift;
    parseConfig();

    my ( $user, $pass, $enable ) = getCredentials( $dref );

    return get_cisco_session(
			     {
            Host        => $fqdn,
            User1       => $user,
            Pass1       => $pass,
            EnablePass1 => $enable,                                  
            User2       => $username2,
            Pass2       => $passwd2,                                       
            EnablePass2 => $enablepasswd,                                          
        }
    );
}

#############################################################################
# Logs in to device(Host) using primary credentials (User1 and Pass1) and
# returns a session object.  Optional values are Timeout and User2 and Pass2.
# You can also pass in EnablePass1 and EnablePass2 if the session needs to
# be enabled.  While this is a seemingly needless layer on Telnet::Cisco,
# it saves a lot of code rewrite and login logic for a lot of scripts.
#############################################################################
sub get_cisco_session {
    my $session_obj;
    my ($arg_ref) = @_;

    &parseConfig();

    # Hostname of target cisco device
    my $hostname = $arg_ref->{Host};

    # Primary username and password required
    my $user1 = $arg_ref->{User1};
    my $pass1 = $arg_ref->{Pass1};
    if (!$user1 || !$pass1 || !$hostname ) {
	croak("Minimum set of arguments undefined in cisco_get_session\n");
    }

    # Optional username and password if first fails
    my $user2 = $arg_ref->{User2};
    my $pass2 = $arg_ref->{Pass2};

    # Enable passwords if required
    my $enable_pass1 = $arg_ref->{EnablePass1};
    my $enable_pass2 = $arg_ref->{EnablePass2};

    # Set the timeout for commands
    my $cisco_timeout = $arg_ref->{Timeout};
    if (!defined $cisco_timeout) {
	$cisco_timeout = $default_timeout;
    }

    # Attempt primary login
    $EVAL_ERROR = undef;
    eval {
	$session_obj = 
	attempt_session( $hostname, $user1, $pass1, $cisco_timeout );

	# Enable if defined
	if ($enable_pass1) {
	        enable_session($session_obj, $enable_pass1);
	    }
    };

    # If primary login fails, check for backup credentials if login fails
    if ($EVAL_ERROR =~ "login" ) {
	# Secondary User Credentials
	if(defined $user2 and defined $pass2) {

	    $EVAL_ERROR = undef;

	    eval {
		$session_obj =
		attempt_session( $hostname, $user2, $pass2, $cisco_timeout );
		
		# Enable if defined
		if ($enable_pass2) {
		    enable_session($session_obj, $enable_pass2);
		}
	    };

	    if ( $EVAL_ERROR ) {
		croak( "Telnet login failed on $hostname on primary and secondary credentials: $EVAL_ERROR" );
	    }
	}
	else {
	    croak( "Telnet login failed on $hostname and no backup credentials provided: $EVAL_ERROR" );
	}
    }
    
    # Login Failure
    elsif ($EVAL_ERROR) {
	croak( "$EVAL_ERROR" );
    }
    
    return $session_obj;
}


#-----------------------------------------------------------------------------
# Accepts (hostname, username, password, timeout)
# Returns Net::Telnet::Cisco ref to logged in session
#-----------------------------------------------------------------------------
sub attempt_session {
    my ( $hostname, $cisco_user, $cisco_passwd, $cisco_timeout ) = @_;

    my $session_obj;
    # Get a new cisco session object
    eval {
	    $session_obj = Net::Telnet::Cisco->new( Host => $hostname, 
                            Timeout => $cisco_timeout,
                        );
    };
    if ( $EVAL_ERROR ) {
        croak("\nNetwork Error: Failed to connect to $hostname");
    }

    # Prompt fix for NX-OS
    $myprompt = '/(?m:[\w.-]+\s?(?:\(config[^\)]*\))?\s?[\$#>]\s?(?:\(enable\))?\s*$)/';
    
    $session_obj->prompt( $myprompt );

    # Log in to the router
    $session_obj->login(
        Name     => $cisco_user,
        Password => $cisco_passwd,
			Timeout  => $cisco_timeout,
    );

    $session_obj->cmd( String => "terminal length 0" ); # no-more


    return $session_obj;
}

#-----------------------------------------------------------------------------
# Attempts to get enable privileges
#-----------------------------------------------------------------------------
sub enable_session {
    my ($session_obj, $enablepasswd) = @_;
    
    if ($session_obj->enable($enablepasswd)) {
	my @output = $session_obj->cmd('show privilege') if $DEBUG;
	print "My privileges: @output\n" if $DEBUG>3;
    }
    else { warn "Can't enable: " . $session_obj->errmsg }
    
}

#-----------------------------------------------------------------------------
# Print a spinning progress indicator, use $|=1; in scripts
#-----------------------------------------------------------------------------
sub whirley {
    if ($WHIRLEY_COUNT+1==@whirley) {
        $WHIRLEY_COUNT=0;
    } 
    else {
        $WHIRLEY_COUNT++;
    }
    return "$whirley[$WHIRLEY_COUNT]";
}

####
# Ping device and return up/down status with ping times
# Returns (up_down_bool, ping_time_in_ms)
####
sub ping_device {
    my @results;
    my ($pinghost) = @_;
    my $ping;

    # Try ICMP ping first, then UDP if it fails
    $EVAL_ERROR = "";
    eval {
        $ping = Net::Ping->new("icmp");
        $ping->hires();
        @results = $ping->ping( $pinghost, 2);
    };
    if ($EVAL_ERROR) {
        print "ICMP Ping failed, switching to UDP\n" if $DEBUG;
        $ping = Net::Ping->new("udp");
        $ping->hires(); # detailed stats                                                                                                                           
        @results = $ping->ping( $pinghost, 2 );
    }
    # Format time in ms
    $results[1] = sprintf( "%.2f", $results[1] * 1000 );
    return @results;
}

#######################
# Config File Section #
#######################

# Load Config if not loaded
sub checkConfig {
    if ( !$configged ) {
	parseConfig();
	$configged = 1;
    }
}

sub parseConfig {
    # Create any variables that do not exist to avoid errors
    my $config = AppConfig->new({
                                 CREATE => 1,
                                });

    $config->define( "max_macs=s", "use_trunks=s@", "arp_file=s", "mac_file=s", "int_file=s", "nd_file=s" );
    $config->define( "ipv6_file=s", "datadir=s", "skip_port=s%", "use_port=s%", "ssh_timeout=s", "use_fqdn" );
    $config->define( "devuser=s", "devpass=s", "devuser2=s", "devpass2=s", "enablepass=s", "telnet_timeout=s" );
    $config->define( "authgroup=s%", "authgroup_user=s%", "authgroup_pass=s%", "authgroup_enable=s%" );
    $config->define( "login_timeout=s", "ssh_port=s" );

    $config->file( "$config_file" );

    # Username data
    $username      = $config->devuser();     # First User
    $passwd        = $config->devpass();     # First Password
    $username2     = $config->devuser2();     # DB Read/Write User
    $passwd2       = $config->devpass2();     # R/W Password
    $enablepasswd  = $config->enablepass();   # DB Read Only User
    
    # Load Authgroup Hashes
    my $ag_ref        = $config->authgroup();
    my $ag_user_ref   = $config->authgroup_user();
    my $ag_pass_ref   = $config->authgroup_pass();
    my $ag_enable_ref = $config->authgroup_enable();    
    %authgroup_user   = %$ag_user_ref;
    %authgroup_pass   = %$ag_pass_ref;
    %authgroup_enable = %$ag_enable_ref;

    # Process config file authgroup switches, alternative to ,authgroup= in config file
    foreach my $group ( keys %$ag_ref ) {
        my @devices = split( /\s+/, $$ag_ref{$group} );
        foreach my $device ( @devices ) {
            $authgroup{"$device"} = $group;
            print "authgroup: $device in $group\n" if $DEBUG>5;
        }
    }

    #print "Authgroup: $authgroup_user{group1}\n";

    # SSH Timeouts
    if ( $config->telnet_timeout() ) {
        $default_timeout = $config->telnet_timeout();
    }
    if ( $config->ssh_timeout() ) {
        $ssh_timeout = $config->ssh_timeout();
    }

    # SSH Port
    if ( $config->ssh_port() ) {
	$ssh_port = $config->ssh_port();
    }

    # Login Timeout, fallback to ssh_timeout
    if ( $config->login_timeout() ) {
        $login_timeout = $config->login_timeout()
    }
    else {
        $login_timeout = $ssh_timeout;
    }

    # Write to file options
    my $pre = $prependNew;
    $datadir                = $config->datadir();

    if ( $config->arp_file() ) {
        $arpFile            = $config->arp_file();
        $arpFile            = "$datadir/$pre$arpFile";
    }

    if ( $config->ipv6_file() ) {
        $v6File             = $config->ipv6_file();
        $v6File             = "$datadir/$pre$v6File";
    }
    
    if ( $config->mac_file() ) {
        $macFile            = $config->mac_file();
        $macFile            = "$datadir/$pre$macFile";
    }
    
    if ( $config->int_file() ) {
        $intFile            = $config->int_file();
        $intFile            = "$datadir/$pre$intFile";
    }

    if ( $config->nd_file() ) {
        $ndFile             = $config->nd_file();
        $ndFile             = "$datadir/$pre$ndFile";
    }

    # Trunk Handling
    $maxMacs = $config->max_macs() if $config->max_macs();

    my $useTrunks_ref = $config->use_trunks();
    my @useTrunks = @$useTrunks_ref;

    my $port_ref = $config->skip_port();

    # Skip Port config option
    foreach my $switch ( keys %$port_ref ) {
        my @ports = split( /\s+/, $$port_ref{$switch} );
        foreach my $port ( @ports ) {
            $skip_port{"$switch,$port"} = 1;
            print "skip: $switch,$port\n" if $DEBUG>5;
        }
    }

    # Use ports option
    my $useport_ref = $config->use_port();
    foreach my $switch ( keys %$useport_ref ) {
        my @ports = split( /\s+/, $$useport_ref{$switch} );
        foreach my $port ( @ports ) {
            $use_port{"$switch,$port"} = 1;
            print "useport: $switch,$port\n" if $DEBUG>5;
        }
    }

    # Populate %useTrunkPorts config option
    foreach my $switch ( @useTrunks ) {
        $useTrunkPorts{"$switch"} = 1;
    }

    # FQDN Switch Override
    $useFQDN = $config->use_fqdn();
}

#
1;

