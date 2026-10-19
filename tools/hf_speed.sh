#!/usr/bin/env bash
# hf_speed.sh — the HyperFrames render speed layer: one command per tier, with the flags this repo
#   has verified (engines/remotion-speed.md). Two tiers, no creative compromise between them:
#
#     draft   iteration at GPU speed — Chrome on the host GPU (--browser-gpu: Linux launches with
#             --use-gl=angle --use-angle=gl-egl, the angle-egl path) + NVENC hardware encoding
#             (--gpu: probes nvenc/vaapi/qsv/amf and falls back to libx264 where there is no GPU)
#             + JPEG q80 intermediates + segmented capture. NOT byte-deterministic: GPU text
#             raster and NVENC output vary per run/machine, so drafts go to out/, never ship.
#     final   the delivery path this repo trusts: software Chrome (--no-browser-gpu) + screenshot
#             capture (--experimental-fast-capture=false) + software x264 (--quality delivery) —
#             byte-stable and free of the GPU bad-frame class (engines/README.md, "浏览器 GPU"),
#             with parallel-stream capture and segmented capture + resume so a long film survives
#             a crash and only re-renders the missing segments.
#     4k      final at --resolution 4k with the 8 GB Node heap the repo already recommends.
#
# usage: tools/hf_speed.sh <project-dir> [--tier draft|final|4k] [--fps N] [--workers N]
#                          [--output PATH] [--segment-frames N | --no-segments] [--resume]
#                          [--keep-segments] [--bitrate 8M | --crf N] [--dry-run]
#        tools/hf_speed.sh <project-dir> --bench [--runs N]
#        tools/hf_speed.sh <project-dir> --gpu-probe
#
#   <project-dir>        a HyperFrames project (index.html + hyperframes.json; what bin/vh hf-init
#                        scaffolds). The binary resolves to $HYPERFRAMES_BIN, else the project's
#                        own node_modules/.bin/hyperframes (hf-init pins 0.8.82), else
#                        npx hyperframes@${HYPERFRAMES_VERSION:-0.8.82}.
#   --tier               draft (default) | final | 4k — see above
#   --fps N              pass through (composition default stays; --fps 15 is the extra-speed
#                        draft option — motion is half-sampled, judge layout/timing only)
#   --workers N          parallel Chrome workers (default 2, right for 4 vCPU: auto resolves to
#                        max(6, cores/8) which oversubscribes a small box; each worker ≈ 256 MB)
#   --output PATH        default out/draft.mp4 / out/final.mp4 / out/final-4k.mp4 under the project
#   --segment-frames N   segmented capture (both tiers, mp4): N frames per segment, default 3000
#                        (100 s at 30 fps); browser recycled every 3 segments; segments land in
#                        renders/.hf-segments/<hash>/ — with --keep-segments a crashed render
#                        resumes with --resume and only re-renders the missing segments
#   --no-segments        render monolithic (byte-identical to a plain hyperframes render)
#   --bitrate 8M         with draft's NVENC: -b:v instead of -cq (NVENC files run larger than
#                        x264 at equal quality; 8M ≈ a CRF-18 x264 1080p30 file)
#   --crf N              override the software encoder CRF (final/4k, or draft on a GPU-less box)
#   --bench              hyperframes benchmark: renders preset fps/quality/worker configs and
#                        compares speed and size — the honest way to pick --workers
#   --gpu-probe          doctor + nvidia-smi + the ffmpeg encoder list: what the GPU path will do
#                        on this machine, before committing to a render
#   --dry-run            print the exact command and env, run nothing
#
# Exit status: 0 rendered/benchmarked/probed · 1 the render or benchmark failed ·
#   2 could not start (no project dir, no hyperframes binary, bad option).
# The repo's standing env applies (bin/vh hf-init): HYPERFRAMES_SKIP_SKILLS=1 DO_NOT_TRACK=1 are
# set here too. For background runs add HYPERFRAMES_RENDER_DETACHED=1 yourself (engines/README.md,
# "用 & 或 nohup 把渲染放到后台" — the variable must sit on that one line, not be exported).
set -uo pipefail
unset CDPATH

usage() { sed -n '3,44p' "$0"; }
die() { printf '\033✗\033 %s\n' "$*" >&2; exit 2; }
ok()  { printf '\033✓\033 %s\n' "$*"; }
wa()  { printf '\033!\033 %s\n' "$*" >&2; }

