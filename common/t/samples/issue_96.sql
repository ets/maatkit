DROP DATABASE IF EXISTS issue_96;
CREATE DATABASE issue_96;
USE issue_96;
DROP TABLE IF EXISTS t;
CREATE TABLE `t` (
  `package_id` bigint(20) unsigned default NULL,
  `location` varchar(4) default NULL,
  `from_city` varchar(100) default NULL,
  UNIQUE KEY `package_id` (`package_id`,`location`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
INSERT INTO t VALUES
   (1,'ABC','lo'),
   (NULL,'CHY','ch'),
   (2,'BFN','na'),
   (NULL,NULL,'gl'),
   (12,'TTT','ty'),
   (4,'CPR','ta'),
   (8,'CSX','dz'),
   (9,NULL,NULL),
   (NULL,NULL,NULL),
   (11,'PBR',NULL),
   (NULL,'THR',NULL),
   (6,NULL,'jr');