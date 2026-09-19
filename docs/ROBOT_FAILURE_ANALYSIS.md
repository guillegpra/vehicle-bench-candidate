# Robot failure analysis — 19 September 2026

The supplied run has 50 tests: 27 passed and 23 failed. It mixes test-harness errors with actual bench defects. Fixing the harness will expose some failures that were previously hidden. The `env/` source and calibration files have not been modified, and no runtime calibration or configuration workaround was applied.

## Test fixes applied

| Original error | Cause and change |
| --- | --- |
| S01: `Should Be False` missing | Replaced with an exact comparison to Robot's `${False}`. |
| S01: `doors_locked` absent from dumpsys | `dumpsys vehicle` exposes `DOOR_LOCK`, not a separate Body ECU state. Body checks now call the ECU's read-only `GetBodyState` gRPC method directly; backend and VHAL checks remain separate. |
| S02 stop: `body_ecu.*climate_active` absent | Same incorrect data source. Read actual ECU climate state, decoding its set point at 0.5 °C per LSB. Stopping checks inactive state without requiring a particular retained set point. |
| S03: all four charging regex failures | Robot consumes a single backslash. Changed regex tokens to double backslashes in the resource file, preserving `\s`, `\(` and `\)` for the regex engine. |
| S05: online/offline regex failures | Same escaping correction. |
| S05: `Assert Heartbeat Sequence Timing` missing | Implemented sequence/timing validation with a documented 0.25 s tolerance. Observe a fresh 8-second log window; historical logs include a 456-second gap and cannot establish current nominal timing. |
| S06: `Get JSON Value As Integer` missing | Added JSON parsing with an integer type assertion; this now exposes the actual 600 ms calibration rather than a missing keyword. |
| S07: ambiguous `Get Gateway DLT Log` | Renamed the host-file reader to `Get Gateway DLT File`; before/after comparisons use the same source. Also imported `log_validation.py`, otherwise the next failure would be a missing `Assert No New Gateway Errors` keyword. |

The new `body_state.py` helper reads `env/proto/vehicle_ecu.proto` and generates Python bindings in a temporary directory, never in `env/`. It uses `BODY_ECU_ADDR` from the existing variables file and dependencies already declared in `starter/requirements.txt`.

## Bench defects: reported, not changed

| Defect and affected tests | Source evidence | Required owner-side correction (outside this task) |
| --- | --- | --- |
| Door commands time out: S01 twenty cycles and failed-command setup; S06 nominal cycles; possible intermittent failures in any door-dependent test | `env/ecu-gateway/tcu_cal.json:13` sets 600 ms, while `env/body-ecu/body_cal.json:4` allows 250–800 ms. | Set a deadline accommodating maximum actuation plus transport overhead. Increasing Robot's polling timeout cannot fix an already-cancelled gRPC call. |
| 21.5 °C becomes 21.0 °C: S02 half-degree and convergence tests | `env/ecu-gateway/tcu_cal.json:17` selects `floor_integer`; `gateway.py:119` implements `int(temp_c) * scale`. `env/backend/app/main.py:271` returns the requested set point while active, concealing the actual ECU value from API-only checks. | Preserve half-degree precision in encoding and make reported state accurately reflect vehicle telemetry. Keep the expected 21.5 °C assertions. |
| Invalid temperatures return 200: S02 negative range and S04 boundary tests | `env/backend/app/main.py:27` defaults legacy schema on; the model at line 49 lacks bounds; the route at line 224 selects it. | Use the bounded schema for the API contract. No compatibility flag or compose override was changed to bypass this defect. |
| Charging stop remains ACCEPTED: S06 unexecutable command; will also affect S03 stop and S07 charging flow once earlier harness failures are gone | `env/ecu-gateway/tcu_cal.json:11` maps `CHARGE_STOP`, but backend dispatches `CHARGING_STOP` (`env/backend/app/main.py:255`). `gateway.py:172` drops unmapped commands without reporting a terminal failure. | Correct the mapping and report FAILED with a reason for unsupported commands. Longer polling does not repair a dropped command. |

Correlated evidence in the existing logs:

- Request `0886fe30-da6a-49e4-a765-54d045ff418f`: gateway deadline 600 ms and `DEADLINE_EXCEEDED`; Body ECU selected 706 ms and finished at 708 ms (`traces/logs/tcu.dlt:23406`, `traces/logs/body_ecu.dlt:5994`).
- Request `c9b0cca3-4fe9-4c79-926d-537f65db7f6a`: ECU selected 654 ms; same 600 ms timeout (`traces/logs/body_ecu.dlt:6000`). This is a failure during the invariance test's baseline setup, not evidence that its final invariance assertion ran.
- Request `3b4807d8-6e3f-4deb-b4d0-7e479c934e14`: explicitly logged as `no handler for command, dropping`, command `CHARGING_STOP` (`traces/logs/tcu.dlt:24082`).

## Additional findings that can be masked by passing tests

- `env/body-ecu/server.py:102` shields actuation from cancellation. A command reported FAILED after a deadline can still change the latch later. A failure-preserves-state test needs a real transition, a confirmed failure, and observation after actuation/telemetry convergence. The current S01 test only logs a message and passes when its attempted failure actually completes; this is a coverage gap, not proof of invariance.
- `env/body-ecu/body_cal.json` enables `hvac_reset_on_door_unlock`; `server.py:125` explicitly stops active HVAC on unlock. This contradicts the subsystem-independence expectation. The current test can miss it because it accepts either terminal command status and samples cached backend state immediately. This source defect remains unchanged.
- S05's `missed=3` assertion searches historical logs and may match an earlier outage. Also, VHAL can mark offline after a failed state poll (`gateway.py:275`), independently of the heartbeat threshold. Its pass alone does not isolate the three-miss requirement.
- S06's final no-timeout check searches the whole gateway log, so a previous run's error can fail it. Scope that evidence to the tested request IDs or a fresh log window when expanding this test.

## Validation and rerun

Completed:

- Robot dry run: **50/50 passed**. This validates keyword resolution and structure, not live vehicle behavior.
- Four Python helper regression tests passed.
- One offline Robot regression passed: realistic VHAL charging/online assertions, plus rejection of wrong charging/offline expectations. The mock override produces a Robot warning about a future Robot 8 precedence change; it does not affect production suites.
- Read-only connectivity check confirmed backend, ADB and containers were available.

A full live rerun was not performed. The installed Robot interpreter lacks `grpcio` and `grpcio-tools`; installation into an isolated `/tmp` environment was declined. The direct Body ECU helper therefore still needs live verification with the project dependencies installed.

From the project root, in an interpreter/environment containing `starter/requirements.txt`:

```sh
python -m robot --outputdir results/fixed starter/robot/tests
```

Offline checks:

```sh
python3 -m unittest discover -s starter/robot/checks -v
robot --outputdir results/fix-offline starter/robot/checks/assertions.robot
robot --dryrun --outputdir results/fix-dryrun starter/robot/tests
```

Retain the failures caused by the bench defects as requirement failures. Do not change expected temperatures, HTTP statuses or terminal states simply to make this bench pass.
