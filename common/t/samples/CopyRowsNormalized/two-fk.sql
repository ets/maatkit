DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

-- Database: test

CREATE TABLE `account` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `account_number` int(11) default NULL,
  `name` varchar(255) default NULL,
  PRIMARY KEY  (`id`),
  UNIQUE KEY `account_number` (`account_number`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB;

CREATE TABLE `data_report` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `date` date default NULL,
  `posted` datetime default NULL,
  `parent_account` int(10) unsigned NOT NULL default '0',
  PRIMARY KEY  (`id`),
  UNIQUE KEY `IDX` (`date`,`posted`,`parent_account`),
  KEY `parent_account_idxfk` (`parent_account`),
  CONSTRAINT `data_report_ibfk_1` FOREIGN KEY (`parent_account`) REFERENCES `account` (`id`)
) ENGINE=InnoDB;

CREATE TABLE `data` (
  `data_report` int(10) unsigned NOT NULL default '0',
  `sub_account` int(10) unsigned NOT NULL default '0',
  `data1` int(11) default NULL,
  PRIMARY KEY  (`data_report`,`sub_account`),
  KEY `sub_account_idxfk` (`sub_account`),
  CONSTRAINT `data_ibfk_2` FOREIGN KEY (`sub_account`) REFERENCES `account` (`id`),
  CONSTRAINT `data_ibfk_1` FOREIGN KEY (`data_report`) REFERENCES `data_report` (`id`)
) ENGINE=InnoDB;

CREATE TABLE `raw_data` (
  `date` date NOT NULL default '0000-00-00',
  `posted` datetime NOT NULL default '0000-00-00 00:00:00',
  `account_number_1` int(11) NOT NULL default '0',
  `name_1` varchar(255) NOT NULL default '',
  `account_number_2` int(11) NOT NULL default '0',
  `name_2` varchar(255) NOT NULL default '',
  `data1` int(11) default NULL,
  PRIMARY KEY  (`date`,`posted`,`account_number_1`,`name_1`,`account_number_2`,`name_2`)
) ENGINE=InnoDB;

INSERT INTO `raw_data` VALUES
  ('2011-05-01','2011-06-01 23:55:58',1,'a',1,'a',10),
  ('2011-05-01','2011-06-01 23:55:58',1,'a',2,'b',11),
  ('2011-05-01','2011-06-01 23:55:58',1,'a',3,'c',12),
  ('2011-05-01','2011-06-01 23:55:58',4,'d',4,'d',13),
  ('2011-05-01','2011-06-01 23:55:58',4,'d',5,'e',14),
  ('2011-05-01','2011-06-01 23:55:58',4,'d',6,'f',15);

