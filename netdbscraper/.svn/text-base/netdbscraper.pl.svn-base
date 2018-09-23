#!/usr/bin/perl
################################################################################
# Gather data from routers and switches for NetDB
# Author: Jonathan Yantis <yantisj@gmail.com>
# Copyright (C) 2013 Jonathan Yantis
################################################################################
#
# Note: Individual switch models are now handled in their own scripts.  This
# parent script simply launches multiple processes with the right configuration
# options.  See the skeletonscraper.pl for more information.
#
# About: This is a multiprocess script to gather information from Cisco switches
# and routers.  It takes input from a file and reads the options for devices,
# each on their own line.  From there, it launches multiple processes and
# implements lock mechanisms to gather the data from the devices and save it to
# files.  There are about four versions of mac-address tables and three ARP
# table formats to parse.  All in all, it's very fast and compact compared to
# SNMP versions I have seen.
#
# Error Detection: The script should complain about all login/enable issues, and
# warn you if it does not receive data from a device.  See Debugging for
# troubleshooting missing data.
#
# Debugging: If you are having issues, raise the debug level to 5 in netdb.conf
# or run this script with -vv.  All commands that return the wrong output, or
# unmatched mac address entries will be printed to the screen.  Many of these
# things are erroneous, but look for your missing data for clues about what
# might be wrong.  You may also find a device is not in the mode you think it is
# with full debugging, and other clues to help you solve problems.
#
# Debugging Example on a Single Device:
# 
# cd /opt/netdb
# ./netdbscraper/netdbscraper.pl -ut[-us] -vv -om /tmp/mac.txt -oa /tmp/arp.txt \
# -oi /tmp/int.txt -sd device.domain.com,netdbarp,vrf-dmz,max_macs=100 
#
# Switch Notes: By default, the script will throw out trunk ports from the table.
# It will also throw out any ports that have over max_macs on them, configured
# from netdb.conf.  If you want to include trunk ports on a device, for a vmware
# host etc, set in netdb.conf:
#
# use_trunks = switch1 # NOT switch1.yourdomain.com
# use_trunks = switch2
#
# If the max_macs is exceeded, it will still throw out the data
# to avoid importing the uplinks in to the database
#
# See netdb.conf for more documentation on max_macs and use_trunks
#
# Program Structure:
# 
# - Reads the variables from the config file and CLI
# - Prepares the files for writing
# - launchProcs() forks individual processes on hosts, queues based on config file
#   timer values.
# - startChild() Controls all logic for gathering info from each device
#   - Calls connectDevice() to get a session on the device, SSH or Telnet
#   - Calls getArpTable() to get the ARP Table
#     - Tries to use one ARP table command, falls back to ASA style
#     - Calls cleanARP() to determine ARP line style and parse results
#   - Calls getIntStatus() to get the interface status
#     - Keeps track of trunk ports for later
#   - Calls getMacTable() to grab the mac table from devices
#     - Error detection to catch alternative sh mac command
#     - Splits the results by spaces, and goes through if/elsif block to find
#       the right style of mac-table.
#     - Consider hard setting the local $DEBUG value to 3+ to troubleshoot
#       mising data.  See code below.
#   - Uses writeFile() to lock a files for writing so procs don't clobber the file
#
# File Formats:
# See updatenetdb.pl for data file formats
#
################################################################################
use lib ".";

use NetDBHelper;
use Getopt::Long;
use AppConfig;
use English qw( -no_match_vars );
use Proc::Queue;
use Proc::ProcessTable;
use File::Flock;
use Net::DNS;
use IO::Socket::INET;
use strict;
use warnings;

# no nonsense
no warnings 'uninitialized';

use POSIX ":sys_wait_h"; # imports WNOHANG

my $config_file = "/etc/netdb.conf";

my $pid;

# Set these for your environment
my $maxMacs        = 7; #max number of macs on a port before it is thrown out, overriden from config file
my %useTrunkPorts;  # Set from config file, if switch exists, does not throw out trunk port data
my %trunkports;
my %skip_port;
my @devices;  # Array of device config lines

my $devtype = "ios"; #Default, controllable from netdb.conf
my $maxProcs = 500; # Absolute maximum number of processes to spawn

my ( $ssh_session, $switchtype, $totalcount, $procDelay, $rootdir );

my $quietmode      = 0;
my $DEBUG          = 0;

# Config Options
my ( $optInputFile, $optDevCLI );
my ( $optMacFile, $optIntFile, $optArpFile, $optProcs, $ext_desc );
my ( $optv6File, $use_telnet, $use_ssh, $optNoWhirl );
my ( $ipv6_maxage, $debug_level, $datadir, $prependNew );
my ( $optNDFile, $optKillTimeout );

# Default extended descriptions
$ext_desc = 1;

# Flush Output for Whirley
$|=1;

# Input Options
if ( $ARGV[0] eq "" ) { &usage(); }

