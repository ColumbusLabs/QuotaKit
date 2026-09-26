#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="${ROOT_DIR}/.build/lint-tools"
BIN_DIR="${TOOLS_DIR}/bin"

SWIFTFORMAT_VERSION="0.63.0"
SWIFTLINT_VERSION="0.65.1"

SWIFTFORMAT_SHA256_DARWIN="28c7802e11fa5ae113d903066439c6bb1be20a8ac1ad9709c42616a7e273fb0f"
SWIFTLINT_SHA256_DARWIN="c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0"
SWIFTFORMAT_SHA256_LINUX_X86_64="b4a3cbb8c852a0baaf9adf853e221ff1dabf921a3d8957a602e0bda3af8470f1"
SWIFTLINT_SHA256_LINUX_X86_64="caeed6f4a679c35539ffaf124f6c4ab4a8416917f7d8796279dc52b74026059d"
SWIFTFORMAT_SHA256_LINUX_ARM64="b0335af32e2c5944a17b3e6d916ff4552eb757ed88f68b80fd19415824850717"
SWIFTLINT_SHA256_LINUX_ARM64="9ffa52f478e6d8eb485d37d14715ffac90abc81c58f3370d598bf75be05605f8"

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

INSTALL_SWIFTFORMAT=false
INSTALL_SWIFTLINT=false

if [[ "$#" -eq 0 ]]; then
  INSTALL_SWIFTFORMAT=true
  INSTALL_SWIFTLINT=true
else
  for tool in "$@"; do
    case "$tool" in
      all)
        INSTALL_SWIFTFORMAT=true
        INSTALL_SWIFTLINT=true
        ;;
      swiftformat)
        INSTALL_SWIFTFORMAT=true
        ;;
      swiftlint)
        INSTALL_SWIFTLINT=true
        ;;
      *)
        fail "Unknown lint tool '${tool}'. Usage: $(basename "$0") [all|swiftformat|swiftlint]..."
        ;;
    esac
  done
fi

sha256_value() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return 0
  fi
  fail "Missing shasum/sha256sum."
}

download_file() {
  local url="$1"
  local out="$2"
  curl -fL --retry 3 --retry-connrefused --retry-delay 2 -o "$out" "$url"
}

install_zip_binary() {
  local label="$1"
  local url="$2"
  local expected_sha="$3"
  local binary_name="$4"
  local installed_name="${5:-$binary_name}"

  local tmp_zip
  tmp_zip="$(mktemp -t "${label}.XXXX")"
  local tmp_dir
  tmp_dir="$(mktemp -d -t "${label}.XXXX")"

  log "==> Downloading ${label}"
  download_file "$url" "$tmp_zip"

  local actual_sha
  actual_sha="$(sha256_value "$tmp_zip")"
  if [[ -n "$expected_sha" && "$actual_sha" != "$expected_sha" ]]; then
    rm -f "$tmp_zip"
    rm -rf "$tmp_dir"
    fail "${label} SHA256 mismatch (expected ${expected_sha}, got ${actual_sha})"
  fi

  unzip -q "$tmp_zip" -d "$tmp_dir"

  local extracted_path=""
  if [[ -f "${tmp_dir}/${binary_name}" ]]; then
    extracted_path="${tmp_dir}/${binary_name}"
  else
    extracted_path="$(find "$tmp_dir" -type f -name "$binary_name" | head -n 1 || true)"
  fi

  if [[ -z "$extracted_path" || ! -f "$extracted_path" ]]; then
    rm -f "$tmp_zip"
    rm -rf "$tmp_dir"
    fail "${label} binary '${binary_name}' not found in archive"
  fi

  install -m 0755 "$extracted_path" "${BIN_DIR}/${installed_name}"

  rm -f "$tmp_zip"
  rm -rf "$tmp_dir"
}

mkdir -p "$BIN_DIR"

swiftformat_installed() {
  [[ -x "${BIN_DIR}/swiftformat" ]] \
    && [[ "$("${BIN_DIR}/swiftformat" --version 2>/dev/null || true)" == "${SWIFTFORMAT_VERSION}" ]]
}

