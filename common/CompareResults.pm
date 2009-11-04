# This program is copyright 2009-@CURRENTYEAR@ Percona Inc.
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
# CompareResults package $Revision$
# ###########################################################################
package CompareResults;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Time::HiRes qw(time);

use constant MKDEBUG => $ENV{MKDEBUG};

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(method base-dir QueryParser MySQLDump TableParser
                          TableSyncer plugins Quoter get_id);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      %args,
      tmp_tbl => '',
      wrap    => '',
      diffs   => {},
   };
   return bless $self, $class;
}

sub before_execute {
   my ( $self, %args ) = @_;
   my @required_args = qw(event dbh tmp_tbl);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($event, $dbh, $tmp_tbl) = @args{@required_args};
   my $sql;

   # Clear previous tmp tbl and tmp tbl wrap.
   $self->{tmp_tbl} = '';
   $self->{wrap}    = '';

   if ( $self->{method} eq 'checksum' ) {
      eval {
         $sql = "DROP TABLE IF EXISTS $tmp_tbl";
         MKDEBUG && _d($sql);
         $dbh->do($sql);

         $sql = "SET storage_engine=MyISAM";
         MKDEBUG && _d($sql);
         $dbh->do($sql);
      };
      if ( $EVAL_ERROR ) {
         MKDEBUG && _d('Error dropping table', $tmp_tbl, ':', $EVAL_ERROR);
         return;
      }

      # Save this tmp tbl and wrap; used later in after_execute()
      # and checksum_results().
      $self->{tmp_tbl} = $tmp_tbl; 
      $self->{wrap}    = "CREATE TEMPORARY TABLE $tmp_tbl AS ";

      # Wrap the original query so when it's executed its results get
      # put in tmp table.
      $event->{arg} = $self->{wrap} . $event->{arg};
      MKDEBUG && _d('Wrapped query:', $event->{arg});
   }

   return $event;
}

