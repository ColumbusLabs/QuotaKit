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

if grep -qE "^[[:space:]]*accountEmail" "$SCHEMA_OUT"; then
    echo "==> SUCCESS: accountEmail is already in Production schema."
    grep -E "QuotaTransition|accountEmail" "$SCHEMA_OUT" | head -10
    exit 0
fi

echo "==> accountEmail NOT in Production schema yet. Patching ..."

# Find the QuotaTransition RECORD TYPE block and add accountEmail
# field right after the existing deviceID field. The .ckdb format
# is a textual DSL with `RECORD TYPE` / `field <name> <Type>` lines.
python3 <<PY > "$SCHEMA_PATCHED"
import re
import sys

with open("$SCHEMA_OUT") as f:
    text = f.read()

# Inside the QuotaTransition record type, insert `accountEmail String`
# after `deviceID String` if not already present.
pattern = re.compile(
    r"(RECORD TYPE QuotaTransition[^}]*?deviceID\s+String[^\n]*\n)",
    re.DOTALL)
def insert(match):
    return match.group(1) + "    accountEmail String\n"
new_text, n = pattern.subn(insert, text, count=1)
if n == 0:
    sys.stderr.write("could not find QuotaTransition.deviceID anchor — manual edit needed\n")
    sys.exit(3)
sys.stdout.write(new_text)
PY

echo "==> Patched schema:"
diff "$SCHEMA_OUT" "$SCHEMA_PATCHED" | head -20

echo
echo "==> Importing patched schema into Production"
xcrun cktool import-schema \
    --team-id "$TEAM_ID" \
    --container-id "$CONTAINER_ID" \
    --environment PRODUCTION \
    --file "$SCHEMA_PATCHED"

echo
echo "==> Verifying accountEmail is now in Production"
xcrun cktool export-schema \
    --team-id "$TEAM_ID" \
    --container-id "$CONTAINER_ID" \
    --environment PRODUCTION \
    --output-file "$SCHEMA_OUT.final"
if grep -qE "^[[:space:]]*accountEmail" "$SCHEMA_OUT.final"; then
    echo "==> DEPLOYED: accountEmail is live in Production. Mac 65.3 writes will succeed."
    grep -E "QuotaTransition|accountEmail" "$SCHEMA_OUT.final" | head -10
else
    echo "==> WARNING: deploy completed but accountEmail not visible in re-export — please verify manually in Dashboard."
    exit 4
fi
