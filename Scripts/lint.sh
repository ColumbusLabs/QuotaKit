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
  command -v python3 >/dev/null 2>&1 || { echo "python3 is required for i18n audit; install via xcode-select --install" >&2; return 2; }

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

  # Cross-check: every String(localized:) in Swift source must have a
  # matching entry in the iOS Localizable.xcstrings. Xcode only auto-extracts
  # new keys on a full Xcode build — swift test / lint never trigger that
  # extraction. Build 130 of iOS 1.7.0 shipped 21 untranslated keys (the
  # entire 1.7.0 in-app release-notes catalog + CloudKit sync status text)
  # to zh-Hans / ja / zh-Hant users as English fallback. The original
  # state="new" audit above passed because the catalog had no orphan
  # entries — but couldn't see that 21 source keys had no catalog entry
  # at all. This second pass closes that gap.
  local ios_xcstrings="$ROOT_DIR/CodexBarMobile/CodexBarMobile/Localizable.xcstrings"
  if [[ -f "$ios_xcstrings" ]]; then
    if ! python3 "$ROOT_DIR/Scripts/audit_localized_keys.py" "$ios_xcstrings" \
         "$ROOT_DIR/CodexBarMobile/CodexBarMobile" \
         "$ROOT_DIR/CodexBarMobile/CodexBarMobileWidgets" \
         "$ROOT_DIR/CodexBarMobile/CodexBarMobilePushExtension"; then
      rc=1
    fi
  fi

  return "$rc"
}

# Guard: the committed Sources/CodexBarCore/Generated/CodexParserHash.generated.swift
# must match a fresh hash of every non-Claude Codex cost-usage Swift source. That hash
# feeds the cache `producerKey` invalidation axis; a stale hash would leave users on
# cached results produced by older parser semantics. Regenerate via:
#   bash Scripts/regenerate-codex-parser-hash.sh
check_codex_parser_hash() {
  "${ROOT_DIR}/Scripts/regenerate-codex-parser-hash.sh" --check
}

