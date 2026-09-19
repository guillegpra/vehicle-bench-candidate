*** Settings ***
Documentation    Docker command bindings for managing the Body ECU container.
Library          Process
Library          String
Variables        ../variables/bench_local.py

*** Keywords ***

Stop Body ECU Container
    ${result}=    Run Process
    ...    docker
    ...    compose
    ...    stop
    ...    body-ecu
    Should Be Equal As Integers    ${result.rc}    0


Start Body ECU Container
    ${result}=    Run Process
    ...    docker
    ...    compose
    ...    start
    ...    body-ecu
    Should Be Equal As Integers    ${result.rc}    0