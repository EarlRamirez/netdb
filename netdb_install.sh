#!/bin/bash

# Install and Configure NetDB on CentOS/RHEL Linux

# Install dependencies and packages
yum -y install gcc unzip make bzip2 curl lynx ftp patch mariadb mariadb-server httpd httpd-tools perl epel-release

yum install perl-List-MoreUtils perl-DBI perl-Net-DNS perl-Math-Round perl-Module-Implementation \
perl-Params-Validate perl-DateTime-Locale perl-DateTime-TimeZone perl-DateTime \
perl-DateTime-Format-MySQL perl-Time-HiRes perl-Digest-HMAC perl-Digest-SHA1 \
perl-Net-IP perl-AppConfig perl-Proc-Queue perl-Proc-ProcessTable perl-NetAddr-IP perl-IO-Socket-IP \
perl-IO-Socket-INET6 perl-ExtUtils-CBuilder perl-Socket perl-YAML perl-CGI perl-CPAN

# Create netdb user
useradd netdb
usermod -aG wheel netdb

# Create directory and update permission
tar -xzvf netdb.tar.gx -C /opt/
chown -R netdb.netdb /opt/netdb
mkdir -pv /var/log/netdb
chown -R netdb.apache /var/log/netdb

# Create symbolic links
ln -s /opt/netdb/netdb.pl /usr/local/bin/netdb
ln -s /opt/netdb/netdbctl.pl /usr/local/bin/netdbctl

# Copy netdb-logrotate script 
cp /opt/netdb/extra/netdb-logrotate /etc/logrotate.d/

Configure Mariadb
systemctl enable mariadb && systemctl start mariadb
mysql_secure_installation
mysql -u root -p
create database netdb;
use netdb;
source /opt/netdb/createnetdb.sql

CREATE USER 'netdbuser'@'localhost' IDENTIFIED BY 'netdb1234';
GRANT SELECT ON *.* TO 'netdbuser'@'localhost';

CREATE USER 'netdbadmin'@'localhost' IDENTIFIED BY 'netdbadmin1234';
GRANT SELECT,INSERT,UPDATE,LOCK TABLES,SHOW VIEW,DELETE ON *.* TO 'netdbadmin'@'localhost';
exit

# Add netdb perl modules
mkdir /usr/lib64/perl5/Net/
ln -s /opt/netdb/NetDBHelper.pm /usr/lib64/perl5/NetDBHelper.pm
ln -s /opt/netdb/NetDB.pm /usr/lib64/perl5/NetDB.pm
 
# Install remaining perl modules
for mod in Attribute::Handlers Data::UUID Net::MAC::Vendor Net::SSH::Expect File::Flock ExtUtils::Constant
do cpan $mod
done;

# Create directories and copy required files
cp /opt/netdb/netdb.conf /etc/
touch /opt/netdb/data/devicelist.csv
cp /opt/netdb/netdb-cgi.conf /etc/
mkdir -pv /var/www/html/netdb
touch /var/www/html/netdb/netdbReport.csv
cp -r /opt/netdb/extra/depends /var/www/html/netdb/
cp /opt/netdb/netdb.cgi.pl /var/www/cgi-bin/netdb.pl

# Create netdb web UI credentials
touch /var/www/html/netdb/netdb.passwd
htpasswd -c /var/www/html/netdb/netdb.passwd netdb

# Create control log
touch /var/www/html/netdb/control.log
echo "Nothing here yet!!" > /var/www/html/netdb/control.log

# Update document root permission and fire up the web server
chown -R apache:apache /var/www/html/netdb
systemctl enable httpd && systemctl start httpd

# Create firewall rule
firewall-cmd --permanent --add-service=http && firewall-cmd --reload

