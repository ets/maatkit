# This program is copyright 2007-2009 Baron Schwartz.
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
# TableNibbler package $Revision: 5266 $
# ###########################################################################
package TableNibbler;

use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(TableParser Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = { %args };
   return bless $self, $class;
}

# Arguments are as follows:
# * tbl_struct    Hashref returned from TableParser::parse().
# * cols          Arrayref of columns to SELECT from the table
# * index         Which index to ascend; optional.
# * asc_only      Whether to ascend strictly, that is, the WHERE clause for
#                 the asc_stmt will fetch the next row > the given arguments.
#                 The option is to fetch the row >=, which could loop
#                 infinitely.  Default is false.
#
# Returns a hashref of
#   * cols:  columns in the select stmt, with required extras appended
#   * index: index chosen to ascend
#   * where: WHERE clause
#   * slice: col ordinals to pull from a row that will satisfy ? placeholders
#   * scols: ditto, but column names instead of ordinals
#
# In other words,
#   $first = $dbh->prepare <....>;
#   $next  = $dbh->prepare <....>;
#   $row = $first->fetchrow_arrayref();
#   $row = $next->fetchrow_arrayref(@{$row}[@slice]);
sub generate_asc_stmt {
   my ( $self, %args ) = @_;
   my @required_args = qw(tbl_struct index);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($tbl_struct, $index) = @args{@required_args};
   my @cols = $args{cols}  ? @{$args{cols}} : @{$tbl_struct->{cols}};
   my $q    = $self->{Quoter};

   # This shouldn't happen.  TableSyncNibble shouldn't call us with
   # a nonexistent index.
   die "Index '$index' does not exist in table"
      unless exists $tbl_struct->{keys}->{$index};

   my @asc_cols = @{$tbl_struct->{keys}->{$index}->{cols}};
   my @asc_slice;

   # These are the columns we'll ascend.
   @asc_cols = @{$tbl_struct->{keys}->{$index}->{cols}};
   MKDEBUG && _d('Will ascend index', $index);
   MKDEBUG && _d('Will ascend columns', join(', ', @asc_cols));
   if ( $args{asc_first} ) {
      @asc_cols = $asc_cols[0];
      MKDEBUG && _d('Ascending only first column');
   }

   # We found the columns by name, now find their positions for use as
   # array slices, and make sure they are included in the SELECT list.
   my %col_posn = do { my $i = 0; map { $_ => $i++ } @cols };
   foreach my $col ( @asc_cols ) {
      if ( !exists $col_posn{$col} ) {
         push @cols, $col;
         $col_posn{$col} = $#cols;
      }
      push @asc_slice, $col_posn{$col};
   }
   MKDEBUG && _d('Will ascend, in ordinal position:', join(', ', @asc_slice));

   my $asc_stmt = {
      cols  => \@cols,
      index => $index,
      where => '',
      slice => [],
      scols => [],
   };

   # ##########################################################################
   # Figure out how to ascend the index by building a possibly complicated
   # WHERE clause that will define a range beginning with a row retrieved by
   # asc_stmt.  If asc_only is given, the row's lower end should not include
   # the row.
   # ##########################################################################
   if ( @asc_slice ) {
      my $cmp_where;
      foreach my $cmp ( qw(< <= >= >) ) {
         # Generate all 4 types, then choose the right one.
         $cmp_where = $self->generate_cmp_where(
            type        => $cmp,
            slice       => \@asc_slice,
            cols        => \@cols,
            quoter      => $q,
            is_nullable => $tbl_struct->{is_nullable},
         );
         $asc_stmt->{boundaries}->{$cmp} = $cmp_where->{where};
      }
      my $cmp = $args{asc_only} ? '>' : '>=';
      $asc_stmt->{where} = $asc_stmt->{boundaries}->{$cmp};
      $asc_stmt->{slice} = $cmp_where->{slice};
      $asc_stmt->{scols} = $cmp_where->{scols};
   }

   return $asc_stmt;
}

# Generates a multi-column version of a WHERE statement.  It can generate >,
# >=, < and <= versions.
# Assuming >= and a non-NULLable two-column index, the WHERE clause should look
# like this:
# WHERE (col1 > ?) OR (col1 = ? AND col2 >= ?)
# Ascending-only and nullable require variations on this.  The general
# pattern is (>), (= >), (= = >), (= = = >=).
sub generate_cmp_where {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(type slice cols is_nullable) ) {
      die "I need a $arg arg" unless defined $args{$arg};
   }
   my @slice       = @{$args{slice}};
   my @cols        = @{$args{cols}};
   my $is_nullable = $args{is_nullable};
   my $type        = $args{type};
   my $q           = $self->{Quoter};

   (my $cmp = $type) =~ s/=//;

   my @r_slice;    # Resulting slice columns, by ordinal
   my @r_scols;    # Ditto, by name

   my @clauses;
   foreach my $i ( 0 .. $#slice ) {
      my @clause;

      # Most of the clauses should be strict equality.
      foreach my $j ( 0 .. $i - 1 ) {
         my $ord = $slice[$j];
         my $col = $cols[$ord];
         my $quo = $q->quote($col);
         if ( $is_nullable->{$col} ) {
            push @clause, "((? IS NULL AND $quo IS NULL) OR ($quo = ?))";
            push @r_slice, $ord, $ord;
            push @r_scols, $col, $col;
         }
         else {
            push @clause, "$quo = ?";
            push @r_slice, $ord;
            push @r_scols, $col;
         }
      }

      # The last clause in each parenthesized group should be > or <, unless
      # it's the very last of the whole WHERE clause and we are doing "or
      # equal," when it should be >= or <=.
      my $ord = $slice[$i];
      my $col = $cols[$ord];
      my $quo = $q->quote($col);
      my $end = $i == $#slice; # Last clause of the whole group.
      if ( $is_nullable->{$col} ) {
         if ( $type =~ m/=/ && $end ) {
            push @clause, "(? IS NULL OR $quo $type ?)";
         }
         elsif ( $type =~ m/>/ ) {
            push @clause, "((? IS NULL AND $quo IS NOT NULL) OR ($quo $cmp ?))";
         }
         else { # If $type =~ m/</ ) {
            push @clause, "((? IS NOT NULL AND $quo IS NULL) OR ($quo $cmp ?))";
         }
         push @r_slice, $ord, $ord;
         push @r_scols, $col, $col;
      }
      else {
         push @r_slice, $ord;
         push @r_scols, $col;
         push @clause, ($type =~ m/=/ && $end ? "$quo $type ?" : "$quo $cmp ?");
      }

      # Add the clause to the larger WHERE clause.
      push @clauses, '(' . join(' AND ', @clause) . ')';
   }
   my $result = '(' . join(' OR ', @clauses) . ')';
   my $where = {
      slice => \@r_slice,
      scols => \@r_scols,
      where => $result,
   };
   return $where;
}

# Figure out how to delete rows. DELETE requires either an index or all
# columns.  For that reason you should call this before calling
# generate_asc_stmt(), so you know what columns you'll need to fetch from the
# table.  Arguments:
#   * tbl_struct
#   * cols
#   * index
# These are the same as the arguments to generate_asc_stmt().  Return value is
# similar too.
sub generate_del_stmt {
   my ( $self, %args ) = @_;

   my $tbl  = $args{tbl_struct};
   my @cols = $args{cols} ? @{$args{cols}} : ();
   my $tp   = $self->{TableParser};
   my $q    = $self->{Quoter};

   my @del_cols;
   my @del_slice;

   # ##########################################################################
   # Detect the best or preferred index to use for the WHERE clause needed to
   # delete the rows.
   # ##########################################################################
   my $index = $tp->find_best_index($tbl, $args{index});
   die "Cannot find an ascendable index in table" unless $index;

   # These are the columns needed for the DELETE statement's WHERE clause.
   if ( $index ) {
      @del_cols = @{$tbl->{keys}->{$index}->{cols}};
   }
   else {
      @del_cols = @{$tbl->{cols}};
   }
   MKDEBUG && _d('Columns needed for DELETE:', join(', ', @del_cols));

   # We found the columns by name, now find their positions for use as
   # array slices, and make sure they are included in the SELECT list.
   my %col_posn = do { my $i = 0; map { $_ => $i++ } @cols };
   foreach my $col ( @del_cols ) {
      if ( !exists $col_posn{$col} ) {
         push @cols, $col;
         $col_posn{$col} = $#cols;
      }
      push @del_slice, $col_posn{$col};
   }
   MKDEBUG && _d('Ordinals needed for DELETE:', join(', ', @del_slice));

   my $del_stmt = {
      cols  => \@cols,
      index => $index,
      where => '',
      slice => [],
      scols => [],
   };

   # ##########################################################################
   # Figure out how to target a single row with a WHERE clause.
   # ##########################################################################
   my @clauses;
   foreach my $i ( 0 .. $#del_slice ) {
      my $ord = $del_slice[$i];
      my $col = $cols[$ord];
      my $quo = $q->quote($col);
      if ( $tbl->{is_nullable}->{$col} ) {
         push @clauses, "((? IS NULL AND $quo IS NULL) OR ($quo = ?))";
         push @{$del_stmt->{slice}}, $ord, $ord;
         push @{$del_stmt->{scols}}, $col, $col;
      }
      else {
         push @clauses, "$quo = ?";
         push @{$del_stmt->{slice}}, $ord;
         push @{$del_stmt->{scols}}, $col;
      }
   }

   $del_stmt->{where} = '(' . join(' AND ', @clauses) . ')';

   return $del_stmt;
}

# Design an INSERT statement.  This actually does very little; it just maps
# the columns you know you'll get from the SELECT statement onto the columns
# in the INSERT statement, returning only those that exist in both sets.
# Arguments:
#    ins_tbl   hashref returned by TableParser::parse() for the INSERT table
#    sel_cols  arrayref of columns to SELECT from the SELECT table
# Returns a hashref:
#    cols  => arrayref of columns for INSERT
#    slice => arrayref of sel_cols indices corresponding to the INSERT cols
# The cols array is used to construct the INSERT's INTO clause like:
#    INSERT INTO ins_tbl (@cols) VALUES ...
# The slice array is used like:
#    $row = $sel_sth->fetchrow_arrayref();
#    $ins_sth->execute(@{$row}[@slice]);
# For example, if we select columns (a, b, c) but the insert table only
# has columns (a, c), then the return hashref will be:
#    cols  => [a, c]
#    slice => [0, 2]
# Therefore, the select statement will return an array with 3 elements
# (one for each column), but the insert statement will slice this array
# to get only the elements/columns it needs.
sub generate_ins_stmt {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(ins_tbl sel_cols) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $ins_tbl  = $args{ins_tbl};
   my @sel_cols = @{$args{sel_cols}};

   die "You didn't specify any SELECT columns" unless @sel_cols;

   my @ins_cols;
   my @ins_slice;
   for my $i ( 0..$#sel_cols ) {
      next unless $ins_tbl->{is_col}->{$sel_cols[$i]};
      push @ins_cols, $sel_cols[$i];
      push @ins_slice, $i;
   }

   return {
      cols  => \@ins_cols,
      slice => \@ins_slice,
   };
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
# End TableNibbler package
# ###########################################################################
