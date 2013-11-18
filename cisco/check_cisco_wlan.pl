#!/usr/bin/perl -w
#
# Code based on snmpwalk.pl
#
# written for Cisco WLAN controllers
#
# Rod Cordova (@gitrc)

use strict;
use Net::SNMP v5.1.0 qw(:snmp DEBUG_ALL);
use Getopt::Std;
use vars qw($SCRIPT $VERSION %OPTS);
use lib "/usr/local/nagios/libexec";
use utils qw($TIMEOUT %ERRORS &usage);

$SCRIPT  = 'check_cisco_wlan.pl';
$VERSION = '0.1';

my %targets = (

    'apclients'    => '1.3.6.1.4.1.14179.2.2.2.1.15',
    'apstatus'     => '1.3.6.1.4.1.14179.2.2.1.1.6',
    'admstatus'    => '1.3.6.1.4.1.14179.2.2.1.1.37',
    'operstatus'   => '1.3.6.1.4.1.14179.2.2.1.1.37',
    'load'         => '1.3.6.1.4.1.14179.2.2.16.1.1',
    'interference' => '1.3.6.1.4.1.14179.2.2.16.1.2',
    'noise'        => '1.3.6.1.4.1.14179.2.2.16.1.3',
    'coverage'     => '1.3.6.1.4.1.14179.2.2.16.1.24',
);

my @profiles = ( 'load', 'interference', 'noise', 'coverage' );
my %output;
my @apclients;

#foreach my $key (keys %targets)
#{
#print "$key: $targets{$key}" . "\n";
#}
#exit 0;

# Validate the command line options
if ( !getopts( 'a:A:c:dD:E:m:n:p:r:t:u:v:x:X:', \%OPTS ) ) {
    _usage();
}

# Do we have enough/too much information?
if ( @ARGV < 1 ) {
    _usage();
}

foreach my $key ( keys %targets ) {

    # Create the SNMP session
    my ( $s, $e ) = Net::SNMP->session(
        -hostname => $ARGV[0],
        exists( $OPTS{a} ) ? ( -authprotocol => $OPTS{a} )  : (),
        exists( $OPTS{A} ) ? ( -authpassword => $OPTS{A} )  : (),
        exists( $OPTS{c} ) ? ( -community    => $OPTS{c} )  : (),
        exists( $OPTS{D} ) ? ( -domain       => $OPTS{D} )  : (),
        exists( $OPTS{d} ) ? ( -debug        => DEBUG_ALL ) : (),
        exists( $OPTS{m} ) ? ( -maxmsgsize   => $OPTS{m} )  : (),
        exists( $OPTS{p} ) ? ( -port         => $OPTS{p} )  : (),
        exists( $OPTS{r} ) ? ( -retries      => $OPTS{r} )  : (),
        exists( $OPTS{t} ) ? ( -timeout      => $OPTS{t} )  : (),
        exists( $OPTS{u} ) ? ( -username     => $OPTS{u} )  : (),
        exists( $OPTS{v} ) ? ( -version      => $OPTS{v} )  : (),
        exists( $OPTS{x} ) ? ( -privprotocol => $OPTS{x} )  : (),
        exists( $OPTS{X} ) ? ( -privpassword => $OPTS{X} )  : ()
    );

    # Was the session created?
    if ( !defined($s) ) {
        _exit($e);
    }

    # Perform repeated get-next-requests or get-bulk-requests (SNMPv2c)
    # until the last returned OBJECT IDENTIFIER is no longer a child of
    # OBJECT IDENTIFIER passed in on the command line.

    my @args = (
        exists( $OPTS{E} ) ? ( -contextengineid => $OPTS{E} ) : (),
        exists( $OPTS{n} ) ? ( -contextname     => $OPTS{n} ) : (),
        -varbindlist => [ $targets{$key} ]
    );

    if ( $s->version == SNMP_VERSION_1 ) {

        my $oid;

        while ( defined( $s->get_next_request(@args) ) ) {
            $oid = ( $s->var_bind_names() )[0];

            if ( !oid_base_match( $targets{$key}, $oid ) ) { last; }

            #printf(
            #"%s = %s: %s\n", $oid,
            #snmp_type_ntop($s->var_bind_types()->{$oid}),
            #if ( $target eq '1.3.6.1.4.1.14179.2.2.1.1.6' ) {
            #    push @apstatus, $s->var_bind_list()->{$oid};
            #}
            #else {
            #push @apclients, $s->var_bind_list()->{$oid};
            #}
            push @{ $output{$key} }, $s->var_bind_list()->{$oid};

            #);

            @args = ( -varbindlist => [$oid] );
        }

    }
    else {

        push( @args, -maxrepetitions => 25 );

      outer: while ( defined( $s->get_bulk_request(@args) ) ) {

            my @oids = oid_lex_sort( keys( %{ $s->var_bind_list() } ) );

            foreach (@oids) {

                if ( !oid_base_match( $ARGV[0], $_ ) ) { last outer; }
                printf( "%s = %s: %s\n",
                    $_,
                    snmp_type_ntop( $s->var_bind_types()->{$_} ),
                    $s->var_bind_list()->{$_},
                );

                # Make sure we have not hit the end of the MIB
                if ( $s->var_bind_list()->{$_} eq 'endOfMibView' ) {
                    last outer;
                }
            }

            # Get the last OBJECT IDENTIFIER in the returned list
            @args = ( -maxrepetitions => 25, -varbindlist => [ pop(@oids) ] );
        }
    }

    # Let the user know about any errors
    if ( $s->error() ne '' ) {
        _exit( $s->error() );
    }

    # Close the session
    $s->close();
}    # end of foreach targets loop

