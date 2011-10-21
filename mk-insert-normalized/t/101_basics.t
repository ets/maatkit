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
require "$trunk/mk-insert-normalized/mk-insert-normalized";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 41;
}

my $in  = "mk-insert-normalized/t/samples/";
my $out = "mk-insert-normalized/t/samples/";
my $output;
my $cnf = '/tmp/12345/my.sandbox.cnf';

# ###########################################################################
#
#   data --> entity
#   |
#   +------> data_report
#
# Where --> means "references".  So data has a fk col that references entity,
# and another that references data_report.
# ###########################################################################
$sb->create_dbs($dbh, ['test']);
$sb->load_file('master', "common/t/samples/mysqldump-no-data/dump002.txt", "test");
$sb->load_file('master', "$in/raw-data.sql", "test");
$dbh->do('use test');

my $rows = $dbh->selectall_arrayref('select * from data_report, entity, data');
is_deeply(
   $rows,
   [],
   'Dest tables data_report, entity, and data are empty'
);

$rows = $dbh->selectall_arrayref('select * from raw_data order by date');
is_deeply(
   $rows,
   [
      ['2011-06-01', 101, 'ep1-1', 'ep2-1', 'd1-1', 'd2-1'],
      ['2011-06-02', 102, 'ep1-2', 'ep2-2', 'd1-2', 'd2-2'],
      ['2011-06-03', 103, 'ep1-3', 'ep2-3', 'd1-3', 'd2-3'],
      ['2011-06-04', 104, 'ep1-4', 'ep2-4', 'd1-4', 'd2-4'],
      ['2011-06-05', 105, 'ep1-5', 'ep2-5', 'd1-5', 'd2-5'],
   ],
   'Source table raw_data has data'
);

#ok(
   output(
      sub { mk_insert_normalized::main(
         '--source', "F=$cnf,D=test,t=raw_data",
         '--dest',   "t=data",
         '--constant-values', "$trunk/mk-insert-normalized/t/samples/raw-data-const-vals.txt",
         qw(--databases test --print --execute --txn-size 1 --no-verify)) },
#      "$out/raw-data.txt",
#      sed => [
#         "-e 's/pid:[0-9]*/pid:0/g' -i.bak",
#         "-e 's/user:[a-z]*/user:test/g' -i.bak",
#      ],
   );
#   "Normalize raw_data"
#);

is_deeply(
   $dbh->selectall_arrayref('select * from raw_data order by date'),
   $rows,
   "Source table not modified"
);

$rows = $dbh->selectall_arrayref('select * from data_report order by id');
is_deeply(
   $rows,
   [
      [1, '2011-06-01', '2011-06-15 00:00:00', '2011-06-14 00:00:00'],
      [2, '2011-06-02', '2011-06-15 00:00:00', '2011-06-14 00:00:00'],
      [3, '2011-06-03', '2011-06-15 00:00:00', '2011-06-14 00:00:00'],
      [4, '2011-06-04', '2011-06-15 00:00:00', '2011-06-14 00:00:00'],
      [5, '2011-06-05', '2011-06-15 00:00:00', '2011-06-14 00:00:00'],
   ],
   'data_report rows'
);

$rows = $dbh->selectall_arrayref('select * from entity order by id');
is_deeply(
   $rows,
   [
      [1, 'ep1-1', 'ep2-1'],
      [2, 'ep1-2', 'ep2-2'],
      [3, 'ep1-3', 'ep2-3'],
      [4, 'ep1-4', 'ep2-4'],
      [5, 'ep1-5', 'ep2-5'],
   ],
   'entity rows'
);

$rows = $dbh->selectall_arrayref('select * from data order by data_report');
is_deeply(
   $rows,
   [
      [1, 101, 1, 'd1-1', 'd2-1'],
      [2, 102, 2, 'd1-2', 'd2-2'],
      [3, 103, 3, 'd1-3', 'd2-3'],
      [4, 104, 4, 'd1-4', 'd2-4'],
      [5, 105, 5, 'd1-5', 'd2-5'],
   ],
   'data row'
);

# ############################################################################
#
#   address -> city -> country
#
# This struct is a little different than the previous because there's a table
# that is both referenced and references: city.
# ############################################################################
$dbh->do('drop database if exists test');
$dbh->do('create database test');
$sb->load_file("master", "common/t/samples/CopyRowsNormalized/tbls002.sql", "test");
$dbh->do('use test');

