-- NetDB v1.11 to v1.12 SQL Upgrade Script

-- To upgrade your database, run these commands from the console (BACKUP FIRST):
--
--  netdbctl -bu /tmp/netdbbackup.sql
--
--  mysql -u root -p netdb (login to netdb with your password)
--  source /opt/netdb/sql/upgrade-v1.11-to-v1.12.sql
--
-- Expect to see Query OK

--
--

-- Set the new DB version
UPDATE meta SET version='1.12' where name='netdb';

ALTER TABLE `ipmac` ADD COLUMN vrf VARCHAR(40) AFTER vlan;
ALTER TABLE `ipmac` ADD COLUMN router VARCHAR(40) AFTER vrf;
ALTER TABLE `macwatch` ADD COLUMN alertcmd VARCHAR(256) AFTER email;
ALTER TABLE `switchstatus` ADD COLUMN lastup datetime AFTER lastseen;
ALTER TABLE `switchstatus` ADD COLUMN p_minutes INT AFTER lastup;
ALTER TABLE `switchstatus` ADD COLUMN p_uptime VARCHAR(55) AFTER p_minutes;
ALTER TABLE `switchports` ADD COLUMN minutes INT AFTER type;
ALTER TABLE `switchports` ADD COLUMN uptime VARCHAR(55) AFTER minutes;

ALTER TABLE `switchports` ADD COLUMN s_speed VARCHAR(30) AFTER type;
ALTER TABLE `switchports` ADD COLUMN s_ip VARCHAR(32) AFTER type;
ALTER TABLE `switchports` ADD COLUMN s_vlan VARCHAR(20) AFTER type;
ALTER TABLE `mac` ADD COLUMN mac_nd VARCHAR(30) AFTER vendor;

alter table switchstatus modify speed varchar(30);

ALTER TABLE `ipmac` ADD COLUMN ip_minutes INT AFTER lastseen;
ALTER TABLE `ipmac` ADD COLUMN ip_uptime VARCHAR(55) AFTER ip_minutes;



create or replace view supermac
AS SELECT mac.mac,mac.lastip,ipmac.name,ipmac.vlan,ipmac.vrf,ipmac.router,mac.vendor,mac.mac_nd,mac.lastswitch,mac.lastport,
switchstatus.description,switchstatus.status,switchstatus.p_uptime,switchstatus.p_minutes,switchstatus.lastup,
mac.firstseen,mac.lastseen,mac.filtered,mac.note,nacreg.userID,nacreg.firstName,nacreg.lastName,disabled.distype,disabled.disuser,disabled.discase,
disabled.severity,disabled.disdate
FROM mac LEFT JOIN (switchstatus) ON (mac.lastswitch=switchstatus.switch AND mac.lastport=switchstatus.port)
LEFT JOIN (ipmac) ON (mac.mac=ipmac.mac AND mac.lastip=ipmac.ip) LEFT JOIN (nacreg) ON (mac.mac=nacreg.mac)
LEFT JOIN (disabled) ON (mac.mac=disabled.mac);

create or replace view superswitch
AS select sw.switch,sw.port,sw.type,st.description,st.status,sw.uptime,sw.minutes,sw.s_speed,sw.s_ip,sw.s_vlan,
st.p_uptime,st.p_minutes,st.lastup,sw.mac,sw.firstseen,sw.lastseen,
ip.ip,ipmac.name,mac.vendor,mac.mac_nd,ipmac.vlan,ipmac.vrf,ipmac.router,ip.static,
nd.n_host,nd.n_ip,nd.n_desc,nd.n_model,nd.n_port,nd.n_protocol,nd.n_lastseen
FROM switchports AS sw LEFT JOIN (switchstatus AS st) ON (sw.switch=st.switch AND sw.port=st.port)
LEFT JOIN (neighbor AS nd) ON (sw.switch=nd.switch AND sw.port=nd.port)
LEFT JOIN (mac) ON (sw.mac=mac.mac) LEFT JOIN (ip) ON (mac.lastip=ip.ip)
LEFT JOIN (ipmac) ON (ip.ip=ipmac.ip AND mac.mac=ipmac.mac);

create or replace view superarp
AS select ipmac.ip,ipmac.mac,ipmac.name,ipmac.firstseen,ipmac.lastseen,ipmac.vlan,ipmac.vrf,ipmac.router,ip.static,mac.lastswitch,mac.lastport,mac.vendor,
mac.mac_nd,mac.filtered,mac.note,nacreg.userID,nacreg.firstName,nacreg.lastName
FROM ipmac LEFT JOIN (ip) ON (ipmac.ip=ip.ip) LEFT JOIN (mac) ON (ipmac.mac=mac.mac) LEFT JOIN (nacreg) ON (ipmac.mac=nacreg.mac);

-- End of SQL Revisions
