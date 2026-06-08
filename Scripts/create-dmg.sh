#!/usr/bin/env bash
set -euo pipefail

APP_PATH=${1:?"Usage: $0 /path/to/QuotaKit.app /path/to/QuotaKit.dmg [VolumeName]"}
DMG_PATH=${2:?"Usage: $0 /path/to/QuotaKit.app /path/to/QuotaKit.dmg [VolumeName]"}
VOL_NAME=${3:-QuotaKit}

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

APP_NAME=$(basename "$APP_PATH")
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/quotakit-dmg.XXXXXX")
RW_DMG="$WORK_DIR/${VOL_NAME}.rw.dmg"
MOUNT_DIR="$WORK_DIR/mount"
mkdir -p "$MOUNT_DIR"
cleanup() {
  hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

APP_SIZE_MB=$(du -sm "$APP_PATH" | awk '{print $1}')
DMG_SIZE_MB=$((APP_SIZE_MB + 96))

rm -f "$DMG_PATH"
hdiutil create \
  -size "${DMG_SIZE_MB}m" \
  -fs HFS+ \
  -volname "$VOL_NAME" \
  -ov \
  "$RW_DMG" >/dev/null

hdiutil attach \
  -readwrite \
  -noverify \
  -noautoopen \
  -mountpoint "$MOUNT_DIR" \
  "$RW_DMG" >/dev/null

ditto --noextattr --noqtn "$APP_PATH" "$MOUNT_DIR/$APP_NAME"
ln -s /Applications "$MOUNT_DIR/Applications"

# Best-effort Finder layout. This is skipped in headless contexts.
osascript >/dev/null 2>&1 <<OSA || true
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {100, 100, 640, 420}
    set arrangement of icon view options of container window to not arranged
    set icon size of icon view options of container window to 96
    set position of item "$APP_NAME" of container window to {170, 160}
    set position of item "Applications" of container window to {420, 160}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA

sync
hdiutil detach "$MOUNT_DIR" -quiet
hdiutil convert \
  "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH" >/dev/null

hdiutil verify "$DMG_PATH" >/dev/null
echo "Created $DMG_PATH"
