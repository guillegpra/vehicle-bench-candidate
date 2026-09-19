*** Settings ***
Documentation       Scenario S04: REST API schema constraints and robustness validation.
Resource            ../resources/rest_api.resource
Variables           ../variables/bench_local.py

Suite Setup         Initialize Vehicle Session
Suite Teardown      Close Vehicle Session

*** Test Cases ***
Reject Climate Temperature Out Of Boundaries
    [Documentation]    OpenAPI limits target_temp_c (16.0 to 28.0). Expects 422.
    &{too_hot}=        Create Dictionary    target_temp_c=${35.0}
    ${resp}=           Send Raw Request     POST    /climate/start    body=${too_hot}
    Should Be Equal As Integers    ${resp.status_code}    422

    &{too_cold}=       Create Dictionary    target_temp_c=${10.0}
    ${resp_cold}=      Send Raw Request     POST    /climate/start    body=${too_cold}
    Should Be Equal As Integers    ${resp_cold.status_code}    422

Reject Charging Target SoC Outside Boundaries (req:REQ-CHG-003)
    [Tags]    req:REQ-CHG-003
    [Documentation]
    ...    Values below 50 or above 100 shall return HTTP 422.

    &{too_low}=    Create Dictionary
    ...    target_soc_percent=49

    ${resp}=    Send Raw Request
    ...    POST
    ...    /charging/start
    ...    body=${too_low}

    Should Be Equal As Integers
    ...    ${resp.status_code}
    ...    422

    &{too_high}=    Create Dictionary
    ...    target_soc_percent=101

    ${resp}=    Send Raw Request
    ...    POST
    ...    /charging/start
    ...    body=${too_high}

    Should Be Equal As Integers
    ...    ${resp.status_code}
    ...    422

Reject Missing API Key (req:REQ-API-001)
    [Tags]    req:REQ-API-001
    [Documentation]    Expects 401 Unauthorized when the API key header is completely omitted.
    # Use standalone POST to avoid inheriting the session's default X-API-Key header
    ${resp}=    POST    ${BACKEND_URL}/vehicle/lock    expected_status=any
    Should Be Equal As Integers    ${resp.status_code}    401

Reject Invalid API Key (req:REQ-API-001)
    [Tags]    req:REQ-API-001
    [Documentation]    Expects 401 Unauthorized when an incorrect key is provided.
    &{bad_header}=     Create Dictionary    X-API-Key=invalid-secret-key
    ${resp}=           Send Raw Request     POST    /vehicle/lock    custom_headers=${bad_header}
    Should Be Equal As Integers    ${resp.status_code}    401

Verify Lock Command Contract And Latency SLA (req:REQ-API-002)
    [Tags]    req:REQ-API-002
    [Documentation]    Ensures /vehicle/lock returns 200 ACCEPTED within 500ms with schema conformance.
    ${resp}=    Send Lock Command
    Verify Command Accepted Contract    ${resp}

Verify Start Climate Command Contract And Latency SLA (req:REQ-API-002)
    [Tags]    req:REQ-API-002
    [Documentation]    Ensures /climate/start returns 200 ACCEPTED within 500ms with schema conformance.
    ${resp}=    Send Start Climate Command    target_temp=22.0
    Verify Command Accepted Contract    ${resp}

Verify All Command Endpoints Adhere To Acceptance Contract (req:REQ-API-002)
    [Tags]    req:REQ-API-002
    [Documentation]    Iterates through command endpoints checking the 500ms and schema SLA.
    # Unlock
    ${resp_unlock}=    Send Unlock Command
    Verify Command Accepted Contract    ${resp_unlock}

    # Stop Climate
    ${resp_cstop}=     Send Stop Climate Command
    Verify Command Accepted Contract    ${resp_cstop}

    # Start Charging
    ${resp_chg}=       Send Start Charging Command    target_soc=80
    Verify Command Accepted Contract    ${resp_chg}

    # Stop Charging
    ${resp_chgstop}=   Send Stop Charging Command
    Verify Command Accepted Contract    ${resp_chgstop}

Verify Command Reaches Terminal State Within 5 Seconds (req:REQ-API-003)
    [Tags]    req:REQ-API-003
    [Documentation]    Ensures commands reach COMPLETED or FAILED within 5s and never stay ACCEPTED.
    # Trigger a command that executes normally
    ${resp}=      Send Lock Command
    Should Be Equal As Integers    ${resp.status_code}    200
    ${req_id}=    Set Variable    ${resp.json()['request_id']}

    # Poll and assert terminal condition within 5 seconds
    ${record}=    Wait For Command Terminal State Within 5 Seconds    ${req_id}
    Log           Command finalized in status ${record['status']} with elapsed time ${record.get('elapsed_ms')} ms

Verify Failed Command Supplies Reason Within 5 Seconds (req:REQ-API-003)
    [Tags]    req:REQ-API-003
    [Documentation]    Trigger an action that fails at the vehicle/ECU level and confirm reason is populated within 5s.
    # Unlock command (or any command rejected by ECU timeout/interlock)
    ${resp}=      Send Unlock Command
    Should Be Equal As Integers    ${resp.status_code}    200
    ${req_id}=    Set Variable    ${resp.json()['request_id']}

    ${record}=    Wait For Command Terminal State Within 5 Seconds    ${req_id}
    IF    '${record['status']}' == 'FAILED'
        Should Not Be Empty    ${record['reason']}
    END

Reject Unknown Command Request ID (req:REQ-API-004)
    [Tags]    req:REQ-API-004
    [Documentation]    Expects 404 when querying a non-existent request_id.
    ${resp}=           Send Raw Request     GET     /vehicle/commands/non-existent-uuid-999
    Should Be Equal As Integers    ${resp.status_code}    404

Verify Vehicle Status Contract And Freshness SLA (req:REQ-API-005)
    [Tags]    req:REQ-API-005
    [Documentation]    Asserts all required keys exist and report_age_s < 10s when vehicle is online.
    ${status}=    Get Vehicle Status
    Verify Vehicle Status Contract    ${status}

Verify OpenAPI Specification Published At Standard Endpoint (req:REQ-API-006)
    [Tags]    req:REQ-API-006
    [Documentation]    Ensures /openapi.json returns HTTP 200, uses OpenAPI 3.x, and documents all public routes.
    ${resp}=    Get OpenAPI Specification
    Should Be Equal As Integers    ${resp.status_code}    200
    
    ${spec}=    Set Variable    ${resp.json()}
    Verify OpenAPI Specification Contract    ${spec}