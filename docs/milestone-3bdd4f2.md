# Connection Recovery And Device Selection

Release line: site (unversioned)
Milestone index: 3bdd4f2
Canonical path: `docs/milestone-3bdd4f2.md`
Canonical branch or ref: site
Git upstream: origin/site
Remote tracker: [jeonghanlee/measComp milestone 1](https://github.com/jeonghanlee/measComp/milestone/1)
GitHub milestone: Connection recovery and device selection
Due date: none
Remote milestone observed at: 2026-11-06T19:16:41Z; state: open; five closed issues and one open issue
Recheck remote milestone with `gh api repos/jeonghanlee/measComp/milestones/1`.
Baseline commit: 3bdd4f24d820579f3f423c7be968baf2bb413950

Next session entry point: M1 through M5 and M7 are complete and landed on `origin/site`. M6 (issue #7) remains a draft plan; decide its cache identity, hostname verification and mixed-selection scenario, then accept the plan and record implementation authorization before starting it.

## Scope

This document assigns issues #2 through #7 to six work units, plus one follow-up work unit without an issue, for the independently maintained `site` branch. It owns their scope, implementation plans, tests, verification results and closure evidence. GitHub retains the live issue metadata. M1 through M5 are complete; M6 remains a draft plan.

The common integration environment is Linux with the real measComp driver, EPICS Base 7.0.10, asyn 4.45 and patched ULDAQ 1.2.2. Extend the shipped Perl/Bash tests and retain `tests/reconnect_ioc.cpp`; use external device protocol fixtures, without replacing internal driver, asyn or ULDAQ functions. Record the source commit, dependency identities, assertions, fixture requests and native IOC exit status for each executed check. Checks reproducing a defect must fail for the intended assertion on the affected baseline and pass on the fixed code; setup and build failures do not establish a regression. Compatibility checks and positive controls must pass on both the baseline and fixed code. When a check combines these purposes, record the defect assertion separately from its controls.

Existing failure observations below come from the linked issues at the baseline commit. They are not successful verification of a fix. M1 through M5 record observed post-fix verification, repository landing and linked-issue closure. M6 remains unimplemented. The analog metadata findings are separate from the normal floating-point TC32 temperature path. MAC rediscovery and same-IP/different-discovery-port selection retain their specific applicability conditions.

**Out of scope:** ULDAQ vendor patch development, upstream submissions, release numbering, tags, deployment, output-command replay, and a general qualification of Windows, USB, EXP-32 or hardware power cycling. Changes to `docs/reconnection.md` and `tests/README.md` belong to the affected work unit when behavior or test invocation changes. Existing test limitations remain explicit.

## Milestone

### Work

| ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| M1 | TC write and readback consistency | Milestone | Complete | No | | Device and cache agree after a failed write and reconnect; [detail](#m1---tc-write-and-readback-consistency) |
| M2 | Digital output failure handling | Milestone | Complete | No | | Transport errors disconnect and invalidate inputs before the next poll; [detail](#m2---digital-output-failure-handling) |
| M3 | Analog enum initialization | Milestone | Complete | No | | Offline-start records obtain the same enums as online-start records; [detail](#m3---analog-enum-initialization) |
| M4 | Analog conversion initialization | Milestone | Complete | No | | Offline-start conversion matches online-start conversion and measured raw values; [detail](#m4---analog-conversion-initialization) |
| M5 | MAC device rediscovery | Milestone | Complete | No | | An initially absent MAC-selected device connects without disturbing existing ports; [detail](#m5---mac-device-rediscovery) |
| M6 | Discovery endpoint identity | Milestone | Not started | Yes | | Devices sharing an IP but using different discovery ports remain independent; [detail](#m6---discovery-endpoint-identity) |
| M7 | Identifier case and refresh diagnostics | Milestone | Complete | No | | A lower-case MAC connects and a failed refresh is reported once; [detail](#m7---identifier-case-and-refresh-diagnostics) |

The row order follows issue numbers and imposes no execution dependency. Current status: six Complete and one Not started. `Ready` records dependency readiness only; the remaining draft plan still requires acceptance and implementation authorization. No external prerequisite is currently established. If a required hardware or third-party dependency is selected later, add an external-gate row and record the affected work before changing its status.

### Milestone Details

#### M1 - TC Write And Readback Consistency

Origin: 3bdd4f2 / M1
Identity History: none
GitHub Issue: [#2](https://github.com/jeonghanlee/measComp/issues/2)
Status: Complete

##### Summary

A failed thermocouple-type write can leave the public asyn cache reporting an unconfirmed value. At the baseline, a successful type `2` write followed by a type `3` write with injected EOF returned `asynError`; reconnect restored device type `2`, while `THERMOCOUPLE_TYPE` still read `3`. Direct IP selection is affected. In `measCompApp/src/drvMultiFunction.cpp`, `writeInt32()` updates the cache before the vendor call, successful writes alone update `savedTCType_`, and `restoreTemperatureConfig()` restores hardware without reconciling the cache.

##### Scope

Make thermocouple-type writes, saved successful settings and cache-backed readback consistent across vendor write failure and reconnection. Extend the real TC32 transport regression and retain a successful-write control.

Out of scope: queued output replay, changing thermocouple type definitions, and unrelated integer parameter behavior.

##### Completion Criteria

- A failed TC-type write does not leave the cache reporting an unconfirmed setting.
- After reconnect, the device setting and cache-backed readback agree with the last successful write.
- Regression coverage exercises the real driver and transport failure, and retains a successful-write control.
- All local checks pass with durable evidence.
- The linked issue is observed closed, or Closure Evidence records a dated exception limited to issue closure.

##### Dependencies And Decisions

- None. No execution order or external dependency is established.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-11-05; the reviewed plan was accepted for sequential issue implementation, beginning with #2.
Implementation Authorization: 2026-11-05; implement and verify the first issue under the instruction to resolve the issues one at a time.
Superseded Plan Artifacts: none

1. Commit thermocouple-type cache and saved-setting updates only after a successful vendor write, preserving the last confirmed value on failure.
2. Reconcile cache-backed readback with successfully restored settings in `restoreTemperatureConfig()` and publish the matching callbacks.
3. Add successful-write, failed-write and reconnect assertions to the shipped Perl test using the public asyn interface and external fixture observations.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Write type `2`, inject EOF during type `3`, reconnect, and compare the actual fixture setting with public asyn readback. | Common integration environment; direct-IP TC32 fixture | The failed write returns an error; both device and cache report type `2` after recovery. |
| T2 | Integration | Read the cache immediately after a failed write, then perform a successful write after recovery and repeat the failure sequence. | Common integration environment; direct-IP TC32 fixture | A failed write never becomes the confirmed cache value; each successful write updates both device and cache. |
| T3 | Regression | Run the complete shipped reconnect suite, including settings restoration, bank-wide open detection and connection controls. | Common integration environment | All assertions pass, no unsupported fixture requests occur, and the IOC exits normally. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-05T18:14:19Z | Debian 13.7; Perl 5.40.1; EPICS Base 7.0.10; asyn 4.45; patched ULDAQ 1.2.2; real IOC and external TC32 fixture | Pass | Type `2` succeeded, type `3` returned `asynError` after command `0x15` EOF, and both public SyncIO readback and the device returned `2` after reconnect. The baseline failed the same assertion with device `2` and cache `3`. |
| T2 | 2026-11-05T18:14:19Z | Same real-path environment as T1 | Pass | Immediate public asynInt32 cache reads returned the last successful value. Sequences were channel 0: `2` then failed `3`, channel 0: `4` then failed `5`, and channel 31: `6` then failed `7`. Each successful write updated device and readback; each recovery preserved `2`, `4` or `6` respectively. |
| T3 | 2026-11-05T18:14:19Z | Same real-path environment as T1 | Pass | Full shipped suite: 38/38 assertions, seven injected faults, zero fixture errors, native test exit `0` and IOC exit `0`. Existing EOF, short-header, timeout, bank-wide OTD, auto-connect and port-enable checks all passed. |

Verification evidence:

- Baseline source: `3bdd4f24d820579f3f423c7be968baf2bb413950`; driver SHA-256 `f1d3e202cea90d7eabaf4fd25316ebaa383662a63b2fc13ff9816d0c8cfaf367`. The new regression failed at `TC channel 0 type 2 survives failed write` at 2026-11-05T18:12:52Z: immediate cache `3`, recovered cache `3`, device `2`. Native test exit was `1`; the failing test terminated its IOC with SIGTERM (`-15`). There were no fixture errors.
- Fixed driver SHA-256: `68c3346f4c80c0e05ebd48c6cba0ed0526e1cf65d61e4279133774e9fe9c2ed1`; test runner: `10926572fa4656fd2e3af2fde590704c94789b21812d229e875f1e0f0efcba83`; test IOC source: `ae46143ecb75d2ecb99036e83bb84c71138449407657ef5103846a6cf5a1d4d9`.
- Dependency SHA-256: patched `libuldaq.so` `6ff4e93258081a8936416698a798ffdd5536255deb8a2d681344fc4bc86439e4`; `libasyn.so` `2badf9290ba0b58801c0df8d4e899de024212b3a7e34d88c056e3d72c6405564`; `libdbCore.so` `8ff86ce4a6a5e6e010be7688cf413f6bc0e7c0997c134b96401e8d7197927bc3`.
- Build commands, generated IOC, source hashes and raw IOC/JSON logs are retained locally under `work/m1-tc-cache/baseline/` and `work/m1-tc-cache/fixed/`. Fixed JSON SHA-256: `ba90022560b4cb8d8fbfac3be42bd5bb4cf6e96a457ccf3dce6c70cb35606546`. The observations and identities above remain in this document; ignored `work/` files are not repository landing evidence. Reproduce with `tests/README.md` and the supplied `build_reconnect.pl` and `test_reconnect.pl` entry points.
- Negative controls used copies of the real driver with the shipped tests unchanged. At 2026-11-05T18:16:03Z, `early-tc-cache` failed the same assertion with immediate cache `3`, recovered cache `2`, device `2`. At 2026-11-05T18:16:07Z, `no-restore` failed with immediate and recovered cache `2`, device `1`. Both native test exits were `1`, IOC exits were `-15` after assertion cleanup, and fixture errors were empty. Their builds and logs are under the corresponding `work/m1-tc-cache/` directories.
- The unchanged baseline suite previously passed 29/29 assertions with no fixture errors and IOC exit `0` at 2026-11-05T01:57:10Z. The fixed run above retains all 29 checks and adds nine TC checks.
- Perl syntax, POD and help checks passed on Debian 13.7 / Perl 5.40.1. Syntax, module loading, help and usage-error exit `2` also passed on Perl 5.26.3 in the existing `jeonghanlee/rocky8-epics:1.2.2` image (`507b995d50e4`); the full IOC integration run was on Debian, not Rocky.

##### Closure Evidence

- The accepted implementation and T1 through T3 are verified in 98415c0d604a386c4b946f67857624ffe6923b55. TC writes commit the cache only after vendor success, and successful restoration reconciles the cache before connection callbacks are published for temperature addresses.
- Review acceptance: 2026-11-05; first-person, third-person and second-person self-review completed for the M1 implementation and documentation. No unresolved in-scope findings remain. The third-person check confirmed all 12 recorded build inputs still match the files and the IOC resolves the intended vendor and EPICS libraries.
- Remote landing observed at 2026-11-05T19:06:14Z: after fetching `origin`, `origin/site` was 7ccb7d0b86c64582eafd369332078cd396ffedd6 and contained 98415c0d604a386c4b946f67857624ffe6923b55. Comparing the five changed driver, test and documentation files between the fix commit and `origin/site` produced no differences. Recheck with `git fetch origin`, `git branch -r --contains 98415c0` and a path-limited `git diff 98415c0 origin/site`.
- Issue #2 was observed closed with reason `completed` at 2026-11-05T19:01:10Z; GitHub recorded closure at 2026-11-05T19:00:37Z. Its body matches the verified implementation, all four acceptance items are checked, and the result comment is https://github.com/jeonghanlee/measComp/issues/2#issuecomment-6666614605. No completion condition is waived.

##### GitHub Projection

Title: Keep thermocouple readback consistent after a failed write
Labels: bug
GitHub Milestone: Connection recovery and device selection
Observed State: closed
Observed Labels: bug
Observed Milestone: Connection recovery and device selection (milestone 1)
Last Compared: 2026-11-05T19:01:10Z; remote updated at 2026-11-05T19:00:37Z

Recheck metadata with `gh issue view 2 --repo jeonghanlee/measComp --json state,labels,milestone,updatedAt`.

#### M2 - Digital Output Failure Handling

Origin: 3bdd4f2 / M2
Identity History: none
GitHub Issue: [#3](https://github.com/jeonghanlee/measComp/issues/3)
Status: Complete

##### Summary

At the baseline, a digital output EOF returned `asynError` while the port remained connected and temperature input severity remained `NO_ALARM` before the next poll. The reproduction used `POLL_SLEEP_MS=10000` and confirmed that the poller was sleeping. Direct IP selection is affected. `writeUInt32Digital()` in `measCompApp/src/drvMultiFunction.cpp` reports the vendor error but lacks the `isConnectionError()` and `disconnect()` transition used by `writeInt32()`.

##### Scope

Apply transport-error disconnection and input invalidation to digital output writes, preserving last valid input values and the existing reconnect policy.

Out of scope: automatic digital output replay, changing digital direction semantics, and disconnecting healthy devices for non-transport errors.

##### Completion Criteria

- Digital output transport errors promptly disconnect the port and invalidate input records while preserving their last valid values.
- Reconnection obeys the existing port-enable and auto-connect controls.
- Non-transport write errors do not unnecessarily disconnect a healthy device.
- Regression coverage observes the error transition before another poll can mask the omission.
- All local checks pass with durable evidence.
- The linked issue is observed closed, or Closure Evidence records a dated exception limited to issue closure.

##### Dependencies And Decisions

- None. Shared source files with M1 do not establish a functional dependency.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-11-05; the reviewed issue #3 plan was accepted as the next item in sequential implementation.
Implementation Authorization: 2026-11-05; proceed with the next issue after #2 closure.
Superseded Plan Artifacts: none

1. Apply the existing connection-error classification to digital vendor writes and invoke the normal disconnect path after releasing the vendor mutex.
2. Stop multi-bit write processing on the first vendor error so later successful operations cannot erase it; retain non-transport error reporting without disconnecting a healthy port.
3. Add public port-state and input-alarm observations before the next poll, with normal-write and non-transport-error controls.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Set all port bits to output and use the full-port mask to exercise `ulDOut`; confirm a successful write, wait until the poller sleeps, inject EOF during another word write, and inspect temperature and digital inputs before the next poll. | Common integration environment; TC32 fixture; long poll interval | Fixture traffic confirms the word-write path; the failed write disconnects the port immediately, input severity becomes INVALID, and last valid input values remain available. |
| T2 | Integration | During a word write, return a complete response with the matching command and frame ID, a correct checksum and one unexpected payload byte. Confirm that real ULDAQ returns `ERR_BAD_BUFFER_SIZE`, then issue a normal write. A nonzero response status alone is not an error trigger in this ULDAQ path. | Common integration environment; external TC32 protocol fixture | The failed operation reports `asynError` without disconnecting a healthy device; the next normal write succeeds. This is a compatibility control and must also pass on the baseline. |
| T3 | Integration | While connected and enabled, disable auto-connect, inject a write transport failure and confirm disconnection. Restore the fixture and verify that auto-connect disabled prevents recovery. Disable the port, enable auto-connect, and verify that the disabled port still prevents recovery; a write then returns `asynDisabled` without device traffic. Finally enable the port and observe recovery. | Common integration environment; TC32 fixture; observations spanning the reconnect interval | The fault occurs while writes are enabled. Both controls independently prevent recovery; enabling both permits reconnection and clears input alarms after valid reads. |
| T4 | Integration | Select at least two output bits with a partial-port mask to exercise the `ulDBitOut` loop. Suppress one response for a non-final selected bit until the vendor call times out, keep the socket open, discard that response, and answer subsequent requests normally. Record the real read/write request sequence and inspect the public result and input state before the next poll. | Common integration environment; external TC32 protocol fixture; long poll interval | The baseline exposes an earlier transport failure overwritten by a later successful bit operation. Fixed code returns an error, disconnects and invalidates inputs while preserving their last valid values. Processing stops on the first error, with no later bit requests. |

Execution contract: each case starts a fresh IOC and external fixture in an isolated Linux network namespace. The executable contains the actual driver and discovery source, real EPICS/asyn/ULDAQ libraries, and shipped temperature and binary-input templates. Only the external device transport is simulated. Perl 5.26.3 is the oldest CLI target; the integration host uses Perl 5.40.1. Runtime evidence is retained below `work/m2-digital/`, separately for baseline, fixed code and scratch mutations.

| Safeguard | Criterion and evidence |
| --- | --- |
| Volume and limits | Each digital case has a 90-second outer deadline; the existing reconnect case has 100 seconds. Retain complete IOC logs, request/reply traces, JSON checks and native exit codes. Record actual file sizes and request counts; this bounded functional test does not establish sustained retention or endurance. |
| Expected results | T1-T4 define connection, severity, value and write-result expectations independently of observed results. T2 must also pass on the baseline. A missing response or incomplete case is not acceptance. |
| Time boundaries | Set the poll interval to 10 seconds and observe the final temperature request before injection. Require the failure observation within that interval and no intervening input poll in the trace. T3 observes each disabled control for 12 seconds. Use monotonic timestamps for intervals and UTC for run correlation. |
| Fault application | Record selected command, frame, payload, fault mode and actual error diagnostic. EOF closes the external socket; bit timeout drops one response without closing it; the non-transport control returns a complete checksummed response with one unexpected byte. |
| Measurement meaning | Each trace belongs to one fresh fixture/IOC lifetime. Connection counts and request counts are per fixture; state snapshots include the public port state and actual record values/severities. Permit callback completion only inside the same no-poll observation window. |
| Source and dependencies | Retain builder commands, source SHA-256 manifest, executable hash and linked-library identities for each build. Execute the shipped Perl entry point with the generated IOC and DBD. Baseline and scratch mutants use the same fixtures. |
| Case coverage | Run T1-T4 separately and the existing reconnect suite. Baseline word/bit failures must occur at their intended assertions. Scratch mutations that omit first-error handling or classify a non-transport error as transport must fail the corresponding checks. Retain setup-failure and handled-interruption outcomes separately. |

Long observations, archive transfer, offline replay and durable two-stage terminal-save protocols are not part of this test contract. No claim is made for hardware, Windows, USB or expansion devices.

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-05T19:23:36Z | Debian 13; common integration environment; isolated TC32 fixture | Passed | `work/m2-digital/fixed-final/digital-word.log.json`: 11/11 checks, native test and IOC exit 0. Baseline `baseline-2/digital-word-final` returns an error but retains connected/NO_ALARM before any next poll, failing the intended immediate-disconnect assertion. |
| T2 | 2026-11-05T19:23:26Z | Same real stack; complete external response with one unexpected byte | Passed | `work/m2-digital/fixed-final/digital-control.log.json`: 12/12 checks, error 9, retained connection, subsequent successful write, native test and IOC exit 0. Baseline control also passes 12/12. `disconnect-any-error/build/digital-control` fails at the intended connection-retention assertion. |
| T3 | 2026-11-05T19:23:50Z | Same real stack; separate fresh IOC and fixture | Passed | `work/m2-digital/fixed-final/digital-policy.log.json`: 17/17 checks; both disabled-control windows span 12 seconds, no extra connection, disabled write returns status 5 with request count unchanged at 244, then recovery; native test and IOC exit 0. |
| T4 | 2026-11-05T19:23:36Z | Same real stack; socket retained while one bit response is suppressed | Passed | `work/m2-digital/fixed-final/digital-bits.log.json`: 15/15 checks, 3.220-second write failure, status 3, disconnected/INVALID with unchanged values, exactly one read and one write before failure observation; native test and IOC exit 0. Baseline `baseline-2/digital-bits-verified` and `overwrite-bit-error/build/digital-bits` both fail the intended retained-error assertion after later successful bit traffic. |

The fixed driver SHA-256 is `7d5d220de8c1d6bf958c740ba62bd3714578ad44bf8b27d31aca73ac2287fcdc`; the test executable is `8f0f76d8532ac6a0f9a144e001dda3b583d5ed8ca17f1c89f9b8db80c7c1eef3`. `work/m2-digital/fixed-final/inputs.json` retains 13 build input hashes, all matched to the verified source. Each run also retains its current test hashes, UTC bounds, stdout/stderr, native status and full JSON trace. `work/m2-digital/libraries.txt` and `libraries.sha256` identify the loaded dependencies. The patched ULDAQ hash is `6ff4e93258081a8936416698a798ffdd5536255deb8a2d681344fc4bc86439e4`.

The existing reconnect case passed 38/38 at 2026-11-05T19:24:11Z (`fixed-final/reconnect.log.json`, native test and IOC exit 0), giving 93/93 checks across the five final cases. Their JSON evidence contains 211 to 1,136 requests per case and occupies 45,710 to 244,371 bytes per file. `work/m2-digital/results.txt` records the exact counts. The baseline word/control runs preceded the final timeout diagnostic adjustment; that adjustment only changes the bit-timeout assertion from error 103 to errors 7 or 103. The final baseline bit run and both scratch mutants use the final test bytes. In this fixture ULDAQ reports error 7 after the receive timeout because its UDP connection-code probe does not report the device as busy; the retained TCP trace independently establishes later successful requests on the baseline.

Perl syntax, POD and CLI checks passed on Debian 13 / Perl 5.40.1 and the existing Rocky 8 image / Perl 5.26.3. The Rocky image identity and module probe are retained in `work/m2-digital/rocky8-image.txt`, `rocky8-cli.txt` and `rocky8-final.txt`; no Rocky IOC integration result is claimed. Initial missing-template failure and TERM interruption were exercised through the shipped CLI after observing the real IOC and listening sockets. `work/m2-digital/lifecycle.txt` and `fixed-final/lifecycle-*` retain native runner exits 1/143, child identities, and socket observations proving cleanup without an external cleanup guard.

##### Closure Evidence

- The implementation and T1-T4 are verified in 5ee7103001a907d03f7354805a911b064e2749db. Repository landing and linked-issue closure are observed below; no completion condition is waived.
- Remote landing observed at 2026-11-05T20:38:24Z: after fetching `origin`, `origin/site` was 5ee7103001a907d03f7354805a911b064e2749db, matching local HEAD. The committed diff matches the reviewed eight-file selection. Comparing the driver, tests and reconnection documentation between the fix commit and `origin/site` produced no differences. Recheck with `git fetch origin`, `git rev-parse HEAD origin/site` and `git diff 5ee7103 origin/site -- measCompApp/src/drvMultiFunction.cpp tests docs/reconnection.md`.
- Issue #3 was observed closed with reason `completed` at 2026-11-05T20:38:24Z; GitHub recorded closure at 2026-11-05T20:37:58Z. Its body matches the verified implementation, all five acceptance items are checked, and the result comment is https://github.com/jeonghanlee/measComp/issues/3#issuecomment-6668705283.
- Review acceptance: 2026-11-05; four direct self-review passes (first-person, third-person, second-person, second-person recheck), no delegated review. The reader pass found a missing `TEMPLATE` definition after leaving the earlier namespace; the digital instructions now establish it explicitly. Commands extracted directly from the corrected README passed all 55 digital checks with normal IOC exits and shell exit 0; evidence is `work/m2-digital/readme-digital.stdout`, `readme-digital.stderr` and `fixed-final/{word,control,policy,bits}.log.json`. The third-person pass rechecked request order, connection identity and recorded response frames/checksums. No unresolved in-scope finding remains.

##### GitHub Projection

Title: Disconnect on digital output transport errors
Labels: bug
GitHub Milestone: Connection recovery and device selection
Observed State: closed
Observed Labels: bug
Observed Milestone: Connection recovery and device selection (milestone 1)
Last Compared: 2026-11-05T20:38:24Z; remote updated at 2026-11-05T20:37:58Z

Recheck metadata with `gh issue view 3 --repo jeonghanlee/measComp --json state,labels,milestone,updatedAt`.

#### M3 - Analog Enum Initialization

Origin: 3bdd4f2 / M3
Identity History: none
GitHub Issue: [#4](https://github.com/jeonghanlee/measComp/issues/4)
Status: Complete

##### Summary

Analog records initialized offline can retain empty enum labels and wrong values after connection. At the baseline, the shipped analog template with an external TC32 fixture populated `ANALOG_IN_TYPE` as `TC deg.` with value `2` when starting online. Starting offline and connecting later left the record's `ZRST` empty and `ZRVL=0`, although the driver returned the correct enum. Other analog models were not exercised. `readEnum()` returns `asynDisconnected` before `pBoardEnums_` exists; later scalar callbacks do not publish the enum changes required by asyn device support.

##### Scope

Publish valid model-specific dynamic enums to records after successful initialization, including direct-IP offline startup. Initialize the shipped analog input, voltage input and analog output mbbo templates so record selection converts through the enum values after recovery. Cover the shipped `measCompApp/Db/measCompAnalogIn.template` and a supported analog model through an external protocol fixture.

Out of scope: treating the TC32 floating-point temperature template as an analog enum consumer, changing enum definitions, and general qualification of every supported device model.

##### Completion Criteria

- Offline-start records receive their applicable enum labels and values when device initialization succeeds.
- Offline-then-online and online-start records expose the same model-specific enums.
- Each applicable enum selection reaches the driver as its model-specific numeric value after offline startup and reconnect.
- Coverage includes the shipped analog template and a supported analog model, without assuming that TC32 temperature records use this template.
- All local checks pass with durable evidence.
- The linked issue is observed closed, or Closure Evidence records a dated exception limited to issue closure.

##### Dependencies And Decisions

- None. A supported analog-model protocol fixture is part of this deliverable, not an assumed external approval or hardware prerequisite.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-11-05; include template initialization and actual selection-write verification in M3 (option 1).
Implementation Authorization: 2026-11-05; implement and verify the accepted M3 scope including SDEF initialization. Commit, push and issue changes remain separate operations.
Superseded Plan Artifacts: none

1. Enumerate the model-specific enum parameters and record addresses populated by successful device initialization.
2. Share enum selection with `readEnum()` and publish callbacks for every driver address after successful connection and IOC initialization. Keep the enum definitions unchanged; defer publication while `interruptAccept` is false.
3. Extend the external protocol fixtures and IOC test configuration for E-1608. Load the shipped analog input, voltage input and analog output templates and compare record fields with public driver enums and independently specified model values.
4. Give each affected mbbo a nonempty initial state label so Base initializes SDEF before connection. Verify every supported selection through real record processing, then compare RVAL, SDEF, completion/alarm state and public asynInt32 readback. Repeat across both startup orders and reconnects. An otherwise fixed build using the original templates must fail this check.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Repeat online startup and offline-then-online startup with the shipped analog template and TC32 metadata reproduction. | Common integration environment; TC32 fixture | Both runs expose `TC deg.` with enum value `2` in the driver and record fields. |
| T2 | Integration | Run both startup orders for a supported analog model and inspect each applicable dynamic enum through the shipped template. | Common integration environment; supported analog-model protocol fixture | Record strings, numeric values and severities match the driver for the selected model in both startup orders. |
| T3 | Regression | Repeat disconnect and reconnect, then run the normal TC32 temperature suite. | Common integration environment | Enum values remain valid across recovery; the separate temperature path retains its existing behavior. |
| T4 | Integration | Write each supported index through the actual mbbo VAL field, await asynchronous completion, and inspect RVAL, SDEF, severity and public driver readback. Test all loaded addresses and startup cases, including after each reconnect. | Common integration environment; TC32 metadata and E-1608 fixtures | SDEF is 1 and each index maps to its specified numeric value. Original templates with the fixed driver fail after offline startup. |

Execution contract: use the real driver, asyn 4.45.0, EPICS Base 7.0.10 and patched ULDAQ 1.2.2, with only the UDP/TCP device boundary simulated. Retain build inputs, commands, complete IOC output, assertion JSON, protocol requests, faults and native statuses under `work/m3-enums/`. Perl syntax and CLI must remain compatible with Perl 5.26.3 on the prepared Rocky 8 image; integration runs on Debian 13 with Perl 5.40.1.

- Volume: each fresh IOC serves bounded enum snapshots (all 16 record states), with no record truncation or sampling. This is functional verification, not a sustained-load or retention claim.
- Expected values: TC32 type is `TC deg.` / `2`; E-1608 input ranges are `+= 10V`, `+= 5V`, `+= 2V`, `+= 1V` / `1, 0, 14, 4`, output range is `+= 10V` / `1`, and input type is `Volts` / `1`. All enum severities are zero. Check address zero and nonzero addresses, including the final supported input channel.
- Time: use monotonic 12-second recovery deadlines and UTC run bounds. Each case has its own IOC and device lifetime; no cross-lifetime counter deltas.
- Faults: offline startup must be observed disconnected before enabling device responses. For recovery, inject EOF on an actual digital-input request, observe disconnection, then restore responses. Fixture traffic must prove exposure.
- Measurement: compare complete enum strings, values and state severities with the model specification and public `readEnum()` result. Write every supported selection through `dbPutField()` and check asynchronous completion, record raw value and public asynInt32 readback. Acquisition conversion coefficients belong to M4, not this check.
- Source identity: retain all compiled sources, test scripts/modules, loaded templates, generated database and linked library identities. A baseline build uses the real pre-fix driver with the same test bytes; each offline baseline must fail at a record enum assertion while online controls pass.
- Coverage: TC32 and E-1608, online and offline startup, E-1608 connection after record initialization but before interrupt acceptance, two subsequent reconnects, normal finish, missing-template failure and TERM cleanup. Also repeat the existing TC32 and digital regression cases. Verify the test's own cleanup without an outer cleanup guard and with a live-process/socket positive control. Portable evidence transfer, offline replay and two-stage terminal persistence are not part of this runner's contract.

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-05T22:03:51Z to 22:04:07Z | Debian 13; real IOC, Base 7.0.10, asyn 4.45.0, patched ULDAQ 1.2.2; TC32 fixture | Passed: 55 online and 56 offline assertions, including metadata, actual selections and two reconnects per case. The baseline driver passes online and fails offline at the record range enum assertion while its public driver enum assertion passes. | `work/m3-enums/selection-fixed/enum-tc32-*.log.json`; `work/m3-enums/negative-v2/baseline/build/` |
| T2 | 2026-11-05T22:03:51Z to 22:04:07Z | Same libraries; E-1608 fixture; shipped analog input, voltage input and analog output templates | Passed: 175 online, 176 offline and 178 initialization-overlap assertions. The baseline driver passes online; offline and overlap fail at the record range enum assertion. | `work/m3-enums/selection-fixed/enum-e1608-*.log.json`; `work/m3-enums/negative-v2/baseline/build/` |
| T3 | 2026-11-05T22:03:51Z to 22:05:46Z | Same libraries; independent IOC/fixture per case | Passed: all five enum cases preserve metadata and selection conversion through two observed EOF/disconnect/reconnect cycles each. Existing reconnect 38 and digital word/control/policy/bits 11/12/17/15 assertions pass, with normal IOC exits and no unsupported fixture commands. | `work/m3-enums/selection-fixed/`; per-case output, status, UTC bounds and source hashes |
| T4 | 2026-11-05T22:03:51Z to 22:04:07Z | Same libraries and shipped templates; TC32 metadata and E-1608 fixtures | Passed: every supported index on every loaded enum record reaches the driver as its expected numeric value, with SDEF=1, PACT=0 and no record alarm. Original templates with the fixed driver pass online but fail offline at the first selection check. | `work/m3-enums/selection-fixed/`; `work/m3-enums/negative-v2/template/build/` |

The ten final cases passed 733 assertions, including 640 in the five enum cases. T4 is included in those counts, not added again. The fixed build's 17 recorded input hashes and the retained source/template/binary checksums were rechecked unchanged after execution. Driver SHA-256: `cfdd7bf9fa168a9af7b43f2775141b80af229b818008bc6bc3ddf4012321b32d`; runner: `f54c6f1fdce29c5a5c99f733781be5da8d8d8d25a07c0f35a9c888d25d4041ea`; IOC source: `6799683a33e6c691952be06795c1e5ef16b7bf523933754c49449cdcacbb2520`. Build commands, input hashes and runtime library resolution are retained in `work/m3-enums/selection-fixed/`, `selection-proof.sha256` and `selection-libraries.txt`. The baseline uses the real driver from `5ee7103001a907d03f7354805a911b064e2749db` with the final test bytes.

Final negative controls returned status 1 at their intended assertions: address-zero-only publication at `startup TEST:A7Range record enums`, publication before interrupt acceptance at `startup TEST:A0Range record enums`, and original templates at `startup TEST:A0Range selection 0 maps to 1` for E-1608 and `selection 0 maps to 0` for TC32 (SDEF remains zero). See `work/m3-enums/negative-v2/`. A separate scratch runner that skipped successful checks failed at `startup enum target coverage`; its evidence and the predeclared mutation table are under `work/m3-enums/`. The earlier `baseline-init/` and `fixed/` runs omit successful enum assertions because of that runner defect; they are excluded from acceptance evidence.

Final Perl 5.26.3 syntax, POD, module loading and CLI checks passed in the prepared Rocky 8 image `sha256:507b995d50e4fee989c55b3fcbbfd7da3d9dc57a469ec771739cd6f399f967c9`; see `work/m3-enums/selection-rocky8.txt`. Missing-template and TERM runs returned runner statuses 1 and 143 with IOC statuses 6 and -15. Live child and listening-socket positive controls were observed before each failure; neither remained afterward, without a cleanup guard. See `work/m3-enums/selection-lifecycle.txt` and the `selection-fixed/lifecycle-*` evidence.

SDEF premise: the diagnostic at 2026-11-05T21:08:29Z to 21:08:40Z observed selection `2` produce `RVAL=14` online and `RVAL=2` offline with the original templates. asyn 4.45 copies enum fields without recomputing SDEF. The accepted template initialization resolves that record-selection defect, as verified by T4; it does not address M4's ADC conversion slope. Diagnostic evidence and primary sources remain under `work/m3-enums/selection-probe/` and `work/m3-enums/reference/`.

Documentation execution: from 2026-11-05T22:13:40Z to 22:14:50Z, the namespace setup and all five enum commands extracted from `tests/README.md` ran sequentially in one fresh namespace against the same fixed build. All 640 assertions passed, including 204 actual selections and two observed faults per case; all five IOCs and the command sequence exited 0. This repeats the enum verification and is not added to the 733-assertion acceptance total. Retained evidence: `work/m3-enums/readme-enums.*` and `selection-fixed/{t-online,t-offline,e-online,e-offline,e-init}.log*`. The README, extracted commands and source/template/binary checksums were unchanged after execution.

##### Closure Evidence

- Local review accepted on 2026-11-05 after first-person, third-person and second-person self-review: three direct passes in the available records, none delegated. The third-person pass checked the complete M3 change against its accepted plan, primary record/callback sources, retained negative controls and a fresh execution of the documented commands. The second-person pass checked the changed test guide, reconnection documentation and M3 detail against actual outputs. No unresolved findings remain; termination condition: no finding above the severity floor.
- Enum publication, initial template states and selection-write regression are implemented and verified in d839e5ecfcef9a708fb72a24663c076a911573a9. The commit contains the reviewed eleven-file selection. No required check is waived.
- Remote landing observed at 2026-11-05T22:21:59Z: after fetching origin, local HEAD and origin/site both resolved to d839e5ecfcef9a708fb72a24663c076a911573a9. Their full-tree comparison produced no differences, their ahead/behind counts were zero, and the working tree was clean. The GitHub branch API confirmed the same site commit at 2026-11-05T23:49:22Z. Recheck with `git -C /data/gitsrc/measComp fetch origin`, `git -C /data/gitsrc/measComp rev-parse HEAD origin/site` and `git -C /data/gitsrc/measComp diff HEAD origin/site`.
- Issue #4 was closed as completed at 2026-11-05T23:57:15Z, observed at 2026-11-05T23:57:38Z. Its body matches the prepared implementation and verification record, with all five acceptance criteria checked. The completion comment matches the prepared outcome and references d839e5ecfcef9a708fb72a24663c076a911573a9. Required verification, repository landing and linked-issue closure are complete; no check or external condition is waived.

##### GitHub Projection

Title: Refresh analog record enums after offline startup
Labels: bug
GitHub Milestone: Connection recovery and device selection
Observed State: closed (completed)
Observed Labels: bug
Observed Milestone: Connection recovery and device selection (milestone 1)
Last Compared: 2026-11-05T23:57:38Z; remote updated at 2026-11-05T23:57:15Z

Recheck metadata with `gh issue view 4 --repo jeonghanlee/measComp --json state,labels,milestone,updatedAt`.

#### M4 - Analog Conversion Initialization

Origin: 3bdd4f2 / M4
Identity History: none
GitHub Issue: [#5](https://github.com/jeonghanlee/measComp/issues/5)
Status: Complete

##### Summary

An analog record created offline can retain its default conversion slope after the driver obtains valid ADC bounds. At the baseline, the shipped analog template with a TC32 fixture and `EGUF=1`, `EGUL=0` reported bounds `0..16777215`. Online startup set `ESLO=5.9604648328104516e-08`; offline startup followed by connection retained `ESLO=1`. This proves a metadata defect, not voltage acquisition on another model. `MultiFunction::getBounds()` returns `asynDisconnected` before initialization, while `asynInt32Average` initializes the record's stored bounds and conversion coefficients at record initialization.

##### Scope

Initialize raw analog conversion from confirmed model-specific ADC bounds after offline startup and verify engineering-unit values through `measCompApp/Db/measCompAnalogIn.template`. Direct IP configurations are included.

Out of scope: replacing the asyn library, inventing universal ADC bounds, changing engineering-unit conventions, and applying raw ADC conversion to the floating-point TC32 temperature path.

##### Completion Criteria

- After offline startup and connection, conversion coefficients match those obtained by starting online with the same engineering limits and ADC resolution.
- A supported analog device or external protocol fixture verifies engineering-unit values through the real shipped record template.
- Changing engineering limits continues to use valid device bounds.
- The normal TC32 temperature path remains unaffected.
- All local checks pass with durable evidence.
- The linked issue is observed closed, or Closure Evidence records a dated exception limited to issue closure.

##### Dependencies And Decisions

- No execution dependency. M3 and M4 share an analog template and fixture support; metadata-only TC32 observations cannot satisfy the analog-value check.
- Decision Date: 2026-11-06. Maintain automatic ADC bounds recovery in this repository's device support. Delegate averaging through the public asyn DSET, preserve its private state, and maintain confirmed bounds separately. Per-model DB bit-count configuration was not selected.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-11-06; repo-owned automatic bounds recovery selected and confirmed after two independent plan reviews.
Implementation Authorization: 2026-11-06; implement and verify the selected option 1 with the parent as facilitator and implementer.
Superseded Plan Artifacts: none

1. Add `devMeasComp.cpp` with `measCompInt32Average`; resolve `asynAiInt32Average` through `registryDeviceSupportFind()` and delegate initialization, averaging reads and I/O interrupt registration through the public `aidset`. Preserve asyn's `dpvt` ownership and callback state.
2. Obtain bounds through a separate `asynInt32SyncIO` connection. Retry at record processing while unconfirmed; accept only successful `high > low` results. Calculate LINEAR `ESLO`/`EOFF` before converting a valid raw sample. Preserve INVALID/UDF on missing bounds or missing samples; never acquire a record lock from a driver callback.
3. Retain confirmed bounds for the configured device lifetime and recalculate when engineering limits change. Preserve manual SLOPE coefficients and leave the floating-point temperature and voltage paths unchanged.
4. Use one shipped `devMeasComp.dbd` include in production and the test builder, update the AnalogIn template, and hash the new build inputs. Extend the external E1608 raw response and actual IOC observations for periodic, I/O Intr and Passive records.
5. Verify real raw-to-engineering values, two-sample averaging, changed limits, no-sample invalidity and TCP recovery. Run the same final test code against the original device support and template: online controls must pass and offline conversion assertions must fail for the intended defect. Retain the temperature and enum regressions.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Run both TC32 bounds startup cases with `EGUF=1`, `EGUL=0`, then change limits. Repeat with the original template and identical harness. | Common integration environment; TC32 metadata fixture | Both fixed startup orders produce the 24-bit slope without validating a missing sample; original online passes and offline fails the coefficient assertion. |
| T2 | Integration | Run both E-1608 bounds startup cases, apply input settings through the shipped records, and supply raw 32768, 0 and 65535 through Ethernet responses. Repeat with the original template and identical harness. | Common integration environment; E-1608 fixture | Periodic and I/O Intr values use 16-bit bounds; original online passes and offline fails the raw-32768 engineering-value assertion after receiving the sample. |
| T3 | Integration | Change `EGUF` and `EGUL`, check two-sample averaging and manual SLOPE, repeat values after TCP EOF/reconnect, and process Passive input without new samples. | Common integration environment; E-1608 fixture | Confirmed bounds remain correct, averaging and SLOPE remain intact, and missing samples preserve value with UDF and INVALID. |
| T4 | Regression | Run complete temperature reconnect and all five enum cases; check Perl syntax, POD, modules and CLI on Debian 13 and Rocky 8. | Common integration environment; Perl 5.40.1 and 5.26.3 | All existing assertions pass with normal IOC exit, and both interpreters accept the test tools. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-06T02:22:14Z | Debian 13; Base 7.0.10, asyn 4.45, patched ULDAQ 1.2.2 | Pass | `bounds-tc32-online`: 22 checks; offline: 25. Both confirm `0..16777215`, initial `ESLO=5.9604648328104516e-08`, changed-limit coefficients and invalid missing samples. Original online passes 22; offline fails `startup A0 conversion coefficients` with `ESLO=1`. |
| T2 | 2026-11-06T02:22:17Z | Same integration environment; E-1608 fixture | Pass | `bounds-e1608-online`: 106 checks; offline: 109, including T3. Both process raw 32768, 0 and 65535 with `0..65535` bounds and valid values. Original online passes 106; offline receives raw 32768 but fails `startup A0 raw 32768 engineering value`: `ESLO=1`, `VAL=32758` for limits -10..10. |
| T3 | 2026-11-06T02:22:17Z | Same integration environment; E-1608 fixture | Pass | T2 cases include limits 2..7, an average raw value of 2000, manual `ESLO=2`, `EOFF=3`, `VAL=2003`, observed analog TCP EOF, restored values, and unchanged Passive value with UDF/INVALID when samples stop. |
| T4 | 2026-11-06T02:24:07Z | Same integration environment; Debian 13 Perl 5.40.1; Rocky 8 Perl 5.26.3 | Pass | Reconnect 38 checks; TC32 enum online/offline 55/56; E-1608 enum online/offline/init 175/176/178: 678 checks. All six IOC exits are zero with no fixture errors. Syntax, POD, 17 module loads and help/invalid-usage checks pass on both Perl versions. |

##### Closure Evidence

- Bounds recovery, the analog template change and the real-IOC regression are implemented and verified in 0bb9e829ddb1ffdbcea0e1033acf8eb2de67753e. The commit contains the reviewed fifteen-file selection and its `Refs #5` footer does not close the issue. No required check is waived. The ten positive IOC cases pass 940 assertions with no fixture errors and native exit zero. Original offline controls exit 1 at their intended assertion; cleanup then terminates those IOC processes, so their IOC exit is -15 rather than a successful shutdown.
- Review acceptance: 2026-11-06. Independent API and test implementation reviews and a subsequent maintainer reader review returned no findings. API checks expanded the production DBD, compiled its registrar, and exercised six real failed-initialization observations in two isolated IOCs. The test reviewer rebuilt independently, repeated the 940 positive assertions and original controls, and checked 611 actual analog frames and 54 successful phase values. This does not qualify a full production executable link or installation.
- Full third-person review: 2026-11-06. A subsequent complete review of the change against the accepted plan returned no findings and made no product change. It repeated the ten positive cases (940 checks, native IOC exit zero, 447 valid actual analog response frames) and matched all 19 build inputs to the current files. The original device support and template passed both online controls; its offline TC32 run failed `startup A0 conversion coefficients` and its offline E-1608 run failed `startup A0 raw 32768 engineering value`, each with IOC status -15 from cleanup. Additional real-IOC probes passed 55 checks (candidate online 18, candidate offline 19, original asyn online 18): `ESLO=2.25` and `EOFF=-7.5` configured before `iocInit` survived initialization, SCAN transitions among periodic, I/O Intr and Passive kept the SLOPE coefficients, and two-sample averaging was retained. Evidence: `work/m4-bounds/review-pass4/audit.txt` and its `probe-*` files.
- Evidence: `work/m4-bounds/build-04/` retains build commands, dependency/source hashes, generated DBD/registrar, IOC binary and each case's UTC interval, stdout, stderr, JSON, source hashes and native runner status. `perl-debian13-final.txt` and `perl-rocky8.txt` retain compatibility checks. These are local evidence paths; reproduce with the shipped builder and cases in `tests/README.md`.
- Source identity: baseline `8d210c413e3d994d50bea2332c644a922a495f28` plus the worktree later committed unchanged as 0bb9e829ddb1ffdbcea0e1033acf8eb2de67753e (all fifteen product hashes matched the reviewed inputs immediately before and after the commit); `devMeasComp.cpp` SHA-256 `299969e94503a42ce2938a7134bce1bd933530f9aa73f000d2a41605adfcd79b`; `test_reconnect.pl` SHA-256 `23dba4484d623747d83a6697c27e3da714c3b048bea2d2db7b92d40cb5de737c`. Original controls use the same final runner, fixture, binary and libraries with the exact HEAD AnalogIn template, whose SHA-256 is `b1e6947addb294e5a309c2eac55d45ff74176368edc17d4e735d8dbe9cc61674`.
- Remote landing observed at 2026-11-06T08:22:52Z: after fetching origin, local HEAD and origin/site both resolved to 0bb9e829ddb1ffdbcea0e1033acf8eb2de67753e. Their full-tree comparison produced no differences, their ahead/behind counts were zero, and the working tree was clean. The GitHub branch API confirmed the same site commit at 2026-11-06T08:22:53Z. Recheck with `git -C /data/gitsrc/measComp fetch origin`, `git -C /data/gitsrc/measComp rev-parse HEAD origin/site` and `git -C /data/gitsrc/measComp diff HEAD origin/site`.
- Issue #5 was closed as completed at 2026-11-06T08:21:31Z, observed at 2026-11-06T08:22:53Z. Its body matches the prepared implementation and verification record, with all five acceptance criteria checked. The completion comment references 0bb9e829ddb1ffdbcea0e1033acf8eb2de67753e. Required verification, repository landing and linked-issue closure are complete; no check or external condition is waived.

##### GitHub Projection

Title: Initialize analog conversion bounds after offline startup
Labels: bug
GitHub Milestone: Connection recovery and device selection
Observed State: closed (completed)
Observed Labels: bug
Observed Milestone: Connection recovery and device selection (milestone 1)
Last Compared: 2026-11-06T08:22:53Z; remote updated at 2026-11-06T08:21:31Z

Recheck metadata with `gh issue view 5 --repo jeonghanlee/measComp --json state,labels,milestone,updatedAt`.

#### M5 - MAC Device Rediscovery

Origin: 3bdd4f2 / M5
Identity History: none
GitHub Issue: [#6](https://github.com/jeonghanlee/measComp/issues/6)
Status: Complete

##### Summary

A MAC-selected device absent from the initial inventory is not rediscovered when it becomes available. At the baseline, an online-start broadcast control connected, but offline startup produced only the initial discovery request and remained disconnected with INVALID input severity through the 12-second recovery window. `measCompDiscoverDevices()` in `measCompApp/src/measCompDiscover.cpp` marks even an empty inventory initialized and returns that cache on later calls; the MAC branch of `measCompCreateDevice()` searches only the cache. Direct-IP selection follows a separate lookup and is outside this reproduced failure condition.

##### Scope

Allow bounded rediscovery of an initially absent MAC-selected device while preserving established handles, inventory identity and other configured ports.

Out of scope: replacing explicit IP selection, changing MAC syntax, and continuous unbounded network discovery.

##### Completion Criteria

- A MAC-selected device absent at startup can be discovered and connected after becoming available.
- Rediscovery is bounded by the reconnection policy and does not create duplicate inventory entries.
- Existing device handles and other configured ports remain valid during an inventory refresh.
- Regression coverage includes broadcast discovery, an online-start positive control, and offline-start recovery.
- All local checks pass with durable evidence.
- The linked issue is observed closed, or Closure Evidence records a dated exception limited to issue closure.

##### Dependencies And Decisions

- None. Shared inventory code with M6 requires compatible changes, not an invented prerequisite order.
- Decision Date: 2026-11-06. Refresh runs only inside the MAC branch of `measCompCreateDevice()` when the requested MAC is absent from the inventory. A process-wide minimum interval of 4 seconds between discovery attempts bounds it. The interval is shorter than the driver's five-second reconnect delay by decision of 2026-11-06, revised at the owner's direction after the implementation review: a retry starts before it waits for the vendor-call lock, so with an equal interval the refresh was skipped in three of four two-port runs and the second device connected after about 9.3 seconds instead of about 4.4 seconds; with four seconds all four runs connected after about 4.4 seconds. Retries stay driven by each port's existing reconnect gate, auto-connect and enable policy; no new thread or timer is added.
- Decision Date: 2026-11-06. Refresh merges by appending unknown unique IDs only and never repeats the IP-copy step on known entries. In ULDAQ 1.2.2, `ulCreateDaqDevice()` returns the existing device object for a known descriptor and `ulReleaseDaqDevice()` deletes it, so rerunning the current inventory loop would delete another port's live device.
- Decision Date: 2026-11-06. The Windows branch follows the same structure and is not verified, consistent with this milestone's Windows exclusion.
- Behavioral constraints recovered on 2026-11-06 from ULDAQ 1.2.2 `NetDiscovery.cpp` and the driver: a broadcast query waits 250 ms per non-loopback IPv4 interface while the inventory lock and the driver's global vendor-call lock are held; a broadcast query rebuilds ULDAQ's automatic discovery list from responding devices only, and established devices reconnect from their last discovery information. Refresh therefore queries Ethernet devices only and stays throttled.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-11-06; accepted by the owner after the discovery code, the ULDAQ 1.2.2 discovery and device-management sources and the existing test harness were read in full; no separate plan review was held. Amended 2026-11-06 at the owner's direction to apply every finding of the implementation review: plan item 6 adds the case `mac-known-absent`, T2 and T3 gain assertions, T5 is new, and the minimum refresh interval is 4 seconds with a 3.9-second spacing check and an 8-second limit for the second device in T3.
Implementation Authorization: 2026-11-06; implement and verify the accepted plan items 1 to 6, including the amendment above.
Superseded Plan Artifacts: none

1. In `measCompApp/src/measCompDiscover.cpp`, record the monotonic time of every discovery attempt, including the startup one. Add an internal refresh that returns at once when less than 4 seconds have passed since the last attempt; otherwise it queries Ethernet devices only, into a temporary array, through `ulGetDaqDeviceInventory(ETHERNET_IFC, ...)`. Verified by the T1 spacing and T2 no-refresh assertions.
2. Append only descriptors whose unique ID is absent from the inventory, up to the inventory limit, and read the IP address only for those new entries. Existing entries, their indices and vendor device objects are never touched. Verified by T3 connection continuity and distinct inventory entries.
3. In the MAC branch of `measCompCreateDevice()`, search the inventory; when the MAC is absent, refresh once and search again. The direct-IP branch and the startup discovery behavior are unchanged. Verified by T1 and T4.
4. Document MAC rediscovery in `docs/reconnection.md`: the trigger, the 4-second bound, the Ethernet-only scope, the brief wait other vendor calls incur during a broadcast, and unchanged IP selection.
5. Extend `tests/TC32.pm`: an opt-in broadcast listener that replies from the address-bound socket, an optional MAC, and timestamped discovery-request evidence. Broadcast replies stay off by default so existing direct-IP cases keep their path. Verified by T4.
6. Extend `tests/reconnect_ioc.cpp` and `tests/test_reconnect.pl`: a device identifier argument, an optional second port, per-port state and an inventory listing command. Add cases `mac-tc32-offline`, `mac-tc32-online`, `mac-two-ports` and `mac-known-absent`, with their commands and negative controls in `tests/README.md`. The two-port cases end the IOC directly and check only that it stops on request; the reason is recorded under Verification Results. Verified by T1 to T3 and T5 on the fixed and original drivers.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Start the IOC with the TC32 MAC as the device identifier while the fixture is absent. Record every received discovery request with its monotonic time, then enable the fixture. Repeat with the original driver and identical harness. | Common integration environment; isolated network namespace; TC32 fixture with broadcast replies enabled | Fixed driver: the port is disconnected with INVALID input while the device is absent, consecutive discovery requests are at least 3.9 seconds apart, and the port connects with a valid 22.5 temperature within 12 seconds of enabling the fixture. Original driver: sends only the startup discovery request and fails the connection deadline. |
| T2 | Regression | Start the same MAC-selected fixture online, check the connection, inject EOF and recover, then disable auto-connect with the fixture absent and observe 12 seconds, and repeat with the port disabled instead. | Same environment | Online startup connects with no discovery request after the first; EOF recovery reconnects from the existing descriptor; with auto-connect disabled or the port disabled no discovery request or connection occurs. The original driver passes the same assertions. |
| T3 | Integration | Run two ports: port A (MAC A, online at start, 22.5) and port B (MAC B, absent, 37.25). When A is healthy, enable B. Record connection counts, request streams and the inventory listing. | Same environment; two external fixtures at distinct addresses | B connects with 37.25 within 8 seconds; A keeps its single connection, keeps 22.5 and never goes 3 seconds without a request from the moment it is healthy; the inventory lists exactly two distinct unique IDs; neither fixture reports unsupported requests. |
| T4 | Regression | Run the shipped reconnect, digital, enum and bounds cases, and check Perl syntax, POD, module loading and help/invalid-usage on Debian 13 and Rocky 8. | Same environment; Perl 5.40.1 and 5.26.3 | All existing assertions pass unchanged with normal IOC exit, and both interpreters accept the test tools. |
| T5 | Integration | Run the two ports of T3, but take A offline with an EOF before enabling B. Enable B, list the inventory, then make A available again. | Same environment; two external fixtures | B connects with 37.25 while A is silent to the refresh broadcast; the inventory still lists both unique IDs; A reconnects from its inventory entry with 22.5 and without another discovery request; B keeps its single connection. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-06T16:39:10Z to 16:44:14Z (fixed, README blocks); 16:45:02Z to 16:59:48Z (original and variants) | Debian 13; real IOC, Base 7.0.10, asyn 4.45.0, patched ULDAQ 1.2.2; TC32 fixture selected by MAC with broadcast replies | Pass: `mac-tc32-offline` 6 assertions on the fixed driver. Three broadcast discovery requests while absent, 5.09 seconds apart; connected with a valid 22.5 within 3.75 seconds of enabling the fixture; six repeated runs passed with the same values. The original driver fails at the connection deadline with the port disconnected and INVALID. | `work/m5-mac/r8/build/`; `work/m5-mac/r8/v-baseline/` |
| T2 | Same intervals | Same environment | Pass: `mac-tc32-online` 14 assertions on both drivers. The startup discovery is the only request through an idle interval, an EOF reconnect, a 12-second window with auto-connect disabled, a 12-second window with the port disabled, and both recoveries; every reconnect uses the known inventory entry. | Same directories |
| T3 | Same intervals | Same environment; two TC32 fixtures with different MACs | Pass: `mac-two-ports` 8 assertions on the fixed driver. Both fixtures see three shared discovery requests during the absence, 5.55 and 5.39 seconds apart; the second device connects with 37.25 within 4.35 seconds (limit 8); the first port keeps its single connection and 22.5, and its longest pause between requests from the moment it was healthy is 0.70 seconds (limit 3); the inventory lists exactly the two MACs. Ten repeated runs passed, connecting after 4.26 to 4.50 seconds, with the closest two refreshes 4.87 seconds apart. The original driver fails at the second port's connection deadline. | Same directories |
| T4 | Same intervals | Same environment; Debian 13 Perl 5.40.1; Rocky 8 Perl 5.26.3 | Pass: the 14 existing cases pass 995 assertions with every IOC exit 0 (reconnect 38; digital 11, 12, 17, 15; enum 55, 56, 175, 176, 178; bounds 22, 25, 106, 109). Syntax, POD, module loading and help/invalid-usage checks pass on both Perl versions. | `work/m5-mac/r8/build/`; `perl-debian13.txt`; `perl-rocky8.txt` |
| T5 | Same intervals | Same environment; two TC32 fixtures with different MACs | Pass: `mac-known-absent` 7 assertions on the fixed driver. The second device connects after 6.48 seconds while the first is silent to the refresh broadcast; the inventory still lists both MACs; the first port reconnects from its entry with 22.5 and without another discovery request; the second keeps its single connection. Ten repeated runs passed after 6.48 to 6.73 seconds. The original driver fails at the second port's connection deadline. | Same directories |

Source identity of the final run: `measCompDiscover.cpp` SHA-256 `b08b9fb3e3ae6c3c63bfdca2fe97cef0ad9dd81729bc405ee104aee41c7b8fb7`; `test_reconnect.pl` `654460900c4ee3437e76735d04cc83f493efae12804d16e155cda1d659af47e8`; `TC32.pm` `4276c4b0c0714604040ce9fe842414ed6d84415aeed65ab86a9d72290d179728`; `E1608.pm` `621e8daa6c1cad55010dcaa381c3f4722913054c83585d60ab3c1d91f791f930`; `reconnect_ioc.cpp` `e8d863c8ccc15091688e04d18a1de0e5b18596578121aea8f352a57843ba9870`; patched ULDAQ library `6ff4e93258081a8936416698a798ffdd5536255deb8a2d681344fc4bc86439e4`. The 19 build input hashes were rechecked unchanged after execution. The original driver is the committed `1a06b5d` discovery source built with the same final test bytes.

Negative controls on scratch copies of the final tree failed at the intended assertion: `no-mac-refresh` at the connection deadline in `mac-tc32-offline`; `refresh-releases-known` at `mac first port keeps its connection` in `mac-two-ports` and at the first port's connection deadline in `mac-known-absent`; `refresh-rereads-known` and `refresh-no-dedupe` at `mac first port keeps its connection` in `mac-two-ports`, which shows the vendor library deleting a connected port's device object on a repeated IP read; `refresh-drops-known` at `mac inventory keeps the absent known device` in `mac-known-absent`; `refresh-no-throttle` (interval zero) at `mac rediscovery requests while absent` in `mac-tc32-offline` and at `mac absent port shares bounded discovery` in `mac-two-ports`; `refresh-stalls-ports` at `mac first port continues polling` in `mac-two-ports`. `refresh-interval-equals-retry` (five seconds) failed `mac second device connects with its own value` in five of six runs; the sixth run met the retry phase that avoids a skipped refresh. Evidence is under `work/m5-mac/r8/`.

Limit of the two-port cases: they end the IOC with `_exit` and check only that it stops on request. With two ports the driver's exit handlers can destroy a port object while its poller thread still runs; in 15 runs of a scratch scenario with both devices present from the start, the original driver and the fixed driver each aborted once on the normal exit. This race is not part of this work.

Phase check of the shared refresh: with both devices absent and the second port started 0, 2.5 and 4.5 seconds after the first, the fixture saw 3, 3 and 4 broadcast discovery requests. The requests after the startup one were 5.07 to 5.09 seconds apart, except the first refresh at 4.77 seconds when the second port started 4.5 seconds late. That is one refresh per reconnect delay, not one per port. These runs used a scratch variant of the test IOC that delays the second port and a scratch test that waits eleven seconds; they are not part of the shipped cases. Evidence: `work/m5-mac/r9/offset/` and `work/m5-mac/r8/scratch-absent/`.

Unverified consumer: `drvUSBCTR.cpp`, the other caller of `measCompCreateDevice()`, could not be compiled in this environment because the header `drvMca.h` of another module is missing. The declaration and signature of the function are unchanged, and the refresh applies only to identifiers that are not USB serial numbers.

Sanitizer check: the four MAC cases pass on a test IOC built with AddressSanitizer and UBSan, with zero reports from either. Evidence: `work/m5-mac/r10/`.

##### Closure Evidence

- MAC rediscovery, the bounded inventory refresh and the real-IOC regression are implemented and verified in 470aabbf51bb2605c85a7c96550f85ff765c9c34. The commit contains the reviewed nine-file selection and its `Refs #6` footer does not close the issue. All required checks passed and none is waived.
- Review: a third-person review in the author's stance, not independent of the author's session, read the complete change and re-ran it by execution from README commands extracted verbatim, with variants the author had not written. It reported two minor findings, three informational findings and one observation outside its scope; the owner ordered all of them applied. The review also showed that the first fix of the polling check missed a four-second stall, which was corrected and re-checked. Applying the findings added the case `mac-known-absent` and further assertions. The later runs showed that a refresh interval equal to the retry delay skipped refreshes under vendor-lock contention, and the owner chose a 4-second interval. Five further passes in the author's stance followed, four second-person and one third-person with a sanitizer build, and the last pass of each person returned no finding above the floor.
- Evidence: `work/m5-mac/` retains the builds with command and input hashes, the UTC intervals, stdout, stderr, JSON and native runner status of every case, and the negative-control runs. These are local evidence paths; reproduce with the shipped builder and the cases in `tests/README.md`.
- Remote landing observed at 2026-11-06T19:16:40Z: after fetching origin, local HEAD and origin/site both resolved to 470aabbf51bb2605c85a7c96550f85ff765c9c34. Their full-tree comparison produced no differences, their ahead/behind counts were zero, and the working tree was clean. The GitHub branch API confirmed the same site commit at the same observation. Recheck with `git -C /data/gitsrc/measComp fetch origin`, `git -C /data/gitsrc/measComp rev-parse HEAD origin/site` and `git -C /data/gitsrc/measComp diff HEAD origin/site`.
- Issue #6 was closed as completed at 2026-11-06T19:15:25Z, observed at 2026-11-06T19:16:41Z. Its body matches the prepared implementation and verification record, with all five acceptance criteria checked. The completion comment references 470aabbf51bb2605c85a7c96550f85ff765c9c34. Required verification, repository landing and linked-issue closure are complete; no check or external condition is waived.

##### GitHub Projection

Title: Rediscover MAC-addressed devices after offline startup
Labels: bug
GitHub Milestone: Connection recovery and device selection
Observed State: closed (completed)
Observed Labels: bug
Observed Milestone: Connection recovery and device selection (milestone 1)
Last Compared: 2026-11-06T19:16:41Z; remote updated at 2026-11-06T19:15:25Z

Recheck metadata with `gh issue view 6 --repo jeonghanlee/measComp --json state,labels,milestone,updatedAt`.

#### M6 - Discovery Endpoint Identity

Origin: 3bdd4f2 / M6
Identity History: none
GitHub Issue: [#7](https://github.com/jeonghanlee/measComp/issues/7)
Status: Not started

##### Summary

Directly discovered devices at the same IP but different discovery ports can resolve to the same cached descriptor. At the baseline, devices with distinct MAC addresses and temperatures `22.5` and `37.25` produced `22.5` with `NO_ALARM` on the second asyn port; the second endpoint received no connection requests. The parent of b2c1312 returned `37.25` and connected to both devices under the same dependencies and external fixtures. Distinct-IP and single-device alternate-port controls passed. In `measCompApp/src/measCompDiscover.cpp`, b2c1312 stores the resolved host in `descriptor.reserved`, while cache lookup ignores `portNum`.

##### Scope

Include the resolved IP address and discovery port in direct-discovery cache identity, keeping distinct endpoints and their established connections independent.

Out of scope: changing the public device identifier syntax, treating discovery ports as arbitrary TCP service ports, and claiming that distinct-IP configurations exhibit this reproduced failure.

##### Completion Criteria

- Cache identity distinguishes the resolved IP address and discovery port.
- Two distinct devices at one IP and different discovery ports connect independently and return their own values.
- Configuring the second device does not reconnect or replace the first device's connection.
- Distinct-IP, explicit default-port, hostname and MAC selection continue to work.
- A regression test fails on the current code and verifies actual requests reaching both external endpoints.
- All local checks pass with durable evidence.
- The linked issue is observed closed, or Closure Evidence records a dated exception limited to issue closure.

##### Dependencies And Decisions

- None. M5 and M6 share discovery code but solve different conditions and retain separate acceptance checks.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Store and compare a normalized direct-discovery endpoint containing the resolved IP address and discovery port instead of matching the host alone.
2. Preserve vendor descriptor fields and MAC identity; handle broadcast-discovered descriptors and default-port equivalence explicitly.
3. Add two real asyn ports backed by distinct external devices at one IP, recording both endpoint traffic and the first device's connection continuity.
4. Add the selection control matrix for distinct IPs, default and alternate discovery ports, hostname resolution and MAC selection.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Configure two fixtures with different MACs and temperatures at one documentation-range IP and two discovery ports; read both real asyn ports. | Common integration environment; two external TC32 devices | Values remain `22.5` and `37.25` at their intended ports; both endpoints receive real requests. |
| T2 | Integration | Establish the first connection before configuring the second and observe endpoint connections throughout. | Common integration environment; same-IP fixtures | Configuring the second endpoint neither reconnects nor replaces the first connection. |
| T3 | Regression | Exercise distinct IPs, omitted versus explicit default discovery port, a single alternate port, hostname resolution and MAC selection. | Common integration environment; external fixtures and namespace-local name resolution | Each supported selector reaches its intended device and equivalent default-port selectors preserve identity. |
| T4 | Regression | Build the affected baseline and fixed tree with identical dependencies and run the same two-endpoint regression. | Common integration environment | Baseline fails the endpoint-selection assertion; fixed code passes it with actual requests to both endpoints and normal IOC exit. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | Common integration environment | Pending | None |
| T2 | Not run | Common integration environment | Pending | None |
| T3 | Not run | Common integration environment | Pending | None |
| T4 | Not run | Common integration environment | Pending | None |

##### Closure Evidence

- None. No fix or successful post-fix verification is recorded.

##### GitHub Projection

Title: Include discovery port in the device cache identity
Labels: bug
GitHub Milestone: Connection recovery and device selection
Observed State: open
Observed Labels: bug
Observed Milestone: Connection recovery and device selection (milestone 1)
Last Compared: 2026-11-05T18:05:51Z; remote updated at 2026-11-05T18:05:33Z

Recheck metadata with `gh issue view 7 --repo jeonghanlee/measComp --json state,labels,milestone,updatedAt`.

#### M7 - Identifier Case And Refresh Diagnostics

Origin: 3bdd4f2 / M7
Identity History: none
GitHub Issue: none
Status: Complete

##### Summary

Two observations of the review of M5 on 2026-11-06. A MAC address configured in lower case never connects, on the driver before M5 and after it, because the inventory lookup compares the identifier with the upper-case MAC the vendor library reports; after M5 such a port also triggers one broadcast refresh per retry for as long as it stays configured. A refresh whose vendor inventory query fails leaves no diagnostic, so a persistent failure to rediscover devices is invisible beyond the driver's connection errors.

##### Scope

Match MAC addresses and USB serial numbers without regard to case in the inventory lookup, and report a failed inventory refresh once when it starts failing and once when it succeeds again.

Out of scope: any other identifier syntax, the direct-IP lookup, and reporting every failed refresh.

##### Completion Criteria

- A port configured with a lower-case MAC containing hexadecimal letters connects and lists its upper-case MAC in the inventory.
- A refresh whose vendor query fails is reported exactly once per failure episode, and its recovery once.
- The existing MAC and regression cases pass unchanged.
- All local checks pass with durable evidence.

##### Dependencies And Decisions

- Decision Date: 2026-11-06. The owner directed both review observations to be applied and recorded as this work unit without a linked issue. The case-insensitive comparison uses `epicsStrCaseCmp` and applies to the unique-ID lookup only.
- No execution dependency on M6.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-11-06; accepted by the owner's direction to apply the review findings.
Implementation Authorization: 2026-11-06; implement and verify items 1 to 3.
Superseded Plan Artifacts: none

1. In `measCompApp/src/measCompDiscover.cpp`, compare unique IDs with `epicsStrCaseCmp` in the inventory lookup. Verified by T1.
2. In the same file, keep the vendor status of the last refresh and print one line when it changes to a failure and one line when it changes back. Verified by T2.
3. Configure the second port of `mac-two-ports` and `mac-known-absent` with a lower-case MAC containing hexadecimal letters; document both behaviors and the two baselines in `docs/reconnection.md` and `tests/README.md`. Verified by T1 and T3.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Run `mac-two-ports` and `mac-known-absent` with the second port configured as a lower-case MAC. Repeat on the M5 source `470aabb` with identical tests. | Common integration environment; two TC32 fixtures | Fixed driver: both cases pass and the inventory lists the upper-case MAC. M5 source: both cases fail at the second port's connection deadline. |
| T2 | Integration | Build a scratch copy whose refresh forces a vendor failure on its second and third calls, run `mac-tc32-offline` with a 26-second absence. | Common integration environment | Exactly one failure line and one recovery line in the IOC log; the case still passes. |
| T3 | Regression | Run the 18 shipped cases, the Perl checks on Debian 13 and Rocky 8, and the MAC cases on a sanitizer build. | Common integration environment; Perl 5.40.1 and 5.26.3 | All assertions pass unchanged with normal IOC exit; no sanitizer report. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-06T19:51:01Z to 19:56:04Z (fixed); M5-source control in the same run | Debian 13; real IOC, Base 7.0.10, asyn 4.45.0, patched ULDAQ 1.2.2; two TC32 fixtures | Pass: `mac-two-ports` 8 and `mac-known-absent` 7 assertions with the second port `02:00:00:00:ab:33`; the inventory lists `02:00:00:00:AB:33`. The M5 source passes the online and offline cases and fails both two-port cases at the second port's deadline. | `work/m5-mac/r14/build/`; `work/m5-mac/r14/m5/` |
| T2 | 2026-11-06, same session | Same environment; scratch copy with forced failures | Pass: six refreshes 5.06 to 5.10 seconds apart; the log holds one `inventory query failed, status=99` line and one `succeeded again` line; the case passes. | `work/m5-mac/r14/diag/` |
| T3 | 2026-11-06T19:51:01Z to 19:56:04Z | Same environment; Debian 13 Perl 5.40.1; Rocky 8 Perl 5.26.3 | Pass: 14 existing cases 995 assertions and 4 MAC cases 35 assertions, every IOC exit 0; Perl checks pass on both; the MAC cases pass on the AddressSanitizer and UBSan build with no report. The source before M5 still fails the three absent-device cases at their deadlines. | `work/m5-mac/r14/`; `perl-debian13.txt`; `perl-rocky8.txt`; `asan/`; `base/` |

Source identity of the final run: `measCompDiscover.cpp` SHA-256 prefix `55f3b409e0e7850b`; `test_reconnect.pl` prefix `82327ddfa0aa618a`; the 19 build input hashes were rechecked unchanged after execution.

##### Closure Evidence

- The case-insensitive lookup, the refresh diagnostic, the test change and the documentation are implemented and verified in 09f2a2e78b05616f9c403122e97bdb8ea0e50d47. The commit contains the reviewed five-file selection. No check is waived.
- Remote landing observed at 2026-11-06T20:51:26Z: after fetching origin, local HEAD and origin/site both resolved to 09f2a2e78b05616f9c403122e97bdb8ea0e50d47, their full-tree comparison produced no differences, their ahead/behind counts were zero, the working tree was clean, and the GitHub branch API returned the same commit. Recheck with `git -C /data/gitsrc/measComp fetch origin`, `git -C /data/gitsrc/measComp rev-parse HEAD origin/site` and `git -C /data/gitsrc/measComp diff HEAD origin/site`.
- No linked issue; required verification and repository landing are complete, and no external condition is waived.
- Review: two third-person passes in the author's stance on 2026-11-06, the second after the findings were applied; one minor finding on the README baseline description was applied.

##### GitHub Projection

Title: none
Labels: none
GitHub Milestone: none
Observed State: not projected

## Backlog

### Work

| ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- |

### Backlog Details

None. All six assigned issues are in the Milestone section.
