--login to db with: mysql -u root -p

-- Show Databases
SHOW DATABASES;

-- Select DB
USE netdb;

-- MYSQL Status
SHOW STATUS;

-- InnoDB Status
SHOW INNODB STATUS;

-- Tables
SHOW TABLES;

-- Table Column Description
DESCRIBE ipmac;

-- Table Status Data
SHOW TABLE STATUS;

-- Table Creation
SHOW CREATE TABLE ipmac;

-- Show Indexes
SHOW INDEX IN ipmac;

-- Recent neighbors in a building
select switch,port,n_host,n_desc from neighbor where n_lastseen > '2013-07-11 07:53:08' and switch like 'muh%';


-- Mac Occurances in the ARP Table (spoofer?)
select mac, count(*) as occurances, vlan, name, lastseen 
FROM ipmac WHERE lastseen > '2009-03-01 23:02:37'
GROUP BY mac ORDER BY occurances DESC
INTO OUTFILE '/tmp/arpspoofers.txt'
        FIELDS TERMINATED BY ','
        ENCLOSED BY '"'
        LINES TERMINATED BY '\n';

-- Hub Report (multiple macs per port, filter phones)
select switch,port, count(mac) as occurances  from superswitch 
where lastseen > '2012-04-12 11:18:33' and switch not like 'mdc%' 
and vendor not like '%Tenovis%' and vendor not like '%Avaya%' 
group by switch,port ORDER BY occurances DESC;

-- Spurious mac data, high occurances of unknown vendor codes on a port
select lastswitch,lastport, count(mac) as occurances 
from mac where vendor is null group by lastswitch,lastport order by occurances desc;

-- Delete data from ports where vendor is null (for above query)
delete from mac where lastswitch='switch' and lastport='Gi4/34' and vendor is null;

-- Delete from ip table where not in ipmac table and not static
delete from ip where ip not in (select ip from ipmac) and static='0';

-- Find ARP table usage by vlan
select vlan,count(*) as occurances from ipmac where lastseen > '2011-12-05 20:02:42' group by vlan order by occurances desc;

-- Get Vendor Report
select mac.mac,mac.lastip,ipmac.name,mac.vendor,mac.lastswitch,mac.lastport,ipmac.lastseen 
from mac join ipmac on mac.mac = ipmac.mac and mac.lastip = ipmac.ip 
where upper(vendor) like '%sun micro%' 
ORDER BY ipmac.name 
INTO OUTFILE '/tmp/report.txt';

-- Highest AP Client Count
select switch,port, count(mac) as occurances from switchports where type='wifi' group by port order by occurances desc;

-- Android Phones and spacial streams
select mac,vendor,mac_nd,switch,port,description,s_speed from superswitch where mac_nd='Android' and s_speed like '%HT%';


-- Most mobile wireless users
select switch,mac,name,count(port) as occurances from superswitch where type='wifi' group by mac order by occurances desc;

-- Most mobile computers
select superswitch.mac, superswitch.ip, superswitch.name, mac.vendor, count(superswitch.switch) as occurances 
from superswitch left join mac using (mac) where ip is not null and vendor not like '%cisco%' and vendor not like '%vmware%' 
group by mac ORDER BY occurances DESC;

-- Top NetDB Users
select username, count(*) as occurances from transactions group by username ORDER BY occurances DESC;

-- Count Entries in table
SELECT COUNT(1) FROM ipmac;

