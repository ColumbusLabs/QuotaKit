#!/usr/bin/env bash
#
# Archive the iOS app (CodexBarMobile) and upload to TestFlight via
# App Store Connect API key.
#
# Required env (loaded from ~/.codexbar-secrets/codexbar-release.env):
#   APP_STORE_CONNECT_KEY_ID
#   APP_STORE_CONNECT_ISSUER_ID
#   APP_STORE_CONNECT_API_KEY_FILE  (path to .p8)
#
# Usage: ./Scripts/upload_ios_testflight.sh
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# shellcheck disable=SC1091
source "$ROOT/Scripts/load-release-secrets.sh"

if [[ -z "${APP_STORE_CONNECT_KEY_ID:-}" \
   || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" \
   || -z "${APP_STORE_CONNECT_API_KEY_FILE:-}" ]]; then
  echo "ERROR: App Store Connect credentials missing" >&2
  exit 1
fi

if [[ ! -f "$APP_STORE_CONNECT_API_KEY_FILE" ]]; then
  echo "ERROR: API key file not found: $APP_STORE_CONNECT_API_KEY_FILE" >&2
  exit 1
fi

STAMP=$(date +%Y%m%d-%H%M%S)
ARCHIVE_PATH="/tmp/CodexBarMobile-$STAMP.xcarchive"
EXPORT_PATH="/tmp/CodexBarMobile-$STAMP-export"
OPTIONS_PLIST=$(mktemp /tmp/cbm-export-options.XXXXXX.plist)

cat > "$OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>3TUERHN53E</string>
    <key>uploadSymbols</key>
    <true/>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
PLIST

# Provisioning profiles are auto-created by -allowProvisioningUpdates, which
# uses the App Store Connect API key to fetch / generate profiles + register
# devices. No Keychain-based Apple ID fallback needed.
echo "==> Archiving CodexBarMobile (Build $(grep CURRENT_PROJECT_VERSION CodexBarMobile/project.yml | head -1 | awk '{print $2}' | tr -d '"'))..."
xcodebuild archive \
  -project CodexBarMobile/CodexBarMobile.xcodeproj \
  -scheme CodexBarMobile \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$APP_STORE_CONNECT_API_KEY_FILE" \
  -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID" \
  | tail -40

echo ""
echo "==> Exporting .ipa from archive..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$OPTIONS_PLIST" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$APP_STORE_CONNECT_API_KEY_FILE" \
  -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID" \
  | tail -40

IPA=$(find "$EXPORT_PATH" -name "*.ipa" | head -1)
if [[ -z "$IPA" ]]; then
  echo "ERROR: no .ipa produced at $EXPORT_PATH" >&2
  exit 1
fi
echo ""
echo "==> Uploading $IPA to TestFlight..."
xcrun altool --upload-app \
  --type ios \
  --file "$IPA" \
  --apiKey "$APP_STORE_CONNECT_KEY_ID" \
  --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"

echo ""
echo "==> Upload complete. ASC will now process + email when TestFlight is ready (~5-30 min)."
echo "Archive: $ARCHIVE_PATH"
echo "IPA:     $IPA"
rm -f "$OPTIONS_PLIST"
