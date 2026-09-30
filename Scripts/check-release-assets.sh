#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [[ -f "$ROOT/.mac-release.env" ]]; then
  source "$ROOT/.mac-release.env"
fi
source "$ROOT/Scripts/sparkle_helpers.sh"
source "$ROOT/Scripts/release_artifacts.sh"

TAG=${1:-$(git describe --tags --abbrev=0)}
APP_NAME="${MAC_RELEASE_APP_NAME:-QuotaKit}"
ARTIFACT_PREFIX="${MAC_RELEASE_ARTIFACT_PREFIX:-${APP_NAME}-macos-[A-Za-z0-9_+-]+-}"
RELEASE_REPO="${MAC_RELEASE_REPO:-ColumbusLabs/QuotaKit}"
BUNDLE_ID="${MAC_RELEASE_BUNDLE_ID:-com.columbuslabs.quotakit.mac}"
TEAM_ID="${MAC_RELEASE_TEAM_ID:-${APP_TEAM_ID:-${QUOTAKIT_TEAM_ID:-}}}"
if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ || ! "$BUNDLE_ID" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "Configure the expected QuotaKit signing team (APP_TEAM_ID) and bundle identifier before checking assets." >&2
  exit 1
fi
if [[ ! "${TAG#v}" =~ ^[A-Za-z0-9._+-]+$ || ! "$APP_NAME" =~ ^[A-Za-z0-9._+-]+$ ]]; then
  echo "Invalid release tag or app name." >&2
  exit 1
fi

QUOTAKIT_RELEASE_REPO="$RELEASE_REPO" check_assets "$TAG" "$ARTIFACT_PREFIX"

ARCHIVE=$(codexbar_app_zip_name "${TAG#v}" "${ARCHES:-arm64 x86_64}")
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/quotakit-release-assets.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT
gh release download "$TAG" --repo "$RELEASE_REPO" --pattern "$ARCHIVE" --dir "$TEMP_DIR"
ditto -x -k --norsrc "$TEMP_DIR/$ARCHIVE" "$TEMP_DIR"
APP_PATH="$TEMP_DIR/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" || -L "$APP_PATH" ]]; then
  echo "Release archive must contain a real ${APP_NAME}.app directory." >&2
  exit 1
fi
REQUIREMENT="=anchor apple generic and identifier \"$BUNDLE_ID\""
REQUIREMENT+=" and certificate leaf[subject.OU] = \"$TEAM_ID\""
REQUIREMENT+=' and certificate 1[field.1.2.840.113635.100.6.2.6] exists'
REQUIREMENT+=' and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'
codesign --verify --deep --strict --all-architectures --verbose=2 \
  --test-requirement "$REQUIREMENT" "$APP_PATH"
echo "Release $TAG has the ${APP_NAME} app DMG, app zip, and dSYM zip; downloaded app signature verified."
