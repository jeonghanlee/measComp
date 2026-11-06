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

Enter an isolated namespace and create the two documentation-only addresses:

```bash
unshare -Urn bash
ip link set lo up
ip link add sim0 type dummy
ip addr add 192.0.2.1/24 dev sim0
ip link set sim0 up
ip addr add 192.0.2.2/32 dev lo
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

This test does not establish hardware power-cycle behavior, sustained network
loss endurance, Channel Access client reconnection, EXP-32, USB or Windows support.