dir=""; tier=draft; fps=""; workers=2; output=""; seg_frames=3000; segments=1
resume=0; keep=0; bitrate=""; crf=""; dry=0; bench=0; runs=3; probe=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tier) tier=${2:?}; shift ;; --tier=*) tier=${1#*=} ;;
    --fps) fps=${2:?}; shift ;; --fps=*) fps=${1#*=} ;;
    --workers) workers=${2:?}; shift ;; --workers=*) workers=${1#*=} ;;
    --output|-o) output=${2:?}; shift ;; --output=*) output=${1#*=} ;;
    --segment-frames) seg_frames=${2:?}; shift ;; --segment-frames=*) seg_frames=${1#*=} ;;
    --no-segments) segments=0 ;;
    --resume) resume=1 ;; --keep-segments) keep=1 ;;
    --bitrate) bitrate=${2:?}; shift ;; --bitrate=*) bitrate=${1#*=} ;;
    --crf) crf=${2:?}; shift ;; --crf=*) crf=${1#*=} ;;
    --bench) bench=1 ;; --runs) runs=${2:?}; shift ;; --runs=*) runs=${1#*=} ;;
    --gpu-probe) probe=1 ;;
    --dry-run) dry=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option $1 (see --help)" ;;
    *) [ -z "$dir" ] && dir=$1 || die "one project directory at a time" ;;
  esac; shift
done
[ -n "$dir" ] || { usage >&2; exit 2; }
case "$tier" in draft|final|4k) ;; *) die "--tier must be draft, final or 4k, not '$tier'" ;; esac
[[ "$workers" =~ ^[1-9][0-9]*$ ]] || die "--workers takes a whole number ≥ 1, not '$workers'"
[[ "$seg_frames" =~ ^[1-9][0-9]*$ ]] || die "--segment-frames takes a whole number ≥ 1, not '$seg_frames'"
[ "$seg_frames" -ge 30 ] || wa "segments under 30 frames are clamped to 30 by the engine (MIN_SEGMENT_FRAMES)"
[ -n "$bitrate" ] && [ -n "$crf" ] && die "--bitrate and --crf are mutually exclusive (the engine rejects both too)"
[ "$bench" = 1 ] && [ "$probe" = 1 ] && die "--bench and --gpu-probe are separate runs"

[ -d "$dir" ] || die "no such directory: $dir"
dir=$(cd "$dir" && pwd) || exit 2
[ -f "$dir/index.html" ] || die "$dir has no index.html — not a HyperFrames project (bin/vh hf-init <dir>)"

# the binary: override, else the project's own pin, else npx with the repo's pinned version
HF_VER=${HYPERFRAMES_VERSION:-0.8.82}
if [ -n "${HYPERFRAMES_BIN:-}" ]; then
  command -v "${HYPERFRAMES_BIN%% *}" >/dev/null 2>&1 || die "HYPERFRAMES_BIN not executable: $HYPERFRAMES_BIN"
  HF=("${HYPERFRAMES_BIN%% *}")                    # first word only: the override is one binary, not a command line
  [ "${#HYPERFRAMES_BIN}" -gt "${#HF[0]}" ] && wa "HYPERFRAMES_BIN has arguments after the binary — ignored (set the full path only)"
  HF[0]=$(cd "$(dirname "${HF[0]}")" && pwd)/$(basename "${HF[0]}")   # absolute: the render cd's into the project
elif [ -x "$dir/node_modules/.bin/hyperframes" ]; then HF=("$dir/node_modules/.bin/hyperframes")
elif command -v npx >/dev/null 2>&1; then HF=(npx --yes "hyperframes@$HF_VER")
else die "hyperframes not found: install it in the project (bin/vh hf-init) or set HYPERFRAMES_BIN"; fi

