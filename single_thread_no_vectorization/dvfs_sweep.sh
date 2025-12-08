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
# ROOT PERMISSION CHECK
########################################
if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo."
  exit 1
fi

[[ -x "$KERNEL1" ]] || { echo "KERNEL1 missing: $KERNEL1"; exit 1; }
[[ -x "$KERNEL2" ]] || { echo "KERNEL2 missing: $KERNEL2"; exit 1; }
[[ -x "$WRAPPER" ]] || { echo "power_wrapper missing: $WRAPPER"; exit 1; }

########################################
# LOG FILES
########################################
BASE1="$(basename "$KERNEL1")"
BASE2="$(basename "$KERNEL2")"

mkdir -p ./dvfs_out

LOGFILE="./dvfs_out/sweep_${BASE1}_${BASE2}_$(date +%Y%m%d_%H%M%S).txt"
CSVFILE="./dvfs_out/sweep_${BASE1}_${BASE2}.csv"   # no timestamp

: > "$LOGFILE"   # clear text log
: > "$CSVFILE"   # clear/create CSV

log() {
  echo "$@" | tee -a "$LOGFILE" >&2
}

ts() { date "+%Y-%m-%d %H:%M:%S"; }

########################################
# CPU FREQ CONTROL
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
AVAIL_FREQS_FILE="${POLICY}/scaling_available_frequencies"

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

# Extract "elapsed = XXXX.YYY ms" from kernel output -> numeric ms
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
  log "-------------------------------"
  log " ${label} @ ${freq} kHz"
  log "-------------------------------"
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

  # Latency (ms) from kernel
  local LAT_MS
  LAT_MS="$(printf '%s\n' "$OUT" | parse_kernel_elapsed_ms || echo 0)"

  # Average power in W from power_wrapper
  local PWR_W
  PWR_W="$(printf '%s\n' "$OUT" | parse_field AVG_POWER_W || echo 0)"

  # Energy in mJ: E[mJ] = latency_ms * power_W
  local ENE_MJ
  ENE_MJ="$(awk -v lat="$LAT_MS" -v pwr="$PWR_W" 'BEGIN{printf "%.6f", lat * pwr}')"

  log "[${label}] latency = ${LAT_MS} ms"
  log "[${label}] power   = ${PWR_W} W"
  log "[${label}] energy  = ${ENE_MJ} mJ"

  echo "$LAT_MS $ENE_MJ"
}

########################################
# GET AVAILABLE FREQUENCIES
########################################
get_available_freqs(){
  local freqs=()

  if [[ -r "$AVAIL_FREQS_FILE" ]]; then
    # File usually contains a space-separated list of kHz values
    read -r -a freqs < "$AVAIL_FREQS_FILE"
  else
    # Fallback: just use min and max
    local minf maxf
    minf="$(cat "$MINF")"
    maxf="$(cat "$MAXF")"
    freqs=("$minf" "$maxf")
  fi

  echo "${freqs[@]}"
}

########################################
# MAIN SWEEP
########################################

log "Two-kernel DVFS sweep"
log "Kernel1: $BASE1"
log "Kernel2: $BASE2"
log "Text log: $LOGFILE"
log "CSV file: $CSVFILE"
log "-----------------------------------------"

FREQS=($(get_available_freqs))

log "Available frequencies (kHz): ${FREQS[*]}"
log ""

# CSV header (clean)
echo "COMBO_INDEX,FREQ1_KHZ,FREQ2_KHZ,LAT1_MS,LAT2_MS,TOTAL_LAT_MS,ENE1_MJ,ENE2_MJ,TOTAL_ENE_MJ" >> "$CSVFILE"
# Also echo header into text log for convenience
log "COMBO_INDEX,FREQ1_KHZ,FREQ2_KHZ,LAT1_MS,LAT2_MS,TOTAL_LAT_MS,ENE1_MJ,ENE2_MJ,TOTAL_ENE_MJ"

combo_idx=0

for F1 in "${FREQS[@]}"; do
  for F2 in "${FREQS[@]}"; do
    combo_idx=$((combo_idx + 1))

    log ""
    log "========================================="
    log " Combination #${combo_idx}: F1=${F1} kHz, F2=${F2} kHz"
    log "========================================="

    read LAT1_MS ENE1_MJ <<< "$(run_kernel_at_freq "$F1" "$KERNEL1" "Kernel 1")"
    read LAT2_MS ENE2_MJ <<< "$(run_kernel_at_freq "$F2" "$KERNEL2" "Kernel 2")"

    TOTAL_LAT_MS="$(awk -v a="$LAT1_MS" -v b="$LAT2_MS" 'BEGIN{printf "%.6f", a + b}')"
    TOTAL_ENE_MJ="$(awk -v a="$ENE1_MJ" -v b="$ENE2_MJ" 'BEGIN{printf "%.6f", a + b}')"

    log ""
    log "Summary for combination #${combo_idx}:"
    log "  Total Latency: ${TOTAL_LAT_MS} ms"
    log "  Total Energy : ${TOTAL_ENE_MJ} mJ"

    CSV_LINE="${combo_idx},${F1},${F2},${LAT1_MS},${LAT2_MS},${TOTAL_LAT_MS},${ENE1_MJ},${ENE2_MJ},${TOTAL_ENE_MJ}"

    # Write to text log
    log "$CSV_LINE"
    # Write to CSV file (no extra decoration)
    echo "$CSV_LINE" >> "$CSVFILE"

    # Sleep between combinations: 5 seconds (5000 ms)
    msleep 5000
  done
done

log ""
log "Sweep complete. Total combinations: ${combo_idx}"
log "Results CSV: $CSVFILE"