sub execute {
   my ( $self, %args ) = @_;
   my @required_args = qw(event dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($event, $dbh) = @args{@required_args};
   my $query         = $event->{arg};
   my ( $start, $end, $query_time );

   $event->{Query_time} = 0;

   if ( $self->{method} eq 'rows' ) {
      my $sth;
      eval {
         $sth = $dbh->prepare($query);
      };
      if ( $EVAL_ERROR ) {
         MKDEBUG && _d('Error on prepare:', $EVAL_ERROR);
         return;
      }

      eval {
         $start = time();
         $sth->execute();
         $end   = time();
         $query_time = sprintf '%.6f', $end - $start;
      };
      if ( $EVAL_ERROR ) {
         MKDEBUG && _d('Error executing query:', $EVAL_ERROR);
         return;
      }

      $event->{results_sth} = $sth;
   }
   else {
      eval {
         $start = time();
         $dbh->do($query);
         $end   = time();
         $query_time = sprintf '%.6f', $end - $start;
      };
      if ( $EVAL_ERROR ) {
         MKDEBUG && _d('Error executing query:', $EVAL_ERROR);
         return;
      }
   }

   $event->{Query_time} = $query_time;

   return $event;
}

sub after_execute {
   my ( $self, %args ) = @_;
   my @required_args = qw(event);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($event) = @args{@required_args};

   if ( $self->{method} eq 'checksum' ) {
      $event->{arg} =~ s/^$self->{wrap}//;
      MKDEBUG && _d('Unwrapped query:', $event->{arg}); 
   }

   return $event;
}

sub compare {
   my ( $self, %args ) = @_;
   my @required_args = qw(events hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   $self->{diffs} = {};
   my ($events, $hosts) = @args{@required_args};
   return $self->{method} eq 'rows' ? $self->_compare_rows(%args)
                                    : $self->_compare_checksums(%args);
}

sub _compare_checksums {
   my ( $self, %args ) = @_;
   my @required_args = qw(events hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($events, $hosts) = @args{@required_args};

   my $event0 = $self->_checksum_results(
      event => $events->[0],
      dbh   => $hosts->[0]->{dbh},
   );

   my $different_row_counts    = 0;
   my $different_column_counts = 0; # TODO
   my $different_column_types  = 0; # TODO
   my $different_checksums     = 0;

   my $n_events = scalar @$events;
   foreach my $i ( 1..($n_events-1) ) {
      my $event = $self->_checksum_results(
         event => $events->[$i],
         dbh   => $hosts->[$i]->{dbh},
      );

      $different_checksums++
         if ($event0->{checksum} || 0) != ($event->{checksum} || 0);
      $different_row_counts++
         if ($event0->{row_count} || 0) != ($event->{row_count} || 0);
   }

   my $item = $event0->{fingerprint} || $event0->{arg};
   if ( $different_checksums ) {
      $self->{diffs}->{checksums}->{$item}->{$event0->{sampleno} || 0}
         = [ map { $_->{checksum} } @$events ];
   }

   return (
      different_row_counts    => $different_row_counts,
      different_checksums     => $different_checksums,
      different_column_counts => $different_column_counts,
      different_column_types  => $different_column_types,
   );
}

sub _checksum_results {
   my ( $self, %args ) = @_;
   my @required_args = qw(event dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($event, $dbh) = @args{@required_args};
   my $tmp_tbl       = $self->{tmp_tbl};
   my $sql;

   my $n_rows       = 0;
   my $tbl_checksum = 0;
   eval {
      $sql = "SELECT COUNT(*) FROM $tmp_tbl";
      MKDEBUG && _d($sql);
      ($n_rows) = @{ $dbh->selectcol_arrayref($sql) };

      $sql = "CHECKSUM TABLE $tmp_tbl";
      MKDEBUG && _d($sql);
      $tbl_checksum = $dbh->selectrow_arrayref($sql)->[1];
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d('Error counting rows or checksumming', $tmp_tbl, ':',
         $EVAL_ERROR);
      return;
   }
   $event->{row_count} = $n_rows;
   $event->{checksum}  = $tbl_checksum;
   MKDEBUG && _d('n rows:', $n_rows, 'tbl checksum:', $tbl_checksum);

   $sql = "DROP TABLE IF EXISTS $tmp_tbl";
   MKDEBUG && _d($sql);
   eval { $dbh->do($sql); };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d('Error dropping tmp table:', $EVAL_ERROR);
      return;
   }

   return $event;
}

sub _compare_rows {
   my ( $self, %args ) = @_;
   my @required_args = qw(events hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($events, $hosts) = @args{@required_args};

   my $different_row_counts    = 0;
   my $different_column_counts = 0; # TODO
   my $different_column_types  = 0; # TODO
   my $different_column_values = 0;

   my $n_events = scalar @$events;
   my $event0   = $events->[0]; 
   my $item     = $event0->{fingerprint} || $event0->{arg};
   my $dbh      = $hosts->[0]->{dbh};  # doesn't matter which one

   my $res_struct = MockSyncStream::get_result_set_struct($dbh,
      $event0->{results_sth});
   MKDEBUG && _d('Result set struct:', Dumper($res_struct));

   # Use a mock sth so we don't have to re-execute event0 sth to compare
   # it to the 3rd and subsequent events.
   my @event0_rows      = @{ $event0->{results_sth}->fetchall_arrayref({}) };
   $event0->{row_count} = scalar @event0_rows;
   my $left = new MockSth(@event0_rows);
   $left->{NAME} = [ @{$event0->{results_sth}->{NAME}} ];

   EVENT:
   foreach my $i ( 1..($n_events-1) ) {
      my $event = $events->[$i];
      my $right = $event->{results_sth};

      $event->{row_count} = 0;

      # Identical rows are ignored.  Once a difference on either side is found,
      # we gobble the remaining rows in that sth and print them to an outfile.
      # This short circuits RowDiff::compare_sets() which is what we want to do.
      my $no_diff      = 1;  # results are identical; this catches 0 row results
      my $outfile      = new Outfile();
      my ($left_outfile, $right_outfile, $n_rows);
      my $same_row     = sub {
            $event->{row_count}++;  # Keep track of this event's row_count.
            return;
      };
      my $not_in_left  = sub {
         my ( $rr ) = @_;
         $no_diff = 0;
         # $n_rows will be added later to this event's row_count.
         ($right_outfile, $n_rows) = $self->write_to_outfile(
            side    => 'right',
            sth     => $right,
            row     => $rr,
            Outfile => $outfile,
         );
         return;
      };
      my $not_in_right = sub {
         my ( $lr ) = @_;
         $no_diff = 0;
         # left is event0 so we don't need $n_rows back.
         ($left_outfile, undef) = $self->write_to_outfile(
            side    => 'left',
            sth     => $left,
            row     => $lr,
            Outfile => $outfile,
         ); 
         return;
      };

      my $rd       = new RowDiff(dbh => $dbh);
      my $mocksync = new MockSyncStream(
         query        => $event0->{arg},
         cols         => $res_struct->{cols},
         same_row     => $same_row,
         not_in_left  => $not_in_left,
         not_in_right => $not_in_right,
      );

      MKDEBUG && _d('Comparing result sets with MockSyncStream');
      $rd->compare_sets(
         left   => $left,
         right  => $right,
         syncer => $mocksync,
         tbl    => $res_struct,
      );

      # Add number of rows written to outfile to this event's row_count.
      # $n_rows will be undef if there were no differences; row_count will
      # still be correct in this case because we kept track of it in $same_row.
      $event->{row_count} += $n_rows || 0;

      $different_row_counts++ if $event0->{row_count} != $event->{row_count};
      $left->reset();
      next EVENT if $no_diff;

      # The result sets differ, so now we must begin the difficult
      # work: finding and determining the nature of those differences.
      MKDEBUG && _d('Result sets are different');


      # Make sure both outfiles are created, else diff_rows() will die.
      if ( !$left_outfile ) {
         MKDEBUG && _d('Right has extra rows not in left');
         (undef, $left_outfile) = $self->open_outfile(side => 'left');
      }
      if ( !$right_outfile ) {
         MKDEBUG && _d('Left has extra rows not in right');
         (undef, $right_outfile) = $self->open_outfile(side => 'right');
      }

      my @diff_rows = $self->diff_rows(
         left_dbh        => $hosts->[0]->{dbh},
         left_outfile    => $left_outfile,
         right_dbh       => $hosts->[$i]->{dbh},
         right_outfile   => $right_outfile,
         res_struct      => $res_struct,
         query           => $event0->{arg},
         db              => $args{tmp_db} || $event0->{db},
         max_differences => $args{max_differences},
      );

      if ( scalar @diff_rows ) { 
         $different_column_values++;
         $self->{diffs}->{col_vals}->{$item}->{$event0->{sampleno} || 0}
            = \@diff_rows;
      }
   }

   return (
      different_row_counts    => $different_row_counts,
      different_column_values => $different_column_values,
      different_column_counts => $different_column_counts,
      different_column_types  => $different_column_types,
   );
}

# Required args:
#   * left_dbh       scalar: active dbh for left
#   * left_outfile   scalar: outfile name for left
#   * right_dbh      scalar: active dbh for right
#   * right_outfile  scalar: outfile name for right
#   * res_struct     hashref: result set structure
#   * db             scalar: database to use for creating temp tables
#   * query          scalar: query, parsed for indexes
# Optional args:
#   * max-differences  scalar: stop after this many differences are found
#   * float-precision  scalar: round float, double, decimal types to N places
# Returns: scalar
# Can die: no
# diff_rows() loads and compares two result sets and returns the number of
# differences between them.  This includes missing rows and row data
# differences.
sub diff_rows {
   my ( $self, %args ) = @_;
   my @required_args = qw(left_dbh left_outfile right_dbh right_outfile
                          res_struct db query);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($left_dbh, $left_outfile, $right_dbh, $right_outfile, $res_struct,
       $db, $query)
      = @args{@required_args};

   # First thing, make two temps tables into which the outfiles can
   # be loaded.  This requires that we make a CREATE TABLE statement
   # for the result sets' columns.
   my $left_tbl  = "`$db`.`mk_upgrade_left`";
   my $right_tbl = "`$db`.`mk_upgrade_right`";
   my $table_ddl = $self->make_table_ddl($res_struct);

   $left_dbh->do("DROP TABLE IF EXISTS $left_tbl");
   $left_dbh->do("CREATE TABLE $left_tbl $table_ddl");
   $left_dbh->do("LOAD DATA LOCAL INFILE '$left_outfile' "
      . "INTO TABLE $left_tbl");

   $right_dbh->do("DROP TABLE IF EXISTS $right_tbl");
   $right_dbh->do("CREATE TABLE $right_tbl $table_ddl");
   $right_dbh->do("LOAD DATA LOCAL INFILE '$right_outfile' "
      . "INTO TABLE $right_tbl");

   MKDEBUG && _d('Loaded', $left_outfile, 'into table', $left_tbl, 'and',
      $right_outfile, 'into table', $right_tbl);

   # Now we need to get all indexes from all tables used by the query
   # and add them to the temp tbl.  Some indexes may be invalid, dupes,
   # or generally useless, but we'll let the sync algo decide that later.
   $self->add_source_indexes(
      %args,
      dsts      => [
         { dbh => $left_dbh,  tbl => $left_tbl  },
         { dbh => $right_dbh, tbl => $right_tbl },
      ],
   );

   # Create a RowDiff with callbacks that will do what we want when rows and
   # columns differ.  This RowDiff is passed to TableSyncer which calls it.
   # TODO: explain how these callbacks work together.
   my $max_diff = $args{'max-differences'} || 1_000;  # 1k=sanity/safety
   my $n_diff   = 0;
   my @missing_rows;
   my @different_rows;
   use constant LEFT  => 0;
   use constant RIGHT => 1;
   my @l_r = (undef, undef);
   my @last_diff_col;
   my $last_diff = 0;
   my $key_cmp      = sub {
      push @last_diff_col, [@_];
      $last_diff--;
      return;
   };
   my $same_row = sub {
      my ( $lr, $rr ) = @_;
      if ( $l_r[LEFT] && $l_r[RIGHT] ) {
         MKDEBUG && _d('Saving different row');
         push @different_rows, $last_diff_col[$last_diff];
         $n_diff++;
      }
      elsif ( $l_r[LEFT] ) {
         MKDEBUG && _d('Saving not in right row');
         push @missing_rows, [$l_r[LEFT], undef];
         $n_diff++;
      }
      elsif ( $l_r[RIGHT] ) {
         MKDEBUG && _d('Saving not in left row');
         push @missing_rows, [undef, $l_r[RIGHT]];
         $n_diff++;
      }
      else {
         MKDEBUG && _d('No missing or different rows in queue');
      }
      @l_r           = (undef, undef);
      @last_diff_col = ();
      $last_diff     = 0;
      return;
   };
   my $not_in_left  = sub {
      my ( $rr ) = @_;
      $same_row->() if $l_r[RIGHT];  # last missing row
      $l_r[RIGHT] = $rr;
      $same_row->(@l_r) if $l_r[LEFT] && $l_r[RIGHT];
      return;
   };
   my $not_in_right = sub {
      my ( $lr ) = @_;
      $same_row->() if $l_r[LEFT];  # last missing row
      $l_r[LEFT] = $lr;
      $same_row->(@l_r) if $l_r[LEFT] && $l_r[RIGHT];
      return;
   };
   my $done = sub {
      my ( $left, $right ) = @_;
      MKDEBUG && _d('Found', $n_diff, 'of', $max_diff, 'max differences');
      if ( $n_diff >= $max_diff ) {
         MKDEBUG && _d('Done comparing rows, got --max-differences', $max_diff);
         $left->finish();
         $right->finish();
         return 1;
      }
      return 0;
   };
   my $trf;
   if ( my $n = $args{'float-precision'} ) {
      $trf = sub {
         my ( $l, $r, $tbl, $col ) = @_;
         return $l, $r
            unless $tbl->{type_for}->{$col} =~ m/(?:float|double|decimal)/;
         my $l_rounded = sprintf "%.${n}f", $l;
         my $r_rounded = sprintf "%.${n}f", $r;
         MKDEBUG && _d('Rounded', $l, 'to', $l_rounded,
            'and', $r, 'to', $r_rounded);
         return $l_rounded, $r_rounded;
      };
   };

   my $rd = new RowDiff(
      dbh          => $left_dbh,
      key_cmp      => $key_cmp,
      same_row     => $same_row,
      not_in_left  => $not_in_left,
      not_in_right => $not_in_right,
      done         => $done,
      trf          => $trf,
   );
   my $ch = new ChangeHandler(
      src_db     => $db,
      src_tbl    => 'mk_upgrade_left',
      dst_db     => $db,
      dst_tbl    => 'mk_upgrade_right',
      tbl_struct => $res_struct,
      queue      => 0,
      replace    => 0,
      actions    => [],
      Quoter     => $self->{Quoter},
   );

   # With whatever index we may have, let TableSyncer choose an
   # algorithm and find were rows differ.  We don't actually sync
   # the tables (execute=>0).  Instead, the callbacks above will
   # save rows in @missing_rows and @different_rows.
   $self->{TableSyncer}->sync_table(
      plugins       => $self->{plugins},
      src           => {
         dbh => $left_dbh,
         db  => $db,
         tbl => 'mk_upgrade_left',
      },
      dst           => {
         dbh => $right_dbh,
         db  => $db,
         tbl => 'mk_upgrade_right',
      },
      tbl_struct    => $res_struct,
      cols          => $res_struct->{cols},
      chunk_size    => 1_000,
      RowDiff       => $rd,
      ChangeHandler => $ch,
   );

   if ( $n_diff < $max_diff ) {
      $same_row->() if $l_r[LEFT] || $l_r[RIGHT];  # save remaining rows
   }

   return @different_rows;
}

# Writes the current row and all remaining rows to an outfile.
# Returns the outfile's name.
sub write_to_outfile {
   my ( $self, %args ) = @_;
   my @required_args = qw(side row sth Outfile);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ( $side, $row, $sth, $outfile ) = @args{@required_args};
   my ( $fh, $file ) = $self->open_outfile(%args);

   # Write this one row.
   $outfile->write($fh, [ MockSyncStream::as_arrayref($sth, $row) ]);

   # Get and write all remaining rows.
   my $remaining_rows = $sth->fetchall_arrayref();
   $outfile->write($fh, $remaining_rows);

   my $n_rows = 1 + @$remaining_rows;
   MKDEBUG && _d('Wrote', $n_rows, 'rows');

   close $fh or warn "Cannot close $file: $OS_ERROR";
   return $file, $n_rows;
}

sub open_outfile {
   my ( $self, %args ) = @_;
   my $outfile = $self->{'base-dir'} . "/$args{side}-outfile.txt";
   open my $fh, '>', $outfile or die "Cannot open $outfile: $OS_ERROR";
   MKDEBUG && _d('Opened outfile', $outfile);
   return $fh, $outfile;
}

# Returns just the column definitions for the given struct.
# Example:
#   (
#     `i` integer,
#     `f` float(10,8)
#   )
sub make_table_ddl {
   my ( $self, $struct ) = @_;
   my $sql = "(\n"
           . (join("\n",
                 map {
                    my $name = $_;
                    my $type = $struct->{type_for}->{$_};
                    my $size = $struct->{size}->{$_} || '';
                    "  `$name` $type$size,";
                 } @{$struct->{cols}}))
           . ')';
   # The last column will be like "`i` integer,)" which is invalid.
   $sql =~ s/,\)$/\n)/;
   MKDEBUG && _d('Table ddl:', $sql);
   return $sql;
}

# Adds every index from every table used by the query to all the
# dest tables.  dest is an arrayref of hashes, one for each destination.
# Each hash needs a dbh and tbl key; e.g.:
#   [
#     {
#       dbh => $dbh,
#       tbl => 'db.tbl',
#     },
#   ],
# For the moment, the sub returns nothing.  In the future, it should
# add to $args{struct}->{keys} the keys that it was able to add.
sub add_source_indexes {
   my ( $self, %args ) = @_;
   my @required_args = qw(query dsts db);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($query, $dsts) = @args{@required_args};

   my $qp = $self->{QueryParser};
   my $tp = $self->{TableParser};
   my $q  = $self->{Quoter};
   my $du = $self->{MySQLDump};

   my @src_tbls = $qp->get_tables($query);
   my @keys;
   foreach my $db_tbl ( @src_tbls ) {
      my ($db, $tbl) = $q->split_unquote($db_tbl, $args{db});
      if ( $db ) {
         my $tbl_struct;
         eval {
            $tbl_struct = $tp->parse(
               $du->get_create_table($dsts->[0]->{dbh}, $q, $db, $tbl)
            );
         };
         if ( $EVAL_ERROR ) {
            MKDEBUG && _d('Error parsing', $db, '.', $tbl, ':', $EVAL_ERROR);
            next;
         }
         push @keys, map {
            my $def = ($_->{is_unique} ? 'UNIQUE ' : '')
                    . "KEY ($_->{colnames})";
            [$def, $_];
         } grep { $_->{type} eq 'BTREE' } values %{$tbl_struct->{keys}};
      }
      else {
         MKDEBUG && _d('Cannot get indexes from', $db_tbl, 'because its '
            . 'database is unknown');
      }
   }
   MKDEBUG && _d('Source keys:', Dumper(\@keys));
   return unless @keys;

   for my $dst ( @$dsts ) {
      foreach my $key ( @keys ) {
         my $def = $key->[0];
         my $sql = "ALTER TABLE `$dst->{tbl}` ADD $key->[0]";
         MKDEBUG && _d($sql);
         eval {
            $dst->{dbh}->do($sql);
         };
         if ( $EVAL_ERROR ) {
            MKDEBUG && _d($EVAL_ERROR);
         }
         else {
            # TODO: $args{res_struct}->{keys}->{$key->[1]->{name}} = $key->[1];
         }
      }
   }

   # If the query uses only 1 table then return its struct.
   # TODO: $args{struct} = $struct if @src_tbls == 1;
   return;
}

sub report {
   my ( $self, %args ) = @_;
   my @required_args = qw(hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($hosts) = @args{@required_args};

   return unless keys %{$self->{diffs}};

   # These columns are common to all the reports; make them just once.
   my $query_id_col = {
      name        => 'Query ID',
      fixed_width => 18,
   };
   my @host_cols = map {
      my $col = { name => $_->{name} };
      $col;
   } @$hosts;

   foreach my $diff ( qw(checksums col_vals) ) {
      my $report = "_report_diff_$diff";
      $self->$report(
         query_id_col => $query_id_col,
         host_cols    => \@host_cols,
         %args
      );
   }
}

sub _report_diff_checksums {
   my ( $self, %args ) = @_;
   my @required_args = qw(query_id_col host_cols);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $get_id = $self->{get_id};

   return unless keys %{$self->{diffs}->{checksums}};

   my $report = new ReportFormatter();
   $report->set_title('Checksum differences');
   $report->set_columns(
      $args{query_id_col},
      @{$args{host_cols}},
   );

   my $diff_checksums = $self->{diffs}->{checksums};
   foreach my $item ( sort keys %$diff_checksums ) {
      map {
         $report->add_line(
            $get_id->($item) . '-' . $_,
            @{$diff_checksums->{$item}->{$_}},
         );
      } sort { $a <=> $b } keys %{$diff_checksums->{$item}};
   }

   $report->print();

   return;
}

sub _report_diff_col_vals {
   my ( $self, %args ) = @_;
   my @required_args = qw(query_id_col host_cols);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $get_id = $self->{get_id};

   return unless keys %{$self->{diffs}->{col_vals}};

   my $report = new ReportFormatter();
   $report->set_title('Column value differences');
   $report->set_columns(
      $args{query_id_col},
      {
         name => 'Column'
      },
      @{$args{host_cols}},
   );
   my $diff_col_vals = $self->{diffs}->{col_vals};
   foreach my $item ( sort keys %$diff_col_vals ) {
      foreach my $sampleno (sort {$a <=> $b} keys %{$diff_col_vals->{$item}}) {
         map {
            $report->add_line(
               $get_id->($item) . '-' . $sampleno,
               @$_,
            );
         } @{$diff_col_vals->{$item}->{$sampleno}};
      }
   }

   $report->print();

   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End CompareResults package
# ###########################################################################