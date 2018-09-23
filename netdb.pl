#!/usr/bin/perl -w
##########################################################################
# netdb.pl - CLI Interface to query Network Tracking Database
# Author: Jonathan Yantis <yantisj@gmail.com>
# Copyright (C) 2014 Jonathan Yantis
##########################################################################
#
# Queries NetDB for information from the database
#
# All data passing and data types are built on an array of hashrefs,
# and array is always passed between subs as a reference.
#
# Relies on NetDB.pm module for all database access and queries.
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

# Used for development, work against the non-production NetDB library in 
# the current directory if available
use lib ".";
#print "\@INC is @INC\n";
use NetDB;
use Getopt::Long;
use Sys::Hostname;
use AppConfig;
use Time::HiRes qw (gettimeofday);
use strict;
use warnings;
# no nonsense
no warnings 'uninitialized';

my $netdbVer = 1;
my $netdbMinorVer = 13;
my $DEBUG;

my @netdbBulk;
my $transactionID;
my $transactions = 1;
my $starttime = [ Time::HiRes::gettimeofday( ) ];

my ( $optneverseen, $optstatic, $optdays, $optip, $optmac, $opthostname );
my ( $optvendorcode, $optport, $opthours, $optcsv, $optfile );
my ( $optvlanstatus, $optswitch, $optnewmacs, $optvlan, $opthistory, $optnt );
my ( $optmrtg, $optstats, $config_file, $optrootdir );
my ( $optuser, $mac_format, $optquote, $optswitchreport, $optDescription );

$config_file = "/etc/netdb.conf";

# Parse Configuration File
parseConfig();

# Input Options
if ( $ARGV[0] eq "" ) { &usage(); }

GetOptions(
    'us'    => \$optneverseen,
    's'    => \$optstatic,
    'd=i'  => \$optdays,
    'h=i'  => \$opthours,
    'i=s'  => \$optip,
    'm=s'  => \$optmac,
    'mf=s' => \$mac_format,
    'n=s'  => \$opthostname,
    'u=s'  => \$optuser,
    'p=s'  => \$optport,
    'sw=s' => \$optswitch,
    'ds=s' => \$optDescription,
    'up=s'   => \$optswitchreport,
    'vc=s' => \$optvendorcode,
    'vl=s' => \$optvlan,
    'vs=s' => \$optvlanstatus,
    'nm'   => \$optnewmacs,
    'mr'   => \$optmrtg,
    't'    => \$opthistory,
    'st'   => \$optstats,
    'nt'   => \$optnt,
    'f'    => \$optfile,
    'c'    => \$optcsv,
    'q'    => \$optquote,
    'conf=s' => \$config_file,
    'v'    => \$DEBUG,
    'vv'   => \$DEBUG,
          )
or &usage();

# Get database connection
my $dbh = connectDBro( $config_file );

# Library Version Check
my $libraryVersion = getVersion();
if ( $libraryVersion ne "$netdbVer.$netdbMinorVer" ) {
    print STDERR "WARNING: NetDB Library version v$libraryVersion mismatch with netdb.pl v$netdbVer.$netdbMinorVer\n";
}

# Convert all time to hours
if ( $optdays ) {
    $opthours = $opthours + $optdays*24;
}

# Set default time
if ( !$opthours && !$optstats) {
    $opthours = 7*24;   # 7 days search default
    $optdays = 7;
}

# If stats mode, go back 10 years
elsif( !$opthours && $optstats ) {
    $opthours = "100000";
}

# Don't record transaction for this command, used for scripts
if ( $optnt ) {
    $transactions = undef;
}

# Translate Mac Formats
if ( $mac_format ) {
    $mac_format = 'ieee_dash' if $mac_format eq 'dash';
    $mac_format = 'ieee_colon' if $mac_format eq 'colon';
    $mac_format = 'no_format' if $mac_format eq 'none';
}

# Get a list of statics that have never been seen
if ( $optneverseen ) {
    my $netdbPrint_ref = getNeverSeen( $dbh );
    
    # Sort by IP address
    $netdbPrint_ref = sortByIP( $netdbPrint_ref );

    # Dereference array of hashrefs
    my @netdbPrint = @$netdbPrint_ref;    

    # Get length for loop
    my $netdbPrint_length = @netdbPrint;

    # Go through array of hashrefs and pass them to insertIPMAC
    for (my $i=0; $i < $netdbPrint_length; $i++)
    {
        print "$netdbPrint[$i]{ip}\n";
    }
}

# Get a list of statics not seen in $opthours
elsif ( $optstatic && $opthours ) {
    my $netdb_ref = getLastSeen( $dbh, $opthours );
    printNetdbIPMAC( $netdb_ref );
}

# Get a list of mac entries at ip addresses
elsif ( $optip && $optfile ) {

    open( FILE, "$optip")
        or die "|ERROR|: Can not open $optip, error: $!\n";
    my $count=1;
    my @ipAdders;
    while (<FILE>) {
        # Skip line if line has a comment
        next if $_ =~ /^#/;
        # strip miscellaneous newlines
        $_ =~ s/[\r|\n]+//;
        # break up line if there is more than one address on the line
        my @line = split (/[,]|\s+/);

        foreach my $ip_adder (@line){
            if ($ip_adder){
                $ip_adder =~ s/\s+//;
                chomp($ip_adder);
                # Checks IPv4 first, assuuming thats where most will be
                if ( $ip_adder =~ /[0-9]{1,3}(\.[0-9]{1,3}){3}/ ){
                    print "|DEBUG|: Adding IPv4 address: $ip_adder\n" if $DEBUG>1;
                    push (@ipAdders, $ip_adder);
                }
                # Checks IPv6 (regexing this is crazy!)
                elsif ($ip_adder =~ /^(([A-Fa-f0-9]{1,4}:){7}[A-Fa-f0-9]{1,4})$|^([A-Fa-f0-9]{1,4}::([A-Fa-f0-9]{1,4}:){0,5}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){2}:([A-Fa-f0-9]{1,4}:){0,4}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){3}:([A-Fa-f0-9]{1,4}:){0,3}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){4}:([A-Fa-f0-9]{1,4}:){0,2}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){5}:([A-Fa-f0-9]{1,4}:){0,1}[A-Fa-f0-9]{1,4})$|^(([A-Fa-f0-9]{1,4}:){6}:[A-Fa-f0-9]{1,4})$/){
                    print "|DEBUG|: Adding IPv6 address: $ip_adder\n" if $DEBUG>1;
                    push (@ipAdders, $ip_adder);
                }
                else{
                    print "|DEBUG|: Invalid IP address found in the line\n" if $DEBUG;
                }
            } # END is there an IP
            $count++;
        } # END for breaks up line if there are multible IPs per line
    } # END while that reads in the CSV file
 
    $transactionID = recordTransaction( scalar(@ipAdders), 'IPs' ) if $transactions;
    my $netdb_ref = getMACsfromIPList( $dbh, \@ipAdders, $opthours );

    if ( $$netdb_ref[0]{"mac"} ) {
        ## get the switchport for each entry returned
        #$netdb_ref = getSwitchportList( $netdb_ref );
 
        printNetdbIPMACList( $netdb_ref );
 
        ## Print Registration Data if only one mac
        #getNACRegData( $$netdb_ref[0]{"mac"} ) if ( !$$netdb_ref[1] && $$netdb_ref[0] && $$netdb_ref[0]{"mac"} );
    }
    elsif ( $optdays ) {
        print "No records found in $optdays days.\n";
    }
    else {
    print "No records found\n";
    }
} # END if optip and optfile

