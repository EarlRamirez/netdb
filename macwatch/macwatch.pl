#!/usr/bin/perl
###########################################################################
# macwatch.pl - MAC address alert/watch Plugin
# Author: Andrew Loss <aterribleloss@gmail.com>
# Copyright (C) 2013 Andrew Loss
###########################################################################
# 
# MAC watch allows for alerting of networkind staff when a MAC
# that is stored in the database to be watched is seen on the network.
#  The default eamil list is the list of email that will set to be paged
# when a new MAC is added, unless the -e option is used to override it.
#  The offset is how far back (in seconds) that you want to check back in
# the database, mostlikly want to set this to double what your polling the
# polling interval. The offset can be set from the command line with the 
# -s option followed by an interger, otherwise it wil default to 10 minutes.
# that is stored in the database to be watched is seen on the network.
#  Enableing command execution could pose a security risk to the box netdb
# is running on and you network. If you do decicde to enable command
# execution for when a device is detected, be sure that the interface is 
# secure and that the script that is to be run as been thoughly tested.
#
###########################################################################
##  MAC maniputlation options:
# -m The MAC maniputlation option. show the information on a MAC address using:
#       macwatch.pl -m 00:00:00:00:00:00
# To add a MAC to the watch list use the following (if the MAC already exists in
#   the table then this will change the note):
#       macwatch.pl -m 00:00:00:00:00:00 -a "some use full info about the entry"
# To override the default email list when adding a MAC address, or overwrite an
#   existing email list for a MAC. Each email must be seprately declared, and the
#   -a opton must be specified if it is a new MAC. Overwriting the default list:
#       macwatch.pl -m 00:00:00:00:00:00 -e "admin@example.net" -e "security@mail.net"
# -i when combined with -m option toggles the activity flag of a MAC, taking it in or 
#   out of polling.
#       macwatch.pl -m 00:00:00:00:00:00 -i
# -c when combined with the -m and -a option is used stores a command to be run by
#   the netdb user when the MAC is discovered on the network. Command requires
#   a command parameter that is executable by netdb.
#        macwatch.pl -m 00:00:00:00:00:00 -a "a note" -c "shutdownScript.sh"
# -f when combined with the -m option sets MAC as found and takes it out of polling.
#   found requires a note parameter, which is how it was found and by who.
#        macwatch.pl -m 00:00:00:00:00:00 -f "Police found it at a pawn shop"
#
##  Polling options:
# -s (offset) runs the operations that test to see if the MAC address has recently
#   been seen on the network. The offset is optional and in seconds, the default is 10 seonds.
#       macwatch.pl -s -f 6005
#
##  Listing Options:
#    -l            Display all MAC addresses in the watch table.
#    -l a          Display all active check MACs in the watch table.
#    -l f          Display all found MACs in the watched table.
#
###########################################################################
# License:
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details:
# http://www.gnu.org/licenses/gpl.txt
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
###########################################################################
#

use NetDB;
use DBI;
use Getopt::Long;
use strict;

# command line options
my ( $optcheck, $optmac, $optaddnote, $optfoundnote, $optinactive, $optlist, $optdelete, $optcmd, @optemails);
# Debuging level
my $DEBUG = 0;
# Enable command execution
my $enableCMD = 0;
# Default list of people to e-mail
my @default_emails = ( 'someone@someplace.edu','admin@net.example.com',
                      );
#URL of the web front end to NetDB (including netdb.pl)
my $netdbURL = "https://server.example.com/cgi-bin/netdb.pl";

## Time (in seconds) of how far back to chek the rusults for,
#  Should probably be doulble what you polling interval is.
my $offset = 600;   # 10 minutes

GetOptions(
    's:1'     => \$optcheck,
    'm=s'     => \$optmac,
    'a=s'     => \$optaddnote,
    'f=s'     => \$optfoundnote,
    'e=s'     => \@optemails,
    'c=s'     => \$optcmd,
    'i'       => \$optinactive,
    'd'       => \$optdelete,
    'l:s'     => \$optlist,
    'debug=i' => \$DEBUG,
    'v'       => \$DEBUG,
    'vv'      => \$DEBUG,
          ) or &usage();

