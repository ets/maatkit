#!/usr/bin/perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 7;

use GeneralLogParser;
use MaatkitTest;

my $p = new GeneralLogParser();

my $oktorun = 1;
my $sample  = "common/t/samples/genlogs/";

test_log_parser(
   parser  => $p,
   file    => $sample.'genlog001.txt',
   oktorun => sub { $oktorun = $_[0]; },
   result  => [
      {  ts         => '051007 21:55:24',
         Thread_id  => '42',
         arg        => 'administrator command: Connect',
         bytes      => 30,
         cmd        => 'Admin',
         db         => 'db1',
         host       => 'localhost',
         pos_in_log => 0,
         user       => 'root',
         Query_time => 0,
      },
      {  ts         => undef,
         Thread_id  => '42',
         arg        => 'SELECT foo 
                         FROM tbl
                         WHERE col=12345
                         ORDER BY col',
         bytes      => 124,
         cmd        => 'Query',
         pos_in_log => 58,
         Query_time => 0,
         db         => 'db1',
      },
      {  ts         => undef,
         Thread_id  => '42',
         arg        => 'administrator command: Quit',
         bytes      => 27,
         cmd        => 'Admin',
         pos_in_log => 244,
         Query_time => 0,
      },
      {  ts         => '061226 15:42:36',
         Thread_id  => '11',
         arg        => 'administrator command: Connect',
         bytes      => 30,
         cmd        => 'Admin',
         host       => 'localhost',
         pos_in_log => 244,
         user       => 'root',
         Query_time => 0,
      },
      {  ts         => undef,
         Thread_id  => '11',
         arg        => 'administrator command: Init DB',
         bytes      => 30,
         cmd        => 'Admin',
         db         => 'my_webstats',
         pos_in_log => 300,
         Query_time => 0,
      },
      {  ts         => undef,
         Thread_id  => '11',
         arg        => 'SELECT DISTINCT col FROM tbl WHERE foo=20061219',
         bytes      => 47,
         cmd        => 'Query',
         pos_in_log => 346,
         Query_time => 0,
         db         => 'my_webstats',
      },
      {  ts         => '061226 16:44:48',
         Thread_id  => '11',
         arg        => 'administrator command: Quit',
         bytes      => 27,
         cmd        => 'Admin',
         pos_in_log => 464,
         Query_time => 0,
      },
   ]
);

is(
   $oktorun,
   0,
   'Sets oktorun'
);
$oktorun = 1;

test_log_parser(
   parser  => $p,
   file    => $sample.'genlog002.txt',
   result  => [
      {
         Query_time  => 0,
         Thread_id   => '51',
         arg         => 'SELECT category_id
                FROM auction_category_map 
                WHERE auction_id = \'3015563\'',
         bytes       => 106,
         cmd         => 'Query',
         pos_in_log  => 0,
         ts          => '100211  0:55:24'
      },
      {
         Query_time  => 0,
         Thread_id   => '51',
         arg         => 'SELECT auction_id, auction_title_en AS title, close_time,
                                         number_of_items_per_lot, 
                                         replace (replace (thumbnail_url,  \'sm_thumb\', \'carousel\'), \'small_thumb\', \'carousel\') as thumbnail_url,
                                         replace (replace (thumbnail_url,  \'sm_thumb\', \'tiny_thumb\'), \'small_thumb\', \'tiny_thumb\') as tinythumb_url,
                                         current_bid
                FROM   auction_search
                WHERE  platform_flag_1 = 1
                AND    close_flag = 0 
                AND    close_time >= NOW()
                AND    marketplace = \'AR\'
                AND auction_id IN (3015562,3028764,3015564,3019075,3015574,2995142,3040162,3015573,2995135,3015578)
                ORDER BY close_time ASC
                LIMIT 500',
         bytes       => 858,
         cmd         => 'Query',
         pos_in_log  => 237,
         ts          => undef
      },
   ],
);


# #############################################################################
# Issue 972: mk-query-digest genlog timestamp fix
# #############################################################################
test_log_parser(
   parser  => $p,
   file    => $sample.'genlog003.txt',
   oktorun => sub { $oktorun = $_[0]; },
   result  => [
      {  ts         => '051007   21:55:24',
         Thread_id  => '42',
         arg        => 'administrator command: Connect',
         bytes      => 30,
         cmd        => 'Admin',
         db         => 'db1',
         host       => 'localhost',
         pos_in_log => 0,
         user       => 'root',
         Query_time => 0,
      },
      {  ts         => undef,
         Thread_id  => '42',
         arg        => 'SELECT foo 
                         FROM tbl
                         WHERE col=12345
                         ORDER BY col',
         bytes      => 124,
         cmd        => 'Query',
         pos_in_log => 60,
         Query_time => 0,
         db         => 'db1',
      },
      {  ts         => undef,
         Thread_id  => '42',
         arg        => 'administrator command: Quit',
         bytes      => 27,
         cmd        => 'Admin',
         pos_in_log => 246,
         Query_time => 0,
      },
      {  ts         => undef,
         Thread_id  => '11',
         arg        => 'administrator command: Connect',
         bytes      => 30,
         cmd        => 'Admin',
         host       => 'localhost',
         pos_in_log => 246,
         user       => 'root',
         Query_time => 0,
      },
      {  ts         => undef,
         Thread_id  => '11',
         arg        => 'administrator command: Init DB',
         bytes      => 30,
         cmd        => 'Admin',
         db         => 'my_webstats',
         pos_in_log => 302,
         Query_time => 0,
      },
      {  ts         => undef,
         Thread_id  => '11',
         arg        => 'SELECT DISTINCT col FROM tbl WHERE foo=20061219',
         bytes      => 47,
         cmd        => 'Query',
         pos_in_log => 348,
         Query_time => 0,
         db         => 'my_webstats',
      },
      {  ts         => undef,
         Thread_id  => '11',
         arg        => 'administrator command: Quit',
         bytes      => 27,
         cmd        => 'Admin',
         pos_in_log => 466,
         Query_time => 0,
      },
   ]
);

# #############################################################################
# Done.
# #############################################################################
exit;
