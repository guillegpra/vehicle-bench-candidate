*** Settings ***
Documentation       Scenario S01: Central door lock and unlock duty cycle verification.
Resource            ../resources/rest_api.resource
Resource            ../resources/adb.resource
Variables           ../variables/bench_local.py

Suite Setup         Initialize Vehicle Session
Suite Teardown      Close Vehicle Session
Test Setup          Reset Vehicle Bench

*** Variables ***
${CONSECUTIVE_CYCLES}    20

*** Test Cases ***
Verify Lock Command Execution (req:REQ-LCK-001)
    [Tags]    req:REQ-LCK-001
    [Documentation]    Issues lock command and checks terminal state.
    ${resp}=              Send Lock Command
    Should Be Equal As Integers    ${resp.status_code}    200
    ${req_id}=            Set Variable    ${resp.json()['request_id']}
    Wait For Command Terminal State       ${req_id}

    ${status}=            Get Vehicle Status
    Should Be True        ${status['doors']['locked']}

Verify Unlock Command Execution (req:REQ-LCK-002)
    [Tags]    req:REQ-LCK-002
    [Documentation]    Issues unlock command and verifies latch state updates.
    ${lock_resp}=         Send Lock Command
    Wait For Command Terminal State       ${lock_resp.json()['request_id']}

    ${unlock_resp}=       Send Unlock Command
    Should Be Equal As Integers    ${unlock_resp.status_code}    200
    Wait For Command Terminal State       ${unlock_resp.json()['request_id']}

    ${status}=            Get Vehicle Status
    Should Be Equal    ${status['doors']['locked']}    ${False}

Verify Lock Command Propagates To All Layers Within 10 Seconds (req:REQ-LCK-001)
    [Tags]    req:REQ-LCK-001
    [Documentation]    POST /vehicle/lock -> doors.locked=true, VHAL DOOR_LOCK=1, ECU doors_locked=true within 10s.
    
    # 1. Precondition: Ensure vehicle is initially unlocked
    ${init_unlock}=    Send Unlock Command
    Should Be Equal As Integers    ${init_unlock.status_code}    200

    # 2. Trigger Lock Command
    ${resp}=    Send Lock Command
    Should Be Equal As Integers    ${resp.status_code}    200
    ${req_id}=    Set Variable     ${resp.json()['request_id']}

    # 3. Synchronous / Asynchronous confirmation
    Wait For Command Terminal State Within 5 Seconds    ${req_id}

    # 4. Enforce the 10s multi-tier synchronization constraint
    Wait For Full Lock Synchronization Within 10 Seconds

Verify Unlock Command Propagates To All Layers Within 10 Seconds (req:REQ-LCK-002)
    [Tags]    req:REQ-LCK-002
    [Documentation]    POST /vehicle/unlock -> doors.locked=false, VHAL DOOR_LOCK=0, ECU doors_locked=false within 10s.
    
    # 1. Precondition: Ensure vehicle is locked first so we test a real state change
    ${lock_resp}=    Send Lock Command
    Should Be Equal As Integers    ${lock_resp.status_code}    200
    Wait For Command Terminal State Within 5 Seconds    ${lock_resp.json()['request_id']}

    # 2. Trigger Unlock Command
    ${resp}=    Send Unlock Command
    Should Be Equal As Integers    ${resp.status_code}    200
    ${req_id}=    Set Variable     ${resp.json()['request_id']}

    # 3. Wait for command terminal state (COMPLETED)
    Wait For Command Terminal State Within 5 Seconds    ${req_id}

    # 4. Enforce the 10s multi-tier synchronization constraint
    Wait For Full Unlock Synchronization Within 10 Seconds

Verify Twenty Consecutive Lock Unlock Cycles With Zero Failures (req:REQ-LCK-003)
    [Tags]    req:REQ-LCK-003
    [Documentation]    Executes 20 full cycles (40 commands); asserts 0 FAILED and actuation <= 1000 ms.
    
    FOR    ${cycle}    IN RANGE    ${CONSECUTIVE_CYCLES}
        # Actuate Lock (Expect doors.locked = True)
        Execute Door Transition And Verify Actuation    LOCK      ${True}

        # Actuate Unlock (Expect doors.locked = False)
        Execute Door Transition And Verify Actuation    UNLOCK    ${False}
    END

