*** Settings ***
Documentation       Scenario S07: Cross-node logging and request correlation.
Resource            ../resources/rest_api.resource
Resource            ../resources/adb.resource
Resource            ../resources/logs.resource
Variables           ../variables/bench_local.py

Suite Setup         Initialize Vehicle Session
Suite Teardown      Close Vehicle Session
Test Setup          Reset Vehicle Bench


*** Test Cases ***
Lock Command Is Traceable Across All Nodes (req:REQ-LOG-001)
    [Tags]    req:REQ-LOG-001

    ${resp}=    Send Lock Command
    Should Be Equal As Integers    ${resp.status_code}    200

    ${request_id}=    Set Variable    ${resp.json()['request_id']}
    Wait For Command Terminal State Within 5 Seconds    ${request_id}

    Assert Request Traceable Across All Logs
    ...    ${request_id}
    ...    LOCK


Climate Command Is Traceable Across All Nodes (req:REQ-LOG-001)
    [Tags]    req:REQ-LOG-001

    ${resp}=    Send Start Climate Command    target_temp=21.5
    Should Be Equal As Integers    ${resp.status_code}    200

    ${request_id}=    Set Variable    ${resp.json()['request_id']}
    Wait For Command Terminal State Within 5 Seconds    ${request_id}

    Assert Request Traceable Across All Logs
    ...    ${request_id}
    ...    CLIMATE_START


Charging Command Is Traceable Across All Nodes (req:REQ-LOG-001)
    [Tags]    req:REQ-LOG-001

    ${resp}=    Send Start Charging Command    target_soc=80
    Should Be Equal As Integers    ${resp.status_code}    200

    ${request_id}=    Set Variable    ${resp.json()['request_id']}
    Wait For Command Terminal State Within 5 Seconds    ${request_id}

    Assert Request Traceable Across All Logs
    ...    ${request_id}
    ...    CHARGING_START

Nominal Lock Unlock Flow Produces No Gateway Errors (req:REQ-LOG-002)
    [Tags]    req:REQ-LOG-002

    ${before}=    Get Gateway DLT File

    ${lock}=    Send Lock Command
    Wait For Command Terminal State Within 5 Seconds    ${lock.json()['request_id']}

    ${unlock}=    Send Unlock Command
    Wait For Command Terminal State Within 5 Seconds    ${unlock.json()['request_id']}

    Assert No New Gateway Errors Since    ${before}


Nominal Climate Flow Produces No Gateway Errors (req:REQ-LOG-002)
    [Tags]    req:REQ-LOG-002

    ${before}=    Get Gateway DLT File

    ${start}=    Send Start Climate Command    target_temp=21.5
    Wait For Command Terminal State Within 5 Seconds    ${start.json()['request_id']}

    ${stop}=    Send Stop Climate Command
    Wait For Command Terminal State Within 5 Seconds    ${stop.json()['request_id']}

    Assert No New Gateway Errors Since    ${before}


Nominal Charging Flow Produces No Gateway Errors (req:REQ-LOG-002)
    [Tags]    req:REQ-LOG-002

    ${before}=    Get Gateway DLT File

    ${start}=    Send Start Charging Command    target_soc=80
    Wait For Command Terminal State Within 5 Seconds    ${start.json()['request_id']}

    ${stop}=    Send Stop Charging Command
    Wait For Command Terminal State Within 5 Seconds    ${stop.json()['request_id']}

    Assert No New Gateway Errors Since    ${before}
