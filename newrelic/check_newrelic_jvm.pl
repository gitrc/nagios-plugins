#!/usr/bin/perl -w
#
#
# Pull JVM level metrics from New Relic for proper alerting/monitoring/trending
#
# TODO: generate the appid/instanceid hashes on-the-fly using the REST API
#
# Rod Cordova (@gitrc)
#
# November 2012
#

use LWP::Simple;
use LWP::UserAgent;
use HTTP::Request::Common;
use HTTP::Cookies;
use MIME::Lite;
use Data::Dumper;
use List::Util qw(sum);
use Getopt::Long;
use JSON;
use strict;

use vars qw($opt_H $opt_w $opt_c $opt_m $opt_t);
use lib "/usr/local/nagios/libexec";
use utils qw($TIMEOUT %ERRORS &usage);

sub print_help ();
sub print_usage ();

if ( grep /--help/, @ARGV ) {
    print "usage: $0 -H <hostname> -w <warn> -c <crit> -m <metric> -t <timeout>\n";
    print "\n";
    print
"valid metrics are: gc_cpu background_task_cpu background_task_mem heap_max heap_used heap_commit\n";
    exit 0;
}

# set default timeout
$opt_t = '20';

Getopt::Long::Configure('bundling');
GetOptions(
    "w=s"        => \$opt_w,
    "warning=s"  => \$opt_w,
    "c=s"        => \$opt_c,
    "critical=s" => \$opt_c,
    "m=s"        => \$opt_m,
    "metric=s"   => \$opt_m,
    "H=s"        => \$opt_H,
    "hostname=s" => \$opt_H,
    "t=i"  	 => \$opt_t,
    "timeout=i"  => \$opt_t,
);

($opt_H)
  || ( $opt_H = shift )
  || usage("$0: Host name not specified.  Try --help\n");
my $host = $1 if ( $opt_H =~ /^([-_.A-Za-z0-9]+\$?)$/ );

($opt_w)
  || ( $opt_w = shift )
  || usage("$0: warn not specified.  Try --help\n");
my $warn = $1 if ( $opt_w =~ /^([-_.A-Za-z0-9]+\$?)$/ );

($opt_c)
  || ( $opt_c = shift )
  || usage("$0: crit not specified.  Try --help\n");
my $crit = $1 if ( $opt_c =~ /^([-_.A-Za-z0-9\\]+)$/ );

($opt_m)
  || ( $opt_m = shift )
  || usage("$0: metric not specified.  Try --help\n");
my $metric_name = $1 if ( $opt_m =~ /^(\w+)$/ );

my %metrics = (
    'gc_cpu'              => '12341234',
    'background_task_mem' => '25395109',
    'background_task_cpu' => '25395110',
    'heap_max'            => '25395390',
    'heap_used'           => '25395327',
    'heap_commit'         => '25395316',
);

my %units = (
    'gc_cpu'              => '%',
    'background_task_mem' => 'MB',
    'background_task_cpu' => '%',
    'heap_max'            => 'MB',
    'heap_used'           => 'MB',
    'heap_commit'         => 'MB',
);

# go to the website to pull out the agent IDs from the URL, format is below
my %agents = (
    'node1'    	    => 'NNNNNN_iNNNN',
    'node2'	    => 'NNNNNN_iNNN',
);

my $metric_id = $metrics{$metric_name} || usage "invalid metric\n";
usage "invalid hostname\n" unless $agents{$host};

$SIG{'ALRM'} = sub {
    print "UNKNOWN: Timeout after $opt_t sec.\n";
    exit 3;
};

alarm($opt_t);

my $app_id = $agents{$host};
$app_id =~ m/\d+_i(\d+)/;
my $agent_id = $1;

my $t_url = 'https://rpm.newrelic.com/session';

my $login        = 'apiuser@example.com';
my $password     = 'password';
my $submit_value = 'Login_submit';
my $account_id   = 'NNNNNN';

my $ua = LWP::UserAgent->new;
$ua->agent(
    "Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)");

$ua->cookie_jar(
    HTTP::Cookies->new(
        file           => "cookies.nr.txt",
        autosave       => 1,
        ignore_discard => 1
    )
);

