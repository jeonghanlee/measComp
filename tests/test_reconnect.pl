#!/usr/bin/env perl
use strict;
use warnings;

use Errno qw(EINTR);
use File::Basename qw(dirname);
use File::Spec;
use FindBin qw($RealBin);
use lib $RealBin;
use Getopt::Long qw(GetOptionsFromArray);
use IO::Handle;
use IO::Select;
use JSON::PP;
use Pod::Usage qw(pod2usage);
use POSIX qw(WNOHANG);
use Scalar::Util qw(looks_like_number);
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC sleep);
use TC32;
use E1608;

my $JSON = JSON::PP->new->canonical;
my $signal_status = 0;
my @STATE_FIELDS = qw(connected auto enabled pact udf severity value severity31 value31 digital_severity digital_value);
my $READ_TIMEOUT = 8;
my $RECOVERY_TIMEOUT = 12;
my $EXIT_TIMEOUT = 5;
my $DIGITAL_POLL_MS = 10000;
my $POLICY_WINDOW = 12;
my $ABSENT_WINDOW = 11;
my $RECONNECT_DELAY = 5;
my $REFRESH_INTERVAL = 4;
my $INTERVAL_TOLERANCE = 0.1;
my $REDISCOVERY_LIMIT = 8;
my $POLL_GAP_LIMIT = 3;
my $MAC_A = "\x02\0\0\0\0\x32";
my $MAC_B = "\x02\0\0\0\xab\x33";
my %CASES = map { $_ => 1 } qw(reconnect digital-word digital-control digital-policy digital-bits
    enum-tc32-online enum-tc32-offline enum-e1608-online enum-e1608-offline enum-e1608-init
    bounds-tc32-online bounds-tc32-offline bounds-e1608-online bounds-e1608-offline
    mac-tc32-online mac-tc32-offline mac-two-ports mac-known-absent
    endpoint-same-ip endpoint-mixed endpoint-distinct-ip endpoint-default-port endpoint-alt-port
    endpoint-hostname endpoint-hostname-port endpoint-wrong-port);
my $ALT_DISCOVERY_PORT = 54221;
my $UNUSED_DISCOVERY_PORT = 54231;
my $FIXTURE_HOSTNAME = 'fixture-a';
my @ANALOG_FIELDS = qw(bounds_status low high raw value slope offset egul eguf udf severity pact linear timestamp);
my $ANALOG_TOLERANCE = 1e-10;

sub now {
    return clock_gettime(CLOCK_MONOTONIC);
}

