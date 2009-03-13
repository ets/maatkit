#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 58;

require "../OptionParser-2.pm";
require "../DSNParser.pm";

my $dp = new DSNParser();
my $o  = new OptionParser(
   descr  => 'synchronizes data efficiently between MySQL tables.',
   prompt => '[OPTIONS]  DSN [DSN ...]',
   dsn    => $dp,
);

isa_ok($o, 'OptionParser');

my @opt_specs;
my %opts;
my %short_opts;

@opt_specs = $o->_pod_to_specs('samples/pod_sample_01.txt');
is_deeply(
   \@opt_specs,
   [
      { spec => 'database|D=s', desc => 'database string'            },
      { spec => 'port|p=i',     desc => 'port (default 3306)'        },
      { spec => 'price=f',      desc => 'price float (default 1.23)' },
      { spec => 'hash-req=H',   desc => 'hash required'              },
      { spec => 'hash-opt=h',   desc => 'hash optional'              },
      { spec => 'array-req=A',  desc => 'array required'             },
      { spec => 'array-opt=a',  desc => 'array optional'             },
      { spec => 'host=d',       desc => 'host DSN'                   },
      { spec => 'chunk-size=z', desc => 'chunk size'                 },
      { spec => 'time=m',       desc => 'time'                       },
      { spec => 'help+',        desc => 'help cumulative'            },
      { spec => 'magic!'        desc => 'magic negatable'            },
   ],
   'Convert POD OPTIONS to opt specs (pod_sample_01.txt)',
);

$o->_parse_specs(@opt_specs);
%opts = $o->get_opts();
is_deeply(
   \%opts,
   {
      'database'   => {
         spec           => 'database|D=s',
         desc           => 'database string',
         group          => 'default',
         short          => 'D',
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         type           => 's',
         got            => 0,
         value          => undef,
      },
      'port'       => {
         spec           => 'port|p=i',
         desc           => 'port (default 3306)',
         group          => 'default',
         short          => 'p',
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         type           => 'i',
         got            => 0,
         value          => undef,
      },
      'price'      => {
         spec           => 'price=f',
         desc           => 'price float (default 1.23)',
         group          => 'default',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         type           => 'f',
         got            => 0,
         value          => undef,
      },
      'hash-req'   => {
         spec           => 'hash-req=H',
         desc           => 'hash required',
         group          => 'default',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         type           => 'H',
         got            => 0,
         value          => undef,
      },
      'hash-opt'   => {
         spec           => 'hash-opt=h',
         desc           => 'hash optional',
         group          => 'default',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         type           => 'h',
         got            => 0,
         value          => undef,
      },
      'array-req'  => {
         spec           => 'array-req=A',
         desc           => 'array required',
         group          => 'default',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         type           => 'A',
         got            => 0,
         value          => undef,
      },
      'array-opt'  => {
         spec           => 'array-opt',
         desc           => 'array optional',
         group          => 'default',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         type           => 'a',
         got            => 0,
         value          => undef,
      },
      'host'       => {
         spec           => 'host=d',
         desc           => 'host DSN',
         group          => 'default',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         type           => 'd',
         got            => 0,
         value          => undef,
      },
      'chunk-size' => {
         spec           => 'chunk-size=z',
         desc           => 'chunk size',
         group          => 'default',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         type           => 'z',
         got            => 0,
         value          => undef,
      },
      'time'       => {
         spec           => 'time=m',
         desc           => 'time',
         group          => 'default',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 0,
         is_required    => 0,
         type           => 'm',
         got            => 0,
         value          => undef,
      },
      'help'       => {
         spec           => 'help+',
         desc           => 'help cumulative',
         group          => 'default',
         short          => undef,
         is_cumulative  => 1,
         is_negatable   => 0,
         is_required    => 0,
         type           => undef,
         got            => 0,
         value          => undef,
      },
      'magic'      => {
         spec           => 'magic!',
         desc           => 'magic negatable',
         group          => 'default',
         short          => undef,
         is_cumulative  => 0,
         is_negatable   => 1,
         is_required    => 0,
         type           => undef,
         got            => 0,
         value          => undef,
      }
   }
   'Parse opt specs'
);

