# Network Thermocouple Acquisition

Release line: site (unversioned)
Milestone index: 9c39e49
Canonical path: `docs/milestone-9c39e49.md`
Canonical branch or ref: site
Git upstream: origin/site
Remote tracker: [jeonghanlee/measComp milestone 2](https://github.com/jeonghanlee/measComp/milestone/2)
GitHub milestone: Network thermocouple acquisition
Due date: none
Remote milestone observed at: 2026-11-08T09:41:22Z; state: open; four open issues (#12 to #15) and one closed issue (#11)
Recheck remote milestone with `gh api repos/jeonghanlee/measComp/milestones/2`.
Baseline commit: 9c39e491e463fac77f15cfcec16aa8b4a97cbf10

Next session entry point: Review and accept the plan of M2 (issue #12) in its detail, the nearest Ready row; then implement it. Post the pending comment on jeonghanlee/uldaq-env#3 that links commit 73a1164. Issues #11 to #15 are assigned to GitHub milestone 2.

## Scope

This document assigns issues #11 through #15, found by comparing the driver with ULDAQ 1.2.2, to five work units for the independently maintained `site` branch. It owns their scope, implementation plans, tests, verification results and closure evidence. GitHub retains only the live issue state, labels and milestone assignment. The previous generation, which completed issues #2 through #8, is kept at the prior-state commit named in History.

The common integration environment is Linux with the real measComp driver, EPICS Base 7.0.10, asyn 4.45 and patched ULDAQ 1.2.2. Extend the shipped Perl/Bash tests and retain `tests/reconnect_ioc.cpp`; use external device protocol fixtures, without replacing internal driver, asyn or ULDAQ functions. Record the source commit, dependency identities, assertions, fixture requests and native IOC exit status for each executed check. Checks reproducing a defect must fail for the intended assertion on the affected baseline and pass on the fixed code; setup and build failures do not establish a regression. Compatibility checks and positive controls must pass on both the baseline and fixed code. When a check combines these purposes, record the defect assertion separately from its controls.

**Out of scope:** changes to the ULDAQ library itself, which jeonghanlee/uldaq-env tracks, release numbering, tags, deployment, and a general qualification of Windows, USB or hardware power cycling. Changes to `docs/reconnection.md` and `tests/README.md` belong to the affected work unit when behavior or test invocation changes.

## Milestone

### Work

| ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| M1 | Silent device stalls other ports | Carry-forward | Complete | No | | A healthy port keeps polling beside a silent network device; issue #11; [detail](#m1---silent-device-stalls-other-ports) |
| M2 | Persistent read error logging | Carry-forward | Not started | Yes | | A persistent thermocouple read error is reported once per change; issue #12; [detail](#m2---persistent-read-error-logging) |
| M3 | Single-request thermocouple read and acquisition time | Carry-forward | Not started | Yes | | One temperature request per scale group per poll with one acquisition timestamp; issue #13; [detail](#m3---single-request-thermocouple-read-and-acquisition-time) |
| M4 | Thermocouple device diagnostics | Carry-forward | Not started | Yes | | Cold-junction temperatures, mains rejection and calibration information are exposed; issue #14; [detail](#m4---thermocouple-device-diagnostics) |
| M5 | Temperature filter on Linux | Carry-forward | Not started | Yes | | The temperature filter takes effect on Linux; issue #15; [detail](#m5---temperature-filter-on-linux) |

The row order follows issue numbers and imposes no execution dependency. Current status: one Complete and four Not started. `Ready` records dependency readiness only. No external prerequisite is established for these rows.

### Milestone Details

#### M1 - Silent Device Stalls Other Ports

Origin: 9c39e49 / M1
Identity History: none
GitHub Issue: [#11](https://github.com/jeonghanlee/measComp/issues/11)
Status: Complete

##### Summary

A network device that stops answering without closing its connection stalls the other ports of the same IOC: with a second TC32 device dropping packets after it had connected, a healthy TC32 port received about half the requests it receives beside a healthy second device (240 to 243 against 481 to 512 in 20 seconds over three runs each) and paused for up to 6.3 seconds instead of 0.76 seconds, in stalls of about 3.1 seconds that repeat every 5.5 seconds. The process-wide `ULMutex` is held for the whole poll and during `connect()`, while ULDAQ waits 3 seconds per connection and command. The shipped fixtures model an offline device as an immediate close, so the case was never exercised.

##### Scope

Space the reconnection attempts of a port by the time its failed attempts take once three consecutive attempts have failed, so a device that stays silent cannot hold the process-wide mutex for more than about a tenth of the time, while a short outage recovers with the existing 5-second retry. Narrowing the mutex per device is not part of this unit.

Out of scope: Changing the vendor timeouts, which jeonghanlee/uldaq-env#3 covers, splitting the process-wide mutex per device, the broadcast discovery wait, and the stalls during the first three attempts of an outage, about 15 seconds, which keep today's behavior.

##### Completion Criteria

- A shipped case runs a healthy TC32 port beside a second TC32 device that is dropped after it has connected, with a healthy-second-device control in the same case set.
- Beginning 25 seconds after the device goes silent, when the retry interval has grown, the healthy port's request count over a 40-second window is at least 80 percent of the control's, and no pause in that window is longer than 4 seconds.
- The first three consecutive failed attempts are each followed by the 5-second interval; after the third and later failures the interval is the larger of 5 seconds and 10 times that attempt's duration, capped at 60 seconds, and a successful connection resets both the interval and the count.
- The silent port is reported disconnected while the device is silent and reconnects with its own value within the capped interval after the device answers again.
- After a second outage long enough for the interval to be spaced, disabling and enabling the silent port again reconnects it within 12 seconds of the device answering.
- The existing cases pass unchanged.
- The linked issue is observed closed, or Closure Evidence records a dated exception limited to issue closure.
##### Dependencies And Decisions

- None. No work or external gate must complete first.
- Decision Date: 2026-11-08. The owner assigned this work to the Network thermocouple acquisition milestone, GitHub milestone 2.
- Decision Date: 2026-11-08. The owner chose to space the retry attempts by their duration and not to split the process-wide mutex per device: the vendor library keeps its device registry in a `std::map` without a lock, so concurrent calls on different devices would need a readers-writer lock and a thread-sanitizer check, and the mutex narrowing is revisited only if the spaced retries prove insufficient. The multiplier of 10 and the cap of 60 seconds are accepted with the plan.
- Decision Date: 2026-11-08. The spacing starts only after three consecutive failed attempts. An attempt to reconnect to an offline device does not fail at once: the vendor connection includes a discovery query and its timeouts, and in the shipped offline fixture an attempt took about 4 to 5 seconds. Spacing from the first failure therefore delayed every reconnection to 30 to 60 seconds and broke the 12-second recovery of the existing `reconnect` and `mac-known-absent` cases, observed on 2026-11-08 with 46 seconds between two attempts. Three attempts at the existing interval keep the recovery of a short outage unchanged.
##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-11-08; accepted by the owner after the first implementation, which spaced every retry from the first failure, was observed to break the recovery of the existing cases and the three-failure rule was proposed in its place.
Implementation Authorization: 2026-11-08; implement and verify the accepted plan items 1 to 3. Amended 2026-11-08 at the owner's direction after the first implementation review: enabling the port or auto-connect again resets the interval and the count, and the silent-device case covers it with a second outage and a test IOC command that enables the second port.
Superseded Plan Artifacts: the plan accepted on 2026-11-08 that spaced every retry from the first failed attempt, superseded the same day after it broke the recovery of the existing cases; its acceptance and authorization no longer apply.

1. In `measCompApp/src/drvMultiFunction.cpp`, measure the duration of each vendor connection attempt inside `connect()` after the process-wide mutex is held, so the wait for the mutex is not counted, count consecutive failed attempts, and keep a per-port retry interval that the reconnect gate uses in place of the fixed `RECONNECT_DELAY`: after the first and second consecutive failures the interval stays `RECONNECT_DELAY`, after the third and later failures it is the larger of `RECONNECT_DELAY` and 10 times that attempt's duration, capped at 60 seconds, and a successful attempt resets the interval and the count. The inventory refresh interval stays below the 5-second minimum, as the MAC rediscovery design requires. Verified by T1 and T2.
2. In `tests/test_reconnect.pl`, add a case where the second device is removed from the network after it has connected, with a control case where it stays healthy, and measure the healthy port's request count and longest pause from the fixture traffic. Verified by T1.
3. In `docs/reconnection.md` and `tests/README.md`, describe the adaptive retry interval and the new cases. Verified by T3.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Run the new silent-device case and its healthy control, three runs each, and compare the healthy port's requests and longest pause over the 40-second window that begins 25 seconds after the device goes silent; then make the device answer again and wait for the silent port; after a second spaced outage, disable and enable the silent port and wait for it again. Build the two negative controls of `tests/README.md` once each. | Common integration environment; two TC32 fixtures, the second one removed from the network | Request count at least 80 percent of the control, no pause longer than 4 seconds, the silent port reconnects within the capped interval and within 12 seconds after it is enabled again; the unchanged driver and the unspaced-retry control fail the request assertion, and the control that keeps the spacing on enable fails the enable assertion. |
| T2 | Regression | Run the 18 shipped cases, the 8 endpoint cases and the exit loop, the Perl checks on Debian 13 and Rocky 8 and the compile of the changed C++ files on Rocky 8. | Same environment; Perl 5.40.1 and 5.26.3 | All pass with normal IOC exit and their recovery deadlines unchanged. |
| T3 | Review | Read the changed `docs/reconnection.md` and `tests/README.md` as the operator who sets up the case. | Repository documents | The retry interval, its cap and the remaining first stall are described. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-08T07:35:35Z to 07:56:13Z | Debian 13; real IOC, Base 7.0.10, asyn 4.45.0, patched ULDAQ 1.2.2; two TC32 fixtures, the second one's address removed from the namespace after it connected | Pass: `silent-device` in four runs on the fixed driver (the README command and three more) passes its 8 assertions and gives 1.72 to 1.78 times the control's requests in the window that begins 25 seconds after the removal, a longest pause of 3.05 to 3.18 seconds; the second port reconnects with 37.25 within 16.9 to 17.5 seconds of the address returning, and within 2.1 to 2.6 seconds after it is enabled again following the second outage. The driver before this change, with the same tests, fails `silent healthy port keeps polling` in all three runs with 0.70 to 0.74 of the control's requests. The `silent-retry-unspaced` control fails the same assertion with 0.70; the `silent-enable-keeps-spacing` control passes the polling assertion with 1.72 and fails `silent second port reconnects promptly after it is enabled again` after 12.3 seconds. | `work/m1-silent/r2/`: `block6.out`, `silent-fixed-*`, `silent-base-*`, `mut-*-run` |
| T2 | 2026-11-08T07:29:30Z to 08:05:48Z | Same environment; Perl 5.40.1 and 5.26.3; Rocky 8 image | Pass: the 14 earlier cases pass 995 assertions, the 4 MAC cases 35 and the 8 endpoint cases 45 with their recovery deadlines unchanged and every IOC exit 0; the exit loop passes 150 of 150; the Perl checks pass on both versions; `drvMultiFunction.cpp` and `tests/reconnect_ioc.cpp` compile on Rocky 8 without error. | `work/m1-silent/r2/` |
| T3 | 2026-11-08 | Repository documents in the working tree of this verification | Pass: `docs/reconnection.md` describes the three five-second attempts, the spacing by ten times the attempt duration, the 60-second cap, the reset on enabling the port or auto-connect again and how long the port must stay disabled, and the remaining stalls that need ULDAQ changes; `tests/README.md` gives the silent-device command, its duration, its original-behavior control and two negative controls. | `docs/reconnection.md` section Silent devices; `tests/README.md` section Silent device case |

Source identity of the run: `drvMultiFunction.cpp` SHA-256 `b4e05e793c0ef94640be6a50c7e41973e520ee6a993eb40ce4ac478ec32934c7`; `test_reconnect.pl` `7c488bd86e5b119dff87609abe8e47103b1e8b99e496fa3a8755a8c21a4a2f7c`; `reconnect_ioc.cpp` `cc832ef9b638ecb09c6b7ff7b9600ec63bee305df9b4a2e2c350bf8d7cb4762e`; `build_reconnect.pl` `c9f049c2ba64934b717e0d27b49fcdd0941cfc472c1ef1da0bb993351478a400`; `exit_loop.bash` `5f4a0f6085a08021f94508424297302de8913745de940d53c2d59786f96f9826`. No source file changed between the start of the run and these hashes. The driver before this change is the committed `0dd4827` `drvMultiFunction.cpp` built with the final tests.

The healthy port's count rises above the control's because the silent port stops polling while it is disconnected, so the ratio measures how much of the window the silent port's attempts block. The original driver's 0.70 to 0.74 lies 0.06 below the 0.8 threshold, and the fixed driver's lowest value lies 0.92 above it.

##### Closure Evidence

- Measured 2026-11-08 with the shipped harness and TC32 fixtures in a network namespace, in a two-port IOC over a 20-second window, three runs per condition: with the second device healthy 481, 512 and 483 requests and a longest pause of 0.71 to 0.76 seconds; with the second device's address removed after it had connected 240, 243 and 242 requests and a longest pause of 6.1 to 6.3 seconds. A comparison with an IOC whose second port was never created (10,302 requests) was an unlike baseline and is not used. The request trace shows 3.1 to 3.2 second stalls every 5.5 seconds, the length of one failed connection attempt under the process-wide mutex. No plan is accepted yet.
- Observed 2026-11-08 with a first implementation that spaced every retry from the first failure: `reconnect` and `mac-known-absent` exceeded their 12-second recovery deadline, with 46 seconds between two attempts in `reconnect`, while `bounds-tc32-offline`, `bounds-e1608-offline`, `enum-e1608-init`, `mac-tc32-offline` and `endpoint-wrong-port` passed. The local evidence is under `work/m1-silent/early/`.
- Landed: observed 2026-11-08T09:41:22Z after `git fetch`, `origin/site` is at commit 73a116466c52277443b666a3a2fe24588280def8, the same commit as the local `HEAD`, and the six changed paths of that commit (`measCompApp/src/drvMultiFunction.cpp`, `tests/reconnect_ioc.cpp`, `tests/test_reconnect.pl`, `tests/README.md`, `docs/reconnection.md`, `docs/milestone-9c39e49.md`) show no difference between that commit and `origin/site`. Recheck with `git diff 73a1164 origin/site -- <path>`.
- Issue: the owner delegated the issue operations on 2026-11-08; the body was synchronized with the implemented rule and its five acceptance criteria were checked, a closing comment was posted and issue #11 was closed as completed at 2026-11-08T09:31:22Z. The read-back shows state CLOSED, label bug and milestone 2.
- Remaining stalls: the 3-second stall of each attempt to a silent device needs the configurable timeouts of jeonghanlee/uldaq-env#3, and the lock cannot be split per device until the vendor registry is protected; both stay outside this unit.

##### GitHub Projection

Title: Keep a silent network device from stalling the other ports of the IOC
Labels: bug
GitHub Milestone: Network thermocouple acquisition (milestone 2)
Observed State: closed
Observed Labels: bug
Observed Milestone: Network thermocouple acquisition (milestone 2)
Last Compared: 2026-11-08T09:41:22Z; remote updated at 2026-11-08T09:31:22Z

#### M2 - Persistent Read Error Logging

Origin: 9c39e49 / M2
Identity History: none
GitHub Issue: [#12](https://github.com/jeonghanlee/measComp/issues/12)
Status: Not started

##### Summary

A TC32 channel outside the common-mode range makes `ulTIn()` return `ERR_CMR_EXCEEDED` on every read, and the poller calls `reportError()` for the channel on every poll: with the fixture reporting the condition on every channel, the IOC printed 3,040 error lines in about five seconds while the records stayed INVALID with their last value.

##### Scope

Report a channel's read error when its status changes and once when it returns to normal, keeping the per-channel INVALID status on every poll and the open-thermocouple value.

Out of scope: Connection errors, the open-thermocouple value and other boards' read paths.

##### Completion Criteria

- A persistent condition produces one line when it starts and one when it ends.
- The record is INVALID while the condition lasts and recovers afterwards.
- `LAST_ERROR_MESSAGE` names the condition while it lasts.
- A shipped case drives the condition from the TC32 fixture and counts the lines, and the existing cases pass unchanged.
- The linked issue is observed closed, or Closure Evidence records a dated exception limited to issue closure.

##### Dependencies And Decisions

- None. No work or external gate must complete first.
- Decision Date: 2026-11-08. The owner assigned this work to the Network thermocouple acquisition milestone, GitHub milestone 2.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Implement the change described in Scope in `measCompApp/src/drvMultiFunction.cpp` with the shipped test case named in the Completion Criteria. Verified by T1.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Run the new shipped case and the existing cases with the README commands. | Common integration environment | The Completion Criteria hold and the existing cases pass. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | Common integration environment | Pending | none |

##### Closure Evidence

- Measured 2026-11-08 with the shipped harness and the TC32 fixture returning the common-mode sentinel -7777: 3,040 lines in about five seconds, severity INVALID, value held at 22.5. No plan is accepted yet.

##### GitHub Projection

Title: Report a persistent thermocouple read error once instead of on every poll
Labels: bug
GitHub Milestone: Network thermocouple acquisition (milestone 2)
Observed State: open
Observed Labels: bug
Observed Milestone: Network thermocouple acquisition (milestone 2)
Last Compared: 2026-11-08T05:09:19Z; remote updated at 2026-11-08T05:09:15Z

#### M3 - Single Request Thermocouple Read And Acquisition Time

Origin: 9c39e49 / M3
Identity History: none
GitHub Issue: [#13](https://github.com/jeonghanlee/measComp/issues/13)
Status: Not started

##### Summary

The poller reads the TC32 and E-TC one channel per `ulTIn()`, which ULDAQ implements as a one-channel `tInArray()`, so each channel costs its own request under the process-wide mutex, the channels of one poll are read at different moments, and the driver never sets the asyn timestamp.

##### Scope

Read each poll with `ulTInArray()` grouped by temperature scale, take per-channel results from the -9999 and -7777 values the call fills in before returning a range-wide status, and call `updateTimeStamp()` once after the read.

Out of scope: USB thermocouple boards, the default poll period and the posting of unchanged values.

##### Completion Criteria

- One temperature request per scale group per poll on the TC32 and E-TC fixtures, counted from the fixture traffic.
- All channels of a poll carry one timestamp, usable with `TSE=-2`.
- Open and out-of-range channels are handled per channel without affecting the others.
- Per-channel scales keep their values, and the existing cases pass unchanged.
- The linked issue is observed closed, or Closure Evidence records a dated exception limited to issue closure.

##### Dependencies And Decisions

- None. No work or external gate must complete first.
- Decision Date: 2026-11-08. The owner assigned this work to the Network thermocouple acquisition milestone, GitHub milestone 2.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Implement the change described in Scope in `measCompApp/src/drvMultiFunction.cpp` with the shipped test case named in the Completion Criteria. Verified by T1.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Run the new shipped case and the existing cases with the README commands. | Common integration environment | The Completion Criteria hold and the existing cases pass. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | Common integration environment | Pending | none |

##### Closure Evidence

- Found 2026-11-08 by reading `AiETc32::tIn()`, `AiETc32::tInArray()`, `AiETc::tInArray()` and the poller; not measured. No plan is accepted yet.

##### GitHub Projection

Title: Read all thermocouple channels in one request and stamp the acquisition time
Labels: enhancement
GitHub Milestone: Network thermocouple acquisition (milestone 2)
Observed State: open
Observed Labels: enhancement
Observed Milestone: Network thermocouple acquisition (milestone 2)
Last Compared: 2026-11-08T05:09:19Z; remote updated at 2026-11-08T05:09:16Z

#### M4 - Thermocouple Device Diagnostics

Origin: 9c39e49 / M4
Identity History: none
GitHub Issue: [#14](https://github.com/jeonghanlee/measComp/issues/14)
Status: Not started

##### Summary

ULDAQ implements, and the driver does not expose, the cold-junction temperatures, the TC32 50 or 60 Hz rejection, the calibration table selection and the calibration dates of the network TC32 and E-TC.

##### Scope

Add parameters and records for these items and restore the settings after a reconnect as for the thermocouple type.

Out of scope: Other boards, alarm outputs and calibration itself.

##### Completion Criteria

- The cold-junction temperatures are read on every poll.
- The rejection frequency and calibration table can be set, read back and survive a reconnect.
- The calibration dates are readable after connection.
- The fixtures implement the commands, a shipped case checks each item, and the existing cases pass unchanged.
- The linked issue is observed closed, or Closure Evidence records a dated exception limited to issue closure.

##### Dependencies And Decisions

- None. No work or external gate must complete first.
- Decision Date: 2026-11-08. The owner assigned this work to the Network thermocouple acquisition milestone, GitHub milestone 2.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Implement the change described in Scope in `measCompApp/src/drvMultiFunction.cpp` with the shipped test case named in the Completion Criteria. Verified by T1.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Run the new shipped case and the existing cases with the README commands. | Common integration environment | The Completion Criteria hold and the existing cases pass. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | Common integration environment | Pending | none |

##### Closure Evidence

- Found 2026-11-08 by reading the ULDAQ `AiETc32` and `AiETc` implementations against the driver; not measured. No plan is accepted yet.

##### GitHub Projection

Title: Expose the cold-junction temperatures, mains rejection and calibration information of the network thermocouple devices
Labels: enhancement
GitHub Milestone: Network thermocouple acquisition (milestone 2)
Observed State: open
Observed Labels: enhancement
Observed Milestone: Network thermocouple acquisition (milestone 2)
Last Compared: 2026-11-08T05:09:19Z; remote updated at 2026-11-08T05:09:18Z

#### M5 - Temperature Filter On Linux

Origin: 9c39e49 / M5
Identity History: none
GitHub Issue: [#15](https://github.com/jeonghanlee/measComp/issues/15)
Status: Not started

##### Summary

The `$(P)$(R)Filter` record writes `TEMPERATURE_FILTER`, which the Windows path passes to `cbTIn()`, but `ulTIn()` has no filter and the Linux path ignores the value, so the setting is accepted and has no effect.

##### Scope

Apply the filter in the driver on Linux by averaging successive readings, following the meaning of the Windows option.

Out of scope: Boards not read through `ulTIn()` and the Windows behavior.

##### Completion Criteria

- With the filter enabled, the published value is the average defined by the Windows behavior; disabled, it is the latest reading.
- The setting survives a reconnect.
- A shipped case checks filtered and unfiltered values, and the existing cases pass unchanged.
- The linked issue is observed closed, or Closure Evidence records a dated exception limited to issue closure.

##### Dependencies And Decisions

- None. No work or external gate must complete first.
- Decision Date: 2026-11-08. The owner assigned this work to the Network thermocouple acquisition milestone, GitHub milestone 2.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Implement the change described in Scope in `measCompApp/src/drvMultiFunction.cpp` with the shipped test case named in the Completion Criteria. Verified by T1.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Run the new shipped case and the existing cases with the README commands. | Common integration environment | The Completion Criteria hold and the existing cases pass. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | Common integration environment | Pending | none |

##### Closure Evidence

- Found 2026-11-08 by reading the poller and the template; not measured. The exact Windows averaging is taken from the Universal Library documentation before implementation. No plan is accepted yet.

##### GitHub Projection

Title: Make the temperature filter setting take effect on Linux
Labels: bug
GitHub Milestone: Network thermocouple acquisition (milestone 2)
Observed State: open
Observed Labels: bug
Observed Milestone: Network thermocouple acquisition (milestone 2)
Last Compared: 2026-11-08T05:09:19Z; remote updated at 2026-11-08T05:09:19Z

## Backlog

### Work

| ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| M6 | USB counter poller exit race | Carry-forward | Open | No |  | `drvUSBCTR.cpp` stops its poller before the process exits, as the multifunction driver does; priority and scope are undecided; [detail](#m6---usb-counter-poller-exit-race) |
| M7 | Generator transport-error handling | Carry-forward | Blocked | No | G1 | A transport error in a generator write disconnects the port and the first error code is kept; the network temperature devices are unchanged; [detail](#m7---generator-transport-error-handling) |
| M8 | Open-detect result on input type change | Carry-forward | Blocked | No | G1 | A connection error from the open-detect call in the input-type branch disconnects the port; [detail](#m8---open-detect-result-on-input-type-change) |
| G1 | USB board for hardware verification | External gate | Open | No |  | A USB board that exercises M7 or M8 is available and its model is recorded; [detail](#g1---usb-board-for-hardware-verification) |

### Backlog Details

#### M6 - USB Counter Poller Exit Race

Origin: 9c39e49 / M6
Identity History: none
GitHub Issue: none
Status: Open

##### Summary

`measCompApp/src/drvUSBCTR.cpp` starts a `USBCTRPoller` thread with `epicsThreadCreate()` and its loop runs in `while(1)` with no stop condition and no join, the pattern that makes a two-port multifunction IOC abort while exiting when the vendor library deletes its devices during `exit()`. The same exit race is therefore likely, but it was not reproduced: the file includes `drvMca.h` from the separate `mca` module, which is absent from the available build environment, so it could not be compiled or run here.

##### Scope

Decide whether the USB counter driver gets the same stop and join exit handler, and how it is built and verified without the missing module.

Out of scope: the multifunction driver, which is fixed separately, and Windows.

##### Completion Criteria

- The owner decides the priority and the verification environment, and the row is then moved to Not started, Deferred or retired with a dated decision.

##### Dependencies And Decisions

- None recorded. Verification needs a build environment that provides the `mca` module headers.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Reproduce the exit abort on a build that includes the `mca` module, then apply the stop and join exit handler and rerun the same loop.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | A counted loop of normal exits of an IOC that configures the USB counter driver. | An environment that provides the `mca` module and a counter device or protocol fixture | Every exit has status 0 and no sanitizer report; the unchanged driver aborts in some exits. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | Environment with the `mca` module | Pending | none |

##### Closure Evidence

- Observed 2026-11-07 while reviewing the multifunction exit fix: `drvUSBCTR.cpp` lines 434 and 1499 show the thread creation and the unconditional loop. The build verification of this file was declined on 2026-11-06 and is recorded in `docs/CLOSED_DOORS.md`; this row concerns the exit pattern, not that build verification.

##### GitHub Projection

Title: none
Labels: none
GitHub Milestone: none
Observed State: none
Observed Labels: none
Observed Milestone: none
Last Compared: never

#### M7 - Generator Transport Error Handling

Origin: 9c39e49 / M7
Identity History: none
GitHub Issue: [#9](https://github.com/jeonghanlee/measComp/issues/9)
Status: Blocked (prior status: Not started)

##### Summary

`writeFloat64()` restarts a running pulse generator or waveform generator with vendor calls and returns `asynError` on a failure without disconnecting the port, unlike `writeInt32()` and `writeUInt32Digital()`. The stop and restart pairs at five sites accumulate their status with a bitwise OR, and 12 of the 21 pairs of different connection-error codes combine into a code that `isConnectionError()` rejects. Found by reading the code on 2026-11-07 and not reproduced. The paths run on the USB boards with a pulse generator (USB-1608G, USB-1608HS-2AO, USB-1808) or an analog output scan, and the digitizer restart also on the network E-1608; the network temperature devices TC32 and E-TC reach none of them.

##### Scope

Add the connection-error disconnect to `writeFloat64()` and keep the first non-zero error code at the five OR sites.

Out of scope: the pulse generator running state in `disconnect()`, whose handling depends on how the vendor library leaves a running timer after a transport loss, the reconnection policy, discovery and the poller.

##### Completion Criteria

- A transport error from a generator stop or restart in `writeFloat64()` disconnects the port and marks the inputs disconnected.
- Different connection-error codes from the stop and the restart still disconnect the port at all five sites.
- The shipped cases, including the network temperature device cases, pass unchanged.
- A hardware check on a USB board with a pulse generator or waveform generator records the disconnect, with the board model and library version.
- The linked issue is observed closed, or Closure Evidence records a dated exception limited to issue closure.

##### Dependencies And Decisions

- G1: the hardware check needs a USB board; the regression checks do not.
- Decision Date: 2026-11-08. The owner decided to fix both this item and M8 and to keep them in the Backlog for now; the USB board is not known to exist.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. In `measCompApp/src/drvMultiFunction.cpp`, replace the OR accumulation at the five sites by a first-error accumulation and add the `isConnectionError()` and `disconnect()` step to `writeFloat64()` after the vendor mutex is released. Verified by T1 and T2.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Regression | Run the 18 shipped cases and the 8 endpoint cases, the Perl checks on Debian 13 and Rocky 8 and the compile of the changed C++ files on Rocky 8; the cases that use the TC32 and E-TC protocol fixtures are the guard for the network temperature devices. | Common integration environment; Rocky 8 image | All pass with normal IOC exit; the changed files compile on Rocky 8. |
| T2 | Hardware | Unplug a USB board with a pulse generator or waveform generator while a generator parameter changes and read the port state and log. | A USB board that has the feature (G1) | The port is disconnected and the inputs are marked disconnected. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | Common integration environment | Pending | none |
| T2 | Not run | USB board (G1) | Pending | none |

##### Closure Evidence

- Found 2026-11-07 during a coherence review of the completed work units, confirmed by reading the code and by computing the error-code combinations from `uldaq.h`; not reproduced. No plan is accepted yet.

##### GitHub Projection

Title: Disconnect on transport errors when generator settings change and keep the first error code
Labels: bug
GitHub Milestone: none
Observed State: open
Observed Labels: bug
Observed Milestone: none
Last Compared: 2026-11-08T02:31:58Z; remote updated at 2026-11-08T02:31:48Z

#### M8 - Open Detect Result On Input Type Change

Origin: 9c39e49 / M8
Identity History: none
GitHub Issue: [#10](https://github.com/jeonghanlee/measComp/issues/10)
Status: Blocked (prior status: Not started)

##### Summary

When the analog input type changes to thermocouple, `writeInt32()` calls `setOpenThermocoupleDetect()` and drops its return value, while the other callers keep it, so a transport error in that call leaves the port connected and the write reporting success. The call is from the original upstream code and its siblings were changed when the thermocouple settings were made consistent after a reconnect. Found by reading the code on 2026-11-07 and not reproduced. The branch runs only on the USB-2408-2AO, the one board with a configurable input type; the network temperature devices TC32 and E-TC never run it.

##### Scope

Store the result of the open-detect call in the status that the end of `writeInt32()` classifies, keeping the first non-zero error code.

Out of scope: other boards, the restore of the thermocouple settings after a reconnect and the reconnection policy.

##### Completion Criteria

- A connection error from the open-detect call in the input-type branch disconnects the port and `writeInt32()` returns `asynError`.
- A non-transport error from that call returns `asynError` without disconnecting a healthy device.
- The shipped cases, including the network temperature device cases, pass unchanged.
- A hardware check on a USB-2408-2AO records the disconnect when the board is unplugged during the input type switch, with the board model and library version.
- The linked issue is observed closed, or Closure Evidence records a dated exception limited to issue closure.

##### Dependencies And Decisions

- G1: the hardware check needs a USB-2408-2AO; the regression checks do not.
- Decision Date: 2026-11-08. The owner decided to fix both this item and M7 and to keep them in the Backlog for now; the USB board is not known to exist.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. In `measCompApp/src/drvMultiFunction.cpp`, assign the result of the open-detect call in the input-type branch of `writeInt32()` to the status, keeping the first non-zero error code. Verified by T1 and T2.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Regression | Run the 18 shipped cases and the 8 endpoint cases, the Perl checks on Debian 13 and Rocky 8 and the compile of the changed C++ files on Rocky 8; the cases that use the TC32 and E-TC protocol fixtures are the guard for the network temperature devices. | Common integration environment; Rocky 8 image | All pass with normal IOC exit; the changed file compiles on Rocky 8. |
| T2 | Hardware | Unplug a USB-2408-2AO while the input type switches from voltage to thermocouple and read the port state and log. | A USB-2408-2AO (G1) | The port is disconnected and the write returns `asynError`. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | Common integration environment | Pending | none |
| T2 | Not run | USB-2408-2AO (G1) | Pending | none |

##### Closure Evidence

- Found 2026-11-07 during a coherence review of the completed work units, confirmed by reading the code and the commit history of the call sites; not reproduced. No plan is accepted yet.

##### GitHub Projection

Title: Check the open thermocouple detection result when the analog input type changes
Labels: bug
GitHub Milestone: none
Observed State: open
Observed Labels: bug
Observed Milestone: none
Last Compared: 2026-11-08T02:31:58Z; remote updated at 2026-11-08T02:31:50Z

#### G1 - USB Board For Hardware Verification

Origin: 9c39e49 / G1
GitHub Issue: none
Status: Open

##### Summary

M7 and M8 need a hardware check on a USB board: M7 on a board with a pulse generator (USB-1608G, USB-1608HS-2AO or USB-1808) or a waveform generator, M8 on a USB-2408-2AO. The owner has not confirmed that a USB board exists or which model it is. The responsible party is the owner; the affected work is M7 and M8. The regression checks of both do not depend on this gate.

##### Completion Criteria

- The owner confirms a USB board and its model, and the model is one of the boards that exercise M7 or M8, or the owner decides to waive the hardware check with a dated decision.

##### Verification Results

| Observed At | Result | Evidence |
| --- | --- | --- |
| 2026-11-08 | Pending | The owner does not know the model or whether the board exists. |

##### Closure Evidence

- none

## History

| Reset Date | Prior State Commit |
| --- | --- |
| 2026-11-08 | 9c39e491e463fac77f15cfcec16aa8b4a97cbf10 |
