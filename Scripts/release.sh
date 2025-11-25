#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

source "$ROOT/version.env"
source "$HOME/Projects/agent-scripts/release/sparkle_lib.sh"

APPCAST="$ROOT/appcast.xml"
APP_NAME="CodexBar"
ARTIFACT_PREFIX="CodexBar-"
BUNDLE_ID="com.steipete.codexbar"
TAG="v${MARKETING_VERSION}"

function err() { echo "ERROR: $*" >&2; exit 1; }

git status --porcelain | grep . && err "Working tree not clean"

"$ROOT/Scripts/validate_changelog.sh" "$MARKETING_VERSION"

swiftformat Sources Tests >/dev/null
swiftlint --strict
swift test

# Build, sign, notarize
"$ROOT/Scripts/sign-and-notarize.sh"

# Sparkle hygiene
clear_sparkle_caches "$BUNDLE_ID"

# Verify appcast/enclosure
KEY_FILE=$(clean_key "$SPARKLE_PRIVATE_KEY_FILE")
trap 'rm -f "$KEY_FILE"' EXIT
verify_appcast_entry "$APPCAST" "$MARKETING_VERSION" "$KEY_FILE"

# Optional live-update test
if [[ "${RUN_SPARKLE_UPDATE_TEST:-0}" == "1" ]]; then
  PREV_TAG=$(git tag --sort=-v:refname | sed -n '2p')
  [[ -z "$PREV_TAG" ]] && err "RUN_SPARKLE_UPDATE_TEST=1 set but no previous tag found"
  echo "Starting live update test from $PREV_TAG -> v${MARKETING_VERSION}"
  "$ROOT/Scripts/test_live_update.sh" "$PREV_TAG" "v${MARKETING_VERSION}"
fi

gh release create "$TAG" CodexBar-${MARKETING_VERSION}.zip CodexBar-${MARKETING_VERSION}.dSYM.zip \
  --title "CodexBar ${MARKETING_VERSION}" \
  --notes "See CHANGELOG.md for this release."

check_assets "$TAG" "$ARTIFACT_PREFIX"

git tag -f "$TAG"
git push origin main --tags
