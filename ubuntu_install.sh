#!/bin/bash
NETDBUSER="netdb"

#To make a more easy install on Ubuntu...

#user creation
useradd $NETDBUSER
retval=$?
if [ $retval -ne 0 ]; then
    if [ $retval -ne 9 ]; 
    then
        echo "Could not add user  $NETDBUSER"
        return
    fi
    else
    echo "Added $NETDBUSER"    
fi

#apt installs
apt update
apt-get install liblist-moreutils-perl libdbi-perl libnet-dns-perl libdatetime-perl \
libdatetime-format-mysql-perl libossp-uuid-perl libdigest-hmac-perl libdigest-sha-perl libdigest-sha-perl\
 libwww-perl libexpect-perl libnet-telnet-cisco-perl libappconfig-perl libio-lockedfile-perl libnetaddr-ip-perl \
libnet-ip-perl libio-socket-inet6-perl libfile-flock-perl libproc-processtable-perl


#perl crap (hope this can be automated)


#linking stuff


#init mysql


#disbale user login