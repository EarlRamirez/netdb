#!/bin/sh
# Avoid any foreign key contraint issues on restore if any exist

(
echo "SET AUTOCOMMIT=0;"
echo "SET FOREIGN_KEY_CHECKS=0;"
cat /backup/netdb.sql
echo "SET FOREIGN_KEY_CHECKS=1;"
echo "COMMIT;"
echo "SET AUTOCOMMIT=1;"
) | mysql --user=root -p netdb
