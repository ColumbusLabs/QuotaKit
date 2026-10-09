#!/usr/bin/env bash

set -euo pipefail

lint_result="${1:-}"
changes_result="${2:-}"
macos_tests_required="${3:-}"
macos_test_result="${4:-}"
macos_tests_deferred="${5:-}"
ios_tests_required="${6:-}"
ios_test_result="${7:-}"
linux_build_result="${8-<missing>}"
macos_compatibility_result="${9-<missing>}"
linux_build_required="${10-<missing>}"

if [[ "$lint_result" != "success" ]]; then
  printf 'lint job finished with %s\n' "${lint_result:-<empty>}" >&2
  exit 1
fi

if [[ "$changes_result" != "success" ]]; then
  printf 'changes job finished with %s\n' "${changes_result:-<empty>}" >&2
  exit 1
fi

case "${linux_build_required}:${linux_build_result}" in
  true:success)
    printf 'Linux glibc CLI matrix passed.\n'
    ;;
  false:skipped)
    printf 'Linux glibc CLI matrix skipped by its path gate.\n'
    ;;
  *)
    printf 'Linux glibc build gate/result mismatch: required=%s result=%s\n' \
      "${linux_build_required:-<empty>}" "${linux_build_result:-<empty>}" >&2
    exit 1
    ;;
esac

case "${macos_tests_required}:${macos_tests_deferred}:${macos_test_result}" in
  true:false:success)
    printf 'macOS Swift test shards passed.\n'
    ;;
  false:false:skipped)
    printf 'macOS Swift tests skipped for docs/site-only changes.\n'
    ;;
  true:true:skipped)
    printf 'macOS Swift tests are required but deferred; aggregate CI remains incomplete\n' >&2
    exit 1
    ;;
  *)
    printf 'macOS test gate/result mismatch: required=%s deferred=%s result=%s\n' \
      "${macos_tests_required:-<empty>}" "${macos_tests_deferred:-<empty>}" \
      "${macos_test_result:-<empty>}" >&2
    exit 1
    ;;
esac

case "${macos_tests_required}:${macos_compatibility_result}" in
  true:success)
    printf 'Xcode 26.3 compatibility build passed.\n'
    ;;
  false:skipped)
    printf 'Xcode 26.3 compatibility build skipped for docs/site-only changes.\n'
    ;;
  *)
    printf 'Xcode 26.3 compatibility build gate/result mismatch: required=%s result=%s\n' \
      "${macos_tests_required:-<empty>}" "${macos_compatibility_result:-<empty>}" >&2
    exit 1
    ;;
esac

case "${ios_tests_required}:${ios_test_result}" in
  true:success)
    printf 'iOS simulator tests passed.\n'
    ;;
  false:skipped)
    printf 'iOS simulator tests skipped: no iOS-impacting paths changed.\n'
    ;;
  *)
    printf 'iOS test gate/result mismatch: required=%s result=%s\n' \
      "${ios_tests_required:-<empty>}" "${ios_test_result:-<empty>}" >&2
    exit 1
    ;;
esac
