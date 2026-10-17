#!/usr/bin/env bash
# render.sh — a HyperFrames render with every speed setting the machine allows, and nothing that
# would change the film: fps, workers, the capture path and the encoder are chosen from what
# tools/kaggle/setup.sh probed (run it once first; it writes .kaggle/env.sh). Sound is not a HyperFrames
# thing: bin/vh mux puts the mix on after, as with any HyperFrames render in this repo.
#
#   tools/kaggle/render.sh <project> [options]        <project>: the folder with index.html
#
#   Options this script takes (everything else is passed to `hyperframes render` unchanged):
#     --workers N         override the worker policy below
#     --fps N             override the fps policy below
#     --no-gpu            encode on the CPU (libx264) even though setup.sh found NVENC
#     --no-fast-capture   render through screenshots, not the drawElement fast capture
#     --detach            run in the background (HYPERFRAMES_RENDER_DETACHED=1); the log path is printed
#
#   Examples:
#     tools/kaggle/render.sh projects/26-launch --quality draft            # review pass
#     tools/kaggle/render.sh projects/26-launch --quality delivery        # final pass
#     tools/kaggle/render.sh projects/26-launch --quality draft --resolution 4k
#
# The policies (each one is a measured trap in HyperFrames 0.8.82 — engines/README.md's HyperFrames
# section and tools/kaggle/README.md have the numbers):
#   fps       the composition's own data-fps is kept when it is 30 or less (a film written at 24 stays
#             24); 30 when it asks for nothing; when it asks for more than 30 a notice is printed and
#             its choice is kept — add --fps 30 yourself if the film's spec allows halving the frames.
#   workers   under 240 s: 1 (a single worker keeps the streaming encode; multi-worker short films
#             buffer every frame to disk first). 240 s and up: HyperFrames auto — with the fast capture
#             that is the parallel router's 3 workers, and an explicit --workers here would switch the
#             router off (it only routes when the count was left to auto). Software rendering: one
#             worker per spare core, at most 6.
#   encoder   --gpu when NVENC probed OK: HyperFrames encodes with h264_nvenc at the --quality's own
#             constant-quality level, on the second T4 (.kaggle/ffmpeg-gpu.sh pins it there), so the
#             browser keeps GPU 0. bin/vh deliver still re-encodes the platform copy on the CPU.
#   capture   --browser-gpu and --experimental-fast-capture only when setup.sh saw hardware WebGL:
#             on a software GPU the fast capture is slower than screenshots, so it is never asked for.
set -euo pipefail
unset CDPATH
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

case "${1:-}" in
  -h|--help) sed -n '2,35p' "$0"; exit 0 ;;
  "") sed -n '2,35p' "$0" >&2; exit 1 ;;
esac
PROJ=$1; shift
case "$PROJ" in
  -*) printf '\033[31m✗\033[0m the project folder comes first: tools/kaggle/render.sh <project> [options]\n' >&2; exit 1 ;;
esac

ENVF="$ROOT/.kaggle/env.sh"
if [ ! -f "$ENVF" ]; then
  printf '\033[31m✗\033[0m no %s: run tools/kaggle/setup.sh once first (it probes the GPUs, caches Chrome and writes it)\n' "$ENVF" >&2
  exit 2
fi
# shellcheck disable=SC1090   # env.sh is written by tools/kaggle/setup.sh; every value in it was probed there
. "$ENVF"

DETACH=0; NO_GPU=0; NO_FAST=0; WORKERS_OPT=""; FPS_OPT=""; pass=()
while [ $# -gt 0 ]; do
  case "$1" in
    --detach) DETACH=1 ;;
    --no-gpu) NO_GPU=1 ;;
    --no-fast-capture) NO_FAST=1 ;;
    --workers) WORKERS_OPT=${2:?--workers needs a number}; shift ;;
    --workers=*) WORKERS_OPT=${1#*=} ;;
    -w) WORKERS_OPT=${2:?-w needs a number}; shift ;;
    --fps) FPS_OPT=${2:?--fps needs a number}; shift ;;
    --fps=*) FPS_OPT=${1#*=} ;;
    -f) FPS_OPT=${2:?-f needs a number}; shift ;;
    -h|--help) sed -n '2,35p' "$0"; exit 0 ;;
    *) pass+=("$1") ;;
  esac
  shift
done
if [ ! -f "$PROJ/index.html" ]; then
  printf '\033[31m✗\033[0m no index.html in %s (a HyperFrames project is a folder with one; bin/vh hf-init scaffolds it)\n' "$PROJ" >&2
  exit 1
fi
PROJ="$(cd "$PROJ" && pwd)"

# the film's own length and frame rate, from the root composition (what `hyperframes render` itself reads)
meta=$(python3 - "$PROJ/index.html" <<'PY'
import re, sys
try: s = open(sys.argv[1], encoding="utf-8").read()
except OSError: sys.exit(0)
root = ""
for tag in re.findall(r'<div[^>]*\bdata-composition-id\b[^>]*>', s):
    root = tag; break
def attr(name):
    m = re.search(r'\b' + name + r'="([\d.]+)"', root)
    return m.group(1) if m else ""
print(attr("data-duration"), attr("data-fps"))
PY
)
DUR=${meta%% *}; DFPS=${meta##* }

flags=(); fps_note=""; workers_note=""

# ── fps ─────────────────────────────────────────────────────────────────────────────────────────
if [ -n "$FPS_OPT" ]; then
  flags+=(--fps "$FPS_OPT"); fps_note="fps $FPS_OPT (yours)"
elif [ -z "$DFPS" ]; then
  flags+=(--fps 30); fps_note="fps 30 (no data-fps; HyperFrames' own default, made explicit)"
elif awk -v d="$DFPS" 'BEGIN{exit !(d<=30)}'; then
  fps_note="fps $DFPS (the composition's own; kept, it is 30 or less)"
else
  fps_note="fps $DFPS (the composition asks for it; add --fps 30 to halve the frames if the film's spec allows)"
fi

# ── workers ─────────────────────────────────────────────────────────────────────────────────────
if [ -n "$WORKERS_OPT" ]; then
  flags+=(--workers "$WORKERS_OPT"); workers_note="workers $WORKERS_OPT (yours)"
elif [ -z "$DUR" ]; then
  workers_note="workers: HyperFrames auto (no data-duration to read)"
elif awk -v d="$DUR" 'BEGIN{exit !(d<240)}'; then
  flags+=(--workers 1); workers_note="workers 1 (under 240 s: a single worker keeps the streaming encode)"
elif [ "${OVH_KAGGLE_BROWSER_GPU:-software}" = hardware ]; then
  workers_note="workers: HyperFrames auto, with the fast capture that is the parallel router's 3 (an explicit --workers would switch the router off)"
else
  cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
  w=$((cores - 1)); if [ $w -lt 1 ]; then w=1; fi; if [ $w -gt 6 ]; then w=6; fi
  flags+=(--workers "$w"); workers_note="workers $w (software rendering: one Chrome per spare core, at most 6)"
fi

# ── encoder and capture ─────────────────────────────────────────────────────────────────────────
if [ "${OVH_KAGGLE_NVENC:-0}" = 1 ] && [ "$NO_GPU" = 0 ]; then
  flags+=(--gpu)
fi
if [ "${OVH_KAGGLE_BROWSER_GPU:-software}" = hardware ]; then
  flags+=(--browser-gpu)
  if [ "$NO_FAST" = 0 ]; then flags+=(--experimental-fast-capture); fi
fi

# ── the launcher ────────────────────────────────────────────────────────────────────────────────
if [ -x "$PROJ/node_modules/.bin/hyperframes" ]; then
  cmd=("$PROJ/node_modules/.bin/hyperframes")
else
  cmd=(npx --yes "hyperframes@${HYPERFRAMES_VERSION:-0.8.82}")   # bin/vh hf-init pins it into the project
fi

printf '\033[36m→\033[0m project  : %s (%s)\n' "$PROJ" "$(if [ -n "$DUR" ]; then printf '%s s' "$DUR"; else printf 'length unknown'; fi)"
if [ "${OVH_KAGGLE_BROWSER_GPU:-software}" = hardware ]; then
  printf '\033[36m→\033[0m browser  : GPU 0, hardware WebGL (%s)\n' "${OVH_KAGGLE_WEBGL_RENDERER:-probed OK}"
else
  printf '\033[36m→\033[0m browser  : CPU (SwiftShader software rendering)\n'
fi
if [ "${OVH_KAGGLE_NVENC:-0}" = 1 ] && [ "$NO_GPU" = 0 ]; then
  printf '\033[36m→\033[0m encode   : GPU %s, h264_nvenc at the --quality level (bin/vh deliver still re-encodes the platform copy on the CPU)\n' "${OVH_KAGGLE_NVENC_GPU:-0}"
else
  printf '\033[36m→\033[0m encode   : CPU (libx264)\n'
fi
printf '\033[36m→\033[0m %s\n' "$fps_note"
printf '\033[36m→\033[0m %s\n' "$workers_note"
printf '\033[36m→\033[0m command  : %s\n' "$(printf '%s ' "${cmd[@]}" render . ${flags[@]+"${flags[@]}"} ${pass[@]+"${pass[@]}"})"

cd "$PROJ"
if [ "$DETACH" = 1 ]; then
  mkdir -p out
  log="$PROJ/out/render-$(date +%Y%m%d-%H%M%S).log"
  HYPERFRAMES_RENDER_DETACHED=1 nohup "${cmd[@]}" render . ${flags[@]+"${flags[@]}"} ${pass[@]+"${pass[@]}"} >"$log" 2>&1 &
  printf '\033[32m✓\033[0m detached — log: %s\n' "$log"
  printf '  watch : tail -f %s\n' "$log"
  printf '  stop  : pkill -f "]yperframes render.*%s"\n' "$PROJ"
else
  exec "${cmd[@]}" render . ${flags[@]+"${flags[@]}"} ${pass[@]+"${pass[@]}"}
fi
