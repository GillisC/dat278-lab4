#!/usr/bin/env bash

set -euo pipefail

########################################
# CONFIG: define kernels & wrapper
########################################
KERNEL1="./img_preproc.sh"          # change to your executable
KERNEL2="./conv.sh"                 # change to your executable
WRAPPER_DIR="../utils/power"
WRAPPER="${WRAPPER_DIR}/power_wrapper.sh"

########################################
# ARGS
########################################
if [[ $# -ne 2 ]]; then
  echo "Usage: sudo $0 FREQ1_KHZ FREQ2_KHZ"
  exit 1
fi

FREQ1_KHZ="$1"
FREQ2_KHZ="$2"

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo."
  exit 1
fi

[[ -x "$KERNEL1" ]] || { echo "KERNEL1 missing: $KERNEL1"; exit 1; }
[[ -x "$KERNEL2" ]] || { echo "KERNEL2 missing: $KERNEL2"; exit 1; }
[[ -x "$WRAPPER" ]] || { echo "power_wrapper missing: $WRAPPER"; exit 1; }

########################################
# LOG FILE
########################################
BASE1="$(basename "$KERNEL1")"
BASE2="$(basename "$KERNEL2")"
LOGFILE="./dvfs_out/${BASE1}_${BASE2}_${FREQ1_KHZ}_${FREQ2_KHZ}.txt"
mkdir -p ./dvfs_out
: > "$LOGFILE"   # clear

log() {
  echo "$@" | tee -a "$LOGFILE" >&2
}

ts() { date "+%Y-%m-%d %H:%M:%S"; }

########################################
# CPU FREQ CONTROL (same style as sweep)
########################################
LOCK_TIMEOUT_MS=2000
SETTLE_MS=300

POLICY="/sys/devices/system/cpu/cpufreq/policy0"
SET_GOV="${POLICY}/scaling_governor"
SETSPEED="${POLICY}/scaling_setspeed"
MINF="${POLICY}/scaling_min_freq"
MAXF="${POLICY}/scaling_max_freq"
CURF="${POLICY}/scaling_cur_freq"
AVAIL_GOVS="${POLICY}/scaling_available_governors"

msleep() {
python3 - "$1" <<'PY'
import sys, time
time.sleep(int(sys.argv[1]) / 1000.0)
PY
}

bounded_wait_for_freq(){
  local target="$1"
  local waited=0 step=50
  while (( waited < LOCK_TIMEOUT_MS )); do
    local cur="$(cat "$CURF" 2>/dev/null || echo "$target")"
    if [[ "$cur" -eq "$target" ]]; then return 0; fi
    msleep "$step"; waited=$((waited+step))
  done
  return 1
}

choose_and_set_governor(){
  local req="userspace"
  if [[ -r "$AVAIL_GOVS" ]] && ! grep -qw userspace "$AVAIL_GOVS"; then
    req="performance"
  fi
  echo "$req" > "$SET_GOV" 2>/dev/null || true
  cat "$SET_GOV" 2>/dev/null || echo "?"
}

lock_freq_khz(){
  local khz="$1"

  echo "$khz" > "$MINF"
  echo "$khz" > "$MAXF"
  msleep "$SETTLE_MS"

  local gov
  gov="$(cat "$SET_GOV" 2>/dev/null || echo "")"
  if [[ "$gov" == "userspace" && -w "$SETSPEED" ]]; then
    echo "$khz" > "$SETSPEED" || true
  fi
  msleep "$SETTLE_MS"

  bounded_wait_for_freq "$khz" && return 0

  echo "$khz" > "$MINF"
  echo "$khz" > "$MAXF"
  msleep "$SETTLE_MS"
  bounded_wait_for_freq "$khz"
}

########################################
# power_wrapper helpers
########################################
parse_field(){
  grep -oE "$1=[0-9.]+" | head -1 | cut -d= -f2
}

# Extract "elapsed = XXXX.YYY ms" from kernel output
# Returns only the numeric value (milliseconds).
parse_kernel_elapsed_ms(){
  grep -oE 'elapsed *= *[0-9.]+ *ms' \
  | head -1 \
  | grep -oE '[0-9.]+' \
  | head -1
}

########################################
# RUN A KERNEL AT A FREQUENCY
# returns: "<LAT_MS> <ENE_MJ>"
########################################
run_kernel_at_freq(){
  local freq="$1"
  local kernel="$2"
  local label="$3"

  log ""
  log "==============================="
  log "          ${label}"
  log "==============================="
  log ""

  log "$(ts) | Running ${label} at ${freq} kHz"

  choose_and_set_governor >/dev/null || true

  if lock_freq_khz "$freq"; then
    local cur
    cur="$(cat "$CURF" 2>/dev/null || echo "$freq")"
    log "Locked to ~ $((cur/1000)) MHz (gov=$(cat "$SET_GOV" 2>/dev/null || echo '?'))"
  else
    log "⚠️ Failed to lock frequency to ${freq} kHz"
  fi

  # Run kernel via power_wrapper
  local OUT
  OUT="$("$WRAPPER" "$kernel" 2>&1 || true)"

  # Latency in ms from the kernel's "elapsed = X ms" line
  local LAT_MS
  LAT_MS="$(printf '%s\n' "$OUT" | parse_kernel_elapsed_ms || echo 0)"

  # Average power in W from power_wrapper
  local PWR_W
  PWR_W="$(printf '%s\n' "$OUT" | parse_field AVG_POWER_W || echo 0)"

  # Energy in mJ: E[mJ] = latency_ms * power_W
  local ENE_MJ
  ENE_MJ="$(awk -v lat="$LAT_MS" -v pwr="$PWR_W" 'BEGIN{printf "%.6f", lat * pwr}')"

  log "[${label}] latency (from kernel) = ${LAT_MS} ms"
  log "[${label}] power   (avg)         = ${PWR_W} W"
  log "[${label}] energy               = ${ENE_MJ} mJ"

  # Return values (for read)
  echo "$LAT_MS $ENE_MJ"
}

########################################
# MAIN
########################################

log "Two-kernel measurement"
log "Kernel1: $BASE1"
log "Kernel2: $BASE2"
log "Freq1:   $FREQ1_KHZ kHz"
log "Freq2:   $FREQ2_KHZ kHz"
log "Log file: $LOGFILE"
log "-----------------------------------------"

read LAT1_MS ENE1_MJ <<< "$(run_kernel_at_freq "$FREQ1_KHZ" "$KERNEL1" "Kernel 1")"
read LAT2_MS ENE2_MJ <<< "$(run_kernel_at_freq "$FREQ2_KHZ" "$KERNEL2" "Kernel 2")"

TOTAL_LAT_MS="$(awk -v a="$LAT1_MS" -v b="$LAT2_MS" 'BEGIN{printf "%.6f", a + b}')"
TOTAL_ENE_MJ="$(awk -v a="$ENE1_MJ" -v b="$ENE2_MJ" 'BEGIN{printf "%.6f", a + b}')"

log ""
log "==============================="
log "           SUMMARY"
log "==============================="
log ""
log "Total Latency: ${TOTAL_LAT_MS} ms"
log "Total Energy : ${TOTAL_ENE_MJ} mJ"
log "==============================="

# Only numeric total latency (in ms) to stdout
echo "$TOTAL_LAT_MS"