#!/usr/bin/env perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use MaatkitTest;
use Sandbox;
require "$trunk/mk-archiver/mk-archiver";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');
my $slave_dbh = $sb->get_dbh_for('slave1');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 8;
}

my $output;
my $cnf = "/tmp/12345/my.sandbox.cnf";
# Add path to samples to Perl's INC so the tool can find the module.
my $cmd = "perl -I $trunk/mk-archiver/t/samples $trunk/mk-archiver/mk-archiver";

# ###########################################################################
# Delete rows in corresponding table.
# ###########################################################################
$sb->load_file('master', "mk-archiver/t/samples/delete_details.sql");
$dbh->do('use test');

my $log2_before = [
   [  1, '2011-08-29', 1, 3, 5, 7, 9, 'ok'      ],
   [  2, '2011-08-29', 2, 4, 6, 8, 10, 'ok'     ],
   [  3, '2011-08-29', 21, 22, 23, 24, 25, 'ok' ],
   [  4, '2011-08-29', 20, 31, 32, 33, 34, 'ok' ],
   [  5, '2011-08-29', 0, 0, 0, 0, 0, 'na'      ],
];
my $details_before = [
   [  1, 'one'          ],
   [  2, 'two'          ],
   [  3, 'three'        ],
   [  4, 'four'         ],
   [  5, 'five'         ],
   [  6, 'six'          ],
   [  7, 'seven'        ],
   [  8, 'eight'        ],
   [  9, 'nine'         ],
   [ 10, 'ten'          ],
   [ 11, 'eleven'       ],
   [ 12, 'twelve'       ],
   [ 13, 'thrirteen'    ],
   [ 14, 'fourteen'     ],
   [ 15, 'fifteen'      ],
   [ 16, 'sixteen'      ],
   [ 17, 'seventeen'    ],
   [ 18, 'eighteen'     ],
   [ 19, 'nineteen'     ],
   [ 20, 'twenty'       ],
   [ 21, 'twenty-one'   ],
   [ 22, 'twenty-two'   ],
   [ 23, 'twenty-three' ],
   [ 24, 'twenty-four'  ],
   [ 25, 'twenty-five'  ],
   [ 30, 'thirty'       ],
   [ 31, 'thirty-one'   ],
   [ 32, 'thirty-two'   ],
   [ 33, 'thirty-three' ],
   [ 34, 'thirty-four'  ],
   [ 35, 'thirty-five'  ],
];

my $log2_after = [ [  5, '2011-08-29', 0, 0, 0, 0, 0, 'na'    ] ];
my $details_after = [
   [ 11, 'eleven'       ],
   [ 12, 'twelve'       ],
   [ 13, 'thrirteen'    ],
   [ 14, 'fourteen'     ],
   [ 15, 'fifteen'      ],
   [ 16, 'sixteen'      ],
   [ 17, 'seventeen'    ],
   [ 18, 'eighteen'     ],
   [ 19, 'nineteen'     ],
   [ 30, 'thirty'       ],
   [ 35, 'thirty-five'  ],
];

is_deeply(
   $dbh->selectall_arrayref('select * from `log2` order by id'),
   $log2_before,
   'log2 before deleting'
);

is_deeply(
   $dbh->selectall_arrayref('select * from details order by id'),
   $details_before,
   'details before deleting'
);

`$cmd --purge --source F=$cnf,D=test,t=log2,m=delete_details --where "1=1"`;

is_deeply(
   $dbh->selectall_arrayref('select * from `log2` order by id'),
   $log2_after,
   'log2 after deleting'
);

is_deeply(
   $dbh->selectall_arrayref('select * from details order by id'),
   $details_after,
   'details after deleting'
);

# ###########################################################################
# Archive rows in tables.
# ###########################################################################
$sb->load_file('master', "mk-archiver/t/samples/delete_details.sql");
$dbh->do('use test');

`$cmd --purge --source F=$cnf,D=test,t=log2,m=delete_details --dest D=test_archive,t=log2 --where "1=1"`;

is_deeply(
   $dbh->selectall_arrayref('select * from `log2` order by id'),
   $log2_after,
   'test.log2 after archiving'
);

is_deeply(
   $dbh->selectall_arrayref('select * from details order by id'),
   $details_after,
   'test.details after archiving'
);

is_deeply(
   $dbh->selectall_arrayref('select * from `test_archive`.`log2` order by id'),
   [
      [qw(1 2011-08-29     1   3   5   7   9 ok)],
      [qw(2 2011-08-29     2   4   6   8  10 ok)],
      [qw(3 2011-08-29    21  22  23  24  25 ok)],
      [qw(4 2011-08-29    20  31  32  33  34 ok)],
   ],
   'test_archive.log2 after archiving'
);

is_deeply(
   $dbh->selectall_arrayref('select * from `test_archive`.`details` order by id'),
   [
      [qw(  1 one          )],
      [qw(  2 two          )],
      [qw(  3 three        )],
      [qw(  4 four         )],
      [qw(  5 five         )],
      [qw(  6 six          )],
      [qw(  7 seven        )],
      [qw(  8 eight        )],
      [qw(  9 nine         )],
      [qw( 10 ten          )],
      [qw( 20 twenty       )],
      [qw( 21 twenty-one   )],
      [qw( 22 twenty-two   )],
      [qw( 23 twenty-three )],
      [qw( 24 twenty-four  )],
      [qw( 25 twenty-five  )],
      [qw( 31 thirty-one   )],
      [qw( 32 thirty-two   )],
      [qw( 33 thirty-three )],
      [qw( 34 thirty-four  )],
   ],
   'test_archive.details after archiving'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
