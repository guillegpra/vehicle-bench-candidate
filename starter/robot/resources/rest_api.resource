*** Settings ***
Documentation    REST API client bindings matching Connected Vehicle Backend OpenAPI specs.
Library          RequestsLibrary
Library          Collections
Variables        ../variables/bench_local.py

*** Variables ***
${API_KEY}       dev-key-001

*** Keywords ***
Initialize Vehicle Session
    [Documentation]    Establishes the persistent HTTP session using alias 'backend'.
    ${headers}=       Create Dictionary    X-API-Key=${API_KEY}    Content-Type=application/json
    Create Session    backend    ${BACKEND_URL}    headers=${headers}    disable_warnings=1

Open Backend Session
    [Documentation]    Alias required by smoke.robot
    Initialize Vehicle Session

Close Vehicle Session
    [Documentation]    Tears down all open HTTP sessions.
    Delete All Sessions

Reset Vehicle Bench
    [Documentation]    Resets vehicle commands and returns system to baseline.
    ${resp}=    POST On Session    backend    /bench/reset    expected_status=any
    RETURN      ${resp}

Get Vehicle Status
    [Documentation]    Fetches current telemetry from /vehicle/status.
    ${resp}=    GET On Session     backend    /vehicle/status    expected_status=200
    RETURN      ${resp.json()}

Wait For Command Terminal State
    [Arguments]    ${request_id}    ${timeout}=10s
    Wait Until Keyword Succeeds    ${timeout}    500ms    Assert Command State    ${request_id}

Assert Command State
    [Arguments]    ${request_id}
    ${resp}=    GET On Session    backend    /vehicle/commands/${request_id}    expected_status=200
    ${data}=    Set Variable      ${resp.json()}
    IF    '${data['status']}' == 'FAILED'
        Fail    Vehicle command ${request_id} REJECTED with reason: "${data.get('reason')}"
    END
    Should Be Equal As Strings    ${data['status']}    COMPLETED    msg=Command still pending

Verify Command Accepted Contract
    [Arguments]    ${resp}
    [Documentation]    Validates latency <= 500ms, HTTP 200, UUID request_id, status=ACCEPTED, and ISO 8601 UTC timestamp.
    
    # 1. HTTP 200 Status Code
    Should Be Equal As Integers    ${resp.status_code}    200

    # 2. Latency <= 500 ms (resp.elapsed is a Python timedelta object provided by requests)
    ${elapsed_s}=     Set Variable    ${resp.elapsed.total_seconds()}
    ${elapsed_ms}=    Evaluate        ${elapsed_s} * 1000
    Should Be True    ${elapsed_ms} <= 500    msg=Response took ${elapsed_ms} ms, exceeding the 500 ms SLA limit.

    ${body}=    Set Variable    ${resp.json()}

    # 3. Status = ACCEPTED
    Dictionary Should Contain Key    ${body}    status
    Should Be Equal As Strings       ${body['status']}    ACCEPTED

    # 4. request_id is a valid UUID (8-4-4-4-12 hexadecimal format)
    Dictionary Should Contain Key    ${body}    request_id
    Should Match Regexp              ${body['request_id']}    ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$

    # 5. submitted_at is ISO 8601 UTC with millisecond precision and 'Z' suffix (e.g., 2026-09-18T20:30:15.123Z)
    Dictionary Should Contain Key    ${body}    submitted_at
    Should Match Regexp              ${body['submitted_at']}    ^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$

Wait For Command Terminal State Within 5 Seconds
    [Arguments]    ${request_id}    ${timeout}=5s
    [Documentation]    Polls GET /vehicle/commands/{request_id} until a terminal state is reached within 5s.
    ${record}=    Wait Until Keyword Succeeds    ${timeout}    250ms    Verify Command Terminal State Contract    ${request_id}
    RETURN        ${record}

Verify Command Terminal State Contract
    [Arguments]    ${request_id}
    [Documentation]    Asserts status is COMPLETED or FAILED, and checks reason when FAILED.
    ${resp}=    GET On Session    backend    /vehicle/commands/${request_id}    expected_status=200
    ${body}=    Set Variable      ${resp.json()}

    # 1. State must not remain ACCEPTED
    Should Not Be Equal As Strings    ${body['status']}    ACCEPTED    msg=Command ${request_id} still ACCEPTED after polling

    # 2. Terminal state must be COMPLETED or FAILED
    Should Contain Any    ${body['status']}    COMPLETED    FAILED    msg=Terminal status invalid: ${body['status']}

    # 3. If FAILED, reason must be present, non-null, and non-empty
    IF    '${body['status']}' == 'FAILED'
        Dictionary Should Contain Key    ${body}    reason
        Should Not Be Empty              ${body['reason']}    msg=FAILED status missing failure reason
        Should Not Be Equal              ${body['reason']}    ${None}
    END

    RETURN    ${body}

