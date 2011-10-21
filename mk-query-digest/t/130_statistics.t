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

# See 101_slowlog_analyses.t or http://code.google.com/p/maatkit/wiki/Testing
shift @INC;  # our unshift (above)
shift @INC;  # MaatkitTest's unshift

require "$trunk/mk-query-digest/mk-query-digest";

my @args   = qw(--no-report --statistics);
my $sample = "$trunk/common/t/samples/";

ok(
   no_diff(
      sub { mk_query_digest::main(@args, $sample.'slow002.txt') },
      "mk-query-digest/t/samples/stats-slow002.txt"
   ),
   '--statistics for slow002.txt',
);

# #############################################################################
# Done.
# #############################################################################
exit;