$rows = $dbh->selectall_arrayref('select * from address, city, country');
is_deeply(
   $rows,
   [],
   'Dest tables address, city, and country are empty'
);

$rows = $dbh->selectall_arrayref('select * from denorm_address order by address_id');
is_deeply(
   $rows,
   [
      [1,  '47 MySakila Drive',    300, 'Lethbridge',      20, 'Canada'],
      [2,  '28 MySQL Boulevard',   576, 'Woodridge',        8, 'Australia'],
      [3,  '23 Workhaven Lane',    300, 'Lethbridge',      20, 'Canada'],
      [4,  '1411 Lillydale Drive', 576, 'Woodridge',        8, 'Australia'],
      [5,  '1913 Hanoi Way',       463, 'Sasebo',          50, 'Japan'],
      [6,  '1121 Loja Avenue',     449, 'San Bernardino', 103, 'United States'],
      [7,  '692 Joliet Street',     38, 'Athenai',         39, 'Greece'],
      [8,  '1566 Inegl Manor',     349, 'Myingyan',        64, 'Myanmar'],
      [9,  '53 Idfu Parkway',      361, 'Nantou',          92, 'Taiwan'],
      [10, '1795 Santiago Way',    295, 'Laredo',         103, 'United States'],
   ],
   'Source table denorm_address has data'
);

mk_insert_normalized::main(
   '--source', "F=$cnf,D=test,t=denorm_address",
   '--dest',   "t=address",
   qw(--databases test --execute --no-verify),
   qw(--insert-ignore));  # required since denorm_address has dupes

is_deeply(
   $dbh->selectall_arrayref('select * from denorm_address order by address_id'),
   $rows,
   "Source table not modified"
);

$rows = $dbh->selectall_arrayref('select * from country order by country_id');
is_deeply(
   $rows,
   [
      [8,   'Australia'],
#     [8,   'Australia'],
      [20,  'Canada'],
#     [20,  'Canada'],
      [39,  'Greece'],
      [50,  'Japan'],
      [64,  'Myanmar'],
      [92,  'Taiwan'],
      [103, 'United States'],
#     [103, 'United States'],
   ],
   'country rows'
);

$rows = $dbh->selectall_arrayref('select * from city order by city_id');
is_deeply(
   $rows,
   [
      [38,  'Athenai',        39],
      [295, 'Laredo',         103],
      [300, 'Lethbridge',     20],
#     [300, 'Lethbridge',     20],
      [349, 'Myingyan',       64],
      [361, 'Nantou',         92],
      [449, 'San Bernardino', 103],
      [463, 'Sasebo',         50],
      [576, 'Woodridge',      8],
#     [576, 'Woodridge',      8],
   ],
   'city rows'
);

$rows = $dbh->selectall_arrayref('select * from address order by address_id');
is_deeply(
   $rows,
   [
      [1,  '47 MySakila Drive',     300],
      [2,  '28 MySQL Boulevard',    576],
      [3,  '23 Workhaven Lane',     300],
      [4,  '1411 Lillydale Drive',  576],
      [5,  '1913 Hanoi Way',        463],
      [6,  '1121 Loja Avenue',      449],
      [7,  '692 Joliet Street',      38],
      [8,  '1566 Inegl Manor',      349],
      [9,  '53 Idfu Parkway',       361],
      [10, '1795 Santiago Way',     295],
   ],
   'address rows'
);
$rows = $dbh->selectall_arrayref('select * from denorm_address order by address_id');
my $rows2 = $dbh->selectall_arrayref('select address.address_id, address, city.city_id, city, country.country_id, country from address left join city using (city_id) left join country using (country_id) order by address.address_id');
is_deeply(
   $rows,
   $rows2,
   "Normalized rows match denormalized rows"
);

# ###########################################################################
#
#   items --> types
#   |
#   +-------> colors
#
# items is nothing but an auto-inc pk col and two fk cols that reference
# types and colors.  No columns will map to items because there are no
# columns in denorm_items with the same name.  But the tool should detect
# this and map items explicitly, and that should work because it has fk
# cols that reference other tables.
# ###########################################################################
$dbh->do('drop database if exists test');
$dbh->do('create database test');
$sb->load_file("master", "common/t/samples/CopyRowsNormalized/tbls003.sql", "test");
$dbh->do('use test');

$rows = $dbh->selectall_arrayref('select * from types, colors, items');
is_deeply(
   $rows,
   [],
   'Dest tables types, colors, and items are empty'
);