Verify Failed Command Preserves Vehicle State (req:REQ-LCK-003)
    [Tags]    req:REQ-LCK-003
    [Documentation]    Asserts that if a command results in FAILED, the vehicle door latch state remains unchanged.
    
    # 1. Establish known baseline state (e.g., locked = True)
    Execute Door Transition And Verify Actuation    LOCK    ${True}
    ${pre_status}=    Get Vehicle Status
    ${initial_lock_state}=    Set Variable    ${pre_status['doors']['locked']}

    # 2. Issue a command that results in FAILED (e.g. unlock timeout or fault condition)
    ${resp}=    Send Unlock Command
    Should Be Equal As Integers    ${resp.status_code}    200
    ${req_id}=    Set Variable     ${resp.json()['request_id']}

    ${record}=    Wait For Command Terminal State Within 5 Seconds    ${req_id}
    
    # 3. Invariance check: if FAILED, state must strictly match initial state
    IF    '${record['status']}' == 'FAILED'
        ${post_status}=    Get Vehicle Status
        Should Be Equal    ${post_status['doors']['locked']}    ${initial_lock_state}
        ...    msg=State changed despite command returning FAILED!
    ELSE
        Log    Command completed successfully; state invariance on failure skipped.
    END

Verify Lock Unlock Does Not Modify Idle Subsystem States (req:REQ-LCK-004)
    [Tags]    req:REQ-LCK-004
    [Documentation]    Ensures lock/unlock cycle does not mutate default/idle climate and charging telemetry.
    
    # 1. Capture initial baseline snapshot
    ${initial_snapshot}=    Get Climate And Charging Telemetry Snapshot

    # 2. Execute Lock and verify no mutation
    ${lock_resp}=    Send Lock Command
    Should Be Equal As Integers    ${lock_resp.status_code}    200
    Wait For Command Terminal State Within 5 Seconds    ${lock_resp.json()['request_id']}
    Assert Climate And Charging Unchanged    ${initial_snapshot}

    # 3. Execute Unlock and verify no mutation
    ${unlock_resp}=  Send Unlock Command
    Should Be Equal As Integers    ${unlock_resp.status_code}    200
    Wait For Command Terminal State Within 5 Seconds    ${unlock_resp.json()['request_id']}
    Assert Climate And Charging Unchanged    ${initial_snapshot}

Verify Lock Unlock Does Not Interrupt Active Subsystems (req:REQ-LCK-004)
    [Tags]    req:REQ-LCK-004
    [Documentation]    Ensures door actuation does not shut down or abort active climate or charging sessions.
    [Teardown]         Run Keywords    Send Stop Climate Command    AND    Send Stop Charging Command

    # 1. Engage active preconditioning and charging sessions
    ${clim_resp}=    Send Start Climate Command    target_temp=23.5
    Should Be Equal As Integers    ${clim_resp.status_code}    200
    Wait For Command Terminal State Within 5 Seconds    ${clim_resp.json()['request_id']}

    ${chg_resp}=     Send Start Charging Command    target_soc=90
    Should Be Equal As Integers    ${chg_resp.status_code}    200
    Wait For Command Terminal State Within 5 Seconds    ${chg_resp.json()['request_id']}

    # 2. Snapshot active states
    ${active_snapshot}=    Get Climate And Charging Telemetry Snapshot
    Should Be True         ${active_snapshot['climate']['active']}

    # 3. Actuate doors (Lock -> Unlock cycle)
    ${l_resp}=    Send Lock Command
    Wait For Command Terminal State Within 5 Seconds    ${l_resp.json()['request_id']}
    Assert Climate And Charging Unchanged    ${active_snapshot}

    ${u_resp}=    Send Unlock Command
    Wait For Command Terminal State Within 5 Seconds    ${u_resp.json()['request_id']}
    Assert Climate And Charging Unchanged    ${active_snapshot}
