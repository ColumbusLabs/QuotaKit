#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codexbar-test-sharding.XXXXXX")"
trap 'rm -rf "${TEMP_DIR}"' EXIT

IFS= read -r -d '' FAKE_SWIFT_SCRIPT <<'EOF' || true
set -euo pipefail

printf '%s\n' "$*" >> "${FAKE_SWIFT_LOG}"
if [[ -n "${FAKE_SWIFT_TEST_HOMES:-}" ]]; then
  case "$*" in
    "test list"*|"build --show-bin-path"*|"test --skip-build --no-parallel"*)
      home_state=missing
      if [[ -d "${HOME}" ]]; then
        home_state=present
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$*" "${HOME}" "${CFFIXED_USER_HOME:-}" "${CODEX_HOME:-<unset>}" \
        "${CODEX_SQLITE_HOME-<unset>}" "${home_state}" >> "${FAKE_SWIFT_TEST_HOMES}"
      ;;
  esac
fi
if [[ "$*" == "build --show-bin-path"* ]]; then
  printf '%s\n' "${FAKE_SWIFT_BIN_PATH:?}"
  exit 0
fi
if [[ "$*" == "test list"* ]]; then
  if [[ "${FAKE_SWIFT_MODE:-success}" == "list_fail" ]]; then
    sleep "${FAKE_SWIFT_LIST_DELAY:?}"
    printf 'test-list stdout marker\n'
    printf 'test-list stderr marker\n' >&2
    exit 42
  fi
  if [[ "${FAKE_SWIFT_MODE:-success}" == "list_sparkle_fail_once" && ! -f "${FAKE_SWIFT_STATE}" ]]; then
    printf 'failed\n' > "${FAKE_SWIFT_STATE}"
    printf 'Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle\n' >&2
    printf 'tried: %s/PackageFrameworks/Sparkle.framework/Versions/B/Sparkle\n' \
      "${FAKE_SWIFT_BIN_PATH:?}" >&2
    exit 1
  fi
  printf '%s\n' \
    "CodexBarTests.Alpha/test_one()" \
    "CodexBarTests.Alpha/test_two(argument:)" \
    "CodexBarTests.Beta/test_two" \
    "CodexBarTests.Gamma/test_three" \
    "CodexBarTests.Delta/test_four" \
    "CodexBarTests.Epsilon/test_five" \
    "CodexBarTests.Zeta/test_six" \
    "CodexBarTests.Eta/test_seven" \
    "CodexBarTests.Theta/test_eight" \
    'CodexBarTests.`top level works`()' \
    'CodexBarTests.`top/level slash works`()'
  exit 0
fi

is_group=0
if [[ "$*" == *"|"* ]]; then
  is_group=1
fi

next_group_attempt() {
  local attempt=0
  if [[ -f "${FAKE_SWIFT_STATE}" ]]; then
    read -r attempt < "${FAKE_SWIFT_STATE}"
  fi
  attempt=$((attempt + 1))
  printf '%s\n' "${attempt}" > "${FAKE_SWIFT_STATE}"
  printf '%s\n' "${attempt}"
}

case "${FAKE_SWIFT_MODE:-success}" in
  group_fail_once)
    if [[ "${is_group}" == "1" && "$(next_group_attempt)" == "1" ]]; then
      exit 1
    fi
    ;;
  group_always_fail)
    if [[ "${is_group}" == "1" ]]; then
      exit 1
    fi
    ;;
  group_timeout)
    if [[ "${is_group}" == "1" ]]; then
      sleep 2
    fi
    ;;
  singleton_timeout)
    if [[ "${is_group}" == "0" ]]; then
      sleep 2
    fi
    ;;
  group_fail_then_timeout)
    if [[ "${is_group}" == "1" ]]; then
      attempt="$(next_group_attempt)"
      if [[ "${attempt}" == "1" ]]; then
        exit 1
      fi
      sleep 2
    fi
    ;;