# Colums in the table macwatch.
my @cols = ('mac','active','entered','enteruser','note','found','foundon','foundnote','switch','lastalert', 'email', 'alertcmd');

# check for Flaged MAC on the network.
if($optcheck) {
    # set the offset of polling
    if($optcheck>1){$offset = $optcheck;}
    #open up a database connection with NetDB
    my $dbh = NetDB::connectDBrw();
    print "|DEBUG|: searching for watched MAC addresses\n" if $DEBUG;
    # Search for watched MACs on the network.
    my $netdbAlert_ref = checkWatchedMACs( $dbh, $offset );
    my %notices;
    # flag as sending alert
    print "|DEBUG|: Setting flag of found MACs\n" if $DEBUG>1;
    setMACAlert( $dbh, $netdbAlert_ref);
    # convert the MACs to : form
    $netdbAlert_ref = convertMacFormat( $netdbAlert_ref, 'ieee_colon' );

    my @netdbWatch = @$netdbAlert_ref;
    my $netdbWatch_len = @netdbWatch;
    # Format alert e-mails.
    print "|DEBUG|: Generating e-mail for ".($netdbWatch_len)." MAC(s) found\n" if $DEBUG>1;
    for (my $i=0; $i < $netdbWatch_len; $i++) {
        my $mac = $netdbWatch[$i]{mac};
        print "|DEBUG|: preparting alert for $mac\n" if $DEBUG>3;
        next unless ($netdbWatch[$i]{mac});

        $notices{$mac}{alert} = generateAlert($netdbWatch[$i]);
        $notices{$mac}{email} = $netdbWatch[$i]{email};
    }

    # email the results
    foreach my $mac (keys %notices){
        print "|SENDING|:\n$notices{$mac}{alert}" if $DEBUG>2;
        # email the results
        emailAlert( "MAC Watch Alert: $mac", $notices{$mac}{alert}, $notices{$mac}{email} );
    }
}
# add a device to the watch table
# or mark a device as found.
elsif($optmac ){
    my $mac = getCiscoMac($optmac);
    
    if($optaddnote || $optfoundnote || $optinactive || @optemails || $optdelete){
        my $dbh = NetDB::connectDBrw();
        my $user = getlogin();
        my $mac_ref = getWatchedMAC( $dbh, $mac );
        my @watchedMACs = @$mac_ref;
        my $email;
        my @emails;

        if($optemails[0]){
            foreach my $address (@optemails){
                if($address =~ /[a-zA-Z0-9\.]+[@][a-zA-Z0-9\.]+\.[a-zA-Z0-9]+/){
                    push (@emails,$address);
                }
                else{
                    print "|Warning|: $address is invalid email address.\n" if $DEBUG;
                }
            }
        }
        else{ @emails = @default_emails};

        if($optaddnote || @optemails){
            if( $mac eq $watchedMACs[0]{mac} ){
                if(!defined(@optemails)){
                    $email = $watchedMACs[0]{email};
                }
                else{
                    $email = join ',',@emails;
                }
                print "|Warning|: MAC: $optmac is already in the list; user: $user updating notes and/or emails.\n";
                alterMACInfo( $dbh, $mac, $optaddnote, $email);
            }
            else{
                $email = join ',',@emails;
                if( $enableCMD ){
                    addWatchMAC( $dbh, $mac, $optaddnote, $user, $email, $optcmd );
				}
                else{
                    addWatchMAC( $dbh, $mac, $optaddnote, $user, $email );
                }
                print "|DEBUG|: MAC: $optmac added to watchlist by $user.\n" if $DEBUG;
            }
        }
        elsif($optfoundnote){
            if( $mac eq $watchedMACs[0]{mac} ){
                setMACFound( $dbh, $mac, $optfoundnote, $user );
                print "|DEBUG|: MAC: $optmac marked as found.\n" if $DEBUG;
            }
            else{
                print "|ERROR|: MAC: $optmac is not on the watch list, can not mark as found.\n";
            }
        }
        elsif($optinactive){
            if( $mac != $mac_ref ){

                if(toggleMACActive( $dbh, $mac )){
                    print "|DEBUG|: MAC: $optmac marked as active.\n" if $DEBUG;
                }
                else{
                    print "|DEBUG|: MAC: $optmac marked as inactive.\n" if $DEBUG;
                }
            }
            else{
                print "|ERROR|: MAC: $optmac is not on the watch list, can not set inactive.\n";
            }
        }
        elsif($optdelete){
            print "Preparing to delete $optmac\n";
            if( $mac eq $watchedMACs[0]{mac} ){
                print "Confirm Deletion of $optmac. [yes/no]: ";

                my $confirmation = <STDIN>;
                if ( $confirmation =~ /yes/ ) {
                    print "Deleting $optmac from watch list database...";
	                removeMAC( $dbh, $mac );
                    print "done.\n\n";
                }
            }
            else{
                die "MAC: $optmac does not exist on the watch list, exiting.\n";
            }
        }
        else{
            die "|ERROR|: a fatal error has occurred, exiting!\n";
            # This is really bad if we get here.
        }
    }
    else{
        my $dbh = NetDB::connectDBro();
        
        my $netdb_ref = getWatchedMAC($dbh,$mac);
        $netdb_ref = convertMacFormat( $netdb_ref, 'ieee_colon' );
        my @reports = macReport($netdb_ref);
        
        ## display the results
        print "Results mactching: $mac\n";
        foreach my $macRes (@reports){
            print "$macRes\n";
        }
    }
}
# display various lists from the table
elsif(defined $optlist){
    my $dbh = NetDB::connectDBro();
    my $netdb_ref = undef;
    my @reports;

    if($optlist eq 'a'){
        $netdb_ref = getActiveWatchedMACs($dbh);
        $netdb_ref = convertMacFormat( $netdb_ref, 'ieee_colon' );
        @reports = macReport($netdb_ref);
        print "All actively watched MACs:\n";
    }
    elsif($optlist eq 'f'){
        $netdb_ref = getFoundMACs($dbh);
        $netdb_ref = convertMacFormat( $netdb_ref, 'ieee_colon' );
        @reports = macReport($netdb_ref);
        print "All found MACs:\n";
    }
    elsif($optlist eq ''){
        $netdb_ref = getWatchedMACs($dbh);
        $netdb_ref = convertMacFormat( $netdb_ref, 'ieee_colon' );
        @reports = macReport($netdb_ref);
        print "All watched MACs:\n";
    }

    # display the results
    if ($reports[0]){
        foreach my $macRes (@reports){
            print "$macRes\n";
        }
    }
}
else{
    usage();
}