# Get a list of mac entries at ip address
elsif ( $optip ) {
    $transactionID = recordTransaction( $optip, 'IP' ) if $transactions;

    my $netdb_ref = getMACsfromIP( $dbh, $optip, $opthours );

    if ( $$netdb_ref[0]{"mac"} ) {
	printNetdbIPMAC( $netdb_ref );
	
	# Print the switchport history if only one entry returned
	getSwitchport( $$netdb_ref[0]{"mac"} ) if ( !$$netdb_ref[1] && $$netdb_ref[0] && $$netdb_ref[0]{"mac"} );
	
	# Print Registration Data if only one mac
	getNACRegData( $$netdb_ref[0]{"mac"} ) if ( !$$netdb_ref[1] && $$netdb_ref[0] && $$netdb_ref[0]{"mac"} );

    }
    elsif ( $optdays ) {
	print "No records found in $optdays days.\n";
    }
    else {
	print "No records found\n";
    }
}


# Get a list of IPs entries at MAC addresses
elsif ( $optmac && $optfile ) {
    open( FILE, "$optmac")
        or die "|ERROR|: Can not open $optmac, error: $!\n";
    my $count=1;
    my @macAdders;
    while (<FILE>) {
        # Skip line if line has a comment
        next if $_ =~ /^#/;
        # strip miscellaneous newlines
        $_ =~ s/[\r|\n]+//;
        # break up line if there is more than one address on the line
        my @line = split (/[,]|\s+/);
 
        foreach my $mac_adder (@line){
            if ($mac_adder){
                $mac_adder =~ s/\s+//;
                chomp($mac_adder);
                # Checks : or - based MAC, assumeing it will be most likely
                if ( $mac_adder =~ /[A-Fa-f0-9]{2}([:|-][A-Fa-f0-9]{2}){5}/ ){
                    print "|DEBUG|: Adding IEEE MAC: $mac_adder\n" if $DEBUG>1;
                    push (@macAdders, $mac_adder);
                }
                elsif ( $mac_adder =~ /[A-Fa-f0-9]{4}(\.[A-Fa-f0-9]{4}){2}/ ){
                    print "|DEBUG|: Adding Cisco MAC: $mac_adder\n" if $DEBUG>1;
                    push (@macAdders, $mac_adder);
                }
                else{
                    print "|DEBUG|: Invalid MAC address found in the line\n" if $DEBUG;
                }
            } # END is there a MAC
            $count++;
        } # END for breaks up line if there are multible MACss per line
    } # END while that reads in the CSV file

    $transactionID = recordTransaction( scalar(@macAdders), 'MACs' ) if $transactions;
    my $netdb_ref;

    # Full mac address query
	$netdb_ref = getMACList( $dbh, \@macAdders, $opthours );

    if ( $$netdb_ref[0]{mac} ) {
        # get the switchport for each entry returned
        #$netdb_ref = getSwitchportList( $netdb_ref );

        printNetdbIPMACList( $netdb_ref );
    }
    elsif ( $optdays ) {
        print "No records found in $optdays days.\n";
    }
    else {
        print "No records found\n";
    }
}

# Get a list of ip entries at mac address
elsif ( $optmac ) {
    $transactionID = recordTransaction( $optmac, 'MAC' ) if $transactions;


    my $netdb_ref;
    my $short_mac;

    # Last 4 digits (ff:ff)
    if ( $optmac =~ /^\w\w\:\w\w$/ ) {
	$netdb_ref = getShortMAC( $dbh, $optmac, $opthours );
	$short_mac = $optmac;
	$optmac = $$netdb_ref[0]{"mac"};
    }

    # Mac Wildcard Search (55:55* or *55:55:55 etc)
    elsif ( $optmac =~ /^\w\w(\:\w\w){1,4}\*$/ || $optmac =~ /^\*(\w\w\:){1,4}\w\w$/ ) {
        $netdb_ref = getShortMAC( $dbh, $optmac, $opthours );
	$short_mac = $optmac;
        $optmac = $$netdb_ref[0]{"mac"};
    }

    # Full mac address query
    else {
	$netdb_ref = getMAC( $dbh, $optmac, $opthours );
    }

    if ( $$netdb_ref[0]{mac} ) {
	printNetdbMAC( $netdb_ref );
	
	# Make sure there are not multiple entries, print IP info
	if ( !$$netdb_ref[1] && $$netdb_ref[0] ) {
	    my $netdbip_ref = getIPsfromMAC( $dbh, $optmac, $opthours );
	    printNetdbIPMAC( $netdbip_ref );
	}
	# Print the switchport history if only one entry returned
	getSwitchport( $$netdb_ref[0]{"mac"} ) if ( !$$netdb_ref[1] && $$netdb_ref[0] );
	
	# Print registration data for a mac address search if one entry
	if ( !$$netdb_ref[1] ) {    
	    getNACRegData( $optmac );
	}
	
	if ( !$optcsv && $$netdb_ref[0]{distype} ) {
	    printDisabledinFormat( $netdb_ref );
	}

    }
    elsif ( $optdays ) {
        print "No records found in $optdays days.\n";
    }
    else {
	print "No records found\n";
    }
}

