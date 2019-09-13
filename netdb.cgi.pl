#!/usr/bin/perl -wT
#################################################################################
# Network Tracking Database CGI Interface
# Author: Jonathan Yantis <yantisj@gmail.com>
# Copyright (C) 2014 Jonathan Yantis
#########################################################################
#
#   netdb.pl takes input from the web and searches the NetDB database.  The
# script determines if the input is a mac address, hostname or an IP address.
# By selecting different options, searches on vendor codes, switch reports and
# vlan reports can be created.  
#
# Dependencies:
# - Make sure to install under user authenticated location on your webserver, 
# relies on usernames for accounting.
# - Most options are configured from the netdb-cgi.conf files installed in /etc
#
# Installing:
# - Install netdb-cgi.conf in /etc and configure the options for your site.
# - Make sure the netdb.conf and netdb-cgi.conf files are readable by www-data
# - Create netdbReport.csv in /var/www/ and make it owned by the webserver user (www-data)
# - Copy or link the depends directory from netdb/extra/depends/ to the root location on
#   your web server (eg /var/www/depends).
# - Copy the netdb.cgi.pl file to your cgi-bin directory and rename to netdb.pl
# - Use the netdb-template.html file as the basis for your own website, relies on
#   <!-- PAGECONTENT --> and netdb.css primarily
# - Optionally install Jose Pedro Oliveira's wakeonlan script to /usr/bin
# - Edit /opt/netdb/extra/about.html with your own about page info
#
# Debugging/Troubleshooting:
#  Script should output all errors to the webpage.  Call script with
#  http://site/netdb.pl?debug=1 to enable extensive debugging.
#
# Version History:
# v1.0  04/26/2008 - Script ported from hal to the tools site
# v1.1  06/30/2008 - Added extended reporting on super tables (views)
# v1.2  07/08/2008 - Added CSV reporting and transaction logs
# v1.3  08/08/2008 - Added AJAX Table Support
# v1.4  11/06/2008 - Added WoL support
# v2.0  11/16/2008 - Rewrote interface using JQuery UI Tabs.  Added
#                    inline camtrace, inline WoL, and inline Excel
#                    reports.  Reworked look and feel and expanded
#                    the help documentation.
# v2.1  12/30/2008 - Added extended switchport information to match NetDB's
#                    v1.3 library.  Cleaned up some output issues.
# v2.2  02/04/2009 - Added getVlanSwitchStatus reports to website to get
#                    all switchports configured with a vlan
# v2.3  02/09/2009 - Fixed loading image to remove absolute positioning and
#                    alternate template issues.  Changed CSS for tables.
# v2.4  02/11/2009 - Added description to switch reports
# v2.5  02/27/2009 - Cleaned up error reporting and error handling, new css code
# v2.6  03/04/2008 - Removed all XML and Spry javascript libraries.  Moved to
#                    jquery tablesort.  Changed from checkboxes to drop down box.
#                    Added new devices report.
# v2.7  03/11/2009 - Upgraded to jquery-1.3.2 and jquery-ui-1.7, cleaned up code
# v2.8  03/31/2009 - Added Access Level Controls and moved all configuration options
#                    to /etc/netdb-cgi.conf
# v2.9  06/02/2009 - Added mac_format options to netdb-cgi.conf
# v2.10 06/18/2009 - Added user report and NAC registration display table
# v2.11 07/10/2009 - Added full jquery ui library and css to code.  Changed error
#                    reporting to dialog boxes for clarity.  Made address text
#                    box auto selected when page loads.
# v2.12 03/04/2010 - Added VLAN Change Capability
# v2.13 10/15/2010 - Added IPv6 Support
# v2.14 03/25/2011 - Added Unused ports report and cleaned up user error reporting
# v2.15 05/02/2011 - Added custom shutdown support (local to developer)
# v2.16            - Bug fixes for v1.10
# v2.17 10/17/2012 - Added neighbor discovery data and NAC role changes
# v2.18 02/14/2013 - Adding VRF support, inventory and new icons
# v2.19 02/27/2014 - Added description search and shut/no shut functionality
#
#################################################################################
use CGI qw(:standard Vars);
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use Net::IP;
use NetDB;
use AppConfig;
use DateTime;
use Time::HiRes qw (gettimeofday);
use English;
use strict;
eval "use WebTemplate;"; # Custom module for template processing, ok if not available

# No nonsense
no warnings 'uninitialized';

#############################################################################
# Primary Configuration File (edit this file with your configuration options)
#############################################################################
my $config_cgi = "/etc/netdb-cgi.conf";

################################################
# Script Variables (DO NOT EDIT BELOW THIS LINE)
################################################
my $wolTimeout       =25; #

my ( $scriptName, $ownerInfo, $ownerEmail, $pageTitle, $pageName, $template, $cgibin, $root, );
my ( $aboutFile, $config_file, $useCamtrace, $useStatistics, $mac_format, $desc_length );
my ( $findipuser, $trans_script, $mnc_shut, $mnc_unshut, $mnc_block, $mnc_noblock, $desc_script );
my ( $shut_script, $mnc_portshut, $mnc_portunshut );

# Other Vars
my $netdbCGIVer      = '2.19';
my $netdbVer         = '1';
my $netdbMinorVer    = '13';

# Default Description Length
$desc_length = 30;

# DEVELOPMENT - Change the default config file if executed file is the development path
if ( $0 eq '/usr/lib/cgi-bin/netdb2.pl' || $0 eq '/usr/lib/cgi-bin2/netdb2.pl' ) {
    $config_cgi = "/scripts/dev/netdb/netdbdev-cgi.conf";
}

#####################
# Process Config File
#####################
&parseConfig();

# File and Script Dependencies
my $netdbCSVcmd      = "/opt/netdb/netdb.pl -c -conf $config_file";
my $wakecmd          = "/usr/bin/wakeonlan -i ";
my $docRootTools2    = '/var/www/tools2/'; ## Only used for alternate web templates
my $CSVFile          = 'netdbReport.csv';
my $netdbVerFile     = '/opt/netdb/data/netdbversion.txt';

# Stats generated from update-statistics.sh
my $netdbTotalStats  = '/opt/netdb/data/netdbstats.txt';
my $netdbMonthlyStats = '/opt/netdb/data/netdbmonthlystats.txt';
my $netdbDailyStats  = '/opt/netdb/data/netdbdailystats.txt';

# ENV vars
my $docRoot          = $ENV{'DOCUMENT_ROOT'};
my $source_address   = $ENV{REMOTE_ADDR};
my $envuser          = $ENV{REMOTE_USER};

#Clean domain info from username
( $envuser ) = split( /\@/, $envuser ); 


# Tools Template
if ( $docRoot eq $docRootTools2 ) {
    $cgibin    = '/cgi-bin2';
    $root      = '/var/www/tools2';
    $template  = "/var/www/tools2/output-template.htm";
}

# Dynamic File Locations
my $scriptLocation   = "$cgibin/$scriptName"; 
my $camtraceLoc      = "$cgibin/camtrace.pl";
my $dnsLoc           = "$cgibin/dns.pl";
my $CSVFileLoc       = "$root/$CSVFile";

# Text arrays for preloading tables and text output from queries
my @ntable;
my @netdbText;

# Authorization Variables
my $defaultAuthLevel;
my $userAuthLevel;
my %reportAuthLevel;
my %reportMaxCount;
my %vlanAuth;
my %nacAuth;


# Other Vars
my $DEBUG; # Set to 1 or append ?debug=1 to url
my ( $CSVOption, $verbose, $vendorOption, $switchReport, $vlanReport, $vlanStatusReport, $newMacsReport, $userReport );
my ( $inputType, $wakeLoc, $menuBar, $searchDays, $errmsg, $infomsg, $transactionID, $skipTemplate, $getOptions );
my ( $useNAC, $vlan_script, $unusedPortsReport, $role_file, $role_script, $statseeker, $useInventory, $invReport );
my ( $wifi_http, $descReport, $use_fqdn );
my $starttime = [ Time::HiRes::gettimeofday( ) ];

# Detaint the Path
$ENV{'PATH'} =~ /(.*)/;
$ENV{'PATH'} = $1;

# Autoflush
$OUTPUT_AUTOFLUSH = 1;

# DEVELOPMENT - Change default config file if this is the development copy
if ( $0 eq '/usr/lib/cgi-bin/netdb2.pl' || $0 eq '/usr/lib/cgi-bin2/netdb2.pl' ) {
    my $config_cgi = "/scripts/dev/netdb/netdbdev-cgi.conf";
}

#################################################
# Process variables and check for POST state data
#################################################
my %FORM = Vars();

# Search over days
if ( $FORM{"days"} ) {
    $searchDays = parseInputVar( "days" );
}

# Enable Debugging, use as a GET variable
if ( $FORM{"debug"} ) {
    $DEBUG = 1;
    $verbose = 1;
    $getOptions = $getOptions . "&debug=1"
}

# Verbose camtrace output
if ( $FORM{"verbose"} ) {
    $verbose = 1;
}

# Mac Format Option
if ( $FORM{"macformat"} ) {
    $mac_format = parseInputVar( "macformat" );

    $mac_format = 'ieee_dash' if $mac_format eq 'dash';
    $mac_format = 'ieee_colon' if $mac_format eq 'colon';
    $mac_format = 'no_format' if $mac_format eq 'none';

    $getOptions = $getOptions . "&macformat=$mac_format"
}

# Parse Select Form for report type
if ( my $option = $FORM{"netdbselect"} ) {
   $vendorOption      = 1 if $option eq 'vendor';
   $vlanReport        = 1 if $option eq 'vlan';
   $switchReport      = 1 if $option eq 'switch';
   $vlanStatusReport  = 1 if $option eq 'status';
   $newMacsReport     = 1 if $option eq 'newmacs';
   $userReport        = 1 if $option eq 'user';
   $unusedPortsReport = 1 if $option eq 'unusedports';
   $invReport         = 1 if $option eq 'invreport';
   $descReport        = 1 if $option eq 'desc_search';
}


## GET Option processing
# Vendor Code
if ( $FORM{"vendor"} ) {
    $vendorOption = 1;
}

# Switch Report
if ( $FORM{"switchreport"} ) {
    $switchReport = 1;
}

# Unused Port Report
if ( $FORM{"unusedports"} ) {
    $unusedPortsReport = 1;
}

# Inventory Report
if ( $FORM{"invreport"} ) {
    $invReport = 1;
}

# VLAN Report
if ( $FORM{"vlan"} ) {
    $vlanReport = 1;
}

# User Report
if ( $FORM{"user"} ) {
    $userReport = 1;
}


###########################################
# Skip template processing for AJAX Results
###########################################
if ( $FORM{"skiptemplate"} ) {

    $skipTemplate = 1;

    print header; # Always print a content type header

    # Generating CSV report, results returned inline in tab
    if ( $transactionID = $FORM{csvreport} ) {
        generateReport();
    }

    # Wake on LAN, results retunred inline in WoL tab
    elsif ( $FORM{"wake"} ) {
        my $wake = parseInputVar("address");
        my $wakeip = parseInputVar("wakeip");
        &wakeOnLan( $wake, $wakeip );
    }
    elsif ( $FORM{"disableclient"} ) {
	disableClient();
    }
    elsif ( $FORM{"vlanchange"} ) {
	changeVlan();
    }
    elsif ( $FORM{"descchange"} ) {
	changeDesc();
    }
    elsif ( $FORM{"shutchange"} ) {
        changeStatus();
    }

    elsif ( $FORM{"findipuser"} ) {
	findIPUser();
    }

    elsif ( $FORM{"bradfordtrans"} ) {
	bradfordTransactions();
    }
    elsif ( $FORM{"rolechange"} ) {
	changeRole();
    }
    
    else {
	sendMain();
    }
}

##########################################################
# Normal Script Processing, non-ajax full template support
##########################################################
else {
    print header;
    
    ##################
    # Process Template
    ##################
    open( my $TEMPLATE, '<', "$template") or die "Can't open Template: $template: $!";
    
    while ( my $line = <$TEMPLATE> ) {
	
	# Search for comments used to insert dynamic content in to template
	if ( $line =~ /<!--\s\w+\s-->/ ) {
	    
	    if ( $line =~ /--\sPAGETITLE\s--/ ) {
		print "$pageTitle";
	    }
	    elsif ( $line =~ /--\sPAGENAME\s--/ ) {
		print "$pageName\n";
	    }
	    elsif ( $line =~ /--\sSIDELINKS1\s--/ ) {
		WebTemplate::printSideLinks( (1, "nst", "Team Links" ) );
	    }

	    ## Call main routine to populate page content
	    elsif ( $line =~ /--\sPAGECONTENT\s--/ ) {
		
		if ( $FORM{"vlanchange"} ) {
		    &changeVlan();
		}
		else {
		    sendMain();
		}
	    }
	    elsif ( $line =~ /--\sYOURIPADDRESS\s--/ ) {
		print "<br><strong>IP: $ENV{REMOTE_ADDR} </strong>";
	    }
	    
	    ##################################################
	    # Javascript and CSS header code specific to NetDB
	    ##################################################
	    elsif ( $line =~ /--\sSTYLESHEET\s--/ ) {
		print '<!-- Start NetDB Header Code -->' . "\n";
		print '<meta http-equiv="Content-Style-Type" content="text/css">' . "\n";
		print '<meta http-equiv="Content-Script-Type" content="text/javascript">' . "\n";
		print $line;
		print '<script type="text/javascript" src="/depends/jquery-1.3.2.min.js"></script>' . "\n";
		print '<script type="text/javascript" src="/depends/jquery-ui-1.7.2.custom.min.js"></script>' . "\n";
                print '<link rel="stylesheet" href="/depends/jquery-ui-1.7.2.custom.css" type="text/css" media="print, projection, screen">' . "\n";
                print '<script type="text/javascript" src="/depends/jquery.tablesorter.js"></script>' . "\n";
		print '<script type="text/javascript" src="/depends/jquery.livequery.js"></script>' . "\n";
                print '<script type="text/javascript" src="/depends/jquery.bgiframe.min.js"></script>' . "\n";
		
		# Print custom javascript code for NetDB
		&printHeaderCode();
		
		print "\n" . '<!-- End NetDB Header Code -->' . "\n";
	    }

	    # If unknown comment, just print the line anyway
	    else {
		print "$line\n";
	    }
	}
	
	# Fixup for tools site
	elsif($line =~ /2col_leftNav.css/) {
	    $line =~ s/2col_leftNav.css/\/2col_leftNav.css/g;
	    print "$line";
	}

	# If nothing special on line, print it out unchanged
	else { 
	    print $line; 
	}
    }
}
    
#######################################
#**************************************
# Main routine after template handoff
#**************************************
#######################################
sub sendMain {

    my $address;
    my $switchSearch;

    # Parse and detaint input from POST/GET variable
    $address = parseInputVar("address");
    $switchSearch = $FORM{switch};       # Macs on a switchport

    # Set searchDays if unset
    $searchDays = 7 if !$searchDays;

    # Make sure days is reasonable
    if ( $searchDays > 5000 ) {
	$searchDays = 5000;
    }

    # Some links call script with alternate var 'search'
    if ( !$address ) {
	$address = parseInputVar("search");
    }

    # Make sure a valid mac, ip or host, pass to special parser
    if ( $address && !$switchSearch && !$switchReport && !$vendorOption && !$vlanReport && 
	 !$vlanStatusReport && !$unusedPortsReport && !$invReport ) {
	print "<br>Debug: Calling NetDB Parser on $address\n" if $DEBUG;
	($address, $inputType) = parseNetDBAddress($address);
	print "<br>Debug: NetDB Parser results $address as $inputType\n" if $DEBUG;
    }

    # Switchport search, address is a mac
    if ( $switchSearch ) {
	$inputType = "switch";
    }
    
    # Unused Port Report
    if ( $unusedPortsReport ) {
	$inputType = "unusedports"
    }

    # Inventory Report
    if ( $invReport ) {
	$inputType = "invreport";
    }

    # Vendor Code Search
    if ( $vendorOption ) {
        $inputType = "vendor";
    }

    # Switch Report Option
    if ( $switchReport ) {
	$inputType = "switchreport";

	# Strip off any domain name from the switch name unless using fqdn
	( $address ) = split( /\./, $address ) if !$use_fqdn;
    }

    # Switchport Description Search
    if ( $descReport ) {
	
	# Loose input searching
	$address = parseInputVarLoose("address");

	$inputType = "desc_search";
    }
    
    # Vlan Report
    if ( $vlanReport ) {
	$inputType = "vlanreport";
    }

    # Vlan Status Report
    if ( $vlanStatusReport ) {
	$inputType = "vlanstatus";
    }

    # New MAC Address Report
    if ( $newMacsReport ) {
	$inputType = "newmacs";
	$address   = "New Devices";
    }

    # User Report
    if ( $userReport ) {
	$inputType = "user";
    } 

    # Header
    if ( !$skipTemplate ) {
	print "<br>Debug: Printing Header\n" if $DEBUG;
	printHeader($address);
    }

    # AJAX Return Block for inline requests
    if ( !$skipTemplate ) {
	print "<div id=\"ajaxresults\">\n";
    }

    # Check to see if generating report
    if ( $transactionID = $FORM{csvreport} ) {
	generateReport();
    }

    # WoL GET Method support
    elsif ( $FORM{wake} ) {
	my $wakemac = parseInputVar("address");
        my $wakeip = parseInputVar("wakeip");
	wakeOnLan( $wakemac, $wakeip );
	printFooter( $address );
    }

    ###############################################
    # Query NetDB if $address passed all the checks
    ###############################################
    elsif ( $address ) {

	# Record a transaction for security purposes
	$transactionID = recordTransaction( $address, $inputType );

	# Make sure user is authorized to access this type of report
	my $success = &checkAuthorization( $address, $inputType );
	
	if ( $success eq "authorized" ) {

	    # Call NetDB routine to query database
	    getNetDB( $address, $inputType );
	    
	    # Print Results if no errors
	    if ( !$errmsg && !$infomsg ) {
		printResults( $address ); # Print NetDB Results
	    }
	}
    }
    
    # Print any error or informational messages in dialog boxes
    if ( $infomsg || $errmsg ) {

	print '<div class="netdbresults" style="display: block;">' . "\n";
        printAboutNetDB();
        printFooter( $address );
        print '</div>' . "\n";
	
	# Informational Message
	if ( $infomsg ) {

	    my ($infotype) = split( /\:/, $infomsg );

            $infomsg =~ s/$infotype\:\s//;	    
	    print "<font size=\"3\"><div id=\"infodialog\" title=\"$infotype\">";
	    print "<p>$infomsg</p>\n";
	    print '</div>';
	}
	
	# Error Message
	if ($errmsg) {

            my ($infotype) = split( /\:/, $errmsg );

	    $errmsg =~ s/$infotype\:\s//;
            print "<font size=\"3\"><div id=\"errordialog\" title=\"$infotype\">";
            print "<p>$errmsg</p>\n";
            print '</div>';
	}

    }

    # Print about NetDB if no address passed in and no errors encountered
    elsif ( !$address ) {
	print '<div class="netdbresults" style="display: block;">' . "\n";
        printNetDBStats() if $useStatistics;
        printAboutNetDB();
	printFooter( $address );
	print '</div>' . "\n";
    }

    # Close AJAX Results
    print "</div>\n" if !$skipTemplate;
}



#########################################################
# Check to see if user is authorized for this report type
#########################################################
sub checkAuthorization {
    my $address = shift;
    my $reportType = shift;

    print "<br>Access Control: User $envuser has access level $userAuthLevel, attempting to access $reportType report 
           level $reportAuthLevel{$reportType}" if $DEBUG;

    # Check to see if user has high enough access level for report unless report has no access restrictions
    if ( $userAuthLevel >= $reportAuthLevel{"$reportType"} || !$reportAuthLevel{"$reportType"} ) {
	return "authorized";
    }
    
    # If doing a switch report for a specific port (eg switch,Gi4/1) , allow access
    elsif ( $reportType eq "switchreport" && $address =~ /\w+\,\w+\d+\// ) {
	return "authorized";
    }

    else {
	
	# Special case when users are searching their own registration data
	if ( $userReport && $address eq $envuser ) {
	    return "authorized";
	}
	elsif ( $userReport ) {
	    $errmsg = "<b>No Access</b>: By default, users can only search for their own registrations. If you work in IT, send an email " .
	    "to <a href=\"mailto:$ownerEmail\">$ownerInfo</a> and request that your username be added to the NetDB Level $reportAuthLevel{$reportType} " .
            "Access List. <br><br>(config: $config_cgi)";

	}
	else {
	    $errmsg = "<b>No Access to $reportType</b>: You must request permission to access the report type you selected (<b>$reportType</b>). " .
	    "If you need access, send an email " . 
	    "to <a href=\"mailto:$ownerEmail\">$ownerInfo</a> and request that your username be added to the NetDB Level $reportAuthLevel{$reportType} " . 
            "Access List. <br><br>(config: $config_cgi)";
            print STDERR "Netdb: User $envuser tried to access $reportType and was denied\n";
	}
    }

    return;
}

