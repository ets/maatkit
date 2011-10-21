#!/usr/bin/perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use DSNParser;
use Sandbox;
use OptionParser;
use Quoter;
use TableParser;
use MySQLDump;
use MaatkitTest;
use Schema;
use SchemaIterator;
use ForeignKeyIterator;
use ColumnMap;
use TableNibbler;
use CopyRowsNormalized;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $src_dbh = $sb->get_dbh_for('master');
my $dst_dbh = $sb->get_dbh_for('master');

if ( !$src_dbh ) {
   plan skip_all => 'Cannot connect to MySQL';
}
else {
   plan tests => 64;
}

my $dbh    = $src_dbh;  # src, dst, doesn't matter for checking the tables
my $output = '';
my $in     = "common/t/samples/CopyRowsNormalized/";

my $q  = new Quoter;
my $tp = new TableParser(Quoter => $q);
my $du = new MySQLDump();
my $o  = new OptionParser(description => 'SchemaIterator');
$o->get_specs("$trunk/mk-table-checksum/mk-table-checksum");

my $stats = {};

sub make_copier {
   my ( %args ) = @_;

   my $schema   = new Schema();

   my $schema_itr;
   my $si       = new SchemaIterator(
      dbh          => $src_dbh,
      OptionParser => $o,
      Quoter       => $q,
      MySQLDump    => $du,
      TableParser  => $tp,
      Schema       => $schema,
      keep_ddl     => $args{foreign_keys} ? 1 : 0,
   );
   if ( $args{foreign_keys} ) {
      $schema_itr = new ForeignKeyIterator(
         db             => $args{src_db},
         tbl            => $args{src_tbl},
         reverse        => 1,
         SchemaIterator => $si,
         Quoter         => $q,
         TableParser    => $tp,
         Schema         => $schema,
      );
   }
   else {
      $schema_itr = $si;
   }

   # Init the schema qualifier.
   1 while(defined $schema_itr->next_schema_object());

   my $src = {
      dbh   => $src_dbh,
      tbl   => $schema->get_table($args{src_db}, $args{src_tbl}),
      index => $args{index} || 'PRIMARY',
   };

   my @dst_tbls;
   foreach my $dst_tbl ( @{$args{dst_tbls}} ) {
      push @dst_tbls, $schema->get_table(@$dst_tbl);
   }
   my $dst = {
      dbh  => $dst_dbh,
      tbls => \@dst_tbls,
   };
   
   my $column_map = new ColumnMap(
      src_tbl                => $schema->get_table($args{src_db}, $args{src_tbl}),
      dst_tbls               => \@dst_tbls,
      Schema                 => $schema,
      constant_values        => $args{constant_values},
      column_map             => $args{column_map},
      foreign_key_column_map => $args{fk_column_map},
      ignore_columns         => $args{ignore_columns},
      Quoter                 => $q,
   );
   foreach my $dst_tbl ( @dst_tbls ) {
      if ( !$column_map->insert_plan($dst_tbl) ) {
         die "No insert plan for table $dst_tbl->{db}.$dst_tbl->{tbl}";
      }
   }

   $stats = {};

   my $copy_rows = new CopyRowsNormalized(
      %args,
      execute      => defined $args{execute} ? $args{execute} : 1,
      src          => $src,
      dst          => $dst,
      ColumnMap    => $column_map,
      Quoter       => $q,
      TableNibbler => new TableNibbler(TableParser => $tp, Quoter => $q),
      stats        => $stats,
   );

   return $copy_rows;
}

# ###########################################################################
# Just a simple table, osc.t, with col id=PK, col c=varchar, and
# a duplicate table osc.__new_t, so all columns map.
# ###########################################################################
$sb->load_file("master", "common/t/samples/osc/tbl001.sql");
@ARGV = qw(-d osc);
$o->get_opts();
my $copy_rows = make_copier(
   src_db   => 'osc',
   src_tbl  => 't',
   dst_tbls => [['osc', '__new_t']],
   txn_size => 2,
   warnings => 'die',
);

my $rows = $dbh->selectall_arrayref('select * from osc.__new_t');
is_deeply(
   $rows,
   [],
   'Dest table is empty'
);

$rows = $dbh->selectall_arrayref('select * from osc.t order by id');
is_deeply(
   $rows,
   [ [qw(1 a)], [qw(2 b)], [qw(3 c)], [qw(4 d)], [qw(5 e)] ],
   'Source table has rows'
);

