#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RELEASE_SCRIPT="$ROOT/Scripts/ios_testflight_xcode.sh"
CLANG_WRAPPER="$ROOT/Scripts/xcode-clang-probe-wrapper.sh"
MOBILE_RELEASE_DOC="$ROOT/docs/RELEASING-MOBILE.md"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/quotakit-testflight-lane.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

assert_contains() {
  local path="$1"
  local expected="$2"
  grep -Fq -- "$expected" "$path" || fail "$path is missing: $expected"
}

assert_not_contains() {
  local path="$1"
  local unexpected="$2"
  if grep -Fq -- "$unexpected" "$path"; then
    fail "$path unexpectedly contains: $unexpected"
  fi
}

FAKE_DEVELOPER_DIR="$TEMP_DIR/FakeDeveloper"
FAKE_CLANG="$FAKE_DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
mkdir -p "$(dirname "$FAKE_CLANG")"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf '\''%s\n'\'' "$@"' > "$FAKE_CLANG"
chmod +x "$FAKE_CLANG"

DEVELOPER_DIR="$FAKE_DEVELOPER_DIR" "$CLANG_WRAPPER" \
  -v -E -dM -arch arm64 -isysroot /fake/iPhoneOS.sdk -x c -c /dev/null \
  > "$TEMP_DIR/probe.args"
if grep -Fxq -- '-v' "$TEMP_DIR/probe.args"; then
  fail "Xcode null-input macro probe retained -v"
fi
assert_contains "$TEMP_DIR/probe.args" '-E'
assert_contains "$TEMP_DIR/probe.args" '-dM'
assert_contains "$TEMP_DIR/probe.args" '/dev/null'

DEVELOPER_DIR="$FAKE_DEVELOPER_DIR" "$CLANG_WRAPPER" \
  -v -E -dM -x c project-source.c > "$TEMP_DIR/source-macro-dump.args"
assert_contains "$TEMP_DIR/source-macro-dump.args" '-v'

DEVELOPER_DIR="$FAKE_DEVELOPER_DIR" "$CLANG_WRAPPER" \
  -v -c project-source.c > "$TEMP_DIR/compile.args"
assert_contains "$TEMP_DIR/compile.args" '-v'

FAKE_BIN="$TEMP_DIR/fake-bin"
mkdir -p "$FAKE_BIN"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'case "${1:-}" in' \
  '  --version) printf "Version: %s\n" "${MOCK_XCODEGEN_VERSION:-2.45.4}" ;;' \
  '  generate) exit 0 ;;' \
  '  *) exit 2 ;;' \
  'esac' > "$FAKE_BIN/xcodegen"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ "${1:-}" == "find-identity" ]]; then' \
  '  if [[ "${MOCK_IDENTITY_AVAILABLE:-1}" == "1" ]]; then' \
  '    printf '\''  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Apple Distribution: Columbus Labs LLC (78PXX669LQ)"\n'\''' \
  '  fi' \
  'elif [[ "${1:-}" == "cms" ]]; then' \
  '  for arg in "$@"; do profile="$arg"; done' \
  '  cat "$profile"' \
  'else' \
  '  exit 2' \
  'fi' > "$FAKE_BIN/security"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'code_path=""' \
  'for arg in "$@"; do code_path="$arg"; done' \
  'printf '\''%s\n'\'' "$*" >> "${MOCK_CODESIGN_ARGS_LOG:?}"' \
  'if [[ " $* " == *" --verify "* && -n "${MOCK_CODESIGN_FAIL_PATH:-}" && "$code_path" == "$MOCK_CODESIGN_FAIL_PATH" ]]; then' \
  '  exit 1' \
  'fi' \
  'if [[ " $* " == *" --entitlements :- "* ]]; then' \
  '  cat "$code_path/MockSignedEntitlements.plist"' \
  'fi' \
  'if [[ " $* " == *" --extract-certificates "* ]]; then' \
  '  certificate_prefix=""' \
  '  expect_certificate_prefix=0' \
  '  for arg in "$@"; do' \
  '    if [[ "$expect_certificate_prefix" == 1 ]]; then certificate_prefix="$arg"; break; fi' \
  '    if [[ "$arg" == "--extract-certificates" ]]; then expect_certificate_prefix=1; fi' \
  '  done' \
  '  [[ -n "$certificate_prefix" ]] || exit 2' \
  '  printf "%s" "${MOCK_LEAF_CERTIFICATE_CONTENT:-mock-leaf-certificate}" > "${certificate_prefix}0"' \
  'fi' \
  'exit "${MOCK_CODESIGN_STATUS:-0}"' > "$FAKE_BIN/codesign"
