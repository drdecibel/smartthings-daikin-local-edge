# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 drdecibel

.PHONY: test package create-channel enroll-channel assign-driver install logcat

test:
	lua test/test_core.lua

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
