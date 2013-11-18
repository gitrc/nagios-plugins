#!/usr/bin/perl -w
#
#
# notify-by-stashboard.pl - send updates to stashboard
#
# Rod Cordova (@gitrc)
#

use strict;

require 'OAuth.pm';

my $service = $ARGV[0];
my $state   = $ARGV[1];
my $message = $ARGV[2];

if ( $#ARGV < 2 ) {
    &usage;
    exit;
}

sub usage {
    print "usage: $0 <service name> <status> <quoted message>\n";
}

my %services = (

    'www.example.com'    	=> 'stashboard service name',
    'www.example2.com' 		=> 'stashboard service name',
    'www.example3.com'       	=> 'stashboard service name',

);

my %states = (

    'OK'       => 'up',
    'WARNING'  => 'warning',
    'CRITICAL' => 'down',

);

die "ERROR: unknown service $service\n" if !$services{$service};

my $oua = LWP::Authen::OAuth->new(
    oauth_consumer_key    => 'anonymous',
    oauth_consumer_secret => 'anonymous',
    oauth_token           => 'your_token',
    oauth_token_secret    => 'your_secret',
);

my $r = $oua->post(
"https://mystashboardurl.appspot.com/admin/api/v1/services/$services{$service}/events",
    [
        'status'  => $states{$state},
        'message' => $message,
    ]
);
if ( $r->is_error ) {
    print "POST failed: " . $r->as_string;
}

# the end
