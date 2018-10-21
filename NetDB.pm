#########################################################################
# NetDB.pm - Network Tracking Database Interface/Update Module
# Author: Jonathan Yantis <yantisj@gmail.com>
# Copyright (C) 2014 Jonathan Yantis
#########################################################################
#
# Module contains all the SQL statements and update logic to
# insert data in to NetDB.  Initially, this data comes from
# the arp table and is updated from utilities like updatenetdb.pl.
# Data can be queried from netdb.
#
# Populating Database:
# netdbscraper.pl updates the CSV files on disk, and updatenetdb.pl
# interfaces with this module to insert the data in the database.
# See that file first and what methods it calls to import certain
# types of data.
#
# Important Requirements:
# - All MAC addresses should be in the format xxxx.xxxx.xxxx
# - Database server must be mysql and database must exist, use
#   createnetdb.sql to initialize a new database
# - Several CPAN modules are required, see use statements below
# - Mac table lookup requires a configured oui.txt file
# - Configured from $config_file, make sure file exists and is correct
#
# API:
# All external scripts should use $dbh from connectDB[ro|rw]() as
# first argument
#
# Debugging:
#  Set $DEBUG=1 for insert debugging, 2 for full debugging on all
#  transactions.  Also consider setting $dbh->{PrintError} = 1;
#  in ConnectDB methods.
#
## Configuration File Example (Append to /etc/netdb.conf):
#dbname   = netdb       # DB must be created using createnetdb.sql first
#dbhost   = localhost   # Host MySQL is running on
#dbuser   = netdbadmin  # R/W User
#dbpass   = yourpasswd  # R/W Password
#dbuserRO = netdbuser   # Read Only User - Can use the same dbuser and pass or restrict to SELECT only user
#dbpassRO = yourpasswd
#
# File from IEEE containing MAC vendor codes, recommended to schedule a cron job to update
# cron entry: 00 5   15 * *   root    wget http://standards.ieee.org/regauth/oui/oui.txt -O /scripts/data/oui.txt
#ouifile   = /scripts/data/oui.txt
#
# NetDB Library Error log
#error_log = /var/log/netdb/netdb.error
#
##########################################################################
# Versions:
#
#  v1.0 - 4/18/2008 - Initial Library Written
#  v1.1 - 4/25/2008 - Numerour additions, mostly search options
#           Created the switchports table to track movement of
#           mac addresses.
#  v1.2 - 7/1/2008 - Added the superswitch view for more detailed
#           switch reports.
#  v1.3 - 12/30/2008 - Added switchstatus table to database and
#           methods to update the table.  This is used for switch
#           reports to get information on all ports on a switch.
#  v1.4 - 02/04/2009 - r75-78 - Added getVlanSwitchStatus to get
#           all ports configured for a vlan and any associated
#           mac addresses.  Also added sortBySwitch.
#  v1.5 - 02/11/2009 - r87 - Added description to intstatus table
#  v1.6 - 06/25/2009 - r145 - Implemented NAC registration import
#           and export methods.
#  v1.7 - 07/24/2009 - Rewrote date handling code and fixed bugs.
#         Throttled DateTime requests to improve performance.
#
##########################################################################
# Simple Data Structure Example:
#
#  # IP and mac are almost always required
# my @netdb = ( { ip => '128.23.1.1', mac => '1111.2222.3333' },
#            { ip => '128.23.1.1', mac => '1111.2222.3333' },
#          );
#
# my $netdb_ref = getQuery( \@netdb ); # pass as a reference
# @netdb = @$netdb_ref;                # Dereference
#
# For bulk updates, subs access ref to array of %netdb refs
#
# See updatenetdb.pl load methods and netdb.pl print methods
# for examples of how to handle the data structure.
#
##########################################################################
# Database Structure:
#  See createnetdb.sql, it is actively maintained and can be used
#  to start the database over from scratch.  If you make ANY edits
#  to the database structure, make sure to update the file with
#  your changes in case the database needs to be recreated from
#  scratch
#
##########################################################################
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
package NetDB;
use List::MoreUtils;   # for any()
use English qw( -no_match_vars );
use AppConfig;
use Carp;
use DBI;
use DateTime;
use DateTime::Duration;
use DateTime::Format::MySQL;
use Data::UUID; # Generate transaction ids
use Net::IP;
use Net::DNS;
use Net::DNS::Resolver;
use NetAddr::IP;
use Net::MAC::Vendor;
require Exporter;
use strict;
use warnings;

# no nonsense
no warnings 'uninitialized';

our @ISA = qw(Exporter);
our @EXPORT = qw( connectDBrw connectDBro insertIPMAC bulkInsertIPMAC bulkUpdateStatic getMAC getMACList
                  getSwitchports getSwitchReport getNeverSeen getLastSeen getMACsfromIP getMACsfromIPList
                  getIPsfromMAC getNamefromIPMAC bulkUpdateMac getVendorCode getNewMacs getVlanReport sortByPort
                  insertTransaction getTransaction getTHistory sortByIP insertVlanChange bulkUpdateSwitchStatus
                  getDBStats getVlanSwitchStatus sortBySwitch deleteMacs deleteArp deleteSwitch getVersion
                  convertMacFormat insertNACReg bulkInsertNACReg getNACReg getNACUser getNACUserMAC
                  getShortMAC getDeleteStats getUnusedPorts getDisabled insertDisabled deleteDisabled
                  getCiscoMac getIEEEMac getDashMac sortIPList nameToIP IPToName setNetDBDebug
                  deleteWifi bulkInsertND updateNACRole updateDescription updatePortVLAN
                  getSwitchportDesc dropSwitch renameSwitch
           );


# Module Version
my $VERSION = "1.13";

##########################################################################################
# NetDB Customized Settings
##########################################################################################

# Configuration is primarily read from $config_file in /etc/netdb.conf

# Configuration file to read from
my $config_file = "/etc/netdb.conf";

# DEBUG: Set to 1 for inserts, dates etc, 2 for full debug
my $DEBUG          = 0;    # Logs to stdout and to $errlog
my $printDBIErrors = 1;    # We try to catch all errors, but this may be useful for development
my $maxDateTimes   = 5000; # Maximum number of DB updates before getting a new DateTime
my $maxSwitchAge   = 7;    # Remove old switches after this many days
my $disable_v6_DNS = 0;

############################################################################################
# End Customized Settings
############################################################################################

my $dbname;       # DB Name
my $dbhost;       # DB Host
my $dbuser;       # DB Read/Write User
my $dbpass;       # R/W Password
my $dbuserRO;     # DB Read Only User
my $dbpassRO;     # DB RO Password
my $useDBTransactions = 1;     # Required for proper error handling


# Required log file to write all errors to, must be writable
my $errlog;

# optional mac vendor file, highly recommended to keep this up to date
# cron entry: 00 5   15 * *   root    wget http://standards.ieee.org/regauth/oui/oui.txt -O /scripts/data/oui.txt
my $ouidb;

# Misc Vars
my $success    = 1;
my $mac_format = "cisco";
my $update_interval = 15;  # Default update time from cron, should be configured in netdb.conf


my ( $dbh, $no_switchstatus, $errmsg, $disable_DNS, $regex );


# Search over 5 years by default
my $search_dt  = DateTime->now();
   $search_dt->subtract( years => '5' );



#######################################################################################


######################################################
# SQL Query Handlers Localized below in prepareSQL() #
######################################################

# Statics in the table ip that have never had a mac address associated
my $selectNeverSeen_h;

# Selects statics that have been seen in a certain time range
my $selectLastSeen_h;

# Used for building selectLastSeen_h ip,mac pairs
my $selectSeen_h;

# Get all IPs that a mac address has had
my $SELECTipmacWHEREmac_h;

# Get all macs that an IP has had
my $SELECTipmacWHEREip_h;

# Get all ipmac entries that a hostname wildcard had
my $SELECTipmacWHEREname_h;

my $SELECTipmacWHEREvlan_h;

my $SELECTvlanstatusWHEREvlan_h;

my $SELECTsupermacWHEREvendor_h;

my $SELECTsupermacWHEREfirstmac_h;

# SQL Insert/Update/Query Handlers

# User Access Transactions
my $insertTransaction_h;
my $insertTransaction_h_string = "INSERT INTO transactions (id,ip,username,querytype,queryvalue,querydays,time) VALUES (?,?,?,?,?,?,?)";

my $selectTransaction_h;
my $selectTHistory_h;

# Switchports Table
my $selectSwitchports_h;
my $selectSwitchports_h_string = "SELECT * FROM switchports WHERE mac=? AND switch=? AND port=? ORDER BY lastseen";

my $updateSwitchports_h;
my $updateSwitchports_h_string = "UPDATE switchports SET lastseen=?,type=?,minutes=?,uptime=?,s_vlan=?,s_ip=?,s_name=?,s_speed=? WHERE mac=? AND switch=? AND port=?";

my $insertSwitchports_h;
my $insertSwitchports_h_string = "INSERT INTO switchports (mac,switch,port,type,minutes,uptime,s_vlan,s_ip,s_name,s_speed,firstseen,lastseen) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)";

#
my $selectSwitchportsWHEREmac_h;
my $selectSwitchportsWHEREmac_h_string = "SELECT * FROM switchports WHERE mac=? ORDER BY lastseen";

my $selectSwitchportsWHEREswitchport_h;
my $selectSwitchportsWHEREswitch_h;

# Switch Status Table
my $selectSwitchStatus_h;
my $selectSwitchStatus_h_string = "SELECT * FROM switchstatus WHERE switch=? AND port=?";

my $updateSwitchStatus_h;
my $updateSwitchStatus_h_string = "UPDATE switchstatus SET vlan=?,status=?,speed=?,duplex=?,description=?,lastseen=?,lastup=?," .
                                  "p_minutes=?,p_uptime=? WHERE switch=? AND port=?";

my $insertSwitchStatus_h;
my $insertSwitchStatus_h_string = "INSERT INTO switchstatus (switch,port,vlan,status,speed,duplex,description,lastseen,lastup,p_minutes,p_uptime) " .
                                  "VALUES (?,?,?,?,?,?,?,?,?,?,?)";

my $selectSwitchStatusWHEREswitch_h;
my $selectSwitchStatusWHEREswitch_h_string = "SELECT * FROM switchstatus WHERE switch like ?";

# Superswitch Table
my $selectSuperswitch_h;
my $selectSuperswitchWHEREmac_h;
my $selectSuperswitchWHEREswitch_h;

# Search superswitch for description
my $selectSuperswitchWHEREdesc_h;


# Insert in to ipmac tables, foreign key constraints on ip(ip),mac(mac)
my $selectIPMACPair_h;
my $selectIPMACPair_h_string = "SELECT * FROM ipmac WHERE ip=? AND mac=?";

my $updateIPMACPair_h;
my $updateIPMACPair_h_string = "UPDATE ipmac SET name=?,lastseen=?,ip_minutes=?,ip_uptime=?,vlan=?,vrf=?,router=? WHERE ip=? AND mac=?";

my $insertIPMACPair_h;
my $insertIPMACPair_h_string = "INSERT INTO ipmac (ip,mac,name,firstseen,lastseen,ip_minutes,ip_uptime,vlan,vrf,router) VALUES (?,?,?,?,?,?,?,?,?,?)";

# Insert in to IP Table
my $selectIP_h;
my $selectIP_h_string = "SELECT * FROM ip WHERE ip=?";

my $updateIP_h;
my $updateIP_h_string = "UPDATE ip SET static=?,lastmac=? WHERE ip=?";

my $insertIP_h;
my $insertIP_h_string = "INSERT INTO ip (ip,static,lastmac) VALUES (?,?,?)";

my $resetIPStatic_h;
my $resetIPStatic_h_string = "UPDATE ip SET static=0";


# MAC Table
my $selectMAC_h;
my $selectMAC_h_string = "SELECT * FROM mac WHERE mac=?";

my $selectSuperMAC_h;
my $selectSuperMAC_h_string = "SELECT * FROM supermac WHERE mac=?";

my $selectShortMAC_h;

# ipmac mac table update routines
my $updateMAC_h;
my $updateMAC_h_string = "UPDATE mac SET lastip=?,vendor=?,lastseen=?,lastipseen=? WHERE mac=?";

my $insertMAC_h;
my $insertMAC_h_string = "INSERT INTO mac (mac,lastip,vendor,firstseen,lastseen,lastipseen) VALUES (?,?,?,?,?,?)";

# Insert switchport info in to mac table
my $updateMACSwitchport_h;
my $updateMACSwitchport_h_string = "UPDATE mac SET lastswitch=?, lastport=?, vendor=?, mac_nd=?, lastseen=? WHERE mac=?";

my $insertMACSwitchport_h;
my $insertMACSwitchport_h_string = "INSERT INTO mac (mac,lastswitch,lastport,vendor,mac_nd,firstseen,lastseen) VALUES (?,?,?,?,?,?,?)";

# Neighbor Discovery Data
my $selectND_h;
my $selectND_h_string = "SELECT * FROM neighbor WHERE switch=? AND port=?";

my $insertND_h;
my $insertND_h_string = "INSERT INTO neighbor (switch,port,n_host,n_ip,n_desc,n_model,n_port,n_protocol,n_lastseen) VALUES (?,?,?,?,?,?,?,?,?)";

my $updateND_h;
my $updateND_h_string = "UPDATE neighbor SET n_host=?, n_ip=?, n_desc=?, n_model=?, n_port=?, n_protocol=?, n_lastseen=? WHERE switch=? AND port=?";



# nacreg data
my $selectNACReg_h;
my $selectNACReg_h_string = "SELECT * from nacreg WHERE mac=?";

my $selectNACUser_h;
my $selectNACUserMAC_h;

my $updateNACReg_h;
my $updateNACReg_h_string = "UPDATE nacreg SET time=?, firstName=?, lastName=?, userID=?, email=?, phone=?, type=?, entity=?, critical=?, role=?, title=?, status=?, pod=?, dbid=? WHERE mac=?";

my $insertNACReg_h;
my $insertNACReg_h_string = "INSERT INTO nacreg (mac,time,firstName,lastName,userID,email,phone,type,entity,critical,role,title,status,pod,dbid) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";


# Disabled Table Data
my $selectDisabled_h;
my $selectDisabled_h_string = "SELECT * FROM disabled where mac=?";

my $insertDisabled_h;
my $insertDisabled_h_string = "INSERT INTO disabled (mac,distype,disuser,disdata,discase,disdate,severity) VALUES (?,?,?,?,?,?,?)";

my $deleteDisabled_h;
my $deleteDisabled_h_string = "DELETE FROM disabled where mac=?";


# Printer VLAN
my $insertVLANCHANGE_h;
my $insertVLANCHANGE_h_string = "INSERT INTO vlanchange (switch,port,vlan,username,ip,changetype,time) VALUES (?,?,?,?,?,?,?)";


my $selectVLANCHANGE_h;
my $selectVLANCHANGE_h_string = "SELECT * FROM vlanchange WHERE switch=?,port=?,changetype=?";


# Delete Methods
my $selectDeleteMacs_h;
my $deleteMacs_h;
my $selectDeleteArp_h;
my $deleteArp_h;
my $selectDeleteSwitch_h;
my $deleteSwitch_h;
my $selectDeleteWifi_h;
my $deleteWifi_h;

#########################
# DB Connection Methods #
#########################