chmod +x "$FAKE_BIN/xcodegen" "$FAKE_BIN/security" "$FAKE_BIN/codesign"

assert_contains "$RELEASE_SCRIPT" 'if [[ "$asc_auth_values" -ne 3 ]]'
assert_contains "$RELEASE_SCRIPT" 'API-key authentication is required; Xcode-account fallback is disabled.'
assert_contains "$RELEASE_SCRIPT" 'codesign --force --sign "$signing_identity_hash" --keychain "$LOGIN_KEYCHAIN"'
assert_contains "$RELEASE_SCRIPT" "printf '       security unlock-keychain %q\\n'"
assert_contains "$RELEASE_SCRIPT" 'Xcode GUI/account: not used'
assert_contains "$RELEASE_SCRIPT" 'PATH="$EXPORT_SYSTEM_PATH" /usr/bin/xcodebuild -exportArchive'
assert_contains "$RELEASE_SCRIPT" 'CLANG_PROBE_WORKAROUND_XCODE_BUILD="17F113"'
assert_contains "$RELEASE_SCRIPT" 'REQUIRED_XCODEGEN_VERSION="2.45.4"'
assert_contains "$RELEASE_SCRIPT" 'verify_archive_contents "$APP_PATH"'
assert_contains "$RELEASE_SCRIPT" 'codesign --verify --deep --strict "$app_path"'
assert_contains "$RELEASE_SCRIPT" 'codesign -d --extract-certificates "$certificate_prefix"'
assert_contains "$RELEASE_SCRIPT" 'DeveloperCertificates.$certificate_index'
assert_contains "$RELEASE_SCRIPT" 'CFBundleShortVersionString "$MARKETING"'
assert_contains "$RELEASE_SCRIPT" '/usr/bin/plutil -lint "$OPTIONS_PLIST"'
assert_contains "$RELEASE_SCRIPT" 'Entitlements:aps-environment production'
assert_contains "$RELEASE_SCRIPT" 'Entitlements:com.apple.developer.icloud-container-environment Production'
assert_contains "$RELEASE_SCRIPT" 'QUOTAKIT_DISABLE_CLANG_PROBE_WORKAROUND'
assert_contains "$RELEASE_SCRIPT" '-destination "generic/platform=iOS"'
assert_not_contains "$RELEASE_SCRIPT" "echo 'Xcode account'"

help_output=$($RELEASE_SCRIPT --help 2>&1)
grep -Fq 'Xcode-account authentication' <<<"$help_output" \
  || fail "release help does not declare API-key-only authentication"
grep -Fq -- '--preflight-only' <<<"$help_output" \
  || fail "release help does not expose the safe preflight"

if QUOTAKIT_RELEASE_SECRETS_LOADED=1 \
  APP_STORE_CONNECT_API_KEY_FILE='' \
  APP_STORE_CONNECT_KEY_ID='' \
  APP_STORE_CONNECT_ISSUER_ID='' \
  PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$RELEASE_SCRIPT" --preflight-only >"$TEMP_DIR/missing-auth.log" 2>&1
then
  fail "release preflight accepted missing App Store Connect API-key credentials"
fi
assert_contains "$TEMP_DIR/missing-auth.log" 'Xcode-account fallback is disabled'

if MOCK_XCODEGEN_VERSION=2.46.0 \
  PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$RELEASE_SCRIPT" --preflight-only >"$TEMP_DIR/wrong-xcodegen.log" 2>&1
then
  fail "release preflight accepted XcodeGen 2.46.0"
fi
assert_contains "$TEMP_DIR/wrong-xcodegen.log" 'XcodeGen 2.45.4 is required; found 2.46.0'
assert_contains "$TEMP_DIR/wrong-xcodegen.log" 'Put XcodeGen 2.45.4 first on PATH'

