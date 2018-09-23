--mac 		    # [varchar] MAC address that we will be watching for (Primary Key)
--active 		# [bool] if we are actively watching for this entry
--entered 	    # [date] date that the MAC was put on the watchlist
--entereduser   # [varchar] user that entered the MAC into the watchlist
--found		    # [bool] flag for the device being found.
--foundom       # [date] date that the MAC was marked as found.
--foundby       # [varchar] user that set the MAC as found
--note		    # [varchar] any additional information about why it is in the database.
--email         # [varchar] comma seperated lists of email addresses that need to be notified if the MAC is found
--lastalert     # [date] last time we saw the MAC on the network and pages where sent
--switch        # [varchar] last switch/router/networking device the MAC was seen on when the last alert was sent.

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

