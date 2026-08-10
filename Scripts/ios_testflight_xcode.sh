#!/usr/bin/env bash
#
# Archive QuotaKit iOS and upload it to App Store Connect/TestFlight using the
# headless xcodebuild CLI lane.
#
# This is the canonical iOS upload lane. It generates the project, archives for
# generic iOS with App Store distribution profiles, verifies the widget
# extension is embedded, then exports with destination=upload.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

RUN_LINT=1
DO_ARCHIVE=1
DO_UPLOAD=1
PREFLIGHT_ONLY=0
ARCHIVE_PATH=""
TEAM_ID="${IOS_TEAM_ID:-${QUOTAKIT_TEAM_ID:-${APP_TEAM_ID:-${DEVELOPMENT_TEAM:-}}}}"
EXPORT_SYSTEM_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
CLANG_PROBE_WORKAROUND_XCODE_BUILD="17F113"

usage() {
  cat <<'USAGE' >&2
Usage: Scripts/ios_testflight_xcode.sh [options]

Options:
  --team-id TEAM       Apple Developer team ID to use for signing.
  --archive-path PATH  Reuse or write a specific .xcarchive path.
  --skip-lint          Skip ./Scripts/lint.sh lint.
  --skip-archive       Reuse --archive-path and only export/upload.
  --archive-only       Stop after creating and verifying the archive.
  --preflight-only     Validate credentials, signing, and tool versions only.
  -h, --help           Show this help.

Environment:
  IOS_TEAM_ID, QUOTAKIT_TEAM_ID, APP_TEAM_ID, or DEVELOPMENT_TEAM may provide
  the team ID. If omitted, the script tries to infer it from an installed
  "Apple Distribution: Columbus Labs LLC (...)" signing identity.
  APP_STORE_CONNECT_API_KEY_FILE, APP_STORE_CONNECT_KEY_ID, and
  APP_STORE_CONNECT_ISSUER_ID are all required. Xcode-account authentication
  is intentionally unsupported in this headless release lane.
  QUOTAKIT_SIGNING_KEYCHAIN may override the login Keychain used for signing.
  QUOTAKIT_DISABLE_CLANG_PROBE_WORKAROUND=1 is only for an explicit
  archive-only maintenance check after an Xcode upgrade.
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
    --preflight-only)
      PREFLIGHT_ONLY=1
      DO_ARCHIVE=0
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

ASC_AUTH_ARGS=()
asc_auth_values=0
[[ -n "${APP_STORE_CONNECT_API_KEY_FILE:-}" ]] && ((asc_auth_values += 1))
[[ -n "${APP_STORE_CONNECT_KEY_ID:-}" ]] && ((asc_auth_values += 1))
[[ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]] && ((asc_auth_values += 1))

if [[ "$asc_auth_values" -ne 3 ]]; then
  echo "ERROR: App Store Connect API-key authentication is required; Xcode-account fallback is disabled." >&2
  echo "       Set APP_STORE_CONNECT_API_KEY_FILE, APP_STORE_CONNECT_KEY_ID, and APP_STORE_CONNECT_ISSUER_ID." >&2
  exit 2
fi

if [[ ! -f "$APP_STORE_CONNECT_API_KEY_FILE" || ! -r "$APP_STORE_CONNECT_API_KEY_FILE" ]]; then
  echo "ERROR: App Store Connect API key file was not found or is not readable." >&2
  exit 2
fi

ASC_AUTH_ARGS=(
  -authenticationKeyPath "$APP_STORE_CONNECT_API_KEY_FILE"
  -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID"
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID"
)

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

if [[ "$DO_ARCHIVE" -eq 0 && "$PREFLIGHT_ONLY" -eq 0 && -z "$ARCHIVE_PATH" ]]; then
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
SIGNING_PROBE_LOG="$RUN_DIR/signing-probe.log"

xcode_version_output=$(/usr/bin/xcodebuild -version 2>&1) || {
  echo "ERROR: xcodebuild is unavailable through the active developer directory." >&2
  printf '%s\n' "$xcode_version_output" >&2
  exit 2
}
xcode_version=$(awk 'NR == 1 {print $2}' <<<"$xcode_version_output")
xcode_build=$(awk '/^Build version / {print $3}' <<<"$xcode_version_output")
developer_dir=$(xcode-select -p 2>/dev/null || true)
system_rsync_output=$(/usr/bin/rsync --version 2>&1 || true)
system_rsync_version=${system_rsync_output%%$'\n'*}
shell_rsync_path=$(command -v rsync 2>/dev/null || true)
if [[ -n "$shell_rsync_path" ]]; then
  shell_rsync_output=$("$shell_rsync_path" --version 2>&1 || true)
  shell_rsync_version=${shell_rsync_output%%$'\n'*}
else
  shell_rsync_path="unavailable"
  shell_rsync_version="unavailable"
fi

echo "==> Release toolchain"
echo "    Xcode: ${xcode_version:-unknown} (build ${xcode_build:-unknown})"
echo "    Developer directory: ${developer_dir:-unknown}"
echo "    System rsync: $system_rsync_version (/usr/bin/rsync)"
echo "    Shell rsync: $shell_rsync_version ($shell_rsync_path)"
echo "    Export PATH: $EXPORT_SYSTEM_PATH"