# Establish connection to database, must connect to pass in to other functions
sub connectDBrw {

    # Alternate Config File Option
    my $alt_config = shift;
    $config_file = $alt_config if $alt_config;

    &parseConfig();

    print "DEBUG: Connecting to Database as RW User\n" if $DEBUG>1;

    my $dbh = DBI->connect("dbi:mysql:$dbname:$dbhost", "$dbuser", "$dbpass");

    if ( $dbh ) {
    $dbh->{PrintError} = $printDBIErrors;

        # DB Version Check, die if failure
        checkDBVersion( $dbh );

    return $dbh;
    }
    else {
    logErrorMessage( "$DBI::errstr" );
    croak "$DBI::errstr\n";
    }
}

# Establish user level access to the database, read-only access
sub connectDBro {

    # Alternate Config File Option
    my $alt_config = shift;
    $config_file = $alt_config if $alt_config;

    &parseConfig();

    print "DEBUG: Connecting to Database as RO User\n" if $DEBUG>1;

    my $dbh = DBI->connect("dbi:mysql:$dbname:$dbhost", "$dbuserRO", "$dbpassRO");

    if ( $dbh ) {
    $dbh->{PrintError} = $printDBIErrors;

    # DB Version Check, die if failure
    checkDBVersion( $dbh );

    # Return Handler
        return $dbh;
    }
    else {
        logErrorMessage( "$DBI::errstr" );
        croak "$DBI::errstr\n";
    }
}

# Set the debug level from the command line -debug (updatenetdb.pl)
sub setNetDBDebug {
    my $cli_debug = shift;

    # Match CLI debug levels to library debug level
    processDebug( $cli_debug );

    print "NetDB Library Debug Level: $DEBUG\n";
}

sub getVersion {
    return $VERSION;
}

########################
# Database Get Methods #
########################
#---------------------------------------------------------------------------------------------
# Get MAC table entry where MAC
#   Input: ($dbh,$mac)
#       dbh: database handle
#       mac: MAC addresse
#   Output:
#       netdb refrence: the resulting table produced by the MAC lookup
#--------------------------------------------------------------------------------------------
sub getMAC {
    $dbh = shift;
    my $mac = shift;
    my @macAdder = $mac;

    if ( !$mac || !$dbh ) {
        croak ("Must supply mac, check your input");
    }

    return getMACList($dbh,\@macAdder);
} # END sub getMAC
#---------------------------------------------------------------------------------------------
# Get MAC table entry where for list of MACs
#   Input: ($dbh,$mac_ref)
#       dbh: database handle
#       mac reference: refrence to an array of MAC addresses
#   Output: ($netdb_ref)
#       netdb refrence: the resulting table produced by the MAC lookups
#---------------------------------------------------------------------------------------------
sub getMACList {
    $dbh = shift;
    my $mac_ref = shift;
    my @MACs = @$mac_ref;
    my $counter = 0;
    my @netdbBulk;

     if ( !$dbh ) {
        croak ("|ERROR|: No database handle, check your input");
    }

    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }
    foreach my $mac (@MACs){
        $mac = getCiscoMac($mac);
        next if ( !$mac );
        $selectSuperMAC_h->execute( $mac );

        while ( my $row = $selectSuperMAC_h->fetchrow_hashref() ) {
            if ( $row ) {
                $netdbBulk[$counter] = $row;
                $counter++;
            }
        } # END while through queries
    } # END foreach loop though each mac address
    my $netdb_ref = shortenV6( \@netdbBulk );
    return $netdb_ref;
} # END sub getMACList
#---------------------------------------------------------------------------------------------
# Get mac table entries where short mac
# Format of mac: xx:xx (last 4) or xx:xx* or *xx:xx
#---------------------------------------------------------------------------------------------
sub getShortMAC {
    $dbh = shift;
    my $mac = shift;
    my $counter = 0;
    my $hours = shift;
    my $search;
    my $type = "end";
    my @netdbBulk;

    # Determine where wildcard is

    # Search first part of mac address (xx:xx:xx*)
    if ( $mac =~ /\*$/ ) {

    # Strip out characters and put mac in partial cisco format
    $mac =~ s/(\*|\:)//g;
    $mac =~ s/(\w{4})/$1\./g;

    chop( $mac ) if $mac =~ /\.$/;

        $search = "$mac\%";
    }

    # Search the end of mac address (*xx:xx:xx)
    else {
    # Reverse String for processing
    $mac = reverse( $mac );

        # Strip out characters and put mac in partial cisco format
        $mac =~ s/(\*|\:)//g;
        $mac =~ s/(\w{4})/$1\./g;

    # Reverse Again
    $mac = reverse( $mac );

        $search = "\%$mac";
    }

    print "Debug: search short mac: $search\n" if $DEBUG;


    if ( !$search || !$dbh ) {
        croak ("Must supply short mac, check your input: $search");
    }

    # Initialize Search hours before setting up queries
    if ( $hours ) {
        $search_dt = getDate( $hours );
    }

    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }

    $selectShortMAC_h->execute( "$search" );

    while ( my $row = $selectShortMAC_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }

    my $netdb_ref = shortenV6( \@netdbBulk );
    return $netdb_ref;
}

#---------------------------------------------------------------------------------------------
# Get switchports on a mac entry
#---------------------------------------------------------------------------------------------
sub getSwitchports {
    $dbh = shift;
    my $mac = shift;
    my $hours = shift;
    my $row;
    my $counter = 0;
    my @netdbBulk;

    $mac = getCiscoMac($mac);

    if ( !$mac || !$dbh ) {
        croak ("Must supply mac, check your input");
    }
    # Initialize Search hours before setting up queries
    if ( $hours ) {
        $search_dt = getDate( $hours );
    }
    # Initialize queries if necessary
    if ( !$selectIP_h || $hours ) {
        prepareSQL();
    }

    $selectSuperswitchWHEREmac_h->execute( $mac );
    while ( $row = $selectSuperswitchWHEREmac_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }

    my $netdb_ref = shortenV6( \@netdbBulk );
    $netdb_ref = fixupSwitchports( \@netdbBulk );
    return $netdb_ref;
}
#---------------------------------------------------------------------------------------------
# Get a switch report on a switch name and optionally a port after the comma
#---------------------------------------------------------------------------------------------
sub getSwitchReport {
    $dbh = shift;
    my $switch = shift;
    my $hours = shift;
    my $port;
    my $row;
    my $counter = 0;
    my @netdbBulk;

    # Split off port if it exists
    ($switch, $port) = split( /\,/, $switch);

    # If no port, use wildcard
    if ( !$port ) {
        $port = "\%";
    }
    else {
        $port = "$port";
    }

    # Allow wildcard (*) for switch names
    $switch =~ s/\*$/\%/; $switch =~ s/^\*/\%/; $switch =~ s/\*//g;
    if ( !$switch || !$dbh ) {
        croak ("Must supply switch, check your input");
    }
    # Initialize Search hours before setting up queries
    if ( $hours ) {
        $search_dt = getDate( $hours );
    }
    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }

    $selectSuperswitchWHEREswitch_h->execute( $switch, $port );
    while ( $row = $selectSuperswitchWHEREswitch_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }

    my $netdb_ref = shortenV6( \@netdbBulk );
    $netdb_ref = fixupSwitchports( \@netdbBulk );
    return $netdb_ref;

}

#---------------------------------------------------------------------------------------------
# Get all switchports that have a description that matches %$search%
#---------------------------------------------------------------------------------------------
sub getSwitchportDesc {
    $dbh = shift;
    my $search = shift;
    my $hours = shift;
    my $row;
    my $counter = 0;
    my @netdbBulk;

    if ( !$search || !$dbh ) {
        croak ("Must supply description search term, check your input");
    }

    chomp( $search );
    $search = "\%$search\%";

    # Initialize Search hours before setting up queries
    if ( $hours ) {
        $search_dt = getDate( $hours );
    }
    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }

    $selectSuperswitchWHEREdesc_h->execute( $search );
    while ( $row = $selectSuperswitchWHEREdesc_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }

    my $netdb_ref = shortenV6( \@netdbBulk );
    $netdb_ref = fixupSwitchports( \@netdbBulk );
    return $netdb_ref;
}


#---------------------------------------------------------------------------------------------
# Hostname Search on ipmac
#---------------------------------------------------------------------------------------------
sub getNamefromIPMAC {
    $dbh = shift;
    my $name = shift;
    my $hours = shift;

    my $row;
    my $counter = 0;
    my @netdbBulk;

    if ( !$name || !$dbh ) {
        croak ("Must supply hostname, check your input");
    }

    # Initialize Search hours before setting up queries
    if ( $hours ) {
        $search_dt = getDate( $hours );
    }
    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }

    # Don't full-text search hostnames unless requested
    # Big performance increases with large ARP tables
    if ( $regex ) {
        # Allow (*) as wildcard at the beginning and end of line
        $name =~ s/\*$/\%/; $name =~ s/^\*/\%/; $name =~ s/\*//g;
        $SELECTipmacWHEREname_h->execute( $name );
    }
    else {
        $SELECTipmacWHEREname_h->execute( "\%$name\%" );
    }

    while ( $row = $SELECTipmacWHEREname_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }

    my $netdb_ref = shortenV6( \@netdbBulk );
    return $netdb_ref;
}
#---------------------------------------------------------------------------------------------
# Get all macs at IP address
#   Input: ($dbh,$ip,$hours)
#       dbh: database handle
#       ip: an IP addresses
#       hours: how far back to look for the information
#   Output: ($netdb_ref)
#       netdb refrence: the resulting table produced by the IP lookup
#---------------------------------------------------------------------------------------------
sub getMACsfromIP {
    $dbh = shift;
    my $ip = shift;
    my $hours = shift;
    my @ipAdder = $ip;

    if ( !$ip || !$dbh ) {
        croak ("Must supply a valid IPv4 or IPv6 address, or partial IP eg. 10.10. check your input");
    }

    return getMACsfromIPList ( $dbh, \@ipAdder, $hours);
} # END sub getMACsfromIP
#---------------------------------------------------------------------------------------------
# Get all macs from a list of IP address
#   Input: ($dbh,$ip,$hours)
#       dbh: database handle
#       ip reference: refrence to an array of IP addresses
#       hours: how far back to look for the information
#   Output: ($netdb_ref)
#       netdb refrence: the resulting table produced by the IP lookups
#---------------------------------------------------------------------------------------------
sub getMACsfromIPList {
    $dbh = shift;
    my $ip = shift;
    my $hours = shift;
    my @IPs = @$ip;

    my $row;
    my $counter = 0;
    my @netdbBulk;

    if ( !$dbh ) {
        croak ("|ERROR|: No database handle, check your input, check your input");
    }

    # Initialize Search hours before setting up queries
    if ( $hours ) {
        $search_dt = getDate( $hours );
    }
    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }

    foreach my $ip (@IPs){
        next if ( !$ip );
        # Support wildcard ip queries
        my $ipchk = new Net::IP($ip);

        # Valid IP check
        if ( $ipchk ) {
            # IPv6 Address, get long format and strip colons
            if ( $ip =~ /:/ ) {
                $ip = $ipchk->ip();
                $ip =~ s/://g;
            }
        }
        # Partial IP, eg. 10.10.
        elsif ( $ip =~ /^(\d+)(\.\d+){1}/ ) {
            $ip = "$ip%";
        }
        else {
            $ip = undef;
        }

        $SELECTipmacWHEREip_h->execute( $ip );

        while ( $row = $SELECTipmacWHEREip_h->fetchrow_hashref() ) {
            if ( $row ) {
                $netdbBulk[$counter] = $row;
                $counter++;
            }
        }
    }

    my $netdb_ref = shortenV6( \@netdbBulk );
    return $netdb_ref;
} # END sub getMACsfromIPList
#---------------------------------------------------------------------------------------------
# Get all IP address at MAC
#---------------------------------------------------------------------------------------------
sub getIPsfromMAC {

    $dbh = shift;
    my $mac = shift;
    my $hours = shift;

    my $row;
    my $counter = 0;
    my @netdbBulk;

    $mac = getCiscoMac($mac);

    if ( !$mac || !$dbh ) {
        croak ("Must supply mac address, check your input");
    }

   # Initialize Search hours before setting up queries
    if ( $hours ) {
        $search_dt = getDate( $hours );
    prepareSQL(); # Reinitialize time stamps
    }

    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }

    $SELECTipmacWHEREmac_h->execute( $mac );

    while ( $row = $SELECTipmacWHEREmac_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }

    my $netdb_ref = shortenV6( \@netdbBulk );
    return $netdb_ref;
}
#---------------------------------------------------------------------------------------------
# Get ipmac entries where vlan=
#---------------------------------------------------------------------------------------------
sub getVlanReport {
    $dbh = shift;
    my $vlan = shift;
    my $hours = shift;

    my $row;
    my $counter = 0;
    my @netdbBulk;

    if ( !$vlan || !$dbh ) {
        croak ("Must supply vlan, check your input");
    }

    # Initialize Search hours before setting up queries
    if ( $hours ) {
        $search_dt = getDate( $hours );
    }

    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }

    $SELECTipmacWHEREvlan_h->execute( $vlan );

    while ( $row = $SELECTipmacWHEREvlan_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }

    my $netdb_ref = shortenV6( \@netdbBulk );
    return $netdb_ref;
}
#---------------------------------------------------------------------------------------------
# Get superstatus table where vlan
#---------------------------------------------------------------------------------------------
sub getVlanSwitchStatus {
    $dbh = shift;
    my $vlan = shift;
    my $hours = shift;

    my $row;
    my $counter = 0;
    my @netdbBulk;


    if ( !$vlan || !$dbh ) {
        croak ("Must supply vlan, check your input");
    }

   # Initialize Search hours before setting up queries
    if ( $hours ) {
        $search_dt = getDate( $hours );
    }

    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }

    $SELECTvlanstatusWHEREvlan_h->execute( $vlan );

    while ( $row = $SELECTvlanstatusWHEREvlan_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }

    my $netdb_ref = shortenV6( \@netdbBulk );
    return $netdb_ref;
}
#---------------------------------------------------------------------------------------------
# Get new mac address on the network in the past $hours
#---------------------------------------------------------------------------------------------
sub getNewMacs {
    $dbh = shift;
    my $hours = shift;

    my $row;
    my $counter = 0;
    my @netdbBulk;

    if ( !$hours || !$dbh ) {
        croak ("Must supply timeframe, check your input");
    }

    # Initialize Search hours before setting up queries
    $search_dt = getDate( $hours );

    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }

    $SELECTsupermacWHEREfirstmac_h->execute();

    while ( $row = $SELECTsupermacWHEREfirstmac_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }

    my $netdb_ref = shortenV6( \@netdbBulk );
    return $netdb_ref;
}
#---------------------------------------------------------------------------------------------
# Vendor code search on mac
#---------------------------------------------------------------------------------------------
sub getVendorCode {
    $dbh = shift;
    my $vendor = shift;
    $vendor = uc($vendor);
    my $hours = shift;

    my $row;
    my $counter = 0;
    my @netdbBulk;

    print "Search String: $vendor\n" if $DEBUG;

    if ( !$vendor || !$dbh ) {
        croak ("Must supply Vendor Code substr, check your input");
    }

    # Initialize Search hours before setting up queries
    if ( $hours ) {
        $search_dt = getDate( $hours );
    }

    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }

    $SELECTsupermacWHEREvendor_h->execute( "\%$vendor\%" );

    while ( $row = $SELECTsupermacWHEREvendor_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }
    my $netdb_ref = sortByLastIP( \@netdbBulk );
    $netdb_ref = shortenV6( $netdb_ref );
    return $netdb_ref;
}
#---------------------------------------------------------------------------------------------
# Get NAC Registration for a mac address
#---------------------------------------------------------------------------------------------
sub getNACReg {
    $dbh = shift;
    my $mac = shift;

    my $row;
    my $counter = 0;
    my @netdbBulk;


    $mac = getCiscoMac( $mac );

    if ( !$mac || !$dbh ) {
        croak ("Must supply mac address, check your input");
    }

    if ( !$selectIP_h ) {
        prepareSQL();
    }

    $selectNACReg_h->execute( $mac );

    while ( $row = $selectNACReg_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }
    return \@netdbBulk;

}
#---------------------------------------------------------------------------------------------
# Get all registrations for a user
#---------------------------------------------------------------------------------------------
sub getNACUser {
    $dbh = shift;
    my $user = shift;
    my $hours = shift;

    my $row;
    my $counter = 0;
    my @netdbBulk;

    # Shift date if needed
    if ( $hours ) {
        $search_dt = getDate( $hours );
    }

    if ( !$user || !$dbh ) {
        croak ("Must supply mac address, check your input");
    }

    if ( !$selectIP_h ) {
        prepareSQL();
    }

    $selectNACUser_h->execute( $user );

    while ( $row = $selectNACUser_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }
    return \@netdbBulk;
}
#---------------------------------------------------------------------------------------------
# Get all data from the supermac table registered to this user
#---------------------------------------------------------------------------------------------
sub getNACUserMAC {
    $dbh = shift;
    my $user = shift;
    my $hours = shift;

    my $row;
    my $counter = 0;
    my @netdbBulk;

    # Shift date if needed
    if ( $hours ) {
        $search_dt = getDate( $hours );
    }

    if ( !$user || !$dbh ) {
        croak ("Must supply mac address, check your input");
    }

    if ( !$selectIP_h ) {
        prepareSQL();
    }

    $selectNACUserMAC_h->execute( $user );

    while ( $row = $selectNACUserMAC_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }
    my $netdb_ref = shortenV6( \@netdbBulk );
    return $netdb_ref;
}