###########################################
# Generate a CSV Report, inline ajax return
###########################################
sub generateReport {

    # Query as unpriviledge user
    my $dbh = connectDBro( $config_file );

    my $netdb_ref = getTransaction( $dbh, $transactionID );
    my @netDB = @$netdb_ref;

    my $querytype  = $netDB[0]{querytype};
    my $queryvalue = $netDB[0]{queryvalue};
    #$queryvalue    =~ s/*/\%/gi;           #flip to sql regex
    my $querydays  = $netDB[0]{querydays};
    my $success;

    $searchDays = $querydays;

    $netdbCSVcmd = $netdbCSVcmd . " -d $querydays";

    if ( $mac_format ) {
	$netdbCSVcmd = $netdbCSVcmd . " -mf $mac_format";
    }

    # Use netdb CLI program to generate report based on type
    if ( $querytype eq 'IP' ) {
	`$netdbCSVcmd -i $queryvalue > $CSVFileLoc`;
	$success = 1;
    }
    elsif ( $querytype eq 'switch' ) {
        `$netdbCSVcmd -p $queryvalue > $CSVFileLoc`;
        $success = 1;
    }
    elsif ( $querytype eq 'Hostname' ) {
        `$netdbCSVcmd -n $queryvalue > $CSVFileLoc`;
        $success = 1;
    }
    elsif ( $querytype eq 'vlanreport' ) {
        `$netdbCSVcmd -vl $queryvalue > $CSVFileLoc`;
        $success = 1;
    }
    elsif ( $querytype eq 'vendor' ) {
        `$netdbCSVcmd -vc $queryvalue > $CSVFileLoc`;
        $success = 1;
    }
    elsif ( $querytype eq 'switchreport' ) {
        `$netdbCSVcmd -sw $queryvalue > $CSVFileLoc`;
        $success = 1;
    }
    elsif ( $querytype eq 'desc_search' ) {
        `$netdbCSVcmd -ds $queryvalue > $CSVFileLoc`;
        $success = 1;
    }
    elsif ( $querytype eq 'vlanstatus' ) {
	`$netdbCSVcmd -vs $queryvalue > $CSVFileLoc`;
	$success = 1;
    }
    elsif ( $querytype eq 'user' ) {
        `$netdbCSVcmd -u $queryvalue > $CSVFileLoc`;
        $success = 1;
    }

    elsif ( $querytype eq 'unusedports' ) {
        `$netdbCSVcmd -up $queryvalue > $CSVFileLoc`;
        $success = 1;
    }

    # Display report link if successful
     if ( $success ) {
        print "<p><font size=\"+1\"><a class=\"btn\" href =\"/$CSVFile\"><span><span>Download CSV Report</span></span></a></font></p>\n";
        print "<br><br> (report id:$transactionID)</p>\n" if $DEBUG;
    }
    else {
	print "<p>Error: Could not generate report for [$transactionID] $queryvalue $querytype</p>";
    }

}

##################################################
# Input Handling, check for safe input and detaint
##################################################
sub parseInputVar {
    my $inputVar = shift;
    my $inputData = $FORM{$inputVar};
    my $returnData; ## Used as detainted var

    #########################################
    # Initially Verify Input Data and Detaint
    #########################################
    if ( $inputData ) {

        # Strip out unwanted hostname (hack)
        $inputData =~ s/\.clinlan\.local//;

	# Strip out 1q from vlan id if passed in
	$inputData =~ s/\(1q\)//;


	print "<br>Debug: Input Parser on $inputVar - input:$inputData" if $DEBUG;

	# Truncate Input Data to 75 characters
        $inputData = substr( $inputData, 0, 75 );
	
	# Strip out escape/unneeded characters for security
	$inputData =~ s/(\%)//g; # Strip out wildcards

	

	# Strip out spaces if this is not a vendor search
	if ( $vendorOption || $invReport ) {
	    $inputData =~ s/\s+/ /g;
	    $inputData = lc( $inputData );
	}
	else {
	    $inputData =~ s/\s+//g;
	}
	

	# Allowed characters
	($returnData) = $inputData =~ m/^([A-Z0-9_.\-\:\s\,\/\*]+)$/ig;

	print " output:$returnData\n" if $DEBUG;
	
	if ( $inputData ne $returnData ) {
	    $errmsg = "<b>Input Error</b>: There is a problem with the data you submitted - <strong>$inputData</strong>";
	    $returnData = undef;
	}
    }
    
    return ( $returnData );
}


####################################################################
# Less Strict Input Handling, still check for safe input and detaint
####################################################################
sub parseInputVarLoose {
    my $inputVar = shift;
    my $inputData = $FORM{$inputVar};
    my $returnData; ## Used as detainted var

    #########################################
    # Initially Verify Input Data and Detaint
    #########################################
    if ( $inputData ) {

        # Strip out unwanted hostname (hack)
        $inputData =~ s/\.clinlan\.local//;

	print "<br>Debug: Input Parser on $inputVar - input:$inputData" if $DEBUG;

	# Truncate Input Data to 400 characters
        $inputData = substr( $inputData, 0, 400 );

	# Strip out escape/unneeded characters for security
	$inputData =~ s/(\%)//g; # Strip out wildcards

	# Allowed characters
	($returnData) = $inputData =~ m/^([A-Z0-9_.\-\:\s\,\/\[\]\s\*]+)$/ig;

	print " output:$returnData\n" if $DEBUG;
	
	if ( $inputData ne $returnData ) {
	    $errmsg = "<b>Input Error</b>: There is a problem with the data you submitted - <strong>$inputData</strong>";
	    $returnData = undef;
	}
    }
    
    return ( $returnData );
}


##################################################
# Once input passes intial parser, find out what
# sort of NetDB query it is.
# Identifies MACs and IPs, everything else is 
# considered a hostname.
##################################################
sub parseNetDBAddress {    
    
    my $inputAddress = shift;
    my $inputType    = shift;
    my $searchmac;
    my $mymac;
    my $myip;

    if ($inputAddress) {
	#IP address
	if ( ( $inputAddress =~ /^\d+\.\d+\.\d+\.\d+$/ || $inputAddress =~ /^\d+\.\d+\.\d+\.$/ )
	     && $inputAddress !~ /\w\w\w\w\.\w\w\w\w\.\w\w\w\w/ ) 
	{
	    $inputAddress =~ s/\s+//g; #strip out any spaces
	    $inputType    = "IP";
	}
	
	# IPv6 Address
	elsif ( $inputAddress =~ /\w\w\w:/ || $inputAddress =~ /::/ ) {
	    $inputAddress =~ s/\s+//g; #strip out any spaces
            $inputType    = "IP";
	}

	# Check MAC Address
	elsif ( $inputAddress !~ /^(\d+)(\.\d+){3}$/ && $inputAddress !~ /((musc.edu)|(clinlan.local))/) {
	    
	    # Convert to lowercase
	    my $mac = $inputAddress;
            $mac =~ tr/[A-F]/[a-f]/;

	    # Check for short mac format, xx:xx
	    if ( $mac =~ /^\w\w\:\w\w$/ ) {
                $inputAddress = $mac;
                $inputType    = "ShortMAC";
	    }
	    
	    # Mac Wildcard Search (55:55* or *55:55:55 etc)
	    elsif ( $mac =~ /^\w\w(\:\w\w){1,4}\:?\*$/ || $mac =~ /^\*\:?(\w\w\:){1,4}\w\w$/ ) {
		$inputAddress = $mac;
                $inputType    = "ShortMAC";
		
	    }

	    # Not a short mac, normal mac processing
	    else { 
		# Strip out all extra characters
		$mac =~ s/(:|\.|\-|(^0x)|)//g;
		
		# Make sure it's a mac address
		if ( $mac =~ /^(([a-f]|[0-9]){12})$/ ) {
		    
		    # Nasty code to put the submitted mac address in to the desired format. I should have made a new
		    # subroutine instead of this mess, but it works.
		    my %machash;
		    $machash{mac} = $mac;
		    my @tmpmac = (\%machash);
		    my $tmpref = convertMacFormat( \@tmpmac, $mac_format );
		    @tmpmac = @$tmpref; 
		    $mac = $tmpmac[0]{mac};
		    
		    $inputAddress = $mac;
		    $inputType    = "MAC";
		}
	    
	    
		# Hostname
		elsif ( $inputAddress =~ /^\w+/ ) {
		    $inputAddress =~ s/\s+//g;
		    $inputType    = "Hostname";
		}
		else {
		    $errmsg =  "<b>Input Error</b>: $inputAddress is not an IP address, hostname or MAC address";
		    $inputAddress = undef;
		}
	    }
	}

	# Hostname
	elsif ( $inputAddress =~ /^\w+/ ) {
	    $inputAddress =~ s/\s+//g;
            $inputType    = "Hostname";
	}
	else {
	    $errmsg = "<b>Input Error</b>: $inputAddress is not an IP address, hostname or MAC address";
	    $inputAddress = undef;
	}
    }
    else { 
	$inputAddress = undef; 
    }
    return ( ($inputAddress, $inputType) );
}

#####################
# Wake On Lan Support
#####################
sub wakeOnLan {
    my $wakemac = shift;
    my $wakeip = shift;
    my $secondarynet;
    my @ipmacpair;

    # If not supplied ip mac pair, search for device via hostname
    if ( !$wakeip ) {
	@ipmacpair = getIPMACs( $wakemac );
    }

    # Supplied mac and IP, add single entry
    else {
	push( @ipmacpair, "$wakeip,$wakemac" );
    }

    # Catch no data and return error
    if ( !$ipmacpair[0] ) {
	print "<div id=\"errordialog\">Could not find this device on the network, ";
	print "could be the wrong hostname or search criteria</div><br>\n";

	print "<div class=\"messagebox info\">Could not find this device on the network, ";
        print "could be the wrong hostname or search criteria</div><br>\n";
	return;
    }

    foreach my $pair ( @ipmacpair ) {

	( $wakeip, $wakemac ) = split( /\,/, $pair );
	
	if ( $envuser ne "wol20" ) {
	    recordTransaction( $wakemac, "WoL" );
	}
	$wakemac = getIEEEMac( $wakemac );
	
	my @ip = split(/\./, $wakeip );
	
	# Check for even or odd subnet
	if ( $ip[2] % 2 == 0 ) {
	    $secondarynet = $ip[2] + 1;
	}
	else {
	    $secondarynet = $ip[2] - 1;
	}
	
	# Create the broadcast subnet addresses
	my $broadcast1 = "$ip[0].$ip[1].$ip[2].255";
	my $broadcast2 = "$ip[0].$ip[1].$secondarynet.255";
	
	if ( $ip[2] == 44 || $ip[2] == 45 ) {
	    $broadcast1 = "128.23.47.255";
	}
	
	`$wakecmd $broadcast1 $wakemac`;
	`$wakecmd $broadcast2 $wakemac`;
	
	print "<br>Sent WoL magic packets to $wakemac on subnets $broadcast1 and $broadcast2\n" if $DEBUG;
	
	# Ping device and wait for it to wake up
	my $pingpid = open( my $PING, '-|', "/bin/ping -c $wolTimeout $wakeip") || warn("Couldn't execute ping $wakeip: $!");
	
	my $isAwake;
	while ( my $line = <$PING> ) {
	    if ( $line =~ /bytes from/ ) {
		$isAwake = 1;
		kill 15, $pingpid;
		last;
	    }
	}
	close $PING;
	
	print "<br>" if $FORM{"skiptemplate"};    
	
	if ( $isAwake ) {
	    print "<div class=\"messagebox success\">$wakeip is awake and on the network. ";
	    print "Bookmark <a href=\"$scriptLocation?address=$wakemac&wake=1&wakeip=$wakeip\">this link</a>";
	    print " to wake up this device in the future.</div><br>\n";
	}
	else {
	    print "<div class=\"messagebox info\">$wakeip is not responding to pings (usually the device is slow 
               to boot or has a local firewall issue). 
               It still might be awake and on the network. Tried to wakeup $wakemac.";
	    print " Bookmark <a href=\"$scriptLocation?address=$wakemac&wake=1&wakeip=$wakeip\">this link</a>";
	    print " to wake up this device in the future.</div><br>\n";
	}

	print <<SCRIPT;
    <script>
    \$(function() {
	\$(".messagebox").fadeIn(500);
}); 
</script>
SCRIPT

    } # End Foreach
}

###################
# NetDB HTML Header
###################
sub printHeader {

    my $address = shift;

    $address = $FORM{"address"} if !$address;

    print ' <div class="box">' . "\n";
    print '<h1>Search Network Tracking Database</h1>';
    print '<p>Search for hostname, IP or MAC address, or select a different report type</p>';
    print "<form name=\"netdbform\" method=\"POST\" action=\"$scriptLocation\#content\">";

    print '<label><span>Search</span> ';
    if($address) {
	print "<input name\=\"address\" id=\"netdbaddress\" type\=\"text\" class=\"input-text\" size\=\"35\" 
               value\=\"$address\" tabindex=\"5\"></label>\n";
    }
    else {
	print "<input name\=\"address\" id=\"netdbaddress\" type\=\"text\" class=\"input-text\" size\=\"35\" 
               value\=\"$source_address\" tabindex=\"5\"></label>\n";
    }
    
    # Hidden POST State Variables
    if ( $DEBUG ) {
	print '<input type="hidden" name="debug" value="1">';
    }
    if ( $FORM{"tools"} ) {
	print '<input type="hidden" name="tools" value="1">';
    }
    if ( $FORM{"macformat"} ) {
        print "<input type=\"hidden\" name=\"macformat\" value=\"$mac_format\">";
    }

    ## Query Type Select Box
    print '<label><span>Report Type</span>
           <select size="1" tabindex="6" name="netdbselect">
';
    print  '<option value="freesearch">Device by IP, MAC or hostname</option>';

    # User Search
    if ( $useNAC ) {
	if ( $userReport ) {
	    print '<option value="user" selected>Devices by a User ID</option>';
	}
	else {
	    print '<option value="user">Devices by a User ID</option>';
	}
    }

    # Vendor Code Search
    if ( $vendorOption ) {
        print '<option value="vendor" selected>Devices by a Vendor Code</option>';
    }
    else {
        print '<option value="vendor">Devices by a Vendor Code</option>';
    }

    # Vlan Search
    if ( $vlanReport ) {
        print '<option value="vlan" selected>Devices in ARP Table by VLAN ID</option>';
    }
    else {
        print '<option value="vlan">Devices in ARP Table by VLAN ID</option>';
    }

    # New MACs report
    if ( $newMacsReport ) {
       print '<option value="newmacs" selected>All New Devices (in days)</option>';
   }
    else {
        print '<option value="newmacs">All New Devices (in days)</option>';
    }

    print '<option value="spaceholder">----------------------------</option>';

    # Switch Report
    if ( $switchReport ) {
        print '<option value="switch" selected>Switch Report on a Name</option>';
    }
    else {
        print '<option value="switch">Switch Report on a Name</option>';
    }

    # Inventory Report (optional)
    if ( $useInventory ) {
        if ( $invReport ) {
            print '<option value="invreport" selected>Switch Inventory on a Name</option>';
        }
        else {
            print '<option value="invreport">Switch Inventory on a Name</option>';
        }
    }

    # Unused Port Report
    if ( $unusedPortsReport ) {
        print '<option value="unusedports" selected>Switchports Unused (in days)</option>';
    }
    else {
        print '<option value="unusedports">Switchports Unused (in days)</option>';
    }


    # Switch Status
    if ( $vlanStatusReport ) {
        print '<option value="status" selected>Switchports on a VLAN ID</option>';
    }
    else {
        print '<option value="status">Switchports on a VLAN ID</option>';
    }

    # Switch Status
    if ( $descReport ) {
        print '<option value="desc_search" selected>Switchports with a Description</option>';
    }
    else {
        print '<option value="desc_search">Switchports with a Description</option>';
    }

    print '</select></label>';
    print "<label><span>Days in Past</span><input name\=\"days\" type\=\"text\" class=\"input-text\" size\=\"4\" 
           value\=\"$searchDays\" tabindex=\"7\"></label>\n";
    print '<center><button tabindex="8" class="btn primary" id="netdbsubmit" type="submit"><span><span>Query NetDB</span></span></button></center>';

    # Loading Image (Killed via javascript after page has loaded)
    print '<div class="loading" style="position:relative; left:300px; bottom:55px; height:0px; width:0px">
           <img src="/depends/loading.gif" border=0></div>';

    print "\n" . '</form></div>' . "\n";
    print '<div id="netdbnotice"></div>';
    

}


#########################################
# Print NetDB Results in tabbed interface
#########################################
sub printResults {

    my $address = shift;

    # Overall Results Block to fade in
    print "<div class=\"netdbresults\">\n";
    
    ## JQuery UI Tabs block
    print '
        <div id="container-1">
            <ul>
                <li><a href="#results"><span>Results</span></a></li>
';

    if ( $inputType ne "vendor") {
	print "<li><a href=\"\#plaintext\"><span>Plain Text</span></a></li>";
    }


    print "<li><a href=\"$scriptLocation?csvreport=$transactionID&address=$address&switchreport=$switchReport" if !$wakeLoc;
    print "&vlan=$vlanReport&vendor=$vendorOption&skiptemplate=1$getOptions\"><span>Excel Report</span></a></li>\n" if !$wakeLoc;
    print "<li><a href=\"$camtraceLoc?address=$address&skiptemplate=1\"><span>Camtrace</span></a></li>\n" if $wakeLoc && $useCamtrace;

    # DNS Audit
    if ( $useCamtrace && ( $inputType eq "Hostname" || $inputType eq "IP" ) ) {
	print "<li><a href=\"$dnsLoc?address=$address&skiptemplate=1\"><span>DNS Audit</span></a></li>\n";
    }
    
    # findupuser extension
    if ( $useCamtrace && ( $inputType eq "IP" ) ) {
	print "<li><a href=\"$scriptLocation?address=$address&skiptemplate=1&findipuser=1\"><span>Find IP User</span></a></li>\n";
    }

    # Bradford Transactions
    if ( $useCamtrace && ( $inputType eq "MAC" ) ) {
	print "<li><a href=\"$scriptLocation?address=$address&skiptemplate=1&bradfordtrans=1&days=$searchDays\"><span>Bradford Transactions</span></a></li>\n";
    }


    
    print "<li>$wakeLoc</li>\n" if $wakeLoc;
    print '<li><a href="#netdbhelp"><span>NetDB Help</span></a></li>';

    print ' </ul>
            <div id="results">
';

    ## Tab Data

    # NetDB Table Results
    print "@ntable";
    print "</div>\n";

    # NetDB Plain Text
    if ( $inputType ne "vendor" ) {
	print '
            <div id="plaintext">
              <div class="notice" style="display: block;">
        ';

	print @netdbText;
	print "</div></div>\n";
    }

    # About NetDB
    print '
            <div id="netdbhelp">
            <br>
';    
    printAboutNetDB( 1 );

    print '
            </div>
        </div>
';

    # Print Footer
    printFooter( $address );

    print "</div>\n"; #close netdbresults div
}


########
# Footer
########
sub printFooter {
    my $address = shift;
    my @version = ( "NetDB v1.$netdbMinorVer" );

    print "<hr>\n";


    # NetDB Version Info
    if ( $useStatistics ) {
	open( my $NETDBVER, '<', "$netdbVerFile" ) or print "<br>WARNING: Can't open $netdbVerFile";
	@version = <$NETDBVER>;
    }
    print "<font size=\"1\">";
    print "$version[0] | CGI v$netdbCGIVer\n";

    # Benchmark results
    if ( $address ) {
        my $runtime = Time::HiRes::tv_interval( $starttime );
        $runtime = sprintf( "%.3f", $runtime );
        $runtime = $runtime * 1000;
        print " | [" . $runtime . "ms]";
    }

    # Owner Information
    print " | $ownerInfo\n";

    # Library Version Check
    my $libraryVersion = getVersion();
    if ( $libraryVersion ne "$netdbVer.$netdbMinorVer" ) {
	print "<br><b style=\"color:red\">Warning: Library version v$libraryVersion mismatch with $scriptName v$netdbVer.$netdbMinorVer</b>\n";
	print STDERR "Warning: NetDB Library version v$libraryVersion mismatch with $scriptName v$netdbVer.$netdbMinorVer\n";
    }

    print "</font><br><br>\n";
}