%short_opts = $o->get_short_opts();
is_deeply(
   \%short_opts,
   {
      'D' => 'database',
      'p' => 'port',
   }
   'Get short opts'
);

is(
   $o->get('database'),
   undef,
   'Get valueless long opt'
);

is(
   $o->get('p'),
   undef,
   'Get valuless short opt'
);

eval { $o->get('foo'); };
like(
   $EVAL_ERROR,
   qr/Option --foo does not exist/,
   'Die trying to get() nonexistent long opt'
);

eval { $o->get('x'); };
like(
   $EVAL_ERROR,
   qr/Option --x does not exist/,
   'Die trying to get() nonexistent short opt'
);

#
# TODO: convert/incorporate the "legacy" tests below
#

# #############################################################################
# Tests with defaultset!, defaults-file|F=s, dog|D=s, foo!, love|l+
# #############################################################################
my @specs = (
   { s => 'defaultset!',       d => 'alignment test with a very long thing '
                                    . 'that is longer than 80 characters wide '
                                    . 'and must be wrapped' },
   { s => 'defaults-file|F=s', d => 'alignment test' },
   { s => 'dog|D=s',           d => 'Dogs are fun' },
   { s => 'foo!',              d => 'Foo' },
   { s => 'love|l+',           d => 'And peace' },
);

my $p = new OptionParser(@specs);
my %defaults = ( foo => 1 );
my %opts;
my %basic = ( version => undef, help => undef );

%opts = $p->parse(%defaults);
is_deeply(
   \%opts,
   { %basic, foo => 1, D => undef, l => undef, F => undef, defaultset => undef },
   'Basics works'
);

@ARGV = qw(--nofoo);
%opts = $p->parse(%defaults);
is_deeply(
   \%opts,
   { %basic, foo => 0, D => undef, l => undef, F => undef, defaultset => undef },
   'Can negate negatable opt'
);

@ARGV = qw(--nodog);
%opts = $p->parse(%defaults);
is_deeply(
   \%opts,
   { %basic, foo => 1, D => undef, l => undef, F => undef, defaultset => undef },
   'Cannot negate non-negatable opt'
);
is($p->{__error__}, 1, 'Trying to negate non-negatable opt sets an error');

@ARGV = qw(--bar);
%opts = $p->parse();
ok(!defined $opts{bar}, 'Completely nonexistent opt is ignored');

$defaults{bone} = 1;
eval {
   %opts = $p->parse(%defaults);
};
is ($EVAL_ERROR, "Cannot set default for non-existent option 'bone'\n", 'No bone');

delete $defaults{bone};
@ARGV = qw(--love -l -l);
%opts = $p->parse(%defaults);
is_deeply(
   \%opts,
   { %basic, foo => 1, D => undef, l => 3, F => undef, defaultset => undef },
   'More love'
);

$p->{prompt} = '<options>';
is($p->usage,
<<EOF
OptionParser.t   For more details, please use the --help option, or try 'perldoc
OptionParser.t' for complete documentation.

Usage: OptionParser.t <options>

Options:
  --defaults-file -F  alignment test
  --[no]defaultset    alignment test with a very long thing that is longer than
                      80 characters wide and must be wrapped
  --dog           -D  Dogs are fun
  --[no]foo           Foo
  --help              Show this help message
  --love          -l  And peace
  --version           Output version information and exit

Options and values after processing arguments:
  --defaults-file     (No value)
  --defaultset        FALSE
  --dog               (No value)
  --foo               FALSE
  --help              FALSE
  --love              (No value)
  --version           FALSE
EOF
, 'Options aligned and prompt included'
);

# #############################################################################
# Tests with database|D=s, nouniquechecks!
# #############################################################################