#---------------------------------------------------------------------------------------------
# Get disabled entry for mac address
#---------------------------------------------------------------------------------------------
sub getDisabled {
    $dbh = shift;
    my $mac = shift;
    my $row;
    my @netdbBulk;
    my $counter = 0;

    $mac = getCiscoMac( $mac );

    if ( !$mac || !$dbh ) {
        croak ("getDisabled: Must supply mac address, check your input");
    }

    if ( !$selectIP_h ) {
        prepareSQL();
    }

    $selectDisabled_h->execute( $mac );

    while ( $row = $selectDisabled_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }
    return \@netdbBulk;

}

#---------------------------------------------------------------------------------------------
# Get array of hashrefs of statics not seen in $hours
#---------------------------------------------------------------------------------------------
sub getLastSeen {
    $dbh = shift;
    my $hours = shift;

    my $row;
    my $counter = 0;
    my $dt;
    my @netdbBulk;

    # Shift Date for search entries older than $hours
    $dt = getDate( $hours ) if $hours;

    prepareSQL();

    $selectSeen_h->execute();

    while ( $row = $selectSeen_h->fetchrow_hashref() ) {
        $selectLastSeen_h->execute( $$row{ip}, $$row{lastmac}, $dt );
        $row = $selectLastSeen_h->fetchrow_hashref();
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }

    my $netdb_ref = sortLastSeen( \@netdbBulk );
    $netdb_ref = shortenV6( $netdb_ref );

    return $netdb_ref;
}
#---------------------------------------------------------------------------------------------
# Get transaction id from id
#---------------------------------------------------------------------------------------------
sub getTransaction {
    $dbh = shift;
    my $id = shift;
    my $counter = 0;
    my @netdbBulk;

    if ( !$id || !$dbh ) {
        croak ("Must supply id, check your input");
    }

    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }

    $selectTransaction_h->execute( $id );

    while ( my $row = $selectTransaction_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }
    return \@netdbBulk;
}
#---------------------------------------------------------------------------------------------
# Get Transaction History
#---------------------------------------------------------------------------------------------
sub getTHistory {
    $dbh = shift;
    my $counter = 0;
    my @netdbBulk;
    my $hours = shift;

   # Initialize Search hours before setting up queries
    if ( $hours ) {

        $search_dt = getDate( $hours );
    }

    if ( !$dbh ) {
        croak ("No dbh");
    }

    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }

    $selectTHistory_h->execute();

    while ( my $row = $selectTHistory_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }
    return \@netdbBulk;
}
#---------------------------------------------------------------------------------------------
# Get array of hashrefs of never used static addresses
#---------------------------------------------------------------------------------------------
sub getNeverSeen {
    $dbh = shift;

    my $row;
    my $counter = 0;
    my @netdbBulk;

    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }

    $selectNeverSeen_h->execute();

    while ( $row = $selectNeverSeen_h->fetchrow_hashref() ) {
        $netdbBulk[$counter] = $row;
        $counter++;
    }

    return \@netdbBulk;
}
#---------------------------------------------------------------------------------------------
## Get unused port report
#---------------------------------------------------------------------------------------------
sub getUnusedPorts {
    $dbh = shift;
    my $switch = shift;
    my $hours = shift;
    my ( $row, $counter, $status_h, $ports_h );
    my @netdbBulk;
    my %ports;
    my %status;

    # Shift date if needed
    if ( $hours ) {
        if ( $hours == "168" ) {
            print STDERR "WARNING: Unused Port Report Only for the Past 7 Days, use -d\n";
        }
        $search_dt = getDate( $hours );
    }
    if ( !$switch || !$dbh ) {
        croak ("Must supply switch or all, check your input");
    }

    # Allow (*) as wildcard at the beginning and end of line
    $switch =~ s/\*$/\%/; $switch =~ s/^\*/\%/; $switch =~ s/\*//g;

    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }

    # Full Report if switch==all
    if ( $switch eq 'all' ) {
        $ports_h = $dbh->prepare( "SELECT * from switchports WHERE lastseen > '$search_dt'" );
        $status_h = $dbh->prepare( "SELECT * from switchstatus" );

        $ports_h->execute();
        $status_h->execute();
    }

    # Report on specific switch
    else {
        $selectSwitchportsWHEREswitch_h->execute( $switch );
        $selectSwitchStatusWHEREswitch_h->execute( $switch );

        $ports_h = $selectSwitchportsWHEREswitch_h;
        $status_h = $selectSwitchStatusWHEREswitch_h;
    }
    # Get all the ports that have something on them in the past days
    while ( $row = $ports_h->fetchrow_hashref() ) {
        if ( $row ) {
            #print "$$row{switch},$$row{port}\n"
            $ports{"$$row{switch},$$row{port}"} = 1;
        }
    }
    # Filter out ports that are up or that had something on them in the past
    while ( $row = $status_h->fetchrow_hashref() ) {
        if ( $row ) {
            #print "$$row{switch},$$row{port}\n"
            if ( !$ports{"$$row{switch},$$row{port}"} && $$row{status} !~ /(up|connected)/i ) {
                $netdbBulk[$counter] = $row;
                $counter++;
            }
        }
    }

    return \@netdbBulk;
}
#---------------------------------------------------------------------------------------------
## Database Statistics
#---------------------------------------------------------------------------------------------
sub getDBStats {
    $dbh = shift;
    my $hours = shift;
    my $ip = shift;
    my $row;
    my $counter = 0;
    my %stats;
    my $dbs;
    my $dbs_h;

    if ( !$hours || !$dbh ) {
        croak ("Must supply hours, check your input");
    }

    # Initialize Search hours before setting up queries
    if ( $hours ) {
        $search_dt = getDate( $hours );
    }

    # Check for an ip filter
    if ( !$ip ) {
        $dbs_h = $dbh->prepare( "SELECT COUNT(1) FROM supermac where lastseen > '$search_dt'" );
        $dbs_h->execute();
    }
    else {
        $dbs_h = $dbh->prepare( "SELECT COUNT(1) FROM supermac where lastip like ? lastseen > '$search_dt'" );
        $dbs_h->execute( $ip );
    }
    $stats{mac} = $dbs_h->fetchrow_array();

    $dbs_h = $dbh->prepare( "SELECT COUNT(1) FROM mac where firstseen > '$search_dt'" );
    $dbs_h->execute();
    $stats{newmacs} = $dbs_h->fetchrow_array();

    $dbs_h = $dbh->prepare( "SELECT COUNT(1) FROM ipmac where lastseen > '$search_dt'" );
    $dbs_h->execute();
    $stats{ipmac} = $dbs_h->fetchrow_array();

    $dbs_h = $dbh->prepare( "SELECT COUNT(1) FROM ip" );
    $dbs_h->execute();
    $stats{ip} = $dbs_h->fetchrow_array();

    $dbs_h = $dbh->prepare( "SELECT COUNT(1) FROM switchports where lastseen > '$search_dt' AND type IS NULL OR type = ''" );
    $dbs_h->execute();
    $stats{switchports} = $dbs_h->fetchrow_array();

    $dbs_h = $dbh->prepare( "SELECT COUNT(1) FROM switchports where lastseen > '$search_dt' AND type = 'wifi'" );
    $dbs_h->execute();
    $stats{wifi} = $dbs_h->fetchrow_array();

    $dbs_h = $dbh->prepare( "SELECT COUNT(1) FROM switchstatus" );
    $dbs_h->execute();
    $stats{switchstatus} = $dbs_h->fetchrow_array();

    $dbs_h = $dbh->prepare( "SELECT COUNT(1) FROM nacreg" );
    $dbs_h->execute();
    $stats{nacreg} = $dbs_h->fetchrow_array();

    $dbs_h = $dbh->prepare( "SELECT COUNT(1) FROM transactions where time > '$search_dt'" );
    $dbs_h->execute();
    $stats{transactions} = $dbs_h->fetchrow_array();

    return \%stats;
}

#---------------------------------------------------------------------------------------------
## Database Deletion Statistics
#---------------------------------------------------------------------------------------------
sub getDeleteStats {
    $dbh = shift;
    my $hours = shift;
    my $ip = shift;

    my $row;
    my $counter = 0;
    my %stats;
    my $dbs;
    my $dbs_h;

    if ( !$hours || !$dbh ) {
        croak ("Must supply hours, check your input");
    }

   # Initialize Search hours before setting up queries
    if ( $hours ) {
        $search_dt = getDate( $hours );
    }

    # Check for an ip filter
    if ( !$ip ) {
        $dbs_h = $dbh->prepare( "SELECT COUNT(1) FROM mac where lastseen < '$search_dt'" );
        $dbs_h->execute();
    }
    else {
        $dbs_h = $dbh->prepare( "SELECT COUNT(1) FROM mac where IFNULL(lastip,\"ABC\") like ? AND lastseen < '$search_dt'" );
        $dbs_h->execute( $ip );
    }
    $stats{mac} = $dbs_h->fetchrow_array();

    # Superarp, optional IP filter
    if ( !$ip ) {
        $dbs_h = $dbh->prepare( "SELECT COUNT(1) FROM ipmac where lastseen < '$search_dt'" );
        $dbs_h->execute();
    }
    else {
        $dbs_h = $dbh->prepare( "SELECT COUNT(1) FROM ipmac where ip like ? AND lastseen < '$search_dt'" );
        $dbs_h->execute( $ip );
    }
    $stats{ipmac} = $dbs_h->fetchrow_array();

    # These don't apply to IP filters
    if ( !$ip ) {
        $dbs_h = $dbh->prepare( "SELECT COUNT(1) FROM switchports where lastseen < '$search_dt'" );
        $dbs_h->execute();
        $stats{switchports} = $dbs_h->fetchrow_array();

        $dbs_h = $dbh->prepare( "SELECT COUNT(1) FROM nacreg left join (mac) ON nacreg.mac=mac.mac where mac.lastseen < '$search_dt'" );
        $dbs_h->execute();
        $stats{nacreg} = $dbs_h->fetchrow_array();
    }

    return \%stats;
}

#---------------------------------------------------------------------------------------------
# Generate uuid to use as transaction id
#---------------------------------------------------------------------------------------------
sub getTransactionID {
    my $ug    = new Data::UUID;
    my $uuid1 = $ug->create();
    my $str   = $ug->to_string( $uuid1 );
    return $str;
}


###########################
# Sort and Helper Methods #
###########################

# Verify Database version is the same as the library $VERSION
sub checkDBVersion {
    my $dbh = shift;

    my  $dbs_h = $dbh->prepare( "SELECT version FROM meta where name = 'netdb'" );
    $dbs_h->execute();
    my $version = $dbs_h->fetchrow_array();

    print "Library Version: $VERSION, Database Version: $version\n" if $DEBUG;

    if ( $VERSION ne $version ) {
        logErrorMessage( "NetDB Library version $VERSION does not match database version $version." );
        die "Error: Library/DB mismatch, please run the upgrade script in the sql directory.\n";
    }
}

# Get DateTime object optionally shifted by $hours in the Local Timezone
sub getDate {
    my $dt     = DateTime->now();
    my $hours  = shift;
    my $tz     = DateTime::TimeZone->new( name => 'local' );

    print "tz: $tz\n" if $DEBUG>1;

    $dt->set_time_zone( $tz );
    $dt->subtract( hours => $hours) if $hours;

    print "Debug: DateTime Value: $dt\n" if $DEBUG>1;

    return $dt;
}

# Sort @netdbBulk by lastseen, needed for sorts on lists not in database
sub sortLastSeen {
    my $netdbBulk_ref = shift;

    # Dereference %netdbBulk
    my @netdbBulk = @$netdbBulk_ref;

    @netdbBulk = sort {
        DateTime->compare_ignore_floating(
            DateTime::Format::MySQL->parse_datetime($$a{lastseen}),
            DateTime::Format::MySQL->parse_datetime($$b{lastseen})
        )
    } @netdbBulk;

    return \@netdbBulk;
}

# Sort @netdbBulk by $$netdbBulk{port}
sub sortByPort {
    my $netdbBulk_ref = shift;
    my @netdbBulk = @$netdbBulk_ref;

    my ( $v1, $v2 );
    my @tmp;

    # Sort by 0/0/0 first
    @netdbBulk = sort {
        @tmp = ( $$a{port} =~ /\d+/g ); # Get GigabitEthernet x/y/z as individual numbers in an array
        $v1 = $tmp[0]*100000 + $tmp[1]*1000 + $tmp[2]; # Assign weights to x/y/z for correct sorting

        @tmp = ( $$b{port} =~ /\d+/g );
        $v2 = $tmp[0]*100000 + $tmp[1]*1000 + $tmp[2];

        $v1 cmp $v2; # Compare the two weights
    } @netdbBulk;

    # Then sort by Gi, Fa etc
    @netdbBulk = sort {

        ($v1) = split( /\d+/, $$a{port} ); # Split off the numbers
    ($v2) = split( /\d+/, $$b{port} );
        $v1 cmp $v2; # Compare the two weights
    } @netdbBulk;

    return \@netdbBulk;
}

# Sort @netdbBulk by $$netdbBulk{switch}
sub sortBySwitch {
    my $netdbBulk_ref = shift;
    my @netdbBulk = @$netdbBulk_ref;

    my ( $v1, $v2 );
    my @tmp;

    @netdbBulk = sort {
        $v1 = $$a{switch};
        $v2 = $$b{switch};
        $v1 cmp $v2;
    } @netdbBulk;

    return \@netdbBulk;
}

