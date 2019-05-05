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
NIC="$(ip route show | grep default | awk '{ print $5 }')"
IP_ADDR="$(ip -o -4 addr show dev $NIC | sed 's/.* inet \([^/]*\).*/\1/')"
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
perl-List-MoreUtils perl-DBI perl-Net-DNS perl-Math-Round perl-Module-Implementation perl-Data-UUID \
perl-Params-Validate perl-DateTime-Locale perl-DateTime-TimeZone perl-DateTime perl-JSON-PP \
perl-DateTime-Format-MySQL perl-Time-HiRes perl-Digest-HMAC perl-Digest-SHA1 perl-Net-SSLeay \
perl-Net-IP perl-AppConfig perl-Proc-Queue perl-Proc-ProcessTable perl-NetAddr-IP perl-IO-Socket-IP wget \
perl-IO-Socket-INET6 perl-ExtUtils-CBuilder perl-Socket perl-YAML perl-CGI perl-CPAN expect mod_ssl git expect

#TODO Create a function to kill the script if all a packages are not installed

# Install remaining perl modules use '-f' to force the installtion of File::Flock 
# Need to convert this module to RPM and submit it to EPEL
echo "Installing NetDB Perl dependencies..."
for mod in Net::MAC::Vendor Net::SSH::Expect Attribute::Handlers File::Flock ExtUtils::Constant
do y|cpan -f $mod
done

# Create netdb user
#TODO Have netdb function as a regular user
echo "Creating netdb user..."
useradd netdb && usermod -aG wheel netdb

#TODO have this process replaced by git clone <url> /opt/
echo "Clonning git repository..."
git clone https://github.com/EarlRamirez/netdb.git /opt/netdb


#TODO Create a function if git clone fails
chown -R netdb.netdb /opt/netdb
mkdir -pv /var/log/netdb
chown -R netdb.apache /var/log/netdb

# Create symbolic links
ln -s /opt/netdb/netdb.pl /usr/local/bin/netdb
ln -s /opt/netdb/netdbctl.pl /usr/local/bin/netdbctl

# Copy netdb-logrotate script 
cp /opt/netdb/extra/netdb-logrotate /etc/logrotate.d/

# Configure MariaDB
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

# Add netdb perl modules
echo "Setting up NetDB directories and Symlinks"
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

# Add netdb credentials
echo "NetDB credentials"
sed -i 's,^\(dbpass   = \).*,\1'$MYSQL_USER_RW',' "/etc/netdb.conf"
sed -i 's,^\(dbpassRO = \).*,\1'$MYSQL_USER_RO',' "/etc/netdb.conf"

# Configure MRTG
echo "Configuring MRTG..."
mv /etc/mrtg/mrtg.cfg /etc/mrtg/mrtg.cfg.bkp
cp /opt/netdb/extra/mrtg.cfg /etc/mrtg/mrtg.cfg
cp -r /opt/netdb/extra/mrtg /var/www/html/netdb/
cp /opt/netdb/extra/mrtg_cron /etc/cron.d/mrtg
rm -rf /var/www/mrtg
indexmaker --title="NetDB Graphs" --show=week /opt/netdb/extra/mrtg.cfg > /var/www/html/netdb/mrtg/index.html
sed -i 's,Alias \/mrtg \/var\/www\/mrtg, Alias \/mrtg \/var\/www\/html\/netdb\/mrtg,g' /etc/httpd/conf.d/mrtg.conf
sed -i 's,Require local,Require ip 10.0.0.0\/18 172.16.0.0\/16 192.168.0.0\/16,g' /etc/httpd/conf.d/mrtg.conf

# Create netdb web UI credentials
touch /var/www/html/netdb/netdb.passwd
echo "Enter your netdb web UI password"
htpasswd -c -B /var/www/html/netdb/netdb.passwd netdb

# Create SSL Self-signed certificate
echo "Creating self-signed SSL certificate...."
GEN_CERT="openssl req -x509 -nodes -days 1095 -newkey rsa:2048 -keyout /etc/pki/tls/private/netdb-selfsigned.key -out /etc/pki/tls/certs/netdb-selfsigned.crt"
		
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

# Append DH parameters to the certificate
echo "Appening DH Parameters to Certificate"
cat /etc/ssl/certs/dhparam.pem | sudo tee -a /etc/ssl/certs/netdb-selfsigned.crt
echo ""

# Create virtual host
echo "Creating NetDB virtual host"
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

#TODO Create a netdb cron and place it in /etc/cron.d/
echo "Adding cron jobs"
echo "#######################################" >> /etc/crontab
echo "# NetDB Cron Jobs						 " >> /etc/crontab
echo "#######################################" >> /etc/crontab
echo "" >> /etc/crontab
echo "# Update NetDB MAC and ARP table data" >> /etc/crontab
echo "*/15 * * * * netdb /opt/netdb/netdbctl.pl -ud -a -m -nd > /dev/null" >> /etc/crontab
echo "" >> /etc/crontab
echo "# Update static address flag from DHCP, relies on file to be up to date" >> /etc/crontab
echo "35 * * * * netdb /opt/netdb/netdbctl.pl -s  > /dev/null" >> /etc/crontab
echo "" >> /etc/crontab
echo "# Force DNS updates on all current ARP entries once a day" >> /etc/crontab
echo "5 13 * * * netdb /opt/netdb/netdbctl.pl -f > /dev/null" >> /etc/crontab
echo "" >> /etc/crontab
echo "# Cleanup netdb's SSH known_host file automatically (uncomment)" >> /etc/crontab
echo "00 5 * * * netdb rm -rf /home/netdb/.ssh/known_hosts 2> /dev/null" >> /etc/crontab
echo "" >> /etc/crontab
echo "# Update statistics for graphs if enabled, run before MRTG" >> /etc/crontab
echo "*/5 * * * * netdb /opt/netdb/extra/update-statistics.sh > /dev/null" >> /etc/crontab
echo "" >> /etc/crontab
echo "# Update MAC Vendor Database from IEEE monthly" >> /etc/crontab
echo "00 5 15 * * netdb wget http://standards-oui.ieee.org/oui/oui.txt -O /opt/netdb/data/oui.txt" >> /etc/crontab
echo "" >> /etc/crontab
echo "#### End Cron Jobs #####" >> /etc/crontab

# Make Control log available from the Web UI
ln -s /var/log/netdb/control.log /var/www/html/netdb/control.log

# Update document root permission and fire up the web server
echo "Updating NetDB document root permissions"
chown -R apache:apache /var/www/html/netdb
restorecon -Rv /var/www/html

# Fix Apache error AH00558
echo "ServerName  localhost" >> /etc/httpd/conf/httpd.conf

# Start httpd and create firewall rule
echo "Starting httpd and permitting port and 443"
firewall-cmd --permanent --add-service=https && firewall-cmd --reload
systemctl enable httpd && systemctl start httpd

# Add hostname to /etc/hosts
echo "Patching hosts file.."
echo  "$IP_ADDR	$HOSTNAME" >> /etc/hosts

# Creat Lock directory
echo "Creating lock directory"
mkdir -pv /var/lock/netdb
chown -R netdb.netdb /var/lock/netdb

# Fix MRTG SELinux error 
echo "Modifying SELinux permissions"
chcon -R -t mrtg_etc_t /etc/mrtg
restorecon -Rv /etc/mrtg
semodule -i /opt/netdb/extra/my-mrtg.pp

echo ""
echo "Script completed"
echo ""
echo "Point your browser to https://$IP_ADDR to access the web UI"
