#!/usr/bin/perl
###################################################################################
# netdbctl.pl - Network Tracking Database Update Control Process
# Author: Jonathan Yantis <yantisj@gmail.com>
# Copyright (C) 2014 Jonathan Yantis
###################################################################################
# Controls NetDB's update processes, used to queue
# updates to the database.
#
# This was written to replace a shell script and add
# flexibility for testing and user requested updates.
# The script is messy with a lot of system calls, but
# it ties together all the logic for updating the db
# to one script.
#
# Features:
#  - Uses a configuration file, usually located at /etc/netdbconf
#  - Runs as a limited user, make sure that user can write to
#    the data directory and the log directory, plus read the
#    root directory
#  - Locks process using /var/lock/netdbctl.lock and flock
#  - Logs by default to control.log in /var/log/netdb,
#    this includes errors connecting to devices and
#    any sort of error in the update process
#  - Internal NetDB errors are logged to netdb.error and
#    that is handled by the NetDB.pm module.
#
###################################################################################
# Device file format:
# hostname[,netdbarp,vrf-VRFNAME,netdbnomac]
#
# Note:
#  - By default, NetDB will try to pull the mac table from devices in the file
#  - If ,netdbarp is appended, then NetDB will pull the arp table
#  - If ,vrf-VRFNAME is appended with netdbarp, NetDB will pull the arp table
#    from the vrf named VRFNAME
#  - If ,netdbnomac is appended, NetDB will not try to pull the mac or int status
#    data from the device
#
###################################################################################
# Config file example (append to /etc/netdb.conf):
## System level user, must have r/w file permissions to directories and files below
# netdb_user  = netdb
## Base directory of NetDB Install
#rootdir     = /scripts/dev/netdb
## Data directory to write data files to
#datadir     = /scripts/dev/netdb/data
## Control log to output script results to and errors
#control_log = /var/log/netdb/control.log
## Lock file to make sure only one copy of netdbctl is running at once
#lock_file   = /var/lock/netdbctl.lock
#
## Static Addresses (one ip per line)
#statics_file = /home/nst/statics.txt
#
###################################################################################
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
###################################################################################
use Getopt::Long;
use AppConfig;
use English qw( -no_match_vars );
use Fcntl qw (:flock); # For process locking
use Carp;
use strict;
use warnings;

# no nonsense
no warnings 'uninitialized';

$|++;          #turns off stdout buffering
               #good for testing but a big performance
               #penalty

# On kill signal, release lock file
$SIG{INT} =  \&release_lock;
$SIG{ABRT} =  \&release_lock;
$SIG{QUIT} =  \&release_lock;
$SIG{TERM} =  \&release_lock;

# Primary Configuration File, change with -c
my $config_file = "/etc/netdb.conf";

# Lock the process to keep multiple processes from running at once
my $lock_file;

# Other options
my $netdb_user = "netdb";
my $optlogfile;
my $optrootdir;
my $optdatadir;
my $extra_options;
my $config_option;
my @output;

# Debug mode
my $DEBUG          = 0;
my $netdbVer = 1;
my $netdbMinorVer = 13;

############################
# Begin Script Configuration
############################
my ( $optupdatedevs, $optupdatenac, $optimportarp, $optimportmacs, $optimportstatics, $optimportnac, $optforcedns );
my ( $optignorelock, $optconfigfile, $optarpfile, $optmacfile, $optintfile, $optnacfile, $optstaticsfile, $optdevicefile );
my ( $optupdatedb, $dbname, $dbhost, $dbuser, $dbpass, $optbackupdb, $optrestoredb, $use_telnet, $use_ssh, $conf_debug );
my ( $optdays, $optdbstats, $optdelmac, $optdelarp, $optdelswitch, $optdelstats, $optipfilter, $optv6file, $optimportv6 );
my ( $optbradfordclientfile, $optbradfordprofilefiles, $optupdatenac2, $optdelwifi, $optndfile, $optimportnd );
my ( $optDropSwitch, $optRenameSwitch );

# Input Options
if ( $ARGV[0] eq "" ) { &usage(); exit; }

