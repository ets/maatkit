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
require "$trunk/mk-config-diff/mk-config-diff";

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
   plan tests => 2;
}

my $cnf = '/tmp/12345/my.sandbox.cnf';
my $output;
my $retval;

# ############################################################################
# Report stuff.
# ############################################################################

$output = output(
   sub { $retval = mk_config_diff::main(
      'h=127.1,P=12345,u=msandbox,p=msandbox', 'P=12346',
      '--no-report')
   },
   stderr => 1,
);

is(
   $retval,
   1,
   "Diff but no report"
);

is(
   $output,
   "",
   "Diff but not output because --no-report"
);

# #############################################################################
# Done.
# #############################################################################
exit;