#############################################
# Query NetDB and call print methods
#############################################
sub getNetDB {
    
    my $address   = shift;
    my $inputType = shift;
    my $opthours = $searchDays * 24;
    my $netdb_ref;

    # Connect to the NetDB database
    my $dbh = connectDBro( $config_file );
    my $dbname = $dbh->{Name};
    my $dbuser = $dbh->{Username};

    # MenuBar
    $menuBar =~ s/TRANSACTION/$transactionID/;
    print $menuBar;


    print "<br>Database: Connected to $dbname as $dbuser, querying $address as $inputType\n" if $verbose;
    print "<br>Transaction ID: $transactionID\n" if $verbose;
    
    # IP Address Report
    if ( $inputType eq "IP" ) {

	$CSVOption = "-i $address";

	$netdb_ref = getMACsfromIP( $dbh, $address, $opthours );

	if ( $$netdb_ref[0] ) {

	    # Check to see that maximum return count not exceeded
	    if ( @$netdb_ref < $reportMaxCount{"$userAuthLevel"} ) { 

		printNetdbIPMAC( $netdb_ref );
		
		if ( !$$netdb_ref[1] ) {
		    printWakeOnLan( $$netdb_ref[0]{"mac"}, $$netdb_ref[0]{"ip"} ); # Wake on lan for single host
		}
	    }
	    else {
		&exceedMaxCount( $netdb_ref );
	    }
	}
	else {
	    $infomsg = "<b>IP Search</b>: No ARP entries for IP $address within the past $searchDays days.";
	}
	# Print Registration Data if Available on single entries
        getNACRegData( $dbh, $$netdb_ref[0]{"mac"} ) if ( !$$netdb_ref[1] && $$netdb_ref[0] );

	# Print the switchport history if only one entry returned
	getSwitchport( $dbh, $$netdb_ref[0]{"mac"}, $opthours ) if ( !$$netdb_ref[1] && $$netdb_ref[0] );
    }

    # Hostname Report
    elsif ( $inputType eq "Hostname" ) {

	$CSVOption = "-n $address";

	$netdb_ref = getNamefromIPMAC( $dbh, $address, $opthours );

	if ( $$netdb_ref[0] ) {
            if ( @$netdb_ref < $reportMaxCount{"$userAuthLevel"} ) {
		
		printNetdbIPMAC( $netdb_ref );
		
		if ( !$$netdb_ref[1] ) {
		    printWakeOnLan( $$netdb_ref[0]{"mac"}, $$netdb_ref[0]{"ip"} ); # Wake on lan for single host
		}
	    }
            else {
                &exceedMaxCount( $netdb_ref );
            }
        }
        else {
            $infomsg = "<b>Hostname Search</b>: No hostname $address within the past $searchDays days, expecting a full or partial hostname.
                        <br><br>Usage Tip: 
                        When searching for full or partial hostnames, the IP address of the device must reverse lookup 
                        in DNS to the hostname searched.  Aliases and secondaries won't lookup.";
        }
	# Print Registration Data if Available on single entries
        getNACRegData( $dbh, $$netdb_ref[0]{"mac"} ) if ( !$$netdb_ref[1] && $$netdb_ref[0] );
	
	# Print the switchport history if only one entry returned
	getSwitchport( $dbh, $$netdb_ref[0]{"mac"}, $opthours ) if ( !$$netdb_ref[1] && $$netdb_ref[0] );
    }

    # MAC Report
    elsif ( $inputType eq "MAC" ) {
        $CSVOption = "-m $address";
	getMACReport( $dbh, $address, $opthours );
    }
    
    # ShortMAC Report
    elsif ( $inputType eq "ShortMAC" ) {
	$netdb_ref = getShortMAC( $dbh, $address, $opthours );
	
	# Multiple MACs returned, print them all and stop
	if ( $$netdb_ref[1] ) {
	    printNetdbMAC( $netdb_ref );
	}

	# Single Mac entry, get full report
	elsif ( $$netdb_ref[0]{"mac"} ) {
	    getMACReport( $dbh, $$netdb_ref[0]{"mac"}, $opthours );
	}
	else {
	    $infomsg = "<b>Short MAC Search</b>: No records for Short MAC $address within the past $searchDays days.";
	}
    }

    # Single Switchport Report
    elsif ( $inputType eq "switch" ) {
	getSwitchport( $dbh, $address, $opthours );
    }
    
    # Vendor Code Search
    elsif ( $inputType eq "vendor" ) {
	
	$CSVOption = "-vc $address";

	my $netdb_ref = getVendorCode( $dbh, $address, $opthours );
	
	if ( $$netdb_ref[0] ) {
	    if ( @$netdb_ref < $reportMaxCount{"$userAuthLevel"} ) {
		printNetdbMAC( $netdb_ref );
	    }
	    else {
		&exceedMaxCount( $netdb_ref );
	    }
	}
	    
        else {
            $infomsg = "<b>Vendorcode Report</b>: No records for vendor code $address within the past $searchDays days. Expecting a string like 
                       'apple'<br><br> 
                        Usage Tip: Sometimes vendor searches fail when special characters like & are used, try searching for part of the vendor code.";
        }
    }

    # Switch Report
    elsif ( $inputType eq "switchreport" ) {

	$CSVOption = "-sw $address";

	my $netdb_ref = getSwitchReport( $dbh, $address, $opthours );

        if ( $$netdb_ref[0] ) {
	    if ( @$netdb_ref < $reportMaxCount{"$userAuthLevel"} ) {

		# Optional Inventory Header
		if ( $useInventory ) {
		    printSwitchInventory( $address );
		}
		
		# Regular Switch Report
		printNetdbSwitchports( $netdb_ref );
	    }
            else {
                &exceedMaxCount( $netdb_ref );
            }
	}
	else {
            $infomsg = "<b>Switch Report</b>: No switches named $address found within the past $searchDays days. 
                        <br><br><b>New Feature</b>: Search for partial switch names such as site2* or *datacenter*.";
	}
    }

    # Description Search
    elsif ( $inputType eq "desc_search" ) {

	$CSVOption = "-ds $address";

        my $netdb_ref = getSwitchportDesc( $dbh, $address, $opthours );

        if ( $$netdb_ref[0] ) {
            if ( @$netdb_ref < $reportMaxCount{"$userAuthLevel"} ) {
		
                # Regular Switch Report
                printNetdbSwitchports( $netdb_ref );
            }
            else {
                &exceedMaxCount( $netdb_ref );
            }
        }
        else {
            $infomsg = "<b>Description Search</b>: No switch ports with description $address (case-insensitive) found within the past $searchDays days."
        }
    }

    # Unused Ports Report
    elsif ( $inputType eq "unusedports" ) {

        $CSVOption = "-su $address";

        my $netdb_ref = getUnusedPorts( $dbh, $address, $opthours );

	# Switch Inventory
	if ( $useInventory ) {
	    printSwitchInventory( $address );
	}

        if ( $$netdb_ref[0] ) {
            if ( @$netdb_ref < $reportMaxCount{"$userAuthLevel"} ) {
                printNetdbSwitchports( $netdb_ref );
            }
            else {
                &exceedMaxCount( $netdb_ref );
            }
        }	
        else {
            $infomsg = "<b>Unused Ports</b>: No unused ports for switch $address within the past $searchDays days.
                        Expecting the name of a switch or a partial switch name such as site2* or *datacenter*.";
        }	
    }

    # Vlan Report
    elsif ( $inputType eq "vlanreport" ) {

        $CSVOption = "-vl $address";

	$netdb_ref = getVlanReport( $dbh, $address, $opthours );

        if ( $$netdb_ref[0] ) {
            if ( @$netdb_ref < $reportMaxCount{"$userAuthLevel"} ) {
		printNetdbIPMAC( $netdb_ref );
	    }
            else {
                &exceedMaxCount( $netdb_ref );
            }
        }
        else {
            $infomsg = "<b>VLAN Report</b>: No ARP entries on VLAN $address within the past $searchDays days. 
                        Expecting a VLAN number.";
        }
    }

    # Vlan Status
    elsif ( $inputType eq "vlanstatus" ) {
        $CSVOption = "-vs $address";

        $netdb_ref = getVlanSwitchStatus( $dbh, $address, $opthours );

        if ( $$netdb_ref[0] ) {
            if ( @$netdb_ref < $reportMaxCount{"$userAuthLevel"} ) {
		printNetdbSwitchports( $netdb_ref );
            }
            else {
                &exceedMaxCount( $netdb_ref );
            }
        }
        else {
            $infomsg = "<b>VLAN Switchport Report</b>: No switchports found for VLAN $address within the past $searchDays" .
                       "days in switch status table, expecting a VLAN number.";
        }
    }

    # NAC User Report
    elsif ( $inputType eq "user" ) {

	$CSVOption = "-u $address";

	# MAC Table data for a user
        $netdb_ref = getNACUserMAC( $dbh, $address, $opthours );

        if ( $$netdb_ref[0] ) {
            if ( @$netdb_ref < $reportMaxCount{"$userAuthLevel"} ) {
		getNACRegData( $dbh, $$netdb_ref[0]{"mac"} );
                printNetdbMAC( $netdb_ref );
            }
            else {
                &exceedMaxCount( $netdb_ref );
            }
	    
	    # ARP Table Data
	    $netdb_ref = getNACUser( $dbh, $address, $opthours );

	    if ( @$netdb_ref < $reportMaxCount{"$userAuthLevel"} ) {
                printNetdbIPMAC( $netdb_ref );
	    }
            else {
                &exceedMaxCount( $netdb_ref );
            }
        }
        else {
            $infomsg = "<b>NAC User Report</b>: No MACs found for username $address ($inputType) within the past $searchDays days.";
        }

    }
    

    # New MACs Report
    elsif ( $inputType eq "newmacs" ) {
        $CSVOption = "-vs $address";

	# Don't allow searches longer than 30 days
	$opthours = 720 if $opthours > 720;

        $netdb_ref = getNewMacs( $dbh, $opthours );


        if ( $$netdb_ref[0] ) {
            if ( @$netdb_ref < $reportMaxCount{"$userAuthLevel"} ) {
		printNetdbIPMAC( $netdb_ref );
            }
            else {
                &exceedMaxCount( $netdb_ref );
            }
        }
        else {
            $infomsg = "No new LAN devices within this time period.";
        }
    }
    
    # Switch Inventory (Optional)
    elsif ( $inputType eq "invreport" && $useInventory ) {
	$CSVOption = "-si $address";

	printSwitchInventory( $address, $dbh );
    }

    # Unknown Report Type Error
    else {
	$errmsg = "Unknown Report Type: $inputType";
    }
    return;    
}

# Called if too many results returned for user access level
sub exceedMaxCount {
    my $netdb_ref = shift;
    
    my $nextLevel = $userAuthLevel + 1;
    my $count = @$netdb_ref;

    print "Exceeded Max Results Count: $count results" if $DEBUG;

    $errmsg = "<b>Too Many Results</b>: Your query returned too many results for Access Level $userAuthLevel (max $reportMaxCount{$userAuthLevel}).  Please " . 
              "try to restrict your search terms, or contact <a href=\"mailto:$ownerEmail\">$ownerInfo</a> and request that your username be added to the " . 
	      "Level $nextLevel Access List.<br><br>(config: $config_cgi)";
    return;
}

# Prints a single switchport entry
sub getSwitchport {
    my $dbh = shift;
    my $address = shift;
    my $opthours = shift;

    my $netdb_ref = getMAC( $dbh, $address );
    
    if ( $$netdb_ref[0] ) {

	printNetdbMAC( $netdb_ref );

	$netdb_ref = getSwitchports( $dbh, $address, $opthours );
	printNetdbSwitchports( $netdb_ref );
    }
    else {
	$infomsg = "<b>MAC Address Search</b>: No records for MAC $address within the past $searchDays days";
    }
}

# Print the NAC Registration Data if Available
sub getNACRegData {
    my $dbh = shift;
    my $address = shift;

    # Only get NAC Data if NAC is enabled
    if ( $useNAC ) {
	my $netdb_ref = getNACReg( $dbh, $address );
	
	if ( $$netdb_ref[0] ) {	
	    printNetdbNACReg( $netdb_ref );
	}
    }
}

# Get Data on a single MAC Entry
sub getMACReport {
    my $dbh = shift;
    my $address = shift;
    my $opthours = shift;
    my $v4count = 0;
    my $v6count = 0;
    
    my $netdb_ref = getIPsfromMAC( $dbh, $address, $opthours );

    # At least one entry returned
    if ( $$netdb_ref[0] ) {
	if ( @$netdb_ref < $reportMaxCount{"$userAuthLevel"} ) {

	    
	    # Multiple ARP entries, print Mac Entry and registration at top
	    if ( $$netdb_ref[1] ) {
		
		# Print Single Mac Entry
		my $netdbmac_ref = getMAC( $dbh, $address );
		printNetdbMAC( $netdbmac_ref );
		
		# Deprecated method
		#printMacEntry( $dbh, $address );

		getNACRegData( $dbh, $address );
		
		# Print ARP Table Results
		printNetdbIPMAC( $netdb_ref );

		# Check for IPv4 entry plus v6 entry or more, if so print switchport
		foreach my $nref ( @$netdb_ref ) {
		    if ( $$nref{ip} =~ /^\d+\.\d+\.\d+\.\d+$/ ) {
			$v4count++;
		    }
		    elsif ( $$nref{ip} =~ /:/ ) {
			$v6count++;
		    }
		}
		
		# Print switchport entry if multiple ARP entries are less than 10
		if ( $v4count >= 1 && $v4count < 10 ) {
		    my $switch_ref = getSwitchports( $dbh, $address, $opthours );
		    printNetdbSwitchports( $switch_ref );
		}
	    }
	    
	    # Single ARP Entry, just print ARP Table Entry
	    else {
		printNetdbIPMAC( $netdb_ref );
	    }
	    
	    # Wake on LAN tab
	    if ( !$$netdb_ref[1] || ($v4count == 1 && $v6count ) ) {
		printWakeOnLan( $$netdb_ref[0]{"mac"}, $$netdb_ref[0]{"ip"} ); # Wake on lan for single host                                 
	    }
	}
	else {
	    &exceedMaxCount( $netdb_ref );
	}
    }
    # Fallback to mac table if nothing in arp table
    else {
	getSwitchport( $dbh, $address, $opthours );
    }

    # Print Registration Data if Available on single entries
    getNACRegData( $dbh, $$netdb_ref[0]{"mac"} ) if ( !$$netdb_ref[1] && $$netdb_ref[0] );
    
    # Print the switchport history if only one entry returned
    getSwitchport( $dbh, $$netdb_ref[0]{"mac"} ) if ( !$$netdb_ref[1] && $$netdb_ref[0] );
}


# Get IP MAC Pairs for WoL hostname search 
sub getIPMACs {
    my $hostname = shift;
    my $opthours = shift;
    my @ipmacpair;

    print "<br>DEBUG Wake NAME: $hostname" if $DEBUG;;

    my $dbh = connectDBro( $config_file );

    $opthours = 168 if !$opthours;
    
    my $netdb_ref = getNamefromIPMAC( $dbh, $hostname, $opthours );

    if ( $$netdb_ref[0] && @$netdb_ref < 3 ) {

	foreach my $entry_ref ( @$netdb_ref ) { 
	    push( @ipmacpair, "$entry_ref->{ip},$entry_ref->{mac}" );
	    print "<br>DEBUG WoL: $entry_ref->{ip},$entry_ref->{mac}" if $DEBUG;
	}
	
	return @ipmacpair;
    }
    elsif ( @$netdb_ref >= 3 ) {
	print "<div id=\"errordialog\">Received too many search results for hostname</div><br>\n";
	return undef;
    }
}

# Logs user transaction to the transaction table
sub recordTransaction {
    
    # Priviledged Access
    my $dbh_p = connectDBrw( $config_file );

    my ( $queryvalue, $querytype ) = @_;
    my $ip       = $ENV{REMOTE_ADDR};
    my $username = $envuser; 
    $searchDays = 1 if !$searchDays;
    my $tid;

    $username = 'noauth' if !$username;

    my %netdbTransaction = ( ip => $ip,
			     username => $username,
			     querytype => $querytype,
			     queryvalue => $queryvalue,
			     querydays => $searchDays,
			   );

    # Keep transactionID for CSV Reports
    $tid = insertTransaction( $dbh_p, \%netdbTransaction );

    return $tid;
}

#######################
# Table Printout Code #
#######################


