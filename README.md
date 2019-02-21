
## NetDB (Work in Progress)

[NetDB](http://netdbtracking.sourceforge.net/) Network tracking database (NetDB) utilises the LAMP (Linux, Apache, MariaDB and Perl) stack for scraping and storing your network infomration in a centralised location.


-----------
### Credit

All credit goes to Jonathan Yantis.

------------
### Installation

The installations script is geared toward a vanilla installation of your favourite Red Hat based distro; however, if you are going to install NetDB on an existing server that has the LAMP stack or just want do it manually follow the below steps.

- Install epel repo and update the OS

__yum install -y epel-release && yum -y update__

- Install the necessary packages

__yum install -y gcc unzip make bzip2 curl lynx ftp patch mariadb mariadb-server httpd httpd-tools perl mrtg__ \
__perl-List-MoreUtils perl-DBI perl-Net-DNS perl-Math-Round perl-Module-Implementation__ \
__perl-Params-Validate perl-DateTime-Locale perl-DateTime-TimeZone perl-DateTime__ \
__perl-DateTime-Format-MySQL perl-Time-HiRes perl-Digest-HMAC perl-Digest-SHA1__ \
__perl-Net-IP perl-AppConfig perl-Proc-Queue perl-Proc-ProcessTable perl-NetAddr-IP perl-IO-Socket-IP__ \
__perl-IO-Socket-INET6 perl-ExtUtils-CBuilder perl-Socket perl-YAML perl-CGI perl-CPAN expect mod_ssl git expect__

- Install Perl modules that is required for NetDB

__cpan Attribute::Handlers__

__cpan Data::UUID__

__cpan Net::MAC::Vendor__

__cpan Net::SSH::Expect__

__cpan File::Flock__

__cpan ExtUtils::Constant__

- Create NetDB user 

__useradd netdb && usermod -aG wheel netdb__

- Clone NetDB repository to /opt/netdb

__git clone https://github.com/EarlRamirez/netdb.git /opt/netdb__

- Change the directory ownership and create the necessary directories

__chown -R netdb.netdb /opt/netdb__

__mkdir -pv /var/log/netdb__

__chown -R netdb.apache /var/log/netdb__


-----------
### Troubleshotting
