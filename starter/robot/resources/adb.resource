*** Settings ***
Documentation    ADB command bindings for telematics gateway inspection.
Library          Process
Library          String
Library          ../libraries/gateway_log.py
Library          ../libraries/body_state.py
Variables        ../variables/bench_local.py

*** Keywords ***
Adb Shell
    [Arguments]    @{command}
    [Documentation]    Executes a shell command via ADB and returns stripped stdout.
    ${cmd_str}=    Catenate    SEPARATOR=${SPACE}    @{command}
    ${result}=     Run Process    adb    -s    ${ADB_SERIAL}    shell    ${cmd_str}
    IF    ${result.rc} != 0
        Fail    adb failed: ${result.stderr}: ${result.rc} != 0
    END
    ${clean}=      Strip String    ${result.stdout}
    RETURN         ${clean}

Run ADB Shell Command
    [Arguments]    ${command}
    ${result}=     Run Process    adb    -s    ${ADB_SERIAL}    shell    ${command}
    RETURN         ${result.stdout}

Get Android Property
    [Arguments]    ${prop_name}
    ${output}=     Run ADB Shell Command    getprop ${prop_name}
    ${clean}=      Strip String    ${output}
    RETURN         ${clean}

Verify No Critical Logcat Errors
    ${logcat_fatal}=    Run ADB Shell Command    logcat -d *:F
    Should Not Contain    ${logcat_fatal}    FATAL EXCEPTION

Assert Gateway VHAL Door Lock
    [Documentation]    Inspects VHAL properties via dumpsys to verify DOOR_LOCK = 1.
    ${dumpsys}=    Adb Shell    dumpsys vehicle
    # Checks VHAL property DOOR_LOCK (matches 'DOOR_LOCK = 1', 'DOOR_LOCK: 1', or 'DOOR_LOCK, value: 1')
    Should Match Regexp    ${dumpsys}    (?i)DOOR_LOCK.*[=:]\\s*1

Assert Body ECU Doors Locked
    [Documentation]    Reads the Body ECU directly using GetBodyState.
    ${state}=    Get Body ECU State    ${BODY_ECU_ADDR}
    Should Be Equal    ${state['doors_locked']}    ${True}

Assert Gateway VHAL Door Unlock
    [Documentation]    Inspects VHAL properties via dumpsys to verify DOOR_LOCK = 0.
    ${dumpsys}=    Adb Shell    dumpsys vehicle
    Should Match Regexp    ${dumpsys}    (?i)DOOR_LOCK.*[=:]\\s*0

Assert Body ECU Doors Unlocked
    [Documentation]    Reads the Body ECU directly using GetBodyState.
    ${state}=    Get Body ECU State    ${BODY_ECU_ADDR}
    Should Be Equal    ${state['doors_locked']}    ${False}

# --- Climate (S02) ---
Assert Gateway VHAL HVAC Properties
    [Arguments]    ${expected_temp}    ${power_on}=1
    [Documentation]    Inspects VHAL HVAC properties via dumpsys.
    ${dumpsys}=    Adb Shell    dumpsys vehicle
    # Validate VHAL HVAC_TEMPERATURE_SET
    Should Match Regexp    ${dumpsys}    (?i)HVAC_TEMPERATURE_SET.*[=:]\\s*${expected_temp}
    # Validate VHAL HVAC_POWER_ON
    Should Match Regexp    ${dumpsys}    (?i)HVAC_POWER_ON.*[=:]\\s*${power_on}

Assert Body ECU Climate Convergence
    [Arguments]    ${expected_active}    ${expected_temp}=${None}
    ${state}=    Get Body ECU State    ${BODY_ECU_ADDR}
    ${active}=    Convert To Boolean    ${expected_active}
    Should Be Equal    ${state['climate_active']}    ${active}
    IF    $expected_temp is not None
        Should Be Equal As Numbers    ${state['target_temp_c']}    ${expected_temp}
    END

Assert Body ECU Charging State
    [Arguments]    ${expected_state}
    ${state}=    Get Body ECU State    ${BODY_ECU_ADDR}
    Should Be Equal    ${state['charging_state']}    ${expected_state}

# --- Charging (S03) ---
Assert Gateway VHAL Charging State
    [Arguments]    ${expected_state}
    ${dumpsys}=    Adb Shell    dumpsys vehicle
    Should Match Regexp
    ...    ${dumpsys}
    ...    (?m)^\\s*Property:\\s+0x11400F0F\\s+\\(EV_CHARGE_STATE\\s+\\)\\s+value=${expected_state}\\s*$