# Hostname Wildcard Search
elsif ( $opthostname ) {
    $transactionID = recordTransaction( $opthostname, 'Hostname' ) if $transactions;

    my $netdb_ref = getNamefromIPMAC( $dbh, $opthostname, $opthours );

    if ( $$netdb_ref[0]{mac} ) {

	printNetdbIPMAC( $netdb_ref );
	
	# Print the switchport history if only one entry returned
	getSwitchport( $$netdb_ref[0]{"mac"} ) if ( !$$netdb_ref[1] && $$netdb_ref[0] );
	
	# Print Registration Data if only one mac
	getNACRegData( $$netdb_ref[0]{"mac"} ) if ( !$$netdb_ref[1] && $$netdb_ref[0] );
    }
    elsif ( $optdays ) {
        print "No records found in $optdays days.\n";
    }
    else {
        print "No records found\n";
    }
}

# Get all ARP entries registered to a user
elsif ( $optuser ) {
    $transactionID = recordTransaction( $optuser, 'user' ) if $transactions;
    
    my $netdb_ref = getNACUserMAC( $dbh, $optuser, $opthours );
    printNetdbMAC( $netdb_ref );

    if ( !$optcsv ) {
	$netdb_ref = getNACUser( $dbh, $optuser, $opthours );
	printNetdbIPMAC( $netdb_ref );
    }
}

# Get everything related to a switch, and optional port after the comma
elsif ( $optswitch ) {
    $transactionID = recordTransaction( $optswitch, 'switchreport' ) if $transactions;

    my $netdb_ref = getSwitchReport( $dbh, $optswitch, $opthours );
    printNetdbSwitchports( $netdb_ref );
}

# Get all ports that match regex description
elsif ( $optDescription ) {
    $transactionID = recordTransaction( $optDescription, 'descsearch' ) if $transactions;

    my $netdb_ref = getSwitchportDesc( $dbh, $optDescription, $opthours );
    printNetdbSwitchports( $netdb_ref );
}

# Search on Vendor Code
elsif ( $optvendorcode ) {
    $transactionID = recordTransaction( $optvendorcode, 'vendor' ) if $transactions;

    my $netdb_ref = getVendorCode( $dbh, $optvendorcode, $opthours );
    printNetdbMAC( $netdb_ref );
}

# Get new mac addresses in past hours
elsif ( $optnewmacs && $opthours ) {
    my $netdb_ref = getNewMacs( $dbh, $opthours );

    # Count and output for mrtg
    if ( $optmrtg ) {
	my $cnt = @$netdb_ref;

	print "$cnt\n$cnt\n$cnt\n$cnt";
    }
    else {
	printNetdbMAC( $netdb_ref );
    }
}

# Vlan Report
elsif ( $optvlan ) {
    $transactionID = recordTransaction( $optvlan, 'vlanreport' ) if $transactions;

    my $netdb_ref = getVlanReport( $dbh, $optvlan, $opthours );
    printNetdbIPMAC( $netdb_ref );
}
# Get Vlan report from switch status pages
elsif ( $optvlanstatus ) {
    $transactionID = recordTransaction( $optvlanstatus, 'vlanstatus' ) if $transactions;

    my $netdb_ref = getVlanSwitchStatus( $dbh, $optvlanstatus, $opthours );
    printNetdbSwitchports( $netdb_ref );
}

# Get switchport history for mac address
elsif ( $optport ) {
    $transactionID = recordTransaction( $optport, 'switch' ) if $transactions;

    getSwitchport( $optport );
}

# Database Transaction History
elsif ( $opthistory ) {
    my $netdb_ref = getTHistory( $dbh, $opthours );
    printTHistoryinFormat( $netdb_ref );
}

elsif ( $optstats ) {
    my $h_ref = getDBStats( $dbh, $opthours );
    my %stats = %$h_ref;

    my $dbRowCount = $stats{mac} + $stats{ipmac} + $stats{switchports} + $stats{transactions} 
                   + $stats{switchstatus} + $stats{nacreg} + $stats{wifi};

    print "\n  NetDB Statistics";
    print " over $opthours hours" if $opthours != 100000;
    print "\n ---------------------------------\n";
    print "   New MACs:         $stats{newmacs}\n" if $opthours != "100000";
    print "   MAC Entries:      $stats{mac}\n";
    print "   ARP Entries:      $stats{ipmac}\n";
    print "   Switch Entries:   $stats{switchports}\n";
    print "   WiFi Entries:     $stats{wifi}\n";
    print "   Status Entries:   $stats{switchstatus}\n" if $opthours == "100000";
    print "   Registrations:    $stats{nacreg}\n" if $opthours == "100000";
    print "   DB Transactions:  $stats{transactions}\n";
    print "   Total Rows in DB: $dbRowCount\n" if $opthours == "100000";
}


# Unused Switchport Report
elsif ( $optswitchreport ) {
    $transactionID = recordTransaction( "$optswitchreport", 'unusedports' ) if $transactions;

    my $netdb_ref = getUnusedPorts( $dbh, $optswitchreport, $opthours );
    printNetdbSwitchports( $netdb_ref );  
}

else {
    &usage();
}

if ( $DEBUG ) {
    my $runtime = Time::HiRes::tv_interval( $starttime );
    $runtime = sprintf( "%.3f", $runtime );
    $runtime = $runtime * 1000;
    print "\nRuntime [" . $runtime . "ms]\n";
}

print "\n";
# End Main

#---------------------------------------------------------------------------------------------
# Logs user transaction to the transaction table
#---------------------------------------------------------------------------------------------
sub recordTransaction {
    # Priviledged Access
    my $dbh_p = connectDBrw( $config_file );

    my ( $queryvalue, $querytype ) = @_;

    my $ip       = hostname();
    my $username = `whoami`;
    chomp($username);
    my $tid;

    my %netdbTransaction = ( ip => $ip,
                             username => $username,
                             querytype => $querytype,
                             queryvalue => $queryvalue,
                             querydays => $opthours/24,
                           );

    # Keep transactionID for CSV Reports
    $tid = insertTransaction( $dbh_p, \%netdbTransaction );
#    print header;
#    print "$ip $username $querytype $queryvalue $searchDays";

    return $tid;
}

