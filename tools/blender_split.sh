#!/usr/bin/env bash
# blender_split.sh — render one Blender sequence on BOTH T4s at once: split the frame
#   range across the GPUs, one blender process per card, each pinned by CUDA_VISIBLE_DEVICES
#   through tools/blender_run.sh (which also applies the Cycles profile). Two halves of a
#   range never share a GPU, so every frame is rendered whole on one card: the per-frame
#   pixels match a single-GPU render of that frame (blender-perf.md's determinism
#   stance — one device per render), unlike Cycles multi-GPU, which interleaves devices
#   inside every frame and changes the noise pattern (#101561).
#
# Why this is safe here: the harness's scene contract (engines/blender.md, "每帧是 t 的
#   纯函数：关键帧与物理") already requires physics as L0 analytic keyframes, L1 baked
#   keyframes or L2 disk caches — never simulated at render time — so frame N does not
#   depend on frame N-1 and a range split cannot change any frame. Scenes that break
#   that rule (unbaked particles, Geometry Nodes simulation zones) are out of contract
#   for this tool, exactly like render-split.sh's determinism gate for web films.
#
# usage: tools/blender_split.sh <scene.blend> [--frames START-END] [--out DIR]
#                              [--gpus N[,M…]] [--profile draft|final|final-cpu]
#                              [--bias A:B…] [--resume] [--encode OUT.mp4] [--fps N]
#                              [--nvenc] [--blender PATH] [--dry-run]
#   <scene.blend>    the scene to render (required).
#   --frames S-E     frame range; default: the scene's own frame_start..frame_end, read
#                    back with a 1-line bpy probe (adds one blender startup, ~2-5 s).
#   --out DIR        output folder for the PNG sequence (default: renders/blender-split/
#                    <scene-stem>/ under the repo root); files land as f_####.png.
#   --gpus N[,M…]    physical GPU indices to use (default: every GPU nvidia-smi lists;
#                    with one GPU the tool runs ONE unpinned process — Cycles multi-GPU
#                    is the fallback there, blender_run.sh's "no --gpu" mode).
#   --profile P      Cycles profile chain: draft | final | final-cpu (default: final),
#                    applied by tools/blender_run.sh before the render action.
#   --bias A:B…      work split between the GPUs, default 1:1 (equal). "2:1" gives the
#                    first GPU two frames for every one of the second — for when one
#                    card also rasterizes for Chrome (engines/README.md's GPU split
#                    table). A 0 weight skips that GPU's half entirely.
#   --resume         scan the output folder, render ONLY the missing frames (split
#                    across the GPUs through -f lists), keep everything already on disk.
#   --encode OUT.mp4 after the frames: ffmpeg the PNG sequence to an MP4 (libx264 CRF 18
#                    slow — the repo's delivery doctrine; --nvenc switches to
#                    h264_nvenc p7/cq 19, the Kaggle final tier from tools/kaggle/render.sh).
#   --fps N          encode frame rate (default 30; ignored without --encode).
#   --blender PATH   blender binary (passed through to blender_run.sh).
#   --dry-run        print the commands, render nothing.
#
# Exit status: 0 all frames on disk (and the encode if asked) · 1 a half failed or the
#   frame count is wrong · 2 usage error, no blender, or no scene file.
#
# Verified: two-process orchestration, range math, resume lists and the encode step run
#   against a stub blender (tools/blender_split_test.sh); live pair-render on real GPUs
#   is the Kaggle step (record the wall time in the project's NOTES.md beside
#   blender_bench.sh's calibration, budget = frames × median × 1.5).
set -uo pipefail
unset CDPATH
cd "$(dirname "$0")/.." || exit 2   # repo root, same convention as blender_run.sh

usage() { sed -n '4,45p' "$0"; }
die() { printf '[!!] %s\n' "$*" >&2; exit 2; }
say() { printf '[split] %s\n' "$*"; }

SCENE=""; FRAMES=""; OUT=""; GPUS=""; PROFILE="final"; BIAS=""
RESUME=0; ENCODE=""; FPS=30; NVENC=0; BLENDER=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --frames)  shift; FRAMES="${1:-}" ;;
    --out)     shift; OUT="${1:-}" ;;
    --gpus)    shift; GPUS="${1:-}" ;;
    --profile) shift; PROFILE="${1:-}" ;;
    --bias)    shift; BIAS="${1:-}" ;;
    --resume)  RESUME=1 ;;
    --encode)  shift; ENCODE="${1:-}" ;;
    --fps)     shift; FPS="${1:-}" ;;
    --nvenc)   NVENC=1 ;;
    --blender) shift; BLENDER="${1:-}" ;;
    --dry-run) DRY=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option $1 (see --help)" ;;
    *) [ -z "$SCENE" ] && SCENE=$1 || die "one scene file at a time" ;;
  esac; shift
