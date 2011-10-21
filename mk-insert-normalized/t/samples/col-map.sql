drop database if exists test;
create database test;
use test;
create table a (
  id   int auto_increment primary key,
  col1 int not null,
  col2 int not null,
  col3 int not null,
  col4 int not null
);
insert into a (col1, col2, col3, col4) values (1, 1, 1, 1), (2, 2, 2, 2), (3, 3, 3, 3);

create table y (
  id int auto_increment primary key,
  col1 int not null,
  col2 int not null
) engine=innodb;

create table z (
  id int auto_increment primary key,
  cola int not null,
  col2 int not null default 42,  -- default should be used
  three int not null,
  fk_col int not null,
  unique key (fk_col),
  FOREIGN KEY (fk_col) REFERENCES y (id)
) engine=innodb;