# Sort @netdbBulk by $$netdbBulk{ip}
sub sortByIP {
    my $netdbBulk_ref = shift;
    my @netdbBulk = @$netdbBulk_ref;

    my ( $v1, $v2 );
    my @tmp;

    @netdbBulk = sort {
        @tmp = ( $$a{ip} =~ /(\d+)/g ); # Split IP by . in to @tmp
        $v1 = $tmp[0]*100000000 + $tmp[1]*1000000 + $tmp[2]*1000 + $tmp[3]; # Assign weights a.b.c.d

        @tmp = ( $$b{ip} =~ /(\d+)/g ); # Split IP by . in to @tmp
        $v2 = $tmp[0]*100000000 + $tmp[1]*1000000 + $tmp[2]*1000 + $tmp[3]; # Assign weights a.b.c.d

        $v1 cmp $v2; # Compare the two weights
    } @netdbBulk;

    return \@netdbBulk;
}

# Sort @netdbBulk by $$netdbBulk{lastip}
sub sortByLastIP {
    my $netdbBulk_ref = shift;
    my @netdbBulk = @$netdbBulk_ref;

    my ( $v1, $v2 );
    my @tmp;

    @netdbBulk = sort {
        @tmp = ( $$a{lastip} =~ /(\d+)/g ); # Split IP by . in to @tmp
        $v1 = $tmp[0]*100000000 + $tmp[1]*1000000 + $tmp[2]*1000 + $tmp[3]; # Assign weights a.b.c.d

        @tmp = ( $$b{lastip} =~ /(\d+)/g ); # Split IP by . in to @tmp
        $v2 = $tmp[0]*100000000 + $tmp[1]*1000000 + $tmp[2]*1000 + $tmp[3]; # Assign weights a.b.c.d

        $v1 cmp $v2; # Compare the two weights
    } @netdbBulk;

    return \@netdbBulk;
}

# Convert the Mac address format from cisco to ieee_dash or ieee_colon
sub convertMacFormat {
    my $netdbBulk_ref  = shift;
    my $new_mac_format = shift;

    # Fallback to the default display format if no specific format is passed in
    $new_mac_format = $mac_format if !$new_mac_format;

    print "NetDB Debug: Converting Data to MAC Format $new_mac_format\n" if $DEBUG>1;

    if ( $new_mac_format ne 'cisco') {
        foreach my $netdb_ref ( @$netdbBulk_ref ) {
            if ( $new_mac_format eq 'ieee_colon' ) {
                $$netdb_ref{mac} = getIEEEMac($$netdb_ref{mac});
            }
            elsif ( $new_mac_format eq 'ieee_dash' ) {
                $$netdb_ref{mac} = getDashMac($$netdb_ref{mac});
            }
            elsif ( $new_mac_format eq 'no_format' ) {
                $$netdb_ref{mac} =~ s/(:|\.|\-|(^0x)|)//g;
            }
            else {
            $$netdb_ref{mac} = getCiscoMac($$netdb_ref{mac});
            }
        }
    }
    return $netdbBulk_ref;
}

#######################################################
# Clean up mac addresses and put them in cisco format
# returns xxxx.xxxx.xxxx or just xxxx for short format
#######################################################
sub getCiscoMac {
    my ($mac) = @_;

    if ( $mac ) {
        $mac =~ s/(:|\.|\-|(^0x)|)//g;
        $mac =~ tr/[A-F]/[a-f]/;
        $mac =~ s/(\w{4})/$1\./g;
        chop($mac);

        if ((length($mac) == 4) || (length($mac) == 14)) {
            return $mac
        }
        else {
            return undef;
        }
    }
    else {
        return undef;
    }
}

#######################################################
# Clean up mac addresses and put them in windows format
# returns xx:xx:xx:xx:xx:xx
#######################################################
sub getIEEEMac {
    my ($mac) = @_;

    if ( $mac ) {
        $mac =~ s/(:|\.|\-|(^0x)|)//g;
        $mac =~ tr/[A-F]/[a-f]/;
        $mac =~ s/(\w{2})/$1\:/g;
        chop($mac);

        if ((length($mac) == 4) || (length($mac) == 17)) {
            return $mac
        }
        else {
            return undef;
        }
    }
    else {
        return undef;
    }
}

# Gets mac in xx-xx-xx-xx-xx-xx format
sub getDashMac {
    my ($mac) = @_;

    if ( $mac ) {
        $mac =~ s/(:|\.|\-|(^0x)|)//g;
        $mac =~ tr/[A-F]/[a-f]/;
        $mac =~ s/(\w{2})/$1\-/g;
        chop($mac);

        if ((length($mac) == 4) || (length($mac) == 17)) {
            return $mac
        }
        else {
            return undef;
        }
    }
    else {
        return undef;
    }
}

# Get the shortened format of any V6 Address
sub shortenV6 {
    my $netdbBulk_ref = shift;
    my @netdbBulk = @$netdbBulk_ref;

    foreach my $ipref ( @netdbBulk ) {

    # ip field shorten
    if ( length ( $$ipref{ip} ) == 32 ) {
        $$ipref{ip} =~ s/(\w\w\w\w)/$1\:/g;
        chop( $$ipref{ip} );

        my $v6obj = new Net::IP ($$ipref{ip}) || next;
        $$ipref{ip} = $v6obj->short();
    }

    my $l = length( $$ipref{lastip} );

    # lastip field
    if ( length ( $$ipref{lastip} ) == 32 ) {
            $$ipref{lastip} =~ s/(\w\w\w\w)/$1\:/g;
            chop( $$ipref{lastip} );

            my $v6obj = new Net::IP ($$ipref{lastip}) || next;
            $$ipref{lastip} = $v6obj->short();
        }
    }
    return \@netdbBulk;
}

# Cross reference data from other fields and overwrite some values based on priority of information
sub fixupSwitchports {
    my $netdbBulk_ref = shift;
    my @netdbBulk = @$netdbBulk_ref;

    foreach my $swref ( @netdbBulk ) {
        # Wifi entry
        if ( $$swref{vlan} eq 'wifi' || !$$swref{vlan} ) {
            $$swref{vlan} = $$swref{s_vlan} if $$swref{s_vlan};
            $$swref{status} = $$swref{s_speed} if $$swref{s_speed};
            $$swref{wifi} = 1;
        }
        # Basic overrides
        else {
            # If parent port is a trunk port, reflect that vlan is tagged
            if ( $$swref{vlan} eq 'trunk' ) {
                $$swref{vlan} = "$$swref{s_vlan}(t)" if $$swref{s_vlan};
            }
            # "If there is a mismatch between the parent port vlan id and the mac on the vlan, star it (voice usually)
            elsif ( $$swref{s_vlan} && $$swref{s_vlan} ne $$swref{vlan} ) {
                $$swref{vlan} = "$$swref{s_vlan}(*)";
            }
            $$swref{speed} = $$swref{s_speed} if $$swref{s_speed};
        }
        # MAC Neighbor discovery
        $$swref{lastip} = $$swref{s_ip} if $$swref{s_ip};
        $$swref{n_host} = $$swref{mac_nd} if $$swref{mac_nd};
    }

    return \@netdbBulk;
} # END sub ficupSwitchports

####
# Sort a list by IP address if IP address is contained somewhere in the list
# Thanks to http://www.sysarch.com/Perl/sort_paper.html
####
sub sortIPList {
    my @sortlist = @_;

    @sortlist = sort {
    pack('C4' => $a =~
      /(\d+)\.(\d+)\.(\d+)\.(\d+)/)
    cmp
    pack('C4' => $b =~
      /(\d+)\.(\d+)\.(\d+)\.(\d+)/)
    } @sortlist;

    return @sortlist;
}

####
# Take in single hostname and return array of IPs
####
sub nameToIP {
    my $name = shift;

    my @addresses = gethostbyname($name);

    return @addresses;
}

####
# Pass in an array and it will translate all IP addresses in to hostnames and return the array
####
sub IPToName {
    my @ip_array = @_;
    my $i = 0;
    my $array_length = @ip_array;

    my $res_ref = Net::DNS::Resolver->new || die "Unable to create NetAddr::IP object\n";
    my $ip_ref = new NetAddr::IP "128.23.1.1" || die "Unable to create NetAddr::IP object\n";

    for ($i=0; $i < $array_length; $i++) {
        if ($ip_array[$i]) {
            #$ip_array[$i] =~ s/(\d+\.\d+\.\d+\.\d+)/&translate_ip_to_name($1, $res_ref, $ip_ref)/eg;
            $ip_array[$i] = translate_ip_to_name( $ip_array[$i], $res_ref, $ip_ref );
        }
    }

    return @ip_array;
}

####
# Don't call directly, used to lookup IP addresses
####
sub translate_ip_to_name {
    my ($ip_address, $res, $ip, ) = @_;

    $res->udp_timeout(2);
    $res->udppacketsize(1400); # To avoid long responses from locking up Net::DNS

    my $query = $res->search("$ip_address");
    if ($query) {
        foreach my $rr ($query->answer) {
            next unless $rr->type eq "PTR";
            return $rr->ptrdname;
        }
    }
    else {
        return $ip_address;
    }


}

# Convert minutes to human readable format
sub minutes2human {
    my $minutes = shift;
    my $secs = $minutes*60;

    if    ($secs >= 365*24*60*60) { return sprintf '%.2fyears', $secs/(365*24*60*60) }
    elsif ($secs >=     24*60*60) { return sprintf '%.1fdays', $secs/(    24*60*60) }
    elsif ($secs >=        60*60) { return sprintf '%.1fhours', $secs/(       60*60) }
    elsif ($secs >=           60) { return sprintf '%.1fmin', $secs/(          60) }
    else                          { return sprintf '%.1fsec', $secs                }
}


########################################
# Database Inserts and Updates Section #
########################################

# Insert Vlan Change (not used currently)
sub insertVlanChange {
    $dbh = shift;
    my $netdbentry_ref = shift;
    # Dereference %netdbentry
    my %netdbentry = %$netdbentry_ref;

    my $switch        = $netdbentry{"switch"};
    my $port          = $netdbentry{"port"};
    my $vlan          = $netdbentry{"vlan"};
    my $username      = $netdbentry{"username"};
    my $ip            = $netdbentry{"ip"};
    my $changetype    = $netdbentry{"changetype"};
    my $timestamp     = getDate();

    if ( !$switch || !$port || !$vlan || !$changetype ) {
        croak ("Must supply switch, port, vlan, changetype");
    }
    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }
    $insertVLANCHANGE_h->execute( $switch, $port, $vlan, $username, $ip, $changetype, $timestamp );
}

# Record query transaction
sub insertTransaction {
    $dbh = shift;
    my $netdbentry_ref = shift;
    # Dereference %netdbentry
    my %netdbentry = %$netdbentry_ref;

    my $id            = getTransactionID();
    my $ip            = $netdbentry{"ip"};
    my $username      = $netdbentry{"username"};
    my $querytype     = $netdbentry{"querytype"};
    my $queryvalue    = $netdbentry{"queryvalue"};
    my $querydays     = $netdbentry{"querydays"};

    my $timestamp = getDate();

    if ( !$id || !$ip || !$username || !$querytype || !$queryvalue ) {
        croak ("Must supply id($id), ip($ip), username($username), querydays($querydays), queryvalue($queryvalue) and querytype($querytype)");
    }
    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
        $selectIP_h = undef; # Bug Fix Need to reset the SQL handlers after a transaction
                             # messes up $search_dt initialzing the handlers
    }

    my $success = 1;
    $success = $insertTransaction_h->execute( $id, $ip, $username, $querytype, $queryvalue, $querydays, $timestamp );
    logErrorMessage( "Database Error: $DBI::errstr" ) if !$success;

    return $id;
}

# Update the NAC role for a device for instant updates
sub updateNACRole {
    my $dbh = shift;
    my $mac = shift;
    my $role = shift;

    $mac = getCiscoMac( $mac );
    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }
    if ( !$mac || !$role ) {
        croak( "Must Supply mac and role" );
    }

    my $success = 1;
    my $updateNACRole_h;
    my $updateNACRole_h_string = "UPDATE nacreg SET role=? WHERE mac=?";
    $updateNACRole_h = $dbh->prepare( $updateNACRole_h_string );

    $success = $updateNACRole_h->execute( $role, $mac );
    logErrorMessage( "Database Error: $DBI::errstr" ) if !$success;

    return;
}

# Update the description on a port
sub updateDescription {
    my $dbh = shift;
    my $switch = shift;
    my $port = shift;
    my $description = shift;

    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }
    if ( !$description ) {
        croak( "Must Supply a switch, port and description" );
    }

    my $success = 1;
    my $updateDescription_h;
    my $updateDescription_h_string = "UPDATE switchstatus SET description=? WHERE switch=? AND port=?";
    $updateDescription_h = $dbh->prepare( $updateDescription_h_string );

    $success = $updateDescription_h->execute( $description, $switch, $port );
    logErrorMessage( "Database Error: $DBI::errstr" ) if !$success;

    return;
}

# Update the VLAN ID on a port (for instant updates in CGI)
sub updatePortVLAN {
    my $dbh = shift;
    my $switch = shift;
    my $port = shift;
    my $vlan = shift;

    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }
    if ( !$vlan ) {
        croak( "Must Supply a switch, port and description" );
    }

    my $success = 1;
    my $updatePortVLAN_h;
    my $updatePortVLAN_h_string = "UPDATE switchstatus SET vlan=? WHERE switch=? AND port=?";
    $updatePortVLAN_h = $dbh->prepare( $updatePortVLAN_h_string );

    $success = $updatePortVLAN_h->execute( $vlan, $switch, $port );
    logErrorMessage( "Database Error: $DBI::errstr" ) if !$success;

    return;
}

# Interates switch status update, removes old switches from status table
sub bulkUpdateSwitchStatus {
    my $dbh = shift;
    my $netdbBulk_ref = shift;
    my $lastseen  = getDate();
    my $dateCount = 0;

    # Dereference array of hashrefs
    my @netdbBulk = @$netdbBulk_ref;

    # Get length for loop
    my $netdbBulk_length = @netdbBulk;

    # Go through array of hashrefs and pass them to insertIPMAC
    for (my $i=0; $i < $netdbBulk_length; $i++) {
        insertSwitchStatus( $dbh, $netdbBulk[$i], $lastseen );
    }

    # Delete Old Status Entries from over a week ago
    my $l_maxSwitchAge = $maxSwitchAge * 24;        # Convert to hour format
    my $weekold_dt  = getDate( $l_maxSwitchAge );

    my $deleteOldStatus_h = $dbh->prepare("DELETE FROM switchstatus WHERE lastseen < '$weekold_dt'");
    $deleteOldStatus_h->execute();
}


