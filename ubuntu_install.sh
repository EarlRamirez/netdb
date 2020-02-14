##!/bin/bash
NETDBUSER="netdb"
DATABASE="netdb"
SQLSERVER="mysql-server"
SQLCLIENTPACKAGE="mysql-client"
SQLCLIENT="mysql"
DBUSER="netdb"
DBPASS="geheim"
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
sudo apt install $SQLCLIENTPACKAGE $SQLSERVER


#apt installs
apt update &&
apt-get install liblist-moreutils-perl libdbi-perl libnet-dns-perl libdatetime-perl \
libdatetime-format-mysql-perl libossp-uuid-perl libdigest-hmac-perl libdigest-sha-perl libdigest-sha-perl \
libwww-perl libexpect-perl libnet-telnet-cisco-perl libappconfig-perl libio-lockedfile-perl libnetaddr-ip-perl \
libnet-ip-perl libio-socket-inet6-perl libfile-flock-perl libproc-processtable-perl liblist-moreutils-perl libappconfig-perl \

apt-get install libyaml-perl unzip make bzip2 curl lynx ncftp ftp patch makepatch \
libproc-queue-perl libnet-mac-vendor-perl libnet-openssh-perl

#42 + 117 packages
echo "Putting netdb to /opt"
mkdir /opt/netdb
cp -r ./* /opt/netdb
chown -R netdb:netdb /opt/netdb/
mkdir /var/log/netdb/
chown netdb /var/log/netdb/
chgrp www-data /var/log/netdb/
cp  /opt/netdb/netdb.conf /etc

mkdir /var/lock/netdb/
chown -R netdb:netdb /var/lock/netdb/

#linking stuff
echo "Linking executable"
ln -s /opt/netdb/netdb.pl /usr/local/bin/netdb
ln -s /opt/netdb/netdbctl.pl /usr/local/bin/netdbctl
cp /opt/netdb/extra/netdb-logrotate /etc/logrotate.d/

#init mysql
echo "creating database"
sudo $SQLCLIENT < createdb.sql
sudo $SQLCLIENT netdb < createnetdb.sql
sudo $SQLCLIENT netdb < createuser.sql
#set user
crontab -l >> file
cat ./extra/crontab >> file
crontab file
rm file
#cgi
mkdir /var/www
chown -R www-data:www-data /var/www/
cp  /opt/netdb/netdb-cgi.conf /etc
chmod a+r /etc/netdb-cgi.conf
touch /var/www/netdbReport.csv
chown www-data:www-data /var/www/netdbReport.csv
cp -r /opt/netdb/extra/depends/ /var/www/depends
chown --recursive  www-data:www-data  /var/www/depends
mkdir /usr/cgi-bin
chgrp -R www-data /usr/cgi-bin
cp netdb.cgi.pl /usr/cgi-bin
chown  www-data:www-data /usr/cgi-bin/netdb.cgi.pl
#disbale user login
passwd -l netdb
