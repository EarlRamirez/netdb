#!/bin/bash

# Install and Configure NetDB on CentOS/RHEL Linux

# Install dependencies and packages
yum -y install epel-release

yum install -y gcc unzip make bzip2 curl lynx ftp patch mariadb mariadb-server httpd httpd-tools perl \
perl-List-MoreUtils perl-DBI perl-Net-DNS perl-Math-Round perl-Module-Implementation \
perl-Params-Validate perl-DateTime-Locale perl-DateTime-TimeZone perl-DateTime \
perl-DateTime-Format-MySQL perl-Time-HiRes perl-Digest-HMAC perl-Digest-SHA1 \
perl-Net-IP perl-AppConfig perl-Proc-Queue perl-Proc-ProcessTable perl-NetAddr-IP perl-IO-Socket-IP \
perl-IO-Socket-INET6 perl-ExtUtils-CBuilder perl-Socket perl-YAML perl-CGI perl-CPAN expect

# Install remaining perl modules
for mod in Attribute::Handlers Data::UUID Net::MAC::Vendor Net::SSH::Expect File::Flock ExtUtils::Constant
do cpan $mod
done;

# Create netdb user
useradd netdb
usermod -aG wheel netdb

# Create directory and update permission
# Download netdb-1.13.2.tar.gz from Sourceforge https://sourceforge.net/projects/netdbtracking/files/latest/download
#TODO have this process replaced by git clone <url> /opt/
tar -xzvf netdb-1.13.2.tar.gz -C /opt/
chown -R netdb.netdb /opt/netdb
mkdir -pv /var/log/netdb
chown -R netdb.apache /var/log/netdb

# Create symbolic links
ln -s /opt/netdb/netdb.pl /usr/local/bin/netdb
ln -s /opt/netdb/netdbctl.pl /usr/local/bin/netdbctl

# Copy netdb-logrotate script 
cp /opt/netdb/extra/netdb-logrotate /etc/logrotate.d/

#TODO Streamline MariaDB portion, users must be prompt to create their passwords
#####################
# Configure Mariadb #
#####################
systemctl enable mariadb && systemctl start mariadb
	# Automated configuration for securing MySQL/MariaDB		
		echo "* Securing MariaDB."
		SECURE_MYSQL=$(expect -c "
		set timeout 10
		spawn /bin/mysql_secure_installation
		expect \"Enter current password for root (enter for none):\"
		send \"$mysql_root\r\"
		expect \"Change the root password?\"
		send \"y\r\"
		expect \"New password:\"
		send \"$mysql_root_pass\r\"
		expect \"Re-enter new password:\"
		send \"$mysql_root_pass\r\"
		expect \"Remove anonymous users?\"
		send \"y\r\"
		expect \"Disallow root login remotely?\"
		send \"y\r\"
		expect \"Remove test database and access to it?\"
		send \"y\r\"
		expect \"Reload privilege tables now?\"
		send \"y\r\"
		expect eof
		")
		echo "$SECURE_MYSQL"
		echo ""


mysql -u root --password=$mysql_root_pass --execute="use netdb;source /opt/netdb/createnetdb.sql"
mysql -u root --password=$mysql_root_pass --execute="use netdb;GRANT ALL PRIVILEGES ON netdb.* TO netdb@localhost IDENTIFIED BY '$mysqluserpw';"
mysql -u root --password=$mysql_root_pass --execute="use netdb;GRANT SELECT,INSERT,UPDATE,LOCK TABLES,SHOW VIEW,DELETE ON netdb.* TO 'netdbadmin'@'localhost' IDENTIFIED BY '$mysqluserro';"


# Add netdb perl modules
mkdir /usr/lib64/perl5/Net/
ln -s /opt/netdb/NetDBHelper.pm /usr/lib64/perl5/NetDBHelper.pm
ln -s /opt/netdb/NetDB.pm /usr/lib64/perl5/NetDB.pm

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

#TODO Create virtual host
set_vhost() {
	netdb_vhost=/etc/httpd/conf.d/netdb.conf
	{
		echo "<VirtualHost _default_:80>"
		echo	 "DocumentRoot /var/www/html/netdb/"
		echo	 "ServerName $fqdn"
		echo		"<Directory />"
		echo			"Options FollowSymlinks"
		echo			"AllowOverride None"
		echo 		"</Directory>"
		echo 		"<Directory /var/www/html/netdb>"
		echo			"Options Indexes FollowSymlinks MultiViews"
		echo			"AllowOverride None"
		echo			"Redirect /index.html /cgi-bin/netdb.pl"
		echo			"AuthType basic"
		echo			"AuthName "NetDB Login""
		echo			"AuthUserFile /var/www/html/netdb/netdb.passwd"
		echo			"Require valid-user"
		echo 		"</Directory>"
		echo 	"ScriptAlias /cgi-bin/ /var/www/cgi-bin/"
		echo 		"<Directory "/var/www/cgi-bin">"
		echo 			"Options +ExecCGI -MultiViews +FollowSymlinks"
		echo 			"Allow from all"
		echo 			"AuthType basic"
		echo			"AuthName "NetDB Login""
		echo	 		"AuthUserFile /var/www/html/netdb/netdb.passwd"
		echo	 		"Require valid-user"
		echo 		"</Directory>"
		echo 	"ErrorLog /var/log/httpd/netdb_error.log"
		echo 	"Customlog /var/log/httpd/access.log combined"
		echo "</VirtualHost>"
	} >> "$netdb_vhost"
}

set_vhost()

#TODO Create SSL certificate

#TODO Configure MGRT 

#TODO Add crontab entries, don't forget you need to run it as root to get past the lockfile (temp fix)

# Make Control log available from the Web UI
ln -s /var/log/netdb/control.log /var/www/html/netdb/control.log

# Update document root permission and fire up the web server
chown -R apache:apache /var/www/html/netdb
systemctl enable httpd && systemctl start httpd

# Create firewall rule
firewall-cmd --permanent --add-service=http && firewall-cmd --reload

# Add hostname to /etc/hosts
hostname="$(hostname)"
fqdn="$(hostname --fqdn)"
ipaddr="$(ip -o -4 addr show dev eth0 | sed 's/.* inet \([^/]*\).*/\1/')"
echo  $ipaddr	$hostname >> /etc/hosts

