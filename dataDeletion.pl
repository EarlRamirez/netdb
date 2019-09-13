#!/usr/bin/perl
###########################################################################
# dataDeletion.pl - Database cleaning/trimming Plugin
# Author: Andrew Loss <aterribleloss@gmail.com>
# Copyright (C) 2013 Andrew Loss
###########################################################################
# 
# Used to trim old data from the database, recommended that this runs as a
# scheduled job. If your network is extremely large, and/or have a large
# number of new network users consistently.
#
# How to use:
#  The -d for days option deletes all data older than the number of days
#  specified by the -d option. This will vary depending on the records
#  keeping for your organization.
#  An IP address can be used to narrow the deletion of MAC and IP address,
#  specified as: eg. 10.1.1.%
#
# Debugging:
#  Standard output is silent and errors are logged to the control.log file.
#  For more extensive output use the -debug option, levels 0-5 available
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
#
use strict;
use warnings;
use NetDB;
use Getopt::Long;

# Sanity
no warnings 'uninitialized';

# currently only roughly supporting levels 0-4
our $DEBUG;
our $scriptName = "dataDeletion.pl";
our $logfile ="/var/log/netdb/control.log";

# command line options
my ( $optType, $optdays, $optipfilter );
# other vars
my ( $hours, $del_mac, $del_sp, $del_wifi, $del_arp );

# Print usage if no input
if ( $ARGV[0] eq "" ) { &usage(); }

GetOptions(
    'd=i'     => \$optdays,
    'ip=s'    => \$optipfilter,
    'debug=i' => \$DEBUG,
    'v'       => \$DEBUG,
    ) or &usage();

if ( $optdays ) {
    $hours = $optdays*24;
}

# Connect to the database with read/write access
my $dbh = connectDBrw();

if( $hours ){
    &logMessage("Starting database cleanup of anything older then ".($optdays)." days.");
    $del_mac = delMAC( $dbh, $hours, $optipfilter );
    $del_sp = delSwitchPort( $dbh, $hours, $optipfilter );
    $del_wifi = delWifi( $dbh, $hours, $optipfilter );
    $del_arp = delARP( $dbh, $hours, $optipfilter );

    &logMessage("Removed: \n");
    &logMessage("\t$del_mac MAC addresses\n");
    &logMessage("\t$del_sp switchport entries\n");
    &logMessage("\t$del_wifi WiFi entries\n");
    &logMessage("\t$del_arp entries\n");
	&logMessage("\t\t totaling in ".($del_mac+$del_sp+$del_wifi+$del_arp)." rows deleted from the NetDB database.");
}

