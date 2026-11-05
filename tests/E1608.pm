package E1608;
use strict;
use warnings;

use parent 'TC32';
use Socket qw(inet_aton);

# The Ethernet devices share discovery and command framing. Only the
# device-specific payloads differ; the inherited transport stays external.
sub discovery {
    my ($self) = @_;
    return 'D' . pack('a6vva16vvvva4vCa22', "\x02\0\0\0\0\x08", 0x12f,
        0x100, 'E-1608-TEST', $self->{port}, $self->{port} + 1, 0, 0,
        inet_aton($self->{address}), 0x100, 0, "\0" x 22);
}

sub response {
    my ($self, $command, $data) = @_;
    if ($command == 0x40 || $command == 0x44) {
        return $self->reject('invalid memory request length') unless length($data) == 4;
        my ($address, $count) = unpack('vv', $data);
        my $memory = $command == 0x40
            ? pack('f<f<', 1, 0) x 10 . pack('C6', 24, 1, 1, 0, 0, 0) . "\0" x 426
            : "\0" x 512;
        return $self->reject('memory request out of bounds') if $address + $count > length($memory);
        return substr($memory, $address, $count);
    }
    if ($command == 0x10) {
        return $self->reject('invalid analog input request length') unless length($data) == 2;
        my ($channel, $range) = unpack('CC', $data);
        return $self->reject('invalid analog input channel or range') if $channel > 11 || $range > 3;
        return pack('v', 32768);
    }
    if ($command == 0x21) {
        return $self->reject('invalid analog output request')
            unless length($data) == 3 && ord(substr($data, 0, 1)) < 2;
        return '';
    }
    if ($command == 0x03 || $command == 0x05) {
        return $self->reject('invalid digital write length') unless length($data) == 1;
        $self->{$command == 0x03 ? 'output' : 'direction'} = ord($data);
        return '';
    }
    if ($command == 0x13) {
        return $self->reject('invalid scan stop request') unless $data eq "\1";
        return '';
    }
    return $self->reject('unexpected command payload') if length($data);
    return pack('v', 0) if $command == 0x52;
    return pack('V', 0) if $command == 0x30;
    return pack('C', $self->{digital_in}) if $command == 0x00;
    return pack('C', $self->{output} // 0) if $command == 0x02;
    return pack('C', $self->{direction} // 255) if $command == 0x04;
    return '' if $command == 0x31;
    return $self->reject(sprintf('unknown E-1608 TCP command 0x%02x', $command));
}

1;

__END__

=head1 NAME

E1608 - External E-1608 UDP/TCP fixture for enum integration tests

=head1 DESCRIPTION

Uses TC32's nonblocking Ethernet transport and fault injection with E-1608 discovery and command payloads. Implements calibration memory with unit slopes and zero offsets, digital I/O, counters, scan stop and single analog input/output commands used by ULDAQ 1.2.2. Analog input returns midscale raw counts. Unsupported requests are errors. This bounded fixture verifies metadata recovery, not hardware calibration or scan acquisition.

=cut
