#!/usr/bin/env bash
# monitor.sh — one glance at EVERYTHING the Kaggle box is doing while renders run:
#   both T4s (util, memory, temperature, power), which processes hold each card,
#   CPU cores and load, RAM, and the /kaggle/working disk — the "no compromises"
#   check that all the GPU/CPU/RAM you pay for is actually being spent.
#
# usage: tools/kaggle/monitor.sh [--once] [--watch [N]] [--json] [--log FILE]
#                              [--no-cpu-sample] [-h]
#   --once          one snapshot and exit (the default)
#   --watch [N]     refresh every N seconds, minimum 2, default 5 (Ctrl-C stops;
#                   each snapshot prints whole — no screen tricks, so it works
#                   in a Kaggle notebook cell and in a log)
#   --json          machine-readable: one JSON object per line (JSONL), the
#                   same fields the human table shows
#   --log FILE      append every snapshot to FILE as JSONL (works with --watch;
#                   the file is created if missing, never truncated)
#   --no-cpu-sample skip the 1-second /proc/stat read that computes CPU busy%
#                   (a snapshot then costs ~0 s instead of ~1 s)
#
# What a healthy full-power run looks like (the two-card doctrine,
# engines/README.md's GPU 分工): during a Blender split both GPU rows near
# 100% util; during a web-film render GPU 0 (Chrome) busy and GPU 1 pulsing
# at NVENC encode time; CPU load well under the core count means the browsers
# are not starving; the number that kills a session is the DISK — renders stop
# when /kaggle/working fills toward 20 GB, and the 12-hour cap does the rest.
#
# Exit status: 0 a snapshot was taken (even with GPUs missing — the reason is
#   printed) · 2 usage error or an unwritable --log.
#
# Verified: stub-checked in tools/kaggle/test.sh's monitor group (query parsing,
#   the human table, JSON validity, the log, the refusals); on a real Kaggle
#   T4 box the numbers are the run's own NOTES.md material.
set -uo pipefail
unset CDPATH
cd "$(dirname "$0")/../.." || exit 2   # repo root

usage() { sed -n '4,25p' "$0"; }
die() { printf '[monitor] %s\n' "$*" >&2; exit 2; }

MODE="once"; INTERVAL=5; JSON=0; LOG=""; CPUSAMPLE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --once)        MODE="once" ;;
    --watch)       MODE="watch"
                   case "${2:-}" in
                     ''|*[!0-9]*) ;;              # --watch alone: keep default
                     *) INTERVAL="$2"; shift ;;
                   esac ;;
    --watch=*)     MODE="watch"; INTERVAL="${1#*=}" ;;
    --json)        JSON=1 ;;
    --log)         shift; LOG="${1:-}" ;;
    --log=*)       LOG="${1#*=}" ;;
    --no-cpu-sample) CPUSAMPLE=0 ;;
    -h|--help)     usage; exit 0 ;;
    -*) die "unknown option $1 (see --help)" ;;
    *) die "unexpected argument: $1" ;;
  esac; shift
done
case "$INTERVAL" in
  ''|*[!0-9]*) die "--watch takes a number of seconds (min 2), not $INTERVAL" ;;
esac
[ "$INTERVAL" -ge 2 ] || die "--watch needs at least 2 seconds, not $INTERVAL"
if [ -n "$LOG" ]; then
  # append-noop: creates the file if missing, proves it writable, never truncates
  : >>"$LOG" 2>/dev/null || die "cannot write log file: $LOG"
fi

# --- the one command that must exist for the GPU rows -------------------------------------
SMI=""
command -v nvidia-smi >/dev/null 2>&1 && SMI="nvidia-smi"

# --- collectors ---------------------------------------------------------------------------
gpu_rows() {   # index,name,util%,mem_used,mem_total,temp,power per line
  [ -n "$SMI" ] || return 0
  "$SMI" --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw \
         --format=csv,noheader,nounits 2>/dev/null
}
gpu_procs() {  # pid,name,mem per line (which process holds a card)
  [ -n "$SMI" ] || return 0
  "$SMI" --query-compute-apps=pid,process_name,used_memory --format=csv,noheader,nounits 2>/dev/null
}
trim() { printf '%s' "$1" | sed 's/^ *//;s/ *$//'; }

# CPU busy% over ~1 s from two /proc/stat reads (the aggregate cpu line)
cpu_busy() {
  [ "$CPUSAMPLE" = 1 ] || { printf 'null'; return; }
  [ -r /proc/stat ] || { printf 'null'; return; }
  read -r _ a1 b1 c1 d1 e1 f1 g1 _ </proc/stat || { printf 'null'; return; }
  idle1=$((d1 + e1)); total1=$((a1 + b1 + c1 + d1 + e1 + f1 + g1))
  sleep 1
  read -r _ a2 b2 c2 d2 e2 f2 g2 _ </proc/stat || { printf 'null'; return; }
  idle2=$((d2 + e2)); total2=$((a2 + b2 + c2 + d2 + e2 + f2 + g2))
  dt=$((total2 - total1)); di=$((idle2 - idle1))
  [ "$dt" -gt 0 ] || { printf 'null'; return; }
  printf '%d' $(( 100 * (dt - di) / dt ))
}
mem_kb() { awk -v key="$1" '$1 == key":" {print $2; exit}' /proc/meminfo 2>/dev/null; }

