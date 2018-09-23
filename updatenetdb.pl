#!/usr/bin/perl -w
##########################################################################
# updatenetdb.pl - Imports data in the the NetDB Database
# Author: Jonathan Yantis <yantisj@gmail.com>
# Copyright (C) 2014 Jonathan Yantis
##########################################################################
#
# Update script for the NetDB Database.  Interfaces with NetDB.pm
# and uses the update methods to update the database.  This script
# primarily parses the data from files and creates the data structure
# to pass to the NetDB module.  Expected file formats are below.
#
# It is possible to use NetDB without the maccount and arpcount scrapers.
# If you put your arp and mac tables in the formats below, you can use
# this script to import them in to the database, and not use the scapers.
#
# Update Methods:
#  - Insert ARP Table data
#  - Insert MAC address data
#  - Insert switch status data (csv format)
#  - Insert static address data (one IP per line in file)
#
##########################################################################
# Simple Data Structure Example:
#
# # IP and mac are almost always required
# my @netdb = ( { ip => '128.23.1.1', mac => '1111.2222.3333' },
#            { ip => '128.23.1.1', mac => '1111.2222.3333' },
#          );
#
# my $netdb_ref = getQuery( \@netdb ); # pass as a reference
# @netdb = @$netdb_ref;                # Dereference                        
#
##########################################################################
# File Formats:
#
# Note: All MAC addresses can be in any format, all are converted to 
#       xxxx.xxxx.xxx
#
# Mac Table File Format (per line, type optional usually wifi if set):
# switch,mac,port,type
# 
# Status file:
# switch,port,status,vlan,description
#
# Registration file:
# mac,regtime,firstName,lastName,userID,email,phone,device_type,Org_Entity,critical(1),role,title,state
#
# Note: 
#   - Port should match the port format above (i.e. Don't mix short and 
#       long port names)
#   - Status should be connect, notconnect, disabled or err-disabled.
#   - If you can not import this information, switch reports will be
#     will not be as extensive.  Set no_switchstatus variable to 1
#     in netdb.conf.     
#     
#   - Vlan can be bare vlan number, like 200 or the word 'trunk'
#
# ARP Table File Format (per line):
# ip,mac,age,interface
#
# Note: age not required, could be 1.1.1.1,0011.2222.3333,,Vlan5
#       Also, NetDB only considers the interface if it is VlanX.
#       If the interface is anything else, NetDB will not use the 
#       interface data (only the IP and mac).
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

# Used for development work against the non-production NetDB library
use lib ".";
use NetDB;
use Getopt::Long;
use Net::IP;
use strict;
use warnings;

# no nonsense
no warnings 'uninitialized';

my $netdbVer = 1;
my $netdbMinorVer = 13;
my $DEBUG;

my ( $optsource, $optstatic, $optv6, $optmac, $optstatus, $optforcehost, $opthours, $optdays, $optdelmac, $config_file );
my ( $optdelarp, $optdelswitch, $optdelwifi, $optregistrations, $optdelstats, $optipfilter, $optND );
my ( $optDropSwitch, $optRenameSwitch );

# Input Options
if ( $ARGV[0] eq "" ) { &usage(); }

GetOptions(
    'a=s'  => \$optsource,
    'v6=s' => \$optv6,
    's=s'  => \$optstatic,
    'm=s'  => \$optmac,
    'nd=s' => \$optND,
    'i=s'  => \$optstatus,
    'r=s'  => \$optregistrations,
    'f'    => \$optforcehost,
    'd=s'  => \$optdays,
    'dm'   => \$optdelmac,
    'da'   => \$optdelarp,
    'ds'   => \$optdelswitch,
    'dt'   => \$optdelstats,
    'dw'   => \$optdelwifi,
    'drop=s'  => \$optDropSwitch,
    'rS=s'    => \$optRenameSwitch,
    'ip=s'    => \$optipfilter,
    'conf=s'  => \$config_file,
    'v'       => \$DEBUG,    
    'debug=s' => \$DEBUG,
      )

or &usage(); 

# Connect to the database with read/write access
my $dbh = connectDBrw( $config_file );

# Library Version Check
my $libraryVersion = getVersion();
if ( $libraryVersion ne "$netdbVer.$netdbMinorVer" ) {
    print STDERR "WARNING: NetDB Library version v$libraryVersion mismatch with updatenetdb.pl v$netdbVer.$netdbMinorVer\n";
}