Verify Vehicle Status Contract
    [Arguments]    ${status}
    [Documentation]    Validates presence and types of vin, doors, climate, charging, and connectivity telemetry.

    # 1. Top-Level VIN
    Dictionary Should Contain Key    ${status}    vin
    Should Not Be Empty              ${status['vin']}

    # 2. Doors schema
    Dictionary Should Contain Key    ${status}              doors
    Dictionary Should Contain Key    ${status['doors']}     locked
    Should Be True                   isinstance($status['doors']['locked'], bool)

    # 3. Climate schema
    Dictionary Should Contain Key    ${status}                climate
    Dictionary Should Contain Key    ${status['climate']}     active
    Dictionary Should Contain Key    ${status['climate']}     target_temp_c
    Should Be True                   isinstance($status['climate']['active'], bool)
    Should Be True                   isinstance($status['climate']['target_temp_c'], (int, float))

    # 4. Charging schema
    Dictionary Should Contain Key    ${status}                 charging
    Dictionary Should Contain Key    ${status['charging']}      state
    Dictionary Should Contain Key    ${status['charging']}      soc_percent
    Dictionary Should Contain Key    ${status['charging']}      target_soc_percent
    Should Contain Any               ${status['charging']['state']}    IDLE    CHARGING    COMPLETE    FAULT    UNKNOWN

    # 5. Connectivity schema
    Dictionary Should Contain Key    ${status}                    connectivity
    Dictionary Should Contain Key    ${status['connectivity']}     ecu_online
    Dictionary Should Contain Key    ${status['connectivity']}     last_report_at
    Dictionary Should Contain Key    ${status['connectivity']}     report_age_s
    Should Be True                   isinstance($status['connectivity']['ecu_online'], bool)

    # 6. Connected Vehicle SLA: report_age_s must be below 10 seconds
    IF    ${status['connectivity']['ecu_online']}
        ${age}=    Convert To Number    ${status['connectivity']['report_age_s']}
        Should Be True    ${age} < 10.0    msg=Telemetry report age ${age}s exceeds 10s connected threshold
        Should Be True    ${age} >= 0.0    msg=Report age cannot be negative
    END

Get OpenAPI Specification
    [Documentation]    Fetches the raw OpenAPI specification document.
    ${resp}=    GET On Session    backend    /openapi.json    expected_status=200
    RETURN      ${resp}

Verify OpenAPI Specification Contract
    [Arguments]    ${spec}
    [Documentation]    Validates OpenAPI version 3.x and confirms coverage of all public endpoints.

    # 1. Verify OpenAPI 3 specification format (e.g. 3.0.x or 3.1.x)
    Dictionary Should Contain Key    ${spec}    openapi
    Should Match Regexp              ${spec['openapi']}    ^3\\..*

    # 2. Verify Info block presence
    Dictionary Should Contain Key    ${spec}    info
    Dictionary Should Contain Key    ${spec['info']}    title
    Dictionary Should Contain Key    ${spec['info']}    version

    # 3. Verify Paths dictionary contains all public endpoints
    Dictionary Should Contain Key    ${spec}    paths
    ${paths}=    Set Variable    ${spec['paths']}

    @{expected_public_endpoints}=    Create List
    ...    /health
    ...    /vehicle/lock
    ...    /vehicle/unlock
    ...    /climate/start
    ...    /climate/stop
    ...    /charging/start
    ...    /charging/stop
    ...    /vehicle/status
    ...    /vehicle/commands
    ...    /vehicle/commands/{request_id}

    FOR    ${endpoint}    IN    @{expected_public_endpoints}
        Dictionary Should Contain Key    ${paths}    ${endpoint}
        ...    msg=OpenAPI document missing public endpoint: ${endpoint}
    END

# --- Doors (S01) ---
Send Lock Command
    ${resp}=    POST On Session    backend    /vehicle/lock    expected_status=any
    RETURN      ${resp}

Send Unlock Command
    ${resp}=    POST On Session    backend    /vehicle/unlock    expected_status=any
    RETURN      ${resp}

