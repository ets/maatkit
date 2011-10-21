DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

CREATE TABLE `log2` (
  `id` int(11) NOT NULL auto_increment,
  `date` date NOT NULL default '0000-00-00',
  `in_id` int(11) default NULL,                   -- details id 1
  `request_id` int(11) default NULL,              -- details id 2
  `response_id` int(11) default NULL,             -- details id 3
  `out_id` int(11) default NULL,                  -- details id 4
  `comment_id` int(11) default NULL,              -- details id 5
  `state` char(2) default NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM;

INSERT INTO log2 VALUES
(null, '2011-08-29', 1,3,5,7,9,'ok'),
(null, '2011-08-29', 2,4,6,8,10,'ok'),
(null, '2011-08-29', 21,22,23,24,25,'ok'),
(null, '2011-08-29', 20,31,32,33,34,'ok'),
(null, '2011-08-29', 0,0,0,0,0,'na');

CREATE TABLE `details` (
  `id` int(11) NOT NULL auto_increment,
  `data` text NOT NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM;

INSERT INTO details VALUES
(1, 'one'),
(2, 'two'),
(3, 'three'),
(4, 'four'), 
(5, 'five'),
(6, 'six'), 
(7, 'seven'), 
(8, 'eight'), 
(9, 'nine'), 
(10, 'ten'),
(11, 'eleven'),    -- kept
(12, 'twelve'),    -- kept
(13, 'thrirteen'), -- kept
(14, 'fourteen'),  -- kept
(15, 'fifteen'),   -- kept
(16, 'sixteen'),   -- kept
(17, 'seventeen'), -- kept
(18, 'eighteen'),  -- kept
(19, 'nineteen'),  -- kept
(20, 'twenty'),
(21, 'twenty-one'), 
(22, 'twenty-two'), 
(23, 'twenty-three'), 
(24, 'twenty-four'), 
(25, 'twenty-five'),
(30, 'thirty'),      -- kept
(31, 'thirty-one'), 
(32, 'thirty-two'), 
(33, 'thirty-three'), 
(34, 'thirty-four'), 
(35, 'thirty-five'); -- kept

DROP DATABASE IF EXISTS `test_archive`;
CREATE DATABASE `test_archive`;
USE test_archive;

CREATE TABLE `log2` (
  `id` int(11) NOT NULL auto_increment,
  `date` date NOT NULL default '0000-00-00',
  `in_id` int(11) default NULL,                   -- details id 1
  `request_id` int(11) default NULL,              -- details id 2
  `response_id` int(11) default NULL,             -- details id 3
  `out_id` int(11) default NULL,                  -- details id 4
  `comment_id` int(11) default NULL,              -- details id 5
  `state` char(2) default NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM;

CREATE TABLE `details` (
  `id` int(11) NOT NULL auto_increment,
  `data` text NOT NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM;
