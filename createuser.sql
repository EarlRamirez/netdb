use netdb;
CREATE USER IF NOT EXISTS 'netdbadmin'@'localhost' IDENTIFIED BY 'netdbadminpass';
GRANT ALL PRIVILEGES ON netdb.* TO 'netdbadmin'@'localhost';