Assert Backend Doors Locked
    [Documentation]    Verifies that GET /vehicle/status reports doors.locked = true.
    ${status}=    Get Vehicle Status
    Should Be True    ${status['doors']['locked']}    msg=Backend status does not report doors.locked = true

Assert Backend Doors Unlocked
    [Documentation]    Verifies that GET /vehicle/status reports doors.locked = false.
    ${status}=    Get Vehicle Status
    Should Not Be True    ${status['doors']['locked']}    msg=Backend status does not report doors.locked = false

Assert Full Lock Synchronization
    [Documentation]    Ensures Backend API, Gateway VHAL, and Body ECU all reflect locked state.
    Assert Backend Doors Locked
    Assert Gateway VHAL Door Lock
    Assert Body ECU Doors Locked

Wait For Full Lock Synchronization Within 10 Seconds
    [Documentation]    Polls all three layers until all report locked within the 10s SLA.
    Wait Until Keyword Succeeds    10s    500ms    Assert Full Lock Synchronization

Assert Full Unlock Synchronization
    [Documentation]    Ensures Backend API, Gateway VHAL, and Body ECU all reflect unlocked state.
    Assert Backend Doors Unlocked
    Assert Gateway VHAL Door Unlock
    Assert Body ECU Doors Unlocked

Wait For Full Unlock Synchronization Within 10 Seconds
    [Documentation]    Polls all three layers until all report unlocked within the 10s SLA.
    Wait Until Keyword Succeeds    10s    500ms    Assert Full Unlock Synchronization

Execute Door Transition And Verify Actuation
    [Arguments]    ${action}    ${expected_locked}
    [Documentation]    Executes lock/unlock, verifies COMPLETED status, checks actuation <= 1000 ms, and validates new state.
    
    IF    '${action}' == 'LOCK'
        ${resp}=    Send Lock Command
    ELSE IF    '${action}' == 'UNLOCK'
        ${resp}=    Send Unlock Command
    ELSE
        Fail    Invalid action: ${action}
    END

    Should Be Equal As Integers    ${resp.status_code}    200
    ${req_id}=    Set Variable     ${resp.json()['request_id']}

    # 1. Command must complete with status = COMPLETED
    ${record}=    Wait For Command Terminal State Within 5 Seconds    ${req_id}
    Should Be Equal As Strings    ${record['status']}    COMPLETED    msg=Command ${req_id} failed: ${record.get('reason')}

    # 2. Body ECU actuation time takes up to 1 s (1000 ms)
    IF    'elapsed_ms' in $record and $record['elapsed_ms'] is not None
        Should Be True    ${record['elapsed_ms']} <= 1000
        ...    msg=Actuation elapsed_ms (${record['elapsed_ms']} ms) exceeded 1000 ms limit
    END

    # 3. Verify vehicle state reflection
    ${status}=    Get Vehicle Status
    Should Be Equal    ${status['doors']['locked']}    ${expected_locked}
    ...    msg=Expected doors.locked to be ${expected_locked} after ${action}

Get Climate And Charging Telemetry Snapshot
    [Documentation]    Captures the current climate and charging state dictionaries from /vehicle/status.
    ${status}=    Get Vehicle Status
    ${snapshot}=  Create Dictionary
    ...    climate=${status['climate']}
    ...    charging=${status['charging']}
    RETURN        ${snapshot}

Assert Climate And Charging Unchanged
    [Arguments]    ${expected_snapshot}
    [Documentation]    Verifies operational states and target values remain identical to the pre-actuation snapshot.
    ${current}=    Get Vehicle Status

    # 1. Climate state invariance
    Should Be Equal    ${current['climate']['active']}    ${expected_snapshot['climate']['active']}
    ...    msg=Door command mutated climate.active state!
    Should Be Equal As Numbers    ${current['climate']['target_temp_c']}    ${expected_snapshot['climate']['target_temp_c']}
    ...    msg=Door command mutated climate.target_temp_c!

    # 2. Charging state invariance
    Should Be Equal As Strings    ${current['charging']['state']}    ${expected_snapshot['charging']['state']}
    ...    msg=Door command mutated charging.state!
    Should Be Equal As Integers   ${current['charging']['target_soc_percent']}    ${expected_snapshot['charging']['target_soc_percent']}
    ...    msg=Door command mutated charging.target_soc_percent!

# --- Climate (S02) ---
Send Start Climate Command
    [Arguments]    ${target_temp}=22.0
    ${temp_float}=    Convert To Number    ${target_temp}
    &{payload}=       Create Dictionary    target_temp_c=${temp_float}
    ${resp}=          POST On Session      backend    /climate/start    json=${payload}    expected_status=any
    RETURN            ${resp}

