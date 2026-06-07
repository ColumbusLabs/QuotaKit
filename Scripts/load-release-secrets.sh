#!/usr/bin/env bash

if [[ -n "${QUOTAKIT_RELEASE_SECRETS_LOADED:-}" ]]; then
  return 0
fi

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DEFAULT_RELEASE_ENV="$HOME/.quotakit-secrets/quotakit-release.env"
RELEASE_ENV_CANDIDATES=()

if [[ -n "${QUOTAKIT_RELEASE_ENV:-}" ]]; then
  RELEASE_ENV_CANDIDATES+=("${QUOTAKIT_RELEASE_ENV}")
elif [[ -n "${CODEXBAR_RELEASE_ENV:-}" ]]; then
  RELEASE_ENV_CANDIDATES+=("${CODEXBAR_RELEASE_ENV}")
fi
RELEASE_ENV_CANDIDATES+=(
  "${DEFAULT_RELEASE_ENV}"
  "${ROOT}/.quotakit-release.local.env"
)

for release_env in "${RELEASE_ENV_CANDIDATES[@]}"; do
  if [[ -n "$release_env" && -f "$release_env" ]]; then
    # shellcheck disable=SC1090
    source "$release_env"
    break
  fi
done

if [[ -z "${SPARKLE_PRIVATE_KEY_FILE:-}" && -f "$HOME/.quotakit-secrets/sparkle_ed25519.key" ]]; then
  SPARKLE_PRIVATE_KEY_FILE="$HOME/.quotakit-secrets/sparkle_ed25519.key"
fi

if [[ -z "${APP_STORE_CONNECT_API_KEY_FILE:-}" && -n "${APP_STORE_CONNECT_KEY_ID:-}" ]]; then
  candidate_key="$HOME/.quotakit-secrets/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
  if [[ -f "$candidate_key" ]]; then
    APP_STORE_CONNECT_API_KEY_FILE="$candidate_key"
  fi
fi

export SPARKLE_PRIVATE_KEY_FILE
export APP_STORE_CONNECT_API_KEY_FILE
export APP_STORE_CONNECT_API_KEY_P8
export APP_STORE_CONNECT_KEY_ID
export APP_STORE_CONNECT_ISSUER_ID
export APP_IDENTITY
export QUOTAKIT_RELEASE_SECRETS_LOADED=1
