#!/usr/bin/env bash
set -euo pipefail

APP_IDENTITY="${APP_IDENTITY:-}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/version.env"
if [[ -f "$ROOT/.mac-release.env" ]]; then
  source "$ROOT/.mac-release.env"
fi
APP_NAME="${MAC_RELEASE_APP_NAME:-QuotaKit}"
APP_EXECUTABLE="${MAC_RELEASE_APP_EXECUTABLE:-QuotaKit}"
APP_SWIFTPM_PRODUCT="${MAC_RELEASE_APP_SWIFTPM_PRODUCT:-CodexBar}"
CLI_EXECUTABLE_NAME="${MAC_RELEASE_CLI_EXECUTABLE:-QuotaKitCLI}"
WATCHDOG_EXECUTABLE_NAME="${MAC_RELEASE_WATCHDOG_EXECUTABLE:-QuotaKitClaudeWatchdog}"
WIDGET_PRODUCT_NAME="${MAC_RELEASE_WIDGET_PRODUCT_NAME:-QuotaKitWidget}"
APP_BUNDLE="${APP_NAME}.app"
# Load local-only release secrets from ~/.quotakit-secrets if available.
source "$ROOT/Scripts/load-release-secrets.sh"
if [[ -z "$APP_IDENTITY" ]]; then
  echo "Set APP_IDENTITY to a QuotaKit-owned Developer ID identity." >&2
  exit 1
fi
RELEASE_ASSET_BASENAME="${MAC_RELEASE_APP_NAME:-$APP_NAME}-macos-universal-${MARKETING_VERSION}"
ZIP_NAME="${RELEASE_ASSET_BASENAME}.zip"
DMG_NAME="${RELEASE_ASSET_BASENAME}.dmg"
DSYM_ZIP="${RELEASE_ASSET_BASENAME}.dSYM.zip"
RELEASE_STAGE_DIR=$(mktemp -d /tmp/quotakit-release.XXXXXX)
STAGED_APP_BUNDLE="${RELEASE_STAGE_DIR}/${APP_BUNDLE}"

verify_distribution_policy() {
  local app=$1
  if command -v syspolicy_check >/dev/null 2>&1; then
    syspolicy_check distribution "$app"
  else
    spctl -a -t exec -vv "$app"
  fi
}