my @ARGV2 = @ARGV;

my $config = AppConfig->new({
                             CREATE => 1,
                            });

$config->define( "netdb_user|u=s" , "rootdir|rd=s", "datadir|dd=s", "control_log|l=s", "lock_file|k=s", "ignore_lock|i", "debug=s" );
$config->define( "statics_file|sf=s", "device_file|df=s", "arp_file|af=s", "mac_file|mf=s", "int_file|if=s", "nac_file|nf=s" );
$config->define( "dbname=s", "dbhost=s", "dbuser=s", "dbpass=s", "no_switchstatus", "use_telnet|ut", "use_ssh|us" );
$config->define( "ipv6_file=s", "bradford_client_file|bcf=s", "bradford_profiled_file|bpf=s", "nd_file=s" );
$config->define( "ud", "um", "ua", "un", "un2", "a", "m", "n", "s", "f", "verbose|v", "vv", "config_file|conf|c=s", "bu=s", "re=s" );
$config->define( "v6", "st", "d=s", "dm", "da", "ds", "dt", "dw", "ip=s", "ehelp", "nd", "drop=s", "rS=s" );

# Get the config file if it exists from ARGV
$config->args(\@ARGV2);

# If an alternate config file was passed in, read from that
if ( $config->config_file() ) {
    $config_file = $config->config_file();
    $config_option = "-conf $config_file";
}

# Read in options from config file
$config->file( "$config_file" );

# Reread in ARGV to override any config file options passed in from CLI
$config->args();

if ( !$config->netdb_user() ) {
    print STDERR "Could not get username, make sure config file or CLI options are correct\n";
    exit(0);
}


$dbname         = $config->dbname();     # DB Name
$dbhost         = $config->dbhost();     # DB Host
$dbuser         = $config->dbuser();     # DB Read/Write User
$dbpass         = $config->dbpass();     # R/W Password
$netdb_user     = $config->netdb_user();
$optupdatedevs  = $config->ud();
$optupdatedevs  = $config->um() if $config->um();
$optupdatedevs  = $config->ua() if $config->ua();
$optupdatenac   = $config->un();
$optupdatenac2  = $config->un2();
$optbradfordclientfile = $config->bcf();
$optbradfordprofilefiles = $config->bpf();
$optimportarp   = $config->a();
$optimportv6    = $config->v6();
$optimportmacs  = $config->m();
$optimportstatics = $config->s();
$optimportnac  = $config->n();
$optimportnd    = $config->nd();
$optforcedns = $config->f();
$optlogfile = $config->control_log();
$optrootdir = $config->rootdir();
$optdatadir = $config->datadir();
$lock_file = $config->lock_file();
$optignorelock = $config->ignore_lock();
$optstaticsfile = $config->statics_file();
$optdevicefile  = $config->device_file();
$optarpfile     = $config->arp_file();
$optv6file      = $config->ipv6_file();
$optmacfile     = $config->mac_file();
$optintfile     = $config->int_file();
$optnacfile     = $config->nac_file();
$optndfile     = $config->nd_file();
$optbackupdb    = $config->bu();
$optrestoredb   = $config->re();
$use_telnet     = $config->use_telnet();
$use_ssh        = $config->use_ssh();
$optdays        = $config->d();
$optdbstats     = $config->st();
$optdelmac      = $config->dm();
$optdelarp      = $config->da();
$optdelswitch   = $config->ds();
$optdelwifi     = $config->dw();
$optdelstats    = $config->dt();
$optipfilter    = $config->ip();
$optDropSwitch = $config->drop();
$optRenameSwitch = $config->rS();


# CLI Debug
$DEBUG = 1 if $config->verbose();
$DEBUG = 3 if $config->vv();

# Read debug level from config file, override if it is higher
$conf_debug = $config->debug();
$DEBUG = $conf_debug if ( $conf_debug > $DEBUG );

# NetDB Extended Help output
if ( $config->ehelp() ) {
    usage();
    usage2();
    exit;
}

logMessage( "NetDB Debug Level: $DEBUG\n" ) if $DEBUG>1;

