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
    my ($class, $address, $port, $options) = @_;
    $address //= $DEFAULT_ADDRESS;
    $port //= $DEFAULT_PORT;
    $options //= {};
    # The address-bound and wildcard UDP sockets share the discovery port only
    # when both set SO_REUSEADDR, so the option is set only for broadcast mode.
    my $udp = IO::Socket::INET->new(LocalAddr => $address, LocalPort => $port, Proto => 'udp',
        ReuseAddr => $options->{broadcast} ? 1 : 0)
        or die "$address:$port: UDP bind: $!\n";
    my $tcp = IO::Socket::INET->new(LocalAddr => $address, LocalPort => $port,
        Proto => 'tcp', Listen => 5, ReuseAddr => 1)
        or die "$address:$port: TCP bind: $!\n";
    my $broadcast;
    if ($options->{broadcast}) {
        $broadcast = IO::Socket::INET->new(LocalAddr => '0.0.0.0', LocalPort => $port, Proto => 'udp',
            ReuseAddr => 1)
            or die "0.0.0.0:$port: UDP broadcast bind: $!\n";
        $broadcast->blocking(0);
    }
    $udp->blocking(0);
    $tcp->blocking(0);
    return bless {
        address => $address, port => $port, udp => $udp, tcp => $tcp, broadcast => $broadcast,
        mac => $options->{mac}, discovery_requests => [],
        readers => IO::Select->new($udp, $tcp, $broadcast // ()), clients => {},
        online => 0, temperature => 22.5, types => chr(1) x 64, measure => "\0\0",
        fault => undef, faults => [], errors => [], connections => 0, requests => 0,
        digital_in => 1, digital_out => [0, 0], traffic => [],
    }, $class;
}

sub discovery {
    my ($self) = @_;
    my $mac = $self->{mac} // "\x02\0\0\0\0\x32";
    return 'D' . pack('a6vva16vvvva4vCa22', $mac, 0x132,
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
    return pack('CC', $self->{digital_in}, 0) if $command == 0x00;
    return pack('VV', @{$self->{digital_out}}) if $command == 0x02;
    if ($command == 0x03) {
        return $self->reject('invalid digital output length') unless length($data) == 5;
        my ($index, $value) = unpack('CV', $data);
        return $self->reject('digital write to absent EXP-32') unless $index == 1;
        $self->{digital_out}[0] = $value;
        return '';
    }
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
    my ($self, $socket, $source) = @_;
    my $peer = recv($socket, my $data, 512, 0);
    return if !defined($peer) && ($! == EAGAIN || $! == EWOULDBLOCK || $! == EINTR);
    defined $peer or die "UDP receive: $!\n";
    if ($data eq 'D') {
        push @{$self->{discovery_requests}}, {time => clock_gettime(CLOCK_MONOTONIC),
            source => $source, online => $self->{online} ? 1 : 0};
    }
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
        my $traffic = {command => $command, frame => $frame, payload => unpack('H*', $payload),
            time => clock_gettime(CLOCK_MONOTONIC), connection => $self->{connections}};
        push @{$self->{traffic}}, $traffic;
        my $selected = $self->{fault} && $command == $self->{fault}[0];
        if ($selected && $command == 0x12) {
            my (undef, undef, $base) = unpack('CCV', $payload);
            $selected = $base == 0x80000000;
        }
        my $mode = $selected ? $self->{fault}[1] : '';
        if ($selected) {
            $self->{fault} = undef;
            my $now = clock_gettime(CLOCK_MONOTONIC);
            push @{$self->{faults}}, [$command, $mode, $now];
            $traffic->{fault} = $mode;
            next if $mode eq 'drop';
        }
        if ($selected && $mode ne 'bad-size') {
            $self->{online} = 0;
            $self->{readers}->remove($client->{socket});
            if ($mode eq 'short') {
                $client->{output} .= "\xdb\x92\x01";
                $client->{closing} = 1;
            } elsif ($mode eq 'timeout') {
                $client->{deadline} = clock_gettime(CLOCK_MONOTONIC) + $TIMEOUT_HOLD;
            } else {
                shutdown($client->{socket}, SHUT_WR);
                $self->close_client($id);
            }
            return;
        }
        my $response = $self->response($command, $payload);
        if (!defined $response) { $self->close_client($id); return; }
        $response .= "\0" if $mode eq 'bad-size';
        my $reply = pack('CCCCv', 0xdb, $command | 0x80, $frame, 0, length($response)) . $response;
        $reply .= chr((255 - unpack('%32C*', $reply)) & 255);
        $traffic->{reply} = unpack('H*', $reply);
        $client->{output} .= $reply;
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
        if ($id == fileno($self->{udp})) { $self->read_udp($self->{udp}, 'unicast'); }
        elsif ($self->{broadcast} && $id == fileno($self->{broadcast})) {
            $self->read_udp($self->{broadcast}, 'broadcast');
        }
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
    for my $name (qw(udp tcp broadcast)) {
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

Implements the discovery, digital input/output, temperature and configuration frames used by the real ULDAQ library. The fixture models a TC32 without EXP-32 and records unsupported requests as errors. A nonblocking event loop serves the sockets while the test waits for IOC output. EOF, incomplete response headers and receive timeout are injected at the network boundary. The timeout socket remains open for ten seconds after fault injection. The drop fault discards one request without closing the socket; subsequent requests receive normal responses. The bad-size fault returns a complete checksummed response with one unexpected payload byte. Request timestamps, connection numbers, payloads and complete response frames are retained as evidence. The optional third constructor argument is a hash reference. Its C<mac> key sets the six-byte MAC address in the discovery reply. Its C<broadcast> key adds a wildcard UDP listener on the discovery port that records every broadcast discovery request with its monotonic time and replies, while the fixture is online, from the address-bound socket so the reply source is the device address. Broadcast replies are off by default, so cases that select a device by IP address keep their direct descriptor path. Every discovery request, broadcast or addressed, is retained in C<discovery_requests> with its source and online state.

=cut
