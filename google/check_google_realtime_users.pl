#!/usr/bin/perl -w
#
# check_google_realtime_users.pl - Self explanatory
#
# you need to be on the realtime API beta to use this, just grab the google-perl-api-client stuff (eg directory)
#
# https://developers.google.com/analytics/devguides/reporting/realtime/v3/reference/data/realtime/get#examples
#
# Rod Cordova (@gitrc)
#


use strict;
use warnings;
use feature qw/say/;
use FindBin;
use JSON;
use Data::Dumper;

use Google::API::Client;
use OAuth2::Client;

use lib 'eg/lib';
use Sample::Utils qw/get_or_restore_token store_token/;

use Getopt::Long;
use vars qw($opt_H $opt_w $opt_c);
use lib "/usr/local/nagios/libexec"  ;
use utils qw($TIMEOUT %ERRORS &usage);

sub print_help ();
sub print_usage ();

Getopt::Long::Configure('bundling');
GetOptions
         ("w=s" => \$opt_w, "warning=s"  => \$opt_w,
         "c=s" => \$opt_c, "critical=s" => \$opt_c,
         "H=s" => \$opt_H, "hostname=s" => \$opt_H);

my $opt_s;
my $opt_u;
my $session;
my $error;

($opt_H) || ($opt_H = shift) || usage("Host name not specified\n");
my $host = $1 if ($opt_H =~ /^([-_.A-Za-z0-9]+\$?)$/);
#($host) || usage("Invalid hostname: $opt_H\n");

($opt_w) || ($opt_s = shift) || usage("warn not specified\n");
my $warn = $1 if ($opt_w =~ /^([-_.A-Za-z0-9]+\$?)$/);

($opt_c) || ($opt_u = shift) || usage("crit not specified\n");
my $crit = $1 if ($opt_c =~ /^([-_.A-Za-z0-9\\]+)$/);

my %views = ( 'www.example.com' => '12345678',
	      'www.example2.com' => '12345678',
	      'www.example3.com' => '12345678',
);

my $service = Google::API::Client->new->build('analytics', 'v3');

my $file = "$FindBin::Bin/../client_secrets.json";
my $auth_driver = OAuth2::Client->new_from_client_secrets($file, $service->{auth_doc});

my $dat_file = "$FindBin::Bin/token.dat";

my $access_token = get_or_restore_token($dat_file, $auth_driver);

#my $res = $service->management->accounts->list->execute({ auth_driver => $auth_driver });
#my $res = $service->data->realtime->get({ auth_driver => $auth_driver });
my $res = $service->data->realtime->get(body => { ids => "ga:$views{$host}", metrics => 'ga:activeVisitors' })->execute({ auth_driver => $auth_driver });

#say Dumper($res);
#print Dumper $res->{totalsForAllResults}->{'ga:activeVisitors'};

my $metric = $res->{totalsForAllResults}->{'ga:activeVisitors'};
my $state = "OK";

if ($metric > $crit)
        {
        print "CRITICAL: $metric users | count=$metric\n";
        $state = "CRITICAL";
        }
        elsif ($metric > $warn)
        {
        print "WARNING: $metric users | count=$metric\n";
        $state = "WARNING";
        }
        else
        {
        print "OK: $metric users | count=$metric\n";
        }
exit $ERRORS{$state};





store_token($dat_file, $auth_driver);
__END__
