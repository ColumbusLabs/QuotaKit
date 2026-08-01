#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

# shellcheck disable=SC1091
source "$ROOT/Scripts/load-release-secrets.sh"

required=(
  APP_STORE_CONNECT_API_KEY_FILE
  APP_STORE_CONNECT_KEY_ID
  APP_STORE_CONNECT_ISSUER_ID
  APP_IDENTITY
)
for variable in "${required[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "ERROR: $variable is required in the QuotaKit release environment." >&2
    exit 2
  fi
done

if [[ ! -f "$APP_STORE_CONNECT_API_KEY_FILE" ]]; then
  echo "ERROR: App Store Connect API key file was not found." >&2
  exit 2
fi

export QUOTAKIT_MAC_PROFILE_OUTPUT="${QUOTAKIT_MAC_PROFILE_OUTPUT:-$ROOT/Provisioning/QuotaKit_Dev.provisionprofile}"
export QUOTAKIT_MAC_BUNDLE_ID="${MAC_RELEASE_BUNDLE_ID:-com.columbuslabs.quotakit.mac}"

exec ruby "$ROOT/Scripts/refresh-mac-direct-profile.rb"