#################
##             ##
##  FUNCTIONS  ##
##             ##
#################

# email data information
sub emailAlert {
    my $subject = shift;
    my $body = shift;
    my $addresses = shift;
    my $host = `hostname -s`.".".`hostname -d`;
    $host =~ s/[\r\n]//g;
    my $from = getlogin || getpwuid($<) || "netdb";
    #$addresses = join ',',@emails;
    if ( $addresses && $body && $subject ){
        print "E-mailing found MAC to $addresses\n" if $DEBUG;
        open(MAIL, "|/usr/sbin/sendmail -t");
        print MAIL "To: $addresses\n";
        print MAIL "From: ".$from."\@$host\n";
        print MAIL "Subject: $subject\n";
        print MAIL "MIME-Version: 1.0\n";
        print MAIL "Content-Type: text/html; charset=ISO-8859-1\n";
        print MAIL "<html>\n<body>\n";
        print MAIL $body;
        print MAIL "</body>\r</html>";
        close(MAIL);
    }
    else{
        print "No information to send\n" if $DEBUG;
    }
}
# Report on MAC address
sub macReport {
    my $netdb_ref = shift;
    my $macInfo;
    my @macReport;

    my @netdbWatch = @$netdb_ref;
    my $netdbWatch_len = @netdbWatch;
    for (my $i=0; $i < $netdbWatch_len; $i++) {
        next unless ($netdbWatch[$i]{mac});
        print "|DEBUG|: Watched MAC: $netdbWatch[$i]{mac}\n" if $DEBUG>4;
        # formating
        if ($netdbWatch[$i]{active}){ $netdbWatch[$i]{active} = "YES"; }
        else{ $netdbWatch[$i]{active} = "NO"; }
        
        $macInfo = undef;
        $macInfo = "Watched MAC:\t$netdbWatch[$i]{mac}\n";
        $macInfo .= "  + Activly checked: ".$netdbWatch[$i]{active}."\n";
        $macInfo .= "  + Entered on:      ".$netdbWatch[$i]{entered}."\n";
        $macInfo .= "  + Entered by:      ".$netdbWatch[$i]{enteruser}."\n";
        $macInfo .= "  + Notes:           ".$netdbWatch[$i]{note}."\n";
        $macInfo .= "  + Last alert:      ".$netdbWatch[$i]{lastalert}."\n";
        if ( $enableCMD && $netdbWatch[$i]{alertcmd}){
            $macInfo .= "  + cmd to be run:   ".$netdbWatch[$i]{alertcmd}."\n";
        }
        $macInfo .= "  + Last seen on:    ".$netdbWatch[$i]{switch}."\n";
        if ($netdbWatch[$i]{found}){
            $macInfo .= "  + Found:           ".$netdbWatch[$i]{foundon}."\n";
            $macInfo .= "  + Found set by:    ".$netdbWatch[$i]{foundby}."\n";
            $macInfo .= "  + Found notes:     ".$netdbWatch[$i]{foundnote}."\n";
        }
        else{
            $macInfo .= "  + Found:           NO\n";
        }
        $macInfo .= "  + To be contacted: ".$netdbWatch[$i]{email}."\n";

        push(@macReport, $macInfo);
    }
    return @macReport;
}
# take a netdb refrence and returns an array of alerts
sub generateAlert {
    #my %netdbAlert = shift;
    my $netdbAlert_ref = shift;
    my ($alert, $cmdOut);

    my %netdbAlert = %$netdbAlert_ref;

    if($netdbAlert{mac}){
        print "|DEBUG|: Found watched MAC: ".$netdbAlert{mac}." \n" if $DEBUG>3;
        $alert = undef; $cmdOut = undef;
        $alert = "<table>\n";
        $alert .= " <tr>\n  <td colspan=2><h2>WATCHED MAC ALERT</h2>\n</td>\n </tr>\n";
        $alert .= " <tr>\n  <td><b>MAC Address:</b></td>\n".
                  "  <td><a href=\"$netdbURL?address=".$netdbAlert{mac}.
                  "&days=7\" title=\"MAC address\">".$netdbAlert{mac}."</a></td>\n </tr>\n";
        $alert .= " <tr>\n  <td>IP Address:</td>\n  <td>".$netdbAlert{lastip}."</td>\n </tr>\n";
        $alert .= " <tr>\n  <td>Switch, Port:</td>\n  <td>".$netdbAlert{lastswitch}.",&nbsp;".$netdbAlert{lastport}."</td>\n </tr>\n";
        $alert .= " <tr>\n  <td>VLAN:</td>\n  <td>".$netdbAlert{vlan}."</td>\n </tr>\n";
        $alert .= " <tr>\n  <td>First Seen:</td>\n  <td>".$netdbAlert{firstseen}."</td>\n </tr>\n";
        $alert .= " <tr>\n  <td>Last Seen:</td>\n  <td>".$netdbAlert{lastseen}."</td>\n <tr>\n";
        if ($netdbAlert{userID}){
            $alert .= " <tr>\n  <td>Registration Info:</td>\n  <td>".$netdbAlert{userID}."</td>\n </tr>\n";
            $alert .= " <tr>\n  <td>fName:</td>\n  <td>".$netdbAlert{firstName}."</td>\n  <td>lName:</td>\n  <td>".$netdbAlert{lastName}."</td>\n </tr>\n";
        }
        $alert .= " <tr>\n  <td>Added to list:</td>\n  <td>".$netdbAlert{entered}."</td>\n </tr>\n";
        $alert .= " <tr>\n  <td>Added by:</td>\n  <td>".$netdbAlert{enteruser}."</td>\n </tr>\n";
		if ( $enableCMD && $netdbAlert{alertcmd} ){
			$cmdOut = `$netdbAlert{alertcmd}`;
			print "|DEBUG|: Alert for MAC: ".$netdbAlert{mac}." ran command: ".$netdbAlert{alertcmd}."\n" if $DEBUG>3;
			$alert .= " <tr>\n  <td>CMD run: </td>\n  <td> YES </td>\n </tr>\n";
		}
        $alert .= " <tr>\n  <td colspan=2><b>Notes:</b></td>\n </tr>".
                  " <tr>\n  <td colspan=2>&nbsp;".$netdbAlert{note}."</td>\n <tr>\n</table>\n<br>\n";
        return $alert;
    }
    return undef;
}

