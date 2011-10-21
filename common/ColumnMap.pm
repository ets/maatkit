# This program is copyright 2011 Percona Inc.
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
# ColumnMap package $Revision: 7624 $
# ###########################################################################

# Package: ColumnMap
# ColumnMap maps columns from one table to other tables.  A column map helps
# decompose a table into serveral other tables (for example, normalizing a
# denormalized table).  For all columns in the given source table, the given
# <Schema> is searched for other tables with identical column names.  It's
# possible for a single column to map to multiple columns in different tables.
#
# A column map is used by selecting mapped columns from the source table, then
# inserting mapped columns into the destination tables using mapped values.
# See the test file or mk-insert-normalized and its test for examples.
package ColumnMap;

{ # package scope
use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

# Insert group columns array index
use constant DST_COL    => 0;  # Dest table column receiving value
use constant VALUE_TYPE => 1;  # Type of value being inserted
use constant VALUE      => 2;  # The value being insrted

# Value types (value for DST_COL comes from a...)
use constant COLUMN       => 1;
use constant SELECTED_ROW => 2;
use constant CONSTANT     => 3;

# Sub: new
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   src_tbl  - <Schema::get_table()> to map columns from.
#   dst_tbls - Arrayref of <Schema::get_table()> hashrefs.
#   Schema   - <Schema> object with tables to map tbl columns to.
#   Quoter   - <Quoter> object.
#
# Optional Arguments:
#   ignore_columns         - Hashref of src_tbl columns to ignore (not mapped),
#                            keyed on column name with any true value.
#   constant_values        - Hashref of constant values, keyed on column name.
#   column_map             - Arrayref of hashrefs w/ column mappings.
#   foreign_key_column_map - Arrayref of hashrefs w/ fk column mappings.
#   print                  - Print column map.
#
# Returns:
#   ColumnMap object
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(src_tbl dst_tbls Schema Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($src_tbl, $dst_tbls, $schema) = @args{@required_args};
   my $ignore_columns  = $args{ignore_columns};
   my $constant_values = $args{constant_values};
   my $column_map      = $args{column_map};
   my $fk_map          = $args{foreign_key_column_map}; 
   
   my %map_once;

   DST_TBL:
   foreach my $dst_tbl ( @$dst_tbls ) {
      MKDEBUG && _d('Mapping columns in dest table',
         $dst_tbl->{db}, $dst_tbl->{tbl});

      my %fk_col;
      if ( my $fks = $dst_tbl->{fk_struct} ) {
         foreach my $fk ( values %$fks ) {
            map { $fk_col{$_} = $fk } @{$fk->{cols}};
         }
      }

      my @insert_plan;
      DST_COL:
      foreach my $dst_col ( @{$dst_tbl->{tbl_struct}->{cols}} ) {
         if ( $ignore_columns && $ignore_columns->{$dst_col} ) {
            MKDEBUG && _d($dst_col, 'is ignored');
            next DST_COL;
         }
         
         if ( $constant_values && defined $constant_values->{$dst_col} ) {
            MKDEBUG && _d($dst_col, 'gets values from contant value');
            push @{$insert_plan[0]->{columns}}, [
               $dst_col,
               CONSTANT,
               $constant_values->{$dst_col},
            ];
            $src_tbl->{mapped_columns}->{$dst_col}++;
            next DST_COL;
         } # const map

         if ( $column_map ) {
            my $mapped_cols = 0;
            foreach my $map (
               grep {
                     $dst_tbl->{db}  eq $_->{dst_col}->{db}
                  && $dst_tbl->{tbl} eq $_->{dst_col}->{tbl}
                  && $dst_col        eq $_->{dst_col}->{col}
               } @$column_map ) {
               my $groupno = ($map->{group_number} || 1) - 1;
               MKDEBUG && _d($dst_col, 'gets values from mapped column',
                  $map->{src_col}, 'for insert group', $groupno);
               push @{$insert_plan[$groupno]->{columns}}, [
                  $dst_col,
                  COLUMN,
                  $map->{src_col},
               ];
               $src_tbl->{mapped_columns}->{$map->{src_col}}++;
               if ( $map->{map_once} ) {
                  $map_once{$dst_col} = 1;
               }
               else {
                  $mapped_cols++;
               }
            }
            next DST_COL if $mapped_cols;
         } # manual col map

         if ( my $fk = $fk_col{$dst_col} ) {
            MKDEBUG && _d($dst_col, 'is a foreign key column');
            my $groupno = 0;
            if ( $fk_map ) {
               FK_MAP:
               foreach my $map ( @$fk_map ) {
                  if (    $dst_tbl->{db}  eq $map->{db}
                       && $dst_tbl->{tbl} eq $map->{tbl}
                       && $dst_col        eq $map->{col} )
                  {
                     $groupno = ($map->{group_number} || 1) - 1;
                     last FK_MAP;
                  }
               }
            }

            my $select_row_params = _map_fk(
               %args,
               tbl     => $dst_tbl,
               fk      => $fk,
               groupno => $groupno,
            );
            if ( $select_row_params ) {
               MKDEBUG && _d($dst_col,'gets values from insert group',$groupno);
               push @{$insert_plan[0]->{columns}}, [
                  $dst_col,
                  SELECTED_ROW,
                  $select_row_params,
               ];
               next DST_COL;
            }

            # If the fk col doesn't map, then try other methods, i.e. normal
            # auto-col mapping by name (the next if block). 
            MKDEBUG && _d('Foreign key column did not map');
         } # fk map

         if ( $src_tbl->{tbl_struct}->{is_col}->{$dst_col} ) {
            if ( $map_once{$dst_col} ) {
               MKDEBUG && _d($dst_col, "is already mapped once");
               next DST_COL;
            }
            if ( $column_map ) {
               foreach my $map (
                  grep { $dst_col eq $_->{src_col} } @$column_map )
               {
                  if ( $map->{map_once} ) {
                     MKDEBUG && _d($dst_col, "will be manually mapped");
                     next DST_COL;
                  }
               }
            }

            MKDEBUG && _d($dst_col, 'gets values from source column', $dst_col);
            push @{$insert_plan[0]->{columns}}, [
               $dst_col,
               COLUMN,
               $dst_col,
            ];
            $src_tbl->{mapped_columns}->{$dst_col}++;
            next DST_COL;
         } # auto col map

         MKDEBUG && _d($dst_col, 'is not mapped');
      } # DST_COL

      _check_insert_plan(
         tbl         => $dst_tbl,
         insert_plan => \@insert_plan,
      );
      for my $i ( 0..$#insert_plan ) {
         $insert_plan[$i]->{group_number}    = $i;
         $dst_tbl->{last_row_inserted}->[$i] = undef;
      }
      $dst_tbl->{insert_plan} = \@insert_plan;

   } # DST_TBL

   my $self = {
      %args,
   };

   return bless $self, $class;
}

sub _map_fk {
   my ( %args ) = @_;
   my @required_args = qw(fk tbl Schema);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($fk, $tbl, $schema) = @args{@required_args};
   my $groupno             = $args{groupno} || 0;

   # Each fk constraint essentially maps fk columns in the source table
   # to parent columns.  For example,
   #   CONSTRAINT foo FOREIGN KEY            (fk_col1, fk_col2)
   #                  REFERENCES  parent_tbl (p_col1,  p_col2)
   # Column dst_tbl.fk_col1 is mapped/constrained to parent_tbl.p_col1.
   # So we must preserve these mappings/contraints, else the caller won't
   # have all the necessary values to insert rows into the dest tables.
   MKDEBUG && _d('Mapping fk columns in constraint', $fk->{name});

   # TableParser::get_fks() should handle this, but just in case...
   if ( !$fk->{parent_tbl}->{db} ) {
      MKDEBUG && _d('No fk parent table database,',
         'assuming child table database', $tbl->{db});
      $fk->{parent_tbl}->{db} = $tbl->{db};
   }
   my $parent_tbl = $schema->get_table(@{$fk->{parent_tbl}}{qw(db tbl)}); 
   if ( !$parent_tbl ) {
      MKDEBUG && _d('Parent table', @{$fk->{parent_tbl}}{qw(db tbl)},
         'was filtered out');
      return;
   }

   my @fk_cols     = @{$fk->{cols}};
   my @parent_cols = @{$fk->{parent_cols}};
   my %cols;
   FK_COLUMN:
   for my $i ( 0..$#fk_cols ) {
      my $fk_col     = $fk_cols[$i];
      my $parent_col = $parent_cols[$i];
      MKDEBUG && _d($fk_col, 'references',
         $parent_tbl->{db}, $parent_tbl->{tbl}, $parent_col);
      $cols{$parent_col} = $fk_col;
      if ( $args{print} ) {
         print "-- Foreign key column $tbl->{db}.$tbl->{tbl}.$fk_col "
             . "maps to column "
             . "$parent_tbl->{db}.$parent_tbl->{tbl}.$parent_col\n";
      }
   }

   my $select_row_params = {
      tbl   => $parent_tbl,
      cols  => \%cols,
      where => \$parent_tbl->{last_row_inserted}->[$groupno], # ref to hashref
   };
   return $select_row_params;
}

sub _check_insert_plan {
   my ( %args ) = @_;
   my @required_args = qw(tbl insert_plan);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tbl, $insert_plan) = @args{@required_args};

   foreach my $insert_group ( @$insert_plan ) {
      my %seen;
      foreach my $col ( @{$insert_group->{columns}} ) {
         if ( my $first_col = $seen{$col->[DST_COL]} ) {
            die "Two values are mapped to $tbl->{db}.$tbl->{tbl}."
               . $col->[DST_COL] . ": "
               . _print_column_value($col)
               . " and " . _print_column_value($first_col) . "\n";
         }
         $seen{$col->[DST_COL]} = $col;
      }
   }

   return;
}

