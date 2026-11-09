# MultiFunction reconnect tests

The test compiles the repository's MultiFunction driver, device discovery
and analog device support, links real EPICS/asyn/ULDAQ libraries, and loads the shipped
temperature, binary-input and analog templates. External TC32 and E-1608
UDP/TCP devices are simulated; internal driver and library functions run unchanged.

## Prerequisites

- Linux with Bash, `g++`, Perl 5.26 or later, `ip`, `unshare` and `timeout`.
- A complete Perl installation with `JSON::PP`, `Digest::SHA`, `IO::Socket::INET`,
  `IO::Select`, `Time::HiRes`, `Getopt::Long` and `Pod::Usage`. Debian's `perl`
  package includes these modules; Rocky installations also need
  `perl-JSON-PP` and `perl-Digest-SHA` when using `perl-interpreter`.
- EPICS Base 7.0.10 and asyn 4.45, including headers, libraries and Base build tools.
- ULDAQ 1.2.2 built with the required TCP receive patch through
  [`uldaq-env`](https://github.com/jeonghanlee/uldaq-env), as described in the
  [Linux vendor dependency](../docs/reconnection.md#linux-vendor-dependency).
- Permission to create a user/network namespace and a dummy network interface.

Run from this repository. Set these paths for the local installations; the
ULDAQ headers and patched `libuldaq.so` must come from the same `uldaq-env`
build. `BUILD` must name a directory that does not yet exist. Each run retains
its generated files, source hashes, build commands, build log, IOC log and JSON
assertion results.

```bash
export BASE=/opt/epics/base
export ASYN=/opt/epics/asyn
export ULDAQ_INCLUDE=/opt/uldaq/include
export ULDAQ_LIB=/opt/uldaq/lib
export BUILD=/tmp/meascomp-reconnect-test
perl tests/build_reconnect.pl
```

For an uninstalled ULDAQ build, use its `src` directory for headers and
`src/.libs` for libraries. The builder records the complete command and source
hashes and sets runtime library search paths to the supplied library directories.
Do not override those directories with an unrelated `LD_LIBRARY_PATH`.

Enter an isolated namespace and create the documentation-only addresses. The
third address serves only the second device of the two-port MAC case:

```bash
unshare -Urn bash
ip link set lo up
ip link add sim0 type dummy
ip addr add 192.0.2.1/24 dev sim0
ip link set sim0 up
ip addr add 192.0.2.2/32 dev lo
ip addr add 192.0.2.3/32 dev lo
```

Run the test inside that shell, then leave the namespace:

```bash
export TEMPLATE="$PWD/measCompApp/Db/measCompTemperatureIn.template"
timeout 100s perl tests/test_reconnect.pl "$BUILD/reconnect-ioc" "$BUILD/reconnect.dbd" "$TEMPLATE" "$BUILD/ioc.log"
exit
```

Success requires all assertions and normal IOC exit. A failed assertion or
missing required response exits nonzero. The JSON file beside `ioc.log` retains
observed checks, injected transport faults and the IOC exit status. Inspect both
the process exit status and JSON; a partial list of passing checks is not success.
Both Perl commands provide `--help`. Usage errors return 2; build, runtime and
assertion errors return 1. INT and TERM return 130 and 143 after terminating and
reaping the active child. The test retains available IOC output and JSON evidence
on handled failures and interruptions.

`build_reconnect.pl` generates the database definition and registrar and compiles
the IOC. `test_reconnect.pl` controls the IOC through pipes and evaluates its
output. `TC32.pm` serves the external device protocol through a nonblocking
socket event loop while the test waits for IOC responses. `E1608.pm` uses the
same Ethernet framing with E-1608 discovery, calibration-memory and I/O payloads.

The default `reconnect` fixture starts offline, then becomes available. It sends a valid 22.5 C
baseline, tests EOF during the final temperature channel, a short digital-input response and
silence beyond ULDAQ's receive timeout, and verifies recovery within 12 seconds
of becoming available. Every failure must produce a disconnected port and INVALID
input severity without replacing the last valid temperature. Restored settings
must match the last successful writes, including conflicting bank-wide writes.
TC-type writes include successful controls and EOF during a setting change.
The test reads the actual asynInt32 cache immediately while disconnected, then
compares normal SyncIO readback and the fixture's setting after reconnect.
It repeats the sequence with a new successful value on channel 0 and also
checks channel 31. Cache inspection uses the public interface under the port
lock because queued I/O is rejected while disconnected; it does not replace
any driver or library function. Every failed write must preserve the last
successful type, both before and after recovery.
Auto-connect is disabled for six seconds to verify that it prevents retries;
port disable and enable must stop and resume polling. The fixture rejects
unexpected protocol commands and requests for absent EXP-32 channels.

## Digital write cases

`--case` selects one independent case; omitting it runs `reconnect`. Every
invocation starts a fresh IOC and fixture. Repeat the namespace setup above,
then run these commands in that shell. Keep `BUILD` set to the existing build
directory; each case uses a separate log path.

```bash
export TEMPLATE="$PWD/measCompApp/Db/measCompTemperatureIn.template"
export IOC="$BUILD/reconnect-ioc"
export DBD="$BUILD/reconnect.dbd"
timeout 90s perl tests/test_reconnect.pl --case digital-word "$IOC" "$DBD" "$TEMPLATE" "$BUILD/word.log"
timeout 90s perl tests/test_reconnect.pl --case digital-control "$IOC" "$DBD" "$TEMPLATE" "$BUILD/control.log"
timeout 90s perl tests/test_reconnect.pl --case digital-policy "$IOC" "$DBD" "$TEMPLATE" "$BUILD/policy.log"
timeout 90s perl tests/test_reconnect.pl --case digital-bits "$IOC" "$DBD" "$TEMPLATE" "$BUILD/bits.log"
exit
```

All cases verify a successful full-port write, set a 10-second poll interval
and observe a completed healthy poll before injecting the selected fault.
The error result and input state must be observed before another input poll;
the JSON records monotonic request times and actual request/reply bytes.

| Case | Fault and acceptance |
| --- | --- |
| `digital-word` | EOF during `ulDOut`: return an error, disconnect immediately, set temperature and digital input severity to INVALID, preserve last valid input values, then recover. |
| `digital-control` | A complete response with one unexpected byte produces real ULDAQ `ERR_BAD_BUFFER_SIZE`; return an error while retaining the healthy connection, then accept a normal write. |
| `digital-policy` | After write EOF, restore the fixture with auto-connect disabled for 12 seconds. Disable the port and enable auto-connect for another 12 seconds; neither state permits recovery. A disabled-port write returns `asynDisabled` without device traffic. Enabling the port restores valid inputs. |
| `digital-bits` | Drop the first selected bit's write request and response, retaining the socket for subsequent requests. The real vendor timeout must remain the operation result; disconnect and stop before a later bit can succeed. |

Digital fault assertions compare the same temperature and binary-input values
before failure, while INVALID, and after recovery. They do not verify output
replay or rollback of earlier successful bit writes.

## Analog enum cases

Repeat the namespace setup above, then run these commands in that shell with
the existing `BUILD`. Each case starts a fresh IOC and device fixture.

```bash
export TEMPLATE="$PWD/measCompApp/Db/measCompAnalogIn.template"
export IOC="$BUILD/reconnect-ioc"
export DBD="$BUILD/reconnect.dbd"
export RUNNER="$PWD/tests/test_reconnect.pl"
timeout 90s perl "$RUNNER" --case enum-tc32-online "$IOC" "$DBD" "$TEMPLATE" "$BUILD/t-online.log"
timeout 90s perl "$RUNNER" --case enum-tc32-offline "$IOC" "$DBD" "$TEMPLATE" "$BUILD/t-offline.log"
timeout 90s perl "$RUNNER" --case enum-e1608-online "$IOC" "$DBD" "$TEMPLATE" "$BUILD/e-online.log"
timeout 90s perl "$RUNNER" --case enum-e1608-offline "$IOC" "$DBD" "$TEMPLATE" "$BUILD/e-offline.log"
timeout 90s perl "$RUNNER" --case enum-e1608-init "$IOC" "$DBD" "$TEMPLATE" "$BUILD/e-init.log"
exit
```

TC32 cases load the shipped analog-input template at addresses 0 and 31 to
exercise enum metadata; normal TC32 temperature acquisition uses its separate
floating-point template. E-1608 cases load analog-input and voltage-input
templates at addresses 0 and 7, and analog-output templates at addresses 0 and 1.
The voltage-input and analog-output templates must be beside `TEMPLATE`.

Every case compares all 16 record enum states with public `readEnum()` results
and the model's specified strings, values and severities. It writes each
supported selection through the record's `VAL`, waits for asynchronous processing
to finish, and checks `RVAL`, `SDEF=1`, alarm severity and public asynInt32
readback. The same checks run after two observed EOF/disconnect/reconnect cycles.
Each phase also checks its number of inspected records so a partial pass cannot
silently omit the remaining targets.

Online cases make the device available before driver construction. Offline cases
observe a disconnected IOC before enabling responses. The `init` case holds
IOC initialization after record initialization, enables the device, observes
real polling while `interruptAccept=0`, and then completes IOC initialization.
This verifies deferred enum delivery through the actual asyn device support.
These cases establish enum metadata and selection conversion, not ADC
engineering-unit conversion, analog output voltage or scan acquisition.

## Analog bounds cases

Repeat the namespace setup above and use the existing `BUILD`. Each case
starts a fresh IOC and external fixture. The builder includes the shipped
`devMeasComp.dbd` and records its hash along with `devMeasComp.cpp`.

```bash
export TEMPLATE="$PWD/measCompApp/Db/measCompAnalogIn.template"
export IOC="$BUILD/reconnect-ioc"
export DBD="$BUILD/reconnect.dbd"
export RUNNER="$PWD/tests/test_reconnect.pl"
timeout 90s perl "$RUNNER" --case bounds-tc32-online "$IOC" "$DBD" "$TEMPLATE" "$BUILD/bt-on.log"
timeout 90s perl "$RUNNER" --case bounds-tc32-offline "$IOC" "$DBD" "$TEMPLATE" "$BUILD/bt-off.log"
timeout 90s perl "$RUNNER" --case bounds-e1608-online "$IOC" "$DBD" "$TEMPLATE" "$BUILD/be-on.log"
timeout 90s perl "$RUNNER" --case bounds-e1608-offline "$IOC" "$DBD" "$TEMPLATE" "$BUILD/be-off.log"
exit
```

TC32 cases compare the confirmed 24-bit bounds and LINEAR coefficients with
`EGUL=0`, `EGUF=1`, then with changed limits. These are metadata checks:
without analog samples, the records must remain undefined and INVALID.

E-1608 cases apply Range and Type through the shipped records after enums
arrive, including reapplying settings whose PINI writes failed while offline.
The fixture supplies raw counts 32768, 0 and 65535 through real Ethernet
responses. Periodic and I/O Intr records must receive fresh samples with
correct RVAL, ESLO, EOFF and VAL, first for limits -10..10 and then 2..7.
The same measurements repeat after an observed TCP EOF and reconnect.
Additional checks cover a two-sample I/O Intr average, manual SLOPE coefficients,
and Passive processing without new samples after port disable. A missing sample
must leave the value unchanged with UDF and INVALID severity.

For the original-behavior control, keep the final runner, fixtures, IOC binary
and dependencies identical, but pass a scratch copy of the original
`measCompAnalogIn.template` using `asynInt32Average`. Both online cases must
pass. Offline TC32 must fail the startup coefficient assertion; offline E-1608
must reach the raw-32768 response and fail its startup engineering-value
assertion. Setup errors or absent sample traffic do not count as detecting
the conversion defect.

## MAC rediscovery cases

Repeat the namespace setup above, including the third address, and use the
existing `BUILD`. Each case starts a fresh IOC and one or two external TC32
fixtures. The IOC selects each device by its MAC address, so the real driver
finds it through broadcast discovery. The fixtures answer broadcast discovery
only in these cases; every other case selects the device by IP address.

```bash
export TEMPLATE="$PWD/measCompApp/Db/measCompTemperatureIn.template"
export IOC="$BUILD/reconnect-ioc"
export DBD="$BUILD/reconnect.dbd"
export RUNNER="$PWD/tests/test_reconnect.pl"
timeout 150s perl "$RUNNER" --case mac-tc32-online "$IOC" "$DBD" "$TEMPLATE" "$BUILD/mo-on.log"
timeout 150s perl "$RUNNER" --case mac-tc32-offline "$IOC" "$DBD" "$TEMPLATE" "$BUILD/mo-off.log"
timeout 150s perl "$RUNNER" --case mac-two-ports "$IOC" "$DBD" "$TEMPLATE" "$BUILD/mo-two.log"
timeout 150s perl "$RUNNER" --case mac-known-absent "$IOC" "$DBD" "$TEMPLATE" "$BUILD/mo-known.log"
exit
```

`mac-tc32-offline` starts with the device absent and observes the port
disconnected with INVALID input for eleven seconds while the fixture records
every broadcast discovery request. It then makes the device available and
requires a valid 22.5 C reading within twelve seconds. The recorded requests
must number two or three, at least 3.9 seconds apart: the startup discovery
plus the refreshes allowed by the four-second minimum interval, less a
tolerance. The driver's five-second reconnect delay makes the actual spacing
about five seconds.

`mac-tc32-online` starts with the device present. The startup discovery must
be the only discovery request through an idle interval, an EOF and reconnect,
and two twelve-second periods with the device absent, one with auto-connect
disabled and one with the port disabled. The device must reconnect from its
known inventory entry in every case.

`mac-two-ports` runs two ports on separate fixtures with different MAC
addresses and temperatures, 22.5 C and 37.25 C. The first device is present at
startup and the second is absent. The second port is configured with its MAC
in lower case, so the case also verifies that the driver matches it to the
upper-case MAC the vendor library reports; `mac-known-absent` uses the same
identifiers. Both fixtures must see the same bounded
discovery requests during the absence. When the second device becomes
available it must connect with its own value within eight seconds, which a
refresh skipped because of the lock wait would exceed, while the first port
keeps its single connection and its value. From the moment the first port is
healthy until the end, including every refresh while the second device is
absent, it must never go three seconds without a request. The inventory
listing must contain exactly the two MAC addresses.

`mac-known-absent` uses the same two fixtures, but takes the first device
offline with an EOF before the second device becomes available. The second
device must connect while the first is silent to the refresh broadcast, the
inventory listing must still contain both MAC addresses, and the first port
must reconnect from its inventory entry with a valid reading and without
another discovery request.

Every case leaves the IOC through the normal exit and requires exit status
zero, including the cases with two ports. The driver stops and joins its poller
threads in an exit handler; see the exit loop below for the repeated check.

The Ethernet-only restriction of the refresh is not exercised, because the
namespace has no USB device; it is established by reading the source.

The original-behavior controls build the IOC from an earlier
`measCompDiscover.cpp` with the final tests and fixtures. Use a scratch copy of
the repository in which only `measCompApp/src/measCompDiscover.cpp` is replaced
by the earlier version, because `build_reconnect.pl` compiles the sources of
the repository that holds the running tests. Two baselines detect two defects.
With the source from before MAC rediscovery, the online case must pass, the
offline case must fail at the connection deadline with the port still
disconnected, and the two-port and known-absent cases must fail at the second
port's connection deadline, because an absent device is never rediscovered.
With the source that rediscovers devices but compares MAC addresses with their
exact case, the online and offline cases must pass and only the two-port and
known-absent cases must fail at the second port's connection deadline, because
their second port is configured with a lower-case MAC. Build or setup errors do
not count as detecting a defect.

## Discovery endpoint cases

These cases need the third address and, for the hostname case, a mount
namespace in which the shipped `tests/endpoint-hosts` file replaces
`/etc/hosts` so that `fixture-a` resolves to the first fixture's address. The
bind mount is visible only inside the namespace; the host's own file is not
changed. Enter the namespace with the mount flag, then set up the addresses
as above and mount the hosts file:

```bash
unshare -Urnm bash
ip link set lo up
ip link add sim0 type dummy
ip addr add 192.0.2.1/24 dev sim0
ip link set sim0 up
ip addr add 192.0.2.2/32 dev lo
ip addr add 192.0.2.3/32 dev lo
mount --bind "$PWD/tests/endpoint-hosts" /etc/hosts
```

Run the cases in that shell with the existing `BUILD`:

```bash
export TEMPLATE="$PWD/measCompApp/Db/measCompTemperatureIn.template"
export IOC="$BUILD/reconnect-ioc"
export DBD="$BUILD/reconnect.dbd"
export RUNNER="$PWD/tests/test_reconnect.pl"
timeout 120s perl "$RUNNER" --case endpoint-same-ip "$IOC" "$DBD" "$TEMPLATE" "$BUILD/ep-same.log"
timeout 120s perl "$RUNNER" --case endpoint-mixed "$IOC" "$DBD" "$TEMPLATE" "$BUILD/ep-mixed.log"
timeout 120s perl "$RUNNER" --case endpoint-distinct-ip "$IOC" "$DBD" "$TEMPLATE" "$BUILD/ep-distinct.log"
timeout 120s perl "$RUNNER" --case endpoint-default-port "$IOC" "$DBD" "$TEMPLATE" "$BUILD/ep-default.log"
timeout 120s perl "$RUNNER" --case endpoint-alt-port "$IOC" "$DBD" "$TEMPLATE" "$BUILD/ep-alt.log"
timeout 120s perl "$RUNNER" --case endpoint-hostname "$IOC" "$DBD" "$TEMPLATE" "$BUILD/ep-host.log"
timeout 120s perl "$RUNNER" --case endpoint-hostname-port "$IOC" "$DBD" "$TEMPLATE" "$BUILD/ep-hostport.log"
timeout 120s perl "$RUNNER" --case endpoint-wrong-port "$IOC" "$DBD" "$TEMPLATE" "$BUILD/ep-wrong.log"
exit
```

`endpoint-same-ip` runs two fixtures at one address, 22.5 C on discovery port
54211 selected as `192.0.2.2` and 37.25 C on port 54221 selected as
`192.0.2.2:54221`. Each port must read its own device, each fixture must see
exactly one connection, the first port must never go three seconds without a
request after it is healthy, and the inventory must list the two MAC
addresses. `endpoint-mixed` selects the first fixture by its MAC through the
startup broadcast and the second as `192.0.2.2:54221`, with the same
requirements plus a single discovery request for the first device.
`endpoint-distinct-ip` runs the same two fixtures at distinct addresses on
the default port.

The three single-device cases guard behavior that also holds before the
endpoint identity. `endpoint-default-port` selects a broadcast-discovered
device as `192.0.2.2:54211` and requires one inventory entry, one connection
and, after the startup broadcast, no addressed discovery request other than
the vendor library's single MAC check at connection; a device that the
inventory lookup missed would be queried directly first. `endpoint-alt-port`
runs one fixture on port 54221 and selects it with that port.
`endpoint-hostname`
selects a fixture as `fixture-a` and requires the inventory to hold its
resolved address, and `endpoint-hostname-port` selects a fixture on port
54221 as `fixture-a:54221`. `endpoint-wrong-port` selects `192.0.2.2:54231`,
a discovery port nobody listens on, and requires the port to stay
disconnected with INVALID input for twelve seconds, no connection at the
fixture, an empty inventory and a normal exit.

The reuse of an inventory entry for a device whose MAC is already known is
not exercised, because a fixture answers at one address only; it is
established by reading the source.

For the original-behavior control, replace `measCompApp/src/measCompDiscover.cpp`
in a scratch copy by the version from before the endpoint identity, as
described for the MAC cases. `endpoint-same-ip` and `endpoint-mixed` must
fail `endpoint second port reads its device` with the second port reporting
22.5, and the six other cases must pass.

## Silent device case

`silent-device` runs a healthy TC32 at `192.0.2.2` beside a second TC32 at
`192.0.2.3`. After both are healthy it counts the requests the first fixture
receives in 40 seconds, then removes `192.0.2.3` from the namespace with `ip`,
so the second device's packets are dropped without a reset, as for a device
that loses power. Beginning 25 seconds after the removal it counts the first
fixture's requests over another 40 seconds and requires at least 80 percent of
the first count and no pause longer than 4 seconds. It then restores the
address and requires the second port to reconnect with 37.25 within 70
seconds. A second outage of 22 seconds, long enough for the retry interval to
be spaced, ends with the address restored and the second port disabled and
enabled again, which must reconnect it within 12 seconds. The IOC must then
exit normally. The case takes about two and a half minutes. Run it in the
namespace shell of the other cases, which already has `192.0.2.3/32` on `lo`:

```bash
export TEMPLATE="$PWD/measCompApp/Db/measCompTemperatureIn.template"
export IOC="$BUILD/reconnect-ioc"
export DBD="$BUILD/reconnect.dbd"
export RUNNER="$PWD/tests/test_reconnect.pl"
timeout 240s perl "$RUNNER" --case silent-device "$IOC" "$DBD" "$TEMPLATE" "$BUILD/silent.log"
exit
```

For the original-behavior control, build a scratch copy whose
`measCompApp/src/drvMultiFunction.cpp` is the version from before the spaced
retries, as described for the MAC cases, and run the same command from its
root. It must fail `silent healthy port keeps polling`, because a five-second
retry of a silent device leaves the healthy port 70 to 74 percent of the
control's requests in the measured window, below the 80 percent threshold.

## Read error case

`read-error` runs a healthy TC32 and switches a persistent common-mode
condition on for channels 0 and 31, the two channels with temperature records
in the test IOC. The fixture returns -7777 for them, which ULDAQ reports as
error 107 on every read. Over an 8-second window of at least 100 polls it
requires one error line per channel that names the channel, records that stay
INVALID with their held value, and `LAST_ERROR_MESSAGE` naming the condition.
It then injects a different error on channel 31 while its condition lasts
and requires one new line for that error and one when the common-mode error
returns. It forces a connection error and requires one new line per channel
after the reconnect. It switches the condition off on
channel 0 and requires one line for its return to normal with the message
still naming the failure of channel 31, then off on channel 31 and requires
its line and a cleared message. The IOC must then exit normally. The case
takes about 25 seconds. It needs no extra address, so it runs in the
namespace shell of the other cases:

```bash
export TEMPLATE="$PWD/measCompApp/Db/measCompTemperatureIn.template"
export IOC="$BUILD/reconnect-ioc"
export DBD="$BUILD/reconnect.dbd"
export RUNNER="$PWD/tests/test_reconnect.pl"
timeout 120s perl "$RUNNER" --case read-error "$IOC" "$DBD" "$TEMPLATE" "$BUILD/read-error.log"
exit
```

For the original-behavior control, build a scratch copy whose
`measCompApp/src/drvMultiFunction.cpp` is the version from before the
once-per-change reporting, as described for the MAC cases, and run the same
command from its root. It must fail `read error reported once per channel`,
because that driver prints an error line on every poll for every failing
channel, hundreds of lines in the window instead of two.

## Temperature array case

`temperature-array` runs a healthy TC32 and counts the temperature requests
its fixture receives against the digital reads, one per poll. With all
channels at one scale a poll must issue one request for all 32 channels. It
then sets channel 0 to Fahrenheit and channel 31 to Kelvin and requires three
requests per poll, for channel 0, channels 1 to 30 and channel 31, and the
records to read 72.5 and 295.65 for 22.5 degrees Celsius. The test IOC loads
the records of channels 0, 1 and 31 scanned `I/O Intr`, the only scan for which
`TSE=-2` takes effect, with `TSE=-2`, and the record of channel 2 without the
macro, whose `TSE` field must be 0. The timestamps must be
equal within one poll, lie within two seconds of the current time and advance
from one poll to the next. The case then makes channel 0 open, channel 1
disabled and channel 31 a common-mode error in one request and requires -9999
valid, -11111 valid and INVALID with the held value, with the driver reporting
an error only for channel 31. It then fails one request without a connection
error, which must fail all 32 channels and keep the port connected. Finally it
forces a transport error on the temperature request, requires every channel to
fail and the port to reconnect, and requires the IOC to exit normally. The case takes about 20
seconds and runs in the namespace shell of the other cases:

```bash
export TEMPLATE="$PWD/measCompApp/Db/measCompTemperatureIn.template"
export IOC="$BUILD/reconnect-ioc"
export DBD="$BUILD/reconnect.dbd"
export RUNNER="$PWD/tests/test_reconnect.pl"
timeout 120s perl "$RUNNER" --case temperature-array "$IOC" "$DBD" "$TEMPLATE" "$BUILD/temperature-array.log"
exit
```

For the original-behavior control, build a scratch copy whose
`measCompApp/src/drvMultiFunction.cpp` is the version from before the
single-request read, as described for the MAC cases, and run the same command
from its root. It must fail `temperature array one request per poll`, because
that driver issues one request for each of the 32 channels of a poll.

## Exit loop

The driver stops and joins each port's poller thread in an exit handler, so
the poller never calls into the vendor library after the process has begun to
unload it. Before this, about two to three percent of the normal exits of
`endpoint-same-ip` aborted with a pure virtual call; the race needs a poller
that is inside a vendor call when the library destructor deletes the devices,
so a single run does not show it. `tests/exit_loop.bash` runs one case many
times, each run in its own network namespace so that parallel runs do not share
the fixture addresses, and fails when any run ends with a nonzero status. It is
started outside a namespace shell and needs the unprivileged `unshare` that the
other cases use. Run it from the repository root with `BUILD` set as above:

```bash
export TEMPLATE="$PWD/measCompApp/Db/measCompTemperatureIn.template"
export IOC="$BUILD/reconnect-ioc"
export DBD="$BUILD/reconnect.dbd"
bash "$PWD/tests/exit_loop.bash" endpoint-same-ip 150 3 "$IOC" "$DBD" "$TEMPLATE" "$BUILD/exit-loop"
```

The 150 runs take about nine minutes at three at a time. The script prints the
number of each failed run, and the output directory keeps these files for every
run N: `run-N.log` is the IOC console log, where an abort prints its message,
`run-N.out` lists each assertion as one JSON line, `run-N.err` is the runner's
error output, `run-N.log.json` is the full record and `run-N.status` is the
runner's exit status.

With 150 runs the original driver is expected to abort at least once with
97 percent probability, and the fixed driver must report 150 passed. For the
original-behavior control, make a scratch copy of the repository whose
`measCompApp/src/drvMultiFunction.cpp` is the version from before the exit
handler, as described for the MAC cases, build it with its own `BUILD`, and run
the same commands from the root of the scratch copy. A clean result there does
not prove the absence of the race, only a failing run proves its presence.

## Static checks

Run these from this repository root. The Perl checks cover the four Perl
files of the test, their usage messages and the modules they load; the
compile checks cover the C++ files that the test builds. Run the Perl checks
on the host and, with the repository mounted read-only, in the image of the
Rocky 8 build environment, `jeonghanlee/rocky8-epics:1.2.2` (EPICS Base
7.0.10, asyn 4.45 and ULDAQ headers). The host commands need `podchecker`,
which Debian's `perl` package provides, and the Rocky 8 commands need Docker
and that image. The last two Perl commands must print `exit 2`. Every other
command must print no error; the compile prints deprecation warnings about
`rset`, which are expected.

```bash
for f in test_reconnect.pl build_reconnect.pl TC32.pm E1608.pm; do perl -I tests -wc tests/$f; podchecker tests/$f; done
for m in Cwd Digest::SHA File::Path File::Spec FindBin Getopt::Long JSON::PP Pod::Usage POSIX Time::HiRes Errno File::Basename IO::Handle IO::Select Scalar::Util IO::Socket::INET Socket; do perl -M$m -e1 || echo "missing $m"; done
perl tests/test_reconnect.pl --help
perl tests/build_reconnect.pl --help
perl tests/test_reconnect.pl --case invalid; echo "exit $?"
env -u BASE -u ASYN -u BUILD -u ULDAQ_INCLUDE -u ULDAQ_LIB perl tests/build_reconnect.pl; echo "exit $?"
```

```bash
docker run --rm --network none -v "$PWD":/w:ro jeonghanlee/rocky8-epics:1.2.2 bash -c 'cd /w && for f in test_reconnect.pl build_reconnect.pl TC32.pm E1608.pm; do perl -I tests -wc tests/$f; podchecker tests/$f; done'
docker run --rm --network none -v "$PWD":/w:ro jeonghanlee/rocky8-epics:1.2.2 bash -c 'B=/opt/epics/1.2.2/rocky-8.10/7.0.10; for f in measCompApp/src/drvMultiFunction.cpp tests/reconnect_ioc.cpp; do g++ -Wall -Wextra -fsyntax-only -Wno-write-strings -Wno-unused-parameter -I$B/base/include -I$B/base/include/os/Linux -I$B/base/include/compiler/gcc -I$B/modules/asyn-4.45.0/include -I$B/vendor/include -I/w/measCompApp/src /w/$f; done'
```

## Negative controls

Apply each change separately to a scratch copy of the named source, rebuild
with `build_reconnect.pl`, and run the complete test. A failure counts only at
the expected assertion or deadline; a build or setup failure is not a detected
driver defect.

| Mutation ID | Source change | Expected failure |
| --- | --- | --- |
| `no-reconnect` | Suppress the poller's automatic connect call | Offline startup recovery deadline |
| `early-tc-cache` | Update the TC parameter cache before the vendor call | `TC channel 0 type 2 survives failed write` |
| `no-restore` | Skip `restoreTemperatureConfig` after reconnect | `TC channel 0 type 2 survives failed write` |
| `ignore-auto` | Reconnect with auto-connect disabled | `autoconnect disabled but connected` |
| `ignore-enable` | Poll with the port disabled | `disabled port stops polling` |
| `no-channel-limit` | Remove the no-expansion temperature-count reduction | Startup recovery or an absent EXP-32 request; not currently detected |
| `no-digital-disconnect` | Omit the connection-error transition in `writeUInt32Digital` | `digital word error disconnects immediately` in `digital-word` |
| `overwrite-bit-error` | Remove the output bit loop's first-error break | `digital bit write preserves transport error` in `digital-bits` |
| `disconnect-any-error` | Disconnect on every digital vendor error | `digital non-transport error keeps connection` in `digital-control` |
| `no-enum-callback` | Omit enum publication | `startup TEST:A0Range record enums` in an offline enum case |
| `enum-address-zero` | Publish enums only at address 0 | `startup TEST:A7Range record enums` in `enum-e1608-offline` |
| `early-enum-callback` | Publish before `interruptAccept` without deferring | `startup TEST:A0Range record enums` in `enum-e1608-init` |
| `no-initial-enum` | Remove the initial `Unavailable` labels from the templates | `startup TEST:A0Range selection 0 maps to 1` in `enum-e1608-offline` |
| `no-mac-refresh` | Skip the inventory refresh in the MAC branch of `measCompCreateDevice` | Connection deadline in `mac-tc32-offline` |
| `refresh-releases-known` | After a refresh, repeat the IP address read for every inventory entry | `mac first port keeps its connection` in `mac-two-ports`; connection deadline of the first port in `mac-known-absent` |
| `refresh-rereads-known` | Repeat the IP address read for refreshed devices that are already known | `mac first port keeps its connection` in `mac-two-ports` |
| `refresh-no-dedupe` | Append every refreshed descriptor without comparing unique IDs | `mac first port keeps its connection` in `mac-two-ports` |
| `refresh-drops-known` | Replace the inventory with the devices that answer the refresh | `mac inventory keeps the absent known device` in `mac-known-absent` |
| `refresh-no-throttle` | Set the minimum interval between discovery attempts to zero | `mac rediscovery requests while absent` in `mac-tc32-offline`; `mac absent port shares bounded discovery` in `mac-two-ports` |
| `refresh-stalls-ports` | Hold the vendor lock for four seconds in every refresh | `mac first port continues polling` in `mac-two-ports` |
| `refresh-interval-equals-retry` | Set the minimum interval between discovery attempts to five seconds | `mac second device connects with its own value` in `mac-two-ports` when a refresh is skipped; the result varies with the retry phase |
| `endpoint-ignore-port` | Match a direct-discovery entry by IP address alone | `endpoint second port reads its device` in `endpoint-same-ip` and `endpoint-mixed` |
| `endpoint-no-default-port` | Record port 0 instead of the default discovery port for broadcast-discovered entries | `endpoint broadcast-discovered device is not queried again` in `endpoint-default-port`; the inventory stays correct because the direct query's result is matched by MAC, and `endpoint-mixed` is unaffected because a MAC selector never reaches the address lookup |
| `silent-retry-unspaced` | Keep the five-second interval after every failed connection attempt | `silent healthy port keeps polling` in `silent-device` |
| `silent-enable-keeps-spacing` | Do not reset the interval when the port or auto-connect is enabled again | `silent second port reconnects promptly after it is enabled again` in `silent-device` |
| `read-error-every-poll` | Report a repeated failure status of a thermocouple channel on every poll | `read error reported once per channel` in `read-error` |
| `read-error-ignores-code-change` | Compare only whether the status is zero, not its value, when deciding to report a channel | `a different error on a failing channel is reported again` in `read-error` |
| `read-error-keeps-state` | Do not clear the per-channel read status when the port connects | `read error reported again once per channel after reconnect` in `read-error` |
| `read-error-end-sets-message` | Set `LAST_ERROR_MESSAGE` when a channel returns to normal | `LAST_ERROR_MESSAGE keeps naming the failing channel` in `read-error` |
| `tin-per-channel` | End a run of channels at every channel, so each channel is read by its own `ulTInArray()` call | `temperature array one request per poll` in `temperature-array` |
| `tin-single-scale` | Ignore the scale of the following channels when forming a run | `temperature array one request per scale run` in `temperature-array` |
| `tin-no-timestamp` | Omit `updateTimeStamp()` after the reads | `temperature array timestamp is the time of the poll` in `temperature-array` |
| `tin-run-failure` | Treat the data of a request that failed for another reason as per-channel results | `temperature array request failure fails every channel and keeps the port connected` in `temperature-array` |
| `tin-tse-default` | Change the default of the `TSE` macro in the temperature template to -2 | `temperature array TSE macro defaults to 0` in `temperature-array` |
| `tin-call-status` | Give every channel of a request the status of the call | `temperature array open channel reads -9999 and stays valid` in `temperature-array` |

This test does not establish hardware power-cycle behavior, sustained network
loss endurance, Channel Access client reconnection, EXP-32, USB or Windows support.
