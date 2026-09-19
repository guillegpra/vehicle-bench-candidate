*** Settings ***
Documentation       Scenario S02: Remote climate preconditioning.
Resource            ../resources/rest_api.resource
Resource            ../resources/adb.resource
Variables           ../variables/bench_local.py

Suite Setup         Initialize Vehicle Session
Suite Teardown      Close Vehicle Session
Test Setup          Reset Vehicle Bench

*** Variables ***
${TARGET_TEMP}      21.5
${VALID_SET_POINT}        21.5
${MIN_SET_POINT}          16.0
${MAX_SET_POINT}          28.0

*** Test Cases ***
Start Climate Preconditioning Cycle
    [Documentation]    Starts HVAC pre-conditioning and verifies vehicle telemetry state.
    ${resp}=              Send Start Climate Command    ${TARGET_TEMP}
    Should Be Equal As Integers    ${resp.status_code}    200
    ${req_id}=            Set Variable    ${resp.json()['request_id']}
    Wait For Command Terminal State       ${req_id}

    ${status}=            Get Vehicle Status
    Should Be True        ${status['climate']['active']}
    Should Be Equal As Numbers    ${status['climate']['target_temp_c']}    ${TARGET_TEMP}

Stop Climate Preconditioning Cycle
    [Documentation]    Stops HVAC and asserts inactive state.
    Send Start Climate Command    ${TARGET_TEMP}
    ${stop_resp}=         Send Stop Climate Command
    Should Be Equal As Integers    ${stop_resp.status_code}    200
    Wait For Command Terminal State    ${stop_resp.json()['request_id']}

    ${status}=            Get Vehicle Status
    Should Not Be True    ${status['climate']['active']}

Start Preconditioning At Set Point With 0.5 degC Resolution (req:REQ-CLI-001)
    [Tags]    req:REQ-CLI-001
    [Documentation]    POST /climate/start {21.5} sets backend active=true, setpoint=21.5, and VHAL HVAC_TEMPERATURE_SET within 10s.
    ${resp}=              Send Start Climate Command    target_temp=${VALID_SET_POINT}
    Should Be Equal As Integers    ${resp.status_code}    200
    ${req_id}=            Set Variable    ${resp.json()['request_id']}
    Wait For Command Terminal State Within 5 Seconds    ${req_id}

    # Verify multi-tier convergence within 10 seconds
    Wait Until Keyword Succeeds    10s    500ms    Assert Full Climate Start Synchronization    ${VALID_SET_POINT}

Reject Target Temperature Outside Allowed Range (req:REQ-CLI-002)
    [Tags]    req:REQ-CLI-002
    [Documentation]    Values outside [16.0, 28.0] return 422 and do not forward commands to the vehicle.
    # Snapshot commands count before negative testing
    ${commands_before}=    GET On Session    backend    /vehicle/commands    expected_status=200
    ${count_before}=       Get Length        ${commands_before.json()}

    # Lower boundary violation (< 16.0)
    Assert Target Temp Rejected With 422    15.5
    Assert Target Temp Rejected With 422    10.0

    # Upper boundary violation (> 28.0)
    Assert Target Temp Rejected With 422    28.5
    Assert Target Temp Rejected With 422    35.0

    # Verify no command was forwarded or added to the command queue
    ${commands_after}=     GET On Session    backend    /vehicle/commands    expected_status=200
    ${count_after}=        Get Length        ${commands_after.json()}
    Should Be Equal As Integers    ${count_before}    ${count_after}
    ...    msg=Commands were queued despite returning HTTP 422

Accept Boundary Temperatures
    [Documentation]    Verifies exact boundary values [16.0, 28.0] succeed.
    ${resp_min}=    Send Start Climate Command    target_temp=${MIN_SET_POINT}
    Should Be Equal As Integers    ${resp_min.status_code}    200
    Wait For Command Terminal State Within 5 Seconds           ${resp_min.json()['request_id']}

    ${resp_max}=    Send Start Climate Command    target_temp=${MAX_SET_POINT}
    Should Be Equal As Integers    ${resp_max.status_code}    200
    Wait For Command Terminal State Within 5 Seconds           ${resp_max.json()['request_id']}

Stop Preconditioning Multi Tier Verification (req:REQ-CLI-003)
    [Tags]    req:REQ-CLI-003
    [Documentation]    POST /climate/stop sets backend active=false, VHAL HVAC_POWER_ON=0, and ECU active=false within 10s.
    # Precondition: Activate climate
    ${start_resp}=    Send Start Climate Command    target_temp=${VALID_SET_POINT}
    Wait For Command Terminal State Within 5 Seconds    ${start_resp.json()['request_id']}

    # Stop Climate
    ${stop_resp}=     Send Stop Climate Command
    Should Be Equal As Integers    ${stop_resp.status_code}    200
    Wait For Command Terminal State Within 5 Seconds    ${stop_resp.json()['request_id']}

    # Verify multi-tier deactivation within 10 seconds
    Wait Until Keyword Succeeds    10s    500ms    Assert Full Climate Stop Synchronization

Verify State Convergence Between Backend And Body ECU (req:REQ-CLI-004)
    [Tags]    req:REQ-CLI-004
    [Documentation]    Set point and active state on backend match Body ECU values once converged (10 s).
    # 1. Test convergence in active state
    ${start_resp}=    Send Start Climate Command    target_temp=${VALID_SET_POINT}
    Wait For Command Terminal State Within 5 Seconds    ${start_resp.json()['request_id']}
    Wait Until Keyword Succeeds    10s    500ms    Assert Full Climate Start Synchronization    ${VALID_SET_POINT}

    # 2. Test convergence in stopped state
    ${stop_resp}=     Send Stop Climate Command
    Wait For Command Terminal State Within 5 Seconds    ${stop_resp.json()['request_id']}
    Wait Until Keyword Succeeds    10s    500ms    Assert Full Climate Stop Synchronization

*** Keywords ***
Assert Full Climate Start Synchronization
    [Arguments]    ${target_temp}
    Assert Backend Climate State       ${True}    ${target_temp}
    Assert Gateway VHAL HVAC Properties    ${target_temp}    power_on=1
    Assert Body ECU Climate Convergence    true    ${target_temp}

Assert Full Climate Stop Synchronization
    Assert Backend Climate State       ${False}
    Assert Gateway VHAL HVAC Properties    .*    power_on=0
    Assert Body ECU Climate Convergence    false
