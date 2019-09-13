#!/usr/bin/perl
################################################################################
# Send jobs to cisco devices
# Author: Jonathan Yantis <yantisj@gmail.com>
# Copyright (C) 2013 Jonathan Yantis
################################################################################
#
# Based on netdbscraper architecture to send jobs to cisco devices
#
################################################################################
use lib ".";

use NetDBHelper;
use Getopt::Long;
use AppConfig;
use English qw( -no_match_vars );
use Proc::Queue;
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

my $devtype = "cisco"; #Default, controllable from netdb.conf
my $maxProcs = 500; # Absolute maximum number of processes to spawn

my ( $ssh_session, $switchtype, $totalcount, $procDelay, $rootdir );

my $quietmode      = 0;
my $DEBUG          = 0;
my $LOGFILE;

# New Config Options

# Config Options (OLD)
my ( $optDevFile, $optCmdFile, $optVlanFile, $optDevCLI, $optLogFile );
my ( $optMacFile, $optIntFile, $optArpFile, $optProcs, $ext_desc );
my ( $optv6File, $use_telnet, $use_ssh, $optNoWhirl );
my ( $ipv6_maxage, $debug_level, $datadir, $prependNew );
my ( $optLogDir, $optConfDir, $optWriMem, $optStatus );
my ( $optInterfaces );

# Default extended descriptions
$ext_desc = 1;

# Flush Output for Whirley
$|=1;

# Input Options
if ( $ARGV[0] eq "" ) { &usage(); }