sub _print_column_value {
   my ( $col ) = @_;
   return "" unless $col;
   my $str = (  $col->[VALUE_TYPE] == COLUMN       ? 'column'
              : $col->[VALUE_TYPE] == CONSTANT     ? 'constant'
              : $col->[VALUE_TYPE] == SELECTED_ROW ? 'selected row'
              :                                      'invalid type');
   if ( $col->[VALUE_TYPE] != SELECTED_ROW ) {
      $str .= ' ' . $col->[VALUE];
   }
   return $str;
}

sub _select_row {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh select_row_params);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $params) = @args{@required_args};
   my $tbl            = $params->{tbl};
   my $where          = $params->{where};  # this is a ref to a hashref
   MKDEBUG && _d('Selecting row from', $tbl->{db}, $tbl->{tbl});

   my $sth = $params->{select_row_sth} ||= $self->_make_select_row_sth(%args);
   MKDEBUG && _d($sth->{Statement});

   # $where is a ref to a hashref, so it has to be dereferenced with $$
   my @params = map { $$where->{$_} } sort keys %$$where;
   print $sth->{Statement}, "\n" if $self->{print};
   $sth->execute(@params);

   my $row = $sth->fetchrow_hashref();
   MKDEBUG && _d('Selected row:', Dumper($row));

   $sth->finish();
   return $row;
}

