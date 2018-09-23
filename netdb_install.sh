#!/bin/bash

# Install and Configure NetDB on CentOS/RHEL Linux

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

# Install dependencies and packages
yum -y install gcc unzip make bzip2 curl lynx ftp patch

yum install perl-List-MoreUtils perl-DBI perl-Net-DNS perl-Math-Round perl-Module-Implementation \
perl-Params-Validate perl-DateTime-Locale perl-DateTime-TimeZone perl-DateTime \
perl-DateTime-Format-MySQL perl-Time-HiRes perl-Digest-HMAC perl-Digest-SHA1 \
perl-Net-IP perl-AppConfig perl-Proc-Queue perl-Proc-ProcessTable perl-NetAddr-IP perl-IO-Socket-IP \
perl-IO-Socket-INET6 perl-ExtUtils-CBuilder perl-Socket perl-YAML perl-CGI perl-CPAN

NetDB Perl module         req  CentOS/RHEL package
---------------------	  ----------------------
install List::MoreUtils			perl-List-MoreUtils
install DBI						perl-DBI
install Net::DNS				perl-Net-DNS
install Math::Round				perl-Math-Round
install Module::Implementation	perl-Module-Implementation
install Attribute::Handlers
install Params::Validate		perl-Params-Validate
install DateTime::Locale		perl-DateTime-Locale
install DateTime::TimeZone		perl-DateTime-TimeZone
install DateTime				perl-DateTime
install DateTime::Format::MySQL	perl-DateTime-Format-MySQL
install Time::HiRes				perl-Time-HiRes
install Data::UUID				
install Digest::HMAC			perl-Digest-HMAC
install Digest::SHA1			perl-Digest-SHA1
install Net::MAC::Vendor 
install Net::SSH::Expect
install Net::Telnet::Cisco  ## Only install if Telnet is required
install Net::IP					perl-Net-IP
install AppConfig				perl-AppConfig				
install Proc::Queue				perl-Proc-Queue
install Proc::ProcessTable		perl-Proc-ProcessTable
install File::Flock				
install NetAddr::IP				perl-NetAddr-IP
install IO::Socket::INET		perl-IO-Socket-IP # May still need to install IO::Socket::INET module for backward compatibility
install IO::Socket::INET6		perl-IO-Socket-INET6
install ExtUtils::Constant			
install ExtUtils::CBuilder		perl-ExtUtils-CBuilder
install Socket					perl-Socket
install YAML					perl-YAML

 
cpan Attribute::Handlers
cpan Data::UUID
cpan Net::MAC::Vendor
cpan Net::SSH::Expect
cpan File::Flock
cpan ExtUtils::Constant


