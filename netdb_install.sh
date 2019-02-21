#!/bin/bash

# Install and Configure NetDB on CentOS/RHEL Linux
# This script aims to automate the installation of NetDB and potentially use it for docker containers.
#TODO Configure installation logging

# Variables
COUNTRY_NAME=US
STATE=Florida
LOCALITY=Miami
ORGANISATION=Networking
ORGANISATION_UNIT=NetworkTracking
EMAIL=netdb@localdomain.com
HOSTNAME="$(hostname)"
FQDN="$(hostname --fqdn)"
IP_ADDR="$(ip -o -4 addr show dev eth0 | sed 's/.* inet \([^/]*\).*/\1/')"
MYSQL_ROOT=""
echo "Enter your MariaDB new root password: "
read -rs MYSQL_ROOT_PASS
echo "Enter netdb MariaDB RW password: "
read -rs MYSQL_USER_RW
echo "Enter netdb MariaDB RO password: "
read -rs MYSQL_USER_RO

# Add EPEL Repository and install packages
echo "Installing EPEL Repo..."
yum -y install epel-release

echo "Installing NetDB Packages...."
yum install -y gcc unzip make bzip2 curl lynx ftp patch mariadb mariadb-server httpd httpd-tools perl mrtg \
perl-List-MoreUtils perl-DBI perl-Net-DNS perl-Math-Round perl-Module-Implementation \
perl-Params-Validate perl-DateTime-Locale perl-DateTime-TimeZone perl-DateTime \
perl-DateTime-Format-MySQL perl-Time-HiRes perl-Digest-HMAC perl-Digest-SHA1 \
perl-Net-IP perl-AppConfig perl-Proc-Queue perl-Proc-ProcessTable perl-NetAddr-IP perl-IO-Socket-IP \
perl-IO-Socket-INET6 perl-ExtUtils-CBuilder perl-Socket perl-YAML perl-CGI perl-CPAN expect mod_ssl git expect

# Install remaining perl modules use '-f' to force the installtion of File::Flock
echo "Installing NetDB Perl dependencies..."
for mod in Attribute::Handlers Data::UUID Net::MAC::Vendor Net::SSH::Expect File::Flock ExtUtils::Constant
do y|cpan -f $mod
done;

# Create netdb user
#TODO Have netdb function as a regular user
echo "Creating netdb user..."
useradd netdb && usermod -aG wheel netdb


#TODO have this process replaced by git clone <url> /opt/
echo "Clonning git repository..."
git clone https://github.com/EarlRamirez/netdb.git /opt/netdb
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
echo "Starting and configuring MariaDB..."
systemctl enable mariadb && systemctl start mariadb