if ( $DEBUG > 0 ) {
    $extra_options = $extra_options . " -v";
}
if ( $DEBUG > 3 ) {
    $extra_options = $extra_options . " -vv";
}

# Set updating flag if changes are going to be made to the database
if ( $optupdatedevs || $optimportarp || $optimportmacs || $optimportstatics || $optforcedns
     || $optupdatenac || $optupdatenac2 || $optimportnac || $optimportv6 || $optimportnd ) {
    $optupdatedb = 1;
}
if ( $optdelmac || $optdelarp || $optdelswitch || $optdelwifi ) {
    $optupdatedb = 1;
}

##########################
# End Script Configuration
##########################

# Drop priviledges
if ( !$optrestoredb ) {
    drop_privileges( $netdb_user );
}

## Lock the process
#this next open will succeed if you have w permission...
#even if you you don't have the lock yet or lock file
#doesn't exist yet..
open( LOCKFILE, ">>$lock_file" ) or die "Cannot open $lock_file";
my  $got_lock =flock(LOCKFILE, LOCK_EX | LOCK_NB);

# Check to see if netdbctl process is locked
if ( !$got_lock && !$optignorelock ) {
    open( LOCKREAD, "$lock_file" ) or die "Cannot open $lock_file for reading";
    my $lock_info = <LOCKREAD>;

    print STDERR "netdbctl: ERROR $lock_file locked by $lock_info, check to see if netdbctl is already running\n";
    &logMessage( "netdbctl: ERROR $lock_file locked by $lock_info, check to see if netdbctl is already running" );
    exit(1);
}
# Put the pid and the process name in the lock file
else {
    my $date = localtime;
    print LOCKFILE "$0 ($$) $date";
}