$p = new OptionParser(
      { s => 'database|D=s',      d => 'Specify the database for all tables' },
      { s => 'nouniquechecks!',   d => 'Set UNIQUE_CHECKS=0 before LOAD DATA INFILE' },
);
is($p->usage,
<<EOF
OptionParser.t   For more details, please use the --help option, or try 'perldoc
OptionParser.t' for complete documentation.

Usage: OptionParser.t <options>

Options:
  --database        -D  Specify the database for all tables
  --help                Show this help message
  --[no]nouniquechecks  Set UNIQUE_CHECKS=0 before LOAD DATA INFILE
  --version             Output version information and exit

Options and values after processing arguments:
  --database            (No value)
  --help                FALSE
  --nouniquechecks      FALSE
  --version             FALSE
EOF
, 'Options aligned when short options shorter than long, no-usage defaults to <options>'
);

# #############################################################################
# Tests with cat|C=s
# #############################################################################

$p = new OptionParser(
   { s => 'cat|C=s', d => 'How to catch the cat; required' }
);

%opts = $p->parse();
is(
   $p->{__error__},
   1,
   'Required option sets error',
);

is_deeply(
   $p->{errors},
   ['Required option --cat must be specified'],
   'Note set upon missing --cat',
);

$p->{prompt} = 'foofoo';
$p->{descr}  = 'barbar';
is($p->errors,
<<EOF
Usage: OptionParser.t foofoo

Errors in command-line arguments:
  * Required option --cat must be specified

OptionParser.t barbar  For more details, please use the --help option, or try
'perldoc OptionParser.t' for complete documentation.
EOF
, 'Error output includes note about missing cat');

@ARGV = qw(--cat net);
%opts = $p->parse();
is_deeply(
   \%opts,
   { %basic, C => 'net' },
   'Required option OK',
);

# #############################################################################
# Tests with ignore|i, replace|r, delete|d
# #############################################################################

$p = new OptionParser(
      { s => 'ignore|i',    d => 'Use IGNORE for INSERT statements' },
      { s => 'replace|r',   d => 'Use REPLACE instead of INSERT statements' },
      '--ignore and --replace are mutually exclusive.',
);

is($p->usage, <<EOF
OptionParser.t   For more details, please use the --help option, or try 'perldoc
OptionParser.t' for complete documentation.

Usage: OptionParser.t <options>

Options:
  --help        Show this help message
  --ignore  -i  Use IGNORE for INSERT statements
  --replace -r  Use REPLACE instead of INSERT statements
  --version     Output version information and exit
  --ignore and --replace are mutually exclusive.

Options and values after processing arguments:
  --help        FALSE
  --ignore      FALSE
  --replace     FALSE
  --version     FALSE
EOF
, 'Usage with instructions');

@ARGV = qw(--replace);
%opts = $p->parse();
is(
   $p->{__error__}, undef, '--replace does not trigger error',
);

@ARGV = qw(--ignore --replace);
%opts = $p->parse();
is(
   $p->{__error__}, 1,
   '--ignore --replace triggers error',
);

is_deeply(
   $p->{errors},
   ['--ignore and --replace are mutually exclusive.'],
   'Note set when instruction violated',
);

$p = new OptionParser(
      { s => 'ignore|i',    d => 'Use IGNORE for INSERT statements' },
      { s => 'replace|r',   d => 'Use REPLACE instead of INSERT statements' },
      { s => 'delete|d',    d => 'Delete' },
      '-ird are mutually exclusive.',
);

@ARGV = qw(--ignore --replace);
%opts = $p->parse();
is(
   $p->{__error__}, 1, 
   '--ignore --replace triggers error when short spec used',
);

is_deeply(
   $p->{errors},
   ['--ignore, --replace and --delete are mutually exclusive.'],
   'Note set with long opt name and nice commas when instruction violated',
);

eval {
   $p = new OptionParser(
         { s => 'ignore|i',    d => 'Use IGNORE for INSERT statements' },
         { s => 'replace|r',   d => 'Use REPLACE instead of INSERT statements' },
         { s => 'delete|d',    d => 'Delete' },
         'Use one and only one of --insert, --replace, or --delete.',
   );
};
like($EVAL_ERROR, qr/No such option 'insert'/, 'Bad option in one-and-only-one');