# Copy all rows from osc.t --> osc.__new_t.
$copy_rows->copy();

is_deeply(
   $dbh->selectall_arrayref('select * from osc.t order by id'),
   $rows,
   'Source table not modified'
);

is_deeply(
   $dbh->selectall_arrayref('select * from osc.__new_t'),
   $rows,
   'Dest table has rows'
);

is(
   $stats->{rows_selected},
   5,
   '5 rows selected'
);

is(
   $stats->{rows_inserted},
   5,
   '5 rows inserted'
);

is(
   $stats->{start_transaction},
   3,
   '3 transactions started',
);

is(
   $stats->{commit},
   3,
   '3 transactions commmitted'
);

is(
   $stats->{chunks},
   4,
   '4 chunks'
);

is(
   $stats->{show_warnings},
   5,
   '5 SHOW WARNINGS'
);

is(
   $stats->{warnings},
   undef,
   'No warnings'
);

# ###########################################################################
# Copying table a rows to 2 tables: b and c.  a.id doesn't map, so b.b_id
# and c.c_id should auto-inc.  There should be more inserts than fetched rows.
# ###########################################################################
$sb->load_file("master", "$in/tbls001.sql");
@ARGV = qw(-d test);
$o->get_opts();
$copy_rows = make_copier(
   src_db   => 'test',
   src_tbl  => 'a',
   dst_tbls => [['test', 'b'], ['test', 'c']],
   txn_size => 2,
);

$rows = $dbh->selectall_arrayref('select * from test.a order by id');
is_deeply(
   $rows,
   [ [qw(1 a)], [qw(2 b)], [qw(3 c)], [qw(4 d)], [qw(5 e)] ],
   'Source table has rows'
);

# Copy all rows from osc.t --> osc.__new_t.
$copy_rows->copy();

is_deeply(
   $dbh->selectall_arrayref('select * from osc.t order by id'),
   $rows,
   'Source table not modified'
);

is_deeply(
   $dbh->selectall_arrayref('select * from test.b order by b_id'),
   $rows,
   '1st dest table has rows'
);

is_deeply(
   $dbh->selectall_arrayref('select * from test.c order by c_id'),
   $rows,
   '2nd dest table has rows'
);

is(
   $stats->{rows_selected},
   5,
   '5 rows selected'
);

is(
   $stats->{rows_inserted},
   10,
   '10 rows inserted'
);

# ###########################################################################
# Normalize a table with foreign key columns that map by fetching back the
# last insert id.
# ###########################################################################
$dbh->do('drop database if exists test');
$dbh->do('create database test');
$sb->load_file("master", "common/t/samples/mysqldump-no-data/dump002.txt", "test");
$sb->load_file("master", "mk-insert-normalized/t/samples/raw-data.sql", "test");
@ARGV = qw(-d test);
$o->get_opts();
$copy_rows = make_copier(
   foreign_keys => 1,
   src_db       => 'test',
   src_tbl      => 'raw_data',
   txn_size     => 3,
   dst_tbls     => [
      ['test', 'data_report'], # child2
      ['test', 'entity'     ], # child1
      ['test', 'data'       ], # parent
   ],
   constant_values => {
      posted   => '2011-06-15',
      acquired => '2011-06-14',
   },
);

$rows = $dbh->selectall_arrayref('select * from data_report, entity, data');
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

$copy_rows->copy();

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
   'data rows'
);

# ############################################################################
# This fk struct is address -> city -> country.
# ############################################################################
$dbh->do('drop database if exists test');
$dbh->do('create database test');
$sb->load_file("master", "$in/tbls002.sql", "test");
@ARGV = qw(-d test);
$o->get_opts();
$copy_rows = make_copier(
   insert_ignore => 1,
   foreign_keys  => 1,
   src_db        => 'test',
   src_tbl       => 'denorm_address',
   txn_size      => 5,
   dst_tbls      => [
      ['test', 'country'],
      ['test', 'city'   ],
      ['test', 'address'], # parent
   ],
);

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

$copy_rows->copy();

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
# The dest table is nothing but fk cols, so no source tbl cols map to it
# and all its values come from fetch backs.
# ###########################################################################
$dbh->do('drop database if exists test');
$dbh->do('create database test');
$sb->load_file("master", "$in/tbls003.sql", "test");
@ARGV = qw(-d test);
$o->get_opts();
$copy_rows = make_copier(
   foreign_keys => 1,
   src_db       => 'test',
   src_tbl      => 'denorm_items',
   dst_tbls     => [
      ['test', 'types' ], # child2
      ['test', 'colors'], # child1
      ['test', 'items' ], # parent
   ],
);

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

