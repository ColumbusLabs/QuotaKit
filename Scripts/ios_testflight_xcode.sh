#!/usr/bin/env bash
#
# Archive QuotaKit iOS and upload it to App Store Connect/TestFlight using the
# direct Xcode lane.
#
# This is the canonical iOS upload lane. It generates the project, archives for
# generic iOS with automatic provisioning, verifies the widget extension is
# embedded, then exports with destination=upload.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

RUN_LINT=1
DO_ARCHIVE=1
DO_UPLOAD=1
ARCHIVE_PATH=""
TEAM_ID="${IOS_TEAM_ID:-${QUOTAKIT_TEAM_ID:-${APP_TEAM_ID:-${DEVELOPMENT_TEAM:-}}}}"

usage() {
  cat <<'USAGE' >&2
Usage: Scripts/ios_testflight_xcode.sh [options]

Options:
  --team-id TEAM       Apple Developer team ID to use for signing.
  --archive-path PATH  Reuse or write a specific .xcarchive path.
  --skip-lint          Skip ./Scripts/lint.sh lint.
  --skip-archive       Reuse --archive-path and only export/upload.
  --archive-only       Stop after creating and verifying the archive.
  -h, --help           Show this help.

Environment:
  IOS_TEAM_ID, QUOTAKIT_TEAM_ID, APP_TEAM_ID, or DEVELOPMENT_TEAM may provide
  the team ID. If omitted, the script tries to infer it from an installed
  "Apple Distribution: Columbus Labs LLC (...)" signing identity.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team-id)
      TEAM_ID="${2:?Missing value for --team-id}"
      shift 2
      ;;
    --archive-path)
      ARCHIVE_PATH="${2:?Missing value for --archive-path}"
      shift 2
      ;;
    --skip-lint)
      RUN_LINT=0
      shift
      ;;
    --skip-archive)
      DO_ARCHIVE=0
      shift
      ;;
    --archive-only)
      DO_UPLOAD=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -f "$ROOT/Scripts/load-release-secrets.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/Scripts/load-release-secrets.sh"
fi

TEAM_ID="${TEAM_ID:-${IOS_TEAM_ID:-${QUOTAKIT_TEAM_ID:-${APP_TEAM_ID:-${DEVELOPMENT_TEAM:-}}}}}"

if [[ -z "$TEAM_ID" ]]; then
  TEAM_ID=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -nE 's/.*"Apple Distribution: Columbus Labs LLC \(([A-Z0-9]+)\)".*/\1/p' \
    | head -1)
fi

if [[ -z "$TEAM_ID" ]]; then
  echo "ERROR: Unable to determine Apple Developer team ID." >&2
  echo "       Pass --team-id TEAM or set IOS_TEAM_ID/QUOTAKIT_TEAM_ID." >&2
  exit 2
fi

if [[ "$DO_ARCHIVE" -eq 0 && -z "$ARCHIVE_PATH" ]]; then
  echo "ERROR: --skip-archive requires --archive-path PATH." >&2
  exit 2
fi

STAMP=$(date +%Y%m%d-%H%M%S)
RUN_DIR="/tmp/quotakit-ios-testflight-$STAMP"
mkdir -p "$RUN_DIR"

if [[ -z "$ARCHIVE_PATH" ]]; then
  ARCHIVE_PATH="$RUN_DIR/QuotaKit.xcarchive"
fi

ARCHIVE_LOG="$RUN_DIR/archive.log"
EXPORT_LOG="$RUN_DIR/export-upload.log"
EXPORT_PATH="$RUN_DIR/export"
OPTIONS_PLIST="$RUN_DIR/ExportOptions-app-store-connect.plist"

printf '%s\n' "$ARCHIVE_PATH" > /tmp/quotakit-latest-archive-path
printf '%s\n' "$ARCHIVE_LOG" > /tmp/quotakit-latest-archive-log
printf '%s\n' "$EXPORT_LOG" > /tmp/quotakit-latest-export-log

cat > "$OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>destination</key>
  <string>upload</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>uploadSymbols</key>
  <true/>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
PLIST