sub getSwitchport {
    my $mac = shift;

    my $netdb_ref = getSwitchports( $dbh, $mac, $opthours );
    printNetdbSwitchports( $netdb_ref );
}
#---------------------------------------------------------------------------------------------
# Get and print single NAC entry
#---------------------------------------------------------------------------------------------
sub getNACRegData {
    my $mac = shift;

    my $netdb_ref = getNACReg( $dbh, $mac );

    if ( !$optcsv && $$netdb_ref[0]{"mac"} ) {
        printNACReginFormat( $netdb_ref );
    }
}
#---------------------------------------------------------------------------------------------
# Print results from NetDB ip Table
#---------------------------------------------------------------------------------------------
sub printNetdbIPinCSV {
    my $netdbPrint_ref = shift;

    # Sort by IP address
    $netdbPrint_ref = sortByIP( $netdbPrint_ref );
    # Dereference array of hashrefs
    my @netdbPrint = @$netdbPrint_ref;
    # Get length for loop
    my $netdbPrint_length = @netdbPrint;

    # Header
    print "IP Address,Mac Address,Lastmac\n" if @netdbPrint;
    # Go through array of hashrefs and pass them to insertIPMAC
    for (my $i=0; $i < $netdbPrint_length; $i++)
    {
        print "$netdbPrint[$i]{ip},$netdbPrint[$i]{static},$netdbPrint[$i]{lastmac}\n";
    }
}
#---------------------------------------------------------------------------------------------
# Print out the contents of the Switchports Table
#---------------------------------------------------------------------------------------------
sub printNetdbSwitchports {
    my $netdb_ref = shift;

    # Convert MAC Address Format to default display format from config file
    $netdb_ref = convertMacFormat( $netdb_ref, $mac_format );

    if ( $optcsv ) {
        printNetdbSwitchportsinCSV( $netdb_ref );
    }
    else {
        printNetdbSwitchportsinFormat( $netdb_ref );
    }
}
#---------------------------------------------------------------------------------------------
# Print results from NetDB mac Table
#---------------------------------------------------------------------------------------------
sub printNetdbSwitchportsinFormat {
    my $netdbPrint_ref = shift;
    my $i;
    my $tmpwrite = "/tmp/netdbtmp";

    # Sort Array of hashrefs based on Cisco Port naming scheme
    $netdbPrint_ref = sortByPort( $netdbPrint_ref );
    $netdbPrint_ref = sortBySwitch( $netdbPrint_ref );

    # Dereference array of hashrefs
    my @netdbPrint = @$netdbPrint_ref;

    # Get length for loop
    my $netdbPrint_length = @netdbPrint;


    # Lines per page
    $= = 35;

    open( STDOUTSWITCH, '>', "$tmpwrite") or die "Can't open up $tmpwrite: $!\n";

   # Formats for report, watch that trailing . is on the far left
    format STDOUTSWITCH_TOP =

  Switch             Port       S VLAN  Description              MAC Address        First Seen        Last Seen
  -----------------  ---------- - ----  -----------------------  -----------------  ----------------  ----------------
.
  format STDOUTSWITCH =
  @>>>>>>>>>>>>>>>>  @<<<<<<<<< @ @>>>  @<<<<<<<<<<<<<<<<<<<<<<  @<<<<<<<<<<<<<<<<  @>>>>>>>>>>>>>>>  @>>>>>>>>>>>>>>>  
  $netdbPrint[$i]{switch},$netdbPrint[$i]{port},$netdbPrint[$i]{status},$netdbPrint[$i]{vlan},$netdbPrint[$i]{description},$netdbPrint[$i]{mac},$netdbPrint[$i]{firstseen}, $netdbPrint[$i]{lastseen}
.

    # Go through array of hashrefs and pass them to insertIPMAC
    for ($i=0; $i < $netdbPrint_length; $i++)
    {
	$netdbPrint[$i]{status} = "U" if ( $netdbPrint[$i]{status} =~ /up|connected/ );
        $netdbPrint[$i]{status} = "D" if ( $netdbPrint[$i]{status} =~ /down|notconnect/ );
        $netdbPrint[$i]{status} = "S" if ( $netdbPrint[$i]{status} eq 'disabled' );
        $netdbPrint[$i]{status} = "E" if ( $netdbPrint[$i]{status} eq 'err-disabled' );
        $netdbPrint[$i]{status} = "F" if ( $netdbPrint[$i]{status} eq 'faulty' );
        $netdbPrint[$i]{status} = "M" if ( $netdbPrint[$i]{status} eq 'monitor' );

	$netdbPrint[$i]{port} =~ s/^Eth/E/; # Nexus FeX truncate

	# Replace empty MAC Field with ND data
	if ( !$netdbPrint[$i]{mac} && $netdbPrint[$i]{n_host} ) {
	    my ( $host ) = split( /\./, $netdbPrint[$i]{n_host} );
	    $netdbPrint[$i]{mac} = "ND:$host";
	}

        write STDOUTSWITCH;
    }

    open( STDOUTSWITCH, '<', "$tmpwrite") or die "Can't open up $tmpwrite: $!\n";

    while ( my $line = <STDOUTSWITCH> ) {
        print $line;
    }
    if ( $DEBUG && $netdbPrint_length != 1 ) {
	print "\n$netdbPrint_length Records Found";
    }

    close STDOUTSWITCH;
    unlink($tmpwrite);
}

#---------------------------------------------------------------------------------------------
# Print results from NetDB ipmac Table
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

    # Quoted CSV Report
    my $q = undef;
    $q = '"' if $optquote;

    # Header
    print "Switch,Port,Status,Speed,Duplex,Vlan,Description,Mac Address,IP Address,Hostname," .
          "UserID,Static,Vendor,First Seen,Last Seen,n_ip,n_host,n_model,n_port,n_desc\n" if @netdbPrint;

    # Go through array of hashrefs and pass them to insertIPMAC
    for (my $i=0; $i < $netdbPrint_length; $i++)
    {
	$netdbPrint[$i]{vendor} =~ s/\,|\.//g; #remove commas for CSV

        print "$q$netdbPrint[$i]{switch}$q,$q$netdbPrint[$i]{port}$q,$q$netdbPrint[$i]{status}$q," .
	      "$q$netdbPrint[$i]{speed}$q,$q$netdbPrint[$i]{duplex}$q,$q$netdbPrint[$i]{vlan}$q,$q";
	print "$netdbPrint[$i]{description}$q,$q$netdbPrint[$i]{mac}$q,$q$netdbPrint[$i]{ip}$q," .
              "$q$netdbPrint[$i]{name}$q,$q$netdbPrint[$i]{userID}$q,$q";
	print "$netdbPrint[$i]{static}$q,$q$netdbPrint[$i]{vendor}$q,$q$netdbPrint[$i]{firstseen}$q," .
	      "$q$netdbPrint[$i]{lastseen}$q,";
	print "$q$netdbPrint[$i]{n_ip}$q,$q$netdbPrint[$i]{n_host}$q,$q$netdbPrint[$i]{n_model}$q," .
              "$q$netdbPrint[$i]{n_port}$q,$q$netdbPrint[$i]{n_desc}$q\n";
    }
}

