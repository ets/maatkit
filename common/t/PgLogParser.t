#!/usr/bin/perl

BEGIN {
   die "The MAATKIT_TRUNK environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_TRUNK} && -d $ENV{MAATKIT_TRUNK};
   unshift @INC, "$ENV{MAATKIT_TRUNK}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 27;

use PgLogParser;
use MaatkitTest;

my $p = new PgLogParser;

# Run some tests of duration_to_secs().
my @duration_tests = (
   ['10.870 ms'     => '0.01087'],
   ['0.084312 sec'  => '0.084312'],
);
foreach my $test ( @duration_tests ) {
   is (
      $p->duration_to_secs($test->[0]),
      $test->[1],
      "Duration for $test->[0] == $test->[1]");
}

# duration_to_secs() should not accept garbage at the end of its argument.
throws_ok (
   sub {
      $p->duration_to_secs('duration: 1.565 ms  statement: SELECT 1');
   },
   qr/Unknown suffix/,
   'duration_to_secs does not like crap at the end',
);

# Tests of 'deferred'.
is($p->deferred, undef, 'Nothing in deferred');
is($p->deferred('foo'), 'foo', 'Store foo in deferred');
is($p->deferred, 'foo', 'Get foo from deferred');
is($p->deferred, undef, 'Nothing in deferred');

# Tests of 'get_meta'
my @meta = (
   ['c=4b7074b4.985,u=fred,D=jim', {
      Session_id => '4b7074b4.985',
      user       => 'fred',
      db         => 'jim',
   }],
   ['c=4b7074b4.985, user=fred, db=jim', {
      Session_id => '4b7074b4.985',
      user       => 'fred',
      db         => 'jim',
   }],
   ['c=4b7074b4.985 user=fred db=jim', {
      Session_id => '4b7074b4.985',
      user       => 'fred',
      db         => 'jim',
   }],
);
foreach my $meta ( @meta ) {
   is_deeply({$p->get_meta($meta->[0])}, $meta->[1], "Meta for $meta->[0]");
}

# A simple log of a session.
test_log_parser(
   parser => $p,
   file   => 'common/t/samples/pg-log-001.txt',
   result => [
      {  ts            => '2010-02-08 15:31:48.685',
         host          => '[local]',
         db            => '[unknown]',
         user          => '[unknown]',
         arg           => 'connection received',
         Session_id    => '4b7074b4.985',
         pos_in_log    => 0,
         bytes         => 19,
         cmd           => 'Admin',
      },
      {  ts            => '2010-02-08 15:31:48.687',
         user          => 'fred',
         db            => 'fred',
         arg           => 'connection authorized',
         Session_id    => '4b7074b4.985',
         pos_in_log    => 107,
         bytes         => 21,
         cmd           => 'Admin',
      },
      {  ts            => '2010-02-08 15:31:50.872',
         db            => 'fred',
         user          => 'fred',
         arg           => 'select 1;',
         Query_time    => '0.01087',
         Session_id    => '4b7074b4.985',
         pos_in_log    => 217,
         bytes         => length('select 1;'),
         cmd           => 'Query',
      },
      {  ts            => '2010-02-08 15:31:58.515',
         db            => 'fred',
         user          => 'fred',
         arg           => "select\n1;",
         Query_time    => '0.013918',
         Session_id    => '4b7074b4.985',
         pos_in_log    => 384,
         bytes         => length("select\n1;"),
         cmd           => 'Query',
      },
      {  ts            => '2010-02-08 15:32:06.988',
         db            => 'fred',
         user          => 'fred',
         host          => '[local]',
         arg           => 'disconnection',
         Session_id    => '4b7074b4.985',
         pos_in_log    => 552,
         bytes         => length('disconnection'),
         cmd           => 'Admin',
      },
   ],
);

# A log that has no fancy line-prefix with user/db/session info.  It also begins
# with an entry whose header is missing.  And it ends with a line that has no
# 'duration' line afterwards.
test_log_parser(
   parser => $p,
   file   => 'common/t/samples/pg-log-002.txt',
   result => [
      {  ts            => '2004-05-07 11:58:22',
         arg           => "SELECT groups.group_name,groups.unix_group_name,\n"
                           . "\tgroups.type_id,users.user_name,users.realname,\n"
                           . "\tnews_bytes.forum_id,news_bytes.summary,news_bytes.post_date,news_bytes.details \n"
                           . "\tFROM users,news_bytes,groups \n"
                           . "\tWHERE news_bytes.group_id='98' AND news_bytes.is_approved <> '4' \n"
                           . "\tAND users.user_id=news_bytes.submitted_by \n"
                           . "\tAND news_bytes.group_id=groups.group_id \n"
                           . "\tORDER BY post_date DESC LIMIT 10 OFFSET 0",
         pos_in_log    => 147,
         bytes         => 404,
         cmd           => 'Query',
         Query_time    => '0.00268',
      },
      {  ts            => '2004-05-07 11:58:36',
         arg           => 'begin; select getdatabaseencoding(); commit',
         cmd           => 'Query',
         pos_in_log    => 641,
         bytes         => 43,
      },
   ],
);

# A log that has no line-prefix at all.  It also has durations and statements on
# the same line.
test_log_parser(
   parser => $p,
   file   => 'common/t/samples/pg-log-003.txt',
   result => [
      {  arg           => "SELECT * FROM users WHERE user_id='692'",
         pos_in_log    => 0,
         bytes         => 39,
         cmd           => 'Query',
         Query_time    => '0.001565',
      },
      {  arg           => "SELECT groups.group_name,groups.unix_group_name,\n"
                          . "\t\tgroups.type_id,users.user_name,users.realname,\n"
                          . "\t\tnews_bytes.forum_id,news_bytes.summary,news_bytes.post_date,news_bytes.details \n"
                          . "\t\tFROM users,news_bytes,groups \n"
                          . "\t\tWHERE news_bytes.is_approved=1 \n"
                          . "\t\tAND users.user_id=news_bytes.submitted_by \n"
                          . "\t\tAND news_bytes.group_id=groups.group_id \n"
                          . "\t\tORDER BY post_date DESC LIMIT 5 OFFSET 0",
         cmd           => 'Query',
         pos_in_log    => 78,
         bytes         => 376,
         Query_time    => '0.00164',
      },
      {  arg           => "SELECT total FROM forum_group_list_vw WHERE group_forum_id='4606'",
         pos_in_log    => 499,
         bytes         => 65,
         cmd           => 'Query',
         Query_time    => '0.000529',
      },
   ],
);

# A simple log of a session.
test_log_parser(
   parser => $p,
   file   => 'common/t/samples/pg-log-004.txt',
   result => [
      {  ts            => '2010-02-10 08:39:56.835',
         host          => '[local]',
         db            => '[unknown]',
         user          => '[unknown]',
         arg           => 'connection received',
         Session_id    => '4b72b72c.b44',
         pos_in_log    => 0,
         bytes         => 19,
         cmd           => 'Admin',
      },
      {  ts            => '2010-02-10 08:39:56.838',
         user          => 'fred',
         db            => 'fred',
         arg           => 'connection authorized',
         Session_id    => '4b72b72c.b44',
         pos_in_log    => 107,
         bytes         => 21,
         cmd           => 'Admin',
      },
      {  ts            => '2010-02-10 08:40:34.681',
         db            => 'fred',
         user          => 'fred',
         arg           => 'select 1;',
         Query_time    => '0.001308',
         Session_id    => '4b72b72c.b44',
         pos_in_log    => 217,
         bytes         => length('select 1;'),
         cmd           => 'Query',
      },
      {  ts            => '2010-02-10 08:44:31.368',
         db            => 'fred',
         user          => 'fred',
         host          => '[local]',
         arg           => 'disconnection',
         Session_id    => '4b72b72c.b44',
         pos_in_log    => 322,
         bytes         => length('disconnection'),
         cmd           => 'Admin',
      },
   ],
);

# A log that shows that continuation lines don't have to start with a TAB, and
# not all queries must be followed by a duration.
test_log_parser(
   parser => $p,
   file   => 'common/t/samples/pg-log-005.txt',
   result => [
      {  ts            => '2004-05-07 12:00:01',
         arg           => 'begin; select getdatabaseencoding(); commit',
         pos_in_log    => 0,
         bytes         => 43,
         cmd           => 'Query',
         Query_time    => '0.000801',
      },
      {  ts            => '2004-05-07 12:00:01',
         arg           => "update users set unix_status = 'A' where user_id in (select\n"
                         . "distinct u.user_id from users u, user_group ug WHERE\n"
                         . "u.user_id=ug.user_id and ug.cvs_flags='1' and u.status='A')",
         pos_in_log    => 126,
         bytes         => 172,
         cmd           => 'Query',
      },
      {  ts            => '2004-05-07 12:00:01',
         arg           => 'SELECT 1 FROM ONLY "public"."supported_languages" x '
                           . 'WHERE "language_id" = $1 FOR UPDATE OF x',
         pos_in_log    => 333,
         bytes         => 92,
         cmd           => 'Query',
      },
   ],
);

# A log with an error.
test_log_parser(
   parser => $p,
   file   => 'common/t/samples/pg-log-006.txt',
   result => [
      {  ts            => '2004-05-07 12:01:06',
         arg           => 'SELECT plugin_id, plugin_name FROM plugins',
         pos_in_log    => 0,
         bytes         => 42,
         cmd           => 'Query',
         Query_time    => '0.002161',
      },
      {  ts            => '2004-05-07 12:01:06',
         arg           => "SELECT \n\t\t\t\tgroups.type,\n"
                           . "\t\t\t\tnews_bytes.details \n"
                           . "\t\t\tFROM \n"
                           . "\t\t\t\tnews_bytes,\n"
                           . "\t\t\t\tgroups \n"
                           . "\t\t\tWHERE \n"
                           . "\t\t\t\tnews_bytes.group_id=groups.group_id \n"
                           . "\t\t\tORDER BY \n"
                           . "\t\t\t\tdate \n"
                           . "\t\t\tDESC LIMIT 30 OFFSET 0",
         pos_in_log    => 125,
         bytes         => 185,
         cmd           => 'Query',
         Error_msg     => 'No such attribute groups.type',
      },
      {  ts            => '2004-05-07 12:01:06',
         arg           => 'SELECT plugin_id, plugin_name FROM plugins',
         pos_in_log    => 412,
         bytes         => 42,
         cmd           => 'Query',
         Query_time    => '0.002161',
      },
   ],
);

# A log with informational messages.
test_log_parser(
   parser => $p,
   file   => 'common/t/samples/pg-log-007.txt',
   result => [
      {  arg           => 'SELECT plugin_id, plugin_name FROM plugins',
         pos_in_log    => 20,
         bytes         => 42,
         cmd           => 'Query',
         Query_time    => '0.002991',
      },
   ],
);

# Test that meta-data in connection/disconnnection lines is captured.
test_log_parser(
   parser => $p,
   file   => 'common/t/samples/pg-log-008.txt',
   result => [
      {  ts            => '2010-02-08 15:31:48',
         host          => '[local]',
         arg           => 'connection received',
         pos_in_log    => 0,
         bytes         => 19,
         cmd           => 'Admin',
      },
      {  ts            => '2010-02-08 15:31:48',
         user          => 'fred',
         db            => 'fred',
         arg           => 'connection authorized',
         pos_in_log    => 64,
         bytes         => 21,
         cmd           => 'Admin',
      },
      {  ts            => '2010-02-08 15:32:06',
         db            => 'fred',
         user          => 'fred',
         host          => '[local]',
         arg           => 'disconnection',
         pos_in_log    => 141,
         bytes         => length('disconnection'),
         cmd           => 'Admin',
      },
   ],
);

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $p->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;
