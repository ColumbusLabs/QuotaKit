#!/usr/bin/env bash
# CodexBar one-shot release helper.
# Usage: scripts/release.sh <marketing_version> <build_number> [release-notes-file]
# Example: scripts/release.sh 0.5.3 18 notes.md

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LOG() { printf "==> %s\n" "$*"; }
ERR() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

if [[ $# -lt 2 ]]; then
  ERR "Usage: $0 <marketing_version> <build_number> [release-notes-file]"
fi

VERSION="$1"
BUILD="$2"
NOTES_FILE="${3:-}"
ZIP_NAME="CodexBar-${VERSION}.zip"
DSYM_ZIP=".build/CodexBar-${VERSION}.dSYM.zip"

require() {
  command -v "$1" >/dev/null || ERR "Missing required command: $1"
}

require git
require swiftlint
require swift
require sign_update
require gh
require zip
require curl

[[ -z "${APP_STORE_CONNECT_API_KEY_P8:-}" || -z "${APP_STORE_CONNECT_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]] && \
  ERR "APP_STORE_CONNECT_* env vars must be set."
[[ -z "${SPARKLE_PRIVATE_KEY_FILE:-}" ]] && ERR "SPARKLE_PRIVATE_KEY_FILE must be set."

git diff --quiet || ERR "Working tree is not clean."

update_file_versions() {
  LOG "Bumping versions to $VERSION ($BUILD)"
  python - "$VERSION" "$BUILD" <<'PY' || ERR "Failed to bump versions"
import sys, pathlib, re
root = pathlib.Path(".")
ver, build = sys.argv[1], sys.argv[2]

def repl(path, pattern, repl):
    text = path.read_text()
    new, n = re.subn(pattern, repl, text, flags=re.M)
    if n == 0:
        raise SystemExit(f"no match in {path}")
    path.write_text(new)

repl(pathlib.Path("Scripts/package_app.sh"),
     r'(CFBundleShortVersionString</key><string>)([^<]+)',
     rf"\\1{ver}")
repl(pathlib.Path("Scripts/package_app.sh"),
     r'(CFBundleVersion</key><string>)([^<]+)',
     rf"\\1{build}")
repl(pathlib.Path("Scripts/sign-and-notarize.sh"),
     r'^(ZIP_NAME=)"CodexBar-[^"]+\\.zip"$',
     rf'\\1"CodexBar-{ver}.zip"')
repl(pathlib.Path("Sources/CodexBar/UsageFetcher.swift"),
     r'clientVersion: "([^"]+)"',
     f'clientVersion: "{ver}"')
PY
}

update_changelog_header() {
  LOG "Ensuring changelog header is dated for $VERSION"
  python - "$VERSION" <<'PY' || ERR "Failed to update CHANGELOG"
import sys, pathlib, re, datetime
ver = sys.argv[1]
today = datetime.date.today().isoformat().replace('-', '‑')  # keep en dash style? No, use iso
today = datetime.date.today().strftime("%Y-%m-%d")
p = pathlib.Path("CHANGELOG.md")
text = p.read_text()
pat = re.compile(rf"^##\\s+{re.escape(ver)}\\s+—\\s+Unreleased", re.M)
new, n = pat.subn(f"## {ver} — {today}", text, count=1)
if n == 0:
    sys.exit("Changelog section not found for version")
p.write_text(new)
PY
}

run_quality_gates() {
  LOG "Running swiftlint"
  swiftlint --strict
  LOG "Running swift test"
  swift test
}

build_and_notarize() {
  LOG "Building, signing, notarizing"
  ./Scripts/sign-and-notarize.sh
}

zip_dsym() {
  LOG "Zipping dSYM"
  local dsym_dir=".build/arm64-apple-macosx/release/CodexBar.dSYM"
  [[ -d "$dsym_dir" ]] || ERR "dSYM not found at $dsym_dir"
  mkdir -p "$(dirname "$DSYM_ZIP")"
  rm -f "$DSYM_ZIP"
  (cd "$(dirname "$dsym_dir")" && zip -r "../../CodexBar-${VERSION}.dSYM.zip" "$(basename "$dsym_dir")") >/dev/null
}

sign_zip() {
  LOG "Generating Sparkle signature"
  SIGNATURE=$(echo "SMYPxE98bJ5iLdHTLHTqGKZNFcZLgrT5Hyjh79h3TaU=" | sign_update --ed-key-file - -p "$ZIP_NAME")
  SIZE=$(stat -f%z "$ZIP_NAME")
}

update_appcast() {
  LOG "Updating appcast.xml"
  local pubdate
  pubdate=$(LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')
  python - "$VERSION" "$BUILD" "$SIGNATURE" "$SIZE" "$pubdate" <<'PY' || exit 1
import sys, pathlib
ver, build, sig, size, pub = sys.argv[1:]
path = pathlib.Path("appcast.xml")
xml = path.read_text()
entry = f"""        <item>
            <title>{ver}</title>
            <pubDate>{pub}</pubDate>
            <link>https://raw.githubusercontent.com/steipete/CodexBar/main/appcast.xml</link>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{ver}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <enclosure url="https://github.com/steipete/CodexBar/releases/download/v{ver}/CodexBar-{ver}.zip" length="{size}" type="application/octet-stream" sparkle:edSignature="{sig}"/>
        </item>
"""
marker = "<channel>"
idx = xml.find(marker)
if idx == -1:
    raise SystemExit("no <channel> in appcast")
insert_at = xml.find("\n", idx) + 1
path.write_text(xml[:insert_at] + entry + xml[insert_at:])
PY
}

create_tag_and_release() {
  LOG "Creating tag v$VERSION"
  git add CHANGELOG.md Scripts/package_app.sh Scripts/sign-and-notarize.sh Sources/CodexBar/UsageFetcher.swift appcast.xml
  git commit -m "Release $VERSION (build $BUILD)"
  git tag "v$VERSION"
  LOG "Pushing main and tag"
  git push origin main
  git push origin "v$VERSION"

  LOG "Uploading artifacts to GitHub release"
  local notes_arg=()
  [[ -n "$NOTES_FILE" ]] && notes_arg=(--notes-file "$NOTES_FILE")
  gh release create "v$VERSION" "$ZIP_NAME" "$DSYM_ZIP" \
    --title "CodexBar $VERSION" \
    --notes "Automated release $VERSION" \
    "${notes_arg[@]:-}" --draft=false --verify-tag
}

verify_downloads() {
  LOG "Verifying enclosure URL"
  curl -I "https://github.com/steipete/CodexBar/releases/download/v${VERSION}/CodexBar-${VERSION}.zip" | head -n 5
  LOG "Verifying dSYM URL"
  curl -I "https://github.com/steipete/CodexBar/releases/download/v${VERSION}/CodexBar-${VERSION}.dSYM.zip" | head -n 5
  LOG "Appcast head:"
  curl -s https://raw.githubusercontent.com/steipete/CodexBar/main/appcast.xml | head -n 15
}

update_file_versions
update_changelog_header
run_quality_gates
build_and_notarize
zip_dsym
sign_zip
update_appcast
create_tag_and_release
verify_downloads

LOG "Release $VERSION (build $BUILD) completed."
