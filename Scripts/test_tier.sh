#!/usr/bin/env bash

# Fast, explicit test tiers for daily work. `make test` remains the full suite.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIER="${1:-}"
BASE="${TEST_AFFECTED_BASE:-}"

cd "$ROOT_DIR"

run_suites() {
  local suites=()
  while (($#)); do
    suites+=(--suite "$1")
    shift
  done
  CODEXBAR_TEST_GROUP_SIZE=8 ./Scripts/test.sh "${suites[@]}"
}

smoke_suites=(
  "CodexBarTests.ProviderArchitectureGatekeeperTests"
  "CodexBarTests.ProviderPluginRuntimeTests"
  "CodexBarTests.ProviderPluginParityTests"
  "CodexBarTests.ProviderPluginDetailsParityTests"
  "CodexBarTests.SyncCoordinatorTests"
  "CodexBarTests.CodexBarCoreResourcesTests"
)

case "$TIER" in
  smoke)
    run_suites "${smoke_suites[@]}"
    ./Scripts/test-plugin-engines.sh
    ;;
  affected)
    if [[ -z "$BASE" ]]; then
      for candidate in origin/main main; do
        if git rev-parse --verify --quiet "${candidate}^{commit}" >/dev/null; then
          BASE="$candidate"
          break
        fi
      done
    fi
    if [[ -z "$BASE" ]]; then
      printf 'No affected-test base is available; running the full suite.\n'
      exec ./Scripts/test.sh
    fi

    base_commit="$(git merge-base "$BASE" HEAD)"
    mapfile -t changed_paths < <(
      {
        git diff --name-only "${base_commit}...HEAD"
        git diff --name-only --cached
        git diff --name-only
      } | awk 'NF && !seen[$0]++'
    )
    if ((${#changed_paths[@]} == 0)); then
      printf 'No committed changes relative to %s; running smoke tier.\n' "$BASE"
      run_suites "${smoke_suites[@]}"
      exit 0
    fi

    suites=()
    requires_full=false
    for path in "${changed_paths[@]}"; do
      case "$path" in
        README.md|LICENSE|docs/*)
          ;;
        Tests/CodexBarTests/*Tests.swift)
          suites+=("CodexBarTests.$(basename "$path" .swift)")
          ;;
        *) requires_full=true ;;
      esac
    done
    if [[ "$requires_full" == true ]]; then
      printf 'Affected changes include production/build/unknown paths; running the full suite.\n'
      exec ./Scripts/test.sh
    fi
    if ((${#suites[@]} == 0)); then
      printf 'Documentation-only change; no Swift test impact.\n'
      exit 0
    fi
    mapfile -t suites < <(printf '%s\n' "${suites[@]}" | awk '!seen[$0]++')
    printf 'Affected-test base: %s\nAffected suites:\n' "$BASE"
    printf -- '- %s\n' "${suites[@]}"
    run_suites "${suites[@]}"
    ;;
  *)
    printf 'Usage: %s <smoke|affected>\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac
