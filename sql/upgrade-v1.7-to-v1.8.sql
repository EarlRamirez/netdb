-- NetDB v1.7 to v1.8 SQL Upgrade Script

-- To upgrade your database, run these commands from the console (BACKUP FIRST):
--
--  mysql -u root -p (login with your password)
--  use netdb
--  source /opt/netdb/sql/upgrade-v1.7-to-v1.8.sql
--
-- Expect to see Query OK

--
-- Changes added to NetDB v1.8 for upgrades from v1.7
--

-- fix transactions table
alter table transactions modify id varchar(50);

-- support for extended descriptions
alter table switchstatus modify description varchar(150);

-- drop macauth column from mac
alter table mac drop column macauth;
drop view if exists macauth;

-- add filtered column
alter table mac add column filtered INT(10);

-- add note column
alter table mac add column note VARCHAR(140);

-- speed and duplex
alter table switchstatus add column speed varchar(20);
alter table switchstatus add column duplex varchar(20);


-- Fix the supermac and superarp view
create or replace view supermac
AS SELECT mac.mac,mac.lastip,ipmac.name,ipmac.vlan,mac.vendor,mac.lastswitch,mac.lastport,mac.firstseen,mac.lastseen,
mac.filtered,mac.note,nacreg.userID,nacreg.firstName,nacreg.lastName
FROM mac LEFT JOIN (ipmac) ON (mac.mac=ipmac.mac AND mac.lastip=ipmac.ip) LEFT JOIN (nacreg) ON (mac.mac=nacreg.mac);

create or replace view superarp
AS select ipmac.ip,ipmac.mac,ipmac.name,ipmac.firstseen,ipmac.lastseen,ipmac.vlan,ip.static,mac.lastswitch,mac.lastport,mac.vendor,
mac.filtered,mac.note,nacreg.userID,nacreg.firstName,nacreg.lastName
FROM ipmac LEFT JOIN (ip) ON (ipmac.ip=ip.ip) LEFT JOIN (mac) ON (ipmac.mac=mac.mac) LEFT JOIN (nacreg) ON (ipmac.mac=nacreg.mac);


-- End of SQL Revisions