# Pass debug value to library if manually set higher than 1 here
if ( $DEBUG > 1 ) {
    setNetDBDebug( $DEBUG );
}

my @netdbBulk;

if ( $optdays ) {
    $opthours = $optdays*24;
}
# ARP Table Updates
if ( $optsource ) {
    print "DEBUG: Loading Arp Table in to hash\n" if $DEBUG>3;
    &loadArpTable();
    
    print "DEBUG: Second Entry: $netdbBulk[1]{ip} $netdbBulk[1]{mac} $netdbBulk[1]{vlan}\n" if $DEBUG>3;

    if ( $netdbBulk[0]{ip} ) {
        print "DEBUG: Inserting arp table in to database\n" if $DEBUG>3;
        bulkInsertIPMAC( $dbh, \@netdbBulk, $optforcehost );
    }
    else {
        print "ARP Table Empty, nothing to import";
    }
}
# IPv6 Neighbor Table Updates
if ( $optv6 ) {
    print "DEBUG: Loading IPv6 Table in to hash\n" if $DEBUG>3;
    &loadv6Table();

    print "DEBUG: Second Entry: $netdbBulk[1]{ip} $netdbBulk[1]{mac} $netdbBulk[1]{vlan}\n" if $DEBUG>3;
    if ( $netdbBulk[0]{ip} ) {
        print "DEBUG: Inserting IPv6 table in to database\n" if $DEBUG>3;
        bulkInsertIPMAC( $dbh, \@netdbBulk, $optforcehost );
    }
    else {
        print "IPv6 Neighbor Table Empty, nothing to import";
    }
}
# Update static addresses
if ( $optstatic ) {
    print "DEBUG: Loading Static Table in to hash\n" if $DEBUG>3;
    &loadStaticTable();

    print "DEBUG: Second Entry: $netdbBulk[1]{ip} $netdbBulk[0]{static}\n" if $DEBUG>3;

    print "DEBUG: Inserting statics in to database\n" if $DEBUG>3;
    bulkUpdateStatic( $dbh, \@netdbBulk );
}
# Insert mac table in to database
if ( $optmac ) {
    print "DEBUG: Loading Mac Table in to hash\n" if $DEBUG>3;
    &loadMacTable();

    print "DEBUG: Second Entry: $netdbBulk[1]{mac} $netdbBulk[1]{switch}\n" if $DEBUG>3;

    if ( $netdbBulk[0]{mac} ) {
        print "DEBUG: Inserting macs in to database\n" if $DEBUG>3;
        bulkUpdateMac( $dbh, \@netdbBulk );
    }
    else {
        print "MAC Table Empty, nothing to import";
    }
}
# Insert sh int status in to switchstatus table
if ( $optstatus ) {
    print "DEBUG: Loading Int Status in to hash\n" if $DEBUG>3;
    &loadStatusTable();

    print "DEBUG: Second Entry: $netdbBulk[1]{switch} $netdbBulk[1]{portvlan}\n" if $DEBUG>3;

    if ( $netdbBulk[0]{switch} ) {
        print "DEBUG: Inserting status in to database\n" if $DEBUG>3;
        bulkUpdateSwitchStatus( $dbh, \@netdbBulk );
    }
    else {
        print "Switch Status Table Empty, nothing to import";
    }
}
# Insert registrations in to nacreg table
if ( $optregistrations ) {

    print "DEBUG: Loading Registrations in to hash\n" if $DEBUG>3;
    &loadRegTable();
    
    print "DEBUG: Fourth Entry: $netdbBulk[3]{mac} $netdbBulk[3]{userID}\n" if $DEBUG>3;
    print "DEBUG: Inserting registrations in to database\n" if $DEBUG>3;
    
    bulkInsertNACReg( $dbh, \@netdbBulk );
    
}
# Insert Neighbor Discovery in to database
if ( $optND ) {
    print "DEBUG: Neighbor Discovery in to hash\n" if $DEBUG>3;

    my $netdb_ref = loadNDTable( $optND );
    @netdbBulk = @$netdb_ref;

    print "DEBUG: Fourth Entry: $netdbBulk[3]{switch} $netdbBulk[3]{port} $netdbBulk[3]{n_port} $netdbBulk[3]{n_desc}\n" if $DEBUG>3;
    print "DEBUG: Inserting neighbor data in to database\n" if $DEBUG>3;
    
    bulkInsertND( $dbh, \@netdbBulk );

}
# Delete MAC data older than so many days
if ( $optdelmac && $opthours ) {
    print "Querying database for data to delete older than $optdays days...\n";
    
    my $netdb_ref = deleteMacs( $dbh, $opthours, undef, $optipfilter );

    if ( $$netdb_ref[1] ) {

        printNetdbMACinCSV( $netdb_ref );

        my $records = @$netdb_ref;

        print "\nAre you sure you want to delete these $records records from the database?  Did you do a backup using netdbctl first?";
        print "\nConfirm Deletion of Data. [yes/no]: ";
    
        my $confirmation = <STDIN>;

        if ( $confirmation =~ /yes/ ) {
            print "Deleting Data from Database...";
            deleteMacs( $dbh, $opthours, 1, $optipfilter );
            print "done.\n\n";
        }
        else {
            print "Aborted.\n\n";
        }
    }
    else {
        print "No data found to delete.\n";
    }
}
# Delete ARP data older than so many days
if ( $optdelarp && $opthours ) {
    print "Querying database for data to delete older than $optdays days...\n";

    my $netdb_ref = deleteArp( $dbh, $opthours, undef, $optipfilter );

    if ( $$netdb_ref[1] ) {

        printNetdbIPMACinCSV( $netdb_ref );

        my $records = @$netdb_ref;

        print "\nAre you sure you want to delete these $records ARP records from the database?  Did you do a backup using netdbctl first?";
        print "\nConfirm Deletion of Data. [yes/no]: ";

        my $confirmation = <STDIN>;

        if ( $confirmation =~ /yes/ ) {
            print "Deleting Data from Database...";
            deleteArp( $dbh, $opthours, 1, $optipfilter );
            print "done.\n\n";
        }
        else {
            print "Aborted.\n\n";
        }
    }
    else {
        print "No data found to delete.\n";
    }
}
# Delete Switchport data older than so many days
if ( $optdelswitch && $opthours ) {
    print "Querying database for data to delete older than $optdays days...\n";

    my $netdb_ref = deleteSwitch( $dbh, $opthours, undef );

    if ( $$netdb_ref[1] ) {

        printNetdbSwitchportsinCSV( $netdb_ref );

        my $records = @$netdb_ref;

        print "\nAre you sure you want to delete these $records switchport records from the database?  Did you do a backup using netdbctl first?";
        print "\nConfirm Deletion of Data. [yes/no]: ";

        my $confirmation = <STDIN>;

        if ( $confirmation =~ /yes/ ) {
            print "Deleting Data from Database...";
            deleteSwitch( $dbh, $opthours, 1 );
            print "done.\n\n";
        }
        else {
            print "Aborted.\n\n";
        }
    }
    else {
        print "No data found to delete.\n";
    }
}
# Delete Wifi data older than so many days
if ( $optdelwifi && $opthours ) {
    print "Querying database for Wifi data to delete older than $optdays days...\n";

    my $netdb_ref = deleteWifi( $dbh, $opthours, undef );

    if ( $$netdb_ref[1] ) {

        printNetdbSwitchportsinCSV( $netdb_ref );

        my $records = @$netdb_ref;

        print "\nAre you sure you want to delete these $records wifi records from the database?  Did you do a backup using netdbctl first?";
        print "\nConfirm Deletion of Data. [yes/no]: ";

        my $confirmation = <STDIN>;

        if ( $confirmation =~ /yes/ ) {
            print "Deleting Data from Database...";
            deleteWifi( $dbh, $opthours, 1 );
            print "done.\n\n";
        }
        else {
            print "Aborted.\n\n";
        }
    }
    else {
        print "No data found to delete.\n";
    }
}
# Get delete statistics for a number of days
if ( $optdelstats && $opthours ) {
    my $h_ref = getDeleteStats( $dbh, $opthours, $optipfilter );
    my %stats = %$h_ref;

    my $dbRowCount = $stats{mac} + $stats{ipmac} + $stats{switchports};

    $stats{switchports} = "Unknown when using filter" if !$stats{switchports};
    $stats{nacreg} = "Unknown when using filter" if !$stats{nacreg};


    print "\n  NetDB Delete Statistics";
    print " over $optdays days" if $opthours != 100000;
    print "\n ---------------------------------\n";
    print "   MAC Entries:      $stats{mac}\n";
    print "   ARP Entries:      $stats{ipmac}\n";
    print "   Switch Entries:   $stats{switchports}\n";
    print "   Registrations:    $stats{nacreg}\n";
    print "   Total Deletable Rows: $dbRowCount\n";
    print "\n Note: Deleting MAC entries will delete all previously associated ARP, switch and registration\n "
        . "entries. If you combine these statistics with an SQL IP filter and delete the matched mac entries,\n "
    . "the related switch and NAC registration data will also be deleted.  The MAC address is the primary\n "
    . "key for those tables.\n\n";
}

