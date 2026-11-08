#!/usr/bin/env bash
set -euo pipefail

url="${1:?GitHub release download URL required}"
destination="${2:?destination required}"
expected_sha="${3:?expected SHA-256 required}"
pattern='^https://github[.]com/([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)/releases/download/([a-zA-Z0-9_.-]+)/([a-zA-Z0-9_.-]+)$'
[[ "$url" =~ $pattern ]] || { echo "Unsupported release download URL: $url" >&2; exit 2; }
repo="${BASH_REMATCH[1]}"
tag="${BASH_REMATCH[2]}"
asset="${BASH_REMATCH[3]}"
[[ "$expected_sha" =~ ^[a-f0-9]{64}$ ]] || { echo "Invalid SHA-256 pin" >&2; exit 2; }

download="$(mktemp "${destination}.XXXXXX")"
trap 'rm -f "$download"' EXIT
curl_release=(curl -fsSL --retry 2 --retry-max-time 30 --max-time 30)
api="https://api.github.com/repos/$repo/releases"

if asset_id="$("${curl_release[@]}" "$api/tags/$tag" |
    jq -er --arg name "$asset" '[.assets[] | select(.name == $name)] | if length == 1 then .[0].id else empty end')" &&
    "${curl_release[@]}" -H 'Accept: application/octet-stream' "$api/assets/$asset_id" -o "$download" &&
    printf '%s  %s\n' "$expected_sha" "$download" | shasum -a 256 -c -; then
    echo "Verified $asset from the GitHub Releases API"
else
    echo "GitHub Releases API did not return a verified $asset. Trying the release URL."
    "${curl_release[@]}" "$url" -o "$download"
    printf '%s  %s\n' "$expected_sha" "$download" | shasum -a 256 -c -
fi
mv -f "$download" "$destination"
