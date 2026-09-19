*** Settings ***
Documentation       Scenario S03: Electric vehicle remote charging control.
Resource            ../resources/rest_api.resource
Resource            ../resources/adb.resource
Variables           ../variables/bench_local.py

Suite Setup         Initialize Vehicle Session
Suite Teardown      Close Vehicle Session
Test Setup          Reset Vehicle Bench


*** Test Cases ***
Verify Initial Charging State
    [Documentation]    Verifies the vehicle starts in a non-charging state after bench reset.
    [Tags]    req:REQ-CHG-001    req:REQ-CHG-002

    ${status}=    Get Vehicle Status
    Should Be True    '${status['charging']['state']}' in ['IDLE', 'UNKNOWN']

    Assert Gateway Charging State    IDLE


Start Charging And Verify SOC Progress
    [Documentation]    Starts charging, verifies CHARGING state and target,
    ...                and confirms SOC increases by at least 1% within 10 seconds.
    [Tags]    req:REQ-CHG-001

    ${before}=    Get Vehicle Status
    ${initial_soc}=    Set Variable    ${before['charging']['soc_percent']}

    ${resp}=    Send Start Charging Command    target_soc=80
    Should Be Equal As Integers    ${resp.status_code}    200
    Should Be Equal As Strings    ${resp.json()['status']}    ACCEPTED

    Wait For Command Terminal State    ${resp.json()['request_id']}

    # Backend must report charging and echo the requested target.
    Wait Until Keyword Succeeds
    ...    10s
    ...    500ms
    ...    Assert Backend Charging State
    ...    CHARGING
    ...    80

    # Gateway/VHAL must expose the same charging state and target.
    Wait Until Keyword Succeeds
    ...    10s
    ...    500ms
    ...    Assert Gateway Charging State
    ...    CHARGING
    ...    80

    # SOC must increase by at least 1% within the requirement window.
    Wait Until Keyword Succeeds
    ...    10s
    ...    500ms
    ...    Assert SOC Increased By At Least
    ...    ${initial_soc}
    ...    1


Stop Charging And Verify All Layers Stop
    [Documentation]    Stops an active charging session and verifies backend and VHAL
    ...                reach IDLE and SOC stops increasing.
    [Tags]    req:REQ-CHG-002

    ${start_resp}=    Send Start Charging Command    target_soc=80
    Should Be Equal As Integers    ${start_resp.status_code}    200
    Wait For Command Terminal State    ${start_resp.json()['request_id']}

    Wait Until Keyword Succeeds
    ...    10s
    ...    500ms
    ...    Assert Backend Charging State
    ...    CHARGING
    ...    80

    Wait Until Keyword Succeeds
    ...    10s
    ...    500ms
    ...    Assert Gateway Charging State
    ...    CHARGING
    ...    80

    ${stop_resp}=    Send Stop Charging Command
    Should Be Equal As Integers    ${stop_resp.status_code}    200
    Wait For Command Terminal State    ${stop_resp.json()['request_id']}

    # Give the asynchronous gateway/backend synchronization up to 10 seconds.
    Wait Until Keyword Succeeds
    ...    10s
    ...    500ms
    ...    Assert Backend Charging State
    ...    IDLE

    Wait Until Keyword Succeeds
    ...    10s
    ...    500ms
    ...    Assert Gateway Charging State
    ...    IDLE

    # Capture SOC only after the complete IDLE synchronization.
    ${status}=    Get Vehicle Status
    ${soc_at_idle}=    Set Variable    ${status['charging']['soc_percent']}

    # Allow enough time for another charging tick. SOC must remain unchanged.
    Sleep    4s

    ${later}=    Get Vehicle Status
    Should Be Equal As Integers
    ...    ${later['charging']['soc_percent']}
    ...    ${soc_at_idle}


Complete Charging At Target SOC
    [Documentation]    Verifies that reaching the target SOC causes the Body ECU/VHAL
    ...                charging state to become COMPLETE and that the backend reflects it.
    [Tags]    req:REQ-CHG-004

    # Use 50% so the completion test remains short while exercising the lower
    # boundary of the valid charging target range.
    ${resp}=    Send Start Charging Command    target_soc=50
    Should Be Equal As Integers    ${resp.status_code}    200
    Should Be Equal As Strings    ${resp.json()['status']}    ACCEPTED

    Wait For Command Terminal State    ${resp.json()['request_id']}

    # Wait until the backend reports that the target SOC has been reached.
    Wait Until Keyword Succeeds
    ...    30s
    ...    500ms
    ...    Assert Backend SOC At Least
    ...    50

    # Once the target is reached, VHAL must report COMPLETE.
    Wait Until Keyword Succeeds
    ...    10s
    ...    500ms
    ...    Assert Gateway Charging State
    ...    COMPLETE
    ...    50

    # Backend must reflect COMPLETE within the synchronization window.
    Wait Until Keyword Succeeds
    ...    10s
    ...    500ms
    ...    Assert Backend Charging State
    ...    COMPLETE
    ...    50
