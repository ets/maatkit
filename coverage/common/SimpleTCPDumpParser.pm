---------------------------- ------ ------ ------ ------ ------ ------ ------
File                           stmt   bran   cond    sub    pod   time  total
---------------------------- ------ ------ ------ ------ ------ ------ ------
...on/SimpleTCPDumpParser.pm  100.0   71.4   57.1  100.0    0.0   70.2   89.2
SimpleTCPDumpParser.t         100.0   50.0   33.3  100.0    n/a   29.8   93.6
Total                         100.0   68.8   50.0  100.0    0.0  100.0   90.7
---------------------------- ------ ------ ------ ------ ------ ------ ------


Run:          -e
Perl version: 118.53.46.49.48.46.48
OS:           linux
Start:        Thu May  5 16:41:35 2011
Finish:       Thu May  5 16:41:35 2011

Run:          SimpleTCPDumpParser.t
Perl version: 118.53.46.49.48.46.48
OS:           linux
Start:        Thu May  5 16:41:36 2011
Finish:       Thu May  5 16:41:37 2011

/home/daniel/dev/maatkit/trunk/common/SimpleTCPDumpParser.pm

line  err   stmt   bran   cond    sub    pod   time   code
1                                                     # This program is copyright 2011 Baron Schwartz.
2                                                     # Feedback and improvements are welcome.
3                                                     #
4                                                     # THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
5                                                     # WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
6                                                     # MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
7                                                     #
8                                                     # This program is free software; you can redistribute it and/or modify it under
9                                                     # the terms of the GNU General Public License as published by the Free Software
10                                                    # Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
11                                                    # systems, you can issue `man perlgpl' or `man perlartistic' to read these
12                                                    # licenses.
13                                                    #
14                                                    # You should have received a copy of the GNU General Public License along with
15                                                    # this program; if not, write to the Free Software Foundation, Inc., 59 Temple
16                                                    # Place, Suite 330, Boston, MA  02111-1307  USA.
17                                                    # ###########################################################################
18                                                    # SimpleTCPDumpParser package $Revision: 7472 $
19                                                    # ###########################################################################
20                                                    package SimpleTCPDumpParser;
21                                                    
22             1                    1             5   use strict;
               1                                  2   
               1                                  7   
23             1                    1             5   use warnings FATAL => 'all';
               1                                  3   
               1                                  5   
24             1                    1             6   use English qw(-no_match_vars);
               1                                  2   
               1                                  7   
25             1                    1            11   use Time::Local qw(timelocal);
               1                                  4   
               1                                  8   
26             1                    1             7   use Data::Dumper;
               1                                  2   
               1                                  6   
27                                                    
28    ***      1            50      1             6   use constant MKDEBUG => $ENV{MKDEBUG} || 0;
               1                                  8   
               1                                 12   