$copy_rows->copy();

$rows = $dbh->selectall_arrayref('select * from types order by type_id');
is_deeply(
   $rows,
   [
      [1,   't1'],
      [2,   't2'], # dupe
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
      [2,   'red'   ], # dupe
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
$sb->load_file("master", "$in/tbls004.sql", "test");
@ARGV = qw(-d test);
$o->get_opts();
$copy_rows = make_copier(
   foreign_keys  => 1,
   insert_ignore => 1,
   src_db        => 'test',
   src_tbl       => 'raw_data',
   txn_size      => 100,
   dst_tbls      => [
      ['test', 'entity'     ], # child2
      ['test', 'data_report'], # child1
      ['test', 'data'       ], # parent
   ],
);

$copy_rows->copy();

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
) or print Dumper($rows);

# ###########################################################################
# Two runs on the same tables.
# ###########################################################################
$sb->load_file("master", "$in/tbls005.sql", "test");
@ARGV = ('-d', 'test', '-t', 'raw_data,data,entity,data_report');
$o->get_opts();
$copy_rows = make_copier(
   foreign_keys  => 1,
   insert_ignore => 1,
   src_db        => 'test',
   src_tbl       => 'raw_data',
   txn_size      => 100,
   dst_tbls      => [
      ['test', 'entity'     ], # child2
      ['test', 'data_report'], # child1
      ['test', 'data'       ], # parent
   ],
);

$copy_rows->copy();

@ARGV = ('-d', 'test', '-t', 'raw_data_2,data,entity,data_report');
$o->get_opts();

$copy_rows = make_copier(
   foreign_keys  => 1,
   insert_ignore => 1,
   src_db        => 'test',
   src_tbl       => 'raw_data_2',
   txn_size      => 100,
   dst_tbls      => [
      ['test', 'entity'     ], # child2
      ['test', 'data_report'], # child1
      ['test', 'data'       ], # parent
   ],
);

$copy_rows->copy();

$rows = $dbh->selectall_arrayref('select * from data_report order by id');
is_deeply(
   $rows,
   [
      [1, '2011-06-01', '2011-06-01 23:23:23', '2011-06-01 23:55:55' ],
      [4, '2011-06-01', '2011-06-01 23:23:23', '2011-06-01 23:55:57' ],
   ],
   'data_report rows (with raw_data_2)'
) or print Dumper($rows);

$rows = $dbh->selectall_arrayref('select * from entity order by id');
is_deeply(
   $rows,
   [
      [1, 10, 11 ],
      [3, 20, 21 ],
   ],
   'entity rows (with raw_data_2)'
) or print Dumper($rows);

$rows = $dbh->selectall_arrayref('select * from data order by data_report');
is_deeply(
   $rows,
   [
      [1, 1, 1, 12, 13],
      [1, 2, 1, 12, 13],
      [1, 2, 3, 22, 23],
      [4, 1, 1, 12, 13],
      [4, 2, 1, 12, 13],
      [4, 2, 3, 22, 23],

   ],
   'data rows (with raw_data_2)'
);

# ###########################################################################
# Don't allow auto inc column value gaps.
# ###########################################################################
$sb->load_file("master", "$in/tbls005.sql", "test");
@ARGV = ('-d', 'test', '-t', 'raw_data,data,entity,data_report');
$o->get_opts();
$copy_rows = make_copier(
   auto_increment_gaps => 0,
   foreign_keys        => 1,
   insert_ignore       => 1,
   src_db              => 'test',
   src_tbl             => 'raw_data',
   txn_size            => 100,
   dst_tbls            => [
      ['test', 'entity'     ], # child2
      ['test', 'data_report'], # child1
      ['test', 'data'       ], # parent
   ],
);

$copy_rows->copy();

@ARGV = ('-d', 'test', '-t', 'raw_data_2,data,entity,data_report');
$o->get_opts();

$copy_rows = make_copier(
   auto_increment_gaps => 0,
   foreign_keys        => 1,
   insert_ignore       => 1,
   src_db              => 'test',
   src_tbl             => 'raw_data_2',
   txn_size            => 100,
   dst_tbls            => [
      ['test', 'entity'     ], # child2
      ['test', 'data_report'], # child1
      ['test', 'data'       ], # parent
   ],
);

$copy_rows->copy();

$rows = $dbh->selectall_arrayref('select * from data_report order by id');
is_deeply(
   $rows,
   [
      [1, '2011-06-01', '2011-06-01 23:23:23', '2011-06-01 23:55:55' ],
      [2, '2011-06-01', '2011-06-01 23:23:23', '2011-06-01 23:55:57' ],
   ],
   'data_report rows (no auto inc gaps)'
) or print Dumper($rows);

$rows = $dbh->selectall_arrayref('select * from entity order by id');
is_deeply(
   $rows,
   [
      [1, 10, 11 ],
      [2, 20, 21 ],
   ],
   'entity rows (no auto inc gaps)'
) or print Dumper($rows);

$rows = $dbh->selectall_arrayref('select * from data order by data_report');
is_deeply(
   $rows,
   [
      [1, 1, 1, 12, 13],
      [1, 2, 1, 12, 13],
      [1, 2, 2, 22, 23],
      [2, 1, 1, 12, 13],
      [2, 2, 1, 12, 13],
      [2, 2, 2, 22, 23],
   ],
   'data rows (no auto inc gaps)'
) or print Dumper($rows);

# ###########################################################################
# Manually mapped columns.
# ###########################################################################
$sb->load_file("master", "mk-insert-normalized/t/samples/col-map.sql");
@ARGV = ('-d', 'test', '-t', 'a,y,z');
$o->get_opts();

$copy_rows = make_copier(
   foreign_keys        => 1,
   src_db              => 'test',
   src_tbl             => 'a',
   ignore_columns      => {id=>1},
   column_map          => [
      { src_col  => 'col1',
        map_once => 0,
        dst_col  => { db => 'test', tbl => 'z', col => 'cola' },
      },
      { src_col  => 'col3',
        map_once => 0,
        dst_col  => { db => 'test', tbl => 'z', col => 'three' },
      },
      { src_col  => 'col2',
        map_once => 1,
        dst_col  => { db => 'test', tbl => 'y', col => 'col2' },
      }
   ],
   dst_tbls            => [
      ['test', 'y'],
      ['test', 'z'],
   ],
);

$copy_rows->copy();

$rows = $dbh->selectall_arrayref('select * from test.y order by id');
is_deeply(
   $rows,
   [
      [1, 1, 1],
      [2, 2, 2],
      [3, 3, 3],
   ],
   'y rows (--column-map)'
);

$rows = $dbh->selectall_arrayref('select id, cola, col2, three from test.z order by id');
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
# Manually mapped columns with duplicate row name.
# ###########################################################################
$sb->load_file("master", "mk-insert-normalized/t/samples/map-name.sql");
@ARGV = ('-d', 'test');
$o->get_opts();

$copy_rows = make_copier(
   foreign_keys        => 1,
   txn_size            => 100,
   insert_ignore       => 1,
   auto_increment_gaps => 0,
   src_db              => 'test',
   src_tbl             => 'raw_data',
   column_map          => [
      { src_col  => 'name_1',
        map_once => 1,
        dst_col  => { db => 'test', tbl => 'entity_1', col => 'name' },
      },
      { src_col  => 'name_2',
        map_once => 1,
        dst_col  => { db => 'test', tbl => 'entity_2', col => 'name' },
      },
   ],
   dst_tbls            => [
      ['test', 'entity_2'],
      ['test', 'data_report'],
      ['test', 'entity_1'],
      ['test', 'data'],
   ],
);

$copy_rows->copy();

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
$sb->load_file("master", "$in/two-fk.sql");
@ARGV = ('-d', 'test');
$o->get_opts();
$copy_rows = make_copier(
   foreign_keys        => 1,
   txn_size            => 100,
   insert_ignore       => 1,
   auto_increment_gaps => 0,
   src_db              => 'test',
   src_tbl             => 'raw_data',
   column_map          => [
      { src_col      => 'name_1',
        group_number => 1,
        dst_col      => { db => 'test', tbl => 'account', col => 'name' },
      },
      { src_col      => 'account_number_1',
        group_number => 1,
        dst_col      => { db => 'test', tbl => 'account', col => 'account_number' },
      },
      { src_col      => 'name_2',
        group_number => 2,
        dst_col      => { db => 'test', tbl => 'account', col => 'name' },
      },
      { src_col      => 'account_number_2',
        group_number => 2,
        dst_col      => { db => 'test', tbl => 'account', col => 'account_number' },
      },
   ],
   fk_column_map       => [
      { db => 'test', tbl => 'data', col => 'sub_account', group_number => 2 },
   ],
   dst_tbls            => [
      ['test', 'account'],
      ['test', 'data_report'],
      ['test', 'data'],
   ],
);

$copy_rows->copy();

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
) or print Dumper($rows);

