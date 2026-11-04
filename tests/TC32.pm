package TC32;
use strict;
use warnings;

use Errno qw(EAGAIN EWOULDBLOCK EINTR);
use IO::Select;
use IO::Socket::INET;
use Socket qw(inet_aton SHUT_WR);
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);

my $DEFAULT_ADDRESS = '192.0.2.2';
my $DEFAULT_PORT = 54211;
my $HEADER_LENGTH = 6;
my $TIMEOUT_HOLD = 10;

sub new {
    my ($class, $address, $port) = @_;
    $address //= $DEFAULT_ADDRESS;
    $port //= $DEFAULT_PORT;
    my $udp = IO::Socket::INET->new(LocalAddr => $address, LocalPort => $port, Proto => 'udp')
        or die "$address:$port: UDP bind: $!\n";
    my $tcp = IO::Socket::INET->new(LocalAddr => $address, LocalPort => $port,
        Proto => 'tcp', Listen => 5, ReuseAddr => 1)
        or die "$address:$port: TCP bind: $!\n";
    $udp->blocking(0);
    $tcp->blocking(0);
    return bless {
        address => $address, port => $port, udp => $udp, tcp => $tcp,
        readers => IO::Select->new($udp, $tcp), clients => {},
        online => 0, temperature => 22.5, types => chr(1) x 64, measure => "\0\0",
        fault => undef, faults => [], errors => [], connections => 0, requests => 0,
    }, $class;
}

sub discovery {
    my ($self) = @_;
    return 'D' . pack('a6vva16vvvva4vCa22', "\x02\0\0\0\0\x32", 0x132,
        0x100, 'TC32-TEST       ', $self->{port}, $self->{port} + 1, 0, 0,
        inet_aton($self->{address}), 0x100, 0, "\0" x 22);
}

sub response {
    my ($self, $command, $data) = @_;
    return "\0\0" if $command == 0x52;
    return pack('v6', (0x100) x 6) if $command == 0x53;
    return $self->{types} if $command == 0x14;
    if ($command == 0x15) {
        return $self->reject('invalid TC configuration length') unless length($data) == 64;
        $self->{types} = $data;
        return '';
    }
    return $self->{measure} if $command == 0x18;
    if ($command == 0x19) { $self->{measure} = $data; return ''; }
    return '' if $command == 0x1b;
    return pack('C6', 24, 1, 1, 0, 0, 0) x ($command == 0x3a ? 2 : 4)
        if $command == 0x3a || $command == 0x3c;
    return "\0" x 576 if $command == 0x20;
    return "\0\0" if $command == 0x00;
    return "\0" x 8 if $command == 0x02;
    if ($command == 0x12) {
        return $self->reject('invalid temperature request length') unless length($data) == 10;
        my (undef, $scale, $base, $expansion) = unpack('CCVV', $data);
        return $self->reject('driver queried absent EXP-32 channels') if $expansion;
        return $self->reject('unexpected temperature scale') if $scale;
        my $count = unpack('%32b*', pack('V', $base));
        return pack('f<', $self->{temperature}) x $count;
    }
    return $self->reject(sprintf('unknown TCP command 0x%02x', $command));
}

sub reject {
    my ($self, $message) = @_;
    push @{$self->{errors}}, $message;
    return;
}

sub close_client {
    my ($self, $id) = @_;
    my $client = delete $self->{clients}{$id};
    return unless $client;
    $self->{readers}->remove($client->{socket});
    close($client->{socket}) or die "TCP client $id: close: $!\n";
    return;
}

sub read_udp {
    my ($self) = @_;
    my $peer = recv($self->{udp}, my $data, 512, 0);
    return if !defined($peer) && ($! == EAGAIN || $! == EWOULDBLOCK || $! == EINTR);
    defined $peer or die "UDP receive: $!\n";
    return unless $self->{online};
    my $reply;
    if ($data eq 'D') { $reply = $self->discovery(); }
    elsif (substr($data, 0, 1) eq 'C') { $reply = "C\0"; }
    else { push @{$self->{errors}}, 'unknown UDP command ' . unpack('H*', $data); return; }
    defined(send($self->{udp}, $reply, 0, $peer)) or die "UDP send: $!\n";
    return;
}

sub accept_client {
    my ($self) = @_;
    my $socket = $self->{tcp}->accept();
    return if !$socket && ($! == EAGAIN || $! == EWOULDBLOCK || $! == EINTR);
    $socket or die "TCP accept: $!\n";
    if (!$self->{online}) { close($socket) or die "TCP reject: $!\n"; return; }
    $socket->blocking(0);
    $self->{connections}++;
    $self->{clients}{fileno($socket)} = {socket => $socket, input => '', output => '', closing => 0};
    $self->{readers}->add($socket);
    return;
}

