
--
-- Database: test
--

drop database if exists test;
create database test;
use test;

CREATE TABLE `report_animal` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `acquired` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`id`),
  UNIQUE KEY `acquired` (`acquired`)
) ENGINE=InnoDB;

CREATE TABLE `species` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `type` varchar(255) NOT NULL default '0',
  PRIMARY KEY  (`id`),
  UNIQUE KEY `type` (`type`)
) ENGINE=InnoDB;

CREATE TABLE `animal` (
  `report_animal` int(10) unsigned NOT NULL default '0',
  `name` varchar(255) NOT NULL default '',
  `max_weight` float default NULL,
  `species` int(10) unsigned default NULL,
  PRIMARY KEY  (`report_animal`,`name`),
  KEY `species_idxfk` (`species`),
  CONSTRAINT `animal_ibfk_2` FOREIGN KEY (`species`) REFERENCES `species` (`id`),
  CONSTRAINT `animal_ibfk_1` FOREIGN KEY (`report_animal`) REFERENCES `report_animal` (`id`)
) ENGINE=InnoDB;

CREATE TABLE `raw_data_animal_1` (
  `mkin_id` int(10) unsigned NOT NULL auto_increment,
  `acquired` datetime NOT NULL default '0000-00-00 00:00:00',
  `name` varchar(255) NOT NULL default '',
  `max_weight` float default NULL,
  PRIMARY KEY  (`mkin_id`),
  UNIQUE KEY `acquired` (`acquired`,`name`)
) ENGINE=InnoDB;

INSERT INTO `raw_data_animal_1` VALUES
(1,'2011-08-20 15:00:00','cat',15),
(2,'2011-08-20 15:00:00','dog',45),
(3,'2011-08-20 16:00:00','bird',5),
(4,'2011-08-20 16:00:00','frog',2);
