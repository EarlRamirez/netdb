#
# Includes common subroutines to manage Cisco devices
#
# Update 11/08: Now includes get_cisco_session_auto which will use the local
# username and password instead of passing in the info from each switch.
# This way for all newer scripts you can just change the password in this
# file instead of all individual files.
#
# Update 1/09: Reads username and password from /etc/netdb.conf file
#
# Update 06/09: Added SSH methods and Net::SSH::Expect
#
# Configuration File:
## Device Credentials for routers and switches
#devuser    = switch_user       # Needs R/W Credentials for the time being
#devpass    = yourpasswd
#devuser2   = alt_user          # Alternate Username (usually local user if primary fails)
#devpass2   = yourpasswd
#enablepass = yourenablepasswd  # Optional if needed
#
package CiscoHelper;

use AppConfig;
eval "use Net::Telnet::Cisco;"; # Optional unless telnet is required
use Net::SSH::Expect;
use Net::Ping;
use Net::DNS;
use NetAddr::IP;
use IO::Select;
use List::MoreUtils;   # for any()
use English qw( -no_match_vars );
use Carp;
require Exporter;


our @ISA = qw(Exporter);
our @EXPORT = qw( get_cisco_session get_cisco_session_auto get_cisco_ssh get_cisco_ssh_auto ping_device get_cisco_mac get_windows_mac get_dash_mac );

$VERSION = 1.10;
$DEBUG = 0;

# Variables
my $config_file = "/etc/netdb.conf";

# End User Configuration

## Username and password option for get_cisco_session_auto
# Gets data from /etc/netdb.conf
my $username;
my $passwd;
my $username2;       # Try this if the first username/password fails
my $passwd2;
my $enablepasswd;  # The second passwd always tries to enable

my $default_timeout = 30;
my $ssh_timeout = 5;
my $WHIRLEY_COUNT=-1;

#$whirley='-\|/';@whirley=split //,$whirley;
#$whirley='>--- ->-- -->- ---> ---* --- ---< --<- -<-- <--- *---';@whirley=split /\s+/,$whirley;
$whirley='[>...] [.>..] [..>.] [...>] [...<] [..<.] [.<..] [<...]';@whirley=split /\s+/,$whirley;
#$whirley='... .o. ooo oOo OOO oOo ooo .o.';@whirley=split /\s+/,$whirley;


####
# Sort a list by IP address if IP address is contained somewhere in the list
# Thanks to http://www.sysarch.com/Perl/sort_paper.html
####
sub sort_ip_list {
    my @sortlist = @_;
    
    @sortlist = sort {
    pack('C4' => $a =~
      /(\d+)\.(\d+)\.(\d+)\.(\d+)/)
    cmp
    pack('C4' => $b =~
      /(\d+)\.(\d+)\.(\d+)\.(\d+)/)
    } @sortlist;

    return @sortlist;
}


####
# Take in single hostname and return array of IPs
####
sub name_to_ip {
    my $name = shift;

    my @addresses = gethostbyname($name);

    return @addresses;
}

####
# Pass in an array and it will translate all IP addresses in to hostnames and return the array
####
sub ip_to_name {

    my @ip_array = @_;
    my $i = 0;
    my $array_length = @ip_array;

    my $res_ref = Net::DNS::Resolver->new || die "Unable to create NetAddr::IP object\n";
    my $ip_ref = new NetAddr::IP "128.23.1.1" || die "Unable to create NetAddr::IP object\n";

    for ($i=0; $i < $array_length; $i++) {
	if ($ip_array[$i]) {
#	    $ip_array[$i] =~ s/(\d+\.\d+\.\d+\.\d+)/&translate_ip_to_name($1, $res_ref, $ip_ref)/eg; 
	    $ip_array[$i] = translate_ip_to_name( $ip_array[$i], $res_ref, $ip_ref );
	}
    }

    return @ip_array;
}