done
[ -n "$SCENE" ] || { usage >&2; exit 2; }
[ -f "$SCENE" ] || die "scene not found: $SCENE"
case "$PROFILE" in draft|final|final-cpu) ;; *) die "--profile is draft | final | final-cpu, not $PROFILE" ;; esac
case "$FPS" in ''|*[!0-9]*) die "--fps takes a number, not $FPS" ;; esac

# --- GPUs: the cards to split across ---------------------------------------------------
if [ -n "$GPUS" ]; then
  IFS=',' read -r -a GPU_LIST <<< "$GPUS" || true
  [ "${#GPU_LIST[@]}" -ge 1 ] || die "--gpus needs numbers, got $GPUS"
else
  GPU_LIST=()
  if command -v nvidia-smi >/dev/null 2>&1; then
    while IFS= read -r gidx; do
      [ -n "$gidx" ] && GPU_LIST+=("$gidx")
    done < <(nvidia-smi -L 2>/dev/null | sed -n 's/^GPU \([0-9]*\):.*/\1/p')
  fi
  [ "${#GPU_LIST[@]}" -eq 0 ] && GPU_LIST=("")   # unpinned single process: Cycles multi-GPU
fi
NGPU=${#GPU_LIST[@]}

# --- frame range: --frames or the scene's own --------------------------------------------
if [ -n "$FRAMES" ]; then
  case "$FRAMES" in *[!0-9-]*) die "--frames takes START-END (e.g. 0-239), not $FRAMES" ;; esac
  FSTART="${FRAMES%%-*}"; FEND="${FRAMES##*-}"
  [ -n "$FSTART" ] && [ -n "$FEND" ] || die "--frames takes START-END, not $FRAMES"
else
  say "reading the scene's own frame range (one blender probe)…"
  PROBE="${BLENDER:-blender}"
  if ! command -v "$PROBE" >/dev/null 2>&1; then
    PROBE=""
    for c in ./blender ../blender /usr/local/bin/blender "$HOME/blender-5.2.2-linux-x64/blender"; do
      if command -v "$c" >/dev/null 2>&1; then PROBE="$c"; break; fi
    done
  fi
  [ -n "$PROBE" ] || die "no blender on PATH for the range probe; pass --blender PATH or --frames S-E"
  RANGE_LINE="$("$PROBE" -b "$SCENE" --python-expr \
    'import bpy; s=bpy.context.scene; print(f"{s.frame_start} {s.frame_end}")' 2>/dev/null | tail -n 1)" || true
  case "$RANGE_LINE" in
    *" "*) FSTART="${RANGE_LINE%% *}"; FEND="${RANGE_LINE##* }" ;;
    *) die "could not read the frame range; pass --frames START-END" ;;
  esac
  case "$FSTART$FEND" in *[!0-9]*) die "bad frame range from the scene: '$RANGE_LINE'" ;; esac
fi
[ "$FEND" -ge "$FSTART" ] || die "empty frame range: $FSTART-$FEND"
TOTAL=$((FEND - FSTART + 1))

# --- output folder: absolute, so blender_run.sh's repo-root cd cannot move it -------------
STEM="$(basename "$SCENE")"; STEM="${STEM%.blend}"
[ -n "$OUT" ] || OUT="renders/blender-split/$STEM"
mkdir -p "$OUT" || die "cannot create $OUT"
OUT="$(cd "$OUT" && pwd)" || exit 2
PATTERN="$OUT/f_####"

frame_file() { printf '%s/f_%04d.png' "$OUT" "$1"; }

# --- which frames are missing ---------------------------------------------------------------
ALL_FRAMES=()
i=$FSTART
while [ "$i" -le "$FEND" ]; do ALL_FRAMES+=("$i"); i=$((i + 1)); done
if [ "$RESUME" = 1 ]; then
  MISSING=()
  for f in "${ALL_FRAMES[@]}"; do
    [ -f "$(frame_file "$f")" ] || MISSING+=("$f")
  done
  say "resume: $((TOTAL - ${#MISSING[@]}))/$TOTAL frames already on disk, rendering ${#MISSING[@]}"
else
  MISSING=("${ALL_FRAMES[@]}")
fi
NMISS=${#MISSING[@]}
[ "$NMISS" -eq 0 ] && say "nothing to render: all $TOTAL frames on disk"

# --- split the work: weights → per-GPU lists -------------------------------------------------
WEIGHTS=()
if [ -n "$BIAS" ]; then
  IFS=':' read -r -a WEIGHTS <<< "$BIAS" || true
  [ "${#WEIGHTS[@]}" -eq "$NGPU" ] || die "--bias needs one weight per GPU ($NGPU), got $BIAS"
else
  for _ in $(seq 1 "$NGPU"); do WEIGHTS+=(1); done
fi
WSUM=0
for w in "${WEIGHTS[@]}"; do
  case "$w" in ''|*[!0-9]*) die "--bias weights are numbers, got $BIAS" ;; esac
  WSUM=$((WSUM + w))
done
[ "$WSUM" -gt 0 ] || die "--bias weights sum to zero"