# Drop all switch entries from the database for this switch name
if ( $optDropSwitch ) {

    print "\nAre you sure you want to drop all switch status and mac table entries for $optDropSwitch?  Did you do a backup using netdbctl first?";
    print "\nConfirm Deletion of Data. [yes/no]: ";
    
    my $confirmation = <STDIN>;
    
    if ( $confirmation =~ /yes/ ) {
	print "Deleting Data from Database...";
	dropSwitch( $dbh, $optDropSwitch );
	print "done.\n";
    }
    else {
	print "Aborted.\n\n";
    }
}

# Rename switch, option is oldname,newname
if ( $optRenameSwitch ) {

    my ( $oldSwitch, $newSwitch ) = split( /\,/, $optRenameSwitch );

    chomp( $newSwitch );
    print "\rRenaming $oldSwitch to $newSwitch...";

    if ( $oldSwitch && $newSwitch ) {
	print "\rRenaming $oldSwitch to $newSwitch...";
	renameSwitch( $dbh, $oldSwitch, $newSwitch );
	print "done.\n";
    }
    else { 
	print "Error: Must pass in oldswitch and newswitch name to -rS\n";
    }
}

#######################
##                   ##
## Load data methods ##
##                   ##
#######################
#---------------------------------------------------------------------------------------------
# Load a list of ips and set them static in the database
#---------------------------------------------------------------------------------------------
sub loadStaticTable {

    open( my $STATIC, '<', "$optstatic") or die "Can't open $optstatic";

    my $myline;
    my @mydata;
    my $arrayCount = 0;
    @netdbBulk = undef;

    while ( $myline = <$STATIC> ) {
        next if $myline =~ /^#/; # discard comments
        chomp($myline);
        @mydata = split(/\s+/, $myline);

        # make sure it's an IP in field 1
        if( $mydata[0] =~ /(\d+)(\.\d+){3}/ ) {
            $netdbBulk[$arrayCount] = { ip => $mydata[0], static => "1" };
            $arrayCount++;
        }
        else {
            chomp( $myline );
            print "updatenetdb: Load Static Table rejected $myline\n" if $DEBUG>3;
        }
    }
}