####
# Don't call directly, used to lookup IP addresses
####
sub translate_ip_to_name {
    my ($ip_address, $res, $ip, ) = @_;

    $res->udp_timeout(2);
    $res->udppacketsize(1400); # To avoid long responses from locking up Net::DNS

    my $query = $res->search("$ip_address");
    if ($query) {
        foreach my $rr ($query->answer)
        {
            next unless $rr->type eq "PTR";
            return $rr->ptrdname;
        }
    }
    else {
        return $ip_address;
    }


}

####
# Ping device and return up/down status with ping times
# Returns (up_down_bool, ping_time_in_ms)
####
sub ping_device {
    my @results;
    my ($pinghost) = @_;
    my $ping;
    
    # Try ICMP ping first, then UDP if it fails
    $EVAL_ERROR = "";
    eval {
        $ping = Net::Ping->new("icmp");
        $ping->hires();
        @results = $ping->ping( $pinghost, 2);
    };
    if ($EVAL_ERROR)
    {
        print "ICMP Ping failed, switching to UDP\n" if $DEBUG;
        $ping = Net::Ping->new("udp");
        $ping->hires(); # detailed stats
        @results = $ping->ping( $pinghost, 2 );
    }

    # Format time in ms
    $results[1] = sprintf( "%.2f", $results[1] * 1000 );
    return @results;
}

# Use the local username and password from library to login
sub get_cisco_session_auto {

    &parseConfig();

    return get_cisco_session(
                                          {
            Host        => $_[0],
            User1       => $username,
            Pass1       => $passwd,
            EnablePass1 => $enablepasswd,                                  
            User2       => $username2,
            Pass2       => $passwd2,                                       
            EnablePass2 => $enablepasswd,                                          
        }
    );
}


#############################################################################
# Logs in to device(Host) using primary credentials (User1 and Pass1) and
# returns a session object.  Optional values are Timeout and User2 and Pass2.
# You can also pass in EnablePass1 and EnablePass2 if the session needs to
# be enabled.  While this is a seemingly needless layer on Telnet::Cisco,
# it saves a lot of code rewrite and login logic for a lot of scripts.
#############################################################################
sub get_cisco_session {
    my $session_obj;
    my ($arg_ref) = @_;

    &parseConfig();

    # Hostname of target cisco device
    my $hostname = $arg_ref->{Host};

    # Primary username and password required
    my $user1 = $arg_ref->{User1};
    my $pass1 = $arg_ref->{Pass1};
    if (!$user1 || !$pass1 || !$hostname ) {
	croak("Minimum set of arguments undefined in cisco_get_session\n");
    }
    
    # Optional username and password if first fails
    my $user2 = $arg_ref->{User2};
    my $pass2 = $arg_ref->{Pass2};

    # Enable passwords if required
    my $enable_pass1 = $arg_ref->{EnablePass1};
    my $enable_pass2 = $arg_ref->{EnablePass2};
    
    # Set the timeout for commands
    my $cisco_timeout = $arg_ref->{Timeout};
    if (!defined $cisco_timeout) {
	$cisco_timeout = $default_timeout;
    }
    
    # Attempt primary login
    $EVAL_ERROR = undef;
    eval {
	$session_obj = 
	attempt_session( $hostname, $user1, $pass1, $cisco_timeout );

	# Enable if defined
	if ($enable_pass1) {
	    enable_session($session_obj, $enable_pass1);
	}
    };

    # If primary login fails, check for backup credentials and try those
    if ($EVAL_ERROR) {
	if(defined $user2 and defined $pass2) {
	    $session_obj =
	    attempt_session( $hostname, $user2, $pass2, $cisco_timeout );

	    # Enable if defined
	    if ($enable_pass2) {
		enable_session($session_obj, $enable_pass2);
	    }
	}
	else {
	    croak( "\nAuthentication Error: Primary login failed on $hostname and no secondary login credentials provided" );
	}
    }
    
    return $session_obj;
}