# ARP Table Data
#
# Data is saved to @ntable and @netdbText arrays to be outputed by 
# printResults
#
sub printNetdbIPMAC {
    my $ptext_ref = shift;
    my $resultcountPrint = undef;
    
    # Sort Array of hashrefs by IP address
    $ptext_ref = sortByIP( $ptext_ref );

    # Put the mac address in to the desired format
    $ptext_ref = convertMacFormat( $ptext_ref, $mac_format );

    # Dereference array of hashrefs
    my @ptext = @$ptext_ref;

    # Get length for loop
    my $ptext_length = @ptext;

    if ( $ptext_length > 1 ) {
        $resultcountPrint = "\($ptext_length\)";
    }

    # If there is data, populate the arrays
    if ( $ptext_length > 0 ) {

        push ( @ntable, '<div class="netdb">');

        # Only Enable sorting on table if it has more than one item
        if ( $ptext_length > 1 ) {
            push( @ntable, '<table id="netdbipmac">');
        }
        else {
            push( @ntable, '<table>');
        }

        # Table Caption
        push ( @ntable, "<caption><h2>ARP Table $resultcountPrint</h2></caption>" );

        push ( @ntable, '
        <thead>
        <tr>
        <th>IP Address</th>
        <th>MAC Address</th>
        ');
	
	if ( $useNAC ) {
	    push ( @ntable, '<th>User</th>');
	}

        push ( @ntable, '
        <th>VLAN</th>
        <th>Hostname</th>
        <th>DHCP</th>
        <th>Firstseen</th>
        <th>Lastseen</th>
      </tr>
      </thead>
      <tbody>
');
	# Go through hashref array and print table
	for (my $i=0; $i < $ptext_length; $i++)
	{
	    # Change 0's and 1's to yes and no for statics
	    if ( $ptext[$i]{static} == 1 ) {
		$ptext[$i]{static} = "<b>static</b>";
	    }
	    else {
		$ptext[$i]{static} = "dynamic";
	    }

	    # Try to get the ip from lastip if ip is null
            $ptext[$i]{ip} = $ptext[$i]{lastip} if !$ptext[$i]{ip};

	    # IP
	    push ( @ntable, "<tr><td><a href=\"$scriptLocation?address=$ptext[$i]{ip}&days=$searchDays$getOptions\#content\"" );

	    # Router and VRF Tooltip
	    push ( @ntable, "title=\"Router: $ptext[$i]{router}" );
	    #push ( @ntable, "<br>VRF: $ptext[$i]{vrf}" ) if $ptext[$i]{vrf};
	    push ( @ntable, "\" class=\"tooltip\">" );
	    push ( @ntable, "$ptext[$i]{ip}</a>" );
	    #push ( @ntable, " [$ptext[$i]{vrf}]" ) if $ptext[$i]{vrf};
	    push ( @ntable, "</td>\n" );

	    # Add mac_nd to vendor data if available
	    my $mac_nd;
	    $mac_nd = "<br>$ptext[$i]{mac_nd}" if $ptext[$i]{mac_nd};

	    push ( @ntable, "<td><a href=\"$scriptLocation?address=$ptext[$i]{mac}&days=$searchDays$getOptions\#content\"
                                  title=\"$ptext[$i]{vendor}$mac_nd\" class=\"tooltip\">$ptext[$i]{mac}</a>\n" );
	    push ( @ntable, "<font size=\"2\"> <a href=\"$scriptLocation?address=$ptext[$i]{mac}&switch=1&days=$searchDays$getOptions\#content\"
                                  title=\"Last Port: $ptext[$i]{lastswitch} $ptext[$i]{lastport}\" class=\"tooltip\">
                                  [ports]</a></font></td>\n" );
	    push ( @ntable, "<td><a href=\"$scriptLocation?address=$ptext[$i]{userID}&user=1&days=$searchDays$getOptions\#content\"
		                  title=\"$ptext[$i]{firstName} $ptext[$i]{lastName}\" class=\"tooltip\">$ptext[$i]{userID}</a>\n" ) if $useNAC;
	    push ( @ntable, "<td><a href=\"$scriptLocation?address=$ptext[$i]{vlan}&vlan=1&days=$searchDays$getOptions\#content\">
                                  $ptext[$i]{vlan}</a>" );
            if ( $ptext[$i]{vrf} ) {
                push ( @ntable, "<b>/ $ptext[$i]{vrf}</b>" ); #VRF
            }
            push ( @ntable, "</td>\n" );
 
	    push ( @ntable, "<td><a href=\"$scriptLocation?address=$ptext[$i]{name}&days=$searchDays$getOptions\#content\">
                                  $ptext[$i]{name}</a></td>\n" );
	    push ( @ntable, "<td>$ptext[$i]{static}</td>\n" );
	    push ( @ntable, "<td>$ptext[$i]{firstseen}</td><td>$ptext[$i]{lastseen}</td></tr>\n" );


	    # Plain Text Output
	    push ( @netdbText, "<h1>ARP: ($ptext[$i]{ip}, $ptext[$i]{mac}, $ptext[$i]{vlan})</h1>\n<hr/>\n" );

	    push ( @netdbText, "<label><span>IP Address: </span><a href=\"$scriptLocation?address=$ptext[$i]{ip}&days=$searchDays$getOptions\#content\">
                                $ptext[$i]{ip}</a></label>\n" );
	    push ( @netdbText, "<label><span>MAC Address: </span><a href=\"$scriptLocation?address=$ptext[$i]{mac}&days=$searchDays$getOptions\#content\">
                                $ptext[$i]{mac}</a></label>\n" );
            push ( @netdbText, "<label><span>Hostname: </span><a href=\"$scriptLocation?address=$ptext[$i]{name}&days=$searchDays$getOptions\#content\">
                                $ptext[$i]{name}</a></label>\n" );
            push ( @netdbText, "<label><span>Vendor Code: </span><a href=\"$scriptLocation?address=$ptext[$i]{vendor}&days=$searchDays&vendor=1\#content\">
                                $ptext[$i]{vendor}</a></label>\n" );
            push ( @netdbText, "<label><span>VLAN: </span><a href=\"$scriptLocation?address=$ptext[$i]{vlan}&vlan=1&days=$searchDays$getOptions\#content\">
                                $ptext[$i]{vlan}</a></label>\n" ) if $ptext[$i]{vlan};
            push ( @netdbText, "<label><span>First Seen: </span>$ptext[$i]{firstseen}</label>\n" );
            push ( @netdbText, "<label><span>Last Seen: </span>$ptext[$i]{lastseen}</label>\n" );
	    push ( @netdbText, "<br>\n" );

	}
	
	push ( @ntable, "</tbody></table></div>\n" );
# 	push ( @ntable, "<br>\n" );
    }
}


##################
# MAC Table Data #
##################
sub printNetdbMAC {
    my $ptext_ref = shift;
    my $resultcountPrint = undef;
    my $disauth;
    my $enauth;
    
    if ( $reportAuthLevel{"disable_client"} ) {

	# Get Disable Authorization
	if ( $userAuthLevel >= $reportAuthLevel{"disable_client"} && $reportAuthLevel{"disable_client"} ) {
	    $disauth = 1;
	    print "<br>Debug: User Authorized to Disable Clients\n" if $DEBUG;
	} 
	if ( $userAuthLevel >= $reportAuthLevel{"enable_client"} && $reportAuthLevel{"enable_client"} ) {
	    $enauth = 1;
	    print "<br>Debug: User Authorized to Enable Clients\n" if $DEBUG;
	}
	
	# Create Disable Dialog Box
	print "<div id=\"disabledialog\" title=\"Disable a MAC Address\" style=\"display: none;\"><font size=\"3\">\n";
	print '<div class="loading" id=\"loadingdisable\" style="position:relative; margin:10px; left:0px; top:0px; height:0px; width:0px">
           <img src="/depends/loading.gif" border=0></div>';
	print "<div id=\"disabletext\"></div>\n";
	
	print "<div id=\"disableform\"><form name=\"disableform\" method=\"POST\" action=\"\">";
	
	print "<br><br><label><span><b>Block Type</b></span><br></label>";
	print "<br><input name\=\"blocktype\" id=\"blockfirewall\" type\=\"radio\" value=\"nonetnac\"  size\=\"10\">Block Internet Access via NAC</input>";
	print "<br><input name\=\"blocktype\" id=\"blockshut\" type\=\"radio\" text=\"Shutdown MAC Address\"value=\"shutdown\" size\=\"10\">Shutdown MAC Address (Preferred)</input>";
	#print "<br><input name\=\"blocktype\" id=\"portshut\" type\=\"radio\" text=\"Physically Shutdown Port\"value=\"shutdown\" size\=\"10\">Physically Shutdown Port</input>";
	print "<br><br> <button tabindex=\"2\" id=\"disablesubmit\" type=\"submit\">Next</button>";
	print '<input type="hidden" name="disablechange" value="1">';
	
	print "</form>";
	print"</div></font></div>";
	
	
	# Create Enable Dialog Box
	print "<div id=\"enabledialog\" title=\"Unblock a MAC Address\" style=\"display: none;\"><font size=\"3\">\n";
	print '<div class="loading" style="position:relative; margin:20px; left:0px; top:0px; height:0px; width:0px">
           <img src="/depends/loading.gif" border=0></div>';
	print "<div id=\"enabletext\"></div>\n";
	
	print "<div id=\"enableform\"><form name=\"enableform\" method=\"POST\" action=\"\">";
	print "<br><b><label><span>Short note on reason to unblock (required)</span></label></b>";
	print "<br><input name\=\"enablenote\" id=\"enablenote\" type\=\"text\" class=\"input-text\" size\=\"50\"
                          tabindex=\"20\"></input></label>\n";
	print "<br><br> <button tabindex=\"2\" id=\"enablesubmit\" type=\"submit\">Unblock Client</button>";
	print '<input type="hidden" name="enablechange" value="1">';
	
	print "</form>";
	print"</div></font></div>";
    }



    # Put the mac address in to the desired format
    $ptext_ref = convertMacFormat( $ptext_ref, $mac_format );
    
    # Dereference array of hashrefs
    my @ptext = @$ptext_ref;

    # Get length for loop
    my $ptext_length = @ptext;

    if ( $ptext_length > 1 ) {
        $resultcountPrint = "\($ptext_length\)";
    }

    # If there is returned data, print the table
    if ( $ptext_length > 0 ) {

        push ( @ntable, '<div class="netdb">');

        # Only Enable sorting on table if it has more than one item
        if ( $ptext_length > 1 ) {
            push( @ntable, '<table id="netdbmac">');
        }
        else {
            push( @ntable, '<table>');
        }	

        push ( @ntable, "<caption><h2>MAC Address Table $resultcountPrint</h2></caption>" );

        push ( @ntable, '
        <thead>
        <tr>
        <th>MAC Address</th>
        <th>Last IP Address</th>
        <th>Last Hostname</th>
        <th>NIC Vendor</th>
        <th>Last Switch</th>
        <th>Last Port</th>
      </tr>
      </thead>
      <tbody>
' );

	# Print Results
	for (my $i=0; $i < $ptext_length; $i++)
	{

	    # Clean up vendor code data
	    my $vendorLink = $ptext[$i]{"vendor"};
	    $vendorLink =~ s/\s/%20/g;
            $vendorLink =~ s/\&/%26/g;
            $ptext[$i]{"vendor"} =~ s/\&\s//g;


	    # Client is disabled, flag it and print the right dialog box
	    if ( $ptext[$i]{distype} ) {

		my $encodedcase = $ptext[$i]{discase};
		$encodedcase =~ s/\[|\]//g;

		$encodedcase = CGI::escape( $encodedcase );

		push ( @ntable, "<tr><td><b><a href=\"$scriptLocation?address=$ptext[$i]{mac}&days=$searchDays$getOptions\#content\"
                                   title=\"Restriction $ptext[$i]{distype}, device owned by $ptext[$i]{userID}, 
                                   restricted by $ptext[$i]{disuser} 
                                   on $ptext[$i]{disdate}, CaseID $ptext[$i]{discase}\" class=\"tooltip\">
                                   $ptext[$i]{mac}</a> <font color=\"red\">( Security Restriction - ELOG Case: 
                                   <a href=\"http://hal.musc.edu:8080/nst-shutports/?mode=full&reverse=0&reverse=1&npp=20&subtext=$encodedcase\">
                                   $ptext[$i]{discase}</a>
                                   -- <a href=\"mailto:security\@musc.edu?Subject=Case $ptext[$i]{discase} MAC $ptext[$i]{mac}\">
                                   Email Security</a> )</b></font>\n" );
		
		# Enable Client Access (checked again later, not allowed if case is severe)
		if ( $enauth ) {
		    push ( @ntable, " <a href=\"#enable-$ptext[$i]{mac}-$ptext[$i]{distype}-$ptext[$i]{severity}\" class=\"enableclient\">" );
		    push ( @ntable, "<img src=\"/depends/green_icon.png\" border=\"0\"></a>" );
		}
		push ( @ntable, "</td>" );
	    }

	    # Normal Client
	    else {
		push ( @ntable, "<tr><td><a href=\"$scriptLocation?address=$ptext[$i]{mac}&days=$searchDays$getOptions\#content\"
                                   title=\"First Seen: $ptext[$i]{firstseen} Last Seen: $ptext[$i]{lastseen}\ User: $ptext[$i]{userID}\" class=\"tooltip\">
                                   $ptext[$i]{mac}</a>\n" );
		
		# Disable Client (checked again later)
		if ( $disauth ) {
		    push ( @ntable, " <a href=\"#disable-$ptext[$i]{mac}\" class=\"disclient\">" );
		    push ( @ntable, "<img src=\"/depends/x_icon3.png\" border=\"0\"></a>" );
		}
		push ( @ntable, "</td>" );
	    }

	    push ( @ntable, "<td><a href=\"$scriptLocation?address=$ptext[$i]{lastip}&days=$searchDays$getOptions\#content\">$ptext[$i]{lastip}</a></td>\n" );
	    push ( @ntable, "<td><a href=\"$scriptLocation?address=$ptext[$i]{name}&days=$searchDays$getOptions\#content\">$ptext[$i]{name}</a></td>\n" );

	    # Vendor with extended mac_nd if available
	    push ( @ntable, "<td><a href=\"$scriptLocation?address=$vendorLink&vendor=1&days=$searchDays$getOptions\#content\">$ptext[$i]{vendor}\n</a>" );

	    if ( $ptext[$i]{mac_nd} ) {
		push ( @ntable, " ($ptext[$i]{mac_nd})" );
		
	    }
	    push ( @ntable, "</td>\n" );

	    push ( @ntable, "<td><a href=\"$scriptLocation?address=$ptext[$i]{lastswitch}&days=$searchDays$getOptions&switchreport=1\#content\">
                                  $ptext[$i]{lastswitch}</a></td>\n" );
	    push ( @ntable, "<td><a href=\"$scriptLocation?address=$ptext[$i]{lastswitch},$ptext[$i]{lastport}&days=$searchDays$getOptions&switchreport=1\#content\">
                                 $ptext[$i]{lastport}</a></td></tr>\n" );
	}
        push ( @ntable, "</tbody></table></div>\n" );
    }
}

#####################################################################
# Switch Inventory Data 
#
# Recursive, first search for exact match, then recall with wildcard
# if none found
#
#####################################################################
sub printSwitchInventory {
    my $host = shift;
    my ( $switch ) = split( /\./, $host );
    my $dbh = shift;
    my $wildcard = shift;
    my ( $multiReport, $model, $version, $longversion, $match, $term1, $term2 );
    my %model;
    my %version;
    my %longversion;
    my %uptime;
    my %fqdn;
    my @switches;

    # Two search terms, wildcard by default
    if ( $switch =~ /\w+\s+\w+/ ) {
	( $term1, $term2 ) = split( /\s+/, $switch );
	$wildcard = 1;
	print "<br>Term1: $term1 Term2: $term2" if $DEBUG;
	$multiReport = 1;
    }

    # Wildcard switch report
    if ( $switch =~ /\w+\*/ || $wildcard ) {
	$multiReport = 1;
	$switch =~ s/\*$//;
    }

    # Single Device Report
    else {
	push( @switches, $switch );
    }


    # Get Versions from file
    open( my $VERSION, '<', $useInventory ) or die "Can't open $useInventory file.";;

    # Populate hashes with switch info from file, do search if wildcard
    while ( my $line = <$VERSION> ) {
	my ( $fileswitch, $uptime, $fqdn );
	( $fqdn, $model, $longversion, $version, $uptime ) = split( /,/, $line );
	( $fileswitch ) = split( /\./, $fqdn );
	$fqdn{$fileswitch} = $fqdn;

	$version{$fileswitch} = $version;
	$model{$fileswitch} = $model;
	$longversion{$fileswitch} = $longversion;

	# Get uptime and cleanup
	$uptime =~ s/\//\, /g;
	$uptime{$fileswitch} = "Uptime: $uptime";
	
	# Search for multiple switches from file based on wildcard
	if ( $fileswitch =~ /$term1/ && $fileswitch =~ /$term2/ && $multiReport ) {
	    push( @switches, $fileswitch );
	} 
	elsif ( $fileswitch =~ /$switch/ && $multiReport ) {
            push( @switches, $fileswitch );
        }  
    }

    # Do a wildcard recursive search if no results on specific entry
    if ( !$multiReport && !$model{$switch} ) {
	printSwitchInventory( $switch, $dbh, 1 );
	return;
    }

    # If a wildcard search and only one entry, turn off multiReport
    if ( $wildcard && !$switches[1] ) {
	$multiReport = undef;
	$switch = $switches[0];
    }


    # Report Dialog Box
    print "<div id=\"reportdialog\" title=\"NetDB Report\" style=\"display: none;\"><font size=\"3\">\n";
    print "<pre id=\"reporttext\"></pre>\n";

    print "</font></div>";

    push( @ntable, '<div class="netdb">');
    push( @ntable, '<br><table border="1" id="netdbinv">');

    if ( $multiReport && $switches[1] ) {
        push ( @ntable, "<caption><h2>Switch Inventory</h2></caption>" );
        push( @ntable, '
        <thead>
        <tr>
        <th>Switch</th>
        <th>Model</th>
        <th>Version</th>
        <th>Interfaces</th>
        <th>VLANs</th>
        <th>CDP</th>
        <th>Unused Ports</th>
        <th>Configuration</th>
      </tr>
      </thead>
');
    }

    
    push( @ntable, "\n<tbody>" );

    
    foreach my $switch ( @switches ) {

	$version{$switch} = "Unknown" if !$version{$switch};

	push ( @ntable, "<tr><td> 
                         <a href=\"$scriptLocation?address=$switch&days=$searchDays$getOptions&switchreport=1\#content\">
                                  <b>$switch</b></a><a href=\"ssh://$fqdn{$switch}\">
                                  <img src=\"/depends/terminal-icon.png\" align=\"right\" border=\"0\"></td>\n" );
        push( @ntable, "<td><a href=\"#invreport-/status/$switch-model.txt\" class=\"invreport tooltip\"
                        title=\"$uptime{$switch}\"><b>$model{$switch}</b></a></td>\n" );
	push( @ntable, "<td><a href=\"#invreport-/status/$switch-ver.txt\" class=\"invreport tooltip\"
                        title=\"$longversion{$switch}\"><b>$version{$switch}</b></a></td>\n" );
	push( @ntable, "<td><a href=\"#invreport-/status/$switch-int.txt\" class=\"invreport\"><b>Interfaces</b></a></td>\n" );
        push( @ntable, "<td><a href=\"#invreport-/status/$switch-vlan.txt\" class=\"invreport\"><b>VLANs</b></a></td>\n" );
        push( @ntable, "<td><a href=\"#invreport-/status/$switch-cdp.txt\" class=\"invreport\"><b>CDP</b></a></td>\n" );
	push( @ntable, "<td><a href=\"$scriptLocation?address=$switch&days=365$getOptions&unusedports=1\#content\"><b>Unused Ports</b></a></td>" );
#	push( @ntable, "<td><a href=\"/configs/$switch-confg\">Saved Configuration</a></td>\n" );
	push( @ntable, "<td><a href=\"#invreport-/configs/$switch-confg\" class=\"invreport\"><b>Configuration</b></a></td>\n" );
	push( @ntable, "</tr>\n" );
    }

    push( @ntable, "</tbody></table></div>\n" );


    # If not a multiswitch report, print the netdb switch results
    if ( !$multiReport && $dbh && $switches[0] ) {
	my $netdb_ref = getSwitchReport( $dbh, $switch, 168 );

	printNetdbSwitchports( $netdb_ref );
    }
    elsif ( $wildcard && !$switches[0] && $inputType eq "invreport" ) {
	$infomsg = "<b>Switch Inventory</b>: No switch named $host or partially named $host found.
                        <br><br><b>Search Feature</b>: Search for for more than one term, such as mdf muh.";
    }
}

####################
# Switchports data #
####################
sub printNetdbSwitchports {
    my $ptext_ref = shift;
    my $resultcountPrint = undef;
    my $vcauth = undef;
    my $wifi = undef;
    my $descauth = undef;
    my $wifiauth;
    my %freeports;
    my %portstatus;

    # Sort Array of hashrefs based on Cisco Port naming scheme
    $ptext_ref = sortByPort( $ptext_ref );
    $ptext_ref = sortBySwitch( $ptext_ref );

    # Put the mac address in to the desired format
    $ptext_ref = convertMacFormat( $ptext_ref, $mac_format );

    # Dereference array of hashrefs
    my @ptext = @$ptext_ref;

    # Get length for loop
    my $ptext_length = @ptext;

    # Get Wifi Data Authorization
    if ( $userAuthLevel >= $reportAuthLevel{"wifidata"} && $reportAuthLevel{"wifidata"} ) {
	$wifiauth = 1;
        print "<br>Debug: User Authorized for WifiData\n" if $DEBUG;
    }

    # Get Vlan Change Authorization
    if ( $userAuthLevel >= $reportAuthLevel{"vlan_change"} && $reportAuthLevel{"vlan_change"} ) {
	$vcauth = 1;
	print "<br>Debug: User Authorized for Vlan Change\n" if $DEBUG;
    }

    # Get Description Change Authorization
    if ( $userAuthLevel >= $reportAuthLevel{"desc_change"} && $reportAuthLevel{"desc_change"} ) {
        $descauth = 1;
        print "<br>Debug: User Authorized for Description Change\n" if $DEBUG;
    }

    # Create VLAN Change Dialog Box
    print "<div id=\"vlandialog\" title=\"Change the VLAN on a Switchport\" style=\"display: none;\"><font size=\"3\">\n";
    print '<div class="loading" id=\"loadingvlan\" style="position:relative; margin:20px; left:0px; top:0px; height:0px; width:0px">
           <img src="/depends/loading.gif" border=0></div>';
    print "<div id=\"vlantext\"></div>\n";
    
    print "<div id=\"vlanform\"><form name=\"vlanchangeform\" id=\"vlanform\" method=\"POST\" action=\"\">";
    
    print "<br><label><span>VLAN ID </span><input name\=\"vlan\" id=\"vlanid\" type\=\"text\" class=\"input-text\" size\=\"10\" 
               tabindex=\"5\" type=\"submit\"></label>";
    print " <button tabindex=\"2\" id=\"vlansubmit\" type=\"submit\">Change VLAN</button>";
    print "<br><label><span>Voice VLAN </span><input name\=\"voicevlan\" id=\"voicevlan\" type\=\"text\" class=\"input-text\" size\=\"10\"
               tabindex=\"5\" type=\"submit\" type=\"hidden\"></label>";
    print '<input type="hidden" name="vlanchange" value="1">';
    print '<input type="hidden" id="vlanswitchport" name="vlanswitchport" value="1">';
    
    print "</form>";
    print"</div></font></div>";

    
    # Description Change Box
    print "<div id=\"descdialog\" title=\"Change the Description on a Switchport\" style=\"display: none;\"><font size=\"3\">\n";
    print '<div class="loading" id=\"loadingdesc\" style="position:relative; margin:20px; left:0px; top:0px; height:0px; width:0px">
           <img src="/depends/loading.gif" border=0></div>';
    print "<div id=\"desctext\"></div>\n";

    print "<div id=\"descform\"><form name=\"descchangeform\" id=\"descform\" method=\"POST\" action=\"\">";

    print "<br><label><span>Description </span><input name\=\"desc\" id=\"descid\" type\=\"text\" class=\"input-text\" size\=\"40\"
               tabindex=\"5\" type=\"submit\"></label>";
    print " <br><br><button tabindex=\"2\" id=\"descsubmit\" type=\"submit\">Change Description</button>";
    print '<input type="hidden" name="descchange" value="1">';
    print '<input type="hidden" id="descswitchport" name="descswitchport" value="1">';

    print "</form>";
    print"</div></font></div>";


    # Shut/NoShut Box
    print "<div id=\"shutdialog\" title=\"Change the Status of a Switchport\" style=\"display: none;\"><font size=\"3\">\n";
    print '<div class="loading" id=\"loadingshut\" style="position:relative; margin:20px; left:0px; top:0px; height:0px; width:0px">
           <img src="/depends/loading.gif" border=0></div>';
    print "<div id=\"shuttext\"></div>\n";

    print "<div id=\"shutform\"><form name=\"shutchangeform\" id=\"descform\" method=\"POST\" action=\"\">";

#    print "<br><label><span>Description </span><input name\=\"shut\" id=\"shutid\" type\=\"text\" class=\"input-text\" size\=\"40\"
#               tabindex=\"5\" type=\"submit\"></label>";

    # Start Select Box
    print '<br><br><label><span><b>Action Type</b></span>
                   <select size="1" tabindex="7" name="shut" id="shutid">
                  ';
    
    # Always Print Default Role First
    print '<option value="shutnoshut" selected>Shut/No Shut</option>';
    print '<option value="shut">Shutdown</option>';
    print '<option value="noshut">No Shutdown</option>';
    
    print '</select></label>';

    print " <br><br><button tabindex=\"2\" id=\"shutsubmit\" type=\"submit\">Change Status</button>";
    print '<input type="hidden" name="shutchange" value="1">';
    print '<input type="hidden" id="shutswitchport" name="shutswitchport" value="1">';

    print "</form>";
    print"</div></font></div>";
    
    # Statseeker Graphs
    print "<div id=\"statdialog\" title=\"Statseeker Graphs\" style=\"display: none;\"><font size=\"3\">\n";
    print "<div id=\"stattext\"></div>\n";
    print "</font></div>";

    # Interface Statistics
    print "<div id=\"intdialog\" title=\"Interface Statistics\" style=\"display: none;\"><font size=\"3\">\n";
    print "<pre id=\"inttext\"></pre>\n";
    print "</font></div>";

    
    # Find Free vs Unfree Ports statistics
    if ( $ptext_length > 1 ) {
	my $totalCount;

        foreach my $netdb_ref (@ptext) {
            my %netdb_entry = %$netdb_ref;

	    # Avoid counting the same port more than once
	    if ( !$portstatus{"$netdb_entry{switch}$netdb_entry{port}"} ) {

		$portstatus{"$netdb_entry{switch}$netdb_entry{port}"} = 1;
		$totalCount++;

		# If there is a mac on the port, it's an access layer device
		if ( $netdb_entry{"mac"} ) {
		    $portstatus{"inuse"}++;
		}
		elsif ( $netdb_entry{"vlan"} ne 'trunk' ) {
		    $portstatus{"notinuse"}++;
		    $freeports{"$netdb_entry{switch}"}++;
		}
		elsif ( $netdb_entry{"vlan"} eq 'trunk' ) {
		    $portstatus{"trunk"}++;
		}
		else {
		    $portstatus{"unknown"}++;  
		}
	    }
	    
        }
	if ( $portstatus{notinuse} || $portstatus{trunk} ) {
	    $resultcountPrint = "\($totalCount\)";	
	    $resultcountPrint = "\( Total Ports:$totalCount / Active:$portstatus{inuse} / Inactive:$portstatus{notinuse} / Trunks:$portstatus{trunk} \)";
	}
	else {
            $resultcountPrint = "\($totalCount\)";
	}
    }

    # Check for whether data is standard switchport data or wifi data

    if ( $ptext[0]{type} eq "wifi" || $ptext[0]{wifi} ) {
	$wifi = 1;
    }

    # Check for Wifi Authentication Before Returning Wifi Data
    if ( $wifi && !$wifiauth ) {
	push ( @ntable, "<h2>Not Authorized for Wifi data, please request access to wifidata reports</h2>" );	
	return;
    }


    # If there is data, print the table
    if ( $ptext_length > 0 ) {

        push ( @ntable, '<div class="netdb">');

	# Only Enable sorting on table if it has more than one item
	if ( $ptext_length > 1 ) {
	    push( @ntable, '<table id="netdbswitch">');
	}
	else {
	    push( @ntable, '<table>');
	}

        # Table Header depends on report type
	if ( $unusedPortsReport ) {
	    
	    #	    foreach my $key ( keys %freeports ) {
	    #		print "<br>$key: $freeports{$key}\n";
	    #	    }

	    push ( @ntable, "<caption><h2>$portstatus{notinuse} Unused Ports in $searchDays days</h2></caption>" );
	}
	elsif ( $wifi ) {
	    push ( @ntable, "<caption><h2>Access Point History $resultcountPrint</h2></caption>" );
	} 
	else {
	    push ( @ntable, "<caption><h2>Switchport History $resultcountPrint</h2></caption>" );
	}


	## Switchport Table Column Definition
        push ( @ntable, '
        <thead>
        <tr>
');
	# If wifi ports, display Controller and AP versus switch and port
	if ( $wifi ) {
	    push ( @ntable, '
            <th>Controller</th>
            <th>Access Point</th>
            <th>Speed</th>
            <th>SSID</th>
');
	}
	# Standard switch and port
	else {
	    push ( @ntable, '
            <th>Switch</th>
            <th>Port</th>
            <th>Status</th>
            <th>VLAN</th>
');
	}

        push ( @ntable, '
        <th>Desc</th>
        <th>ND</th>
' );

	# Unused ports report displays differently
	if ( $unusedPortsReport ) {
            push( @ntable, '<th>Last Up</th><th>Free Ports</th>
      </tr>
      </thead>
      <tbody>
      ');
	
	}

	# Normal Switchport Report
	else {
            push( @ntable, '<th>MAC</th>');
	
	push ( @ntable, '
        <th>Last IP</th>
        <th>Hostname</th>
' );
	
	    if ( $useNAC ) {
            push ( @ntable, '<th>User</th>');
        }


	push ( @ntable, '
        <th>DHCP</th>
        <th>Firstseen</th>
        <th>Lastseen</th>
      </tr>
      </thead>
      <tbody>
' );
	} # End Table Header


	# Print Results
	for (my $i=0; $i < $ptext_length; $i++)
	{
            # Change 0's and 1's to yes and no for statics
            if ( $ptext[$i]{static} == 1 ) {
                $ptext[$i]{static} = "<b>static</b>";
            }
            else {
                $ptext[$i]{static} = "dynamic";
            }

	    ## Truncate Description unless it's a special EEG circuit (site specific)
	    if ( $ptext[$i]{description} !~ /Video EEG/ ) {

		# Save description for tooltip
                $ptext[$i]{extdesc} = $ptext[$i]{description};

		# Truncate description unless it's a video eeg ports (site specific)
		$ptext[$i]{description} = substr( $ptext[$i]{description}, 0, $desc_length );
	    }
	    # EEG Port, color red
	    else {
                $ptext[$i]{description} = '<font color="red"><b>Video EEG</b></font>';
	    }

	    # Fix Status Messages Up
	    $ptext[$i]{status} = "Up" if $ptext[$i]{status} eq "connected";
	    $ptext[$i]{status} = "Down" if $ptext[$i]{status} eq "notconnect";
            $ptext[$i]{status} = "<b>Shut</b>" if $ptext[$i]{status} eq "disabled";
            $ptext[$i]{status} = '<font color="red"><b>ERR-D</b></font>' if $ptext[$i]{status} eq "err-disabled";
            $ptext[$i]{status} = '<font color="red"><b>FAULT</b></font>' if $ptext[$i]{status} eq "faulty";
            $ptext[$i]{status} = "<b>monitor</b>" if $ptext[$i]{status} eq "monitor";


	    ############
	    # Table Data
	    ############

	    ## Switch
            push ( @ntable, "<tr><td><a href=\"$scriptLocation?address=$ptext[$i]{switch}&days=$searchDays$getOptions&switchreport=1\#content\">
                                  $ptext[$i]{switch}</a></td>" );

            push ( @ntable, "<td>" );

	    ## Port
	    push ( @ntable, "<a href=\"$scriptLocation?address=$ptext[$i]{switch},$ptext[$i]{port}&days=$searchDays$getOptions&switchreport=1\#content\" " . 
		   "title=\"" );

	    # Wifi speed different from speed/duplex
	    if ( $wifi && $ptext[$i]{speed} ) {
		push( @ntable, "AP Speed: $ptext[$i]{speed}<br>" );
		push( @ntable, "Client Speed: $ptext[$i]{status}<br><br>" );
	    }
	    elsif ( $ptext[$i]{speed} ) {
		push( @ntable, "Speed/Duplex: $ptext[$i]{speed}/$ptext[$i]{duplex}<br><br>" ); 
	    }
	    push( @ntable, "Last Up: $ptext[$i]{lastup}<br>" ) if $ptext[$i]{lastup};
	 
	    # Uptime tooltip if available
	    if ( $ptext[$i]{p_uptime} && $ptext[$i]{p_uptime} ne '0.0sec' ) {
		push( @ntable, "Port Uptime: $ptext[$i]{p_uptime}<br>" )
	    }
	    # If device uptime minutes exist add to description
	    if ( $ptext[$i]{uptime} ) {
		push( @ntable, "MAC Uptime: $ptext[$i]{uptime} on this port<br>" );
	    }
	    push( @ntable, "\" class=\"tooltip\">$ptext[$i]{port}</a>" );

	    
            # Interface Statistics based on Inventory
            if ( $useInventory ) {
                my $invfile = $ptext[$i]{port};
                $invfile =~ s/\//\-/g; # Change / to - for files
                $invfile = "/interfaces/$ptext[$i]{switch}/$invfile.txt";

                push ( @ntable, " <a href=\"#interface-$invfile\" class=\"interface\">" );
                push ( @ntable, " <img src=\"/depends/stats_icon.gif\"> </a>" );
            }

	    # Airwave link
	    if ( $wifi && $wifi_http ) {
		my $wifimac = $ptext[$i]{mac};
		$wifimac = uc( $wifimac );
		push ( @ntable, " <a href=\"$wifi_http$wifimac\" >" );
		push ( @ntable, " <img src=\"/depends/line_graph-g.png\" target=\"_blank\"> </a>" );		
	    }

	    # Statseeker Graphs
            elsif ( $statseeker ) {
		my $statport = $ptext[$i]{port};
		
		# Nexus fix, change Eth to Ethernet
		if ( $statport =~ /^Eth\d+/ ) {
		    $statport =~ s/^Eth/Ethernet/;
		}
		if ( $statport =~ /^Po\d+/ ) {
                    $statport =~ s/^Po/port-channel/;
                }

                push ( @ntable, " <a href=\"#statseeker-$ptext[$i]{switch},$statport\" class=\"statseeker\">" );
                       push ( @ntable, " <img src=\"/depends/line_graph-g.png\"> </a>" );
            }

            push ( @ntable, "</td>\n" );
            ## END Port

	    ## Check for VLAN Authorization for vlan change and port status control
	    my $authorized_vlan = checkVlanAuth( $ptext[$i]{switch} );


	    ## Status
	    push ( @ntable, "<td>" );
	    
	    # Allow status changes if allowed to change vlan
	    if ( ( $vcauth || $authorized_vlan ) && $ptext[$i]{vlan} =~ /\d+/ ) {
		push ( @ntable, " <a href=\"#shutchange-$ptext[$i]{switch},$ptext[$i]{port}\" class=\"shutchange\">" );
		push ( @ntable, "<img src=\"/depends/power_off.png\" border=\"0\"></a>" );
	    }

	    ## End Status
	    push ( @ntable, "$ptext[$i]{status}</td>" );


	    # VLAN
            push ( @ntable, "<td>" );

            # Vlan Change
            
            if ( ( $vcauth || $authorized_vlan ) && $ptext[$i]{vlan} =~ /\d+/ && $ptext[$i]{vlan} !~ /\(t/) {
                push ( @ntable, " <a href=\"#vlanchange-$ptext[$i]{switch},$ptext[$i]{port}\" class=\"vlanchange\">" );
                       push ( @ntable, "<img src=\"/depends/change.png\" border=\"0\"></a>" );
            }

	    # Special vlan flag from database (*), remove and add tooltip
	    my $vflag;
	    if ( $ptext[$i]{vlan} =~ /\(\*\)/ ) {
		$ptext[$i]{vlan} =~ s/\(\*\)//;
		$vflag = 1;
	    }

	    ## VLAN with dot1q tooltip
	    push ( @ntable, "<a " );
            push ( @ntable, "class=\"tooltip\" title=\"Discrepency between the switchport's untagged <br>vlan and this mac address's vlan ID\" " ) if $vflag;
	    push ( @ntable, "href=\"$scriptLocation?address=$ptext[$i]{vlan}&vlan=1&days=$searchDays$getOptions\#content\">$ptext[$i]{vlan}" );
	    push ( @ntable, " (*/1q)" ) if $vflag;
	    push ( @ntable, "</a></td>" );
            
	    
	    # Description
	    push ( @ntable, "<td>" );

            # Ability to change descriptions
            if ( $descauth ) {
                push ( @ntable, " <a href=\"#descchange-$ptext[$i]{switch},$ptext[$i]{port}\" class=\"descchange\">" );
                push ( @ntable, "<img src=\"/depends/pencil_icon2.png\" border=\"0\"></a>" );
            }

            push ( @ntable, "<span class=\"tooltip\" title=\"$ptext[$i]{extdesc}\">$ptext[$i]{description}</span>" );
	    push ( @ntable, "</td>\n" );


	    # BRANCH Unused Ports versus normal Switchport report
	    if ( $unusedPortsReport ) {
		push ( @ntable, "<td></td><td>$ptext[$i]{lastup}</td>" );
		push ( @ntable, "<td>$freeports{$ptext[$i]{switch}}</td></tr>" );
	    }
	    
	    else {

		# Neighbor
		my ( $shortname ) = split( /\./, $ptext[$i]{n_host} );
		$ptext[$i]{n_desc} =~ s/0x2C/\,/g;
		my $hostlink = "<a href=\"$scriptLocation?address=$shortname&days=$searchDays$getOptions&switchreport=1\#content\"                
                                title=\"<b>IP:</b> $ptext[$i]{n_ip}<br><b>Host:</b> $ptext[$i]{n_host}<br>
                                <b>Model:</b> $ptext[$i]{n_model}<br><b>Remote Port:</b> $ptext[$i]{n_port}
                                <br><b>Lastseen:</b> $ptext[$i]{n_lastseen}<br><br><b>Description:</b> $ptext[$i]{n_desc}<br> \"
                                     class=\"tooltip\">$shortname</a>";
		push ( @ntable, "<td>$hostlink</td>" );
		
		# MAC
		push ( @ntable, "<td><a href=\"$scriptLocation?address=$ptext[$i]{mac}&days=$searchDays$getOptions\#content\"
                                  title=\"Vendor: $ptext[$i]{vendor} ");

		# Add mac uptime to tooltip as well
		if ( $ptext[$i]{uptime} ) {
		    push( @ntable, "<br>Uptime: $ptext[$i]{uptime} on this port<br>" );
		}
		push ( @ntable, "\" class=\"tooltip\">$ptext[$i]{mac}</a></td>" );
	    
		# IP
		push ( @ntable, "<td><a href=\"$scriptLocation?address=$ptext[$i]{ip}&days=$searchDays$getOptions\#content\" " );
		push ( @ntable, "title=\"Router: $ptext[$i]{router}" );
		push ( @ntable, "<br>VRF: $ptext[$i]{vrf}" ) if $ptext[$i]{vrf};
		push ( @ntable, "<br>Warning: Relying on last known IP address from mac table, missing switch IP" ) if !$ptext[$i]{s_ip};
		push ( @ntable, "\" class=\"tooltip\">" );

		# Populate switch IP if available s_ip, otherwise populate last_ip
		$ptext[$i]{switch_ip} = $ptext[$i]{ip};
		$ptext[$i]{switch_ip} = $ptext[$i]{s_ip} if $ptext[$i]{s_ip};
		
		push ( @ntable, "$ptext[$i]{switch_ip}</a>" );
                push ( @ntable, " (!!)" ) if ( !$ptext[$i]{s_ip} && $ptext[$i]{ip} );
		push ( @ntable, " [$ptext[$i]{vrf}]" ) if $ptext[$i]{vrf};
		push ( @ntable, "</td>\n" );
		
		# Hostname, use s_name if available
		$ptext[$i]{name} = $ptext[$i]{s_name} if $ptext[$i]{s_name};
		push ( @ntable, "<td><a href=\"$scriptLocation?address=$ptext[$i]{name}&days=$searchDays$getOptions\#content\">$ptext[$i]{name}</a></td>" );

		
		# UserID
		push ( @ntable, "<td><a href=\"$scriptLocation?address=$ptext[$i]{userID}&user=1&days=$searchDays$getOptions\#content\"
                                  title=\"$ptext[$i]{firstName} $ptext[$i]{lastName}\" class=\"tooltip\">$ptext[$i]{userID}</a>\n" ) if $useNAC;
		push ( @ntable, "<td>$ptext[$i]{static}</td>" );
		push ( @ntable, "<td>$ptext[$i]{firstseen}</td>" );
		push ( @ntable, "<td>$ptext[$i]{lastseen}</td></tr>\n" );
		
		push ( @netdbText, "<h1>Switchport: $ptext[$i]{switch} $ptext[$i]{port}</h1>\n<hr/>\n" );
		
		if ( $ptext[$i]{mac} ) {
		    push ( @netdbText, "<label><span>IP Address: </span><a href=\"$scriptLocation?address=$ptext[$i]{ip}&days=$searchDays$getOptions\#content\">
                                    $ptext[$i]{ip}</a></label>\n" );
		    push ( @netdbText, "<label><span>MAC Address: </span><a href=\"$scriptLocation?address=$ptext[$i]{mac}&days=$searchDays$getOptions\#content\">
                                    $ptext[$i]{mac}</a></label>\n" );
		    push ( @netdbText, "<label><span>Hostname: </span><a href=\"$scriptLocation?address=$ptext[$i]{name}&days=$searchDays$getOptions\#content\">
                                    $ptext[$i]{name}</a></label>\n" );
		}
		push ( @netdbText, "<label><span>VLAN: </span><a href=\"$scriptLocation?address=$ptext[$i]{vlan}&vlan=1&days=$searchDays$getOptions\#content\">
                                $ptext[$i]{vlan}</a></label>\n" );
		push ( @netdbText, "<label><span>Switch: </span><a href=\"$scriptLocation?address=$ptext[$i]{switch}&days=$searchDays$getOptions&switchreport=1\#content\">
                                $ptext[$i]{switch}</a></label>\n" );
		push ( @netdbText, "<label><span>Port: </span><a href=\"$scriptLocation?address=$ptext[$i]{switch},$ptext[$i]{port}&days=$searchDays$getOptions&switchreport=1\#content\">
                                $ptext[$i]{port}</a></label>\n" );
		push ( @netdbText, "<label><span>Port Status: </span>$ptext[$i]{status}</label>\n" );
		
		if ( $ptext[$i]{mac} ) {
		    push ( @netdbText, "<label><span>First Seen: </span>$ptext[$i]{firstseen}</label>\n" );
		    push ( @netdbText, "<label><span>Last Seen: </span>$ptext[$i]{lastseen}</label>\n" );
		}
		push ( @netdbText, "<br>\n" );
		
	    } 
	}
	# Close out table for both switch report and unused ports
	push ( @ntable, "</tbody></table></div>\n" );
	
#        push ( @ntable, "<br>\n" );	
    }
}


sub printNetdbNACReg {
    my $ptext_ref = shift;
    my $resultcountPrint = undef;
    my $vcauth;

    # Check for VLAN Change Authority for complete NAC role access
    if ( $userAuthLevel >= $reportAuthLevel{"vlan_change"} && $reportAuthLevel{"vlan_change"} ) {
        $vcauth = 1;
    }

    # Put the mac address in to the desired format
    $ptext_ref = convertMacFormat( $ptext_ref, $mac_format );

    # Dereference array of hashrefs
    my @ptext = @$ptext_ref;

    my $ptext_length = @ptext;
    
    # If there is returned data, print the table
    if ( $ptext_length > 0 ) {

	# Role based access dialog box
	if ( $role_file ) {
	    my $role_ref = getRoles();
	    my %devrole = %$role_ref;


	    # Create Role Change Dialog Box
	    print "<div id=\"roledialog\" title=\"Change the Role on a Device\" style=\"display: none;\"><font size=\"3\">\n";
	    print '<div class="loading" id=\"loadingrole\" style="position:relative; margin:20px; left:0px; top:0px; height:0px; width:0px">
           <img src="/depends/loading.gif" border=0></div>';
	    print "<div id=\"roletext\"></div>\n";
	    
	    print "<div id=\"roleform\"><form name=\"roleform\" method=\"POST\" action=\"\">";
	    
	    # Start Select Box
	    print '<br><br><label><span><b>Role Type</b></span>
                   <select size="1" tabindex="7" name="roletype" id="roletype">
                  ';  
	    
	    # Always Print Default Role First
	    print '<option value="default-role" selected>Default NAC VLAN</option>';

	    # Iterate all Roles
            foreach my $key ( keys %devrole ) {
                #print "  $key => $devrole{$key}\n";
		if ( $key !~ /default/ ) {
		    #print "<input name\=\"roletype\" id=\"$key-role\" type\=\"radio\" value=\"$key-role\"  size\=\"10\">$devrole{$key}</input><br>";
		    print  "<option value=\"$key-role\">$devrole{$key}</option>";
		}
            }
	    print '</select></label>';

	    print "<br><br><button tabindex=\"2\" id=\"rolesubmit\" type=\"submit\"><b>Change Role</b></button>";
	    print '<input type="hidden" name="rolechange" value="1">';
	    
	    print "</form>";
	    print"</div></font></div>";
	}
	
	# Print Roles JS
	getRoles( 1 );


        push ( @ntable, '<div class="netdb">');

        # Only Enable sorting on table if it has more than one item
        if ( $ptext_length > 1 ) {
            push( @ntable, '<table id="netdbipmac">');
        }
        else {
            push( @ntable, '<table>');
        }

        # Table Caption
        push ( @ntable, "<caption><h2>Registration Data $resultcountPrint</h2></caption>" );

        push ( @ntable, '
      <thead>
       <tr>
        <th>Username</th>
        <th>First Name</th>
        <th>Last Name</th>
        <th>Email</th>
        <th>Title</th>
        <th>Device Type</th>
        <th>Role</th>
       </tr>
      </thead>
      <tbody>
');
	# Go through hashref array and print table
        for (my $i=0; $i < $ptext_length; $i++)
        {
            # Change 0's and 1's to yes and no for statics
            if ( $ptext[$i]{critical} eq '1' ) {
                $ptext[$i]{critical} = '<b><font color="#CC0000">Critical</font></b>';
            }
            else {
                $ptext[$i]{critical} = "normal";
            }
	    
	    push ( @ntable, "<tr><td><a href=\"$scriptLocation?address=$ptext[$i]{userID}&user=1&days=$searchDays$getOptions\#content\">$ptext[$i]{userID}</a></td>\n" );
            push ( @ntable, "<td>$ptext[$i]{firstName}</td>\n" );
            push ( @ntable, "<td>$ptext[$i]{lastName}</td>\n" );
            push ( @ntable, "<td><a href=\"mailto:$ptext[$i]{email}\">$ptext[$i]{email}</a></td>\n" );
            push ( @ntable, "<td>$ptext[$i]{title}</td>\n" );
            push ( @ntable, "<td>$ptext[$i]{type}</td>\n" );
            push ( @ntable, "<td>$ptext[$i]{role}\n" );

	    # Allow role change if authorized for VLAN changes or if allowed via nac_group
	    if ( $nacAuth{$ptext[$i]{userID}} || $vcauth ) {
                push ( @ntable, " <a href=\"#rolechange-$ptext[$i]{mac}\" class=\"rolechange\">" );
		push ( @ntable, "<img src=\"/depends/change.png\" border=\"0\"></a>" );
            }

	    push ( @ntable, "</td></tr>\n" );
	}
        push ( @ntable, "</tbody></table></div>\n" );
    }
}

# Get a list of NAC roles from Role File
sub getRoles {

    my $printJS = shift;
    
    my $config = AppConfig->new({
                                 CREATE => 1,
                                });
    
    $config->define( "role=s%" );

    $config->file( "$role_file" );

    $scriptName    = $config->scriptName();

    my $devrole_ref = $config->role();
    my %devrole = %$devrole_ref;

    # Only print JS if requested
    if ( !$printJS ) {
	return \%devrole;
    }
    else {

    # Role submit JS code.  Need to pull the device roles to build the form correctly.
    print '<script type="text/javascript">' . "\n";
    print <<ROLEJS1;

    // IE Fix to catch click for ajax submit (if it fails, does a normal post action)
 \$("\#rolesubmit").click(function() {
    \$("\#roleform").submit();
    return false;
 });

 // IE Fix for pressing enter to submit form in roleid box
 \$("\#roleid").bind("keydown", function (e) {
    var key = e.keyCode || e.which;
    if (key === 13 && \$.browser.msie ) { \$("\#roleform").submit(); }
 });


 //role Change AJAX Submit
 \$("\#roleform").submit(function() {

     // Build ajax submit string
     var myLoc = document.location.toString();

     // Get the mac
     myLoc = myLoc.split("\#rolechange-")[1];
//myLoc = myLoc.replace(/\#rolechange-/i, "");  
 

     // Get the role value
     var myrole = \$("\#roletype").val();
     \$(".loading").css('visibility', 'visible');

     var dataString = "skiptemplate=1&rolechange=1&role=" + myrole + "&rolemac=" + myLoc;
     //alert(myrole);
     //return false;

     \$("\#roleform").hide();     
     \$("\#roletext").html("<br><br><br>Changing role, wait for verification (Press esc to close)<br>");
     \$("\#loadingrole\").show();
     // Ajax onclick to call camtrace with skiptemplate, then print results to ajaxresults div
     \$.ajax({
    type: "POST",
    url: "$scriptLocation",
    data: dataString,
    success: function( data ) {

                  // Print results after camtrace.pl returns
                  \$("\#roletext").html(data);
                  \$(".loading").css('visibility', 'hidden'); //Hide all loading images
      }
     });

   //\$(".loading").css('visibility', 'hidden'); //Hide all loading images

   return false;
 });

ROLEJS1
    print '</script>';    

    return \%devrole;
    }

}

# Wake on Lan Button
sub printWakeOnLan {
    my $wakemac = shift;
    my $wakeip = shift;
    my $debugmode;

    if ( $DEBUG ) {
	$debugmode = "&debug=1";
    }

    $wakeLoc = "<a href=\"$scriptLocation?address=$wakemac&wakeip=$wakeip&wake=1&skiptemplate=1$debugmode\"><span>Wake on LAN</span></a>";
}

# Outputs an about page with help information etc
sub printAboutNetDB {
    my $line;
    my $inline = shift;

    open( my $ABOUT, '<', "$aboutFile" ) or print "<br>WARNING: Can't open $aboutFile";

    print '<!-- printAboutNetDB -->' . "\n";

    print "<hr/>\n" if !$inline;

    print "<div class=\"smallfont\">\n";
    
    while ( $line = <$ABOUT> ) {
	print "$line";
    }

    print "</div>\n";
}

# NetDB statistics, relies on update-statistics.sh
sub printNetDBStats {
    
    my $line;
    my @stats;
    
    # Statistics for front page
    #print "<div class=\"smallfont\">\n";
    
    open( my $MONTHLYSTATS, '<', "$netdbMonthlyStats" ) or print "<br>Error: Can't open $netdbMonthlyStats";
    open( my $DAILYSTATS, '<', "$netdbDailyStats" ) or print "<br>Error: Can't open $netdbDailyStats";
    open( my $TOTALSTATS, '<', "$netdbTotalStats" ) or print "<br>Error: Can't open $netdbTotalStats";
    
    print "<hr/><br>\n";
    print "<div class=\"box\">\n";
    print "<div class=\"netdb\">\n";
    print "<h1>NetDB Statistics</h1><hr/>\n";
    print '<font size="4"><a href="/mrtg/">Network Graphs</a></font><br><br>';
    
    print "<h3>Statistics from the last 24 hours:</h3>\n";
    print '<table class="netdb" style="width:45%">';

    while ( $line = <$DAILYSTATS> ) {
        if ( $line =~ /\:\s+/ ) {
            @stats = split( /\:\s+/, $line );
            $stats[0] = "Transactions" if $stats[0] =~ /Transactions/;
            $stats[0] = "DB Rows" if $stats[0] =~ /Total\sRows/;
            print "<tr><td>$stats[0]</td><td>$stats[1]</td></tr>\n";
        }
    }
    print "</table>\n";

    print "<br><h3>Statistics from the last 30 days:</h3>\n";
    print '<table class="netdb" style="width:45%">';

    while ( $line = <$MONTHLYSTATS> ) {
        if ( $line =~ /\:\s+/ ) {
            @stats = split( /\:\s+/, $line );
            $stats[0] = "Transactions" if $stats[0] =~ /Transactions/;
            $stats[0] = "DB Rows" if $stats[0] =~ /Total\sRows/;
            print "<tr><td>$stats[0]</td><td>$stats[1]</td></tr>\n";
        }
    }
    print "</table>\n";

    print "<br><h3>All Time Statistics:</h3>\n";
    print '<table class="netdb" style="width:45%">';

    while ( $line = <$TOTALSTATS> ) {
	if ( $line =~ /\:\s+/ ) {
            @stats = split( /\:\s+/, $line );
            $stats[0] = "Transactions" if $stats[0] =~ /Transactions/;
	    $stats[0] = "DB Rows" if $stats[0] =~ /Total\sRows/;
            print "<tr><td>$stats[0]</td><td>$stats[1]</td></tr>\n";
	}
    }
    print "</table>\n";
    print "</div></div>\n";
}

###############################
# Change the role on a device #
###############################
sub changeRole {
    my $mac  = parseInputVar( "rolemac" );
    my $role = parseInputVar( "role" );
    my $dirty_user = $envuser;
    my $role_auth = undef;
    my $username;
    #$DEBUG = 1;

    my @output;
    my $verbose;

    # Cleanup role input
    $role =~ s/\-role$//;

    my $role_ref = getRoles();
    my $full_role = "$$role_ref{$role}";
    my $role_cmd = "$role_script -m $mac -dr $role";
    
    # Detaint username
    $dirty_user =~ s/(\*|\%)//g;
    ( $username ) = $dirty_user =~ m/^([A-Z0-9_.\-\:\s\,\/]+)$/ig;
    $username = lc( $username );


    if ( !$role || $role eq "undefined" ) {
	print "Error: Please Select a Role";
	return;
    }

    if ( $userAuthLevel >= $reportAuthLevel{"role_change"} && $reportAuthLevel{"role_change"}) {
	print "<br>Authorized for Change: $username $mac $role" if $DEBUG;
	$role_auth = 1;
    }
    else {
	print "<br>Not Authorized for Role Change: $username $mac $role";
	return;
    }

    # Authorized to make change and command exists
    if ( $role_auth && $role_cmd ) {
	
	# Record Transaction
	#$dbh = connectDBrw( $config_file );
	$transactionID = recordTransaction( $mac, $role );
	
	print "<br>Running Command: $role_cmd\n" if $DEBUG;
	
	@output = `$role_cmd`;
	my $success;
	
	print "<br>Debug Results: @output" if $DEBUG;
	
	foreach my $line ( @output ) {
	    if ( $line =~ /Success/ ) {

		print "Successfully Changed Role to $full_role:<br>\n";

		$line =~ s/www\-data/$username/;
		print "<br>$line";
		$success = 1;
	    }
	}
	if ( !$success ) {
	    print "<br>ERROR, Role Command Failed: ";
	    print "$role_cmd\n<br><br>Results:";
	    foreach my $line ( @output ) {
		print "<br>$line";
	    }
	}
	
	# Update Role in Database
	else {
	    
	    print "<br>Changing Role in Database to: $full_role\n" if $DEBUG;

	    my $dbh = connectDBrw( $config_file );
	    updateNACRole( $dbh, $mac, $full_role );
	}
    }

}


#########################################################
# Disable a MAC Address, AJAX Form
#########################################################
sub disableClient {
    my $mac = parseInputVar( "disablemac" );
    my $blocktype = parseInputVar( "blocktype" );
    my $caseid = parseInputVarLoose( "caseid" );
    my $stage = parseInputVar( "stage" );
    my $elogtextTainted = $FORM{"elogtext"};
    my $elogtext = $elogtextTainted;
    my $enablenote = parseInputVarLoose( "note" );
    my $severe = parseInputVar( "severe" );
    my $noelog = parseInputVar( "noelog" );
    my $dirty_user = $envuser;
    my $username;
    my $success;
    my $disauth;
    my $enauth;
    my @output;
    my $verbose;
    #$DEBUG =1;

    my $dbh;

    print "<br>DEBUG: disable client $mac type $blocktype caseid $caseid\n" if $DEBUG;

#    print "enable: $enablenote";

    $verbose = "-v" if $DEBUG;

    $severe = undef if $severe eq "undefined";
    $noelog = undef if $noelog eq "undefined";


    # Detaint username
    $dirty_user =~ s/(\*|\%)//g;
    ( $username ) = $dirty_user =~ m/^([A-Z0-9_.\-\:\s\,\/]+)$/ig;
    $username = lc( $username );

    #print "<br>Checking Authorization for $envuser for disable_client" if $DEBUG;

    if ( $mac ) {

	# Check to see if script variable is defined
	if ( !$mnc_shut ) {
	    print "<br>Configuration Error: mcn_shut is undefined in $config_cgi<br>";
	}
	
		# Get Disable Authorization
	if ( $userAuthLevel >= $reportAuthLevel{"disable_client"} && $reportAuthLevel{"disable_client"} ) {
	    $disauth = 1;
	    print "<br>Debug: User Authorized to Disable Clients\n" if $DEBUG;
	} 
	if ( $userAuthLevel >= $reportAuthLevel{"enable_client"} && $reportAuthLevel{"enable_client"} ) {
	    $enauth = 1;
	    print "<br>Debug: User Authorized to Enable Clients\n" if $DEBUG;
	}

	if ( !$enauth ) {
	    print "<br>Error: Not Authorized";
	}


	# Check user authorization based on per switch setting or access level in the config file
	elsif ( $enauth ) {
	    
	    # Get DB connection
	    $dbh = connectDBrw( $config_file );
	    
	    print "<a href=\"#disable\" class=\"distest\">distest</a>" if $DEBUG;
	    
	    
	    # Print block form
	    if ( $stage eq "1" && $disauth ) {
		

		# Create Firewall Block Form
		if ( $blocktype eq "shutdown" ) {
		    print "<h2>Port Shutdown for $mac</h2>";
		}
		elsif ( $blocktype eq "nonetnac" ) {
		    print "<h2>Block Internet Access via Bradford</h2>";
		}
                elsif ( $blocktype eq "portshutdown" ) {
                    print "<h2>Physically Shutdown Switchport</h2>";
                }
		elsif ( !$blocktype || $blocktype eq "unknown" ) {
		    print "<b>Error: You must select a block type</b>";
		    exit;
		}
		else {
		    print "Error: Unknown blocktype: $blocktype";
		    exit;
		}

		print "<br><div id=\"disable2form\"><form name=\"firewallform\" method=\"POST\" action=\"\">";
		
		print "<label><span><b>Case ID</b></span>";
		print "<input name\=\"caseid\" id=\"caseid\" type\=\"text\" class=\"input-text\" size\=\"30\"
                          tabindex=\"20\"></input></label>\n";
		print "<br><input id=\"severe\" type=\"checkbox\" />Severe Shutdown (restrict re-enable rights)";
		print "<br><input id=\"noelog\" type=\"checkbox\" />Suppress ELOG";
		print "<br><br><label><span><b>ELOG Contents</b></span></label>";
		print "<br><textarea name=\"elogtext\" id=\"elogtext\" cols=\"50\" rows=\"12\" tabindex=\"21\" />";
		print "<br><br> <button tabindex=\"2\" id=\"disablesubmit\" type=\"submit\">Disable Client</button>";
		
		print "<input type=\"hidden\" name=\"disablemac\" value=\"$mac\">";
		
		print "</form>";
		print"</div></font>";
		
	    }
	    
	    # Received Block form contents, block client
	    elsif ( $stage eq "2" && $disauth ) {
		
		my $cmd;

		# Record Transaction
		$transactionID = recordTransaction( $mac, $blocktype );
		
		if ( $blocktype eq "shutdown" ) {
		    $cmd = "$mnc_shut $mac -u $username"
		}
		elsif ( $blocktype eq "nonetnac" ) {
		    $cmd = "$mnc_block $mac -u $username"
		}
		
		# Set Options
		$cmd = "$cmd -case '$caseid'" if $caseid;
		$cmd = "$cmd -sev" if $severe;
		
		# Prepare elog text
		if ( !$noelog ) {
		    my $file = "/tmp/$username-elog.txt";
		    
		    open( my $ELOG, '>', $file) or die "Can't open $file";

		    # Strip elogtext= from serialized data
		    $elogtext =~ s/elogtext\=//i;

		    print $ELOG $elogtext;
		    close $ELOG;			
		    
		    $cmd = "$cmd -elog $file";
		}
		else {
		    $cmd = "$cmd -nolog";
		}
		
		# Firewall block
		if ( $blocktype eq "nonetnac" ) {
		    print "firewall cmd: $cmd" if $DEBUG;
		}
		
		# Port shutdown/filter
		elsif ( $blocktype eq "shutdown" ) {			
		    print "shutdown cmd: $cmd" if $DEBUG;
		}
		
		
		my @output;

		# Suppress command if $DEBUG
		@output = `$cmd` if !$DEBUG;
		my $success;
		
		
		# Check output for errors
		foreach my $line ( @output ) {
		    if ( $line =~ /^Shutdown Success/ ) {
			$success = 1;
			print "<b><br>$line</b>";
		    }
		    elsif ( $line =~ /^MNC Success: Changed Role/ ) {
			$line =~ s/^MNC Success: Changed Role/Successfully Changed Role /;
			$success = 1;
                        print "<b><br>$line</b>";
		    }
		    elsif ( $line =~ /Message successfully transmitted/ ) {
			print "<b><br>ELOG Generated: $line</b>";
		    }
		}
		
		if ( !$success ) {
		    foreach my $line ( @output ) {
			print "<br>$line\n";
		    }
		}
		
		print "<br>MAC: $mac<br>CASE: $caseid<br>TYPE: $blocktype<br>ELOG: $elogtext<br>noelog: $noelog<br>severe: $severe\n" if $DEBUG;
                print "$errmsg";		
	    }

	    # Stage 3 Re-Enable Block
	    elsif ( $stage eq "3" && $enauth ) {
		print "<br>Stage 3 $blocktype severe $severe\n" if $DEBUG; 

		# Check for severe shutdown authorization
		if ( $severe && !$disauth ) {
		    print "<b>Not Authorized: This device has been flagged as a critical security violation and 
                           only someone from security can re-enable it</b>\n";
		    exit;
		}

		# Make sure level 2 users give a reason
		if ( $enauth && !$disauth && !$enablenote ) {
		    print "<b>Input Error: Reason Required to Unblock: $errmsg</b>";
		    exit;
		}
		elsif ( $disauth && !$enablenote ) {
		    $enablenote = "authorized user";
		}


		my $transtype;
		$transtype = "unshut" if $blocktype eq "shutdown";
                $transtype = "nacdefault" if $blocktype eq "nonetnac";

		# Record Transaction
                $transactionID = recordTransaction( $mac, $transtype );

		my $cmd;
		
		if ( $blocktype eq "shutdown" ) {
		    $cmd = "$mnc_unshut $mac -u $username -note '$enablenote'"
		}
		elsif ( $blocktype eq "nonetnac" ) {
		    $cmd = "$mnc_noblock $mac -u $username"
		}
		else {
		    print "Error: Unknown block type ($blocktype)";
		    exit;
		}
		
		# Firewall block
		if ( $blocktype eq "nonetnac" ) {
		    print "firewall cmd: $cmd" if $DEBUG;
		}
		
		# Port shutdown/filter
		elsif ( $blocktype eq "shutdown" ) {			
		    print "shutdown cmd: $cmd" if $DEBUG;
		}
		
		
		# Run Command
		my @output = `$cmd`;
		my $success;
		
		
		# Check output for errors
		foreach my $line ( @output ) {
		    if ( $line =~ /^Shutdown Success/ ) {
			$success = 1;
			$line =~ s/^Shutdown\sSuccess/Successful/;
			print "<b><br>$line</b>";
		    }
                    elsif ( $line =~ /^MNC Success: Changed Role/ ) {
                        $line =~ s/^MNC Success: Changed Role/Successfully Changed Role /;
                        $success = 1;
                        print "<b><br>$line</b>";
                    }
		}
		
		if ( !$success ) {
		    foreach my $line ( @output ) {
			print "<br>$line\n";
		    }
		}
		
		print "<br>MAC: $mac<br>CASE: $caseid<br>TYPE: $blocktype<br>ELOG: $elogtext<br>noelog: $noelog<br>severe: $severe\n" if $DEBUG;
		
		# Stray errors
		print "$errmsg";
	    }

#	    $transactionID = recordTransaction( "$mac", "$blocktype" );

	}

	else {
	    print "User $envuser unauthorized to disable clients";
	}
    }
    else {
	print "Input Error: No MAC Submitted";
    }

    # Javascript for dialog box, ajax submit
    print '<script type="text/javascript">' . "\n";

    print <<SCRIPT;

\$(function() {


 \$(".distest").click(function() {
   alert("hello");
 });

 //AJAX Disable Submit
 \$("\#disable2form").submit(function() {

// alert(\$("\#elogtext\").serialize());

     // Build ajax submit string
     var myLoc = document.location.toString();

//       var myType  = \$("\#blocktype").val();
     var myElog = \$("\#elogtext\").serialize();
//     alert(myElog);
     var myCase = \$("\#caseid\").val();
     var noelog = \$("\#noelog:checked\").val();
     var severe = \$("\#severe:checked\").val();
     \$(".loading").css('visibility', 'visible');


     var dataString = "skiptemplate=1&stage=2&disableclient=1&disablemac=" + "$mac" + "&caseid=" + myCase + "&blocktype=$blocktype&severe=" + severe + "&noelog=" + noelog + "&elogtext=" + myElog;
// var dataString = "skiptemplate=1&disableclient=1&disablemac=$mac" + "&caseid=" + myCase;
//    alert(dataString);

     \$("\#disableform").hide();     
     \$("\#disabletext").html("<br><br><br>Attempting to Disable Port (Press esc to close)<br>");
     // Ajax onclick to call camtrace with skiptemplate, then print results to ajaxresults div
     \$.ajax({
    type: "POST",
    url: "$scriptLocation",
    data: dataString,
    success: function( data ) {

                  // Print results after camtrace.pl returns
                  \$("\#disabletext").html(data);
                  \$(".loading").css('visibility', 'hidden'); //Hide all loading images
      }
     });

   //\$(".loading").css('visibility', 'hidden'); //Hide all loading images

   return false;
 });


});

SCRIPT

print "</script>\n";

}

####################################
# Process Status Change AJAX style #
####################################
sub changeStatus {
    my $shut = parseInputVarLoose( "shut" );
    my $switchport = parseInputVar( "shutswitchport" );
    my ( $switch ) = split(/\,/, $switchport );
    my $dirty_user = $envuser;    
    my $username;
    my $success;
    my @output;
    my $verbose;
    my $shutauth;

    $shut = CGI::unescape( $shut );

    $verbose = "-v" if $DEBUG;

    #$DEBUG =1;
    
    # Detaint username
    $dirty_user =~ s/(\*|\%)//g;
    ( $username ) = $dirty_user =~ m/^([A-Z0-9_.\-\:\s\,\/]+)$/ig;
    $username = lc( $username );

    my $authorized_vlan = checkVlanAuth( $switch );

    if ( $authorized_vlan || ( $userAuthLevel >= $reportAuthLevel{"vlan_change"} && $reportAuthLevel{"vlan_change"} ) ) {
	$shutauth = 1;
        print "<br>Debug: User Authorized for Status Change: $shut ON $switchport\n" if $DEBUG;
    }
    else {
	print "<br>Error: User NOT Authorized for Status Change\n";
	return;
    }

    # Make sure script is defined
    if ( !$shut_script ) {
        print "<br>Error: shut_script undefined\n";
        return;
    }

    if ( $shutauth ) {
	my $transactionID = recordTransaction( "$switchport", "$shut" );
	
	print "<div class=\"loading\">Changing status on switchport: $switchport,$shut<br></div>\n";
	print "shut_change command: $shut_script $switchport,$shut $verbose" if $DEBUG;
	@output = `$shut_script $switchport,$shut $verbose`;


	my $success;
	# Print Results from script
	foreach my $line ( @output ) {
	    if ( $line =~ /(Camtrace success)|(Successfully)/ ) {
		$success = 1;

		# Update status in database
		#my $dbh = connectDBrw( $config_file );
		#my ( $switch, $port ) = split( /\,/, $switchport );
		#updateDescription( $dbh, $switch, $port, $desc );

		print $line;
	    }
	    elsif ( $success ) {
		print "<br>$line";
	    }
	}
	if ( !$success ) {
	    print "<br>Status Change Failed<br>\n";
	    foreach my $line ( @output ) {
		print "<br>$line\n";
	    }
	}
    }    
}



#########################################
# Process Description Change AJAX style #
#########################################
sub changeDesc {
    my $desc = parseInputVarLoose( "desc" );
    my $switchport = parseInputVar( "descswitchport" );
    my $dirty_user = $envuser;
    my $username;
    my $success;
    my @output;
    my $verbose;
    my $descauth;

    $desc = CGI::unescape( $desc );

    $verbose = "-v" if $DEBUG;

    #$DEBUG =1;

    # Detaint username
    $dirty_user =~ s/(\*|\%)//g;
    ( $username ) = $dirty_user =~ m/^([A-Z0-9_.\-\:\s\,\/]+)$/ig;
    $username = lc( $username );

    if ( $userAuthLevel >= $reportAuthLevel{"desc_change"} && $reportAuthLevel{"desc_change"} ) {
        $descauth = 1;
        print "<br>Debug: User Authorized for Description Change: $desc ON $switchport\n" if $DEBUG;
    }
    else {
        print "<br>Error: User NOT Authorized for Description Change\n";
        return;
    }

    # Make sure script is defined
    if ( !$desc_script ) {
        print "<br>Error: desc_script undefined\n";
        return;
    }

    if ( $descauth ) {
        my $transactionID = recordTransaction( "$switchport", "desc_change" );

        print "<div class=\"loading\">Changing description on switchport: $switchport,$desc<br></div>\n";
        print "desc_change command: $desc_script $switchport,\"$desc\" $verbose" if $DEBUG;
        @output = `$desc_script $switchport,\"$desc\" $verbose`;


        my $success;
        # Print Results from script
        foreach my $line ( @output ) {
            if ( $line =~ /(Camtrace success)|(Successfully)/ ) {
                $success = 1;

                # Update description in database
                my $dbh = connectDBrw( $config_file );
                my ( $switch, $port ) = split( /\,/, $switchport );
                updateDescription( $dbh, $switch, $port, $desc );

                print $line;
            }
            elsif ( $success ) {
                print "<br>$line";
            }
        }
        if ( !$success ) {
            print "Description Change Failed<br>\n";
            foreach my $line ( @output ) {
                print "<br>$line\n";
            }
        }
    }
}

#########################################################
# Process a VLAN Change request, ajax or get request
#########################################################
sub changeVlan {
    my $vlan = parseInputVar( "vlan" );
    my $voicevlan = parseInputVar( "voicevlan" );
    my $switchport = parseInputVar( "vlanswitchport" );
    my $dirty_user = $envuser;
    my $username;
    my $success;
    my @output;
    my $verbose;
    my ( $switch ) = split( /\,/, $switchport );

    $verbose = "-v" if $DEBUG;
    
    # Detaint username
    $dirty_user =~ s/(\*|\%)//g;
    ( $username ) = $dirty_user =~ m/^([A-Z0-9_.\-\:\s\,\/]+)$/ig;
    $username = lc( $username );

    print "Checking Authorization for $envuser for vlan_change" if $DEBUG;

    my $authorized_vlan = checkVlanAuth( $switch );

    if ( $vlan =~ /^\d+$/ && $switchport ) {
	
	# Check for voice vlan
	if ( $voicevlan =~ /^\d+$/ ) {
	    $vlan = "$vlan,$voicevlan";
	}

	# Check to see if script variable is defined
	if ( !$vlan_script ) {
	    print "<br>Configuration Error: vlan_script is undefined in $config_cgi<br>";
	}

	# Check user authorization based on per switch setting or access level in the config file
	elsif ( $authorized_vlan || ( $userAuthLevel >= $reportAuthLevel{"vlan_change"} && $reportAuthLevel{"vlan_change"} ) ) {    
	    $transactionID = recordTransaction( "$switchport,$vlan", "vlan_change" );

	    print "<div class=\"loading\">Changing switchport vlan: $switchport,$vlan<br></div>\n";
	    print "vlan_change command: $vlan_script $switchport,$vlan -u $username $verbose" if $DEBUG;
	    @output = `$vlan_script $switchport,$vlan -u $username $verbose`;

#	    @output = "Success";

	    # Print Results from script
	    foreach my $line ( @output ) {
		$line =~ s/^(MNC\s\w+:)/<b>$1<\/b>/;
		$line =~ s/^<b>(MNC ERROR:)/<b style="color:red">$1<\/b>/;
                $line =~ s/^(Camtrace\s\w+:)/<b>$1<\/b>/;

		# Update VLAN Instantly
		if ( $line =~ /Success/ ) {
		    my $dbh = connectDBrw( $config_file );
		    my ( $switch, $port ) = split( /\,/, $switchport );
		    updatePortVLAN( $dbh, $switch, $port, $vlan );		    
		}

		print "$line\n<br>";
	    }
	}

	else {
	    print "User $envuser unauthorized to change vlans on $switch";
	}
    }
    elsif ( $vlan !~ /\d+/ ) {
	print "Input Error: No VLAN Submitted";
    }
    else {
	print "Input error: Bad VLAN ID: $vlan";
    }
	
}


###################################################
# Run custom script to correlate usernames to IPs #
###################################################
sub findIPUser {
    my $address = parseInputVar( "address" );
    my $dirty_user = $envuser;
    my $username;
    my @output;
    my $verbose;
    
    # Detaint username
    $dirty_user =~ s/(\*|\%)//g;
    ( $username ) = $dirty_user =~ m/^([A-Z0-9_.\-\:\s\,\/]+)$/ig;

    if ( !$findipuser ) {
	print "<br>Error: Undefined findipuser script";
    }
    elsif ( !$address ) {
	print "<br>Error: Input problem on address";
    }

    # User Authorized
    elsif ( $userAuthLevel >= $reportAuthLevel{"findipuser"} && $reportAuthLevel{"findipuser"} ) {
	print "<h3>Findipuser results on $address</h3><br>";

	$transactionID = recordTransaction( "$address", "findipuser" );

	#print "<div class=\"loading\">Running findipuser on $address for $username<br></div>\n";
	print "findipuser command: $findipuser $address" if $DEBUG;
	@output = `$findipuser "$address "`;

	
	# Print Script results
	print "<font face=\"courier\">";
	my $nowait;
	
	foreach my $line ( @output ) {
	
	    if ( $nowait ) {
		print "$line\n<br>";
	    }
	    elsif ( $line =~ /^Username/ ) {
		$nowait = 1;
                print "$line\n<br>";
	    }
	}
	print "</font>";
    }
    else {
	print "<br>User $envuser unauthorized to run findipuser, email $ownerEmail to request authorization";
    }
    
}


###################################################
# Run custom script to correlate usernames to IPs #
###################################################
sub bradfordTransactions {
    my $address = parseInputVar( "address" );
    my $dirty_user = $envuser;
    my $username;
    my @output;
    my @ntable;
    my $verbose;
    

    # Detaint username
    $dirty_user =~ s/(\*|\%)//g;
    ( $username ) = $dirty_user =~ m/^([A-Z0-9_.\-\:\s\,\/]+)$/ig;

    if ( !$trans_script ) {
	print "<br>Error: Undefined Bradford Transactions script";
    }
    elsif ( !$address ) {
	print "<br>Error: Input problem on address";
    }

    # User Authorized
    elsif ( $userAuthLevel >= $reportAuthLevel{"bradfordtransactions"} && $reportAuthLevel{"bradfordtransactions"} ) {
	#print "<h3>Bradford Transaction results on $address</h3><br>";

	$transactionID = recordTransaction( "$address", "bradfordTrans" );

	#print "<div class=\"loading\">Running findipuser on $address for $username<br></div>\n";
#	print "<br>bradford command: $trans_script $address -d $searchDays<br>";
	@output = `$trans_script $address -d $searchDays`;

	
	# Print Script results
	
        push ( @ntable, '<div class="netdb">');
	push( @ntable, '<table id="netdbipmac">');

        # Table Caption
        push ( @ntable, "<caption><h2>Bradford Transaction Logs</h2></caption>" );

        push ( @ntable, '
        <thead>
        <tr>
        <th>Connect Time</th>
        <th>Disconnect Time</th>
        ');

        push ( @ntable, '
        <th>User ID</th>
        <th>IP Address</th>
        <th>MAC Address</th>
      </tr>
      </thead>
      <tbody>
');

	# Split up the CSV output and print a table line
	foreach my $line ( @output ) {

	    
	    my @line = split( /\,/, $line );
	    
	    if ( $line[4] && $line[4] =~ /\:/ ) {
		
		push ( @ntable, "<tr><td>$line[0]</td>" );
		push ( @ntable, "<td>$line[1]</td>" );
		push ( @ntable, "<td>$line[2]</td>" );
		push ( @ntable, "<td>$line[3]</td>" );
		push ( @ntable, "<td>$line[4]</td></tr>" );
	    }
	}

	push ( @ntable, "</tbody></table></div>\n" );
	
	## Print Table

	print @ntable;
    }
    else {
	print "<br>User $envuser unauthorized to run bradfordtransactions, email $ownerEmail to request authorization";
    }
    
}


# Check VLAN Authorization for a switch

sub checkVlanAuth {
    my $req_switch = shift;

    foreach my $auth_switch ( sort keys %vlanAuth ) {

	# Exact Match
	if ( $auth_switch eq $req_switch ) {
	    return 1;
	}

	# Match on end of line wildcard
	elsif ( $auth_switch =~ /\*$/ ) {
	    $auth_switch =~ s/\*//g;
	    
	    if ( $req_switch =~ /^$auth_switch/ ) {
	        return 1;
	    }
	}
	# Match on beginning of line wildcard
        elsif ( $auth_switch =~ /^\*/ ) {
            $auth_switch =~ s/\*//g;

            if ( $req_switch =~ /$auth_switch$/ ) {
                return 1;
            }
        }

	# Match middle of word wildcard
	elsif (  $auth_switch =~ /\*/ ) {
	    my @tmp = split( /\*/, $auth_switch );

	    if ( $req_switch =~ /^$tmp[0]/ && $req_switch =~ /$tmp[1]$/ ) {
		return 1;
	    }
	}


    } 

    return undef;
}


# Parse Configuration from file
sub parseConfig {

    my $vlan_ref;

    # Create any variables that do not exist to avoid errors
    my $config = AppConfig->new({
                                 CREATE => 1,
                                });
    
    $config->define( "scriptName=s", "ownerInfo=s", "pageTitle=s", "pageName=s", "template=s", "cgibin=s" );
    $config->define( "root=s", "aboutFile=s", "config_file=s", "useCamtrace=s", "useStatistics=s", "debug=s" );
    $config->define( "ownerEmail=s", "default_auth_level=s", "level1_access=s", "level2_access=s", "level3_access=s" );
    $config->define( "level0_reports=s", "level1_reports=s", "level2_reports=s", "level3_reports=s" );
    $config->define( "level0_maxcount=s", "level1_maxcount=s", "level2_maxcount=s", "level3_maxcount=s" );
    $config->define( "mac_format=s", "useNAC=s", "vlan_script=s", "desc_length=s", "vlan_change=s%"  );
    $config->define( "findipuser=s", "trans_script=s", "mnc_shut=s", "mnc_unshut=s", "mnc_portshut=s", "mnc_portunshut=s" );
    $config->define( "mnc_block=s", "mnc_noblock=s", "role_file=s", "role_script=s", "nac_group=s%" );
    $config->define( "desc_script=s", "shut_script=s", "statseeker", "useInventory=s", "wifi_http=s", "use_fqdn" );

    $config->file( "$config_cgi" );

    $scriptName    = $config->scriptName();
    $ownerInfo     = $config->ownerInfo();
    $ownerEmail    = $config->ownerEmail();
    $pageTitle     = $config->pageTitle();
    $pageTitle     = "<title>$pageTitle</title>";
    $pageName      = $config->pageName();
    $pageName      = "<h2>$pageName</h2>";
    $template      = $config->template();
    $cgibin        = $config->cgibin();
    $root          = $config->root();
    $aboutFile     = $config->aboutFile();
    $config_file   = $config->config_file();
    $useCamtrace   = $config->useCamtrace();
    $useStatistics = $config->useStatistics();
    $useNAC        = $config->useNAC();
    $useInventory  = $config->useInventory();
    $statseeker    = $config->statseeker();
    $role_file     = $config->role_file();
    $role_script   = $config->role_script();
    $vlan_script   = $config->vlan_script();
    $mac_format    = $config->mac_format();
    $desc_length   = $config->desc_length() if $config->desc_length();
    $findipuser    = $config->findipuser();
    $trans_script  = $config->trans_script();
    $desc_script   = $config->desc_script();
    $shut_script   = $config->shut_script();
    $mnc_shut      = $config->mnc_shut();
    $mnc_unshut    = $config->mnc_unshut();
    $mnc_block     = $config->mnc_block();
    $mnc_noblock   = $config->mnc_noblock();
    $mnc_portshut  = $config->mnc_portshut();
    $mnc_portunshut = $config->mnc_portunshut();
    $DEBUG         = $config->debug();   
    $defaultAuthLevel = $config->default_auth_level();
    $wifi_http     = $config->wifi_http();
    $use_fqdn      = $config->use_fqdn();

    $vlan_ref          = $config->vlan_change();

    # Sanity Check
    if ( !$template ) {
	die "Could not load the template, make sure script has access to the $config_cgi file";
    }

    # Get the environment username
    $envuser          = $ENV{REMOTE_USER};

    #Clean domain info from username
    ( $envuser ) = split( /\@/, $envuser ); 

    my @list;

    # By Default, put users in default auth level
    $userAuthLevel = $defaultAuthLevel;    

    # Check for level 1 access
    @list = split( /\s+/, $config->level1_access() );


    foreach my $entry ( @list ) {
	print $entry;
	if ( $entry eq lc( $envuser ) ) {
	    $userAuthLevel = 1;
	}
    }
    
    # Level 2 Users
    @list = split( /\s+/, $config->level2_access() );

    foreach my $entry ( @list ) {
        if ( $entry eq lc( $envuser ) ) {
            $userAuthLevel = 2;
        }
    }

    # Level 3 Users
    @list = split( /\s+/, $config->level3_access() );

#    die "debug list: @list";

    foreach my $entry ( @list ) {
        if ( $entry eq lc( $envuser ) ) {
            $userAuthLevel = 3;
        }
    }


    # Vlan Change ability per switch
    my $line = $$vlan_ref{"$envuser"};
    my @switches = split( /\s+/, $line );
    
    foreach my $switch ( @switches ) {
	$vlanAuth{"$switch"} = 1;
    }
    

    # Process Report Type Authorization Levels

    # Level 0 Reports
    @list = split( /\s+/, $config->level0_reports() );

    foreach my $entry ( @list ) {
	$reportAuthLevel{"$entry"} = 0;
    }

    # Level 1 Reports
    @list = split( /\s+/, $config->level1_reports() );

    foreach my $entry ( @list ) {
        $reportAuthLevel{"$entry"} = 1;
    }

    # Level 2 Reports
    @list = split( /\s+/, $config->level2_reports() );

    foreach my $entry ( @list ) {
        $reportAuthLevel{"$entry"} = 2;
    }    

    # Level 3 Reports
    @list = split( /\s+/, $config->level3_reports() );

    foreach my $entry ( @list ) {
        $reportAuthLevel{"$entry"} = 3;
    }

    # NAC Groups
    my $nacgroup_ref = $config->nac_group();
    my %nacgroup = %$nacgroup_ref;
    my $username = $envuser;

    foreach my $key ( keys %nacgroup ) {

	# If user is in group, put all usernames in group in to %nacAuth
	if ( $nacgroup{$key} =~ /$username/ ) {
	    my @users = split( /\s+/, $nacgroup{$key} );
	    foreach my $user ( @users ) {
		$nacAuth{$user} = 1;
	    }
	}
    }


    # Process Max Row Counts
    $reportMaxCount{"0"} = $config->level0_maxcount();
    $reportMaxCount{"1"} = $config->level1_maxcount();
    $reportMaxCount{"2"} = $config->level2_maxcount();
    $reportMaxCount{"3"} = $config->level3_maxcount();

    # Default values if nothing in config file for auth levels
    $reportMaxCount{"0"} = 100000 if !$reportMaxCount{"0"};
    $reportMaxCount{"1"} = 100000 if !$reportMaxCount{"1"};
    $reportMaxCount{"2"} = 100000 if !$reportMaxCount{"2"};
    $reportMaxCount{"3"} = 100000 if !$reportMaxCount{"3"};

#    die "User in $userAuthLevel, $reportMaxCount{2}";
    
}


# Javascript helper code, mostly graphics effects and sorting
# Needs to be moved to a seperate netdb.js file.
sub printHeaderCode {
    print '<script type="text/javascript">' . "\n";

    print <<SCRIPT;

/** NetDB JQuery Javascript **/

/* OnReady Event, show and hide different divs on page */
\$(document).ready(function(){

  // Submit Ready
  var submitReady = true;

  /* Initiate the Tooltip code */
  tooltip();

  /* Notify IE6 Users that their browser sucks */
  if ( \$.browser.msie && \$.browser.version=="6.0") {
     \$("\#netdbnotice").append('<div class="messagebox info"> You may have to scroll down to see your results when using Internet Explorer 6.</div><br>');
  }

  /* JQuery Tabs */
  \$("\#container-1").tabs({
      fx: { opacity: \'toggle\', duration: \'fast\' },
      load: function(event, ui) {
  
          \$('.ajaxlink', ui.panel).livequery('click', function(event) {
            \$(ui.panel).load(this.href);
            return false;
        });
    }
    });                                                     

    /* Hide/Unhide different elements */
    \$(".messagebox").fadeIn(400); //Fade in warning div
    \$(".notice").fadeIn(400); //Fade in notice message
    //\$(".netdbresults").show( 'fold', '', 1000); //Fade in NetDB Results
    \$(".netdbresults").fadeIn(300); //Fade in NetDB Results
    \$(".loading").css('visibility', 'hidden'); //Hide all loading images

    initTableSorter();

     // Setup info dialog box
     \$("\#infodialog").dialog({
       bgiframe: true,
       modal: true,
       width: 450,
       stack: false,
       position: ['center', 230],
       buttons: {
         Ok: function() { \$(this).dialog('close'); 
                           \$("\#netdbaddress").focus(); }
       } //buttons
     });

     // Setup error dialog box
     \$("\#errordialog").dialog({
       bgiframe: true,
       modal: true,
       width: 450,
       stack: false,
       position: ['center', 230],
       buttons: {
         Ok: function() { \$(this).dialog('close'); 
                           \$("\#netdbaddress").focus(); }
       } //buttons
     }).prev().addClass('ui-state-highlight');


    // Allows enter key to close dialog only if dialog box is open
    \$(document).bind("keydown.dialog-overlay", function(event) {
       if ( event.keyCode == 13 ) { 
         if ( \$("\#infodialog").length > 0 && \$("\#infodialog").dialog("isOpen") ) { 
           \$("\#infodialog").dialog("close");
           return false; // Stops event propogation
          }
         else if ( \$("\#errordialog").length > 0 && \$("\#errordialog").dialog("isOpen") ) {
             \$("\#errordialog").dialog("close");
             return false;
         }
         else {
            return true;
         }
       }
    });


/*************************/
/* Disable Client Dialog */
/*************************/

\$("\#disabledialog").dialog({
       autoOpen: false,
       bgiframe: true,
       modal: true,
       width: 600,
       height: 550,
       stack: false,
       position: ['center', 150]
});
                                                                                                                                             


// Clicked on Disable Client Box
\$(".disclient").click(function() {
  \$(".loading").css('visibility', 'hidden'); //Hide all loading images

  // Get the mac
  var myLoc = \$(this).attr('href'); 

  // Strip the anchor out of the address location to get just the switchport
  myLoc = myLoc.replace(/\#disable-/i, "");

  // Change the switchport value to reflect the selected switchport
  \$("\#disablemac").val(myLoc);

  // Add text for dialog box
  \$("\#disabletext").html("<b>Do you want to Shutdown or Block Internet Access for " + myLoc + "?</b>" );


  \$("\#disableform").show();

  //alert("Thanks for visiting!");

  \$("\#disabledialog").dialog("open");


});


 //Disable AJAX Submit
 \$("\#disableform").submit(function() {

     // Build ajax submit string
     var myLoc = document.location.toString();

     // Get the switch and port passed
     myLoc = myLoc.split("\#disable-")[1];
   

    var myType = "unknown";
//       var myType  = \$("\#blocktype").val();
     \$(".loading").css('visibility', 'visible');

    if ( \$("\#blockfirewall:checked").is(":checked") ) {
       myType = "nonetnac";
    }
    if (\$("\#blockshut:checked").is(":checked") ) {
      myType = "shutdown";
    }
    if (\$("\#portshut:checked").is(":checked") ) {
      myType = "portshutdown";
    }

     var dataString = "skiptemplate=1&stage=1&disableclient=1&disablemac=" + myLoc + "&blocktype=" + myType;
     //alert(dataString);

     \$("\#disableform").hide();     
     \$("\#disabletext").html("<br><br><br>Attempting to Disable Device (Press esc to close)<br>");

     \$.ajax({
    type: "POST",
    url: "$scriptLocation",
    data: dataString,
    success: function( data ) {

                  // Print results 
                  \$("\#disabletext").html(data);
                  \$(".loading").css('visibility', 'hidden'); //Hide all loading images
                    //Move focus to dialog box
                  \$("\#caseid").focus();  
                  \$("\#caseid").select();

      }
     });

   //\$(".loading").css('visibility', 'hidden'); //Hide all loading images

   return false;
 });


 /******************/
 /* Enable Box     */
 /******************/

\$("\#enabledialog").dialog({
       autoOpen: false,
       bgiframe: true,
       modal: true,
       width: 610,
       height: 275,
       stack: false,
       position: ['center', 150]
});
                                                                                                                                             


// Clicked on Enable Client Box
\$(".enableclient").click(function() {
  \$(".loading").css('visibility', 'hidden'); //Hide all loading images

  // Get the mac
  var myLoc = \$(this).attr('href'); 

  // Strip the anchor out of the address location to get just the switchport
  myLoc = myLoc.replace(/\#enable-/i, "");

  var results = myLoc.split("-");

  myLoc = results[0];
  var type = results[1];

  // Change the switchport value to reflect the selected switchport
  \$("\#enablemac").val(myLoc);

  // Add text for dialog box
  \$("\#enabletext").text("Are you sure you want to remove security block (" + type + ") for " + myLoc + " ?" );


  \$("\#enableform").show();

  //alert("Thanks for visiting!");

  \$("\#enabledialog").dialog("open");


});



 \$("\#enableform").submit(function() {

     // Build ajax submit string
     var myLoc = document.location.toString();

     // Get the switch and port passed
     myLoc = myLoc.split("\#enable-")[1];
   
     var results = myLoc.split("-");                                                                                                                                                                          
     myLoc = results[0];
     var type = results[1];
     var severe = results[2];
     var myNote = \$("\#enablenote\").val();

     \$(".loading").css('visibility', 'visible');

     var dataString = "skiptemplate=1&stage=3&disableclient=1&disablemac=" + myLoc + "&blocktype=" + type + "&note=" + myNote + "&severe=" + severe;
     // alert(dataString);

     \$("\#enableform").hide();     
     \$("\#enabletext").html("<br><br><br>Attempting to Enable Client (Press esc to close)<br>");
     // Ajax onclick to call camtrace with skiptemplate, then print results to ajaxresults div
     \$.ajax({
    type: "POST",
    url: "$scriptLocation",
    data: dataString,
    success: function( data ) {

                  // Print results 
                  \$("\#enabletext").html(data);
                  \$(".loading").css('visibility', 'hidden'); //Hide all loading images
                    //Move focus to dialog box
      }
     });

   //\$(".loading").css('visibility', 'hidden'); //Hide all loading images

   return false;
 });


/*****************/
/** Role Dialog **/
/*****************/

\$("\#roledialog").dialog({
       autoOpen: false,
       bgiframe: true,
       modal: true,
       width: 475,
       height: 250,
       stack: false,
       position: ['center', 150]
});  

// Clicked on role dialog box link, spawn dialog

\$(".rolechange").click(function() {
  \$(".loading").css('visibility', 'hidden'); //Hide all loading images
  \$("\#roleform").show();

  // Get the port clicked on
  var myLoc = \$(this).attr('href');
  // Strip the anchor out of the address location to get just the mac
  myLoc = myLoc.replace(/\#rolechange-/i, "");

  // Change the role value to reflect the mac address
  \$("\#rolechange").val(myLoc);

  // Add text for dialog box
  \$("\#roletext").text("What role do you want to change " + myLoc + " to?" );
  \$("\#roledialog").dialog("open");

  //Move focus to dialog box
  \$("\#roleid").focus();
  \$("\#roleid").select();
 
 //return false;
});  


/**********************/
/* Description Change Dialog */
/**********************/

\$("\#descdialog").dialog({
       autoOpen: false,
       bgiframe: true,
       modal: true,
       width: 450,
       height: 240,
       stack: false,
       position: ['center', 150]
});

// Clicked on description dialog box link, spawn dialog
\$(".descchange").click(function() {
  \$(".loading").css('visibility', 'hidden'); //Hide all loading images

  \$("\#descform").show();

  // Get the port clicked on
  var myLoc = \$(this).attr('href'); 

  // Strip the anchor out of the address location to get just the switchport
  myLoc = myLoc.replace(/\#descchange-/i, "");

  // Change the switchport value to reflect the selected switchport
  \$("\#descswitchport").val(myLoc);

  // Add text for dialog box
  \$("\#desctext").text("What Description do you want to change port " + myLoc + " to?" );
  \$("\#descdialog").dialog("open");

  //Move focus to dialog box
  \$("\#descid").focus();  
  \$("\#descid").select();

  //return false;
  });

// IE Fix to catch click for ajax submit (if it fails, does a normal post action)
 \$("\#descsubmit").click(function() {
    \$("\#descform").submit();
    return false;
 });

 // IE Fix for pressing enter to submit form in vlanid box
 \$("\#descid").bind("keydown", function (e) {
    var key = e.keyCode || e.which;
    if (key === 13 && \$.browser.msie ) { \$("\#descform").submit(); }
 });


 //Desc Change AJAX Submit
 \$("\#descform").submit(function() {

     // Build ajax submit string
     var myLoc = document.location.toString();

     // Get the switch and port passed
     myLoc = myLoc.split("\#descchange-")[1];
   
     // Get the Description value
     var myDesc = \$("\#descid").val();    
     myDesc = escape( myDesc );

     \$(".Loading").css('visibility', 'visible');

     var dataString = "skiptemplate=1&descchange=1&desc=" + myDesc + "&descswitchport=" + myLoc;

     //alert(dataString);
     //return false;


     \$("\#descform").hide();     
     \$("\#desctext").html("<br>Updating Description, wait for verification or move on to other ports. (Press esc to close)<br>");
     \$("\#loadingdesc\").show();
     // Ajax onclick to call camtrace with skiptemplate, then print results to ajaxresults div
     \$.ajax({
    type: "POST",
    url: "$scriptLocation",
    data: dataString,
    success: function( data ) {

                  // Print results after camtrace.pl returns
                  \$("\#desctext").html(data);
                  \$(".loading").css('visibility', 'hidden'); //Hide all loading images
      }
     });

   //\$(".loading").css('visibility', 'hidden'); //Hide all loading images

   return false;
 });


/**********************/
/*  ShutNoShut Dialog */
/**********************/

\$("\#shutdialog").dialog({
       autoOpen: false,
       bgiframe: true,
       modal: true,
       width: 450,
       height: 240,
       stack: false,
       position: ['center', 150]
});

// Clicked on shut/no shut dialog box link, spawn dialog
\$(".shutchange").click(function() {
  \$(".loading").css('visibility', 'hidden'); //Hide all loading images

  \$("\#shutform").show();

  // Get the port clicked on
  var myLoc = \$(this).attr('href');

  // Strip the anchor out of the address location to get just the switchport
  myLoc = myLoc.replace(/\#shutchange-/i, "");

  // Change the switchport value to reflect the selected switchport
  \$("\#shutswitchport").val(myLoc);

  // Add text for dialog box
  \$("\#shuttext").text("What Action do you want to take on " + myLoc + "?" );
  \$("\#shutdialog").dialog("open");

  //Move focus to dialog box
  \$("\#shutid").focus();
  \$("\#shutid").select();


  //return false;
  });

// IE Fix to catch click for ajax submit (if it fails, does a normal post action)
 \$("\#shutsubmit").click(function() {
    \$("\#shutform").submit();
    return false;
 });

 // IE Fix for pressing enter to submit form in vlanid box
 \$("\#shutid").bind("keydown", function (e) {
    var key = e.keyCode || e.which;
    if (key === 13 && \$.browser.msie ) { \$("\#shutform").submit(); }
 });


 //Desc Change AJAX Submit
 \$("\#shutform").submit(function() {

     // Build ajax submit string
     var myLoc = document.location.toString();

     // Get the switch and port passed
     myLoc = myLoc.split("\#shutchange-")[1];

     // Get the Description value
     var myShut = \$("\#shutid").val();
     myShut = escape( myShut );

     \$(".Loading").css('visibility', 'visible');

     var dataString = "skiptemplate=1&shutchange=1&shut=" + myShut + "&shutswitchport=" + myLoc;

     //alert(dataString);
    //return false;


     \$("\#shutform").hide();
     \$("\#shuttext").html("<br>Updating Port, wait for verification or move on to other ports. (Press esc to close)<br>");
     \$("\#loadingshut\").show();
     // Ajax onclick to call camtrace with skiptemplate, then print results to ajaxresults div
     \$.ajax({
    type: "POST",
    url: "$scriptLocation",
    data: dataString,
    success: function( data ) {

                  // Print results after camtrace.pl returns
                  \$("\#shuttext").html(data);
                  \$(".loading").css('visibility', 'hidden'); //Hide all loading images
      }
     });

   //\$(".loading").css('visibility', 'hidden'); //Hide all loading images

   return false;
 });


/**********************/
/* Statseeker Graphs  */
/**********************/

\$("\#statdialog").dialog({
       autoOpen: false,
       bgiframe: true,
       modal: false,
       width: 850,
       height: 240,
       stack: false,
       position: ['center', 300 ]
});

\$(".statseeker").click(function() {
  \$(".loading").css('visibility', 'hidden'); //Hide all loading images

  // \$("\#vlanform").show();

  // Get the port clicked on
  var myLoc = \$(this).attr('href'); 

  // Strip the anchor out of the address location to get just the switchport
  myLoc = myLoc.replace(/\#statseeker-/i, "");

  var splitResult = myLoc.split(",");

  // Change the switchport value to reflect the selected switchport
  //\$("\#vlanswitchport").val(myLoc);

  var imgurl = "<img src=\\"sp.py?match=" + splitResult[0] + "\&intmatch=" + splitResult[1] + "\&command=Graph\\">";

  // Add text for dialog box
  \$("\#stattext").html( imgurl );
  \$("\#statdialog").dialog("open");

  //return false;
  });


/*********************/
/* Interface Stats  */
/********************/

\$("\#intdialog").dialog({
       autoOpen: false,
       bgiframe: true,
       modal: false,
       width: 700,
       height: 550,
       stack: false,
       position: ['center', 200 ]
});

 \$(".interface").click(function() {
  \$(".loading").css('visibility', 'hidden'); //Hide all loading images

  // Get the port clicked on
  var myLoc = \$(this).attr('href'); 

  // Strip the anchor out of the address location to get just the filename
  myLoc = myLoc.replace(/\#interface-/i, "");

  // Add text for dialog box
  //\$("\#inttext").load( myLoc );

   \$.ajax({
    url: myLoc,
    cache: false,
    dataType: "text",
    success: function(data) {
        \$("\#inttext").html(data);
      }
   });  

\$("\#intdialog").dialog("open");

  //return false;
  });



/***************************/
/* Inventory Report Dialog */
/***************************/

\$("\#reportdialog").dialog({
       autoOpen: false,
       bgiframe: true,
       modal: false,
       width: 750,
       height: 650,
       stack: false,
       position: ['center', 100 ]
});

\$(".invreport").click(function() {
  \$(".loading").css('visibility', 'hidden'); //Hide all loading images

  \$("\#reporttext").html("<br>");

  //\$("\#reportdialog").dialog('option', 'title', 'test' );

  // Get the port clicked on
  var myLoc = \$(this).attr('href');

  // Strip the anchor out of the address location to get just the switchport
  myLoc = myLoc.replace(/\#invreport-/i, "");

  var splitResult = myLoc.split(",");

  var myTitle = "test"; 
  myTitle = myLoc.replace("/status/", "");
  myTitle = myTitle.replace("/configs/", "");
  myTitle = myTitle.replace(".txt", "");

  \$("\#reportdialog").dialog('option', 'title', myTitle );

//  alert(myLoc);

  // Add text for dialog box
//  \$("\#reporttext").load( myLoc );

   \$.ajax({
    url: myLoc,
    cache: false,
    dataType: "text",
    success: function(data) {
        \$("\#reporttext").html(data);
      }
   });

  \$("\#reportdialog").dialog("open");

  return false;
  }); 


/**********************/
/* Vlan Change Dialog */
/**********************/

\$("\#vlandialog").dialog({
       autoOpen: false,
       bgiframe: true,
       modal: true,
       width: 450,
       height: 240,
       stack: false,
       position: ['center', 230]
});
                                                                                                                                             


// Clicked on dialog box link, spawn dialog
\$(".vlanchange").click(function() {
  \$(".loading").css('visibility', 'hidden'); //Hide all loading images

  \$("\#vlanform").show();

  // Get the port clicked on
  var myLoc = \$(this).attr('href'); 

  // Strip the anchor out of the address location to get just the switchport
  myLoc = myLoc.replace(/\#vlanchange-/i, "");

  // Change the switchport value to reflect the selected switchport
  \$("\#vlanswitchport").val(myLoc);

  // Add text for dialog box
  \$("\#vlantext").text("What VLAN do you want to change port " + myLoc + " to?" );
  \$("\#vlandialog").dialog("open");

  //Move focus to dialog box
  \$("\#vlanid").focus();  
  \$("\#vlanid").select();

  //return false;
  });



// IE Fix to catch click for ajax submit (if it fails, does a normal post action)
 \$("\#vlansubmit").click(function() {
    \$("\#vlanform").submit();
    return false;
 });

 // IE Fix for pressing enter to submit form in vlanid box
 \$("\#vlanid").bind("keydown", function (e) {
    var key = e.keyCode || e.which;
    if (key === 13 && \$.browser.msie ) { \$("\#vlanform").submit(); }
 });


 //VLAN Change AJAX Submit
 \$("\#vlanform").submit(function() {

     // Build ajax submit string
     var myLoc = document.location.toString();

     // Get the switch and port passed
     myLoc = myLoc.split("\#vlanchange-")[1];
   
     // Get the VLAN value
     var myVlan = \$("\#vlanid").val();    
     var myVoice = \$("\#voicevlan").val();
     \$(".loading").css('visibility', 'visible');

     var dataString = "skiptemplate=1&vlanchange=1&vlan=" + myVlan + "&voicevlan=" + myVoice + "&vlanswitchport=" + myLoc;
     //alert(dataString);

     \$("\#vlanform").hide();     
     \$("\#vlantext").html("<br><br><br>Changing port, wait for verification or move on to other ports. (Press esc to close)<br>");
     \$("\#loadingvlan\").show();
     // Ajax onclick to call camtrace with skiptemplate, then print results to ajaxresults div
     \$.ajax({
    type: "POST",
    url: "$scriptLocation",
    data: dataString,
    success: function( data ) {

                  // Print results after camtrace.pl returns
                  \$("\#vlantext").html(data);
                  \$(".loading").css('visibility', 'hidden'); //Hide all loading images
      }
     });

   //\$(".loading").css('visibility', 'hidden'); //Hide all loading images

   return false;
 });


 // Select and focus on Address by default on load
 \$("\#netdbaddress").focus();
 \$("\#netdbaddress").select();


}); //END \$(document).ready(function(){});


/** FUNCTIONS **/

function initTableSorter() {
    /* Table Sorter Code
     *
     * Parser to sort by port
     */
    \$.tablesorter.addParser({ 
        // set a unique id 
        id: 'port', 
        is: function(s) { 
            // return false so this parser is not auto detected 
            return false; 
        }, 
        format: function(s) { 

            s = \$(s).text();
            //alert(s);

            s = s.toLowerCase().replace(/gi/i, "10").replace(/fa/i, "10").replace(/eth/i, "10"); //strip out the Gi and Fa
            s = s.toLowerCase().replace(/te/i, "10").replace(/po/i, "100000").replace(/v10/i, "200000");
            var splitResult = s.split("/"); // Split on the / character
            var num1 = parseFloat(splitResult[0]); // Convert string to numbers
            
            //alert(s);

            var num2 = 1;
            if( splitResult[1] ) {
              num2  = parseFloat(splitResult[1]);
            }

            var num3 = 1;
            if( splitResult[2] ) {
              num3  = parseFloat(splitResult[2]);
            }
            var myReturn = num1*100000+num2*1000+num3;   // Add a weights to port sections

            return myReturn;
        }, 
        // set type, either numeric or text 
        type: 'numeric' 
    }); 


   //Strip link and sort numerically
    \$.tablesorter.addParser({
        // set a unique id
        id: 'striplink',
        is: function(s) {
            // return false so this parser is not auto detected
            return false;
        },
        format: function(s) {

           //alert(s);

            s = \$(s).text();

            return s;
        },
        // set type, either numeric or text
        type: 'numeric'
    });


   //Strip link and sort text
    \$.tablesorter.addParser({
        // set a unique id
        id: 'striplinktext',
        is: function(s) {
            // return false so this parser is not auto detected
            return false;
        },
        format: function(s) {

            s = \$(s).text();

            //alert(s);

            return s;
        },
        // set type, either numeric or text
        type: 'text'
    });


   // Sort by IP Address
    \$.tablesorter.addParser({
        // set a unique id
        id: 'customIP',
        is: function(s) {
            // return false so this parser is not auto detected
            return false;
        },
        format: function(s) {
            // format your data for normalization
            var splitIP = s.split("."); // Split on the . character
            var num1 = parseFloat(splitIP[0]); // Convert string to numbers
            var num2 = parseFloat(splitIP[1]);
            var num3 = parseFloat(splitIP[2]);
            var num4 = parseFloat(splitIP[3]);
            var myReturn = num1*1000000000+num2*100000+num3*1000+num4;   // Add a weights to port sections

            return myReturn;
        },
        // set type, either numeric or text
        type: 'numeric'
    });

    // ARP Table
    \$("\#netdbipmac").tablesorter({
      sortList: [[0,0]],
      headers: {
          0: { sorter: "customIP" }
      } 
    });

    // MAC Table
    \$("\#netdbmac").tablesorter({
      headers: {
        1: { sorter: "customIP" },
        4: { sorter: "text" },
        5: { sorter: "port" }
      }
    });

    // Switchport Table
    \$("\#netdbswitch").tablesorter({
      sortList: [[0,0], [1,0]],
      headers: {
        1: { sorter: "port" },
        3: { sorter: "striplink" },
        6: { sorter: "ipAddress" }
      }
    });

    \$("\#netdbinv").tablesorter({
      sortList: [[0,0]],
      headers: {
        0: { sorter: "striplinktext" }
      }
    });
}

/* Tooltip Code */
this.tooltip = function(){
  /* CONFIG */
  xOffset = 10;
  yOffset = 20;
  // these 2 variable determine popup's distance from the cursor
  // you might want to adjust to get the right result
  /* END CONFIG */
  \$("a.tooltip").hover(function(e){
    this.t = this.title;
    this.title = "";
    \$("body").append("<p id='tooltip'>"+ this.t +"</p>");
    \$("\#tooltip")
    .css("top",(e.pageY - xOffset) + "px")
    .css("left",(e.pageX + yOffset) + "px")
    .fadeIn("50");
  },
  function(){
    this.title = this.t;
    \$("\#tooltip").remove();
  });
  \$("a.tooltip").mousemove(function(e){
    \$("\#tooltip")
    .css("top",(e.pageY - xOffset) + "px")
    .css("left",(e.pageX + yOffset) + "px");
  });

};
    
SCRIPT

    print '</script>';
}
