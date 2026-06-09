#!/usr/bin/env bash
set -euo pipefail

TEAM_ID="${QUOTAKIT_CLOUDKIT_TEAM_ID:-78PXX669LQ}"
CONTAINER_ID="${QUOTAKIT_CLOUDKIT_CONTAINER_ID:-iCloud.com.columbuslabs.quotakit}"
ENVIRONMENT="${QUOTAKIT_CLOUDKIT_ENVIRONMENT:-PRODUCTION}"
SCHEMA_OUT="${QUOTAKIT_CLOUDKIT_SCHEMA_OUT:-$(mktemp /tmp/quotakit-cloudkit-schema.XXXXXX)}"

if [[ "${QUOTAKIT_SKIP_CLOUDKIT_SCHEMA_VERIFY:-0}" == "1" ]]; then
  cat <<EOF
WARNING: Skipping CloudKit Production schema verification because
QUOTAKIT_SKIP_CLOUDKIT_SCHEMA_VERIFY=1 is set.

This bypass is only for documented emergency releases. Normal Mac releases
must verify ${CONTAINER_ID} ${ENVIRONMENT} before publishing.
EOF
  exit 0
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "ERROR: xcrun is required to run cktool schema verification." >&2
  exit 2
fi

echo "==> Exporting CloudKit schema"
echo "    team:      ${TEAM_ID}"
echo "    container: ${CONTAINER_ID}"
echo "    env:       ${ENVIRONMENT}"

if ! xcrun cktool export-schema \
    --team-id "$TEAM_ID" \
    --container-id "$CONTAINER_ID" \
    --environment "$ENVIRONMENT" \
    --output-file "$SCHEMA_OUT"
then
  cat <<EOF >&2

ERROR: Could not export CloudKit schema.

cktool requires a CloudKit Management Token. Save one with:

  xcrun cktool save-token --type management --token "<token>"

Create the token in CloudKit Dashboard:
  https://icloud.developer.apple.com
  Container: ${CONTAINER_ID}
  Tokens -> Create Management Token

If this is an emergency release, set QUOTAKIT_SKIP_CLOUDKIT_SCHEMA_VERIFY=1
and document why in the release notes/checklist.
EOF
  exit 2
fi

record_block() {
  local record_type="$1"
  awk -v record_type="$record_type" '
    in_block && $0 ~ "^[[:space:]]*RECORD TYPE[[:space:]]+" {
      exit
    }
    $0 ~ "^[[:space:]]*RECORD TYPE[[:space:]]+" record_type "[[:space:]]*\\(" {
      in_block = 1
    }
    in_block {
      print
    }
  ' "$SCHEMA_OUT"
}

record_type_exists() {
  local record_type="$1"
  record_block "$record_type" | grep -q "RECORD TYPE"
}

field_exists() {
  local record_type="$1"
  local field="$2"
  record_block "$record_type" | grep -qE "^[[:space:]]+${field}[[:space:]]+"
}

queryable_field_exists() {
  local record_type="$1"
  local field="$2"
  record_block "$record_type" | awk -v field="$field" '
    /QUERYABLE/ {
      in_queryable = 1
    }
    in_queryable && $0 ~ field {
      found = 1
    }
    END {
      exit found ? 0 : 1
    }
  '
}

failures=()

require_record_type() {
  local record_type="$1"
  if ! record_type_exists "$record_type"; then
    failures+=("missing record type: ${record_type}")
  fi
}

require_field() {
  local record_type="$1"
  local field="$2"
  if ! field_exists "$record_type" "$field"; then
    failures+=("missing field: ${record_type}.${field}")
  fi
}

require_queryable_field() {
  local record_type="$1"
  local field="$2"
  if ! queryable_field_exists "$record_type" "$field"; then
    failures+=("missing queryable index: ${record_type}.${field}")
  fi
}

require_queryable_record_name() {
  local record_type="$1"
  if ! queryable_field_exists "$record_type" "recordName" \
      && ! queryable_field_exists "$record_type" "___recordID"
  then
    failures+=("missing queryable index: ${record_type}.recordName")
  fi
}

require_record_type "DeviceSnapshot"
require_field "DeviceSnapshot" "deviceName"
require_field "DeviceSnapshot" "deviceID"
require_field "DeviceSnapshot" "appVersion"
require_field "DeviceSnapshot" "syncTimestamp"
require_field "DeviceSnapshot" "payload"
require_queryable_record_name "DeviceSnapshot"

require_record_type "DeviceProviderSnapshot"
require_field "DeviceProviderSnapshot" "deviceID"
require_field "DeviceProviderSnapshot" "deviceName"
require_field "DeviceProviderSnapshot" "providerID"
require_field "DeviceProviderSnapshot" "providerName"
require_field "DeviceProviderSnapshot" "accountEmail"
require_field "DeviceProviderSnapshot" "lastUpdated"
require_field "DeviceProviderSnapshot" "encodingVersion"
require_field "DeviceProviderSnapshot" "payload"
require_queryable_field "DeviceProviderSnapshot" "deviceID"
require_queryable_record_name "DeviceProviderSnapshot"

require_record_type "ProviderAccountLinkage"
require_field "ProviderAccountLinkage" "providerID"
require_field "ProviderAccountLinkage" "linkedIdentifiers"
require_field "ProviderAccountLinkage" "confirmedAt"
require_field "ProviderAccountLinkage" "confirmedFromDeviceID"
require_field "ProviderAccountLinkage" "unmerge"
require_queryable_record_name "ProviderAccountLinkage"

require_record_type "QuotaTransition"
require_field "QuotaTransition" "providerName"
require_field "QuotaTransition" "providerID"
require_field "QuotaTransition" "state"
require_field "QuotaTransition" "transitionAt"
require_field "QuotaTransition" "deviceID"
require_field "QuotaTransition" "accountEmail"

if ((${#failures[@]} > 0)); then
  echo
  echo "ERROR: CloudKit ${ENVIRONMENT} schema is not release-ready:" >&2
  for failure in "${failures[@]}"; do
    echo "  - ${failure}" >&2
  done
  cat <<EOF >&2

Deploy the missing schema changes to Production in CloudKit Dashboard:
  https://icloud.developer.apple.com
  Container: ${CONTAINER_ID}
  Schema -> Deploy Schema Changes to Production
EOF
  exit 1
fi

echo "==> CloudKit ${ENVIRONMENT} schema verified for ${CONTAINER_ID}"
