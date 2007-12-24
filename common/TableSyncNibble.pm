# This program is copyright (c) 2007 Baron Schwartz.
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
# TableSyncNibble package $Revision$
# ###########################################################################
use strict;
use warnings FATAL => 'all';

# This package implements a moderately complex sync algorithm:
# * Prepare to nibble the table (see TableNibbler.pm)
# * Fetch the nibble'th next row (say the 500th) from the current row
# * Checksum from the current row to the nibble'th as a chunk
# * If a chunk differs, make a note to checksum the rows in the chunk (state 1)
# * Checksum them (state 2)
# * If a row differs, it must be synced
# See TableSyncStream for the TableSync interface this conforms to.
#
# TODO: a variation on this algorithm and benchmark:
# * create table __temp(....);
# * insert into  __temp(....) select pk_cols, row_checksum limit N;
# * select group_checksum(row_checksum) from __temp;
# * if they differ, select each row from __temp;
# * if rows differ, fetch back and sync as usual.
# * truncate and start over.
package TableSyncNibble;

use List::Util qw(max);

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(dbh database table handler nibbler quoter struct
                        parser checksum cols vp chunksize where chunker
                        versionparser possible_keys) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   # Sanity check.  The row-level (state 2) checksums use __crc, so the table
   # had better not use that...
   $args{crc_col} = '__crc';
   while ( $args{struct}->{is_col}->{$args{crc_col}} ) {
      $args{crc_col} = "_$args{crc_col}"; # Prepend more _ until not a column.
   }
   $ENV{MKDEBUG} && _d('CRC column will be named ' . $args{crc_col});

   $args{sel_stmt} = $args{nibbler}->generate_asc_stmt(
      parser   => $args{parser},
      tbl      => $args{struct},
      index    => $args{possible_keys}->[0],
      quoter   => $args{quoter},
      asconly  => 1,
   );
   my $cmp_where = $args{nibbler}->generate_cmp_where(
      type        => '<=', # The "or equal" is because asconly is given above.
      quoter      => $args{quoter},
      slice       => $args{sel_stmt}->{slice},
      cols        => $args{sel_stmt}->{cols},
      is_nullable => $args{struct}->{is_nullable},
   );
   $args{sel_stmt}->{limit} = $cmp_where->{where};

   die "No suitable index found"
      unless $args{sel_stmt}->{index}
         && $args{struct}->{keys}->{$args{sel_stmt}->{index}}->{unique};
   $args{key_cols} = $args{struct}->{keys}->{$args{sel_stmt}->{index}}->{cols};

   # Decide on checksumming strategy and store checksum query prototypes for
   # later. TODO: some of this code might be factored out into TableSyncer.
   $args{algorithm} = $args{checksum}->best_algorithm(
      algorithm   => 'BIT_XOR',
      vp          => $args{vp},
      dbh         => $args{dbh},
      where       => 1,
      chunk       => 1,
      count       => 1,
   );
   $args{func} = $args{checksum}->choose_hash_func(
      func => 'SHA1',
      dbh  => $args{dbh},
   );
   $args{crc_wid} = max(16, length(
      $args{dbh}->selectall_arrayref("SELECT $args{func}('a')")->[0]->[0]));
   if ( $args{algorithm} eq 'BIT_XOR' ) {
      $args{opt_slice}
         = $args{checksum}->optimize_xor(dbh => $args{dbh}, func => 'SHA1');
   }

   $args{chunk_sql} ||= $args{checksum}->make_checksum_query(
      dbname    => $args{database},
      tblname   => $args{table},
      table     => $args{struct},
      quoter    => $args{quoter},
      algorithm => $args{algorithm},
      func      => $args{func},
      crc_wid   => $args{crc_wid},
      opt_slice => $args{opt_slice},
      cols      => $args{cols},
   );
   $args{row_sql} ||= $args{checksum}->make_row_checksum(
      table     => $args{struct},
      quoter    => $args{quoter},
      func      => $args{func},
      cols      => $args{cols},
   );

   $args{state}  = 0;
   $args{nibble} = 0;
   $args{handler}->fetch_back($args{dbh});
   return bless { %args }, $class;
}

# Depth-first: if a nibble is bad, return SQL to inspect rows individually.
# Otherwise get the next nibble.  This way we can sync part of the table before
# moving on to the next part.
sub get_sql {
   my ( $self, %args ) = @_;
   if ( $self->{state} ) {
      return 'SELECT '
         . join(', ', map { $self->{quoter}->quote($_) } @{$self->key_cols()})
         . ', ' . $self->{row_sql} . " AS $self->{crc_col}"
         . ' FROM ' . $self->{quoter}->quote(@args{qw(database table)})
         . ' WHERE (' . $self->{chunks}->[$self->{chunk_num}] . ')'
         . ($args{where} ? " AND ($args{where})" : '');
   }
   else {
      my $where = $self->__get_boundaries();
      return $self->{chunker}->inject_chunks(
         database  => $args{database},
         table     => $args{table},
         chunks    => [$where],
         chunk_num => 0,
         query     => $self->{chunk_sql},
         where     => $args{where},
         quoter    => $self->{quoter},
      );
   }
}