$p = new OptionParser(
      { s => 'ignore|i',    d => 'Use IGNORE for INSERT statements' },
      { s => 'replace|r',   d => 'Use REPLACE instead of INSERT statements' },
      { s => 'delete|d',    d => 'Delete' },
      'Use one and only one of --ignore, --replace, or --delete.',
);
@ARGV = qw(--ignore --replace);
%opts = $p->parse();

is(
   $p->{__error__}, 1,
   '--ignore --replace triggers error for one-and-only-one',
);

is_deeply(
   $p->{errors},
   ['--ignore, --replace and --delete are mutually exclusive.'],
   'Note set with one-and-only-one',
);

$p = new OptionParser(
      { s => 'ignore|i',    d => 'Use IGNORE for INSERT statements' },
      { s => 'replace|r',   d => 'Use REPLACE instead of INSERT statements' },
      { s => 'delete|d',    d => 'Delete' },
      'Use one and only one of --ignore, --replace, or --delete.',
);
@ARGV = ();
%opts = $p->parse();
is(
   $p->{__error__}, 1,
   'Missing options triggers error for one-and-only-one',
);

is_deeply(
   $p->{errors},
   ['Specify at least one of --ignore, --replace or --delete'],
   'Note set with one-and-only-one when none specified',
);

$p = new OptionParser(
      { s => 'ignore|i',    d => 'Use IGNORE for INSERT statements' },
      { s => 'replace|r',   d => 'Use REPLACE instead of INSERT statements' },
      { s => 'delete|d',    d => 'Delete' },
      'Use at least one of --ignore, --replace, or --delete.',
);
@ARGV = ();
%opts = $p->parse();
is(
   $p->{__error__}, 1,
   'Missing options triggers error for at-least-one',
);

is_deeply(
   $p->{errors},
   ['Specify at least one of --ignore, --replace or --delete'],
   'Note set with at-least-one when none specified',
);

$p = new OptionParser(
      { s => 'ignore|i',    d => 'Use IGNORE for INSERT statements' },
      { s => 'replace|r',   d => 'Use REPLACE instead of INSERT statements' },
      { s => 'delete|d',    d => 'Delete' },
      'Use at least one of --ignore, --replace, or --delete.',
);
@ARGV = qw(-ir);
%opts = $p->parse();
is_deeply(
   \%opts,
   { %basic, i => 1, r => 1, d => undef },
   'Multiple options OK for at-least-one',
);

# #############################################################################
# Tests with foo, bar
# #############################################################################

# Defaults encoded in descriptions.
$p = new OptionParser(
   { s => 'foo=i', d => 'Foo (default 5)' },
   { s => 'bar',   d => 'Bar (default)' },
);
@ARGV = ();
%opts = $p->parse();
is_deeply(
   \%opts,
   { %basic, foo => 5, bar => 1 },
   'Defaults encoded in description',
);

$p = new OptionParser(
   { s => 'foo=z', d => 'Number' },
);

@ARGV = qw(--foo 5k);
%opts = $p->parse();
is_deeply(
   \%opts,
   { %basic, foo => 1024*5, },
   '5K expanded',
);

@ARGV = qw(--foo -5k);
%opts = $p->parse();
is_deeply(
   \%opts,
   { %basic, foo => -1024*5, },
   '-5K expanded',
);

@ARGV = qw(--foo +5k);
%opts = $p->parse();
is_deeply(
   \%opts,
   { %basic, foo => '+' . (1024*5), },
   '+5K expanded',
);

@ARGV = qw(--foo 5);
%opts = $p->parse();
is_deeply(
   \%opts,
   { %basic, foo => 5 },
   '5 expanded',
);