esac
EOF

reset_case() {
  local name="$1"
  export FAKE_SWIFT_LOG="${TEMP_DIR}/${name}-swift.log"
  export FAKE_SWIFT_STATE="${TEMP_DIR}/${name}-state"
  export GITHUB_STEP_SUMMARY="${TEMP_DIR}/${name}-summary.md"
  rm -f "${FAKE_SWIFT_LOG}" "${FAKE_SWIFT_STATE}" "${GITHUB_STEP_SUMMARY}"
}

run_harness() {
  python3 "${ROOT_DIR}/Scripts/ci_swift_test_by_suite.py" \
    "$@" \
    --swift-command /bin/bash \
    --swift-command-arg=-c \
    --swift-command-arg="${FAKE_SWIFT_SCRIPT}" \
    --swift-command-arg=fake-swift
}

python3 - "${ROOT_DIR}/.github/workflows/ci.yml" <<'PY'
import pathlib
import re
import sys

workflow = pathlib.Path(sys.argv[1]).read_text()
if "types: [opened, synchronize, reopened, ready_for_review, converted_to_draft]" not in workflow:
    raise SystemExit("CI must rerun when a pull request becomes ready or draft")
if "CI_PULL_REQUEST_DRAFT: ${{ github.event.pull_request.draft || false }}" not in workflow:
    raise SystemExit("CI must pass draft state to the macOS test gate")
if "macos-tests-deferred: ${{ steps.macos-tests.outputs.macos-tests-deferred }}" not in workflow:
    raise SystemExit("CI must expose whether macOS tests were deferred")
job_match = re.search(r"(?ms)^  swift-test-macos:\n(?P<body>.*?)(?=^  [a-zA-Z0-9_-]+:|\Z)", workflow)
if not job_match:
    raise SystemExit("swift-test-macos job not found in CI workflow")

job = job_match.group("body")
required_not_deferred = (
    "if: ${{ needs.changes.outputs.macos-tests == 'true' && "
    "needs.changes.outputs.macos-tests-deferred != 'true' }}"
)
if required_not_deferred not in job:
    raise SystemExit("swift-test-macos must skip only required tests explicitly deferred for drafts")
if "shard-index: ${{ fromJSON(needs.changes.outputs.macos-shard-indexes) }}" not in job:
    raise SystemExit("swift-test-macos must use the validated path gate shard indexes")
if not re.search(r"(?m)^\s+shard-count:\s+\[4\]\s*$", job):
    raise SystemExit("swift-test-macos shard-count must be [4]")
job_timeout = re.search(r"(?m)^    timeout-minutes: (\d+)$", job)
test_step = re.search(r"(?ms)^      - name: Swift Test\n(.*?)(?=^      - |\Z)", job)
if not test_step or not re.search(r"(?m)^\s+\./Scripts/test.sh --direct-workers 2$", test_step.group(1)):
    raise SystemExit("required hosted tests must use two direct workers per shard")
if "continue-on-error" in test_step.group(1) or "--limit-groups" in test_step.group(1):
    raise SystemExit("required full-inventory tests must remain gating and unlimited")
if any(value not in test_step.group(1) for value in [
    "CODEXBAR_TEST_GROUP_SIZE=4", "CODEXBAR_TEST_SUITE_TIMEOUT=120",
    "CODEXBAR_TEST_RETRY_NON_TIMEOUT_FAILURES=0",
]):
    raise SystemExit("required tests must retain group size, deadlines and failure policy")
diagnostics = re.search(r"(?ms)^      - name: Collect crash reports on failure\n(.*?)(?=^      - |\Z)", job)
if not diagnostics or "if: ${{ failure() }}" not in diagnostics.group(1):
    raise SystemExit("crash diagnostics must include all required test failures")
if 'swift_test_diagnostics.py --since "$RUNNER_TEMP/codexbar-tests-started"' not in job:
    raise SystemExit("crash diagnostics must use the explicit test-start timestamp")