# Each GPU gets its share by weight (floor), the LAST gpu with a non-zero weight takes
# the remainder, so counts always add up exactly. Contiguous shares render with
# -s/-e/-a (the repo's chunk pattern); anything with holes (resume) with -f list.
GPU_LISTS=(); GPU_CONTIG=()
i=0; done_count=0; g=0; last_nonzero=-1
for w in "${WEIGHTS[@]}"; do [ "$w" -gt 0 ] && last_nonzero=$g; g=$((g + 1)); done
say "splitting $NMISS frames across $NGPU GPU(s) (weights ${WEIGHTS[*]})"
g=0
for w in "${WEIGHTS[@]}"; do
  if [ "$g" = "$last_nonzero" ]; then
    want=$((NMISS - done_count))                    # remainder: exact by construction
  else
    want=$(( (NMISS * w) / WSUM ))
  fi
  list=""; prev=""; contig=1; n=0
  while [ "$n" -lt "$want" ] && [ "$i" -lt "$NMISS" ]; do
    f="${MISSING[$i]}"
    if [ -n "$prev" ] && [ "$((prev + 1))" != "$f" ]; then contig=0; fi
    list+="${f},"; prev="$f"
    i=$((i + 1)); n=$((n + 1))
  done
  GPU_LISTS[$g]="${list%,}"
  GPU_CONTIG[$g]=$contig
  done_count=$((done_count + n))
  g=$((g + 1))
done
[ "$done_count" -eq "$NMISS" ] || die "internal split error: $done_count of $NMISS frames assigned"

# --- run one blender per GPU -----------------------------------------------------------------
cleanup() {
  local p
  for p in ${PIDS[@]+"${PIDS[@]}"}; do kill "$p" 2>/dev/null; done
}
PIDS=()
trap cleanup INT TERM
g=0
while [ "$g" -lt "$NGPU" ]; do
  LIST="${GPU_LISTS[$g]}"
  if [ -z "$LIST" ]; then
    say "GPU ${GPU_LIST[$g]:-unpinned}: 0 frames (weight 0)"
    g=$((g + 1)); continue
  fi
  GPUARG=(); [ -n "${GPU_LIST[$g]}" ] && GPUARG=(--gpu "${GPU_LIST[$g]}")
  NFRAMES="$(awk -F, '{print NF}' <<< "$LIST")"
  if [ "${GPU_CONTIG[$g]}" = 1 ]; then
    FS="${LIST%%,*}"; FE="${LIST##*,}"
    RUN=(tools/blender_run.sh ${GPUARG[@]+"${GPUARG[@]}"} --profile "$PROFILE"
         ${BLENDER:+"--blender"} ${BLENDER:+"$BLENDER"} --
         blender -b "$SCENE" -o "$PATTERN" -F PNG -s "$FS" -e "$FE" -a)
  else
    RUN=(tools/blender_run.sh ${GPUARG[@]+"${GPUARG[@]}"} --profile "$PROFILE"
         ${BLENDER:+"--blender"} ${BLENDER:+"$BLENDER"} --
         blender -b "$SCENE" -o "$PATTERN" -F PNG -f "$LIST")
  fi
  say "GPU ${GPU_LIST[$g]:-unpinned}: $NFRAMES frames"
  if [ "$DRY" = 1 ]; then
    printf '[dry] %s\n' "${RUN[*]}"
  else
    LOG="$OUT/half-$g.log"
    "${RUN[@]}" >"$LOG" 2>&1 &
    PIDS+=($!)
  fi
  g=$((g + 1))
done
[ "$DRY" = 1 ] && { printf '[dry] nothing rendered\n'; exit 0; }

# --- wait + verify ------------------------------------------------------------------------------
FAILED=0
n=0
for pid in ${PIDS[@]+"${PIDS[@]}"}; do
  if ! wait "$pid"; then
    say "half $n FAILED (log: $OUT/half-$n.log)"; FAILED=1
  fi
  n=$((n + 1))
done
GOT=0
for f in "${ALL_FRAMES[@]}"; do
  [ -f "$(frame_file "$f")" ] && GOT=$((GOT + 1))
done
if [ "$GOT" -ne "$TOTAL" ]; then
  say "frame count mismatch: $GOT/$TOTAL on disk"
  FAILED=1
fi

# --- encode ---------------------------------------------------------------------------------------
if [ -n "$ENCODE" ] && [ "$FAILED" = 0 ]; then
  ENC=(-c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p)
  [ "$NVENC" = 1 ] && ENC=(-c:v h264_nvenc -preset p7 -cq 19 -pix_fmt yuv420p)
  say "encoding $TOTAL frames → $ENCODE"
  if ffmpeg -y -hide_banner -nostdin -loglevel error -framerate "$FPS" \
       -i "$OUT/f_%04d.png" "${ENC[@]}" "$ENCODE"; then
    say "encoded: $ENCODE"
  else
    say "encode failed"; FAILED=1
  fi
fi

[ "$FAILED" = 0 ] && say "done: $TOTAL frames in $OUT" || exit 1
exit 0
