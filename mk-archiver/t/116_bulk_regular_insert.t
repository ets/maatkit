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

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 4;
}

my $output;
my $cnf = "/tmp/12345/my.sandbox.cnf";
# Add path to samples to Perl's INC so the tool can find the module.
my $cmd = "perl -I $trunk/mk-archiver/t/samples $trunk/mk-archiver/mk-archiver";

# #############################################################################
# First run without the plugin to get a reference for how the tables should
# be after a normal bulk insert run.
# #############################################################################
$sb->load_file('master', "mk-archiver/t/samples/bulk_regular_insert.sql");
$dbh->do('use bri');

output(
   sub { mk_archiver::main("--source", "F=$cnf,D=bri,t=t", qw(--dest t=t_arch --where 1=1 --bulk-insert --limit 3)) },
);

my $t_rows      = $dbh->selectall_arrayref('select * from t order by id');
my $t_arch_rows = $dbh->selectall_arrayref('select * from t_arch order by id');

is_deeply(
   $t_rows,
   [ ['10', 'jj', '11:11:10'] ],
   "Table after normal bulk insert"
);

is_deeply(
   $t_arch_rows,
   [
      ['1','aa','11:11:11'],
      ['2','bb','11:11:12'],
      ['3','cc','11:11:13'],
      ['4','dd','11:11:14'],
      ['5','ee','11:11:15'],
      ['6','ff','11:11:16'],
      ['7','gg','11:11:17'],
      ['8','hh','11:11:18'],
      ['9','ii','11:11:19'],
   ],
   "Archive table after normal bulk insert"
);

# #############################################################################
# Do it again with the plugin.  The tables should be identical.
# #############################################################################
$sb->load_file('master', "mk-archiver/t/samples/bulk_regular_insert.sql");
$dbh->do('use bri');

`$cmd --source F=$cnf,D=bri,t=t --dest t=t_arch,m=bulk_regular_insert --where "1=1" --bulk-insert --limit 3`;

my $bri_t_rows      = $dbh->selectall_arrayref('select * from t order by id');
my $bri_t_arch_rows = $dbh->selectall_arrayref('select * from t_arch order by id');

is_deeply(
   $bri_t_rows,
   $t_rows,
   "Table after bulk_regular_insert"
);

is_deeply(
   $bri_t_arch_rows,
   $t_arch_rows,
   "Archive table after bulk_regular_insert"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
