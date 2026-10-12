#!/usr/bin/env bash
# Samples the running QuotaKit Lite once a minute and fails on a footprint over 30 MB or any CPU sample over 1%
# (068 §9). Run it before installing a build with structural changes, and leave the Mac idle meanwhile.
#
# Usage: Scripts/lite-soak.sh [minutes]   (default 60)

set -euo pipefail

minutes="${1:-60}"
max_footprint_mb=30
max_cpu=1.0

pid="$(pgrep -x QuotaKitLite || true)"
[[ -n "$pid" ]] || { echo "error: QuotaKit Lite is not running" >&2; exit 1; }

failures=0
for ((sample = 1; sample <= minutes; sample++)); do
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "error: QuotaKit Lite (pid $pid) exited during the soak" >&2
    exit 1
  fi
  # "QuotaKitLite [123]: 64-bit    Footprint: 15 MB (16384 bytes per page)", in whole MB.
  footprint_mb="$(footprint "$pid" 2>/dev/null | awk '/Footprint:/ {
    for (i = 1; i < NF; i++) if ($i == "Footprint:") {
      value = $(i + 1); unit = $(i + 2)
      if (unit == "KB") value /= 1024; else if (unit == "GB") value *= 1024
      printf "%d", value + 0.5; exit
    }
  }')"
  cpu="$(ps -o %cpu= -p "$pid" | tr -d ' ')"
  status="ok"
  if [[ -n "$footprint_mb" ]] && (( footprint_mb > max_footprint_mb )); then
    status="FOOTPRINT"
    failures=$((failures + 1))
  fi
  if awk -v cpu="$cpu" -v max="$max_cpu" 'BEGIN { exit !(cpu > max) }'; then
    status="${status/ok/}CPU"
    failures=$((failures + 1))
  fi
  printf '%s  sample %d/%d  footprint %s MB  cpu %s%%  %s\n' \
    "$(date +%H:%M:%S)" "$sample" "$minutes" "${footprint_mb:-?}" "$cpu" "$status"
  (( sample < minutes )) && sleep 60
done

if (( failures > 0 )); then
  echo "soak failed: $failures sample(s) over budget" >&2
  exit 1
fi
echo "soak passed: $minutes samples within ${max_footprint_mb} MB and ${max_cpu}% CPU"
