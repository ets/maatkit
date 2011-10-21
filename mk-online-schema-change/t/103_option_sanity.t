#!/usr/bin/env perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 4;

use MaatkitTest;

my $output  = "";
my $cmd     = "$trunk/mk-online-schema-change/mk-online-schema-change";

$output = `$cmd`;
like(
   $output,
   qr/A DSN with a t part must be specified/,
   "Must specify a DSN with t part"
);

$output = `$cmd h=127.1,P=12345,u=msandbox,p=msandbox`;
like(
   $output,
   qr/The DSN must specify a t/,
   "DSN must specify t part"
);

$output = `$cmd h=127.1,P=12345,u=msandbox,p=msandbox h=127.1`;
like(
   $output,
   qr/Specify only one DSN/,
   "Only 1 DSN allowed"
);

$output = `$cmd h=127.1,P=12345,t=tbl`;
like(
   $output,
   qr/No database was specified/,
   "Either DSN D part or --database required"
);

# #############################################################################
# Done.
# #############################################################################
exit;
