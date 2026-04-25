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

cmd="${1:-lint}"

case "$cmd" in
  lint)
    ensure_tools
    "${BIN_DIR}/swiftformat" Sources Tests --lint
    "${BIN_DIR}/swiftlint" --strict
    audit_xcstrings
    ;;
  format)
    ensure_tools
    "${BIN_DIR}/swiftformat" Sources Tests
    ;;
  audit-i18n)
    audit_xcstrings
    ;;
  *)
    printf 'Usage: %s [lint|format|audit-i18n]\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac
