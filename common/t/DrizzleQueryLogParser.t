#!/usr/bin/perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 3;

use DrizzleQueryLogParser;
use MaatkitTest;

my $p = new DrizzleQueryLogParser;

my $sample = "common/t/samples/drizzle_query_log/";

# Check that I can parse a slow log in the default slow log format.
test_log_parser(
   parser => $p,
   file   => "$sample/query_log001",
   result => [
      {
         error => 'No',
         Query_time => '7.890123',
         lock_time => '4.567890',
         query_id => '2',
         rows_examined => '3',
         rows_sent => '4',
         schema => 'test',
         session_id => '1',
         session_time => '1.234567',
         ts => '1234-56-78T90:12:34.567890',
         tmp_tables => '5',
         warnings => '6',
         arg => 'SET GLOBAL query_log_file_enabled=TRUE;',
      },
      {
         error => 'Yes',
         Query_time => '0.000315',
         lock_time => '0.000315',
         query_id => '6',
         rows_examined => '0',
         rows_sent => '0',
         schema => '',
         session_id => '1',
         session_time => '16.723020',
         ts => '2011-05-15T01:48:17.814985',
         tmp_tables => '0',
         warnings => '1',
         arg => 'set query_log_file_enabled=true;',
      },
      {
         error => 'No',
         Query_time => '0.000979',
         index => 'No',
         lock_time => '0.000562',
         query_id => '7',
         rows_examined => '10',
         rows_sent => '10',
         schema => 'has a space',
         session_id => '1',
         session_time => '20.435445',
         ts => '2011-05-15T01:48:21.526746',
         tmp_tables => '0',
         warnings => '0',
         arg => "show variables like 'query_log%';",
      },
      {
         error => 'No',
         Query_time => '0.000979',
         host => 'db1.prod',
         index => 'Yes',
         lock_time => '0.000562',
         query_id => '8',
         rows_examined => '10',
         rows_sent => '10',
         schema => 'has a space',
         session_id => '1',
         session_time => '20.999999',
         ts => '2011-05-15T01:48:21.000000',
         tmp_tables => '0',
         warnings => '0',
         arg => "select col from table where col = 'Some
value

with

  multiple lines and spaces.
';",
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