# Updates table switchstatus which contains switch,port,vlan,status,lastseen
#
sub insertSwitchStatus {
    $dbh = shift;
    my $netdbentry_ref = shift;
    my $lastseen = shift;
    # Dereference %netdbentry
    my %netdbentry = %$netdbentry_ref;

    my $switch   = $netdbentry{"switch"};
    my $port     = $netdbentry{"port"};
    my $vlan     = $netdbentry{"vlan"};
    my $status   = $netdbentry{"status"};
    my $speed    = $netdbentry{"speed"};
    my $duplex   = $netdbentry{"duplex"};
    my $desc     = $netdbentry{"description"};

    my $row = "";
    my ( $old_pe, $old_re ); #SQL variables to be saved to restore

    if ( !$switch || !$port || !$vlan || !$status ) {
        croak ("Must supply switch port, portvlan and portstatus, check your input");
    }

    print "Entry: $switch, $port, $vlan, $status, $speed, $duplex\n" if $DEBUG>1;
    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }

    # Rolls back all changes if anything goes wrong
    $useDBTransactions = undef;

    if ( $useDBTransactions ) {
        $old_pe = $dbh->{PrintError}; # save and reset
        $old_re = $dbh->{RaiseError}; # error-handling
        $dbh->{PrintError} = 0;    # attributes
        $dbh->{RaiseError} = 1;
        $dbh->{AutoCommit} = 0;    # disable auto-commit mode
    }

    #########################
    # Database update routine
    #########################
    $EVAL_ERROR = undef;
    eval {
        # Update/Insert MAC Table
        $selectSwitchStatus_h->execute( $switch, $port );
        $row = $selectSwitchStatus_h->fetchrow_hashref();

        # Entry Exists, update
        if ( $$row{"port"} ) {
            print "Record Exists in switchports: $$row{switch} $$row{port}\n" if $DEBUG>1;
            # If port is up, update lastup to current date, otherwise keep old date
            my $lastup = $$row{"lastup"};
            my $minutes = $$row{"p_minutes"};

            if ( $status eq "connected" ) {
                $lastup = $lastseen;
                # Add update_interval to minute counter
                $minutes = $minutes + $update_interval;
            }
            my $uptime = minutes2human( $minutes );
            $success = 1;
            $success = $updateSwitchStatus_h->execute( $vlan, $status, $speed, $duplex, $desc, $lastseen, $lastup, $minutes, $uptime, $switch, $port );
            croak ("Update Failure in mac: $DBI::errstr\n") if !$success;
            print "Single switchstatus Update: $vlan, $status, $switch, $port, $desc, $lastseen, $lastup, $minutes, $uptime\n" if $DEBUG>1;
        }
        else {
            $success = 1;
            # Update lastup if port is up, otherwise leave null
            my $lastup = undef;
            my $minutes = undef;
            if ( $status eq "connected" ) {
                $lastup = $lastseen;
                $minutes = $update_interval;
            }
            my $uptime = minutes2human( $minutes );
            $insertSwitchStatus_h->execute( $switch, $port, $vlan, $status, $speed, $duplex, $desc, $lastseen, $lastup, $minutes, $uptime );
            croak ("Insert Failure in mac: $DBI::errstr\n") if !$success;
            print "|DEBUG|: Inserted switchstatus: switch:$switch, port:$port, ".
                  "vlan:$vlan, lastup:$lastup, status:$status, speed:$speed, ".
                  "duplex:$duplex, desc:$desc IN switchstatus table\n" if $DEBUG;
        }
    };
    if ( $useDBTransactions ) {
        if ( $EVAL_ERROR ) {      # Transaction Failed
            $dbh->rollback();    # rollback if transaction failed
            logErrorMessage( "Database Error: Transaction failed: $EVAL_ERROR" );
        }
        $dbh->{AutoCommit} = 1;    # restore auto-commit mode
        $dbh->{PrintError} = $old_pe; # restore error attributes
        $dbh->{RaiseError} = $old_re;
    }
}

## Bulk Insert Neighbor Data
sub bulkInsertND {
    my $dbh = shift;
    my $netdbBulk_ref = shift;
    my $lastseen  = getDate();
    my $dateCount = 0;

    # Dereference array of hashrefs
    my @netdbBulk = @$netdbBulk_ref;

    # Get length for loop
    my $netdbBulk_length = @netdbBulk;

    # Go through array of hashrefs and pass them to insertIPMAC
    for (my $i=0; $i < $netdbBulk_length; $i++) {
        # Insert entry in to database
        insertND( $dbh, $netdbBulk[$i], $lastseen );
    }
    # Delete Old ND Entries from over a week ago
    my $l_maxSwitchAge = $maxSwitchAge * 24;        # Convert to hour format
    my $weekold_dt  = getDate( $l_maxSwitchAge );

    my $deleteOldStatus_h = $dbh->prepare("DELETE FROM neighbor WHERE n_lastseen < '$weekold_dt'");
    $deleteOldStatus_h->execute();
}

## Insert Neighbor Entry in to Database
sub insertND {
    $dbh = shift;
    my $netdbentry_ref = shift;
    my $lastseen = shift;
    # Dereference %netdbentry
    my %netdbentry = %$netdbentry_ref;

    my $switch     = $netdbentry{"switch"};
    my $port       = $netdbentry{"port"};
    my $n_host     = $netdbentry{"n_host"};
    my $n_ip       = $netdbentry{"n_ip"};
    my $n_desc     = $netdbentry{"n_desc"};
    my $n_model    = $netdbentry{"n_model"};
    my $n_port     = $netdbentry{"n_port"};
    my $n_protocol = $netdbentry{"n_protocol"};

    # Normalize ports (deprecated, scraper responsibility)
    #$port = normalizePort( $port );
    #$n_port = normalizePort( $n_port );
    my $row = "";
    my ( $old_pe, $old_re ); #SQL variables to be saved to restore

    if ( !$switch || !$port || !$n_host ) {
        croak ("insertND: Must supply switch port, and n_host, check your input");
    }
    print "Entry: $switch, $port, $n_host, $n_ip, $n_model, $n_port, $n_protocol\n" if $DEBUG>1;
    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }
    # Rolls back all changes if anything goes wrong
    $useDBTransactions = undef;

    if ( $useDBTransactions ) {
        $old_pe = $dbh->{PrintError}; # save and reset
        $old_re = $dbh->{RaiseError}; # error-handling
        $dbh->{PrintError} = 0;    # attributes
        $dbh->{RaiseError} = 1;
        $dbh->{AutoCommit} = 0;    # disable auto-commit mode
    }

    #########################
    # Database update routine
    #########################
    $EVAL_ERROR = undef;
    eval {
        # Update/Insert MAC Table
        $selectSwitchStatus_h->execute( $switch, $port );
        $row = $selectSwitchStatus_h->fetchrow_hashref();

        # Check for status table entry
        if ( !$$row{"port"} ) {
            logErrorMessage( "Neighbor Discovery Warning: Switch and port not found in switchstatus table: $switch,$port" ) if $DEBUG;
            return;
        }
        # Check for existing neighbor entry
        $selectND_h->execute( $switch, $port );
        $row = $selectND_h->fetchrow_hashref();
        # Entry exists, update entry
        if ( $$row{"port"} ) {
            $success = 1;
            $success = $updateND_h->execute( $n_host, $n_ip, $n_desc, $n_model, $n_port, $n_protocol, $lastseen, $switch, $port );
            croak ("Update Failure in ND: $DBI::errstr\n") if !$success;

            print "Single neighbor update: $switch, $port, $n_host, $n_ip, $n_model, $n_port, $n_protocol\n" if $DEBUG>1;
        }
        # Entry does not exist, insert new entry
        else {
            $success = 1;
            $success = $insertND_h->execute( $switch, $port, $n_host, $n_ip, $n_desc, $n_model, $n_port, $n_protocol, $lastseen );
            croak ("Update Failure in ND: $DBI::errstr\n") if !$success;

            print "Single neighbor insert: $switch, $port, $n_host, $n_ip, $n_model, $n_port, $n_protocol\n" if $DEBUG;
        }
    };

    if ( $useDBTransactions ) {
        if ( $EVAL_ERROR ) {      # Transaction Failed
            $dbh->rollback();    # rollback if transaction failed
            logErrorMessage( "Database Error: Transaction failed: $EVAL_ERROR" );
        }
        $dbh->{AutoCommit} = 1;    # restore auto-commit mode
        $dbh->{PrintError} = $old_pe; # restore error attributes
        $dbh->{RaiseError} = $old_re;
    }
}

######################################
# Bulk updates the switchports table #
######################################
sub bulkUpdateMac {
    $dbh = shift;
    my $netdbBulk_ref = shift;
    my $lastseen  = getDate();
    my $dateCount = 0;

    # Update Vendor Cache Database from file
    Net::MAC::Vendor::load_cache( $ouidb );
    # Dereference array of hashrefs
    my @netdbBulk = @$netdbBulk_ref;
    # Get length for loop
    my $netdbBulk_length = @netdbBulk;
    # Go through array of hashrefs and pass them to insertIPMAC
    for (my $i=0; $i < $netdbBulk_length; $i++) {
        insertMAC( $dbh, $netdbBulk[$i], $lastseen );
    }
}

#######################################
# Inserts in to the switchports table #
#######################################
sub insertMAC {
    $dbh = shift;
    my $netdbentry_ref = shift;
    my $lastseen = shift;

    # Dereference %netdbentry
    my %netdbentry = %$netdbentry_ref;

    my $mac     = $netdbentry{"mac"};
    my $switch  = $netdbentry{"switch"};
    my $port    = $netdbentry{"port"};
    my $type    = $netdbentry{"type"};
    my $s_vlan  = $netdbentry{"s_vlan"};
    my $s_ip    = $netdbentry{"s_ip"};
    my $s_name  = $netdbentry{"s_name"};;
    my $s_speed = $netdbentry{"s_speed"};
    my $mac_nd  = $netdbentry{"mac_nd"};
    my $vendor;

    my $row = "";
    my ( $old_pe, $old_re ); #SQL variables to be saved to restore

    # Format mac address in cisco format, returns null if input is corrupted
    $mac = getCiscoMac($mac);

    if ( !$mac || !$switch || !$port ) {
        print STDERR "insertMAC: Must supply mac address ($mac), switch($switch) and port($port), check your input\n";
        return;
    }
    print "Entry: $mac, $switch, $port\n" if $DEBUG>1;
    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }
    # Rolls back all changes if anything goes wrong
    if ( $useDBTransactions ) {
        $old_pe = $dbh->{PrintError}; # save and reset
        $old_re = $dbh->{RaiseError}; # error-handling
        $dbh->{PrintError} = 0;    # attributes
        $dbh->{RaiseError} = 1;
        $dbh->{AutoCommit} = 0;    # disable auto-commit mode
    }

    ## If s_ip is null, try to get latest IP from lastip in mac table to store
    ## statically with switch entry along with hostname
    if ( !$s_ip ) {
        my $mac_ref = getMAC( $dbh, $mac );
        # Entry exists
        if ( $$mac_ref[0]{mac} && $$mac_ref[0]{lastip} ) {
            # Check to see if current IP is within the hour
            my @ipdate = split( /\s/, $$mac_ref[0]{lastipseen} );
            my @dt = split( /\:/, $ipdate[1] );

            my @today = split( /T/, $lastseen );
            my @now = split( /\:/, $ipdate[1] );
            #print "date: $ipdate[0] $today[0] $dt[0] $now[0]\n";

            if ( ( $ipdate[0] eq $today[0] ) && ( $dt[0] == $now[0] ) ) {
        	    #print "Accepted s_ip: $mac,$switch,$port,$s_ip,$$mac_ref[0]{lastipseen}\n";
        	    $s_ip = $$mac_ref[0]{lastip};
        	    $s_name = $$mac_ref[0]{name};
            }
            else {
        	    print "Rejected s_ip update: $mac,$switch,$port,$s_ip,$$mac_ref[0]{lastipseen}\n" if $DEBUG>1;
        	    $s_ip = $$mac_ref[0]{s_ip};
                $s_name = $$mac_ref[0]{s_name};
            }
        }
    }

    #########################
    # Database update routine
    #########################
    $EVAL_ERROR = undef;
    eval {
        # Update/Insert MAC Table
        $selectMAC_h->execute( $mac );
        $row = $selectMAC_h->fetchrow_hashref();

        #############
        # mac table #
        #############
        if ( $$row{"mac"} ) {
            print "Record Exists in mac: $$row{mac}\n" if $DEBUG>1;
            # Update vendor code
            $vendor = $$row{"vendor"};
            if ( !$vendor ) {
                my $winmac = getIEEEMac( $mac );
                my $vendor_ref = Net::MAC::Vendor::fetch_oui_from_cache( $winmac );
                $vendor = $$vendor_ref[0];
            }
            $success = 1;
            $success = $updateMACSwitchport_h->execute( $switch, $port, $vendor, $mac_nd, $lastseen, $mac );
            die ("Update Failure in mac for $mac: $DBI::errstr\n") if !$success;
        }
        # Insert new entry in mac table
        else {
            # Vendor code lookup
            my $winmac = getIEEEMac( $mac );
            my $vendor_ref = Net::MAC::Vendor::fetch_oui_from_cache( $winmac );
            $vendor = $$vendor_ref[0];
            $success = 1;
            $insertMACSwitchport_h->execute( $mac, $switch, $port, $vendor, $mac_nd, $lastseen, $lastseen );
            die ("Insert Failure in mac: $DBI::errstr\n") if !$success;

            print "|DEBUG|: Inserted: $mac, $switch, $port, $vendor, $mac_nd, $lastseen, $lastseen IN mac table\n" if $DEBUG;
        }
        #####################
        # Switchports table #
        #####################
        $selectSwitchports_h->execute( $mac, $switch, $port );
        $row = $selectSwitchports_h->fetchrow_hashref();
        # Update switchports info
        if ( $$row{"mac"} ) {
            # Add update_interval to minute counter
            my $minutes = $$row{"minutes"} + $update_interval;
            # Human readable uptime
            my $uptime = minutes2human( $minutes );

            print "Updating Record: $lastseen, $type, $minutes, $uptime, $s_vlan, $s_ip, $s_name, $s_speed, $mac, $switch, $port\n" if $DEBUG>1;
            $success = 1;
            $success = $updateSwitchports_h->execute( $lastseen, $type, $minutes, $uptime, $s_vlan, $s_ip, $s_name, $s_speed, $mac, $switch, $port );
            die ("Update Failure in mac for $mac: $DBI::errstr\n") if !$success;
        }
        # Insert new switchports entry
        else {
            my $uptime = minutes2human( $update_interval );
            print "|DEBUG|: Inserting: $mac, $switch, $port, $type, ".
                  "$update_interval, $uptime, $s_vlan, $s_ip, $s_name, $s_speed, ".
                  "$lastseen, $lastseen IN switchports\n" if $DEBUG>1;
            $success = 1;
            $insertSwitchports_h->execute( $mac, $switch, $port, $type,
                                           $update_interval, $uptime, $s_vlan,
                                           $s_ip, $s_name, $s_speed, $lastseen, $lastseen);
            die ("Insert Failure in mac for $mac: $DBI::errstr\n") if !$success;

            print "|DEBUG|: Inserted $mac, $switch, $port, $type, ".
                  "$update_interval, $uptime, $s_vlan, $s_ip, $s_speed, ".
                  "$lastseen, $lastseen IN switchports\n" if $DEBUG;
        }
        # Commit changes to database
        $dbh->commit() if $useDBTransactions;
    };
    if ( $useDBTransactions ) {
        if ( $EVAL_ERROR ) {    # Transaction Failed
            $dbh->rollback();   # rollback if transaction failed
            logErrorMessage( "Database Transaction Error (MAC): $EVAL_ERROR" );
        }
        $dbh->{AutoCommit} = 1;    # restore auto-commit mode
        $dbh->{PrintError} = $old_pe; # restore error attributes
        $dbh->{RaiseError} = $old_re;
    }
}

# Bulk Insert, takes array of hashrefs
sub bulkInsertIPMAC {
    $dbh = shift;
    my $netdbBulk_ref = shift;
    my $forceHostnameUpdate = shift;
    my $lastseen  = getDate();
    my $dateCount = 0;

    # Update Vendor Cache Database from file
    Net::MAC::Vendor::load_cache( $ouidb );
    # Dereference array of hashrefs
    my @netdbBulk = @$netdbBulk_ref;
    # Get length for loop
    my $netdbBulk_length = @netdbBulk;
    # Go through array of hashrefs and pass them to insertIPMAC
    for (my $i=0; $i < $netdbBulk_length; $i++) {
        insertIPMAC( $dbh, $netdbBulk[$i], $forceHostnameUpdate, $lastseen );
    }
}

