#!/usr/bin/env perl
use strict;
use warnings;

use Cwd qw(abs_path);
use Digest::SHA;
use File::Path qw(make_path);
use File::Spec;
use FindBin qw($RealBin);
use Getopt::Long qw(GetOptionsFromArray);
use JSON::PP;
use Pod::Usage qw(pod2usage);
use POSIX qw(WNOHANG);
use Time::HiRes qw(sleep);

my $JSON = JSON::PP->new->canonical->pretty->indent_length(2);
my $signal_status = 0;

sub write_file {
    my ($path, $text) = @_;
    open(my $out, '>:raw', $path) or die "$path: $!\n";
    print {$out} $text or die "$path: write: $!\n";
    close($out) or die "$path: close: $!\n";
    return;
}

sub run_command {
    my ($command, $log) = @_;
    my $pid = fork();
    defined $pid or die "$command->[0]: fork: $!\n";
    if (!$pid) {
        POSIX::setpgid(0, 0) == 0 or POSIX::_exit(126);
        open(STDOUT, '>&', $log) or POSIX::_exit(126);
        open(STDERR, '>&', $log) or POSIX::_exit(126);
        $SIG{INT} = $SIG{TERM} = 'DEFAULT';
        {
            no warnings 'exec';
            exec { $command->[0] } @$command;
        }
        POSIX::_exit(127);
    }
    my $waited;
    my $done = eval {
        do { $waited = waitpid($pid, 0) } while ($waited == -1 && $! == POSIX::EINTR());
        $waited == $pid or die "$command->[0]: waitpid: $!\n";
        1;
    };
    if (!$done) {
        my $error = $@;
        # Terminate the compiler process group before propagating interruption.
        kill 'TERM', -$pid;
        my $reaped = 0;
        for (1 .. 50) {
            if (waitpid($pid, WNOHANG) == $pid) { $reaped = 1; last; }
            sleep(0.1);
        }
        if (!$reaped) { kill 'KILL', -$pid; waitpid($pid, 0); }
        die $error;
    }
    my $status = $?;
    die "$command->[0]: terminated by signal " . ($status & 127) . "\n" if $status & 127;
    die "$command->[0]: exit " . ($status >> 8) . "; see build.log\n" if $status;
    return;
}

