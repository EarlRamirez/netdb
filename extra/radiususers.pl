#!/usr/bin/perl
#
# Converts Radius records from Splunk in to NAC user file for import (custom)
#
use strict;
use warnings;


my $DEBUG = 0;

# Grab Splunk Radius Records from the past 30 minutes
my @radout = `/scripts/splunkalert/splunkalert.pl -cs "host::radauth*" -c 1000000 -m 30 2> /dev/null`;

my ( $user , $mac );
my @usertable;
my @tmp;

foreach my $line ( @radout ) {

    # Match a new date line, store then wipe out old values
    if ( $line =~ /^\w\w\w\s+\w\w\w\s+\d+/ ) {

	if ( $user && $mac ) {
	    push( @usertable, "$mac,,,,$user,,,Radius Authentication" );
	}

	print "\nNew Entry:\n" if $DEBUG;
	$user = undef;
	$mac = undef;
	next;
    }

    # Remove leading white space
    $line =~ s/^\s+//;
    chomp( $line );

    # MAC Address Processing
    if ( $line =~ /Calling-Station-Id/ ) {
	
	@tmp = split( /\s+\=\s+/, $line);

	# Strip quotes
	$tmp[1] =~ s/\"//g;
        $mac = $tmp[1];

	print "mac: $tmp[1]\n" if $DEBUG;
    }

    # Username processing
    elsif ( $line =~ /User-Name/ ) {
	
        @tmp = split( /\s+\=\s+/, $line);

        # Strip quotes
        $tmp[1] =~ s/\"//g;

	# Split usernames with domain "clinlan\user"
	if ( $tmp[1] =~ /\\/ ) {
	    @tmp = split( /\\/, $tmp[1] );
	}

	# Host Authentication
	if ( $tmp[1] =~ /host\// ) {
	    $tmp[1] = "hostauth";
	}

	# Strip @ domain
	if ( $tmp[1] =~ /\@/ ) {
            @tmp = split( /\@/, $tmp[1] );
	    $tmp[1] = $tmp[0];
        }

        $user = $tmp[1];
	print "user: $user\n" if $DEBUG;
    }

}

# Print out user table

foreach my $line ( @usertable ) {
    print "$line\n";
}
