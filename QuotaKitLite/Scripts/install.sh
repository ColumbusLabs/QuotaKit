#!/usr/bin/env bash
# Builds QuotaKit Lite from source, signs it, installs it to ~/Applications and relaunches it.
# See CodexBarMobile/Research/068-quotakit-lite-mac.md §3.2 and §6.5.
#
# CloudKit (iPhone sync) needs the "QuotaKit Lite Developer ID" provisioning profile at
# Provisioning/QuotaKitLite.provisionprofile (gitignored) or $LITE_PROVISIONING_PROFILE.
# Without it the app is still built and installed, just without the CloudKit entitlement.

set -euo pipefail

LITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_DIR="$(cd "$LITE_DIR/.." && pwd)"

APP_NAME="QuotaKit Lite"
EXECUTABLE="QuotaKitLite"
BUNDLE_ID="com.columbuslabs.quotakit.lite"
TEAM_ID="78PXX669LQ"
IDENTITY="${LITE_SIGNING_IDENTITY:-Developer ID Application: Columbus Labs LLC (${TEAM_ID})}"
PROFILE="${LITE_PROVISIONING_PROFILE:-$ROOT_DIR/Provisioning/QuotaKitLite.provisionprofile}"
INSTALL_DIR="${LITE_INSTALL_DIR:-$HOME/Applications}"
APP="$LITE_DIR/.build/app/$APP_NAME.app"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"

fail() {
  echo "error: $*" >&2
  exit 1
}

cd "$LITE_DIR"
swift build -c release --product "$EXECUTABLE"
BIN_PATH="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$LITE_DIR/App/Info.plist" "$APP/Contents/Info.plist"
cp "$LITE_DIR"/Resources/*.svg "$LITE_DIR"/Resources/*.png "$APP/Contents/Resources/"
cp "$LITE_DIR/App/Icon.icns" "$APP/Contents/Resources/Icon.icns"

sign_args=(--force --options runtime --timestamp=none --sign "$IDENTITY")
if [[ -f "$PROFILE" ]]; then
  profile_app_id="$(/usr/bin/security cms -D -i "$PROFILE" \
    | /usr/bin/plutil -extract 'Entitlements.com\.apple\.application-identifier' raw -)"
  [[ "$profile_app_id" == "$TEAM_ID.$BUNDLE_ID" ]] \
    || fail "profile $PROFILE is for $profile_app_id, expected $TEAM_ID.$BUNDLE_ID"
  cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
  sign_args+=(--entitlements "$LITE_DIR/App/QuotaKitLite.entitlements")
  cloudkit="enabled"
else
  echo "warning: no provisioning profile at $PROFILE; installing without CloudKit (no iPhone sync)" >&2
  cloudkit="disabled"
fi
codesign "${sign_args[@]}" "$APP"
codesign --verify --strict "$APP"

# Replace a running copy. SIGTERM is enough: Lite persists state as it changes, not on quit.
if pgrep -xq "$EXECUTABLE"; then
  pkill -TERM -x "$EXECUTABLE" || true
  for _ in {1..50}; do
    pgrep -xq "$EXECUTABLE" || break
    sleep 0.1
  done
  pgrep -xq "$EXECUTABLE" && fail "$EXECUTABLE did not quit"
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED_APP"
ditto "$APP" "$INSTALLED_APP"
echo "installed $INSTALLED_APP ($(du -sh "$INSTALLED_APP" | cut -f1), CloudKit $cloudkit)"

if [[ "${LITE_NO_LAUNCH:-0}" != "1" ]]; then
  open "$INSTALLED_APP"
fi
