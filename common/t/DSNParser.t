#!/usr/bin/perl

BEGIN {
   die "The MAATKIT_TRUNK environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_TRUNK} && -d $ENV{MAATKIT_TRUNK};
   unshift @INC, "$ENV{MAATKIT_TRUNK}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 27;

use DSNParser;
use OptionParser;
use MaatkitTest;

my $dp = new DSNParser;

is_deeply(
   $dp->parse('u=a,p=b'),
   {  u => 'a',
      p => 'b',
      S => undef,
      h => undef,
      P => undef,
      F => undef,
      D => undef,
      A => undef,
   },
   'Basic DSN'
);

is_deeply(
   $dp->parse('u=a,p=b,A=utf8'),
   {  u => 'a',
      p => 'b',
      S => undef,
      h => undef,
      P => undef,
      F => undef,
      D => undef,
      A => 'utf8',
   },
   'Basic DSN with charset'
);

$dp = new DSNParser(
   { key => 't', copy => 0 }
   );

is_deeply(
   $dp->parse('u=a,p=b'),
   {  u => 'a',
      p => 'b',
      S => undef,
      h => undef,
      P => undef,
      F => undef,
      D => undef,
      t => undef,
      A => undef,
   },
   'DSN with an extra option'
);

is_deeply(
   $dp->parse('u=a,p=b', { D => 'foo', h => 'me' }, { S => 'bar', h => 'host' } ),
   {  D => 'foo',
      F => undef,
      h => 'me',
      p => 'b',
      P => undef,
      S => 'bar',
      t => undef,
      u => 'a',
      A => undef,
   },
   'DSN with defaults'
);

is(
   $dp->as_string(
      $dp->parse('u=a,p=b', { D => 'foo', h => 'me' }, { S => 'bar', h => 'host' } )
   ),
   'D=foo,S=bar,h=me,p=...,u=a',
   'DSN stringified when it gets DSN as arg'
);

is(
   $dp->as_string(
      'D=foo,S=bar,h=me,p=b,u=a',
   ),
   'D=foo,S=bar,h=me,p=b,u=a',
   'DSN stringified when it gets a string as arg'
);

is (
   $dp->as_string({ bez => 'bat', h => 'foo' }),
   'h=foo',
   'DSN stringifies without extra crap',
);

is ($dp->usage(),
<<EOF
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
  t    no    [No description]
  u    yes   User for login if not current user

  If the DSN is a bareword, the word is treated as the 'h' key.
EOF
, 'Usage');

$dp->prop('autokey', 'h');
is_deeply(
   $dp->parse('automatic'),
   {  D => undef,
      F => undef,
      h => 'automatic',
      p => undef,
      P => undef,
      S => undef,
      t => undef,
      u => undef,
      A => undef,
   },
   'DSN with autokey'
);

$dp->prop('autokey', 'h');
is_deeply(
   $dp->parse('localhost,A=utf8'),
   {  u => undef,
      p => undef,
      S => undef,
      h => 'localhost',
      P => undef,
      F => undef,
      D => undef,
      t => undef,
      A => 'utf8',
   },
   'DSN with an explicit key and an autokey',
);

is_deeply(
   $dp->parse('automatic',
      { D => 'foo', h => 'me', p => 'b' },
      { S => 'bar', h => 'host', u => 'a' } ),
   {  D => 'foo',
      F => undef,
      h => 'automatic',
      p => 'b',
      P => undef,
      S => 'bar',
      t => undef,
      u => 'a',
      A => undef,
   },
   'DSN with defaults and an autokey'
);

is ($dp->usage(),
<<EOF
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
  t    no    [No description]
  u    yes   User for login if not current user

  If the DSN is a bareword, the word is treated as the 'h' key.
EOF
, 'Usage');

is_deeply (
   [
      $dp->get_cxn_params(
         $dp->parse(
            'u=a,p=b',
            { D => 'foo', h => 'me' },
            { S => 'bar', h => 'host' } ))
   ],
   [
      'DBI:mysql:foo;host=me;mysql_socket=bar;mysql_read_default_group=client',
      'a',
      'b',
   ],
   'Got connection arguments',
);

is_deeply (
   [
      $dp->get_cxn_params(
         $dp->parse(
            'u=a,p=b,A=foo',
            { D => 'foo', h => 'me' },
            { S => 'bar', h => 'host' } ))
   ],
   [
      'DBI:mysql:foo;host=me;mysql_socket=bar;charset=foo;mysql_read_default_group=client',
      'a',
      'b',
   ],
   'Got connection arguments with charset',
);

# Make sure we can connect to MySQL with a charset
my $d = $dp->parse('h=127.0.0.1,P=12345,A=utf8,u=msandbox,p=msandbox');
my $dbh;
eval {
   $dbh = $dp->get_dbh($dp->get_cxn_params($d), {});
};
SKIP: {
   skip 'Cannot connect to sandbox master', 5 if $EVAL_ERROR;

   $dp->fill_in_dsn($dbh, $d);
   is($d->{P}, 12345, 'Left port alone');
   is($d->{u}, 'msandbox', 'Filled in username');
   is($d->{S}, '/tmp/12345/mysql_sandbox12345.sock', 'Filled in socket');
   is($d->{h}, '127.0.0.1', 'Left hostname alone');

   is_deeply(
      $dbh->selectrow_arrayref('select @@character_set_client, @@character_set_connection, @@character_set_results'),
      [qw(utf8 utf8 utf8)],
      'Set charset'
   );
};

$dp->prop('dbidriver', 'Pg');
is_deeply (
   [
      $dp->get_cxn_params(
         {
            u => 'a',
            p => 'b',
            h => 'me',
            D => 'foo',
         },
      )
   ],
   [
      'DBI:Pg:dbname=foo;host=me',
      'a',
      'b',
   ],
   'Got connection arguments for PostgreSQL',
);

$dp->prop('required', { h => 1 } );
throws_ok (
   sub { $dp->parse('u=b') },
   qr/Missing DSN part 'h' in 'u=b'/,
   'Missing host part',
);

throws_ok (
   sub { $dp->parse('h=foo,Z=moo') },
   qr/Unrecognized DSN part 'Z' in 'h=foo,Z=moo'/,
   'Extra key',
);

# #############################################################################
# Test parse_options().
# #############################################################################
my $o = new OptionParser(
   description => 'parses command line options.',
   dp          => $dp,
);
$o->_parse_specs(
   { spec => 'defaults-file|F=s', desc => 'defaults file'  },
   { spec => 'password|p=s',      desc => 'password'       },
   { spec => 'host|h=s',          desc => 'host'           },
   { spec => 'port|P=i',          desc => 'port'           },
   { spec => 'socket|S=s',        desc => 'socket'         },
   { spec => 'user|u=s',          desc => 'user'           },
);
@ARGV = qw(--host slave1 --user foo);
$o->get_opts();

is_deeply(
   $dp->parse_options($o),
   {
      D => undef,
      F => undef,
      h => 'slave1',
      p => undef,
      P => undef,
      S => undef,
      t => undef,
      u => 'foo',
      A => undef,
   },
   'Parses DSN from OptionParser obj'
);

# #############################################################################
# Test copy().
# #############################################################################
my $dsn_1 = {
   D => undef,
   F => undef,
   h => 'slave1',
   p => 'p1',
   P => '12345',
   S => undef,
   t => undef,
   u => 'foo',
   A => undef,
};
my $dsn_2 = {
   D => 'test',
   F => undef,
   h => undef,
   p => 'p2',
   P => undef,
   S => undef,
   t => 'tbl',
   u => undef,
   A => undef,
};

is_deeply(
   $dp->copy($dsn_1, $dsn_2),
   {
      D => 'test',
      F => undef,
      h => 'slave1',
      p => 'p2',
      P => '12345',
      S => undef,
      t => 'tbl',
      u => 'foo',
      A => undef,
   },
   'Copy DSN without overwriting destination'
);
is_deeply(
   $dp->copy($dsn_1, $dsn_2, overwrite=>1),
   {
      D => 'test',
      F => undef,
      h => 'slave1',
      p => 'p1',
      P => '12345',
      S => undef,
      t => 'tbl',
      u => 'foo',
      A => undef,
   },
   'Copy DSN and overwrite destination'
);

# #############################################################################
# Issue 93: DBI error messages can include full SQL
# #############################################################################
SKIP: {
   skip 'Cannot connect to sandbox master', 1 unless $dbh;
   eval { $dbh->do('SELECT * FROM doesnt.exist WHERE foo = 1'); };
   like(
      $EVAL_ERROR,
      qr/SELECT \* FROM doesnt.exist WHERE foo = 1/,
      'Includes SQL in error message (issue 93)'
   );
};


# #############################################################################
# Issue 597: mk-slave-prefetch ignores --set-vars
# #############################################################################

# This affects all scripts because prop() doesn't match what get_dbh() does.
SKIP: {
   skip 'Cannot connect to sandbox master', 1 unless $dbh;
   $dbh->do('SET @@global.wait_timeout=1');

   # This dbh is going to timeout too during this test so close
   # it now else we'll get an error.
   $dbh->disconnect();

   $dp = new DSNParser();
   $dp->prop('set-vars', 'wait_timeout=1000');
   $d  = $dp->parse('h=127.0.0.1,P=12345,A=utf8,u=msandbox,p=msandbox');
   my $dbh2 = $dp->get_dbh($dp->get_cxn_params($d), {});
   sleep 2;
   eval {
      $dbh2->do('SELECT DATABASE()');
   };
   is(
      $EVAL_ERROR,
      '',
      'SET vars (issue 597)'
   );
   $dbh2->disconnect();

   # Have to reconnect $dbh since it timedout too.
   $dbh = $dp->get_dbh($dp->get_cxn_params($d), {});
   $dbh->do('SET @@global.wait_timeout=28800');
};

# #############################################################################
# Done.
# #############################################################################
$dbh->disconnect() if $dbh;
exit;