#---------------------------------------------------------------------------------------------
# Print out the contents of the MAC Table
#---------------------------------------------------------------------------------------------
sub printNetdbMAC {
    my $netdb_ref = shift;

    # Convert MAC Address Format to default display format from config file
    $netdb_ref = convertMacFormat( $netdb_ref, $mac_format );

    if ( $optcsv ) {
        printNetdbMACinCSV( $netdb_ref );
    }
    else {
        printNetdbMACinFormat( $netdb_ref );
    }

#    if ( !$optcsv || $$netdb_ref[0]{distype} ) {
#	printDisabledinFormat( $netdb_ref );
#    }
}

#---------------------------------------------------------------------------------------------
# Print results from NetDB mac Table
#---------------------------------------------------------------------------------------------
sub printNetdbMACinFormat {
    my $netdbPrint_ref = shift;
    my $i;
    my $tmpwrite = "/tmp/netdbtmp";

    # Dereference array of hashrefs
    my @netdbPrint = @$netdbPrint_ref;

    # Get length for loop
    my $netdbPrint_length = @netdbPrint;

    # Registration Status
    for ($i=0; $i < $netdbPrint_length; $i++)
    {
        if ( $netdbPrint[$i]{userID} ) {
            $netdbPrint[$i]{userID} = "Y"
        }
        else {
            $netdbPrint[$i]{userID} = "N";
        }
    }
    
    # Lines per page
    $= = 35;
    #$^L = '-';

    open( STDOUTMAC, '>', "$tmpwrite") or die "Can't open up $tmpwrite: $!\n";

   # Formats for report, watch that trailing . is on the far left
    format STDOUTMAC_TOP =

  MAC Address       R  Last IP                    Vendor Code                       First Seen        Last Seen
  ----------------- -  ---------------  ------------------------------------------  ----------------  ----------------
.
  format STDOUTMAC =
  @<<<<<<<<<<<<<<<< @  @<<<<<<<<<<<<<<  @|||||||||||||||||||||||||||||||||||||||||  @<<<<<<<<<<<<<<<  @<<<<<<<<<<<<<<<
  $netdbPrint[$i]{mac}, $netdbPrint[$i]{userID}, $netdbPrint[$i]{lastip}, $netdbPrint[$i]{vendor},  $netdbPrint[$i]{firstseen}, $netdbPrint[$i]{lastseen}
.

    # Go through array of hashrefs and pass them to insertIPMAC
    for ($i=0; $i < $netdbPrint_length; $i++)
    {
        write STDOUTMAC;
    }

    open( STDOUTMAC, '<', "$tmpwrite") or die "Can't open up $tmpwrite: $!\n";

    while ( my $line = <STDOUTMAC> ) {
	print $line;
    }
    if ( $DEBUG && $netdbPrint_length != 1 ) {
        print "\n$netdbPrint_length Records Found";
    }
    
    close STDOUTMAC;
    unlink($tmpwrite);
}

#---------------------------------------------------------------------------------------------
# Print results from NetDB ipmac Table
#---------------------------------------------------------------------------------------------
sub printNetdbMACinCSV {
    my $netdbPrint_ref = shift;

    # Dereference array of hashrefs
    my @netdbPrint = @$netdbPrint_ref;

    # Get length for loop
    my $netdbPrint_length = @netdbPrint;

    # Quoted CSV Report
    my $q = undef;
    $q = '"' if $optquote;

    # Header
    print "MAC Address,Last IP,Hostname,Vendor Code,Last Switch,Last Port,First Seen,Last Seen\n" if @netdbPrint;

    # Go through array of hashrefs and pass them to insertIPMAC
    for (my $i=0; $i < $netdbPrint_length; $i++)
    {
	$netdbPrint[$i]{vendor} =~ s/\,|\.//g; #remove commas for CSV
        print "$q$netdbPrint[$i]{mac}$q,$q$netdbPrint[$i]{lastip}$q,$q$netdbPrint[$i]{name}$q,$q$netdbPrint[$i]{vendor}$q,$q$netdbPrint[$i]{lastswitch}$q,$q";
	print "$netdbPrint[$i]{lastport}$q,$q$netdbPrint[$i]{firstseen}$q,$q$netdbPrint[$i]{lastseen}$q\n";
    }
}

