#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
This script is deprecated and intentionally does not deploy schema changes.

It used to target an inherited CloudKit container. Current QuotaKit releases
use:

  Team:      78PXX669LQ
  Container: iCloud.com.columbuslabs.quotakit

Use the read-only verifier instead:

  Scripts/verify-cloudkit-schema.sh

If it reports missing Production schema, deploy the changes manually in
CloudKit Dashboard:

  https://icloud.developer.apple.com
  Container iCloud.com.columbuslabs.quotakit
  Schema -> Deploy Schema Changes to Production
EOF

exit 2