sub main {
    my (@args) = @_;
    my %options = (arch => 'linux-x86_64');
    my %variables = (base => 'BASE', asyn => 'ASYN', 'uldaq-include' => 'ULDAQ_INCLUDE',
                     'uldaq-lib' => 'ULDAQ_LIB', build => 'BUILD');
    for my $name (keys %variables) {
        $options{$name} = $ENV{$variables{$name}} if defined $ENV{$variables{$name}};
    }
    Getopt::Long::Configure('no_auto_abbrev', 'no_ignore_case');
    GetOptionsFromArray(\@args, \%options, 'base=s', 'asyn=s', 'uldaq-include=s',
        'uldaq-lib=s', 'build=s', 'arch=s', 'help')
        or pod2usage(-exitval => 2, -verbose => 0);
    pod2usage(-exitval => 0, -verbose => 1) if $options{help};
    pod2usage(-exitval => 2, -message => 'Unexpected positional arguments') if @args;
    for my $name (sort keys %variables) {
        pod2usage(-exitval => 2, -message => "Missing --$name or $variables{$name}")
            unless defined $options{$name} && length $options{$name};
    }

    my $build = File::Spec->rel2abs($options{build});
    die "$build: build directory already exists\n" if -e $build || -l $build;
    make_path($build);
    $build = abs_path($build) // die "$build: resolve: $!\n";
    my %paths;
    for my $name (qw(base asyn uldaq-include uldaq-lib)) {
        $paths{$name} = abs_path($options{$name}) // die "$options{$name}: resolve: $!\n";
    }
    my ($base, $asyn, $include, $library) = @paths{qw(base asyn uldaq-include uldaq-lib)};
    my $repository = abs_path("$RealBin/..");
    my $binaries = "$base/bin/$options{arch}";
    my $dbd = "$build/reconnect.dbd";
    my $registrar = "$build/reconnect_register.cpp";
    my $definition = "$build/reconnectInclude.dbd";
    write_file($definition, "include \"base.dbd\"\ninclude \"asyn.dbd\"\nregistrar(drvMultiFunctionRegister)\n");
    my @sources = ("$RealBin/reconnect_ioc.cpp", $registrar,
        "$repository/measCompApp/src/drvMultiFunction.cpp",
        "$repository/measCompApp/src/measCompDiscover.cpp");
    my @includes = ("$base/include", "$base/include/os/Linux", "$base/include/compiler/gcc",
        "$asyn/include", $include, "$repository/measCompApp/src");
    my @libraries = ("$asyn/lib/$options{arch}", "$base/lib/$options{arch}", $library);
    my @commands = (
        ['perl', "$binaries/dbdExpand.pl", '-I', "$base/dbd", '-I', "$asyn/dbd",
         '-o', $dbd, $definition],
        ['perl', "$binaries/registerRecordDeviceDriver.pl", '-o', $registrar,
         $dbd, 'review_registerRecordDeviceDriver'],
        ['g++', '-std=gnu++11', '-O0', '-g', '-Wno-write-strings',
         (map { "-I$_" } @includes), @sources, (map { "-L$_" } @libraries),
         (map { "-Wl,-rpath,$_" } @libraries), '-lasyn', '-ldbRecStd', '-ldbCore',
         '-lca', '-lCom', '-luldaq', '-lpthread', '-o', "$build/reconnect-ioc"]);
    write_file("$build/commands.json", $JSON->encode(\@commands));
    open(my $log, '>:raw', "$build/build.log") or die "$build/build.log: $!\n";
    for my $command (@commands) { run_command($command, $log); }
    close($log) or die "$build/build.log: close: $!\n";

    my @members = (@sources, "$repository/measCompApp/src/measCompDiscover.h",
        "$repository/measCompApp/Db/measCompTemperatureIn.template",
        "$repository/measCompApp/Db/measCompBinaryIn.template",
        "$repository/measCompApp/Db/measCompAnalogIn.template",
        "$repository/measCompApp/Db/measCompVoltageIn.template",
        "$repository/measCompApp/Db/measCompAnalogOut.template",
        "$RealBin/test_reconnect.pl", "$RealBin/TC32.pm", "$RealBin/build_reconnect.pl",
        "$RealBin/E1608.pm",
        "$asyn/include/asynDriver.h", "$include/uldaq.h", "$library/libuldaq.so");
    my %hashes;
    for my $path (@members) {
        my $sha = Digest::SHA->new(256);
        $sha->addfile($path, 'b');
        $hashes{$path} = $sha->hexdigest;
    }
    write_file("$build/inputs.json", $JSON->encode(\%hashes));
    print "$build/reconnect-ioc\n" or die "stdout: $!\n";
    return 0;
}

my $status;
local $SIG{INT} = sub { $signal_status = 130; die "interrupted\n"; };
local $SIG{TERM} = sub { $signal_status = 143; die "terminated\n"; };
eval {
    $status = main(@ARGV);
    defined $status or die "internal error: main returned no status\n";
    1;
} or do {
    my $error = $@;
    print STDERR "build_reconnect: $error";
    $status = $signal_status || 1;
};
exit $status;

__END__

=head1 NAME

build_reconnect.pl - Build the real Linux reconnect test IOC

=head1 SYNOPSIS

perl tests/build_reconnect.pl --base DIR --asyn DIR --uldaq-include DIR --uldaq-lib DIR --build DIR

=head1 OPTIONS

=over 4

=item --base DIR

EPICS Base installation. Defaults to BASE.

=item --asyn DIR

asyn installation. Defaults to ASYN.

=item --uldaq-include DIR

Patched ULDAQ headers. Defaults to ULDAQ_INCLUDE.

=item --uldaq-lib DIR

Matching patched ULDAQ shared libraries. Defaults to ULDAQ_LIB.

=item --build DIR

New output directory, including missing parents. Defaults to BUILD. Existing output directories are rejected.

=item --arch NAME

EPICS host architecture, default linux-x86_64.

=item --help

Print usage and exit successfully.

=back

=head1 OUTPUT

Print the executable path. Retain commands.json, build.log, inputs.json and all generated IOC files in the build directory.

=head1 EXIT STATUS

0 means success, 1 means a build or file error, and 2 means invalid usage. INT and TERM return 130 and 143 after terminating the active build process group.

=cut