if ( $optupdatedb ) {
    logMessage( "Parsing Devices from Big Brother (optional)\n" ) if $DEBUG>1;
    `/scripts/inventory/parsebb.pl 2> /dev/null`;

    # Update Data from Network Devices
    if ( $optupdatedevs ) {
        &logMessage( "Running netdbscraper on devices" );
        my $c_opt;
        $c_opt = "$c_opt -us" if $use_ssh;
        $c_opt = "$c_opt -ut" if $use_telnet;

        my $dev_cmd = "$optrootdir/netdbscraper/netdbscraper.pl -nw $c_opt -conf $config_file -f $optdevicefile -pn";
        $dev_cmd = $dev_cmd . " -debug $DEBUG";

        open( DEVCMD, "$dev_cmd 2>&1|") || die("Couldn't execute $dev_cmd: $!");
        while ( my $line = <DEVCMD> ) {
            &logMessage( $line );
        }
        `cp $optdatadir/new$optmacfile $optdatadir/$optmacfile`;
        `cp $optdatadir/new$optintfile $optdatadir/$optintfile`;
        `cp $optdatadir/new$optarpfile $optdatadir/$optarpfile`;
        `cp $optdatadir/new$optv6file $optdatadir/$optv6file` if $optv6file;
        `cp $optdatadir/new$optndfile $optdatadir/$optndfile` if $optndfile;
    }

    # Import MAC Table in to NetDB
    if ( $optimportmacs ) {
        my $count;
        # Insert the int status info unless no_switchstatus enabled
        if ( !$config->no_switchstatus() ) {
            $count = `cat $optdatadir/$optintfile | wc -l`;
            chomp( $count );

            &logMessage( "Importing $count intstatus entries in to switchstatus table" );
            my $status_import_cmd = "$optrootdir/updatenetdb.pl -i $optdatadir/$optintfile $config_option -debug $DEBUG";
            open( STATUSCMD, "$status_import_cmd 2>&1|") || die("Couldn't execute $status_import_cmd: $!");
            while ( my $line = <STATUSCMD> ) {
                &logMessage( $line );
            }
        }
        $count = `cat $optdatadir/$optmacfile | wc -l`;
        chomp( $count );

        &logMessage( "Importing $count MAC entries in to switchports table" );
        my $switch_import_cmd = "$optrootdir/updatenetdb.pl -m $optdatadir/$optmacfile $config_option -debug $DEBUG";
        open( SWITCHCMD, "$switch_import_cmd 2>&1|") || die("Couldn't execute $switch_import_cmd: $!");
        while ( my $line = <SWITCHCMD> ) {
            &logMessage( $line );
        }
    }

    # Insert Neighbor Discovery Data
    if ( $optimportnd ) {
        my $count = `cat $optdatadir/$optndfile | wc -l`;
        chomp( $count );

        &logMessage( "Importing $count neighbor discovery entries in to neighbor table" );
        my $nd_import_cmd = "$optrootdir/updatenetdb.pl -nd $optdatadir/$optndfile $config_option -debug $DEBUG";
        open( STATUSCMD, "$nd_import_cmd 2>&1|") || die("Couldn't execute $nd_import_cmd: $!");
        while ( my $line = <STATUSCMD> ) {
            &logMessage( $line );
        }
    }

    # Import IPv6 Table in to NetDB
    # Import before IPv4 so lastip shows up as V4 address
    if ( $optimportv6 ) {
        my $count = `cat $optdatadir/$optv6file | wc -l`;
        chomp( $count );

        &logMessage( "Importing $count IPv6 Entries in to ipmac table" );
        my $v6_import_cmd = "$optrootdir/updatenetdb.pl -v6 $optdatadir/$optv6file $config_option -debug $DEBUG";
        open( V6IMPORTCMD, "$v6_import_cmd 2>&1|") || die("Couldn't execute $v6_import_cmd: $!");
        while ( my $line = <V6IMPORTCMD> ) {
            &logMessage( $line );
        }
    }

    # Import ARP Table in to NetDB
    if ( $optimportarp ) {
        my $count = `cat $optdatadir/$optarpfile | wc -l`;
        chomp( $count );

        &logMessage( "Importing $count ARP Entries in to ipmac table" );
        my $arp_import_cmd = "$optrootdir/updatenetdb.pl -a $optdatadir/$optarpfile $config_option -debug $DEBUG";
        open( ARPIMPORTCMD, "$arp_import_cmd 2>&1|") || die("Couldn't execute $arp_import_cmd: $!");
        while ( my $line = <ARPIMPORTCMD> ) {
            &logMessage( $line );
        }
    }

    # Import list of static addresses in to NetDB
    if ( $optimportstatics ) {
        my $count = `cat $optstaticsfile | wc -l`;
        chomp( $count );

        &logMessage( "Importing $count Static Addresses from DHCP Server" );
        @output = `$optrootdir/updatenetdb.pl -s $optstaticsfile $config_option -debug $DEBUG 2>&1`;
        &logMessage( @output );
    }

    # Update Bradford Registrations
    if ( $optupdatenac ) {
        &logMessage( "Running bradford.pl" );

        # Get the registrations from bradford nac
        my $nac_cmd = "$optrootdir/bradford/bradford.pl -o $optdatadir/$optnacfile $config_option $extra_options";
        open( NACCMD, "$nac_cmd 2>&1|") || die("Couldn't execute $nac_cmd: $!");
        while ( my $line = <NACCMD> ) {
            &logMessage( $line );
        }
    }

    # Update Bradford Registrations using new client dump method
    if ( $optupdatenac2 ) {
        &logMessage( "Running bclientdump.pl" );
        # Handle multiple input files CSV separated
        my @bfiles = split( /\,/, $optbradfordclientfile );
	my @bpfiles = split( /\,/, $optbradfordprofilefiles );
        my $files;
	my $pfiles;

        foreach my $file ( @bfiles ) {
            $files = $files . "$optdatadir/$file,";
        }
	foreach my $file ( @bpfiles ) {
            $pfiles = $pfiles . "$optdatadir/$file,";
        }

        chop( $files );

        # Get the registrations from bradford nac
        my $nac_cmd = "$optrootdir/bradford/bclientdump.pl -i $files -o $optdatadir/$optnacfile $config_option $extra_options";

	if ( $optbradfordprofilefiles ) {
	    $nac_cmd = $nac_cmd . " -p $pfiles"
	}

	#die "naccmd: $nac_cmd";

        open( NACCMD2, "$nac_cmd 2>&1|") || die("Couldn't execute $nac_cmd: $!");
        while ( my $line = <NACCMD2> ) {
            &logMessage( $line );
        }
    }

    # Import NAC Registration Data in to NetDB
    if ( $optimportnac ) {
        my $count = `cat $optdatadir/$optnacfile | wc -l`;
        chomp( $count );

        &logMessage( "Importing $count NAC Registration Entries in to nacreg table" );
        my $nac_import_cmd = "$optrootdir/updatenetdb.pl -r $optdatadir/$optnacfile $config_option -debug $DEBUG";
        open( NACIMPORTCMD, "$nac_import_cmd 2>&1|") || die("Couldn't execute $nac_import_cmd: $!");
        while ( my $line = <NACIMPORTCMD> ) {
            &logMessage( $line );
        }
    }

    # Force a DNS update on everything in the arp table
    if ( $optforcedns ) {
        &logMessage( "Forcing DNS Update on all ARP table entries" );
        @output = `$optrootdir/updatenetdb.pl -f -a $optdatadir/$optarpfile $config_option -debug $DEBUG 2>&1`;
        &logMessage( @output );
    }

    # Delete Methods, call updatenetdb.pl
    if ( $optdelmac || $optdelarp || $optdelswitch || $optdelwifi ) {
        # Optional SQL filter for delete methods
        if ( $optipfilter ) {
            $config_option = "$config_option -ip $optipfilter";
        }

        if ( $optdays !~ /^\d+$/ ) {
            print "Input Error: must combine delete options with -d days\n";
        }
        elsif ( $optdelmac ) {
            exec ( "$optrootdir/updatenetdb.pl -dm -d $optdays $config_option" );
        }
        elsif ( $optdelarp ) {
            exec ( "$optrootdir/updatenetdb.pl -da -d $optdays $config_option" );
        }
        elsif ( $optdelswitch ) {
            exec ( "$optrootdir/updatenetdb.pl -ds -d $optdays $config_option" );
        }
        elsif ( $optdelwifi ) {
            exec ( "$optrootdir/updatenetdb.pl -dw -d $optdays $config_option" );
        }
    }
    # Completed database update
    logMessage( "NetDB update complete" );
}