Assert Gateway VHAL Charging Target
    [Arguments]    ${expected_target}
    ${dumpsys}=    Adb Shell    dumpsys vehicle
    Should Match Regexp
    ...    ${dumpsys}
    ...    (?m)^\\s*Property:\\s+0x11400F10\\s+\\(EV_CHARGE_TARGET\\s+\\)\\s+value=${expected_target}\\s*$

Assert Gateway VHAL Charging SOC
    [Arguments]    ${expected_soc}
    ${dumpsys}=    Adb Shell    dumpsys vehicle
    Should Match Regexp
    ...    ${dumpsys}
    ...    (?m)^\\s*Property:\\s+0x11600309\\s+\\(EV_BATTERY_LEVEL\\s+\\)\\s+value=${expected_soc}\\s*$

Assert Full Charging Idle Synchronization
    Assert Backend Charging State    IDLE
    Assert Gateway VHAL Charging State    IDLE

Assert Gateway Charging State
    [Arguments]    ${expected_state}    ${expected_target}=${None}    ${expected_soc}=${None}

    ${dumpsys}=    Adb Shell    dumpsys vehicle

    Should Match Regexp
    ...    ${dumpsys}
    ...    (?m)^\\s*Property:\\s+0x11400F0F\\s+\\(EV_CHARGE_STATE\\s+\\)\\s+value=${expected_state}\\s*$

    IF    $expected_target is not None
        Should Match Regexp
        ...    ${dumpsys}
        ...    (?m)^\\s*Property:\\s+0x11400F10\\s+\\(EV_CHARGE_TARGET\\s+\\)\\s+value=${expected_target}\\s*$
    END

    IF    $expected_soc is not None
        Should Match Regexp
        ...    ${dumpsys}
        ...    (?m)^\\s*Property:\\s+0x11600309\\s+\\(EV_BATTERY_LEVEL\\s+\\)\\s+value=${expected_soc}\\s*$
    END

# --- S05 ---
Assert Body ECU Online
    ${dumpsys}=    Adb Shell    dumpsys vehicle
    Should Match Regexp
    ...    ${dumpsys}
    ...    (?m)^\\s*last_sync:.*body_ecu_online:\\s*True\\s*$

Assert Body ECU Offline
    ${dumpsys}=    Adb Shell    dumpsys vehicle
    Should Match Regexp
    ...    ${dumpsys}
    ...    (?m)^\\s*last_sync:.*body_ecu_online:\\s*False\\s*$

Get Gateway DLT Log
    [Documentation]    Reads the gateway DLT log through ADB.
    ${log}=    Adb Shell    cat /data/log/dlt/tcu.dlt
    RETURN    ${log}


Count Heartbeat Responses
    [Arguments]    ${log}
    ${matches}=    Get Regexp Matches
    ...    ${log}
    ...    (?m)^.*TCU\\s+HB\\s+(?:DEBUG|WARN)\\s+.*heartbeat (?:ok|latency above threshold).*$

    ${count}=    Get Length    ${matches}
    RETURN    ${count}


Count Heartbeat Warnings
    [Arguments]    ${log}
    ${matches}=    Get Regexp Matches
    ...    ${log}
    ...    (?m)^.*TCU\\s+HB\\s+WARN\\s+.*heartbeat latency above threshold.*$

    ${count}=    Get Length    ${matches}
    RETURN    ${count}


Count Regexp Matches
    [Arguments]    ${text}    ${pattern}
    ${matches}=    Get Regexp Matches    ${text}    ${pattern}
    ${count}=    Get Length    ${matches}
    RETURN    ${count}


Assert All Slow Heartbeats Are WARN
    [Arguments]    ${log}

    ${samples}=    Get Regexp Matches
    ...    ${log}
    ...    (?m)^.*TCU\\s+HB\\s+(DEBUG|WARN)\\s+.*latency_ms=(\\d+).*$
    ...    1
    ...    2

    FOR    ${sample}    IN    @{samples}
        ${level}=      Set Variable    ${sample}[0]
        ${latency}=    Convert To Integer    ${sample}[1]

        IF    ${latency} > 100
            Should Be Equal As Strings
            ...    ${level}
            ...    WARN
            ...    msg=Heartbeat latency ${latency} ms was not logged as WARN
        END
    END

# S06
Count Gateway Grpc Requests
    [Arguments]    ${log}    ${request_id}    ${method}

    ${matches}=    Get Regexp Matches
    ...    ${log}
    ...    (?m)^.*GRPC\\s+INFO\\s+.*${method} -> req=${request_id}\\b.*$

    ${count}=    Get Length    ${matches}
    RETURN    ${count}