#---------------------------------------------------------------------------------------------
# NAC Registration data
#---------------------------------------------------------------------------------------------
sub loadRegTable {

    open( my $SOURCE, '<', "$optregistrations") or die "Can't open $optregistrations: $!";

    my $myline;
    my @mydata;
    my $arrayCount = 0;
    @netdbBulk = undef;
    
    while ( $myline = <$SOURCE>) {
        next if $myline =~ /^#/; # discard comments
        chomp($myline);
        @mydata = split(/\,/, $myline);
    
        # make sure it's a mac in field 0
        $mydata[0] = getCiscoMac( $mydata[0] );

        if ( $mydata[0] && $mydata[4] ) {
            
	    $netdbBulk[$arrayCount] = { 
		mac => $mydata[0], time => $mydata[1], firstName => $mydata[2], lastName => $mydata[3], userID => $mydata[4], 
                email => $mydata[5], phone => $mydata[6], type  => $mydata[7], entity => $mydata[8], critical => $mydata[9],
                role => $mydata[10], title => $mydata[11], status => $mydata[12], expiration => $mydata[13],
		pod => $mydata[14], dbid => $mydata[15]		      
				      };
            
	    $arrayCount++;
        }
        else {
            chomp( $myline );
            print "updatenetdb: Load Nac Reg Table rejected $myline\n" if $DEBUG>3;
        }
    }
    close $SOURCE;
}