#---------------------------------------------------------------------------------------------
# Print out the contents of the ip table
#---------------------------------------------------------------------------------------------
sub printNetdbIPMAC {
    my $netdb_ref = shift;

    # Convert MAC Address Format to default display format from config file
    $netdb_ref = convertMacFormat( $netdb_ref, $mac_format );

    if ( $optcsv ) {
        printNetdbIPMACinCSV( $netdb_ref );
    }
    else {
        printNetdbIPMACinFormat( $netdb_ref );
    }
}
#---------------------------------------------------------------------------------------------
# Print results from NetDB ipmac Table
#---------------------------------------------------------------------------------------------
sub printNetdbIPMACinFormat {
    my $netdbPrint_ref = shift;
    my $i;
    my $v4display;
    my $v6display;
    my $tmpwrite = "/tmp/netdbtmp3";
    my $tmpwrite2 = "/tmp/netdbtmp2";

    # Sort by IP address
    $netdbPrint_ref = sortByIP( $netdbPrint_ref );

    # Dereference array of hashrefs
    my @netdbPrint = @$netdbPrint_ref;

    # Get length for loop
    my $netdbPrint_length = @netdbPrint;

    for ($i=0; $i < $netdbPrint_length; $i++)
    {
        if ( $netdbPrint[$i]{userID} ) {
            $netdbPrint[$i]{userID} = "Y"
        }
        else {
            $netdbPrint[$i]{userID} = "N";
        }
        # V6 Format
        if ( $netdbPrint[$i]{ip} =~ /:/ ) {
            $v6display = 1;
        }
        # V4 Format
        elsif ( $netdbPrint[$i]{ip} =~ /(\d+)(\.\d+){3}/ ) {
            $v4display = 1;
        }
    }
    # Lines per page
    $= = 35;

    #$^L = '-';
    
    if ( $v4display ) {
        # Formats for report, watch that trailing . is on the far left
        format STDOUT_TOP =

  IP Address       MAC Address       R             Hostname            VLAN   VRF   First Seen        Last Seen
  ---------------  ----------------- -  -----------------------------  ----  -----  ----------------  ----------------
.
  format STDOUT =
  @<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<< @  @||||||||||||||||||||||||||||  @>>>  @>>>>  @>>>>>>>>>>>>>>>  @>>>>>>>>>>>>>>>
  $netdbPrint[$i]{ip}, $netdbPrint[$i]{mac}, $netdbPrint[$i]{userID}, $netdbPrint[$i]{name}, $netdbPrint[$i]{vlan}, $netdbPrint[$i]{vrf}, $netdbPrint[$i]{firstseen}, $netdbPrint[$i]{lastseen}
.

    # Go through array of hashrefs and pass them to insertIPMAC
    for ($i=0; $i < $netdbPrint_length; $i++)
    {
        #print "$netdbPrint[$i]{ip},\t$netdbPrint[$i]{mac},\t$netdbPrint[$i]{vlan},\t$netdbPrint[$i]{name},\t$netdbPrint[$i]{firstseen},\t$netdbPrint[$i]{lastseen}\n";
        # Print if IPv4 Address
        if ( $netdbPrint[$i]{ip} =~ /(\d+)(\.\d+){3}/ ) {
            write STDOUT;
        }
    }
} # v4 display
    

    # IPv6 Format
    if ( $v6display ) {

    open( STDOUTVSIX, '>', "$tmpwrite2") or die "Can't open up $tmpwrite2: $!\n";


    # Formats for report, watch that trailing . is on the far left
    format STDOUTVSIX_TOP =

             IPv6 Address                           Hostname                  VLAN  First Seen        Last Seen
  --------------------------------------  ----------------------------------  ----  ----------------  ----------------
.
  format STDOUTVSIX =
  @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @|||||||||||||||||||||||||||||||||  @<<<< @>>>>>>>>>>>>>>>  @>>>>>>>>>>>>>>>
  $netdbPrint[$i]{ip}, $netdbPrint[$i]{name}, $netdbPrint[$i]{vlan}, $netdbPrint[$i]{firstseen}, $netdbPrint[$i]{lastseen}
.

    # Go through array of hashrefs and pass them to insertIPMAC
    for ($i=0; $i < $netdbPrint_length; $i++)
    {
        #print "$netdbPrint[$i]{ip},\t$netdbPrint[$i]{mac},\t$netdbPrint[$i]{vlan},\t$netdbPrint[$i]{name},\t$netdbPrint[$i]{firstseen},\t$netdbPrint[$i]{lastseen}\n";
	
	# Print if IPv6 Address
	if ( $netdbPrint[$i]{ip} =~ /:/ ) {
	    write STDOUTVSIX;
	}
    }
    
    open( STDOUTVSIX, '<', "$tmpwrite2") or die "Can't open up $tmpwrite2: $!\n";
    
    while ( my $line = <STDOUTVSIX> ) {
	print $line;
    }
    close STDOUTVSIX;
    unlink($tmpwrite2);
    
    
} #v6 display
    if ( $DEBUG && $netdbPrint_length != 1 ) {
        print "\n$netdbPrint_length Records Found";
    }

} # END sub printNetdbIPMACinFormat
#---------------------------------------------------------------------------------------------
# Print out the contents of the ip table from mass search
#   Input: ($netdb_ref)
#       netdb refrence: refrence to a table with the results of a mass lookup
#   Output: none
#---------------------------------------------------------------------------------------------
sub printNetdbIPMACList {
    my $netdb_ref = shift;

    # Convert MAC Address Format to default display format from config file
    $netdb_ref = convertMacFormat( $netdb_ref, $mac_format );

    if ( $optcsv ) {
	printNetdbIPMACinCSV( $netdb_ref );
    }
    else {
	printNetdbIPMACListinFormat( $netdb_ref );
    }
} # END sub printNetdbIPMACList
#---------------------------------------------------------------------------------------------
# Print results from Mass NetDB ipmac Table
#   Input: ($netdbPrint_ref)
#       netdb print ref: ref to netdb data to be printed
#   Output: none
#---------------------------------------------------------------------------------------------
sub printNetdbIPMACListinFormat {
    my $netdbPrint_ref = shift;
    my $i;
    my $tmpwrite = "/tmp/netdbtmp3";

    # Sort by IP address
    $netdbPrint_ref = sortByIP( $netdbPrint_ref );

    # Dereference array of hashrefs
    my @netdbPrint = @$netdbPrint_ref;

    # Get length for loop
    my $netdbPrint_length = @netdbPrint;

    for ($i=0; $i < $netdbPrint_length; $i++)
    {
        if ( $netdbPrint[$i]{userID} ) {
            $netdbPrint[$i]{userID} = "Y"
        }
        else {
            $netdbPrint[$i]{userID} = "N";
        }
    }

    # Lines per page
    $= = 35;
    #$^L = '-';

    open( STDOUTLIST, '>', "$tmpwrite") or die "Can't open up $tmpwrite: $!\n";

    #Formats for report, watch that trailing . is on the far left
    format STDOUTLIST_TOP =

  IP Address                              MAC Address        Switch            Port        S  Description         VLAN             Hostname             First Seen           Last Seen
  --------------------------------------  -----------------  ----------------  ----------  -  ------------------  ----  ------------------------------  -------------------  -------------------
.
  format STDOUTLIST =
  @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<  @<<<<<<<<<<<<<<<< @<<<<<<<<<< @< @<<<<<<<<<<<<<<<<<< @<<<<  @||||||||||||||||||||||||||||| @>>>>>>>>>>>>>>>>>>  @>>>>>>>>>>>>>>>>>>
  $netdbPrint[$i]{lastip}, $netdbPrint[$i]{mac}, $netdbPrint[$i]{lastswitch}, $netdbPrint[$i]{lastport}, $netdbPrint[$i]{status}, $netdbPrint[$i]{description}, $netdbPrint[$i]{vlan}, $netdbPrint[$i]{name}, $netdbPrint[$i]{firstseen}, $netdbPrint[$i]{lastseen}
.

    # Go through array of hashrefs and add them to output
    for ($i=0; $i < $netdbPrint_length; $i++)
    {
        # this converts port status to their one letter represenitve
        $netdbPrint[$i]{status} = "U" if ( $netdbPrint[$i]{status} =~ /up|connected/ );
        $netdbPrint[$i]{status} = "D" if ( $netdbPrint[$i]{status} =~ /down|notconnect/ );
        $netdbPrint[$i]{status} = "S" if ( $netdbPrint[$i]{status} eq 'disabled' );
        $netdbPrint[$i]{status} = "E" if ( $netdbPrint[$i]{status} eq 'err-disabled' );
        $netdbPrint[$i]{status} = "F" if ( $netdbPrint[$i]{status} eq 'faulty' );
        $netdbPrint[$i]{status} = "M" if ( $netdbPrint[$i]{status} eq 'monitor' );

        #print "$netdbPrint[$i]{ip},\t$netdbPrint[$i]{mac},\t$netdbPrint[$i]{lastswitch},\t$netdbPrint[$i]{lastport},\t$netdbPrint[$i]{status},\t$netdbPrint[$i]{description},\t$netdbPrint[$i]{vlan},\t$netdbPrint[$i]{name},\t$netdbPrint[$i]{firstseen},\t$netdbPrint[$i]{lastseen}\n";

        # Were is the IP coming from
        if ( !$netdbPrint[$i]{lastip} ){
            $netdbPrint[$i]{lastip} = $netdbPrint[$i]{ip};
        }

        write STDOUTLIST;
    }
    close STDOUTLIST;

    open( STDOUTLIST, '<', "$tmpwrite") or die "Can't open up $tmpwrite: $!\n";
    while ( my $line = <STDOUTLIST> ) {
        print $line;
    }

    if ( $DEBUG && $netdbPrint_length != 1 ) {
        print "\n$netdbPrint_length Records Found";
    }

    close STDOUTLIST;
    unlink($tmpwrite);
} # END sub printNetdbIPMACListinFormat
#---------------------------------------------------------------------------------------------
# Print registration data in format
#---------------------------------------------------------------------------------------------
sub printNACReginFormat {
    my $netdbPrint_ref = shift;
    my $i;
    my $tmpwrite = "/tmp/netdbtmp";

    # Dereference array of hashrefs
    my @netdbPrint = @$netdbPrint_ref;

    # Get length for loop
    my $netdbPrint_length = @netdbPrint;

    for ($i=0; $i < $netdbPrint_length; $i++)
    {
        if ( $netdbPrint[$i]{critical} ) {
            $netdbPrint[$i]{critical} = "CRITICAL"
        }
        else {
            $netdbPrint[$i]{critical} = "no";
        }
    }

    # Lines per page
    $= = 35;
    #$^L = '-';
    open( STDOUTNAC, '>', "$tmpwrite") or die "Can't open up $tmpwrite: $!\n";
    
    #Formats for report, watch that trailing . is on the far left
    format STDOUTNAC_TOP =

  First Name     Last Name       User          Email             Role               Type 
  -------------  --------------  ------------  ----------------  -----------------  ----------------------------------
.
  format STDOUTNAC =
  @<<<<<<<<<<<<  @<<<<<<<<<<<<<  @<<<<<<<<<<<  @<<<<<<<<<<<<<<<  @<<<<<<<<<<<<<<<<  @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
  $netdbPrint[$i]{firstName},  $netdbPrint[$i]{lastName}, $netdbPrint[$i]{userID}, $netdbPrint[$i]{email}, $netdbPrint[$i]{role}, $netdbPrint[$i]{type}
.

    # Go through array of hashrefs and pass them to insertIPMAC
    for ($i=0; $i < $netdbPrint_length; $i++)
    {
        write STDOUTNAC;
    }

    open( STDOUTNAC, '<', "$tmpwrite") or die "Can't open up $tmpwrite: $!\n";

    while ( my $line = <STDOUTNAC> ) {
        print $line;
    }
    if ( $DEBUG && $netdbPrint_length != 1 ) {
        print "\n$netdbPrint_length Records Found";
    }
    
    close STDOUTNAC;
    unlink($tmpwrite);
}
#---------------------------------------------------------------------------------------------
# Print registration data in format
#---------------------------------------------------------------------------------------------
sub printDisabledinFormat {
    my $netdbPrint_ref = shift;
    my $i;
    my $tmpwrite = "/tmp/netdbtmp";

    # Dereference array of hashrefs
    my @netdbPrint = @$netdbPrint_ref;

    # Get length for loop
    my $netdbPrint_length = @netdbPrint;

#    for ($i=0; $i < $netdbPrint_length; $i++)
#    {
#        if ( $netdbPrint[$i]{critical} ) {
#	    $netdbPrint[$i]{critical} = "CRITICAL"
#	}
#	else {
#	    $netdbPrint[$i]{critical} = "no";
#	}
#    }


    # Lines per page
    $= = 35;
    #$^L = '-';
    open( STDOUTDIS, '>', "$tmpwrite") or die "Can't open up $tmpwrite: $!\n";
    
       # Formats for report, watch that trailing . is on the far left
    format STDOUTDIS_TOP =

  Disabled Time        Disabled Type  Authorized User   Case ID  
  -------------------  -------------  ----------------  -----------------------------
.
  format STDOUTDIS =
  @<<<<<<<<<<<<<<<<<<  @<<<<<<<<<<<<  @<<<<<<<<<<<<<<<  @<<<<<<<<<<<<<<<<<<<<<<<<<<<<
  $netdbPrint[$i]{disdate}, $netdbPrint[$i]{distype},  $netdbPrint[$i]{disuser}, $netdbPrint[$i]{discase}
.

    # Go through array of hashrefs and pass them to insertIPMAC
    for ($i=0; $i < $netdbPrint_length; $i++)
    {
        write STDOUTDIS;
    }

    open( STDOUTDIS, '<', "$tmpwrite") or die "Can't open up $tmpwrite: $!\n";

    while ( my $line = <STDOUTDIS> ) {
        print $line;
    }
    if ( $DEBUG && $netdbPrint_length != 1 ) {
        print "\n$netdbPrint_length Records Found";
    }
    
    close STDOUTDIS;
    unlink($tmpwrite);
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

    # Quoted CSV Report
    my $q = undef;
    $q = '"' if $optquote;

    # Header
    print "IP Address,MAC Address,Owner,VLAN,Router,VRF,Static,Hostname,Switch,Port,Description,Vendor Code,Firstseen,Lastseen\n" if @netdbPrint;

    # Go through array of hashrefs and pass them to insertIPMAC
    for (my $i=0; $i < $netdbPrint_length; $i++)
    {
        $netdbPrint[$i]{vendor} =~ s/\,|\.//g; #remove commas for CSV
        # Were is the IP coming from
        if ( $netdbPrint[$i]{lastip} ){
            print "$q$netdbPrint[$i]{lastip}$q,";
        }
        else {
            print "$q$netdbPrint[$i]{ip}$q,";
        }
        print "$q$netdbPrint[$i]{mac}$q,$q$netdbPrint[$i]{userID}$q,$q$netdbPrint[$i]{vlan}$q,$q$netdbPrint[$i]{router}$q,$q$netdbPrint[$i]{vrf}$q,";
        print "$q$netdbPrint[$i]{static}$q,$q$netdbPrint[$i]{name}$q,$q$netdbPrint[$i]{lastswitch}$q,$q$netdbPrint[$i]{lastport}$q,$q$netdbPrint[$i]{description}$q,";
        print "$q$netdbPrint[$i]{vendor}$q,$q$netdbPrint[$i]{firstseen}$q,$q$netdbPrint[$i]{lastseen}$q\n";
    }
}