FAKE_API_KEY="$TEMP_DIR/AuthKey_TEST.p8"
FAKE_KEYCHAIN="$TEMP_DIR/test-signing.keychain-db"
touch "$FAKE_API_KEY" "$FAKE_KEYCHAIN"

run_preflight() {
  local output_path="$1"
  local identity_available="$2"
  local codesign_status="$3"
  QUOTAKIT_RELEASE_SECRETS_LOADED=1 \
  QUOTAKIT_SIGNING_KEYCHAIN="$FAKE_KEYCHAIN" \
  APP_STORE_CONNECT_API_KEY_FILE="$FAKE_API_KEY" \
  APP_STORE_CONNECT_KEY_ID=TESTKEY123 \
  APP_STORE_CONNECT_ISSUER_ID=00000000-0000-0000-0000-000000000000 \
  IOS_TEAM_ID=78PXX669LQ \
  MOCK_IDENTITY_AVAILABLE="$identity_available" \
  MOCK_CODESIGN_STATUS="$codesign_status" \
  MOCK_CODESIGN_ARGS_LOG="$TEMP_DIR/codesign.args" \
  PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$RELEASE_SCRIPT" --preflight-only >"$output_path" 2>&1
}

if run_preflight "$TEMP_DIR/missing-identity.log" 0 0; then
  fail "release preflight accepted a genuinely missing distribution identity"
fi
assert_contains "$TEMP_DIR/missing-identity.log" 'certificate/private-key pair is not installed'
assert_contains "$TEMP_DIR/missing-identity.log" 'This is the only release recovery that may require Xcode'

if run_preflight "$TEMP_DIR/locked-key.log" 1 1; then
  fail "release preflight accepted an unusable distribution private key"
fi
assert_contains "$TEMP_DIR/locked-key.log" 'private key is not usable for headless signing'
assert_contains "$TEMP_DIR/locked-key.log" "security unlock-keychain $FAKE_KEYCHAIN"

: > "$TEMP_DIR/codesign.args"
run_preflight "$TEMP_DIR/success.log" 1 0
assert_contains "$TEMP_DIR/success.log" 'App Store Connect auth: API key (required)'
assert_contains "$TEMP_DIR/success.log" 'Xcode GUI/account: not used'
assert_contains "$TEMP_DIR/success.log" 'Signing probe: passed'
assert_contains "$TEMP_DIR/success.log" 'Preflight complete; no project generation, archive, export, or upload performed'
assert_not_contains "$TEMP_DIR/success.log" 'Generating Xcode project'
assert_contains "$TEMP_DIR/codesign.args" "--keychain $FAKE_KEYCHAIN"

new_plist() {
  local plist="$1"
  printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0"><dict/></plist>' > "$plist"
}

plist_add() {
  local plist="$1"
  shift
  /usr/libexec/PlistBuddy "$@" "$plist"
}

create_info_plist() {
  local plist="$1"
  local bundle_id="$2"
  local build="$3"
  local marketing="$4"
  new_plist "$plist"
  plist_add "$plist" \
    -c "Add :CFBundleIdentifier string $bundle_id" \
    -c "Add :CFBundleVersion string $build" \
    -c "Add :CFBundleShortVersionString string $marketing"
}

create_entitlements() {
  local plist="$1"
  local bundle_id="$2"
  local app_group="$3"
  local cloudkit="$4"
  local push="$5"
  new_plist "$plist"
  plist_add "$plist" \
    -c 'Add :com.apple.developer.team-identifier string 78PXX669LQ' \
    -c "Add :application-identifier string 78PXX669LQ.$bundle_id"
  if [[ "$app_group" == 1 ]]; then
    plist_add "$plist" \
      -c 'Add :com.apple.security.application-groups array' \
      -c 'Add :com.apple.security.application-groups:0 string group.com.columbuslabs.quotakit'
  fi
  if [[ "$cloudkit" == 1 ]]; then
    plist_add "$plist" \
      -c 'Add :com.apple.developer.icloud-container-identifiers array' \
      -c 'Add :com.apple.developer.icloud-container-identifiers:0 string iCloud.com.columbuslabs.quotakit' \
      -c 'Add :com.apple.developer.icloud-services array' \
      -c 'Add :com.apple.developer.icloud-services:0 string CloudKit' \
      -c 'Add :com.apple.developer.icloud-container-environment string Production'
  fi
  if [[ "$push" == 1 ]]; then
    plist_add "$plist" -c 'Add :aps-environment string production'
  fi
}