@ARGV = qw(--foo 5z);
%opts = $p->parse();
is(
   $p->{__error__}, 1,
   'Bad number value threw error',
);
is_deeply(
   $p->{errors},
   ['Invalid --foo argument'],
   'Bad number argument set note',
);

$p = new OptionParser(
   { s => 'foo=m', d => 'Time' },
   { s => 'bar=m', d => 'Time (suffix m)' },
);
@ARGV = qw(--foo 5h --bar 5);
%opts = $p->parse();
is_deeply(
   \%opts,
   { %basic, foo => 3600*5, bar => 60*5 },
   'Time value decoded',
);

is($p->usage, <<EOF
OptionParser.t   For more details, please use the --help option, or try 'perldoc
OptionParser.t' for complete documentation.

Usage: OptionParser.t <options>

Options:
  --bar      Time.  Optional suffix s=seconds, m=minutes, h=hours, d=days; if no
             suffix, m is used.
  --foo      Time.  Optional suffix s=seconds, m=minutes, h=hours, d=days; if no
             suffix, s is used.
  --help     Show this help message
  --version  Output version information and exit

Options and values after processing arguments:
  --bar      (No value)
  --foo      (No value)
  --help     FALSE
  --version  FALSE
EOF
, 'Usage for time value');

@ARGV = qw(--foo 5z);
%opts = $p->parse();
is(
   $p->{__error__}, 1,
   'Bad time value threw error',
);
is_deeply(
   $p->{errors},
   ['Invalid --foo argument'],
   'Bad time argument set note',
);

# One option disables another.
$p = new OptionParser(
   { s => 'foo=i', d => 'Foo disables --bar' },
   { s => 'bar',   d => 'Bar (default 1)' },
);
@ARGV = qw(--foo 5);
%opts = $p->parse();
is_deeply(
   \%opts,
   { %basic, foo => 5, bar => undef },
   '--foo disables --bar',
);

# Option can't disable a non-existent option.
eval {
   $p = new OptionParser(
      { s => 'foo=i', d => 'Foo disables --fox' },
      { s => 'bar',   d => 'Bar (default 1)' },
   );
};
like(
   $EVAL_ERROR,
   qr/No such option 'fox' while processing foo/,
   'Invalid option name in disable instruction',
);

# Option can't 'allowed with' a non-existent option.
eval {
   $p = new OptionParser(
      { s => 'foo=i', d => 'Foo disables --bar' },
      { s => 'bar',   d => 'Bar (default 1)' },
      'allowed with --foo: --fox',
   );
};
like(
   $EVAL_ERROR,
   qr/No such option 'fox' while processing allowed with --foo: --fox/,
   'Invalid option name in \'allowed with\' instruction',
);

is_deeply(
   [$p->get_participants('--foo --bar, --baz, -abc')],
   [qw(foo bar baz a b c)],
   'Extract option names from a string',
);

my $d = new DSNParser;
$p = new OptionParser(
   { s => 'foo=d', d => 'DSN foo' },
   { s => 'bar=d', d => 'DSN bar' },
   'DSN values in --foo default to values in --bar if COPY is yes.',
);
$p->{dsn} = $d;
is($p->usage(),
<<EOF
OptionParser.t   For more details, please use the --help option, or try 'perldoc
OptionParser.t' for complete documentation.

Usage: OptionParser.t <options>

Options:
  --bar      DSN bar
  --foo      DSN foo
  --help     Show this help message
  --version  Output version information and exit
  DSN values in --foo default to values in --bar if COPY is yes.

DSN syntax is key=value[,key=value...]  Allowable DSN keys:
  KEY  COPY  MEANING
  ===  ====  =============================================
  A    yes   Default character set
  D    yes   Database to use
  F    yes   Only read default options from the given file
  P    yes   Port number to use for connection
  S    yes   Socket file to use for connection
  h    yes   Connect to host
  p    yes   Password to use when connecting
  u    yes   User for login if not current user

Options and values after processing arguments:
  --bar      (No value)
  --foo      (No value)
  --help     FALSE
  --version  FALSE
EOF
, 'DSN is integrated into help output');

