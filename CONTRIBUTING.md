# Contributing

Bug reports, test results and pull requests are welcome. Reports from adapters
other than BRP069B4x are especially useful.

## Before opening an issue

- Confirm the adapter model and firmware version (the `ver` field).
- Confirm that `/common/basic_info`, `/aircon/get_control_info` and
  `/aircon/get_sensor_info` answer with `ret=OK` on the local network.
- Confirm that the hub and the adapter can reach each other over UDP port 30050
  and HTTP port 80, with no client isolation between them.
- Run `smartthings edge:drivers:logcat` while reproducing the problem.

## Privacy

Never post an unedited `/common/basic_info` response. It contains the MAC
address, the Wi-Fi SSID and cloud account fields. Remove or mask:

- MAC addresses
- UUIDs and device identifiers
- Wi-Fi SSIDs
- IP addresses, when they are not needed for the diagnosis
- Password and account related fields (`id`, `pw`, `lpw_flag`)

The fields `ver`, `adp_kind`, `pv`, `cpv`, mode values and sensor values are
normally useful for compatibility testing and safe to share.

`tools/privacy-scan.sh` runs on every push and fails the build if a tracked file
contains an address, MAC address, credential or account identifier. Run it
locally before opening a pull request.

## Running the checks

```sh
make check
```

That runs the Lua syntax check, both test suites and the privacy scan. The
tests need only a Lua 5.3 or 5.4 interpreter; no hub and no adapter are
involved.

## Pull requests

1. Keep all communication local. Do not add cloud dependencies.
2. Do not log complete Daikin responses, addresses or identifiers.
3. Keep sending the full mandatory parameter set to `/aircon/set_control_info`.
   A command must never reset a value the user did not change.
4. Preserve the placeholder target temperatures for dry (`M`) and fan-only
   (`--`) modes.
5. Add or update a test for every behaviour change. Protocol translation belongs
   in `test/test_core.lua`; request, command, discovery and lifecycle behaviour
   belongs in `test/test_driver.lua`.
6. Run `make check` before submitting.
7. Contributions are accepted under GPL-3.0-or-later.
