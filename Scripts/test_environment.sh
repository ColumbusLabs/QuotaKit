#!/usr/bin/env bash

# Enumerate exported names only: never serialize inherited credential values.
codexbar_scrub_test_environment() {
  local name
  while IFS= read -r name; do
    # Explicit non-secret controls and build search paths (_PAT also matches _PATH).
    # Do not allow CODEXBAR_* wholesale; provider credentials use that prefix too.
    case "$name" in
      CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS|CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS|\
      CODEXBAR_DISABLE_KEYCHAIN_ACCESS|CODEXBAR_USE_LOCAL_SWEETCOOKIEKIT|\
      LD_LIBRARY_PATH|DYLD_LIBRARY_PATH|DYLD_FRAMEWORK_PATH|LIBRARY_PATH|PKG_CONFIG_PATH) continue ;;
    esac
    if [[ "$name" =~ [Tt][Oo][Kk][Ee][Nn]|[Kk][Ee][Yy]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Pp][Aa][Ss][Ss][Ww][Dd]|[Ww][Ee][Bb][Hh][Oo][Oo][Kk]|[Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll]|[Cc][Oo][Oo][Kk][Ii][Ee]|[Pp][Rr][Ii][Vv][Aa][Tt][Ee]|_[Pp][Aa][Tt] ]]; then
      unset "$name"
    fi
  done < <(compgen -e)
}
codexbar_scrub_test_environment
unset -f codexbar_scrub_test_environment

# Inherited by test runners and their CLI children.
export CODEXBAR_TEST_CODEX_FILE_ISOLATION=1
unset CODEXBAR_TEST_CODEX_FILE_FIXTURES
export CODEXBAR_TEST_SESSION_FILE_ISOLATION=1

if [[ "${CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS:-}" != "1" ]]; then
  export CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1
fi

# Run direct SwiftPM test entrypoints away from the caller's app caches. Keep the
# caller's other toolchain and package-resolution settings intact.
codexbar_run_swift_test_with_private_home() {
  local test_home status tool_home platform
  local -a command swiftpm_arguments
  command=("$@")
  if [[ "${command[0]:-}" != "swift" || "${command[1]:-}" != "test" ]]; then
    echo "codexbar_run_swift_test_with_private_home expects a swift test command" >&2
    return 2
  fi

  # SwiftPM reads mirrors, registry configuration and fingerprints from its shared
  # user paths. Keep existing tool state reachable while HOME is private to tests.
  tool_home="${HOME:-}"
  platform="$(uname -s)"
  if [[ -n "${tool_home}" && "${SWIFTPM_CACHE_PATH:-}" == "" ]]; then
    if [[ "${platform}" == "Darwin" ]]; then
      if [[ -d "${tool_home}/Library/Caches/org.swift.swiftpm" ]]; then
        swiftpm_arguments+=(--cache-path "${tool_home}/Library/Caches/org.swift.swiftpm")
      fi
    elif [[ "${platform}" == "Linux" ]]; then
      if [[ -d "${tool_home}/.cache/org.swift.swiftpm" ]]; then
        swiftpm_arguments+=(--cache-path "${tool_home}/.cache/org.swift.swiftpm")
      fi
    fi
  fi
  if [[ -n "${tool_home}" ]]; then
    if [[ "${platform}" == "Darwin" ]]; then
      if [[ -d "${tool_home}/Library/org.swift.swiftpm/configuration" ]]; then
        swiftpm_arguments+=(--config-path "${tool_home}/Library/org.swift.swiftpm/configuration")
      fi
      if [[ -d "${tool_home}/Library/org.swift.swiftpm/security" ]]; then
        swiftpm_arguments+=(--security-path "${tool_home}/Library/org.swift.swiftpm/security")
      fi
    elif [[ "${platform}" == "Linux" ]]; then
      if [[ -d "${tool_home}/.swiftpm/configuration" ]]; then
        swiftpm_arguments+=(--config-path "${tool_home}/.swiftpm/configuration")
      fi
      if [[ -d "${tool_home}/.swiftpm/security" ]]; then
        swiftpm_arguments+=(--security-path "${tool_home}/.swiftpm/security")
      fi
    fi
  fi
  if [[ -n "${swiftpm_arguments[0]:-}" ]]; then
    command=("${command[@]:0:2}" "${swiftpm_arguments[@]}" "${command[@]:2}")
  fi

  test_home="$(mktemp -d "${TMPDIR:-/tmp}/quotakit-test-home.XXXXXX")"
  if HOME="${test_home}" CFFIXED_USER_HOME="${test_home}" "${command[@]}"; then
    status=0
  else
    status=$?
  fi
  rm -rf "${test_home}"
  return "${status}"
}
