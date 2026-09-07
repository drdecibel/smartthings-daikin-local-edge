# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 drdecibel

LUA ?= lua5.3
LUAC ?= luac5.3

.PHONY: check syntax test manifest privacy package build-only create-channel enroll-channel assign-driver install logcat

# Everything that can be verified without a hub or an adapter.
check: syntax test manifest privacy

syntax:
	find src test -name '*.lua' -print0 | xargs -0 -n1 $(LUAC) -p

test:
	$(LUA) test/test_core.lua
	$(LUA) test/test_driver.lua

manifest:
	python3 tools/check-manifest.py

privacy:
	sh tools/privacy-scan.sh

# Build the package without uploading it, into a directory outside the repo.
build-only:
	smartthings edge:drivers:package . --build-only ../daikin-local-edge.zip

package:
	smartthings edge:drivers:package .

create-channel:
	smartthings edge:channels:create

enroll-channel:
	smartthings edge:channels:enroll

assign-driver:
	smartthings edge:channels:assign

install:
	smartthings edge:drivers:install

logcat:
	smartthings edge:drivers:logcat
