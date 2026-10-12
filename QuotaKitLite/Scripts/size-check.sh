#!/usr/bin/env bash
# Fails when the stripped QuotaKit Lite binary grows past its budget (068 §1: the bundle stays within 3 MB).
# Usage: Scripts/size-check.sh <release binary> [limit in bytes]

set -euo pipefail

binary="${1:?usage: size-check.sh <release binary> [limit-bytes]}"
limit="${2:-3145728}"

[[ -f "$binary" ]] || { echo "error: no binary at $binary" >&2; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp "$binary" "$work/QuotaKitLite"
# The same strip install.sh applies, so the gate measures what gets installed.
strip -x "$work/QuotaKitLite"
size="$(stat -f %z "$work/QuotaKitLite")"
printf 'QuotaKit Lite stripped binary: %d bytes (limit %d)\n' "$size" "$limit"
if (( size > limit )); then
  echo "error: QuotaKit Lite binary is over its size budget" >&2
  exit 1
fi