sub _make_select_row_sth {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh select_row_params);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $params)       = @args{@required_args};
   my ($tbl, $cols, $where) = @{$params}{qw(tbl cols where)};
   my $q                    = $self->{Quoter};

   my $sql
      = "SELECT "
      . join(', ', map {
            $q->quote($_) . " AS " . $q->quote($cols->{$_}) } sort keys %$cols)
      . " FROM " . $q->quote($tbl->{db}, $tbl->{tbl})
      . " WHERE " . join(' AND ',map { $q->quote($_)."=?" } sort keys %$$where)
      . " LIMIT 1";

   my $sth = $args{dbh}->prepare($sql);
   return $sth;
}

sub insert_plan {
   my ( $self, $tbl ) = @_;
   die "I need a tbl argument" unless $tbl;
   if ( !$tbl->{insert_plan} ) {
      MKDEBUG && _d('No insert plan for table', $tbl->{db}, $tbl->{tbl});
      return;
   }
   return $tbl->{insert_plan};
}

sub mapped_columns {
   my ( $self, $tbl ) = @_;
   if ( !$tbl->{mapped_columns} ) {
      return;
   }
   my $cols = sort_columns(
      tbl  => $tbl,
      cols => [ keys %{$tbl->{mapped_columns}} ],
   );
   return $cols;
}

sub insert_columns {
   my ( $self, $column_group ) = @_;
   die "I need a tbl argument" unless $column_group;
   my @cols;
   foreach my $col ( @{$column_group->{columns}} ) {
      push @cols, $col->[DST_COL];
   }
   return \@cols;
}

sub map_values {
   my ( $self, %args ) = @_;
   my @required_args = qw(src_row dst_tbl insert_group);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($src_row, $dst_tbl, $insert_group) = @args{@required_args};

   my %dst_row;
   COLUMN:
   foreach my $col ( @{$insert_group->{columns}} ) {
      my ($dst_col, $value_type, $value) = @$col;
      if ( $value_type == COLUMN ) {
         MKDEBUG && _d('Value for column', $dst_col,
            'comes from column', $value);
         $dst_row{$dst_col} = $src_row->{$value};
      }
      elsif ( $value_type == SELECTED_ROW ) {
         MKDEBUG && _d('Value for column', $dst_col,
            'comes from a selected row');
         my $selected_row = $self->_select_row(
            %args,
            select_row_params => $value,
         );
         $dst_row{$dst_col} = $selected_row->{$dst_col};
      }
      elsif ( $value_type == CONSTANT ) {
         MKDEBUG && _d('Value for column', $dst_col,
            'comes from a constant value');
         $dst_row{$dst_col} = $value;
      }
      else {
         die "Invalid value type for $dst_tbl->{db}.$dst_tbl->{tbl}.$dst_col: "
            . (defined $value_type ? $value_type : '');
      }
   }

   MKDEBUG && _d("Mapped values:\n",
      map {
         my $col = $_->[DST_COL];
         "$col=" . (defined $dst_row{$col} ? $dst_row{$col} : 'undef') . "\n"
      } @{$insert_group->{columns}});

   $dst_tbl->{last_row_inserted}->[$insert_group->{group_number}] = \%dst_row;

   return \%dst_row;
}

# Sub: sort_columns
#   Sort columns based on their real order in the table.
#
# Parameters:
#   %args - Arguments.
#
# Required Arguments:
#   tbl  - <Schema::get_table()> hashref.
#   cols - Arrayref of columns in tbl to sort.
#
# Returns:
#   Array of sorted column names.
sub sort_columns {
   my ( %args ) = @_;
   my @required_args = qw(tbl cols);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $col_pos = $args{tbl}->{tbl_struct}->{col_posn};
   my $cols    = $args{cols};

   my @sorted_cols
      = sort { $col_pos->{$a} <=> $col_pos->{$b} } 
        grep { defined $col_pos->{$_}            }
        @$cols;

   return \@sorted_cols;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

} # package scope
1;

# ###########################################################################
# End ColumnMap package
# ###########################################################################
