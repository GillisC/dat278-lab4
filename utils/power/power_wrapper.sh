#!/bin/bash
# power_wrapper.sh — run a command while sampling power; print time, avg W, energy J

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

POWER_FILE="$(mktemp)"
"${SCRIPT_DIR}/power_sampler.sh" "$POWER_FILE" &
SAMPLER_PID=$!

# time the command
start_ts="$(date +%s.%N)"
"$@"
cmd_rc=$?
end_ts="$(date +%s.%N)"

# stop sampler
kill "$SAMPLER_PID" 2>/dev/null || true

# compute elapsed seconds using awk (handles floating subtraction)
elapsed_s="$(awk -v a="$start_ts" -v b="$end_ts" 'BEGIN{printf "%.6f", (b-a)}')"

# drop last (possibly partial) line; ignore error if file empty
sed -i '$ d' "$POWER_FILE" || true

# average power (W); 0.0 if no samples
avg_w="$(awk '{s+=$1;n++} END{ if(n>0) printf "%.6f", s/n; else printf "0.000000" }' "$POWER_FILE")"
rm -f "$POWER_FILE"

# energy (J)
energy_j="$(awk -v t="$elapsed_s" -v p="$avg_w" 'BEGIN{printf "%.6f", t*p}')"

# machine-friendly output
echo "EXEC_TIME_S=${elapsed_s}"
echo "AVG_POWER_W=${avg_w}"
echo "ENERGY_J=${energy_j}"

exit "$cmd_rc"