my %counter;
my @ERRORS;

# iterate through the hash of arrays for validation of status values
foreach my $val ( keys %output ) {
    next if $val =~ /^apclients/;
    $counter{$val} = 0;
    foreach my $result ( @{ $output{$val} } ) {
        if ( $result != 1 ) {
            $counter{$val}++;
	    push @ERRORS, $result;
        }
    }

}

# total wlan clients
my $sum;
my $i;
foreach $i ( @{ $output{apclients} } ) {
    $sum += $i;
}

my $status  = "OK";
my $apcount = @{ $output{apstatus} };

#if (@ERRORS)
#{
#$status = "WARNING";
#}

print "WLAN $status: ";
for my $key ( keys %counter ) {
    my $value = $counter{$key};
    print "$value $key failures / ";
}

print
" - $apcount total WLAN Access Points - $sum total WLAN Clients | clients=$sum\n";

exit $ERRORS{$status};

#for my $val ( keys %output ) { print "$val: @{ $output{$val} }\n"; }

# [private] ------------------------------------------------------------------

sub _exit {
    printf join( '', sprintf( "%s: ", $SCRIPT ), shift(@_), ".\n" ), @_;
    exit 1;
}

sub _usage {
    print << "USAGE";
$SCRIPT v$VERSION
Usage: $SCRIPT [options] <hostname>
Options: -v 1|2c|3      SNMP version
         -d             Enable debugging
   SNMPv1/SNMPv2c:
         -c <community> Community name
   SNMPv3:
         -u <username>  Username (required)
         -E <engineid>  Context Engine ID
         -n <name>      Context Name
         -a <authproto> Authentication protocol <md5|sha>
         -A <password>  Authentication password
         -x <privproto> Privacy protocol <des|3des|aes>
         -X <password>  Privacy password
   Transport Layer:
         -D <domain>    Domain <udp|udp6|tcp|tcp6>
         -m <octets>    Maximum message size
         -p <port>      Destination port
         -r <attempts>  Number of retries
         -t <secs>      Timeout period
USAGE
    exit 1;
}

# ============================================================================

