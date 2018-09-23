#!/usr/bin/perl
##########################################################################
# bclientdump.pl - Processes Bradford Client Dump Data
# Author: Jonathan Yantis <yantisj@gmail.com>
# Copyright (C) 2014 Jonathan Yantis
##########################################################################
# 
# Process Bradford "client" dump results
#
# Test with: ./bclientdump.pl -i /opt/netdb/data/pod1.txt,/opt/netdb/data/pod2.txt \
#            -p /opt/netdb/data/pod1-profiled.txt,/opt/netdb/data/pod2-profiled.txt -o ./nac.csv -v
#
# Output Format: mac,regtime,firstName,lastName,userID,email,phone,device_type,\
#              Org_Entity,critical[Critical|Non-Critic],Device Role,Job Title,\
#              Device Status
#
# You need to setup a cronjob to get the client dump data on to the NetDB
# server.
#
#
#
#####################################################
use Getopt::Long;
use AppConfig;
use English qw( -no_match_vars );
use strict;
use warnings;

# no nonsense
no warnings 'uninitialized';


my $DEBUG          = 0;
my $config_file    = "/etc/netdb.conf";

my ( $optoutfile, $optinfile, $opt_profiled );
my @csv;
my @reflist;
my %table;

# Input Options
if ( !$ARGV[0] ) { &usage(); }

GetOptions(
    'o=s'  => \$optoutfile,
    'i=s'  => \$optinfile,
    'p=s'  => \$opt_profiled,
    'conf=s' => \$config_file,
    'v'    => \$DEBUG,
          )
or &usage();

# Parse Configuration File
&parseConfig();


if ( !$optinfile || !$optoutfile ) {
    print "Input Error: Must define input and output file\n";
    &usage();
}


# Process multiple input files, write later
my @files = split( /\,/, $optinfile );