# ── --gpu-probe: what the GPU path will do here, before committing to a render
if [ "$probe" = 1 ]; then
  echo "== hyperframes doctor =="
  (cd "$dir" && env HYPERFRAMES_SKIP_SKILLS=1 DO_NOT_TRACK=1 "${HF[@]}" doctor) || true
  echo; echo "== NVIDIA GPU =="
  if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi || true; else
    wa "no nvidia-smi: no NVIDIA driver here — --browser-gpu will fall back to SwiftShader, --gpu to libx264 (both automatic, both correct)"; fi
  echo; echo "== ffmpeg hardware encoders =="
  ff=$(command -v ffmpeg || true); [ -z "$ff" ] && [ -x "$dir/node_modules/.bin/ffmpeg" ] && ff="$dir/node_modules/.bin/ffmpeg"
  if [ -n "$ff" ]; then
    hw=$("$ff" -hide_banner -encoders 2>/dev/null | grep -E "h264_(nvenc|vaapi|qsv|amf)" || true)
    [ -n "$hw" ] && { ok "compiled in:"; echo "$hw"; } || wa "no h264_nvenc/vaapi/qsv/amf in this ffmpeg — --gpu falls back to libx264"
  else
    wa "ffmpeg not found on PATH (hyperframes manages its own copy if you have none)"
  fi
  echo; echo "next: a 2-second draft render shows the live verdict in its log —"
  echo "  HYPERFRAMES_DEBUG_GPU_PROBE=1 $(basename "$0") '$dir' --tier draft --output out/probe.mp4"
  echo "  GPU picked   → banner 'GPU: encoder GPU + browser GPU (forced)', encode via h264_nvenc"
  echo "  no GPU       → 'browserGpuMode probe → software' + '[gpuEncoder] nvenc probe failed' (both safe fallbacks)"
  exit 0
fi

# ── --bench: the honest way to pick --workers on a new box
if [ "$bench" = 1 ]; then
  (cd "$dir" && exec env HYPERFRAMES_SKIP_SKILLS=1 DO_NOT_TRACK=1 "${HF[@]}" benchmark --runs "$runs")
  exit $?
fi

# ── the tier → flags
flags=(--quality delivery)          # final/4k default; draft overrides below
envs=()                             # extra env for the render command
case "$tier" in
  draft)
    flags=(--quality draft --browser-gpu --gpu)
    [ -n "$bitrate" ] && flags+=(--video-bitrate "$bitrate")
    output=${output:-out/draft.mp4}
    ;;
  final)
    flags=(--quality delivery --no-browser-gpu --experimental-fast-capture=false)
    envs+=(HF_CAPTURE_PARALLEL_STREAM=true)     # multi-worker screenshots stream into the encoder, no frame disk blowup
    output=${output:-out/final.mp4}
    ;;
  4k)
    flags=(--quality delivery --no-browser-gpu --experimental-fast-capture=false --resolution 4k)
    envs+=(HF_CAPTURE_PARALLEL_STREAM=true NODE_OPTIONS=--max-old-space-size=8192)
    output=${output:-out/final-4k.mp4}
    ;;
esac
[ -n "$fps" ] && flags+=(--fps "$fps")
flags+=(--workers "$workers")
[ -n "$crf" ] && flags+=(--crf "$crf")
[ "$resume" = 1 ] && flags+=(--resume)
[ "$keep" = 1 ] && flags+=(--keep-segments)
[ "$segments" = 1 ] && envs+=(HF_SEGMENTED_CAPTURE=true HF_SEGMENT_FRAMES="$seg_frames" HF_SEGMENT_BROWSER_RECYCLE=3)

# never clobber: out/<name>.mp4 → out/<name>-2.mp4, -3, … (--output is appended after this)
mkdir -p "$dir/$(dirname "$output")"
if [ -e "$dir/$output" ]; then
  n=2; while [ -e "$dir/${output%.mp4}-$n.mp4" ]; do n=$((n + 1)); done
  output="${output%.mp4}-$n.mp4"
  wa "output exists → rendering to $output instead"
fi
flags+=(--output "$output")

echo "$tier tier → ${output}  (workers=$workers, segments=$([ "$segments" = 1 ] && echo "$seg_frames frames/seg, recycle 3" || echo off))"
if [ "$dry" = 1 ]; then
  printf '  env %s\n' "${envs[*]:-(none)}"
  printf '  (cd %s && hyperframes render . %s)\n' "$dir" "${flags[*]}"
  exit 0
fi
cd "$dir" && exec env HYPERFRAMES_SKIP_SKILLS=1 DO_NOT_TRACK=1 ${envs[@]+"${envs[@]}"} "${HF[@]}" render . "${flags[@]}"
