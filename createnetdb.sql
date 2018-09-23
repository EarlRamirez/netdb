-- Create the NetDB Database from scratch
-- Use as source file on newly created database

-- About:
-- Database is normalized for fast updates.  Reports rely on database
-- views to generate reports.  There are also foreign key contraints
-- so that a mac address must exist in the mac table to be added to the
-- ipmac or switchports table.  Primary keys and indexes are ordered
-- for performance.

-- DROP DATABASE netdb;
-- CREATE DATABASE netdb;
-- use netdb;

-- ip table
CREATE TABLE ip (
        ip VARCHAR(32) NOT NULL,
        static TINYINT,
        lastmac VARCHAR(20),
        owner  VARCHAR(30),
        PRIMARY KEY (ip)
) ENGINE=INNODB;

-- mac table
CREATE TABLE mac (
	mac VARCHAR(20) NOT NULL,
	lastip VARCHAR(32),
        lastswitch VARCHAR(100),
        lastport   VARCHAR(50),
	vendor varchar(50),
	mac_nd varchar(30),
	firstseen datetime,
        lastseen datetime,
	lastipseen datetime,
        filtered INT(10),
	note VARCHAR(140),
	PRIMARY KEY (mac)
) ENGINE=INNODB;



-- arp table
CREATE TABLE ipmac (
	ip VARCHAR(32) NOT NULL,
	mac VARCHAR(20) NOT NULL,
	name VARCHAR(100),
	firstseen DATETIME,
	lastseen DATETIME,
        `ip_minutes` INT,
        `ip_uptime` varchar(55),
	vlan INT(11),
	vrf VARCHAR(40),
	router VARCHAR(40),
	CONSTRAINT FOREIGN KEY (ip) REFERENCES ip (ip) ON DELETE CASCADE ON UPDATE CASCADE,
        CONSTRAINT FOREIGN KEY (mac) REFERENCES mac (mac) ON DELETE CASCADE ON UPDATE CASCADE,
        PRIMARY KEY (ip, mac),
        KEY `name_idx` (`name`),
        KEY `vlan_idx` (`vlan`)
) ENGINE=INNODB;