############################################################################
# Inserts or updates a single IP/MAC pair entry in the NetDB ipmacpair table
# Do Not Use for mass updates, use bulkInsertIPMAC
#
# Input: array with $dbh and $netdbentry_ref hash_ref
#
############################################################################
sub insertIPMAC {
    $dbh = shift;
    my $netdbentry_ref = shift;
    my $forceHostnameUpdate = shift;
    my $lastseen = shift;

    # Dereference %netdbentry
    my %netdbentry = %$netdbentry_ref;

    my $ip     = $netdbentry{"ip"};
    my $mac    = $netdbentry{"mac"};
    my $name   = $netdbentry{"name"};
    my $vrf    = $netdbentry{"vrf"};
    my $router = $netdbentry{"router"};
    # check?
    my $static    = $netdbentry{"static"};
    my $switch    = $netdbentry{"switch"};
    my $port      = $netdbentry{"port"};
    my $vlan      = $netdbentry{"vlan"};
    my $owner     = $netdbentry{"owner"};
    my $vendor;

    my $ipv6;
    my $v6obj;
    my $row = "";
    my ( $old_pe, $old_re ); #SQL variables to be saved to restore

    # Format mac address in cisco format, returns null if input is corrupted
    $mac = getCiscoMac($mac);

    # Make sure ip address is formatted correctly
    if ( $ip !~ /^(\d+)(\.\d+){3}$/ ) {
        # Check for IPv6 Address
        $v6obj = new Net::IP ($ip) || croak ("Bad IP Address Input for IPMAC: $ip\n");
        $ip = $v6obj->ip();
        # If V6 Address Returned, flag ipv6 and strip colons for input data, save formatted v6 address
        if ( $ip ) {
            $ipv6 = $ip;
            $ip =~ s/\://g;
            print "v6 matched: $ip\n" if $DEBUG > 3;
        }
        else {
            $ip = undef;
        }
    }
    # Strip off the Vlan text
    if ( $vlan =~ /Vlan\d+/) {
        $vlan =~ s/Vlan//;
    }
    elsif ( $vlan =~ /Vl\d+/ ) {
        $vlan =~ s/Vl//;
    }
    else {
        $vlan = undef;
    }

    if ( !$ip || !$mac || !$dbh ) {
    croak ("Must supply both a mac address and ip(v6) address, check your input: ip: $ip, mac:$mac");
    }
    print "|DEBUG|: Parsed Input: $ip, $mac, $lastseen\n" if $DEBUG>1;

    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }

    # Rolls back all changes if anything goes wrong
    if ( $useDBTransactions ) {
        $old_pe = $dbh->{PrintError}; # save and reset
        $old_re = $dbh->{RaiseError}; # error-handling
        $dbh->{PrintError} = 0;    # attributes
        $dbh->{RaiseError} = 1;
        $dbh->{AutoCommit} = 0;    # disable auto-commit mode
    }

    # Can set static if desired, otherwise it will use the existing entry
    $static = 1 if $static;

    #########################
    # Database update routine
    #########################
    $EVAL_ERROR = undef;
    eval {
        # Check IP Table First
        $selectIP_h->execute( $ip );
        $row = $selectIP_h->fetchrow_hashref();
        if ( $$row{"ip"} ) {
            print "Record Exists in ip: $$row{ip}\n" if $DEBUG>1;
            $static = $$row{"static"} if !$static;
            $success = 1;
            $success = $updateIP_h->execute( $static, $mac, $ip );
            die ("Update Failure in ip for $ip: $DBI::errstr\n") if !$success;
        }
        else {
            $success = 1;
            $insertIP_h->execute( $ip, $static, $mac );
            die ("Insert Failure in ip for $ip: $DBI::errstr\n") if !$success;
            print "|DEBUG|: Inserted: ip:$ip, mac:$mac, static:$static IN ip table\n" if $DEBUG>1;
        }
        # Check MAC Table
        $selectMAC_h->execute( $mac );
        $row = $selectMAC_h->fetchrow_hashref();

        if ( $$row{"mac"} ) {
            print "Record Exists in mac: $$row{mac}\n" if $DEBUG>1;
            # Update vendor code
            $vendor = $$row{"vendor"};
            if ( !$vendor ) {
                my $winmac = getIEEEMac( $mac );
                my $vendor_ref = Net::MAC::Vendor::fetch_oui_from_cache( $winmac );
                $vendor = $$vendor_ref[0];
            }
            $success = 1;
            $success = $updateMAC_h->execute( $ip, $vendor, $lastseen, $lastseen, $mac );
            die ("Update Failure in mac for $mac: $DBI::errstr\n") if !$success;
        }
        # Insert new entry in to mac table
        else {
            #Get Vendor Code
            my $winmac = getIEEEMac( $mac );
            my $vendor_ref = Net::MAC::Vendor::fetch_oui_from_cache( $winmac );
            $vendor = $$vendor_ref[0];
            $success = 1;
            $insertMAC_h->execute( $mac, $ip, $vendor, $lastseen, $lastseen, $lastseen );
            die ("Insert Failure in mac for $mac: $DBI::errstr\n") if !$success;
            print "|DEBUG|: Inserted: ip:$ip, mac:$mac, vendor:$vendor IN mac table\n" if $DEBUG;
        }
        # Finally Check ipmac table
        $selectIPMACPair_h->execute( $ip, $mac );
        $row = $selectIPMACPair_h->fetchrow_hashref();

        # Record exists, update lastseen
        if ( $$row{"ip"} ) {
            print "Record Exists in ipmac, updating: $$row{ip} $$row{mac} $$row{firstseen} $$row{lastseen} $$row{vlan} $$row{vrf} $$row{router}\n\n" if $DEBUG>1;
            # Use existing static value if not hard setting
            $static = $$row{"static"} if !$static;
            # Update DNS
            if ( ( !$disable_DNS && ( $$row{"name"} =~ /^(\d+)(\.\d+){3}$/ || $$row{"name"} =~ /\w+:\w+:\w+:/ )
               || $forceHostnameUpdate ) ) {
                print "Debug: Updating DNS entry on $ip\n" if $DEBUG>1;
                # Check for IPv6 Lookup
                if ( $ipv6 ) {
                    if ( !$disable_v6_DNS ) {
                      ($name) = IPToName($ipv6);
                      if ( $name =~ /\w+:\w+:\w+:/ ) {
                          $name = $v6obj->short();
                      }
                   }
                }
                else {
                    ($name) = IPToName($ip);
                }
                print "Debug: DNS Results on $ip: $name\n" if $DEBUG>1;
            }
            else {
                $name = $$row{"name"};
            }
            # Make sure there are not duplicate IPMAC pairs from ARP table
            # before updating minute counter by checking to see if lastseen is
            # the same as the current date
            my ( $minutes, $uptime );
            my $compare = $$row{lastseen};
            $compare =~ s/\s/T/;

            # First instance of IPMAC Pair
            if ( $compare ne $lastseen ) {
                # Add update_interval to minute counter
                $minutes = $$row{"ip_minutes"} + $update_interval;
                # Human readable uptime
                $uptime = minutes2human( $minutes );
            }
            # Duplicate IPMAC pair
            else {
                $minutes = $$row{"ip_minutes"};
                $uptime = $$row{"ip_uptime"};
                #print "lastseen: $$row{lastseen} getdate: $lastseen\n";
            }
            # Update
            $success = 1;
            $success = $updateIPMACPair_h->execute( $name, $lastseen, $minutes, $uptime, $vlan, $vrf, $router, $ip, $mac );
            die ("Update Failure in ipmac for $ip/$mac: $DBI::errstr\n") if !$success;
        }
        # Record does not exist, insert new record
        else {
            # Initial DNS lookup
            if ( !$disable_DNS ) {
                print "Debug: Updating DNS entry on $ip\n" if $DEBUG>1;
                # Check for IPv6 Lookup
                if ( $ipv6 ) {
                    ($name) = IPToName($ipv6);
                    # Shorten IPv6 name if no reverse entry
                    if ( $name =~ /\w+:\w+:\w+:/ ) {
                        $name = $v6obj->short();
                    }
                }
                else {
                    ($name) = IPToName($ip);
                }
                print "Debug: DNS Results on $ip: $name\n" if $DEBUG>1;
            }
            else {
                if ( $ipv6 ) {
                    $name = $v6obj->short();
                }
                else {
                    $name = $ip;
                }
            }
            # Setup minute counter
            my $minutes = $update_interval;
            # Human readable uptime
            my $uptime = minutes2human( $minutes );

            $success = 1;
            $insertIPMACPair_h->execute( $ip, $mac, $name, $lastseen, $lastseen, $minutes, $uptime, $vlan, $vrf, $router );
            die ("Insert Failure in ipmac for $ip/$mac: $DBI::errstr\n") if !$success;

            print "DEBUG: Inserted: ip:$ip, mac:$mac, name:$name, vlan:$vlan IN ipmac table\n" if $DEBUG;
        }
        # Commit changes to database
        $dbh->commit() if $useDBTransactions;
    };
    if ( $useDBTransactions ) {
        if ( $EVAL_ERROR ) {      # Transaction Failed
            $dbh->rollback();    # rollback if transaction failed
            logErrorMessage( "Database Transaction Error (IPMAC): $EVAL_ERROR" );
        }
        $dbh->{AutoCommit} = 1;    # restore auto-commit mode
        $dbh->{PrintError} = $old_pe; # restore error attributes
        $dbh->{RaiseError} = $old_re;
    }
}

# Bulk Insert, takes array of hashrefs
sub bulkInsertNACReg {
    $dbh = shift;
    my $netdbBulk_ref = shift;
    my $lastseen  = getDate();
    my $dateCount = 0;

    # Dereference array of hashrefs
    my @netdbBulk = @$netdbBulk_ref;

    # Get length for loop
    my $netdbBulk_length = @netdbBulk;

    # Go through array of hashrefs and pass them to insertNACReg
    for (my $i=0; $i < $netdbBulk_length; $i++) {
        insertNACReg( $dbh, $netdbBulk[$i], $lastseen );
    }
}

####################################################
# Inserts NAC registrations in to the nacreg table #
####################################################
sub insertNACReg {
    $dbh = shift;
    my $netdbentry_ref = shift;
    my $lastseen = shift;

    # Dereference %netdbentry
    my %netdbentry = %$netdbentry_ref;

    my $mac        = $netdbentry{"mac"};
    my $regtime    = $netdbentry{"time"};
    my $firstName  = $netdbentry{"firstName"};
    my $lastName   = $netdbentry{"lastName"};
    my $userID     = $netdbentry{"userID"};
    my $email      = $netdbentry{"email"};
    my $phone      = $netdbentry{"phone"};
    my $type       = $netdbentry{"type"};
    my $entity     = $netdbentry{"entity"};
    my $role       = $netdbentry{"role"};
    my $title      = $netdbentry{"title"};
    my $status     = $netdbentry{"status"};
    my $pod        = $netdbentry{"pod"};
    my $dbid       = $netdbentry{"dbid"};
    my $critical;


    $critical = 1 if ( $netdbentry{"critical"} eq "1" );

    my $row = "";
    my ( $old_pe, $old_re ); #SQL variables to be saved to restore
    # Format mac address in cisco format, returns null if input is corrupted
    $mac = getCiscoMac($mac);

    if ( !$regtime ) {
        $regtime = $lastseen;
    }
    if ( !$mac || !$userID || !$regtime ) {
        print STDERR "insertNACReg: Must supply mac address ($mac), time($regtime) and userID($userID), check your input\n";
        return;
    }
    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }
    # Rolls back all changes if anything goes wrong
    if ( $useDBTransactions ) {
        $old_pe = $dbh->{PrintError}; # save and reset
        $old_re = $dbh->{RaiseError}; # error-handling
        $dbh->{PrintError} = 0;    # attributes
        $dbh->{RaiseError} = 1;
        $dbh->{AutoCommit} = 0;    # disable auto-commit mode
    }

    #########################
    # Database update routine
    #########################
    $EVAL_ERROR = undef;
    eval {
        # Make sure there is an entry in the mac address table already
        $selectMAC_h->execute( $mac );
        $row = $selectMAC_h->fetchrow_hashref();

        # Procede only if there is an entry in the main mac table already
        if ( $$row{"mac"} ) {
            print "Record Exists in mac, proceding with nacreg entry: $$row{mac}\n" if $DEBUG>1;
            # Find out if there is an existing registration
            $selectNACReg_h->execute( $mac );
            $row = $selectNACReg_h->fetchrow_hashref();

            # nacreg entry exists, update entry
            if ( $$row{"mac"} ) {
                my $reg = 1;
                # Only insert radius data if no existing registration data or in special cases, replace NAC data
                if ( $type =~ /Radius/ ) {
                    # If existing type is non-radius, check before inserting
                    if ( $$row{"type"} !~ /Radius/ ) {
                        # Unless NAC data is crap, skip this entry
                        if ( $$row{"userID"} !~ /nac\-\w+|registered/ ) {
                            $reg = undef;
                            print "Found NAC Data when inserting radius entry, skipping insert: $$row{userID}\n" if $DEBUG>1;
                        }
                        else {
                            print "Found NAC Data with junk user data, replacing $$row{userID} with $userID\n" if $DEBUG;
                        }
                    }
                    # If existing entry type is Radius, save certain entries in case it has extra data from NAC
                    else {
                        $type = $$row{"type"};
                        $role = $$row{"role"};
                        $title = $$row{"title"};
                    }
                }

                # Check for existing Radius entry, replace with NAC data unless these cases exist
                elsif ( $$row{"type"} =~ /Radius/ ) {
                    # If NAC data is mostly junk, only partially update NAC entry to reflect NAC data
                    if ( $userID =~ /nac\-\w+|registered/ ) {
                        # Add NAC data to Radius entry
                        $type = "NAC User: $userID Type: $type / Radius Authentication";
                        # Use existing userID from Radius instead
                        $userID = $$row{"userID"};
                        # Wipe out other data
                        $firstName = undef;
                        $lastName = undef;
                        $email = undef;
                        print "Found Radius data when importing junk NAC data, selectively updating: $userID\n" if $DEBUG;
                    }
                }

                # Selectively insert NAC data based on rules above for Radius data
                if ( $reg ) {
                    print "Debug: Updating registration for $mac/$userID/$email in nacreg\n" if $DEBUG>1;
                    $success = 1;
                    $success = $updateNACReg_h->execute( $regtime, $firstName, $lastName, $userID, $email, $phone, $type, $entity, $critical, $role, $title, $status, $pod, $dbid, $mac );
                    die ("Update Failure in nacreg for $mac/$userID: $DBI::errstr\n") if !$success;
                }
            }
            # Insert a new nacreg entry
            else {
                print "Debug: Inserting registration for $mac/$userID in nacreg\n" if $DEBUG;
                $success = 1;
                $success = $insertNACReg_h->execute( $mac, $regtime, $firstName, $lastName, $userID, $email, $phone, $type, $entity, $critical, $role, $title, $status, $pod, $dbid );
                die ("Insert Failure in nacreg for $mac/$userID/$regtime: $DBI::errstr\n") if !$success;
            }
        }
        else {
            print "No mac record found in mac table for NAC registration: $mac/$userID/$regtime\n" if $DEBUG>1;
        }
        # Commit changes to database
        $dbh->commit() if $useDBTransactions;
    };
    if ( $useDBTransactions ) {
        if ( $EVAL_ERROR ) {      # Transaction Failed
            $dbh->rollback();    # rollback if transaction failed
            logErrorMessage( "Database Transaction Error (nacreg): $EVAL_ERROR" );
        }
        $dbh->{AutoCommit} = 1;    # restore auto-commit mode
        $dbh->{PrintError} = $old_pe; # restore error attributes
        $dbh->{RaiseError} = $old_re;
    }
}

