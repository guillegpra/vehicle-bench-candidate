# Test Strategy - <release>

## 1. Scope and objective

This test strategy defines the verification process for the simulated vehicle environment, covering end-to-end communication from cloud REST services to the telematic gateway and Body ECU. 
The primary goal is to ensure functional reliability, contract compliance, protocol timing correctness, and zero unhandled exceptions across all vehicle operational scenarios.

## 2. Scope

#### In-Scope:

- Cloud Backend Service: REST API functional correctness, HTTP contract validation, error codes, and schema conformance (`env/backend/app/main.py`).   
- Telematics Gateway (TCU): Android OS subsystem behavior, system properties (getprop/setprop), service state inspection (dumpsys), command processing (am/pm), and crash diagnostics (logcat) via ADB.   
- Body ECU: gRPC protocol serialization, RPC service endpoints (`env/proto/vehicle_ecu.proto`), and calibration handling (`body_cal.json,` `tcu_cal.json`).   
- Test Scenarios: Complete validation of scenarios *S01* through *S04* against golden network traces (`traces/reference/`).   

#### Out-of-Scope:
- Physical hardware 
- Production over-the-air (OTA) cryptographic signature validation.

## 3. Test levels and techniques

| Test Tier | Component Focus | Interfaces & Protocols | Tools & Libraries | Pass Criteria |
| :--- | :--- | :--- | :--- | :--- |
| **Tier 1: Contract & API** | Cloud Backend | HTTP/REST, JSON payloads | Robot Framework (`rest_api.resource`), `RequestsLibrary` | 100% contract compliance; correct 4xx codes on invalid inputs. |
| **Tier 2: Gateway Runtime** | Android Gateway (TCU) | ADB socket protocol, Android CLI | Robot Framework (`adb.resource`), `adbd` | Zero unhandled exceptions in `logcat`; expected service state in `dumpsys`. |
| **Tier 3: ECU Protocol** | Body ECU | gRPC, Protocol Buffers | Python gRPC client stubs, JSON calibration validators | Protobuf schemas strictly validated; zero serialization exceptions. |
| **Tier 4: End-to-End Scenarios** | Complete Bench Integration | REST $\rightarrow$ Gateway $\rightarrow$ Body ECU | `scenario-runner`, `capture` container, Wireshark/`tshark` | Scenario flows complete successfully; PCAP traces match golden reference. |

## 4. Traceability matrix

### S01: Lock/Unlock Cycles
* **Objective**: Validate central locking actuation, state synchronization, and duty-cycle command queuing.
* **Execution**: Trigger alternating lock and unlock requests through the REST API; poll gateway properties via ADB and gRPC response telemetry on the Body ECU.
* **Verification**: Verify that door latch states remain consistent across all tiers without lost commands during rapid cycling.
* **Trace Reference**: Compare capture files to `traces/reference/S01_lock_unlock_cycles.pcap`.

### S02: Climate Preconditioning
* **Objective**: Verify cabin thermal regulation, preconditioning triggers, and battery State of Charge (SoC) safety guards.
* **Execution**: Submit preconditioning temperature requests; poll thermal loop states; monitor DLT log records using `env/common/dltlog.py`.
* **Verification**: Verify target cabin temperature stabilization and automatic lockout when simulated SoC falls below calibrated limits.
* **Trace Reference**: Compare capture files to `traces/reference/S02_climate_preconditioning.pcap`.

### S03: Charging Session
* **Objective**: Validate EV charging state machine transitions and threshold adherence.
* **Execution**: Emulate EVSE cable connection, initiate charging commands, monitor energy transfer telemetry, and simulate cable disconnect events.
* **Verification**: Confirm state transitions strictly follow `Disconnected` $\rightarrow$ `Connected` $\rightarrow$ `Charging` $\rightarrow$ `Completed` per calibration files (`tcu_cal.json`, `body_cal.json`).
* **Trace Reference**: Compare capture files to `traces/reference/S03_charging_session.pcap`.

### S04: API Validation & Robustness
* **Objective**: Evaluate input sanitization, schema boundaries, and error handling under malformed requests.
* **Execution**: Execute negative test suites passing missing keys, invalid types, out-of-range floats, and oversized payloads.
* **Verification**: Assert that the backend returns standard 4xx status codes without throwing unhandled 500 internal server exceptions.
* **Trace Reference**: Compare capture files to `traces/reference/S04_api_validation.pcap`.

## 5. Automation Strategy & Test Tooling

* **Core Framework**: Robot Framework executing test suites inside the `scenario-runner` container.
* **Shared Keyword Libraries**:
  * `starter/robot/resources/rest_api.resource`: Wraps REST endpoints, JSON payload construction, and response status assertions.
  * `starter/robot/resources/adb.resource`: Encapsulates ADB commands including `getprop`, `dumpsys`, and `logcat` filter operations.
* **Trace & Log Diagnostics**:
  * Packet capture inspection via `capture` container running `tcpdump`.
  * Automated PCAP differential analysis against reference captures using `tshark`.
  * Diagnostic event stream verification using DLT log formats defined in `docs/LOG_FORMAT.md`.

## 6. Quality Gates & Defect Workflow

* **Smoke Gate (G1)**: Execution of `starter/robot/tests/smoke.robot` confirming all container services and ADB ports are reachable.
* **Regression Gate (G2)**: Automated execution of scenarios S01 through S04 achieving a 100% pass rate with zero unexpected protocol drops.
* **Trace Fidelity Gate (G3)**: Network trace packet sequence and timing must align within accepted tolerance of golden samples in `traces/reference/`.
* **Defect Triage**: Any identified regression or anomalous behavior between `traces/samples/` and `traces/reference/` must be analyzed and documented in `templates/RCA_TEMPLATE.md`.


1. Scope and objective (what is validated, what is not, release question to answer)
2. System under test and observation points (interfaces used as stimulus vs oracle)
3. Risks and test focus (table: risk, likelihood, impact, mitigation)
4. Test levels and techniques (smoke, contract, feature, end-to-end, diagnostics; techniques used)
5. Traceability matrix (REQ id -> test cases)
6. Environment, data, repeatability (reset strategy, timing constants, flakiness handling)
7. Entry / exit criteria and current verdict
8. CI/CD (what runs where, artefacts)
9. Use of AI assistance (what for, how verified)