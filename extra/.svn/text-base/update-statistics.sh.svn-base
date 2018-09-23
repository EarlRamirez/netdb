#!/bin/sh
#
# Update statistics for MRTG
# 
# This script is highly customized for MUSC and very hackish.  The script creates the data for MRTG graphs
# in the mrtg.conf file.  Take what you want from it for your own statistics, but some of it will make
# not sense in your environment.
#
# Make sure to run 1 minute BEFORE MRTG runs.  See the sample crontab file.
#
export LANG=C
## MAC based Graphs
#
# Gather NetDB Statistics
/opt/netdb/netdb.pl -st > /opt/netdb/data/netdbstats.txt
/opt/netdb/netdb.pl -st -h 1 > /opt/netdb/data/netdbhourlystats.txt
/opt/netdb/netdb.pl -st -h 24 > /opt/netdb/data/netdbdailystats.txt
/opt/netdb/netdb.pl -st -d 30 > /opt/netdb/data/netdbmonthlystats.txt

## Arp table data (real-time data from the file, rather than the DB)
cat /opt/netdb/data/arptable.txt | wc -l > /opt/netdb/data/mrtgarpcount.txt
tail /opt/netdb/data/mrtgarpcount.txt >> /opt/netdb/data/mrtgarpcount.txt
tail /opt/netdb/data/mrtgarpcount.txt >> /opt/netdb/data/mrtgarpcount.txt

# Switchport entries per run of maccount (real-time)
cat /opt/netdb/data/mactable.txt | wc -l > /opt/netdb/data/mrtgdevcount.txt
cat /opt/netdb/data/mactable.txt | wc -l >> /opt/netdb/data/mrtgdevcount.txt
cat /opt/netdb/data/mactable.txt | wc -l >> /opt/netdb/data/mrtgdevcount.txt
cat /opt/netdb/data/mactable.txt | wc -l >> /opt/netdb/data/mrtgdevcount.txt

# MAC Entries from NetDB over the past hour (from the DB)
cat /opt/netdb/data/netdbhourlystats.txt | grep "MAC Entries" | perl -nle '@tmp = split(/:\s+/); print $tmp[1]' > /opt/netdb/data/mrtgmaccount.txt
tail -1 /opt/netdb/data/mrtgmaccount.txt >> /opt/netdb/data/mrtgmaccount.txt
tail -1 /opt/netdb/data/mrtgmaccount.txt >> /opt/netdb/data/mrtgmaccount.txt
tail -1 /opt/netdb/data/mrtgmaccount.txt >> /opt/netdb/data/mrtgmaccount.txt

# MAC Entries over 7 days (for a steady long term growth chart)
/opt/netdb/netdb.pl -st -d 7 | grep "MAC Entries" | perl -nle '@tmp = split(/:\s+/); print $tmp[1]' > /opt/netdb/data/mrtg7day.txt
tail -1 /opt/netdb/data/mrtg7day.txt >> /opt/netdb/data/mrtg7day.txt
tail -1 /opt/netdb/data/mrtg7day.txt >> /opt/netdb/data/mrtg7day.txt
tail -1 /opt/netdb/data/mrtg7day.txt >> /opt/netdb/data/mrtg7day.txt

# Total ARP Table Count
cat /opt/netdb/data/netdbstats.txt | grep "ARP" | perl -nle '@tmp = split(/:\s+/); print $tmp[1]' > /opt/netdb/data/mrtgtotarpcount.txt
tail -1 /opt/netdb/data/mrtgtotarpcount.txt >> /opt/netdb/data/mrtgtotarpcount.txt
tail -1 /opt/netdb/data/mrtgtotarpcount.txt >> /opt/netdb/data/mrtgtotarpcount.txt
tail -1 /opt/netdb/data/mrtgtotarpcount.txt >> /opt/netdb/data/mrtgtotarpcount.txt

# Connected Ports (real-time)
grep connected /opt/netdb/data/intstatus.txt | wc -l > /opt/netdb/data/mrtgconnected.txt
tail /opt/netdb/data/mrtgconnected.txt >> /opt/netdb/data/mrtgconnected.txt
tail /opt/netdb/data/mrtgconnected.txt >> /opt/netdb/data/mrtgconnected.txt

# Total Ports (from the DB)
cat /opt/netdb/data/netdbstats.txt | grep "Status Entries" | perl -nle '@tmp = split(/\:\s+/); print $tmp[1];' > /opt/netdb/data/mrtgtotalports.txt
tail /opt/netdb/data/mrtgtotalports.txt >> /opt/netdb/data/mrtgtotalports.txt
tail /opt/netdb/data/mrtgtotalports.txt >> /opt/netdb/data/mrtgtotalports.txt

# Total Rows in NetDB Database
cat /opt/netdb/data/netdbstats.txt | grep "Total Rows" | perl -nle '@tmp = split(/\:\s+/); print $tmp[1];' > /opt/netdb/data/mrtgdbrows.txt
tail /opt/netdb/data/mrtgdbrows.txt >> /opt/netdb/data/mrtgdbrows.txt
tail /opt/netdb/data/mrtgdbrows.txt >> /opt/netdb/data/mrtgdbrows.txt

# Get new macs in the past hour to graph
/opt/netdb/netdb.pl -nm -mr -h 1 > /opt/netdb/data/newmacslasthour.txt

# NetDB Version
/opt/netdb/netdb.pl | head -1 > /opt/netdb/data/netdbversion.txt

