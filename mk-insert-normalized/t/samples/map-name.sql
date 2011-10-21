DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

-- Database: test

CREATE TABLE `data_report` (
  `id` int(11) NOT NULL auto_increment,
  `date` date default NULL,
  `acquired` datetime default NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `data_report_idx` (`date`,`acquired`)
) ENGINE=InnoDB;

CREATE TABLE `entity_1` (
  `id` int(11) NOT NULL auto_increment,
  `name` varchar(255) default NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `entity_idx` (`name`)
) ENGINE=InnoDB;

CREATE TABLE `entity_2` (
  `id` int(11) NOT NULL auto_increment,
  `name` varchar(255) default NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `entity_idx` (`name`)
) ENGINE=InnoDB;

CREATE TABLE `data` (
  `data_report` int(11) NOT NULL default '0',
  `hour` tinyint(4) NOT NULL default '0',
  `entity_1` int(11) NOT NULL default '0',
  `entity_2` int(11) NOT NULL default '0',
  `data` int(11) default NULL,
  PRIMARY KEY (`data_report`,`hour`,`entity_1`,`entity_2`),
  KEY `entity_1_idxfk` (`entity_1`),
  KEY `entity_2_idxfk` (`entity_2`),
  FOREIGN KEY (`data_report`) REFERENCES `data_report` (`id`),
  FOREIGN KEY (`entity_1`) REFERENCES `entity_1` (`id`),
  FOREIGN KEY (`entity_2`) REFERENCES `entity_2` (`id`)
) ENGINE=InnoDB;

CREATE TABLE `raw_data` (
  `date` date NOT NULL default '0000-00-00',
  `acquired` datetime NOT NULL default '0000-00-00 00:00:00',
  `hour` tinyint(4) NOT NULL default '0',
  `name_1` varchar(255) NOT NULL default '',
  `name_2` varchar(255) NOT NULL default '',
  `data` int(11) default NULL,
  PRIMARY KEY  (`date`,`acquired`,`hour`,`name_1`,`name_2`)
) ENGINE=InnoDB;

INSERT INTO `raw_data` VALUES
  ('2011-06-01','2011-06-01 23:55:58',1,'a','x',27),
  ('2011-06-01','2011-06-01 23:55:58',2,'a','x',27),
  ('2011-06-01','2011-06-01 23:55:58',3,'b','y',23),
  ('2011-06-01','2011-06-01 23:55:58',4,'a','x',27),
  ('2011-06-01','2011-06-01 23:55:58',4,'b','x',23),
  ('2011-06-01','2011-06-01 23:55:58',4,'b','y',23),
  ('2011-06-01','2011-06-01 23:55:58',5,'b','y',29);
