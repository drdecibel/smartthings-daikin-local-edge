#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 drdecibel
"""Validate config.yml and the device profiles against the constraints the
SmartThings upload API enforces, and against the driver source.

`edge:drivers:package --build-only` does not check any of this; the API only
rejects it at upload time, so it is checked here instead.
"""

from pathlib import Path
import re
import sys

import yaml

# Enforced by the driver upload API.
PACKAGE_KEY_PATTERN = re.compile(r"^[a-zA-Z0-9 _/\-()\[\]{}.]{1,36}$")

ROOT = Path(__file__).resolve().parent.parent
problems = []


def fail(message):
    problems.append(message)


def load(path):
    with path.open(encoding="utf-8") as stream:
        return yaml.safe_load(stream)


config = load(ROOT / "config.yml")

for field in ("name", "packageKey", "description", "permissions"):
    if not config.get(field):
        fail(f"config.yml is missing {field}")

package_key = config.get("packageKey", "")
if not PACKAGE_KEY_PATTERN.match(package_key):
    fail(
        f"packageKey {package_key!r} ({len(package_key)} characters) does not match "
        f"the API pattern {PACKAGE_KEY_PATTERN.pattern}"
    )

for permission in config.get("permissions", {}):
    if permission not in ("lan", "discovery", "zigbee", "zwave", "matter", "ble"):
        fail(f"config.yml declares an unexpected permission: {permission}")

profiles = {}
for path in sorted((ROOT / "profiles").glob("*.yml")):
    profile = load(path)
    name = profile.get("name")
    if not name:
        fail(f"{path.name} has no profile name")
        continue
    profiles[name] = profile

    for component in profile.get("components", []):
        if not component.get("id"):
            fail(f"{path.name} has a component without an id")
        if not component.get("capabilities"):
            fail(f"{path.name} component {component.get('id')} declares no capabilities")

source = (ROOT / "src" / "init.lua").read_text(encoding="utf-8")
constants = (ROOT / "src" / "constants.lua").read_text(encoding="utf-8")

referenced = re.search(r'C\.PROFILE\s*=\s*"([^"]+)"', constants)
if not referenced:
    fail("src/constants.lua does not define C.PROFILE")
elif referenced.group(1) not in profiles:
    fail(
        f"src/constants.lua uses profile {referenced.group(1)!r}, "
        f"but only {sorted(profiles)} exist"
    )

for name, profile in profiles.items():
    for component in profile.get("components", []):
        for capability in component.get("capabilities", []):
            capability_id = capability.get("id")
            if capability_id and f"capabilities.{capability_id}" not in source:
                fail(
                    f"{name} component {component['id']} declares capability "
                    f"{capability_id}, which src/init.lua never references"
                )

if problems:
    for problem in problems:
        print(f"MANIFEST: {problem}")
    sys.exit(1)

print(f"Manifest check: packageKey {package_key!r} "
      f"({len(package_key)} characters) and {len(profiles)} profile(s) are valid.")
