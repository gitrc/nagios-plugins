#!/usr/bin/perl -w
#
# Send Nagios notifications via Google SMS
#
# Rod Cordova (@gitrc)
#
# Late 2009

my $username = 'google@username';
my $password = 'changeme';
my $phone = $ARGV[0];
my $message = $ARGV[1];

if ($#ARGV < 1) {
        &usage;
        exit;
}

use Google::Voice;
my $g = Google::Voice->new->login($username, $password);
$g->send_sms($phone => $message); 


sub usage {
                print "usage: $0 <phone_number> <quoted message>\n";
}