#---------------------------------------------------------------------------------------------
# Load the arp table in to the netdb data structure
#
# Format: ip,mac,age,interface 
# Note: age not required, could be 1.1.1.1,0011.2222.3333,,Vlan5
#---------------------------------------------------------------------------------------------
sub loadArpTable {
    open( my $SOURCE, '<', "$optsource") or die "Can't open $optsource";
    my $myline;
    my @mydata;
    my $arrayCount = 0;
    @netdbBulk = undef;

    while ( $myline = <$SOURCE>) {
        next if $myline =~ /^#/; # discard comments
        chomp($myline);
        @mydata = split(/\,/, $myline);

        # make sure it's an IP in field 1
        if( $mydata[0] =~ /(\d+)(\.\d+){3}/ ) {
            # Reformat mac address in to cisco format and check to see if good results
            # come back
            $mydata[1] = getCiscoMac( $mydata[1] );

            if ( $mydata[1] ) {
                $netdbBulk[$arrayCount] = { ip => $mydata[0], mac => $mydata[1], vlan => $mydata[3], 
                        vrf => $mydata[4], router => $mydata[5] };
                #print "$mydata[0], $mydata[1], $mydata[3], $mydata[4], $mydata[5]\n";
                $arrayCount++;
            }
            else {
                chomp( $myline );
                print "updatenetdb: Load ARP Table rejected $myline\n" if $DEBUG>3;
            }
        }
    }

    close $SOURCE;
}

#---------------------------------------------------------------------------------------------
# Load the IPv6 table in to the netdb data structure
#
# Format: ip,mac,age,interface 
# Note: age not required, could be 2620::1,0011.2222.3333,,Vlan5
#---------------------------------------------------------------------------------------------
sub loadv6Table {
    open( my $SOURCE, '<', "$optv6") or die "Can't open $optsource";
    my $myline;
    my @mydata;
    my $arrayCount = 0;
    @netdbBulk = undef;

    while ( $myline = <$SOURCE>) {
        next if $myline =~ /^#/; # discard comments
        chomp($myline);
        @mydata = split(/\,/, $myline);

        # make sure it's an IPv6 in field 1
        if( $mydata[0] =~ /\w+:\w+:\w+:/ ) {
            # Reformat mac address in to cisco format and check to see if good results
            # come back
            $mydata[1] = getCiscoMac( $mydata[1] );

            # Format IPv6 Address in to strait 32character value
            my $ip = new Net::IP ($mydata[0]) || print "Failed to format IPv6 Address: $mydata[0]\n";

            # Convert to long format
            $mydata[0] = $ip->ip();

            if ( $mydata[1] ) {
                $netdbBulk[$arrayCount] = { ip => $mydata[0], mac => $mydata[1], vlan => $mydata[3], 
                        vrf => $mydata[4], router => $mydata[5] };
                #print "$mydata[0], $mydata[1], $mydata[3]\n";
                $arrayCount++;
            }
            else {
                chomp( $myline );
                print "updatenetdb: Load ARPv6 Table rejected $myline\n" if $DEBUG>3;
            }
        }
    }

    close $SOURCE;
}

#---------------------------------------------------------------------------------------------
# Load the mac table in to the netdb data structure
#
# Example: mdcmdf,000d.567e.6071,GigabitEthernet5/40
#---------------------------------------------------------------------------------------------
sub loadMacTable {
    open( my $SOURCE, '<', "$optmac") or die "Can't open $optsource";
    my $myline;
    my @mydata;
    my $arrayCount = 0;
    @netdbBulk = undef;

    while ( $myline = <$SOURCE>) {
        next if $myline =~ /^#/; # discard comments
        chomp($myline);
	$myline =~ s/\n|\r//g;

        @mydata = split(/\,/, $myline);
        # Reformat mac address in to cisco format and check to see if good results                                                                
        # come back
        $mydata[1] = getCiscoMac( $mydata[1] );
	
        # make sure it's a MAC in field 1 and there is port information
        if( $mydata[1] =~ /\w+\.\w+\.\w+/ && $mydata[2] ne "0" ) {
            $netdbBulk[$arrayCount] = { switch => $mydata[0], mac => $mydata[1], port => $mydata[2], type => $mydata[3], 
				        s_vlan => $mydata[4], s_ip => $mydata[5], s_speed => $mydata[6], mac_nd => $mydata[7] };
            $arrayCount++;
        }
        else {
            chomp( $myline );
            print "updatenetdb: Load MAC Table rejected $myline\n" if $DEBUG>3;
        }
    }
}