$rows = $dbh->selectall_arrayref('select * from denorm_items order by id');
is_deeply(
   $rows,
   [
      [1,   't1',   'red'   ],
      [2,   't2',   'red'   ],
      [3,   't2',   'blue'  ],
      [4,   't3',   'black' ],
      [5,   't4',   'orange'],
      [6,   't5',   'green' ],
   ],
   'Source table denorm_items has data'
);

mk_insert_normalized::main(
   '--source', "F=$cnf,D=test,t=denorm_items",
   '--dest',   "t=items",
   qw(--databases test --execute --no-verify));

$rows = $dbh->selectall_arrayref('select * from types order by type_id');
is_deeply(
   $rows,
   [
      [1,   't1'],
      [2,   't2'],
      [3,   't2'],
      [4,   't3'],
      [5,   't4'],
      [6,   't5'],
   ],
   'types rows'
);

$rows = $dbh->selectall_arrayref('select * from colors order by color_id');
is_deeply(
   $rows,
   [
      [1,   'red'   ],
      [2,   'red'   ],
      [3,   'blue'  ],
      [4,   'black' ],
      [5,   'orange'],
      [6,   'green' ],
   ],
   'colors rows'
);

$rows = $dbh->selectall_arrayref('select * from items order by item_id');
is_deeply(
   $rows,
   [
      [1, 1, 1],
      [2, 2, 1], # XXX
      [3, 2, 3], # XXX
      [4, 4, 4],
      [5, 5, 5],
      [6, 6, 6],
   ],
   'items rows'
);

# ###########################################################################
# These tables require INSERT IGNORE, an insert a duplicate row which
# causes the auto-inc on entity to *not* be incremented.
# ###########################################################################
$sb->load_file("master", "common/t/samples/CopyRowsNormalized/tbls004.sql", "test");
$dbh->do('use test');

mk_insert_normalized::main(
   '--source', "F=$cnf,D=test,t=raw_data",
   '--dest',   "t=data",
   qw(--databases test --insert-ignore --execute --no-verify));

$rows = $dbh->selectall_arrayref('select * from data_report order by id');
is_deeply(
   $rows,
   [
      [1, '2011-06-01', undef, undef],
      [2, '2011-06-01', undef, undef],
      [3, '2011-06-01', undef, undef],
   ],
   'data_report rows (duplicate key with auto-inc)'
);

$rows = $dbh->selectall_arrayref('select * from entity order by id');
is_deeply(
   $rows,
   [
      [1, 10, 11],
      [3, 20, 21],
   ],
   'entity rows (duplicate key with auto-inc)'
);

$rows = $dbh->selectall_arrayref('select * from data order by data_report');
is_deeply(
   $rows,
   [
      [1, 1, 1, 12, 13],
      [1, 2, 1, 12, 13],
      [1, 2, 3, 22, 23],
   ],
   'data rows (duplicate key with auto-inc)'
);

# ###########################################################################
# Don't allow auto inc column gaps.
# ###########################################################################
$sb->load_file("master", "common/t/samples/CopyRowsNormalized/tbls004.sql", "test");
$dbh->do('use test');

mk_insert_normalized::main(
   '--source', "F=$cnf,D=test,t=raw_data",
   '--dest',   "t=data",
   qw(--databases test --insert-ignore --execute --no-verify),
   qw(--no-auto-increment-gaps));

$rows = $dbh->selectall_arrayref('select * from data_report order by id');
is_deeply(
   $rows,
   [
      [1, '2011-06-01', undef, undef],
   ],
   'data_report rows (no auto inc gaps)'
);

$rows = $dbh->selectall_arrayref('select * from entity order by id');
is_deeply(
   $rows,
   [
      [1, 10, 11],
      [2, 20, 21],
   ],
   'entity rows (no auto inc gaps)'
);

$rows = $dbh->selectall_arrayref('select * from data order by data_report');
is_deeply(
   $rows,
   [
      [1, 1, 1, 12, 13],
      [1, 2, 1, 12, 13],
      [1, 2, 2, 22, 23],
   ],
   'data rows (no auto inc gaps)'
);

# ###########################################################################
# Manual --column-map.
# ###########################################################################
$sb->load_file("master", "mk-insert-normalized/t/samples/col-map.sql");
$dbh->do('use test');

