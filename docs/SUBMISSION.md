# Vehicle Bench Assessment

**Submission · Guillermo García Pradales · September 19, 2026**

## 1. Execution instructions

Run the commands below from the project root.

### Prerequisites

| Tool | Version / purpose |
| --- | --- |
| Docker and Docker Compose | Compose v2.20+; runs the vehicle bench services |
| Python | 3.11+; runs Robot Framework and its dependencies |
| Android Debug Bridge (`adb`) | Android Platform Tools; connects to the gateway |
| Wireshark / TShark | Optional; inspects packet captures |

### Step 1 — Start the bench

Build and start the cloud backend, telematics gateway with its ADB daemon, Body ECU, and packet capture services:

```bash
docker compose up -d --build
```

The Toolbox is available separately through the Compose `tools` profile.

### Step 2 — Connect to the gateway

The mock Android telematics gateway exposes ADB on port `5555`:

```bash
adb connect 127.0.0.1:5555
adb devices -l
```

### Step 3 — Install test dependencies

Create and activate a Python virtual environment, then install the required packages:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r starter/requirements.txt
```

### Step 4 — Run the tests

**Smoke checks** — verify connectivity before running the full suite:

```bash
robot --variablefile starter/robot/variables/bench_local.py \
    --outputdir results/smoke/ \
    starter/robot/tests/smoke.robot
```

**Full suite** — run scenarios S01–S07 and the smoke tests:

```bash
robot --variablefile starter/robot/variables/bench_local.py \
    --outputdir results/ \
    starter/robot/tests/
```

**Individual scenario** — for example, S01 central locking:

```bash
robot --variablefile starter/robot/variables/bench_local.py \
    --outputdir results/s01/ \
    starter/robot/tests/s01_lock_unlock.robot
```

Each run writes the following artifacts to its selected output directory:

| Artifact | Contents |
| --- | --- |
| `report.html` | Test results summary |
| `log.html` | Detailed execution log |
| `output.xml` | Machine-readable Robot Framework results |

## 2. Continuous integration

The [Robot vehicle bench workflow](../.github/workflows/robot-tests.yml) runs on pushes, pull requests, and manual dispatch from GitHub's **Actions → Robot vehicle bench → Run workflow** menu.

### Pipeline stages

| Stage | What happens |
| --- | --- |
| **1. Prepare the runner** | Use Ubuntu 24.04 and Python 3.12 with pip caching; install ADB and project dependencies. |
| **2. Validate the test setup** | Run Python helper checks, offline Robot checks, and a dry run of the full suite. |
| **3. Start a fresh bench** | Clear historical DLT logs and live captures in the disposable CI checkout, build the Compose images, and start services with readiness checks. |
| **4. Verify connectivity** | Connect ADB and wait for `/vehicle/status` to report an online ECU with initialized door telemetry. |
| **5. Execute the suite** | Run all Robot tests sequentially and generate HTML, XML, and xUnit results. |
| **6. Collect diagnostics** | Save container status, container logs, and the ADB device list; stop the bench and flush packet captures. |
| **7. Archive evidence** | Upload test reports, diagnostics, DLT logs, and packet captures using `actions/upload-artifact@v6`, with 14-day retention. |

Diagnostic collection and artifact upload run even when tests fail. Known bench defects remain test failures; details are recorded in the [Robot failure analysis](ROBOT_FAILURE_ANALYSIS.md).

## 3. Assumptions

**State convergence.** Requirements that allow up to 10 seconds for state changes to propagate—such as `REQ-LCK-001`, `REQ-CLI-001`, and `REQ-CHG-001`—use polling assertions:

```robotframework
Wait Until Keyword Succeeds    10s    500ms    <assertion keyword>
```

The fixed 500 ms retry interval allows asynchronous state updates to converge within the specified window without relying on a single immediate assertion.

## 4. Time spent

Approximately **7 hours** were spent on the assignment, including around **3 hours** defining the Robot Framework tests. This was my first time using Robot Framework.

## 5. AI usage

AI assisted with:

- Troubleshooting installation and configuration errors.
- Learning Robot Framework and adjusting test scripts.
- Preparing and formatting Markdown documentation.
