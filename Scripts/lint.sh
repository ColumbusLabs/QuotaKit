#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${ROOT_DIR}/.build/lint-tools/bin"

ensure_tools() {
  if [[ ! -x "${BIN_DIR}/swiftformat" || ! -x "${BIN_DIR}/swiftlint" ]]; then
    "${ROOT_DIR}/Scripts/install_lint_tools.sh"
  fi
}

cmd="${1:-lint}"

case "$cmd" in
  lint)
    ensure_tools
    "${BIN_DIR}/swiftformat" Sources Tests --lint
    "${BIN_DIR}/swiftlint" --strict
    ;;
  format)
    ensure_tools
    "${BIN_DIR}/swiftformat" Sources Tests
    ;;
  *)
    printf 'Usage: %s [lint|format]\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac

