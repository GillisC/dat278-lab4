#!/bin/bash
# power_sampler.sh — sample RPi PMIC current/voltage and stream instantaneous power (W)

set -euo pipefail

POWER_OUT="$1"
: "${POWER_OUT:?Usage: power_sampler.sh <output_file>}"

BOTH=$(mktemp)
CURRENT=$(mktemp)
TENSION=$(mktemp)

cleanup() {
  rm -f "$CURRENT" "$TENSION" "$BOTH"
}
trap cleanup EXIT

while true; do
  # ~1 kHz target (best-effort; vcgencmd is the bottleneck)
  sleep 0.001
  vcgencmd pmic_read_adc > "$BOTH"
  grep current "$BOTH" | awk '{print substr($2, 1, length($2)-1)}' | sed 's/.*=//g' > "$CURRENT"
  grep volt    "$BOTH" | awk '{print substr($2, 1, length($2)-1)}' | sed 's/.*=//g' | head -12 > "$TENSION"
  paste "$CURRENT" "$TENSION" | awk '{sum+=$1*$2}END{print sum}' >> "$POWER_OUT"
done