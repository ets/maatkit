#!/usr/bin/env perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use MaatkitTest;
use Sandbox;
require "$trunk/mk-table-sync/mk-table-sync";

my $output;
my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 3;
}

$sb->wipe_clean($master_dbh);
$sb->create_dbs($master_dbh, [qw(test)]);

# #############################################################################
# Issue 22: mk-table-sync fails with uninitialized value at line 2330
# #############################################################################
$sb->use('master', "-D test < $trunk/mk-table-sync/t/samples/issue_22.sql");
$sb->use('master', "-D test -e \"SET SQL_LOG_BIN=0; INSERT INTO test.messages VALUES (1,2,'author','2008-09-12 00:00:00','1','0','headers','msg');\"");
$sb->create_dbs($master_dbh, [qw(test2)]);
$sb->use('master', "-D test2 < $trunk/mk-table-sync/t/samples/issue_22.sql");

$output = 'foo'; # To make explicitly sure that the following command
                 # returns blank because there are no rows and not just that
                 # $output was blank from a previous test
$output = `/tmp/12345/use -D test2 -e 'SELECT * FROM messages'`;
ok(!$output, 'test2.messages is empty before sync (issue 22)');

$output = `$trunk/mk-table-sync/mk-table-sync --no-check-slave --execute u=msandbox,p=msandbox,P=12345,h=127.1,D=test,t=messages u=msandbox,p=msandbox,P=12345,h=127.1,D=test2,t=messages 2>&1`;
ok(!$output, 'Synced test.messages to test2.messages on same host (issue 22)');

$output     = `/tmp/12345/use -D test  -e 'SELECT * FROM messages'`;
my $output2 = `/tmp/12345/use -D test2 -e 'SELECT * FROM messages'`;
is($output, $output2, 'test2.messages matches test.messages (issue 22)');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
