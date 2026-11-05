# TC32 reconnect test

The test compiles the repository's MultiFunction driver and device discovery
code, links real EPICS/asyn/ULDAQ libraries, and loads the shipped
`measCompTemperatureIn.template`. Only the external TC32 UDP/TCP transport is
simulated. Internal driver and library functions are not replaced.

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
socket event loop while the test waits for IOC responses.

The fixture starts offline, then becomes available. It sends a valid 22.5 C
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

## Negative controls

Apply each change separately to a scratch copy of the actual driver, rebuild
with `build_reconnect.pl`, and run the complete test. A failure counts only at
the expected assertion or deadline; a build or setup failure is not a detected
driver defect.

| Mutation ID | Driver change | Expected failure |
| --- | --- | --- |
| `no-reconnect` | Suppress the poller's automatic connect call | Offline startup recovery deadline |
| `early-tc-cache` | Update the TC parameter cache before the vendor call | `TC channel 0 type 2 survives failed write` |
| `no-restore` | Skip `restoreTemperatureConfig` after reconnect | `TC channel 0 type 2 survives failed write` |
| `ignore-auto` | Reconnect with auto-connect disabled | `autoconnect disabled but connected` |
| `ignore-enable` | Poll with the port disabled | `disabled port stops polling` |
| `no-channel-limit` | Remove the no-expansion temperature-count reduction | Startup recovery or an absent EXP-32 request; not currently detected |

This test does not establish hardware power-cycle behavior, sustained network
loss endurance, Channel Access client reconnection, EXP-32, USB or Windows support.
