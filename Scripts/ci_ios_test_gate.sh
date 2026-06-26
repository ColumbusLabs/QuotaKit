#!/usr/bin/env bash

set -euo pipefail

changed_paths_file="${1:-}"

if [[ -z "$changed_paths_file" || ! -f "$changed_paths_file" ]]; then
  printf 'Usage: %s <changed-paths-file>\n' "$(basename "$0")" >&2
  exit 2
fi

ios_tests=false
ios_tests_reason=""
path_count=0

require_ios_tests() {
  local path="$1"
  local reason="$2"

  ios_tests=true
  if [[ -z "$ios_tests_reason" ]]; then
    ios_tests_reason="${path}: ${reason}"
  fi
}

classify_path() {
  local path="$1"
  [[ -z "$path" ]] && return

  path_count=$((path_count + 1))

  case "$path" in
    CodexBarMobile/*)
      require_ios_tests "$path" "changes iOS app, project, tests, widgets, or release metadata"
      ;;
    Shared/*)
      require_ios_tests "$path" "changes shared sync code used by the iOS app"
      ;;
    .github/workflows/ci.yml)
      require_ios_tests "$path" "changes iOS CI contract"
      ;;
    Scripts/ci_ios_test_gate.sh|Scripts/ci_verify_test_jobs.sh|Scripts/test_ci_path_gate.sh)
      require_ios_tests "$path" "changes iOS CI gate or aggregate verification"
      ;;
    Scripts/ios_testflight_xcode.sh|Scripts/upload_ios_testflight.sh)
      require_ios_tests "$path" "changes iOS archive or TestFlight upload lane"
      ;;
    .swiftlint.yml|Scripts/lint.sh|Scripts/audit_localized_keys.py|Scripts/check-app-locales.mjs|Scripts/audit_customer_branding.py|Scripts/audit_provider_palette.py)
      require_ios_tests "$path" "changes mobile-relevant lint or localization checks"
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
  printf 'Invalid git name-status row; refusing to skip iOS tests.\n' >&2
  exit 2
fi

if [[ "$path_count" -eq 0 ]]; then
  require_ios_tests '<empty diff>' 'no changed paths were reported'
fi

if [[ "$ios_tests" == true ]]; then
  summary_reason="$ios_tests_reason"
else
  summary_reason="no iOS-impacting paths changed"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'ios-tests=%s\n' "$ios_tests" >> "$GITHUB_OUTPUT"
  printf 'ios-tests-reason=%s\n' "$summary_reason" >> "$GITHUB_OUTPUT"
  printf 'changed-path-count=%s\n' "$path_count" >> "$GITHUB_OUTPUT"
fi

if [[ "$ios_tests" == true ]]; then
  printf 'iOS simulator tests required for this change set: %s.\n' "$ios_tests_reason"
else
  printf 'Skipping iOS simulator tests: no iOS-impacting paths changed.\n'
fi
