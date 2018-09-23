-- NetDB v1.8 to v1.9 SQL Upgrade Script

-- To upgrade your database, run these commands from the console (BACKUP FIRST):
--
--  netdbctl -bu /tmp/netdbbackup.sql
--
--  mysql -u root -p netdb (login to netdb with your password)
--  source /opt/netdb/sql/upgrade-v1.7-to-v1.8.sql
--
-- Expect to see Query OK

--
-- Changes added to NetDB v1.10 for upgrades from v1.9
--

ALTER TABLE `nacreg` ADD COLUMN role VARCHAR(30) AFTER mac;

ALTER TABLE `nacreg` ADD COLUMN status VARCHAR(50) AFTER role;

ALTER TABLE `nacreg` MODIFY type VARCHAR(50);

ALTER TABLE `nacreg` ADD COLUMN title VARCHAR(50) AFTER email;

ALTER TABLE `switchports` ADD COLUMN type VARCHAR(30) AFTER mac;

CREATE TABLE `disabled` (
  `mac` varchar(20) NOT NULL PRIMARY KEY,
  `distype` varchar(20) NOT NULL,
  `disuser` varchar(20) NOT NULL,
  `disdata` varchar(100),
  `discase` varchar(30),
  `disdate` datetime NOT NULL,
  `severity` int(10),
  CONSTRAINT FOREIGN KEY (mac) REFERENCES mac (mac) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- netdb metadata
CREATE TABLE `meta` (
  name VARCHAR(50),
  version VARCHAR(50)
) ENGINE=InnoDB;

INSERT into meta set name='netdb',version='1.10';


create or replace view supermac
AS SELECT mac.mac,mac.lastip,ipmac.name,ipmac.vlan,mac.vendor,mac.lastswitch,mac.lastport,mac.firstseen,mac.lastseen,
mac.filtered,mac.note,nacreg.userID,nacreg.firstName,nacreg.lastName,disabled.distype,disabled.disuser,disabled.discase,
disabled.severity,disabled.disdate
FROM mac LEFT JOIN (ipmac) ON (mac.mac=ipmac.mac AND mac.lastip=ipmac.ip) LEFT JOIN (nacreg) ON (mac.mac=nacreg.mac)
LEFT JOIN (disabled) ON (mac.mac=disabled.mac);

create or replace view superswitch
AS select switchports.switch,switchports.port,switchports.type,switchports.mac,ip.ip,ipmac.name,mac.vendor,ipmac.vlan,ip.static,
switchports.firstseen,switchports.lastseen
FROM switchports LEFT JOIN (mac) ON (switchports.mac=mac.mac) LEFT JOIN (ip) ON (mac.lastip=ip.ip)
LEFT JOIN (ipmac) ON (ip.ip=ipmac.ip AND mac.mac=ipmac.mac);

-- End of SQL Revisions