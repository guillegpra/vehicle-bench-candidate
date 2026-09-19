# Test Strategy — Vehicle Bench Release 4.12.0

**Gateway 4.12.0 · Backend 1.8.3 · Body ECU 2.7.1 · 19 September 2026**

## 1. What we want to verify

The goal is to check that remote commands reach the vehicle, do what was requested, and leave the backend, gateway and Body ECU reporting the same state. We also check that invalid requests are rejected and that failures can be traced through the logs.

The suite has **50 Robot tests**, covering smoke checks and scenarios S01–S07 against [the bench requirements](REQUIREMENTS.md). Four Python helper tests and one offline Robot test check the test tooling separately.

This is a simulated bench. Physical hardware, production Android behavior, OTA security, load testing, cable-disconnect events and low-battery climate behavior are outside the current scope. Packet captures are available for investigation, but there is no automated comparison against reference traces.

## 2. How we test it

Commands travel through **REST → gateway → gRPC → Body ECU**, with vehicle state reported back to the backend. The main risks are commands being dropped or timing out, incorrect temperature conversion, and one function unexpectedly affecting another.

We use several views of the same operation:

| Interface | What we check |
| --- | --- |
| REST API | Command acceptance, response times, terminal status, vehicle telemetry, input validation and OpenAPI. |
| ADB | Gateway identity and service state, VHAL properties, logs and calibration values. |
| Direct gRPC | Actual Body ECU door and climate state through `GetBodyState`. Charging tests currently rely on backend and VHAL readings. |
| DLT and logcat | Request correlation, forwarding times, heartbeat behavior and gateway errors. |
| Docker Compose and PCAP | Stop/start the ECU for supervision testing; retain network traffic for manual diagnosis. |

An accepted API request does not prove that the vehicle performed the action. Where implemented, we compare backend results with gateway and direct ECU readings. Boundary values, repeated cycles and controlled ECU shutdowns exercise failure paths as well as normal use.

## 3. Coverage at a glance

The table groups all 50 tests by purpose. Each suite link contains the individual test cases; requirement ranges refer to the IDs in [REQUIREMENTS.md](REQUIREMENTS.md).

| Suite | Tests | Coverage and requirements |
| --- | ---: | --- |
| [Smoke](../starter/robot/tests/smoke.robot) | 3 | Backend/VIN check, gateway model and boot/service properties, and ADB TCP connectivity. **API-005; ADB-001.** |
| [S01 — Locking](../starter/robot/tests/s01_lock_unlock.robot) | 8 | Basic lock/unlock, synchronization across all three layers, 20 consecutive cycles, unchanged state after failure, and protection of idle/active climate and charging states. **LCK-001–004.** |
| [S02 — Climate](../starter/robot/tests/s02_climate.robot) | 7 | Basic start/stop, 0.5 °C precision, invalid and valid boundary temperatures, stop synchronization, and backend/ECU agreement. **CLI-001–004.** |
| [S03 — Charging](../starter/robot/tests/s03_charging.robot) | 4 | Initial state, charging start and SOC increase, stop and SOC stability, and completion at the target. **CHG-001, 002, 004.** |
| [S04 — API validation](../starter/robot/tests/s04_api_validation.robot) | 12 | Invalid temperature/SOC, missing and invalid API keys, three acceptance-contract tests covering all six command endpoints, terminal state and failure reasons, unknown IDs, status freshness and OpenAPI. **API-001–006; CLI-002; CHG-003.** |
| [S05 — ECU supervision](../starter/robot/tests/s05_ecu_supervision.robot) | 5 | Online status, slow-heartbeat WARN classification, warning rate, heartbeat period, and offline detection after stopping the ECU. **ECU-001.** |
| [S06 — Command delivery](../starter/robot/tests/s06_command_delivery.robot) | 5 | Exactly-once LOCK forwarding, forwarding delay, failed-command reporting, deadline calibration, and 10 nominal lock/unlock cycles without timeout. **ECU-002; NET-001.** |
| [S07 — Logging](../starter/robot/tests/s07_logging.robot) | 6 | Cross-node request correlation for lock, climate start and charging start; no new gateway errors during each function's normal flow. **LOG-001–002.** |

`REQ-ADB-002` is also exercised through the VHAL checks in S01–S03, although charging is not compared directly with the ECU. Four tests still lack requirement tags: basic climate start/stop, accepted temperature boundaries, and S04's temperature rejection test. `REQ-ADB-002` also needs an explicit tag.

## 4. Running the suite reliably

Use a dedicated Docker Compose bench and run tests sequentially: they share vehicle state, and S05 deliberately stops the ECU. Install [the dependencies](../starter/requirements.txt) in the same Python environment used to run Robot, including `grpcio` and `grpcio-tools`. Connection settings are in [bench_local.py](../starter/robot/variables/bench_local.py); local commands are in [SUBMISSION.md](SUBMISSION.md).