step_timeout = re.search(r"(?m)^        timeout-minutes: (\d+)$", test_step.group(1)) if test_step else None
if not step_timeout or int(step_timeout.group(1)) < 60:
    raise SystemExit("Swift Test must retain at least 60 minutes for the four required shards")
if not job_timeout or int(job_timeout.group(1)) < int(step_timeout.group(1)) + 15:
    raise SystemExit("macOS job must leave at least 15 minutes outside Swift Test")
if "CODEXBAR_TEST_SHARD_INDEX=${{ matrix.shard-index }}" not in job:
    raise SystemExit("swift-test-macos must pass matrix.shard-index to Scripts/test.sh")
if "CODEXBAR_TEST_SHARD_COUNT=${{ matrix.shard-count }}" not in job:
    raise SystemExit("swift-test-macos must pass matrix.shard-count to Scripts/test.sh")
if "CODEXBAR_TEST_KEEP_GOING=1" not in job:
    raise SystemExit("swift-test-macos broad test must continue after failed groups")
if "swift test --filter \"$CODEXBAR_TEST_FILTER\"" not in job:
    raise SystemExit("swift-test-macos must run the selected focused suites")
PY

reset_case retry
export FAKE_SWIFT_MODE=group_fail_once
run_harness --group-size 4 --timeout 10 > "${TEMP_DIR}/retry.log"
grep -Fq "failed with exit code 1; retrying group once" "${TEMP_DIR}/retry.log"
grep -Fq "Swift test timing summary:" "${TEMP_DIR}/retry.log"
grep -Fq '| Discovered selections | `10` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected selections | `10` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected groups | `3` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| First-pass successful groups | `2` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| First-pass failed groups | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Full-group retries | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Recovered groups | `1` |' "${GITHUB_STEP_SUMMARY}"
[[ "$(grep -c '^test --skip-build --no-parallel' "${FAKE_SWIFT_LOG}")" -eq 4 ]]
grep -Fq "CodexBarTests\\.Alpha" "${FAKE_SWIFT_LOG}"
grep -Fq "CodexBarTests\\.Beta" "${FAKE_SWIFT_LOG}"
grep -Fq "CodexBarTests\\..*top\\ level\\ works" "${FAKE_SWIFT_LOG}"
grep -Fq "CodexBarTests\\..*top/level\\ slash\\ works" "${FAKE_SWIFT_LOG}"
[[ "$(wc -l < "${FAKE_SWIFT_LOG}")" -eq 5 ]]

reset_case private-home
export FAKE_SWIFT_MODE=success
export FAKE_SWIFT_TEST_HOMES="${TEMP_DIR}/private-test-homes.txt"
CODEX_HOME="${TEMP_DIR}/inherited-codex-home" \
  CODEX_SQLITE_HOME="${TEMP_DIR}/inherited-codex-sqlite" \
  run_harness --group-size 4 --limit-groups 2 --timeout 10 > "${TEMP_DIR}/private-home.log"
# Discovery and each serial group use a distinct temporary home removed on return.
[[ "$(wc -l < "${FAKE_SWIFT_TEST_HOMES}")" -eq 3 ]]
[[ "$(cut -f2 "${FAKE_SWIFT_TEST_HOMES}" | sort -u | wc -l)" -eq 3 ]]
while IFS=$'\t' read -r command test_home fixed_home codex_home sqlite_home home_state; do
  [[ "${test_home}" == "${fixed_home}" && "${test_home}" != "${HOME}" ]] || exit 1
  [[ "${codex_home}" == "${test_home}/.codex" && "${sqlite_home}" == "<unset>" ]] || exit 1
  [[ "${home_state}" == "present" && ! -e "${test_home}" ]] || exit 1
done < "${FAKE_SWIFT_TEST_HOMES}"
unset FAKE_SWIFT_TEST_HOMES

