#!/usr/bin/env bash
#
# Compatibility wrapper for the canonical QuotaKit iOS TestFlight lane.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

echo "==> Scripts/upload_ios_testflight.sh is deprecated; using Scripts/ios_testflight_xcode.sh"
exec "$ROOT/Scripts/ios_testflight_xcode.sh" "$@"
