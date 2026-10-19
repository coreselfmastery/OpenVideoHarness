#!/usr/bin/env bash
# Pin GPUs and apply a performance profile, then run Blender (engines/blender-perf.md).
# The physical pin is CUDA_VISIBLE_DEVICES (the only mechanism that reaches the CUDA
# driver before Blender starts); the in-process selection is tools/blender_perf.py.
# usage: tools/blender_run.sh [--gpu N] [--device SPEC] [--profile P] [--simplify]
#                              [--blender PATH] -- <blender args…>
#   --gpu N       export CUDA_VISIBLE_DEVICES=N for this Blender only: the process
#                 sees just that card (with --gpu 1, the physical GPU 1 appears at
#                 in-process index 0). Default on Kaggle 2x T4 while ManimGX renders:
#                 --gpu 1 — ManimGX cannot be pinned off GPU 0 (Vulkan ignores
#                 CUDA_VISIBLE_DEVICES, engines/manimgx.md), so Blender takes GPU 1.
#                 Omit it to render with BOTH cards (Cycles multi-GPU).
#   --device SPEC in-process selection passed to blender_perf: auto | cpu | cuda |
#                 optix | hip | oneapi | metal | cuda:N | gpu:N. auto = CUDA first
#                 on Linux (the T4 doctrine; RT-core owners pass optix), Metal on
#                 macOS. Mutually sensible with --gpu: prefer --gpu for the physical
#                 pin and --device cpu to force CPU from a pinned process.
#   --profile P   draft | final | final-cpu — inserted as a --python chain BEFORE
#                 your args: the script runs before the -a/-f render action, so one
#                 process applies the profile and renders with it (verified live).
#                 For scripts that rebuild the scene from scratch (read_factory_
#                 settings, like the swatch renderer), import the library instead.
#   --simplify    force Simplify on: the VRAM emergency lever (16 GB on a T4).
#   --blender     path to the blender binary (default: `command -v blender`).
# Everything after `--` is passed to Blender verbatim, e.g.:
#   tools/blender_run.sh --gpu 1 --profile final -- \
#     blender -b build/scene.blend -o //../out/plate/f_#### -F PNG -s 0 -e 59 -a \
#     -- --cycles-device CUDA --cycles-print-stats
# No watchdog here on purpose: the render paths that need one (render.sh, bin/vh)
# already run under their own timeout (engines/blender-perf.md, "时间预算").
# Exit status: Blender's own; 2 = usage or no blender found.
set -uo pipefail
unset CDPATH
cd "$(dirname "$0")/.." || exit 2   # repo root: the --python path is relative to it

GPU=""; DEVICE=""; PROFILE=""; SIMPLIFY=""; BLENDER="${BLENDER:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --gpu)     shift; GPU="${1:-}" ;;
    --device)  shift; DEVICE="${1:-}" ;;
    --profile) shift; PROFILE="${1:-}" ;;
    --simplify) SIMPLIFY=1 ;;
    --blender) shift; BLENDER="${1:-}" ;;
    --) shift; break ;;
    *) printf '[!!] unknown flag: %s (everything after -- goes to Blender)\n' "$1" >&2
       sed -n '2,25p' "$0" >&2; exit 2 ;;
  esac
  shift
done
[ $# -gt 0 ] || { sed -n '2,25p' "$0" >&2; exit 2; }
BLENDER="${BLENDER:-}"
# Resolution order: an explicit --blender path, then `blender` on PATH, then the common
# local installs. Bug fixed here (found live by blender_split's stub test): when `blender`
# WAS on PATH the old guard's || block never ran, so BLENDER stayed EMPTY — the exec below
# then died with "env: '': No such file or directory" on any machine where PATH resolution
# was the success path (exactly Kaggle's case). The empty-variable case is now closed.
if ! command -v "${BLENDER:-blender}" >/dev/null 2>&1; then
  for c in ./blender ../blender /usr/local/bin/blender "$HOME/blender-5.2.2-linux-x64/blender"; do
    command -v "$c" >/dev/null 2>&1 && BLENDER="$c" && break
  done
fi
[ -n "$BLENDER" ] || BLENDER="blender"
command -v "$BLENDER" >/dev/null 2>&1 || { printf '[!!] no blender on PATH; pass --blender PATH\n' >&2; exit 2; }
if [ "${1:-}" = "blender" ]; then shift; fi   # allow `-- blender -b …` and `-- -b …`

# --- the physical pin --------------------------------------------------------------
EXTRA_ENV=()
if [ -n "$GPU" ]; then
  case "$GPU" in
    ''|*[!0-9]*) printf '[!!] --gpu takes a number (0-based physical index), not %s\n' "$GPU" >&2; exit 2 ;;
  esac
  EXTRA_ENV+=("CUDA_VISIBLE_DEVICES=$GPU")
  printf '[pin] CUDA_VISIBLE_DEVICES=%s (physical GPU %s; in-process it is index 0)\n' "$GPU" "$GPU"
  if [ -n "$DEVICE" ] && [ "$DEVICE" != "cpu" ]; then
    printf '[pin] note: with the env pin above, in-process indices shift; prefer --gpu alone, or --device cpu\n' >&2
  fi
else
  printf '[pin] no --gpu: every visible CUDA device renders together (Cycles multi-GPU)\n'
fi

# --- the profile chain (before user args; runs before the render action) ------------
# Assembly subtlety, verified live: `--python tools/blender_perf.py` goes FIRST among
# Blender args; its subcommand tokens go at the very END of argv, in the region after
# the user's `--`, which Python scripts and Cycles options already share (blender.md,
# "渲染预设与 render 命令"). A `--` is injected only if the user's args lack one.
# Never use --profile with a script that parses its argv strictly (the swatch renderer
# is the example: it imports the library instead).
PERF_PRE=(); PERF_TAIL=()
if [ -n "$PROFILE" ]; then
  case "$PROFILE" in
    draft|final|final-cpu|fast|cpu|deterministic) ;;
    *) printf '[!!] --profile is draft | final | final-cpu, not %s\n' "$PROFILE" >&2; exit 2 ;;
  esac
  PERF_PRE=(--python tools/blender_perf.py --python-exit-code 1)
  PERF_TAIL=(apply --profile "$PROFILE")
  [ -n "$DEVICE" ] && PERF_TAIL+=("--device" "$DEVICE")
  [ -n "$SIMPLIFY" ] && PERF_TAIL+=(--simplify)
  printf '[perf] profile %s%s%s\n' "$PROFILE" "${DEVICE:+ · device $DEVICE}" "${SIMPLIFY:+ · simplify}"
fi

has_dd=0
for a in "$@"; do [ "$a" = "--" ] && { has_dd=1; break; }; done

printf '[run] %s %s\n' "${EXTRA_ENV[*]}" "$*"
if [ "$has_dd" = 1 ]; then
  exec env "${EXTRA_ENV[@]+${EXTRA_ENV[@]}}" "$BLENDER" ${PERF_PRE[@]+"${PERF_PRE[@]}"} "$@" ${PERF_TAIL[@]+"${PERF_TAIL[@]}"}
else
  exec env "${EXTRA_ENV[@]+${EXTRA_ENV[@]}}" "$BLENDER" ${PERF_PRE[@]+"${PERF_PRE[@]}"} "$@" -- ${PERF_TAIL[@]+"${PERF_TAIL[@]}"}
fi
