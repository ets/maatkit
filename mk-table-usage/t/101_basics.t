#!/usr/bin/env perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 6;

use MaatkitTest;
shift @INC;  # our unshift (above)
shift @INC;  # MaatkitTest's unshift

require "$trunk/mk-table-usage/mk-table-usage";

my @args   = qw();
my $in     = "$trunk/mk-table-usage/t/samples/in/";
my $out    = "mk-table-usage/t/samples/out/";
my $output = '';

# ############################################################################
# Basic queries that parse without problems.
# ############################################################################
ok(
   no_diff(
      sub { mk_table_usage::main(@args, "$in/slow001.txt") },
      "$out/slow001.txt",
   ),
   'Analysis for slow001.txt'
);

ok(
   no_diff(
      sub { mk_table_usage::main(@args, "$in/slow002.txt") },
      "$out/slow002.txt",
   ),
   'Analysis for slow002.txt (issue 1237)'
);

ok(
   no_diff(
      sub { mk_table_usage::main(@args, '--query',
         'DROP TABLE IF EXISTS t') },
      "$out/drop-table-if-exists.txt",
   ),
   'DROP TABLE IF EXISTS'
);

# ############################################################################
# --id-attribute
# ############################################################################
ok(
   no_diff(
      sub { mk_table_usage::main(@args, "$in/slow003.txt",
         qw(--id-attribute ts)) },
      "$out/slow003-003.txt",
   ),
   'Analysis for slow003.txt with --id-attribute'
);

# ############################################################################
# --constant-data-value
# ############################################################################
$output = output(
   sub { mk_table_usage::main('--query', 'INSERT INTO t VALUES (42)',
      qw(--constant-data-value <const>)) },
);
like(
   $output,
   qr/SELECT <const>/,
   "--constant-data-value"
);

# ############################################################################
# Queries with tables that can't be resolved.
# ############################################################################

# The tables in the WHERE can't be resolved so there's no WHERE access listed.
ok(
   no_diff(
      sub { mk_table_usage::main(@args, "$in/slow003.txt") },
      "$out/slow003-001.txt",
   ),
   'Analysis for slow003.txt'
);


# #############################################################################
# Done.
# #############################################################################
exit;
