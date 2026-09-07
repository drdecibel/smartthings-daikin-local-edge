# Changelog

All notable changes to this project will be documented in this file.

## 0.2.0 - 2026-09-07

First version intended for a public SmartThings channel. Independent review of
the 0.1.0 implementation against the SmartThings Edge documentation and the
published Daikin legacy local API documentation found several protocol defects,
which are fixed here.

### Fixed

- `packageKey` shortened to `io.github.drdecibel.daikin.local`. The upload API
  limits it to 36 characters (`^[a-zA-Z0-9 _/\-()\[\]{}.]{1,36}$`) and rejected
  the previous 44-character key. Nothing had been published under the old key.
- Dry mode and fan-only mode now send the placeholder target temperature the
  adapter requires (`stemp=M` and `stemp=--`). Sending a number made the adapter
  refuse the whole request with `ret=PARAM NG`, so those two modes could not be
  selected at all.
- Target humidity is now taken from the stored per-mode value (`dh1`..`dh7`)
  instead of the currently active `shum`, so switching modes no longer discards
  the humidity setting of the mode being entered.
- Thermostat setpoints arriving in Fahrenheit are converted, rounded to 0.5 C
  and clamped to the documented Daikin ranges. A Fahrenheit location previously
  sent values such as 72 straight to the adapter.
- The compressor sentinel value 999 is no longer read as a running compressor,
  so an idle unit no longer reports heating or cooling.
- Fan-only mode reports the operating state "fan only", and auto mode derives
  heating or cooling from the indoor temperature instead of always reporting
  idle.
- A deleted device can be discovered again without restarting the driver.
- A single failed poll no longer marks the device offline; three consecutive
  failures do.

### Added

- Support for indoor units that expose the louver as two axes (`f_dir_ud` and
  `f_dir_lr`) instead of the combined `f_dir` field.
- Automatic recovery when the adapter moves to another address: after repeated
  failures the driver broadcasts again and updates the stored address.
- Optional parameters are only sent when the adapter reports them, so units
  without fan-rate or louver control are not sent unsupported parameters.
- Heating and cooling setpoint ranges are published so the app slider matches
  what the adapter accepts.
- Turbo fan speed, mapping the highest Daikin fan level instead of folding it
  into high.
- `test/test_driver.lua`, which exercises the request, command, discovery and
  lifecycle paths against stand-ins for the SmartThings Edge runtime.
- `tools/privacy-scan.sh`, run in CI, which fails the build if a tracked file
  contains an address, MAC address, credential or account identifier.
- `tools/check-manifest.py`, run in CI, which checks config.yml against the
  constraints the upload API enforces and against the driver source. The CLI
  build step does not check any of them.

### Changed

- Query strings are built inside the driver in the documented Daikin parameter
  order, removing a dependency on an undocumented runtime library.
- Timer handles are stored on the device and cancelled explicitly instead of
  iterating the internal timer table of the device thread.
- Selecting auto keeps the auto variant the adapter already uses (0, 1 or 7)
  rather than always sending 0.
- Adjusting a setpoint while the unit is in auto now changes the single auto
  target temperature instead of forcing the unit out of auto.
- The configured address preference is validated, so the driver cannot be
  pointed at an unintended HTTP target.
- Everything written to the driver log passes through an address filter.
- Numeric parsing rejects Daikin sentinels and Lua-only number forms.
- Percent decoding matches the adapter encoding: `+` is a literal plus.
- The validation workflow prefers Lua 5.3, which is the Edge runtime version,
  and also runs the driver tests and the privacy scan.

## 0.1.0 - 2026-09-06

- Initial community implementation. Never published to a SmartThings channel.
- Local UDP discovery and HTTP control for BRP069B4x adapters.
- Power, operating mode, heating and cooling setpoints, fan speed and swing.
- Indoor and outdoor temperature and compressor-based operating state.
- Configurable polling interval and optional IP or hostname override.
- Automated Lua, YAML and core-behaviour validation with GitHub Actions.
- GPL-3.0-or-later licensing with attribution to `drdecibel`.