sub read_client {
    my ($self, $id) = @_;
    my $client = $self->{clients}{$id};
    my $count = sysread($client->{socket}, my $data, 65536);
    return if !defined($count) && ($! == EAGAIN || $! == EWOULDBLOCK || $! == EINTR);
    if (!defined($count) || !$count) { $self->close_client($id); return; }
    $client->{input} .= $data;
    while (length($client->{input}) >= $HEADER_LENGTH) {
        my ($delimiter, $command, $frame, undef, $length) = unpack('CCCCv', $client->{input});
        my $total = $HEADER_LENGTH + $length + 1;
        last if length($client->{input}) < $total;
        my $request = substr($client->{input}, 0, $total, '');
        if ($delimiter != 0xdb || unpack('%32C*', $request) % 256 != 255) {
            $self->reject('invalid request frame');
            $self->close_client($id);
            return;
        }
        my $payload = substr($request, $HEADER_LENGTH, $length);
        $self->{requests}++;
        my $selected = $self->{fault} && $command == $self->{fault}[0];
        if ($selected && $command == 0x12) {
            my (undef, undef, $base) = unpack('CCV', $payload);
            $selected = $base == 0x80000000;
        }
        if ($selected) {
            my $mode = $self->{fault}[1];
            $self->{fault} = undef;
            $self->{online} = 0;
            my $now = clock_gettime(CLOCK_MONOTONIC);
            push @{$self->{faults}}, [$command, $mode, $now];
            $self->{readers}->remove($client->{socket});
            if ($mode eq 'short') {
                $client->{output} .= "\xdb\x92\x01";
                $client->{closing} = 1;
            } elsif ($mode eq 'timeout') {
                $client->{deadline} = $now + $TIMEOUT_HOLD;
            } else {
                shutdown($client->{socket}, SHUT_WR);
                $self->close_client($id);
            }
            return;
        }
        my $response = $self->response($command, $payload);
        if (!defined $response) { $self->close_client($id); return; }
        my $reply = pack('CCCCv', 0xdb, $command | 0x80, $frame, 0, length($response)) . $response;
        $client->{output} .= $reply . chr((255 - unpack('%32C*', $reply)) & 255);
    }
    return;
}

sub write_client {
    my ($self, $id) = @_;
    my $client = $self->{clients}{$id};
    return unless $client;
    my $count = syswrite($client->{socket}, $client->{output});
    return if !defined($count) && ($! == EAGAIN || $! == EWOULDBLOCK || $! == EINTR);
    if (!defined($count) || !$count) { $self->close_client($id); return; }
    substr($client->{output}, 0, $count, '');
    if ($client->{closing} && !length($client->{output})) {
        shutdown($client->{socket}, SHUT_WR);
        $self->close_client($id);
    }
    return;
}

sub poll {
    my ($self, $timeout) = @_;
    my $now = clock_gettime(CLOCK_MONOTONIC);
    my $writers = IO::Select->new();
    for my $id (keys %{$self->{clients}}) {
        my $client = $self->{clients}{$id};
        if (defined $client->{deadline}) {
            if ($now >= $client->{deadline}) { $self->close_client($id); next; }
            my $left = $client->{deadline} - $now;
            $timeout = $left if $left < $timeout;
        }
        $writers->add($client->{socket}) if length $client->{output};
    }
    my ($readable, $writable) = IO::Select->select($self->{readers}, $writers, undef, $timeout);
    for my $socket (@{$readable // []}) {
        my $id = fileno($socket);
        if ($id == fileno($self->{udp})) { $self->read_udp(); }
        elsif ($id == fileno($self->{tcp})) { $self->accept_client(); }
        else { $self->read_client($id); }
    }
    for my $socket (@{$writable // []}) {
        my $id = fileno($socket);
        $self->write_client($id) if defined $id && exists $self->{clients}{$id};
    }
    return;
}

sub close {
    my ($self) = @_;
    for my $id (keys %{$self->{clients}}) { $self->close_client($id); }
    for my $name (qw(udp tcp)) {
        my $socket = delete $self->{$name};
        next unless $socket;
        $self->{readers}->remove($socket);
        close($socket) or die "$name: close: $!\n";
    }
    return;
}

1;

__END__

=head1 NAME

TC32 - External UDP/TCP TC32 fixture for the reconnect integration test

=head1 DESCRIPTION

Implements the discovery, digital input, temperature and configuration frames used by the real ULDAQ library. The fixture models a TC32 without EXP-32 and records unsupported requests as errors. A nonblocking event loop serves the sockets while the test waits for IOC output. EOF, incomplete response headers and receive timeout are injected at the network boundary. The timeout socket remains open for ten seconds after fault injection.

=cut