#ok(
   output(
      sub { mk_insert_normalized::main(
         '--source', "F=$cnf,D=test,t=a",
         '--dest',   "t=z",
         qw(--ignore-columns id),
         '--column-map', "$trunk/mk-insert-normalized/t/samples/col-map.txt",
         qw(--databases test --print --execute --no-verify)) },
#      "$out/col-map-output.txt",
#      sed => [
#         "-e 's/pid:[0-9]*/pid:0/g' -i.bak",
#         "-e 's/user:[a-z]*/user:test/g' -i.bak",
#      ],
   );
#   "--column-map"
#);

$rows = $dbh->selectall_arrayref('select * from y order by id');
is_deeply(
   $rows,
   [
      [1, 1, 1],
      [2, 2, 2],
      [3, 3, 3],
   ],
   'y rows (--column-map)'
);

# Both y and z have a col2, but only y.col2 gets the value from a.col2 because
# of the manual column map "col2 test.y.col2 !".  So z.col2 should use its
# default value: 42
$rows = $dbh->selectall_arrayref('select id, cola, col2, three from z order by id');
is_deeply(
   $rows,
   [
      [1, 1, 42, 1],
      [2, 2, 42, 2],
      [3, 3, 42, 3],
   ],
   'z rows (--column-map)'
);

# ###########################################################################
# Manual --column-map with duplicate name.
# ###########################################################################
$sb->load_file("master", "mk-insert-normalized/t/samples/map-name.sql");
$dbh->do('use test');

output(
   sub { mk_insert_normalized::main(
      '--source', "F=$cnf,D=test,t=raw_data",
      '--dest',   "t=data",
      '--column-map', "$trunk/mk-insert-normalized/t/samples/map-name.txt",
      qw(--insert-ignore --no-auto-increment-gaps),
      qw(--databases test --execute --no-verify)) },
);

$rows = $dbh->selectall_arrayref('select * from test.entity_1 order by id');
is_deeply(
   $rows,
   [ [1, 'a'], [2, 'b'] ],
   'entity_1 rows (duplicate `name` column)'
);

$rows = $dbh->selectall_arrayref('select * from test.entity_2 order by id');
is_deeply(
   $rows,
   [ [1, 'x'], [2, 'y'] ],
   'entity_2 rows (duplicate `name` column)'
);

$rows = $dbh->selectall_arrayref('select * from test.data_report order by id');
is_deeply(
   $rows,
   [ [1, '2011-06-01','2011-06-01 23:55:58'] ],
   'data_report rows (duplicate `name` column)'
);

$rows = $dbh->selectall_arrayref('select * from test.data order by data_report, hour, entity_1, entity_2');
is_deeply(
   $rows,
   [
      [1, 1, 1, 1, 27],
      [1, 2, 1, 1, 27],
      [1, 3, 2, 2, 23],
      [1, 4, 1, 1, 27],
      [1, 4, 2, 1, 23],
      [1, 4, 2, 2, 23],
      [1, 5, 2, 2, 29],
   ],
   'data rows (duplicate `name` column)'
);

# ###########################################################################
# Two insert groups.
# ###########################################################################
$sb->load_file("master", "common/t/samples/CopyRowsNormalized/two-fk.sql");
$dbh->do('use test');

output(
   sub { mk_insert_normalized::main(
      '--source', "F=$cnf,D=test,t=raw_data",
      '--dest',   "t=data",
      '--column-map', "$trunk/$in/two-fk-column-map.txt",
      '--foreign-key-column-map', "$trunk/$in/two-fk-fk-column-map.txt",
      qw(--insert-ignore --no-auto-increment-gaps),
      qw(--databases test --execute --no-verify)) },
);

$rows = $dbh->selectall_arrayref('select * from test.account order by id');
is_deeply(
   $rows,
   [
      [1, 1, 'a'],
      [2, 2, 'b'],
      [3, 3, 'c'],
      [4, 4, 'd'],
      [5, 5, 'e'],
      [6, 6, 'f']
   ],
   'account rows (two inserts)'
);

$rows = $dbh->selectall_arrayref('select * from test.data_report order by id');
is_deeply(
   $rows,
   [
      [1, '2011-05-01', '2011-06-01 23:55:58', 1],
      [2, '2011-05-01', '2011-06-01 23:55:58', 4],
   ],
   'data_report rows (two inserts)'
);

$rows = $dbh->selectall_arrayref('select * from test.data order by data_report');
is_deeply(
   $rows,
   [
      [1, 1, 10],
      [1, 2, 11],
      [1, 3, 12],
      [2, 4, 13],
      [2, 5, 14],
      [2, 6, 15],
   ],
   'data rows (two inserts)'
);

