# Network Thermocouple Acquisition

Release line: site (unversioned)
Milestone index: 9c39e49
Canonical path: `docs/milestone-9c39e49.md`
Canonical branch or ref: site
Git upstream: origin/site
Remote tracker: [jeonghanlee/measComp milestone 2](https://github.com/jeonghanlee/measComp/milestone/2)
GitHub milestone: Network thermocouple acquisition
Due date: none
Remote milestone observed at: 2026-11-09T17:31:46Z; state: open; two open issues (#14 and #15) and three closed issues (#11 to #13)
Recheck remote milestone with `gh api repos/jeonghanlee/measComp/milestones/2`.
Baseline commit: 9c39e491e463fac77f15cfcec16aa8b4a97cbf10

Next session entry point: Review and accept the plan of M4 (issue #14) in its detail, the nearest Ready row; it can use the per-channel values and the request shape that the single-request read added to `tests/TC32.pm`. Issues #11 to #15 are assigned to GitHub milestone 2.

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
| M4 | Thermocouple device diagnostics | Carry-forward | Not started | Yes | | Cold-junction temperatures, mains rejection and calibration information are exposed; issue #14; [detail](#m4---thermocouple-device-diagnostics) |
| M5 | Temperature filter on Linux | Carry-forward | Not started | Yes | | The temperature filter takes effect on Linux; issue #15; [detail](#m5---temperature-filter-on-linux) |

The row order follows issue numbers and imposes no execution dependency. Current status: three Complete and two Not started. `Ready` records dependency readiness only. No external prerequisite is established for these rows.

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
Status: Complete

##### Summary

A TC32 channel outside the common-mode range makes `ulTIn()` return `ERR_CMR_EXCEEDED` on every read, and the poller calls `reportError()` for the channel on every poll: with the fixture reporting the condition on every channel, the IOC printed 3,040 error lines in about five seconds while the records stayed INVALID with their last value.

##### Scope

Report a thermocouple channel's read error once when its status changes, with the channel number in the line, and once when the channel returns to normal at the same error trace level, keeping the per-channel INVALID status on every poll and the open-thermocouple value. The per-channel state starts over when the port connects and when a channel leaves the thermocouple type.

Out of scope: Connection errors, the open-thermocouple value, the other read calls of the poll loop (digital input, counter, analog input and scan status), which M9 tracks, and Windows verification.

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
- Remaining behavior: the other reads of the poll loop (digital input, counter, analog input and scan status) still print an error on every poll; row M9 tracks them. The device value -8888 means an open thermocouple: ULDAQ turns it into the data value -9999 with `ERR_OPEN_CONNECTION`, and the driver already reports -9999 without an error (read in the ULDAQ 1.2.2 source 2026-11-09).

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
- A record with `TSE=-2` takes the timestamp of its poll: the timestamp lies within two seconds of the current time, advances from one poll to the next, and is the same for the records of different channels in one poll.
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

##### GitHub Projection

Title: Read all TC32 thermocouple channels in one request and stamp the acquisition time
Labels: enhancement
GitHub Milestone: Network thermocouple acquisition (milestone 2)
Observed State: closed
Observed Labels: enhancement
Observed Milestone: Network thermocouple acquisition (milestone 2)
Last Compared: 2026-11-09T17:31:46Z; remote updated at 2026-11-09T17:30:19Z

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
| M9 | Persistent errors of the other poll-loop reads | Carry-forward | Open | No |  | The digital input, counter, analog input and scan status reads report a persistent error once per change as the temperature read does, or the owner records that they need not; priority and fixture are undecided; [detail](#m9---persistent-errors-of-the-other-poll-loop-reads) |
| M10 | E-TC array read | Carry-forward | Open | No |  | The E-TC reads its channels with one request per poll, verified with an E-TC protocol fixture; priority and fixture scope are undecided; [detail](#m10---e-tc-array-read) |
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
| T1 | Regression | Run every case of `tests/test_reconnect.pl` and the exit loop with the README commands, and the Perl checks and the compile of the changed C++ files in the Rocky 8 image with the commands of the README section "Static checks"; the cases that use the TC32 and E-TC protocol fixtures are the guard for the network temperature devices. | Common integration environment; Rocky 8 image | All pass with normal IOC exit; the changed files compile on Rocky 8. |
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
| T1 | Regression | Run every case of `tests/test_reconnect.pl` and the exit loop with the README commands, and the Perl checks and the compile of the changed C++ files in the Rocky 8 image with the commands of the README section "Static checks"; the cases that use the TC32 and E-TC protocol fixtures are the guard for the network temperature devices. | Common integration environment; Rocky 8 image | All pass with normal IOC exit; the changed file compiles on Rocky 8. |
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

#### M9 - Persistent Errors Of The Other Poll-Loop Reads

Origin: 9c39e49 / M9
Identity History: none
GitHub Issue: none
Status: Open

##### Summary

The poll loop of `MultiFunction::pollerThread()` calls `reportError()` on every poll for each failing read, not only for the temperature read: `DIn`, `CIn`, `AIn` and the two scan status calls print the same error line on every poll while an error persists (`drvMultiFunction.cpp`, read 2026-11-08). The temperature read is changed under M2; the others were not reproduced, because the TC32 fixture has no condition for them.

##### Scope

Decide whether these reads report a persistent error once per change as M2 does, with which fixture conditions, and whether a shared helper replaces the per-read state.

Out of scope: the temperature read, which M2 changes, and connection errors.

##### Completion Criteria

- The owner decides the priority and scope, and the row is then moved to Not started, Deferred or retired with a dated decision.

##### Dependencies And Decisions

- Decision Date: 2026-11-08. The owner chose to register these reads here and to change only the temperature read under M2.

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

Decide whether the E-TC gets the array read of the TC32 and an E-TC fixture for its discovery and `CMD_TIN` frames.

Out of scope: The TC32, which reads its channels in one request under the persistent read error and single-request work, and USB boards.

##### Completion Criteria

- The owner decides the priority and the fixture scope, and the row is then moved to Not started, Deferred or retired with a dated decision.

##### Dependencies And Decisions

- Decision Date: 2026-11-09. The owner chose to change only the TC32 under the single-request work and to register the E-TC here, because no fixture exists for it.

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
