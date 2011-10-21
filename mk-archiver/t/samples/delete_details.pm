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

package delete_details;

# This mk-archiver plugin demonstrates how to archive/DELETE associated
# rows in another table.  The main table (the one being archived) has
# certain columns which match rows in the associated table.  For example,
# if the main table is `log`, it may have 5 columns called `entry_N` that
# match to rows in associated table `entries`, column `id`.  So if this
# `log` row is archived:
#        log.id: 1
#   log.entry_1: 10
#   log.entry_2: 20
#   log.entry_3: 30
# Then rows in `entries` where `entries`.`id` in (10,20,30) are also deleted.
#
# Limitations:
#   * Does not work with --bulk-delete
#   * All tables must be on the same server
#   * No NULL values

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant MKDEBUG  => $ENV{MKDEBUG};

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

# ###########################################################################
# Customize these values for your tables.  Do not quote with backticks (`).
# ###########################################################################
my @main_tbl_cols = qw(
   in_id
   request_id
   response_id
   out_id
   comment_id
);
my $other_db  = undef;  # undef=same as main table db
my $other_tbl = 'details';
my $other_col = 'id';

# ###########################################################################
# Do not modify anything below here.
# ###########################################################################
sub new {
   my ( $class, %args ) = @_;
   my $o  = $args{OptionParser};
   my $q  = $args{Quoter};
   my $dp = $args{DSNParser};
   my $tp = $args{TableParser};
   
   $other_col = $q->quote($other_col);

   my $del_sql
      = "DELETE FROM " . $q->quote(($other_db || $args{db}), $other_tbl)
      . " WHERE " . join(' OR ', map {"$other_col=?"} (0..$#main_tbl_cols));
   MKDEBUG && _d($del_sql);
   my $del_sth = $args{dbh}->prepare($del_sql);

   my $before_delete;
   if ( my $dest_dsn = $o->get('dest') ) {
      $other_db ||= $dest_dsn->{D};

      my $dest_dbh = $dp->get_dbh(
         $dp->get_cxn_params($dest_dsn), { AutoCommit => 1 });

      my $sql        = "SHOW CREATE TABLE " . $q->quote($other_db, $other_tbl);
      my $row        = $args{dbh}->selectrow_arrayref($sql);
      my $tbl_struct = $tp->parse($row->[1]);
      my $cols       = $tbl_struct->{cols};

      my $sel_sql
         = "SELECT " . join(', ', map { $q->quote($_) } @$cols)
         . " FROM " . $q->quote($args{db}, $other_tbl)
         . " WHERE " . join(' OR ', map {"$other_col=?"} (0..$#main_tbl_cols));
      MKDEBUG && _d($sel_sql);
      my $sel_sth = $args{dbh}->prepare($sel_sql);

      my $ins_sql
         = "INSERT INTO " . $q->quote($other_db, $other_tbl)
         . ' (' . join(', ', map { $q->quote($_) } @$cols) . ')'
         . ' VALUES ('. join(', ', map { '?' } @$cols) . ')';
      MKDEBUG && _d($ins_sql);
      my $ins_sth = $dest_dbh->prepare($ins_sql);

      $before_delete = sub {
         my ( %args ) = @_;
         my $other_row_ids = $args{other_row_ids};

         MKDEBUG && _d($sel_sth->{Statement}, 'params:', @$other_row_ids);
         $sel_sth->execute(@$other_row_ids);

         while ( my $other_row = $sel_sth->fetchrow_arrayref() ) {
            MKDEBUG && _d($ins_sth->{Statement}, 'params:', @$other_row);
            $ins_sth->execute(@$other_row);
         }

         MKDEBUG && _d($del_sth->{Statement}, 'params:', @$other_row_ids);
         $del_sth->execute(@$other_row_ids);

         return;
      };
   }
   else {
      $before_delete = sub {
         my ( %args ) = @_;
         my $other_row_ids = $args{other_row_ids};
         MKDEBUG && _d($del_sth->{Statement}, 'params:', @$other_row_ids);
         $del_sth->execute(@$other_row_ids);
         return;
      };
   }

   my $self = {
      col_pos       => undef,
      before_delete => $before_delete,
   };

   if ( $o->get('dry-run') ) {
      print "# delete_details plugin:\n"
          . "#   other table $other_tbl\n"
          . "#   main table columns: " . join(', ', @main_tbl_cols) . "\n"
          . "#   " . ($o->get('dest') ? 'archive' : 'delete') .  " rows\n";
   }

   return bless $self, $class;
}

sub before_begin {
   my ( $self, %args ) = @_;
   my $allcols = $args{allcols};
   MKDEBUG && _d('allcols:', Dumper($allcols));

   # (These loops aren't ideal but it doesn't matter because the list
   # of cols will be very short.)
   my %col_pos;
   MAIN_TBL_COL:
   foreach my $main_tbl_col ( @main_tbl_cols ) {
      my $col_pos = 0;
      foreach my $selected_col ( @$allcols ) {
         if ($selected_col eq $main_tbl_col) {
            $col_pos{$main_tbl_col} = $col_pos;
            next MAIN_TBL_COL;
         }
         $col_pos++;
      }
      die "Main table column $main_tbl_col not selected by mk-archiver: "
         . join(', ', @$allcols) . "\n"
         . "delete_details plugin configured to use main table columns: "
         . join(', ', @main_tbl_cols);
   }

   MKDEBUG && _d("Main tbl col pos in selected rows:\n",
      join("\n", map {
                    my $col = $main_tbl_cols[$_];
                    "$col=$col_pos{$col}";
                 } (0..$#main_tbl_cols)));
   $self->{col_pos} = [ values %col_pos ];

   return;
}

sub is_archivable {
   my ( $self, %args ) = @_;
   return 1;
}

sub before_delete {
   my ( $self, %args ) = @_;
   my $row           = $args{row};
   my @other_row_ids = map { $row->[$_] } @{$self->{col_pos}};
   return $self->{before_delete}->(
      %args,
      other_row_ids => \@other_row_ids,
   );
}

sub before_bulk_delete {
   my ( $self, %args ) = @_;
   return;
}

sub after_finish {
   my ( $self ) = @_;
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