reset_case strict
export FAKE_SWIFT_MODE=group_fail_once
set +e
CODEXBAR_TEST_GROUP_SIZE=4 \
  CODEXBAR_TEST_SUITE_TIMEOUT=10 \
  CODEXBAR_TEST_RETRY_NON_TIMEOUT_FAILURES=0 \
  "${ROOT_DIR}/Scripts/test.sh" \
    --limit-groups 1 \
    --swift-command /bin/bash \
    --swift-command-arg=-c \
    --swift-command-arg="${FAKE_SWIFT_SCRIPT}" \
    --swift-command-arg=fake-swift \
    > "${TEMP_DIR}/strict.log" 2>&1
strict_status=$?
set -e
[[ "${strict_status}" -eq 1 ]]
grep -Fq '| First-pass failed groups | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Full-group retries | `0` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Isolated selection retries | `0` |' "${GITHUB_STEP_SUMMARY}"
[[ "$(wc -l < "${FAKE_SWIFT_LOG}")" -eq 2 ]]

reset_case keep-going
export FAKE_SWIFT_MODE=group_always_fail
set +e
CODEXBAR_TEST_GROUP_SIZE=4 \
  CODEXBAR_TEST_SUITE_TIMEOUT=10 \
  CODEXBAR_TEST_RETRY_NON_TIMEOUT_FAILURES=0 \
  CODEXBAR_TEST_KEEP_GOING=1 \
  "${ROOT_DIR}/Scripts/test.sh" \
    --swift-command /bin/bash \
    --swift-command-arg=-c \
    --swift-command-arg="${FAKE_SWIFT_SCRIPT}" \
    --swift-command-arg=fake-swift \
    > "${TEMP_DIR}/keep-going.log" 2>&1
keep_going_status=$?
set -e
[[ "${keep_going_status}" -eq 1 ]]
[[ "$(wc -l < "${FAKE_SWIFT_LOG}")" -eq 4 ]]
grep -Fq '| First-pass failed groups | `3` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Full-group retries | `0` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq 'Group 1/3 (exit 1): CodexBarTests.Alpha' "${TEMP_DIR}/keep-going.log"
grep -Fq 'Group 2/3 (exit 1):' "${TEMP_DIR}/keep-going.log"
grep -Fq 'Group 3/3 (exit 1):' "${GITHUB_STEP_SUMMARY}"

reset_case shard-0
export FAKE_SWIFT_MODE=success
run_harness --group-size 4 --timeout 10 --shard-index 0 --shard-count 2 > "${TEMP_DIR}/shard-0.log"
grep -Fq '| Shard | `1/2` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected selections | `6` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected groups | `2` |' "${GITHUB_STEP_SUMMARY}"

reset_case shard-1
run_harness --group-size 4 --timeout 10 --shard-index 1 --shard-count 2 > "${TEMP_DIR}/shard-1.log"
grep -Fq '| Shard | `2/2` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected selections | `4` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected groups | `1` |' "${GITHUB_STEP_SUMMARY}"

reset_case shard-4-0
run_harness --group-size 4 --timeout 10 --shard-index 0 --shard-count 4 > "${TEMP_DIR}/shard-4-0.log"
grep -Fq '| Shard | `1/4` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected selections | `4` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected groups | `1` |' "${GITHUB_STEP_SUMMARY}"

reset_case shard-4-1
run_harness --group-size 4 --timeout 10 --shard-index 1 --shard-count 4 > "${TEMP_DIR}/shard-4-1.log"
grep -Fq '| Shard | `2/4` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected selections | `4` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected groups | `1` |' "${GITHUB_STEP_SUMMARY}"

reset_case shard-4-2
run_harness --group-size 4 --timeout 10 --shard-index 2 --shard-count 4 > "${TEMP_DIR}/shard-4-2.log"
grep -Fq '| Shard | `3/4` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected selections | `2` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected groups | `1` |' "${GITHUB_STEP_SUMMARY}"