########################
##                    ##
## DATABASE FUNCTIONS ##
##                    ##
########################
# check MACs in database
sub checkWatchedMACs {
    my $dbh = shift;
    my $offset = shift;
    my $counter = 0;
    my @netdbBulk;

    # my @tables = ("supermac","macwatch");
    # my @cols = ("supermac.mac","macwatch.note","macwatch.entered","supermac.lastip","supermac.name","supermac.vlan","supermac.lastswitch",
    #             "supermac.lastport","supermac.firstseen","supermac.lastseen","supermac.userID","supermac.firstName","supermac.lastName");

    if ( !$dbh ) {
        die ("|ERROR|: No database handle, check your input");
    }
    # my $tables = join ',',map {$dbh->quote_identifier($_)} @tables;
    # my $cols = join ',',map { $dbh->quote_identifier($_) } @cols;
    print "|DEBUG|: Querying database for watched MAC addresses\n" if $DEBUG>1;
    my $sth = $dbh->prepare("SELECT supermac.mac,macwatch.note,macwatch.entered,macwatch.enteruser,
                macwatch.email,macwatch.alertcmd,supermac.lastip,supermac.name,supermac.vlan,
                supermac.lastswitch,supermac.lastport,supermac.firstseen,supermac.lastseen,
                supermac.userID,supermac.firstName,supermac.lastName
            FROM netdb.supermac,netdb.macwatch
            WHERE supermac.mac = macwatch.mac
            AND macwatch.active = 1
            AND supermac.lastseen > DATE_SUB(NOW(),INTERVAL ? SECOND)
            AND ((supermac.lastswitch != macwatch.switch
                OR macwatch.switch IS NULL)
            OR (macwatch.lastalert < DATE_SUB(NOW(),INTERVAL ? SECOND)
                OR macwatch.lastalert IS NULL))");
    $sth->execute( $offset, 3600 );

    while ( my $row = $sth->fetchrow_hashref() ) {
        if ($row){
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }
    my $netdb_ref = NetDB::shortenV6( \@netdbBulk );
    return $netdb_ref;
}
# pull all watched MACs from database
sub getWatchedMACs {
    my $dbh = shift;
    my $counter = 0;
    my @netdbBulk;

    if ( !$dbh ) {
        die ("|ERROR|: No database handle, check your input");
    }
    my $quotedCols = join(",",map( $dbh->quote_identifier($_), @cols));
    my $sth = $dbh->prepare("SELECT $quotedCols FROM macwatch ORDER BY mac");

    $sth->execute();

    while ( my $row = $sth->fetchrow_hashref() ) {
        if ($row){
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }
    my $netdb_ref = NetDB::shortenV6( \@netdbBulk );
    return $netdb_ref;
}
# search MAC in database
sub getWatchedMAC {
    my $dbh = shift;
    my $mac = shift;
    my $counter = 0;
    my @netdbBulk;

    if ( !$dbh ) {
        die ("|ERROR|: No database handle, check your input");
    }
    if ( $mac !~ /[0-9A-Fa-f]{4}(\.[0-9A-Fa-f]{4}){2}/ ) {
        die ("|ERROR|: Invalid MAC address, check your input");
    }
    # paramaterize query
    my $quotedTable = $dbh->quote_identifier("macwatch");
    my $quotedCols = join(",",map( $dbh->quote_identifier($_), @cols));
    my $quotedColMac = $dbh->quote_identifier($cols[0]);
    # prepare query
    my $sth = $dbh->prepare("SELECT $quotedCols FROM $quotedTable WHERE $quotedColMac=? ORDER BY $quotedColMac");
    print "|DEBUG|: running: SELECT $quotedCols FROM $quotedTable WHERE $quotedColMac=? ORDER BY $quotedColMac\n" if $DEBUG>5;
    $sth->execute( $mac );

    while ( my $row = $sth->fetchrow_hashref() ) {
        if ($row){
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }
    my $netdb_ref = NetDB::shortenV6( \@netdbBulk );
    return $netdb_ref;
}
# pull actively watched MACs from database
sub getActiveWatchedMACs {
    my $dbh = shift;
    my $counter = 0;
    my @netdbBulk;

    if ( !$dbh ) {
        die ("|ERROR|: No database handle, check your input");
    }

    my $quotedCols = join(",",map( $dbh->quote_identifier($_), @cols));
    my $sth = $dbh->prepare("SELECT $quotedCols FROM macwatch WHERE active = 1");

    $sth->execute();

    while ( my $row = $sth->fetchrow_hashref() ) {
        if ($row){
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }
    my $netdb_ref = NetDB::shortenV6( \@netdbBulk );
    return $netdb_ref;
}
# pull found MACs from database
sub getFoundMACs {
    my $dbh = shift;
    my $counter = 0;
    my @netdbBulk;

    if ( !$dbh ) {
        die ("|ERROR|: No database handle, check your input");
    }

    my $quotedCols = join(",",map( $dbh->quote_identifier($_), @cols));
    my $sth = $dbh->prepare("SELECT $quotedCols FROM macwatch WHERE found = 1 ORDER BY foundon");

    $sth->execute();

    while ( my $row = $sth->fetchrow_hashref() ) {
        if ($row){
            $netdbBulk[$counter] = $row;
            $counter++;
        }
    }
    my $netdb_ref = NetDB::shortenV6( \@netdbBulk );
    return $netdb_ref;
}
# add watched MAC to database
# MAC address must be in cisco form
sub addWatchMAC {
    my $dbh = shift;
    my $mac = shift;
    my $note = shift;
    my $user = shift;
    my $email = shift;
	my $cmd = shift;

    if ( !$dbh ) {
        die ("|ERROR|: No database handle, check your input");
    }

    # paramertize values
    my $quotedTable = $dbh->quote_identifier("macwatch");
    # mac,active,entered,enteruser,note,email
    my $cols = join ',',map { $dbh->quote_identifier($_) } @cols[0,1,2,3,4,10,11];
    my $sth = $dbh->prepare("INSERT INTO $quotedTable ($cols) VALUES (?,1,NOW(),?,?,?,?)");

    if ($mac !~ /[0-9a-fA-F]{4}(\.[0-9a-fA-F]{4}){2}/){
        die ("|ERROR|: Improperly formated MAC address, check your input");
    }

    $sth->execute( $mac, $user, $note, $email, $cmd );
}
# Alter notes on watched MAC
# MAC address must be in cisco form
sub alterMACInfo {
    my $dbh = shift;
    my $mac = shift;
    my $note = shift;
    my $emails = shift;

    if ( !$dbh ) {
        die ("|ERROR|: No database handle, check your input");
    }
    # paramertize values
    my $quotedTable = $dbh->quote_identifier("macwatch");
    my $noteCol = $dbh->quote_identifier($cols[4]);
    my $macCol = $dbh->quote_identifier($cols[0]);
    my $emailCol = $dbh->quote_identifier($cols[10]);

    my $sth = $dbh->prepare("UPDATE $quotedTable SET $noteCol=?, $emailCol=? WHERE $macCol=?");

    if ($mac !~ /[0-9a-fA-F]{4}(\.[0-9a-fA-F]{4}){2}/){
        die ("|ERROR|: Improperly formated MAC address, check your input");
    }

    $sth->execute( $note, $emails, $mac );
}
# update MACs to found in database
sub setMACFound {
    my $dbh = shift;
    my $mac = shift;
    my $fnote = shift;
    my $user = shift;

    if ( !$dbh ) {
        die ("|ERROR|: No database handle, check your input");
    }
    # paramertize values
    my $quotedTable = $dbh->quote_identifier("macwatch");
	#('mac','active','entered','enteruser','note','found','foundon','foundnote','switch','lastalert', 'email', 'alertcmd');
    my $sth = $dbh->prepare("UPDATE $quotedTable SET $cols[1]=0,$cols[5]=1,$cols[6]=NOW(),$cols[7]=? WHERE $cols[0]=?");

    if ($mac !~ /[0-9a-fA-F]{4}(\.[0-9a-fA-F]{4}){2}/){
        die ("|ERROR|: Improperly formated MAC address, check your input");
    }

    $sth->execute( $fnote,$mac );
}
# update MACs to alerted in database
sub setMACAlert {
    my $dbh = shift;
    my $netdbAlert_ref = shift;
    
    my @netdbAlert = @$netdbAlert_ref;
    my $netdbAlert_len = @netdbAlert;

    if ( !$dbh ) {
        die ("|ERROR|: No database handle, check your input");
    }
    # paramertize values
    my $quotedTable = $dbh->quote_identifier("macwatch");

    my $sth = $dbh->prepare("UPDATE $quotedTable SET lastalert=NOW(),switch=? WHERE mac=?");
    for (my $i=0; $i < $netdbAlert_len; $i++) {
        next unless ($netdbAlert[$i]{mac} =~ /[0-9a-fA-F]{4}(\.[0-9a-fA-F]{4}){2}/);
        # update alert information
        $sth->execute( $netdbAlert[$i]{lastswitch}, $netdbAlert[$i]{mac} );
    }
}
# Remove a MAC addresss from the watch list table
sub removeMAC {
    my $dbh = shift;
    my $mac = shift;
    
    if ( !$dbh ) {
        die ("|ERROR|: No database handle, check your input");
    }
    # paramertize values
    my $quotedTable = $dbh->quote_identifier("macwatch");
    my $sth = $dbh->prepare("DELETE FROM $quotedTable WHERE mac=?");

    if($mac !~ /[0-9a-fA-F]{4}(\.[0-9a-fA-F]{4}){2}/){
        die "|ERROR|: Invalid MAC address.";
    }
    # update active flag
    $sth->execute( $mac );
}
# Toggle the active flag for a MAC addresss
sub toggleMACActive {
    my $dbh = shift;
    my $mac = shift;
    my $sth = undef;    # place holder for query
    my $flag = undef;   # used for returning which way the flag was toggled
    
    if ( !$dbh ) {
        die ("|ERROR|: No database handle, check your input");
    }

    my $netdb_ref = getWatchedMAC($dbh,$mac);
    my @netdb = @$netdb_ref;

    # paramertize values
    my $quotedTable = $dbh->quote_identifier("macwatch");

    if($netdb[0]{active}){
        $sth = $dbh->prepare("UPDATE $quotedTable SET active=0 WHERE mac=?");
        $flag = 0;
    }
    else{
        $sth = $dbh->prepare("UPDATE $quotedTable SET active=1 WHERE mac=?");
        $flag = 1;
    }
    if($mac !~ /[0-9a-fA-F]{4}(\.[0-9a-fA-F]{4}){2}/){
        die "|ERROR|: Invalid MAC address.";
    }
    # update active flag
    $sth->execute( $mac );

    return $flag;
}
# default help
sub usage {

    print <<USAGE;

  About: Manages and executes the MAC watch functionality
  Usage: macwatch.pl [options]

  MAC Options:
    -m   MAC      Preform operations on specified MAC address in the watchlist.
                    If only option will return information on MAC if it exist in the database.
    -a  notes     Add MAC to the watchlist, if not already present; if present
                    modifies notes on MAC. (use with -m)
    -e  email     Specify non default email addresses (ues multiple times for multiple addresses),
                    if present modifies paging email addresses on MAC. (use with -m)
    -f  notes     Set the MAC to found, and add notes about finding MAC (use with -m)
    -c  command   If enabled the command to be executed when MAC is detected (use with -m)
    -i            Toggle the MAC as inactive(stops checking), NOT the same as found.(use with -m)
    -d            Permanently delete the MAC from the watched table. (use with -m)

  Polling Options:
    -s offset     Search database for watched MAC addresses. Offset is optional and in seconds,
                    the default is 10 minutes.

  Listing Options:
    -l            Display all MAC addresses in the watch table.
    -l a          Display all active check MACs in the watch table.
    -l f          Display all found MACs in the watched table.

  Options:
    -conf          Alternate Configuration File (NOT IMPLIMENTED)
    -debug         Set debuging level (0-5)
    -v             Verbose output

USAGE
    exit;
}
