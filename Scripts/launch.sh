#!/bin/bash
set -euo pipefail

# Simple script to launch QuotaKit (kills existing instance first)
# Usage: ./Scripts/launch.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$PROJECT_ROOT/QuotaKit.app"

echo "==> Killing existing QuotaKit instances"
pkill -x QuotaKit || pkill -f QuotaKit.app || true
pkill -x CodexBar || pkill -f CodexBar.app || true
sleep 0.5

if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: QuotaKit.app not found at $APP_PATH"
    echo "Run ./Scripts/package_app.sh first to build the app"
    exit 1
fi

echo "==> Launching QuotaKit from $APP_PATH"
open -n "$APP_PATH"

# Wait a moment and check if it's running
sleep 1
if pgrep -x QuotaKit > /dev/null; then
    echo "OK: QuotaKit is running."
else
    echo "ERROR: App exited immediately. Check crash logs in Console.app (User Reports)."
    exit 1
fi
