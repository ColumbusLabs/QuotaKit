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

assert_contains "$RELEASE_SCRIPT" 'if [[ "$asc_auth_values" -ne 3 ]]'
assert_contains "$RELEASE_SCRIPT" 'API-key authentication is required; Xcode-account fallback is disabled.'
assert_contains "$RELEASE_SCRIPT" 'codesign --force --sign "$signing_identity_hash" --keychain "$LOGIN_KEYCHAIN"'
assert_contains "$RELEASE_SCRIPT" "printf '       security unlock-keychain %q\\n'"
assert_contains "$RELEASE_SCRIPT" 'Xcode GUI/account: not used'
assert_contains "$RELEASE_SCRIPT" 'PATH="$EXPORT_SYSTEM_PATH" /usr/bin/xcodebuild -exportArchive'
assert_contains "$RELEASE_SCRIPT" 'CLANG_PROBE_WORKAROUND_XCODE_BUILD="17F113"'
assert_contains "$RELEASE_SCRIPT" 'QUOTAKIT_DISABLE_CLANG_PROBE_WORKAROUND'
assert_contains "$RELEASE_SCRIPT" '-destination "generic/platform=iOS"'
assert_not_contains "$RELEASE_SCRIPT" "echo 'Xcode account'"

help_output=$($RELEASE_SCRIPT --help 2>&1)
grep -Fq 'Xcode-account authentication' <<<"$help_output" \
  || fail "release help does not declare API-key-only authentication"
grep -Fq -- '--preflight-only' <<<"$help_output" \
  || fail "release help does not expose the safe preflight"

if QUOTAKIT_RELEASE_SECRETS_LOADED=1 \
  APP_STORE_CONNECT_API_KEY_FILE= \
  APP_STORE_CONNECT_KEY_ID= \
  APP_STORE_CONNECT_ISSUER_ID= \
  "$RELEASE_SCRIPT" --preflight-only >"$TEMP_DIR/missing-auth.log" 2>&1
then
  fail "release preflight accepted missing App Store Connect API-key credentials"
fi
assert_contains "$TEMP_DIR/missing-auth.log" 'Xcode-account fallback is disabled'

FAKE_BIN="$TEMP_DIR/fake-bin"
mkdir -p "$FAKE_BIN"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ "${MOCK_IDENTITY_AVAILABLE:-1}" == "1" ]]; then' \
  '  printf '\''  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Apple Distribution: Columbus Labs LLC (78PXX669LQ)"\n'\''' \
  'fi' > "$FAKE_BIN/security"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf '\''%s\n'\'' "$*" >> "${MOCK_CODESIGN_ARGS_LOG:?}"' \
  'exit "${MOCK_CODESIGN_STATUS:-0}"' > "$FAKE_BIN/codesign"
chmod +x "$FAKE_BIN/security" "$FAKE_BIN/codesign"

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

assert_contains "$MOBILE_RELEASE_DOC" 'A locked or unavailable paired iPhone is non-blocking'
assert_contains "$MOBILE_RELEASE_DOC" 'The Xcode GUI is not part of this workflow'
assert_contains "$MOBILE_RELEASE_DOC" 'QUOTAKIT_DISABLE_CLANG_PROBE_WORKAROUND=1'

echo "iOS TestFlight release-lane tests passed."
