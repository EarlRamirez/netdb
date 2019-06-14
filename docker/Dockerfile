FROM centos:7
MAINTAINER Earl Ramirez <earlaramirez@gmail.com>

RUN yum -y install epel-release && yum clean all

RUN yum -y --setop=tsflags=nodocs update \
	&& yum -y --setop=tsflags=nodocs install gcc \
	--setop=tsflags=nodocs unzip \
	--setop=tsflags=nodocs make \
	--setop=tsflags=nodocs bzip2 \
	--setop=tsflags=nodocs curl \
	--setop=tsflags=nodocs lynx \
	--setop=tsflags=nodocs ftp \
	--setop=tsflags=nodocs patch \
	--setop=tsflags=nodocs httpd \
	--setop=tsflags=nodocs httpd-tools \
	--setop=tsflags=nodocs perl \
	--setop=tsflags=nodocs perl-List-MoreUtils \
	--setop=tsflags=nodocs perl-DBI \ 
	--setop=tsflags=nodocs perl-Net-DNS \
	--setop=tsflags=nodocs perl-Math-Round \
	--setop=tsflags=nodocs perl-Module-Implementation \
	--setop=tsflags=nodocs perl-Params-Validate \
	--setop=tsflags=nodocs perl-DateTime-Locale \
	--setop=tsflags=nodocs perl-DateTime-TimeZone \
	--setop=tsflags=nodocs perl-DateTime \
	--setop=tsflags=nodocs perl-DateTime-Format-MySQL \
	--setop=tsflags=nodocs perl-Time-HiRes \
	--setop=tsflags=nodocs perl-Digest-HMAC \
	--setop=tsflags=nodocs perl-Digest-SHA1 \
	--setop=tsflags=nodocs perl-Net-IP \
	--setop=tsflags=nodocs perl-AppConfig \
	--setop=tsflags=nodocs perl-Proc-Queue \
	--setop=tsflags=nodocs perl-Proc-ProcessTable \
	--setop=tsflags=nodocs perl-NetAddr-IP \
	--setop=tsflags=nodocs perl-IO-Socket-IP wget \
	--setop=tsflags=nodocs perl-IO-Socket-INET6 \
	--setop=tsflags=nodocs perl-ExtUtils-CBuilder \
	--setop=tsflags=nodocs perl-Socket \
	--setop=tsflags=nodocs perl-YAML \
	--setop=tsflags=nodocs perl-CGI \
	--setop=tsflags=nodocs perl-CPAN \
	--setop=tsflags=nodocs mod_ssl \
	--setop=tsflags=nodocs git  \
	--setop=tsflags=nodocs cronie \
	--setop=tsflags=nodocs perl-App-cpanminus \
	&& yum clean all

RUN cpanm -f Attribute::Handlers \
	&& cpanm -f Data::UUID \
	&& cpanm -f Net::MAC::Vendor \
	&& cpanm -f Net::SSH::Expect \
	&& cpanm -f File::Flock \
	&& cpanm -f ExtUtils::Constant

RUN useradd netdb && usermod -aG wheel netdb 

RUN git clone https://github.com/EarlRamirez/netdb.git /opt/netdb \
	&& chown -R netdb.netdb /opt/netdb \
	&& mkdir -pv /var/log/netdb \
	&& chown -R netdb.apache /var/log/netdb \
	&& ln -s /opt/netdb/netdb.pl /usr/local/bin/netdb \
	&& ln -s /opt/netdb/netdbctl.pl /usr/local/bin/netdbctl \
	&& cp /opt/netdb/extra/netdb-logrotate /etc/logrotate.d/ \
	&& mkdir /usr/lib64/perl5/Net/ \
	&& ln -s /opt/netdb/NetDBHelper.pm /usr/lib64/perl5/NetDBHelper.pm \
	&& ln -s /opt/netdb/NetDB.pm /usr/lib64/perl5/NetDB.pm \
	&& cp /opt/netdb/netdb.conf /etc/ \
	&& touch /opt/netdb/data/devicelist.csv \
	&& mkdir -pv /var/www/html/netdb \
	&& cp /opt/netdb/netdb-cgi.conf /etc/ \
	&& touch /var/www/html/netdb/netdbReport.csv \
	&& cp -r /opt/netdb/extra/depends /var/www/html/netdb/ \
	&& cp /opt/netdb/netdb.cgi.pl /var/www/cgi-bin/netdb.pl \ 
	&& mkdir -pv /var/lock/netdb \
	&& chown -R netdb.netdb /var/lock/netdb \
	&& echo "ServerName localhost" >> /etc/httpd/conf/httpd.conf \
	&& rm -rf /usr/share/backgrounds 

ADD netdb.conf /etc/httpd/conf.d/netdb.conf
ADD netdb_crontab /etc/cron.d/
ADD netdb.passwd /var/www/html/netdb/

ADD entrypoint.sh /entrypoint.sh
RUN chmod -v +x /entrypoint.sh

ENTRYPOINT ["/usr/sbin/crond"]

CMD ["/entrypoint.sh"]

EXPOSE 80
