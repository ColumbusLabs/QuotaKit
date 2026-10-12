#!/usr/bin/env bash
# Lists full-app commits that touched code QuotaKit Lite ports, since Lite's last review (068 §8).
#
# Lite re-implements the Claude, Codex and Antigravity parsers and requests, the account identity strings and the
# alert and sync wire formats. When the full app adapts to an endpoint change, the same fix usually needs porting.
# After reviewing (and porting), record the new baseline:
#   Scripts/lite-drift-check.sh --mark-reviewed
#
# Usage: Scripts/lite-drift-check.sh [--strict | --mark-reviewed]
#   --strict         exit 1 when there are unreviewed commits (for an upstream-sync checklist)
#   --mark-reviewed  set the baseline to HEAD

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE_FILE="$ROOT_DIR/QuotaKitLite/DRIFT_BASELINE"

watched=(
  Sources/CodexBarCore/Providers/Claude/ClaudeOAuth
  Sources/CodexBarCore/Providers/Codex/CodexOAuth
  Sources/CodexBarCore/Providers/Antigravity/AntigravityStatusProbe.swift
  Sources/CodexBarCore/Providers/Antigravity/AntigravityStatusProbe+ResponseModels.swift
  Sources/CodexBarCore/Providers/Antigravity/AntigravityStatusProbe+PortDetection.swift
  Sources/CodexBarCore/Providers/Antigravity/AntigravityQuotaSummaryParser.swift
  Sources/CodexBarCore/DarwinProcessEnumerator.swift
  Sources/CodexBarCore/Sync/AccountIdentityComputer.swift
  Sources/CodexBar/Sync/QuotaTransitionWriter.swift
  Sources/CodexBar/SessionQuotaNotifications.swift
)

mode="${1:-}"
case "$mode" in
  ""|--strict|--mark-reviewed) ;;
  *)
    echo "usage: $(basename "$0") [--strict | --mark-reviewed]" >&2
    exit 2
    ;;
esac

if [[ "$mode" == "--mark-reviewed" ]]; then
  git -C "$ROOT_DIR" rev-parse HEAD > "$BASELINE_FILE"
  echo "QuotaKit Lite drift baseline set to $(cut -c1-9 "$BASELINE_FILE")"
  exit 0
fi

[[ -f "$BASELINE_FILE" ]] || { echo "error: missing $BASELINE_FILE" >&2; exit 2; }
baseline="$(tr -d '[:space:]' < "$BASELINE_FILE")"
git -C "$ROOT_DIR" cat-file -e "${baseline}^{commit}" 2>/dev/null \
  || { echo "error: baseline $baseline is not in this clone" >&2; exit 2; }

commits="$(git -C "$ROOT_DIR" log --oneline "${baseline}..HEAD" -- "${watched[@]}")"
if [[ -z "$commits" ]]; then
  echo "QuotaKit Lite: no full-app parser or wire-format changes since ${baseline:0:9}."
  exit 0
fi

echo "QuotaKit Lite: full-app changes to review since ${baseline:0:9}:"
echo "$commits"
[[ "$mode" == "--strict" ]] && exit 1
exit 0
