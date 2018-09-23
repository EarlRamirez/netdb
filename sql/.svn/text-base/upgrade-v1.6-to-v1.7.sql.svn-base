-- Changes to the database that need to be applied depending on what version you are running.  
-- To import, run these commands:
-- mysql -u root -p (login with your password)
-- use netdb
-- source /opt/netdb/sql/upgrade-v1.6-to-v1.7.sql
--
-- Expect to see Query OK

--
-- Changes added to NetDB v1.7 for upgrades from v1.6
--

-- missing index
create index mac_idx ON switchports (mac);


-- End of SQL Revisions

