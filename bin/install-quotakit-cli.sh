#!/usr/bin/env bash
set -euo pipefail

APP="/Applications/QuotaKit.app"
HELPER="$APP/Contents/Helpers/QuotaKitCLI"
TARGETS=("/usr/local/bin/quotakit" "/opt/homebrew/bin/quotakit")

if [[ ! -x "$HELPER" ]]; then
  echo "QuotaKitCLI helper not found at $HELPER. Please reinstall QuotaKit." >&2
  exit 1
fi

osascript - "$HELPER" <<'APPLESCRIPT'
on run argv
  set helperPath to item 1 of argv
  set installCommand to "set -euo pipefail" & linefeed & ¬
    "HELPER=" & quoted form of helperPath & linefeed & ¬
    "TARGETS=(\"/usr/local/bin/quotakit\" \"/opt/homebrew/bin/quotakit\")" & linefeed & ¬
    "for t in \"${TARGETS[@]}\"; do" & linefeed & ¬
    "  mkdir -p \"$(dirname \"$t\")\"" & linefeed & ¬
    "  ln -sf \"$HELPER\" \"$t\"" & linefeed & ¬
    "  echo \"Linked $t -> $HELPER\"" & linefeed & ¬
    "done"

  do shell script "bash -c " & quoted form of installCommand with administrator privileges
end run
APPLESCRIPT

echo "QuotaKit CLI installed. Try: quotakit usage"