######################################################################
# Accepts (hostname, username, password, timeout)
# Returns Net::Telnet::Cisco ref to logged in session
######################################################################
sub attempt_session {
    my ( $hostname, $cisco_user, $cisco_passwd, $cisco_timeout ) = @_;

    my $session_obj;
    
    # Get a new cisco session object
    eval {
	    $session_obj = Net::Telnet::Cisco->new( Host => $hostname, 
						    Timeout => $cisco_timeout,
						  );
	    
    };
    if ( $EVAL_ERROR ) {
	croak("\nNetwork Error: Failed to connect to $hostname");
    }

    # Prompt fix for NX-OS
    $myprompt = '/(?m:[\w.-]+\s?(?:\(config[^\)]*\))?\s?[\$#>]\s?(?:\(enable\))?\s*$)/';
    
    $session_obj->prompt( $myprompt );

    # Log in to the router
    $session_obj->login(
        Name     => $cisco_user,
        Password => $cisco_passwd,
        Timeout  => $cisco_timeout,			
    );

    $session_obj->cmd( String => "terminal length 0" ); # no-more


    return $session_obj;
}

# Attempts to get enable privileges
sub enable_session {
    my ($session_obj, $enablepasswd) = @_;
    
    if ($session_obj->enable($enablepasswd)) {
	my @output = $session_obj->cmd('show privilege') if $DEBUG;
	print "My privileges: @output\n" if $DEBUG;
    }
    else { warn "Can't enable: " . $session_obj->errmsg }
    
}

# Auto login
sub get_cisco_ssh_auto {

    &parseConfig();

    return get_cisco_ssh(
			     {
            Host        => $_[0],
            User1       => $username,
            Pass1       => $passwd,
            EnablePass1 => $enablepasswd,                                  
            User2       => $username2,
            Pass2       => $passwd2,                                       
            EnablePass2 => $enablepasswd,                                          
        }
    );
}


# Get an SSH Session using Net::SSH::Expect
sub get_cisco_ssh {
    my $session_obj;
    my ($arg_ref) = @_;

    &parseConfig();

    # Hostname of target cisco device
    my $hostname = $arg_ref->{Host};

    # Primary username and password required
    my $user1 = $arg_ref->{User1};
    my $pass1 = $arg_ref->{Pass1};
    if ( !$hostname ) {
        croak("Minimum set of arguments undefined in cisco_get_ssh\n");
    }
    
    # Optional username and password if first fails
    my $user2 = $arg_ref->{User2};
    my $pass2 = $arg_ref->{Pass2};

    # Enable passwords if required
    my $enable_pass1 = $arg_ref->{EnablePass1};
    my $enable_pass2 = $arg_ref->{EnablePass2};
    
    # Attempt primary login
    $EVAL_ERROR = undef;
    eval {
        $session_obj = 
        attempt_ssh( $hostname, $user1, $pass1 );
	print "SSH: Primary Login Failed to $hostname\n" if $DEBUG;
    };

    # If primary login fails, check for backup credentials and try those
    if ($EVAL_ERROR) {
	print "SSH: Attempting Secondary Login Credentials to $hostname\n" if $DEBUG;

        if(defined $user2 and defined $pass2) {
            $session_obj =
            attempt_ssh( $hostname, $user2, $pass2 );
        }
        else {
            croak( "\nAuthentication Error: Primary login failed and no secondary login credentials provided\n" );
        }
    }
    
    # Attempt to enter enable mode
    &enable_ssh( $session_obj, $enablepasswd );
    
    return $session_obj;    
}

