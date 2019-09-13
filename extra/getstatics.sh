#!/bin/sh

# Pull static addresses from Bluecat DNS/DHCP

psql -U postgres -d proteusdb -h ipam-server -c "select long2ip4(long1) from entity where long2='771';" > /opt/netdb/data/statics2.txt
psql -U postgres -d proteusdb -h ipam-server -c "select long2ip4(long1) from entity where long2='515';" >> /opt/netdb/data/statics2.txt
psql -U postgres -d proteusdb -h ipam-server -c "select long2ip4(long1) from entity where long2='0';" >> /opt/netdb/data/statics2.txt

rm /opt/netdb/data/statics.txt

cat /opt/netdb/data/statics2.txt | perl -nle 's/^\s//; print $_ if /^\d+.\d+.\d+.\d+$/' >> /home/nst/statics.txt