@ARGV = ('--bar', 'D=DB,u=USER,h=localhost', '--foo', 'h=otherhost');
%opts = $p->parse();

is_deeply($opts{bar},
   {  D => 'DB',
      u => 'USER',
      S => undef,
      F => undef,
      P => undef,
      h => 'localhost',
      p => undef,
      A => undef,
   },
   'DSN parsing on type=d',
);

is_deeply($opts{foo},
   {  D => 'DB',
      u => 'USER',
      S => undef,
      F => undef,
      P => undef,
      h => 'otherhost',
      p => undef,
      A => undef,
   },
   'DSN parsing on type=d inheriting from --bar',
);

is($p->usage(%opts),
<<EOF
OptionParser.t   For more details, please use the --help option, or try 'perldoc
OptionParser.t' for complete documentation.

Usage: OptionParser.t <options>

Options:
  --bar      DSN bar
  --foo      DSN foo
  --help     Show this help message
  --version  Output version information and exit
  DSN values in --foo default to values in --bar if COPY is yes.

DSN syntax is key=value[,key=value...]  Allowable DSN keys:
  KEY  COPY  MEANING
  ===  ====  =============================================
  A    yes   Default character set
  D    yes   Database to use
  F    yes   Only read default options from the given file
  P    yes   Port number to use for connection
  S    yes   Socket file to use for connection
  h    yes   Connect to host
  p    yes   Password to use when connecting
  u    yes   User for login if not current user

Options and values after processing arguments:
  --bar      D=DB,h=localhost,u=USER
  --foo      D=DB,h=otherhost,u=USER
  --help     FALSE
  --version  FALSE
EOF
, 'DSN stringified with inheritance into post-processed args');

$p = new OptionParser(
   { s => 'foo|f=d', d => 'DSN foo' },
   { s => 'bar|b=d', d => 'DSN bar' },
   'DSN values in --foo default to values in --bar if COPY is yes.',
);
$p->{dsn} = $d;

@ARGV = ('-b', 'D=DB,u=USER,h=localhost', '-f', 'h=otherhost');
%opts = $p->parse();

is_deeply($opts{f},
   {  D => 'DB',
      u => 'USER',
      S => undef,
      F => undef,
      P => undef,
      h => 'otherhost',
      p => undef,
      A => undef,
   },
   'DSN parsing on type=d inheriting from --bar with short options',
);

# #############################################################################
# Tests with columns|C, tables|t, databases|d, books|b
# #############################################################################

$p = new OptionParser(
   { s => 'columns|C=H',    d => 'Comma-separated list of columns to output' },
   { s => 'tables|t=h',     d => 'Comma-separated list of tables to output' },
   { s => 'databases|d=A',  d => 'Comma-separated list of databases to output' },
   { s => 'books|b=a',      d => 'Comma-separated list of books to output' },
);

@ARGV = ();
%opts = $p->parse;
is_deeply(
   \%opts,
   {  %basic,
      C => {},
      t => undef,
      d => [],
      b => undef,
   },
   'Comma-separated lists: uppercase created even when not given',
);

@ARGV = ('-C', 'a,b', '-t', 'd,e', '-d', 'f,g', '-b', 'o,p' );
%opts = $p->parse;
is_deeply(
   \%opts,
   {  %basic,
      C => { a => 1, b => 1},
      t => { d => 1, e => 1},
      d => [qw(f g)],
      b => [qw(o p)],
   },
   'Comma-separated lists: all processed when given',
);

is($p->usage(%opts),
<<EOF
OptionParser.t   For more details, please use the --help option, or try 'perldoc
OptionParser.t' for complete documentation.

Usage: OptionParser.t <options>

Options:
  --books     -b  Comma-separated list of books to output
  --columns   -C  Comma-separated list of columns to output
  --databases -d  Comma-separated list of databases to output
  --help          Show this help message
  --tables    -t  Comma-separated list of tables to output
  --version       Output version information and exit

Options and values after processing arguments:
  --books         o,p
  --columns       a,b
  --databases     f,g
  --help          FALSE
  --tables        d,e
  --version       FALSE
EOF
, 'Lists properly expanded into usage information',
);

