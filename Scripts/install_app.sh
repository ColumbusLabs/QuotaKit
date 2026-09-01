#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_PATH="${CODEXBAR_INSTALL_PATH:-/Applications/QuotaKit.app}"
SIGNING_MODE="${CODEXBAR_SIGNING:-}"

detect_signing_identity() {
  local identities preferred
  identities="$(security find-identity -p codesigning -v 2>/dev/null | sed -n 's/.*"\(.*\)"/\1/p')"
  if [[ -z "${identities}" ]]; then
    return 1
  fi

  if [[ -n "${APP_IDENTITY:-}" ]] && grep -Fx "${APP_IDENTITY}" <<<"${identities}" >/dev/null 2>&1; then
    printf '%s\n' "${APP_IDENTITY}"
    return 0
  fi

  local prefix
  for prefix in 'Developer ID Application:' 'Apple Development:'; do
    while IFS= read -r preferred; do
      [[ -n "${preferred}" ]] || continue
      printf '%s\n' "${preferred}"
      return 0
    done < <(grep -E "^${prefix}" <<<"${identities}")
  done

  return 1
}

export_team_id_from_identity() {
  local identity="${1:-}"
  if [[ -n "${APP_TEAM_ID:-}" || -z "${identity}" ]]; then
    return
  fi
  local subject
  subject="$(security find-certificate -c "${identity}" -p 2>/dev/null \
    | openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null || true)"
  if [[ "${subject}" =~ (^|,)OU=([A-Z0-9]{10})(,|$) ]]; then
    APP_TEAM_ID="${BASH_REMATCH[2]}"
    export APP_TEAM_ID
    return
  fi
  if [[ "${identity}" =~ \(([A-Z0-9]{10})\)$ ]]; then
    APP_TEAM_ID="${BASH_REMATCH[1]}"
    export APP_TEAM_ID
  fi
}

resolve_signing_mode() {
  if [[ -n "${SIGNING_MODE}" ]]; then
    export_team_id_from_identity "${APP_IDENTITY:-}"
    return
  fi

  if APP_IDENTITY="$(detect_signing_identity)"; then
    export APP_IDENTITY
    export_team_id_from_identity "${APP_IDENTITY}"
    SIGNING_MODE="identity"
    return
  fi

  SIGNING_MODE="adhoc"
}

cd "${ROOT_DIR}"
resolve_signing_mode
env \
  CODEXBAR_SIGNING="${SIGNING_MODE}" \
  CODEXBAR_INSTALL_PATH="${INSTALL_PATH}" \
  "${ROOT_DIR}/Scripts/package_app.sh" "$@"
