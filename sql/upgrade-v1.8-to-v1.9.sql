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
-- Changes added to NetDB v1.9 for upgrades from v1.8
--

-- fix ip tables for IPv6
alter table ip modify ip varchar(32);
alter table ipmac modify ip varchar(32);
alter table mac modify lastip varchar(32);

-- End of SQL Revisions