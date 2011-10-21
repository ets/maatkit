---------------------------- ------ ------ ------ ------ ------ ------ ------
File                           stmt   bran   cond    sub    pod   time  total
---------------------------- ------ ------ ------ ------ ------ ------ ------
...n/TCPRequestAggregator.pm   96.5   73.7   86.4  100.0    0.0   94.7   90.2
TCPRequestAggregator.t        100.0   50.0   33.3  100.0    n/a    5.3   93.9
Total                          97.2   72.5   80.0  100.0    0.0  100.0   90.9
---------------------------- ------ ------ ------ ------ ------ ------ ------


Run:          -e
Perl version: 118.53.46.49.48.46.48
OS:           linux
Start:        Thu May  5 16:41:46 2011
Finish:       Thu May  5 16:41:46 2011

Run:          TCPRequestAggregator.t
Perl version: 118.53.46.49.48.46.48
OS:           linux
Start:        Thu May  5 16:41:48 2011
Finish:       Thu May  5 16:41:48 2011

/home/daniel/dev/maatkit/trunk/common/TCPRequestAggregator.pm

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
18                                                    # TCPRequestAggregator package $Revision: 7473 $
19                                                    # ###########################################################################
20                                                    package TCPRequestAggregator;
21                                                    
22             1                    1             5   use strict;
               1                                  2   
               1                                  8   
23             1                    1             6   use warnings FATAL => 'all';
               1                                  2   
               1                                  5   
24             1                    1             5   use English qw(-no_match_vars);
               1                                  3   
               1                                  6   
25             1                    1             6   use List::Util qw(sum);
               1                                  3   
               1                                 10   
26             1                    1             6   use Data::Dumper;
               1                                  3   
               1                                  7   
27                                                    
28    ***      1            50      1             6   use constant MKDEBUG => $ENV{MKDEBUG} || 0;
               1                                  2   
               1                                 19   
