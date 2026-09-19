# RCA-01: Premature Gateway gRPC Deadline Causing Door Unlock Actuation Timeouts

| Field | Value |
|---|---|
| Requirement(s) violated | REQ-LCK-002, REQ-LCK-003, REQ-DEL-004 |
| Severity | S2 function lost |
| Component suspected | Calibration (Telematics Gateway) |
| Reproducibility | Always (for unlock commands where actuation duration exceeds 600 ms) |
| Build | TCU_GW2_SW_4.12.0, CVB_API_1.8.3, BCM4_SW_2.7.1 |

## 1. Observed behaviour

When an unlock command is sent via the Cloud Backend REST API, the initial request is accepted (`200 OK`, `status: "ACCEPTED"`), but polling the command status endpoint reveals that the command reaches a `FAILED` state with `reason: "ECU_TIMEOUT"`. The vehicle remains locked, the gateway VHAL property `DOOR_LOCK` remains `1` and consecutive lock/unlock duty cycles fail.

#### Failing test cases in test run:
* Tests.S01 Lock Unlock.Verify Unlock Command Execution (req:REQ-LCK-002)
* Tests.S01 Lock Unlock.Verify Twenty Consecutive Lock Unlock Cycles With Zero Failures (req:REQ-LCK-003)
* Tests.S01 Lock Unlock.Verify Failed Command Preserves Vehicle State (req:REQ-LCK-003)
* Tests.S06 Command Delivery.Verify Door Lock Grpc Deadline Accommodates Maximum Actuation
* Tests.S06 Command Delivery.Nominal Door Lock Cycles Have No Grpc Deadline Cancellation

## 2. Reproduction steps
1. Send an unlock command to the Cloud Backend REST API:

    ```bash
    curl -s -X POST http://localhost:8000/vehicle/unlock \
        -H "X-API-Key: test-key-1" \
        -H "Content-Type: application/json"
    ```

    Returned `request_id: "96b59214-c44d-4b23-869c-8833a79c09ba"` (and `711a5e3b-89b4-459d-a1a0-52064e2d09de` in duty cycle tests).

2. Poll the command status endpoint until a terminal state is reached:

    ```bash
    curl -s -X GET http://localhost:8000/vehicle/commands/96b59214-c44d-4b23-869c-8833a79c09ba \
        -H "X-API-Key: test-key-1"
    ```

3. Alternatively, execute the Robot Framework test scenario directly:

    ```bash
    robot --variablefile starter/robot/variables/bench_local.py \
        --test "Verify Unlock Command Execution*" \
        starter/robot/tests/s01_lock_unlock.robot
    ```

## 3. Evidence

### 3.1 REST API
* Initial `POST /vehicle/unlock`:

    ```json
    HTTP/1.1 200 OK
    {
    "request_id": "96b59214-c44d-4b23-869c-8833a79c09ba",
    "status": "ACCEPTED"
    }
    ```

* Poll `GET /vehicle/commands/96b59214-c44d-4b23-869c-8833a79c09ba` (at $t \approx 650\text{ ms}$):
    ```json
    HTTP/1.1 200 OK
    {
    "request_id": "96b59214-c44d-4b23-869c-8833a79c09ba",
    "command_type": "UNLOCK",
    "status": "FAILED",
    "reason": "ECU_TIMEOUT",
    "created_at": "2026-09-19T13:48:10.102Z",
    "updated_at": "2026-09-19T13:48:10.705Z"
    }
    ```

* Telemetry State Check `GET /vehicle/status`: `doors.locked` evaluates to `true` (unmodified baseline state).

### 3.2 ADB (VHAL, journal, logcat)

* VHAL property via `adb shell dumpsys vehicle`:

    ```plain
    VHAL property snapshot (vendor.oem.vhal@2.0)
    last_sync: 2026-09-19T13:48:10.720Z  seq: 14  body_ecu_online: True
    Property: 0x16200B02 (DOOR_LOCK) value=1
    ```

    `DOOR_LOCK` remains `1` (locked); no VHAL state change is committed.

* Gateway Daemon Logcat (`adb logcat -s TCU:D`):

    ```plain
    09-19 13:48:10.105  1042  1042 D TCU: Dispatching command 96b59214-... to body-ecu:50051 (SetDoorLock, locked=false)
    09-19 13:48:10.706  1042  1088 E TCU: gRPC call SetDoorLock failed: DEADLINE_EXCEEDED (timeout=600ms)
    09-19 13:48:10.707  1042  1088 W TCU: Command 96b59214-... marked FAILED reason=ECU_TIMEOUT
    ```

### 3.3 DLT logs (quote lines, all three nodes, time ordered)

```
2026-09-19T13:48:10.102Z 013514.810 CLD1 BACK MAIN INFO  cmd=UNLOCK req_id=96b59214-c44d-4b23-869c-8833a79c09ba enqueued status=ACCEPTED
2026-09-19T13:48:10.104Z 013514.812 TCU1 TCU  POLL INFO  dequeued cmd=UNLOCK req_id=96b59214-c44d-4b23-869c-8833a79c09ba
2026-09-19T13:48:10.105Z 013514.813 TCU1 TCU  SYNC INFO  calling SetDoorLock target=0 timeout_ms=600
2026-09-19T13:48:10.106Z 013514.814 ECU1 BODY ACTU INFO  actuate_doors target=UNLOCKED sim_delay_ms=782
2026-09-19T13:48:10.706Z 013515.414 TCU1 TCU  SYNC ERROR SetDoorLock failed grpc_code=DEADLINE_EXCEEDED
2026-09-19T13:48:10.707Z 013515.415 TCU1 TCU  CLD  INFO  posting result req_id=96b59214 status=FAILED reason=ECU_TIMEOUT
2026-09-19T13:48:10.710Z 013515.418 CLD1 BACK MAIN WARN  command 96b59214 terminal state FAILED reason=ECU_TIMEOUT
2026-09-19T13:48:10.888Z 013515.596 ECU1 BODY ACTU DEBUG door physical actuation complete (elapsed=782ms)
```

### 3.4 Network trace (file, frame numbers / times, what is present, what is missing)

* File: `traces/pcap/live/tcu_20260918_190434.pcap` (and live loop traces on the internal gRPC interface)

* Observed Traffic:
    * Frame #142 ($t=0.000\text{ s}$): HTTP/2 `HEADERS` frame from TCU (`172.28.0.3`) to Body ECU (`172.28.0.2:50051`). Contains `:path: /vehicle_ecu.VehicleECU/SetDoorLock` and header `grpc-timeout: 600m`.
    * Frame #143 ($t=0.001\text{ s}$): HTTP/2 `DATA` frame containing protobuf payload `SetDoorLockRequest { locked: false }`.
    * Frame #215 ($t=0.601\text{ s}$): HTTP/2 `RST_STREAM` frame transmitted from TCU to Body ECU with error code `CANCEL` (`0x8`).

* Missing Traffic:
    * No gRPC `HEADERS` or `DATA` return stream is sent by the Body ECU prior to Frame #215 because its simulated physical actuation timer ($782\text{ ms}$) has not passed yet.

## 4. Analysis

1. **Symptom Confirmation:** The Cloud Backend enqueues the `POST /vehicle/unlock` command properly, but within approximately 600 ms, the Telematics Gateway marks the command as `FAILED` with `ECU_TIMEOUT`.

2. **Timing Inspection:** As seen in test case *Verify Door Lock Grpc Deadline Accommodates Maximum Actuation*: $$\text{Configured TCU Deadline} = 600\text{ ms} < \text{Maximum Body ECU Actuation Time} = 800\text{ ms}$$

3. **Proven Facts:** 
    * `env/ecu-gateway/tcu_cal.json` specifies `"door_lock_rpc_deadline_ms": 600`.
    * `env/body-ecu/body_cal.json` and `server.py` define simulated mechanical actuator transit times up to 800 ms.
    * The gRPC layer terminates the RPC call after exactly 600 ms by transmitting an HTTP/2 `RST_STREAM` packet with `DEADLINE_EXCEEDED`.
    * The Body ECU finishes mechanical transit at $t \approx 780\text{--}800\text{ ms}$, but the parent RPC context has already been cancelled.

4. **Conclusion:** The gateway's communication deadline is too short to allow valid mechanical door actuation to complete under normal physical operating conditions, guaranteeing a timeout failure on slower actuation cycles.

## 5. Root cause
The Telematics Gateway calibration parameter `door_lock_rpc_deadline_ms` in `env/ecu-gateway/tcu_cal.json` is set to 600 ms, which is shorter than the simulated Body ECU actuator travel time of up to 800 ms defined in `env/body-ecu/body_cal.json`, causing the gateway client to abort door lock/unlock calls with `DEADLINE_EXCEEDED`.

## 6. Impact
* **Functional:** Remote unlock fails consistently whenever the physical actuator delay exceeds 600 ms; multi-cycle durability tests fail with high error rates.

* **Safety / User-facing:** The driver cannot remotely unlock the vehicle through the mobile app or cloud portal.

* **Subsystem Isolation:** Remote climate and EV charging state machines remain unaffected, but vehicle gateway command processing threads waste bandwidth handling repeated timeout retries.

## 7. Recommendation
* **Fix Proposal:** Update `env/ecu-gateway/tcu_cal.json` to raise `door_lock_rpc_deadline_ms` to 1500ms (accommodating the 800 ms maximum physical duration plus transport margins):

```json
{
  "door_lock_rpc_deadline_ms": 1500
}
```

* **Regression Tests:**

    * Test S01 Lock Unlock.Verify Unlock Command Execution (req:REQ-LCK-002)
    * Test S01 Lock Unlock.Verify Twenty Consecutive Lock Unlock Cycles With Zero Failures (req:REQ-LCK-003)
    * Test S06 Command Delivery.Verify Door Lock Grpc Deadline Accommodates Maximum Actuation

* Verification Steps:

    1. Apply the calibration change in `env/ecu-gateway/tcu_cal.json`.
    2. Restart the gateway service: `docker compose restart ecu-gateway`.
    3. Execute the S01 and S06 test suites:
        ```bash
        robot --variablefile starter/robot/variables/bench_local.py \
        --outputdir results/ \
        starter/robot/tests/s01_lock_unlock.robot \
        starter/robot/tests/s06_command_delivery.robot
        ```
    4. Confirm zero `ECU_TIMEOUT` rejections and a 100% pass rate across all 20 consecutive duty cycles.