#---------------------------------------------------------------------------------------------
# Load the int status info in to the database
#
# Example: mdcsw1,Gi1/0/27,connected,200
#---------------------------------------------------------------------------------------------
sub loadStatusTable {
    open( my $SOURCE, '<', "$optstatus") or die "Can't open $optstatus";
    my $myline;
    my @mydata;
    my $arrayCount = 0;
    @netdbBulk = undef;

    while ( $myline = <$SOURCE>) {
        next if $myline =~ /^#/; # discard comments
        chomp($myline);
        @mydata = split(/\,/, $myline);

        # Make sure vlan is populated and the port ends in a number
        if( $mydata[3] =~ /\w+/ && $mydata[1] =~ /\w+/ ) {
            $netdbBulk[$arrayCount] = { switch => $mydata[0],
                                        port => $mydata[1], 
                                        status => $mydata[2],
                                        vlan => $mydata[3], 
                                        description => $mydata[4],
                                        speed => $mydata[5],
                                        duplex => $mydata[6],
                                      };
            $arrayCount++;
        }
        else {
            chomp( $myline );
            print "updatenetdb: Load Status Table rejected $myline\n" if $DEBUG>3;
        }
    }
}

#---------------------------------------------------------------------------------------------
# Load the neighbor data in to the neighbor table
#
# Example: switch,port,n_host,n_ip,n_desc,n_model,n_port,protocol
#---------------------------------------------------------------------------------------------
sub loadNDTable {

    my $NDfile = shift;

    open( my $SOURCE, '<', "$NDfile") or die "Can't open $NDfile";
    my $myline;
    my @mydata;
    my $arrayCount = 0;
    my @netdbBulk = undef;

    while ( $myline = <$SOURCE>) {
        next if $myline =~ /^#/; # discard comments
        chomp($myline);
        @mydata = split(/\,/, $myline);

        # Make sure n_ip is populated and description exists
        #if( $mydata[3] =~ /(\d+)(\.\d+){3}/ && $mydata[4] =~ /\w+/ ) { #}
        # Make sure there is local port and a remote device name, anything else is extra
        if( $mydata[1] =~ /\w+/ && $mydata[2] =~ /\w+/ ) {
            $netdbBulk[$arrayCount] = { switch => $mydata[0], port => $mydata[1], 
                    n_host => $mydata[2], n_ip => $mydata[3], 
                    n_desc => $mydata[4], n_model => $mydata[5],
                    n_port => $mydata[6], n_protocol => $mydata[7],
                      };
            $arrayCount++;
        }
        else {
            chomp( $myline );
            print "updatenetdb: Load ND Table rejected: $myline\n" if $DEBUG>3;
        }
    }

    return \@netdbBulk;
}