29                                                    
30                                                    # Required arguments: watch
31                                                    sub new {
32    ***      1                    1      0      8      my ( $class, %args ) = @_;
33             1                                  8      my ($ip, $port) = split(/:/, $args{watch});
34    ***      1            50                   10      my $self = {
35                                                          sessions => {},
36                                                          requests => 0,
37                                                          port     => $port || 3306,
38                                                       };
39             1                                 13      return bless $self, $class;
40                                                    }
41                                                    
42                                                    # This method accepts an open filehandle and callback functions.  It reads
43                                                    # events from the filehandle and calls the callbacks with each event.  $misc is
44                                                    # some placeholder for the future and for compatibility with other query
45                                                    # sources.
46                                                    #
47                                                    # The input is TCP requests and responses, such as the following:
48                                                    #
49                                                    # 2011-04-04 18:57:43.804195 IP 10.10.18.253.58297 > 10.10.18.40.3306: tcp 132
50                                                    # 2011-04-04 18:57:43.804465 IP 10.10.18.40.3306 > 10.10.18.253.58297: tcp 2920
51                                                    #
52                                                    # Each event is a hashref of attribute => value pairs such as the following:
53                                                    #
54                                                    #  my $event = {
55                                                    #     id   => '0',                  # Sequentially assigned ID, in arrival order
56                                                    #     ts   => '1301957863.804195',  # Start timestamp
57                                                    #     end  => '1301957863.804465',  # End timestamp
58                                                    #     arg  => undef,                # For compatibility with other modules
59                                                    #     host => '10.10.18.253',       # Host IP address where the event came from
60                                                    #     port => '58297',              # TCP port where the event came from
61                                                    #     ...                           # Other attributes
62                                                    #  };
63                                                    sub parse_event {
64    ***      4                    4      0    189      my ( $self, %args ) = @_;
65             4                                 17      my @required_args = qw(next_event tell);
66             4                                 17      foreach my $arg ( @required_args ) {
67    ***      8     50                          37         die "I need a $arg argument" unless $args{$arg};
68                                                       }
69             4                                 17      my ($next_event, $tell) = @args{@required_args};
70                                                    
71             4                                 12      my $sessions   = $self->{sessions};
72             4                                 15      my $pos_in_log = $tell->();
73             4                                 34      my $line;
74                                                    
75                                                       EVENT:
76             4                                 13      while ( defined($line = $next_event->()) ) {
77                                                          # Split the line into timestamp, source, and destination
78             8                                151         my ( $ts, $us, $src, $dst )
79                                                             = $line =~ m/([0-9-]{10} [0-9:]{8})(\.\d{6}) IP (\S+) > (\S+):/;
80    ***      8     50                          34         next unless $ts;
81             8                                 26         my $unix_timestamp = make_ts($ts) . $us;
82                                                    
83                                                          # If it's an inbound packet, we record this as the beginning of a request.
84             8    100                          78         if ( $dst =~ m/\.$self->{port}$/o ) {
                    100                               
85             3                                 22            $sessions->{$src} = {
86                                                                pos_in_log => $pos_in_log,
87                                                                ts         => $unix_timestamp,
88                                                                id         => $self->{requests}++,
89                                                             };
90                                                          }
91                                                    
92                                                          # If it's a reply to an inbound request, then we emit an event
93                                                          # representing the entire request, and forget that we saw the request.
94                                                          elsif (defined (my $event = $sessions->{$dst}) ) {
95             3                                 20            my ( $src_host, $src_port ) = $dst =~ m/^(.*)\.(\d+)$/;
96             3                                 12            $event->{end}  = $unix_timestamp;
97             3                                 10            $event->{host} = $src_host;
98             3                                  9            $event->{port} = $src_port;
99             3                                  9            $event->{arg}  = undef;
100            3                                  7            MKDEBUG && _d('Properties of event:', Dumper($event));
101            3                                 10            delete $sessions->{$dst};
102            3                                 23            return $event;
103                                                         }
104            5                                 19         $pos_in_log = $tell->();
105                                                      } # EVENT
106                                                   
107   ***      1     50                         220      $args{oktorun}->(0) if $args{oktorun};
108            1                                  8      return;
109                                                   }
110                                                   
111                                                   # Function to memo-ize and cache repeated calls to timelocal.  Accepts a string,
112                                                   # outputs an integer.
113                                                   {
114                                                      my ($last, $result);
115                                                      # $time = timelocal($sec,$min,$hour,$mday,$mon,$year);
116                                                      sub make_ts {
117   ***      8                    8      0     28         my ($arg) = @_;
118   ***      8    100     66                   67         if ( !$last || $last ne $arg ) {
119            1                                 12            my ($year, $mon, $mday, $hour, $min, $sec) = split(/\D/, $arg);
120            1                                 11            $result = timelocal($sec, $min, $hour, $mday, $mon - 1, $year);
121            1                                213            $last   = $arg;
122                                                         }
123            8                                 33         return $result;
124                                                      }
125                                                   }
126                                                   
127                                                   sub _d {
128            1                    1             7      my ($package, undef, $line) = caller 0;
129   ***      2     50                          11      @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
               2                                  8   
               2                                 10   
130            1                                  5           map { defined $_ ? $_ : 'undef' }
131                                                           @_;
132            1                                  3      print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
133                                                   }
134                                                   
135                                                   1;
136                                                   
137                                                   # ###########################################################################
138                                                   # End SimpleTCPDumpParser package
139                                                   # ###########################################################################


Branches
--------

line  err      %   true  false   branch
----- --- ------ ------ ------   ------
67    ***     50      0      8   unless $args{$arg}
80    ***     50      0      8   unless $ts
84           100      3      5   if ($dst =~ /\.$$self{'port'}$/o) { }
             100      3      2   elsif (defined(my $event = $$sessions{$dst})) { }
107   ***     50      0      1   if $args{'oktorun'}
118          100      1      7   if (not $last or $last ne $arg)
129   ***     50      2      0   defined $_ ? :


Conditions
----------

or 2 conditions

line  err      %      l     !l   expr
----- --- ------ ------ ------   ----
28    ***     50      0      1   $ENV{'MKDEBUG'} || 0
34    ***     50      1      0   $port || 3306

or 3 conditions

line  err      %      l  !l&&r !l&&!r   expr
----- --- ------ ------ ------ ------   ----
118   ***     66      1      0      7   not $last or $last ne $arg


Covered Subroutines
-------------------

