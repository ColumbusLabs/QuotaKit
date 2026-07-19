#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

assert_gate() {
  local expected="$1"
  local name="$2"
  local paths_file="${tmp_dir}/${name}.paths"
  local output_file="${tmp_dir}/${name}.output"
  shift 2

  printf '%s\n' "$@" > "$paths_file"
  GITHUB_OUTPUT="$output_file" "${ROOT_DIR}/Scripts/ci_macos_test_gate.sh" "$paths_file" >/dev/null
  local actual
  actual="$(sed -n 's/^macos-tests=//p' "$output_file")"
  if [[ "$actual" != "$expected" ]]; then
    printf '%s: expected macos-tests=%s, got %s\n' "$name" "$expected" "${actual:-<empty>}" >&2
    exit 1
  fi

  local reason
  reason="$(sed -n 's/^macos-tests-reason=//p' "$output_file")"
  if [[ -z "$reason" ]]; then
    printf '%s: expected macos-tests-reason output\n' "$name" >&2
    exit 1
  fi

  local deferred
  deferred="$(sed -n 's/^macos-tests-deferred=//p' "$output_file")"
  if [[ "$deferred" != false ]]; then
    printf '%s: expected macos-tests-deferred=false, got %s\n' "$name" "${deferred:-<empty>}" >&2
    exit 1
  fi

  local path_count
  path_count="$(sed -n 's/^changed-path-count=//p' "$output_file")"
  if ! [[ "$path_count" =~ ^[0-9]+$ ]]; then
    printf '%s: expected numeric changed-path-count output, got %s\n' \
      "$name" "${path_count:-<empty>}" >&2
    exit 1
  fi

  if [[ "$expected" == false && "$reason" != "docs/site-only changes covered by portable checks" ]]; then
    printf '%s: expected docs/site skip reason, got %s\n' "$name" "$reason" >&2
    exit 1
  fi
}

assert_gate false docs-only $'M\tdocs/providers.md' $'M\tREADME.md'
assert_gate true configuration-doc $'M\tdocs/configuration.md'
assert_gate true rename-to-configuration-doc $'R100\tdocs/old.md\tdocs/configuration.md'
assert_gate true rename-from-configuration-doc $'R100\tdocs/configuration.md\tdocs/new.md'
assert_gate true agents-contract $'M\tAGENTS.md'
assert_gate true rename-to-agents-contract $'R100\tdocs/old.md\tAGENTS.md'
assert_gate true rename-from-agents-contract $'R100\tAGENTS.md\tdocs/new.md'
assert_gate true source $'M\tSources/CodexBar/App.swift'
assert_gate false docs-site $'M\tdocs/index.html' $'M\tdocs/site.css' $'M\tdocs/site.js' \
  $'M\tdocs/site-locales.mjs' $'M\tdocs/social.html' $'M\tdocs/social.png' \
  $'M\tdocs/CNAME' $'M\tdocs/.nojekyll' $'M\tdocs/llms.txt'
assert_gate false docs-site-assets $'M\tdocs/icon.png' $'M\tdocs/logos/provider-logo.svg'
assert_gate true docs-unknown-code $'M\tdocs/custom-tool.js'
assert_gate true docs-site-with-config $'M\tdocs/site.css' $'M\tdocs/configuration.md'
assert_gate true empty
assert_gate true source-to-docs $'R100\tSources/CodexBar/App.swift\tdocs/App.md'
assert_gate true docs-to-source $'R100\tdocs/App.md\tSources/CodexBar/App.swift'
assert_gate false docs-to-site $'R100\tdocs/old.md\tdocs/site.css'

assert_linux_musl_gate() {
  local expected="$1"
  local name="$2"
  local paths_file="${tmp_dir}/linux-musl-${name}.paths"
  local output_file="${tmp_dir}/linux-musl-${name}.output"
  shift 2

  printf '%s\n' "$@" > "$paths_file"
  GITHUB_OUTPUT="$output_file" "${ROOT_DIR}/Scripts/ci_linux_musl_build_gate.sh" "$paths_file" >/dev/null
  local actual
  actual="$(sed -n 's/^linux-musl-build=//p' "$output_file")"
  if [[ "$actual" != "$expected" ]]; then
    printf '%s: expected linux-musl-build=%s, got %s\n' "$name" "$expected" "${actual:-<empty>}" >&2
    exit 1
  fi

  local reason
  reason="$(sed -n 's/^linux-musl-build-reason=//p' "$output_file")"
  if [[ -z "$reason" ]]; then
    printf '%s: expected linux-musl-build-reason output\n' "$name" >&2
    exit 1
  fi
}