my $content = $ua->request(
    POST $t_url ,
    [
        'login[email]'    => $login,
        'login[password]' => $password,
        loginSubmit       => $submit_value
    ]
)->as_string;

my $url;
if ( $metric_name eq 'background_task_cpu' ) {
    $url =
qq {https://rpm.newrelic.com/chart_data/metric_charts/background_job.json?account_id=$account_id&agent=$app_id&application_id=$app_id&chart_type=MSLine&disable_links=true&metric=$metric_id&no_links=true&omit_absent_data=true&render_to=background_task_cpu&title=Background+task+CPU+usage&value=time_percentage&tw%5Bdur%5D=last_30_minutes};
}
elsif ( $metric_name eq 'gc_cpu' ) {
    $url =
qq {https://rpm.newrelic.com/chart_data/base_charts/gc.json?account_id=$account_id&agent=$agent_id&application_id=$app_id&chart_type=StackedArea2D&default_tooltip=true&no_click=true&no_links=true&omit_absent_data=true&render_to=instance_memory_chart_645536_15&tw%5Bdur%5D=last_30_minutes};
}
else {
    $url =
qq {https://rpm.newrelic.com/chart_data/metric_charts/single_metric.json?account_id=$account_id&agent=$agent_id&application_id=$app_id&chart_type=MSLine&exclude_empty_data=true&format_fn=smart_round&metric[]=$metric_id&no_click=true&no_links=true&omit_absent_data=true&value=average_value&tw%5Bdur%5D=last_30_minutes};
}

$content = $ua->request( GET $url )->content;

my $json = decode_json($content);
my @metrics;
my @CRIT;
my @WARN;
my @OK;
my @perfdata;
my %gcmetrics;

if ( $metric_name eq 'gc_cpu' ) {

    foreach my $i ( 0 .. 3 ) {
        if ( $json->{series}[$i]->{name} ) {
            my $data = $json->{series}[$i]{data};
            my @tenmin = splice( @$data, 20, 29 );

            my @metrics;

            foreach my $hash (@tenmin) {
                push @metrics, $hash->{y};
            }
            my $avg  = mean(@metrics);
            my $name = $json->{series}[$i]->{name};
            $name =~ m/GC\s\-\s(\w+)/;
            $name = $1;
            $gcmetrics{$name} = $avg;
        }
    }

    foreach my $key ( keys %gcmetrics ) {
        my $value = $gcmetrics{$key};

        if ( $value >= $crit ) {
            push @CRIT, "$key=$value$units{$metric_name} ";
        }
        elsif ( $value >= $warn ) {
            push @WARN, "$key=$value$units{$metric_name} ";
        }
        else {
            push @OK, "$key=$value$units{$metric_name} ";
        }

        push @perfdata, "$key=$value";
    }

}

else {

# the minimum range in New Relic is 30 minutes but 1 minute samples are available so lets do 10 minute averages
    my $data = $json->{series}[0]{data};
    my @tenmin = splice( @$data, 20, 29 );

    foreach my $hash (@tenmin) {
        push @metrics, $hash->{y};
    }

    my $value = mean(@metrics);

    if ( $value >= $crit ) {
        push @CRIT, "$value$units{$metric_name}";
    }
    elsif ( $value >= $warn ) {
        push @WARN, "$value$units{$metric_name}";
    }
    else {
        push @OK, "$value$units{$metric_name}";
    }

    push @perfdata, "$metric_name=$value";
}

##
## Analyze results

print uc($metric_name) . " ";
my $status = "OK";

if (@CRIT) {
    $status = "CRITICAL";
    print "$status: ";
    foreach my $line (@CRIT) {
        print $line;
    }
    print " | @perfdata\n";
    exit $ERRORS{$status};
}
elsif (@WARN) {
    $status = "WARNING";
    print "$status: ";
    foreach my $line (@WARN) {
        print $line;
    }
    print " | @perfdata\n";
    exit $ERRORS{$status};
}
else {
    print "$status: ";
    foreach my $line (@OK) {
        print $line;
    }
    print " | @perfdata\n";
    exit $ERRORS{$status};
}

sub mean {
    return sprintf( "%.0f", sum(@_) / @_ );
}