sub attempt_ssh {
    my ( $hostname, $cisco_user, $cisco_passwd ) = @_;

    my $session_obj;
    
    # Get a new cisco session object
    print "SSH: Logging in to $hostname\n" if $DEBUG;
    
    $session_obj = Net::SSH::Expect->new(
					 host => $hostname,
					 password => $cisco_passwd,
					 user => $cisco_user,
					 raw_pty => 1,
					 timeout => $ssh_timeout,
					);
    # Login
    $session_obj->login();
    
    my @output = $session_obj->exec( "term length 0" ); # no-more

    # Catch Errors
    foreach my $output ( @output ) {
	
	# ASA Term Length Error Detection
	if ( $output =~ /Invalid/ ) {
	    print "Caught bad ASA Parser trying to set term length\n" if $DEBUG;
	    $session_obj->exec( "terminal pager 0" );
	}
	
	# Login failure
	elsif ( $output =~ /Permission/i ) {
	    die "Permission Denied";
	}
	elsif ( $output =~ /Password/i ) {
	    die "Bad Login";
	}
	else {
	    print "SSH login output: $output\n" if $DEBUG;
	}
    }

    return $session_obj;
}

# Attempts to get enable privileges, brute force,
# if it asks for a password, send it
sub enable_ssh() {
    my ($session_obj, $enablepasswd) = @_;
    
    my @output = $session_obj->exec('enable');

    if ( $output[0] =~ /password/i ) {
	$session_obj->exec("$enablepasswd");
    }
    
}


#######################################################
# Clean up mac addresses and put them in cisco format
# returns xxxx.xxxx.xxxx or just xxxx for short format
#######################################################
sub get_cisco_mac {

    my ($mac) = @_;

    if ( $mac ) {
	$mac =~ s/(:|\.|\-|(^0x)|)//g;
	$mac =~ tr/[A-F]/[a-f]/;
	$mac =~ s/(\w{4})/$1\./g;
	chop($mac);
	
	if ((length($mac) == 4) || (length($mac) == 14)) {
	    return $mac
	}
	else {
	    return undef;
	}
    }
    else {
	return undef;
    }

}    


#######################################################
# Clean up mac addresses and put them in windows format
# returns xx:xx:xx:xx:xx:xx
#######################################################
sub get_windows_mac {

    my ($mac) = @_;


    if ( $mac ) {
	$mac =~ s/(:|\.|\-|(^0x)|)//g;
	$mac =~ tr/[A-F]/[a-f]/;
	$mac =~ s/(\w{2})/$1\:/g;
	chop($mac);
	
	if ((length($mac) == 4) || (length($mac) == 17)) {
	    return $mac
	}
	else {
	    return undef;
	}
    }
    else {
	return undef;
    }

}

# Gets mac in xx-xx-xx-xx-xx-xx format
sub get_dash_mac {

    my ($mac) = @_;

    if ( $mac ) {
	
	$mac =~ s/(:|\.|\-|(^0x)|)//g;
	$mac =~ tr/[A-F]/[a-f]/;
	$mac =~ s/(\w{2})/$1\-/g;
	chop($mac);

	if ((length($mac) == 4) || (length($mac) == 17)) {
	    return $mac
	}
	else {
	    return undef;
	}
    }
    else {
	return undef;
    }
}


# Print a spinning progress indicator, use $|=1; in scripts
sub whirley {
    if ($WHIRLEY_COUNT+1==@whirley) {
	$WHIRLEY_COUNT=0;
    } 
    else {
	$WHIRLEY_COUNT++;
    }
    return "$whirley[$WHIRLEY_COUNT]";
}

# Parse Configuration from file
sub parseConfig() {

    # Create any variables that do not exist to avoid errors
    my $config = AppConfig->new({
        CREATE => 1,
                            });
    
    $config->define( "devuser=s", "devpass=s", "devuser2=s", "devpass2=s", "enablepass=s", "telnet_timeout=s",
		     "ssh_timeout=s" );
    
    $config->file( "$config_file" );

    $username      = $config->devuser();     # First User
    $passwd        = $config->devpass();     # First Password
    $username2     = $config->devuser2();     # DB Read/Write User
    $passwd2       = $config->devpass2();     # R/W Password
    $enablepasswd  = $config->enablepass();   # DB Read Only User

    if ( $config->telnet_timeout() ) {
	$default_timeout = $config->telnet_timeout();
    }
    if ( $config->ssh_timeout() ) {
        $ssh_timeout = $config->ssh_timeout();
    }

}


#
1;