Subroutine  Count Pod Location                                                        
----------- ----- --- ----------------------------------------------------------------
BEGIN           1     /home/daniel/dev/maatkit/trunk/common/SimpleTCPDumpParser.pm:22 
BEGIN           1     /home/daniel/dev/maatkit/trunk/common/SimpleTCPDumpParser.pm:23 
BEGIN           1     /home/daniel/dev/maatkit/trunk/common/SimpleTCPDumpParser.pm:24 
BEGIN           1     /home/daniel/dev/maatkit/trunk/common/SimpleTCPDumpParser.pm:25 
BEGIN           1     /home/daniel/dev/maatkit/trunk/common/SimpleTCPDumpParser.pm:26 
BEGIN           1     /home/daniel/dev/maatkit/trunk/common/SimpleTCPDumpParser.pm:28 
_d              1     /home/daniel/dev/maatkit/trunk/common/SimpleTCPDumpParser.pm:128
make_ts         8   0 /home/daniel/dev/maatkit/trunk/common/SimpleTCPDumpParser.pm:117
new             1   0 /home/daniel/dev/maatkit/trunk/common/SimpleTCPDumpParser.pm:32 
parse_event     4   0 /home/daniel/dev/maatkit/trunk/common/SimpleTCPDumpParser.pm:64 


SimpleTCPDumpParser.t

line  err   stmt   bran   cond    sub    pod   time   code
1                                                     #!/usr/bin/perl
2                                                     
3                                                     BEGIN {
4     ***      1     50     33      1            31      die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
5                                                           unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
6              1                                  7      unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
7                                                     
8                                                        # The timestamps for unix_timestamp are East Coast (EST), so GMT-4.
9              1                                 14      $ENV{TZ}='EST5EDT';
10                                                    };
11                                                    
12             1                    1            12   use strict;
               1                                  2   
               1                                  5   
13             1                    1             6   use warnings FATAL => 'all';
               1                                  2   
               1                                  5   
14             1                    1            12   use English qw(-no_match_vars);
               1                                  2   
               1                                  6   
15             1                    1            10   use Test::More tests => 3;
               1                                  3   
               1                                  9   
16                                                    
17             1                    1            11   use SimpleTCPDumpParser;
               1                                  3   
               1                                 18   
18             1                    1            11   use MaatkitTest;
               1                                  7   
               1                                 66   
19                                                    
20             1                                  5   my $in = "common/t/samples/simple-tcpdump/"; 
21                                                    
22             1                                  9   my $p = new SimpleTCPDumpParser(watch => ':3306');
23                                                    
24                                                    # Check that I can parse a log in the default format.
25             1                                 28   test_log_parser(
26                                                       parser => $p,
27                                                       file   => "$in/simpletcp001.txt",
28                                                       result => [
29                                                          {  ts         => '1301957863.804195',
30                                                             id         => 0,
31                                                             end        => '1301957863.804465',
32                                                             arg        => undef,
33                                                             host       => '10.10.18.253',
34                                                             port       => '58297',
35                                                             pos_in_log => 0,
36                                                          },
37                                                          {  ts         => '1301957863.805801',
38                                                             id         => 2,
39                                                             end        => '1301957863.806003',
40                                                             arg        => undef,
41                                                             host       => '10.10.18.253',
42                                                             port       => 52726,
43                                                             pos_in_log => 308,
44                                                          },
45                                                          {  ts         => '1301957863.805481',
46                                                             id         => 1,
47                                                             end        => '1301957863.806026',
48                                                             arg        => undef,
49                                                             host       => '10.10.18.253',
50                                                             port       => 40135,
51                                                             pos_in_log => 231,
52                                                          },
53                                                       ],
54                                                    );
55                                                    
56                                                    # #############################################################################
57                                                    # Done.
58                                                    # #############################################################################
59             1                                 29   my $output = '';
60                                                    {
61             1                                  3      local *STDERR;
               1                                  5   
62             1                    1             2      open STDERR, '>', \$output;
               1                                292   
               1                                  2   
               1                                  6   
63             1                                 18      $p->_d('Complete test coverage');
64                                                    }
65                                                    like(
66             1                                 19      $output,
67                                                       qr/Complete test coverage/,
68                                                       '_d() works'
69                                                    );
70             1                                  3   exit;


Branches
--------

line  err      %   true  false   branch
----- --- ------ ------ ------   ------
4     ***     50      0      1   unless $ENV{'MAATKIT_WORKING_COPY'} and -d $ENV{'MAATKIT_WORKING_COPY'}


Conditions
----------

and 3 conditions

line  err      %     !l  l&&!r   l&&r   expr
----- --- ------ ------ ------ ------   ----
4     ***     33      0      0      1   $ENV{'MAATKIT_WORKING_COPY'} and -d $ENV{'MAATKIT_WORKING_COPY'}


Covered Subroutines
-------------------

Subroutine Count Location                
---------- ----- ------------------------
BEGIN          1 SimpleTCPDumpParser.t:12
BEGIN          1 SimpleTCPDumpParser.t:13
BEGIN          1 SimpleTCPDumpParser.t:14
BEGIN          1 SimpleTCPDumpParser.t:15
BEGIN          1 SimpleTCPDumpParser.t:17
BEGIN          1 SimpleTCPDumpParser.t:18
BEGIN          1 SimpleTCPDumpParser.t:4 
BEGIN          1 SimpleTCPDumpParser.t:62