create_profile() {
  local plist="$1"
  local bundle_id="$2"
  local app_group="$3"
  local cloudkit="$4"
  local push="$5"
  new_plist "$plist"
  plist_add "$plist" \
    -c 'Add :TeamIdentifier array' \
    -c 'Add :TeamIdentifier:0 string 78PXX669LQ' \
    -c 'Add :Entitlements dict' \
    -c 'Add :Entitlements:com.apple.developer.team-identifier string 78PXX669LQ' \
    -c "Add :Entitlements:application-identifier string 78PXX669LQ.$bundle_id"
  /usr/bin/plutil -insert DeveloperCertificates -array "$plist"
  /usr/bin/plutil -insert DeveloperCertificates.0 \
    -data bW9jay1sZWFmLWNlcnRpZmljYXRl "$plist"
  if [[ "$app_group" == 1 ]]; then
    plist_add "$plist" \
      -c 'Add :Entitlements:com.apple.security.application-groups array' \
      -c 'Add :Entitlements:com.apple.security.application-groups:0 string group.com.columbuslabs.quotakit'
  fi
  if [[ "$cloudkit" == 1 ]]; then
    plist_add "$plist" \
      -c 'Add :Entitlements:com.apple.developer.icloud-container-identifiers array' \
      -c 'Add :Entitlements:com.apple.developer.icloud-container-identifiers:0 string iCloud.com.columbuslabs.quotakit' \
      -c 'Add :Entitlements:com.apple.developer.icloud-services array' \
      -c 'Add :Entitlements:com.apple.developer.icloud-services:0 string CloudKit' \
      -c 'Add :Entitlements:com.apple.developer.icloud-container-environment string Production'
  fi
  if [[ "$push" == 1 ]]; then
    plist_add "$plist" -c 'Add :Entitlements:aps-environment string production'
  fi
}

create_bundle() {
  local bundle_path="$1"
  local bundle_id="$2"
  local app_group="$3"
  local cloudkit="$4"
  local push="$5"
  mkdir -p "$bundle_path"
  create_info_plist "$bundle_path/Info.plist" "$bundle_id" \
    "$PROJECT_BUILD" "$PROJECT_MARKETING"
  create_entitlements "$bundle_path/MockSignedEntitlements.plist" \
    "$bundle_id" "$app_group" "$cloudkit" "$push"
  create_profile "$bundle_path/embedded.mobileprovision" \
    "$bundle_id" "$app_group" "$cloudkit" "$push"
}

ARCHIVE_PATH="$TEMP_DIR/QuotaKit.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/QuotaKit.app"
PUSH_PATH="$APP_PATH/PlugIns/CodexBarMobilePushExtension.appex"
WIDGET_PATH="$APP_PATH/PlugIns/CodexBarMobileWidgets.appex"
FRAMEWORK_PATH="$APP_PATH/Frameworks/Mock.framework"
DYLIB_PATH="$PUSH_PATH/Frameworks/libMock.dylib"
PROJECT_BUILD=$(awk '/CURRENT_PROJECT_VERSION:/ {gsub(/"/, "", $2); print $2; exit}' \
  "$ROOT/CodexBarMobile/project.yml")
PROJECT_MARKETING=$(awk '/MARKETING_VERSION:/ {gsub(/"/, "", $2); print $2; exit}' \
  "$ROOT/CodexBarMobile/project.yml")

