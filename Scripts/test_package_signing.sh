#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PACKAGE_SCRIPT="$ROOT/Scripts/package_app.sh"
RELEASE_SCRIPT="$ROOT/Scripts/sign-and-notarize.sh"
FUNCTIONS_FILE=$(mktemp "${TMPDIR:-/tmp}/codexbar-package-signing-functions.XXXXXX")
trap 'rm -f "$FUNCTIONS_FILE"' EXIT

python3 - "$PACKAGE_SCRIPT" "$FUNCTIONS_FILE" <<'PY'
import plistlib
import re
import subprocess
import sys
from pathlib import Path

script = Path(sys.argv[1]).read_text()
# Exercise the production parser with real pipe input; plistlib.load requires
# a seekable stream on Python 3.14, while security cms writes to a pipe.
profile_parser = re.search(
    r"PROFILE_TEAM_ID=.*?\| python3 -c\s+'([^']+)'", script
).group(1)
for fmt in (plistlib.FMT_XML, plistlib.FMT_BINARY):
    payload = plistlib.dumps({"TeamIdentifier": ["FIXTURE123"]}, fmt=fmt)
    result = subprocess.run(
        [sys.executable, "-c", profile_parser], input=payload, capture_output=True
    )
    assert result.returncode == 0, result.stderr.decode()
    assert result.stdout.strip() == b"FIXTURE123"
for payload in (b"invalid profile", plistlib.dumps({"TeamIdentifier": []})):
    result = subprocess.run(
        [sys.executable, "-c", profile_parser], input=payload, capture_output=True
    )
    assert result.returncode != 0, "Malformed profile unexpectedly passed"

functions = []
for name in (
    'resolve_package_signing_mode',
    'verify_no_quarantine_attribute',
    'verify_packaged_app_integrity',
    'resign_sparkle_framework',
):
    start = script.index(f'{name}() {{')
    end = script.index('\n}\n', start) + 3
    functions.append(script[start:end])
Path(sys.argv[2]).write_text('\n\n'.join(functions))
PY

source "$FUNCTIONS_FILE"

unset CODEXBAR_SIGNING
SIGNING_MODE=
resolve_package_signing_mode
[[ "$SIGNING_MODE" == "adhoc" ]]

CODEXBAR_SIGNING=identity
resolve_package_signing_mode
[[ "$SIGNING_MODE" == "identity" ]]

CODEXBAR_SIGNING=invalid
if resolve_package_signing_mode 2>/dev/null; then
  echo "Invalid package signing mode unexpectedly succeeded" >&2
  exit 1
fi

grep -Fq 'CODEXBAR_SIGNING=identity' "$RELEASE_SCRIPT"

LAUNCH_SMOKE_SCRIPT="$ROOT/Scripts/verify_packaged_app_launch.sh"
grep -Fq '"$ROOT/Scripts/verify_packaged_app_launch.sh" "$APP_BUNDLE"' "$RELEASE_SCRIPT"
grep -Fq 'CODEXBAR_SKIP_LAUNCH_SMOKE=0' "$RELEASE_SCRIPT"
grep -Fq 'CODEXBAR_LAUNCH_SMOKE_REQUIRE_SANDBOX=1' "$RELEASE_SCRIPT"
grep -Fq 'CODEXBAR_LAUNCH_SMOKE_REQUIRE_SURVIVAL=1' "$RELEASE_SCRIPT"
grep -Fq 'CODEXBAR_LAUNCH_SMOKE_SECONDS=2' "$RELEASE_SCRIPT"
grep -Fq 'SWIFT_TESTING_ENABLED=1' "$LAUNCH_SMOKE_SCRIPT"
grep -Fq 'TESTING_LIBRARY_VERSION=1' "$LAUNCH_SMOKE_SCRIPT"
grep -Fq 'QUOTAKIT_DISABLE_CLOUDKIT=1' "$LAUNCH_SMOKE_SCRIPT"
grep -Fq 'CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1' "$LAUNCH_SMOKE_SCRIPT"
grep -Fq 'CODEXBAR_DISABLE_KEYCHAIN_ACCESS=1' "$LAUNCH_SMOKE_SCRIPT"
grep -Fq 'CODEXBAR_TEST_CODEX_FILE_ISOLATION=1' "$LAUNCH_SMOKE_SCRIPT"
grep -Fq 'CODEXBAR_TEST_SESSION_FILE_ISOLATION=1' "$LAUNCH_SMOKE_SCRIPT"
grep -Fq '(deny file-read* (subpath \"${HOME_SANDBOX_PATH}\"))' "$LAUNCH_SMOKE_SCRIPT"
grep -Fq '(deny file-write*)' "$LAUNCH_SMOKE_SCRIPT"
grep -Fq '(deny network*)' "$LAUNCH_SMOKE_SCRIPT"
grep -Fq "TYPED_FALSE_XML='<plist version=\"1.0\"><false/></plist>'" "$LAUNCH_SMOKE_SCRIPT"
grep -Fq -- '-iCloudSyncEnabled "$TYPED_FALSE_XML"' "$LAUNCH_SMOKE_SCRIPT"
grep -Fq -- '-macFleetSyncEnabled "$TYPED_FALSE_XML"' "$LAUNCH_SMOKE_SCRIPT"
grep -Fq -- '-launchAtLogin "$TYPED_FALSE_XML"' "$LAUNCH_SMOKE_SCRIPT"
grep -Fq 'if env["TESTING_LIBRARY_VERSION"] != nil { return true }' \
  "$ROOT/Sources/CodexBar/LaunchAtLoginManager.swift"
