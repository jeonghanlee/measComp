# Network Thermocouple Acquisition

Release line: site (unversioned)
Milestone index: 9c39e49
Canonical path: `docs/milestone-9c39e49.md`
Canonical branch or ref: site
Git upstream: origin/site
Remote tracker: [jeonghanlee/measComp milestone 2](https://github.com/jeonghanlee/measComp/milestone/2)
GitHub milestone: Network thermocouple acquisition
Due date: none
Remote milestone observed at: 2026-11-11T16:15:34Z; state: open; no open issue and five closed issues (#11 to #15)
Recheck remote milestone with `gh api repos/jeonghanlee/measComp/milestones/2`.
Baseline commit: 9c39e491e463fac77f15cfcec16aa8b4a97cbf10

Next session entry point: No row of the Milestone is open and all five issues of GitHub milestone 2 (#11 to #15) are closed; M11 (document the mixed value of the averaging temperature record) is Complete; the Backlog still has M9, narrowed to the two analog input reads at a low priority and still Open, and M10, which is Open and needs an owner decision on its priority and fixture scope before a plan of its own with an E-TC fixture can be written. The work for USB boards (the exit of the USB counter poller, the generator transport error and the open-detect result at an input type change) was taken out on 2026-11-11 because the site has no USB board; it is recorded in `docs/CLOSED_DOORS.md`, and GitHub issues #9 and #10 of the last two were closed as not planned on 2026-11-11. The new TC-32 diagnostic records reach the site only after the distribution moves its measComp pin (`SRC_TAG_MEASCOMP`, now `c38974e` in `configure/RELEASE` of the EPICS-env repository) to a commit of this branch, and after the site database of the tcmd repository loads them; the owner asked the EPICS-env session on 2026-11-11 to use the new measComp at its next release, where the pin is the decision of that session's owner, and the tcmd session was told to wait for that. The fixture can use the per-channel values and the request shape that the single-request read added to `tests/TC32.pm`.

## Scope

This document assigns issues #11 through #15, found by comparing the driver with ULDAQ 1.2.2, to five work units for the independently maintained `site` branch. It owns their scope, implementation plans, tests, verification results and closure evidence. GitHub retains only the live issue state, labels and milestone assignment. The previous generation, which completed issues #2 through #8, is kept at the prior-state commit named in History.

The common integration environment is Linux with the real measComp driver, EPICS Base 7.0.10, asyn 4.45 and patched ULDAQ 1.2.2. Extend the shipped Perl/Bash tests and retain `tests/reconnect_ioc.cpp`; use external device protocol fixtures, without replacing internal driver, asyn or ULDAQ functions. Record the source commit, dependency identities, assertions, fixture requests and native IOC exit status for each executed check. Checks reproducing a defect must fail for the intended assertion on the affected baseline and pass on the fixed code; setup and build failures do not establish a regression. Compatibility checks and positive controls must pass on both the baseline and fixed code. When a check combines these purposes, record the defect assertion separately from its controls.

**Out of scope:** changes to the ULDAQ library itself, which jeonghanlee/uldaq-env tracks, release numbering, tags, deployment, and a general qualification of Windows, USB or hardware power cycling. Changes to `docs/reconnection.md` and `tests/README.md` belong to the affected work unit when behavior or test invocation changes.

## Milestone

### Work

| ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| M1 | Silent device stalls other ports | Carry-forward | Complete | No | | A healthy port keeps polling beside a silent network device; issue #11; [detail](#m1---silent-device-stalls-other-ports) |
| M2 | Persistent read error logging | Carry-forward | Complete | No | | A persistent thermocouple read error is reported once per change; issue #12; [detail](#m2---persistent-read-error-logging) |
| M3 | Single-request thermocouple read and acquisition time | Carry-forward | Complete | No | | One temperature request per scale group per poll with one acquisition timestamp; issue #13; [detail](#m3---single-request-thermocouple-read-and-acquisition-time) |
| M4 | Thermocouple device diagnostics | Carry-forward | Complete | No | | Cold-junction temperatures, mains rejection and calibration information are exposed; issue #14; [detail](#m4---thermocouple-device-diagnostics) |
| M5 | Temperature filter on Linux | Carry-forward | Complete | No | | The documentation states that the temperature filter record has no effect on Linux and names the TC-32 filter control; issue #15; [detail](#m5---temperature-filter-on-linux) |

The row order follows issue numbers and imposes no execution dependency. Current status: five Complete. `Ready` records dependency readiness only. No external prerequisite is established for these rows.

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

- Measured 2026-11-08 with the shipped harness and TC32 fixtures in a network namespace, in a two-port IOC over a 20-second window, three runs per condition: with the second device healthy 481, 512 and 483 requests and a longest pause of 0.71 to 0.76 seconds; with the second device's address removed after it had connected 240, 243 and 242 requests and a longest pause of 6.1 to 6.3 seconds. A comparison with an IOC whose second port was never created (10,302 requests) was an unlike baseline and is not used. The request trace shows 3.1 to 3.2 second stalls every 5.5 seconds, the length of one failed connection attempt under the process-wide mutex. No plan had been accepted at that time; it was accepted on 2026-11-08.
- Observed 2026-11-08 with a first implementation that spaced every retry from the first failure: `reconnect` and `mac-known-absent` exceeded their 12-second recovery deadline, with 46 seconds between two attempts in `reconnect`, while `bounds-tc32-offline`, `bounds-e1608-offline`, `enum-e1608-init`, `mac-tc32-offline` and `endpoint-wrong-port` passed. The local evidence is under `work/m1-silent/early/`.
- Landed: observed 2026-11-08T09:41:22Z after `git fetch`, `origin/site` is at commit 73a116466c52277443b666a3a2fe24588280def8, the same commit as the local `HEAD`, and the six changed paths of that commit (`measCompApp/src/drvMultiFunction.cpp`, `tests/reconnect_ioc.cpp`, `tests/test_reconnect.pl`, `tests/README.md`, `docs/reconnection.md`, `docs/milestone-9c39e49.md`) show no difference between that commit and `origin/site`. Recheck with `git diff 73a1164 origin/site -- <path>`.
- Issue: the owner delegated the issue operations on 2026-11-08; the body was synchronized with the implemented rule and its five acceptance criteria were checked, a closing comment was posted and issue #11 was closed as completed at 2026-11-08T09:31:22Z. The read-back shows state CLOSED, label bug and milestone 2.
- Remaining stalls: the 3-second stall of each attempt to a silent device needs the configurable timeouts of jeonghanlee/uldaq-env#3, and the lock cannot be split per device until the vendor registry is protected; both stay outside this unit.

- Observed 2026-11-09 on a real TC-32 by the session that has the device, with the commit 4884b71 built in a scratch copy and one IOC running without a restart: after a network-cable pull of about 208 seconds and a power-off of about 253 seconds the Ti records went INVALID within a second and kept their last value, one read error line appeared at the onset, and the failed-connection lines came first three times 5.12 seconds apart and then 30.5 to 32.3 seconds apart, never above 60 seconds, 8 and 10 of them in all, with `LAST_ERROR_MESSAGE` holding the connection failure until recovery. The records were valid again 15 seconds after the device answered a ping following the power-off, and 33 seconds after it following the cable pull, where the attempt made two seconds after the ping failed and the next retry succeeded; the poll period returned to about 52.5 ms. The device was observed by ping at half-second steps, so onset and return are known to about a second. The effect on a second port could not be observed with one device.

- Observed 2026-11-09 on the same TC-32 by the session that has the device, scratch builds of the commits named: the build before the retry spacing (0dd4827) kept one connection attempt every 5 seconds through a cable pull of about 607 seconds, 120 failed-connection lines 4.86 to 5.12 seconds apart, and the records were valid again about 3.5 seconds after the device answered a ping; build 4884b71 made about 20 lines for the same length of outage by the intervals measured above (arithmetic, not a measurement). In one IOC process without a restart a cable pull and then a power-off each started again with three attempts 5.12 seconds apart before the intervals grew, so the delay returns to five seconds after a successful connection. A power-off of about 7 minutes of the site IOC made 15 failed-connection lines, three at about 5.1 seconds and then 30 to 32 seconds apart.
- Observed 2026-11-09 for a device that stays linked and stops answering: a host rule dropped every packet from the device while the link stayed up and was removed about 11 minutes later. One read error line appeared at the onset (the time at which the rule was added was not recorded, so the delay between the rule and the line is not known), the records went INVALID holding their value, and the failed-connection lines came three times 5.12 seconds apart and then 30.5 to 32.3 seconds apart, 24 in all and none for each poll; each failed attempt took about 3 seconds, so the interval of ten times the attempt was about 30 seconds, and the 60-second cap was not reached. The records were valid at the first attempt after the rule was removed. Reaching the cap needs attempts longer than 6 seconds, which this test did not produce.
- Observed 2026-11-09 during a cable pull when the retry interval was already about 30 seconds: `asynEnable` and `asynAutoConnect` set to 0 and then 1 with the port address -1 restarted the five-second spacing (the next attempt came 5.4 and 5.6 seconds after the previous one, then three attempts at about 5 seconds, then 30 seconds); the same `asynEnable` with the device address 0 did not (the next attempt came 30.3 seconds later), because address 0 is a device address and the port-level connection is address -1. The command with address 0 for auto-connect was not tried. The commands were sent to the IOC console through its socket.
- Not verified on hardware: the 60-second cap, and the effect of a silent device on a second port, which needs a second device.

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
Status: Complete

##### Summary

A TC32 channel outside the common-mode range makes `ulTIn()` return `ERR_CMR_EXCEEDED` on every read, and the poller calls `reportError()` for the channel on every poll: with the fixture reporting the condition on every channel, the IOC printed 3,040 error lines in about five seconds while the records stayed INVALID with their last value.

##### Scope

Report a thermocouple channel's read error once when its status changes, with the channel number in the line, and once when the channel returns to normal at the same error trace level, keeping the per-channel INVALID status on every poll and the open-thermocouple value. The per-channel state starts over when the port connects and when a channel leaves the thermocouple type.

Out of scope: Connection errors, the open-thermocouple value, the other read calls of the poll loop, of which only the analog input reads print on every poll and which M9 tracks, and Windows verification.

##### Completion Criteria

- A persistent condition on a channel produces one error-level line naming the channel when it starts and one error-level line naming the channel when it ends, not one line per poll.
- The channel's record is INVALID while the condition lasts and recovers its value and severity afterwards.
- `LAST_ERROR_MESSAGE` names the condition while it lasts.
- When the port reconnects while the condition lasts, the channel reports it again once.
- A shipped case drives the condition from the TC32 fixture and counts the lines, it fails on the driver before this change, and the existing cases pass unchanged.
- The linked issue is observed closed, or Closure Evidence records a dated exception limited to issue closure.

##### Dependencies And Decisions

- None. No work or external gate must complete first.
- Decision Date: 2026-11-08. The owner assigned this work to the Network thermocouple acquisition milestone, GitHub milestone 2.
- Decision Date: 2026-11-08. The owner chose one line per channel, each naming its channel, over one device-level line: a condition on all 32 channels prints 32 start lines and 32 end lines once, and the operator sees which channel to inspect.
- Decision Date: 2026-11-08. The owner chose to change only the temperature read and to register the same pattern in the other poll-loop reads (`DIn`, `CIn`, `AIn` and the scan status calls) as backlog row M9, because the issue and its verification are scoped to the temperature read and each other read needs its own fixture condition.
- Decision Date: 2026-11-08. The owner chose to print the end line at the error trace level, so that the start and the end appear under the documented trace mask; the existing device-level line "Device returned to normal status" stays at its driver I/O level.
- Decision Date: 2026-11-08. The owner chose to do this work before M3, as work ordering and not as a behavioral constraint: M3 reads the channels with one `ulTInArray()` call and takes the per-channel result from the -9999 and -7777 values, so the state and the line output of this work are kept apart from the read call, and M3 calls them once per channel.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-11-08; accepted by the owner after three third-person and three second-person review passes, with one line per channel, only the temperature read, an error-level end line and M2 before M3.
Implementation Authorization: 2026-11-08; implement and verify the accepted plan items 1 to 5.
Superseded Plan Artifacts: none

1. `tests/TC32.pm`: replace the single temperature value that the response repeats for every channel with a per-channel value table, add a persistent common-mode condition for selected channels by returning the value -7777 for them, which the earlier measurement showed ULDAQ reports as the common-mode error (`ERR_CMR_EXCEEDED`), switched on and off while the fixture runs, and describe both in the module's POD. The shipped fixture has neither today, and the existing cases keep one value for all channels. Verified by T1 and T2.
2. `tests/reconnect_ioc.cpp`: add a command that prints `LAST_ERROR_MESSAGE` read through the public asyn interface, because the test IOC does not load the device template that carries that record. Verified by T1.
3. `measCompApp/src/drvMultiFunction.cpp`: add one method that takes a channel and its read status, keeps the last status of every temperature channel and decides whether a line is due, apart from the read call. In the temperature loop call it instead of `reportError()`. A changed failure status goes through `reportError()` with the channel number in its text, which also writes `LAST_ERROR_MESSAGE`. The return of a failed channel to normal prints one error-level line directly with `asynPrint()` and leaves `LAST_ERROR_MESSAGE` alone, so a channel that recovers beside a channel that still fails does not replace the message that names the failure; the existing clearing at the end of a poll that is entirely normal stays. Keep `setParamStatus()` on every poll, the open-thermocouple handling and the connection-error path; clear the state when the port connects and when the loop skips a channel because its type is not thermocouple. Verified by T1 and T2.
4. `tests/test_reconnect.pl`: add the case `read-error`. It switches the condition on for channels 0 and 31, the two channels that have temperature records in the test IOC, counts the driver's lines over a window of at least 8 seconds, which holds at least 100 polls at the measured rate of about 19 polls per second, requires one start line per channel, INVALID records with the held value, `LAST_ERROR_MESSAGE` naming the condition and no further lines, forces a reconnect while the condition lasts and requires one new start line per channel, then switches the condition off on one channel and requires one end line for it, the other channel still INVALID and `LAST_ERROR_MESSAGE` still naming the condition, and finally switches it off on the other channel and requires its end line and recovered records. The IOC must exit normally. Verified by T1.
5. `docs/reconnection.md` and `tests/README.md`: describe the once-per-change reporting and its trace level, the new case with its command and duration, its original-behavior control and one negative control for each rule: report on every poll, keep the state across a reconnect, and print the end line through `reportError()`. Add a section "Static checks" to `tests/README.md` that gives the commands for the syntax and POD check of the four Perl files, their usage checks and the module availability check, run on Debian 13 and in the Rocky 8 image, and for the `g++ -fsyntax-only` compile of the changed C++ files in the Rocky 8 image; later work units refer to it. Verified by T2 and T3.

The state reset for a channel that leaves the thermocouple type has no network fixture that changes the channel type, so it is checked by reading the loop only and the result records that limit.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Run `read-error` three times on the changed driver. Build the driver before this change with the final tests and run the case on it. Build the three negative controls of `tests/README.md` once each. | Common integration environment; the TC32 fixture with the common-mode condition | The Completion Criteria hold in all three runs; the driver before this change fails the line-count assertion; each negative control fails its named assertion. |
| T2 | Regression | Run the 27 existing cases and the exit loop with the README commands, the Perl checks on Debian 13 and in the Rocky 8 image and the compile of the changed C++ files in the Rocky 8 image with the commands of the README section "Static checks". | Same environment; Perl 5.40.1 and 5.26.3 | All pass with normal IOC exit and their recovery deadlines unchanged. |
| T3 | Review | Read the changed `docs/reconnection.md` and `tests/README.md` as the operator who sets up the case. | Repository documents | The reporting rule, the trace level, the command, the controls and the static checks are described. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-09T01:15:19Z to 01:17:17Z | Debian 13; real IOC, Base 7.0.10, asyn 4.45.0, patched ULDAQ 1.2.2; one TC32 fixture with channels 0 and 31 returning -7777 | Pass: `read-error` in three runs on the changed driver (the README command and two more) passes its 13 assertions. In an 8.1-second window of 154 to 157 polls the driver prints 2 error lines, one for channel 0 and one for channel 31, both with error 107 and "Common-mode voltage range exceeded"; the records stay INVALID with 22.5; an injected `bad-size` fault on channel 31 prints a line with error 9 and then a line with error 107; after a forced connection error and reconnect each channel reports once more; the return to normal prints one line per channel and `LAST_ERROR_MESSAGE` keeps naming channel 31 until channel 31 also recovers, then clears. The driver before this change, with the same tests, fails `read error reported once per channel` with 308 lines in 154 polls. The control `read-error-every-poll` fails the same assertion, `read-error-ignores-code-change` fails `a different error on a failing channel is reported again`, `read-error-keeps-state` fails `read error reported again once per channel after reconnect` with one line for channel 31, and `read-error-end-sets-message` fails `LAST_ERROR_MESSAGE keeps naming the failing channel`. The restart of the channel state when a channel leaves the thermocouple type is not exercised, because no fixture changes the channel type; it was checked by reading the loop only. | `work/m2-read-error/r3/`: `block7.out`, `read-error-fixed-*`, `var-*-run` |
| T2 | 2026-11-09T01:06:16Z to 01:26:00Z | Same environment; Perl 5.40.1 and 5.26.3; Rocky 8 image | Pass: the 14 earlier cases pass 995 assertions, the 4 MAC cases 35, the 8 endpoint cases 45 and `silent-device` 8, with every IOC exit 0 and their recovery deadlines unchanged; the exit loop passes 150 of 150; the commands of the README section "Static checks" pass on the host and in the Rocky 8 image, including both usage checks that print `exit 2`, and `drvMultiFunction.cpp` and `reconnect_ioc.cpp` compile there without error. | `work/m2-read-error/r3/`: `block0.out` to `block6.out`, `loop.out`, `static0.out`, `static1.out` |
| T3 | 2026-11-08 | Repository documents in the working tree of this verification | Pass: `docs/reconnection.md` describes the once-per-change lines, their trace level, the INVALID records, the `LAST_ERROR_MESSAGE` rule, the restart at a reconnect and the reads that are not covered; `tests/README.md` gives the `read-error` command and its duration of about 25 seconds, the original-behavior control, four negative controls and the Static checks commands. Every command in the text was executed in the run above and the duration was measured at 21 to 22 seconds. | `docs/reconnection.md` section Persistent thermocouple read errors; `tests/README.md` sections Read error case and Static checks |

Source identity of the run: `drvMultiFunction.cpp` SHA-256 `41861dc736de48e1eacbc1e222e8a5ddb1b27fbf6ef4360b1ebe92e32717404a`; `test_reconnect.pl` `3ff52cd40872327435179c330e18e09d4b8434f104565008237c6f5c8b5498e4`; `reconnect_ioc.cpp` `278377dce6b083681ae57be6185ffdcb6c80d6a71d63998761177ca8b860b005`; `TC32.pm` `f80ff25179f1d64d71fcfc78ef5bcee42e472efbe1fcee1ee34a720d2eb287dc`; `E1608.pm` `621e8daa6c1cad55010dcaa381c3f4722913054c83585d60ab3c1d91f791f930`; `build_reconnect.pl` `c9f049c2ba64934b717e0d27b49fcdd0941cfc472c1ef1da0bb993351478a400`; `exit_loop.bash` `5f4a0f6085a08021f94508424297302de8913745de940d53c2d59786f96f9826`; `tests/README.md` `27768c58266ef04a15ae1ce8698d1fa63f6523415d9288fb91eebab074e59c0f`; `docs/reconnection.md` `6a5979e3faa44e0144f24cc10173a236a0c0f44bed1c41dc8de5de3f7ee71d8a`. No source file changed between the start of the run and these hashes, except that the introduction of the README section "Static checks" was reworded afterwards (`tests/README.md` SHA-256 `5b0e2ca3839187e86f205700275f4b7d494ffce6cf20611efa0009ad91f75fc5`); the extracted command blocks of the README, all ten, are byte-identical to the ones the run executed. The overview comment of the case in `tests/test_reconnect.pl` was reworded afterwards too (`test_reconnect.pl` SHA-256 `47e59cb18186b718e3a0658e0508b78d561dfc65fe6cffa180c78e65979b7112`); the difference to the file the run used is those three comment lines only, and `read-error` passed once more on it with 13 of 13 assertions. The driver before this change is the committed `07dc550` `drvMultiFunction.cpp` built with the final tests.

##### Closure Evidence

- Measured 2026-11-08 with the shipped harness and a temporary fixture variant returning the common-mode sentinel -7777: 3,040 lines in about five seconds, severity INVALID, value held at 22.5. The temporary variant is not in the repository, and `tests/TC32.pm` has no common-mode condition (read 2026-11-08). The plan assumed a poll every 50 ms; the measured rate with a TC32 fixture is about 19 polls per second, because each poll reads every channel, so the case uses an 8-second window and requires at least 100 polls.

- Landed: observed 2026-11-09T08:55:32Z after `git fetch`, `origin/site` is at commit 484166964308df93d2b98a5dffd27e5ca668c485, the same commit as the local `HEAD`, and the six paths changed by the implementation commit af3a71d (`measCompApp/src/drvMultiFunction.cpp`, `tests/TC32.pm`, `tests/reconnect_ioc.cpp`, `tests/test_reconnect.pl`, `tests/README.md`, `docs/reconnection.md`) show no difference between that commit and `origin/site`. Recheck with `git diff af3a71d origin/site -- <path>`.
- Issue: the owner delegated the issue operations on 2026-11-09; the body was synchronized with the implemented behavior and its five acceptance criteria were checked, a closing comment was posted and issue #12 was closed as completed at 2026-11-09T08:52:13Z. The read-back shows state CLOSED, label bug and milestone 2.
- Remaining behavior: the analog input reads of the poll loop still print an error on every poll; row M9 tracks them (corrected 2026-11-11: the digital input, counter and scan status reads already report once per outage). The device value -8888 means an open thermocouple: ULDAQ turns it into the data value -9999 with `ERR_OPEN_CONNECTION`, and the driver already reports -9999 without an error (read in the ULDAQ 1.2.2 source 2026-11-09).

- Observed 2026-11-09 on a real TC-32 by the session that has the device, builds of the commit 4884b71 in scratch copies and one IOC process for each run: with the open detection enabled an empty or cut input reads -9999 as a valid value with no error line, and with it disabled the same input reads ordinary temperatures, up to 1229 C for a cut thermocouple, as valid values with no alarm. A channel set to the disabled type through the asyn parameter `TEMPERATURE_SENSOR` with the ULDAQ value `AI_DISABLED` reads -11111 with no error line and the neighbouring channels do not change; writing the thermocouple type back restores it.
- Observed 2026-11-09 in the same runs: the device applied each change of the open detection about 14 seconds after the write, and in each of those changes the common-mode error of one channel appeared once, with the line `Calling TIn channel 0, err=107 Common-mode voltage range exceeded`, the record INVALID for one update and `LAST_ERROR_MESSAGE` set, and half a second later the line `Channel 0 read returned to normal` and the message cleared; no line repeated for each poll while the input stayed open, for more than three minutes. The cause of the device's report at the change is not known, so the once-per-change reporting and the return-to-normal line are observed on hardware, but a persistent common-mode input was not applied. A power-off of the device in this state recovered with the open detection in effect from the first update.
- The report appeared at each of five changes of the open detection, one of them after a reconnect, and never as a persistent condition.
- Not verified on hardware: a persistent common-mode input. The owner of the device declined the test on 2026-11-10 because it needs a voltage applied to an input to lift it outside the common-mode range, so the case of one line at the onset, the channel INVALID with its held value while the condition lasts, one line at the end and the other channels unaffected is covered by the fixture cases `read-error` and `temperature-array` and their negative controls only. Also not verified: whether the driver or the device kept the open detection across the power-off; the restore is separated only by a variant of the driver without it, which was not run.

##### GitHub Projection

Title: Report a persistent thermocouple read error once instead of on every poll
Labels: bug
GitHub Milestone: Network thermocouple acquisition (milestone 2)
Observed State: closed
Observed Labels: bug
Observed Milestone: Network thermocouple acquisition (milestone 2)
Last Compared: 2026-11-09T08:55:32Z; remote updated at 2026-11-09T08:52:13Z

#### M3 - Single Request Thermocouple Read And Acquisition Time

Origin: 9c39e49 / M3
Identity History: none
GitHub Issue: [#13](https://github.com/jeonghanlee/measComp/issues/13)
Status: Complete

##### Summary

The poller reads the TC32 and E-TC one channel per `ulTIn()`, which ULDAQ implements as a one-channel `tInArray()`, so each channel costs its own request under the process-wide mutex, the channels of one poll are read at different moments, and the driver never sets the asyn timestamp.

##### Scope

Read the thermocouple channels of the network TC32 (board type `ETH_TC32`) with `ulTInArray()` over each contiguous run of channels that share a temperature scale, one request per run per poll. Take each channel's result from the values the call fills in (-7777 for a common-mode error, -9999 for an open thermocouple, -11111 for a disabled channel) and pass it to the per-channel status method added for persistent read error logging. Call `updateTimeStamp()` once per poll so every channel carries the acquisition time, and add a `TSE` macro with the default 0 to `measCompTemperatureIn.template`.

Out of scope: The E-TC device, which keeps its per-channel reads and is registered as row M10, USB thermocouple boards, the default poll period, the posting of unchanged values and Windows.

##### Completion Criteria

- With all channels at one scale, one poll of the TC32 fixture issues one temperature request, counted from the fixture traffic against the digital read of the same poll. With channel 0 at Fahrenheit and channel 31 at Kelvin it issues three, for channel 0, channels 1 to 30 and channel 31.
- The channels keep their values in their own scales: 22.5 C reads 72.5 on the Fahrenheit channel and 295.65 on the Kelvin channel.
- A record scanned `I/O Intr` with `TSE=-2` takes the timestamp of its poll: the timestamp lies within two seconds of the current time, advances from one poll to the next, and is the same for the records of different channels in one poll.
- Within one request an open channel reads -9999 and stays valid, a common-mode channel is INVALID with its held value and a disabled channel reads -11111, without changing the other channels of the request.
- A transport error of a request fails every channel of that request, and a connection error disconnects the port as before.
- The `TSE` macro of the temperature template defaults to 0 and leaves the timestamp source of existing records unchanged.
- A shipped case checks these points and fails on the driver before this change, and the 28 existing cases pass with only the request selection of the fixture and the harness adapted.
- The linked issue is observed closed, or Closure Evidence records a dated exception limited to issue closure.

##### Dependencies And Decisions

- None. No work or external gate must complete first.
- Decision Date: 2026-11-08. The owner assigned this work to the Network thermocouple acquisition milestone, GitHub milestone 2.
- Decision Date: 2026-11-08. The owner ordered M2 before M3 as work ordering, not as a behavioral constraint: M2 added the per-channel value table to `tests/TC32.pm` and the method `reportTemperatureStatus()`, and this work gets each channel's result from the values of one `ulTInArray()` call and passes it to that method.
- Decision Date: 2026-11-09. The owner chose to change the TC32 only and to keep the E-TC on its per-channel reads, because no E-TC protocol fixture exists and a change that no test can exercise would ship unverified; the E-TC is registered as row M10 and the scope of the linked issue is narrowed to the TC32 when it is closed.
- Decision Date: 2026-11-09. The owner chose that only the network TC32 uses `ulTInArray()` and the USB boards keep `ulTIn()` for each channel, because the scope excludes USB thermocouple boards and no USB board is available for verification.
- Decision Date: 2026-11-09. The owner chose to add a `TSE` macro with the default 0 to the temperature template, so that a user can set `TSE=-2` in a database; without it the acquisition time could not be used.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-11-09; accepted by the owner after two third-person and one second-person review passes, with the TC32 only, the USB boards unchanged and a `TSE` macro with the default 0.
Implementation Authorization: 2026-11-09; implement and verify the accepted plan items 1 to 6.
Superseded Plan Artifacts: none

1. `tests/TC32.pm`: select the temperature fault on a request whose channel mask includes channel 31, not only on the mask `0x80000000` of a one-channel request, add `set_open(@channels)` and `set_disabled(@channels)` that return the device values -8888 and -9999 for the channels, and describe them in the POD. The existing cases keep their faults. Verified by T1 and T2.
2. `tests/reconnect_ioc.cpp`: load the temperature records of channels 0 and 31 and a third record for channel 1 with `TSE=-2`, and add a command that prints the value, severity, validity and timestamp of a record by name. The third record lets one request show an open, a common-mode and a disabled channel together. Verified by T1.
3. `tests/test_reconnect.pl`: change `channel_requests` of the `read-error` case and the end-of-poll request selection of `digital_window` to select the requests whose mask includes the channel, and add the case `temperature-array`. It counts the temperature requests of polls with all channels at one scale, then with channel 0 at Fahrenheit and channel 31 at Kelvin and checks the three masks and the converted values; requires the timestamp of each record to lie within two seconds of the current time and to advance between two polls, and the records of one poll to share it, so that a driver that never calls `updateTimeStamp()` fails; and switches an open channel 0, a common-mode channel 31 and a disabled channel 1 on in one request and requires -9999 valid, INVALID with the held value and -11111, with the other channels unchanged. It then forces a transport error on the temperature request and requires every channel to fail and the port to recover. The IOC must exit normally. Verified by T1.
4. `measCompApp/src/drvMultiFunction.cpp`: for board type `ETH_TC32` read each contiguous run of one scale with `ulTInArray()` and map the data values to a status for each channel: -7777 to `ERR_CMR_EXCEEDED`, -9999 to a valid reading of -9999 and -11111 to a plain value. Pass each channel's status to `reportTemperatureStatus()`. A call that fails for another reason fails every channel of the run, and a connection error leaves through the existing disconnect path. Call `updateTimeStamp()` once per poll before the callbacks. Keep the `ulTIn()` loop for the other boards, the forced callback, `setParamStatus()` and the meaning of `status` and `inputStatus`. Verified by T1 and T2.
5. `measCompApp/Db/measCompTemperatureIn.template`: add `field(TSE, "$(TSE=0)")` to the temperature record. Verified by T1 and T2.
6. `docs/reconnection.md` and `tests/README.md`: describe the single request per run of one scale, the per-channel meaning of the three device values, the acquisition time and the `TSE` macro, the new case with its command and duration, its original-behavior control and one negative control for each rule: one request per channel, no timestamp, the result taken from the call status, and one scale for all channels. Verified by T3.

The E-TC and USB paths are not changed and no test exercises them, so their unchanged behavior is checked by reading the diff only and the result records that limit.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Run `temperature-array` three times on the changed driver. Build the driver before this change with the final tests and run the case on it. Build the four negative controls of `tests/README.md` once each. | Common integration environment; the TC32 fixture with per-channel values | The Completion Criteria hold in all three runs; the driver before this change fails the request-count assertion; each negative control fails its named assertion. |
| T2 | Regression | Run the 28 existing cases and the exit loop with the README commands, the Perl checks and the compile of the changed C++ files with the commands of the README section "Static checks". | Same environment; Perl 5.40.1 and 5.26.3 | All pass with normal IOC exit and their recovery deadlines unchanged. |
| T3 | Review | Read the changed `docs/reconnection.md` and `tests/README.md` as the operator who sets up the case. | Repository documents | The request rule, the device values, the acquisition time, the `TSE` macro, the command and the controls are described. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-09T17:16:54Z to 17:23:53Z | Debian 13; real IOC, Base 7.0.10, asyn 4.45.0, patched ULDAQ 1.2.2; one TC32 fixture with per-channel values | Pass: `temperature-array` in three runs on the changed driver (the README command and two more) passes its 19 assertions. With all channels at one scale a poll issues one temperature request with the mask `ffffffff` (58 to 59 polls and requests in the 3-second window); with channel 0 at Fahrenheit and channel 31 at Kelvin it issues three, with the masks `00000001`, `7ffffffe` and `80000000` (59 polls, 177 requests); the records read 72.5 and 295.65; the records of one poll share a timestamp, it lies within two seconds of the current time and advances by 1.01 seconds per second; the `TSE` field is 0 for the record loaded without the macro and -2 for the record that sets it; in one request the open channel reads -9999 valid, the disabled channel -11111 and the common-mode channel is INVALID with 22.5, and only channel 31 reports an error; a request that fails with a bad-size response and no connection error fails all 32 channels and leaves the port connected; after a forced transport error every channel fails and the port reconnects. The driver before this change, with the same tests, fails `temperature array one request per poll` with one request for each of the 32 channels. The controls `tin-per-channel` fails the same assertion, `tin-single-scale` fails `temperature array one request per scale run`, `tin-no-timestamp` fails `temperature array timestamp is the time of the poll`, `tin-run-failure` fails `temperature array request failure fails every channel and keeps the port connected`, `tin-tse-default` fails `temperature array TSE macro defaults to 0` with a default of -2, and `tin-call-status` fails `temperature array open channel reads -9999 and stays valid`. The E-TC and USB paths are not exercised by any test; their unchanged behavior was checked by reading the diff only. | `work/m3-array/r5/`: `block8.out`, `array-fixed-*`; `work/m3-array/r6/`: `var-*-run` |
| T2 | 2026-11-09T17:08:27Z to 17:22:23Z | Same environment; Perl 5.40.1 and 5.26.3; Rocky 8 image | Pass: the 14 earlier cases pass 995 assertions, the 4 MAC cases 35, the 8 endpoint cases 45, `silent-device` 8 and `read-error` 13, with every IOC exit 0 and their recovery deadlines unchanged; the exit loop passes 150 of 150; the commands of the README section "Static checks" pass on the host and in the Rocky 8 image, including both usage checks that print `exit 2`, and `drvMultiFunction.cpp` and `reconnect_ioc.cpp` compile there without error. A first full run failed the four digital cases, which is recorded in Closure Evidence, and the run recorded here is the repeat after the correction. | `work/m3-array/r5/`: `block0.out` to `block7.out`, `loop.out`, `static0.out`, `static1.out` |
| T3 | 2026-11-09 | Repository documents in the working tree of this verification | Pass: `docs/reconnection.md` describes the single request per run of one scale, the meaning of the values -9999, -11111 and -7777, the failure of a whole request, the acquisition time, the `TSE` macro with its default and the limit to a network TC32; `tests/README.md` gives the `temperature-array` command and its duration of about 20 seconds, the original-behavior control and six negative controls. Every command in the text was executed in the run above, the macro example is the string the test IOC uses, and the duration was measured at 17 to 18 seconds. | `docs/reconnection.md` section Thermocouple reads and acquisition time; `tests/README.md` section Temperature array case |

Source identity of the run: `drvMultiFunction.cpp` SHA-256 `7fdfcc9ceacfede45c28bad02897c511132f5f4210eec83d20a9a0cfdbd91e77`; `measCompTemperatureIn.template` `e25747a101a3bffbe9fce499ad6fac38593b91093a49d51a839d0093bc62f090`; `test_reconnect.pl` `ef688458c03839c51331087b9ee6ae0f1721273a288c2b5b1fea2edb2e2ac5d1`; `reconnect_ioc.cpp` `92b9fc2e50f150274855b4407ac1735c9f267de21dd0ca9da017347ff416c0d6`; `TC32.pm` `f293d2cb4798702afe3af0909db1d67fd1d5a1e27b8e96666ccbcf3797f5f3ac`; `E1608.pm` `621e8daa6c1cad55010dcaa381c3f4722913054c83585d60ab3c1d91f791f930`; `build_reconnect.pl` `c9f049c2ba64934b717e0d27b49fcdd0941cfc472c1ef1da0bb993351478a400`; `exit_loop.bash` `5f4a0f6085a08021f94508424297302de8913745de940d53c2d59786f96f9826`; `tests/README.md` `48211bdda2929e4f744b6c2a7951006052804133acbf190bbdb98f2a38ece4ca`; `docs/reconnection.md` `319bff5b75cf00aa7d9b5d98e82fd7be4368d81c675f1496e551f9fba2735020`. No source file changed between the start of the run and these hashes; the variants were run again from the same sources in `work/m3-array/r6/`. The driver before this change is the committed `ce193b1` `drvMultiFunction.cpp` built with the final tests.

##### Closure Evidence

- Found 2026-11-08 by reading `AiETc32::tIn()`, `AiETc32::tInArray()`, `AiETc::tInArray()` and the poller; not measured.
- Read 2026-11-09 in the ULDAQ 1.2.2 source: `AiETc32::tInArray` (`src/net/ai/AiETc32.cpp`) maps the device values -7777, -8888 and -9999 to the data values -7777, -9999 and -11111, throws `ERR_OPEN_CONNECTION` before `ERR_CMR_EXCEEDED` when both occur, and takes one scale and a contiguous range; `AiETc::tInArray` (`src/net/ai/AiETc.cpp`) does the same without the common-mode value. In this repository `tests/TC32.pm` selects its temperature fault by the request mask `0x80000000` and `channel_requests` of the `read-error` case counts masks equal to one channel bit; both assume one channel per request. The digital cases found the same assumption in `digital_window` of `tests/test_reconnect.pl` on 2026-11-09, which waits for a request with the mask `0x80000000` to mark the end of a poll; the first full run failed all four with "digital observation poll deadline exceeded".
- The first run of the control `tin-tse-default` passed all assertions instead of failing, because the control script ran every variant with the template of the repository and not with the variant's own copy; the script was corrected and all variants were run again (2026-11-09), which gave the results recorded under T1.

- Landed: observed 2026-11-09T17:31:46Z after `git fetch`, `origin/site` is at commit 95034aa8c14c760614d5578de94dcf169898ab37, the same commit as the local `HEAD`, and the seven paths changed by the implementation commit 01c2ecd (`measCompApp/src/drvMultiFunction.cpp`, `measCompApp/Db/measCompTemperatureIn.template`, `tests/TC32.pm`, `tests/reconnect_ioc.cpp`, `tests/test_reconnect.pl`, `tests/README.md`, `docs/reconnection.md`) show no difference between that commit and `origin/site`. Recheck with `git diff 01c2ecd origin/site -- <path>`.
- Issue: the owner delegated the issue operations on 2026-11-09; the title was narrowed to the TC32, the body was synchronized with the implemented behavior and the narrowed scope and its five acceptance criteria were checked, a closing comment was posted and issue #13 was closed as completed at 2026-11-09T17:30:19Z. The read-back shows state CLOSED, label enhancement and milestone 2.
- Remaining behavior: the E-TC and the USB boards still read one channel per request and keep the processing time as timestamp; row M10 tracks the E-TC, which needs a protocol fixture first.

- Observed 2026-11-09 on a real TC-32 by the session that has the device, with build 4884b71 and the same configuration for builds ce193b1 and 4884b71 over 60 seconds each: the mean poll period was 71.6 ms (839 samples) and 52.5 ms (1,142 samples) with the default pause of 50 ms, so the reading time of a poll fell from about 21.6 ms to about 2.5 ms; all 32 channels read valid temperatures. With `TSE=-2` on three records scanned every second the timestamps did not advance, and after `SCAN` was set to `I/O Intr` they were within a second of the wall clock, identical for channels updated together and advancing with every update. The cause of the first result is in asyn: `asynFloat64Average` sets the record time only for `I/O Intr` records (`devAsynFloat64.c`, `interruptCallbackAverage()` and `processAiAverage()`); the test IOC reproduced it with one record of each scan. The guide, the README and the criterion above were corrected to say so.
- Observed 2026-11-09 on the same TC-32 with scratch builds of 4884b71: for channels 2 and 31 set to Fahrenheit and to Kelvin, the value converted to Celsius matched the readings before and after within 0.05 K, and the neighbouring channels 1, 3 and 30 stayed in Celsius, so a scale in the middle and at the end of the range splits the request correctly; the Volts scale read a raw value and was not compared. For all 32 channels in Celsius the largest difference between the build before and the build after the change, read about a minute apart, was 0.072 K, against a spread of about 0.03 K of one channel over a few seconds. A run of 15 hours 36 minutes, from 2026-11-09 17:24 to 2026-11-10 08:59, covered the same TC-32 with the site IOC built against measComp 4884b71 (the driver code is the same at 217465f) and the 1.5.0 distribution with its vendor ULDAQ: one process without a restart, all 32 inputs fitted with sensors, the open detection enabled, Celsius, the alarm limits 0, 10, 45 and 60, and nobody touched the device or the IOC. `PollTimeMS` read every 10 seconds gave 5,579 samples, no failed read, a mean of 52.91 ms, a range of 51.90 to 53.73 ms and hourly means of 52.81 to 52.96 ms, so no drift. A channel access read of Ti0 to Ti31 every 60 seconds counted no MAJOR, MINOR or INVALID severity, no -9999 and no missing PV in 929 checks. The IOC log held no line of the driver, the device support or asyn and only three autosave writes. Channels 1 to 3 had 56,943 updates each between 25.5 and 29.9 C. At the end the process had used 824.5 seconds of CPU, about 1.5 percent, and 12.8 MB resident; the memory at the start was not recorded, so growth is not assessed.
- Observed 2026-11-09 for the default temperature template of this repository, whose records use `asynFloat64Average` and a one-second scan: at each change of the open detection or of the scale one record publishes a valid value that mixes the two states, such as -4720.89 and -8416.18 at an open detection change (a one-second average of -9999 and the real reading, checked by arithmetic) and 32.39 and 87.40 at a scale change. A site template that sets `DTYP` to `asynFloat64` and `MDEL` to -1 showed no mixed value at the same changes. The shipped suite at 4884b71 was run again on another host with another stack: 29 cases passed, the exit loop passed 150 of 150, and the 12 negative controls of the three fixes each failed at the assertion named in the README.
- Not verified on hardware: the Volts scale against a reference, the E-TC and USB boards, and an outage that lasts hours.

##### GitHub Projection

Title: Read all TC32 thermocouple channels in one request and stamp the acquisition time
Labels: enhancement
GitHub Milestone: Network thermocouple acquisition (milestone 2)
Observed State: closed
Observed Labels: enhancement
Observed Milestone: Network thermocouple acquisition (milestone 2)
Last Compared: 2026-11-11T09:20:12Z; remote updated at 2026-11-09T17:49:00Z

#### M4 - Thermocouple Device Diagnostics

Origin: 9c39e49 / M4
Identity History: none
GitHub Issue: [#14](https://github.com/jeonghanlee/measComp/issues/14)
Status: Complete

##### Summary

ULDAQ implements, and the driver does not expose, the cold-junction temperatures, the TC32 50 or 60 Hz rejection, the calibration table selection and the calibration dates of the network TC32 and E-TC.

##### Scope

For the network TC32 (board type `ETH_TC32`), expose four items. The cold-junction temperatures, 32 values without an EXP-32, are read once per poll with one `ulTInArray()` call over the cold-junction channels `0x80` to `0x80 + 31`, in Celsius. The rejection frequency (50 or 60 Hz) and the calibration table (factory or field) are set and read back through `ulAISetConfig()` and `ulAIGetConfig()` with `AI_CFG_REJECT_FREQ_TYPE` and `AI_CFG_CAL_TABLE_TYPE`, for the base bank and the expansion bank by channel address as the open thermocouple detection is, and are restored after a reconnect as that is. The factory and field calibration dates are read after each connection as the strings of `AI_CFG_CAL_DATE_STR` and `AI_CFG_EXP_CAL_DATE_STR`. The records are two new templates, `measCompTemperatureCJC.template` for each channel and `measCompTemperatureBank.template` for each bank, and only `TC32.substitutions` loads them.

Out of scope: The E-TC, whose counterparts are registered under row M10, other boards, alarm outputs, calibration itself and the expansion bank beyond what the shared code does for it.

##### Completion Criteria

- On the TC32 fixture one poll issues one cold-junction request for all 32 channels, and the cold-junction records show the fixture's value of each channel and follow a change.
- The rejection frequency and the calibration table are set from their records, whose states carry the values 1 and 2, and read back, each changes only its own bit of the device's measurement configuration byte beside the open thermocouple detection, and both are written again after a reconnect that lost the device's configuration.
- The factory date and the field date read after a connection are the fixture's: the factory date and the field date that the fixture holds for the base rejection frequency in effect at the connection. Both are read again after a reconnect, and the field date does not change when the rejection frequency is changed without a reconnect.
- A value other than the two valid ones, written to the rejection frequency or the calibration table, is rejected and changes neither the device nor the readback.
- A failed cold-junction read marks only the cold-junction records and does not change the temperature records.
- The TC32 fixture implements the cold-junction command and configurable calibration dates, a shipped case checks each item, it fails on the driver before this change, and the 29 existing cases pass unchanged.
- No template used by another board changes, and `TC32.substitutions`, which both the USB and the network TC-32 load, is unchanged.
- The linked issue is observed closed, or Closure Evidence records a dated exception limited to issue closure.

##### Dependencies And Decisions

- None. No work or external gate must complete first.
- Decision Date: 2026-11-08. The owner assigned this work to the Network thermocouple acquisition milestone, GitHub milestone 2.
- Decision Date: 2026-11-09. The owner chose to change the TC32 only and to move the E-TC counterparts to row M10, because no E-TC protocol fixture exists; the scope of the linked issue is narrowed to the TC32 when it is closed.
- Decision Date: 2026-11-09. The owner chose new templates loaded by `TC32.substitutions` only, because the existing temperature template is shared by the E-TC and the USB boards, whose databases would otherwise gain records for values they do not have. The choice of the file that loads them is replaced by the decision of 2026-11-10 below.
- Decision Date: 2026-11-09. The owner chose to read the cold-junction temperatures on every poll as the issue asks; the cost is one more request per poll, to be reviewed against the poll time measured on a real TC32.
- Decision Date: 2026-11-09. The owner chose the string items for the calibration dates because they are the documented public items of ULDAQ.
- Decision Date: 2026-11-09. The owner chose to publish the calibration dates as ULDAQ returns them: ULDAQ picks the field date of the base bank at the connection from the rejection frequency the device reports then, and keeps it until the next connection, so the published field date can lag a setting that the driver restores after the connection; the limit is documented and the case checks it. Forcing a second connection to realign the date was rejected as heavier than the date is worth.
- Decision Date: 2026-11-10. The owner chose a new substitutions file for the new records, loaded only for the network TC32 through a commented line in `iocBoot/iocTC32/st.cmd` that the operator enables, and `TC32.substitutions` stays unchanged, because `iocBoot/iocTC32/st.cmd` loads `TC32.substitutions` for the USB and the network TC-32 alike (`boardFamily_` is `USB_TC32` for both), so new records in it would also appear on a USB TC-32, where the driver rejects their writes.
- Decision Date: 2026-11-10. The owner chose to state, as a limit of the real-device check, that the real unit returns the same string for the factory and the field date (Closure Evidence, 2026-11-10), and to keep the fixture requirement that the two dates differ.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-11-10; accepted by the owner after the placement of the new records and the date limit were decided and the plan text was revised accordingly, and after the cold-junction request was read on the real TC32; no separate review pass was held before acceptance.
Implementation Authorization: 2026-11-10; implement and verify the accepted plan items 1 to 6.
Superseded Plan Artifacts: none

1. `tests/TC32.pm`: implement the cold-junction command `0x13`, whose payload is the base and expansion channel masks and whose answer is one float for each requested channel, from a per-channel cold-junction table with a default and a method to set a channel; reject a request for the expansion; make the calibration dates of the commands `0x3A` (the factory dates of the base and the expansion) and `0x3C` (four field dates: base at 60 Hz, base at 50 Hz, expansion at 60 Hz, expansion at 50 Hz) configurable, all different; describe both in the POD. The measurement byte of `0x18` and `0x19` already holds the bits of the open detection, rejection and calibration table. Verified by T1 and T2.
2. `tests/reconnect_ioc.cpp` and `tests/build_reconnect.pl`: load the new templates for the two test channels and bank 0 from the directory of the temperature template, print the string value of a record by name, add a command that writes the rejection frequency or the calibration table through the asyn parameter with any integer so that a case can write an invalid value, and add the two new templates to the input list whose hashes the builder records. Verified by T1.
3. `measCompApp/src/drvMultiFunction.cpp`: add the parameters for the cold-junction value, the rejection frequency, the calibration table and the calibration date strings. For `ETH_TC32` read the cold-junction channels once per poll after the temperature read; a cold-junction failure sets only its own parameters to error and is reported once for each change, and a connection error leaves through the existing disconnect path. Write the rejection frequency and the calibration table with the bank index of `setOpenThermocoupleDetect`, keep the written values and write them again in `restoreTemperatureConfig()`. The values are the ULDAQ enumerators, which start at 1: rejection 1 for 60 Hz and 2 for 50 Hz, calibration table 1 for factory and 2 for field. Reject any other value with an error before the device is touched, because `ulAISetConfig()` casts the value without a check and the TC32 treats every value but 50 Hz and the field table as 60 Hz and the factory table. As `thermocoupleType_` is, leave both parameters out of the early parameter update of `writeInt32()`, so that a readback changes only after a successful write. The settings act only for board type `ETH_TC32`, because `boardFamily_` is `USB_TC32` for the USB TC-32 too, and a write on another board is rejected. and read the settings and both dates after each connection and publish the dates as ULDAQ returns them. Verified by T1 and T2.
4. `measCompApp/Db/measCompTemperatureCJC.template`, `measCompApp/Db/measCompTemperatureBank.template` and a new `measCompApp/Db/TC32Network.substitutions`: the cold-junction record for each channel; the rejection frequency, calibration table and the two date records for each bank. The new file is loaded only for the network TC32, by a commented line in `iocBoot/iocTC32/st.cmd` that the operator enables, and `TC32.substitutions` is not changed. Verified by T1, T2 and a check that `TC32.substitutions` and every other substitutions file are unchanged.
5. `tests/test_reconnect.pl`: add the case `temperature-diagnostics`. It counts the cold-junction requests of polls and checks their mask, compares the cold-junction records with distinct fixture values for channels 0 and 31 and follows a change, sets the rejection frequency and then the calibration table and checks the bits of the measurement byte beside an open detection that was set before, forces a connection error with the device configuration reset and requires both bits and the readbacks to come back, compares the factory and field date strings with expected strings built from the fixture's fields in the same format, which is the local time formatted with `%c`, and checks the field date in three steps: it is the 60 Hz date at the first connection, it stays when the rejection frequency is set to 50 Hz without a reconnect, it stays the 60 Hz date after a reconnect that lost the device configuration even though the 50 Hz setting is restored, and it becomes the 50 Hz date after a reconnect that kept the device configuration. It requires the IOC to exit normally. It writes 0 and 3 to each setting through the new command and requires both writes to be rejected with the device byte and the readback unchanged. It also makes the cold-junction read fail with the fixture's `bad-size` fault on the command `0x13` and checks that only the cold-junction records go to error and the temperature records keep their values and severity. Verified by T1.
6. `docs/reconnection.md` and `tests/README.md`: describe the four items, the bank semantics, the Celsius unit of the cold-junction records, the date format (local time formatted with `%c`), the limit that the field date follows the rejection frequency at the connection, the new templates and the case with its command and duration, its original-behavior control and one negative control for each rule: no cold-junction read, no restore of the settings after a reconnect, swapped factory and field dates, a cold-junction failure that also marks the temperature records, and passing an invalid value to the device. Verified by T3.

The expansion bank goes through the same code by channel address and is not exercised, because the fixture models a TC32 without an EXP-32; the result records that limit. Whether the device keeps the rejection frequency and calibration table across a power cycle is a property of the hardware and is not tested here. The real TC32 that was read returns the same string for the factory date and the field date, so a check on that unit can show only that the date is read and published; the fixture, whose dates differ, is what tells the two apart.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Run `temperature-diagnostics` three times on the changed driver. Build the driver before this change with the final tests and run the case on it. Build the five negative controls of `tests/README.md` once each. | Common integration environment; the TC32 fixture with the cold-junction command and configurable dates | The Completion Criteria hold in all three runs; the driver before this change fails the cold-junction request assertion; each negative control fails its named assertion. |
| T2 | Regression | Run the 29 existing cases and the exit loop with the README commands, the Perl checks and the compile of the changed C++ files with the commands of the README section "Static checks". | Same environment; Perl 5.40.1 and 5.26.3 | All pass with normal IOC exit and their recovery deadlines unchanged. |
| T3 | Review | Read the changed `docs/reconnection.md` and `tests/README.md` as the operator who sets up the case. | Repository documents | The four items, the bank semantics, the units, the templates, the command and the controls are described. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-10T21:01:10Z to 21:04:31Z | Debian 13, Perl 5.40.1; the real IOC built by `tests/build_reconnect.pl` against EPICS Base 7.0.10, asyn 4.46.0 and the ULDAQ 1.2.2 of the 1.5.0 distribution, which records uldaq-env a5094ec for it (the library was not rebuilt, and its TCP receive patch was not checked here); one TC32 fixture with the cold-junction command and six different calibration dates | Pass: `temperature-diagnostics` in three runs on the changed driver, 23 of 23 assertions each, IOC exit 0; the driver of HEAD (SHA-256 `7fdfcc9ceacfede45c28bad02897c511132f5f4210eec83d20a9a0cfdbd91e77`) with the final tests fails `temperature diagnostics one cold-junction request per poll` (58 polls, 0 requests); the seven negative controls of `tests/README.md` for this case (the plan named five; two more were added) each fail the assertion named for them, written before the run | The run directories of this session; the source identity below |
| T2 | 2026-11-10T20:48:15Z to 21:00:54Z; Rocky 8 checks 2026-11-11 about 04:40Z | Debian 13, Perl 5.40.1; Rocky 8.10 image `jeonghanlee/rocky8-epics:1.1.0` (digest `9f814c9189370ec637cd4ae736f09bd3dcfdb6c5eb33c5b63547aebe9378770c`; Perl 5.26.3, g++ 8.5.0, EPICS distribution 1.3.0, asyn 4.46.0) | Pass | Done: 30 cases (the 29 earlier and the new one) pass 1,138 assertions with every IOC exit 0; `endpoint-same-ip` 150 of 150 runs; `perl -wc` and `podchecker` of the four Perl files, the module list and the usage exits (0, 0, 2, 2) pass. In the Rocky 8 image with the repository mounted read-only and the network off, `perl -wc` and `podchecker` of the four Perl files pass, no module of the list is missing and the usage exits are 2 and 2; `g++ -fsyntax-only` of `drvMultiFunction.cpp` and `reconnect_ioc.cpp` reports no error and, besides the expected `rset` warnings, two missing-initializer warnings of `iocshFuncDef::usage` on the lines of `configFuncDef` and `showDevicesFuncDef` that predate this change. Limit: the README names the image 1.2.2 with asyn 4.45 as its base; the check ran on the image 1.1.0 with asyn 4.46, and the image 1.2.2 (digest `507b995d50e4`) is on the host but was not used |
| T3 | 2026-11-10T22:49:01Z | Repository documents in the working tree | Pass: the changed passages of `docs/reconnection.md` and `tests/README.md` were read from the seat of an operator in two second-person passes by delegated readers. The 1st read three excerpts and found 8 must-fix and minor items; 11 of its findings were applied after the owner's ruling and the rest were ruled out as coming from the missing context of the excerpts or as wording additions. The 2nd read both complete documents first line to last, checked every name, command, number and path against the files and the real runs of this session, and found no must-fix and no minor finding; it left three info observations, of which the owner had one corrected: the duration of the case, about 25 s, which the runs measured as 14 and 15 s, now reads about 15 s | The 2nd pass read `docs/reconnection.md` SHA-256 `3bee05fe13b59befa85519a68aee3f55f99704b83e33c4abffa758bf3109d7af` and `tests/README.md` `955e67bdf0e1e76a122a4da8ebf9c24a3396e03893d2eb26bdca8818c2cba22d`; after the one-number correction `tests/README.md` is `459d417bd5a3525bbe08e5bdd4abaa94169060ad23adedf29eb066bf9ff2815f` and `docs/reconnection.md` is unchanged |

Source identity of the run: `tests/test_reconnect.pl` SHA-256 `58cd851b913fa624dae0b7713e315d08747340957a5b7c080e5506fba091af84` (the final file, `b7518f8e054f9bb3dc5a8a04e11c18d96ddcd5b0b7a59eb51fda920183ef99ef`, differs only in the condition of the assertion that names the cold junction in `LAST_ERROR_MESSAGE`, which passed for any text before; the 30 cases pass 1,138 assertions and `endpoint-same-ip` 150 of 150 runs on the final file); `tests/TC32.pm` `3a84e5a52e73a14e7cb78fe4904b194f9486d08832e15bbc68b6e93dff598e24`; `tests/E1608.pm` `621e8daa6c1cad55010dcaa381c3f4722913054c83585d60ab3c1d91f791f930`; `tests/build_reconnect.pl` `bb6f160dad324420c82d664af2e56e389689856eeda8a85f60009a66590190b7`; `tests/reconnect_ioc.cpp` `4c059fd9eb2445abe913ebacc9d8377ffda635ffd4b4641d97df1a98965e37fd`; `tests/exit_loop.bash` `5f4a0f6085a08021f94508424297302de8913745de940d53c2d59786f96f9826`; `drvMultiFunction.cpp` `6c013fdb2cb252615731ae0ec008ecbf5a08d28aa15e7ae92656924e9ac5896e`; `measCompTemperatureIn.template` `e25747a101a3bffbe9fce499ad6fac38593b91093a49d51a839d0093bc62f090`; `measCompTemperatureCJC.template` `ad036cdbc4d28aa4b6c645135dd20ed421f0f9b08a814d06ae182c58c8f29cc9`; `measCompTemperatureBank.template` `524343c4d2b05e6a9beaef4fdabf2f9bf527bcd5cf1fa96161c4cb51b76d6b06`; `TC32Network.substitutions` `af947bd984c8c16934637724676504e146e747ae328612a1c45245475c377dda`. The input hashes that the builder recorded for the regression build equal the hashes of the nine files it lists. The final driver adds one statement, which returns from the cold-junction read when the device reports no temperature channels; the 30 cases and the exit loop (150 of 150) were run again on it and passed, while the negative controls, the original-behavior control and the read-only real-device read ran on the driver `ea97fb69` that lacks this statement, and no case reaches the statement.

##### Closure Evidence

- Found 2026-11-08 by reading the ULDAQ `AiETc32` and `AiETc` implementations against the driver; not measured.
- Read 2026-11-09 in the ULDAQ 1.2.2 source: the rejection frequency, the calibration table and the open thermocouple detection are the bits `filter`, `cal` and `otd` of one byte for each bank, read and written whole by `CMD_MEASURE_CONFIG_R` and `CMD_MEASURE_CONFIG_W` (`src/net/ai/AiETc32.cpp`); the cold-junction channels are read with `CMD_CJC_MULTI` (`0x13`) at the channel numbers offset by `0x80`, 32 of them without an EXP-32; the public date items are `AI_CFG_CAL_DATE_STR` and `AI_CFG_EXP_CAL_DATE_STR`. `tests/TC32.pm` has no `0x13` and returns constant dates for `0x3A` and `0x3C`.
- Read 2026-11-09 in the ULDAQ 1.2.2 source: `AiETc32::initialize()` reads the dates once per connection and picks the base field date from the base rejection frequency reported then (`mTc32FieldCalDates[1]` at 50 Hz, `[0]` at 60 Hz), and `getCfg_CalDateStr()` returns that stored value as `strftime("%c")` of the local time; the expansion field date is chosen from the expansion rejection frequency at each call.
- Read 2026-11-09 for the input side: `ulAISetConfig()` casts the written value to `AiRejectFreqType` or `AiCalTableType` without a range check (`src/ulc.cpp`), the enumerators are 1 and 2 (`AI_RFT_60HZ`, `AI_RFT_50HZ`, `AI_CTT_FACTORY`, `AI_CTT_FIELD` in `src/uldaq.h`), and `AiETc32::setCfg_RejectFreqType()` and `setCfg_CalTableType()` store every other value as 60 Hz or the factory table. In `drvMultiFunction.cpp` the thermocouple type template states carry the ULDAQ values (`ZRVL` 1 for Type J), `writeInt32()` updates every parameter before the device write except `thermocoupleType_`, and `boardFamily_` is `USB_TC32` for both `USB_TC32` and `ETH_TC32`.
- Observed 2026-11-10 on a real TC-32 by the session that has the device, with a read-only probe of the 1.5.0 distribution's vendor ULDAQ that used only `ulAIGetConfig()`, `ulAIGetConfigStr()` and `ulTInArray()` and wrote nothing to the device: `ulTInArray()` over the channels `0x80` to `0x9F` in Celsius returned 32 values in one call, 10 of 10 calls succeeded with a mean of 0.97 ms, and the values lay between 29.4 and 30.5 C, rising with the channel number, while the thermocouple channels read 27 to 36 C at the same time; one cold-junction channel alone (`0x80`) took 0.67 ms, and the call over channels 0 to 31 took 1.01 ms, so one more request for each poll costs about 1 ms of device time here, and the cost on the driver side was not measured. The settings read back were rejection frequency 1 (60 Hz), calibration table 1 (factory) and open detection 2 (enabled). `AI_CFG_CAL_DATE_STR` returned the same string for the factory date (index 0) and the field date (index 1) of this unit, so a real unit of this kind cannot show the difference that the fixture dates are meant to show. Not tested: writing the rejection frequency or the calibration table, the expansion bank, and what the device keeps over a power cycle.
- Read 2026-11-10 in the ULDAQ source (`src/net/ai/AiETc32.h` and `AiETc32.cpp` of the `uldaq` repository at e1b9c47, whose latest tag is v1.2.0; the 1.5.0 distribution carries 1.2.2): the measurement byte of each bank holds `otd` in bit 0 (1 disables the detection), `filter` in bit 1 (1 is 50 Hz) and `cal` in bit 2 (1 is the field table), and `initialize()` reads the dates once and picks the base field date from the rejection frequency that the device reports then.
- Captured 2026-11-10 on a real TC32 with a send and receive logging shim on the read-only probe: the cold-junction request `0x13` carries the payload `ffffffff00000000` for the 32 channels and `0100000000000000` for one, and is answered with one little-endian float for each channel (128 bytes for 32); `0x3A` returns 12 bytes and `0x3C` 24 bytes of six-byte dates, the unit's date bytes being `15 03 0b 03 26 13`, which is 2021-03-11 03:38:19. The fixture was compared with these frames in 15 checks (lengths, byte order, refusal of an expansion mask, date shape and setters) and all passed.
- Observed 2026-11-10T20:52Z to 20:54Z on the same real TC32 with the driver of the working tree (a scratch build, only the new records loaded, so that no existing `PINI` record wrote to the device): `<channel>ColdJunction` of channels 0, 1, 2, 15, 28 and 31 read 29.86 to 30.89 C, `Bank0RejectFreq` read 60 Hz, `Bank0CalTable` read Factory, and `Bank0CalDateFactory` and `Bank0CalDateField` both read `Thu Mar 11 03:38:19 2021`; the IOC log held no driver line. The interval between updates of one cold-junction record was 53.79 ms on average over 558 updates, against 52.9 ms for `PollTimeMS` of the site IOC, about 0.9 ms more, measured while a regression ran on the same host and with two different measures, so it is an estimate. The probe read the same settings and dates before and after (rejection 1, table 1, open detection 2, both dates equal); the settings were not written there.
- Limits of the check: of the 23 assertions of `temperature-diagnostics`, 17 are proved able to fail by a negative control: the seven of the first series (one request per poll, the factory date, the rejection frequency set from its record, the restore after a reconnect, the date read again after a reconnect, the rejection of invalid values, the failed read that marks only the cold-junction records) and ten of a second series, each a fresh copy with one literal edit of the driver and the failing assertion named before the run (the cold-junction records showing the fixture values, the field date at the first connection, the open detection write, the calibration table set from its record, the readback, the field date not following a setting, the field date after the reconnect that lost the settings, the report once of a persistent cold-junction failure, the recovery line, and the message of the failure). The message assertion first passed under its edit because its condition lost its place among the arguments of `check()` when the match failed; it was corrected and then failed under the same edit. Six have no negative control: the cold-junction records following a change and the unchanged temperature records, because the edits that break them also break an earlier assertion or the start-up wait, and the test stops at the first failed assertion; the readbacks after a reconnect, which two code paths fill; the field date at 50 Hz after the reconnect that kept the settings, which the edit used did not reach; and the fixture error list and the IOC exit, which check the test tool and the exit that every case and the exit loop already observe. The second series ran on `tests/test_reconnect.pl` `58cd851b`, except the message edit, which ran on the final file. The helper `digital_window` of `tests/test_reconnect.pl` now skips the cold-junction request that ends a poll before its window starts, because the digital cases count the requests after that point and the first regression run failed `digital bit write stops after first error` without it; its assertions are unchanged and the three digital cases pass. The expected date text is built in the C locale, because the IOC never sets a locale. The expansion bank goes through the same code and was not exercised. The run directories are in the session's temporary directory and are not retained.
- Landed: observed 2026-11-11T09:15:36Z after `git fetch`, `origin/site` is at commit e38ae56202d342af35c414bcd099b1a3270ca1f2, the same commit as the local `HEAD`, and the twelve paths changed by the commits c3efe8e to e38ae56 (`.gitignore`, `measCompApp/src/drvMultiFunction.cpp`, `measCompApp/Db/measCompTemperatureCJC.template`, `measCompApp/Db/measCompTemperatureBank.template`, `measCompApp/Db/TC32Network.substitutions`, `iocBoot/iocTC32/st.cmd`, `tests/TC32.pm`, `tests/reconnect_ioc.cpp`, `tests/build_reconnect.pl`, `tests/test_reconnect.pl`, `tests/README.md`, `docs/reconnection.md`, and this register as of that commit) show no difference between `HEAD` and `origin/site`. The implementation is 1d0b251, the correction of the message assertion 101804a, and the documents 1e5c5ea and e38ae56. Recheck with `git diff e38ae56 origin/site -- <path>`.
- Issue: the owner delegated the issue operations on 2026-11-11; the title was narrowed to the network TC32, the body was rewritten for the implemented behavior and its four acceptance criteria were checked, a closing comment was posted and issue #14 was closed as completed at 2026-11-11T09:15:21Z. The read-back shows state CLOSED, reason COMPLETED, label enhancement and milestone 2.
- Remaining behavior: the E-TC counterparts are registered under row M10, which needs a protocol fixture first; the expansion bank has no records and was not exercised.
- Documented after the closure, on 2026-11-11 and outside the Completion Criteria of this row: the user documentation `docs/source/measCompMultiFunctionDoc.rst` describes the five records (commit 2ae358c; it could not be rendered because `sphinx-build` is not installed on the host), and `tests/README.md` names the Rocky 8 image 1.1.0 with asyn 4.46 and the expected compile warnings (commit 872a1c5), which corrects the base that the limit of the T2 result above states as 1.2.2.

##### GitHub Projection

Title: Expose network TC32 cold-junction, rejection and calibration data
Labels: enhancement
GitHub Milestone: Network thermocouple acquisition (milestone 2)
Observed State: closed
Observed Labels: enhancement
Observed Milestone: Network thermocouple acquisition (milestone 2)
Last Compared: 2026-11-11T09:15:36Z; remote updated at 2026-11-11T09:15:21Z

#### M5 - Temperature Filter On Linux

Origin: 9c39e49 / M5
Identity History: none
GitHub Issue: [#15](https://github.com/jeonghanlee/measComp/issues/15)
Status: Complete

##### Summary

The `$(P)$(R)Filter` record writes `TEMPERATURE_FILTER`, which the Windows path passes to `cbTIn()`, but `ulTIn()` has no filter and the Linux path ignores the value, so the setting is accepted and has no effect.

##### Scope

Document that the `Filter` record has no effect on Linux and name the control that the TC-32 has: its only filter is the 50 Hz or 60 Hz noise filter of its A/D converter, set by the rejection frequency record.

Out of scope: Averaging in the driver, the meaning of the Windows option on boards other than the TC-32 (the site has no USB board, so they are not examined), boards not read through `ulTIn()`, and the Windows behavior.

##### Completion Criteria

- `docs/source/measCompMultiFunctionDoc.rst` states that Linux does not use the value of the `Filter` record and that the filter of the TC-32 is set by its rejection frequency record.
- The comment of the Linux read path in `measCompApp/src/drvMultiFunction.cpp` states why the value is not used; the behavior of the driver does not change.
- The existing cases pass unchanged.
- The linked issue is observed closed, or Closure Evidence records a dated exception limited to issue closure.

##### Dependencies And Decisions

- None. No work or external gate must complete first.
- Decision Date: 2026-11-08. The owner assigned this work to the Network thermocouple acquisition milestone, GitHub milestone 2.
- Decision Date: 2026-11-11. The owner chose to document that the `Filter` record has no effect on Linux and to name the filter control of the TC-32, instead of averaging in the driver or connecting the record to the device settings of other boards. No document defines an averaging for the Windows option, the only filter of the TC-32 is its rejection frequency, which the diagnostics records already set, and the site has no USB board, so the other boards are not examined.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-11-11; accepted by the owner after the direction was decided on the evidence of the TC-32 documents; no separate review pass was held before acceptance, and the documentation of the new TC-32 records in the rst file is not part of the plan.
Implementation Authorization: 2026-11-11; implement and verify the accepted plan items 1 and 2.
Superseded Plan Artifacts: the plan of 2026-11-08 to average successive readings in the driver

1. In `docs/source/measCompMultiFunctionDoc.rst`, change the `$(P)$(R)Filter` entry of the temperature record table: Linux does not use the value because ULDAQ has no such option; for the TC-32 the filter is the noise filter of its A/D converter, set by the `$(P)Bank0RejectFreq` record of `measCompApp/Db/TC32Network.substitutions`; the option is not examined for other boards. Verified by T1.
2. In `measCompApp/src/drvMultiFunction.cpp`, replace the comment "cbTin has a filter option but ulTin does not?" in the Linux read path by a statement of what ULDAQ offers (the flags `TIN_FF_DEFAULT` and `TIN_FF_WAIT_FOR_NEW_DATA` only) and that the record value is therefore not used. No code changes. Verified by T2.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Documentation | Read the changed passage of the rst file from the seat of a user who configures a TC-32 and check every statement against its source named in Closure Evidence: the TC-32 User's Guide, the ULDAQ source and `measCompSupport/cbw.h`. | Repository documents in the working tree | The reader can tell that the `Filter` record has no effect on Linux and which record sets the TC-32 filter, and every statement matches its source. |
| T2 | Regression | Compile `drvMultiFunction.cpp`, then run every case of `tests/test_reconnect.pl` and the exit loop with the README commands. | Debian 13 | The file compiles, all cases pass unchanged, every IOC exits normally. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-11, finished by 10:37:56Z | Repository documents in the working tree | Pass: three second-person reads by delegated readers followed the changed `Filter` entry of the rst file and the comment of the driver, from the seats of a TC-32 user and a maintainer, of a Windows TC-32 user and a Linux USB-2408 user, and of a Linux USB TC-32 user, and checked each statement against the TC-32 User's Guide, the ULDAQ header, the code paths and the record names. The first read found one minor finding (the entry named a record that does not work on Windows) and the second one (it named a record that the driver does not expose for the USB TC-32); both were corrected, and the third found nothing above the floor. Five info items were left unchanged | Source identity: `docs/source/measCompMultiFunctionDoc.rst` SHA-256 `19a7f80f34e7af50597de6094f678df320ff9e3ea601373e0bff0f8c47bc330b` |
| T2 | 2026-11-11T10:24:56Z to 10:37:38Z | Debian 13, Perl 5.40.1; EPICS Base 7.0.10 and asyn 4.46.0 of the 1.5.0 distribution | Pass: the real IOC built by `tests/build_reconnect.pl` with the changed driver (build exit 0); the 30 cases pass 1,138 assertions with every IOC exit 0, and `endpoint-same-ip` passes 150 of 150 runs | Source identity: `drvMultiFunction.cpp` SHA-256 `33356351fc067eeca8e1d3b2a63c060c408ff7b5f6271c05826ccaefe297cf98`; `tests/test_reconnect.pl` `b7518f8e054f9bb3dc5a8a04e11c18d96ddcd5b0b7a59eb51fda920183ef99ef`; the run directory is in the session's temporary directory and is not retained |

##### Closure Evidence

- Found 2026-11-08 by reading the poller and the template; not measured.
- Read 2026-11-11 in the TC-32 User's Guide, chapter Specifications, Table 1: the A/D converter is Delta-Sigma with 24 bits, one for each 16 inputs; the entry "Filtering options" is "50 Hz or 60 Hz noise filtering, software-selectable"; the input bandwidth is 22 Hz with 50 Hz filtering and 26 Hz with 60 Hz filtering; the enabled inputs are converted continuously at the maximum converter rate (Note 1). The guide describes no averaging or other filter option.
- Read 2026-11-11 in the InstaCal board configuration screen of the TC-32, kept in the site's device configuration notes: the Measurement Settings tab offers Reject Frequency, Calibration Coefficients, Detect Open TC and the thermocouple type of each channel, and no filter or averaging setting.
- Read 2026-11-11 in the ULDAQ source: the bit named `filter` of the measurement byte of the TC-32 holds the rejection frequency (set for `AI_RFT_50HZ`), so the filter and the rejection frequency are one setting; the flags of `ulTIn()` are `TIN_FF_DEFAULT` and `TIN_FF_WAIT_FOR_NEW_DATA`.
- Read 2026-11-11 in `measCompSupport/cbw.h`: `FILTER` (0x0000) "Filter thermocouple inputs" and `NOFILTER` (0x0400) "Disable filtering for thermocouple", with no averaging defined. In the early Linux drivers of the board vendor the filter of the USB-TEMP and USB-TC boards is the board setting `FILTER_RATE`, "Filter update rate", with no documented values. The Universal Library documentation of the option could not be read from the host, because the site refused automated requests. Hypothesis, not verified: the Windows option selects a device-side filter; it is not examined for boards other than the TC-32.
- Limit: `sphinx-build` is not installed on the host, so the changed documentation cannot be rendered here.
- Landed: observed 2026-11-11T16:15:34Z after `git fetch`, `origin/site` is at commit a9d1fe05a056f4ecfec0740449ec7c8b15aad06a, the same commit as the local `HEAD`, and the two paths changed by the implementation commit 4b6e49a (`docs/source/measCompMultiFunctionDoc.rst`, `measCompApp/src/drvMultiFunction.cpp`) show no difference between `HEAD` and `origin/site`. Recheck with `git diff 4b6e49a origin/site -- <path>`.
- Issue: the owner delegated the issue operations on 2026-11-11; the title was narrowed to the documentation of the filter record, the body was rewritten for the implemented change and its three acceptance criteria were checked, a closing comment was posted and issue #15 was closed as completed at 2026-11-11T16:15:24Z. The read-back shows state CLOSED, reason COMPLETED, label bug and milestone 2.
- Remaining behavior: the driver does not average readings and does not connect the record to the device settings of other boards; what the Windows option does on them is not established, because the site has no USB board.

##### GitHub Projection

Title: Document that the temperature filter record has no effect on Linux
Labels: bug
GitHub Milestone: Network thermocouple acquisition (milestone 2)
Observed State: closed
Observed Labels: bug
Observed Milestone: Network thermocouple acquisition (milestone 2)
Last Compared: 2026-11-11T16:15:34Z; remote updated at 2026-11-11T16:15:24Z

## Backlog

### Work

| ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| M9 | Persistent errors of the other poll-loop reads | Carry-forward | Open | No |  | The two analog input reads report a persistent error once per change as the temperature read does, or the owner records that they need not; the digital input, counter and scan status reads already report once per outage; the priority is low and the fixture is undecided; [detail](#m9---persistent-errors-of-the-other-poll-loop-reads) |
| M10 | E-TC array read | Carry-forward | Open | No |  | The E-TC reads its channels with one request per poll and exposes its cold-junction temperatures, calibration table and calibration dates, verified with an E-TC protocol fixture; priority and fixture scope are undecided; [detail](#m10---e-tc-array-read) |
| M11 | Mixed value at a state change of the averaging temperature record | Carry-forward | Complete | No |  | The user documentation states that the default temperature template publishes one value that mixes the old and the new state at each open-detection or scale change, and which setting avoids it; the default template is unchanged; [detail](#m11---mixed-value-at-a-state-change-of-the-averaging-temperature-record) |

### Backlog Details

#### M9 - Persistent Errors Of The Other Poll-Loop Reads

Origin: 9c39e49 / M9
Identity History: none
GitHub Issue: none
Status: Open

##### Summary

The poll loop of `MultiFunction::pollerThread()` reports a failing read through `reportError()`. The `DIn`, `CIn` and the two scan status reads report only when the previous poll had no error (`if (!prevStatus)`), so they print one line for each outage; the two `AIn` reads call `reportError()` on every poll while a non-connection error persists (`drvMultiFunction.cpp`, read 2026-11-11). The temperature read is changed under M2. The error of an `AIn` read was not reproduced: the TC32 fixture has no analog input, and `tests/E1608.pm` implements the analog input command and inherits the fault injection of `tests/TC32.pm`, but the existing case injects a single end of file on that command, so a fault that keeps failing the read has no case.

##### Scope

Decide whether the two `AIn` reads report a persistent error once per change as M2 does, with which fixture condition, and whether a shared helper replaces the per-read state.

Out of scope: the temperature read, which M2 changes, and connection errors.

##### Completion Criteria

- The owner decides the priority and scope, and the row is then moved to Not started, Deferred or retired with a dated decision.

##### Dependencies And Decisions

- Decision Date: 2026-11-08. The owner chose to register these reads here and to change only the temperature read under M2.
- Decision Date: 2026-11-11. The owner chose to correct the premise of this row, because the other reads already report once per outage, and to narrow it to the two `AIn` reads at a low priority.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. After M2, apply the same once-per-change reporting to the reads the owner selects, with a fixture condition and a counted-lines case for each.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | For each selected read, drive a persistent error from the fixture and count the driver's lines. | Common integration environment with a fixture condition for the read | One start line and one end line per read; the driver before the change prints one per poll. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | Common integration environment | Pending | none |

##### Closure Evidence

- Observed 2026-11-08 while reviewing the plan of M2: the call sites are `reportError()` after `DIn`, `CIn`, `AIn` and the scan status calls in the poll loop.
- Read 2026-11-11: the `if (!prevStatus)` guards of the `DIn`, `CIn`, `AOutScanStatus` and `AInScanStatus` reports come from the upstream commit e32f3c6 of 2020-11-09, "Changes in poller to avoid error storms when device is not available", and were in the code when this row was written (commit 9c39e49); `prevStatus` holds the input status of the previous poll and is cleared when the poll returns to normal. The two `AIn` reports have no such guard. The statement of the 2026-11-08 observation, that these reads print on every poll, therefore holds only for `AIn`.

##### GitHub Projection

Title: none
Labels: none
GitHub Milestone: none
Observed State: none
Observed Labels: none
Observed Milestone: none
Last Compared: never

#### M10 - E-TC Array Read

Origin: 9c39e49 / M10
Identity History: none
GitHub Issue: none
Status: Open

##### Summary

The E-TC network thermocouple device is read one channel per `ulTIn()`, and `AiETc::tIn()` calls `tInArray(channel, channel, ...)`, so each channel costs its own request. `AiETc::tInArray()` reads a range with one `CMD_TIN` request and maps the device values -8888 and -9999 to -9999 and -11111 (`src/net/ai/AiETc.cpp` of ULDAQ 1.2.2, read 2026-11-09). `tests/` has no E-TC protocol fixture, so a change to this path cannot be exercised.

##### Scope

Decide whether the E-TC gets the array read of the TC32, the cold-junction temperatures, the calibration table and the calibration dates that the TC32 gets under the diagnostics work (`AiETc` has no rejection frequency), and an E-TC fixture for its discovery, `CMD_TIN` and `CMD_CJC` frames.

Out of scope: The TC32, which reads its channels in one request under the persistent read error and single-request work, and USB boards.

##### Completion Criteria

- The owner decides the priority and the fixture scope, and the row is then moved to Not started, Deferred or retired with a dated decision.

##### Dependencies And Decisions

- Decision Date: 2026-11-09. The owner chose to change only the TC32 under the single-request work and to register the E-TC here, because no fixture exists for it.
- Decision Date: 2026-11-09. The owner chose to move the E-TC counterparts of the diagnostics work here as well, for the same reason.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Add an E-TC fixture, then apply the array read of the TC32 to the E-TC and count its temperature requests.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Run a case on an E-TC fixture and count the temperature requests of one poll. | Common integration environment with an E-TC fixture | One temperature request per poll; the driver before the change issues one per channel. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | Common integration environment | Pending | none |

##### Closure Evidence

- Observed 2026-11-09 while reviewing the plan of the single-request work: `tests/` holds only `TC32.pm` and `E1608.pm`.

##### GitHub Projection

Title: none
Labels: none
GitHub Milestone: none
Observed State: none
Observed Labels: none
Observed Milestone: none
Last Compared: never

#### M11 - Mixed Value At A State Change Of The Averaging Temperature Record

Origin: 9c39e49 / M11
Identity History: none
GitHub Issue: none
Status: Complete

##### Summary

The shipped temperature template `measCompTemperatureIn.template` reads with `asynFloat64Average` and `SCAN` of one second, so one published value is the mean of the samples of one scan. At the moment the open detection or the scale of a channel changes, that mean mixes the samples of the old and the new state and is published as a valid reading. The site database, which uses `asynFloat64` and `MDEL` -1, published no such value in the same transitions. The cause is the mean that the asyn device support `asynFloat64Average` forms from the values published since the record was last processed (read in the asyn R4-46 source on 2026-11-11); the observed values agree with it by arithmetic.

##### Scope

Document in the user documentation that the default temperature record averages the samples of one scan, so the one value published at a change of the open detection or of the scale can mix the old and the new state, and name the setting that avoids it, `DTYP` `asynFloat64`, which the site template sets together with `MDEL` -1. The default template is not changed.

Out of scope: a change of the default of the template, the site repository, the driver read path and the E-TC and USB boards that share the template.

##### Completion Criteria

- The user documentation says that a value published at a change of the open detection or of the scale can mix the two states when the record averages, and names the setting that avoids it.
- The default template is unchanged.

##### Dependencies And Decisions

- Decision Date: 2026-11-10. The owner chose to register the observation as a backlog row with the priority and the remedy undecided.
- Decision Date: 2026-11-11. The owner chose to document the behavior and leave the default template unchanged, because the site template already avoids it, the averaging is an intended default, and the mixed value appears only at the moment a setting changes.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-11-11; accepted by the owner after the remedy was decided on the observations of the real TC-32 and the site template; no separate review pass was held before acceptance. The wording of the Scope and of plan item 1 was corrected the same day, after the asyn source showed that only `DTYP` removes the averaging; the scope of the plan did not change.
Implementation Authorization: 2026-11-11; implement and verify the accepted plan item 1.
Superseded Plan Artifacts: none

1. In `docs/source/measCompMultiFunctionDoc.rst`, extend the description of the `$(P)$(R)` temperature record: the default template reads with `asynFloat64Average`, so at a change of the open detection or of the scale the one value that averages samples of both states is published as valid, and a record with `DTYP` `asynFloat64` reads the latest value and publishes no such value; the site sets `MDEL` -1 together with it, and the shipped template fixes `DTYP`, so a modified copy of the template is needed. Verified by T1.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Documentation | Read the changed passage from the seat of a user who scans a TC-32 with the default template and check each statement against the template and the observations in Closure Evidence. | Repository documents in the working tree | The reader can tell when a mixed value appears and which setting avoids it, and every statement matches its source. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-11, finished by 2026-11-11T19:14:42Z | Repository documents in the working tree | Pass: three second-person reads by delegated readers followed the changed entry of the record `$(P)$(R)` from the seats of a user who scans a TC-32 with the default template, of a user who must change the template, and of a maintainer who compares the register with the entry and the sources, and checked each statement against the template, the asyn R4-46 source (`devAsynFloat64.c`), the EPICS base source for `MDEL`, the site substitutions and the recorded observations. The first read found one minor finding (the entry did not say where the settings are made, and the shipped template fixes `DTYP` and has no `MDEL`) and the second one (the register still named `DTYP` and `MDEL` together as the avoiding settings); both were corrected, and the third found nothing above the floor. Four info items were left unchanged | Source identity: `docs/source/measCompMultiFunctionDoc.rst` SHA-256 `314a489c36c22b1c597aefcb08e1744864b7e6a3e6d17f8034a40d163b12f682` |

##### Closure Evidence

- Observed 2026-11-09 and 2026-11-10 on the real TC-32 with the measComp-repository IOC (default template, `SCAN` one second, scratch builds of 4884b71): at the open-detection write of 11:26:16 the channel published -4720.89 and, at the reattach about 3 minutes later, -8416.18, each as a valid value without alarm; the cut sensor gave -7887.71 and -8801.9 in the same way; at scale changes one update mixed the units (channel 2: 32.39 and 87.40 from Celsius to Fahrenheit and to Kelvin, 15.66 and 20.51 into and out of Volts; channel 31: 59.77, 211.48, 148.82 and 9.53). Arithmetic, not checked in the code: -4720.89 equals 9 of 19 polls at -9999 and the rest at 29.41, and -8416.18 equals 16 of 19 at -9999 and the rest at 25.70, with about 19 polls in one second.
- Observed 2026-11-09 13:24 to 13:26 on the same device with the site IOC (`tcmd` 498510d, `asynFloat64`, `MDEL` -1) built against measComp 4884b71: the next update after each open-detection and scale change showed the new state with no intermediate value.
- Read 2026-11-11 in the asyn R4-46 source (`devAsynFloat64.c`): `interruptCallbackAverage()` adds each published value to a sum and counts it, and `processAiAverage()` takes the mean and clears both when the record is processed; plain `asynFloat64` has no accumulator and reads the current value. `MDEL` -1 only makes the record post a monitor at every processing and does not change the averaging; the observations of the site record were made with both settings together.
- Read 2026-11-11: the `$(P)$(R)` record of `measCompTemperatureIn.template` has `DTYP` `asynFloat64Average`, and the record table of the user documentation says only that the field should be scanned periodically; the site `TC32-alsu.substitutions` of the `tcmd` repository sets `DTYP=asynFloat64` and `MDEL=-1` for every channel.
- Landed: observed 2026-11-11T19:41:11Z after `git fetch`, `origin/site` is at commit 853295be9000566b6440550572417fd36ec1f859, the same commit as the local `HEAD`, and the path changed by the implementation commit cb05c18 (`docs/source/measCompMultiFunctionDoc.rst`) shows no difference between that commit and `origin/site`. Recheck with `git diff cb05c18 origin/site -- <path>`. There is no linked issue.
- Remaining behavior: the default template is unchanged and still publishes one mixed value at a change of the open detection or of the scale; a user who needs none uses a modified copy of the template with `DTYP` `asynFloat64`. The documentation could not be rendered, because `sphinx-build` is not installed on the host.

##### GitHub Projection

Title: none
Labels: none
GitHub Milestone: none
Observed State: none
Observed Labels: none
Observed Milestone: none
Last Compared: never

## History

| Reset Date | Prior State Commit |
| --- | --- |
| 2026-11-08 | 9c39e491e463fac77f15cfcec16aa8b4a97cbf10 |
