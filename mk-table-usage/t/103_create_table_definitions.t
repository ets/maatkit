#!/usr/bin/env perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 1;

use MaatkitTest;
shift @INC;  # our unshift (above)
shift @INC;  # MaatkitTest's unshift

require "$trunk/mk-table-usage/mk-table-usage";

my @args   = qw();
my $in     = "$trunk/mk-table-usage/t/samples/in/";
my $out    = "mk-table-usage/t/samples/out/";
my $output = '';

# ############################################################################
# Test --create-table-definitions
# ############################################################################

# Without --create-table-definitions, the tables wouldn't be db-qualified.
ok(
   no_diff(
      sub { mk_table_usage::main(@args,
         '--query', 'select city from city where city="New York"',
         '--create-table-definitions',
            "$trunk/common/t/samples/mysqldump-no-data/all-dbs.txt") },
      "$out/create-table-defs-001.txt",
   ),
   '--create-table-definitions'
);

# #############################################################################
# Done.
# #############################################################################
exit;