grep -Fq 'if env["TESTING_LIBRARY_VERSION"] != nil { return true }' \
  "$ROOT/Sources/CodexBar/AppNotifications.swift"
grep -Fq 'environment["QUOTAKIT_DISABLE_CLOUDKIT"] != "1"' \
  "$ROOT/Shared/iCloud/CloudSyncManager.swift"

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codexbar-package-signing.XXXXXX")
trap 'rm -f "$FUNCTIONS_FILE"; rm -rf "$TEMP_DIR"' EXIT
APP="$TEMP_DIR/CodexBar.app"
mkdir -p "$APP/Contents/Frameworks/Sparkle.framework"

xattr() {
  if [[ "${MOCK_QUARANTINE:-0}" == "1" ]]; then
    printf '0081;fake;Safari;https://example.invalid\n'
    return 0
  fi
  return 1
}

codesign() {
  return "${MOCK_CODESIGN_STATUS:-0}"
}

verify_packaged_app_integrity "$APP"

export MOCK_QUARANTINE=1
if verify_packaged_app_integrity "$APP" 2>/dev/null; then
  echo "Quarantined app unexpectedly passed integrity verification" >&2
  exit 1
fi
unset MOCK_QUARANTINE

export MOCK_CODESIGN_STATUS=1
if verify_packaged_app_integrity "$APP" 2>/dev/null; then
  echo "App with an invalid signature unexpectedly passed integrity verification" >&2
  exit 1
fi
unset MOCK_CODESIGN_STATUS

resign() {
  printf '%s\n' "$1"
}

SPARKLE="$TEMP_DIR/Sparkle.framework"
sparkle_targets=$(resign_sparkle_framework "$SPARKLE")
expected_sparkle_targets=$(printf '%s\n' \
  "$SPARKLE/Versions/B/Autoupdate" \
  "$SPARKLE/Versions/B/Updater.app/Contents/MacOS/Updater" \
  "$SPARKLE/Versions/B/Updater.app" \
  "$SPARKLE/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" \
  "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" \
  "$SPARKLE/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer" \
  "$SPARKLE/Versions/B/XPCServices/Installer.xpc" \
  "$SPARKLE/Versions/B/Sparkle" \
  "$SPARKLE/Versions/B" \
  "$SPARKLE")
[[ "$sparkle_targets" == "$expected_sparkle_targets" ]]

# Exercise the launch verifier with a disposable app fixture. The fake
# sandbox-exec records the policy while the fixture app checks its startup
# environment; no QuotaKit binary or user data is opened.
REAL_SANDBOX_EXEC="$(type -P sandbox-exec || true)"
REAL_SWIFTC="$(type -P swiftc || true)"
if [[ -x /usr/libexec/PlistBuddy && -n "$REAL_SANDBOX_EXEC" && -n "$REAL_SWIFTC" ]]; then
  LAUNCH_FIXTURE="$TEMP_DIR/launch-smoke"
  LAUNCH_APP="$LAUNCH_FIXTURE/QuotaKit.app"
  mkdir -p "$LAUNCH_FIXTURE/tmp" "$LAUNCH_FIXTURE/bin" \
    "$LAUNCH_APP/Contents/MacOS" \
    "$LAUNCH_APP/Contents/Helpers/CodexBar_CodexBarCore.bundle"
  cat > "$LAUNCH_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>QuotaKit</string></dict></plist>
PLIST
  cat > "$LAUNCH_FIXTURE/QuotaKit.swift" <<'SWIFT'
import Foundation

let environment = ProcessInfo.processInfo.environment
if environment["CODEXBAR_RESOURCE_SMOKE"] == "1" {
    print("CODEXBAR_RESOURCE_SMOKE_OK")
    exit(0)
}

