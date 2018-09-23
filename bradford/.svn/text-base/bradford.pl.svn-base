#!/usr/bin/perl
# Bradford Custom Integration Script
#
# - Pulls registration data from Bradford NAC and puts the data in to nac.csv file
# - Configured from netdb.conf
# - Requires a user on the Bradford server and the MySQL view below to be applied 
#   to the bsc database.
#
# File Format: mac,regtime,firstName,lastName,userID,email,phone,device_type,Org_Entity,critical[Critical|Non-Critic]
#
# mac and userID required, the rest is optional data
# 
####################################################################################
# SQL view required on Bradford server:
#
# !! DEPRECATED, not required anymore !!
# 
# create or replace view macreg as select p.mac, MAX(p.time) AS time,p.firstName,p.lastName,p.userID,u.email,p.phone,p.city 
# AS type,p.state AS entity,p.zipcode AS critical from REGISTRATIONS AS p 
# LEFT JOIN USERRECORD AS u ON p.userID=u.userID GROUP BY mac ORDER BY time;
#
####################################################################################
#
#use Net::CiscoHelper;   # yantisj's helper module
use Getopt::Long;
use AppConfig;
use English qw( -no_match_vars );
use DBI;
use strict;
use warnings;

# no nonsense
no warnings 'uninitialized';

my $bradford_query = "select p.mac, MAX(p.time) AS time,p.firstName,p.lastName,p.userID,u.email,p.phone,p.city 
                      AS type,p.state AS entity, u.directoryPolicyValue AS attribute from REGISTRATIONS AS p 
                      LEFT JOIN USERRECORD AS u ON p.userID=u.userID GROUP BY mac ORDER BY time";

my $DEBUG          = 0;
my $config_file    = "/etc/netdb.conf";

my ( $optoutfile, $bhost, $buser, $bpass, $cli_host );


# Input Options
if ( $ARGV[0] eq "" ) { &usage(); }

GetOptions(
    'o=s'  => \$optoutfile,
    's=s'  => \$cli_host,
    'conf=s' => \$config_file,
    'v'    => \$DEBUG,
	  )
or &usage();

# Parse Configuration File
&parseConfig();

# CLI Server override
$bhost = $cli_host if $cli_host;

if ( $optoutfile ) {
 
    open( OUTFILE, ">$optoutfile" ) or die "Can't open $optoutfile: $!\n";

    my @hosts = split( /\,/, $bhost );
   
    foreach my $host ( @hosts ) {
	
	my $dbh = DBI->connect("dbi:mysql:bsc:$host", "$buser", "$bpass");

	my $select1_h = $dbh->prepare( $bradford_query );	

	$select1_h->execute();
	
	while ( my $row = $select1_h->fetchrow_hashref() ) {
	    
	    my $critical;

	    $$row{firstName} =~ s/\,//g;
	    $$row{LastName} =~ s/\,//g;
	    $$row{type} =~ s/\,//g;
	    $$row{entity} =~ s/\,//g;
	    
	    $$row{entity} = "MUSC / Affiliates" if $$row{entity} eq "MU";
	    $$row{entity} = "Personal" if $$row{entity} eq "Pe";
	    $$row{entity} = "Vendor / Business Partner" if $$row{entity} eq "Ve";
	    $critical = 1 if $$row{attribute} eq "life-safety";
	    
	    print OUTFILE "$$row{mac},$$row{time},$$row{firstName},$$row{lastName},$$row{userID},$$row{email},$$row{phone},$$row{type},$$row{entity},$critical\n";
	}
    }
    close OUTFILE;
}
else {
    print "Error: Must use -o option\n";
}

sub parseConfig() {
    # Create any variables that do not exist to avoid errors
    my $config = AppConfig->new({
                                 CREATE => 1,
                                });

    $config->define( "bradford_host=s", "bradford_user=s", "bradford_pass=s" );

    $config->file( "$config_file" );

    $bhost = $config->bradford_host();
    $buser = $config->bradford_user();
    $bpass = $config->bradford_pass();
    
    
}


sub usage() {
    print <<USAGE;
    Usage: bradford.pl [options] 

      -o file          Output Mac table to a file
      -s server        Query a different NAC server
      -conf file       Use a different configuration file
      -v               Verbose output

USAGE
    exit;
}
