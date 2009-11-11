#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 2;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

require "../GeneralLogParser.pm";

my $p = new GeneralLogParser();

sub run_test {
   my ( $def ) = @_;
   map     { die "What is $_ for?" }
      grep { $_ !~ m/^(?:misc|file|result|num_events)$/ }
      keys %$def;
   my @e;
   my $num_events = 0;
   eval {
      open my $fh, "<", $def->{file} or die $OS_ERROR;
      $num_events++ while $p->parse_event($fh, $def->{misc}, sub { push @e, @_ });
      close $fh;
   };
   is($EVAL_ERROR, '', "No error on $def->{file}");
   if ( defined $def->{result} ) {
      is_deeply(\@e, $def->{result}, $def->{file})
         or print "Got: ", Dumper(\@e);
   }
   if ( defined $def->{num_events} ) {
      is($num_events, $def->{num_events}, "$def->{file} num_events");
   }
}

run_test({
   file => 'samples/genlog001.txt',
   result => [
      {  ts         => '051007 21:55:24',
         Thread_id  => '42',
         arg        => 'administrator command: Connect;',
         bytes      => 31,
         cmd        => 'Admin',
         db         => 'db1',
         host       => 'localhost',
         pos_in_log => 0,
         user       => 'root',
      },
      {  ts         => undef,
         Thread_id  => '42',
         arg        => 'SELECT foo 
                         FROM tbl
                         WHERE col=12345
                         ORDER BY col;',
         bytes      => 125,
         cmd        => 'Query',
         pos_in_log => 58,
      },
      {  ts         => undef,
         Thread_id  => '42',
         arg        => 'administrator command: Quit;',
         bytes      => 28,
         cmd        => 'Admin',
         pos_in_log => 104,
      },
      {  ts         => '061226 15:42:36',
         Thread_id  => '11',
         arg        => 'administrator command: Connect;',
         bytes      => 31,
         cmd        => 'Admin',
         host       => 'localhost',
         pos_in_log => 244,
         user       => 'root',
      },
      {  ts         => undef,
         Thread_id  => '11',
         arg        => 'administrator command: Init DB;',
         bytes      => 31,
         cmd        => 'Admin',
         db         => 'my_webstats',
         pos_in_log => 300,
      },
      {  ts         => undef,
         Thread_id  => '11',
         arg        => 'SELECT DISTINCT col FROM tbl WHERE foo=20061219;',
         bytes      => 48,
         cmd        => 'Query',
         pos_in_log => 346,
       
      },
      {  ts         => '061226 16:44:48',
         Thread_id  => '11',
         arg        => 'administrator command: Quit;',
         bytes      => 28,
         cmd        => 'Admin',
         pos_in_log => 428,
      },
   ]
});

# #############################################################################
# Done.
# #############################################################################
exit;
