*** Settings ***
Resource    ../resources/adb.resource

*** Test Cases ***
Realistic VHAL Snapshot Matches
    Assert Gateway VHAL Charging State    CHARGING
    Assert Gateway VHAL Charging Target    80
    Assert Gateway VHAL Charging SOC    44
    Assert Gateway Charging State    CHARGING    80    44
    Assert Body ECU Online
    Run Keyword And Expect Error    *does not match*    Assert Gateway Charging State    IDLE
    Run Keyword And Expect Error    *does not match*    Assert Body ECU Offline

*** Keywords ***
Adb Shell
    [Arguments]    @{command}
    RETURN    VHAL property snapshot (vendor.oem.vhal@2.0)\n${SPACE}${SPACE}last_sync: 2026-09-19T12:22:25.921Z${SPACE}${SPACE}seq: 3${SPACE}${SPACE}body_ecu_online: True\n${SPACE}${SPACE}Property: 0x11400F0F (EV_CHARGE_STATE${SPACE}${SPACE}${SPACE}${SPACE}${SPACE}${SPACE}${SPACE}${SPACE} ) value=CHARGING\n${SPACE}${SPACE}Property: 0x11400F10 (EV_CHARGE_TARGET${SPACE}${SPACE}${SPACE}${SPACE}${SPACE}${SPACE}${SPACE}${SPACE}) value=80\n${SPACE}${SPACE}Property: 0x11600309 (EV_BATTERY_LEVEL${SPACE}${SPACE}${SPACE}${SPACE}${SPACE}${SPACE}${SPACE}${SPACE}) value=44
