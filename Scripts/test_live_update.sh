#!/usr/bin/env bash
set -euo pipefail

# Minimal manual-assisted live update check.
# Downloads the previous release, installs to /Applications, launches, and asks the user
# to trigger and confirm the update to the current version.
#
# Usage: ./Scripts/test_live_update.sh <previous-tag> <current-tag>

PREV_TAG=${1:?"pass previous release tag (e.g. v0.5.5)"}
CUR_TAG=${2:?"pass current release tag (e.g. v0.5.6)"}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PREV_VER=${PREV_TAG#v}

ZIP_URL="https://github.com/steipete/CodexBar/releases/download/${PREV_TAG}/CodexBar-${PREV_VER}.zip"
TMP_DIR=$(mktemp -d /tmp/codexbar-live.XXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading previous release $PREV_TAG from $ZIP_URL"
curl -L -o "$TMP_DIR/prev.zip" "$ZIP_URL"

echo "Installing previous release to /Applications/CodexBar.app"
rm -rf /Applications/CodexBar.app
ditto -x -k "$TMP_DIR/prev.zip" "$TMP_DIR"
ditto "$TMP_DIR/CodexBar.app" /Applications/CodexBar.app

echo "Launching previous build…"
open -n /Applications/CodexBar.app
sleep 4

cat <<'MSG'
Manual step: trigger "Check for Updates…" in CodexBar and install the update.
Expect to land on the newly released version. When done, confirm below.
MSG

read -rp "Did the update succeed from ${PREV_TAG} to ${CUR_TAG}? (y/N) " answer
if [[ ! "$answer" =~ ^[Yy]$ ]]; then
  echo "Live update test NOT confirmed; failing per RUN_SPARKLE_UPDATE_TEST." >&2
  exit 1
fi

echo "Live update test confirmed."
