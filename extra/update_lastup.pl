#!/usr/bin/perl -w
###################################################################
#
# Update lastup field with lastseen mac timer
# 
###################################################################
use NetDB;
use Term::ReadKey;
use Getopt::Long;
use DateTime;
use strict;
use warnings;

# no nonsense
no warnings 'uninitialized';

my $DEBUG;
my $UPDATE = 0;

# Get database connection
#my $dbh = connectDBrw( "/n2/netdbdev.conf" );
my $dbh = connectDBrw();
my @netdbBulk;
my $transactionID;
my $transactions = 1;

# Input Options
if ( $ARGV[0] eq "" ) { &usage(); }

GetOptions(
    'v'    => \$DEBUG,
    'update' => \$UPDATE,
          )
or &usage();

#################


# End Main

my %ports;

my $getlastup_h = $dbh->prepare( "select switchstatus.switch,switchstatus.port,switchstatus.lastup,switchports.lastseen,switchports.mac from switchstatus LEFT JOIN (switchports) ON (switchports.switch=switchstatus.switch AND switchports.port=switchstatus.port)" );

$getlastup_h->execute();

print "Comparing all port data...\n";

while ( my $row = $getlastup_h->fetchrow_hashref() ) {
    if ( $row ) {
	if ( !$ports{ "$$row{switch},$$row{port}" } ) {

	    if ( $$row{lastseen} ) {
		$ports{"$$row{switch},$$row{port}"} = $$row{lastseen};
		print "Found lastup $$row{switch},$$row{port},$$row{lastseen}\n" if $DEBUG;
	    }
	}
	else {
	    my $a1 = $ports{"$$row{switch},$$row{port}"};
	    my $b1 = $$row{lastseen};

	    my $compare = DateTime->compare_ignore_floating(
							    DateTime::Format::MySQL->parse_datetime($a1),
							    DateTime::Format::MySQL->parse_datetime($b1)
                                         );
#            print "$a1 $b1 $compare\n";
	    if ( $compare < 0 ) {
		$ports{"$$row{switch},$$row{port}"} = $b1;
		print "Chosing better lastup $b1 over $a1 for $$row{switch},$$row{port}\n" if $DEBUG;
	    }
	}
    }
}




if ( $UPDATE ) {

    print "Updating lastup data in database...\n";

    my $setlastup_h = $dbh->prepare( "UPDATE switchstatus SET lastup=? WHERE switch=? AND port=?" );

    my ( $switchport, $switch, $port, $lastup );
    
    while ( ( $switchport, $lastup ) = each(%ports) ) {

	( $switch, $port ) = split( /\,/, $switchport );
        print "Setting $switch,$port,$lastup\n" if $DEBUG;
        $setlastup_h->execute( $lastup, $switch, $port );
    }

    print "\nFinished INSERT\n\n";
    
}


sub usage {
    print "Run with -v to see what changes will be, run with -update to update database\n";
    exit;
}
