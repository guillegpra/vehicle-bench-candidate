*** Settings ***
Resource    ../resources/rest_api.resource
Resource    ../resources/adb.resource
Suite Setup    Open Backend Session

*** Test Cases ***
Backend Is Reachable
    [Tags]    smoke    req:REQ-API-005
    ${status}=    Get Vehicle Status
    Should Be Equal As Strings    ${status}[vin]    WVGZZZ5NZTW000042

Gateway Is Reachable Over Adb
    [Tags]    smoke    req:REQ-ADB-001

    ${model}=    Get Android Property    ro.product.model
    Should Be Equal As Strings    ${model}    TCU-GW-2

    ${boot}=    Get Android Property    sys.boot_completed
    Should Be Equal As Strings    ${boot}    1

    ${service}=    Get Android Property    init.svc.telematics
    Should Be Equal As Strings    ${service}    running

Verify Gateway ADB TCP Transport
    [Tags]    req:REQ-ADB-001

    ${result}=    Run Process
    ...    adb
    ...    -s
    ...    ${ADB_SERIAL}
    ...    get-state

    Should Be Equal As Integers    ${result.rc}    0
    Should Contain    ${result.stdout}    device