29                                                    
30                                                    # Required arguments: interval, quantile
31                                                    sub new {
32    ***      2                    2      0     15      my ( $class, %args ) = @_;
33             2                                 10      my @required_args = qw(interval quantile);
34             2                                  8      foreach my $arg ( @required_args ) {
35    ***      4     50                          21         die "I need a $arg argument" unless $args{$arg};
36                                                       }
37             2                                 19      my $self = {
38                                                          buffer             => [],
39                                                          last_weighted_time => 0,
40                                                          last_res_time      => 0,
41                                                          last_completions   => 0,
42                                                          current_ts         => 0,
43                                                          %args,
44                                                       };
45             2                                 21      return bless $self, $class;
46                                                    }
47                                                    
48                                                    # This method accepts an open filehandle and callback functions.  It reads
49                                                    # events from the filehandle and calls the callbacks with each event.  $misc is
50                                                    # some placeholder for the future and for compatibility with other query
51                                                    # sources.
52                                                    #
53                                                    # The input is the output of mk-tcp-model, like so:
54                                                    #
55                                                    #   21 1301957863.820001 1301957863.820169  0.000168 10.10.18.253:58297
56                                                    #   22 1301957863.821677 1301957863.821839  0.000162 10.10.18.253:43608
57                                                    #   23 1301957863.822890 1301957863.823074  0.000184 10.10.18.253:52726
58                                                    #   24 1301957863.822895 1301957863.823160  0.000265 10.10.18.253:58297
59                                                    #
60                                                    # Each event is a hashref of attribute => value pairs as defined in
61                                                    # mk-tcp-model's documentation.
62                                                    sub parse_event {
63    ***      6                    6      0    320      my ( $self, %args ) = @_;
64             6                                 27      my @required_args = qw(next_event tell);
65             6                                 20      foreach my $arg ( @required_args ) {
66    ***     12     50                          58         die "I need a $arg argument" unless $args{$arg};
67                                                       }
68             6                                 26      my ($next_event, $tell) = @args{@required_args};
69                                                    
70             6                                 25      my $pos_in_log = $tell->();
71             6                                 54      my $buffer = $self->{buffer};
72             6           100                   27      $self->{last_pos_in_log} ||= $pos_in_log;
73                                                    
74                                                       EVENT:
75             6                                 17      while ( 1 ) {
76           108                                719         MKDEBUG && _d("Beginning a loop at pos", $pos_in_log);
77           108                                296         my ( $id, $start, $elapsed );
78                                                    
79           108                                266         my ($timestamp, $direction);
80           108    100                         470         if ( $self->{pending} ) {
                    100                               
81            48                                110            ( $id, $start, $elapsed ) = @{$self->{pending}};
              48                                231   
82            48                                123            MKDEBUG && _d("Pulled from pending", @{$self->{pending}});
83                                                          }
84                                                          elsif ( defined(my $line = $next_event->()) ) {
85                                                             # Split the line into ID, start, end, elapsed, and host:port
86            51                                830            my ($end, $host_port);
87            51                                463            ( $id, $start, $end, $elapsed, $host_port ) = $line =~ m/(\S+)/g;
88            51                                 99            @$buffer = sort { $a <=> $b } ( @$buffer, $end );
              76                                223   
89            51                                242            MKDEBUG && _d("Read from the file", $id, $start, $end, $elapsed, $host_port);
90            51                                129            MKDEBUG && _d("Buffer is now", @$buffer);
91                                                          }
92           108    100                         477         if ( $start ) { # Test that we got a line; $id can be 0.
                    100                               
93                                                             # We have a line to work on.  The next event we need to process is the
94                                                             # smaller of a) the arrival recorded in the $start of the line we just
95                                                             # read, or b) the first completion recorded in the completions buffer.
96    ***     99    100     66                  799            if ( @$buffer && $buffer->[0] < $start ) {
97            48                                125               $direction       = 'C'; # Completion
98            48                                148               $timestamp       = shift @$buffer;
99            48                                217               $self->{pending} = [ $id, $start, $elapsed ];
100           48                                157               $id = $start = $elapsed = undef;
101           48                                106               MKDEBUG && _d("Completion: using buffered end value", $timestamp);
102           48                                115               MKDEBUG && _d("Saving line to pending", @{$self->{pending}});
103                                                            }
104                                                            else {
105           51                                135               $direction       = 'A'; # Arrival
106           51                                131               $timestamp       = $start;
107           51                                157               $self->{pending} = undef;
108           51                                122               MKDEBUG && _d("Deleting pending line");
109           51                                121               MKDEBUG && _d("Arrival: using the line");
110                                                            }
111                                                         }
112                                                         elsif ( @$buffer ) {
113            5                                 14            $direction = 'C';
114            5                                 18            $timestamp = shift @$buffer;
115            5                                 10            MKDEBUG && _d("No more lines, reading from buffer", $timestamp);
116                                                         }
117                                                         else { # We hit EOF.
118            4                                 10            MKDEBUG && _d("No more lines, no more buffered end times");
119   ***      4     50                          17            if ( $self->{in_prg} ) {
120   ***      0                                  0               die "Error: no more lines, but in_prg = $self->{in_prg}";
121                                                            }
122            4    100                          18            if ( $self->{t_start} < $self->{current_ts} ) {
123            2                                  6               MKDEBUG && _d("Returning event based on what's been seen");
124            2                                 10               return $self->make_event($self->{t_start}, $self->{current_ts});
125                                                            }
126                                                            else {
127            2                                  4               MKDEBUG && _d("No further events to make");
128            2                                 14               return;
129                                                            }
130                                                         }
131                                                   
132                                                         # The notation used here is T_start for start of observation time (T).
133                                                         # The divide, int(), and multiply effectively truncates the value to
134                                                         # $interval precision.
135          104                                480         my $t_start = int($timestamp / $self->{interval}) * $self->{interval};
136          104           100                  399         $self->{t_start} ||= $timestamp; # Not $t_start; that'd skew 1st interval.
137          104                                258         MKDEBUG && _d("Timestamp", $timestamp, "interval start time", $t_start);
138                                                   
139                                                         # If $timestamp is not within the current interval, then we need to save
140                                                         # everything for later, compute stats for the rest of this interval, and
141                                                         # return an event.  The next time we are called, we'll begin the next
142                                                         # interval.  
143          104    100                         380         if ( $t_start > $self->{t_start} ) {
144            2                                  4            MKDEBUG && _d("Timestamp doesn't belong to this interval");
145                                                            # We need to compute how much time is left in this interval, and add
146                                                            # that much res_time  and weighted_time to the running totals, but only
147                                                            # if there is some request in progress.
148   ***      2     50                           9            if ( $self->{in_prg} ) {
149            2                                  5               MKDEBUG && _d("Computing from", $self->{current_ts}, "to", $t_start);
150            2                                  9               $self->{res_time}      += $t_start - $self->{current_ts};
151            2                                  9               $self->{weighted_time} += ($t_start - $self->{current_ts}) * $self->{in_prg};
152                                                            }
153                                                   
154   ***      2     50     66                   19            if ( @$buffer && $buffer->[0] < $t_start ) {
155   ***      0                                  0               die "Error: completions for interval remain unprocessed";
156                                                            }
157                                                   
158                                                            # Reset running totals and last-time-seen stuff for next iteration,
159                                                            # re-buffer the completion or replace the line onto pending, then
160                                                            # return the event.
161            2                                 14            my $event                = $self->make_event($self->{t_start}, $t_start);
162            2                                  7            $self->{last_pos_in_log} = $pos_in_log;
163   ***      2     50                           7            if ( $start ) {
164   ***      0                                  0               $self->{pending} = [ $id, $start, $elapsed ];
165                                                            }
166                                                            else {
167            2                                  8               unshift @$buffer, $timestamp;
168                                                            }
169            2                                 16            return $event;
170                                                         }
171                                                   
172                                                         # Otherwise, we need to compute the running sums and keep looping.
173                                                         else {
174          102    100                         390            if ( $self->{in_prg} ) {
175                                                               # $self->{current_ts} is intitially 0, which would seem likely to
176                                                               # skew this computation.  But $self->{in_prg} will be 0 also, and
177                                                               # $self->{current_ts} will get set immediately after this, so
178                                                               # anytime this if() block runs, it'll be OK.
179           66                                134               MKDEBUG && _d("Computing from", $self->{current_ts}, "to", $timestamp);
180           66                                262               $self->{res_time}      += $timestamp - $self->{current_ts};
181           66                                302               $self->{weighted_time} += ($timestamp - $self->{current_ts}) * $self->{in_prg};
182                                                            }
183          102                                321            $self->{current_ts} = $timestamp;
184          102    100                         370            if ( $direction eq 'A' ) {
185           51                                112               MKDEBUG && _d("Direction A", $timestamp);
186           51                                143               ++$self->{in_prg};
187   ***     51     50                         188               if ( defined $elapsed ) {
188           51                                123                  push @{$self->{response_times}}, $elapsed;
              51                                221   
189                                                               }
190                                                            }
191                                                            else {
192           51                                111               MKDEBUG && _d("Direction C", $timestamp);
193           51                                144               --$self->{in_prg};
194           51                                156               ++$self->{completions};
195                                                            }
196                                                         }
197                                                   
198          102                                429         $pos_in_log = $tell->();
199                                                      } # EVENT
200                                                   
201   ***      0      0                           0      $args{oktorun}->(0) if $args{oktorun};
202   ***      0                                  0      return;
203                                                   }
204                                                   
205                                                   # Makes an event and returns it.  Arguments:
206                                                   #  $t_start -- the start of the observation period for this event.
207                                                   #  $t_end   -- the end of the observation period for this event.
208                                                   sub make_event {
209   ***      4                    4      0     19      my ( $self, $t_start, $t_end ) = @_;
210                                                   
211                                                      # Prep a couple of things...
212            4                                 27      my $quantile_cutoff = sprintf( "%.0f", # Round to nearest int
213            4                                 12         scalar( @{ $self->{response_times} } ) * $self->{quantile} );
214            4                                 11      my @times = sort { $a <=> $b } @{ $self->{response_times} };
             143                                357   
               4                                 11   
215            4                                 40      my $arrivals = scalar(@times);
216            4                                 27      my $sum_times = sum( @times );
217            4           100                   34      my $mean_times = ($sum_times || 0) / ($arrivals || 1);
                           100                        
218            4                                 12      my $var_times = 0;
219            4    100                          20      if ( @times ) {
220            3                                  9         $var_times = sum( map { ($_ - $mean_times) **2 } @times ) / $arrivals;
              51                                172   
221                                                      }
222                                                   
223                                                      # Compute the parts of the event we'll return.
224            4                                 24      my $e_ts
225                                                         = int( $self->{current_ts} / $self->{interval} ) * $self->{interval};
226            4                                 58      my $e_concurrency = sprintf( "%.6f",
227                                                              ( $self->{weighted_time} - $self->{last_weighted_time} )
228                                                            / ( $t_end - $t_start ) );
229            4                                 12      my $e_arrivals   = $arrivals;
230            4                                 28      my $e_throughput = sprintf( "%.6f", $e_arrivals / ( $t_end - $t_start ) );
231            4                                 18      my $e_completions
232                                                         = ( $self->{completions} - $self->{last_completions} );
233            4                                 28      my $e_res_time
234                                                         = sprintf( "%.6f", $self->{res_time} - $self->{last_res_time} );
235            4                                 25      my $e_weighted_time = sprintf( "%.6f",
236                                                         $self->{weighted_time} - $self->{last_weighted_time} );
237            4           100                   32      my $e_sum_time = sprintf("%.6f", $sum_times || 0);
238            4           100                   29      my $e_variance_mean = sprintf("%.6f", $var_times / ($mean_times || 1));
239            4           100                   32      my $e_quantile_time = sprintf("%.6f", $times[ $quantile_cutoff - 1 ] || 0);
240                                                   
241                                                      # Construct the event
242            4                                 61      my $event = {
243                                                         ts            => $e_ts,
244                                                         concurrency   => $e_concurrency,
245                                                         throughput    => $e_throughput,
246                                                         arrivals      => $e_arrivals,
247                                                         completions   => $e_completions,
248                                                         res_time      => $e_res_time ,
249                                                         weighted_time => $e_weighted_time,
250                                                         sum_time      => $e_sum_time,
251                                                         variance_mean => $e_variance_mean,
252                                                         quantile_time => $e_quantile_time,
253                                                         pos_in_log    => $self->{last_pos_in_log},
254                                                         obs_time      => sprintf("%.6f", $t_end - $t_start),
255                                                      };
256                                                   
257            4                                 16      $self->{t_start}            = $t_end;  # Not current_timestamp!
258            4                                224      $self->{current_ts}         = $t_end;  # Next iteration will begin at boundary
259            4                                 14      $self->{last_weighted_time} = $self->{weighted_time};
260            4                                 17      $self->{last_res_time}      = $self->{res_time};
261            4                                 15      $self->{last_completions}   = $self->{completions};
262            4                                 15      $self->{response_times}     = [];
263                                                   
264            4                                 13      MKDEBUG && _d("Event is", Dumper($event));
265            4                                 29      return $event;
266                                                   }
267                                                   
268                                                   sub _d {
269            1                    1             7      my ($package, undef, $line) = caller 0;
270   ***      2     50                          11      @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
               2                                  9   
               2                                 11   
271            1                                  5           map { defined $_ ? $_ : 'undef' }
272                                                           @_;
273            1                                  2      print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
274                                                   }
275                                                   
276                                                   1;
277                                                   
278                                                   # ###########################################################################
279                                                   # End TCPRequestAggregator package
280                                                   # ###########################################################################


