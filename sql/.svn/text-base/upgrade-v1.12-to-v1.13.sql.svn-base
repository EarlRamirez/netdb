-- NetDB v1.12 to v1.13 SQL Upgrade Script

-- To upgrade your database, run these commands from the console (BACKUP FIRST):
--
--  netdbctl -bu /tmp/netdbbackup.sql
--
--  mysql -u root -p netdb (login to netdb with your password)
--  source /opt/netdb/sql/upgrade-v1.12-to-v1.13.sql
--
-- Expect to see Query OK

--
--

-- Set the new DB version
UPDATE meta SET version='1.13' where name='netdb';

alter table nacreg modify userID varchar(30);
ALTER TABLE nacreg ADD COLUMN pod VARCHAR(25);
ALTER TABLE nacreg ADD COLUMN dbid INT;

ALTER TABLE switchports ADD COLUMN s_name VARCHAR(100) AFTER s_ip;

ALTER TABLE mac ADD COLUMN lastipseen datetime AFTER lastseen;

create or replace view superswitch
AS select sw.switch,sw.port,sw.type,st.description,st.status,sw.uptime,sw.minutes,sw.s_speed,sw.s_ip,sw.s_name,sw.s_vlan,
st.p_uptime,st.p_minutes,st.lastup,sw.mac,sw.firstseen,sw.lastseen,
ip.ip,ipmac.name,mac.vendor,mac.mac_nd,ipmac.vlan,ipmac.vrf,ipmac.router,ip.static,
nd.n_host,nd.n_ip,nd.n_desc,nd.n_model,nd.n_port,nd.n_protocol,nd.n_lastseen
FROM switchports AS sw LEFT JOIN (switchstatus AS st) ON (sw.switch=st.switch AND sw.port=st.port)
LEFT JOIN (neighbor AS nd) ON (sw.switch=nd.switch AND sw.port=nd.port)
LEFT JOIN (mac) ON (sw.mac=mac.mac) LEFT JOIN (ip) ON (mac.lastip=ip.ip)
LEFT JOIN (ipmac) ON (ip.ip=ipmac.ip AND mac.mac=ipmac.mac);

create or replace view supermac
AS SELECT mac.mac,mac.lastip,mac.lastipseen,ipmac.name,ipmac.vlan,ipmac.vrf,ipmac.router,mac.vendor,mac.mac_nd,mac.lastswitch,mac.lastport,
switchstatus.description,switchstatus.status,switchstatus.p_uptime,switchstatus.p_minutes,switchstatus.lastup,
mac.firstseen,mac.lastseen,mac.filtered,mac.note,nacreg.userID,nacreg.firstName,nacreg.lastName,nacreg.type,disabled.distype,disabled.disuser,disabled.discase,
disabled.severity,disabled.disdate
FROM mac LEFT JOIN (switchstatus) ON (mac.lastswitch=switchstatus.switch AND mac.lastport=switchstatus.port)
LEFT JOIN (ipmac) ON (mac.mac=ipmac.mac AND mac.lastip=ipmac.ip) LEFT JOIN (nacreg) ON (mac.mac=nacreg.mac)
LEFT JOIN (disabled) ON (mac.mac=disabled.mac);

create or replace view superarp
AS select ipmac.ip,ipmac.mac,ipmac.name,ipmac.firstseen,ipmac.lastseen,ipmac.vlan,ipmac.vrf,ipmac.router,ip.static,
mac.lastswitch,mac.lastport,st.description,st.status,
mac.vendor,mac.mac_nd,mac.filtered,mac.note,nacreg.userID,nacreg.firstName,nacreg.lastName
FROM ipmac LEFT JOIN (ip) ON (ipmac.ip=ip.ip) LEFT JOIN (mac) ON (ipmac.mac=mac.mac)
LEFT JOIN (nacreg) ON (ipmac.mac=nacreg.mac) LEFT JOIN (switchstatus AS st) ON (mac.lastswitch=st.switch AND mac.lastport=st.port);


-- End of SQL Revisions
