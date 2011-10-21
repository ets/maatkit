# This program is copyright 2011 Daniel Nichter
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
# DrizzleQueryLogParser package $Revision: 7627 $
# ###########################################################################
package DrizzleQueryLogParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Data::Dumper;

# Values can be either "double quoted", which can contain spaces, or
# barewords without spaces (numbers, ts, and true|false).
my $val_pat = qr/(?>(?:"[^"]+"|\S+))/;

sub new {
   my ( $class ) = @_;
   my $self = {};
   return bless $self, $class;
}

sub parse_event {
   my ( $self, %args ) = @_;
   my @required_args = qw(next_event tell);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($next_event, $tell) = @args{@required_args};

   local $INPUT_RECORD_SEPARATOR = "\n#\n";
   my $pos_in_log = $tell->();
   my $stmt;

   EVENT:
   while ( defined($stmt = $next_event->()) ) {
      my @properties = ('cmd', 'Query', 'pos_in_log', $pos_in_log);
      $pos_in_log = $tell->();

      chomp $stmt;  # remove input record separator after query

      my @props;
      COMMENT_LINE:
      while ($stmt =~ m/^# /gcm) {
         ATTRIB_VALUE:
         while (my @prop = $stmt =~ m/\G([a-z_]+)=($val_pat)(?:\s|\Z)/gc) {
            # Convert some attributes and values to what mk-query-digest
            # expects.
            $prop[0] = $prop[0] eq 'start_ts'       ? 'ts'
                     : $prop[0] eq 'execution_time' ? 'Query_time'
                     : $prop[0];
            my $i = 1;
            while ($prop[$i]) {
               if ( $prop[$i] =~ m/^"/ ) { # double-quoted string values
                  $prop[$i] =~ s/^"//;
                  $prop[$i] =~ s/"$//;
               }
               elsif ( $prop[$i] eq 'true' || $prop[$i] eq 'false' ) { # bools
                  $prop[$i] = $prop[$i] eq 'true' ? 'Yes' : 'No';
               }
               $i += 2;  # values are every other array element
            }
            push @props, @prop;
         }
      }
      # Everything after the last comment line is the query.
      push @props, 'arg', substr($stmt, pos $stmt);

      # Don't dump $event; want to see full dump of all properties, and after
      # it's been cast into a hash, duplicated keys will be gone.
      MKDEBUG && _d('Properties of event:', Dumper(\@props));
      my $event = { @props };
      if ( $args{stats} ) {
         $args{stats}->{events_read}++;
         $args{stats}->{events_parsed}++;
      }
      return $event;
   } # EVENT

   $args{oktorun}->(0) if $args{oktorun};
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
# End DrizzleQueryLogParser package
# ###########################################################################