#---------------------------------------------------------------------------------------------
# Print Transaction History
# Print results from NetDB mac Table
#---------------------------------------------------------------------------------------------                                                                                                                 
sub printTHistoryinFormat {
    my $netdbPrint_ref = shift;
    my $i;
    my $tmpwrite = "/tmp/netdbtmp";

    # Sort Array of hashrefs based on Cisco Port naming scheme                                                                                           
    $netdbPrint_ref = sortByPort( $netdbPrint_ref );

    # Dereference array of hashrefs                                                                                                                      
    my @netdbPrint = @$netdbPrint_ref;

    # Get length for loop                                                                                                                                
    my $netdbPrint_length = @netdbPrint;

    # Lines per page
    $= = 35;

    open( STDOUTHIST, '>', "$tmpwrite") or die "Can't open up $tmpwrite: $!\n";

   # Formats for report, watch that trailing . is on the far left
    format STDOUTHIST_TOP =

  Username     Query Type            Search String         Days  Source IP        Time                 Transaction ID
  -----------  -------------  ---------------------------  ----  ---------------  -------------------  -------------------------------------
.
  format STDOUTHIST =
  @<<<<<<<<<<  @<<<<<<<<<<<<  @||||||||||||||||||||||||||  @<<<  @<<<<<<<<<<<<<<  @>>>>>>>>>>>>>>>>>>  @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
  $netdbPrint[$i]{username}, $netdbPrint[$i]{querytype}, $netdbPrint[$i]{queryvalue}, $netdbPrint[$i]{querydays}, $netdbPrint[$i]{ip},$netdbPrint[$i]{time},$netdbPrint[$i]{id}
.

    # Go through array of hashrefs and pass them to insertIPMAC
    for ($i=0; $i < $netdbPrint_length; $i++)
    {
        write STDOUTHIST;
    }

    open( STDOUTHIST, '<', "$tmpwrite" ) or die "Can't open up $tmpwrite: $!\n";

    while ( my $line = <STDOUTHIST> ) {
        print $line;
    }
    if ( $DEBUG && $netdbPrint_length != 1 ) {
        print "\n$netdbPrint_length Records Found";
    }


    unlink($tmpwrite);
    close STDOUTHIST;
}
#---------------------------------------------------------------------------------------------
# Get the revision number from svn, if it fails, return 0
#---------------------------------------------------------------------------------------------
sub getSubversion {
    my @output;
    my $tmp;
    my $subver = 0;
    my $revDate;

    eval {
	@output = `svn info $optrootdir 2> /dev/null`;

	foreach my $line ( @output ) {
	    if ( $line =~ /Revision\:/ ) {
		( $subver ) = ( split /\:\s+/, $line )[1];
		chomp( $subver );
	    }
	    elsif ( $line =~ /Last\sChanged\sDate\:\s/ ) {
		( $revDate ) = ( split /\:\s+/, $line )[1];
		($revDate) = split( /\s\(/, $revDate );
		$revDate = "($revDate)";
	    }
	}
    };

    return ( $subver, $revDate );
}

#---------------------------------------------------------------------------------------------
# Parse Configuration from file
#---------------------------------------------------------------------------------------------
sub parseConfig {
    # Create any variables that do not exist to avoid errors
    my $config = AppConfig->new({
				 CREATE => 1,
				});
    
    $config->define( "rootdir=s" );

    $config->file( "$config_file" );

    $optrootdir = $config->rootdir();
}

sub usage {
    my @versionInfo = getSubversion();

    if ( !$versionInfo[0] ) {
        $versionInfo[0] = $netdbMinorVer
    }
    else {
        $versionInfo[0] = "$netdbMinorVer" . " (rev $versionInfo[0])";
    }    
    print "NetDB v$netdbVer.$versionInfo[0] $versionInfo[1]\n";

    print <<USAGE;

  About: Queries the network database for information and generates reports
  Usage: netdb [options]

  Search Type:     (Note: 7 day search by default)
    -i  ipaddr     Search ARP table for entries using this ip address
    -m  macaddr    Search ARP table for entries using this mac address (any format or short xx:xx)
    -p  macaddr    Search switchport table for the history of a mac address 
    -n  hostname   Search ARP table for hostnames that contain this string (case-insensitive) 
    -u  username   Search the ARP table for hosts owned by a user in NAC
    -vc vendor     Search mac table for a partial vendor code (case-insensitive)
    -vl number     Get all ARP entries on a vlan (combine with -d)
    -vs number     Get all switch ports on a vlan (combine with -d)
    -sw switch     Get a switch report over -d days, refine to certain port with -sw switch,port
    -ds desc       Get all switchports that match "description"
    -up all|switch Get all unused ports that have not seen a mac in -d days

  Search over time (should be used with above searches):
    -d  days       Search over a number of days in the past [7 days by default]
    -h  hours      Search over a number of hours rather than days or combine the two      

  Static Address Management:
    -us            Get a list of static IPs that have never been seen on the network
    -s             Get a list of static IPs that have not been seen in a number of -d days   

  Statistics (combine all with -d):
    -nm            Find new mac addresses on the network
    -st            NetDB statistics and table counts (used with -d)
    -t             NetDB transaction history (used with -d)

  Options:
    -f             Use a file as input, file specified in place of normal input
                   (curretly only works with -m)
    -c             Output results in CSV format (Excel Spreadsheet)
    -q             Put quotes around CSV output
    -mf string     Override Mac Format: dash, colon, cisco, or none
    -conf          Alternate Configuration File
    -v             Verbose output

USAGE
    exit;
}