create_archive() {
  /bin/rm -rf "$ARCHIVE_PATH"
  mkdir -p "$ARCHIVE_PATH"
  new_plist "$ARCHIVE_PATH/Info.plist"
  plist_add "$ARCHIVE_PATH/Info.plist" \
    -c 'Add :ApplicationProperties dict' \
    -c 'Add :ApplicationProperties:ApplicationPath string Applications/QuotaKit.app' \
    -c 'Add :ApplicationProperties:CFBundleIdentifier string com.columbuslabs.quotakit.ios' \
    -c "Add :ApplicationProperties:CFBundleVersion string $PROJECT_BUILD" \
    -c 'Add :ApplicationProperties:Team string 78PXX669LQ'
  create_bundle "$APP_PATH" com.columbuslabs.quotakit.ios 1 1 1
  create_bundle "$PUSH_PATH" com.columbuslabs.quotakit.ios.pushextension 0 1 0
  create_bundle "$WIDGET_PATH" com.columbuslabs.quotakit.ios.widgets 1 0 0
  mkdir -p "$FRAMEWORK_PATH" "$(dirname "$DYLIB_PATH")"
  : > "$DYLIB_PATH"
}

run_archive_validation() {
  local output_path="$1"
  local codesign_fail_path="${2:-}"
  : > "$TEMP_DIR/codesign.args"
  QUOTAKIT_RELEASE_SECRETS_LOADED=1 \
  QUOTAKIT_SIGNING_KEYCHAIN="$FAKE_KEYCHAIN" \
  APP_STORE_CONNECT_API_KEY_FILE="$FAKE_API_KEY" \
  APP_STORE_CONNECT_KEY_ID=TESTKEY123 \
  APP_STORE_CONNECT_ISSUER_ID=00000000-0000-0000-0000-000000000000 \
  IOS_TEAM_ID=78PXX669LQ \
  MOCK_IDENTITY_AVAILABLE=1 \
  MOCK_CODESIGN_STATUS=0 \
  MOCK_CODESIGN_FAIL_PATH="$codesign_fail_path" \
  MOCK_LEAF_CERTIFICATE_CONTENT=mock-leaf-certificate \
  MOCK_CODESIGN_ARGS_LOG="$TEMP_DIR/codesign.args" \
  PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$RELEASE_SCRIPT" --skip-lint --skip-archive --archive-only \
      --archive-path "$ARCHIVE_PATH" >"$output_path" 2>&1
}

expect_archive_failure() {
  local name="$1"
  local expected="$2"
  local codesign_fail_path="${3:-}"
  local output_path="$TEMP_DIR/$name.log"
  if run_archive_validation "$output_path" "$codesign_fail_path"; then
    cat "$output_path" >&2
    fail "$name archive validation unexpectedly succeeded"
  fi
  assert_contains "$output_path" "$expected"
}

create_archive
run_archive_validation "$TEMP_DIR/archive-success.log"
assert_contains "$TEMP_DIR/archive-success.log" 'Archive validation passed'
assert_contains "$TEMP_DIR/archive-success.log" \
  "main app: com.columbuslabs.quotakit.ios $PROJECT_MARKETING ($PROJECT_BUILD), signed by 78PXX669LQ"
assert_contains "$TEMP_DIR/archive-success.log" 'push extension: com.columbuslabs.quotakit.ios.pushextension'
assert_contains "$TEMP_DIR/archive-success.log" 'widget extension: com.columbuslabs.quotakit.ios.widgets'
assert_contains "$TEMP_DIR/codesign.args" "--entitlements :- $APP_PATH"
assert_contains "$TEMP_DIR/codesign.args" "--entitlements :- $PUSH_PATH"
assert_contains "$TEMP_DIR/codesign.args" "--entitlements :- $WIDGET_PATH"
assert_contains "$TEMP_DIR/codesign.args" "--verify --deep --strict $APP_PATH"
assert_contains "$TEMP_DIR/codesign.args" "--verify --strict $FRAMEWORK_PATH"
assert_contains "$TEMP_DIR/codesign.args" "--verify --strict $DYLIB_PATH"
assert_contains "$TEMP_DIR/codesign.args" "--extract-certificates"

create_archive
/usr/libexec/PlistBuddy -c 'Set :ApplicationProperties:Team WRONGTEAM' "$ARCHIVE_PATH/Info.plist"
expect_archive_failure wrong-archive-team "archive metadata has invalid ApplicationProperties:Team"

create_archive
mv "$PUSH_PATH" "$TEMP_DIR/missing-push-extension.appex"
expect_archive_failure missing-push-extension 'Missing push extension bundle'