reset_case shard-4-3
run_harness --group-size 4 --timeout 10 --shard-index 3 --shard-count 4 > "${TEMP_DIR}/shard-4-3.log"
grep -Fq '| Shard | `4/4` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected selections | `0` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected groups | `0` |' "${GITHUB_STEP_SUMMARY}"

reset_case shard-list-all
run_harness --group-size 4 --timeout 10 --list-only \
  | grep -v '^Discovered ' \
  | sort > "${TEMP_DIR}/shards-expected.log"
for shard_count in 2 3 4; do
  for ((shard_index = 0; shard_index < shard_count; shard_index++)); do
    reset_case "shard-list-${shard_count}-${shard_index}"
    CODEXBAR_TEST_SHARD_INDEX="$shard_index" CODEXBAR_TEST_SHARD_COUNT="$shard_count" \
      "${ROOT_DIR}/Scripts/test.sh" --group-size 4 --timeout 10 --list-only \
        --swift-command /bin/bash \
        --swift-command-arg=-c \
        --swift-command-arg="${FAKE_SWIFT_SCRIPT}" \
        --swift-command-arg=fake-swift \
        > "${TEMP_DIR}/shard-list-${shard_count}-${shard_index}.log"
    for workers in 2 3; do
      run_harness --group-size 4 --timeout 10 --list-only --direct-workers "$workers" \
        --shard-index "$shard_index" --shard-count "$shard_count" \
        > "${TEMP_DIR}/direct-list.log"
      diff -u "${TEMP_DIR}/shard-list-${shard_count}-${shard_index}.log" "${TEMP_DIR}/direct-list.log"
    done
  done
  cat "${TEMP_DIR}"/shard-list-"${shard_count}"-?.log \
    | grep -v '^Discovered ' \
    | sort > "${TEMP_DIR}/shards-combined.log"
  diff -u "${TEMP_DIR}/shards-expected.log" "${TEMP_DIR}/shards-combined.log"
done

reset_case group-timeout
export FAKE_SWIFT_MODE=group_timeout
run_harness --group-size 4 --limit-groups 1 --timeout 1 > "${TEMP_DIR}/group-timeout.log"
grep -Fq "timed out; retrying selections one at a time" "${TEMP_DIR}/group-timeout.log"
grep -Fq '| Timed out groups | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Recovered groups | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Isolated selection retries | `4` |' "${GITHUB_STEP_SUMMARY}"

reset_case singleton-timeout
export FAKE_SWIFT_MODE=singleton_timeout
set +e
run_harness --group-size 1 --limit-groups 1 --timeout 1 > "${TEMP_DIR}/singleton-timeout.log" 2>&1
singleton_timeout_status=$?
set -e
[[ "${singleton_timeout_status}" -eq 124 ]]
grep -Fq '| Timed out groups | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Recovered groups | `0` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Isolated selection retries | `0` |' "${GITHUB_STEP_SUMMARY}"

reset_case retry-timeout
export FAKE_SWIFT_MODE=group_fail_then_timeout
run_harness --group-size 4 --limit-groups 1 --timeout 1 > "${TEMP_DIR}/retry-timeout.log"
grep -Fq '| Full-group retries | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Timed out groups | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Recovered groups | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Isolated selection retries | `4` |' "${GITHUB_STEP_SUMMARY}"

reset_case repeated-failure
export FAKE_SWIFT_MODE=group_always_fail
set +e
run_harness --group-size 4 --limit-groups 1 --timeout 10 > "${TEMP_DIR}/failure.log" 2>&1
failure_status=$?
set -e
[[ "${failure_status}" -eq 1 ]]
grep -Fq '| Full-group retries | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Recovered groups | `0` |' "${GITHUB_STEP_SUMMARY}"