sub launch_ioc {
    my ($run, $executable, $dbd, $template) = @_;
    my $binary_template = File::Spec->catfile(dirname($template), 'measCompBinaryIn.template');
    my $startup = ($run->{family} // '') eq 'bounds' ? "bounds-$run->{startup}" : $run->{startup};
    my @extra = $run->{model} ? ($run->{model}, $startup)
        : defined $run->{second_id} ? ($run->{second_id}) : ();
    my $device_id = $run->{device_id} // $run->{device}{address};
    pipe(my $input_read, my $input_write) or die "IOC input pipe: $!\n";
    pipe(my $output_read, my $output_write) or die "IOC output pipe: $!\n";
    my $pid = fork();
    defined $pid or die "IOC fork: $!\n";
    if (!$pid) {
        open(STDIN, '<&', $input_read) or POSIX::_exit(126);
        open(STDOUT, '>&', $output_write) or POSIX::_exit(126);
        open(STDERR, '>&', $output_write) or POSIX::_exit(126);
        $SIG{INT} = $SIG{TERM} = $SIG{PIPE} = 'DEFAULT';
        {
            no warnings 'exec';
            exec { $executable } $executable, $dbd, $template, $device_id, $binary_template, @extra;
        }
        POSIX::_exit(127);
    }
    $run->{pid} = $pid;
    close($input_read) or die "IOC input reader: close: $!\n";
    close($output_write) or die "IOC output writer: close: $!\n";
    $input_write->autoflush(1);
    $run->{input} = $input_write;
    $run->{output} = $output_read;
    $run->{selector} = IO::Select->new($output_read);
    return;
}

sub pump {
    my ($run, $seconds) = @_;
    # Two fixtures share the wait so that neither device waits a whole slice for the other.
    my $slice = $run->{device2} ? $seconds / 2 : $seconds;
    $run->{device}->poll($slice);
    $run->{device2}->poll($slice) if $run->{device2};
    while (!$run->{eof} && $run->{selector}->can_read(0)) {
        my $count = sysread($run->{output}, my $data, 65536);
        next if !defined($count) && $! == EINTR;
        defined $count or die "IOC output read: $!\n";
        if (!$count) { $run->{eof} = 1; last; }
        print {$run->{log}} $data or die "$run->{log_path}: write: $!\n";
        $run->{buffer} .= $data;
        while ($run->{buffer} =~ s/\A([^\n]*)\n//) {
            my $line = $1;
            $line =~ s/\s+\z//;
            push @{$run->{lines}}, $line;
            push @{$run->{diagnostics}}, $line if $line =~ /err=\d+/;
        }
    }
    return;
}

sub pause {
    my ($run, $seconds) = @_;
    my $deadline = now() + $seconds;
    while (now() < $deadline) {
        my $left = $deadline - now();
        pump($run, $left < 0.02 ? $left : 0.02) if $left > 0;
    }
    return;
}

sub read_prefix {
    my ($run, $prefix, $timeout) = @_;
    $timeout //= $READ_TIMEOUT;
    my $deadline = now() + $timeout;
    while (now() < $deadline) {
        while (@{$run->{lines}}) {
            my $line = shift @{$run->{lines}};
            return $line if index($line, $prefix) == 0;
        }
        die "IOC output closed before $prefix\n" if $run->{eof};
        pump($run, 0.02);
    }
    die "deadline exceeded waiting for $prefix\n";
}

sub command {
    my ($run, $line, $prefix) = @_;
    $prefix //= 'RESULT';
    print {$run->{input}} "$line\n" or die "IOC input write: $!\n";
    return read_prefix($run, $prefix);
}

sub state {
    my ($run) = @_;
    my @values = split /\s+/, command($run, 'STATE', 'STATE');
    shift @values;
    die "malformed IOC state\n" unless @values == @STATE_FIELDS;
    for my $value (@values) { die "non-numeric IOC state: $value\n" unless looks_like_number($value); }
    my %state;
    @state{@STATE_FIELDS} = map { 0 + $_ } @values;
    return \%state;
}

sub wait_for {
    my ($run, $predicate, $timeout) = @_;
    $timeout //= $RECOVERY_TIMEOUT;
    my $deadline = now() + $timeout;
    my $observed;
    while (now() < $deadline) {
        $observed = state($run);
        return $observed if $predicate->($observed);
        pause($run, 0.1);
    }
    die 'deadline exceeded; last state=' . $JSON->encode($observed)
        . '; simulator errors=' . $JSON->encode($run->{device}{errors}) . "\n";
}

sub check {
    my ($run, $name, $condition, $evidence) = @_;
    my $result = {name => $name, passed => $condition ? JSON::PP::true : JSON::PP::false,
                  evidence => $evidence};
    push @{$run->{checks}}, $result;
    print $JSON->encode($result), "\n" or die "stdout: $!\n";
    die "$name\n" unless $condition;
    return;
}

sub healthy {
    my ($run, $value) = @_;
    return wait_for($run, sub {
        my ($state) = @_;
        return $state->{connected} == 1 && $state->{severity} == 0 && $state->{udf} == 0
            && abs($state->{value} - $value) < 0.001 && $state->{severity31} == 0
            && abs($state->{value31} - $value) < 0.001;
    });
}

sub tc_write_failures {
    my ($run) = @_;
    my $device = $run->{device};
    for my $case ([0, 2, 3], [0, 4, 5], [31, 6, 7]) {
        my ($address, $confirmed, $rejected) = @$case;
        my $write = $address ? 'TC31' : 'TC';
        my $name = "TC channel $address type $confirmed";
        my $result = command($run, "$write $confirmed");
        my $readback = command($run, "READTC $address", 'TCREAD');
        check($run, "$name successful write", $result eq 'RESULT 0'
            && $readback eq "TCREAD 0 $confirmed"
            && ord(substr($device->{types}, $address, 1)) == $confirmed,
            {result => $result, readback => $readback, device => unpack('C*', substr($device->{types}, $address, 1))});
        my $fault_count = @{$device->{faults}};
        $device->{fault} = [0x15, 'eof'];
        $result = command($run, "$write $rejected");
        my $cached = command($run, "CACHETC $address", 'TCREAD');
        my $failed = state($run);
        check($run, "$name write reaches transport failure", $result eq 'RESULT 3'
            && !defined($device->{fault}) && @{$device->{faults}} == $fault_count + 1
            && $device->{faults}[-1][0] == 0x15 && $failed->{connected} == 0,
            {result => $result, cache => $cached, state => $failed, fault => $device->{faults}[-1]});
        $device->{types} = chr(1) x 64;
        $device->{online} = 1;
        healthy($run, $device->{temperature});
        $readback = command($run, "READTC $address", 'TCREAD');
        my $restored = ord(substr($device->{types}, $address, 1));
        check($run, "$name survives failed write", $cached eq "TCREAD 0 $confirmed"
            && $readback eq "TCREAD 0 $confirmed" && $restored == $confirmed,
            {cache_after_failure => $cached, readback_after_reconnect => $readback, device => $restored});
    }
    return;
}

sub reap {
    my ($run) = @_;
    return 1 if defined $run->{ioc_exit};
    my $waited = waitpid($run->{pid}, WNOHANG);
    return 0 if !$waited || ($waited == -1 && $! == EINTR);
    $waited == $run->{pid} or die "IOC waitpid: $!\n";
    my $status = $?;
    $run->{ioc_exit} = ($status & 127) ? -($status & 127) : $status >> 8;
    return 1;
}

sub enum_snapshot {
    my ($run, $address, $parameter, $record) = @_;
    my $line = command($run, "ENUM $address $parameter $record", 'ENUM');
    my @parts = split / \|/, $line, -1;
    my $header = shift @parts;
    my ($status, $count, $error) = $header =~ /\AENUM (\d+) (\d+) (\d+)\z/;
    die "malformed enum header: $header\n" unless defined $error;
    die "incomplete enum snapshot: $line\n" unless @parts == $count + 16;
    my @entries;
    for my $part (@parts) {
        my ($hex, $value, $severity) = $part =~ /\A((?:[0-9a-f]{2})*),(-?\d+),(-?\d+)\z/;
        die "malformed enum entry: $part\n" unless defined $severity;
        push @entries, [pack('H*', $hex), 0 + $value, 0 + $severity];
    }
    my @driver = splice @entries, 0, $count;
    return {status => 0 + $status, error => 0 + $error, driver => \@driver, record => \@entries};
}

sub enum_targets {
    my ($model) = @_;
    my @targets;
    my $ranges = $model eq 'tc32' ? [['N.A.', 0, 0]]
        : [['+= 10V', 1, 0], ['+= 5V', 0, 0], ['+= 2V', 14, 0], ['+= 1V', 4, 0]];
    my $types = $model eq 'tc32' ? [['TC deg.', 2, 0]] : [['Volts', 1, 0]];
    for my $address (0, $model eq 'tc32' ? 31 : 7) {
        push @targets, [$address, 'ANALOG_IN_RANGE', "TEST:A${address}Range", $ranges],
            [$address, 'ANALOG_IN_TYPE', "TEST:A${address}Type", $types];
        push @targets, [$address, 'VOLTAGE_IN_RANGE', "TEST:V${address}Range", $ranges]
            if $model eq 'e1608';
    }
    if ($model eq 'e1608') {
        for my $address (0, 1) {
            push @targets, [$address, 'ANALOG_OUT_RANGE', "TEST:O${address}Range", [['+= 10V', 1, 0]]];
        }
    }
    return @targets;
}

sub wait_connected {
    my ($run, $expected) = @_;
    my $deadline = now() + $RECOVERY_TIMEOUT;
    while (now() < $deadline) {
        my $line = command($run, 'CONNECTED', 'CONNECTED');
        return $line if $line eq "CONNECTED $expected";
        pause($run, 0.1);
    }
    die "connection state $expected deadline exceeded\n";
}

sub verify_enums {
    my ($run, $phase) = @_;
    my $verified = 0;
    for my $target (enum_targets($run->{model})) {
        my ($address, $parameter, $record, $expected) = @$target;
        my $snapshot;
        my @record_expected = (@$expected, map { ['', 0, 0] } @$expected .. 15);
        my $deadline = now() + $RECOVERY_TIMEOUT;
        while (1) {
            $snapshot = enum_snapshot($run, $address, $parameter, $record);
            last if $snapshot->{status} == 0 && !$snapshot->{error}
                && $JSON->encode($snapshot->{record}) eq $JSON->encode(\@record_expected);
            last if now() >= $deadline;
            pause($run, 0.1);
        }
        check($run, "$phase $record driver enums", $snapshot->{status} == 0
            && $JSON->encode($snapshot->{driver}) eq $JSON->encode($expected), $snapshot);
        check($run, "$phase $record record enums", !$snapshot->{error}
            && $JSON->encode($snapshot->{record}) eq $JSON->encode(\@record_expected), $snapshot);
        for my $index (0 .. $#$expected) {
            my $raw = $expected->[$index][1];
            my $result = command($run, "ENUMSET $record $index");
            check($run, "$phase $record selection $index accepted", $result eq 'RESULT 0', $result);
            my $selection;
            my $deadline = now() + $RECOVERY_TIMEOUT;
            while (1) {
                $selection = command($run, "ENUMVALUE $address $parameter $record", 'ENUMVALUE');
                die "malformed enum value: $selection\n"
                    unless $selection =~ /\AENUMVALUE(?: -?\d+){6}\z/;
                last if $selection eq "ENUMVALUE 0 $raw $raw 0 0 1" || now() >= $deadline;
                pause($run, 0.02);
            }
            check($run, "$phase $record selection $index maps to $raw",
                $selection eq "ENUMVALUE 0 $raw $raw 0 0 1", $selection);
        }
        $verified++;
    }
    check($run, "$phase enum target coverage", $verified == ($run->{model} eq 'tc32' ? 4 : 8), $verified);
    return;
}

sub exercise_enums {
    my ($run) = @_;
    my $device = $run->{device};
    if ($run->{startup} eq 'init') {
        check($run, 'records initialized before interrupt acceptance',
            read_prefix($run, 'ENUMINIT', 15) eq 'ENUMINIT 0' && !$device->{connections},
            $device->{connections});
        $device->{online} = 1;
        my $deadline = now() + $RECOVERY_TIMEOUT;
        while (now() < $deadline && !grep { $_->{command} == 0x00 && $_->{reply} } @{$device->{traffic}}) {
            pause($run, 0.02);
        }
        check($run, 'device polling before IOC initialization completes',
            scalar(grep { $_->{command} == 0x00 && $_->{reply} } @{$device->{traffic}}), $device->{traffic});
        print {$run->{input}} "GO\n" or die "IOC input write: $!\n";
        check($run, 'connected while enum callbacks are disabled',
            read_prefix($run, 'ENUMCONNECTED') eq 'ENUMCONNECTED 1 0', 'interruptAccept=0');
    }
    read_prefix($run, 'READY', 15);
    if ($run->{case} =~ /-offline\z/) {
        check($run, 'enum startup is disconnected',
            command($run, 'CONNECTED', 'CONNECTED') eq 'CONNECTED 0' && !$device->{connections},
            $device->{connections});
        $device->{online} = 1;
    }
    wait_connected($run, 1);
    verify_enums($run, 'startup');
    for my $cycle (1 .. 2) {
        my $fault_count = @{$device->{faults}};
        $device->{fault} = [0x00, 'eof'];
        wait_connected($run, 0);
        check($run, "enum cycle $cycle transport fault", !defined($device->{fault})
            && @{$device->{faults}} == $fault_count + 1 && $device->{faults}[-1][0] == 0x00,
            $device->{faults}[-1]);
        $device->{online} = 1;
        wait_connected($run, 1);
        verify_enums($run, "reconnect $cycle");
    }
    check($run, 'enum fixture commands supported', !@{$device->{errors}}, $device->{errors});
    print {$run->{input}} "QUIT\n" or die "IOC input write: $!\n";
    wait_exit($run, $EXIT_TIMEOUT) or die "IOC exit deadline exceeded\n";
    check($run, 'IOC exits normally', $run->{ioc_exit} == 0, $run->{ioc_exit});
    return;
}

sub analog_snapshot {
    my ($run, $address) = @_;
    my @values = split /\s+/, command($run, "ANALOG $address TEST:A$address", 'ANALOG');
    shift @values;
    die "malformed analog snapshot\n" unless @values == @ANALOG_FIELDS;
    for my $value (@values) { die "non-numeric analog snapshot: $value\n" unless looks_like_number($value); }
    my %observed;
    @observed{@ANALOG_FIELDS} = map { 0 + $_ } @values;
    return \%observed;
}

sub put_analog {
    my ($run, $address, $field, $value) = @_;
    my $request = "PUT TEST:A$address.$field $value";
    my $result = command($run, $request);
    # Process-passive fields may return device-support failure after the write.
    my ($status, $actual) = $result =~ /\ARESULT (0|-1|-2) (\S+)\z/;
    my $accepted = defined $status && looks_like_number($actual)
        && ($field eq 'PROC' || near($actual, $value));
    check($run, $request, $accepted, $result);
    return;
}

sub near {
    my ($actual, $expected) = @_;
    return abs($actual - $expected) <= $ANALOG_TOLERANCE;
}

sub verify_coefficients {
    my ($run, $address, $phase, $observed, $low, $high) = @_;
    check($run, "$phase A$address confirmed model bounds", !$observed->{bounds_status}
        && $observed->{low} == $low && $observed->{high} == $high, $observed);
    my $slope = ($observed->{eguf} - $observed->{egul}) / ($high - $low);
    my $offset = ($high * $observed->{egul} - $low * $observed->{eguf}) / ($high - $low);
    check($run, "$phase A$address conversion coefficients", near($observed->{slope}, $slope)
        && near($observed->{offset}, $offset), $observed);
    return ($slope, $offset);
}

sub wait_analog {
    my ($run, $address, $raw, $after, $process) = @_;
    my $deadline = now() + $RECOVERY_TIMEOUT;
    my $observed;
    while (now() < $deadline) {
        command($run, "PUT TEST:A$address.PROC 1") if $process;
        $observed = analog_snapshot($run, $address);
        return $observed if !$observed->{bounds_status} && !$observed->{udf}
            && !$observed->{severity} && !$observed->{pact} && $observed->{raw} == $raw
            && (!defined $after || $observed->{timestamp} > $after);
        pause($run, 0.05);
    }
    die 'deadline exceeded waiting for analog sample: ' . $JSON->encode($observed) . "\n";
}

sub verify_raw_values {
    my ($run, $phase) = @_;
    for my $raw (32768, 0, 65535) {
        my @previous = map { analog_snapshot($run, $_)->{timestamp} } (0, 1);
        my $start = scalar @{$run->{device}{traffic}};
        $run->{device}{analog_raw} = {0 => $raw, 1 => $raw};
        for my $address (0, 1) {
            my $observed = wait_analog($run, $address, $raw, $previous[$address]);
            my @fresh = grep {
                $_->{command} == 0x10 && $_->{reply}
                && hex(substr($_->{payload}, 0, 2)) % 8 == $address
                && substr($_->{reply}, 12, 4) eq unpack('H*', pack('v', $raw))
            } @{$run->{device}{traffic}}[$start .. $#{$run->{device}{traffic}}];
            check($run, "$phase A$address raw $raw reached device path", scalar @fresh, \@fresh);
            my $expected = $observed->{egul} + $raw * ($observed->{eguf} - $observed->{egul}) / 65535;
            check($run, "$phase A$address raw $raw engineering value",
                near($observed->{value}, $expected), $observed);
            verify_coefficients($run, $address, "$phase raw $raw", $observed, 0, 65535);
        }
    }
    return;
}

sub configure_analog {
    my ($run) = @_;
    for my $address (0 .. 2) {
        for my $setting (['Range', 'ANALOG_IN_RANGE', '+= 10V'], ['Type', 'ANALOG_IN_TYPE', 'Volts']) {
            my ($suffix, $parameter, $label) = @$setting;
            my $record = "TEST:A$address$suffix";
            my $deadline = now() + $RECOVERY_TIMEOUT;
            while (1) {
                my $snapshot = enum_snapshot($run, $address, $parameter, $record);
                last if !$snapshot->{status} && !$snapshot->{error}
                    && $snapshot->{record}[0][0] eq $label && $snapshot->{record}[0][1] == 1;
                die "$record enum delivery deadline exceeded\n" if now() >= $deadline;
                pause($run, 0.05);
            }
            my $result = command($run, "ENUMSET $record 0");
            check($run, "$record configuration accepted", $result eq 'RESULT 0', $result);
            $deadline = now() + $RECOVERY_TIMEOUT;
            while (1) {
                $result = command($run, "ENUMVALUE $address $parameter $record", 'ENUMVALUE');
                last if $result eq 'ENUMVALUE 0 1 1 0 0 1';
                die "$record configuration deadline exceeded: $result\n" if now() >= $deadline;
                pause($run, 0.05);
            }
            check($run, "$record configuration confirmed", 1, $result);
        }
    }
    return;
}

sub exercise_bounds {
    my ($run) = @_;
    my $device = $run->{device};
    read_prefix($run, 'READY', 15);
    if ($run->{startup} eq 'offline') {
        check($run, 'bounds startup is disconnected',
            command($run, 'CONNECTED', 'CONNECTED') eq 'CONNECTED 0' && !$device->{connections},
            $device->{connections});
        put_analog($run, 2, 'PROC', 1);
        my $offline = analog_snapshot($run, 2);
        check($run, 'offline bounds do not validate input', $offline->{udf} && $offline->{severity} == 3, $offline);
        $device->{online} = 1;
    }
    wait_connected($run, 1);
    if ($run->{model} eq 'tc32') {
        for my $phase ('startup', 'changed limits') {
            for my $address (0, 2) {
                if ($phase eq 'changed limits') {
                    put_analog($run, $address, 'EGUL', -2);
                    put_analog($run, $address, 'EGUF', 3);
                }
                put_analog($run, $address, 'PROC', 1);
                my $observed = analog_snapshot($run, $address);
                verify_coefficients($run, $address, $phase, $observed, 0, 16777215);
                check($run, "$phase A$address metadata does not validate a sample",
                    $observed->{udf} && $observed->{severity} == 3, $observed);
            }
        }
    } else {
        configure_analog($run);
        verify_raw_values($run, 'startup');
        for my $address (0, 1) {
            put_analog($run, $address, 'EGUL', 2);
            put_analog($run, $address, 'EGUF', 7);
        }
        verify_raw_values($run, 'changed limits');

        put_analog($run, 1, 'SVAL', 2);
        $device->{analog_raw}{1} = [1000, 3000];
        $device->{analog_index}{1} = 0;
        my $average = wait_analog($run, 1, 2000);
        check($run, 'I/O Intr retains two-sample averaging',
            near($average->{value}, 2 + 2000 * 5 / 65535), $average);
        $device->{analog_raw}{1} = 32768;

        put_analog($run, 0, 'LINR', 1);
        put_analog($run, 0, 'ESLO', 2);
        put_analog($run, 0, 'EOFF', 3);
        $device->{analog_raw}{0} = 1000;
        my $manual = wait_analog($run, 0, 1000);
        check($run, 'manual SLOPE conversion remains unchanged',
            $manual->{slope} == 2 && $manual->{offset} == 3 && $manual->{value} == 2003, $manual);
        put_analog($run, 0, 'LINR', 2);

        my $fault_count = @{$device->{faults}};
        $device->{fault} = [0x10, 'eof'];
        wait_connected($run, 0);
        check($run, 'analog EOF reached transport', !defined($device->{fault})
            && @{$device->{faults}} == $fault_count + 1 && $device->{faults}[-1][0] == 0x10,
            $device->{faults}[-1]);
        put_analog($run, 0, 'PROC', 1);
        my $disconnected = analog_snapshot($run, 0);
        check($run, 'analog input is invalid after transport failure',
            $disconnected->{severity} == 3, $disconnected);
        $device->{online} = 1;
        wait_connected($run, 1);
        verify_raw_values($run, 'reconnect');

        my $passive = wait_analog($run, 2, 32768, undef, 1);
        check($run, 'passive input has a valid sample before no-sample check',
            near($passive->{value}, -10 + 32768 * 20 / 65535), $passive);
        check($run, 'disable polling for no-sample check', command($run, 'ENABLE 0') eq 'RESULT 0', 'ENABLE 0');
        my $requests = $device->{requests};
        pause($run, 0.25);
        check($run, 'polling stopped before no-sample check', $requests == $device->{requests}, $device->{requests});
        put_analog($run, 2, 'PROC', 1);
        my $before = analog_snapshot($run, 2);
        put_analog($run, 2, 'PROC', 1);
        my $empty = analog_snapshot($run, 2);
        check($run, 'no new sample preserves value and marks invalid',
            $empty->{udf} && $empty->{severity} == 3 && $empty->{value} == $before->{value}, $empty);
    }
    check($run, 'bounds fixture commands supported', !@{$device->{errors}}, $device->{errors});
    print {$run->{input}} "QUIT\n" or die "IOC input write: $!\n";
    wait_exit($run, $EXIT_TIMEOUT) or die "IOC exit deadline exceeded\n";
    check($run, 'IOC exits normally', $run->{ioc_exit} == 0, $run->{ioc_exit});
    return;
}

sub mac_text {
    my ($mac) = @_;
    return join(':', map { sprintf('%02X', ord($_)) } split(//, $mac));
}

sub setup_mac {
    my ($run) = @_;
    $run->{device} = TC32->new(undef, undef, {broadcast => 1, mac => $MAC_A});
    $run->{device_id} = mac_text($MAC_A);
    return unless $run->{case} eq 'mac-two-ports' || $run->{case} eq 'mac-known-absent';
    $run->{device}{online} = 1;
    $run->{device2} = TC32->new('192.0.2.3', undef, {broadcast => 1, mac => $MAC_B});
    $run->{device2}{temperature} = 37.25;
    # The second device is selected by a lower-case MAC; the driver must match it to the upper-case
    # MAC the vendor library reports.
    $run->{second_id} = lc mac_text($MAC_B);
    return;
}

sub broadcast_times {
    my ($device) = @_;
    return map { $_->{time} } grep { $_->{source} eq 'broadcast' } @{$device->{discovery_requests}};
}

sub spaced {
    my (@times) = @_;
    for my $index (1 .. $#times) {
        return 0 if $times[$index] - $times[$index - 1] < $REFRESH_INTERVAL - $INTERVAL_TOLERANCE;
    }
    return 1;
}

# Longest stretch without a request from the device between two monotonic times, counting the
# edges of the interval, so a port that stops polling is not hidden by a few early requests.
sub max_gap {
    my ($device, $from, $to) = @_;
    my @times = grep { $_ >= $from && $_ <= $to } map { $_->{time} } @{$device->{traffic}};
    my ($previous, $largest) = ($from, 0);
    for my $time (@times, $to) {
        $largest = $time - $previous if $time - $previous > $largest;
        $previous = $time;
    }
    return $largest;
}

sub inventory {
    my ($run) = @_;
    print {$run->{input}} "SHOW\n" or die "IOC input write: $!\n";
    my @lines;
    my $deadline = now() + $READ_TIMEOUT;
    while (now() < $deadline) {
        while (@{$run->{lines}}) {
            my $line = shift @{$run->{lines}};
            if ($line eq 'SHOWEND') {
                my ($count) = map { /\AmeasCompShowDevices, numDevices=(\d+)\z/ ? $1 : () } @lines;
                my @identifiers = map { /\AUniqueID: (\S+)\z/ ? $1 : () } map { s/\A\s+//r } @lines;
                my @reserved = map { /\AReserved: (\S*)\z/ ? $1 : () } map { s/\A\s+//r } @lines;
                die "malformed inventory listing\n" unless defined $count;
                return {count => 0 + $count, identifiers => \@identifiers, reserved => \@reserved};
            }
            push @lines, $line;
        }
        die "IOC output closed before SHOWEND\n" if $run->{eof};
        pump($run, 0.02);
    }
    die "deadline exceeded waiting for SHOWEND\n";
}

sub state_b {
    my ($run) = @_;
    my @values = split /\s+/, command($run, 'STATEB', 'STATEB');
    shift @values;
    die "malformed second port state\n" unless @values == 5;
    for my $value (@values) { die "non-numeric second port state: $value\n" unless looks_like_number($value); }
    my %state;
    @state{qw(connected pact udf severity value)} = map { 0 + $_ } @values;
    return \%state;
}

# Waits for the second port to report the expected value. With $lenient the last observed state is
# returned at the deadline, so a case can assert the value by name instead of dying.
sub wait_b {
    my ($run, $value, $lenient) = @_;
    my $deadline = now() + $RECOVERY_TIMEOUT;
    my $observed;
    while (now() < $deadline) {
        $observed = state_b($run);
        return $observed if $observed->{connected} == 1 && $observed->{severity} == 0
            && $observed->{udf} == 0 && abs($observed->{value} - $value) < 0.001;
        pause($run, 0.1);
    }
    return $observed if $lenient;
    die 'deadline exceeded waiting for second port; last state=' . $JSON->encode($observed) . "\n";
}

sub exercise_mac {
    my ($run) = @_;
    my $device = $run->{device};
    read_prefix($run, 'READY');
    if ($run->{case} eq 'mac-tc32-offline') {
        my $initial = state($run);
        check($run, 'mac startup is disconnected', $initial->{connected} == 0
            && $initial->{severity} == 3 && !$device->{connections}, $initial);
        pause($run, $ABSENT_WINDOW);
        my @times = broadcast_times($device);
        my $absent = state($run);
        check($run, 'mac port stays disconnected while absent', $absent->{connected} == 0
            && $absent->{severity} == 3 && !$device->{connections}, $absent);
        $device->{online} = 1;
        my $enabled = now();
        my $state = healthy($run, 22.5);
        my $elapsed = now() - $enabled;
        check($run, 'mac device connects after becoming available', $elapsed < $RECOVERY_TIMEOUT
            && $device->{connections} == 1, {seconds => $elapsed, state => $state});
        check($run, 'mac rediscovery requests while absent', @times >= 2 && @times <= 3 && spaced(@times), \@times);
    } else {
        my $state = healthy($run, 22.5);
        my @times = broadcast_times($device);
        check($run, 'mac online startup uses one discovery request', @times == 1, \@times);
        pause($run, $RECONNECT_DELAY + 1);
        @times = broadcast_times($device);
        check($run, 'mac connected port sends no further discovery', @times == 1, \@times);
        $device->{fault} = [0x12, 'eof'];
        wait_for($run, sub { my ($s) = @_; return $s->{connected} == 0 && $s->{severity} == 3; });
        check($run, 'mac EOF reached transport', !defined($device->{fault})
            && $device->{faults}[-1][1] eq 'eof', $device->{faults}[-1]);
        $device->{online} = 1;
        healthy($run, 22.5);
        @times = broadcast_times($device);
        check($run, 'mac EOF recovery reconnects without discovery', @times == 1, \@times);

        check($run, 'mac disable autoconnect', command($run, 'AUTO 0') eq 'RESULT 0', 'AUTO 0');
        $device->{fault} = [0x00, 'eof'];
        wait_for($run, sub { my ($s) = @_; return $s->{connected} == 0 && $s->{severity} == 3; });
        my $connections = $device->{connections};
        my $unchanged = 1;
        my $deadline = now() + $POLICY_WINDOW;
        while (now() < $deadline) {
            $unchanged = 0 if state($run)->{connected};
            pause($run, 0.1);
        }
        @times = broadcast_times($device);
        check($run, 'mac autoconnect off prevents discovery and connection', $unchanged
            && $device->{connections} == $connections && @times == 1,
            {connections => $device->{connections}, discovery => \@times});
        check($run, 'mac enable autoconnect', command($run, 'AUTO 1') eq 'RESULT 0', 'AUTO 1');
        $device->{online} = 1;
        healthy($run, 22.5);
        @times = broadcast_times($device);
        check($run, 'mac autoconnect recovery reconnects without discovery', @times == 1, \@times);

        $device->{fault} = [0x00, 'eof'];
        wait_for($run, sub { my ($s) = @_; return $s->{connected} == 0 && $s->{severity} == 3; });
        check($run, 'mac disable port', command($run, 'ENABLE 0') eq 'RESULT 0', 'ENABLE 0');
        $connections = $device->{connections};
        $unchanged = 1;
        $deadline = now() + $POLICY_WINDOW;
        while (now() < $deadline) {
            $unchanged = 0 if state($run)->{connected};
            pause($run, 0.1);
        }
        @times = broadcast_times($device);
        check($run, 'mac disabled port prevents discovery and connection', $unchanged
            && $device->{connections} == $connections && @times == 1,
            {connections => $device->{connections}, discovery => \@times});
        check($run, 'mac enable port', command($run, 'ENABLE 1') eq 'RESULT 0', 'ENABLE 1');
        $device->{online} = 1;
        healthy($run, 22.5);
        @times = broadcast_times($device);
        check($run, 'mac enabled port reconnects without discovery', @times == 1, \@times);
    }
    check($run, 'mac fixture commands supported', !@{$device->{errors}}, $device->{errors});
    print {$run->{input}} "QUIT\n" or die "IOC input write: $!\n";
    wait_exit($run, $EXIT_TIMEOUT) or die "IOC exit deadline exceeded\n";
    check($run, 'mac IOC exits normally', $run->{ioc_exit} == 0, $run->{ioc_exit});
    return;
}

sub exercise_mac_two {
    my ($run) = @_;
    my $first = $run->{device};
    my $second = $run->{device2};
    read_prefix($run, 'READY');
    healthy($run, 22.5);
    my $polling_from = now();
    my $absent = state_b($run);
    check($run, 'mac second port is absent and invalid', $absent->{connected} == 0
        && $absent->{severity} == 3 && !$second->{connections}, $absent);
    pause($run, $ABSENT_WINDOW);
    my @first_times = broadcast_times($first);
    my @second_times = broadcast_times($second);
    my $connections = $first->{connections};
    $second->{online} = 1;
    my $enabled = now();
    my $second_state = wait_b($run, 37.25);
    my $elapsed = now() - $enabled;
    check($run, 'mac second device connects with its own value', $elapsed < $REDISCOVERY_LIMIT
        && $second->{connections} == 1, {seconds => $elapsed, state => $second_state});
    check($run, 'mac absent port shares bounded discovery', @first_times >= 2 && @first_times <= 3
        && spaced(@first_times) && @second_times == @first_times,
        {first => \@first_times, second => \@second_times});
    my $requests = $first->{requests};
    pause($run, 2);
    my $gap = max_gap($first, $polling_from, now());
    my $first_state = state($run);
    check($run, 'mac first port keeps its connection', $first->{connections} == $connections
        && $connections == 1 && $first_state->{connected} == 1 && $first_state->{severity} == 0
        && abs($first_state->{value} - 22.5) < 0.001, {connections => $first->{connections}, state => $first_state});
    check($run, 'mac first port continues polling', $first->{requests} > $requests && $gap < $POLL_GAP_LIMIT,
        {before => $requests, after => $first->{requests}, longest_gap => $gap});
    my $listing = inventory($run);
    my %distinct = map { $_ => 1 } @{$listing->{identifiers}};
    check($run, 'mac inventory has two distinct devices', $listing->{count} == 2
        && @{$listing->{identifiers}} == 2 && keys(%distinct) == 2
        && $distinct{mac_text($MAC_A)} && $distinct{mac_text($MAC_B)}, $listing);
    check($run, 'mac fixture commands supported', !@{$first->{errors}} && !@{$second->{errors}},
        {first => $first->{errors}, second => $second->{errors}});
    print {$run->{input}} "QUIT\n" or die "IOC input write: $!\n";
    wait_exit($run, $EXIT_TIMEOUT) or die "IOC exit deadline exceeded\n";
    check($run, 'mac IOC exits normally', $run->{ioc_exit} == 0, $run->{ioc_exit});
    return;
}

sub exercise_mac_known {
    my ($run) = @_;
    my $first = $run->{device};
    my $second = $run->{device2};
    read_prefix($run, 'READY');
    healthy($run, 22.5);
    $first->{fault} = [0x12, 'eof'];
    wait_for($run, sub { my ($s) = @_; return $s->{connected} == 0 && $s->{severity} == 3; });
    check($run, 'mac known device is absent', !defined($first->{fault}) && !$first->{online},
        $first->{faults}[-1]);
    my $connections = $first->{connections};
    $second->{online} = 1;
    my $enabled = now();
    my $second_state = wait_b($run, 37.25);
    my $elapsed = now() - $enabled;
    check($run, 'mac second device connects while the first is absent', $elapsed < $RECOVERY_TIMEOUT
        && $second->{connections} == 1, {seconds => $elapsed, state => $second_state});
    my $listing = inventory($run);
    my %distinct = map { $_ => 1 } @{$listing->{identifiers}};
    check($run, 'mac inventory keeps the absent known device', $listing->{count} == 2
        && @{$listing->{identifiers}} == 2 && keys(%distinct) == 2
        && $distinct{mac_text($MAC_A)} && $distinct{mac_text($MAC_B)}, $listing);
    my @times = broadcast_times($first);
    $first->{online} = 1;
    my $first_state = healthy($run, 22.5);
    my @after = broadcast_times($first);
    check($run, 'mac known device reconnects from its inventory entry', $first->{connections} > $connections
        && @after == @times, {connections => $first->{connections}, state => $first_state,
        discovery_before => \@times, discovery_after => \@after});
    my $second_after = state_b($run);
    check($run, 'mac second port keeps its connection', $second->{connections} == 1
        && $second_after->{connected} == 1 && $second_after->{severity} == 0
        && abs($second_after->{value} - 37.25) < 0.001, $second_after);
    check($run, 'mac fixture commands supported', !@{$first->{errors}} && !@{$second->{errors}},
        {first => $first->{errors}, second => $second->{errors}});
    print {$run->{input}} "QUIT\n" or die "IOC input write: $!\n";
    wait_exit($run, $EXIT_TIMEOUT) or die "IOC exit deadline exceeded\n";
    check($run, 'mac IOC exits normally', $run->{ioc_exit} == 0, $run->{ioc_exit});
    return;
}

# Endpoint cases select devices by IP address, discovery port, hostname or MAC. Each case names
# the first fixture's address and port, whether it answers broadcast discovery, the IOC's selector
# for it, and optionally the second fixture and its selector.
sub setup_endpoint {
    my ($run) = @_;
    my %layout = (
        'endpoint-same-ip'      => ['192.0.2.2', undef, 0, '192.0.2.2', ['192.0.2.2', $ALT_DISCOVERY_PORT, "192.0.2.2:$ALT_DISCOVERY_PORT"]],
        'endpoint-mixed'        => ['192.0.2.2', undef, 1, mac_text($MAC_A), ['192.0.2.2', $ALT_DISCOVERY_PORT, "192.0.2.2:$ALT_DISCOVERY_PORT"]],
        'endpoint-distinct-ip'  => ['192.0.2.2', undef, 0, '192.0.2.2', ['192.0.2.3', undef, '192.0.2.3']],
        'endpoint-default-port' => ['192.0.2.2', undef, 1, '192.0.2.2:54211', undef],
        'endpoint-alt-port'     => ['192.0.2.2', $ALT_DISCOVERY_PORT, 0, "192.0.2.2:$ALT_DISCOVERY_PORT", undef],
        'endpoint-hostname'     => ['192.0.2.2', undef, 0, $FIXTURE_HOSTNAME, undef],
        'endpoint-hostname-port' => ['192.0.2.2', $ALT_DISCOVERY_PORT, 0, "$FIXTURE_HOSTNAME:$ALT_DISCOVERY_PORT", undef],
        'endpoint-wrong-port'   => ['192.0.2.2', undef, 0, "192.0.2.2:$UNUSED_DISCOVERY_PORT", undef],
    );
    my ($address, $port, $broadcast, $selector, $second) = @{$layout{$run->{case}}};
    $run->{device} = TC32->new($address, $port, {broadcast => $broadcast, mac => $MAC_A});
    $run->{device}{online} = 1;
    $run->{device_id} = $selector;
    return unless $second;
    my ($address2, $port2, $selector2) = @$second;
    $run->{device2} = TC32->new($address2, $port2, {mac => $MAC_B});
    $run->{device2}{online} = 1;
    $run->{device2}{temperature} = 37.25;
    $run->{second_id} = $selector2;
    return;
}

sub exercise_endpoint {
    my ($run) = @_;
    my $first = $run->{device};
    my $second = $run->{device2};
    read_prefix($run, 'READY');
    if ($run->{case} eq 'endpoint-wrong-port') {
        # A selector with a discovery port nobody listens on must find nothing: the direct query
        # times out, the port keeps retrying as for an absent device, and the inventory stays empty.
        pause($run, $RECOVERY_TIMEOUT);
        my $absent = state($run);
        my $listing = inventory($run);
        check($run, 'endpoint wrong port finds no device', $absent->{connected} == 0 && $absent->{severity} == 3
            && !$first->{connections} && $listing->{count} == 0,
            {state => $absent, connections => $first->{connections}, inventory => $listing});
        check($run, 'endpoint fixture commands supported', !@{$first->{errors}}, $first->{errors});
        print {$run->{input}} "QUIT\n" or die "IOC input write: $!\n";
        wait_exit($run, $EXIT_TIMEOUT) or die "IOC exit deadline exceeded\n";
        check($run, 'endpoint IOC exits normally', $run->{ioc_exit} == 0, $run->{ioc_exit});
        return;
    }
    my $healthy_from = now();
    my $first_state = healthy($run, 22.5);
    check($run, 'endpoint first port reads its device', abs($first_state->{value} - 22.5) < 0.001
        && $first_state->{severity} == 0, $first_state);
    if ($second) {
        my $second_state = wait_b($run, 37.25, 1);
        check($run, 'endpoint second port reads its device', abs($second_state->{value} - 37.25) < 0.001
            && $second_state->{severity} == 0 && $second->{connections} == 1,
            {state => $second_state, connections => $second->{connections},
             first_connections => $first->{connections}});
        pause($run, 2);
        my $gap = max_gap($first, $healthy_from, now());
        my $again = state($run);
        check($run, 'endpoint first port keeps its single connection', $first->{connections} == 1
            && $again->{connected} == 1 && abs($again->{value} - 22.5) < 0.001 && $gap < $POLL_GAP_LIMIT,
            {connections => $first->{connections}, state => $again, longest_gap => $gap});
    } else {
        pause($run, 2);
        check($run, 'endpoint single port keeps its single connection', $first->{connections} == 1,
            {connections => $first->{connections}});
    }
    my $listing = inventory($run);
    my %distinct = map { $_ => 1 } @{$listing->{identifiers}};
    my $expected = $second ? 2 : 1;
    check($run, "endpoint inventory has $expected distinct device" . ($expected == 1 ? '' : 's'),
        $listing->{count} == $expected && @{$listing->{identifiers}} == $expected && keys(%distinct) == $expected
        && $distinct{mac_text($MAC_A)} && ($expected == 1 || $distinct{mac_text($MAC_B)}), $listing);
    if ($run->{case} =~ /\Aendpoint-hostname/) {
        check($run, 'endpoint hostname resolves to the device address', @{$listing->{reserved}} == 1
            && $listing->{reserved}[0] eq $first->{address}, $listing);
    }
    if ($first->{broadcast}) {
        # A device found by the startup broadcast must be matched in the inventory, so the only
        # addressed discovery request it receives is the vendor library's MAC check at connection.
        my @times = broadcast_times($first);
        my @unicast = grep { $_->{source} eq 'unicast' } @{$first->{discovery_requests}};
        check($run, 'endpoint broadcast-discovered device is not queried again', @times == 1 && @unicast == 1,
            {broadcast => \@times, unicast => scalar @unicast});
    }
    check($run, 'endpoint fixture commands supported', !@{$first->{errors}} && (!$second || !@{$second->{errors}}),
        {first => $first->{errors}, second => $second ? $second->{errors} : []});
    print {$run->{input}} "QUIT\n" or die "IOC input write: $!\n";
    wait_exit($run, $EXIT_TIMEOUT) or die "IOC exit deadline exceeded\n";
    check($run, 'endpoint IOC exits normally', $run->{ioc_exit} == 0, $run->{ioc_exit});
    return;
}

sub digital_window {
    my ($run) = @_;
    my $device = $run->{device};
    check($run, 'set digital observation interval',
        command($run, "POLL $DIGITAL_POLL_MS") eq 'RESULT 0', $DIGITAL_POLL_MS);
    my $cursor = @{$device->{traffic}};
    my $deadline = now() + $RECOVERY_TIMEOUT;
    while (now() < $deadline) {
        pump($run, 0.02);
        while ($cursor < @{$device->{traffic}}) {
            my $request = $device->{traffic}[$cursor++];
            next unless $request->{command} == 0x12;
            my (undef, undef, $channels) = unpack('CCV', pack('H*', $request->{payload}));
            next unless $channels == 0x80000000;
            my $observed = state($run);
            check($run, 'digital observation starts after a healthy poll',
                $observed->{connected} == 1 && $observed->{severity} == 0
                && $observed->{severity31} == 0 && $observed->{digital_severity} == 0
                && $observed->{digital_value} == 1, {state => $observed, request => $request});
            return {time => $request->{time}, cursor => scalar @{$device->{traffic}}, state => $observed};
        }
    }
    die "digital observation poll deadline exceeded\n";
}

sub digital_observation {
    my ($run, $window) = @_;
    my $observed = state($run);
    my $deadline = now() + 1;
    while (!$observed->{connected} && now() < $deadline
        && ($observed->{severity} != 3 || $observed->{severity31} != 3
            || $observed->{digital_severity} != 3)) {
        pause($run, 0.01);
        $observed = state($run);
    }
    my @traffic = @{$run->{device}{traffic}}[$window->{cursor} .. $#{$run->{device}{traffic}}];
    my $elapsed = now() - $window->{time};
    check($run, 'digital failure observed before another poll',
        $elapsed < $DIGITAL_POLL_MS / 1000
        && !grep({ $_->{command} == 0x00 || $_->{command} == 0x12 } @traffic),
        {elapsed => $elapsed, requests => \@traffic, state => $observed});
    return ($observed, \@traffic);
}

sub digital_policy {
    my ($run) = @_;
    my $device = $run->{device};
    my $connections = $device->{connections};
    $device->{online} = 1;
    my $deadline = now() + $POLICY_WINDOW;
    my $unchanged = 1;
    while (now() < $deadline) {
        my $observed = state($run);
        $unchanged = 0 if $observed->{connected};
        pause($run, 0.1);
    }
    check($run, 'digital autoconnect off prevents recovery',
        $unchanged && $device->{connections} == $connections,
        {seconds => $POLICY_WINDOW, connections => $device->{connections}});
    check($run, 'digital disable port', command($run, 'ENABLE 0') eq 'RESULT 0', 'ENABLE 0');
    check($run, 'digital enable autoconnect', command($run, 'AUTO 1') eq 'RESULT 0', 'AUTO 1');
    $deadline = now() + $POLICY_WINDOW;
    $unchanged = 1;
    while (now() < $deadline) {
        my $observed = state($run);
        $unchanged = 0 if $observed->{connected};
        pause($run, 0.1);
    }
    my $requests = $device->{requests};
    my $result = command($run, 'DOUT 3 ffffffff');
    check($run, 'digital disabled port prevents recovery and writes',
        $unchanged && $device->{connections} == $connections
        && $result eq 'RESULT 5' && $device->{requests} == $requests,
        {seconds => $POLICY_WINDOW, result => $result, connections => $device->{connections},
         requests_before => $requests, requests_after => $device->{requests}});
    check($run, 'digital enable port', command($run, 'ENABLE 1') eq 'RESULT 0', 'ENABLE 1');
    return;
}

sub exercise_digital {
    my ($run) = @_;
    my $device = $run->{device};
    read_prefix($run, 'READY');
    my $initial = state($run);
    check($run, 'digital offline startup', $initial->{connected} == 0, $initial);
    $device->{online} = 1;
    healthy($run, $device->{temperature});
    check($run, 'digital output direction', command($run, 'DIR ffffffff ffffffff') eq 'RESULT 0',
        $device->{digital_out});
    my $cursor = @{$device->{traffic}};
    my $result = command($run, 'DOUT a5a5a5a5 ffffffff');
    my @writes = grep { $_->{command} == 0x03 }
        @{$device->{traffic}}[$cursor .. $#{$device->{traffic}}];
    check($run, 'digital full-port write reaches device', $result eq 'RESULT 0'
        && @writes == 1 && $writes[0]{payload} eq '01a5a5a5a5'
        && $device->{digital_out}[0] == 0xa5a5a5a5, {result => $result, requests => \@writes});

    my $case = $run->{case};
    if ($case eq 'digital-policy' || $case eq 'digital-bits') {
        check($run, 'digital disable autoconnect', command($run, 'AUTO 0') eq 'RESULT 0', 'AUTO 0');
    }
    my $window = digital_window($run);
    my $mode = $case eq 'digital-control' ? 'bad-size' : $case eq 'digital-bits' ? 'drop' : 'eof';
    my $faults = @{$device->{faults}};
    $device->{fault} = [0x03, $mode];
    my $started = now();
    $result = command($run, $case eq 'digital-bits' ? 'DOUT 3 3' : 'DOUT 3 ffffffff');
    my $duration = now() - $started;
    my ($observed, $traffic) = digital_observation($run, $window);
    check($run, 'digital fault reaches selected write', !defined($device->{fault})
        && @{$device->{faults}} == $faults + 1 && $device->{faults}[-1][0] == 0x03
        && $device->{faults}[-1][1] eq $mode,
        {fault => $device->{faults}[-1], duration => $duration, result => $result});

    if ($case eq 'digital-control') {
        my ($fault) = grep { ($_->{fault} // '') eq 'bad-size' } @$traffic;
        my $reply = pack('H*', $fault->{reply});
        my ($start, $code, $frame, $status, $length) = unpack('CCCCv', $reply);
        check($run, 'digital non-transport response is complete', length($reply) == 8
            && $start == 0xdb && $code == 0x83 && $frame == $fault->{frame}
            && $status == 0 && $length == 1 && unpack('%32C*', $reply) % 256 == 255, $fault);
        check($run, 'digital non-transport error keeps connection', $result eq 'RESULT 3'
            && $observed->{connected} == 1 && $observed->{severity} == 0
            && $observed->{digital_severity} == 0
            && scalar(grep { /writeUInt32Digital.*err=9\b/ } @{$run->{diagnostics}}),
            {result => $result, state => $observed, diagnostics => $run->{diagnostics}});
        $result = command($run, 'DOUT 5 ffffffff');
        check($run, 'digital write succeeds after non-transport error', $result eq 'RESULT 0'
            && $device->{digital_out}[0] == 5, {result => $result, device => $device->{digital_out}});
    } else {
        if ($case eq 'digital-bits') {
            check($run, 'digital bit response timeout reaches driver', $duration >= 3
                && $duration < $DIGITAL_POLL_MS / 1000 && $device->{online}
                && scalar(grep { /writeUInt32Digital.*err=(?:7|103)\b/ } @{$run->{diagnostics}}),
                {duration => $duration, result => $result, requests => $traffic, diagnostics => $run->{diagnostics}});
        }
        my $name = $case eq 'digital-bits' ? 'digital bit write preserves transport error'
                                         : 'digital word error disconnects immediately';
        check($run, $name, $result eq 'RESULT 3' && $observed->{connected} == 0
            && $observed->{severity} == 3 && $observed->{severity31} == 3
            && $observed->{digital_severity} == 3
            && $observed->{value} == $window->{state}{value}
            && $observed->{value31} == $window->{state}{value31}
            && $observed->{digital_value} == $window->{state}{digital_value},
            {result => $result, state => $observed, baseline => $window->{state}, requests => $traffic});
        if ($case eq 'digital-bits') {
            check($run, 'digital bit write stops after first error', @$traffic == 2
                && $traffic->[0]{command} == 0x02 && $traffic->[1]{command} == 0x03, $traffic);
            check($run, 'digital restore autoconnect', command($run, 'AUTO 1') eq 'RESULT 0', 'AUTO 1');
        }
        if ($case eq 'digital-policy') { digital_policy($run); }
        else { $device->{online} = 1; }
        my $recovered = wait_for($run, sub {
            my ($state) = @_;
            return $state->{connected} == 1 && $state->{severity} == 0 && $state->{severity31} == 0
                && $state->{digital_severity} == 0;
        });
        check($run, 'digital recovery restores valid inputs',
            $recovered->{value} == $window->{state}{value}
            && $recovered->{value31} == $window->{state}{value31}
            && $recovered->{digital_value} == $window->{state}{digital_value}, $recovered);
    }
    check($run, 'digital fixture commands supported', !@{$device->{errors}}, $device->{errors});
    print {$run->{input}} "QUIT\n" or die "IOC input write: $!\n";
    wait_exit($run, $EXIT_TIMEOUT) or die "IOC exit deadline exceeded\n";
    check($run, 'digital IOC exits normally', $run->{ioc_exit} == 0, $run->{ioc_exit});
    return;
}

sub wait_exit {
    my ($run, $timeout) = @_;
    my $deadline = now() + $timeout;
    while (now() < $deadline) {
        if (reap($run)) { pump($run, 0); return 1; }
        pump($run, 0.02);
    }
    return reap($run);
}

sub exercise {
    my ($run) = @_;
    my $device = $run->{device};
    read_prefix($run, 'READY');
    my $initial = state($run);
    check($run, 'offline record initialized', $initial->{pact} == 0 && $initial->{connected} == 0
        && $initial->{auto} == 1 && $initial->{severity} == 3, $initial);
    $device->{online} = 1;
    check($run, 'offline startup recovers', 1, healthy($run, 22.5));
    tc_write_failures($run);
    my $result = command($run, 'TC 2');
    check($run, 'TC configuration write', $result eq 'RESULT 0', ord(substr($device->{types}, 0, 1)));
    $result = command($run, 'OTD31 0');
    check($run, 'bank configuration write', $result eq 'RESULT 0', unpack('H*', $device->{measure}));
    $result = command($run, 'OTD 1');
    check($run, 'open detection write', $result eq 'RESULT 0', unpack('H*', $device->{measure}));
    check($run, 'settings reached device', ord(substr($device->{types}, 0, 1)) == 2
        && !(ord(substr($device->{measure}, 0, 1)) & 1),
        {tc => ord(substr($device->{types}, 0, 1)), measurement => unpack('H*', $device->{measure})});

    for my $fault (['eof', 0x12], ['short', 0x00], ['timeout', 0x12]) {
        my ($mode, $command_id) = @$fault;
        my $baseline = state($run);
        $device->{fault} = [$command_id, $mode];
        my $failed = wait_for($run, sub {
            my ($state) = @_;
            return $state->{connected} == 0 && $state->{severity} == 3 && $state->{severity31} == 3;
        });
        check($run, "$mode preserves last valid value",
            abs($failed->{value} - $baseline->{value}) < 0.001
            && abs($failed->{value31} - $baseline->{value31}) < 0.001, $failed);
        check($run, "$mode reached transport", !defined($device->{fault})
            && $device->{faults}[-1][1] eq $mode, $device->{faults}[-1]);
        if ($mode eq 'timeout') {
            my $elapsed = now() - $device->{faults}[-1][2];
            check($run, 'timeout before fixture closes socket', $elapsed >= 3 && $elapsed < 10, $elapsed);
        }
        $device->{types} = chr(1) x 64;
        $device->{measure} = "\x01\x01";
        $device->{temperature} += 1.25;
        $device->{online} = 1;
        check($run, "$mode reconnects", 1, healthy($run, $device->{temperature}));
        check($run, "$mode restores settings", ord(substr($device->{types}, 0, 1)) == 2
            && !(ord(substr($device->{measure}, 0, 1)) & 1),
            {tc => ord(substr($device->{types}, 0, 1)), measurement => unpack('H*', $device->{measure})});
    }

    check($run, 'disable autoconnect', command($run, 'AUTO 0') eq 'RESULT 0', 'AUTO 0');
    $device->{fault} = [0x00, 'eof'];
    wait_for($run, sub { my ($state) = @_; return $state->{connected} == 0 && $state->{severity} == 3; });
    my $connections = $device->{connections};
    $device->{online} = 1;
    my $deadline = now() + 6;
    while (now() < $deadline) {
        my $observed = state($run);
        die "autoconnect disabled but connected\n" if $observed->{connected} != 0;
        pause($run, 0.1);
    }
    check($run, 'autoconnect off prevents retries', $device->{connections} == $connections, $device->{connections});
    check($run, 'enable autoconnect', command($run, 'AUTO 1') eq 'RESULT 0', 'AUTO 1');
    check($run, 'autoconnect on recovers', 1, healthy($run, $device->{temperature}));

    check($run, 'disable port', command($run, 'ENABLE 0') eq 'RESULT 0', 'ENABLE 0');
    $deadline = now() + 3;
    while (now() < $deadline) {
        my $requests = $device->{requests};
        pause($run, 0.1);
        last if $device->{requests} == $requests;
    }
    my $requests = $device->{requests};
    pause($run, 0.5);
    check($run, 'disabled port stops polling', $device->{requests} == $requests, $device->{requests});
    check($run, 'enable port', command($run, 'ENABLE 1') eq 'RESULT 0', 'ENABLE 1');
    $device->{temperature} += 1.25;
    check($run, 'enabled port resumes polling', 1, healthy($run, $device->{temperature}));
    check($run, 'fixture commands supported', !@{$device->{errors}}, $device->{errors});
    print {$run->{input}} "QUIT\n" or die "IOC input write: $!\n";
    wait_exit($run, $EXIT_TIMEOUT) or die "IOC exit deadline exceeded\n";
    check($run, 'IOC exits normally', $run->{ioc_exit} == 0, $run->{ioc_exit});
    return;
}

sub finalize {
    my ($run) = @_;
    if ($run->{pid} && !reap($run)) {
        kill 'TERM', $run->{pid};
        if (!wait_exit($run, $EXIT_TIMEOUT)) {
            kill 'KILL', $run->{pid};
            wait_exit($run, $EXIT_TIMEOUT) or die "IOC could not be reaped\n";
        }
    }
    $run->{device}->close() if $run->{device};
    $run->{device2}->close() if $run->{device2};
    for my $name (qw(input output)) {
        close($run->{$name}) or die "IOC $name: close: $!\n" if $run->{$name};
    }
    my $device = $run->{device};
    my $second = $run->{device2};
    my $evidence = {checks => $run->{checks}, faults => $device ? $device->{faults} : [],
        fixture_errors => $device ? $device->{errors} : [], ioc_exit => $run->{ioc_exit},
        case => $run->{case}, diagnostics => $run->{diagnostics},
        traffic => $device ? $device->{traffic} : [],
        discovery => $device ? $device->{discovery_requests} : []};
    if ($second) {
        $evidence->{second_device} = {faults => $second->{faults}, fixture_errors => $second->{errors},
            traffic => $second->{traffic}, discovery => $second->{discovery_requests}};
    }
    my $path = "$run->{log_path}.json";
    open(my $out, '>:raw', $path) or die "$path: $!\n";
    print {$out} $JSON->pretty->indent_length(2)->encode($evidence) or die "$path: write: $!\n";
    close($out) or die "$path: close: $!\n";
    close($run->{log}) or die "$run->{log_path}: close: $!\n";
    return;
}

sub main {
    my (@args) = @_;
    my $help;
    my $case = 'reconnect';
    Getopt::Long::Configure('no_auto_abbrev', 'no_ignore_case');
    GetOptionsFromArray(\@args, 'help' => \$help, 'case=s' => \$case)
        or pod2usage(-exitval => 2, -verbose => 0);
    pod2usage(-exitval => 0, -verbose => 1) if $help;
    pod2usage(-exitval => 2, -message => "Unknown case: $case") unless $CASES{$case};
    pod2usage(-exitval => 2, -message => 'Expected IOC, DBD, template and log paths') unless @args == 4;
    my ($executable, $dbd, $template, $log_path) = @args;
    my $run = {checks => [], lines => [], diagnostics => [], buffer => '',
        log_path => $log_path, ioc_exit => undef, case => $case};
    open($run->{log}, '>:raw', $log_path) or die "$log_path: $!\n";
    $run->{log}->autoflush(1);
    STDOUT->autoflush(1);
    my $success = eval {
        ($run->{family}, $run->{model}, $run->{startup}) = $case =~ /\A(enum|bounds)-(tc32|e1608)-(online|offline|init)\z/;
        if ($case =~ /\Amac-/) { setup_mac($run); }
        elsif ($case =~ /\Aendpoint-/) { setup_endpoint($run); }
        else { $run->{device} = ($run->{model} // '') eq 'e1608' ? E1608->new() : TC32->new(); }
        $run->{device}{online} = 1 if $case =~ /-online\z/;
        launch_ioc($run, $executable, $dbd, $template);
        if (($run->{family} // '') eq 'bounds') { exercise_bounds($run); }
        elsif ($case eq 'mac-two-ports') { exercise_mac_two($run); }
        elsif ($case eq 'mac-known-absent') { exercise_mac_known($run); }
        elsif ($case =~ /\Aendpoint-/) { exercise_endpoint($run); }
        elsif ($case =~ /\Amac-/) { exercise_mac($run); }
        elsif ($run->{model}) { exercise_enums($run); }
        elsif ($case eq 'reconnect') { exercise($run); }
        else { exercise_digital($run); }
        1;
    };
    my $error = $@;
    eval { finalize($run); 1 } or do { $error .= $@; $success = 0; };
    die $error unless $success;
    return 0;
}

my $status;
local $SIG{PIPE} = 'IGNORE';
local $SIG{INT} = sub { $signal_status = 130; die "interrupted\n"; };
local $SIG{TERM} = sub { $signal_status = 143; die "terminated\n"; };
eval {
    $status = main(@ARGV);
    defined $status or die "internal error: main returned no status\n";
    1;
} or do {
    my $error = $@;
    print STDERR "test_reconnect: $error";
    $status = $signal_status || 1;
};
exit $status;

__END__

=head1 NAME

test_reconnect.pl - Exercise the real IOC through external Ethernet device fixtures

=head1 SYNOPSIS

perl tests/test_reconnect.pl IOC DBD TEMPLATE LOG

=head1 OPTIONS

=over 4

=item --help

Print usage and exit successfully.

=item --case NAME

Select reconnect (default), digital-word, digital-control, digital-policy, digital-bits, enum-tc32-online, enum-tc32-offline, enum-e1608-online, enum-e1608-offline, enum-e1608-init, bounds-tc32-online, bounds-tc32-offline, bounds-e1608-online, bounds-e1608-offline, mac-tc32-online, mac-tc32-offline, mac-two-ports, mac-known-absent, endpoint-same-ip, endpoint-mixed, endpoint-distinct-ip, endpoint-default-port, endpoint-alt-port, endpoint-hostname, endpoint-hostname-port or endpoint-wrong-port. Each invocation creates a fresh IOC and its external fixtures.

Enum cases compare all record enum states with public driver reads and model-specific expected values, write every supported selection through the record, and check RVAL, SDEF, asynchronous completion, alarm severity and public driver readback. They repeat two transport failures and reconnects. The init case holds the real IOC after record initialization, enables device responses, proves connection while interruptAccept is zero, and resumes IOC initialization.

Bounds cases check TC32 24-bit conversion metadata without valid voltage samples, or E-1608 16-bit raw samples through periodic and I/O Intr records. They check engineering-limit changes; E-1608 also checks two-sample averaging, manual SLOPE coefficients, transport recovery and missing-sample alarms. The external fixture supplies raw values; real ULDAQ, driver and device support produce the record values.

MAC cases select each TC32 fixture by MAC address, so the real driver finds it through broadcast discovery. mac-tc32-offline observes the absent device for eleven seconds while the fixture records every broadcast discovery request, then makes it available and requires a valid reading within twelve seconds. The recorded requests must number two or three and be at least 3.9 seconds apart, the four-second minimum refresh interval less a tolerance. mac-tc32-online requires the startup discovery to be the only discovery request through an idle interval, an EOF reconnect, and periods with auto-connect disabled and with the port disabled while the device is absent. mac-two-ports runs a second port, selected by a lower-case MAC with hexadecimal letters and with a different temperature, whose device appears while the first port stays connected and must connect within eight seconds, which a skipped refresh would exceed; the first port must keep its single connection and value, must never go three seconds without a request from the moment it is healthy, and the inventory must list exactly two distinct MAC addresses. mac-known-absent takes the first device offline before the second device appears, then requires the inventory to keep both MAC addresses and the first port to reconnect from its inventory entry without another discovery request.

Endpoint cases select devices by IP address, discovery port, hostname or MAC and require every port to read its own device with a single connection per fixture. endpoint-same-ip runs two fixtures at one IP address on discovery ports 54211 and 54221; endpoint-mixed selects the first of them by MAC through broadcast discovery and the second by IP address and port 54221; endpoint-distinct-ip runs two fixtures at distinct addresses. endpoint-default-port selects a broadcast-discovered device with an explicit default port and requires one inventory entry; endpoint-alt-port runs one fixture on port 54221; endpoint-hostname selects one fixture by a name that the namespace resolves through a bind-mounted hosts file and requires the resolved address in the inventory; endpoint-hostname-port selects a fixture on port 54221 by that name and port. endpoint-wrong-port names a discovery port nobody listens on and requires the port to stay disconnected with an empty inventory.

=back

=head1 ARGUMENTS

IOC is the executable built by build_reconnect.pl; DBD is its generated database definition. TEMPLATE is the shipped measCompTemperatureIn.template for reconnect/digital cases, or measCompAnalogIn.template for enum/bounds cases. The shipped measCompBinaryIn.template, measCompVoltageIn.template and measCompAnalogOut.template must be in the same directory. LOG receives the complete IOC output and LOG.json receives assertion evidence, timestamped device requests, response frames, injected faults, fixture errors and the IOC exit status. Run inside the isolated network namespace described in tests/README.md.

=head1 EXIT STATUS

0 requires every assertion and normal IOC exit. Assertion, runtime or evidence errors return 1. Invalid usage returns 2. INT and TERM return 130 and 143 after terminating and reaping the IOC and retaining evidence.

=cut
