# Connection Recovery And Device Selection

Release line: site (unversioned)
Milestone index: 3bdd4f2
Canonical path: `docs/milestone-3bdd4f2.md`
Canonical branch or ref: site
Git upstream: origin/site
Remote tracker: [jeonghanlee/measComp milestone 1](https://github.com/jeonghanlee/measComp/milestone/1)
GitHub milestone: Connection recovery and device selection
Due date: none
Remote milestone observed at: 2026-11-05T19:00:53Z; state: open; one closed issue and five open issues
Recheck remote milestone with `gh api repos/jeonghanlee/measComp/milestones/1`.
Baseline commit: 3bdd4f24d820579f3f423c7be968baf2bb413950

Next session entry point: Prepare M2's verified and reviewed working-tree changes for commit, push and issue #3 reconciliation under the corresponding authorizations. M1 is complete; M3 through M6 await separate implementation.

## Scope

This document assigns issues #2 through #7 to six work units for the independently maintained `site` branch. It owns their scope, implementation plans, tests, verification results and closure evidence. GitHub retains the live issue metadata. M1 is complete. M2 is accepted and authorized for implementation; M3 through M6 remain draft plans.

The common integration environment is Linux with the real measComp driver, EPICS Base 7.0.10, asyn 4.45 and patched ULDAQ 1.2.2. Extend the shipped Perl/Bash tests and retain `tests/reconnect_ioc.cpp`; use external device protocol fixtures, without replacing internal driver, asyn or ULDAQ functions. Record the source commit, dependency identities, assertions, fixture requests and native IOC exit status for each executed check. Checks reproducing a defect must fail for the intended assertion on the affected baseline and pass on the fixed code; setup and build failures do not establish a regression. Compatibility checks and positive controls must pass on both the baseline and fixed code. When a check combines these purposes, record the defect assertion separately from its controls.

Existing failure observations below come from the linked issues at the baseline commit. They are not successful verification of a fix. M1 and M2 record observed post-fix verification; checks for M3 through M6 remain pending. M2 still requires repository landing and issue closure. The analog metadata findings are separate from the normal floating-point TC32 temperature path. MAC rediscovery and same-IP/different-discovery-port selection retain their specific applicability conditions.

**Out of scope:** ULDAQ vendor patch development, upstream submissions, release numbering, tags, deployment, output-command replay, and a general qualification of Windows, USB, EXP-32 or hardware power cycling. Changes to `docs/reconnection.md` and `tests/README.md` belong to the affected work unit when behavior or test invocation changes. Existing test limitations remain explicit.

## Milestone

### Work

| ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| M1 | TC write and readback consistency | Milestone | Complete | No | | Device and cache agree after a failed write and reconnect; [detail](#m1---tc-write-and-readback-consistency) |
| M2 | Digital output failure handling | Milestone | In progress | No | | Transport errors disconnect and invalidate inputs before the next poll; [detail](#m2---digital-output-failure-handling) |
| M3 | Analog enum initialization | Milestone | Not started | Yes | | Offline-start records obtain the same enums as online-start records; [detail](#m3---analog-enum-initialization) |
| M4 | Analog conversion initialization | Milestone | Not started | Yes | | Offline-start conversion matches online-start conversion and measured raw values; [detail](#m4---analog-conversion-initialization) |
| M5 | MAC device rediscovery | Milestone | Not started | Yes | | An initially absent MAC-selected device connects without disturbing existing ports; [detail](#m5---mac-device-rediscovery) |
| M6 | Discovery endpoint identity | Milestone | Not started | Yes | | Devices sharing an IP but using different discovery ports remain independent; [detail](#m6---discovery-endpoint-identity) |

The row order follows issue numbers and imposes no execution dependency. Current status: one Complete, one In progress and four Not started. `Ready` records dependency readiness only; the remaining draft plans still require acceptance and implementation authorization. No external prerequisite is currently established. If a required hardware or third-party dependency is selected later, add an external-gate row and record the affected work before changing its status.

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
Status: In progress

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

- The working-tree implementation and T1-T4 are verified. M2 remains In progress until its repository changes are committed and observed on `origin/site`, and issue #3 is observed closed. No external completion condition is waived.
- Review acceptance: 2026-11-05; four direct self-review passes (first-person, third-person, second-person, second-person recheck), no delegated review. The reader pass found a missing `TEMPLATE` definition after leaving the earlier namespace; the digital instructions now establish it explicitly. Commands extracted directly from the corrected README passed all 55 digital checks with normal IOC exits and shell exit 0; evidence is `work/m2-digital/readme-digital.stdout`, `readme-digital.stderr` and `fixed-final/{word,control,policy,bits}.log.json`. The third-person pass rechecked request order, connection identity and recorded response frames/checksums. No unresolved in-scope finding remains.

##### GitHub Projection

Title: Disconnect on digital output transport errors
Labels: bug
GitHub Milestone: Connection recovery and device selection
Observed State: open
Observed Labels: bug
Observed Milestone: Connection recovery and device selection (milestone 1)
Last Compared: 2026-11-05T18:05:51Z; remote updated at 2026-11-05T18:05:13Z

Recheck metadata with `gh issue view 3 --repo jeonghanlee/measComp --json state,labels,milestone,updatedAt`.

#### M3 - Analog Enum Initialization

Origin: 3bdd4f2 / M3
Identity History: none
GitHub Issue: [#4](https://github.com/jeonghanlee/measComp/issues/4)
Status: Not started

##### Summary

Analog records initialized offline can retain empty enum labels and wrong values after connection. At the baseline, the shipped analog template with an external TC32 fixture populated `ANALOG_IN_TYPE` as `TC deg.` with value `2` when starting online. Starting offline and connecting later left the record's `ZRST` empty and `ZRVL=0`, although the driver returned the correct enum. Other analog models were not exercised. `readEnum()` returns `asynDisconnected` before `pBoardEnums_` exists; later scalar callbacks do not publish the enum changes required by asyn device support.

##### Scope

Publish valid model-specific dynamic enums to records after successful initialization, including direct-IP offline startup. Cover the shipped `measCompApp/Db/measCompAnalogIn.template` and a supported analog model through an external protocol fixture.

Out of scope: treating the TC32 floating-point temperature template as an analog enum consumer, changing enum definitions, and general qualification of every supported device model.

##### Completion Criteria

- Offline-start records receive their applicable enum labels and values when device initialization succeeds.
- Offline-then-online and online-start records expose the same model-specific enums.
- Coverage includes the shipped analog template and a supported analog model, without assuming that TC32 temperature records use this template.
- All local checks pass with durable evidence.
- The linked issue is observed closed, or Closure Evidence records a dated exception limited to issue closure.

##### Dependencies And Decisions

- None. A supported analog-model protocol fixture is part of this deliverable, not an assumed external approval or hardware prerequisite.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Enumerate the model-specific enum parameters and record addresses populated by successful device initialization.
2. Publish asyn enum callbacks after the enum table becomes valid, using the same strings, values and severities as `readEnum()`.
3. Extend the external protocol fixtures and IOC test configuration to load the shipped analog template for a supported analog model; compare record fields with the public driver enums.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Repeat online startup and offline-then-online startup with the shipped analog template and TC32 metadata reproduction. | Common integration environment; TC32 fixture | Both runs expose `TC deg.` with enum value `2` in the driver and record fields. |
| T2 | Integration | Run both startup orders for a supported analog model and inspect each applicable dynamic enum through the shipped template. | Common integration environment; supported analog-model protocol fixture | Record strings, numeric values and severities match the driver for the selected model in both startup orders. |
| T3 | Regression | Repeat disconnect and reconnect, then run the normal TC32 temperature suite. | Common integration environment | Enum values remain valid across recovery; the separate temperature path retains its existing behavior. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | Common integration environment | Pending | None |
| T2 | Not run | Common integration environment | Pending | None |
| T3 | Not run | Common integration environment | Pending | None |

##### Closure Evidence

- None. No fix or successful post-fix verification is recorded.

##### GitHub Projection

Title: Refresh analog record enums after offline startup
Labels: bug
GitHub Milestone: Connection recovery and device selection
Observed State: open
Observed Labels: bug
Observed Milestone: Connection recovery and device selection (milestone 1)
Last Compared: 2026-11-05T18:05:51Z; remote updated at 2026-11-05T18:05:18Z

Recheck metadata with `gh issue view 4 --repo jeonghanlee/measComp --json state,labels,milestone,updatedAt`.

#### M4 - Analog Conversion Initialization

Origin: 3bdd4f2 / M4
Identity History: none
GitHub Issue: [#5](https://github.com/jeonghanlee/measComp/issues/5)
Status: Not started

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

- None. M3 and M4 share an analog template and may share fixture support, but neither fix is a prerequisite for the other. Metadata-only TC32 observations cannot satisfy the analog-value check.

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Confirm the supported record/device-support mechanism for updating conversion bounds after connection and record the concrete API in this plan before acceptance.
2. Add a measComp-owned initialization path that supplies confirmed model-specific bounds and recomputes conversion coefficients without marking uninitialized input data valid.
3. Retain those bounds when engineering limits change; keep the floating-point temperature records outside this path.
4. Add raw-value and engineering-value observations from a supported analog-model protocol fixture through the shipped record template.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Repeat the `EGUF=1`, `EGUL=0` metadata reproduction for online and offline startup, then query actual bounds and record conversion fields. | Common integration environment; TC32 metadata fixture | Both startup orders produce identical confirmed bounds and the expected slope for the reported ADC resolution. |
| T2 | Integration | Supply multiple documented raw ADC values, including endpoints and an interior value, through a supported analog protocol and process the real analog record. | Common integration environment; supported analog-model protocol fixture | Engineering-unit values follow the model's actual bounds and configured engineering limits. |
| T3 | Integration | Change `EGUF` and `EGUL` after connection, then repeat raw-value measurements and another reconnect. | Common integration environment; supported analog-model protocol fixture | Conversion recomputes from valid device bounds and remains correct after recovery. |
| T4 | Regression | Run the complete shipped temperature reconnect suite. | Common integration environment; TC32 fixture | Floating-point temperatures, alarms and recovery behavior remain correct; the IOC exits normally. |

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

Title: Initialize analog conversion bounds after offline startup
Labels: bug
GitHub Milestone: Connection recovery and device selection
Observed State: open
Observed Labels: bug
Observed Milestone: Connection recovery and device selection (milestone 1)
Last Compared: 2026-11-05T18:05:51Z; remote updated at 2026-11-05T18:05:23Z

Recheck metadata with `gh issue view 5 --repo jeonghanlee/measComp --json state,labels,milestone,updatedAt`.

#### M5 - MAC Device Rediscovery

Origin: 3bdd4f2 / M5
Identity History: none
GitHub Issue: [#6](https://github.com/jeonghanlee/measComp/issues/6)
Status: Not started

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

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Refresh discovery when a requested MAC is absent, subject to the existing reconnect interval and port policy.
2. Merge newly discovered descriptors under inventory synchronization without replacing established device handles or duplicating known identities.
3. Extend the external fixture to answer broadcast discovery after becoming available; add a second active port to detect inventory or handle disruption.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Start the IOC with a MAC-selected fixture offline, then enable broadcast discovery responses and record retries and connection state. | Common integration environment; isolated network namespace | The device connects within the defined recovery window; retries respect the existing reconnect interval. |
| T2 | Regression | Start the same MAC fixture online, then exercise EOF recovery and connection-policy controls. | Common integration environment | Online discovery succeeds and the established recovery behavior remains valid. |
| T3 | Integration | Keep one port active while another MAC-selected device appears; repeat discovery and inspect inventory and fixture traffic. | Common integration environment; two external devices | No duplicate inventory entries, invalid handles or disruption of the existing port occur. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | Common integration environment | Pending | None |
| T2 | Not run | Common integration environment | Pending | None |
| T3 | Not run | Common integration environment | Pending | None |

##### Closure Evidence

- None. No fix or successful post-fix verification is recorded.

##### GitHub Projection

Title: Rediscover MAC-addressed devices after offline startup
Labels: bug
GitHub Milestone: Connection recovery and device selection
Observed State: open
Observed Labels: bug
Observed Milestone: Connection recovery and device selection (milestone 1)
Last Compared: 2026-11-05T18:05:51Z; remote updated at 2026-11-05T18:05:28Z

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

## Backlog

### Work

| ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- |

### Backlog Details

None. All six assigned issues are in the Milestone section.