for list_delay in 0.25 1.1; do
  reset_case list-failure
  export FAKE_SWIFT_MODE=list_fail
  export FAKE_SWIFT_LIST_DELAY="$list_delay"
  set +e
  run_harness --group-size 1 --timeout 10 > "${TEMP_DIR}/list-failure.log" 2>&1
  list_failure_status=$?
  set -e
  [[ "${list_failure_status}" -ne 0 ]]
  grep -Fq "test-list stdout marker" "${TEMP_DIR}/list-failure.log"
  grep -Fq "test-list stderr marker" "${TEMP_DIR}/list-failure.log"
  [[ "$(wc -l < "${FAKE_SWIFT_LOG}")" -eq 1 ]]
  # Scheduling can push discovery past one second; only a positive duration is required.
  awk '/- Discovery seconds:/ { positive = ($4 + 0) > 0 } END { exit !positive }' \
    "${TEMP_DIR}/list-failure.log"
  grep -Fq '| Discovered selections | `0` |' "${GITHUB_STEP_SUMMARY}"
done
unset FAKE_SWIFT_LIST_DELAY

reset_case sparkle-recovery
export FAKE_SWIFT_MODE=list_sparkle_fail_once
export FAKE_SWIFT_BIN_PATH="${TEMP_DIR}/sparkle-bin"
export FAKE_SWIFT_TEST_HOMES="${TEMP_DIR}/sparkle-test-homes.txt"
mkdir -p \
  "${FAKE_SWIFT_BIN_PATH}/Sparkle.framework/Versions/B" \
  "${FAKE_SWIFT_BIN_PATH}/Wrong.framework" \
  "${FAKE_SWIFT_BIN_PATH}/PackageFrameworks"
touch "${FAKE_SWIFT_BIN_PATH}/Sparkle.framework/Versions/B/Sparkle"
ln -s ../Wrong.framework "${FAKE_SWIFT_BIN_PATH}/PackageFrameworks/Sparkle.framework"
run_harness --group-size 1 --limit-groups 1 --timeout 10 > "${TEMP_DIR}/sparkle-recovery.log"
[[ "$(readlink "${FAKE_SWIFT_BIN_PATH}/PackageFrameworks/Sparkle.framework")" == "../Sparkle.framework" ]]
[[ "$(grep -c '^test list' "${FAKE_SWIFT_LOG}")" -eq 2 ]]
[[ "$(grep -c '^build --show-bin-path' "${FAKE_SWIFT_LOG}")" -eq 1 ]]
grep -Fq "Recovered SwiftPM Sparkle test runtime; retrying discovery once." \
  "${TEMP_DIR}/sparkle-recovery.log"
[[ "$(wc -l < "${FAKE_SWIFT_TEST_HOMES}")" -eq 4 ]]
[[ "$(cut -f1 "${FAKE_SWIFT_TEST_HOMES}" | grep -c '^test list')" -eq 2 ]]
[[ "$(cut -f1 "${FAKE_SWIFT_TEST_HOMES}" | grep -c '^build --show-bin-path')" -eq 1 ]]
[[ "$(cut -f2 "${FAKE_SWIFT_TEST_HOMES}" | sort -u | wc -l)" -eq 2 ]]
discovery_home="$(sed -n '1p' "${FAKE_SWIFT_TEST_HOMES}" | cut -f2)"
[[ "$(sed -n '2p' "${FAKE_SWIFT_TEST_HOMES}" | cut -f2)" == "${discovery_home}" ]]
[[ "$(sed -n '3p' "${FAKE_SWIFT_TEST_HOMES}" | cut -f2)" == "${discovery_home}" ]]
[[ "$(sed -n '4p' "${FAKE_SWIFT_TEST_HOMES}" | cut -f2)" != "${discovery_home}" ]]
while IFS=$'\t' read -r command test_home fixed_home codex_home sqlite_home home_state; do
  [[ "${test_home}" == "${fixed_home}" && "${test_home}" != "${HOME}" ]] || exit 1
  [[ "${codex_home}" == "${test_home}/.codex" && "${sqlite_home}" == "<unset>" ]] || exit 1
  [[ "${home_state}" == "present" && ! -e "${test_home}" ]] || exit 1