#########################################################
##                                                     ##
## Print methods from netdb.pl for delete confirmation ##
##                                                     ##
#########################################################
#---------------------------------------------------------------------------------------------
# Print results from NetDB mac Table
#---------------------------------------------------------------------------------------------
sub printNetdbMACinCSV {
    my $netdbPrint_ref = shift;

    # Dereference array of hashrefs
    my @netdbPrint = @$netdbPrint_ref;

    # Get length for loop
    my $netdbPrint_length = @netdbPrint;

    # Header
    print "MAC Address,Last IP,Hostname,Vendor Code,Last Switch,Last Port,First Seen,Last Seen\n" if @netdbPrint;

    # Go through array of hashrefs and pass them to insertIPMAC
    for (my $i=0; $i < $netdbPrint_length; $i++){
        $netdbPrint[$i]{vendor} =~ s/\,|\.//g; #remove commas for CSV
        print "$netdbPrint[$i]{mac},$netdbPrint[$i]{lastip},$netdbPrint[$i]{name},$netdbPrint[$i]{vendor},$netdbPrint[$i]{lastswitch},";
        print "$netdbPrint[$i]{lastport},$netdbPrint[$i]{firstseen},$netdbPrint[$i]{lastseen}\n";
    }
}
#---------------------------------------------------------------------------------------------
# Print results from NetDB ipmac Table
#---------------------------------------------------------------------------------------------
sub printNetdbIPMACinCSV {
    my $netdbPrint_ref = shift;

    # Sort by IP address
    $netdbPrint_ref = sortByIP( $netdbPrint_ref );

    # Dereference array of hashrefs
    my @netdbPrint = @$netdbPrint_ref;

    # Get length for loop
    my $netdbPrint_length = @netdbPrint;

    # Header
    print "IP Address,MAC Address,VLAN,Static,Hostname,Switch,Port,Vendor Code,Firstseen,Lastseen\n" if @netdbPrint;

    # Go through array of hashrefs and pass them to insertIPMAC
    for (my $i=0; $i < $netdbPrint_length; $i++){
        $netdbPrint[$i]{vendor} =~ s/\,|\.//g; #remove commas for CSV
        print "$netdbPrint[$i]{ip},$netdbPrint[$i]{mac},$netdbPrint[$i]{vlan},$netdbPrint[$i]{static},$netdbPrint[$i]{name},$netdbPrint[$i]{lastswitch},";
        print "$netdbPrint[$i]{lastport},$netdbPrint[$i]{vendor},$netdbPrint[$i]{firstseen},$netdbPrint[$i]{lastseen}\n";
    }
}
#---------------------------------------------------------------------------------------------
# Print results from NetDB switchports Table
#---------------------------------------------------------------------------------------------
sub printNetdbSwitchportsinCSV {
    my $netdbPrint_ref = shift;

    # Sort Array of hashrefs based on Cisco Port naming scheme
    $netdbPrint_ref = sortByPort( $netdbPrint_ref );
    $netdbPrint_ref = sortBySwitch( $netdbPrint_ref );

    # Dereference array of hashrefs
    my @netdbPrint = @$netdbPrint_ref;

    # Get length for loop
    my $netdbPrint_length = @netdbPrint;

    # Header
    print "Switch,Port,Status,Vlan,Description,Mac Address,IP Address,Hostname,Static,Vendor,First Seen,Last Seen\n" if @netdbPrint;

    # Go through array of hashrefs and pass them to insertIPMAC
    for (my $i=0; $i < $netdbPrint_length; $i++){
        print "$netdbPrint[$i]{switch},$netdbPrint[$i]{port},$netdbPrint[$i]{status},$netdbPrint[$i]{vlan},";
        print "$netdbPrint[$i]{description},$netdbPrint[$i]{mac},$netdbPrint[$i]{ip},$netdbPrint[$i]{name},$netdbPrint[$i]{static},";
        print "$netdbPrint[$i]{vendor},$netdbPrint[$i]{firstseen},$netdbPrint[$i]{lastseen}\n";
    }
}


sub usage {
    print <<USAGE;
updatenetdb: Inserts data in the the nework database 

    Usage: updatenetdb [options]
      -a  file         Import file containing ARP table data
      -v6 file         Import IPv6 Neighbor Table
      -s  file         Import file containing static addresses, resets all existing static addresses to 0
      -m  mac          Import file containing MAC Table Data
      -i  file         Import Interface Status Information
      -r  file         Import Registration Data
      -nd file         Import CDP/LLDP/FDP Neighbor Data
      -f               Force hostname updates on ARP entries (WARNING: generates lots of DNS requests)
   
    Delete Methods (will confirm data to delete, backup with netdbctl first):
      -dt              Get statistics on unused data older than -d days
      -dm              Delete all MAC addresses and associated ARP and Switchport entries older than -d days
      -da              Delete all ARP entries older than -d days
      -ds              Delete all switchport data older than -d days
      -dw              Delete all Wifi data older than -d days
      -d days          Days in the past (combined with delete methods)
      -ip              Optional SQL parameter to narrow deletion for MAC and ARP entries, eg. 10.1.1.%

    Switch Rename and Deletion:
      -rS old,new Rename switch from old name to new name
      -drop name  Drop all switch entries in DB with this name (status and mac entries)

    Misc Options:
      -conf file       Use an alternate config file
      -v               Verbose output (if data is not getting in to the database, set this and check it)
      -debug #         Set the debug level

USAGE
    exit;
}
