
## NetDB (Work in Progress)

[NetDB](http://netdbtracking.sourceforge.net/) Network tracking database (NetDB) utilises the LAMP (Linux, Apache, MariaDB and Perl) stack for scraping and storing your network infomration in a centralised location.


-----------
### Credit

All credit goes to Jonathan Yantis.

------------
### Installation

To install NetDB on a vanilla Red Hat based distribution run the following commands

- Clone the NetDB `git clone https://github.com/EarlRamirez/netdb.git`
- Run the installation script `sudo sh <path_to_netdb>/netdb_install.sh`
- Enter the database passwords

When the installation script is completed, point your browser to the IP address of the server.
		  

----------
### Configuring and Adding Devices

There are a few things that was not done by the installation script; therefore, a few modifications are required for NetDB to start scraping your networking equipment, for example, Cisco switches and routers.

##### Add Devices to the Hosts File

If there isn't any DNS for your devices, its recommended that you update your hosts file with the IP and the host name of your devices 

- Using your favourite editor update the hosts file, `vim /etc/hosts`
	> 10.0.0.1		device1

	> 10.0.0.2		device2

##### Configure Devices to be Scraped

NetDB will only scarp the devices that are in the devicelist.csv which is located in _/opt/netdb/data/devicelist.csv_. The devicelist.csv supports both ARP and VRF, for example, device1 supports has VRF and device1 does not the configuration file will look like this 

- Add devices to the devicelist.csv
	>device1,arp,vrf-one,vrf-two

 	>device2,arp

##### Updating NetDB Configuration File

The final step is to update the netdb.conf with the credentials of your networking devices

- Edit the confoguration file `vim /etc/netdb.conf` and update the following lines
	>devuser    = **your_switch_user**       # Level 5 cisco user (show commands only)

	>devpass    = **your_passwd**

-----------
### Validate the Installation

- Try to scrape devices for data for the first time, add a -debug value if there
  are problems
  >netdbctl -ud -v

- Import data in to database (run this twice the first time)
  >netdbctl -a -m -debug 3

- Check control.log for any errors `tail -f /var/log/netdb/control.log`

- Check the size of the data in the database
   netdb -st

