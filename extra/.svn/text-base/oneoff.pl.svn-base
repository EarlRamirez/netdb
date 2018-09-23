#!/usr/bin/perl -w
###################################################################
#
# Used for one off database interactions
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

# Get database connection
my $dbh = connectDBrw();
my @netdbBulk;
my $transactionID;
my $transactions = 1;

# Input Options
if ( $ARGV[0] eq "" ) { &usage(); }

GetOptions(
    'v'    => \$DEBUG,
          )
or &usage();

#################


print "\n";
# End Main

my %macs;

my $getipmac_h = $dbh->prepare( "select * from ipmac" );

$getipmac_h->execute();

while ( my $row = $getipmac_h->fetchrow_hashref() ) {
    if ( $row ) {
	if ( !$macs{ $$row{mac} } ) {
	    $macs{ $$row{mac} } = $$row{firstseen};
	}
	else {
	    my $a1 = $macs{ $$row{mac} };
	    my $b1 = $$row{firstseen};

	    my $compare = DateTime->compare_ignore_floating(
							    DateTime::Format::MySQL->parse_datetime($a1),
							    DateTime::Format::MySQL->parse_datetime($b1)
                                         );
#            print "$a1 $b1 $compare\n";
	    if ( $compare > 0 ) {
		$macs{ $$row{mac} } = $b1;
#		print "Chose $b1 over $a1 for $$row{mac}\n";
	    }
	}
    }
}


my $setmac_h = $dbh->prepare( "update mac set firstseen=? where mac=?" );

my ($mac, $firstseen);

while ( ( $mac, $firstseen) = each(%macs) ) {
#    print "Setting $mac $firstseen\n";
    $setmac_h->execute( $firstseen, $mac );
}

print "\n\nFinished INSERT\n\n";

#$setmac_h->execute();



sub usage {
    print "Incorrect Usage check input\n";
}
