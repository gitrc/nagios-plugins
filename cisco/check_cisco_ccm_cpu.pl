#!/usr/bin/perl -w
#
# Code based on snmpwalk.pl
#
# written for Cisco Call Manager (IBM) servers
#
# Rod Cordova (@gitrc)
#

use strict;
use Net::SNMP v5.1.0 qw(:snmp DEBUG_ALL);
use Getopt::Std;
use vars qw($SCRIPT $VERSION %OPTS);
use lib "/usr/local/nagios/libexec"  ;
use utils qw($TIMEOUT %ERRORS &usage);

my @cpustatus;

my @targets = ( '1.3.6.1.2.1.25.3.3.1.2' );
$SCRIPT  = 'check_cisco_ccm_cpu.pl';
$VERSION = '0.1';

# Validate the command line options
if ( !getopts( 'a:A:c:dD:E:m:n:p:r:t:u:v:x:X:', \%OPTS ) ) {
    _usage();
}

# Do we have enough/too much information?
if ( @ARGV < 1 ) {
    _usage();
}

foreach my $target (@targets) {

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
        -varbindlist => [$target]
    );

    if ( $s->version == SNMP_VERSION_1 ) {

        my $oid;

        while ( defined( $s->get_next_request(@args) ) ) {
            $oid = ( $s->var_bind_names() )[0];

            if ( !oid_base_match( $target, $oid ) ) { last; }

            #printf(
            #"%s = %s: %s\n", $oid,
            #snmp_type_ntop($s->var_bind_types()->{$oid}),
            push @cpustatus, $s->var_bind_list()->{$oid};

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

my $sum;
my $i;
foreach $i (@cpustatus) {
    $sum += $i;
}

my $STATUS  = "OK";

print
"CPU $STATUS: $sum% utilized | cpu=$sum\n";

exit $ERRORS{$STATUS};

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

