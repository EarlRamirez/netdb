-- NetDB v1.10 to v1.11 SQL Upgrade Script

-- To upgrade your database, run these commands from the console (BACKUP FIRST):
--
--  netdbctl -bu /tmp/netdbbackup.sql
--
--  mysql -u root -p netdb (login to netdb with your password)
--  source /opt/netdb/sql/upgrade-v1.10-to-v1.11.sql
--
-- Expect to see Query OK

--
-- Changes added to NetDB v1.11 for upgrades from v1.10
--

-- Set the new DB version
UPDATE meta SET version='1.11' where name='netdb';

ALTER TABLE `nacreg` MODIFY type VARCHAR(150);

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


-- neighbor table
CREATE TABLE `neighbor` (
  `switch` varchar(100) NOT NULL,
  `port` varchar(30) NOT NULL,
  `n_ip` VARCHAR(32),
  `n_host` VARCHAR(100),
  `n_desc` VARCHAR(2000),
  `n_model` VARCHAR(100),
  `n_port` VARCHAR(30),
  `n_protocol` varchar(10),
  `n_lastseen` datetime NOT NULL,
  CONSTRAINT FOREIGN KEY ( switch, port ) REFERENCES switchstatus ( switch, port ) ON DELETE CASCADE ON UPDATE CASCADE,
  PRIMARY KEY ( switch, port )
) ENGINE=InnoDB;


CREATE TABLE `macwatch` (
  `mac` varchar(20) NOT NULL,
  `active` BOOL,
  `entered` datetime NOT NULL,
  `enteruser` varchar(20) NOT NULL,
  `note` varchar(256) NOT NULL,
  `found` BOOL,
  `foundon` datetime,
  `foundby` varchar(20),
  `foundnote` varchar(160),
  `lastalert` datetime,
  `switch` varchar(100),
  `email` varchar(384),
  PRIMARY KEY  (`mac`),
  KEY `entered_idx` (`entered`),
  KEY `foundon_idx` (`foundon`)
) ENGINE=InnoDB;


-- End of SQL Revisions
