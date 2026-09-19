*** Settings ***
Documentation       Scenario S06: Gateway remote-command delivery and gRPC behaviour.
Resource            ../resources/rest_api.resource
Resource            ../resources/adb.resource
Variables           ../variables/bench_local.py

Suite Setup         Initialize Vehicle Session
Suite Teardown      Close Vehicle Session
Test Setup          Reset Vehicle Bench


*** Test Cases ***
Queued Lock Command Is Forwarded Exactly Once
    [Documentation]    Verifies one queued LOCK command produces exactly one SetDoorLock gRPC request.
    [Tags]    req:REQ-ECU-002

    ${resp}=    Send Lock Command
    Should Be Equal As Integers    ${resp.status_code}    200

    ${request_id}=    Set Variable    ${resp.json()['request_id']}

    Wait For Command Terminal State Within 5 Seconds    ${request_id}

    ${log}=    Get Gateway DLT Log

    ${grpc_calls}=    Count Gateway Grpc Requests
    ...    ${log}
    ...    ${request_id}
    ...    SetDoorLock

    Should Be Equal As Integers
    ...    ${grpc_calls}
    ...    1
    ...    msg=Command ${request_id} generated ${grpc_calls} SetDoorLock calls instead of exactly one


Queued Command Is Forwarded Within One Second
    [Documentation]    Verifies the gRPC forwarding operation starts within 1 s of gateway queueing.
    [Tags]    req:REQ-ECU-002

    ${resp}=    Send Lock Command
    Should Be Equal As Integers    ${resp.status_code}    200

    ${request_id}=    Set Variable    ${resp.json()['request_id']}

    Wait For Command Terminal State Within 5 Seconds    ${request_id}

    ${log}=    Get Gateway DLT Log

    Assert Command Forwarded Within
    ...    ${log}
    ...    ${request_id}
    ...    SetDoorLock
    ...    1000


Unexecutable Command Must Be Reported Failed With Reason
    [Documentation]    Verifies a command that cannot be executed is never silently dropped.
    [Tags]    req:REQ-ECU-002

    ${resp}=    Send Stop Charging Command
    Should Be Equal As Integers    ${resp.status_code}    200

    ${request_id}=    Set Variable    ${resp.json()['request_id']}

    ${record}=    Wait For Command Terminal State Within 5 Seconds    ${request_id}

    Should Be Equal As Strings
    ...    ${record['status']}
    ...    FAILED

    Should Not Be Empty    ${record['reason']}

Verify Door Lock Grpc Deadline Accommodates Maximum Actuation
    [Documentation]    Verifies SetDoorLock deadline is at least the maximum Body ECU actuator time.
    [Tags]    req:REQ-NET-001

    ${cal}=    Adb Shell    cat /vendor/etc/calibration/tcu_cal.json

    ${deadline}=    Get JSON Value As Integer
    ...    ${cal}
    ...    door_lock_ack_timeout_ms

    Should Be True
    ...    ${deadline} >= 800
    ...    msg=SetDoorLock deadline ${deadline} ms is shorter than the Body ECU maximum 800 ms actuation time

Nominal Door Lock Cycles Have No Grpc Deadline Cancellation
    [Documentation]    Verifies nominal lock/unlock traffic has no gateway-side SetDoorLock timeout.
    [Tags]    req:REQ-NET-001

    FOR    ${index}    IN RANGE    10
        ${lock}=    Send Lock Command
        ${lock_id}=    Set Variable    ${lock.json()['request_id']}
        ${lock_record}=    Wait For Command Terminal State Within 5 Seconds    ${lock_id}

        Should Be Equal As Strings
        ...    ${lock_record['status']}
        ...    COMPLETED

        ${unlock}=    Send Unlock Command
        ${unlock_id}=    Set Variable    ${unlock.json()['request_id']}
        ${unlock_record}=    Wait For Command Terminal State Within 5 Seconds    ${unlock_id}

        Should Be Equal As Strings
        ...    ${unlock_record['status']}
        ...    COMPLETED
    END

    ${log}=    Get Gateway DLT Log

    Should Not Match Regexp
    ...    ${log}
    ...    (?m)^.*SetDoorLock failed.*grpc_code=DEADLINE_EXCEEDED.*$