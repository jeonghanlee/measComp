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

Digital output and direction writes apply the same transport-error handling
before returning, without waiting for another poll. A multi-bit operation stops
on its first vendor error; later bit writes cannot overwrite that result.
Earlier successful bit writes are not rolled back. Non-transport errors return
an error without disconnecting an otherwise healthy device.

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

## Analog enum initialization

After a successful connection, the poller publishes model-specific enum labels,
values and severities to every registered driver address. Publication waits until
IOC record initialization is complete, because asyn ignores enum callbacks while
`interruptAccept` is zero. Reconnection publishes the enums again.

The analog-input, voltage-input and analog-output templates define an initial
`Unavailable` state for their dynamic mbbo enums. This makes Base initialize
`SDEF=1` even when the device is offline. The model-specific enum replaces that
initial label after connection, and selecting an item then writes its numeric
enum value instead of its menu index. Custom mbbo templates using these dynamic
enums also need a nonempty initial state label with asyn 4.45.

Enum updates do not process output records or replay failed startup writes.
Reapply configuration after an offline start as described above. ADC conversion
coefficients are separate from enum metadata and selection conversion.

## Analog conversion bounds

`measCompAnalogIn.template` uses this repository's `measCompInt32Average`
device support. It delegates sample averaging and I/O interrupt handling to
asyn 4.45's `asynInt32Average`, and obtains ADC bounds separately through the
public asynInt32 interface. A successful query with `high > low` confirms the
bounds for the configured device's lifetime.

If startup is offline, record processing retries the bounds query. LINEAR
conversion remains INVALID until bounds are confirmed and a valid sample is
available. Confirming bounds alone does not validate an input. Before conversion,
the support calculates `ESLO=(EGUF-EGUL)/(high-low)` and
`EOFF=(high*EGUL-low*EGUF)/(high-low)`. Changing `EGUF` or `EGUL` recalculates
these coefficients; manual SLOPE coefficients remain under user control.

Periodic and Passive records use asyn's accumulated-sample average; I/O Intr
records retain its `SVAL` sample-count behavior. Missing samples and transport
errors retain invalid input alarms. The floating-point temperature and voltage
templates do not use this raw ADC conversion support.

Rebuild the IOC with `measCompSupport.dbd`, which includes `devMeasComp.dbd`,
and the asyn device support definitions. Custom raw analog templates need
`DTYP="measCompInt32Average"` with the existing `@asyn` input link to obtain
this behavior. After an offline start, apply the input Range and Type settings
through their records once enums are available; failed PINI writes are not
replayed by bounds recovery.

## MAC device rediscovery

A device selected by MAC address is looked up in the inventory built by the
startup broadcast discovery. When the MAC is not in the inventory, for example
because the device was powered off at startup, the connection attempt refreshes
the inventory with one new broadcast and searches again. The poller's connect
retry, at most once every five seconds per port, drives the attempts. The
refresh itself runs at most once every four seconds for the whole IOC, so
several ports waiting for absent devices share one broadcast. The interval is
shorter than the retry because a retry starts before it waits for the vendor
call lock; an equal interval would skip every second refresh under contention.
The auto-connect and port-enable settings apply as for any reconnection; while
either is off no discovery takes place.

A refresh queries Ethernet devices only and appends the devices whose MAC is
not yet in the inventory. Existing entries and the vendor device objects of
connected ports are never touched, so their handles stay valid. A broadcast
query waits 250 ms for each non-loopback IPv4 interface, and the vendor calls
of the other ports wait for the same time. Devices selected by IP address or a
resolvable host name use their own lookup and do not trigger a refresh; a name
that cannot be resolved is treated like a MAC address and triggers the same
bounded refresh. USB serial numbers never trigger one. MAC addresses and
serial numbers are matched without regard to case. A refresh whose vendor
query fails is reported once, and once more when the query succeeds again,
so a persistent failure does not flood the log. The refresh belongs to
the shared lookup, but a driver that calls it only once at construction, such
as `USBCTR`, does not retry: a MAC that is absent at that call is found only
if the single refresh allowed at that moment sees it. A known device that
later changes its IP address is not tracked; reconnection uses the last
discovery information. The Windows build uses the same logic and is not
verified.

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
ULDAQ and shipped EPICS temperature and binary-input templates against an external
UDP/TCP TC32 fixture.
It covers offline startup, EOF, incomplete headers, receive timeout, connection
policy, invalid input alarms, last-value retention and configuration restoration.
TC-type write failures are checked immediately through the public asynInt32
cache read interface and after reconnect through normal asynInt32 SyncIO reads.
Digital cases cover full-port write EOF, a non-final bit timeout, non-transport
errors, input alarms and last values before another poll, and recovery controls.
The TC32 fixture represents a device without EXP-32. Separate enum cases load
the shipped analog templates with TC32 metadata and an E-1608 protocol fixture.
They compare every enum state and actual record selection with public driver
readback after online startup, offline startup and reconnect. An E-1608 case
also connects while IOC record initialization is complete but enum callbacks
are still disabled.
Bounds cases verify TC32 24-bit metadata without claiming voltage acquisition.
E-1608 cases pass 16-bit raw values 0, 32768 and 65535 through real ULDAQ,
driver callbacks and periodic/I/O Intr analog records, then check coefficients
and engineering-unit values after startup, changed limits and reconnect.
They also check two-sample averaging, SLOPE preservation and missing samples.
MAC cases select a TC32 fixture by MAC address through broadcast discovery:
offline startup followed by availability, online startup with EOF,
auto-connect and port-disable controls, and two ports where a second device
appears while the first keeps its connection and inventory entry, or while the
first device is absent and its inventory entry must survive the refresh.
Real hardware power cycling, physical ADC calibration, analog output
voltage, scan acquisition, EXP-32, USB, Windows and other models require
separate verification.