let expectedEnvironment = [
    "SWIFT_TESTING_ENABLED": "1",
    "TESTING_LIBRARY_VERSION": "1",
    "QUOTAKIT_DISABLE_CLOUDKIT": "1",
    "CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS": "1",
    "CODEXBAR_DISABLE_KEYCHAIN_ACCESS": "1",
    "CODEXBAR_TEST_CODEX_FILE_ISOLATION": "1",
    "CODEXBAR_TEST_SESSION_FILE_ISOLATION": "1",
]
precondition(expectedEnvironment.allSatisfy { environment[$0.key] == $0.value })
precondition(environment["HOME"] == environment["SMOKE_ORIGINAL_HOME"])
precondition(environment["QUOTAKIT_CONFIG"]?.hasPrefix(
    (environment["TMPDIR"] ?? "") + "/quotakit-launch-smoke.") == true)
let typedFalseXML = "<plist version=\"1.0\"><false/></plist>"
precondition(Array(CommandLine.arguments.dropFirst()) == [
    "-iCloudSyncEnabled", typedFalseXML,
    "-macFleetSyncEnabled", typedFalseXML,
    "-launchAtLogin", typedFalseXML,
])

let settingsKeys = ["iCloudSyncEnabled", "macFleetSyncEnabled", "launchAtLogin"]
let effectiveValues = settingsKeys.map { key -> String in
    guard let value = UserDefaults.standard.object(forKey: key) as? Bool else {
        fatalError("\(key) is not a typed Boolean in NSArgumentDomain")
    }
    precondition(!value, "\(key) must remain disabled during launch smoke")
    return "\(key)=false type=\(type(of: UserDefaults.standard.object(forKey: key)!))"
}
let capture = environment["SMOKE_ISOLATION_CAPTURE"]!
try! (effectiveValues.joined(separator: "\n") + "\n").write(
    toFile: capture, atomically: true, encoding: .utf8)
print("QUOTAKIT_TYPED_FALSE_DEFAULTS_OK")
Thread.sleep(forTimeInterval: 30)
SWIFT
  "$REAL_SWIFTC" "$LAUNCH_FIXTURE/QuotaKit.swift" -o "$LAUNCH_APP/Contents/MacOS/QuotaKit"
  cp "$LAUNCH_APP/Contents/MacOS/QuotaKit" "$LAUNCH_APP/Contents/Helpers/QuotaKitCLI"
  cat > "$LAUNCH_FIXTURE/bin/sandbox-exec" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "-p" ]]
printf '%s\n' "$2" > "$SMOKE_PROFILE_CAPTURE"
shift 2
exec "$@"
SH
  chmod +x "$LAUNCH_FIXTURE/bin/sandbox-exec"
  PATH="$LAUNCH_FIXTURE/bin:$PATH" \
    TMPDIR="$LAUNCH_FIXTURE/tmp" \
    SMOKE_PROFILE_CAPTURE="$LAUNCH_FIXTURE/profile" \
    SMOKE_ISOLATION_CAPTURE="$LAUNCH_FIXTURE/app-check.txt" \
    SMOKE_ORIGINAL_HOME="$HOME" \
    CODEXBAR_LAUNCH_SMOKE_SECONDS=1 \
    bash "$LAUNCH_SMOKE_SCRIPT" "$LAUNCH_APP"
  python3 - "$LAUNCH_FIXTURE/app-check.txt" "$LAUNCH_FIXTURE/profile" "$HOME" <<'PY'
import sys
from pathlib import Path
capture = Path(sys.argv[1]).read_text()
for key in ("iCloudSyncEnabled", "macFleetSyncEnabled", "launchAtLogin"):
    assert f"{key}=false type=__NSCFBoolean" in capture
profile = Path(sys.argv[2]).read_text()
assert f'(deny file-read* (subpath "{sys.argv[3]}"))' in profile
for rule in ("(deny file-write*)", "(deny network*)",
             "com.apple.cfprefsd.agent", "com.apple.cfprefsd.daemon"):
    assert rule in profile
PY
  LAUNCH_PROFILE="$(cat "$LAUNCH_FIXTURE/profile")"
  (
    cd /
    "$REAL_SANDBOX_EXEC" -p "$LAUNCH_PROFILE" /usr/bin/true
    if "$REAL_SANDBOX_EXEC" -p "$LAUNCH_PROFILE" /bin/sh -c ': > "$1"' sh \
        "$LAUNCH_FIXTURE/blocked-write" 2>/dev/null; then
      echo "Launch smoke sandbox unexpectedly permitted a fixture write." >&2
      exit 1
    fi
  )
  [[ ! -e "$LAUNCH_FIXTURE/blocked-write" ]]
  echo "Packaged launch isolation fixture and sandbox policy passed."
else
  echo "Launch smoke fixture skipped: macOS PlistBuddy, sandbox-exec, and swiftc are required."
fi

echo "Package signing tests passed."
