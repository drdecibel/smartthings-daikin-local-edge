# Daikin Local for SmartThings

[![Validate driver](https://github.com/drdecibel/smartthings-daikin-local-edge/actions/workflows/validate.yml/badge.svg)](https://github.com/drdecibel/smartthings-daikin-local-edge/actions/workflows/validate.yml)
[![License: GPL v3+](https://img.shields.io/badge/License-GPL%20v3%2B-blue.svg)](LICENSE)

> Community project. Not affiliated with, endorsed by or supported by Daikin, Samsung or SmartThings.

Copyright © 2026 [drdecibel](https://github.com/drdecibel).

A SmartThings Edge driver that controls Daikin heat pumps directly over the local
network through a BRP069B4x Wi-Fi adapter. The heat pump keeps working in ONecta;
SmartThings talks to the adapter over the LAN and needs no ONecta account, cloud
token or API quota.

## Project status

**Beta.** The driver is complete, reviewed against the published SmartThings Edge
and Daikin local API documentation, and covered by 213 automated checks, but it has
not yet been exercised against a physical heat pump. Treat every command as unproven
until the maturity note below says otherwise, and keep the original Daikin controller
or the ONecta app available while you evaluate it.

| | |
|---|---|
| Driver version | 0.2.0 |
| Verified by | automated tests and documentation review |
| Verified on hardware | not yet |
| Adapter family targeted | BRP069B4x, `adp_kind=3`, firmware family `4_2_303` |

## Installation

### Enrol from a browser (recommended)

The public beta channel invitation is not published yet. It will be linked here and
in the [releases](https://github.com/drdecibel/smartthings-daikin-local-edge/releases)
as soon as the channel exists. The steps will then be:

1. Open the Daikin Local Edge invitation link.
2. Sign in with the Samsung account that owns your hub.
3. Enrol the hub you want to run the driver on.
4. Install **Daikin Local Heat Pump** from **Available Drivers**.
5. Open the SmartThings app.
6. Choose **Add device → Scan nearby**.

### Install with the SmartThings CLI (advanced)

Requires Node.js and the [SmartThings CLI](https://github.com/SmartThingsCommunity/smartthings-cli).

```sh
smartthings edge:channels:create
smartthings edge:channels:enroll
smartthings edge:drivers:package .
smartthings edge:channels:assign
smartthings edge:drivers:install
```

Then choose **Add device → Scan nearby** in the SmartThings app. The CLI prompts for
the channel, driver and hub where it needs them.

## Requirements

- A SmartThings hub that runs Edge drivers
- The hub and the Daikin adapter on the same LAN or VLAN, in the same broadcast domain
- No client isolation between the hub and the adapter
- Outgoing UDP broadcast to port 30050 and HTTP to port 80 allowed
- A DHCP reservation for the adapter is strongly recommended

## What the driver does

| SmartThings control | Daikin equivalent |
|---|---|
| Power | `pow` |
| Mode: auto, heat, cool, dry, fan only | `mode` 0/1/7, 4, 3, 2, 6 |
| Heating and cooling setpoint | `stemp`, stored per mode in `dt3` and `dt4` |
| Fan: auto, low, medium, high, turbo | `f_rate` A, 3, 5, 6, 7 |
| Swing: fixed, vertical, horizontal, all | `f_dir` 0, 1, 2, 3 |
| Indoor temperature | `htemp` |
| Outdoor temperature | `otemp` |
| Operating state | `mode` combined with `cmpfreq` |
| Refresh | `/aircon/get_control_info` and `/aircon/get_sensor_info` |

Discovery is a single UDP broadcast of `DAIKIN_UDP/common/basic_info` to port 30050.
The hub address is never needed, and the adapter address is stored on the device
rather than in this repository.

## How the driver talks to the adapter

- `/aircon/set_control_info` treats all of `pow`, `mode`, `stemp`, `shum`, `f_rate`
  and `f_dir` as authoritative. Every write therefore reads the current control state
  first and sends the complete set back, so a fan change never resets the temperature
  and a mode change never resets the fan.
- The adapter stores the last used temperature, humidity, fan rate and louver
  position for each mode in `dt1`–`dt7`, `dh1`–`dh7`, `dfr1`–`dfr7` and `dfd1`–`dfd7`.
  Switching modes restores those values, matching what the physical remote does.
- Dry mode takes `stemp=M` and fan-only takes `stemp=--`. Sending a number in those
  modes makes the adapter reject the whole request with `ret=PARAM NG`.
- Sending a heating setpoint selects heat and sending a cooling setpoint selects cool,
  because the API exposes a single writable setpoint that always belongs to the active
  mode. In auto the unit has one target temperature, so the driver adjusts it in place
  instead of taking the unit out of auto.
- SmartThings sends setpoints as a bare number with no unit. Values of 40 and above
  are treated as Fahrenheit and converted, matching the SmartThings reference
  thermostat drivers. Setpoints are rounded to 0.5 °C and clamped to the documented
  Daikin ranges (heat 10–31 °C, cool 18–33 °C).
- Indoor units that expose the louver as two axes (`f_dir_ud` and `f_dir_lr`) are
  handled as well as the combined `f_dir` field.
- `cmpfreq` reports 0 or the sentinel 999 when the compressor is not running, so a
  powered-on unit that is not actively heating or cooling reports **idle**.
- A single failed poll does not take the device offline; three consecutive failures
  do. After that the driver broadcasts again to find an adapter that moved to another
  address, unless you pinned the address in the device settings.
- The driver logs request paths, error codes and counters. It never logs a complete
  adapter response, and it removes anything that looks like a local address from the
  text it does log.

## Settings

| Setting | Purpose |
|---|---|
| Fixed IP or hostname | Optional. Overrides the discovered address. Leave empty unless discovery is unreliable. |
| Refresh interval | How often the driver polls while idle: 1, 5, 10 or 15 minutes. |

Hostnames are resolved by the hub. An IP address with a DHCP reservation is the most
reliable option; mDNS names ending in `.local` are not resolved.

## Known limitations

- Not yet verified on physical hardware. See **Project status**.
- Only the BRP069B4x family is targeted. Other BRP069 adapters use the same legacy
  API and may work, but no wider compatibility is claimed.
- Adapter firmware **2.8.0 and newer replaces this API** with a different JSON
  interface (`/dsiot/multireq`). Updating the adapter firmware can remove local
  control entirely.
- Daikin quiet mode (`f_rate=B`) has no portable SmartThings value, so it is displayed
  as **Low**. The driver never selects quiet mode.
- Daikin fan level 2 (`f_rate=4`) is displayed as **Low**; SmartThings offers four
  speeds where Daikin has five.
- Humidity, powerful/econo/streamer modes, holiday mode, timers and energy counters
  are not exposed.
- In auto mode the unit has a single target temperature, so the heating and cooling
  setpoints show the same value.
- The legacy Daikin API is unauthenticated HTTP. Use it only on a trusted network.

## Development

```sh
make check
```

runs the Lua syntax check, both test suites and the privacy scan. Individually:

```sh
lua5.3 test/test_core.lua
lua5.3 test/test_driver.lua
sh tools/privacy-scan.sh
```

`test/test_core.lua` covers the protocol translation, and `test/test_driver.lua`
exercises the request, command, discovery and lifecycle paths against stand-ins for
the SmartThings Edge runtime. Every push and pull request runs the same checks through
[`.github/workflows/validate.yml`](.github/workflows/validate.yml).

To build the package without uploading it:

```sh
make build-only
```

## Troubleshooting

- **No device found.** Confirm that the hub and the adapter share a broadcast domain
  and that UDP broadcast is allowed between them. Confirm the adapter answers
  `http://ADAPTER-ADDRESS/common/basic_info` from a computer on the same network.
- **Device shows as offline.** Check that `http://ADAPTER-ADDRESS/aircon/get_sensor_info`
  returns `ret=OK` from the LAN, then enter that address under the device **Settings**.
- **Commands stop working after a while.** The adapter probably received a new DHCP
  lease. Add a DHCP reservation, or set the address in the device settings.
- **A command has no effect.** Run `smartthings edge:drivers:logcat` and look for
  `ret=PARAM NG`, which means the adapter refused the parameters. Please open an issue
  with the sanitised log.

Never paste an unedited `/common/basic_info` response into an issue: it contains the
MAC address, the Wi-Fi SSID and cloud account fields. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Acknowledgements

The protocol behaviour was verified against published community documentation of the
Daikin legacy local API, in particular
[ael-code/daikin-control](https://github.com/ael-code/daikin-control),
[daimik/Daikin-BRP069C4x-Local-API](https://github.com/daimik/Daikin-BRP069C4x-Local-API),
[pydaikin](https://github.com/fredrike/pydaikin) and the
[Home Assistant Daikin integration](https://www.home-assistant.io/integrations/daikin/).

## License

Copyright © 2026 [drdecibel](https://github.com/drdecibel).

This project is free software licensed under the
[GNU General Public License v3.0 or later](LICENSE). If you distribute copies or
modified versions, you must preserve the license and copyright notices, provide the
corresponding source code, and license the distributed derivative work under
GPL-compatible terms.
