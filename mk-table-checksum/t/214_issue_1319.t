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
require "$trunk/mk-table-checksum/mk-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 1;
}

my $output;
my $res;
my $cnf='/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/mk-table-checksum/mk-table-checksum -F $cnf 127.1";

# #############################################################################
# Issue 1319: mk-table-checksum -w causes perl error
# #############################################################################
$output = `$trunk/mk-table-checksum/mk-table-checksum h=127.1,P=12345,u=msandbox,p=msandbox P=12346 -d mysql -t user --slave-lag -w 60 2>&1`;

unlike(
   $output,
   qr/Odd number of elements/,
   "--wait doesn't cause error (issue 1319)"
);

# #############################################################################
# Done.
# #############################################################################
exit;