$p = new OptionParser(
   { s => 'columns|C=H',    g => 'o', d => 'Comma-separated list of columns to output' },
   { s => 'tables|t=h',     g => 'p', d => 'Comma-separated list of tables to output' },
   { s => 'databases|d=A',  g => 'q', d => 'Comma-separated list of databases to output' },
   { s => 'books|b=a',      g => 'p', d => 'Comma-separated list of books to output' },
);
$p->groups(
   { k => 'p', d => 'Foofoo' },
   { k => 'q', d => 'Bizbat' },
);

is($p->usage(%opts),
<<EOF
OptionParser.t   For more details, please use the --help option, or try 'perldoc
OptionParser.t' for complete documentation.

Usage: OptionParser.t <options>

Options:
  --columns   -C  Comma-separated list of columns to output
  --help          Show this help message
  --version       Output version information and exit

Foofoo:
  --books     -b  Comma-separated list of books to output
  --tables    -t  Comma-separated list of tables to output

Bizbat:
  --databases -d  Comma-separated list of databases to output

Options and values after processing arguments:
  --books         o,p
  --columns       a,b
  --databases     f,g
  --help          FALSE
  --tables        d,e
  --version       FALSE
EOF
, 'Option groupings',
);

# #############################################################################
# Tests using wine, grapes, barely, hops, yeast
# #############################################################################

$p = new OptionParser(
   { s => 'wine',    g => 'o', d => 'wine'                       },
   { s => 'grapes',  g => 'o', d => 'grapes'                     },
   { s => 'barely',  g => 'o', d => 'barely (default yes)'       },
   { s => 'hops=s',  g => 'o', d => 'hops'                       },
   { s => 'yeast=s', g => 'o', d => 'yeast (default Montrachet)' },
   'allowed with --wine: --grapes, --yeast',
);
@ARGV = ('--wine', '--grapes', '--hops=Strisselspalt');
%opts = $p->parse();
is_deeply(
   \%opts,
   {
      wine     => 1,
      grapes   => 1,
      barely   => undef,
      hops     => undef,
      yeast    => 'Montrachet',
      version  => undef,
      help     => undef,
   },
   'Opt only allowed with other opts parses correclty'
);

@ARGV = ('--barely', '--hops=Strisselspalt');
%opts = $p->parse();
is_deeply(
   \%opts,
   {
      wine     => undef,
      grapes   => undef,
      barely   => 1,
      hops     => 'Strisselspalt',
      yeast    => 'Montrachet',
      version  => undef,
      help     => undef,
   },
   'Other ops parse correctly w/o special only allowed opt'
);

is_deeply(
   $p->{given},
   {
      barely => '1',
      hops   => 'Strisselspalt',
   },
   'Given opts'
);

# #############################################################################
# Check that new style (issue 140) =item --[no]foo works like old style:
# =item --foo
# negatable: yes
# #############################################################################
@opt_spec = $p->pod_to_spec("samples/podsample_issue_140.txt");
is_deeply(
   \@opt_spec,
   [
      { s => 'foo',   d => 'Basic foo' },
      { s => 'bar!',  d => 'New negatable bar'},
   ],
   'New =item --[no]foo style for negatables'
);

# #############################################################################
# For issue 92, extract a paragraph from POD.
# #############################################################################
is($p->read_para_after("samples/podsample_issue92.txt", qr/magic/),
   'This is the paragraph, hooray',
   'read_para_after');

# The first time I wrote this, I used the /o flag to the regex, which means you
# always get the same thing on each subsequent call no matter what regex you
# pass in.  This is to test and make sure I don't do that again.
is($p->read_para_after("samples/podsample_issue92.txt", qr/abracadabra/),
   'This is the next paragraph, hooray',
   'read_para_after again');

exit;
