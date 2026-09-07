# Daikin Local for SmartThings

[![Validate driver](https://github.com/drdecibel/smartthings-daikin-local-edge/actions/workflows/validate.yml/badge.svg)](https://github.com/drdecibel/smartthings-daikin-local-edge/actions/workflows/validate.yml)
[![License: GPL v3+](https://img.shields.io/badge/License-GPL%20v3%2B-blue.svg)](LICENSE)

> Community project. Not affiliated with or endorsed by Daikin, Samsung or SmartThings.

Copyright © 2026 [drdecibel](https://github.com/drdecibel).

Professional local SmartThings Edge integration for Daikin heat pumps using BRP069B4x Wi-Fi adapters. The heat pump can remain available in ONecta, while SmartThings communicates directly over the LAN without depending on the ONecta cloud, API quota or credentials.

## Project status

Version `0.1.0` is ready for installation and initial hardware testing. The API parsing and control-state construction are covered by automated tests, but every Daikin indoor-unit variant cannot be tested by the maintainer. Keep the original Daikin controller or official app available while evaluating the driver.

## Supported functions

- Automatic LAN discovery over UDP port 30050
- Power, auto/heat/cool/dry/fan-only modes
- Heating and cooling setpoints
- Auto/low/medium/high fan speed
- Fixed/vertical/horizontal/all-direction swing
- Indoor and outdoor temperature
- Compressor-based operating state where the adapter reports it
- Configurable polling interval and optional fixed IP/hostname override

Tested against the API format reported by a BRP069B4x adapter with `adp_kind=3` and firmware family `4_2_303`. No device identifiers are included in this project.

## Prerequisites

- A SmartThings hub capable of running Edge drivers
- The hub and Daikin adapter on the same LAN/VLAN
- Client isolation disabled between them
- UDP broadcast to port 30050 and HTTP port 80 allowed
- A DHCP reservation for the Daikin adapter is strongly recommended

## Install with SmartThings CLI

1. Install and authenticate the current SmartThings CLI.
2. Create a developer channel and enroll your hub (one-time setup):

   ```sh
   smartthings edge:channels:create
   smartthings edge:channels:enroll
   ```

3. From this directory, package the driver, assign it to the channel, and install it:

   ```sh
   smartthings edge:drivers:package .
   smartthings edge:channels:assign
   smartthings edge:drivers:install
   ```

4. In the SmartThings app, choose **Add device → Scan nearby**.
5. Open the new Daikin device and test **Refresh**, power, heat mode, and a small setpoint change.
6. If discovery works but the address later changes, reserve the address in DHCP. You can also enter an IP address or local hostname under the device's **Settings**.

The CLI prompts you to select the channel, driver and hub when needed. A public invitation link can only be generated after the driver has been uploaded to a SmartThings developer channel.

## Important behavior

- Sending a heating setpoint selects Daikin heat mode; sending a cooling setpoint selects cool mode. This is necessary because this Daikin API exposes one writable active setpoint.
- SmartThings has no portable standard value for Daikin's `B`/quiet fan setting, so a reported quiet setting is displayed as **Low**. The driver does not select quiet mode.
- All set operations first read the current control state and then send all six parameters required by `/aircon/set_control_info`: `pow`, `mode`, `stemp`, `shum`, `f_rate`, and `f_dir`.
- The driver logs request paths and errors, but never logs full Daikin responses containing network identifiers.

## Validation

Run the local core tests with Lua 5.4:

```sh
lua test/test_core.lua
```

Every push and pull request also runs `.github/workflows/validate.yml`, which checks Lua syntax, core behavior and the YAML files.

## Troubleshooting

- **No device found:** verify that the hub and adapter are on the same broadcast domain and that UDP broadcast is allowed.
- **Device is offline:** confirm that `http://DAIKIN-IP/aircon/get_sensor_info` returns `ret=OK` from the LAN, then set the same address in device Settings.
- **Commands fail after an address change:** update the DHCP reservation or host override.

## Acknowledgements

The API behavior and mappings are based on established community work around the Daikin BRP069 local API, including [bendews/smartthings-daikin-wifi](https://github.com/bendews/smartthings-daikin-wifi), [ael-code/daikin-control](https://github.com/ael-code/daikin-control), and the [Home Assistant Daikin integration](https://www.home-assistant.io/integrations/daikin/).

## License

Copyright © 2026 [drdecibel](https://github.com/drdecibel).

This project is free software licensed under the [GNU General Public License v3.0 or later](LICENSE). If you distribute copies or modified versions, you must preserve the license and copyright notices, provide the corresponding source code, and license the distributed derivative work under GPL-compatible terms.
