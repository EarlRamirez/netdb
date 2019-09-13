#!/usr/bin/perl
##########################################################################
# checkpoint_ia.pl - Extract Checkpoint Identity Awareness data
# Authors:
# dav3860
# Jonathan Yantis <yantisj@gmail.com>
# Copyright (C) 2014 Jonathan Yantis, dav3860
##########################################################################
# 
# Extract Checkpoint Identity Awareness data from PDP hosts
#
# In Checkpoint Identity Awareness architecture, the PDP host is 
# responsible for collecting and sharing identities, using AD queries, 
# agents, captive portals, etc
#
# Output Format: mac,,,,userID,,,,,,,,
#
# You need to setup this as a cronjob to get the Checkpoint IA data, and
# run netdbctl -n to import the NAC output file
#
# See forum post:
#
# https://sourceforge.net/p/netdbtracking/discussion/939988/thread/8578821f/?limit=25
#
# The following parameters are needed in /etc/netdb.conf :
# checkpoint_host = 192.168.50.1,10.172.25.254 (a list of Checkpoint firewalls acting as PDP servers)
# checkpoint_user = monitoruser (a user allowed to run the "pdp monitor summary all" command)
# checkpoint_pass = (an optional password. If not given, SSH key authentication will be used)
#
##########################################################################

use NetDB;
use Net::SSH::Expect;
use Getopt::Long;
use AppConfig;
use English qw( -no_match_vars );
use DBI;
use strict;
use warnings;

# no nonsense
no warnings 'uninitialized';

my $DEBUG          = 0;
my $config_file    = "/etc/netdb.conf";
my $ssh_timeout = 10;
my $scriptName = "checkpoint_ia.pl";
my $hours = 4;

my ( $optoutfile, $chost, $cuser, $cpass, $cli_host, $session, $optdomain );


# Input Options
if ( $ARGV[0] eq "" ) { &usage(); }

GetOptions(
    'o=s'  => \$optoutfile,
    's=s'  => \$cli_host,
    'conf=s' => \$config_file,
    'd'    => \$optdomain,
    'v'    => \$DEBUG,
	  )
or &usage();

# Parse Configuration File
&parseConfig();

# CLI Server override
$chost = $cli_host if $cli_host;

if ( $optoutfile ) {
    # Get database connection
    my $dbh = connectDBro( $config_file );
 
    open( OUTFILE, ">$optoutfile" ) or die "Can't open $optoutfile: $!\n";

    my @hosts = split( /\,/, $chost );
   
    # Loop through the list of Checkpoint PDP hosts
    foreach my $host ( @hosts ) {
    
      print "Connecting to device $host\n" if $DEBUG;
      $session = connectDevice( $host, $cuser, $cpass );
      
      # If we're connected
      if ( $session ){
        my $user_ref = getUserTable( $session ); # Get the user table from the Checkpoint PDP
        
        foreach my $row ( @{$user_ref} ) {
          my @entries = split(/,/, $row);
          my $netdb_ref = getMACsfromIP( $dbh, $entries[0], $hours ); # Search for the MACs corresponding to this IP address

          if ( $$netdb_ref[0]{"mac"} ) {
            my $mac = $$netdb_ref[0]{"mac"}; # We only keep the last MAC address
            print OUTFILE "$mac,,,,$entries[1],,,,,,,,\n";
          }
          else {
            print "No mac found for $entries[0]\n" if $DEBUG;
          }
        }
      }
    }
    
    close OUTFILE;
    $dbh->disconnect(); 
}
else {
    print "Error: Must use -o option\n";
} # End Main
 
#---------------------------------------------------------------------------------------------
# Connect to Device method
#---------------------------------------------------------------------------------------------
sub connectDevice {
    my $host = shift;
    my $user = shift;
    my $pass = shift;
    my $session;
      
    # try to connect
    $EVAL_ERROR = undef;
    
    eval {

        # Get a new SSH session object
        print "SSH: Logging in to $host\n" if $DEBUG;
        
        # Connect with SSH key authentication
        if ($pass eq "") {
          $session = Net::SSH::Expect->new(
                          host => $host,
                          user => $user,
                          debug => 1,
                          raw_pty => 1,
                          timeout => $ssh_timeout,
                          );
          $session->run_ssh();
          
          my $output=$session->read_all(2);
          if ($output =~ />\s*\z/) {die "Login Failed for $user"};
          print "Login Output:$output\n" if $DEBUG;
          
        } else { # Connect with password authentication
          $session = Net::SSH::Expect->new(
                          host => $host,
                          user => $user,
                          debug => 1,
                          password => $pass,                          
                          raw_pty => 1,
                          timeout => $ssh_timeout,
                          );
          my @output = $session->login("User: ","Password:");
          #@output = $session->exec( "config paging disable" );
          if ( $output[0] =~ /assword/ ) {
            die "Login Failed for $user";
          }
          print "Login Output:$output[0]\n" if $DEBUG;
        }
    }; # END eval

    if ($EVAL_ERROR) {
        die "Could not open SSH session to $host:\n\t$EVAL_ERROR\n";
    }
    return $session;
} # END sub connect device


#---------------------------------------------------------------------------------------------
# Get the user table from a Checkpoint Identity Awareness PDP server
#
# Array CSV Format: mac,,,,userID,,,,,,,,
#
# Expecting output of the "pdp monitor summary all" command :
# Ip              Name/Domain
# ======================================================
# 192.168.1.1   [u] user1@domain.local
# 192.168.1.2   [u] user3@domain.local
# 192.168.2.10  [m]
# 192.168.1.11  [u] user2@domain.local
# [...]
#
#---------------------------------------------------------------------------------------------
sub getUserTable {
    my $session = shift;
    my $row;
    my @entry;
    my @usertable;

    print "Getting the User Table\n" if $DEBUG;

    $session->exec("stty raw -echo");
    $session->send("pdp monitor summary all"); # Get the Checkpoint PDP user table summary
    
    while ( defined ($row = $session->read_line()) ) {
      if ( $row =~ /^(?:[0-9]{1,3}\.){3}[0-9]{1,3}/ ) {
        @entry = split( /\s+/, $row );
        
        if (($entry[1] eq "[u]") and ($entry[2] ne "")) { # We skip null users and non user accounts
        
          $entry[2] =~ s/^(.*)@.*$/$1/ if not $optdomain; # Strip the domain suffix from the username
          
          print "ip: $entry[0], user: $entry[2]\n" if $DEBUG;
          push( @usertable, "$entry[0],$entry[2]" );
        }
      } # END if data
      @entry = undef;
    }
  	return \@usertable;
} # END sub getUserTable

sub parseConfig() {
    # Create any variables that do not exist to avoid errors
    my $config = AppConfig->new({
                                 CREATE => 1,
                                });

    $config->define( "checkpoint_host=s", "checkpoint_user=s", "checkpoint_pass=s" );

    $config->file( "$config_file" );

    $chost = $config->checkpoint_host();
    $cuser = $config->checkpoint_user();
    $cpass = $config->checkpoint_pass();
    
} # END sub parseConfig


sub usage() {
    print <<USAGE;
    Usage: checkpoint_ia.pl [options] 

      -o file          Output user table to a file
      -s server        Query a different Checkpoint IA Server
      -conf file       Use a different configuration file
      -d               Don't strip the domain suffix from the username
      -v               Verbose output

USAGE
    exit;
}