Send Stop Climate Command
    ${resp}=    POST On Session    backend    /climate/stop    expected_status=any
    RETURN      ${resp}

Assert Backend Climate State
    [Arguments]    ${expected_active}    ${expected_temp}=${None}
    [Documentation]    Asserts climate.active and target_temp_c in /vehicle/status.
    ${status}=    Get Vehicle Status
    IF    ${expected_active}
        Should Be True    ${status['climate']['active']}    msg=Expected climate.active to be True
    ELSE
        Should Not Be True    ${status['climate']['active']}    msg=Expected climate.active to be False
    END
    IF    $expected_temp is not None
        Should Be Equal As Numbers    ${status['climate']['target_temp_c']}    ${expected_temp}
        ...    msg=Backend target_temp_c does not match expected set point
    END

Assert Target Temp Rejected With 422
    [Arguments]    ${invalid_temp}
    [Documentation]    Asserts that temperatures outside [16.0, 28.0] return HTTP 422.
    &{payload}=    Create Dictionary    target_temp_c=${invalid_temp}
    ${resp}=       Send Raw Request     POST    /climate/start    body=${payload}
    Should Be Equal As Integers         ${resp.status_code}    422
    ...    msg=Temperature ${invalid_temp} was not rejected with HTTP 422

# --- Charging (S03) ---
Send Start Charging Command
    [Arguments]    ${target_soc}=80
    ${soc_int}=    Convert To Integer    ${target_soc}
    &{payload}=    Create Dictionary     target_soc_percent=${soc_int}
    ${resp}=       POST On Session       backend    /charging/start    json=${payload}    expected_status=any
    RETURN         ${resp}

Send Stop Charging Command
    ${resp}=    POST On Session    backend    /charging/stop    expected_status=any
    RETURN      ${resp}

Assert Backend Charging State
    [Arguments]    ${expected_state}    ${expected_target}=${None}
    [Documentation]
    ...    Assert backend charging state and optionally target SOC.

    ${status}=    Get Vehicle Status

    Should Be Equal As Strings
    ...    ${status['charging']['state']}
    ...    ${expected_state}
    ...    msg=Expected charging.state=${expected_state}

    IF    $expected_target is not None
        Should Be Equal As Integers
        ...    ${status['charging']['target_soc_percent']}
        ...    ${expected_target}
        ...    msg=Expected target_soc_percent=${expected_target}
    END


Assert SOC Increased By At Least
    [Arguments]    ${initial_soc}    ${minimum_increase}
    [Documentation]
    ...    Verify current SOC is at least initial SOC plus the requested increase.

    ${status}=    Get Vehicle Status
    ${current_soc}=    Set Variable
    ...    ${status['charging']['soc_percent']}

    ${increase}=    Evaluate
    ...    ${current_soc} - ${initial_soc}

    Should Be True
    ...    ${increase} >= ${minimum_increase}
    ...    msg=SOC increased only ${increase}% (initial=${initial_soc}, current=${current_soc})


Assert Backend SOC At Least
    [Arguments]    ${expected_soc}
    ${status}=    Get Vehicle Status

    Should Be True
    ...    ${status['charging']['soc_percent']} >= ${expected_soc}
    ...    msg=SOC ${status['charging']['soc_percent']} has not reached ${expected_soc}


Assert Full Charging Idle Synchronization
    [Documentation]
    ...    Verify backend, gateway VHAL and Body ECU all report IDLE.

    Assert Backend Charging State    IDLE
    Assert Gateway VHAL Charging State    IDLE
    Assert Body ECU Charging State    IDLE


Wait For Full Charging Idle Synchronization
    [Arguments]    ${timeout}=10s
    Wait Until Keyword Succeeds
    ...    ${timeout}
    ...    500ms
    ...    Assert Full Charging Idle Synchronization

# --- Raw Requests for Negative Boundary Tests (S04) ---
Send Raw Request
    [Arguments]    ${method}    ${endpoint}    ${body}=${None}    ${custom_headers}=${None}
    IF    $custom_headers is not None
        ${resp}=    Run Keyword    ${method} On Session    backend    ${endpoint}    json=${body}    headers=${custom_headers}    expected_status=any
    ELSE
        ${resp}=    Run Keyword    ${method} On Session    backend    ${endpoint}    json=${body}    expected_status=any
    END
    RETURN    ${resp}