########################
## Deletion Functions ##
########################
#-----------------------------------------------------------
# Deletes all MAC address entries older then the hours
#  database.
# Input:
#   dbh - database handle
#   hours - hours in the past
#   ipfilter - optional SQL parameter to narrow deletion
# Output:
#   number of entries deleted from database
#-----------------------------------------------------------
sub delMAC {
    my $dbh = shift;
    my $hours = shift;
    my $ipfilter = shift;
    my $records = undef;

    if (!$dbh){ &logMessage("|ERROR|: No database connection!"); return undef; }
    if (!$hours){ &logMessage("|ERROR|: Number of days not specified!"); return undef; }

    my $netdb_ref = deleteMacs( $dbh, $hours, undef, $ipfilter );
    if ( $$netdb_ref[1] ) {
        $records = @$netdb_ref;
        &logMessage("|Notice|: Deleting $records MAC addresses older then ".($hours/24)." days from database...");

        deleteMacs( $dbh, $hours, 1, $ipfilter );
        &logMessage("|Notice|: $records MAC addresses removed from database");
    }
    else{
        $records = 0;
        &logMessage("|Notice|: No MAC addresses older then ".($hours/24)." days found in database");
    }
    return $records;
}
#-----------------------------------------------------------
# Deletes all switchport entries older then the hours
#  database.
# Input:
#   dbh - database handle
#   hours - hours in the past
# Output:
#   number of entries deleted from database
#-----------------------------------------------------------
sub delSwitchPort {
    my $dbh = shift;
    my $hours = shift;
    my $records = undef;

    if (!$dbh){ &logMessage("|ERROR|: No database connection!"); return undef; }
    if (!$hours){ &logMessage("|ERROR|: Number of days not specified!"); return undef; }

    my $netdb_ref = deleteSwitch( $dbh, $hours, undef );
    if ( $$netdb_ref[1] ) {
        $records = @$netdb_ref;
        &logMessage("|Notice|: Deleting $records switchport entries older then ".($hours/24)." days from database...");

        deleteSwitch( $dbh, $hours, 1 );
        &logMessage("|Notice|: $records switchport entries removed from database");
    }
    else{
        $records = 0;
        &logMessage("|Notice|: No switchport entries older then ".($hours/24)." days found in database");
    }
    return $records;
}
#-----------------------------------------------------------
# Deletes all WiFi entries older then the hours database.
# Input:
#   dbh - database handle
#   hours - hours in the past
# Output:
#   number of entries deleted from database
#-----------------------------------------------------------
sub delWifi {
    my $dbh = shift;
    my $hours = shift;
    my $records = undef;

    if (!$dbh){ &logMessage("|ERROR|: No database connection!"); return undef; }
    if (!$hours){ &logMessage("|ERROR|: Number of days not specified!"); return undef; }
    my $netdb_ref = deleteWifi( $dbh, $hours, undef );
    if ( $$netdb_ref[1] ) {
        $records = @$netdb_ref;
        &logMessage("|Notice|: Deleting $records WiFi entries older then ".($hours/24)." days from database...");

        deleteWifi( $dbh, $hours, 1 );
        &logMessage("|Notice|: $records WiFi entries removed from database");
    }
    else{
        $records = 0;
        &logMessage("|Notice|: No WiFi entries older then ".($hours/24)." days found in database");
    }
    return $records;
}
#-----------------------------------------------------------
# Deletes all ARP entries older then the hours database.
# Input:
#   dbh - database handle
#   hours - hours in the past
#   ipfilter - optional SQL parameter to narrow deletion
# Output:
#   number of entries deleted from database
#-----------------------------------------------------------
sub delARP {
    my $dbh = shift;
    my $hours = shift;
    my $ipfilter = shift;
    my $records = undef;

    if (!$dbh){ &logMessage("|ERROR|: No database connection!"); return undef; }
    if (!$hours){ &logMessage("|ERROR|: Number of days not specified!"); return undef; }
    my $netdb_ref = deleteArp( $dbh, $hours, undef, $ipfilter );
    if ( $$netdb_ref[1] ) {
        $records = @$netdb_ref;
        &logMessage("|Notice|: Deleting $records ARP entries older then ".($hours/24)." days from database...");

        deleteArp( $dbh, $hours, 1, $ipfilter );
        &logMessage("|Notice|: $records ARP entries removed from database");
    }
    else{
        $records = 0;
        &logMessage("|Notice|: No ARP entries older then ".($hours/24)." days found in database");
    }
    return $records;
}

######################
## Helper Functions ##
######################

#-----------------------------------------------------------
# Print to the logfile
#-----------------------------------------------------------
sub logMessage {
    my @message = @_;
    my $date = localtime;

    open ( LOG, ">>$logfile" ) or die "Can't log to $logfile\n";

    foreach my $line (@message) {
        chomp( $line );
        if ( $line ) {
            print LOG "$date: $scriptName($$): $line\n";
            print "$date: $scriptName($$): $line\n" if $DEBUG;
        }
    }
    close LOG;
}

#-----------------------------------------------------------
# Generates timestamp in same format as NetDB
#-----------------------------------------------------------
sub netdbTimestamp {
    my $timestamp = `date +'%a %b %d %T %Y'`;
    chomp($timestamp);
    return $timestamp;
}

sub usage {

    print <<USAGE;

  About: Deletes database entries in the NetDB database
  Usage: dataDeletion.pl [options]

    Deletion Options:
      -d days      Days in the past
      -ip          Optional SQL parameter to narrow deletion for MAC and ARP entries, eg. 10.1.1.%

    Misc Options:
      -debug       Set debuging level (0-5)
      -v           Verbose output

USAGE
    exit;
}

