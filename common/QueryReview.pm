# This program is copyright 2008-@CURRENTYEAR@ Percona Inc.
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
# QueryReview package $Revision$
# ###########################################################################
package QueryReview;

# qv is short for "query review" throughout this module.

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use Digest::MD5 qw(md5_hex);
use Data::Dumper;

use constant MKDEBUG => $ENV{MKDEBUG};

# Required args:
# key_attrib    See SQLMetrics::new().
# fingerprint   See SQLMetrics::new().
# dbh           A dbh to the server with the query review table.
# qv_tbl        Full db.tbl name of the query review table.
#               Make sure the table exists! It's not checked here;
#               check it before instantiating an object.
# tbl_struct    Return val from TableParser::parse() for qv_tbl.
#               This is used to discover what columns qv_tbl has.
#
# Optional args:
# preload       SQL clause to limit pre-loaded fingerprints that
#               comes after 'FROM qv_tbl' so it can be a WHERE clause
#               or just LIMIT.
sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(dbh qv_tbl tbl_struct key_attrib fingerprint) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   # Pre-load checksums from the query review table.
   my $sql = "SELECT fingerprint, CONV(checksum, 10, 16) "
           . "FROM $args{qv_tbl} "
           . ($args{preload} ? $args{preload} : '');
   my %checksums
      = map { $_->[0] => $_->[1] }
        @{ $args{dbh}->selectall_arrayref($sql) };

   my $store_new_sth = $args{dbh}->prepare(
         'INSERT IGNORE INTO ' . $args{qv_tbl}
         . '(checksum, fingerprint, sample, first_seen, last_seen) VALUES( '
         . 'CONV(?, 16, 10), ?, ?, COALESCE(?, NOW()), COALESCE(?, NOW()))');

   my $self = {
      dbh           => $args{dbh},
      qv_tbl        => $args{qv_tbl},
      checksums     => \%checksums,
      store_new_sth => $store_new_sth,
      key_attrib    => $args{key_attrib},
      fingerprint   => $args{fingerprint},
   };
   return bless $self, $class;
}

# Save or update the given event in the query review table (qv_tbl).
sub store_event {
   my ( $self, $event ) = @_;
   my $checksum;

   # Skip events which do not have the key_attrib attribute.
   my $key_attrib_val =  $event->{ $self->{key_attrib} };
   return unless defined $key_attrib_val;

   # Get the fingerprint for this event.
   my $fingerprint
      = $self->{fingerprint}->($key_attrib_val, $event, $self->{key_attrib});

   # Update the event if it's an old event (either in cache or
   # in the query review table). Else, add the new event to the
   # query review table.
   if ( exists $self->{checksums}->{$fingerprint} ) {
      # Cached event.
      $checksum = $self->{checksums}->{$fingerprint};
      $self->_update_event($checksum, $event);
   }
   else {
      $checksum = checksum_fingerprint($fingerprint);

      if ( $self->event_is_stored($checksum) ) {
         # Event not cached but stored in the qv_tbl.
         $self->_update_event($checksum, $event);
         $self->{checksums}->{$fingerprint} = $checksum;
      }
      else {
         # New event.
         # The primary key value (checksum column) is generated by checksumming
         # the query and then converting part of the checksum into a bigint.
         my $ts = _parse_timestamp($event->{ts});

         $self->{store_new_sth}->execute(
            $checksum,
            $fingerprint,
            $event->{arg},
            $ts,
            $ts);
         MKDEBUG && _d("Stored new event: $checksum $fingerprint $ts");

         # Cache the event's checksum.
         $self->{checksums}->{$fingerprint} = $checksum;
      }
   }

   $event->{checksum} = $checksum;

   return;
}

sub event_is_stored {
   my ( $self, $checksum ) = @_;
   my $event = $self->{dbh}->selectall_arrayref(
      "SELECT checksum FROM $self->{qv_tbl} "
      . "WHERE checksum=CONV('$checksum',16,10)");
   return scalar @$event ? 1 : 0;
}

sub _update_event {
   my ( $self, $checksum, $event ) = @_;
   return unless (defined $checksum && defined $event);
   my @sets;

   # Update event count.
   push @sets, 'cnt=cnt+1';

   # Update last_seen. We trust that timestamps are always increasing.
   my $ts = _parse_timestamp($event->{ts});
   push @sets, "last_seen='$ts'" if $ts;

   # TODO: update other columsn as need (i.e. optional metric columns)
   # TODO: need a way to update worst sample only if it changes

   my $set_clause = join(',', @sets);
   my $sql        = "UPDATE $self->{qv_tbl} "
                  . "SET    $set_clause "
                  . "WHERE  checksum=CONV('$checksum',16,10)";
   $self->{dbh}->do($sql);

   return;
}

# Returns the rightmost 64 bits of an MD5 checksum of the fingerprint.
sub checksum_fingerprint {
   my ( $fingerprint ) = @_;
   my $checksum = uc substr(md5_hex($fingerprint), -16);
   MKDEBUG && _d("$checksum checksum for $fingerprint");
   return $checksum;
}

# Turns 071015 21:43:52 into a proper datetime format.
# TODO: this should probably go in Transformers
sub _parse_timestamp {
   my ( $val ) = @_;
   return $val unless defined $val;
   $val =~ s/^(\d\d)(\d\d)(\d\d) /20$1-$2-$3 /;
   return $val;
}

sub _d {
   my ( $line ) = (caller(0))[2];
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; } @_;
   print "# QueryReview:$line $PID ", @_, "\n";
}

1;
# ###########################################################################
# End QueryReview package
# ###########################################################################