# NOT updating database, check other options
else {


    # Delete switch from database
    if ( $optDropSwitch ) {
	exec ( "$optrootdir/updatenetdb.pl -drop $optDropSwitch $config_option" );
    }

    # Rename Switch
    if ( $optRenameSwitch ) {
	exec ( "$optrootdir/updatenetdb.pl -rS $optRenameSwitch $config_option" );
    }

    # Database Statistics
    if ( $optdbstats ) {
        if ( $optdays ) {
        exec ( "$optrootdir/netdb.pl -st -d $optdays $config_option" );
        }
        else {
            exec ( "$optrootdir/netdb.pl -st $config_option" );
        }
    }

    # Delete Statistics
    if ( $optdelstats ) {
        if ( $optdays !~ /^\d+$/ ) {
            print "Input Error: must combine delete options with -d days\n";
        }
        else {
            if ( $optipfilter ) {
                $config_option = "$config_option -ip $optipfilter";
            }
            exec ( "$optrootdir/updatenetdb.pl -dt -d $optdays $config_option" );
        }
    }
    # Backup database to a file
    if ( $optbackupdb ) {
        print "Backing up Database $dbname on $dbhost to $optbackupdb\n";
        `mysqldump -u $dbuser --password=$dbpass --host=$dbhost $dbname -r $optbackupdb`;
    }
    elsif ( $optrestoredb ) {
        print "Are you sure you want to restore the $dbname database on $dbhost with the file $optrestoredb? You will need the MySQL root user permissions for this action. \nRestore? [yes/no]: ";

        my $confirm = <STDIN>;
        if ( $confirm =~ /yes/ ) {
            print "\nRestoring Database...\n[MySQL Root User] ";

            open( DB, $optrestoredb ) or die "Can not open restore file: $optrestoredb\n";
            open( RESTOREDB, ">$optrestoredb-restore") or die "Can not create $optrestoredb-restore file\n";

            print RESTOREDB "SET AUTOCOMMIT=0;\n";
            print RESTOREDB "SET FOREIGN_KEY_CHECKS=0;\n";
            while ( my $line = <DB> ) {
                print RESTOREDB $line;
            }
            print RESTOREDB "SET FOREIGN_KEY_CHECKS=1;\n";
            print RESTOREDB "COMMIT;\n";
            print RESTOREDB "SET AUTOCOMMIT=1;\n";

            close DB;
            close RESTOREDB;

            `cat $optrestoredb-restore | mysql --user=root -p $dbname`;
            print "Database Restored.\n";
        }
        else {
            print "\nAborting Database Restore.\n"
        }
    }
}

