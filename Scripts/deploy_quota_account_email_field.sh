#!/usr/bin/env bash
# Deploy the v0.27.0 build 65.3 schema change — adding `accountEmail`
# to the `QuotaTransition` CKRecord type — to CloudKit Production.
#
# Without this step, new Mac builds (65.3+) that try to write
# `accountEmail` to a QuotaTransition record will be rejected by
# Production schema validation and push notifications will silently
# stop firing.
#
# Two modes:
#
# 1) `cktool` mode (preferred, fully automated). Requires:
#    - A CloudKit Management Token (Dashboard → Container → Tokens)
#    - `cktool save-token --type management --token "$TOKEN"`
#    Then run this script with no args.
#
# 2) Manual Dashboard mode (fallback). The script prints the steps
#    when no token is available.
#
# Either way, after the deploy completes, the script verifies the
# field is present in the live Production schema by exporting it
# and grepping for `accountEmail`.
set -euo pipefail

TEAM_ID="3TUERHN53E"
CONTAINER_ID="iCloud.com.o1xhack.codexbar"
SCHEMA_OUT="/tmp/codexbar-ck-prod-schema.ckdb"
SCHEMA_PATCHED="/tmp/codexbar-ck-prod-schema.patched.ckdb"

echo "==> Probing CloudKit Production schema for QuotaTransition.accountEmail"

# Scope the grep to the QuotaTransition block specifically. The schema
# already has an `accountEmail` field on `DeviceProviderSnapshot`
# (envelope record); we want to know whether QuotaTransition itself
# has the column.
quotaTransitionHasField() {
    awk '/RECORD TYPE QuotaTransition \(/,/^[[:space:]]*\)$/' "$1" \
        | grep -qE "^[[:space:]]+accountEmail[[:space:]]"
}

if ! xcrun cktool export-schema \
        --team-id "$TEAM_ID" \
        --container-id "$CONTAINER_ID" \
        --environment PRODUCTION \
        --output-file "$SCHEMA_OUT" 2>&1
then
    cat <<'EOF'

==> cktool needs a management token. Two paths:

    A) Save a token first (one-time setup):
       1. Open https://icloud.developer.apple.com
       2. Select container iCloud.com.o1xhack.codexbar
       3. Tokens → Create Management Token (full schema scope)
       4. xcrun cktool save-token --type management --token "<paste>"
       5. Re-run this script.

    B) Manual Dashboard deploy (no token needed):
       1. Open https://icloud.developer.apple.com
       2. Container iCloud.com.o1xhack.codexbar → Schema
       3. Record Types → QuotaTransition
       4. Add Field: accountEmail (String)
       5. Click "Deploy Schema Changes to Production"
       6. Choose accountEmail and confirm
       7. After deploy, re-run this script to verify.

EOF
    exit 2
fi

echo "==> Production schema fetched ($(wc -l < "$SCHEMA_OUT") lines)"

if quotaTransitionHasField "$SCHEMA_OUT"; then
    echo "==> SUCCESS: accountEmail is already on QuotaTransition in Production."
    awk '/RECORD TYPE QuotaTransition \(/,/^[[:space:]]*\)$/' "$SCHEMA_OUT"
    exit 0
fi

echo "==> accountEmail NOT on QuotaTransition in Production. Two-step CloudKit flow:"
echo "    1) import patched schema to Development (automated below)"
echo "    2) Deploy Dev → Production via Dashboard (manual — cktool has no deploy-schema)"

# Step 1: import the patched schema into Development. Apple's
# CloudKit API rejects `import-schema --environment PRODUCTION` with
# "endpoint not applicable in the environment 'production'" — only
# Development accepts schema imports. Production picks up the change
# only via the explicit Dashboard "Deploy Schema Changes to
# Production" action.
SCHEMA_DEV="/tmp/codexbar-ck-dev-schema.ckdb"
SCHEMA_DEV_PATCHED="/tmp/codexbar-ck-dev-schema.patched.ckdb"

echo
echo "==> Fetching Development schema"
xcrun cktool export-schema \
    --team-id "$TEAM_ID" \
    --container-id "$CONTAINER_ID" \
    --environment DEVELOPMENT \
    --output-file "$SCHEMA_DEV"

if quotaTransitionHasField "$SCHEMA_DEV"; then
    echo "==> Development already has accountEmail on QuotaTransition. Skipping patch step."
else
    echo "==> Patching Development schema to add accountEmail to QuotaTransition"
    # `set -euo pipefail` is active, so a non-zero awk exit aborts the
    # whole script. Wrap in `if !` so we can emit our own error
    # message before exiting.
    if ! awk '
        BEGIN { inQT = 0; inserted = 0 }
        /RECORD TYPE QuotaTransition[[:space:]]*\(/ { inQT = 1 }
        inQT && /^[[:space:]]+deviceID[[:space:]]+STRING/ && !inserted {
            print "        accountEmail    STRING,"
            inserted = 1
        }
        inQT && /^[[:space:]]*\)[[:space:]]*$/ { inQT = 0 }
        { print }
        END { if (!inserted) exit 3 }
    ' "$SCHEMA_DEV" > "$SCHEMA_DEV_PATCHED"; then
        echo "ERROR: awk could not find QuotaTransition.deviceID anchor in $SCHEMA_DEV — manual edit needed." >&2
        exit 3
    fi
    diff "$SCHEMA_DEV" "$SCHEMA_DEV_PATCHED" | head -10

    cat <<'EOF'

  ⚠️  RACE WARNING ⚠️
  `cktool import-schema` has FULL-SCHEMA OVERWRITE semantics. If
  another developer has added a Dev schema field on this container
  since we fetched the schema 2 lines up, that field will be WIPED
  by the import below. Window is ~5 seconds in practice.

  Verify Dev schema editor in Dashboard is closed before proceeding.

EOF

    echo "==> Importing patched schema into Development"
    xcrun cktool import-schema \
        --team-id "$TEAM_ID" \
        --container-id "$CONTAINER_ID" \
        --environment DEVELOPMENT \
        --file "$SCHEMA_DEV_PATCHED"

    echo "==> Verifying Development now has accountEmail on QuotaTransition"
    xcrun cktool export-schema \
        --team-id "$TEAM_ID" \
        --container-id "$CONTAINER_ID" \
        --environment DEVELOPMENT \
        --output-file "$SCHEMA_DEV"
    if ! quotaTransitionHasField "$SCHEMA_DEV"; then
        echo "==> ERROR: Development import succeeded but re-export does not show accountEmail."
        exit 5
    fi
fi

echo
echo "==> Step 1 complete. Step 2 (MANUAL):"
cat <<'EOF'

    Open https://icloud.developer.apple.com
    → Container iCloud.com.o1xhack.codexbar
    → Schema
    → Click "Deploy Schema Changes to Production" (top right)
    → Verify the dialog shows: QuotaTransition + accountEmail (STRING)
    → Click "Deploy" to confirm.

    Then re-run this script — it will verify accountEmail is live in
    Production and exit 0.

EOF
exit 0