if [[ -n "$xcode_build" && "$xcode_build" != "$CLANG_PROBE_WORKAROUND_XCODE_BUILD" ]]; then
  echo "WARNING: The clang-probe workaround was verified on Xcode build $CLANG_PROBE_WORKAROUND_XCODE_BUILD," >&2
  echo "         but the active build is $xcode_build. Run the documented archive-only" >&2
  echo "         maintenance check and remove the workaround if native xcodebuild is stable." >&2
fi

signing_identity_name="Apple Distribution: Columbus Labs LLC ($TEAM_ID)"
signing_identities=$(security find-identity -v -p codesigning 2>/dev/null || true)
signing_identity_line=$(grep -F "\"$signing_identity_name\"" <<<"$signing_identities" | head -1 || true)
signing_identity_hash=$(sed -nE 's/^[[:space:]]*[0-9]+\)[[:space:]]+([[:xdigit:]]{40})[[:space:]].*/\1/p' \
  <<<"$signing_identity_line")

if [[ -z "$signing_identity_hash" ]]; then
  echo "ERROR: The $signing_identity_name certificate/private-key pair is not installed." >&2
  echo "       This is the only release recovery that may require Xcode > Settings > Accounts" >&2
  echo "       > Manage Certificates; Xcode is not part of the normal archive/upload lane." >&2
  exit 2
fi

LOGIN_KEYCHAIN="${QUOTAKIT_SIGNING_KEYCHAIN:-${HOME}/Library/Keychains/login.keychain-db}"
if [[ ! -f "$LOGIN_KEYCHAIN" ]]; then
  echo "ERROR: Signing Keychain was not found: $LOGIN_KEYCHAIN" >&2
  exit 2
fi

SIGNING_PROBE="$RUN_DIR/signing-probe"
/bin/cp /usr/bin/true "$SIGNING_PROBE"
if ! codesign --force --sign "$signing_identity_hash" --keychain "$LOGIN_KEYCHAIN" \
  "$SIGNING_PROBE" >"$SIGNING_PROBE_LOG" 2>&1 \
  || ! codesign --verify --strict "$SIGNING_PROBE" >>"$SIGNING_PROBE_LOG" 2>&1
then
  echo "ERROR: The installed Apple Distribution private key is not usable for headless signing." >&2
  echo "       Unlock it in Terminal, then rerun this command:" >&2
  printf '       security unlock-keychain %q\n' "$LOGIN_KEYCHAIN" >&2
  echo "       If signing still fails after unlock, inspect the key ACL/certificate pair." >&2
  echo "       Signing probe log: $SIGNING_PROBE_LOG" >&2
  exit 2
fi
/bin/rm -f "$SIGNING_PROBE"
echo "    Signing probe: passed ($signing_identity_name)"

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
  <string>manual</string>
  <key>signingCertificate</key>
  <string>Apple Distribution</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>com.columbuslabs.quotakit.ios</key>
    <string>QuotaKit iOS App Store 2026-07-31</string>
    <key>com.columbuslabs.quotakit.ios.pushextension</key>
    <string>QuotaKit Push App Store 2026-07-31</string>
    <key>com.columbuslabs.quotakit.ios.widgets</key>
    <string>QuotaKit Widgets App Store 2026-07-31</string>
  </dict>
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
    echo "Detected blocker: xcodebuild reported an account error even though API-key auth was supplied." >&2
    echo "Do not open Xcode. Verify the App Store Connect key role and provisioning-profile access." >&2
  fi

  if grep -q "rsync: on remote machine: --extended-attributes: unknown option" "$log_file"; then
    echo "Detected blocker: Xcode mixed Apple rsync with an incompatible PATH rsync." >&2
    echo "The export command must keep PATH=$EXPORT_SYSTEM_PATH." >&2
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
echo "    App Store Connect auth: API key (required)"
echo "    Xcode GUI/account: not used"
echo "    Archive: $ARCHIVE_PATH"
echo "    Run logs: $RUN_DIR"

if [[ "$PREFLIGHT_ONLY" -eq 1 ]]; then
  echo ""
  echo "==> Preflight complete; no project generation, archive, export, or upload performed"
  exit 0
fi

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
  ARCHIVE_COMPILER_ARGS=()
  case "${QUOTAKIT_DISABLE_CLANG_PROBE_WORKAROUND:-0}" in
    0)
      ARCHIVE_COMPILER_ARGS=(CC="$ROOT/Scripts/xcode-clang-probe-wrapper.sh")
      ;;
    1)
      echo "WARNING: Running the explicit native-clang maintenance check without the probe workaround." >&2
      ;;
    *)
      echo "ERROR: QUOTAKIT_DISABLE_CLANG_PROBE_WORKAROUND must be 0 or 1." >&2
      exit 2
      ;;
  esac
  set +e
  # Xcode 26.6 can deadlock while probing clang when verbose macro output fills
  # the build service pipe. The wrapper trims only that probe's verbose output.
  /usr/bin/xcodebuild archive \
    -project CodexBarMobile/CodexBarMobile.xcodeproj \
    -scheme CodexBarMobile \
    -configuration Release \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    -destination-timeout 5 \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    "${ASC_AUTH_ARGS[@]}" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    "${ARCHIVE_COMPILER_ARGS[@]}" \
    >"$ARCHIVE_LOG" 2>&1
  status=$?
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
# Keep Apple's rsync on PATH. A Homebrew rsync server rejects Xcode's Apple -E flag.
PATH="$EXPORT_SYSTEM_PATH" /usr/bin/xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$OPTIONS_PLIST" \
  -allowProvisioningUpdates \
  "${ASC_AUTH_ARGS[@]}" \
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
