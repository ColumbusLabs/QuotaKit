#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${ROOT_DIR}/.build/lint-tools/bin"

ensure_tools() {
  # Always delegate to the installer so pinned versions are enforced.
  # The installer is idempotent and exits early when the expected versions are already present.
  "${ROOT_DIR}/Scripts/install_lint_tools.sh"
}

# Audit every `*.xcstrings` file under the iOS app for entries left in
# `state: "new"`. Xcode auto-creates such entries with the English source
# as a fallback `value` whenever a developer adds a new `String(localized:)`
# call, and the build / TestFlight upload still succeeds — so non-English
# locales silently ship the English text. Build 55 (1.1.0 release notes
# English-only on Chinese / Japanese iPhones) and Build 92 (same regression
# for the 1.3.0 catalog) both shipped this way before user-reported.
# Failing lint here forces every new string to carry real translations
# for all 4 locales (en / zh-Hans / zh-Hant / ja) before it can be merged.
audit_xcstrings() {
  command -v jq >/dev/null 2>&1 || { echo "jq is required for i18n audit; install via brew install jq" >&2; return 2; }

  local rc=0
  while IFS= read -r -d '' xcstrings; do
    local missing
    missing=$(jq -r '
      .strings | to_entries
      | map(
          .key as $k
          | ((.value.localizations // {}) | to_entries
              | map(select(.value.stringUnit.state == "new") | "\(.key)|\($k)")
            )
        )
      | flatten | .[]
    ' "$xcstrings")

    if [[ -n "$missing" ]]; then
      local count
      count=$(printf '%s\n' "$missing" | wc -l | tr -d ' ')
      echo "ERROR: $xcstrings has $count locale entries in state=\"new\" (untranslated, English fallback):" >&2
      printf '%s\n' "$missing" | awk -F'|' '{printf "  [%s] %s\n", $1, substr($2, 1, 100) (length($2) > 100 ? "…" : "")}' | head -30 >&2
      [[ "$count" -gt 30 ]] && echo "  … ($((count - 30)) more)" >&2
      echo "Provide proper translations and set state=\"translated\" for each locale." >&2
      rc=1
    else
      echo "i18n audit: $xcstrings — all locales translated"
    fi
  done < <(find "$ROOT_DIR" -name '*.xcstrings' -not -path '*/.build/*' -not -path '*/DerivedData/*' -print0)
  return "$rc"
}

# Guard: any change to the Codex / Claude cost-usage parser must come
# with a `parserLogicVersion` bump in CostUsagePricing.swift, so the
# pricingFingerprint rolls and every user's on-disk cache (which carries
# token attributions baked-in by the previous parser) gets invalidated
# on next launch.
#
# Why this exists: the 0.23.3 hotfix had to ship because a pre-existing
# parser bug (32 KB prefixBytes truncating Codex CLI 0.125 turn_context
# events) silently misattributed ~93% of token usage to gpt-5. The cache
# wouldn't have rolled itself even after the parser fix without the
# manual parserLogicVersion bump. Easy to forget; this lint catches it.
#
# Escape hatch: set ALLOW_PARSER_CHANGE=1 for cosmetic / comment-only
# edits where invalidating user caches would be wasteful.
audit_parser_version() {
  if [[ "${ALLOW_PARSER_CHANGE:-0}" == "1" ]]; then
    echo "parser-version audit: ALLOW_PARSER_CHANGE=1 → skipping"
    return 0
  fi

  local base="${PARSER_LINT_BASE:-origin/mobile-dev}"
  if ! git -C "$ROOT_DIR" rev-parse --verify "$base" >/dev/null 2>&1; then
    echo "parser-version audit: base ref '$base' not found, skipping"
    return 0
  fi

  # Parser-semantics-bearing files. Editing any of these without bumping
  # parserLogicVersion risks shipping a fix whose results never reach
  # users (their caches stay frozen with the old parser's attribution).
  local guarded_files=(
    "Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner.swift"
    "Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner+Claude.swift"
    "Sources/CodexBarCore/Vendored/CostUsage/CostUsageJsonl.swift"
  )
  local pricing_file="Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift"

  local changed_parser=()
  local f
  for f in "${guarded_files[@]}"; do
    if ! git -C "$ROOT_DIR" diff --quiet "$base"...HEAD -- "$f"; then
      changed_parser+=("$f")
    fi
  done

  if [[ ${#changed_parser[@]} -eq 0 ]]; then
    echo "parser-version audit: no parser code changes since $base"
    return 0
  fi

  # Parser code changed. Look for a +/- on the parserLogicVersion line
  # in CostUsagePricing.swift. Pricing-table key edits don't count —
  # those roll the fingerprint via sorted keys already; we want a
  # genuine parserLogicVersion bump.
  if git -C "$ROOT_DIR" diff "$base"...HEAD -- "$pricing_file" \
       | grep -E '^[+-][[:space:]]*static[[:space:]]+let[[:space:]]+parserLogicVersion' >/dev/null; then
    echo "parser-version audit: parser code changed AND parserLogicVersion bumped — OK"
    return 0
  fi

  echo "ERROR: parser code changed since $base but parserLogicVersion was not bumped." >&2
  echo "       Files changed:" >&2
  printf '         - %s\n' "${changed_parser[@]}" >&2
  echo "" >&2
  echo "       Bump 'static let parserLogicVersion = N' in:" >&2
  echo "         $pricing_file" >&2
  echo "       so the pricingFingerprint rolls and every user's on-disk" >&2
  echo "       cache (with old-parser attributions baked in) is invalidated" >&2
  echo "       and re-scanned with the fixed parser on next launch." >&2
  echo "" >&2
  echo "       For comment-only / non-semantic edits set ALLOW_PARSER_CHANGE=1." >&2
  return 1
}

cmd="${1:-lint}"

case "$cmd" in
  lint)
    ensure_tools
    "${BIN_DIR}/swiftformat" Sources Tests --lint
    "${BIN_DIR}/swiftlint" --strict
    audit_xcstrings
    audit_parser_version
    ;;
  format)
    ensure_tools
    "${BIN_DIR}/swiftformat" Sources Tests
    ;;
  audit-i18n)
    audit_xcstrings
    ;;
  audit-parser-version)
    audit_parser_version
    ;;
  *)
    printf 'Usage: %s [lint|format|audit-i18n|audit-parser-version]\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac
