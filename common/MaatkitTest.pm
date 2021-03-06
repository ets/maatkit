# This program is copyright 2009-2010 Percona Inc.
# Feedback and improvements are welcome.
#
# THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
# systems, you can issue `man perlgpl' or `man perlartistic' to read these
# licenses.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307  USA.
# ###########################################################################
# MaatkitTest package $Revision: 7598 $
# ###########################################################################
package MaatkitTest;

# These are common subs used in Maatkit test scripts.  Any file
# arguments (like no_diff() $expected_output) are relative to
# MAATKIT_WORKING_COPY.  So passing "commont/t/samples/foo" means
# "MAATKIT_WORKING_COPY/common/t/samples/foo".  Do not BAIL_OUT() because
# this terminates the *entire* test process; die instead.  All
# subs are exported by default, so is the variable $trunk, so there's
# no need to import() in the test scripts.

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};
our $trunk = $ENV{MAATKIT_WORKING_COPY};

our $sandbox_version = '';
eval {
   chomp(my $v = `$trunk/sandbox/mk-test-env version`);
   $sandbox_version = $v if $v;
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;
use Time::HiRes qw(usleep);
use POSIX qw(signal_h);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

require Exporter;
our @ISA         = qw(Exporter);
our %EXPORT_TAGS = ();
our @EXPORT      = qw(
   output
   load_data
   load_file
   parse_file
   wait_until
   wait_for
   test_log_parser
   test_protocol_parser
   test_packet_parser
   no_diff
   throws_ok
   remove_traces
   $trunk
   $dsn_opts
   $sandbox_version
);
our @EXPORT_OK   = qw();

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

our $dsn_opts = [
   {
      key  => 'A',
      desc => 'Default character set',
      dsn  => 'charset',
      copy => 1,
   },
   {
      key  => 'D',
      desc => 'Database to use',
      dsn  => 'database',
      copy => 1,
   },
   {
      key  => 'F',
      desc => 'Only read default options from the given file',
      dsn  => 'mysql_read_default_file',
      copy => 1,
   },
   {
      key  => 'h',
      desc => 'Connect to host',
      dsn  => 'host',
      copy => 1,
   },
   {
      key  => 'p',
      desc => 'Password to use when connecting',
      dsn  => 'password',
      copy => 1,
   },
   {
      key  => 'P',
      desc => 'Port number to use for connection',
      dsn  => 'port',
      copy => 1,
   },
   {
      key  => 'S',
      desc => 'Socket file to use for connection',
      dsn  => 'mysql_socket',
      copy => 1,
   },
   {
      key  => 't',
      desc => 'Table',
      dsn  => undef,
      copy => 1,
   },
   {
      key  => 'u',
      desc => 'User for login if not current user',
      dsn  => 'user',
      copy => 1,
   },
];

# Runs code, captures and returns its output.
# Optional arguments:
#   * file    scalar: capture output to this file (default none)
#   * stderr  scalar: capture STDERR (default no)
#   * die     scalar: die if code dies (default no)
#   * trf     coderef: pass output to this coderef (default none)
sub output {
   my ( $code, %args ) = @_;
   die "I need a code argument" unless $code;
   my ($file, $stderr, $die, $trf) = @args{qw(file stderr die trf)};

   my $output = '';
   if ( $file ) { 
      open *output_fh, '>', $file
         or die "Cannot open file $file: $OS_ERROR";
   }
   else {
      open *output_fh, '>', \$output
         or die "Cannot capture output to variable: $OS_ERROR";
   }
   local *STDOUT = *output_fh;

   # If capturing STDERR we must dynamically scope (local) STDERR
   # in the outer scope of the sub.  If we did,
   #   if ( $args{stderr} ) { local *STDERR; ... }
   # then STDERR would revert to its original value outside the if
   # block.
   local *STDERR     if $args{stderr};  # do in outer scope of this sub
   *STDERR = *STDOUT if $args{stderr};

   eval { $code->() };

   if ( $EVAL_ERROR ) {
      die $EVAL_ERROR if $die;
      warn $EVAL_ERROR;
   }
   close *output_fh;

   # Possible transform output before returning it.  This doesn't work
   # if output was captured to a file.
   $output = $trf->($output) if $trf;

   return $output;
}

# Load data from file and removes spaces.  Used to load tcpdump dumps.
sub load_data {
   my ( $file ) = @_;
   $file = "$trunk/$file";
   open my $fh, '<', $file or die "Cannot open $file: $OS_ERROR";
   my $contents = do { local $/ = undef; <$fh> };
   close $fh;
   (my $data = join('', $contents =~ m/(.*)/g)) =~ s/\s+//g;
   return $data;
}

# Slurp file and return its entire contents.
sub load_file {
   my ( $file, %args ) = @_;
   $file = "$trunk/$file";
   open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
   my $contents = do { local $/ = undef; <$fh> };
   close $fh;
   chomp $contents if $args{chomp_contents};
   return $contents;
}

sub parse_file {
   my ( $file, $p, $ea ) = @_;
   $file = "$trunk/$file";
   my @e;
   eval {
      open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
      my %args = (
         next_event => sub { return <$fh>;    },
         tell       => sub { return tell $fh; },
         fh         => $fh,
      );
      while ( my $e = $p->parse_event(%args) ) {
         push @e, $e;
         $ea->aggregate($e) if $ea;
      }
      close $fh;
   };
   die $EVAL_ERROR if $EVAL_ERROR;
   return \@e;
}

# Wait until code returns true.
sub wait_until {
   my ( $code, $t, $max_t ) = @_;
   my $slept     = 0;
   my $sleep_int = $t || .5;
   $t     ||= .5;
   $max_t ||= 5;
   $t *= 1_000_000;
   while ( $slept <= $max_t ) {
      return if $code->();
      usleep($t);
      $slept += $sleep_int;
   }
   return;
}

# Wait t seconds for code to return.
sub wait_for {
   my ( $code, $t ) = @_;
   $t ||= 0;
   my $mask   = POSIX::SigSet->new(&POSIX::SIGALRM);
   my $action = POSIX::SigAction->new(
      sub { die },
      $mask,
   );
   my $oldaction = POSIX::SigAction->new();
   sigaction(&POSIX::SIGALRM, $action, $oldaction);
   eval {
      alarm $t;
      $code->();
      alarm 0;
   };
   if ( $EVAL_ERROR ) {
      # alarm was raised
      return 1;
   }
   return 0;
}

sub _read {
   my ( $fh ) = @_;
   return <$fh>;
}

sub test_log_parser {
   my ( %args ) = @_;
   foreach my $arg ( qw(parser file) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $p = $args{parser};

   # Make sure caller isn't giving us something we don't understand.
   # We could ignore it, but then caller might not get the results
   # they expected.
   map  { die "What is $_ for?"; }
   grep { $_ !~ m/^(?:parser|misc|file|result|num_events|oktorun)$/ }
   keys %args;

   my $file = "$trunk/$args{file}";
   my @e;
   eval {
      open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
      my %parser_args = (
         next_event => sub { return _read($fh); },
         tell       => sub { return tell($fh);  },
         fh         => $fh,
         misc       => $args{misc},
         oktorun    => $args{oktorun},
      );
      while ( my $e = $p->parse_event(%parser_args) ) {
         push @e, $e;
      }
      close $fh;
   };

   is(
      $EVAL_ERROR,
      '',
      "No error on $args{file}"
   );

   if ( defined $args{result} ) {
      is_deeply(
         \@e,
         $args{result},
         $args{file}
      ) or print "Got: ", Dumper(\@e);
   }

   if ( defined $args{num_events} ) {
      is(
         scalar @e,
         $args{num_events},
         "$args{file} num_events"
      );
   }

   return \@e;
}

sub test_protocol_parser {
   my ( %args ) = @_;
   foreach my $arg ( qw(parser protocol file) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $parser   = $args{parser};
   my $protocol = $args{protocol};

   # Make sure caller isn't giving us something we don't understand.
   # We could ignore it, but then caller might not get the results
   # they expected.
   map { die "What is $_ for?"; }
   grep { $_ !~ m/^(?:parser|protocol|misc|file|result|num_events|desc)$/ }
   keys %args;

   my $file = "$trunk/$args{file}";
   my @e;
   eval {
      open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
      my %parser_args = (
         next_event => sub { return _read($fh); },
         tell       => sub { return tell($fh);  },
         misc       => $args{misc},
      );
      while ( my $p = $parser->parse_event(%parser_args) ) {
         my $e = $protocol->parse_event(%parser_args, event => $p);
         push @e, $e if $e;
      }
      close $fh;
   };

   is(
      $EVAL_ERROR,
      '',
      "No error on $args{file}"
   );
   
   if ( defined $args{result} ) {
      is_deeply(
         \@e,
         $args{result},
         $args{file} . ($args{desc} ? ": $args{desc}" : '')
      ) or print "Got: ", Dumper(\@e);
   }

   if ( defined $args{num_events} ) {
      is(
         scalar @e,
         $args{num_events},
         "$args{file} num_events"
      );
   }

   return \@e;
}

sub test_packet_parser {
   my ( %args ) = @_;
   foreach my $arg ( qw(parser file) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $parser   = $args{parser};

   # Make sure caller isn't giving us something we don't understand.
   # We could ignore it, but then caller might not get the results
   # they expected.
   map { die "What is $_ for?"; }
   grep { $_ !~ m/^(?:parser|misc|file|result|desc|oktorun)$/ }
   keys %args;

   my $file = "$trunk/$args{file}";
   my @packets;
   open my $fh, '<', $file or die "Cannot open $file: $OS_ERROR";
   my %parser_args = (
      next_event => sub { return _read($fh); },
      tell       => sub { return tell($fh);  },
      misc       => $args{misc},
      oktorun    => $args{oktorun},
   );
   while ( my $packet = $parser->parse_event(%parser_args) ) {
      push @packets, $packet;
   }

   # raw_packet is the actual dump text from the file.  It's used
   # in MySQLProtocolParser but I don't think we need to double-check
   # it here.  It will make the results very long.
   foreach my $packet ( @packets ) {
      delete $packet->{raw_packet};
   }

   if ( !is_deeply(
         \@packets,
         $args{result},
         "$args{file}" . ($args{desc} ? ": $args{desc}" : '')
      ) ) {
      print Dumper(\@packets);
   }

   return;
}

# no_diff() compares the STDOUT output of a cmd or code to expected output.
# Returns true if there are no differences between the two outputs,
# else returns false.  Dies if the cmd/code dies.  Does not capture STDERR.
# Args:
#   * cmd                 scalar or coderef: if cmd is a scalar then the
#                         cmd is ran via the shell.  if it's a coderef then
#                         the code is ran.  the latter is preferred because
#                         it generates test coverage.
#   * expected_output     scalar: file name relative to MAATKIT_WORKING_COPY
#   * args                hash: (optional) may include
#       update_sample            overwrite expected_output with cmd/code output
#       keep_output              keep last cmd/code output file
#   *   trf                      transform cmd/code output before diff
# The sub dies if cmd or code dies.  STDERR is not captured.
sub no_diff {
   my ( $cmd, $expected_output, %args ) = @_;
   die "I need a cmd argument" unless $cmd;
   die "I need an expected_output argument" unless $expected_output;

   $expected_output = "$trunk/$expected_output";
   die "$expected_output does not exist" unless -f $expected_output;

   my $tmp_file      = '/tmp/maatkit-test-output.txt';
   my $tmp_file_orig = '/tmp/maatkit-test-output-original.txt';

   # Determine cmd type and run it.
   if ( ref $cmd eq 'CODE' ) {
      output($cmd, file => $tmp_file);
   }
   elsif ( $args{cmd_output} ) {
      # Copy cmd output to tmp file so we don't with the original.
      open my $tmp_fh, '>', $tmp_file or die "Cannot open $tmp_file: $OS_ERROR";
      print $tmp_fh $cmd;
      close $tmp_fh;
   }
   else {
      `$cmd > $tmp_file`;
   }

   # Do optional arg stuff.
   `cp $tmp_file $tmp_file_orig`;
   if ( my $trf = $args{trf} ) {
      `$trf $tmp_file_orig > $tmp_file`;
   }
   if ( my $sed = $args{sed} ) {
      foreach my $sed_args ( @{$args{sed}} ) {
         `sed $sed_args $tmp_file`;
      }
   }

   # diff the outputs.
   my $retval = system("diff $tmp_file $expected_output");

   # diff returns 0 if there were no differences,
   # so !0 = 1 = no diff in our testing parlance.
   $retval = $retval >> 8; 

   if ( $retval ) {
      if ( $ENV{UPDATE_SAMPLES} || $args{update_sample} ) {
         `cat $tmp_file > $expected_output`;
         print STDERR "Updated $expected_output\n";
      }
   }

   # Remove our tmp files.
   `rm -f $tmp_file $tmp_file_orig`
      unless $ENV{KEEP_OUTPUT} || $args{keep_output};

   return !$retval;
}

sub throws_ok {
   my ( $code, $pat, $msg ) = @_;
   eval { $code->(); };
   like ( $EVAL_ERROR, $pat, $msg );
}

# Remove /*maatkit ...*/ trace comments from the given SQL statement(s).
# Traces are added in ChangeHandler::process_rows().
sub remove_traces {
   my ( $sql ) = @_;
   my $trace_pat = qr/ \/\*maatkit .+?\*\//;
   if ( ref $sql && ref $sql eq 'ARRAY' ) {
      map { $_ =~ s/$trace_pat//gm } @$sql;
   }
   else {
      $sql =~ s/$trace_pat//gm;
   }
   return $sql;
}

1;

# ###########################################################################
# End MaatkitTest package
# ###########################################################################