# Automated configuration for securing MySQL/MariaDB		
		echo "* Securing MariaDB."
		SECURE_MYSQL=$(expect -c "
		set timeout 10
		spawn /bin/mysql_secure_installation
		expect \"Enter current password for root (enter for none):\"
		send \"$MYSQL_ROOT\r\"
		expect \"Change the root password?\"
		send \"y\r\"
		expect \"New password:\"
		send \"$MYSQL_ROOT_PASS\r\"
		expect \"Re-enter new password:\"
		send \"$MYSQL_ROOT_PASS\r\"
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

# Create DB tables and users 
echo "Creating the database and tables...."
mysql -u root --password=$MYSQL_ROOT_PASS --execute="create database if not exists netdb"
mysql -u root --password=$MYSQL_ROOT_PASS netdb < /opt/netdb/createnetdb.sql
mysql -u root --password=$MYSQL_ROOT_PASS --execute="use netdb;GRANT ALL PRIVILEGES ON netdb.* TO netdbadmin@localhost IDENTIFIED BY '$MYSQL_USER_RW';"
mysql -u root --password=$MYSQL_ROOT_PASS --execute="use netdb;GRANT SELECT,INSERT,UPDATE,LOCK TABLES,SHOW VIEW,DELETE ON netdb.* TO 'netdbuser'@'localhost' IDENTIFIED BY '$MYSQL_USER_RO';"

#TODO Update /etc/netdb.conf with credentials

# Add netdb perl modules
mkdir /usr/lib64/perl5/Net/
ln -s /opt/netdb/NetDBHelper.pm /usr/lib64/perl5/NetDBHelper.pm
ln -s /opt/netdb/NetDB.pm /usr/lib64/perl5/NetDB.pm

# Create directories and copy required files
cp /opt/netdb/netdb.conf /etc/
touch /opt/netdb/data/devicelist.csv
mkdir -pv /var/www/html/netdb
cp /opt/netdb/netdb-cgi.conf /etc/
touch /var/www/html/netdb/netdbReport.csv
cp -r /opt/netdb/extra/depends /var/www/html/netdb/
cp /opt/netdb/netdb.cgi.pl /var/www/cgi-bin/netdb.pl

#TODO Configure MRTG virtual host, update alias path and trusted network
mv /etc/mrtg/mrtg.cfg /etc/mrtg/mrtg.cfg.bkp
cp /opt/netdb/extra/mrtg.cfg /etc/mrtg/mrtg.cfg
cp -r /opt/netdb/extra/mrtg /var/www/html/netdb/
rm -rf /var/www/mrtg
indexmaker --title="NetDB Graphs" --show=week /opt/netdb/extra/mrtg.cfg > /var/www/html/netdb/mrtg/index.html


# Create netdb web UI credentials
#TODO replace with DB credentials
touch /var/www/html/netdb/netdb.passwd
echo "Enter your netdb web UI password"
htpasswd -c -B /var/www/html/netdb/netdb.passwd netdb

# Create SSL Self-signed certificate
echo "Creating self-signed SSL certificate...."
GEN_CERT="openssl req -x509 -nodes -days 1095 -newkey rsa:2048 -keyout /etc/pki/tls/private/netdb-selfsigned.key -out /etc/pki/tls/certs/netdb-selfsigned.crt"

# Automated configuration for securing MySQL/MariaDB		
echo "* Generate Self-Signed Certificate."
GENERATE_CERT=$(expect -c "
	set timeout 10
	spawn $GEN_CERT
	expect \"Country Name (2 letter code) \[XX\]:\"
	send \"$COUNTRY_NAME\r\"
	expect \"State or Province Name (full name) \[\]:\"
	send \"$STATE\r\"
	expect \"Locality Name (eg, city) \[Default City\]:\"
	send \"$LOCALITY\r\"
	expect \"Organization Name (eg, company) \[Default Company Ltd\]:\"
	send \"$ORGANISATION\r\"
	expect \"Organizational Unit Name (eg, section) \[\]:\"
	send \"$ORGANISATION_UNIT\r\"
	expect \"Common Name (eg, your name or your server's hostname) \[\]:\"
	send \"$HOSTNAME\r\"
	expect \"Email Address \[\]:\"
	send \"$EMAIL\r\"
	expect eof
")
echo "$GENERATE_CERT"

echo ""

# Create Diffie-Hellman group
echo "Generate DH Parameters"
openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048
echo ""

# Append SSLOpenSSLConfCmd to the certificate
echo "Appening DH Parameters to Certificate"
cat /etc/ssl/certs/dhparam.pem | sudo tee -a /etc/ssl/certs/netdb-selfsigned.crt
echo ""


#TODO Create virtual host and replace Apache with Nginx
set_vhost() {
	netdb_vhost=/etc/httpd/conf.d/netdb.conf
	{
		echo "<VirtualHost _default_:443>"
		echo "   DocumentRoot /var/www/html/netdb/"
		echo "	 ServerName $FQDN"
		echo "	   <Directory />"
		echo "		  Options FollowSymlinks"
		echo "		  AllowOverride None"
		echo " 	   </Directory>"
		echo " 	   <Directory /var/www/html/netdb>"
		echo "	      Options -Indexes +FollowSymlinks +MultiViews"
		echo "		  AllowOverride None"
		echo "		  Redirect /index.html /cgi-bin/netdb.pl"
		echo "		  AuthType basic"
		echo '		  AuthName "NetDB Login"'
		echo "		  AuthUserFile /var/www/html/netdb/netdb.passwd"
		echo "		  Require valid-user"
		echo " 	   </Directory>"
		echo " 	ScriptAlias /cgi-bin/ /var/www/cgi-bin/"
		echo " 	   <Directory "/var/www/cgi-bin">"
		echo " 		  Options +ExecCGI -MultiViews +FollowSymlinks"
		echo " 		  Allow from all"
		echo " 		  AuthType basic"
		echo '		  AuthName "NetDB Login"'
		echo "	 	  AuthUserFile /var/www/html/netdb/netdb.passwd"
		echo "	 	  Require valid-user"
		echo " 	   </Directory>"
		echo " 	ErrorLog /var/log/httpd/netdb_error.log"
		echo " 	Customlog /var/log/httpd/access.log combined"
        echo " 	SSLEngine on"
        echo " 	SSLCertificateFile /etc/pki/tls/certs/netdb-selfsigned.crt"
        echo " 	SSLCertificateKeyFile /etc/pki/tls/private/netdb-selfsigned.key"
        echo " 	SSLProtocol -SSLv3 -TLSv1 TLSv1.1 TLSv1.2"
        echo " 	SSLHonorCipherOrder On"
        echo " 	SSLCipherSuite ALL:!EXP:!NULL:!ADH:!LOW:!SSLv2:!SSLv3:!MD5:!RC4"
		echo "</VirtualHost>"
	} >> "$netdb_vhost"
}

set_vhost

#TODO Add crontab entries, don't forget you need to run it as root to get past the lockfile (temp fix)

# Make Control log available from the Web UI
ln -s /var/log/netdb/control.log /var/www/html/netdb/control.log

# Update document root permission and fire up the web server
echo "Updating NetDB document root permissions"
chown -R apache:apache /var/www/html/netdb
restorecon -Rv /var/www/html
systemctl enable httpd && systemctl start httpd

# Create firewall rule
echo "Permitting port and 443"
firewall-cmd --permanent --add-service=https && firewall-cmd --reload

# Add hostname to /etc/hosts
echo  $IP_ADDR	$hostname >> /etc/hosts

echo "Point your browser to https://$IP_ADDR to access the web UI"

#TODO update OUI link in crontab
#TODO [Fix] (https://sourceforge.net/p/netdbtracking/discussion/939988/thread/77fbf56a/)


