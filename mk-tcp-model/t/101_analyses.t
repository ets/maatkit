#!/usr/bin/env perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 2;

use MaatkitTest;
shift @INC;  # our unshift (above)
shift @INC;  # MaatkitTest's unshift

require "$trunk/mk-tcp-model/mk-tcp-model";

my @args   = qw();
my $in1    = "$trunk/common/t/samples/simple-tcpdump/";
my $in2    = "$trunk/mk-tcp-model/t/samples/in/";
my $out    = "mk-tcp-model/t/samples/out/";
my $output = '';

# ############################################################################
# Basic queries that parse without problems.
# ############################################################################
ok(
   no_diff(
      sub { mk_tcp_model::main(@args, "$in1/simpletcp001.txt") },
      "$out/simpletcp001.txt",
   ),
   'Analysis for simpletcp001.txt'
);

ok(
   no_diff(
      sub { mk_tcp_model::main(@args, "$in2/sorted001.txt",
         qw(--type requests --run-time 1)) },
      "$out/sorted001.txt",
   ),
   'Analysis for sorted001.txt (issue 1341)'
);

# #############################################################################
# Done.
# #############################################################################
exit;
