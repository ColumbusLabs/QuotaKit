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

gh release create "$TAG" CodexBar-${MARKETING_VERSION}.zip CodexBar-${MARKETING_VERSION}.dSYM.zip \
  --title "CodexBar ${MARKETING_VERSION}" \
  --notes "See CHANGELOG.md for this release."

"$ROOT/Scripts/check-release-assets.sh" "$TAG"

git tag -f "$TAG"
git push origin main --tags
