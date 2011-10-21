--
-- Database: test
--

DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

CREATE TABLE `location` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `city` varchar(255) NOT NULL default '',
  `state` varchar(255) NOT NULL default '',
  PRIMARY KEY  (`id`),
  KEY `location_idx` (`city`,`state`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

INSERT INTO `location` VALUES
  (1,'New York City','New York'),
  (2,'Atlanta','Georgia'),
  (3,'San Francisco','California');

CREATE TABLE `report_baseball_team` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `acquired` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`id`),
  UNIQUE KEY `acquired` (`acquired`)
) ENGINE=InnoDB;

CREATE TABLE `baseball_team` (
  `report_baseball_team` int(10) unsigned NOT NULL default '0',
  `name` varchar(255) NOT NULL default '',
  `wins` int(11) default NULL,
  `losses` int(11) default NULL,
  `location` int(10) unsigned default NULL,
  PRIMARY KEY  (`report_baseball_team`,`name`),
  KEY `location_idxfk` (`location`),
  CONSTRAINT `baseball_team_ibfk_2` FOREIGN KEY (`location`) REFERENCES `location` (`id`),
  CONSTRAINT `baseball_team_ibfk_1` FOREIGN KEY (`report_baseball_team`) REFERENCES `report_baseball_team` (`id`)
) ENGINE=InnoDB;

CREATE TABLE `raw_data_baseball` (
  `mkin_id` int(10) unsigned NOT NULL auto_increment,
  `acquired` datetime NOT NULL default '0000-00-00 00:00:00',
  `name` varchar(255) NOT NULL default '',
  `wins` int(11) default NULL,
  `losses` int(11) default NULL,
  `town` int(11) NOT NULL default '0',
  PRIMARY KEY  (`mkin_id`),
  UNIQUE KEY `acquired` (`acquired`,`name`,`town`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

INSERT INTO `raw_data_baseball` VALUES
  (1,'2011-08-01 10:00:00','braves',45,48,2),
  (2,'2011-08-01 10:00:00','mets',50,43,1),
  (3,'2011-08-01 11:00:00','giants',49,42,3),
  (4,'2011-08-01 11:00:00','yankees',44,49,1);
