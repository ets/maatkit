drop database if exists cai;
create database cai;
use cai;

CREATE TABLE `t` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `c` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB;

insert into `t` values
   (1, 'one'),
   (2, 'two'),
   (3, 'three'),
   (4, 'four'),
   (5, 'five'),
   (9, 'nine'),
   (11, 'eleven'),
   (13, 'thirteen'),
   (14, 'fourteen'),
   (50, 'fifty'),
   (51, 'fifty one'),
   (200, 'two hundred'),
   (300, 'three hundred'),
   (304, 'three hundred four'),
   (305, 'three hundred five');

-- After compacting table t, the result should be table r.
-- Just the id vals are shifted down to the lowest possible
-- value, but the c values stay the same.

CREATE TABLE `r` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `c` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB;

insert into `r` values
   (1, 'one'),
   (2, 'two'),
   (3, 'three'),
   (4, 'four'),
   (5, 'five'),
   (6, 'nine'),
   (7, 'eleven'),
   (8, 'thirteen'),
   (9, 'fourteen'),
   (10, 'fifty'),
   (11, 'fifty one'),
   (12, 'two hundred'),
   (13, 'three hundred'),
   (14, 'three hundred four'),
   (15, 'three hundred five');

-- Second test: lowest auto-inc val isn't 1.
-- After compacting, t2 should result in r.

CREATE TABLE `t2` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `c` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB;

insert into `t2` values
   (9,  'one'),
   (10, 'two'),
   (11, 'three'),
   (15, 'four'),
   (17, 'five'),
   (20, 'nine'),
   (21, 'eleven'),
   (22, 'thirteen'),
   (24, 'fourteen'),
   (50, 'fifty'),
   (51, 'fifty one'),
   (200, 'two hundred'),
   (300, 'three hundred'),
   (304, 'three hundred four'),
   (305, 'three hundred five');
