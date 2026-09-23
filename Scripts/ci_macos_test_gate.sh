#!/usr/bin/env bash

set -euo pipefail

changed_paths_file="${1:-}"
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "$changed_paths_file" || ! -f "$changed_paths_file" ]]; then
  printf 'Usage: %s <changed-paths-file>\n' "$(basename "$0")" >&2
  exit 2
fi

macos_tests=false
macos_tests_deferred=false
macos_tests_reason=""
path_count=0
draft_pull_request="${CI_PULL_REQUEST_DRAFT:-false}"
full_suite_required=false
settings_appearance_changed=false
spend_heatmap_changed=false
spend_dashboard_midnight_dst_changed=false

case "$draft_pull_request" in
  true|false)
    ;;
  *)
    printf 'CI_PULL_REQUEST_DRAFT must be true or false.\n' >&2
    exit 2
    ;;
esac

require_macos_tests() {
  local path="$1"
  local reason="$2"

  macos_tests=true
  if [[ -z "$macos_tests_reason" ]]; then
    macos_tests_reason="${path}: ${reason}"
  fi
}

classify_path() {
  local path="$1"
  [[ -z "$path" ]] && return

  path_count=$((path_count + 1))

  case "$path" in
    AGENTS.md|docs/configuration.md)
      require_macos_tests "$path" "changes contributor or runtime configuration contracts"
      full_suite_required=true
      ;;
    *.md)
      ;;
    docs/.nojekyll|docs/CNAME|docs/index.html|docs/llms.txt|docs/site-locales.mjs|docs/site.css|docs/site.js|docs/social.html|docs/social.png)
      ;;
    docs/*.png|docs/*.jpg|docs/*.jpeg|docs/*.webp|docs/*.ico|docs/*.svg)
      ;;
    Sources/CodexBar/PreferencesView.swift|Tests/CodexBarTests/SettingsWindowAppearanceTests.swift)
      require_macos_tests "$path" "covered by the settings appearance suite"
      settings_appearance_changed=true
      ;;
    Sources/CodexBar/SpendActivityHeatmap.swift|Tests/CodexBarTests/SpendActivityHeatmapTests.swift)
      require_macos_tests "$path" "covered by the spend heatmap suite"
      spend_heatmap_changed=true
      ;;
    Tests/CodexBarTests/SpendDashboardMidnightDSTTests.swift)
      require_macos_tests "$path" "covered by the spend dashboard midnight/DST suite"
      spend_dashboard_midnight_dst_changed=true
      ;;
    *)
      require_macos_tests "$path" "not covered by portable docs/site checks"
      full_suite_required=true
      ;;
  esac
}

invalid_row=false
while IFS=$'\t' read -r status first_path second_path extra_path \
  || [[ -n "${status:-}${first_path:-}${second_path:-}${extra_path:-}" ]]
do
  [[ -z "${status}${first_path:-}${second_path:-}${extra_path:-}" ]] && continue

  case "$status" in
    R*|C*)
      if ! [[ "$status" =~ ^[RC][0-9]{1,3}$ ]] \
        || ((10#${status:1} > 100)) \
        || [[ -z "${first_path:-}" || -z "${second_path:-}" || -n "${extra_path:-}" ]]
      then
        invalid_row=true
        break
      fi
      classify_path "$first_path"
      classify_path "$second_path"
      ;;
    A|D|M|T|U|X|B)
      if [[ -z "${first_path:-}" || -n "${second_path:-}" || -n "${extra_path:-}" ]]; then
        invalid_row=true
        break
      fi
      classify_path "$first_path"
      ;;
    *)
      invalid_row=true
      break
      ;;
  esac
done < "$changed_paths_file"

if [[ "$invalid_row" == true ]]; then
  printf 'Invalid git name-status row; refusing to skip macOS tests.\n' >&2
  exit 2
fi

if [[ "$path_count" -eq 0 ]]; then
  require_macos_tests '<empty diff>' 'no changed paths were reported'
  full_suite_required=true
fi

macos_test_filter=""
macos_shard_indexes='[0,1]'
if [[ "$settings_appearance_changed" == true ]] && ! grep -Eq \
  '^[[:space:]]*(struct|final class|class)[[:space:]]+SettingsWindowAppearanceTests[[:space:]:{]' \
  "${repository_root}/Tests/CodexBarTests/SettingsWindowAppearanceTests.swift"
then
  full_suite_required=true
fi
if [[ "$spend_heatmap_changed" == true ]] && ! grep -Eq \
  '^[[:space:]]*(struct|final class|class)[[:space:]]+SpendActivityHeatmapTests[[:space:]:{]' \
  "${repository_root}/Tests/CodexBarTests/SpendActivityHeatmapTests.swift"
then
  full_suite_required=true
fi
if [[ "$spend_dashboard_midnight_dst_changed" == true ]] && ! grep -Eq \
  '^[[:space:]]*(struct|final class|class)[[:space:]]+SpendDashboardMidnightDSTTests[[:space:]:{]' \
  "${repository_root}/Tests/CodexBarTests/SpendDashboardMidnightDSTTests.swift"
then
  full_suite_required=true
fi
if [[ "$macos_tests" == true && "$full_suite_required" == false ]]; then
  if [[ "$settings_appearance_changed" == true ]]; then
    macos_test_filter=SettingsWindowAppearanceTests
  fi
  if [[ "$spend_heatmap_changed" == true ]]; then
    macos_test_filter="${macos_test_filter:+${macos_test_filter}|}SpendActivityHeatmapTests"
  fi
  if [[ "$spend_dashboard_midnight_dst_changed" == true ]]; then
    macos_test_filter="${macos_test_filter:+${macos_test_filter}|}SpendDashboardMidnightDSTTests"
  fi
fi
if [[ -n "$macos_test_filter" ]]; then
  macos_shard_indexes='[0]'
fi

if [[ "$macos_tests" == true && "$draft_pull_request" == true ]]; then
  macos_tests_deferred=true
  summary_reason="draft pull request: macOS Swift tests deferred until ready for review"
elif [[ "$macos_tests" == true ]]; then
  summary_reason="$macos_tests_reason"
else
  summary_reason="docs/site-only changes covered by portable checks"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'macos-tests=%s\n' "$macos_tests" >> "$GITHUB_OUTPUT"
  printf 'macos-tests-deferred=%s\n' "$macos_tests_deferred" >> "$GITHUB_OUTPUT"
  printf 'macos-tests-reason=%s\n' "$summary_reason" >> "$GITHUB_OUTPUT"
  printf 'changed-path-count=%s\n' "$path_count" >> "$GITHUB_OUTPUT"
  printf 'macos-test-filter=%s\n' "$macos_test_filter" >> "$GITHUB_OUTPUT"
  printf 'macos-shard-indexes=%s\n' "$macos_shard_indexes" >> "$GITHUB_OUTPUT"
fi

if [[ "$macos_tests_deferred" == true ]]; then
  printf 'macOS Swift tests required but deferred until ready for review: %s.\n' "$macos_tests_reason"
elif [[ "$macos_tests" == true ]]; then
  if [[ -n "$macos_test_filter" ]]; then
    printf 'Focused macOS Swift tests required (%s): %s.\n' "$macos_test_filter" "$macos_tests_reason"
  else
    printf 'Full macOS Swift tests required for this change set: %s.\n' "$macos_tests_reason"
  fi
else
  printf 'Skipping macOS Swift tests: %s.\n' "$summary_reason"
fi
