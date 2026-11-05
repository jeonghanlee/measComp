# MultiFunction reconnection

`MultiFunctionConfig` creates its parameters and poller even when the device is
offline. The port remains disconnected until the vendor library establishes a
physical connection. The poller retries at most once every five seconds while
the port is enabled and auto-connect is enabled. A vendor call can extend this
interval by its own timeout.

The driver uses the vendor library directly. `drvAsynIPPortConfigure` and its
`asynOption` settings do not control this connection. Use the port-level asyn
controls after `MultiFunctionConfig`, replacing `DAQ` with the configured port:

```text
asynAutoConnect("DAQ", -1, 1)
asynEnable("DAQ", -1, 1)
asynSetTraceMask("DAQ", -1, 1)
```

Setting auto-connect to zero prevents automatic reconnection. Disabling the port
also stops polling after any current poll completes. Enabling auto-connect and
the port resumes retries. The trace mask above keeps error messages enabled.

On a transport failure, the driver closes the vendor connection, notifies asyn
of disconnection, and sends error callbacks. Input records using I/O Intr retain
their last valid values with INVALID severity. Successful reads after reconnect
clear their input errors. `LAST_ERROR_MESSAGE` records the most recent error and
is cleared on connection or polling recovery. It is diagnostic text, not a
replacement for each input record's alarm status.

Successful thermocouple-type and open-detection writes are reapplied when the
device reconnects. Thermocouple-type readback changes only after a successful
write. A failed write retains the previous cache value; reconnection restores
the last successful type and keeps the cache consistent with that setting.
TC32 open detection is stored per 32-channel bank, so the last
successful write to any channel in a bank determines that bank's restored value.
Temperature scale and filter remain in the driver's parameter cache.
Writes attempted while disconnected are rejected, not queued for later replay.
If the IOC starts offline, reapply its output configuration after connection;
failed startup PINI writes are not automatically replayed. Waveform acquisition
and generation are marked stopped; output commands are not automatically replayed.

## Linux vendor dependency

Linux builds require ULDAQ 1.2.2 with the TCP receive patch maintained by
[`uldaq-env`](https://github.com/jeonghanlee/uldaq-env). Without the patch, EOF or
an incomplete TCP response header can be reported as success, allowing an invalid
measurement before a later call detects the disconnection. The patch returns a
connection error for these responses without changing complete-frame parsing.

Follow the `uldaq-env` source initialization and platform configuration
instructions. Its configuration targets apply the required patch; its build and
install targets reject missing, reverted or incompatible patches. From the
configured `uldaq-env` checkout, verify the patch, build and install:

```bash
make patch.check
make build
make install
```

Rebuild measComp and the IOC against the headers and library from that
installation. Confirm that the IOC loads the patched library at runtime;
rebuilding measComp alone does not install the dependency fix. Identify the
ULDAQ build by its source commit, patch state and library hash: the upstream
`UL_VERSION` string remains 1.2.0 in ULDAQ 1.2.2.

## Verification scope

The [reconnect test](../tests/README.md) runs the real MultiFunction driver, asyn,
ULDAQ and EPICS temperature template against an external UDP/TCP TC32 fixture.
It covers offline startup, EOF, incomplete headers, receive timeout, connection
policy, invalid input alarms, last-value retention and configuration restoration.
TC-type write failures are checked immediately through the public asynInt32
cache read interface and after reconnect through normal asynInt32 SyncIO reads.
The fixture represents a TC32 without EXP-32. Real hardware power cycling,
EXP-32, USB, Windows and other supported models require separate verification.