GetOptions(
    'f=s'  => \$optInputFile,
    'sd=s'  => \$optDevCLI,
    'om=s' => \$optMacFile,
    'oi=s' => \$optIntFile,
    'oa=s' => \$optArpFile,
    'o6=s' => \$optv6File,
    'on=s' => \$optNDFile,
    'pn'   => \$prependNew,
    'p=s'  => \$optProcs,
    'ut'   => \$use_telnet,
    'us'   => \$use_ssh,
    'nw'   => \$optNoWhirl,
    'v'    => \$DEBUG,
    'debug=s' => \$debug_level,
    'conf=s' => \$config_file,
          )
or &usage();


############################
# Initialize program state #
############################

# Parse Configuration File
parseConfig();

if ( $debug_level ) {
    $DEBUG = $debug_level;
}

# Pass config file to NetDBHelper and set debug level
altHelperConfig( $config_file, $DEBUG );

if ( $prependNew ) {
    setPrependNew();
}

# Run with single process if not specified
$optProcs = 1  if !$optProcs;

# Populate device list and call launchProcs()
# Only proceed if a list is passed in and at least one output file is specified
if ($optInputFile || $optDevCLI ) {

    # Devices from file
    if ( $optInputFile ) {
	&populateDevsFromFile();
    }
    
    # Single device from cli
    else {
        $devices[0] = $optDevCLI;
    }

    if ( !$devices[0] ) {
	die "Error: No devices to process, check config file:";
    }

    # Start gathering data from devices
    &launchProcs();
}
else {
    print "Error: You must specify a device file\n";
}

# Get device data from the configuration file and parse options.
sub populateDevsFromFile {

    open( my $DEVICES, '<', "$optInputFile") or die "P: Can't open $optInputFile";

    @devices = <$DEVICES>;
}

# Parent Process Launcher
# Start launching processes on @devices
sub launchProcs {

    my @pid;
    my %proc;

    # Clear the results files
    if ( $optMacFile ) {
        open( my $RESULTS, '>', "$optMacFile") or die "Can't write to $optMacFile";
        print $RESULTS "\# NetDB Mac Table Data: (switch,mac,port,type(wifi),vlan/ssid,portlevel_ip,wifi/port speed,mac_nd)\n";
        close $RESULTS;
    }
    
    if ( $optIntFile ) {
        open( my $STATUS, ,'>', "$optIntFile") or die "Can't write to $optIntFile";
        print $STATUS "\# NetDB Interface Status Data: (switch,port,status,vlan,description,speed,duplex)\n";
        close $STATUS;
    }
    if ( $optArpFile ) {
        open( my $ARP, '>', "$optArpFile") or die "Can't write to $optArpFile";
        print $ARP "\# NetDB Arp Table Data: (IP,mac,age,vlan,vrf,router)\n";
        close $ARP;
    }
    if ( $optv6File ) {
        open( my $V6NT, '>', "$optv6File") or die "Can't write to $optv6File";
        print $V6NT "\# NetDB IPv6 Neighbor Table Data: (IP,mac,age,vlan,vrf,router)\n";
        close $V6NT;
    }
    if ( $optNDFile ) {
        open( my $NDT, '>', "$optNDFile") or die "Can't write to $optNDFile";
        print $NDT "\# NetDB Neighbor Discovery Table: (switch,port,n_host,n_ip,n_desc,n_model,n_port,protocol)\n";
        close $NDT;
    }
    
    # Set max processes for safety
    $optProcs = $maxProcs if $optProcs>$maxProcs;
    
    # Configure Proc::Queue options
    Proc::Queue::size( $optProcs );
    Proc::Queue::delay( $procDelay );
    Proc::Queue::debug( 1 ) if $DEBUG>5;
    Proc::Queue::trace( 1 ) if $DEBUG>5;
    
    print "netdbscraper.pl($$): Parent spawning $optProcs processes with $procDelay" . "s delay\n" if $DEBUG;
    

    ###############################################
    # Spawn as many procs as requested/calculated #
    ###############################################
    foreach my $device ( @devices ) {

	# Process device config
	my $devref = processDevConfig( $device );

	# Make sure device is valid
	if ( $$devref{fqdn} ) { 
	    
	    # Fork
	    my $f = fork;
	    
	    # If defined, then it's the child process
	    if(defined ($f) and $f==0) {
		print "PARENT: Forked $$ on $$devref{host}\n" if $DEBUG>5;
		
		# Launch child sub for processing
		startChild( $device );
		exit(0); # Exit after returning
	    }
	    
	    # Save PIDs for reference
	    else {
		push( @pid, $f );
		$proc{"$f"} = $$devref{host};
	    }
	    
	    # Parent process waits to queue next process
	    while ( waitpid(-1, WNOHANG) > 0 ) {
		print STDERR "Processing: ".&NetDBHelper::whirley."\r" if !$DEBUG && !$optNoWhirl;
	    }
	}
    }

    # Get remaining children
    my @proc_kids = getChildren();
    
    # Reset kill alarm on remaining children, waiting for timer
    local $SIG{ALRM} = sub { @proc_kids = getChildren(); kill 9, @proc_kids;
                                 die "|ERROR|: netdbscaper.pl ALARM Timeout, killing @proc_kids"
                             };
    alarm $optKillTimeout;

    # Wait on final Processes after queue is empty
    while ( wait != -1 ) {

	my $running = Proc::Queue::running_now();	
        print "netdbscraper.pl($$): Parent waiting on $running processes to finish\n" if $DEBUG>1;
        print STDERR "Processing: ".&NetDBHelper::whirley."\r" if !$DEBUG && !$optNoWhirl;
    }

    print "Finished                                    \n" if !$optNoWhirl;
    print "netdbscraper.pl($$): Parent Complete\n" if $DEBUG;
}


