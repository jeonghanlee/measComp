#!/usr/bin/env perl
use strict;
use warnings;

use Errno qw(EINTR);
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

my $JSON = JSON::PP->new->canonical;
my $signal_status = 0;
my @STATE_FIELDS = qw(connected auto enabled pact udf severity value severity31 value31);
my $READ_TIMEOUT = 8;
my $RECOVERY_TIMEOUT = 12;
my $EXIT_TIMEOUT = 5;

sub now {
    return clock_gettime(CLOCK_MONOTONIC);
}

sub launch_ioc {
    my ($run, $executable, $dbd, $template) = @_;
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
            exec { $executable } $executable, $dbd, $template, $run->{device}{address};
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
    $run->{device}->poll($seconds);
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
    for my $name (qw(input output)) {
        close($run->{$name}) or die "IOC $name: close: $!\n" if $run->{$name};
    }
    my $device = $run->{device};
    my $evidence = {checks => $run->{checks}, faults => $device ? $device->{faults} : [],
        fixture_errors => $device ? $device->{errors} : [], ioc_exit => $run->{ioc_exit}};
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
    Getopt::Long::Configure('no_auto_abbrev', 'no_ignore_case');
    GetOptionsFromArray(\@args, 'help' => \$help) or pod2usage(-exitval => 2, -verbose => 0);
    pod2usage(-exitval => 0, -verbose => 1) if $help;
    pod2usage(-exitval => 2, -message => 'Expected IOC, DBD, template and log paths') unless @args == 4;
    my ($executable, $dbd, $template, $log_path) = @args;
    my $run = {checks => [], lines => [], buffer => '', log_path => $log_path, ioc_exit => undef};
    open($run->{log}, '>:raw', $log_path) or die "$log_path: $!\n";
    $run->{log}->autoflush(1);
    STDOUT->autoflush(1);
    my $success = eval {
        $run->{device} = TC32->new();
        launch_ioc($run, $executable, $dbd, $template);
        exercise($run);
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

test_reconnect.pl - Exercise the real IOC through a TC32 network fixture

=head1 SYNOPSIS

perl tests/test_reconnect.pl IOC DBD TEMPLATE LOG

=head1 OPTIONS

=over 4

=item --help

Print usage and exit successfully.

=back

=head1 ARGUMENTS

IOC is the executable built by build_reconnect.pl; DBD is its generated database definition. TEMPLATE is the shipped measCompTemperatureIn.template. LOG receives the complete IOC output and LOG.json receives assertion evidence, injected faults, fixture errors and the IOC exit status. Run inside the isolated network namespace described in tests/README.md.

=head1 EXIT STATUS

0 requires every assertion and normal IOC exit. Assertion, runtime or evidence errors return 1. Invalid usage returns 2. INT and TERM return 130 and 143 after terminating and reaping the IOC and retaining evidence.

=cut
