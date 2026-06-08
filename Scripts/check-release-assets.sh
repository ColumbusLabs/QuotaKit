#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [[ -f "$ROOT/.mac-release.env" ]]; then
  source "$ROOT/.mac-release.env"
fi
source "$ROOT/Scripts/sparkle_helpers.sh"

TAG=${1:-$(git describe --tags --abbrev=0)}
APP_NAME="${MAC_RELEASE_APP_NAME:-QuotaKit}"
ARTIFACT_PREFIX="${MAC_RELEASE_ARTIFACT_PREFIX:-${APP_NAME}-macos-[A-Za-z0-9_+-]+-}"

check_assets "$TAG" "$ARTIFACT_PREFIX"

echo "Release $TAG has the ${APP_NAME} app DMG, app zip, and dSYM zip."