GetOptions(
    'df=s'  => \$optDevFile,
    'cf=s'  => \$optCmdFile,
    'vf=s'  => \$optVlanFile,
    'lf=s'  => \$optLogFile,
    'ld=s'  => \$optLogDir,
    'cd=s'  => \$optConfDir,
    'id=s'  => \$optInterfaces,
    'wm'  => \$optWriMem,
    'dc=s'  => \$optDevCLI,
    'pn' => \$prependNew,
    'p=s'  => \$optProcs,
    'sd=s' => \$optStatus,
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

# Log Files
if ( $optLogDir ) {
    if ( $optLogFile ) {
	$optLogFile = "$optLogDir/$optLogFile";
    }
    else {
	$optLogFile = "$optLogDir/sendjob.log";
    }
    
}

# Run with single process if not specified
$optProcs = 1  if !$optProcs;

# Populate device list and call launchProcs()
# Only proceed if a list is passed in and at least one output file is specified
if ( $optDevFile ) {

    # Devices from file
    if ( $optDevFile ) {
	@devices = populateArrayFromFile( $optDevFile );
    }

    if ( !$devices[0] ) {
	die "Error: No devices to process, check config file:";
    }

    # Start gathering data from devices
    launchProcs();
}

# Bulk change vlans on switches
elsif ( $optVlanFile ) {
    @devices = populateArrayFromFile( $optVlanFile );

    if ( !$devices[0] ) {
        die "Error: No devices to process, check config file:";
    }
    
    # Start gathering data from devices
    launchProcs();
}

else {
    print "Error: You must specify a device file\n";
}

# Get device data from the configuration file and parse options.
sub populateArrayFromFile {

    my $file = shift;

    open( my $DEVICES, '<', "$file") or die "P: Can't open $file";

    my @list = <$DEVICES>;
    close $DEVICES;
    
    return @list;
}

# Parent Process Launcher
# Start launching processes on @devices
sub launchProcs {

    my @pid;
    my %proc;

    
    logMessage( "Running Sendjob\n" );
    
    # Set max processes for safety
    $optProcs = $maxProcs if $optProcs>$maxProcs;
    
    # Configure Proc::Queue options
    Proc::Queue::size( $optProcs );
    Proc::Queue::delay( $procDelay );
    Proc::Queue::debug( 1 ) if $DEBUG>5;
    Proc::Queue::trace( 1 ) if $DEBUG>5;
    
    logMessage( "sendjob.pl($$): Parent spawning $optProcs processes with $procDelay" . "s delay\n");
    

    ###############################################
    # Spawn as many procs as requested/calculated #
    ###############################################
    foreach my $device ( @devices ) {

	# Process device config
	my $devref = processDevConfig( $device );

	# Skip backup processing of this device
	if( $$devref{nobackup} ) {
	    print "Skipping $$devref{fqdn} due to nobackup flap\n";
	}

	# Make sure device is valid
	elsif ( $$devref{fqdn} ) { 

	    # Fork
	    my $f = fork;
	    
	    # If defined, then it's the child process
	    if(defined ($f) and $f==0) {
		print "PARENT: Forked $$ on $$devref{host}\n" if $DEBUG>5;
		
		# Launch child sub for processing
		startChild( $device, $$devref{devtype} );
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
    # Wait on final Processes after queue is empty
    while ( wait != -1 ) {
	my $running = Proc::Queue::running_now();	
        logMessage( "Parent waiting on final processes to finish: $running\n") if $DEBUG>2;
        print STDERR "Processing: ".&NetDBHelper::whirley."\r" if !$DEBUG && !$optNoWhirl;
    }

    logMessage( "Parent Complete\n\n" );
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
    my $execstring;

    logMessage( "Child $$devref{fqdn} starting" ) if $DEBUG>1;

    # Alternate device type
    if ( $$devref{devtype} eq 'aruba' ) {
	$execstring = "$rootdir/netdbscraper/arubascraper.pl -debug $DEBUG -conf $config_file";
    }
    else {	
	$execstring = "./childsendjob.pl -debug $DEBUG -conf $config_file";
    }

    if ( $optDevFile ) {
	$execstring = "$execstring -d $devstring";
    }

    # Pass the fqdn through the old devstring method, pass the cmdfile separately to child
    if ( $optCmdFile ) {
	$execstring = "$execstring -cf $optCmdFile";
    }

    # Use the vlan string option instead (switch,vlan[/voice],ports)
    elsif ( $optVlanFile ) {
	$execstring = "$execstring -vs $devstring";
    }

    # Status Directory Option
    $execstring = "$execstring -sd $optStatus" if $optStatus;

    # Interface Directory Option
    $execstring = "$execstring -id $optInterfaces" if $optInterfaces;
  
    # Prepend New Option
    $execstring = "$execstring -pn" if $prependNew;
    
    # Individual Log file option
    $execstring = "$execstring -lf $optLogDir/$$devref{host}.log" if $optLogDir;
    
    # Configuration Directory for saved configs
    $execstring = "$execstring -cnf $optConfDir/$$devref{host}-confg" if $optConfDir;

    # Write Mem on devices
    $execstring = "$execstring -wm" if $optWriMem;

    # Execute device specific scraper command
    logMessage( "Child executing: $execstring\n" ) if $DEBUG>2;
    
    # Do full execution before returning results to keep logged data consistent
    my @output;
    #@output = `$execstring`;

    open( CHILDCMD, "$execstring 2>&1|") || die("Couldn't execute $execstring: $!");
   
    while ( my $line = <CHILDCMD> ) {

	if ( $line =~ /ERROR/ ) {
	    logMessage( $line );
	}
	elsif ( $line =~ /childsendjob.pl/ ) {
	    logMessage( $line );
	}
	else {
	    push( @output, $line );

	    if ( $DEBUG>3 ) {
		logMessage( "DEBUG: $line" );
	    }
	}
    }
    

    if ( @output ) {
	my @log;
	my $date = localtime;
	
	push( @log, " " );
	push( @log, " " );
	push( @log, " " );
	
	push ( @log, "==================================================================================================\n" );
	push ( @log, "$date: sendjob($$): Results from child $$devref{fqdn}\n" );
	push ( @log, "==================================================================================================\n" );
	push( @log, @output );
	
	# Write out child results here
	if ( $optLogFile && !$optLogDir ) {
	    writeFile( \@log, $optLogFile );
	}
	
	# No long file, print results if printing to screen
	elsif ( $DEBUG && !$optLogFile ) {
	    logMessage( @output );
	}
    }

#    if ( $DEBUG>3 ) {
#	print "---------- Results from $$devref{fqdn} ----------\n";
#	print @output;
#	print "\n";
#
#	logMessage( @output );
#    }

    logMessage( "Child Complete: $$devref{fqdn}\n" );

}


# Parse configuration options from $config_file
sub parseConfig {
    # Create any variables that do not exist to avoid errors
    my $config = AppConfig->new({
                                 CREATE => 1,
                                });

    $config->define( "max_macs=s", "mac_procs=s", "use_trunks=s@", "scraper_procs=s", "proc_delay=s", "scraper_count=s", "short_desc" );
    $config->define( "ipv6_maxage=s", "skip_port=s%", "use_telnet", "use_ssh", "arp_file=s", "mac_file=s", "int_file=s" );
    $config->define( "ipv6_file=s", "datadir=s", "devtype=s", "rootdir=s" );
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


    # Populate %useTrunkPorts
    foreach my $switch ( @useTrunks ) {
        $useTrunkPorts{"$switch"} = 1;
    }
}

# Print to the logfile
sub logMessage {

    my @message = @_;
    my @log;
    my $date = localtime;

    foreach my $line (@message) {
        chomp( $line );

	push( @log, "$date: sendjob($$): $line" );

        if ( $line ) {
	    if ( $DEBUG ) {
		print "$date: sendjob($$): $line\n";
	    }
	    elsif ( $line =~ /ERROR/ ) {
		print "$date: sendjob($$): $line\n";
	    }
	}
    }

    if ( $optLogFile ) {
        writeFile( \@log, $optLogFile );
    }
}

sub usage {
    print <<USAGE;
    Usage: sendjob.pl [options] [ -f input_file | -l dev1[,dev2] ]

     Run Option 1:
      -df file         Reads switches in from a file as the first entry line by line
      -cf file         Reads command list to send to devices in file

     Run Option 2:
      -vf file         Reads file of switch,vlan,port1,port2,port3 to flip

     Logging Options:
      -lf file         Log all results to a single file
      -ld directory    Log individual results to this directory
                       sendjob.log will contain parent log
      -cd directory    Config Directory to save configs     
      -sd directory    Save status info to directory
      -id directory    Save individual interface data to directory

     Other Options
      -wm              Save config to memory
      -p number        Launch this many processes (default 1)
    
      -pn              Prepend "new" to output files
      -nw              No whirley output, quiet output
      -v               Verbose output
      -debug #         Manually set debug level (1-6)
      -conf            Alternate netdb.conf file

USAGE
    exit;
}

