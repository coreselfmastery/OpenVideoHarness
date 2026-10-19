#!/usr/bin/env bash
# Time Blender Cycles renders through the performance layer on this machine (Kaggle 2x T4
#   included) and print a markdown table to paste into a project's NOTES.md / LOCAL.md —
#   the machine-readable form of engines/blender.md's "校准协议" (calibrate 5 frames before
#   believing any number). Each mode renders 5 spread frames of a real swatch scene via
#   styles/_swatch/blender_render.py (the repo's own workload, not a synthetic cube), N
#   rounds, best kept. Wall time includes Blender startup; the per-frame column is the sum
#   of the renderer's own per-frame lines. The environment (device, GPU, Blender build,
#   cores) is stamped with the numbers so a table from one machine is never mistaken for
#   a table from another (engines/blender-perf.md, 测量).
# usage: tools/blender_bench.sh [--slug tabletop-miniature] [--frames 0,37,74,111,149]
#                               [--rounds 1] [--no-4k] [--pct 100] [--out file.md]
#   modes: draft (GPU, 32 adaptive/0.1, 120 s cap, Simplify), final (CPU determinism anchor),
#          fast (GPU final profile — the Kaggle quality path), 4k (fast at --pct 200).
#   --no-4k skips the 4K row; --pct overrides the resolution percentage for the first three.
#   A GPU-less machine still works: every GPU mode falls back to CPU with a note in its row.
# Exit status: 0 every mode produced a table row · 1 a mode failed · 2 could not start.
set -uo pipefail
unset CDPATH
cd "$(dirname "$0")/.." || exit 2   # repo root

slug=tabletop-miniature
frames=0,37,74,111,149
rounds=1
no_4k=0
pct=100
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --slug)    slug=$2; shift 2 ;;
    --frames)  frames=$2; shift 2 ;;
    --rounds)  rounds=$2; shift 2 ;;
    --no-4k)   no_4k=1; shift ;;
    --pct)     pct=$2; shift 2 ;;
    --out)     out=$2; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[ -d "styles/$slug" ] || { printf 'no such swatch: styles/%s (see styles/)\n' "$slug" >&2; exit 2; }

BLENDER="${BLENDER:-}"
if ! command -v "${BLENDER:-blender}" >/dev/null 2>&1; then
  for c in ./blender ../blender /usr/local/bin/blender "$HOME/blender-5.2.2-linux-x64/blender"; do
    command -v "$c" >/dev/null 2>&1 && BLENDER="$c" && break
  done
fi
command -v "${BLENDER:-blender}" >/dev/null 2>&1 || { printf 'blender not found: pass BLENDER=… or put it on PATH\n' >&2; exit 2; }

TMP=$(mktemp -d /tmp/bl-bench.XXXXXX) || exit 2
trap 'rm -rf "$TMP"' EXIT

# one round: prints "wall frame_sum device_note"
one_round() {  # $1 = quality, $2 = pct
  local t0 t1 rc wall fsum dnote
  t0=$(date +%s.%N)
  "$BLENDER" -b --factory-startup -noaudio --python-exit-code 1 \
    --python styles/_swatch/blender_render.py -- "styles/$slug" "$TMP/out" \
    --frames "$frames" --quality "$1" --pct "$2" > "$TMP/log" 2>&1
  rc=$?
  t1=$(date +%s.%N)
  [ $rc -eq 0 ] || { printf 'render failed (%s @%s%%): tail of log:\n' "$1" "$2" >&2; tail -4 "$TMP/log" >&2; return 1; }
  wall=$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.1f", b - a }')
  fsum=$(grep -oE '[0-9.]+s *$' "$TMP/log" | grep -oE '[0-9.]+' | awk '{s+=$1} END { printf "%.1f", s }')
  dnote=$(grep -m1 '^\[swatch\] built' "$TMP/log" | sed -E 's/^.*· [a-z]+: //; s/ · [0-9]+ samples.*//; s/  +/ /g; s/ $//')
  printf '%s %s %s' "$wall" "${fsum:-—}" "${dnote:-?}"
}

# a mode: N rounds, keep the best by wall; prints "best-wall frames device"
run_mode() {  # $1 = label, $2 = quality, $3 = pct
  local label=$1 best="" best_f="" best_d="" line wall fsum dnote
  for _ in $(seq 1 "$rounds"); do
    line=$(one_round "$2" "$3") || return 1
    wall=${line%% *}; rest=${line#* }; fsum=${rest%% *}; dnote=${rest#* }
    if [ -z "$best" ] || awk -v a="$wall" -v b="$best" 'BEGIN { exit !(a < b) }'; then
      best=$wall; best_f=$fsum; best_d=$dnote
    fi
  done
  printf '%s %s %s' "$best" "${best_f:-—}" "${best_d:-?}"
  printf '  %s: %s s wall / %s s in frames / %s\n' "$label" "$best" "${best_f:-—}" "${best_d:-?}" >&2
}

bl_ver=$("$BLENDER" --version 2>/dev/null | head -1 | grep -oE 'Blender [0-9.]+' || echo 'Blender ?')
gpu=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | paste -sd + -)
[ -n "$gpu" ] || gpu="no nvidia-smi"

{
  printf '### Blender Cycles benchmark — %s\n\n' "$(date -u +%Y-%m-%d)"
  printf 'scene `styles/%s` · frames `%s` · %s · %d CPU cores · GPU: %s · rounds per mode: %d (best kept)\n\n' \
    "$slug" "$frames" "$bl_ver" "$(nproc)" "$gpu" "$rounds"
  printf '| mode | quality | pct | best wall | in frames | device |\n|---|---|---|---|---|---|\n'
} > "$TMP/table.md"

fails=0
for mode in "draft:draft:$pct" "final:final:$pct" "fast:fast:$pct"; do
  label=${mode%%:*}; rest=${mode#*:}; q=${rest%%:*}; p=${rest#*:}
  if r=$(run_mode "$label" "$q" "$p"); then
    read -r bw bf bd <<< "$r"
    printf '| %s | %s | %s%% | %s s | %s s | %s |\n' "$label" "$q" "$p" "$bw" "$bf" "$bd" >> "$TMP/table.md"
  else fails=$((fails + 1)); fi
done
if [ "$no_4k" = 0 ]; then
  if r=$(run_mode 4k fast 200); then
    read -r bw bf bd <<< "$r"
    printf '| 4k | fast | 200%% | %s s | %s s | %s |\n' "$bw" "$bf" "$bd" >> "$TMP/table.md"
  else fails=$((fails + 1)); fi
fi

cat "$TMP/table.md"
if [ -n "$out" ]; then mkdir -p "$(dirname "$out")" && cp "$TMP/table.md" "$out" && printf '\nwritten to %s\n' "$out"; fi
[ $fails -eq 0 ] || printf '\n%d mode(s) failed\n' "$fails" >&2
exit $(( fails > 0 ? 1 : 0 ))
