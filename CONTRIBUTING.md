# Contributing

Bug reports, test results and pull requests are welcome.

## Before opening an issue

- Confirm that the adapter is a BRP069B4x-family device.
- Confirm that `/common/basic_info`, `/aircon/get_control_info` and `/aircon/get_sensor_info` return `ret=OK` on the local network.
- Check that the SmartThings hub and adapter can communicate over UDP port 30050 and HTTP port 80.
- Run `smartthings edge:drivers:logcat` while reproducing the problem.

## Privacy

Never post an unedited `/common/basic_info` response. Remove or mask:

- MAC addresses
- UUIDs and device IDs
- Wi-Fi SSIDs
- IP addresses, when not needed for diagnosis
- Password or account-related fields

The fields `ver`, `adp_kind`, `pv`, `cpv`, mode values and sensor values are normally useful for compatibility testing.

## Pull requests

1. Keep LAN communication local and avoid new cloud dependencies.
2. Do not log full Daikin responses.
3. Preserve all mandatory `set_control_info` parameters.
4. Add or update a core test for behavior changes.
5. Run `lua test/test_core.lua` before submitting.
