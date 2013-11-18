#!/usr/bin/perl
#
# check_cisco_wlan_mem.pl - check the memory on the Cisco WLAN controllers
#
# Rod Cordova (@gitrc)
#

use strict;
use Net::SNMP;
use Getopt::Long;
use vars qw($opt_H $opt_w $opt_c);
use lib "/usr/local/nagios/libexec";
use utils qw($TIMEOUT %ERRORS &usage);

sub print_help ();
sub print_usage ();

Getopt::Long::Configure('bundling');
GetOptions(
    "w=s"        => \$opt_w,
    "warning=s"  => \$opt_w,
    "c=s"        => \$opt_c,
    "critical=s" => \$opt_c,
    "H=s"        => \$opt_H,
    "hostname=s" => \$opt_H
);

my $opt_s;
my $opt_u;
my $session;
my $error;
my @ERRORS;

($opt_H) || ( $opt_H = shift ) || usage("Host name not specified\n");
my $host = $1 if ( $opt_H =~ /^([-_.A-Za-z0-9]+\$?)$/ );
($host) || usage("Invalid host: $opt_H\n");

($opt_w) || ( $opt_s = shift ) || usage("warn not specified\n");
my $warn = $1 if ( $opt_w =~ /^([-_.A-Za-z0-9]+\$?)$/ );

($opt_c) || ( $opt_u = shift ) || usage("crit not specified\n");
my $crit = $1 if ( $opt_c =~ /^([-_.A-Za-z0-9\\]+)$/ );

( $session, $error ) = Net::SNMP->session(
    Hostname  => $host,
    Community => "publ1c"
);

die "session error: $error" unless ($session);

my $total_mem = $session->get_request("1.3.6.1.4.1.14179.1.1.5.2.0");
my $used_mem  = $session->get_request("1.3.6.1.4.1.14179.1.1.5.3.0");

die "request error: " . $session->error unless ( defined $total_mem );
die "request error: " . $session->error unless ( defined $used_mem );

$session->close;

$total_mem = "$total_mem->{\"1.3.6.1.4.1.14179.1.1.5.2.0\"}";
$used_mem  = "$used_mem->{\"1.3.6.1.4.1.14179.1.1.5.3.0\"}";

# round it
my $used_pct = ( $used_mem / $total_mem ) * 100;
$used_pct = sprintf( "%.0f", $used_pct );
my $state = "OK";

if ( $used_pct >= $crit ) {
    push @ERRORS, "CRITICAL: $used_pct% memory utilization.";
    $state = "CRITICAL";
}
elsif ( $used_pct >= $warn ) {
    push @ERRORS, "WARNING: $used_pct% memory utilization.";
    $state = "WARNING";
}

if (@ERRORS) {
    print @ERRORS;
}
else {
    print "OK: $used_pct% memory utilization";
}

print " (mem_total=$total_mem used_mem=$used_mem) | usage=$used_pct%\n";
exit $ERRORS{$state};