close LOCKFILE    || die "Cannot close $lock_file";
unlink $lock_file || die "Internal program error";
exit(0);  #not needed but this is normal close

#--------------------------------------------------------------------
# Print to the logfile
#   Input:
#       message: message(s) to be logged.
# to use: &logMessage("");
#--------------------------------------------------------------------
sub logMessage {
    my @message = @_;
    my $date = localtime;
    #my @t = localtime;
    #my $date = sprintf('%4d-%02d-%02d %02d:%02d:%02d',
    #        $t[5]+1900,$t[4]+1,$t[3],$t[2],$t[1],$t[0]);

    open ( LOG, ">>$optlogfile" ) or die "Can't log to $optlogfile\n";
    foreach my $line (@message) {
        chomp( $line );
        if ( $line ) {
            print LOG "$date: netdbctl($$): $line\n";
            print "$date: netdbctl($$): $line\n" if $DEBUG;
        }
    }
    close LOG;
}

# Taken from Privileges::Drop;
sub drop_privileges {
    my ($user) = @_;

    # Check if we are root and stop if we are not.
#    if($UID != 0 and $EUID != 0 and $GID =~ /0/ and $EGID =~ /0/) {
#    print "ERROR: Can not change to $netdb_user user, run as root or $netdb_user user\n";
#    exit(1);
#    }

    # Find user in passwd file
    my ($uid, $gid, $home, $shell) = (getpwnam($user))[2,3,7,8];
    if(!defined $uid or !defined $gid) {
        croak("Could not find uid and gid user:$user");
    }

    # Find all the groups the user is a member of
    my @groups;
    while (my ($name, $comment, $ggid, $mstr) = getgrent()) {
        my %membership = map { $_ => 1 } split(/\s/, $mstr);
        if(exists $membership{$user}) {
            push(@groups, $ggid) if $ggid ne 0;
        }
    }

    # Cleanup $ENV{}
    $ENV{USER} = $user;
    $ENV{LOGNAME} = $user;
    $ENV{HOME} = $home;
    $ENV{SHELL} = $shell;

    drop_uidgid($uid, $gid, @groups);

    return ($uid, $gid, @groups);
}

sub drop_uidgid {
    my ($uid, $gid, @groups) = @_;

    # Sort the groups and make sure they are uniq
    my %groups = map { $_ => 1 } grep { $_ ne $gid } (@groups);
    my $newgid ="$gid ".join(" ", sort { $a <=> $b} keys %groups);

    # Drop privileges to $uid and $gid for both effective and save uid/gid
    $GID = $EGID = $newgid;
    $UID = $EUID = $uid;

    # Perl adds $gid two time to the list so it also gets set in posix groups
    $newgid ="$gid ".join(" ", sort { $a <=> $b} keys %groups, $gid);

    # Sort the output so we can compare it
    my $cgid = int($GID)." ".join(" ", sort { $a <=> $b } split(/\s/, $GID));
    my $cegid = int($EGID)." ".join(" ", sort { $a <=> $b } split(/\s/, $EGID));

    # Check that we did actually drop the privileges
    if ( $UID ne $uid or $EUID ne $uid ) {
        print STDERR "ERROR: Can not change to $netdb_user user, run as root or $netdb_user user\n";

        croak("Could not set current uid:$UID, gid:$cgid, euid=$EUID, egid=$cegid "
            ."to uid:$uid, gid:$newgid");
    }
}


