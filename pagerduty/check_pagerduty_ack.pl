#!/usr/bin/perl -w
#
#
# check_pagerduty_ack.pl - check PagerDuty for acknowledged incidents and pass back to Nagios
#
# Requires merlin (Nagios DB backend)
#
# Rod Cordova (@gitrc)
#
# Sep 2012
#

use strict;
use LWP::UserAgent;
use DBD::mysql;
use Data::Dumper;
use JSON;

my $DEBUG;
$DEBUG = exists( $ENV{SSH_CLIENT} ) ? 1 : 0;


my $url = 'https://example.pagerduty.com/api/v1/incidents?status=acknowledged';
my $ua = LWP::UserAgent->new;

my @headers = (
    'User-Agent'   => 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; SV1)',
    'Content-type' => 'application/json',
    'Authorization' => 'Token token=XXXX'
);

my $response = $ua->get( $url, @headers );

if ( $response->is_error ) {
    print "GET failed: " . $response->as_string;
}

my @content = $response->content;

my $json = decode_json(@content);

my $dbh =
  DBI->connect(
    'dbi:mysql:database=merlin;mysql_socket=/var/lib/mysql/mysql.sock',
    'root', '' );
my $query;

for my $item ( @{ $json->{incidents} } ) {
    if (   $item->{trigger_summary_data}->{pd_nagios_object}
        && $item->{last_status_change_by}->{email} )
    {
	my $type = $item->{trigger_summary_data}->{pd_nagios_object};
	my $contact = $item->{last_status_change_by}->{email};
	my $host = $item->{trigger_summary_data}->{HOSTNAME};
	my $desc = $item->{trigger_summary_data}->{SERVICEDESC} if ($type eq "service");

        if ( $type eq "host" ) {
            $query =
"SELECT host_name FROM host WHERE last_hard_state = 1 AND problem_has_been_acknowledged = 0 AND notifications_enabled = 1 AND host_name = \'$item->{trigger_summary_data}->{HOSTNAME}\'";
        }
        else {
            $query =
"SELECT service.host_name,service.service_description FROM service WHERE service.host_name = \'$item->{trigger_summary_data}->{HOSTNAME}\' AND service.service_description = \'$item->{trigger_summary_data}->{SERVICEDESC}\' AND service.last_hard_state in (1,2) AND service.problem_has_been_acknowledged = 0";
        }
        print $item->{last_status_change_by}->{email} . ","
          . $item->{trigger_summary_data}->{pd_nagios_object} . ","
          . $item->{trigger_summary_data}->{HOSTNAME} . ","
          if $DEBUG;
        if ( $type eq "service" ) {
            print $item->{trigger_summary_data}->{SERVICEDESC} . "," if $DEBUG;
        }
        print "\n" if $DEBUG;

        print "DB QUERY: $query\n" if $DEBUG;
        my $sth = $dbh->prepare($query);
        $sth->execute();
        my $found = $sth->fetch();
	if ($found) {
	if ($type eq "host") {
	&send_to_nagios($type,$host,$contact);
	}
	else 
	{
	&send_to_nagios($type,$host,$contact,$desc);
	}
        print "DEBUG: Sending ACK for $type $host" . "\n" if $DEBUG;
	}

    }

}

# Do stuff to Nagios
#

sub send_to_nagios {
    my $type 	     = shift;
    my $host	     = shift;
    my $contact      = shift;
    my $desc	     = shift if ($type eq "service");
    my $time         = time();
    my $msg          = 'ack via PagerDuty';
    my $command_file = "/usr/local/nagios/var/rw/nagios.cmd";
    $contact =~ m/(.+)@.+/;
    my $user = $1;

# Nagios ACK message structure
# [time] ACKNOWLEDGE_SVC_PROBLEM;<host_name>;<service_description>;<sticky>;<notify>;<persistent>;<author>;<comment>
# [time] ACKNOWLEDGE_HOST_PROBLEM;<host_name>;<sticky>;<notify>;<persistent>;<author>;<comment>

    if ( !( -w $command_file ) ) {
        print STDERR "FAILED TO OPEN FIFO FILE";
        exit 1;
    }
    open( CMD, '>>' . $command_file );
    if ( $type eq "service" ) {

        print CMD
"[$time] ACKNOWLEDGE_SVC_PROBLEM;$host;$desc;1;1;1;$user;$msg\n";
    }
    else {
        print CMD
          "[$time] ACKNOWLEDGE_HOST_PROBLEM;$host;1;1;1;$user;$msg\n";
    }
    close(CMD);

}    # end send_to_nagios sub

# the end