# ###########################################################################
# Break a copy to create and catch a warning.
# ###########################################################################
$sb->load_file("master", "common/t/samples/osc/tbl001.sql");

# This z value will be truncated, causing a warning.
$dbh->do('ALTER TABLE osc.__new_t DROP COLUMN `c`, ADD COLUMN `c` varchar(2)');
$dbh->do('update osc.t set c="abcdef" where id=3');

@ARGV = qw(-d osc);
$o->get_opts();
$copy_rows = make_copier(
   src_db   => 'osc',
   src_tbl  => 't',
   dst_tbls => [['osc', '__new_t']],
   txn_size => 2,
   warnings => 'die',
);

$rows = $dbh->selectall_arrayref('select * from osc.t order by id');
is_deeply(
   $rows,
   [ [qw(1 a)], [qw(2 b)], [qw(3 abcdef)], [qw(4 d)], [qw(5 e)] ],
   'Source table has rows'
);

# Copy all rows from osc.t --> osc.__new_t.
$output = output(
   sub { $copy_rows->copy() },
   stderr => 1,
);

is_deeply(
   $dbh->selectall_arrayref('select * from osc.__new_t order by id'),
   [ [qw(1 a)], [qw(2 b)], ], # [qw(3 ab)], [qw(4 d)], [qw(5 e)] ],
   "Warn and partial copy"
);

