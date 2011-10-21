DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

CREATE TABLE `raw_data` (
  `date` date NOT NULL default '0000-00-00',
  `hour` tinyint(4) NOT NULL default '0',
  `entity_property_1` int(11) NOT NULL default '0',
  `entity_property_2` int(11) NOT NULL default '0',
  `data_1` int(11) default NULL,
  `data_2` int(11) default NULL,
  `posted` datetime NOT NULL default '0000-00-00 00:00:00',
  `acquired` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`date`,`hour`,`entity_property_1`,`entity_property_2`,`posted`,`acquired`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

INSERT INTO `raw_data` VALUES
  ('2011-06-01',1,10,11,12,13,'2011-06-01 23:23:23','2011-06-01 23:55:55'),
  ('2011-06-01',2,10,11,12,13,'2011-06-01 23:23:23','2011-06-01 23:55:55'),
  ('2011-06-01',2,20,21,22,23,'2011-06-01 23:23:23','2011-06-01 23:55:55');

CREATE TABLE `raw_data_2` (
  `date` date NOT NULL default '0000-00-00',
  `hour` tinyint(4) NOT NULL default '0',
  `entity_property_1` int(11) NOT NULL default '0',
  `entity_property_2` int(11) NOT NULL default '0',
  `data_1` int(11) default NULL,
  `data_2` int(11) default NULL,
  `posted` datetime NOT NULL default '0000-00-00 00:00:00',
  `acquired` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`date`,`hour`,`entity_property_1`,`entity_property_2`,`posted`,`acquired`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

INSERT INTO `raw_data_2` VALUES
  ('2011-06-01',1,10,11,12,13,'2011-06-01 23:23:23','2011-06-01 23:55:57'),
  ('2011-06-01',2,10,11,12,13,'2011-06-01 23:23:23','2011-06-01 23:55:57'),
  ('2011-06-01',2,20,21,22,23,'2011-06-01 23:23:23','2011-06-01 23:55:57');

CREATE TABLE `data_report` (
  `id` int(11) NOT NULL auto_increment,
  `date` date default NULL,
  `posted` datetime default NULL,
  `acquired` datetime default NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `data_report_idx` (`date`,`posted`,`acquired`)
) ENGINE=InnoDB;

CREATE TABLE `entity` (
  `id` int(11) NOT NULL auto_increment,
  `entity_property_1` int(11) default NULL,
  `entity_property_2` int(11) default NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `entity_idx` (`entity_property_1`,`entity_property_2`)
) ENGINE=InnoDB;

CREATE TABLE `data` (
  `data_report` int(11) NOT NULL default '0',
  `hour` tinyint(4) NOT NULL default '0',
  `entity` int(11) NOT NULL default '0',
  `data_1` int(11) default NULL,
  `data_2` int(11) default NULL,
  PRIMARY KEY (`data_report`,`hour`,`entity`),
  KEY `entity_idxfk` (`entity`),
  CONSTRAINT `data_ibfk_2` FOREIGN KEY (`entity`) REFERENCES `entity` (`id`),
  CONSTRAINT `data_ibfk_1` FOREIGN KEY (`data_report`) REFERENCES `data_report` (`id`)
) ENGINE=InnoDB;
