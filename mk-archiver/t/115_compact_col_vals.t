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
require "$trunk/mk-archiver/mk-archiver";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');
my $slave_dbh = $sb->get_dbh_for('slave1');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 5;
}

my $output;
my $cnf = "/tmp/12345/my.sandbox.cnf";
# Add path to samples to Perl's INC so the tool can find the module.
my $cmd = "perl -I $trunk/mk-archiver/t/samples $trunk/mk-archiver/mk-archiver";

# ###########################################################################
# Bulk delete with limit that results in 2 chunks.
# ###########################################################################
$sb->load_file('master', "mk-archiver/t/samples/compact_col_vals.sql");
$dbh->do('use cai');

is_deeply(
   $dbh->selectall_arrayref('select * from `t` order by id'),
   [
      [   1, 'one'                ], 
      [   2, 'two'                ], 
      [   3, 'three'              ], 
      [   4, 'four'               ], 
      [   5, 'five'               ], 
      [   9, 'nine'               ], 
      [  11, 'eleven'             ], 
      [  13, 'thirteen'           ],
      [  14, 'fourteen'           ], 
      [  50, 'fifty'              ], 
      [  51, 'fifty one'          ], 
      [ 200, 'two hundred'        ], 
      [ 300, 'three hundred'      ], 
      [ 304, 'three hundred four' ], 
      [ 305, 'three hundred five' ], 
   ],
   'Table before compacting'
);

`$cmd --purge --no-safe-auto-inc --source F=$cnf,D=cai,t=t,m=compact_col_vals --where "1=1"`;

my $compact_vals = $dbh->selectall_arrayref('select * from `r` order by id');

is_deeply(
   $dbh->selectall_arrayref('select * from `t` order by id'),
   $compact_vals,
   'Compacted values'
);

my $autoinc = $dbh->selectrow_hashref('show table status from `cai` like "t"');
is(
   $autoinc->{auto_increment},
   16,
   "Reset AUTO_INCREMENT"
);

# Try again with t2 which does not start with 1.
`$cmd --purge --no-safe-auto-inc --source F=$cnf,D=cai,t=t2,m=compact_col_vals --where "1=1"`;

is_deeply(
   $dbh->selectall_arrayref('select * from `t2` order by id'),
   $compact_vals,
   'Compacted values (t2)'
);

$autoinc = $dbh->selectrow_hashref('show table status from `cai` like "t2"');
is(
   $autoinc->{auto_increment},
   16,
   "Reset AUTO_INCREMENT (t2)"
);

# #############################################################################
# Done.
# #############################################################################
#$sb->wipe_clean($dbh);
exit;