done < "${FAKE_SWIFT_TEST_HOMES}"
unset FAKE_SWIFT_TEST_HOMES
unset FAKE_SWIFT_BIN_PATH

reset_case plugin-engine-private-home
mkdir -p "${TEMP_DIR}/fake-bin"
cat > "${TEMP_DIR}/fake-bin/swift" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
home_state=missing
if [[ -d "${HOME}" ]]; then
  home_state=present
fi
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$*" "${HOME}" "${CFFIXED_USER_HOME:-}" "${CODEX_HOME:-<unset>}" \
  "${CODEX_SQLITE_HOME-<unset>}" "${home_state}" "${CODEXBAR_PLUGIN_ENGINE:-<unset>}" \
  >> "${FAKE_SWIFT_NATIVE_HOME_LOG}"
EOF
cat > "${TEMP_DIR}/fake-bin/uname" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "-s" ]]
printf '%s\n' "${FAKE_UNAME_PLATFORM:?}"
EOF
chmod +x "${TEMP_DIR}/fake-bin/swift"
chmod +x "${TEMP_DIR}/fake-bin/uname"
run_plugin_engine_private_home_case() {
  local platform tool_home log cache_path config_path security_path swiftpm_path
  platform="$1"
  tool_home="${TEMP_DIR}/tool-home-${platform}"
  log="${TEMP_DIR}/plugin-engine-homes-${platform}.txt"
  if [[ "${platform}" == "Darwin" ]]; then
    cache_path="${tool_home}/Library/Caches/org.swift.swiftpm"
    config_path="${tool_home}/Library/org.swift.swiftpm/configuration"
    security_path="${tool_home}/Library/org.swift.swiftpm/security"
  else
    cache_path="${tool_home}/.cache/org.swift.swiftpm"
    config_path="${tool_home}/.swiftpm/configuration"
    security_path="${tool_home}/.swiftpm/security"
  fi
  mkdir -p "${cache_path}" "${config_path}" "${security_path}"
  PATH="${TEMP_DIR}/fake-bin:${PATH}" HOME="${tool_home}" \
    CODEX_HOME="${tool_home}/inherited-codex-home" \
    CODEX_SQLITE_HOME="${tool_home}/inherited-codex-sqlite" \
    FAKE_UNAME_PLATFORM="${platform}" FAKE_SWIFT_NATIVE_HOME_LOG="${log}" \
    "${ROOT_DIR}/Scripts/test-plugin-engines.sh" > "${TEMP_DIR}/plugin-engine-private-home-${platform}.log"
  [[ "$(wc -l < "${log}")" -eq 2 ]]
  [[ "$(cut -f2 "${log}" | sort -u | wc -l)" -eq 2 ]]
  while IFS=$'\t' read -r command test_home fixed_home codex_home sqlite_home home_state engine; do
    [[ "${test_home}" == "${fixed_home}" && "${test_home}" != "${tool_home}" ]] || exit 1
    [[ "${codex_home}" == "${test_home}/.codex" && "${sqlite_home}" == "<unset>" ]] || exit 1
    [[ "${home_state}" == "present" && ! -e "${test_home}" ]] || exit 1
  done < "${log}"
  [[ "$(cut -f7 "${log}" | sed -n '1p')" == "<unset>" ]]
  [[ "$(cut -f7 "${log}" | sed -n '2p')" == "quickjs" ]]
  for swiftpm_path in \
    "--cache-path ${cache_path}" \
    "--config-path ${config_path}" \
    "--security-path ${security_path}"; do
    grep -Fq -- "${swiftpm_path}" "${log}"
  done
}
run_plugin_engine_private_home_case Darwin
run_plugin_engine_private_home_case Linux

python3 "${ROOT_DIR}/Scripts/test_swift_test_process_cleanup.py"

echo "Swift test sharding tests passed."