swiftlint_installed() {
  [[ -x "${BIN_DIR}/swiftlint" ]] \
    && [[ "$("${BIN_DIR}/swiftlint" version 2>/dev/null || true)" == "${SWIFTLINT_VERSION}" ]]
}

if { [[ "$INSTALL_SWIFTFORMAT" != true ]] || swiftformat_installed; } \
  && { [[ "$INSTALL_SWIFTLINT" != true ]] || swiftlint_installed; }
then
  log "==> Requested lint tools already installed"
  exit 0
fi

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Darwin)
    SWIFTFORMAT_URL="https://github.com/nicklockwood/SwiftFormat/releases/download/${SWIFTFORMAT_VERSION}/swiftformat.zip"
    SWIFTLINT_URL="https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/portable_swiftlint.zip"

    if [[ "$INSTALL_SWIFTFORMAT" == true ]] && ! swiftformat_installed; then
      install_zip_binary "SwiftFormat ${SWIFTFORMAT_VERSION}" "$SWIFTFORMAT_URL" "$SWIFTFORMAT_SHA256_DARWIN" "swiftformat"
    fi
    if [[ "$INSTALL_SWIFTLINT" == true ]] && ! swiftlint_installed; then
      install_zip_binary "SwiftLint ${SWIFTLINT_VERSION}" "$SWIFTLINT_URL" "$SWIFTLINT_SHA256_DARWIN" "swiftlint"
    fi
    ;;
  Linux)
    case "$ARCH" in
      x86_64)
        SWIFTFORMAT_URL="https://github.com/nicklockwood/SwiftFormat/releases/download/${SWIFTFORMAT_VERSION}/swiftformat_linux.zip"
        SWIFTLINT_URL="https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/swiftlint_linux_amd64.zip"
        SWIFTFORMAT_BINARY="swiftformat_linux"
        SWIFTFORMAT_SHA256="$SWIFTFORMAT_SHA256_LINUX_X86_64"
        SWIFTLINT_SHA256="$SWIFTLINT_SHA256_LINUX_X86_64"
        ;;
      aarch64|arm64)
        SWIFTFORMAT_URL="https://github.com/nicklockwood/SwiftFormat/releases/download/${SWIFTFORMAT_VERSION}/swiftformat_linux_aarch64.zip"
        SWIFTLINT_URL="https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/swiftlint_linux_arm64.zip"
        SWIFTFORMAT_BINARY="swiftformat_linux_aarch64"
        SWIFTFORMAT_SHA256="$SWIFTFORMAT_SHA256_LINUX_ARM64"
        SWIFTLINT_SHA256="$SWIFTLINT_SHA256_LINUX_ARM64"
        ;;
      *)
        fail "Unsupported Linux arch: ${ARCH}"
        ;;
    esac

    if { [[ "$INSTALL_SWIFTFORMAT" == true ]] && [[ -z "$SWIFTFORMAT_SHA256" ]]; } \
      || { [[ "$INSTALL_SWIFTLINT" == true ]] && [[ -z "$SWIFTLINT_SHA256" ]]; }
    then
      log "WARN: Linux SHA256 verification not configured for ${ARCH}; installing anyway."
    fi
    if [[ "$INSTALL_SWIFTFORMAT" == true ]] && ! swiftformat_installed; then
      install_zip_binary "SwiftFormat ${SWIFTFORMAT_VERSION}" "$SWIFTFORMAT_URL" "$SWIFTFORMAT_SHA256" "$SWIFTFORMAT_BINARY" "swiftformat"
    fi
    if [[ "$INSTALL_SWIFTLINT" == true ]] && ! swiftlint_installed; then
      install_zip_binary "SwiftLint ${SWIFTLINT_VERSION}" "$SWIFTLINT_URL" "$SWIFTLINT_SHA256" "swiftlint"
    fi
    ;;
  *)
    fail "Unsupported OS: ${OS}"
    ;;
esac

log "==> Installed lint tools to ${BIN_DIR}"
if [[ "$INSTALL_SWIFTFORMAT" == true ]]; then
  "${BIN_DIR}/swiftformat" --version
fi
if [[ "$INSTALL_SWIFTLINT" == true ]]; then
  "${BIN_DIR}/swiftlint" version
fi