foreach my $nacfile ( @files ) {
    
    open( my $SOURCE, '<', "$nacfile" ) or die "Can't open $nacfile: $!\n";
    
    my $last_ref = { 1 => 1 };
    my $lastline;
    my @r;
    my %entry;
    my @pod = split( /\//, $nacfile );
    my $plength = @pod;
    my ( $pod ) = split(/\./, $pod[$plength-1] );
    
    while ( my $line = <$SOURCE> ) {
	

	# Strip leading spaces
	$line =~ s/^\s+//g;
	
	# Split out results
	@r = split( /\s\=\s/, $line );
	chomp( $r[1] );
	
	# Beginning of new entry
	if ( $r[0] eq "DBID" ) {
	    
	    # Before moving on, save last entry, compare if already exists
	    if ( $entry{MAC} && $entry{MAC} ne "NULL" ) {
		
		#print "working on $entry{MAC}\n";

		# If no entry for mac, insert hash reference entry in to main table
		if ( !$table{$entry{MAC}} ) {

		    # Copy the hash to a new reference
		    my $copy = { %entry };
		    
		    $table{$entry{MAC}} = $copy;
		    #print "inserted: $copy for $entry{MAC}\n";

		}
		# Compare two entries if one exists
		else {		    
		    #print "exist: entry: $entry{MAC}, result $table{$entry{MAC}}\n";
		    $table{$entry{MAC}} = compareEntries( $table{$entry{MAC}}, \%entry );
		}

	    }
	    
	    # clear %entry
	    undef %entry;


	    #my $ref = getNewRef();
	    #%entry = %$ref;
	    #print "new ref: $ref\n";
	    
	    # Record the first and last name if available
	    if ( $lastline =~ /^\w+,\s\w+/ ) {
		( $entry{lastName}, $entry{firstname} ) = split( /\,/, $lastline );
		chomp( $entry{firstname} );
		$entry{firstname} =~ s/^\s+//;
	    }
	}

	# Save DBID and Pod, start of new entry
	if ( $r[0] eq "DBID" ) {
            $entry{DBID} = $r[1];
	    $entry{pod} = $pod;
        }
	
	# MAC Address
	elsif ( $r[0] eq "MAC" ) {
	    #	print "$r[0] $r[1]\n" if $r[1] =~ "00:24:E8:44:AC:BF";
	    $r[1] = uc $r[1];
	    $entry{MAC} = $r[1];
	}
	elsif ( $r[0] eq "UserID" ) {
	    $entry{UserID} = $r[1];

	    if ( $entry{UserID} eq "null" ) {
		$entry{UserID} = "registered";
	    }
	}
	elsif ( $r[0] eq "e-mail" ) {
	    $entry{email} = $r[1];
	}
        elsif ( $r[0] eq "Status" ) {
            $entry{status} = $r[1];
        }
	elsif ( $r[0] eq "OS" ) {
	    $entry{OS} =~ s/\,//g;
	    $entry{OS} = $r[1];
	}
	elsif ( $r[0] eq "Role" ) {
	    $entry{Role} =~ s/\,//g;
	    $entry{Role} = $r[1];
	}
	elsif ( $r[0] eq "Grade" ) {
	    $entry{title} =~ s/\,//g;
	    $entry{title} =~ s/\;//g;
	    $entry{title} = $r[1];
	}
	elsif ( $r[0] eq "Off line Time" ) {
	    $r[1] = convertDate( $r[1] ); 

	    $entry{expiration} = $r[1];
	    #print "expire: $entry{expiration}\n";
	}

	if ( $r[0] =~ /\w+/ ) {
	    print "$r[0]: $r[1]\n" if $DEBUG>1;
	}
	
	# Save last line in case name present
	$lastline = $line;

	# save hashref to check
	#$last_entry = \%entry;
	
    }

    close $SOURCE;
    
}


# Process Profiled Devices
if ( $opt_profiled ) {
    my @pfiles = split( /\,/, $opt_profiled );

    foreach my $pfile ( @pfiles ) {
        open( my $PROF, '<', "$pfile" ) or die "Can't open $pfile: $!\n";

        my $lastline;
	my @r;
	my %entry;
	my @pod = split( /\//, $pfile );
	my $plength = @pod;
	my ( $pod ) = split(/\./, $pod[$plength-1] );
	$pod =~ s/\-profiled//;

	while ( my $line = <$PROF> ) {
	    
	    
	    # Strip leading spaces
	    $line =~ s/^\s+//g;
	    
	    # Split out results
	    @r = split( /\s\=\s/, $line );
	    chomp( $r[1] );


	    # Beginning of new entry, write out old entry before starting new one
	    if ( $r[0] eq "DBID" ) {

		# Before moving on, save last entry, compare if already exists
		if ( $entry{MAC} && $entry{MAC} ne "NULL" ) {
		    
		    print "working on profiled: $entry{MAC}, $entry{Role}, $entry{pod}, $entry{DBID}\n" if $DEBUG;

		    # If no entry for mac, insert hash reference entry in to main table
		    if ( !$table{$entry{MAC}} ) {
			
			# Copy the hash to a new reference
			my $copy = { %entry };
			
			$table{$entry{MAC}} = $copy;
			#print "inserted: $copy for $entry{MAC}\n";
			
		    }
		    # Compare two entries if one exists
		    else {
		    	print "profiled entry exists: $entry{MAC}, result $table{$entry{MAC}}\n" if $DEBUG;
		    	#$table{$entry{MAC}} = compareEntries( $table{$entry{MAC}}, \%entry );
		    }
		    
		}
		
		# clear %entry
		undef %entry;
	    }
	    
	    # Beginning of new entry
	    if ( $r[0] eq "DBID" ) {	
		$entry{DBID} = $r[1];
		$entry{pod} = $pod;
		$entry{UserID} = "nac-profiled";
	    }

	    # MAC Address
	    elsif ( $r[0] eq "MAC" ) {
		#   print "$r[0] $r[1]\n" if $r[1] =~ "00:24:E8:44:AC:BF";
		$r[1] = uc $r[1];
		$entry{MAC} = $r[1];
	    }
	    elsif ( $r[0] eq "Role" ) {
		$entry{Role} =~ s/\,//g;
		$entry{Role} = $r[1];
	    }
	    
	} #END While
		
    } #END File open
}



while ( my ( $key, $value ) = each %table ) {

    my %entry = %$value;

            # write out last entry if it exists
    if ( $entry{MAC} && $entry{MAC} ne "null" ) {
	#print "$entry{MAC},,$entry{firstname},$entry{lastName},$entry{UserID},$entry{email},,$entry{OS},,,$entry{Role},$entry{title},$entry{status}\n";
	push( @csv, "$entry{MAC},,$entry{firstname},$entry{lastName},$entry{UserID},$entry{email},,$entry{OS},,,$entry{Role},$entry{title},$entry{status},$entry{expiration},$entry{pod},$entry{DBID}" );
           
    }
}

# Output results
open( my $OUTPUT, '>', "$optoutfile" ) or die "Can't open $optoutfile: $!\n";

foreach my $line ( @csv ) {
    print $OUTPUT "$line\n";
}





# Compare two MAC entries: 
# - If both show connected, just choose one (shouldn't happen)
# - If one is connected and one not, choose connected
# - If both are not connected, choose larger "expiration"
#
sub compareEntries {
    my $e1 = shift;
    my $e2 = shift;

    print "Cmp: $$e1{MAC} -- e1:$$e1{status},$$e1{expiration},$$e1{Role} -- e2:$$e2{status},$$e2{expiration},$$e2{Role} " if $DEBUG;

    if ( $$e1{status} eq "Connected" && $$e2{status} eq "Connected" ) {
	print "Chose e1 (Both Connected)\n" if $DEBUG;
	return $e1;
    }
    
    # E1 is connected, choose it
    elsif ( $$e1{status} eq "Connected" && $$e1{status} ne $$e2{status} ) {
	print "Chose e1 (Connected)\n" if $DEBUG;
	return $e1;
    }
    elsif ( $$e2{status} eq "Connected" && $$e1{status} ne $$e2{status} ) {
	print "Chose e2 (Connected)\n" if $DEBUG;
	return $e2;
    }
    elsif ( $$e1{expiration} || $$e2{expiration} ) {
	if ( $$e1{expiration} > $$e2{expiration} ) {
	    print "Chose e1 (expire last)\n" if $DEBUG;
	    return $e1;
	}
	elsif ( $$e1{expiration} < $$e2{expiration} ) {
            print "Chose e2 (expire last)\n" if $DEBUG;
            return $e2;	   
	}
	elsif ( $$e1{expiration} == $$e2{expiration} ) {
	    print "Chose e1 (WARNING, equal expiration)\n" if $DEBUG;
	    return $e1;
	}
    }

    # Fallback
    print "Warning: Falling back to e1 entry in compare: $$e1{MAC} -- e1:$$e1{status},$$e1{expiration},$$e1{Role} -- e2:$$e2{status},$$e2{expiration},$$e2{Role}\n" if $DEBUG;
    return $e1;
}

# Convert Bradford date to 20140420 format
sub convertDate {
    my $date = shift;

    my %mon2num = qw(
		     Jan 01  Feb 02  Mar 03  Apr 04  May 05  Jun 06
		     Jul 07  Aug 08  Sep 09  Oct 10 Nov 11 Dec 12
		);

    my ( $j, $mon, $day, $time, $tz, $year ) = split( /\s+/, $date );

    $mon = $mon2num{$mon};
    
    return "$year$mon$day";

}

sub parseConfig() {
    # Create any variables that do not exist to avoid errors
    my $config = AppConfig->new({
                                 CREATE => 1,
                                });

    $config->define( "nac_file=s", "datadir=s", "bradford_clients=s" );

    $config->file( "$config_file" );

    my $datadir = $config->datadir();

    if ( $config->nac_file() && !$optoutfile ) {
	$optoutfile = "$datadir/" . $config->nac_file();
    }

    if ( $config->bradford_clients() && !$optinfile ) {
        $optinfile = "$datadir/" . $config->bradford_clients();
    }
    
}


sub usage() {
    print <<USAGE;
    Usage: bradford.pl [options] 

      -o file          Output NAC Data File
      -i files         Input Client Dump File
      -p files         Input Profiled Device Dump
      -conf file       Use a different configuration file
      -v               Verbose output

USAGE
    exit;
}