sub bulkUpdateStatic {
    my $netdbBulk_ref;
    ($dbh, $netdbBulk_ref) = @_;

    # Dereference array of hashrefs
    my @netdbBulk = @$netdbBulk_ref;
    # Get length for loop
    my $netdbBulk_length = @netdbBulk;
    #Reset the status of all static addresses to 0
    resetStatics( $dbh );
    # Go through array of hashrefs and pass them to insertIPMAC
    for (my $i=0; $i < $netdbBulk_length; $i++) {
        updateStatic( $dbh, $netdbBulk[$i] );
    }
}

# Reset the static status of every IP to 0
sub resetStatics {
    $dbh = shift;
    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }
    # Update IP Table
    my $success = 1;
    $success = $resetIPStatic_h->execute();

    if ( !$success ) {
        logErrorMessage( "Database Error: Transaction failed: $DBI::errstr" );
        croak ( "Could not reset static address status: $DBI::errstr\n" );
    }
}

sub updateStatic {
    $dbh = shift;
    my $netdbentry_ref = shift;
    # Dereference %netdbentry
    my %netdbentry = %$netdbentry_ref;

    my $ip     = $netdbentry{"ip"};
    my $static   = $netdbentry{"static"};
    my $mac = undef;
    my ( $old_pe, $old_re ); #SQL variables to be saved to restore

    my $row = "";

    # Make sure ip address is formatted correctly
    if ( $ip !~ /^(\d+)(\.\d+){3}$/ ) {
        $ip = undef;
    }
    if ( !$ip || !$dbh ) {
        croak ("Must supply and ip address, check your input");
    }
    print "DEBUG: Parsed Input: $ip, $static\n" if $DEBUG>1;
    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }
    # Rolls back all changes if anything goes wrong
    if ( $useDBTransactions ) {
        $old_pe = $dbh->{PrintError}; # save and reset
        $old_re = $dbh->{RaiseError}; # error-handling
        $dbh->{PrintError} = 0;    # attributes
        $dbh->{RaiseError} = 1;
        $dbh->{AutoCommit} = 0;    # disable auto-commit mode
    }
    $EVAL_ERROR = undef;
    eval {
        # Update IP Table
        $selectIP_h->execute( $ip );
        $row = $selectIP_h->fetchrow_hashref();
        if ( $$row{"ip"} ) {
            print "Record Exists in ip: $$row{ip}\n" if $DEBUG>1;
            $mac = $$row{"lastmac"};

            $success = 1;
            $success = $updateIP_h->execute( $static, $mac, $ip );
            die ("Update Failure in ip for $ip: $DBI::errstr\n") if !$success;
        }
        else {
            $success = 1;
            $insertIP_h->execute( $ip, $static, $mac );
            die ("Insert Failure in ip for $ip: $DBI::errstr\n") if !$success;

            print "DEBUG: Inserted: ip:$ip, mac:$mac, static:$static IN ip table\n" if $DEBUG;
        }
        $dbh->commit() if $useDBTransactions;
    };
    if ( $useDBTransactions ) {
        if ( $EVAL_ERROR ) {      # Transaction Failed
            $dbh->rollback();    # rollback if transaction failed
            logErrorMessage( "Database Transaction Error (STATIC): $EVAL_ERROR" );
        }
        $dbh->{AutoCommit} = 1;    # restore auto-commit mode
        $dbh->{PrintError} = $old_pe; # restore error attributes
        $dbh->{RaiseError} = $old_re;
    }
}

# Insert Disabled Entry
sub insertDisabled {
    $dbh = shift;
    my $netdbentry_ref = shift;

    my %netdbentry = %$netdbentry_ref;

    my $mac     = $netdbentry{"mac"};
    my $distype = $netdbentry{"distype"};
    my $disuser = $netdbentry{"disuser"};
    my $disdata = $netdbentry{"disdata"};
    my $discase = $netdbentry{"discase"};
    my $severity  = $netdbentry{"severity"};
    my $disdate  = getDate();

    my $row;
    my ( $old_pe, $old_re ); #SQL variables to be saved to restore

    # Format mac address in cisco format, returns null if input is corrupted
    $mac = getCiscoMac($mac);
    if ( !$mac || !$distype || !$disuser ) {
        print STDERR "insertDisabled: Must supply mac address ($mac), distype($distype) and disuser($disuser), check your input\n";
        return;
    }
    print "Entry: $mac, $disdate, $distype, $disuser, $disdata, $discase\n" if $DEBUG>1;
    # Initialize queries if necessary
    if ( !$selectIP_h ) {
        prepareSQL();
    }
    # Rolls back all changes if anything goes wrong
    if ( $useDBTransactions ) {
        $old_pe = $dbh->{PrintError}; # save and reset
        $old_re = $dbh->{RaiseError}; # error-handling
        $dbh->{PrintError} = 0;    # attributes
        $dbh->{RaiseError} = 1;
        $dbh->{AutoCommit} = 0;    # disable auto-commit mode
    }

    $EVAL_ERROR = undef;
    eval {
        $selectDisabled_h->execute( $mac );
        $row = $selectDisabled_h->fetchrow_hashref();

        # If entry already exists, croak
        if ( $$row{"mac"} ) {
            croak( "MAC $mac already in disabled table, must remove first\n" );
        }
        # Insert new entry in to disabled table
        else {
            $insertDisabled_h->execute( $mac, $distype, $disuser, $disdata, $discase, $disdate, $severity );
        }
        $dbh->commit() if $useDBTransactions;
    };
    if ( $useDBTransactions ) {
        if ( $EVAL_ERROR ) {      # Transaction Failed
            $dbh->rollback();    # rollback if transaction failed
            logErrorMessage( "Database Transaction Error (DISABLED): $EVAL_ERROR" );
        }
        $dbh->{AutoCommit} = 1;    # restore auto-commit mode
        $dbh->{PrintError} = $old_pe; # restore error attributes
        $dbh->{RaiseError} = $old_re;
    }
}

##################
# Delete Methods #
##################

# Delete MAC addresses not seen in so many hours and associated switch and ARP entries
sub deleteMacs {
    $dbh          = shift;
    my $hours     = shift;
    my $confirmed = shift;
    my $ipfilter  = shift;

    my $row;
    my $counter = 0;
    my @netdbBulk;

    if ( !$hours || !$dbh ) {
        croak ("Must supply hours, check your input");
    }
    if ( !$ipfilter ) {
        $ipfilter = '%';
    }
    # Initialize Search hours before setting up queries
    if ( $hours ) {
        $search_dt = getDate( $hours );
    }
    print "Delete Datetime: $search_dt\n" if $DEBUG>1;
    # Initialize queries if necessary
    prepareSQL();
    # If no confirmation, just get the data to be deleted and return
    $selectDeleteMacs_h->execute( $ipfilter );

    while ( $row = $selectDeleteMacs_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }
    # If confirmed, delete the data from the database
    if ( $confirmed ) {
        print "Deleting MACs older than $search_dt from the database\n" if $DEBUG;
        $deleteMacs_h->execute( $ipfilter );
    }
    return \@netdbBulk;
}

# Delete ARP entries
sub deleteArp {
    $dbh          = shift;
    my $hours     = shift;
    my $confirmed = shift;
    my $ipfilter  = shift;

    my $row;
    my $counter = 0;
    my @netdbBulk;

    if ( !$hours || !$dbh ) {
        croak ("Must supply hours, check your input");
    }
    if ( !$ipfilter ) {
        $ipfilter = '%';
    }
    # Initialize Search hours before setting up queries
    if ( $hours ) {
        $search_dt = getDate( $hours );
    }
    print "Delete Datetime: $search_dt\n" if $DEBUG>1;
    # Initialize queries if necessary
    prepareSQL();
    # If no confirmation, just get the data to be deleted and return
    $selectDeleteArp_h->execute( $ipfilter );

    while ( $row = $selectDeleteArp_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }
    # If confirmed, delete the data from the database
    if ( $confirmed ) {
        print "Deleting ARP entries older than $search_dt from the database\n" if $DEBUG;
        $deleteArp_h->execute( $ipfilter );
    }
    return \@netdbBulk;
}

# Delete MAC addresses not seen in so many hours and associated switch and ARP entries
sub deleteSwitch {
    $dbh          = shift;
    my $hours     = shift;
    my $confirmed = shift;

    my $row;
    my $counter = 0;
    my @netdbBulk;

    if ( !$hours || !$dbh ) {
        croak ("Must supply hours, check your input");
    }
    # Initialize Search hours before setting up queries
    if ( $hours ) {
        $search_dt = getDate( $hours );
    }
    print "Delete Datetime: $search_dt\n" if $DEBUG>1;
    # Initialize queries if necessary
    prepareSQL();
    # If no confirmation, just get the data to be deleted and return
    $selectDeleteSwitch_h->execute();

    while ( $row = $selectDeleteSwitch_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }
    # If confirmed, delete the data from the database
    if ( $confirmed ) {
        print "Deleting Switch data older than $search_dt from the database\n" if $DEBUG;
        $deleteSwitch_h->execute();
    }
    return \@netdbBulk;
}