Branches
--------

line  err      %   true  false   branch
----- --- ------ ------ ------   ------
35    ***     50      0      4   unless $args{$arg}
66    ***     50      0     12   unless $args{$arg}
80           100     48     60   if ($$self{'pending'}) { }
             100     51      9   elsif (defined(my $line = &$next_event())) { }
92           100     99      9   if ($start) { }
             100      5      4   elsif (@$buffer) { }
96           100     48     51   if (@$buffer and $$buffer[0] < $start) { }
119   ***     50      0      4   if ($$self{'in_prg'})
122          100      2      2   if ($$self{'t_start'} < $$self{'current_ts'}) { }
143          100      2    102   if ($t_start > $$self{'t_start'}) { }
148   ***     50      2      0   if ($$self{'in_prg'})
154   ***     50      0      2   if (@$buffer and $$buffer[0] < $t_start)
163   ***     50      0      2   if ($start) { }
174          100     66     36   if ($$self{'in_prg'})
184          100     51     51   if ($direction eq 'A') { }
187   ***     50     51      0   if (defined $elapsed)
201   ***      0      0      0   if $args{'oktorun'}
219          100      3      1   if (@times)
270   ***     50      2      0   defined $_ ? :


Conditions
----------

and 3 conditions

line  err      %     !l  l&&!r   l&&r   expr
----- --- ------ ------ ------ ------   ----
96    ***     66      0     51     48   @$buffer and $$buffer[0] < $start
154   ***     66      1      1      0   @$buffer and $$buffer[0] < $t_start