assert_linux_musl_gate true package-manifest $'M\tPackage.swift'
assert_linux_musl_gate true swift-source $'M\tSources/CodexBarCore/Process.swift'
assert_linux_musl_gate true nested-swift-source $'M\tSources/CodexBarCore/Host/Process/Process.swift'
assert_linux_musl_gate true c-module-map $'M\tSources/CSQLite3/module.modulemap'
assert_linux_musl_gate true c-shim-header $'M\tSources/CSQLite3/shim.h'
assert_linux_musl_gate true rename-from-swift $'R100\tSources/CodexBarCore/Old.swift\tdocs/Old.md'
assert_linux_musl_gate true rename-to-swift $'R100\tdocs/New.md\tSources/CodexBarCore/New.swift'
assert_linux_musl_gate false tests-only $'M\tTests/CodexBarTests/ProcessTests.swift'
assert_linux_musl_gate true workflow-only $'M\t.github/workflows/ci.yml'
assert_linux_musl_gate true gate-script $'M\tScripts/ci_linux_musl_build_gate.sh'
assert_linux_musl_gate false script-only $'M\tScripts/ci_verify_test_jobs.sh'
assert_linux_musl_gate true package-resolved $'M\tPackage.resolved'
assert_linux_musl_gate true empty-diff

draft_paths="${tmp_dir}/draft-source.paths"
draft_output="${tmp_dir}/draft-source.output"
printf '%s\n' $'M\tSources/CodexBar/App.swift' > "$draft_paths"
CI_PULL_REQUEST_DRAFT=true GITHUB_OUTPUT="$draft_output" \
  "${ROOT_DIR}/Scripts/ci_macos_test_gate.sh" "$draft_paths" >/dev/null
if [[ "$(sed -n 's/^macos-tests=//p' "$draft_output")" != true ]] \
  || [[ "$(sed -n 's/^macos-tests-deferred=//p' "$draft_output")" != true ]]
then
  printf 'draft source: expected macOS tests to remain required while deferred\n' >&2
  exit 1
fi

assert_ios_gate() {
  local expected="$1"
  local name="$2"
  local paths_file="${tmp_dir}/${name}.ios.paths"
  local output_file="${tmp_dir}/${name}.ios.output"
  shift 2

  printf '%s\n' "$@" > "$paths_file"
  GITHUB_OUTPUT="$output_file" "${ROOT_DIR}/Scripts/ci_ios_test_gate.sh" "$paths_file" >/dev/null
  local actual
  actual="$(sed -n 's/^ios-tests=//p' "$output_file")"
  if [[ "$actual" != "$expected" ]]; then
    printf '%s: expected ios-tests=%s, got %s\n' "$name" "$expected" "${actual:-<empty>}" >&2
    exit 1
  fi

  local reason
  reason="$(sed -n 's/^ios-tests-reason=//p' "$output_file")"
  if [[ -z "$reason" ]]; then
    printf '%s: expected ios-tests-reason output\n' "$name" >&2
    exit 1
  fi

  local path_count
  path_count="$(sed -n 's/^changed-path-count=//p' "$output_file")"
  if ! [[ "$path_count" =~ ^[0-9]+$ ]]; then
    printf '%s: expected numeric changed-path-count output, got %s\n' \
      "$name" "${path_count:-<empty>}" >&2
    exit 1
  fi

  if [[ "$expected" == false && "$reason" != "no iOS-impacting paths changed" ]]; then
    printf '%s: expected iOS skip reason, got %s\n' "$name" "$reason" >&2
    exit 1
  fi
}

assert_ios_gate false ios-docs-only $'M\tdocs/providers.md' $'M\tREADME.md'
assert_ios_gate false ios-mac-source-only $'M\tSources/CodexBar/App.swift'
assert_ios_gate true ios-mobile-source $'M\tCodexBarMobile/CodexBarMobile/ContentView.swift'
assert_ios_gate true ios-mobile-project $'M\tCodexBarMobile/project.yml'
assert_ios_gate true ios-generated-project $'M\tCodexBarMobile/CodexBarMobile.xcodeproj/project.pbxproj'
assert_ios_gate true ios-shared-sync $'M\tShared/SyncModels.swift'
assert_ios_gate true ios-ci-contract $'M\t.github/workflows/ci.yml'
assert_ios_gate true ios-lint-contract $'M\tScripts/lint.sh'
assert_ios_gate true ios-gate-contract $'M\tScripts/ci_ios_test_gate.sh'
assert_ios_gate true ios-aggregate-contract $'M\tScripts/ci_verify_test_jobs.sh'
assert_ios_gate true ios-gate-test-contract $'M\tScripts/test_ci_path_gate.sh'
assert_ios_gate true ios-testflight-lane $'M\tScripts/ios_testflight_xcode.sh'
assert_ios_gate true ios-testflight-wrapper $'M\tScripts/upload_ios_testflight.sh'
assert_ios_gate true ios-swiftlint-contract $'M\t.swiftlint.yml'
assert_ios_gate true ios-docs-to-mobile $'R100\tdocs/App.md\tCodexBarMobile/CodexBarMobile/App.swift'
assert_ios_gate true ios-mobile-to-docs $'R100\tCodexBarMobile/CodexBarMobile/App.swift\tdocs/App.md'
assert_ios_gate true ios-empty