# ############################################################################
# Don't iter fk table that's ignored.
# ############################################################################
$sb->load_file("master", "$in/animals.sql");
$dbh->do('use test');

ok(
   no_diff(
      sub { mk_insert_normalized::main(
         '--source', "F=$cnf,D=test,t=raw_data_animal_1",
         '--dest',   "t=animal",
         qw(--insert-ignore --no-auto-increment-gaps),
         qw(--databases test),
         '--tables', 'raw_data_animal_1,animal,report_animal',
         qw(--print));
      },
      "$out/animals-print.txt",
      sed => ["-i.bak -e 's/pid:[0-9]*/pid:0/g' -e 's/user:.* /user:none /g'"],
   ),
   "animals insert plan"
);

output(
   sub { mk_insert_normalized::main(
      '--source', "F=$cnf,D=test,t=raw_data_animal_1",
      '--dest',   "t=animal",
      qw(--insert-ignore --no-auto-increment-gaps),
      qw(--databases test),
      '--tables', 'raw_data_animal_1,animal,report_animal',
      qw(--execute))
   },
);

$rows = $dbh->selectall_arrayref('select * from test.animal order by report_animal');
is_deeply(
   $rows,
   [
      [1,'cat',15,undef],
      [1,'dog',45,undef],
      [2,'bird',5,undef],
      [2,'frog',2,undef],
   ],
   'animal rows'
);

# ############################################################################
# baseball
# ############################################################################
$sb->load_file("master", "$in/baseball.sql");
$dbh->do('use test');

output(
   sub { mk_insert_normalized::main(
      '--source', "F=$cnf,D=test,t=raw_data_baseball",
      '--dest',   "t=baseball_team",
      qw(--insert-ignore --no-auto-increment-gaps),
      qw(--databases test --column-map), "$trunk/$in/baseball.map",
      '--tables', 'raw_data_baseball,report_baseball_team,baseball_team',
      qw(--execute));
   },
);

$rows = $dbh->selectall_arrayref('select * from test.location order by id');
is_deeply(
   $rows,
   [
      [1, 'New York City',  'New York'  ],
      [2, 'Atlanta',        'Georgia'   ],
      [3, 'San Francisco',  'California'],
   ],
   'location rows'
);

$rows = $dbh->selectall_arrayref('select * from test.report_baseball_team order by id');
is_deeply(
   $rows,
   [
      [1, '2011-08-01 10:00:00'],
      [2, '2011-08-01 11:00:00'],
   ],
   'report_baseball_team rows'
);

$rows = $dbh->selectall_arrayref('select * from test.baseball_team order by name');
is_deeply(
   $rows,
   [
      [1, 'braves',  45, 48, 2],
      [2, 'giants',  49, 42, 3],
      [1, 'mets',    50, 43, 1],
      [2, 'yankees', 44, 49, 1],
   ],
   'baseball_team rows'
);

# ############################################################################
# baseball2 -- no map required
# ############################################################################
$sb->load_file("master", "$in/baseball2.sql");
$dbh->do('use test');

output(
   sub { mk_insert_normalized::main(
      '--source', "F=$cnf,D=test,t=raw_data_baseball",
      '--dest',   "t=baseball_team",
      qw(--insert-ignore --no-auto-increment-gaps),
      qw(--databases test),
      '--tables', 'raw_data_baseball,report_baseball_team,baseball_team',
      qw(--execute));
   },
);

$rows = $dbh->selectall_arrayref('select * from test.location order by id');
is_deeply(
   $rows,
   [
      [1, 'New York City',  'New York'  ],
      [2, 'Atlanta',        'Georgia'   ],
      [3, 'San Francisco',  'California'],
   ],
   'baseball2 location rows'
);

$rows = $dbh->selectall_arrayref('select * from test.report_baseball_team order by id');
is_deeply(
   $rows,
   [
      [1, '2011-08-01 10:00:00'],
      [2, '2011-08-01 11:00:00'],
   ],
   'baseball2 report_baseball_team rows'
);

$rows = $dbh->selectall_arrayref('select * from test.baseball_team order by name');
is_deeply(
   $rows,
   [
      [1, 'braves',  45, 48, 2],
      [2, 'giants',  49, 42, 3],
      [1, 'mets',    50, 43, 1],
      [2, 'yankees', 44, 49, 1],
   ],
   'baseball2 baseball_team rows'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
