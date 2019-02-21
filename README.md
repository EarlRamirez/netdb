
## NetDB (Work in Progress)

[NetDB](http://netdbtracking.sourceforge.net/) Network tracking database (NetDB) utilises the LAMP (Linux, Apache, MariaDB and Perl) stack for scraping and storing your network infomration in a centralised location.


-----------
### Credit

All credit goes to Jonathan Yantis.

------------
### Installation

The installations script is geared toward a vanilla installation of your favourite Red Hat based distro; however, if you are going to install NetDB on an existing server that has the LAMP stack or just want do it manually follow the below steps.

- Install epel repo and update the OS

   >yum install -y epel-release && yum -y update

- Install the necessary packages

   >yum install -y gcc unzip make bzip2 curl lynx ftp patch mariadb mariadb-server httpd httpd-tools perl mrtg perl-List-MoreUtils perl-DBI perl-Net-DNS perl-Math-Round perl-Module-Implementation perl-Params-Validate perl-DateTime-Locale perl-DateTime-TimeZone perl-DateTime perl-DateTime-Format-MySQL perl-Time-HiRes perl-Digest-HMAC perl-Digest-SHA1 perl-Net-IP perl-AppConfig perl-Proc-Queue perl-Proc-ProcessTable perl-NetAddr-IP perl-IO-Socket-IP perl-IO-Socket-INET6 perl-ExtUtils-CBuilder perl-Socket perl-YAML perl-CGI perl-CPAN expect mod_ssl git expect

- Install Perl modules that is required for NetDB

   >cpan Attribute::Handlers && cpan Data::UUID && cpan Net::MAC::Vendor && cpan Net::SSH::Expect && cpan File::Flock && cpan ExtUtils::Constant

- Create NetDB user 

   >useradd netdb && usermod -aG wheel netdb

- Clone NetDB repository to /opt/netdb

   >git clone https://github.com/EarlRamirez/netdb.git /opt/netdb

- Change the directory ownership and create the necessary directories

   >chown -R netdb.netdb /opt/netdb && mkdir -pv /var/log/netdb && chown -R netdb.apache /var/log/netdb

- Create Symbolic NetDB symbolic link

   >ln -s /opt/netdb/netdb.pl /usr/local/bin/netdb && ln -s /opt/netdb/netdbctl.pl /usr/local/bin/netdbctl

- Copy control log rotation script

   >cp /opt/netdb/extra/netdb-logrotate /etc/logrotate.d/

- Configure MariaDB

   >systemctl enable mariadb && systemctl start mariadb

   >mysql_secure_installation

   >mysql -u root -p (Login to MariaDB/MySQL)

       >CREATE DATABASE netdb;  
	   >use netdb;   
	   >source /opt/netdb/createdb.sql;  
		  


----------
### Configuring and Adding Devices

-----------
### Troubleshotting
