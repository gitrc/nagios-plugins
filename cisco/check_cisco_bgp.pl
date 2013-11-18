#!/usr/bin/perl -w 
#
# Code based on snmpwalk.pl and check_bgp.pl
#
#
# Rod Cordova (@gitrc)

use strict;
use Net::SNMP v5.1.0 qw(:snmp DEBUG_ALL);
use Getopt::Std;
use vars qw($SCRIPT $VERSION %OPTS);
use lib "/usr/local/nagios/libexec";
use utils qw($TIMEOUT %ERRORS &usage);

$SCRIPT  = 'check_cisco_bgp.pl';
$VERSION = '0.1';

my @bgpPeerOID;
my %targets = (

    bgpPeerState              => "1.3.6.1.2.1.15.3.1.2",
    bgpPeerAdminStatus        => "1.3.6.1.2.1.15.3.1.3",
    bgpPeerRemoteAs           => "1.3.6.1.2.1.15.3.1.9",
    bgpPeerLastError          => "1.3.6.1.2.1.15.3.1.14",
    bgpPeerFsmEstablishedTime => "1.3.6.1.2.1.15.3.1.16"
);

my %bgpPeerStates = (
    -1 => 'unknown(-1)',
    1  => 'idle(1)',
    2  => 'connect(2)',
    3  => 'active(3)',
    4  => 'opensent(4)',
    5  => 'openconfirm(5)',
    6  => 'established(6)'
);

my %bgpPeerAdminStatuses = (
    1 => 'stop(1)',
    2 => 'start(2)'
);

my %bgpErrorCodes = (
    '01 00' => 'Message Header Error',
    '01 01' => 'Message Header Error - Connection Not Synchronized',
    '01 02' => 'Message Header Error - Bad Message Length',
    '01 03' => 'Message Header Error - Bad Message Type',
    '02 00' => 'OPEN Message Error',
    '02 01' => 'OPEN Message Error - Unsupported Version Number',
    '02 02' => 'OPEN Message Error - Bad Peer AS',
    '02 03' => 'OPEN Message Error - Bad BGP Identifier',
    '02 04' => 'OPEN Message Error - Unsupported Optional Parameter',
    '02 05' => 'OPEN Message Error',                                 #deprecated
    '02 06' => 'OPEN Message Error - Unacceptable Hold Time',
    '03 00' => 'UPDATE Message Error',
    '03 01' => 'UPDATE Message Error - Malformed Attribute List',
    '03 02' => 'UPDATE Message Error - Unrecognized Well-known Attribute',
    '03 03' => 'UPDATE Message Error - Missing Well-known Attribute',
    '03 04' => 'UPDATE Message Error - Attribute Flags Error',
    '03 05' => 'UPDATE Message Error - Attribute Length Erro',
    '03 06' => 'UPDATE Message Error - Invalid ORIGIN Attribute',
    '03 07' => 'UPDATE Message Error',                               #deprecated
    '03 08' => 'UPDATE Message Error - Invalid NEXT_HOP Attribute',
    '03 09' => 'UPDATE Message Error - Optional Attribute Error',
    '03 0A' => 'UPDATE Message Error - Invalid Network Field',
    '03 0B' => 'UPDATE Message Error - Malformed AS_PATH',
    '04 00' => 'Hold Timer Expired',
    '05 00' => 'Finite State Machine Error',
    '06 00' => 'Cease',
    '06 01' => 'Cease - Maximum Number of Prefixes Reached',
    '06 02' => 'Cease - Administrative Shutdown',
    '06 03' => 'Cease - Peer De-configured',
    '06 04' => 'Cease - Administrative Reset',
    '06 05' => 'Cease - Connection Rejected',
    '06 06' => 'Cease - Other Configuration Change',
    '06 07' => 'Cease - Connection Collision Resolution',
    '06 08' => 'Cease - Out of Resources'
);

my %output;

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
        -hostname  => $ARGV[0],
        -translate => [ -timeticks => 0x0 ]
        ,    # Turn off so snapmirrorLag is numeric
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

            #print "DEBUG: $oid\n";
            # capture the peer OIDs since we don't know them (e.g. why we walk)
            if ( $oid =~ /1.3.6.1.2.1.15.3.1.2/ ) {
                my $peerOID = $oid;
                $peerOID =~ s/1.3.6.1.2.1.15.3.1.2.//g;
                push @bgpPeerOID, $peerOID;
            }

            if ( !oid_base_match( $targets{$key}, $oid ) ) { last; }

            push @{ $output{$key} }, $s->var_bind_list()->{$oid};

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

my $status = "OK";

my @CRIT;
my @OK;

#use Data::Dumper;

my $count = 0;
foreach my $result ( @{ $output{bgpPeerState} } ) {
    if ( $result != 6 ) {
my $lasterror;
                my $lasterrorcode = $output{bgpPeerLastError}[$count];
                if (hex($lasterrorcode) != 0) {
                        $lasterrorcode = substr($lasterrorcode,2,2)." ".substr($lasterrorcode,4,2);
                        my ($code,$subcode) = split(" ",$lasterrorcode);
                        if (!defined($bgpErrorCodes{$lasterrorcode})) {
                                $lasterror = $bgpErrorCodes{"$code 00"};
                        } else {
                                $lasterror = $bgpErrorCodes{$lasterrorcode};
                        }
                        if (!defined($lasterror)) {
                                $lasterror = "Unknown ($code $subcode)";
                        }
                }

        push @CRIT,
          " $bgpPeerOID[$count]" . "(AS" . $output{bgpPeerRemoteAs}[$count] . ")" . "="
          . $bgpPeerStates{$result}
          . " last error: $lasterror"; 
	  #. $bgpErrorCodes{$output{bgpPeerLastError}[$count]}";
	#print Dumper $bgpErrorCodes{$output{bgpPeerLastError}[$count]};
    }
    else {
        push @OK, " $bgpPeerOID[$count]"  . "(AS" . $output{bgpPeerRemoteAs}[$count] . ")" . "=" . $bgpPeerStates{$result};
    }
    $count++;
}

if (@CRIT) {
    $status = "CRITICAL";
    print "BGP $status:";
    foreach my $line (@CRIT) {
        print $line;
    }
    print "\n";
    exit $ERRORS{$status};
}
else {
    print "BGP $status:";
    foreach my $line (@OK) {
        print $line;
    }
    print "\n";
    exit $ERRORS{$status};
}

#print "BGP $status: ";

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