# Claude parsing is intentionally excluded from the generated Codex producer hash.
# Keep its cache invalidation contract explicit: semantic scanner changes must bump
# the Claude artifact version in CostUsageCache.swift.
audit_claude_parser_version() {
  if [[ "${ALLOW_PARSER_CHANGE:-0}" == "1" ]]; then
    echo "Claude parser-version audit: ALLOW_PARSER_CHANGE=1 → skipping"
    return 0
  fi

  local base="${PARSER_LINT_BASE:-origin/HEAD}"
  if ! git -C "$ROOT_DIR" rev-parse --verify "$base" >/dev/null 2>&1; then
    if [[ "$base" == */* ]]; then
      local remote="${base%%/*}"
      local branch="${base#*/}"
      git -C "$ROOT_DIR" fetch --quiet --no-tags --depth=50 "$remote" "$branch" 2>/dev/null || true
    fi
  fi

  if ! git -C "$ROOT_DIR" rev-parse --verify "$base" >/dev/null 2>&1; then
    if [[ "${ALLOW_MISSING_BASE:-0}" == "1" ]]; then
      echo "Claude parser-version audit: ALLOW_MISSING_BASE=1 → skipping (base ref '$base' unavailable)"
      return 0
    fi
    echo "ERROR: Claude parser-version audit can't find base ref '$base'." >&2
    echo "       Set PARSER_LINT_BASE to the intended base or fetch that ref." >&2
    return 1
  fi

  local scanner_file="Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner+Claude.swift"
  local cache_file="Sources/CodexBarCore/Vendored/CostUsage/CostUsageCache.swift"
  if git -C "$ROOT_DIR" diff --quiet "$base"...HEAD -- "$scanner_file"; then
    echo "Claude parser-version audit: no parser code changes since $base"
    return 0
  fi

  if git -C "$ROOT_DIR" diff "$base"...HEAD -- "$cache_file" \
       | grep -E '^[+-][[:space:]]*case[[:space:]]+\.claude([^[:alnum:]_]|$).*:[[:space:]]*[0-9]+' >/dev/null; then
    echo "Claude parser-version audit: parser code changed AND artifact version bumped — OK"
    return 0
  fi

  echo "ERROR: Claude parser code changed since $base without a Claude artifact-version bump." >&2
  echo "       Bump the .claude case in $cache_file so stale cached attributions are rescanned." >&2
  echo "       For comment-only edits set ALLOW_PARSER_CHANGE=1." >&2
  return 1
}

check_package_product_paths() {
  "${ROOT_DIR}/Scripts/test_package_product_paths.sh"
}

check_package_strip() {
  "${ROOT_DIR}/Scripts/test_package_strip.sh"
}

check_package_signing() {
  "${ROOT_DIR}/Scripts/test_package_signing.sh"
}

audit_customer_branding() {
  python3 "${ROOT_DIR}/Scripts/audit_customer_branding.py" --self-test
  python3 "${ROOT_DIR}/Scripts/audit_customer_branding.py"
}

audit_provider_palette() {
  python3 "${ROOT_DIR}/Scripts/audit_provider_palette.py"
}

check_release_dsym_paths() {
  "${ROOT_DIR}/Scripts/test_release_dsym_paths.sh"
}

check_sparkle_signing_paths() {
  "${ROOT_DIR}/Scripts/test_sparkle_signing_paths.sh"
}

check_release_feed_url() {
  local expected="https://raw.githubusercontent.com/ColumbusLabs/QuotaKit/main/appcast.xml"

  # shellcheck source=/dev/null
  source "${ROOT_DIR}/.mac-release.env"

  if [[ "${MAC_RELEASE_FEED_URL:-}" != "$expected" ]]; then
    echo "ERROR: .mac-release.env MAC_RELEASE_FEED_URL must point at the customer appcast:" >&2
    echo "       expected: $expected" >&2
    echo "       actual:   ${MAC_RELEASE_FEED_URL:-<unset>}" >&2
    return 1
  fi

  if ! grep -F 'RELEASE_BRANCH="${QUOTAKIT_RELEASE_BRANCH:-${CODEXBAR_RELEASE_BRANCH:-main}}"' \
       "${ROOT_DIR}/Scripts/package_app.sh" >/dev/null; then
    echo "ERROR: Scripts/package_app.sh must default release bundles to the main customer appcast branch." >&2
    return 1
  fi

  if grep -F 'mobile-dev' "${ROOT_DIR}/Scripts/package_app.sh" >/dev/null; then
    echo "ERROR: Scripts/package_app.sh still references mobile-dev; customer release bundles must not." >&2
    return 1
  fi

  echo "release-feed audit: customer appcast URL is $expected"
}

check_swift_test_sharding() {
  "${ROOT_DIR}/Scripts/test_swift_test_sharding.sh"
}

check_ci_path_gate() {
  "${ROOT_DIR}/Scripts/test_ci_path_gate.sh"
}

check_documentation_links() {
  node "${ROOT_DIR}/Scripts/check-documentation-links.mjs"
}

check_repository_size() {
  "${ROOT_DIR}/Scripts/check_repository_size.sh"
  "${ROOT_DIR}/Scripts/test_repository_size.sh"
}

check_shell_scripts() {
  local count=0
  local script
  for script in "${ROOT_DIR}"/Scripts/*.sh "${ROOT_DIR}"/Scripts/mac-release; do
    [[ -f "$script" ]] || continue
    bash -n "$script"
    count=$((count + 1))
  done
  printf 'shell scripts OK: %d files\n' "$count"
}

check_app_locales() {
  node "${ROOT_DIR}/Scripts/check-app-locales.mjs" --test
  node "${ROOT_DIR}/Scripts/check-app-locales.mjs"
}

check_llms_index() {
  node "${ROOT_DIR}/Scripts/generate-llms.mjs" --check
}

run_portable_checks() {
  check_codex_parser_hash
  audit_claude_parser_version
  check_package_product_paths
  check_package_strip
  check_package_signing
  check_release_dsym_paths
  check_sparkle_signing_paths
  check_swift_test_sharding
  check_release_feed_url
  check_ci_path_gate
  check_repository_size
  check_shell_scripts
  check_documentation_links
  check_llms_index
  ensure_tools
}

run_swiftformat_lint() {
  "${BIN_DIR}/swiftformat" \
    Sources \
    Tests \
    Shared \
    CodexBarMobile/CodexBarMobile \
    CodexBarMobile/CodexBarMobileTests \
    CodexBarMobile/CodexBarMobileUITests \
    CodexBarMobile/CodexBarMobileWidgets \
    CodexBarMobile/CodexBarMobilePushExtension \
    --lint
}

run_swiftlint() {
  "${BIN_DIR}/swiftlint" --strict
}

cmd="${1:-lint}"

case "$cmd" in
  lint)
    check_app_locales
    run_portable_checks
    run_swiftformat_lint
    run_swiftlint
    audit_xcstrings
    audit_customer_branding
    audit_provider_palette
    ;;
  lint-linux)
    run_portable_checks
    run_swiftlint
    audit_customer_branding
    audit_provider_palette
    ;;
  lint-macos)
    check_app_locales
    run_portable_checks
    run_swiftformat_lint
    ;;
  format)
    ensure_tools
    "${BIN_DIR}/swiftformat" \
      Sources \
      Tests \
      Shared \
      CodexBarMobile/CodexBarMobile \
      CodexBarMobile/CodexBarMobileTests \
      CodexBarMobile/CodexBarMobileUITests \
      CodexBarMobile/CodexBarMobileWidgets \
      CodexBarMobile/CodexBarMobilePushExtension
    ;;
  audit-i18n)
    audit_xcstrings
    ;;
  audit-parser-version)
    check_codex_parser_hash
    audit_claude_parser_version
    ;;
  audit-parser-hash)
    check_codex_parser_hash
    ;;
  audit-customer-branding)
    audit_customer_branding
    ;;
  audit-provider-palette)
    audit_provider_palette
    ;;
  audit-release-feed)
    check_release_feed_url
    ;;
  *)
    printf 'Usage: %s [lint|lint-linux|lint-macos|format|audit-i18n|audit-parser-version|audit-parser-hash|audit-customer-branding|audit-provider-palette|audit-release-feed]\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac
