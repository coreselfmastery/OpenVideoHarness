#!/usr/bin/env bash
# Time ManimGX renders on this machine (Kaggle T4 x2 included) and print a markdown table to paste
#   into a project's NOTES.md. Each mode runs N rounds; every round reports both the wall time
#   (uv startup included) and the engine's own "rendered in X s" (startup excluded), and the table
#   keeps the best round. The environment (CPU count, GPU, manimgx version) is recorded with the
#   numbers so a table from one machine is never mistaken for a table from another
#   (engines/manimgx-advanced.md, 速度数字).
# usage: tools/manimgx_bench.sh [--scene scenes/x.py::MyScene] [--rounds N] [--4k] [--draft-only]
#                               [--out file.md]
#   defaults: --scene showcase/03-math-fourier/scenes/fourier.py::FourierScene --rounds 1
#   modes rendered: draft (854x480 @ 15 fps, veryfast) and final (1920x1080 @ 30 fps, medium);
#   --4k adds 3840x2160 @ 30 fps; --draft-only skips final (and 4k).
#   The scene must live in a uv project (a pyproject.toml beside or above it: bin/vh new math
#   scaffolds one); renders run from the scene's directory, outputs go to a temp dir.
# Exit status: 0 every render succeeded (table printed) · 1 a render failed · 2 could not start.
set -uo pipefail
unset CDPATH
cd "$(dirname "$0")/.." || exit 2

scene_path=showcase/03-math-fourier/scenes/fourier.py
scene_name=FourierSquareWave
rounds=1
want_4k=0
draft_only=0
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --scene)      scene_path=${2%%::*}; scene_name=${2##*::}
                  [ "$scene_path" = "$scene_name" ] && { printf 'usage: --scene <path>::<Scene>\n' >&2; exit 2; }
                  shift 2 ;;
    --rounds)     rounds=$2; shift 2 ;;
    --4k)         want_4k=1; shift ;;
    --draft-only) draft_only=1; shift ;;
    --out)        out=$2; shift 2 ;;
    -h|--help)    sed -n '3,13p' "$0"; exit 0 ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[ -f "$scene_path" ] || { printf 'scene not found: %s\n' "$scene_path" >&2; exit 2; }
scene_dir=$(cd "$(dirname "$scene_path")" && pwd) || exit 2
scene_file=$scene_dir/$(basename "$scene_path")

if ! command -v uv >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/uv" ]; then
  printf 'uv not found: curl -LsSf https://astral.sh/uv/install.sh | sh\n' >&2; exit 2
fi
uv_run() {
  if command -v uv >/dev/null 2>&1; then uv run "$@"; else "$HOME/.local/bin/uv" run "$@"; fi
}

TMP=$(mktemp -d /tmp/mgx-bench.XXXXXX) || exit 2
trap 'rm -rf "$TMP"' EXIT

# one round: prints "wall engine" (seconds, engine may be empty)
one_round() {  # $1 = WxH, $2 = fps, $3 = preset
  local t0 t1 rc wall engine
  t0=$(date +%s.%N)
  ( cd "$scene_dir" && uv_run manimgx render -r "$1" --fps "$2" --preset "$3" \
      "$scene_file" "$scene_name" -o "$TMP/round.mp4" ) > "$TMP/render.log" 2>&1
  rc=$?
  t1=$(date +%s.%N)
  [ $rc -eq 0 ] && [ -s "$TMP/round.mp4" ] || { printf 'render failed (%s %sfps %s): tail of log:\n' "$1" "$2" "$3" >&2; tail -4 "$TMP/render.log" >&2; return 1; }
  wall=$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.1f", b - a }')
  engine=$(grep -o 'rendered in [0-9.]* s' "$TMP/render.log" | head -1 | grep -o '[0-9.]*' || true)
  printf '%s %s' "$wall" "${engine:-—}"
}

# a mode: N rounds, keep the best; prints "best-wall best-engine size"
run_mode() {  # $1 = label, $2 = WxH, $3 = fps, $4 = preset
  local label=$1 best="" best_engine="" line wall engine size
  for _ in $(seq 1 "$rounds"); do
    line=$(one_round "$2" "$3" "$4") || return 1
    wall=${line%% *}; engine=${line#* }
    if [ -z "$best" ] || awk -v a="$wall" -v b="$best" 'BEGIN { exit !(a < b) }'; then
      best=$wall; best_engine=$engine
    fi
  done
  size=$(du -h "$TMP/round.mp4" 2>/dev/null | cut -f1)
  printf '%s %s %s' "$best" "${best_engine:-—}" "${size:-?}"
  printf '  %s: %s s wall / %s s engine, %s\n' "$label" "$best" "${best_engine:-—}" "${size:-?}" >&2
}

gx_ver=$( ( cd "$scene_dir" && uv_run manimgx --version ) 2>/dev/null | tail -1 )
py_ver=$( ( cd "$scene_dir" && uv_run python --version ) 2>/dev/null | tail -1 )
gpu=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | paste -sd + -)
[ -n "$gpu" ] || gpu="no nvidia-smi"

{
  printf '### ManimGX benchmark — %s\n\n' "$(date -u +%Y-%m-%d)"
  printf 'scene `%s::%s` · %s · %s · %d CPU cores · GPU: %s · rounds per mode: %d (best kept)\n\n' \
    "$scene_path" "$scene_name" "${gx_ver:-manimgx ?}" "${py_ver:-python ?}" "$(nproc)" "$gpu" "$rounds"
  printf '| mode | resolution | fps | preset | best wall | engine | size |\n|---|---|---|---|---|---|---|\n'
} > "$TMP/table.md"

fails=0
if r=$(run_mode draft 854x480 15 veryfast); then
  read -r bw be bs <<< "$r"
  printf '| draft | 854x480 | 15 | veryfast | %s s | %s s | %s |\n' "$bw" "$be" "$bs" >> "$TMP/table.md"
else fails=$((fails + 1)); fi
if [ $draft_only = 0 ]; then
  if r=$(run_mode final 1920x1080 30 medium); then
    read -r bw be bs <<< "$r"
    printf '| final | 1920x1080 | 30 | medium | %s s | %s s | %s |\n' "$bw" "$be" "$bs" >> "$TMP/table.md"
  else fails=$((fails + 1)); fi
fi
if [ $want_4k = 1 ] && [ $draft_only = 0 ]; then
  if r=$(run_mode 4k 3840x2160 30 medium); then
    read -r bw be bs <<< "$r"
    printf '| 4k | 3840x2160 | 30 | medium | %s s | %s s | %s |\n' "$bw" "$be" "$bs" >> "$TMP/table.md"
  else fails=$((fails + 1)); fi
fi

cat "$TMP/table.md"
if [ -n "$out" ]; then mkdir -p "$(dirname "$out")" && cp "$TMP/table.md" "$out" && printf '\nwritten to %s\n' "$out"; fi
[ $fails -eq 0 ] || printf '\n%d mode(s) failed\n' "$fails" >&2
exit $(( fails > 0 ? 1 : 0 ))