snapshot() {
  TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  CORES="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || printf '0')"
  LOAD1="$(awk '{print $1}' /proc/loadavg 2>/dev/null || printf 'null')"
  BUSY="$(cpu_busy)"
  MEM_T="$(mem_kb MemTotal)";  [ -n "$MEM_T" ] || MEM_T=0
  MEM_A="$(mem_kb MemAvailable)"; [ -n "$MEM_A" ] || MEM_A=0
  DISK_P="/kaggle/working"; [ -d "$DISK_P" ] || DISK_P="$PWD"
  DISK_LINE="$(df -h "$DISK_P" 2>/dev/null | awk 'NR==2 {print $3, $2}')"
  if [ -n "$DISK_LINE" ]; then DISK_U="${DISK_LINE% *}"; DISK_T="${DISK_LINE#* }"; else DISK_U="?"; DISK_T="?"; fi

  NGPU=0; GPUS_JSON=""; GPU_TABLE=""
  while IFS=',' read -r idx name util mu mt temp pw; do
    [ -n "${idx:-}" ] || continue
    NGPU=$((NGPU + 1))
    GPU_TABLE="$GPU_TABLE$(printf 'GPU%-2s  %-16s util %3s%%  mem %6s/%-6s MiB  %3s C  %5s W\n' \
      "$(trim "$idx")" "$(trim "$name")" "$(trim "$util")" "$(trim "$mu")" "$(trim "$mt")" \
      "$(trim "$temp")" "$(trim "$pw")")"
    GPUS_JSON="$GPUS_JSON{\"i\":$(trim "$idx"),\"util\":$(trim "$util"),\"mem_used_mib\":$(trim "$mu"),\"mem_total_mib\":$(trim "$mt"),\"temp_c\":$(trim "$temp"),\"power_w\":\"$(trim "$pw")\"},"
  done <<EOF
$(gpu_rows)
EOF
  GPUS_JSON="${GPUS_JSON%,}"

  PROCS_JSON=""
  while IFS=',' read -r pid pname pmem; do
    [ -n "${pid:-}" ] || continue
    PROCS_JSON="$PROCS_JSON{\"pid\":$(trim "$pid"),\"name\":\"$(trim "$pname")\",\"mem_mib\":$(trim "$pmem")},"
  done <<EOF
$(gpu_procs)
EOF
  PROCS_JSON="${PROCS_JSON%,}"

  if [ "$JSON" = 1 ]; then
    LINE="$(printf '{"ts":"%s","cpus":%s,"load1":%s,"cpu_busy_pct":%s,"mem":{"total_kb":%s,"avail_kb":%s},"disk":{"path":"%s","used":"%s","total":"%s"},"gpus":[%s],"gpu_procs":[%s]}' \
      "$TS" "$CORES" "$LOAD1" "$BUSY" "$MEM_T" "$MEM_A" "$DISK_P" "$DISK_U" "$DISK_T" "$GPUS_JSON" "$PROCS_JSON")"
    printf '%s\n' "$LINE"
    [ -n "$LOG" ] && printf '%s\n' "$LINE" >>"$LOG"
  else
    GB_T=$((MEM_T / 1048576)); GB_A=$((MEM_A / 1048576))
    H_BUSY="$BUSY"; [ "$H_BUSY" = null ] && H_BUSY="n/a"
    H_LOAD="$LOAD1"; [ "$H_LOAD" = null ] && H_LOAD="n/a"
    printf '[kaggle] %s · %s GPU(s) · CPU %s cores, load %s, busy %s%% · RAM avail %sG/%sG · disk %s of %s (%s)\n' \
      "$TS" "$NGPU" "$CORES" "$H_LOAD" "$H_BUSY" "$GB_A" "$GB_T" "$DISK_U" "$DISK_T" "$DISK_P"
    if [ -z "$SMI" ]; then
      printf 'no nvidia-smi on PATH — the GPU rows are absent, not zero (a CPU-only box?)\n'
    elif [ "$NGPU" = 0 ]; then
      printf 'nvidia-smi answered no cards — the query may have failed under load; retry\n'
    fi
    printf '%s' "$GPU_TABLE"
    if [ -n "$PROCS_JSON" ]; then
      printf 'card holders: '
      printf '%s' "$PROCS_JSON" | sed 's/},{/} · {/g; s/"pid":/pid /g; s/"name"://g; s/"mem_mib":/ MiB /g; s/[{}"]//g; s/,/ /g'
      printf '\n'
    fi
    [ -n "$LOG" ] && printf '{"ts":"%s","gpus":[%s],"cpu_busy_pct":%s,"load1":%s}\n' \
      "$TS" "$GPUS_JSON" "$BUSY" "$LOAD1" >>"$LOG"
  fi
  return 0
}

if [ "$MODE" = "watch" ]; then
  printf '[monitor] watching every %ss (Ctrl-C stops; every snapshot prints whole)\n' "$INTERVAL"
  while :; do snapshot; printf '\n'; sleep "$INTERVAL"; done
else
  snapshot
fi
