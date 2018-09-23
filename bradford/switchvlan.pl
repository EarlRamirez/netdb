#!/usr/bin/perl
# Call the change vlan script on bradford pods defined in nac1-ctrl.nst.musc.edu
# Relies on ssh keys belonging to www-data to be present on the remote server
use Socket;
use strict;
use warnings;

no warnings 'uninitialized';


# NAC Servers
my @nac_servers = ( "nac1-ctrl.nst.musc.edu", "nac2-ctrl.nst.musc.edu" );
my $DEBUG = 0;


#Parse Input
my @tmp = split( /\,/, $ARGV[0]);
my @output;


my $switch = $tmp[0];
my $port = $tmp[1];
my $vlan = $tmp[2];
my $host;

# Lowercase port
$port = lc( $port );

# Lookup IP of hostname
my $packed_ip = gethostbyname($switch);
if (defined $packed_ip) {
    $switch = inet_ntoa($packed_ip);
}

#print "$switch $nac_servers[0]\n";

my $cmd = "/bsc/campusMgr/bin/RunClient SwitchVlan.class -ip $switch -port $port -vlan $vlan";

print "CMD: $cmd\n" if $DEBUG;

# Call the switch command on each host
foreach my $server (@nac_servers) {

    ( $host ) = split( /\./, $server ); 
    print "\nConnecting to $server to switch port:\n";
    @output = `ssh nst\@$server \'$cmd\'`;

    foreach my $line ( @output ) {
	print "$host: $line\n";
    }
}