# Get remaining children from proccess table to possibly kill if hung
sub getChildren {
    my $t = Proc::ProcessTable->new();
    my @proc_kids = map { $_->pid() }
    grep { $_->ppid() == $$ }
    @{$t->table()};

    return @proc_kids;
}

###############################################################################
# Child fork processing on each device spawned above
# Connects to a device, launches subs to capture data and then writes the files
###############################################################################
sub startChild {
    my $devstring = shift;

    # Clean up device string
    chomp($devstring);
    $devstring =~ s/\s+//g;
    ( $devstring ) = split(/\#/, $devstring );

    my $devref = processDevConfig( $devstring );
  
    # Save the right devtype
    $devtype = $$devref{devtype} if $$devref{devtype};


    my $execstring = "$rootdir/netdbscraper/$devtype" . "scraper.pl -debug $DEBUG " .
                     "-d $devstring,devtype=$devtype -conf $config_file";
    
    # Prepend New Option
    $execstring = "$execstring -pn" if $prependNew;
    

    # Execute device specific scraper command
    print "netdbscraper.pl($$): Child executing: $execstring\n" if $DEBUG>1;
    
    open( DEVCMD, "$execstring 2>&1|") || die("Couldn't execute $execstring: $!");

    while ( my $line = <DEVCMD> ) {
	print $line;
    }

}


# Parse configuration options from $config_file
sub parseConfig {
    # Create any variables that do not exist to avoid errors
    my $config = AppConfig->new({
                                 CREATE => 1,
                                });

    $config->define( "max_macs=s", "mac_procs=s", "use_trunks=s@", "scraper_procs=s", "proc_delay=s", "scraper_count=s", "short_desc" );
    $config->define( "ipv6_maxage=s", "skip_port=s%", "use_telnet", "use_ssh", "arp_file=s", "mac_file=s", "int_file=s" );
    $config->define( "ipv6_file=s", "nd_file=s", "datadir=s", "devtype=s", "rootdir=s", "kill_timeout=s" );
    $config->file( "$config_file" );

    $maxMacs = $config->max_macs() if $config->max_macs();
    my $useTrunks_ref = $config->use_trunks();
    my @useTrunks = @$useTrunks_ref;

    $ext_desc = undef if $config->short_desc();
    my $port_ref = $config->skip_port();

    my ( $pre );
    
    foreach my $switch ( keys %$port_ref ) {
        my @ports = split( /\s+/, $$port_ref{$switch} );
	foreach my $port ( @ports ) {
	    $skip_port{"$switch,$port"} = 1;
	    print "skip: $switch,$port\n" if $DEBUG>5;
	}
    }

    $use_ssh = 1 if $config->use_ssh();
    $use_telnet = 1 if $config->use_telnet();

    # Backwards compatibility with old config option
    if ( !$optProcs ) {
	$optProcs = $config->mac_procs() if $config->mac_procs();
	$optProcs = $config->scraper_count() if $config->scraper_count();
    }

    if ( $config->proc_delay() ) {
	$procDelay = $config->proc_delay();
    }
    # Default proc_delay
    else {
        $procDelay = 0.5;
    }

    # Prepend files with the keyword new if option is set
    $pre = "new" if $prependNew;

    # Kill Alarm Timout
    if ( $config->kill_timeout ) {
	$optKillTimeout = $config->kill_timeout;
    }
    else {
	$optKillTimeout = 3600;
    }

    # Files to write to
    $datadir                = $config->datadir();
    $rootdir                = $config->rootdir();

    # Set the default device type
    $devtype = $config->devtype() if $config->devtype();

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

    if ( !$optIntFile && $config->int_file() ) {
	$optIntFile                = $config->int_file();
	$optIntFile                = "$datadir/$pre$optIntFile";
    }

    if ( !$optNDFile && $config->nd_file() ) {
        $optNDFile                = $config->nd_file();
        $optNDFile                = "$datadir/$pre$optNDFile";
    }


    # Populate %useTrunkPorts
    foreach my $switch ( @useTrunks ) {
        $useTrunkPorts{"$switch"} = 1;
    }
}


sub usage {
    print <<USAGE;
    Usage: netdbscraper.pl [options] [ -f input_file | -l dev1[,dev2] ]

      -f file          Reads switches in from a file as the first entry line by line
      -sd device,[opt] Runs on a single switch/router, same format as file
      -p number        Launch this many processes (default 1)

      -pn              Prepend "new" to output files
      -nw              No whirley output, quiet output
      -v               Verbose output
      -debug #         Manually set debug level (1-6)
      -conf            Alternate netdb.conf file

USAGE
    exit;
}

