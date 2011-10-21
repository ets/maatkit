#!/usr/bin/perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 15;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use MaatkitTest;
use OptionParser;
use DSNParser;
use Quoter;
use TableParser;
use FileIterator;
use Schema;
use SchemaIterator;
use ForeignKeyIterator;
use ColumnMap;

my $q  = new Quoter;
my $tp = new TableParser(Quoter => $q);

my $o  = new OptionParser(description => 'SchemaIterator');
@ARGV = qw();
$o->get_specs("$trunk/mk-table-checksum/mk-table-checksum");
$o->get_opts();

my $in = "$trunk/common/t/samples/mysqldump-no-data/";
my $schema;
my $column_map;

sub make_column_map {
   my ( %args ) = @_;

   @ARGV = $args{filters} ? @{$args{filters}} : ();
   $o->get_opts();

   my $fi       = new FileIterator();
   my $file_itr = $fi->get_file_itr(@{$args{files}});
   
   $schema = new Schema();

   my $schema_itr;
   my $si       = new SchemaIterator(
      file_itr     => $file_itr,
      OptionParser => $o,
      Quoter       => $q,
      TableParser  => $tp,
      Schema       => $schema,
      keep_ddl     => $args{foreign_keys} ? 1 : 0,
   );
   if ( $args{foreign_keys} ) {
      $schema_itr = new ForeignKeyIterator(
         db             => $args{dst_db},
         tbl            => $args{dst_tbl},
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
   my @dst_tbls;
   while ( my $tbl = $schema_itr->next_schema_object() ) {
      push @dst_tbls, $tbl;
   }

   $column_map = new ColumnMap(
      src_tbl         => $schema->get_table($args{src_db}, $args{src_tbl}),
      dst_tbls        => \@dst_tbls,
      Schema          => $schema,
      constant_values => $args{constant_values},
      ignore_columns  => $args{ignore_columns},
      column_map      => $args{column_map},
      Quoter          => $q,
   );
}

# ############################################################################
# A simple 1-to-1 mapping.
# ############################################################################
make_column_map(
   files           => ["$in/dump002.txt"],
   src_db          => 'test',
   src_tbl         => 'raw_data',
   dst_db          => 'test',
   dst_tbl         => 'data',
   foreign_keys    => 1,
   constant_values => {
      posted   => 'NOW()',
      acquired => '',
   },
);

is_deeply(
   $column_map->mapped_columns($schema->get_table('test', 'raw_data')),
   [qw(date hour entity_property_1 entity_property_2 data_1 data_2)],
   "Mapped source table columns, raw_data"
);

my $plan = $column_map->insert_plan($schema->get_table('test', 'data_report'));
is_deeply(
   $plan,
   [
      {  group_number => 0,
         columns      => [
            [ 'date',     ColumnMap::COLUMN,   'date',  ],
            [ 'posted',   ColumnMap::CONSTANT, 'NOW()', ],
            [ 'acquired', ColumnMap::CONSTANT, '',      ],
         ],
      }
   ],
   "data_report insert plan"
);

$plan = $column_map->insert_plan($schema->get_table('test', 'entity'));
is_deeply(
   $plan,
   [
      {  group_number => 0,
         columns      => [
            [ 'entity_property_1', ColumnMap::COLUMN, 'entity_property_1', ],
            [ 'entity_property_2', ColumnMap::COLUMN, 'entity_property_2', ],
         ],
      }
   ],
   "entity insert plan"
);

my $data_report_tbl = $schema->get_table('test', 'data_report');
my $sel_1 = {
   tbl   => $data_report_tbl,
   cols  => { id => 'data_report' },
   where => \$data_report_tbl->{last_row_inserted}->[0],
};

my $entity_tbl = $schema->get_table('test', 'entity');
my $sel_2 = {
   tbl   => $entity_tbl,
   cols  => { id => 'entity' },
   where => \$entity_tbl->{last_row_inserted}->[0],
};

$plan = $column_map->insert_plan($schema->get_table('test', 'data'));
is_deeply(
   $plan,
   [
      {  group_number => 0,
         columns      => [
            [ 'data_report', ColumnMap::SELECTED_ROW, $sel_1,   ],
            [ 'hour',        ColumnMap::COLUMN,       'hour',   ],
            [ 'entity',      ColumnMap::SELECTED_ROW, $sel_2,   ],
            [ 'data_1',      ColumnMap::COLUMN,       'data_1', ],
            [ 'data_2',      ColumnMap::COLUMN,       'data_2', ],
         ],
      }
   ],
   "data insert plan"
);

# ############################################################################
# Ignore columns, i.e. don't map them.
# ############################################################################
make_column_map(
   files           => ["$in/dump002.txt"],
   src_db          => 'test',
   src_tbl         => 'raw_data',
   dst_db          => 'test',
   dst_tbl         => 'data',
   foreign_keys    => 1,
   constant_values => {
      posted   => 'NOW()',
      acquired => '',
   },
   ignore_columns  => { date => 1 },
);

# Unlike similar tests above, date is no longer mapped.
is_deeply(
   $column_map->mapped_columns($schema->get_table('test', 'raw_data')),
   [qw(hour entity_property_1 entity_property_2 data_1 data_2)],
   "Ignored column not mapped from source table"
);

is_deeply(
   $column_map->insert_plan($schema->get_table('test', 'data_report')),
   [{ group_number => 0,
      columns      => [
         ['posted',   ColumnMap::CONSTANT, 'NOW()'],
         ['acquired', ColumnMap::CONSTANT, ''     ],
      ],
   }],
   "No plan for ignored column"
);

# ############################################################################
# Manual column map.
# ############################################################################
make_column_map(
   files           => ["$in/dump002.txt"],
   src_db          => 'test',
   src_tbl         => 'raw_data',
   dst_db          => 'test',
   dst_tbl         => 'data',
   foreign_keys    => 1,
   column_map      => [
      { src_col => 'date',
        dst_col => { db=>'test', tbl=>'data_report', col=>'posted' },
      },
      { src_col => 'hour',
        dst_col => { db=>'test', tbl=>'data_report', col=>'acquired' },
      }
   ],
);

$plan = $column_map->insert_plan($schema->get_table('test', 'data_report'));
is_deeply(
   $plan,
   [
      {  group_number => 0,
         columns      => [
            [ 'date',     ColumnMap::COLUMN, 'date', ],
            [ 'posted',   ColumnMap::COLUMN, 'date', ],
            [ 'acquired', ColumnMap::COLUMN, 'hour', ],
         ],
      }
   ],
   "data_report insert plan with column map"
);

make_column_map(
   files           => ["$in/dump002.txt"],
   src_db          => 'test',
   src_tbl         => 'raw_data',
   dst_db          => 'test',
   dst_tbl         => 'data',
   foreign_keys    => 1,
   column_map      => [
      { src_col  => 'date',
        map_once => 1,  # XXX
        dst_col  => { db=>'test', tbl=>'data_report', col=>'posted' },
      },
      { src_col => 'hour',
        dst_col => { db=>'test', tbl=>'data_report', col=>'acquired' },
      }
   ],
);

$plan = $column_map->insert_plan($schema->get_table('test', 'data_report'));
is_deeply(
   $plan,
   [
      {  group_number => 0,
         columns      => [
            [ 'posted',   ColumnMap::COLUMN, 'date', ],
            [ 'acquired', ColumnMap::COLUMN, 'hour', ],
         ],
      }
   ],
   "Manual column map once"
) or print Dumper($plan);

# ############################################################################
# Two fk refs requiring two inserts.
# ############################################################################
make_column_map(
   files           => ["$trunk/common/t/samples/CopyRowsNormalized/two-fk.sql"],
   src_db          => 'test',
   src_tbl         => 'raw_data',
   dst_db          => 'test',
   dst_tbl         => 'data',
   foreign_keys    => 1,
   constant_values => {
      date    => '2011-07-06',
      posted  => 'NOW()',
   },
   column_map      => [
      { src_col => 'account_number_1',
        dst_col => { db=>'test', tbl=>'account', col=>'account_number' },
        group_number => 1,
      },
      { src_col => 'name_1',
        dst_col => { db=>'test', tbl=>'account', col=>'name' },
        group_number => 1,
      },
      { src_col => 'account_number_2',
        dst_col => { db=>'test', tbl=>'account', col=>'account_number' },
        group_number => 2,
      },
      { src_col => 'name_2',
        dst_col => { db=>'test', tbl=>'account', col=>'name' },
        group_number => 2,
      },
   ],
   foreign_key_map => [
      { db  => 'test',
        tbl => 'data_report',
        col => 'parent_account',
        group_number => 1,
      },
   ],
);

$data_report_tbl = $schema->get_table('test', 'data_report');
my $account_tbl  = $schema->get_table('test', 'account');
my $data_tbl     = $schema->get_table('test', 'data');

$plan = $column_map->insert_plan($account_tbl);
is_deeply(
   $plan,
   [
      {  group_number => 0,
         columns      => [
            [ 'account_number',
              ColumnMap::COLUMN,
              'account_number_1',
            ],
            [ 'name',
               ColumnMap::COLUMN,
               'name_1',
            ]
         ],
      },
      {  group_number => 1,
         columns      => [
            [ 'account_number',
              ColumnMap::COLUMN,
              'account_number_2',
            ],
            [ 'name',
               ColumnMap::COLUMN,
               'name_2',
            ],
         ],
      }
   ],
   'Insert plan for account'
) or print Dumper($plan);

$plan = $column_map->insert_plan($data_report_tbl);
is_deeply(
   $plan,
   [ # inserts
      {  group_number => 0,
         columns      => [
            [ 'date',
              ColumnMap::CONSTANT,
              '2011-07-06',
            ],
            [ 'posted',
               ColumnMap::CONSTANT,
               'NOW()',
            ],
            [ 'parent_account',
               ColumnMap::SELECTED_ROW,
               { tbl   => $account_tbl,
                 cols  => { id => 'parent_account' },
                 where => \$account_tbl->{last_inserted_row}->[0],
               },
            ],
         ],
      },
   ],
   'Insert plan for data_report'
) or print Dumper($plan);

$plan = $column_map->insert_plan($data_tbl);
is_deeply(
   $plan,
   [
      {  group_number => 0,
         columns      => [
            [ 'data_report',
               ColumnMap::SELECTED_ROW,
               {
                  tbl   => $data_report_tbl,
                  cols  => { id => 'data_report' },
                  where => \$data_report_tbl->{last_inserted_row}->[0],
               },
            ],
            [ 'sub_account',
               ColumnMap::SELECTED_ROW,
               {  tbl   => $account_tbl,
                  cols  => { id => 'sub_account' },
                  where => \$account_tbl->{last_inserted_row}->[1],
               },
            ],
            [ 'data1',
               ColumnMap::COLUMN,
               'data1',
            ],
         ],
      }
   ],
   'Insert plan for data'
) or print Dumper($plan);


# ############################################################################
# Don't map to nonexistent table.
# ############################################################################
make_column_map(
   files           => ["$trunk/mk-insert-normalized/t/samples/animals.sql"],
   src_db          => 'test',
   src_tbl         => 'raw_data_animal_1',
   dst_db          => 'test',
   dst_tbl         => 'animal',
   foreign_keys    => 1,
   filters         => ['--databases', 'test',
                       '--tables',    'raw_data_animal_1,animal,report_animal'],
   column_map      => [
      { src_col  => 'acquired',
        dst_col  => { db=>'test', tbl=>'report_animal', col=>'acquired' },
      },
      { src_col => 'name',
        dst_col => { db=>'test', tbl=>'animal', col=>'name' },
      },
      { src_col => 'max_weight',
        dst_col => { db=>'test', tbl=>'animal', col=>'max_weight' },
      },
   ],
);

my $animal_tbl = $schema->get_table('test', 'animal');
my $report_animal_tbl = $schema->get_table('test', 'report_animal');
$plan = $column_map->insert_plan($animal_tbl);
is_deeply(
   $plan,
   [ {
      columns => [
         [ 'report_animal', ColumnMap::SELECTED_ROW, 
            { tbl   => $report_animal_tbl,
              cols  => { id => 'report_animal' },
              where => \$report_animal_tbl->{last_inserted_row}->[0],
            },
         ],
         [ 'name', ColumnMap::COLUMN, 'name' ],
         [ 'max_weight', ColumnMap::COLUMN, 'max_weight' ]
      ],
      group_number => 0
   } ],
   'Insert plan for animals'
) or print Dumper($plan);

# ############################################################################
# baseball
# ############################################################################
make_column_map(
   files           => ["$trunk/mk-insert-normalized/t/samples/baseball.sql"],
   src_db          => 'test',
   src_tbl         => 'raw_data_baseball',
   dst_db          => 'test',
   dst_tbl         => 'baseball_team',
   foreign_keys    => 1,
   filters         => ['--databases', 'test',
                       '--tables',    'raw_data_baseball,report_baseball_team,baseball_team'],
   column_map      => [
      { src_col  => 'town',
        dst_col  => { db=>'test', tbl=>'baseball_team', col=>'location' },
      },
   ],
);

my $baseball_team_tbl = $schema->get_table('test', 'baseball_team');
my $report_baseball_team_tbl = $schema->get_table('test', 'report_baseball_team');
$plan = $column_map->insert_plan($baseball_team_tbl);
is_deeply(
   $plan,
   [ {
      columns => [
         [ 'report_baseball_team', ColumnMap::SELECTED_ROW, 
            { tbl   => $report_baseball_team_tbl,
              cols  => { id => 'report_baseball_team' },
              where => \$report_baseball_team_tbl->{last_inserted_row}->[0],
            },
         ],
         [ 'name',     ColumnMap::COLUMN, 'name'   ],
         [ 'wins',     ColumnMap::COLUMN, 'wins'   ],
         [ 'losses',   ColumnMap::COLUMN, 'losses' ],
         [ 'location', ColumnMap::COLUMN, 'town'   ],
      ],
      group_number => 0
   } ],
   'Insert plan for baseball'
) or print Dumper($plan);

# baseball2 -- no map required

make_column_map(
   files           => ["$trunk/mk-insert-normalized/t/samples/baseball2.sql"],
   src_db          => 'test',
   src_tbl         => 'raw_data_baseball',
   dst_db          => 'test',
   dst_tbl         => 'baseball_team',
   foreign_keys    => 1,
   filters         => ['--databases', 'test', '--tables', 'raw_data_baseball,report_baseball_team,baseball_team'],
);

$baseball_team_tbl = $schema->get_table('test', 'baseball_team');
$report_baseball_team_tbl = $schema->get_table('test', 'report_baseball_team');
$plan = $column_map->insert_plan($baseball_team_tbl);
is_deeply(
   $plan,
   [ {
      columns => [
         [ 'report_baseball_team', ColumnMap::SELECTED_ROW, 
            { tbl   => $report_baseball_team_tbl,
              cols  => { id => 'report_baseball_team' },
              where => \$report_baseball_team_tbl->{last_inserted_row}->[0],
            },
         ],
         [ 'name',     ColumnMap::COLUMN, 'name'     ],
         [ 'wins',     ColumnMap::COLUMN, 'wins'     ],
         [ 'losses',   ColumnMap::COLUMN, 'losses'   ],
         [ 'location', ColumnMap::COLUMN, 'location' ],
      ],
      group_number => 0
   } ],
   'Insert plan for baseball2'
) or print Dumper($plan);

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $column_map->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;
