#!/usr/bin/env bash
set -euo pipefail

[[ "${GITHUB_ACTIONS:-}" == true ]] || { echo "This script is for hosted CI" >&2; exit 2; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

version=2.10.1
sha256=4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a
jq -e --arg version "$version" '.pins[] | select(.identity == "sparkle") | .state.version == $version' \
    "$root/Package.resolved" >/dev/null || { echo "Update the hosted Sparkle artifact pin" >&2; exit 2; }
url="https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-for-Swift-Package-Manager.zip"

case "$(uname -s)" in
    Darwin) default_cache="$HOME/Library/Caches/org.swift.swiftpm" ;;
    Linux) default_cache="${XDG_CACHE_HOME:-$HOME/.cache}/org.swift.swiftpm" ;;
    *) echo "Unsupported SwiftPM runner OS" >&2; exit 2 ;;
esac
artifacts="${SWIFTPM_CACHE_PATH:-$default_cache}/artifacts"
# SwiftPM replaces each non-identifier character in the artifact URL with an underscore.
key="$(printf '%s' "$url" | LC_ALL=C sed 's/[^a-zA-Z0-9_]/_/g')"
destination="$artifacts/$key"

if [[ -f "$destination" ]] && printf '%s  %s\n' "$sha256" "$destination" | shasum -a 256 -c -s; then
    echo "Pinned Sparkle artifact is already in the runner's SwiftPM cache"
    exit 0
fi
mkdir -p "$artifacts"
bash "$root/Scripts/ci_download_release_asset.sh" "$url" "$destination" "$sha256"
