SHELL := /bin/bash

.PHONY: build check docs-list format lint release restart start start-debug start-release stop test test-affected test-full test-live test-smoke test-tty

start:
	./Scripts/compile_and_run.sh

start-debug:
	./Scripts/compile_and_run.sh

start-release:
	./Scripts/package_app.sh release
	pkill -x QuotaKit || pkill -f QuotaKit.app || true
	open -n "$(CURDIR)/QuotaKit.app"

restart: start

stop:
	pkill -x QuotaKit || pkill -f QuotaKit.app || true

check lint:
	./Scripts/lint.sh lint

format:
	./Scripts/lint.sh format

docs-list:
	node Scripts/docs-list.mjs

build:
	swift build

test:
	./Scripts/test.sh

# `test` remains the complete local safety gate. These faster tiers are explicit
# opt-ins for the daily development and upstream-triage loop.
test-full: test

test-smoke:
	./Scripts/test_tier.sh smoke

test-affected:
	./Scripts/test_tier.sh affected

test-tty:
	CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1 swift test --filter TTYIntegrationTests

test-live:
	LIVE_TEST=1 CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS=1 swift test --filter LiveAccountTests

release:
	./Scripts/package_app.sh release