# Delete MAC addresses not seen in so many hours and associated switch and ARP entries
sub deleteWifi {
    $dbh          = shift;
    my $hours     = shift;
    my $confirmed = shift;

    my $row;
    my $counter = 0;
    my @netdbBulk;

    if ( !$hours || !$dbh ) {
        croak ("Must supply hours, check your input");
    }
    # Initialize Search hours before setting up queries
    if ( $hours ) {
        $search_dt = getDate( $hours );
    }
    print "Delete Datetime: $search_dt\n" if $DEBUG>1;
    # Initialize queries if necessary
    prepareSQL();
    # If no confirmation, just get the data to be deleted and return
    $selectDeleteWifi_h->execute();

    while ( $row = $selectDeleteWifi_h->fetchrow_hashref() ) {
        if ( $row ) {
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }
    # If confirmed, delete the data from the database
    if ( $confirmed ) {
        print "Deleting Wifi data older than $search_dt from the database\n" if $DEBUG;
        $deleteWifi_h->execute();
    }
    return \@netdbBulk;
}



# Delete disabled table entry for mac address
sub deleteDisabled {
    $dbh = shift;
    my $mac = shift;

    $mac = getCiscoMac($mac);
    if ( !$mac ) {
        print STDERR "deleteDisabled: Must supply mac address ($mac)";
        return;
    }
    prepareSQL();
    $deleteDisabled_h->execute( $mac );
    return;
}

# Drop all switch entries with this name
sub dropSwitch {
    $dbh = shift;
    my $switch = shift;

    my $dropSwitchStatus_h = $dbh->prepare( "DELETE FROM switchstatus where switch=?" );
    my $dropSwitchEntries_h = $dbh->prepare( "DELETE FROM switchports where switch=?" );

    $dropSwitchStatus_h->execute( $switch );
    $dropSwitchEntries_h->execute( $switch );
}

# Rename oldswitch to newswitch, check that newswitch name does not exist first
sub renameSwitch {
    $dbh = shift;
    my $oldSwitch = shift;
    my $newSwitch = shift;

    my $checkSwitchExists_h = $dbh->prepare( "SELECT * FROM switchstatus where switch=?" );
    $checkSwitchExists_h->execute( $newSwitch );

    #print "renaming $oldSwitch $newSwitch\n";

    my $row = $checkSwitchExists_h->fetchrow_hashref();
    if ( $row ) {
	croak( "Error: Can't rename $oldSwitch to $newSwitch, $newSwitch already exists in DB, drop it first" );
    }
    else {
	my $renameSwitchstatus_h = $dbh->prepare( "UPDATE switchstatus SET switch=? WHERE switch=?" );
	my $renameSwitchports_h  = $dbh->prepare( "UPDATE switchports SET switch=? WHERE switch=?" );
	$renameSwitchstatus_h->execute( $newSwitch, $oldSwitch );
	$renameSwitchports_h->execute( $newSwitch, $oldSwitch );
    }
}


###############################################
# Prepares SQL Queries on $dbh once connected #
###############################################
sub prepareSQL {
    print "Preparing SQL with Datetime: $search_dt\n" if $DEBUG>1;
    # Localize Strings
    # Statics in the table ip that have never had a mac address associated
    my $selectNeverSeen_h_string = "SELECT * FROM ip WHERE static='1' AND lastmac IS NULL";

    # Selects statics that have been seen in a certain time range
    my $selectLastSeen_h_string = "SELECT * FROM superarp WHERE ip=? AND mac=? AND lastseen < ?";

    # Get all IPs that a mac address has had
    my $SELECTipmacWHEREmac_h_string = "SELECT * FROM superarp WHERE mac=? AND lastseen > '$search_dt' ORDER BY lastseen";

    # Get all macs that an IP has had
    my $SELECTipmacWHEREip_h_string = "SELECT * FROM superarp WHERE ip like ? AND lastseen > '$search_dt' ORDER BY ip, lastseen";

    # Get all ipmac entries that a hostname wildcard had
    my $SELECTipmacWHEREname_h_string = "SELECT * FROM superarp WHERE lastseen > '$search_dt' AND name like ? ORDER BY name, lastseen";

    # Get all mac entries that match the last 4 digits of a quiery in so many days
    my $selectShortMAC_h_string = "SELECT * from supermac WHERE (mac like ? AND lastseen > '$search_dt') ORDER BY lastseen";

    # Get all NAC registrations for a user in so many days
    my $selectNACUser_h_string = "SELECT * from superarp WHERE lastseen > '$search_dt' AND userID=? ORDER BY lastseen";

    # Get all NAC supermac registrations for a user in so many days
    my $selectNACUserMAC_h_string = "SELECT * from supermac WHERE lastseen > '$search_dt' AND userID=? ORDER BY lastseen";

    # Get all entries at a vlan
    my $SELECTipmacWHEREvlan_h_string = "SELECT * FROM superarp WHERE vlan=? AND lastseen > '$search_dt' ORDER BY ip, lastseen";

    # Get all ports at a vlan, leave blank if nothing on the port newer than lastseen
    my $SELECTvlanstatusWHEREvlan_h_string =
    "SELECT switchstatus.switch,switchstatus.port,switchstatus.vlan,switchstatus.status,switchstatus.speed,switchstatus.duplex,switchstatus.description,switchstatus.p_uptime,switchstatus.p_minutes,switchstatus.lastup,superswitch.mac,superswitch.ip,superswitch.name,superswitch.static,superswitch.vendor,superswitch.vrf,superswitch.router,superswitch.uptime,superswitch.minutes,superswitch.firstseen,superswitch.lastseen,nacreg.userID,nacreg.firstName,nacreg.lastName,nd.n_host,nd.n_ip,nd.n_desc,nd.n_model,nd.n_port,nd.n_protocol,nd.n_lastseen
     FROM switchstatus LEFT OUTER JOIN neighbor as nd ON ( switchstatus.switch = nd.switch AND switchstatus.port = nd.port )
     LEFT OUTER JOIN superswitch ON switchstatus.switch = superswitch.switch AND switchstatus.port = superswitch.port AND superswitch.lastseen > '$search_dt'
     LEFT OUTER JOIN nacreg ON nacreg.mac = superswitch.mac WHERE (switchstatus.vlan=?) ORDER BY lastseen";

    # Used for building selectLastSeen ip and mac pairs
    my $selectSeen_h_string = "SELECT ip,lastmac FROM ip WHERE static='1' AND lastmac IS NOT NULL";

    # Used for vendor table lookups
    my $SELECTsupermacWHEREvendor_h_string = "SELECT * FROM supermac WHERE UPPER(vendor) like ? AND lastseen > '$search_dt' ORDER BY lastip";

    # Get new mac addresses from supermac view that have been first seen the the past $opthours
    my $SELECTsupermacWHEREfirstmac_h_string = "SELECT * FROM supermac WHERE firstseen > '$search_dt' ORDER BY lastip";

    # Switchport Report
    my $selectSwitchportsWHEREswitchport_h_string = "SELECT * FROM switchports WHERE switch=? AND port like ? AND lastseen > '$search_dt' ORDER BY port, lastseen";

    # Switch Report
    my $selectSwitchportsWHEREswitch_h_string = "SELECT * FROM switchports WHERE switch like ? AND lastseen > '$search_dt' ORDER BY lastseen";

    # Transactions
    my $selectTransaction_h_string = "SELECT * FROM transactions WHERE id=? AND time > '$search_dt'";
    my $selectTHistory_h_string    = "SELECT * FROM transactions WHERE time > '$search_dt' ORDER BY time";

    # Superswitch Report
    my $selectSuperswitch_h_string = "SELECT superswitch.*,neighbor.* FROM superswitch LEFT OUTER JOIN neighbor ON superswitch.switch = neighbor.switch AND superswitch.port = neighbor.port
                                      WHERE mac=? AND switch=? AND port=? AND lastseen > '$search_dt' ORDER BY lastseen";

    # Get's the switch status table and merges it with any recent (from lastdate) switchport entries, otherwise leaves the extra data blank
    my $selectSuperswitchWHEREswitch_h_string =
    "SELECT switchstatus.switch,switchstatus.port,switchstatus.vlan,switchstatus.status,switchstatus.speed,switchstatus.duplex,switchstatus.description,switchstatus.p_uptime,switchstatus.p_minutes,switchstatus.lastup,superswitch.mac,superswitch.ip,superswitch.s_ip,superswitch.s_name,superswitch.name,superswitch.static,superswitch.mac_nd,superswitch.vendor,superswitch.vrf,superswitch.router,superswitch.uptime,superswitch.minutes,superswitch.firstseen,superswitch.lastseen,nacreg.userID,nacreg.firstName,nacreg.lastName,nd.n_host,nd.n_ip,nd.n_desc,nd.n_model,nd.n_port,nd.n_protocol,nd.n_lastseen,superswitch.s_speed,superswitch.s_ip,superswitch.s_vlan
     FROM switchstatus LEFT OUTER JOIN superswitch ON switchstatus.switch = superswitch.switch AND switchstatus.port = superswitch.port AND superswitch.lastseen > '$search_dt'
     LEFT OUTER JOIN neighbor as nd ON ( switchstatus.switch = nd.switch AND switchstatus.port = nd.port )
     LEFT OUTER JOIN nacreg ON nacreg.mac = superswitch.mac
     WHERE (switchstatus.switch like ? AND switchstatus.port like ?) ORDER BY lastseen";

    # Same as above, but search for description instead of switch and port
    my $selectSuperswitchWHEREdesc_h_string =
    "SELECT switchstatus.switch,switchstatus.port,switchstatus.vlan,switchstatus.status,switchstatus.speed,switchstatus.duplex,switchstatus.description,switchstatus.p_uptime,switchstatus.p_minutes,switchstatus.lastup,superswitch.mac,superswitch.ip,superswitch.s_ip,superswitch.s_name,superswitch.name,superswitch.static,superswitch.mac_nd,superswitch.vendor,superswitch.vrf,superswitch.router,superswitch.uptime,superswitch.minutes,superswitch.firstseen,superswitch.lastseen,nacreg.userID,nacreg.firstName,nacreg.lastName,nd.n_host,nd.n_ip,nd.n_desc,nd.n_model,nd.n_port,nd.n_protocol,nd.n_lastseen,superswitch.s_speed,superswitch.s_ip,superswitch.s_vlan
     FROM switchstatus LEFT OUTER JOIN superswitch ON switchstatus.switch = superswitch.switch AND switchstatus.port = superswitch.port AND superswitch.lastseen > '$search_dt'
     LEFT OUTER JOIN neighbor as nd ON ( switchstatus.switch = nd.switch AND switchstatus.port = nd.port )
     LEFT OUTER JOIN nacreg ON nacreg.mac = superswitch.mac
     WHERE (switchstatus.description like ?) ORDER BY lastseen";

    # Get the current port status for a device, vlan data comes from current switchport status
    my $selectSuperswitchWHEREmac_h_string = "SELECT superswitch.*,switchstatus.vlan,switchstatus.status,switchstatus.speed,switchstatus.duplex,switchstatus.description,switchstatus.p_uptime,switchstatus.p_minutes,switchstatus.lastup,nacreg.userID,nacreg.firstName,nacreg.lastName,nd.n_host,nd.n_ip,nd.n_desc,nd.n_model,nd.n_port,nd.n_protocol,nd.n_lastseen
    FROM superswitch
    LEFT JOIN switchstatus ON (superswitch.switch=switchstatus.switch AND superswitch.port=switchstatus.port)
    LEFT JOIN neighbor AS nd ON (superswitch.switch= nd.switch AND superswitch.port= nd.port)
    LEFT OUTER JOIN nacreg ON (nacreg.mac = superswitch.mac) WHERE (superswitch.mac=? AND superswitch.lastseen > '$search_dt') ORDER BY lastseen";

    # OLD Superswitch statements that do not rely on the switchstatus tables
    if ( $no_switchstatus ) {
        $selectSuperswitchWHEREmac_h_string = "SELECT * FROM superswitch WHERE mac=? AND lastseen > '$search_dt' ORDER BY lastseen";
        $selectSuperswitchWHEREswitch_h_string = "SELECT * FROM superswitch WHERE switch=? AND port like ? AND lastseen > '$search_dt' ORDER BY port,lastseen";
    }

    # Delete Methods
    my $selectDeleteMacs_h_string   = "SELECT * FROM mac WHERE lastseen < '$search_dt' AND IFNULL(lastip,\"ABC\") like ? ORDER BY lastseen";
    my $deleteMacs_h_string         = "DELETE FROM mac WHERE lastseen < '$search_dt' AND IFNULL(lastip,\"ABC\") like ?";
    my $selectDeleteArp_h_string    = "SELECT * FROM ipmac WHERE lastseen < '$search_dt' AND ip like ? ORDER BY lastseen";
    my $deleteArp_h_string          = "DELETE FROM ipmac WHERE lastseen < '$search_dt' AND ip like ?";
    my $selectDeleteSwitch_h_string = "SELECT * FROM switchports WHERE lastseen < '$search_dt' AND type IS NULL ORDER BY lastseen";
    my $deleteSwitch_h_string       = "DELETE FROM switchports WHERE lastseen < '$search_dt' AND type IS NULL";
    my $selectDeleteWifi_h_string = "SELECT * FROM switchports WHERE lastseen < '$search_dt' AND type = 'wifi' ORDER BY lastseen";
    my $deleteWifi_h_string       = "DELETE FROM switchports WHERE lastseen < '$search_dt' AND type = 'wifi'";

    $selectNeverSeen_h = $dbh->prepare( $selectNeverSeen_h_string );
    $selectLastSeen_h =  $dbh->prepare( $selectLastSeen_h_string );
    $selectSeen_h =  $dbh->prepare( $selectSeen_h_string );

    $SELECTipmacWHEREmac_h =  $dbh->prepare( $SELECTipmacWHEREmac_h_string );
    $SELECTipmacWHEREip_h =  $dbh->prepare( $SELECTipmacWHEREip_h_string );
    $SELECTipmacWHEREname_h =  $dbh->prepare( $SELECTipmacWHEREname_h_string );
    $SELECTipmacWHEREvlan_h = $dbh->prepare( $SELECTipmacWHEREvlan_h_string );
    $selectShortMAC_h = $dbh->prepare( $selectShortMAC_h_string );
    $SELECTvlanstatusWHEREvlan_h = $dbh->prepare( $SELECTvlanstatusWHEREvlan_h_string );
    $SELECTsupermacWHEREfirstmac_h = $dbh->prepare( $SELECTsupermacWHEREfirstmac_h_string );

    $SELECTsupermacWHEREvendor_h = $dbh->prepare( $SELECTsupermacWHEREvendor_h_string );

    $insertMACSwitchport_h = $dbh->prepare( $insertMACSwitchport_h_string );
    $updateMACSwitchport_h = $dbh->prepare( $updateMACSwitchport_h_string );

    $selectSwitchports_h =  $dbh->prepare( $selectSwitchports_h_string );
    $updateSwitchports_h =  $dbh->prepare( $updateSwitchports_h_string );
    $insertSwitchports_h =  $dbh->prepare( $insertSwitchports_h_string );
    $selectSwitchportsWHEREmac_h =  $dbh->prepare( $selectSwitchportsWHEREmac_h_string );
    $selectSwitchportsWHEREswitchport_h = $dbh->prepare( $selectSwitchportsWHEREswitchport_h_string );
    $selectSwitchportsWHEREswitch_h = $dbh->prepare( $selectSwitchportsWHEREswitch_h_string );

    $selectSuperswitch_h =  $dbh->prepare( $selectSuperswitch_h_string );
    $selectSuperswitchWHEREmac_h =  $dbh->prepare( $selectSuperswitchWHEREmac_h_string );
    $selectSuperswitchWHEREswitch_h = $dbh->prepare( $selectSuperswitchWHEREswitch_h_string );
    $selectSuperswitchWHEREdesc_h = $dbh->prepare( $selectSuperswitchWHEREdesc_h_string );

    $selectSwitchStatus_h =  $dbh->prepare( $selectSwitchStatus_h_string );
    $updateSwitchStatus_h =  $dbh->prepare( $updateSwitchStatus_h_string );
    $insertSwitchStatus_h =  $dbh->prepare( $insertSwitchStatus_h_string );
    $selectSwitchStatusWHEREswitch_h =  $dbh->prepare( $selectSwitchStatusWHEREswitch_h_string );

    $selectND_h = $dbh->prepare( $selectND_h_string );
    $insertND_h = $dbh->prepare( $insertND_h_string );
    $updateND_h = $dbh->prepare( $updateND_h_string );

    $insertTransaction_h = $dbh->prepare( $insertTransaction_h_string );
    $selectTransaction_h = $dbh->prepare( $selectTransaction_h_string );
    $selectTHistory_h = $dbh->prepare( $selectTHistory_h_string );

    $selectIPMACPair_h = $dbh->prepare( $selectIPMACPair_h_string );
    $updateIPMACPair_h = $dbh->prepare( $updateIPMACPair_h_string );
    $insertIPMACPair_h = $dbh->prepare( $insertIPMACPair_h_string );

    $selectIP_h = $dbh->prepare( $selectIP_h_string );
    $updateIP_h = $dbh->prepare( $updateIP_h_string );
    $insertIP_h = $dbh->prepare( $insertIP_h_string );
    $resetIPStatic_h = $dbh->prepare( $resetIPStatic_h_string );

    $selectMAC_h = $dbh->prepare( $selectMAC_h_string );
    $updateMAC_h = $dbh->prepare( $updateMAC_h_string );
    $insertMAC_h = $dbh->prepare( $insertMAC_h_string );

    $selectSuperMAC_h = $dbh->prepare( $selectSuperMAC_h_string );

    $selectNACReg_h = $dbh->prepare( $selectNACReg_h_string );
    $selectNACUser_h = $dbh->prepare( $selectNACUser_h_string );
    $selectNACUserMAC_h = $dbh->prepare( $selectNACUserMAC_h_string );
    $insertNACReg_h = $dbh->prepare( $insertNACReg_h_string );
    $updateNACReg_h = $dbh->prepare( $updateNACReg_h_string );

    $selectDisabled_h = $dbh->prepare( $selectDisabled_h_string );
    $insertDisabled_h = $dbh->prepare( $insertDisabled_h_string );
    $deleteDisabled_h = $dbh->prepare( $deleteDisabled_h_string );

    $insertVLANCHANGE_h = $dbh->prepare( $insertVLANCHANGE_h_string );
    $selectVLANCHANGE_h = $dbh->prepare( $selectVLANCHANGE_h_string );

    $selectDeleteMacs_h = $dbh->prepare( $selectDeleteMacs_h_string );
    $deleteMacs_h       = $dbh->prepare( $deleteMacs_h_string );
    $selectDeleteArp_h = $dbh->prepare( $selectDeleteArp_h_string );
    $deleteArp_h       = $dbh->prepare( $deleteArp_h_string );
    $selectDeleteSwitch_h = $dbh->prepare( $selectDeleteSwitch_h_string );
    $deleteSwitch_h       = $dbh->prepare( $deleteSwitch_h_string );
    $selectDeleteWifi_h = $dbh->prepare( $selectDeleteWifi_h_string );
    $deleteWifi_h       = $dbh->prepare( $deleteWifi_h_string );
}

# Parse Configuration from file
sub parseConfig {
    # Create any variables that do not exist to avoid errors
    my $config = AppConfig->new({
        CREATE => 1,
                            });

    $config->define( "dbname=s", "dbhost=s", "dbuser=s", "dbpass=s", "dbuserRO=s", "dbpassRO=s", "ouifile=s",
             "error_log=s", "no_switchstatus=s", "debug=s", "mac_format=s", "disable_DNS=s", "max_switch_age=s",
             "disable_v6_DNS" );

    $config->define( "regex=s", "update_interval=s" );

    $config->file( "$config_file" );

    $dbname          = $config->dbname();     # DB Name
    $dbhost          = $config->dbhost();     # DB Host
    $dbuser          = $config->dbuser();     # DB Read/Write User
    $dbpass          = $config->dbpass();     # R/W Password
    $dbuserRO        = $config->dbuserRO();   # DB Read Only User
    $dbpassRO        = $config->dbpassRO();   # DB RO Password
    #$ouidb           = "file:/" . $config->ouifile(); # Always retured file not found and caused vendor import to fail
    $no_switchstatus = $config->no_switchstatus();
    $errlog          = $config->error_log();
    $regex           = $config->regex();
    $mac_format      = $config->mac_format();
    $disable_DNS     = $config->disable_DNS();
    $disable_v6_DNS  = $config->disable_v6_DNS();
    $maxSwitchAge    = $config->max_switch_age() if $config->max_switch_age();
    $update_interval = $config->update_interval() if $config->update_interval();

    # Configure the debug level
    if ( $config->debug() ) {
        processDebug( $config->debug() );
    }
}

# Match Config file debug level to library debug level (different than the rest of NetDB)
sub processDebug {
    my $cli_debug = shift;

    if ( $cli_debug > 2 ) {
        $DEBUG = 1;
        $printDBIErrors = 1;
    }
    if ( $cli_debug > 4 ) {
        $DEBUG = 2;
        $printDBIErrors = 1;
    }
}

# Log all errors to a file
sub logErrorMessage {
    my $message = shift;
    chomp( $message );

    my $timestamp = DateTime->now();
    my $tz = DateTime::TimeZone->new( name => 'local' );
    $timestamp->set_time_zone( $tz );
    $timestamp = $timestamp->strftime("%F %r");

    print STDERR "$timestamp: $message\n";

    eval {
        open ( my $ERRLOG, '>>', "$errlog" ) or croak "ERROR: Unable to write error to $errlog\n";
        print $ERRLOG "$timestamp: $message\n";
        close $ERRLOG;
    };
}

#
1;