assert_gate_fails() {
  local name="$1"
  local paths_file="${tmp_dir}/${name}.paths"
  local output_file="${tmp_dir}/${name}.output"
  shift

  printf '%s\n' "$@" > "$paths_file"
  if GITHUB_OUTPUT="$output_file" "${ROOT_DIR}/Scripts/ci_macos_test_gate.sh" "$paths_file" >/dev/null 2>&1; then
    printf '%s: malformed gate input unexpectedly succeeded\n' "$name" >&2
    exit 1
  fi
  if [[ -s "$output_file" ]]; then
    printf '%s: malformed gate input emitted an output\n' "$name" >&2
    exit 1
  fi
}

assert_gate_fails missing-rename-target $'R100\tREADME.md'
assert_gate_fails extra-modified-path $'M\tREADME.md\tdocs/configuration.md'
assert_gate_fails missing-rename-score $'R\tREADME.md\tdocs/README.md'
assert_gate_fails invalid-rename-score $'Rfoo\tREADME.md\tdocs/README.md'
assert_gate_fails out-of-range-rename-score $'R101\tREADME.md\tdocs/README.md'

for malformed_case in missing-rename-target extra-modified-path missing-rename-score \
  invalid-rename-score out-of-range-rename-score
do
  paths_file="${tmp_dir}/${malformed_case}.paths"
  output_file="${tmp_dir}/linux-musl-${malformed_case}.output"
  if GITHUB_OUTPUT="$output_file" \
    "${ROOT_DIR}/Scripts/ci_linux_musl_build_gate.sh" "$paths_file" >/dev/null 2>&1
  then
    printf '%s: malformed Linux musl gate input unexpectedly succeeded\n' "$malformed_case" >&2
    exit 1
  fi
  if [[ -s "$output_file" ]]; then
    printf '%s: malformed Linux musl gate input emitted an output\n' "$malformed_case" >&2
    exit 1
  fi
done

if CI_PULL_REQUEST_DRAFT=maybe GITHUB_OUTPUT="${tmp_dir}/invalid-draft.output" \
  "${ROOT_DIR}/Scripts/ci_macos_test_gate.sh" "${tmp_dir}/docs-only.paths" >/dev/null 2>&1
then
  printf 'invalid draft flag unexpectedly succeeded\n' >&2
  exit 1
fi
unterminated_paths="${tmp_dir}/unterminated.paths"
unterminated_output="${tmp_dir}/unterminated.output"
printf '%s' $'M\tREADME.md\tdocs/configuration.md' > "$unterminated_paths"
if GITHUB_OUTPUT="$unterminated_output" \
  "${ROOT_DIR}/Scripts/ci_macos_test_gate.sh" "$unterminated_paths" >/dev/null 2>&1
then
  printf 'unterminated malformed gate input unexpectedly succeeded\n' >&2
  exit 1
fi
if [[ -s "$unterminated_output" ]]; then
  printf 'unterminated malformed gate input emitted an output\n' >&2
  exit 1
fi

ios_unterminated_output="${tmp_dir}/ios-unterminated.output"
if GITHUB_OUTPUT="$ios_unterminated_output" \
  "${ROOT_DIR}/Scripts/ci_ios_test_gate.sh" "$unterminated_paths" >/dev/null 2>&1
then
  printf 'iOS unterminated malformed gate input unexpectedly succeeded\n' >&2
  exit 1
fi
if [[ -s "$ios_unterminated_output" ]]; then
  printf 'iOS unterminated malformed gate input emitted an output\n' >&2
  exit 1
fi

verify="${ROOT_DIR}/Scripts/ci_verify_test_jobs.sh"
"$verify" success success true success false true success true success >/dev/null
"$verify" success success false skipped false false skipped false skipped >/dev/null
"$verify" success success true success false false skipped true success >/dev/null
"$verify" success success false skipped false true success false skipped >/dev/null
"$verify" success success true success false true success false skipped >/dev/null
"$verify" success success true success false false skipped false skipped >/dev/null
"$verify" success success false skipped false true success true success >/dev/null
"$verify" success success false skipped false false skipped true success >/dev/null

assert_verify_fails() {
  if "$verify" "$@" >/dev/null 2>&1; then
    printf 'unexpected aggregate success: %s\n' "$*" >&2
    exit 1
  fi
}

assert_verify_fails success success true skipped false true success true success
assert_verify_fails success success true skipped true true success true success
assert_verify_fails success success false skipped true true success true success
assert_verify_fails success success true success true true success true success
assert_verify_fails success success false success false true success true success
assert_verify_fails success success "" skipped false true success true success
assert_verify_fails failure success true success false true success true success
assert_verify_fails success failure true success false true success true success
assert_verify_fails success success true success false true skipped true success
assert_verify_fails success success true success false false success true success
assert_verify_fails success success true success false "" skipped true success
assert_verify_fails success success true success false true success true skipped
assert_verify_fails success success true success false true success false success
assert_verify_fails success success true success false true success "" skipped

printf 'CI path gate tests passed.\n'