summarize_failure() {
  local log_file="$1"
  echo ""
  echo "Full log: $log_file" >&2

  if grep -q "No Accounts: Add a new account in Accounts settings" "$log_file"; then
    echo "Detected blocker: Xcode has no Apple Developer account configured for automatic provisioning." >&2
    echo "Add the Columbus Labs account in Xcode Settings > Accounts, or use an API-key/profile path with sufficient signing permissions." >&2
  fi

  if grep -q "doesn't include the App Groups capability\\|doesn't support the group.com.columbuslabs.quotakit App Group" "$log_file"; then
    echo "Detected blocker: installed provisioning profiles do not include group.com.columbuslabs.quotakit." >&2
    echo "Enable App Groups on the app/widget App IDs and regenerate the iOS profiles." >&2
  fi

  if grep -q "doesn't include the iCloud capability\\|doesn't support the iCloud.com.columbuslabs.quotakit iCloud Container" "$log_file"; then
    echo "Detected blocker: installed provisioning profiles do not include the QuotaKit iCloud container." >&2
    echo "Enable iCloud/CloudKit on the relevant App IDs and regenerate the iOS profiles." >&2
  fi

  if grep -q "doesn't include the Push Notifications capability\\|doesn't include the aps-environment" "$log_file"; then
    echo "Detected blocker: installed provisioning profiles do not include Push Notifications." >&2
    echo "Enable Push Notifications on the iOS app App ID and regenerate the profile." >&2
  fi
}

BUILD=$(awk '/CURRENT_PROJECT_VERSION:/ {gsub(/"/, "", $2); print $2; exit}' CodexBarMobile/project.yml)
MARKETING=$(awk '/MARKETING_VERSION:/ {gsub(/"/, "", $2); print $2; exit}' CodexBarMobile/project.yml)

echo "==> QuotaKit iOS TestFlight lane"
echo "    Version: ${MARKETING:-unknown} (${BUILD:-unknown})"
echo "    Team ID: $TEAM_ID"
echo "    Archive: $ARCHIVE_PATH"
echo "    Run logs: $RUN_DIR"

if [[ "$RUN_LINT" -eq 1 ]]; then
  echo ""
  echo "==> Pre-flight lint"
  "$ROOT/Scripts/lint.sh" lint
fi

echo ""
echo "==> Generating Xcode project"
(cd CodexBarMobile && xcodegen generate)

if [[ "$DO_ARCHIVE" -eq 1 ]]; then
  echo ""
  echo "==> Archiving for generic iOS"
  set +e
  xcodebuild archive \
    -project CodexBarMobile/CodexBarMobile.xcodeproj \
    -scheme CodexBarMobile \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    2>&1 | tee "$ARCHIVE_LOG"
  status=${PIPESTATUS[0]}
  set -e

  if [[ "$status" -ne 0 ]]; then
    summarize_failure "$ARCHIVE_LOG"
    exit "$status"
  fi
fi

if [[ ! -d "$ARCHIVE_PATH" ]]; then
  echo "ERROR: Archive not found: $ARCHIVE_PATH" >&2
  exit 1
fi

APP_PATH=$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -type d -name "*.app" | head -1)
if [[ -z "$APP_PATH" ]]; then
  echo "ERROR: No .app bundle found in archive: $ARCHIVE_PATH" >&2
  exit 1
fi

if [[ -d "$APP_PATH/PlugIns/CodexBarMobileWidgets.appex" ]]; then
  echo "==> Verified widget extension is embedded in archive"
else
  echo "ERROR: CodexBarMobileWidgets.appex is missing from the archive." >&2
  exit 1
fi

if [[ "$DO_UPLOAD" -eq 0 ]]; then
  echo ""
  echo "==> Archive complete; upload skipped by --archive-only"
  exit 0
fi

echo ""
echo "==> Exporting and uploading to App Store Connect"
set +e
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$OPTIONS_PLIST" \
  -allowProvisioningUpdates \
  2>&1 | tee "$EXPORT_LOG"
status=${PIPESTATUS[0]}
set -e

if [[ "$status" -ne 0 ]]; then
  summarize_failure "$EXPORT_LOG"
  exit "$status"
fi

echo ""
echo "==> Upload succeeded"
echo "    Archive: $ARCHIVE_PATH"
echo "    Export log: $EXPORT_LOG"
