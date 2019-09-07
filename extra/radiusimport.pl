#!/usr/bin/perl
#
use strict;
use warnings;

# Get Radius Data
`/opt/netdb/extra/radiususers.pl | sort | uniq > /opt/netdb/data/radius.csv`;

# Import Data in to NetDB
`/opt/netdb/netdbctl.pl -k /var/lock/netdbradius.lock -nf radius.csv -n`

