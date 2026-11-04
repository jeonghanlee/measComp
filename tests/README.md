# TC32 reconnect test

The test compiles the repository's MultiFunction driver and device discovery
code, links real EPICS/asyn/ULDAQ libraries, and loads the shipped
`measCompTemperatureIn.template`. Only the external TC32 UDP/TCP transport is
simulated. Internal driver and library functions are not replaced.

## Prerequisites

- Linux with `g++`, Perl, Python 3.10 or later, `ip`, `unshare` and `timeout`.
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

```sh
export BASE=/opt/epics/base
export ASYN=/opt/epics/asyn
export ULDAQ_INCLUDE=/opt/uldaq/include
export ULDAQ_LIB=/opt/uldaq/lib
export BUILD=/tmp/meascomp-reconnect-test
python3 tests/build_reconnect.py
```

For an uninstalled ULDAQ build, use its `src` directory for headers and
`src/.libs` for libraries. The builder records the complete command and source
hashes and sets runtime library search paths to the supplied library directories.
Do not override those directories with an unrelated `LD_LIBRARY_PATH`.

Enter an isolated namespace and create the two documentation-only addresses:

```sh
unshare -Urn bash
ip link set lo up
ip link add sim0 type dummy
ip addr add 192.0.2.1/24 dev sim0
ip link set sim0 up
ip addr add 192.0.2.2/32 dev lo
```

Run the test inside that shell, then leave the namespace:

```sh
export TEMPLATE="$PWD/measCompApp/Db/measCompTemperatureIn.template"
timeout 100s python3 -B tests/test_reconnect.py "$BUILD/reconnect-ioc" "$BUILD/reconnect.dbd" "$TEMPLATE" "$BUILD/ioc.log"
exit
```

Success requires all assertions and normal IOC exit. A failed assertion or
missing required response exits nonzero. The JSON file beside `ioc.log` retains
observed checks, injected transport faults and the IOC exit status. Inspect both
the process exit status and JSON; a partial list of passing checks is not success.

The fixture starts offline, then becomes available. It sends a valid 22.5 C
baseline, tests EOF during the final temperature channel, a short digital-input response and
silence beyond ULDAQ's receive timeout, and verifies recovery within 12 seconds
of becoming available. Every failure must produce a disconnected port and INVALID
input severity without replacing the last valid temperature. Restored settings
must match the last successful writes, including conflicting bank-wide writes.
Auto-connect is disabled for six seconds to verify that it prevents retries;
port disable and enable must stop and resume polling. The fixture rejects
unexpected protocol commands and requests for absent EXP-32 channels.

This test does not establish hardware power-cycle behavior, sustained network
loss endurance, Channel Access client reconnection, EXP-32, USB or Windows support.