or 2 conditions

line  err      %      l     !l   expr
----- --- ------ ------ ------   ----
28    ***     50      0      1   $ENV{'MKDEBUG'} || 0
72           100      3      3   $$self{'last_pos_in_log'} ||= $pos_in_log
136          100    102      2   $$self{'t_start'} ||= $timestamp
217          100      3      1   $sum_times || 0
             100      3      1   $arrivals || 1
237          100      3      1   $sum_times || 0
238          100      3      1   $mean_times || 1
239          100      3      1   $times[$quantile_cutoff - 1] || 0


Covered Subroutines
-------------------

Subroutine  Count Pod Location                                                         
----------- ----- --- -----------------------------------------------------------------
BEGIN           1     /home/daniel/dev/maatkit/trunk/common/TCPRequestAggregator.pm:22 
BEGIN           1     /home/daniel/dev/maatkit/trunk/common/TCPRequestAggregator.pm:23 
BEGIN           1     /home/daniel/dev/maatkit/trunk/common/TCPRequestAggregator.pm:24 
BEGIN           1     /home/daniel/dev/maatkit/trunk/common/TCPRequestAggregator.pm:25 
BEGIN           1     /home/daniel/dev/maatkit/trunk/common/TCPRequestAggregator.pm:26 
BEGIN           1     /home/daniel/dev/maatkit/trunk/common/TCPRequestAggregator.pm:28 
_d              1     /home/daniel/dev/maatkit/trunk/common/TCPRequestAggregator.pm:269
make_event      4   0 /home/daniel/dev/maatkit/trunk/common/TCPRequestAggregator.pm:209
new             2   0 /home/daniel/dev/maatkit/trunk/common/TCPRequestAggregator.pm:32 
parse_event     6   0 /home/daniel/dev/maatkit/trunk/common/TCPRequestAggregator.pm:63 


