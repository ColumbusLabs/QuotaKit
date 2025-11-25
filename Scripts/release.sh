#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

source "$ROOT/version.env"
TAG="v${MARKETING_VERSION}"

function err() { echo "ERROR: $*" >&2; exit 1; }

git status --porcelain | grep . && err "Working tree not clean"

"$ROOT/Scripts/validate_changelog.sh" "$MARKETING_VERSION"

swiftformat Sources Tests >/dev/null
swiftlint --strict
swift test

"$ROOT/Scripts/sign-and-notarize.sh"

# Sparkle hygiene: clear caches before verification/update tests.
rm -rf ~/Library/Caches/com.steipete.codexbar ~/Library/Caches/org.sparkle-project.Sparkle || true

# Verify appcast/enclosure signature matches the published artifact.
"$ROOT/Scripts/verify_appcast.sh" "$MARKETING_VERSION"

# Optional: run a manual live-update test from the previous release (set RUN_SPARKLE_UPDATE_TEST=1).
if [[ "${RUN_SPARKLE_UPDATE_TEST:-0}" == "1" ]]; then
  PREV_TAG=$(git tag --sort=-v:refname | sed -n '2p')
  if [[ -z "$PREV_TAG" ]]; then
    err "RUN_SPARKLE_UPDATE_TEST=1 set but previous tag could not be determined."
  fi
  echo "Starting live update test from $PREV_TAG -> v${MARKETING_VERSION}"
  "$ROOT/Scripts/test_live_update.sh" "$PREV_TAG" "v${MARKETING_VERSION}"
fi

gh release create "$TAG" CodexBar-${MARKETING_VERSION}.zip CodexBar-${MARKETING_VERSION}.dSYM.zip \
  --title "CodexBar ${MARKETING_VERSION}" \
  --notes "See CHANGELOG.md for this release."

"$ROOT/Scripts/check-release-assets.sh" "$TAG"

git tag -f "$TAG"
git push origin main --tags
