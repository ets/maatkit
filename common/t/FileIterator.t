#!/usr/bin/perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 12;

use FileIterator;
use MaatkitTest;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $sample = "$trunk/common/t/samples/";

my ($next_fh, $fh, $name, $size);
my $fi = new FileIterator();
isa_ok($fi, 'FileIterator');

# #############################################################################
# Empty list of filenames.
# #############################################################################
$next_fh = $fi->get_file_itr(qw());
is( ref $next_fh, 'CODE', 'get_file_itr() returns a subref' );
( $fh, $name, $size ) = $next_fh->();
is( "$fh", '*main::STDIN', 'Got STDIN for empty list' );
is( $name, undef, 'STDIN has no name' );
is( $size, undef, 'STDIN has no size' );

# #############################################################################
# Magical '-' filename.
# #############################################################################
$next_fh = $fi->get_file_itr(qw(-));
( $fh, $name, $size ) = $next_fh->();
is( "$fh", '*main::STDIN', 'Got STDIN for "-"' );

# #############################################################################
# Real filenames.
# #############################################################################
$next_fh = $fi->get_file_itr("$sample/memc_tcpdump009.txt", "$sample/empty");
( $fh, $name, $size ) = $next_fh->();
is( ref $fh, 'GLOB', 'Open filehandle' );
is( $name, "$sample/memc_tcpdump009.txt", "Got filename for $name");
is( $size, 587, "Got size for $name");
( $fh, $name, $size ) = $next_fh->();
is( $name, "$sample/empty", "Got filename for $name");
is( $size, 0, "Got size for $name");
( $fh, $name, $size ) = $next_fh->();
is( $fh, undef, 'Ran off the end of the list' );

# #############################################################################
# Done.
# #############################################################################
exit;