like(
   $output,
   qr/Warning after INSERT: Warning 1265 Data truncated for column 'c'/,
   'Print warning from SHOW WARNINGS'
);

like(
   $output,
   qr/Dying because of the warnings above/,
   'Dies because of warnings'
);

# Again but don't die this time.
$sb->load_file("master", "common/t/samples/osc/tbl001.sql");

# This z value will be truncated, causing a warning.
$dbh->do('ALTER TABLE osc.__new_t DROP COLUMN `c`, ADD COLUMN `c` varchar(2)');
$dbh->do('update osc.t set c="abcdef" where id=3');

@ARGV = qw(-d osc);
$o->get_opts();
$copy_rows = make_copier(
   src_db   => 'osc',
   src_tbl  => 't',
   dst_tbls => [['osc', '__new_t']],
   txn_size => 2,
   warnings => 'warn',
);

# Copy all rows from osc.t --> osc.__new_t.
$output = output(
   sub { $copy_rows->copy() },
   stderr => 1,
);

like(
   $output,
   qr/Warning after INSERT: Warning 1265 Data truncated for column/,
   'Warning with warn'
);

is_deeply(
   $dbh->selectall_arrayref('select * from osc.__new_t order by id'),
   [ [qw(1 a)], [qw(2 b)], [qw(3 ab)], [qw(4 d)], [qw(5 e)] ],
   "Warn but copy row"
);

is(
   $stats->{show_warnings},
   5,
   '5 SHOW WARNINGS'
);

# And again but ignore the warning.
$sb->load_file("master", "common/t/samples/osc/tbl001.sql");
$dbh->do('ALTER TABLE osc.__new_t DROP COLUMN `c`, ADD COLUMN `c` varchar(2)');
$dbh->do('update osc.t set c="abcdef" where id=3');
@ARGV = qw(-d osc);
$o->get_opts();
$copy_rows = make_copier(
   src_db   => 'osc',
   src_tbl  => 't',
   dst_tbls => [['osc', '__new_t']],
   txn_size => 2,
   warnings => 'ignore',
);

$output = output(
   sub { $copy_rows->copy() },
   stderr => 1,
);

unlike(
   $output,
   qr/Warning after INSERT: Warning 1265 Data truncated for column/,
   'Warning with warn'
);

is_deeply(
   $dbh->selectall_arrayref('select * from osc.__new_t order by id'),
   [ [qw(1 a)], [qw(2 b)], [qw(3 ab)], [qw(4 d)], [qw(5 e)] ],
   "No warning and rows copied"
);

is(
   $stats->{show_warnings},
   undef,
   'No SHOW WARNINGS'
);

# #############################################################################
# Done.
# #############################################################################
$output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $copy_rows->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
$sb->wipe_clean($dbh);
exit;