Before starting, confirm that the services are healthy, ADB is connected, vehicle telemetry is populated, and logs/results are accessible. S01–S03, S06 and S07 reset the bench before each test. S04 and S05 do not, and the reset helper does not currently assert success, so full order independence is not yet guaranteed. S05 uses a `FINALLY` block to restart the ECU after its outage check.

| Area | Main values and limits |
| --- | --- |
| Commands | Acceptance within 500 ms; terminal-state polling for 5 seconds at 250 ms intervals. The older completion helper allows 10 seconds. |
| State updates | Usually a 10-second window with 500 ms polling, allowing for the gateway's 5-second state refresh. |
| Locking | 20 cycles in S01 and 10 in S06; reported duration ≤1 second when available; configured deadline ≥800 ms. |
| Climate | 21.5 °C precision check; valid boundaries 16 and 28 °C; invalid values 15.5, 10, 28.5 and 35 °C. |
| Charging | Initial SOC 42%; targets 80%, 90% and 50%; invalid targets 49% and 101%. Check at least 1% SOC growth, allow 30 seconds to reach 50%, and sample SOC 4 seconds after stopping. |
| Heartbeat | 2-second period, ±0.25-second tolerance over an 8-second sample; WARN above 100 ms; warning rate ≤10%; offline polling up to 9 seconds. |

Keep the first failure's evidence before resetting or rerunning. Polling should wait for state updates, not hide intermittent failures. **Do not modify `env/` or its calibrations to make tests pass**; report those defects to the bench owner.

## 5. Where coverage still needs work

The suite catches useful defects, but a green result would not yet prove every requirement:

- **Timing:** several tests wait for command completion before starting another 10-second state check. Requirements measure from the HTTP response, so all checks need to share that original deadline.
- **Failure and state checks:** some tests only check failure behavior if a command happens to fail. Immediate backend reads can miss delayed actuation or subsystem changes. Charging needs direct ECU reads, and its 4-second stability sample can precede the next telemetry refresh.
- **Heartbeat evidence:** warning tests use accumulated logs. A state-poll failure can mark VHAL offline before three missed heartbeats, so the outage test must wait for fresh, ordered heartbeat evidence rather than immediately search for `missed=3`.
- **Breadth:** authentication tests cover only `/vehicle/lock`; exactly-once forwarding covers LOCK; log correlation covers three command types. Malformed payloads and exhaustive schema checks are not implemented.
- **Delivery diagnostics:** the unexecutable-command case depends on the current charging-stop defect. The timeout check can include old log entries and does not inspect HTTP/2 cancellation frames. Fresh evidence and controlled fault injection would make these tests stronger.

These are test improvements outside `env/`. Product defects remain failures even when their cause is already known.

## 6. Results and acceptance

The latest saved [live run](../results/output.xml), dated 19 September 2026, has **33 passed, 17 failed and no skipped tests**. Release acceptance is therefore not established.

Of those failures, 13 are consistent with identified bench defects, three are caused by missing `grpc` dependencies, and one reflects the heartbeat test checking for `missed=3` too early. The product issues include door timeouts, HVAC stopping on unlock, 21.5 °C becoming 21.0 °C, invalid temperatures being accepted, and dropped charging-stop commands. Details and supporting evidence are in [ROBOT_FAILURE_ANALYSIS.md](ROBOT_FAILURE_ANALYSIS.md); its original run totals predate this latest result.

The saved dry run passes 50/50, the offline Robot check passes, and four Python helper tests passed during the earlier repairs. Those results validate the test tooling, not the vehicle behavior. No new live run was performed for this document update.

For release approval, applicable tests must pass on the unchanged bench, requirement violations must be resolved, and the remaining coverage gaps must be addressed or explicitly accepted. For the assessment itself, a failing CI run with clear, reproducible defect evidence is a valid outcome. Record the requirement, request ID, expected/actual state and relevant logs using the [RCA template](../templates/RCA_TEMPLATE.md); include PCAP frames when inspected.

## 7. CI and retained evidence

The [GitHub Actions workflow](../.github/workflows/robot-tests.yml) runs on pushes, pull requests and manual dispatch using Ubuntu 24.04 and Python 3.12. It installs tools, runs helper/offline checks and a dry run, starts a fresh bench, waits for ADB and telemetry, then executes all 50 tests sequentially. Smoke tests are included in the full run rather than a separate CI stage.

The job limit is 20 minutes, with 10 minutes for live tests. Test failures fail the job. Diagnostics and uploads run even after failures, and the bench is stopped before uploading captures. Artifacts are kept for 14 days: Robot HTML/XML and xUnit reports, container logs/status, the ADB device list, DLT logs and live PCAPs. A successful GitHub run has not been confirmed by the local evidence reviewed here.

## 8. AI assistance

AI helped troubleshoot Robot tests, prepare shared keywords and the workflow, and edit documentation. This strategy was checked against the test suite, supporting code, requirements and saved results.
