*** Settings ***
Documentation       Scenario S05: Body ECU heartbeat supervision.
Resource            ../resources/rest_api.resource
Resource            ../resources/adb.resource
Resource            ../resources/docker.resource
Variables           ../variables/bench_local.py

Suite Setup         Initialize Vehicle Session
Suite Teardown      Close Vehicle Session


*** Test Cases ***
Verify Body ECU Is Online During Nominal Operation (req:REQ-ECU-001)
    [Documentation]    Confirms the gateway reports the Body ECU online during nominal operation.
    [Tags]    req:REQ-ECU-001

    Wait Until Keyword Succeeds
    ...    5s
    ...    500ms
    ...    Assert Body ECU Online


Verify Heartbeat Latency Above 100ms Is Logged As WARN (req:REQ-ECU-001)
    [Documentation]    Verifies heartbeat samples above 100 ms are classified as WARN.
    [Tags]    req:REQ-ECU-001

    ${log}=    Get Gateway DLT Log

    ${slow_hb_count}=    Count Regexp Matches
    ...    ${log}
    ...    (?m)^.*HB\\s+WARN\\s+.*heartbeat latency above threshold.*latency_ms=(\\d+).*threshold_ms=100.*$

    Should Be True
    ...    ${slow_hb_count} > 0
    ...    msg=No heartbeat latency warning above the 100 ms threshold was found

    Assert All Slow Heartbeats Are WARN    ${log}


Verify Heartbeat Warning Rate Is At Most Ten Percent (req:REQ-ECU-001)
    [Documentation]    Verifies latency WARN events affect no more than 10 percent of heartbeat responses.
    [Tags]    req:REQ-ECU-001

    ${log}=    Get Gateway DLT Log

    ${total}=    Count Heartbeat Responses    ${log}
    ${warnings}=    Count Heartbeat Warnings    ${log}

    Should Be True
    ...    ${total} > 0
    ...    msg=No heartbeat records were found in gateway log

    ${warning_rate}=    Evaluate    ($warnings / $total) * 100

    Should Be True
    ...    ${warning_rate} <= 10
    ...    msg=Heartbeat warning rate was ${warning_rate}% (${warnings}/${total}), exceeding 10%


Verify Heartbeat Period Is Approximately Two Seconds (req:REQ-ECU-001)
    [Documentation]    Verifies nominal heartbeat scheduling is consistent with the configured 2 s period.
    [Tags]    req:REQ-ECU-001

    ${before}=    Get Gateway DLT Log
    Sleep    8s
    ${after}=    Get Gateway DLT Log
    Should Start With    ${after}    ${before}    msg=Gateway log rotated during heartbeat observation
    ${log}=    Evaluate    $after[len($before):]
    Assert Heartbeat Sequence Timing    ${log}    expected_period_s=2.0

Verify Three Consecutive Heartbeat Misses Mark ECU Offline (req:REQ-ECU-001)
    [Documentation]    Stops the Body ECU and verifies heartbeat supervision marks it offline.
    [Tags]    req:REQ-ECU-001    destructive

    Assert Body ECU Online

    Stop Body ECU Container

    TRY
        # 3 misses × 2 s heartbeat period plus scheduling tolerance.
        Wait Until Keyword Succeeds
        ...    9s
        ...    500ms
        ...    Assert Body ECU Offline

        ${log}=    Get Gateway DLT Log
        Should Contain    ${log}    missed=3
    FINALLY
        Start Body ECU Container
        Wait Until Keyword Succeeds    10s    500ms    Assert Body ECU Online
    END
