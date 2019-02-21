
## NetDB (Work in Progress)

[NetDB](http://netdbtracking.sourceforge.net/) Network tracking database (NetDB) utilises the LAMP (Linux, Apache, MariaDB and Perl) stack for scraping and storing your network infomration in a centralised location.


-----------
### Credit

All credit goes to Jonathan Yantis.

------------
### Installation

The installations script is geared toward a vanilla installation of your favourite Red Hat based distro; however, if you are going to install NetDB on an existing server that has the LAMP stack or just want do it manually follow the below steps.

- Install epel repo and update the OS

..._yum install -y epel-release && yum -y update_

- Install the necessary packages

>_yum install -y gcc unzip make bzip2 curl lynx ftp patch mariadb mariadb-server httpd httpd-tools perl mrtg_ \
>_perl-List-MoreUtils perl-DBI perl-Net-DNS perl-Math-Round perl-Module-Implementation_ \
>_perl-Params-Validate perl-DateTime-Locale perl-DateTime-TimeZone perl-DateTime_ \
>_perl-DateTime-Format-MySQL perl-Time-HiRes perl-Digest-HMAC perl-Digest-SHA1_ \
_perl-Net-IP perl-AppConfig perl-Proc-Queue perl-Proc-ProcessTable perl-NetAddr-IP perl-IO-Socket-IP_ \
>_perl-IO-Socket-INET6 perl-ExtUtils-CBuilder perl-Socket perl-YAML perl-CGI perl-CPAN expect mod_ssl git expect_```

- Install Perl modules that is required for NetDB

   ```_cpan Attribute::Handlers_```

   ..._cpan Data::UUID_

   ..._cpan Net::MAC::Vendor_ 

   ..._cpan Net::SSH::Expect_

..._cpan File::Flock_

..._cpan ExtUtils::Constant_

- Create NetDB user 

..._useradd netdb && usermod -aG wheel netdb_

- Clone NetDB repository to /opt/netdb

..._git clone https://github.com/EarlRamirez/netdb.git /opt/netdb_

- Change the directory ownership and create the necessary directories

..._chown -R netdb.netdb /opt/netdb_

..._mkdir -pv /var/log/netdb_

..._chown -R netdb.apache /var/log/netdb_

----------
### Configuring and Adding Devices

-----------
### Troubleshotting
