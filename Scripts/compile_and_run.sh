#!/usr/bin/env bash
# Reset CodexBar: kill running instances, build, test, package, relaunch, verify.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${ROOT_DIR}/CodexBar.app"
APP_PROCESS_PATTERN="CodexBar.app/Contents/MacOS/CodexBar"
DEBUG_PROCESS_PATTERN="${ROOT_DIR}/.build/debug/CodexBar"
RELEASE_PROCESS_PATTERN="${ROOT_DIR}/.build/release/CodexBar"

log()  { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

run_step() {
  local label="$1"; shift
  log "==> ${label}"
  if ! "$@"; then
    fail "${label} failed"
  fi
}

kill_claude_probes() {
  # CodexBar spawns `claude /usage` + `/status` in a PTY; if we kill the app mid-probe we can orphan them.
  pkill -f "claude (/status|/usage) --allowed-tools" 2>/dev/null || true
  sleep 0.2
  pkill -9 -f "claude (/status|/usage) --allowed-tools" 2>/dev/null || true
}

kill_all_codexbar() {
  for _ in {1..10}; do
    pkill -f "${APP_PROCESS_PATTERN}" 2>/dev/null || true
    pkill -f "${DEBUG_PROCESS_PATTERN}" 2>/dev/null || true
    pkill -f "${RELEASE_PROCESS_PATTERN}" 2>/dev/null || true
    pkill -x "CodexBar" 2>/dev/null || true
    # If nothing remains, stop early.
    if ! pgrep -f "${APP_PROCESS_PATTERN}" >/dev/null 2>&1 \
      && ! pgrep -f "${DEBUG_PROCESS_PATTERN}" >/dev/null 2>&1 \
      && ! pgrep -f "${RELEASE_PROCESS_PATTERN}" >/dev/null 2>&1 \
      && ! pgrep -x "CodexBar" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.3
  done
}

# 1) Kill all running CodexBar instances (debug, release, bundled).
log "==> Killing existing CodexBar instances"
kill_all_codexbar
kill_claude_probes

# 2) Build, test, package.
run_step "swift build" swift build -q
run_step "swift test" swift test -q
run_step "package app" "${ROOT_DIR}/scripts/package_app.sh"

# 3) Launch the packaged app.
run_step "launch app" open "${APP_BUNDLE}"

# 4) Verify the app stays up for at least 1s.
sleep 1
if pgrep -f "${APP_PROCESS_PATTERN}" >/dev/null 2>&1; then
  log "OK: CodexBar is running."
else
  fail "App exited immediately. Check crash logs in Console.app (User Reports)."
fi