# Get the revision number from svn, if it fails, return 0
sub getSubversion {
    my @output;
    my $line;
    my $tmp;
    my $subver = 0;
    my $revDate;

    eval {
        @output = `svn info $optrootdir 2> /dev/null`;

        foreach $line (@output) {
            if ( $line =~ /Revision\:/ ) {
                $subver = ( split /\:\s+/, $line )[1];
                chomp( $subver );
            }
            elsif ( $line =~ /Last\sChanged\sDate\:\s/ ) {
                $revDate = ( split /\:\s+/, $line )[1];
                ($revDate) = split( /\s\(/, $revDate );
            }
        }
    };

    return ( $subver, $revDate );
}

sub usage {
#    my @versionInfo = getSubversion();
#    print "NetDB v$netdbVer.$versionInfo[0] ($versionInfo[1])\n";

    print <<USAGE;
netdbctl: Controls the NetDB update processes, normally launched from cron and
          configured from netdb.conf

    Usage: netdbctl [options]

    Update Data Files on Disk:
      -ud         Update ARP, MAC and Interface files on disk from devices
      -un         Update NAC Registrations file from NAC Server
      -un2        Update NAC Registrations from Bradford client file

    Import Data Files from Disk in to Database:
      -a          Import ARP table in to NetDB
      -m          Import switch tables in to NetDB
      -n          Import NAC Registrations in to NetDB
      -s          Import static addresses in NetDB from DHCP Server
      -f          Force a DNS update on everything in the ARP table (use sparingly)

    Backup and Restore:
      -bu file    Backup the database to a file (must be writable by netdb user)
      -re file    Restore the database from a backup (requires MySQL root user permissions)

    Database Statistics and Deletion:
      -st         Database statistics (combine with -d days)
      -dt         Statistics on deletable data older than -d days
      -dm         Delete (confirm) all MAC addresses and associated ARP and Switchport entries older than -d days
      -da         Delete (confirm) all ARP entries older than -d days
      -ds         Delete (confirm) all switchport data older than -d days
      -dw         Delete (confirm) all wifi data older than -d days

    Note: Missing switches age out status info after 7 days automatically

    Switch Rename and Deletion:
      -rS old,new Rename switch from old name to new name
      -drop name  Drop all switch entries in DB with this name (status and mac entries)

    Development:
      -ehelp      Extended Help (Dev Options)
      -conf file  Read an alternate config file (default /etc/netdb.conf)
      -i          Ignore lock file, only use for development
      -v          Verbose output, including device scraper errors (debug 1)
      -debug 1-6  Set a specific debug level

            You must use a configuration file.  While every option can be overidden from
            the CLI, a config file is required.

USAGE

}

sub usage2 {
    print <<USAGE2;

  Extended Development Help

    Configuration File Overrides:
      -dd dir     Use a different data directory  (/opt/netdb/data)
      -rd dir     Use a different root netdb directory (/opt/netdb)
      -us         Enable SSH Protocol (falls back to telnet if enabled)
      -ut         Enable Telnet Protocol
      -u user     System user to run as (launch as root or this user)
      -k file     Lock File (default: /var/lock/netdbctl.lock)
      -l file     Log File  (default: /var/log/netdb/control.log)

    Note: Don't Include Path on These, files located in -dd data directory:
      -df file    Device List File (default: devicelist.csv)
      -af file    ARP Table File (default: arptable.txt)
      -mf file    MAC Table File (default: mactable.txt)
      -if file    Interface Status File (default: mactable.txt)
      -sf file    Static Address File   (default: statics.txt)
      -nf file    NAC User File


USAGE2

}

sub release_lock {
    my $message = shift;

    if ( !$message ) {
        $message = "Caught a kill signal...releasing lock\n";
    }
    else {
        $message = "Caught $message Signal, releasing lock";
    }

    print "$message\n";
    &logMessage( "$message" );
    close LOCKFILE     || die "Cannot close $lock_file";
    unlink $lock_file  || die "Internal program error";
    exit(2);
}