-- mac table data from switches
CREATE TABLE `switchports` (
  `switch` varchar(100) NOT NULL,
  `port` varchar(30) NOT NULL,
  `mac` varchar(20) NOT NULL,
  `type` varchar(30),
  `s_vlan` varchar(20),
  `s_ip` varchar(32),
  `s_name` varchar(100),
  `s_speed` varchar(30),
  `minutes` INT,
  `uptime` varchar(55),
  `firstseen` datetime NOT NULL,
  `lastseen` datetime NOT NULL,
  PRIMARY KEY  (`switch`, `port`, `mac`),
  KEY `mac_idx` (`mac`),
  CONSTRAINT FOREIGN KEY (`mac`) REFERENCES `mac` (`mac`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Necessary for Join performance (fixed, reordered primary key)
-- create index sp_index using btree on switchports (switch,port);

-- interface status data from switches
CREATE TABLE `switchstatus` (
  `switch` varchar(100) NOT NULL,
  `port` varchar(30) NOT NULL,
  `vlan` varchar(15),
  `status` varchar(20) NOT NULL,
  `speed` varchar(30),
  `duplex` varchar(20),
  `description` varchar(150),
  `lastseen` datetime NOT NULL,
  `lastup` datetime,
  `p_minutes` INT,
  `p_uptime` varchar(55),
  PRIMARY KEY  (`switch`, `port`),
  KEY `vlan_idx` (`vlan`)
) ENGINE=InnoDB;

-- optional nac registration data
CREATE TABLE `nacreg` (
  `mac` varchar(20) NOT NULL PRIMARY KEY,
  `role` varchar(30),
  `status` varchar(50),
  `time` datetime NOT NULL,
  `firstName` varchar(50),
  `lastName` varchar(50),
  `userID` varchar(30) NOT NULL,
  `email` varchar(30),
  `title` varchar(50),
  `phone` varchar(12),
  `type` varchar(150),
  `entity` varchar(50),
  `critical` INT(10),
  `pod` varchar(25),
  `dbid` INT,
  CONSTRAINT FOREIGN KEY (mac) REFERENCES mac (mac) ON DELETE CASCADE ON UPDATE CASCADE,
  KEY `user_idx` (`userID`)
) ENGINE=InnoDB;

-- disabled table for shutdown devices
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


-- netdb user queries logging
CREATE TABLE `transactions` (
  id VARCHAR(50) NOT NULL PRIMARY KEY,
  ip VARCHAR(20),
  username VARCHAR(20),
  querytype VARCHAR(20) NOT NULL,
  queryvalue VARCHAR(50),
  querydays INT(6) NOT NULL,
  time datetime NOT NULL
) ENGINE=InnoDB;

-- neighbor table
CREATE TABLE `neighbor` (
  `switch` varchar(100) NOT NULL,
  `port` varchar(30) NOT NULL,
  `n_ip` VARCHAR(32),
  `n_host` VARCHAR(100),
  `n_desc` VARCHAR(2000),
  `n_model` VARCHAR(100),
  `n_port` VARCHAR(30),
  `n_protocol` VARCHAR(10),
  `n_lastseen` datetime NOT NULL,
  CONSTRAINT FOREIGN KEY ( switch, port ) REFERENCES switchstatus ( switch, port ) ON DELETE CASCADE ON UPDATE CASCADE,
  PRIMARY KEY ( switch, port )
) ENGINE=InnoDB;


-- netdb metadata
CREATE TABLE `meta` (
  name VARCHAR(50),
  version VARCHAR(50)
) ENGINE=InnoDB;

-- MAC watch table
CREATE TABLE `macwatch` (
  `mac` VARCHAR(20) NOT NULL,
  `active` BOOL,
  `entered` datetime NOT NULL,
  `enteruser` VARCHAR(20) NOT NULL,
  `note` VARCHAR(256) NOT NULL,
  `found` BOOL,
  `foundon` datetime,
  `foundby` VARCHAR(20),
  `foundnote` VARCHAR(160),
  `lastalert` datetime,
  `switch` VARCHAR(100),
  `email` VARCHAR(384),
  `alertcmd` VARCHAR(256),
  PRIMARY KEY  (`mac`),
  KEY `entered_idx` (`entered`),
  KEY `foundon_idx` (`foundon`)
) ENGINE=InnoDB;


INSERT into meta set name='netdb',version='1.13';

-- Views for reports.  Hides complexity in the database.
-- Each view starts with either mac, arp, mac table or switch interface status data
-- Extra information is appended to the table through joins to get a complete picture

create or replace view supermac
AS SELECT mac.mac,mac.lastip,mac.lastipseen,ipmac.name,ipmac.vlan,ipmac.vrf,ipmac.router,mac.vendor,mac.mac_nd,mac.lastswitch,mac.lastport,
switchstatus.description,switchstatus.status,switchstatus.p_uptime,switchstatus.p_minutes,switchstatus.lastup,
mac.firstseen,mac.lastseen,mac.filtered,mac.note,nacreg.userID,nacreg.firstName,nacreg.lastName,nacreg.type,disabled.distype,disabled.disuser,disabled.discase,
disabled.severity,disabled.disdate
FROM mac LEFT JOIN (switchstatus) ON (mac.lastswitch=switchstatus.switch AND mac.lastport=switchstatus.port)
LEFT JOIN (ipmac) ON (mac.mac=ipmac.mac AND mac.lastip=ipmac.ip) LEFT JOIN (nacreg) ON (mac.mac=nacreg.mac)
LEFT JOIN (disabled) ON (mac.mac=disabled.mac);

create or replace view superswitch
AS select sw.switch,sw.port,sw.type,st.description,st.status,sw.uptime,sw.minutes,sw.s_speed,sw.s_ip,sw.s_name,sw.s_vlan,
st.p_uptime,st.p_minutes,st.lastup,sw.mac,sw.firstseen,sw.lastseen,
ip.ip,ipmac.name,mac.vendor,mac.mac_nd,ipmac.vlan,ipmac.vrf,ipmac.router,ip.static,
nd.n_host,nd.n_ip,nd.n_desc,nd.n_model,nd.n_port,nd.n_protocol,nd.n_lastseen
FROM switchports AS sw LEFT JOIN (switchstatus AS st) ON (sw.switch=st.switch AND sw.port=st.port)
LEFT JOIN (neighbor AS nd) ON (sw.switch=nd.switch AND sw.port=nd.port)
LEFT JOIN (mac) ON (sw.mac=mac.mac) LEFT JOIN (ip) ON (mac.lastip=ip.ip)
LEFT JOIN (ipmac) ON (ip.ip=ipmac.ip AND mac.mac=ipmac.mac);

create or replace view superarp
AS select ipmac.ip,ipmac.mac,ipmac.name,ipmac.firstseen,ipmac.lastseen,ipmac.vlan,ipmac.vrf,ipmac.router,ip.static,
mac.lastswitch,mac.lastport,st.description,st.status,
mac.vendor,mac.mac_nd,mac.filtered,mac.note,nacreg.userID,nacreg.firstName,nacreg.lastName
FROM ipmac LEFT JOIN (ip) ON (ipmac.ip=ip.ip) LEFT JOIN (mac) ON (ipmac.mac=mac.mac) 
LEFT JOIN (nacreg) ON (ipmac.mac=nacreg.mac) LEFT JOIN (switchstatus AS st) ON (mac.lastswitch=st.switch AND mac.lastport=st.port);


-- View based on vendor codes for custom report
create or replace view vendors as
select vendor, count(*) as occurances from mac 
group by vendor order by occurances desc;

