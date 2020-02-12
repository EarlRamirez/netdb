##!/bin/bash
NETDBUSER="netdb"
DATABASE="netdb"
SQLSERVER="mariadb-server"
SQLCLIENT="mariadb-server"
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

#Installing mysql
sudo apt install mysql-client $SQLSERVER


#apt installs
apt update
apt-get install liblist-moreutils-perl libdbi-perl libnet-dns-perl libdatetime-perl \
libdatetime-format-mysql-perl libossp-uuid-perl libdigest-hmac-perl libdigest-sha-perl libdigest-sha-perl\
libwww-perl libexpect-perl libnet-telnet-cisco-perl libappconfig-perl libio-lockedfile-perl libnetaddr-ip-perl \
libnet-ip-perl libio-socket-inet6-perl libfile-flock-perl libproc-processtable-perl

apt-get install libyaml-perl unzip make bzip2 curl lynx ncftp ftp patch makepatch \
libproc-queue-perl libnet-mac-vendor-perl libnet-openssh-perl

#42 + 117 packages
echo "Putting netdb to /opt"
cp ../netdb /opt
chown -R netdb /opt/netdb/
chgrp -R netdb /opt/netdb/
chown netdb /var/log/netdb/
chgrp www-data /var/log/netdb/
cp  /opt/netdb/netdb.con /etc

#linking stuff
echo "Linking executable"
ln -s /opt/netdb/netdb.pl /usr/local/bin/netdb
ln -s /opt/netdb/netdbctl.pl /usr/local/bin/netdbctl
cp /opt/netdb/extra/netdb-logrotate /etc/logrotate.d/

#init mysql
echo "creating database"
sudo mysql < createdb.sql
sudo mysql netdb < createnetdb.sql
#disbale user login