TCPRequestAggregator.t

line  err   stmt   bran   cond    sub    pod   time   code
1                                                     #!/usr/bin/perl
2                                                     
3                                                     BEGIN {
4     ***      1     50     33      1            32      die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
5                                                           unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
6              1                                  8      unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
7                                                     };
8                                                     
9              1                    1            12   use strict;
               1                                  2   
               1                                  6   
10             1                    1             6   use warnings FATAL => 'all';
               1                                  2   
               1                                  6   
11             1                    1            20   use English qw(-no_match_vars);
               1                                  2   
               1                                  9   
12             1                    1            10   use Test::More tests => 5;
               1                                  2   
               1                                 11   
13                                                    
14             1                    1            13   use TCPRequestAggregator;
               1                                  3   
               1                                 16   
15             1                    1            48   use MaatkitTest;
               1                                  3   
               1                                 40   
16                                                    
17             1                                  6   my $in = "common/t/samples/simple-tcprequests/";
18             1                                  3   my $p;
19                                                    
20                                                    # Check that I can parse a simple log and aggregate it into 100ths of a second
21             1                                 10   $p = new TCPRequestAggregator(interval => '.01', quantile => '.99');
22                                                    # intervals.
23             1                                 46   test_log_parser(
24                                                       parser => $p,
25                                                       file   => "$in/simpletcp-requests001.txt",
26                                                       result => [
27                                                          {  ts            => '1301957863.82',
28                                                             concurrency   => '0.346932',
29                                                             throughput    => '1800.173395',
30                                                             arrivals      => 18,
31                                                             completions   => 17,
32                                                             res_time      => '0.002861',
33                                                             weighted_time => '0.003469',
34                                                             sum_time      => '0.003492',
35                                                             variance_mean => '0.000022',
36                                                             quantile_time => '0.000321',
37                                                             obs_time      => '0.009999',
38                                                             pos_in_log    => 0,
39                                                          },
40                                                          {  ts            => '1301957863.83',
41                                                             concurrency   => '0.649048',
42                                                             throughput    => '1600.001526',
43                                                             arrivals      => 16,
44                                                             completions   => 16,
45                                                             res_time      => '0.004933',
46                                                             weighted_time => '0.006490',
47                                                             sum_time      => '0.011227',
48                                                             variance_mean => '0.004070',
49                                                             quantile_time => '0.007201',
50                                                             obs_time      => '0.010000',
51                                                             pos_in_log    => 1296,
52                                                          },
53                                                          {  ts            => '1301957863.84',
54                                                             concurrency   => '1.000000',
55                                                             throughput    => '0.000000',
56                                                             arrivals      => 0,
57                                                             completions   => 1,
58                                                             res_time      => '0.004759',
59                                                             weighted_time => '0.004759',
60                                                             sum_time      => '0.000000',
61                                                             variance_mean => '0.000000',
62                                                             quantile_time => '0.000000',
63                                                             obs_time      => '0.004759',
64                                                             pos_in_log    => '2448',
65                                                          },
66                                                       ],
67                                                    );
68                                                    
69                                                    # Check that I can parse a log whose first event is ID = 0, and whose events all
70                                                    # fit within one time interval.
71             1                                 40   $p = new TCPRequestAggregator(interval => '.01', quantile => '.99');
72             1                                 23   test_log_parser(
73                                                       parser => $p,
74                                                       file   => "$in/simpletcp-requests002.txt",
75                                                       result => [
76                                                          {  ts            => '1301957863.82',
77                                                             concurrency   => '0.353948',
78                                                             throughput    => '1789.648311',
79                                                             arrivals      => 17,
80                                                             completions   => 17,
81                                                             res_time      => '0.002754',
82                                                             weighted_time => '0.003362',
83                                                             variance_mean => '0.000022',
84                                                             sum_time      => '0.003362',
85                                                             quantile_time => '0.000321',
86                                                             obs_time      => '0.009499',
87                                                             pos_in_log    => 0,
88                                                          },
89                                                       ],
90                                                    );
91                                                    
92                                                    # #############################################################################
93                                                    # Done.
94                                                    # #############################################################################
95             1                                 40   my $output = '';
96                                                    {
97             1                                  3      local *STDERR;
               1                                  9   
98             1                    1             3      open STDERR, '>', \$output;
               1                                313   
               1                                  3   
               1                                  9   
99             1                                 18      $p->_d('Complete test coverage');
100                                                   }
101                                                   like(
102            1                                 21      $output,
103                                                      qr/Complete test coverage/,
104                                                      '_d() works'
105                                                   );
106            1                                  3   exit;


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
---------- ----- -------------------------
BEGIN          1 TCPRequestAggregator.t:10
BEGIN          1 TCPRequestAggregator.t:11
BEGIN          1 TCPRequestAggregator.t:12
BEGIN          1 TCPRequestAggregator.t:14
BEGIN          1 TCPRequestAggregator.t:15
BEGIN          1 TCPRequestAggregator.t:4 
BEGIN          1 TCPRequestAggregator.t:9 
BEGIN          1 TCPRequestAggregator.t:98


