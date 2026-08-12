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
REQUIRED_XCODEGEN_VERSION="2.45.4"
EXPECTED_APP_GROUP="group.com.columbuslabs.quotakit"
EXPECTED_ICLOUD_CONTAINER="iCloud.com.columbuslabs.quotakit"

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
  XcodeGen 2.45.4 must be the xcodegen executable selected by PATH.
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

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "ERROR: XcodeGen $REQUIRED_XCODEGEN_VERSION is required, but xcodegen was not found on PATH." >&2
  echo "       Install XcodeGen $REQUIRED_XCODEGEN_VERSION and place that exact version first on PATH." >&2
  exit 2
fi

xcodegen_version_output=$(xcodegen --version 2>&1) || {
  echo "ERROR: Unable to read the XcodeGen version." >&2
  printf '%s\n' "$xcodegen_version_output" >&2
  exit 2
}
xcodegen_version=$(grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' <<<"$xcodegen_version_output" | head -1 || true)
if [[ "$xcodegen_version" != "$REQUIRED_XCODEGEN_VERSION" ]]; then
  echo "ERROR: XcodeGen $REQUIRED_XCODEGEN_VERSION is required; found ${xcodegen_version:-unknown}." >&2
  echo "       Put XcodeGen $REQUIRED_XCODEGEN_VERSION first on PATH, then rerun the release lane." >&2
  echo '       Example: PATH="/path/to/xcodegen-2.45.4/bin:$PATH" ./Scripts/ios_testflight_xcode.sh --preflight-only' >&2
  exit 2
fi

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
echo "    XcodeGen: $xcodegen_version (required)"
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

if ! /usr/bin/plutil -lint "$OPTIONS_PLIST" >/dev/null 2>&1; then
  echo "ERROR: Generated ExportOptions plist is invalid: $OPTIONS_PLIST" >&2
  exit 2
fi

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

project_builds=$(awk '/CURRENT_PROJECT_VERSION:/ {gsub(/"/, "", $2); print $2}' CodexBarMobile/project.yml \
  | sort -u)
if [[ -z "$project_builds" || "$project_builds" == *$'\n'* ]]; then
  echo "ERROR: CodexBarMobile/project.yml must define one consistent CURRENT_PROJECT_VERSION." >&2
  printf '       Found: %s\n' "${project_builds:-<none>}" >&2
  exit 2
fi
BUILD="$project_builds"
MARKETING=$(awk '/MARKETING_VERSION:/ {gsub(/"/, "", $2); print $2; exit}' CodexBarMobile/project.yml)

plist_value() {
  local plist="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null
}

require_plist_value() {
  local label="$1"
  local plist="$2"
  local key="$3"
  local expected="$4"
  local actual
  actual=$(plist_value "$plist" "$key" || true)
  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: $label has invalid $key; expected '$expected', found '${actual:-<missing>}'." >&2
    return 1
  fi
}

require_plist_array_value() {
  local label="$1"
  local plist="$2"
  local key="$3"
  local expected="$4"
  local values
  values=$(plist_value "$plist" "$key" || true)
  if ! grep -Eq "^[[:space:]]*${expected//./\\.}[[:space:]]*$" <<<"$values"; then
    echo "ERROR: $label is missing '$expected' in $key." >&2
    return 1
  fi
}

require_plist_array_value_or_wildcard() {
  local label="$1"
  local plist="$2"
  local key="$3"
  local expected="$4"
  local values
  values=$(plist_value "$plist" "$key" || true)
  if [[ "$values" == "*" ]]; then
    return 0
  fi
  if ! grep -Eq "^[[:space:]]*${expected//./\\.}[[:space:]]*$" <<<"$values"; then
    echo "ERROR: $label is missing '$expected' or a wildcard in $key." >&2
    return 1
  fi
}

extract_leaf_certificate_fingerprint() {
  local label="$1"
  local code_path="$2"
  local codesign_log="$3"
  local safe_label=${label// /-}
  local certificate_dir
  local certificate_prefix
  local leaf_certificate

  certificate_dir=$(mktemp -d "$RUN_DIR/${safe_label}-certificates.XXXXXX") || {
    echo "ERROR: Unable to create a certificate extraction directory for $label." >&2
    return 1
  }
  certificate_prefix="$certificate_dir/certificate"
  leaf_certificate="${certificate_prefix}0"

  if ! codesign -d "--extract-certificates=$certificate_prefix" \
    "$code_path" >>"$codesign_log" 2>&1
  then
    echo "ERROR: Unable to extract the signing certificate chain from $label." >&2
    echo "       Log: $codesign_log" >&2
    return 1
  fi
  if [[ ! -s "$leaf_certificate" ]]; then
    echo "ERROR: $label did not contain an extractable leaf signing certificate." >&2
    echo "       Log: $codesign_log" >&2
    return 1
  fi

  /usr/bin/shasum -a 256 "$leaf_certificate" | awk '{print $1}'
}

verify_strict_code_signature() {
  local label="$1"
  local code_path="$2"
  local codesign_log="$3"
  local fingerprint_output_variable="$4"
  local computed_fingerprint

  if ! codesign --verify --strict "$code_path" >"$codesign_log" 2>&1; then
    echo "ERROR: $label failed strict code-signature verification." >&2
    echo "       Log: $codesign_log" >&2
    return 1
  fi
  computed_fingerprint=$(extract_leaf_certificate_fingerprint \
    "$label" "$code_path" "$codesign_log") || return 1
  printf -v "$fingerprint_output_variable" '%s' "$computed_fingerprint"
}

require_profile_leaf_certificate() {
  local label="$1"
  local profile_plist="$2"
  local expected_fingerprint="$3"
  local safe_label=${label// /-}
  local certificate_count
  local certificate_index
  local encoded_certificate
  local decoded_certificate
  local profile_fingerprint

  certificate_count=$(/usr/bin/plutil -extract DeveloperCertificates raw \
    -expect array -o - "$profile_plist" 2>/dev/null || true)
  if [[ ! "$certificate_count" =~ ^[0-9]+$ || "$certificate_count" -lt 1 ]]; then
    echo "ERROR: $label embedded provisioning profile has no DeveloperCertificates entries." >&2
    return 1
  fi

  for ((certificate_index = 0; certificate_index < certificate_count; certificate_index += 1)); do
    encoded_certificate=$(/usr/bin/plutil \
      -extract "DeveloperCertificates.$certificate_index" raw \
      -expect data -o - "$profile_plist" 2>/dev/null || true)
    [[ -n "$encoded_certificate" ]] || continue
    decoded_certificate="$RUN_DIR/${safe_label}-profile-certificate-$certificate_index.der"
    if ! printf '%s' "$encoded_certificate" | /usr/bin/base64 --decode >"$decoded_certificate"; then
      echo "ERROR: Unable to decode DeveloperCertificates.$certificate_index for $label." >&2
      return 1
    fi
    profile_fingerprint=$(/usr/bin/shasum -a 256 "$decoded_certificate" | awk '{print $1}')
    if [[ "$profile_fingerprint" == "$expected_fingerprint" ]]; then
      return 0
    fi
  done

  echo "ERROR: $label leaf signing certificate is not present in its embedded provisioning profile." >&2
  echo "       Leaf SHA-256: $expected_fingerprint" >&2
  return 1
}

verify_archive_bundle() {
  local label="$1"
  local bundle_path="$2"
  local expected_bundle_id="$3"
  local require_app_group="$4"
  local require_cloudkit="$5"
  local require_push="$6"
  local leaf_fingerprint_output_variable="$7"
  local info_plist="$bundle_path/Info.plist"
  local profile="$bundle_path/embedded.mobileprovision"
  local safe_label=${label// /-}
  local signed_entitlements="$RUN_DIR/${safe_label}-signed-entitlements.plist"
  local profile_plist="$RUN_DIR/${safe_label}-profile.plist"
  local codesign_log="$RUN_DIR/${safe_label}-codesign.log"
  local profile_log="$RUN_DIR/${safe_label}-profile.log"
  local bundle_leaf_fingerprint

  if [[ ! -d "$bundle_path" ]]; then
    echo "ERROR: Missing $label bundle: $bundle_path" >&2
    return 1
  fi
  if [[ ! -f "$info_plist" ]]; then
    echo "ERROR: Missing $label Info.plist: $info_plist" >&2
    return 1
  fi
  if [[ ! -f "$profile" ]]; then
    echo "ERROR: Missing $label embedded provisioning profile: $profile" >&2
    return 1
  fi

  require_plist_value "$label Info.plist" "$info_plist" CFBundleIdentifier "$expected_bundle_id" || return 1
  require_plist_value "$label Info.plist" "$info_plist" CFBundleVersion "$BUILD" || return 1
  require_plist_value "$label Info.plist" "$info_plist" CFBundleShortVersionString "$MARKETING" || return 1

  verify_strict_code_signature "$label" "$bundle_path" "$codesign_log" \
    bundle_leaf_fingerprint || return 1
  if ! codesign -d --entitlements :- "$bundle_path" >"$signed_entitlements" 2>>"$codesign_log"; then
    echo "ERROR: Unable to read signed entitlements from $label." >&2
    echo "       Log: $codesign_log" >&2
    return 1
  fi
  if ! /usr/bin/plutil -lint "$signed_entitlements" >/dev/null 2>&1; then
    echo "ERROR: $label signed entitlements are not a valid plist." >&2
    return 1
  fi

  if ! security cms -D -i "$profile" >"$profile_plist" 2>"$profile_log"; then
    echo "ERROR: Unable to decode $label embedded provisioning profile." >&2
    echo "       Log: $profile_log" >&2
    return 1
  fi
  if ! /usr/bin/plutil -lint "$profile_plist" >/dev/null 2>&1; then
    echo "ERROR: $label embedded provisioning profile is not a valid plist." >&2
    return 1
  fi

  require_plist_value "$label signed entitlements" "$signed_entitlements" \
    com.apple.developer.team-identifier "$TEAM_ID" || return 1
  require_plist_value "$label signed entitlements" "$signed_entitlements" \
    application-identifier "$TEAM_ID.$expected_bundle_id" || return 1
  require_plist_value "$label profile" "$profile_plist" \
    Entitlements:com.apple.developer.team-identifier "$TEAM_ID" || return 1
  require_plist_array_value "$label profile" "$profile_plist" TeamIdentifier "$TEAM_ID" || return 1
  require_plist_value "$label profile" "$profile_plist" \
    Entitlements:application-identifier "$TEAM_ID.$expected_bundle_id" || return 1
  require_profile_leaf_certificate "$label" "$profile_plist" \
    "$bundle_leaf_fingerprint" || return 1

  if [[ "$require_app_group" == 1 ]]; then
    require_plist_array_value "$label signed entitlements" "$signed_entitlements" \
      com.apple.security.application-groups "$EXPECTED_APP_GROUP" || return 1
    require_plist_array_value "$label profile" "$profile_plist" \
      Entitlements:com.apple.security.application-groups "$EXPECTED_APP_GROUP" || return 1
  fi

  if [[ "$require_cloudkit" == 1 ]]; then
    require_plist_array_value "$label signed entitlements" "$signed_entitlements" \
      com.apple.developer.icloud-container-identifiers "$EXPECTED_ICLOUD_CONTAINER" || return 1
    require_plist_array_value "$label profile" "$profile_plist" \
      Entitlements:com.apple.developer.icloud-container-identifiers "$EXPECTED_ICLOUD_CONTAINER" || return 1
    require_plist_array_value "$label signed entitlements" "$signed_entitlements" \
      com.apple.developer.icloud-services CloudKit || return 1
    require_plist_array_value_or_wildcard "$label profile" "$profile_plist" \
      Entitlements:com.apple.developer.icloud-services CloudKit || return 1
    require_plist_value "$label signed entitlements" "$signed_entitlements" \
      com.apple.developer.icloud-container-environment Production || return 1
    require_plist_array_value "$label profile" "$profile_plist" \
      Entitlements:com.apple.developer.icloud-container-environment Production || return 1
  fi

  if [[ "$require_push" == 1 ]]; then
    require_plist_value "$label signed entitlements" "$signed_entitlements" \
      aps-environment production || return 1
    require_plist_value "$label profile" "$profile_plist" \
      Entitlements:aps-environment production || return 1
  fi

  printf -v "$leaf_fingerprint_output_variable" '%s' "$bundle_leaf_fingerprint"
  echo "    $label: $expected_bundle_id $MARKETING ($BUILD), signed by $TEAM_ID"
}

verify_nested_code() {
  local label="$1"
  local code_path="$2"
  local expected_leaf_fingerprint="$3"
  local safe_label=${label// /-}
  local codesign_log="$RUN_DIR/${safe_label}-codesign.log"
  local nested_leaf_fingerprint

  verify_strict_code_signature "$label" "$code_path" "$codesign_log" \
    nested_leaf_fingerprint || return 1
  if [[ "$nested_leaf_fingerprint" != "$expected_leaf_fingerprint" ]]; then
    echo "ERROR: $label is not signed by the same leaf certificate as its containing app bundle: $code_path" >&2
    echo "       Expected SHA-256: $expected_leaf_fingerprint" >&2
    echo "       Actual SHA-256:   $nested_leaf_fingerprint" >&2
    return 1
  fi
  echo "    $label: strict signature and containing-app certificate match ($code_path)"
}

verify_archive_contents() {
  local app_path="$1"
  local archive_info="$ARCHIVE_PATH/Info.plist"
  local application_path=${app_path#"$ARCHIVE_PATH/Products/"}
  local push_path="$app_path/PlugIns/CodexBarMobilePushExtension.appex"
  local widget_path="$app_path/PlugIns/CodexBarMobileWidgets.appex"
  local embedded_extension
  local main_leaf_fingerprint
  local push_leaf_fingerprint
  local widget_leaf_fingerprint
  local nested_code
  local nested_code_index=0
  local expected_nested_leaf_fingerprint
  local deep_codesign_log="$RUN_DIR/main-app-deep-codesign.log"

  echo "==> Verifying archived bundle identities, signatures, profiles, and production entitlements"
  if [[ ! -f "$archive_info" ]]; then
    echo "ERROR: Archive metadata plist is missing: $archive_info" >&2
    return 1
  fi
  require_plist_value "archive metadata" "$archive_info" \
    ApplicationProperties:ApplicationPath "$application_path" || return 1
  require_plist_value "archive metadata" "$archive_info" \
    ApplicationProperties:CFBundleIdentifier com.columbuslabs.quotakit.ios || return 1
  require_plist_value "archive metadata" "$archive_info" \
    ApplicationProperties:CFBundleVersion "$BUILD" || return 1
  require_plist_value "archive metadata" "$archive_info" \
    ApplicationProperties:Team "$TEAM_ID" || return 1

  while IFS= read -r embedded_extension; do
    case "$embedded_extension" in
      "$push_path"|"$widget_path")
        ;;
      *)
        echo "ERROR: Unexpected embedded app extension: $embedded_extension" >&2
        return 1
        ;;
    esac
  done < <(find "$app_path" -type d -name "*.appex" -print)

  if ! codesign --verify --deep --strict "$app_path" >"$deep_codesign_log" 2>&1; then
    echo "ERROR: Main app failed recursive code-signature verification." >&2
    echo "       Log: $deep_codesign_log" >&2
    return 1
  fi

  verify_archive_bundle "main app" "$app_path" \
    com.columbuslabs.quotakit.ios 1 1 1 main_leaf_fingerprint
  verify_archive_bundle "push extension" "$push_path" \
    com.columbuslabs.quotakit.ios.pushextension 0 1 0 push_leaf_fingerprint
  verify_archive_bundle "widget extension" "$widget_path" \
    com.columbuslabs.quotakit.ios.widgets 1 0 0 widget_leaf_fingerprint

  while IFS= read -r nested_code; do
    nested_code_index=$((nested_code_index + 1))
    case "$nested_code" in
      "$push_path"/*)
        expected_nested_leaf_fingerprint="$push_leaf_fingerprint"
        ;;
      "$widget_path"/*)
        expected_nested_leaf_fingerprint="$widget_leaf_fingerprint"
        ;;
      *)
        expected_nested_leaf_fingerprint="$main_leaf_fingerprint"
        ;;
    esac
    verify_nested_code "nested code $nested_code_index" \
      "$nested_code" "$expected_nested_leaf_fingerprint" || return 1
  done < <(find "$app_path" \
    \( \( -type d -name "*.framework" \) -o \
    \( \( -type f -o -type l \) -name "*.dylib" \) \) -print)

  echo "==> Archive validation passed"
}

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

APP_CANDIDATES=$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -type d -name "*.app" 2>/dev/null || true)
APP_COUNT=$(grep -c . <<<"$APP_CANDIDATES" || true)
if [[ "$APP_COUNT" -ne 1 ]]; then
  echo "ERROR: Expected exactly one .app bundle in archive; found $APP_COUNT: $ARCHIVE_PATH" >&2
  exit 1
fi
APP_PATH="$APP_CANDIDATES"

verify_archive_contents "$APP_PATH"

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