# Returns a WHERE clause for finding out the boundaries of the nibble.
# Initially, it'll just be something like "select key_cols ... limit 499, 1".
# We then remember this row (it is also used elsewhere).  Next time it's like
# "select key_cols ... where > remembered_row limit 499, 1".
sub __get_boundaries {
   my ( $self ) = @_;
   my $sel_stmt = $self->{sel_stmt};
   my $sql = 'SELECT '
      . join(',', map { $self->{quoter}->quote($_) } @{$sel_stmt->{cols}})
      . " FROM " . $self->{quoter}->quote($self->{database}, $self->{table})
      . ($self->{versionparser}->version_ge($self->{dbh}, '4.0.9') ? " FORCE" : " USE")
      . " INDEX(" . $self->{quoter}->quote($sel_stmt->{index}) . ")";
   if ( $self->{nibble} ) {
      # TODO
   }
   $sql .= ' LIMIT ' . ($self->{chunksize} - 1) . ', 1';
   $ENV{MKDEBUG} && _d($sql);
   my $row = $self->{dbh}->selectrow_hashref($sql);

   # Inject the row into the WHERE clause. TODO: what if there's no row
   my $n = $self->{nibbler};
   my $s = $self->{sel_stmt};
   my $i = 0;
   (my $where = $s->{limit})
   =~ s{
      ?
      }
      {
         $n->quote($s->{scols}->[$i++])
      }eg;

   $ENV{MKDEBUG} && _d('WHERE clause: ', $where);
   return $where;
}

sub prepare {
   my ( $self, $dbh ) = @_;
   $dbh->do(q{SET @crc := ''});
}

sub same_row {
   my ( $self, $lr, $rr ) = @_;
   if ( $self->{state} ) {
      if ( $lr->{$self->{crc_col}} ne $rr->{$self->{crc_col}} ) {
         $self->{handler}->change('UPDATE', $lr, $self->key_cols());
      }
   }
   elsif ( $lr->{cnt} != $rr->{cnt} || $lr->{crc} ne $rr->{crc} ) {
      $ENV{MKDEBUG} && _d('Will examine this chunk before moving to next');
      $self->{state} = 1; # Must examine this chunk row-by-row
   }
}

# This (and not_in_left) should NEVER be called in state 0.  If there are
# missing rows in state 0 in one of the tables, the CRC will be all 0's and the
# cnt will be 0, but the result set should still come back.
sub not_in_right {
   my ( $self, $lr ) = @_;
   die "Called not_in_right in state 0" unless $self->{state};
   $self->{handler}->change('INSERT', $lr, $self->key_cols());
}

sub not_in_left {
   my ( $self, $rr ) = @_;
   die "Called not_in_left in state 0" unless $self->{state};
   $self->{handler}->change('DELETE', $rr, $self->key_cols());
}

sub done_with_rows {
   my ( $self ) = @_;
   if ( $self->{state} == 1 ) {
      $self->{state} = 2;
      $ENV{MKDEBUG} && _d("Setting state=$self->{state}");
   }
   else {
      $self->{state} = 0;
      $self->{chunk_num}++;
      $ENV{MKDEBUG}
         && _d("Setting state=$self->{state}, chunk_num=$self->{chunk_num}");
   }
}

sub done {
   my ( $self ) = @_;
   $ENV{MKDEBUG}
      && _d("Done with $self->{chunk_num} of "
       . scalar(@{$self->{chunks}}) . ' chunks');
   $ENV{MKDEBUG} && $self->{state} && _d('Chunk differs; must examine rows');
   return $self->{state} == 0
      && $self->{chunk_num} >= scalar(@{$self->{chunks}})
}

sub pending_changes {
   my ( $self ) = @_;
   if ( $self->{state} ) {
      $ENV{MKDEBUG} && _d('There are pending changes');
      return 1;
   }
   else {
      $ENV{MKDEBUG} && _d('No pending changes');
      return 0;
   }
}

sub key_cols {
   my ( $self ) = @_;
   my @cols;
   if ( $self->{state} == 0 ) {
      @cols = qw(chunk_num);
   }
   else {
      @cols = @{$self->{key_cols}};
   }
   $ENV{MKDEBUG} && _d("State $self->{state}, key cols " . join(', ', @cols));
   return \@cols;
}

sub _d {
   my ( $line ) = (caller(0))[2];
   print "# TableSyncNibble:$line ", @_, "\n";
}

1;

# ###########################################################################
# End TableSyncNibble package
# ###########################################################################