create_archive
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.example.wrong' "$WIDGET_PATH/Info.plist"
expect_archive_failure wrong-widget-id "expected 'com.columbuslabs.quotakit.ios.widgets', found 'com.example.wrong'"

create_archive
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 9999' "$PUSH_PATH/Info.plist"
expect_archive_failure wrong-build "expected '$PROJECT_BUILD', found '9999'"

create_archive
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 9.9.9' "$WIDGET_PATH/Info.plist"
expect_archive_failure wrong-marketing "expected '$PROJECT_MARKETING', found '9.9.9'"

create_archive
/usr/libexec/PlistBuddy -c 'Set :com.apple.developer.team-identifier WRONGTEAM' \
  "$APP_PATH/MockSignedEntitlements.plist"
expect_archive_failure wrong-team "expected '78PXX669LQ', found 'WRONGTEAM'"

create_archive
/usr/libexec/PlistBuddy -c 'Set :application-identifier 78PXX669LQ.com.example.wrong' \
  "$PUSH_PATH/MockSignedEntitlements.plist"
expect_archive_failure mismatched-signed-app-id \
  "push extension signed entitlements has invalid application-identifier"

create_archive
/usr/bin/plutil -remove DeveloperCertificates "$WIDGET_PATH/embedded.mobileprovision"
/usr/bin/plutil -insert DeveloperCertificates -array "$WIDGET_PATH/embedded.mobileprovision"
/usr/bin/plutil -insert DeveloperCertificates.0 \
  -data cHJvZmlsZS1vdGhlci1jZXJ0aWZpY2F0ZQ== \
  "$WIDGET_PATH/embedded.mobileprovision"
profile_certificate=$(/usr/bin/plutil -extract DeveloperCertificates.0 raw \
  -expect data -o - "$WIDGET_PATH/embedded.mobileprovision" | /usr/bin/base64 --decode)
[[ "$profile_certificate" == "profile-other-certificate" ]] \
  || fail "profile/leaf mismatch fixture did not replace the profile certificate"
expect_archive_failure mismatched-profile-leaf-certificate \
  "widget extension leaf signing certificate is not present in its embedded provisioning profile"

create_archive
expect_archive_failure nested-signature-failure \
  "failed strict code-signature verification" "$FRAMEWORK_PATH"

create_archive
mkdir -p "$APP_PATH/PlugIns/UnexpectedExtension.appex"
expect_archive_failure unexpected-extension \
  "Unexpected embedded app extension: $APP_PATH/PlugIns/UnexpectedExtension.appex"

create_archive
/usr/libexec/PlistBuddy -c 'Delete :com.apple.security.application-groups' \
  "$WIDGET_PATH/MockSignedEntitlements.plist"
expect_archive_failure missing-app-group "missing 'group.com.columbuslabs.quotakit'"

create_archive
/usr/libexec/PlistBuddy -c 'Set :Entitlements:com.apple.developer.icloud-container-environment Development' \
  "$PUSH_PATH/embedded.mobileprovision"
expect_archive_failure development-cloudkit "expected 'Production', found 'Development'"

create_archive
/usr/libexec/PlistBuddy -c 'Set :aps-environment development' \
  "$APP_PATH/MockSignedEntitlements.plist"
expect_archive_failure development-push "expected 'production', found 'development'"

assert_contains "$MOBILE_RELEASE_DOC" 'A locked or unavailable paired iPhone is non-blocking'
assert_contains "$MOBILE_RELEASE_DOC" 'The Xcode GUI is not part of this workflow'
assert_contains "$MOBILE_RELEASE_DOC" 'QUOTAKIT_DISABLE_CLANG_PROBE_WORKAROUND=1'
assert_contains "$MOBILE_RELEASE_DOC" 'XcodeGen 2.45.4'
assert_contains "$MOBILE_RELEASE_DOC" '090ec29491aad50aec10631bf6e62253fed733c50f3aab0f5ffc86bc170bdbef'
assert_contains "$MOBILE_RELEASE_DOC" 'releases/download/$xcodegen_version/xcodegen.zip'
assert_contains "$MOBILE_RELEASE_DOC" 'fails closed before upload'
assert_contains "$MOBILE_RELEASE_DOC" '`DeveloperCertificates` entry'

echo "iOS TestFlight release-lane tests passed."
