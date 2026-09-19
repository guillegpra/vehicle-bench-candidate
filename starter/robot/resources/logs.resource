*** Settings ***
Library     OperatingSystem
Library     String
Library     ../libraries/log_validation.py
Resource    adb.resource


*** Variables ***
${BACKEND_DLT}     ${CURDIR}/../../../traces/logs/backend.dlt
${GATEWAY_DLT}     ${CURDIR}/../../../traces/logs/tcu.dlt
${BODY_DLT}        ${CURDIR}/../../../traces/logs/body_ecu.dlt


*** Keywords ***
Get Backend DLT Log
    ${log}=    Get File    ${BACKEND_DLT}
    RETURN    ${log}


Get Gateway DLT File
    ${log}=    Get File    ${GATEWAY_DLT}
    RETURN    ${log}


Get Body ECU DLT Log
    ${log}=    Get File    ${BODY_DLT}
    RETURN    ${log}


Get Telematics Logcat
    ${log}=    Adb Shell    logcat -d TelematicsSvc:I '*:S'
    RETURN    ${log}


Assert Request Traceable Across All Logs
    [Arguments]    ${request_id}    ${command}

    ${backend}=    Get Backend DLT Log
    ${gateway}=    Get Gateway DLT File
    ${body}=       Get Body ECU DLT Log
    ${logcat}=     Get Telematics Logcat

    Should Contain
    ...    ${backend}
    ...    req=${request_id}
    ...    msg=Request ${request_id} missing from backend DLT

    Should Contain
    ...    ${gateway}
    ...    req=${request_id}
    ...    msg=Request ${request_id} missing from gateway DLT

    Should Contain
    ...    ${body}
    ...    req=${request_id}
    ...    msg=Request ${request_id} missing from Body ECU DLT

    Should Contain
    ...    ${logcat}
    ...    id=${request_id}
    ...    msg=Request ${request_id} missing from TelematicsSvc logcat

Assert No New Gateway Errors Since
    [Arguments]    ${before}

    ${after}=    Get Gateway DLT File
    Assert No New Gateway Errors    ${before}    ${after}
