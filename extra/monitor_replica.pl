#!/usr/bin/perl
#
# Run check_replication, if it returns anything but OK, send an email
#
use strict;
use Net::SMTP;
use File::Basename;

my $to = 'yantisj@musc.edu';
my @output;
my ( $min, $hour, $wday ) = (localtime)[1,2,6];

my $scriptdir = &File::Basename::dirname($0);
my ($scriptname) = &File::Basename::fileparse($0);
my $line;

# Run command and capture all output, including STDERR
open(PH, "/scripts/netdb/extra/check_replication.pl 2>&1 |");                 # with an open pipe
$output[0] = <PH>;



if ( $output[0] !~ /OK/ ) {

    my $smtp = Net::SMTP->new("hal.musc.edu");
    
    $smtp->mail('script@hal.musc.edu');
    $smtp->to($to);
    
    $smtp->data();
    $smtp->datasend("From: script\@hal.musc.edu\n");
    $smtp->datasend("To: $to\n");
    $smtp->datasend("Content-Type: text/plain\n");
    $smtp->datasend("Subject: NetDB Replication Failure\n");
    $smtp->datasend("\n");
    
    $smtp->datasend("$output[0]");
    $smtp->datasend("\nExecuted Script: $scriptdir/$scriptname @ARGV\n");

    $smtp->dataend();
}

elsif ( $wday == 3 && $hour == 8 ) {
    my $smtp = Net::SMTP->new("hal.musc.edu");

    $smtp->mail('script@hal.musc.edu');
    $smtp->to($to);

    $smtp->data();
    $smtp->datasend("From: script\@hal.musc.edu\n");
    $smtp->datasend("To: $to\n");
    $smtp->datasend("Content-Type: text/plain\n");
    $smtp->datasend("Subject: NetDB Replication to Styx OK\n");
    $smtp->datasend("\n");

    $smtp->datasend("Weekly Report on NetDB Replication OK\n");
    $smtp->datasend("Executed Script: $scriptdir/$scriptname @ARGV\n");

    $smtp->dataend();
}