if [[ -z "${APP_STORE_CONNECT_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  echo "Missing App Store Connect release settings (key id or issuer id)." >&2
  exit 1
fi
if [[ -z "${APP_STORE_CONNECT_API_KEY_FILE:-}" && -z "${APP_STORE_CONNECT_API_KEY_P8:-}" ]]; then
  echo "Set APP_STORE_CONNECT_API_KEY_FILE or APP_STORE_CONNECT_API_KEY_P8." >&2
  exit 1
fi
if [[ -z "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  echo "SPARKLE_PRIVATE_KEY_FILE is required for release signing/verification." >&2
  exit 1
fi
if [[ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
  echo "Sparkle key file not found: $SPARKLE_PRIVATE_KEY_FILE" >&2
  exit 1
fi
key_lines=$(grep -v '^[[:space:]]*#' "$SPARKLE_PRIVATE_KEY_FILE" | sed '/^[[:space:]]*$/d')
if [[ $(printf "%s\n" "$key_lines" | wc -l) -ne 1 ]]; then
  echo "Sparkle key file must contain exactly one base64 line (no comments/blank lines)." >&2
  exit 1
fi

# Notarization API key + zip live in a private per-run temp dir (upstream
# #1228), not predictable /tmp paths. Fork keeps dual _FILE/_P8 support and
# its own mobile-suffixed ZIP_NAME / DSYM_ZIP (defined near the top), so we do
# NOT use upstream's codexbar_app_zip_name (which drops the -mobile.X suffix
# that release.sh / make_appcast expect).
NOTARIZATION_TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/quotakit-notarize.XXXXXX")
chmod 700 "$NOTARIZATION_TEMP_DIR"
API_KEY_PATH="$NOTARIZATION_TEMP_DIR/quotakit-api-key.p8"
NOTARIZATION_ZIP="$NOTARIZATION_TEMP_DIR/${APP_NAME}Notarize.zip"
trap 'rm -rf "$NOTARIZATION_TEMP_DIR" "$RELEASE_STAGE_DIR"' EXIT

if [[ -n "${APP_STORE_CONNECT_API_KEY_FILE:-}" ]]; then
  if [[ ! -f "$APP_STORE_CONNECT_API_KEY_FILE" ]]; then
    echo "App Store Connect API key file not found: $APP_STORE_CONNECT_API_KEY_FILE" >&2
    exit 1
  fi
  ( umask 077; cp "$APP_STORE_CONNECT_API_KEY_FILE" "$API_KEY_PATH" )
else
  ( umask 077; printf '%s' "$APP_STORE_CONNECT_API_KEY_P8" | sed 's/\\n/\n/g' > "$API_KEY_PATH" )
fi
chmod 600 "$API_KEY_PATH"

# Allow building a universal binary if ARCHES is provided; default to universal (arm64 + x86_64).
ARCHES_VALUE=${ARCHES:-"arm64 x86_64"}
ARCH_LIST=( ${ARCHES_VALUE} )
for ARCH in "${ARCH_LIST[@]}"; do
  swift build -c release --arch "$ARCH"
done
CODEXBAR_STAGED_APP_PATH="$STAGED_APP_BUNDLE" CODEXBAR_WIDGET_METADATA_MODE=required CODEXBAR_SIGNING=identity ARCHES="${ARCHES_VALUE}" ./Scripts/package_app.sh release
APP_BUNDLE="$STAGED_APP_BUNDLE"

ENTITLEMENTS_DIR="$ROOT/.build/entitlements"
APP_ENTITLEMENTS="${ENTITLEMENTS_DIR}/${APP_EXECUTABLE}.entitlements"
WIDGET_ENTITLEMENTS="${ENTITLEMENTS_DIR}/${WIDGET_PRODUCT_NAME}.entitlements"

echo "Signing with $APP_IDENTITY"
if [[ -f "$APP_BUNDLE/Contents/Helpers/${CLI_EXECUTABLE_NAME}" ]]; then
  codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" \
    "$APP_BUNDLE/Contents/Helpers/${CLI_EXECUTABLE_NAME}"
fi
if [[ -f "$APP_BUNDLE/Contents/Helpers/${WATCHDOG_EXECUTABLE_NAME}" ]]; then
  codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" \
    "$APP_BUNDLE/Contents/Helpers/${WATCHDOG_EXECUTABLE_NAME}"
fi
if [[ -d "$APP_BUNDLE/Contents/PlugIns/${WIDGET_PRODUCT_NAME}.appex" ]]; then
  codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" \
    --entitlements "$WIDGET_ENTITLEMENTS" \
    "$APP_BUNDLE/Contents/PlugIns/${WIDGET_PRODUCT_NAME}.appex/Contents/MacOS/${WIDGET_PRODUCT_NAME}"
  codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" \
    --entitlements "$WIDGET_ENTITLEMENTS" \
    "$APP_BUNDLE/Contents/PlugIns/${WIDGET_PRODUCT_NAME}.appex"
fi
codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" \
  --entitlements "$APP_ENTITLEMENTS" \
  "$APP_BUNDLE"

DITTO_BIN=${DITTO_BIN:-/usr/bin/ditto}
"$DITTO_BIN" --norsrc -c -k --keepParent "$APP_BUNDLE" "$NOTARIZATION_ZIP"

echo "Submitting for notarization"
xcrun notarytool submit "$NOTARIZATION_ZIP" \
  --key "$API_KEY_PATH" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait

echo "Stapling ticket"
xcrun stapler staple "$APP_BUNDLE"

# Strip any extended attributes that would create AppleDouble files when zipping
xattr -cr "$APP_BUNDLE"
find "$APP_BUNDLE" -name '._*' -delete

"$DITTO_BIN" --norsrc -c -k --keepParent "$APP_BUNDLE" "$ZIP_NAME"
"$ROOT/Scripts/create-dmg.sh" "$APP_BUNDLE" "$DMG_NAME" "$APP_NAME"
codesign --force --timestamp --sign "$APP_IDENTITY" "$DMG_NAME"

echo "Submitting DMG for notarization"
xcrun notarytool submit "$DMG_NAME" \
  --key "$API_KEY_PATH" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait

echo "Stapling DMG ticket"
xcrun stapler staple "$DMG_NAME"

verify_distribution_policy "$APP_BUNDLE"
stapler validate "$APP_BUNDLE"
spctl -a -t open --context context:primary-signature -vv "$DMG_NAME"
stapler validate "$DMG_NAME"

# Launch verification — last gate before declaring the build good.
# spctl / stapler / notarization passed, but those checks don't cover
# every failure mode. Most notably: a bundle missing
# Contents/embedded.provisionprofile passes all of the above but is
# rejected by AMFI at launch time with "Launchd job spawn failed"
# (POSIX 163). The only way to catch this class of failure is to
# actually try to launch the binary.
echo "Launch verification — direct exec of stapled bundle, must stay alive 2s"
"$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE" >/dev/null 2>&1 &
LAUNCH_TEST_PID=$!
sleep 2
if kill -0 "$LAUNCH_TEST_PID" 2>/dev/null; then
  kill -TERM "$LAUNCH_TEST_PID" 2>/dev/null || true
  sleep 1
  if kill -0 "$LAUNCH_TEST_PID" 2>/dev/null; then
    kill -KILL "$LAUNCH_TEST_PID" 2>/dev/null || true
  fi
  wait "$LAUNCH_TEST_PID" 2>/dev/null || true
  echo "Launch verification: OK"
else
  wait "$LAUNCH_TEST_PID" 2>/dev/null || true
  echo "" >&2
  echo "FATAL: $APP_NAME exited within 2s of launch." >&2
  echo "  spctl, stapler, and notarization all passed, but AMFI / Launch" >&2
  echo "  Services rejected the binary at runtime. Most common cause:" >&2
  echo "  Contents/embedded.provisionprofile is missing or malformed" >&2
  echo "  (entitlements with com.apple.application-identifier require it)." >&2
  echo "" >&2
  echo "  Inspect: ls -la \"$APP_BUNDLE/Contents/embedded.provisionprofile\"" >&2
  echo "  Reproduce:  \"$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE\"" >&2
  echo "" >&2
  echo "  Refusing to publish — removing $ZIP_NAME." >&2
  rm -f "$ZIP_NAME"
  exit 1
fi

echo "Packaging dSYM"
FIRST_ARCH="${ARCH_LIST[0]}"
PREFERRED_ARCH_DIR=".build/${FIRST_ARCH}-apple-macosx/release"
DSYM_PATH="${PREFERRED_ARCH_DIR}/${APP_EXECUTABLE}.dSYM"
SOURCE_DSYM_PATH="${PREFERRED_ARCH_DIR}/${APP_SWIFTPM_PRODUCT}.dSYM"
if [[ ! -d "$DSYM_PATH" && -d "$SOURCE_DSYM_PATH" ]]; then
  if [[ ${#ARCH_LIST[@]} -gt 1 ]]; then
    DSYM_PATH="${RELEASE_STAGE_DIR}/base-${APP_EXECUTABLE}.dSYM"
  else
    DSYM_PATH="${RELEASE_STAGE_DIR}/${APP_EXECUTABLE}.dSYM"
  fi
  cp -R "$SOURCE_DSYM_PATH" "$DSYM_PATH"
  if [[ -f "$DSYM_PATH/Contents/Resources/DWARF/${APP_SWIFTPM_PRODUCT}" ]]; then
    mv "$DSYM_PATH/Contents/Resources/DWARF/${APP_SWIFTPM_PRODUCT}" \
      "$DSYM_PATH/Contents/Resources/DWARF/${APP_EXECUTABLE}"
  fi
fi
if [[ ! -d "$DSYM_PATH" ]]; then
  echo "Missing dSYM at $DSYM_PATH" >&2
  exit 1
fi
if [[ ${#ARCH_LIST[@]} -gt 1 ]]; then
  MERGED_DSYM="${RELEASE_STAGE_DIR}/${APP_EXECUTABLE}.dSYM"
  rm -rf "$MERGED_DSYM"
  cp -R "$DSYM_PATH" "$MERGED_DSYM"
  DWARF_PATH="${MERGED_DSYM}/Contents/Resources/DWARF/${APP_EXECUTABLE}"
  BINARIES=()
  for ARCH in "${ARCH_LIST[@]}"; do
    ARCH_DSYM=".build/${ARCH}-apple-macosx/release/${APP_SWIFTPM_PRODUCT}.dSYM/Contents/Resources/DWARF/${APP_SWIFTPM_PRODUCT}"
    if [[ ! -f "$ARCH_DSYM" ]]; then
      echo "Missing dSYM for ${ARCH} at $ARCH_DSYM" >&2
      exit 1
    fi
    BINARIES+=("$ARCH_DSYM")
  done
  lipo -create "${BINARIES[@]}" -output "$DWARF_PATH"
  DSYM_PATH="$MERGED_DSYM"
fi
"$DITTO_BIN" --norsrc -c -k --keepParent "$DSYM_PATH" "$DSYM_ZIP"

echo "Done: $DMG_NAME $ZIP_NAME"
