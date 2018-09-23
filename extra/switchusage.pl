#!/usr/bin/perl
# Calculates the ratio of connected to notconnect ports from int status
# The higher the ratio, the higher the number of unused ports

use strict;

open ( INTSTATUS, "/opt/netdb/data/intstatus.txt" ) or die;

my %connected;
my %notconnect;
my %total;
my %ratio;

my @output;

while ( my $line = <INTSTATUS> ) {
    @output = split( /\,/, $line );

    if ( $output[2] eq "connected" ) {
	$connected{ "$output[0]" }++;
    }
    elsif ( $output[2] eq "notconnect" ) {
        $notconnect{ "$output[0]" }++;
    }
    $total{ "$output[0]" }++;
    #print "$output[0]: $total{$output[0]}\n";
}


while ( my ($key, $value) = each(%notconnect) ) {
#    print "$key => $value\n";
    if ( $connected{$key} != 0 ) {
	$ratio{$key} = $value / $connected{$key};
    }
    else {
	$ratio{$key} = $value;
    }
}


#while ( my ($key, $value) = each(%ratio) ) {
#    print "$key => $value\n";          
#}

open ( DEVICES, "/scripts/inventory/versions.txt" );

my %devices;
my @device;

while ( my $line = <DEVICES> ) {
    @device = split(/\s+/, $line );

    $devices{$device[0]} = $device[1];
}

foreach my $key (sort hashsort (keys(%ratio)) ) {
#    if ( $ratio{$key} > 1 ) {
	print "$key: $ratio{$key} - Total Ports: $total{$key}\n";
#    }
}


sub hashsort {
   $ratio{$b} <=> $ratio{$a};
}

