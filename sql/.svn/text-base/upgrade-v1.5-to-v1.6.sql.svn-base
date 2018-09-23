-- Changes to the database that need to be applied depending on what version you are running.  
-- To import, run these commands:
-- mysql -u root -p (login with your password)
-- use netdb
-- source /opt/netdb/sql/upgrade-v1.5-to-v1.6.sql
--
-- Expect to see Query OK

--
-- Changes added to NetDB v1.6 for upgrades from v1.5
--

create or replace view supermac
AS SELECT mac.mac,mac.lastip,ipmac.name,ipmac.vlan,mac.vendor,mac.lastswitch,mac.lastport,mac.firstseen,mac.lastseen,mac.macauth,nacreg.userID,nacreg.firstName,nacreg.lastName
FROM mac LEFT JOIN (ipmac) ON (mac.mac=ipmac.mac AND mac.lastip=ipmac.ip) LEFT JOIN (nacreg) ON (mac.mac=nacreg.mac);

create or replace view superarp 
AS select ipmac.ip,ipmac.mac,ipmac.name,ipmac.firstseen,ipmac.lastseen,ipmac.vlan,ip.static,mac.lastswitch,mac.lastport,mac.vendor,nacreg.userID,nacreg.firstName,nacreg.lastName 
FROM ipmac LEFT JOIN (ip) ON (ipmac.ip=ip.ip) LEFT JOIN (mac) ON (ipmac.mac=mac.mac) LEFT JOIN (nacreg) ON (ipmac.mac=nacreg.mac);


CREATE TABLE `nacreg` (
  `mac` varchar(20) NOT NULL PRIMARY KEY,
  `time` datetime NOT NULL,
  `firstName` varchar(50),
  `lastName` varchar(50),
  `userID` varchar(12) NOT NULL,
  `email` varchar(30),
  `phone` varchar(12),
  `type` varchar(30),
  `entity` varchar(50),
  `critical` INT(10),
  CONSTRAINT FOREIGN KEY (mac) REFERENCES mac (mac) ON DELETE CASCADE ON UPDATE CASCADE,
  KEY `user_idx` (`userID`)
) ENGINE=InnoDB;

-- End of SQL Revisions

