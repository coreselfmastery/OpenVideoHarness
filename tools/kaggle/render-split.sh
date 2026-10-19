#!/usr/bin/env bash
# render-split.sh — a HyperFrames film drawn as two halves at the same time, for the machine whose one render leaves a
# GPU idle. The film is cut once, at a scene cut near the middle (a data-start the composition itself declares); each
# half is drawn by its own browser through the repo's page contract (tools/film/render.mjs --frames, the same exact-frame
# path bin/vh patch uses) and encoded by its own ffmpeg; the two are joined without re-encoding. With NVENC on a 2-GPU
# box the halves encode on different cards (half A on GPU 0, half B on GPU 1): the browsers stay on GPU 0 — Chrome's EGL
# device has no per-card switch (CUDA_VISIBLE_DEVICES does not reach it) — but each card still runs its own NVENC block,
# so neither waits on the other and the CPU is left to the two browsers.
#
#   tools/kaggle/render-split.sh <project> [options]     <project>: the folder with index.html
#
#   --at SECONDS        split at this time instead of the middle: snapped to the nearest scene cut within half a second
#   --tier draft|final  the encode: draft = NVENC p4 cq 28 (x264: crf 28, faster) — a review pass; final = NVENC p7
#                       cq 19 (x264: crf 16, medium) — the master. No --tier: the repo's own master settings
#                       (NVENC p4 cq 16 / x264 crf 16 medium)
#   --res 480p|720p…    the output's short side in lines (480, 540, 720, 1080): the page keeps its own layout,
#                       Chrome draws it at a fractional deviceScaleFactor — a 720p draft of a 1080p film is the
#                       same picture at 44% of the pixels, both halves at once. The master stays full size
#   --encoder …         x264 or nvenc (default: nvenc when tools/kaggle/setup.sh probed it, else x264)
#   --gpu-a N --gpu-b N which card encodes each half (default A=0, B=the last card); a warning when they are the same
#   --workers N         browsers per half (default 1: two halves = two browsers; the box has to carry them)
#   --fps N             as render.sh: 30 is the default (the composition's own data-fps is kept at 30 or less;
#                       a declared 60 is rendered at 30 unless --fps says otherwise)
#   --crf N --preset P  the encode settings outright (overrides --tier; P is p1–p7 for nvenc)
#   --out FILE          default <project>/renders/<project>.mp4
#   --skip-determinism  don't run `bin/vh determinism` first (it refuses a page whose frames depend on what came before
#                       them — exactly the page a split would draw differently; keep it on)
#   --dry-run           print the plan (the cut, the two commands) and render nothing
#   --keep              keep the halves and their logs beside the film
#   -h | --help         this header
#
#   Everything else is passed to tools/film/render.mjs unchanged. Sound still goes on afterwards with bin/vh mux.
#
# The honest caveat, said here rather than in a footnote: the halves are drawn by the page contract, not by
# `npx hyperframes render` (which cannot render a span — verified against 0.8.82 and 0.8.169). The repo measures that
# difference on every patch it makes: bin/vh patch re-draws frames this way and gates the join at PSNR ≥ 40, and a film
# patched that way is a delivered film. The determinism check below refuses the pages where even that would not hold.
# The master for delivery is still render.sh's; use the split when the wall clock matters more than the engine's own
# renderer (long films, quota pressure) — or to render both tiers of a review round at once.
set -euo pipefail
unset CDPATH
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() { sed -n '2,39p' "$0"; }
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") usage >&2; exit 1 ;;
esac
PROJ=$1; shift
case "$PROJ" in
  -*) printf '\033[31m✗\033[0m the project folder comes first: tools/kaggle/render-split.sh <project> [options]\n' >&2; exit 1 ;;
esac

AT=""; TIER=""; ENCODER=""; GPU_A=""; GPU_B=""; WORKERS=1; FPS_OPT=""; CRF=""; PRESET=""; OUT=""; RES=""
SKIP_DET=0; DRY=0; KEEP=0; pass=()
while [ $# -gt 0 ]; do
  case "$1" in
    --at) AT=${2:?--at needs seconds}; shift ;;
    --tier) TIER=${2:?--tier needs draft or final}; shift ;;
    --tier=*) TIER=${1#*=} ;;
    --encoder) ENCODER=${2:?--encoder needs x264 or nvenc}; shift ;;
    --encoder=*) ENCODER=${1#*=} ;;
    --gpu-a) GPU_A=${2:?--gpu-a needs a card number}; shift ;;
    --gpu-b) GPU_B=${2:?--gpu-b needs a card number}; shift ;;
    --workers|-w) WORKERS=${2:?--workers needs a number}; shift ;;
    --workers=*) WORKERS=${1#*=} ;;
    --fps|-f) FPS_OPT=${2:?--fps needs a number}; shift ;;
    --fps=*) FPS_OPT=${1#*=} ;;
    --res) RES=${2:?--res needs the short side in lines, like 720p}; shift ;;
    --res=*) RES=${1#*=} ;;
    --crf) CRF=${2:?--crf needs a number}; shift ;;
    --crf=*) CRF=${1#*=} ;;
    --preset) PRESET=${2:?--preset needs a name}; shift ;;
    --preset=*) PRESET=${1#*=} ;;
    --out|-o) OUT=${2:?--out needs a file}; shift ;;
    --skip-determinism) SKIP_DET=1 ;;
    --dry-run) DRY=1 ;;
    --keep) KEEP=1 ;;
    -h|--help) usage; exit 0 ;;
    *) pass+=("$1") ;;
  esac
  shift
done
case "$TIER" in draft|final|"") ;; *) printf '\033[31m✗\033[0m --tier: draft or final, not "%s"\n' "$TIER" >&2; exit 1 ;; esac
case "$WORKERS" in ''|*[!0-9]*|0) printf '\033[31m✗\033[0m --workers: a whole number ≥ 1\n' >&2; exit 1 ;; esac
R=""
if [ -n "${RES:-}" ]; then
  R=${RES%p}   # 720p and 720 both mean 720 lines
  case "$R" in ''|*[!0-9]*|0) printf '\033[31m✗\033[0m --res: the short side in lines, like 480p, 720 or 1080p — not "%s"\n' "$RES" >&2; exit 1 ;; esac
fi
for v in ${GPU_A:+"$GPU_A"} ${GPU_B:+"$GPU_B"}; do
  case "$v" in ''|*[!0-9]*) printf '\033[31m✗\033[0m --gpu-a/--gpu-b: whole card numbers\n' >&2; exit 1 ;; esac
done

ENVF="$ROOT/.kaggle/env.sh"
if [ ! -f "$ENVF" ]; then
  printf '\033[31m✗\033[0m no %s: run tools/kaggle/setup.sh once first (it probes the GPUs and writes it)\n' "$ENVF" >&2
  exit 2
fi
# shellcheck disable=SC1090   # written by tools/kaggle/setup.sh; every value in it was probed there
. "$ENVF"

if [ ! -f "$PROJ/index.html" ]; then
  printf '\033[31m✗\033[0m no index.html in %s\n' "$PROJ" >&2; exit 1
fi
PROJ="$(cd "$PROJ" && pwd)"

# ── what the composition says about itself: length, frame rate, and where its scenes start ─────────────────────
# Scene cuts are the data-start times of its clips (what the runtime itself shows by); a cut there leaves every clip
# whole. The split frame k must land exactly on one (k / fps equal to it, within half a frame).
meta=$(python3 - "$PROJ/index.html" <<'PY'
import json, re, sys
try: s = open(sys.argv[1], encoding="utf-8").read()
except OSError: sys.exit(0)
root = ""
for tag in re.findall(r'<[^>]*\bdata-composition-id\b[^>]*>', s):
    root = tag; break
def attr(name, where=None):
    m = re.search(r'\b' + name + r'="([\d.]+)"', where if where is not None else s)
    return m.group(1) if m else ""
dur, fps = attr("data-duration", root), attr("data-fps", root)
w, h = attr("data-width", root) or "1920", attr("data-height", root) or "1080"
starts = sorted({float(x) for x in re.findall(r'\bdata-start="([\d.]+)"', s)})
print(json.dumps({"duration": dur, "fps": fps, "w": w, "h": h, "starts": starts}))
PY
) || { printf '\033[31m✗\033[0m could not read %s/index.html\n' "$PROJ" >&2; exit 1; }
DUR=$(printf '%s' "$meta" | python3 -c 'import json,sys; print(json.load(sys.stdin)["duration"])')
DFPS=$(printf '%s' "$meta" | python3 -c 'import json,sys; print(json.load(sys.stdin)["fps"])')
PW=$(printf '%s' "$meta" | python3 -c 'import json,sys; print(json.load(sys.stdin)["w"])')
PH=$(printf '%s' "$meta" | python3 -c 'import json,sys; print(json.load(sys.stdin)["h"])')
[ -n "$DUR" ] || { printf '\033[31m✗\033[0m the composition has no data-duration: a split needs the length\n' >&2; exit 1; }
awk -v d="$DUR" 'BEGIN{exit !(d < 30)}' && { printf '\033[31m✗\033[0m %s s is too short to split (two browser startups would eat the gain; render.sh renders it whole)\n' "$DUR" >&2; exit 1; }

if [ -n "$FPS_OPT" ]; then FPS=$FPS_OPT; fps_note="fps $FPS (yours)"
elif [ -z "$DFPS" ]; then FPS=30; fps_note="fps 30 (no data-fps; made explicit)"
elif awk -v d="$DFPS" 'BEGIN{exit !(d<=30)}'; then FPS=$DFPS; fps_note="fps $FPS (the composition's own)"
else FPS=30; fps_note="fps 30 (the default here; the composition declares $DFPS — pass --fps $DFPS to keep every frame of it)"
fi
FPS=$(printf '%s' "$FPS" | awk '{printf "%d", ($1==int($1))?$1:int($1+0.5)}')
[ "$FPS" -ge 1 ] || { printf '\033[31m✗\033[0m fps came out as %s\n' "$FPS" >&2; exit 1; }
N=$(python3 -c "import math; print(math.ceil($DUR*$FPS-1e-6))")
[ "$N" -ge 4 ] || { printf '\033[31m✗\033[0m the composition works out to $N frames: nothing to split\n' >&2; exit 1; }

# ── --res: the short side of the video in lines, both halves at the same fractional deviceScaleFactor ─
DPR=""; res_note=""
if [ -n "$R" ]; then
  DPR=$(awk -v l="$R" -v w="$PW" -v h="$PH" 'BEGIN{short=(w<h?w:h); printf "%.4g", l/short}')
  if awk -v d="$DPR" 'BEGIN{exit !(d<0.25)}'; then
    printf '\033[31m✗\033[0m --res %sp on a %sx%s page is dpr %s: under the 0.25 floor\n' "$R" "$PW" "$PH" "$DPR" >&2
    exit 1
  fi
  if awk -v d="$DPR" 'BEGIN{exit !(d>1.0001)}'; then
    printf '\033[31m✗\033[0m --res %sp on a %sx%s page is dpr %s: more pixels than the page has (--res names a draft tier, fewer pixels; --output-resolution on the engine is the supersampler)\n' "$R" "$PW" "$PH" "$DPR" >&2
    exit 1
  fi
  res_note="res      : $(awk -v w="$PW" -v h="$PH" -v d="$DPR" 'BEGIN{printf "%dx%d", int(w*d+0.5), int(h*d+0.5)}') (the page's own layout, drawn at dpr $DPR — a ${R}p draft)"
fi

# ── the cut: a scene cut nearest the middle (or to --at), never nearer an end than a quarter of the film ───────
K=$(python3 - "$DUR" "$FPS" "$N" "$AT" "$meta" <<'PY'
import json, sys
dur, fps, n, at, meta = float(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], json.loads(sys.argv[5])
starts = [s for s in meta["starts"] if 0 < s < dur]
lo, hi = 0.25 * dur, 0.75 * dur
aim = float(at) if at else dur / 2
cands = [s for s in starts if lo <= s <= hi] or [s for s in starts if 0 < s < dur] or []
if cands:
    best = min(cands, key=lambda s: abs(s - aim))
    k = round(best * fps)
    print(json.dumps({"k": k, "at": best, "kind": "scene_cut"}))
else:
    print(json.dumps({"k": max(1, min(n - 1, round(aim * fps))), "at": aim, "kind": "midpoint"}))
PY
) || exit 1
KCUT=$(printf '%s' "$K" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["k"])')
KAT=$(printf '%s' "$K" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["at"])')
KKIND=$(printf '%s' "$K" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["kind"])')
case "$KKIND" in
  scene_cut) cut_note="a scene cut the composition declares (data-start=$KAT)" ;;
  midpoint) cut_note="the middle — the composition declares no data-start to cut on; frames are still exact at the join" ;;
esac
awk -v k="$KCUT" -v n="$N" 'BEGIN{exit !(k>=1 && k<n)}' || { printf '\033[31m✗\033[0m the cut landed on frame %s of %s: no room for two halves\n' "$KCUT" "$N" >&2; exit 1; }

# ── the encode: which encoder, which cards ─────────────────────────────────────────────────────────────────────
if [ -z "$ENCODER" ]; then
  if [ "${OVH_KAGGLE_NVENC:-0}" = 1 ]; then ENCODER=nvenc; else ENCODER=x264; fi
fi
case "$ENCODER" in nvenc|x264) ;; *) printf '\033[31m✗\033[0m --encoder: x264 or nvenc, not "%s"\n' "$ENCODER" >&2; exit 1 ;; esac
GPUS=${OVH_KAGGLE_GPUS:-0}
[ -n "$GPU_A" ] || GPU_A=0
[ -n "$GPU_B" ] || GPU_B=$((GPUS > 1 ? GPUS - 1 : 0))
if [ "$ENCODER" = nvenc ] && [ "$GPU_A" = "$GPU_B" ]; then
  printf '\033[33m!\033[0m both halves would encode on GPU %s — the split still draws two browsers at once, but the two encoders share one card (--gpu-a/--gpu-b to change)\n' "$GPU_A"
fi
if [ -n "$CRF" ]; then :
elif [ "$ENCODER" = nvenc ]; then
  case "$TIER" in draft) CRF=28 ;; final) CRF=19 ;; *) CRF=16 ;; esac
else
  case "$TIER" in draft) CRF=28 ;; final) CRF=16 ;; *) CRF=16 ;; esac
fi
if [ -n "$PRESET" ]; then :
elif [ "$ENCODER" = nvenc ]; then
  case "$TIER" in draft) PRESET=p4 ;; final) PRESET=p7 ;; *) PRESET=p4 ;; esac
else
  case "$TIER" in draft) PRESET=faster ;; final) PRESET=medium ;; *) PRESET=medium ;; esac
fi
GOP=$((2 * FPS))

# ── the browser render.mjs draws with (bin/vh's own order: CHROME_PATH, the caches, a system Chrome) ───────────
CHROME=""
for c in "${CHROME_PATH:-}" "${OVH_KAGGLE_CHROME:-}"; do
  if [ -n "$c" ] && [ -x "$c" ]; then CHROME=$c; break; fi
done
if [ -z "$CHROME" ]; then
  for d in "$HOME/.cache/puppeteer/chrome-headless-shell" "$HOME/.cache/hyperframes/chrome/chrome-headless-shell"; do
    [ -d "$d" ] || continue
    for v in $(ls -1 "$d" 2>/dev/null | sort -r); do
      p=$(find "$d/$v" -maxdepth 3 -type f \( -name chrome-headless-shell -o -name chrome \) 2>/dev/null | head -1)
      if [ -n "$p" ] && [ -x "$p" ]; then CHROME=$p; break 2; fi
    done
  done
fi
if [ -z "$CHROME" ]; then
  for p in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" /usr/bin/google-chrome /usr/bin/google-chrome-stable /usr/bin/chromium /usr/bin/chromium-browser; do
    [ -x "$p" ] && { CHROME=$p; break; }
  done
fi
[ -n "$CHROME" ] || { printf '\033[31m✗\033[0m no headless Chrome found: run tools/kaggle/setup.sh (or set CHROME_PATH)\n' >&2; exit 2; }
command -v ffmpeg >/dev/null 2>&1 || { printf '\033[31m✗\033[0m ffmpeg is not installed\n' >&2; exit 2; }
command -v ffprobe >/dev/null 2>&1 || { printf '\033[31m✗\033[0m ffprobe is not installed\n' >&2; exit 2; }

OUT=${OUT:-$PROJ/renders/$(basename "$PROJ").mp4}
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
WORK="$(dirname "$OUT")/.$(basename "$OUT").split"
LOG="$WORK/log-a.txt"; LOGB="$WORK/log-b.txt"

# ── disk: the two halves and the joined copy sit on it together (render.mjs checks its own peak too) ───────────
free_kb=$(df -Pk "$(dirname "$OUT")" 2>/dev/null | awk 'NR==2{print $4}' || echo 0)
need_kb=$(python3 - "$N" <<'PY' 2>/dev/null || echo 0
# a 1080p-class page until the halves report their own size; the same flat-film floor render.mjs refuses below
import sys
n = int(sys.argv[1]); px = 1920 * 1080
print(int(2 * n * px * 0.01 / 8 / 1024))
PY
)
if [ "$free_kb" -gt 0 ] && [ "$need_kb" -gt 0 ] && [ "$free_kb" -lt "$need_kb" ]; then
  printf '\033[31m✗\033[0m only %s GB free where %s goes; two halves plus the join need about %s GB even for a flat film\n' \
    "$(awk -v k="$free_kb" 'BEGIN{printf "%.1f", k/1048576}')" "$OUT" "$(awk -v k="$need_kb" 'BEGIN{printf "%.1f", k/1048576}')" >&2
  exit 2
fi

# ── the stop machinery, in before the first phase it has to cover (E6) ──────────────────────────────────────────
# A stop during the determinism gate must take the gate down too: the gate is a bin/vh child with its
# own browser, and a trap that only knows the halves would orphan both. The gate therefore runs in the
# background below — a foreground child would hold the trap until it finished on its own.
PID_DET=""; PID_A=""; PID_B=""
cleanup() { rm -rf "$WORK"; }
kill_phase() { # kill_phase TERM|KILL — whichever of the gate and the halves is running (empty pids skipped)
  for p in "$PID_DET" "$PID_A" "$PID_B"; do
    if [ -n "$p" ]; then kill -"$1" "$p" 2>/dev/null || true; fi
  done
}
phase_alive() {
  for p in "$PID_DET" "$PID_A" "$PID_B"; do
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then return 0; fi
  done
  return 1
}
stop_all() { # E6: a stopped split takes the gate or the halves down and leaves nothing behind
  trap - INT TERM
  kill_phase TERM                                    # the halves are the node processes (exec) and the gate is
  for _ in 1 2 3 4 5; do                             # bin/vh: both stop cleanly on TERM (render.mjs deletes its
    phase_alive || break                             # own chunks); give them 5 s before the hammer
    sleep 1
  done
  kill_phase KILL
  for p in "$PID_DET" "$PID_A" "$PID_B"; do
    if [ -n "$p" ]; then wait "$p" 2>/dev/null || true; fi
  done
  printf '\033[31m✗\033[0m stopped — the split is deleted, gate and halves, no film was touched\n' >&2
  cleanup
  exit 130
}
trap stop_all INT TERM

# ── the determinism gate: a page whose frames depend on the frames before them would draw differently halved ──
# (after the dry run: a plan printout draws nothing, so it need not pay for the check)
if [ "$SKIP_DET" = 0 ] && [ "$DRY" = 0 ] && [ -x "$ROOT/bin/vh" ]; then
  printf '\033[36m→\033[0m determinism: the page must draw the same frame whatever came before it (bin/vh determinism)\n'
  (cd "$PROJ" && exec "$ROOT/bin/vh" determinism . --samples 2) >/dev/null 2>&1 & PID_DET=$!
  DET_RC=0
  while kill -0 "$PID_DET" 2>/dev/null; do sleep 1; done
  wait "$PID_DET" || DET_RC=$?
  if [ "$DET_RC" -ne 0 ]; then
    printf '\033[31m✗\033[0m the page does not draw the same frame twice the same way: a split (or any re-render of a span)\n     would show it. Render the film whole (tools/kaggle/render.sh), or fix the page, or --skip-determinism to insist\n' >&2
    exit 1
  fi
fi

enc_note=$([ "$ENCODER" = nvenc ] && printf 'h264_nvenc %s cq %s, half A on GPU %s and half B on GPU %s' "$PRESET" "$CRF" "$GPU_A" "$GPU_B" \
  || printf 'x264 %s crf %s on the CPU' "$PRESET" "$CRF")
printf '\033[36m→\033[0m %s\n' "$fps_note"
[ -n "$res_note" ] && printf '\033[36m→\033[0m %s\n' "$res_note"
printf '\033[36m→\033[0m project  : %s (%s s, %s frames at %s fps)\n' "$PROJ" "$DUR" "$N" "$FPS"
printf '\033[36m→\033[0m cut      : frame %s (t=%s s) — %s\n' "$KCUT" "$(awk -v k="$KCUT" -v f="$FPS" 'BEGIN{printf "%.3f", k/f}')" "$cut_note"
printf '\033[36m→\033[0m encode   : %s\n' "$enc_note"
printf '\033[36m→\033[0m halves   : A frames 0–%s, B frames %s–%s, one browser each (+%s more per --workers)\n' "$((KCUT-1))" "$KCUT" "$((N-1))" "$((WORKERS-1))"
printf '\033[36m→\033[0m browser  : %s (both halves on GPU 0: the EGL device has no per-card switch)\n' "$CHROME"

segcmd() { # segcmd <a> <b> <gpu> <logfile>: the render.mjs line for one half. exec, so the half is the
  # node process itself: a stop signal to it is the one render.mjs handles (it deletes its own chunks)
  printf '%s\n' "exec node $ROOT/tools/film/render.mjs '$PROJ' --force --browser '$CHROME' --frames $1:$2 --fps $FPS ${DPR:+--dpr $DPR} --workers $WORKERS --gop $GOP --out '$WORK/seg$3.mp4' --encoder $ENCODER --crf $CRF --preset $PRESET --gpu $4"
}
if [ "$DRY" = 1 ]; then
  printf '\033[36m→\033[0m dry run — the two halves would be:\n'
  printf '  A: '; segcmd 0 "$KCUT" a "$GPU_A"
  printf '  B: '; segcmd "$KCUT" "$N" b "$GPU_B"
  printf '  join: ffmpeg -f concat -safe 0 -i list.txt -c copy -movflags +faststart %s\n' "$OUT"
  exit 0
fi

# ── both halves at once; the stop trap above covers this phase with the same hands ────────────────────────────
rm -rf "$WORK"; mkdir -p "$WORK"

T0=$(date +%s)
printf '\033[36m→\033[0m rendering both halves… (logs: %s/log-{a,b}.txt; another shell: tail -f them)\n' "$WORK"
segcmd 0 "$KCUT" a "$GPU_A" >"$WORK/cmd-a.txt"
segcmd "$KCUT" "$N" b "$GPU_B" >"$WORK/cmd-b.txt"
bash "$WORK/cmd-a.txt" >"$LOG" 2>&1 & PID_A=$!
bash "$WORK/cmd-b.txt" >"$LOGB" 2>&1 & PID_B=$!
A_DONE=0; B_DONE=0; A_RC=0; B_RC=0
while [ "$A_DONE" = 0 ] || [ "$B_DONE" = 0 ]; do
  if [ "$A_DONE" = 0 ] && ! kill -0 "$PID_A" 2>/dev/null; then A_DONE=1; wait "$PID_A" || A_RC=$?; fi
  if [ "$B_DONE" = 0 ] && ! kill -0 "$PID_B" 2>/dev/null; then B_DONE=1; wait "$PID_B" || B_RC=$?; fi
  if [ "$A_DONE" = 1 ] && [ "$A_RC" -ne 0 ] && [ "$B_DONE" = 0 ]; then kill "$PID_B" 2>/dev/null || true; B_DONE=1; B_RC=130; fi
  if [ "$B_DONE" = 1 ] && [ "$B_RC" -ne 0 ] && [ "$A_DONE" = 0 ]; then kill "$PID_A" 2>/dev/null || true; A_DONE=1; A_RC=130; fi
  [ "$A_DONE" = 0 ] || [ "$B_DONE" = 0 ] || break
  sleep 1
done
trap - INT TERM
if [ "$A_RC" -ne 0 ] || [ "$B_RC" -ne 0 ]; then
  printf '\033[31m✗\033[0m half A exit %s, half B exit %s — no film written\n' "$A_RC" "$B_RC" >&2
  [ "$A_RC" -ne 0 ] && tail -5 "$LOG" >&2
  [ "$B_RC" -ne 0 ] && tail -5 "$LOGB" >&2
  [ "$KEEP" = 1 ] || cleanup
  exit 1
fi
printf '  half A: %s\n' "$(tail -2 "$LOG" | head -1)"
printf '  half B: %s\n' "$(tail -2 "$LOGB" | head -1)"

# ── the join: only ever a stream copy, and only between halves that came out the same shape ────────────────────
# D5 in three checks: both halves' codec parameters agree (a re-encode or a different card setting would show),
# half B starts on a keyframe (the join point is a real cut in the bitstream), and the joined file carries every frame
# of both (no truncation, no duplication at the seam).
same=$(python3 - "$WORK/sega.mp4" "$WORK/segb.mp4" <<'PY'
import json, subprocess, sys
def probe(f, first_packet=False):
    st = json.loads(subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
        "stream=codec_name,profile,level,width,height,pix_fmt,nb_frames", "-of", "json", f],
        capture_output=True, text=True).stdout)["streams"][0]
    if first_packet:
        st["first_flag"] = (subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "packet=flags", "-of", "csv=p=0", f], capture_output=True, text=True).stdout.split() or ["?"])[0]
    return st
a, b = probe(sys.argv[1]), probe(sys.argv[2], True)
keys = ["codec_name", "profile", "level", "width", "height", "pix_fmt"]
bad = [k for k in keys if a.get(k) != b.get(k)]
print(json.dumps({"same": not bad, "bad": bad, "a": a, "b": b}))
PY
) || { printf '\033[31m✗\033[0m ffprobe could not read the halves\n' >&2; [ "$KEEP" = 1 ] || cleanup; exit 1; }
printf '%s' "$same" | python3 -c '
import json, sys
d = json.load(sys.stdin); a, b = d["a"], d["b"]
if not d["same"]: print("halves differ in " + ", ".join(d["bad"])); sys.exit(1)
if not b["first_flag"].startswith("K"): print("half B does not start on a keyframe"); sys.exit(1)
print("ok")' | grep -q '^ok$' || {
  printf '\033[31m✗\033[0m the halves are not the same encode (or half B has no keyframe at its start): %s\n' \
    "$(printf '%s' "$same" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(", ".join(d["bad"]) or "no keyframe at the seam")')" >&2
  [ "$KEEP" = 1 ] || cleanup; exit 1; }
NA=$(printf '%s' "$same" | python3 -c 'import json,sys; print(json.load(sys.stdin)["a"]["nb_frames"])')
NB=$(printf '%s' "$same" | python3 -c 'import json,sys; print(json.load(sys.stdin)["b"]["nb_frames"])')
[ "$NA" = "$KCUT" ] && [ $((NA + NB)) = "$N" ] || {
  printf '\033[31m✗\033[0m the halves drew %s + %s frames, expected %s + %s — the page is not the length it says\n' "$NA" "$NB" "$KCUT" "$((N-KCUT))" >&2
  [ "$KEEP" = 1 ] || cleanup; exit 1; }

printf 'file %s\nfile %s\n' "$WORK/sega.mp4" "$WORK/segb.mp4" > "$WORK/list.txt"
ffmpeg -v error -nostdin -y -f concat -safe 0 -i "$WORK/list.txt" -c copy -movflags +faststart "$OUT" || {
  printf '\033[31m✗\033[0m the join failed\n' >&2; [ "$KEEP" = 1 ] || cleanup; exit 1; }

# D5, the last check: a stream copy leaves the halves' bytes alone, so the film is about the two files put together
NJ=$(ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames -of csv=p=0 "$OUT" 2>/dev/null | head -1)
SZJ=$(wc -c < "$OUT" | awk '{print $1}')
SZAB=$(( $(wc -c < "$WORK/sega.mp4" | awk '{print $1}') + $(wc -c < "$WORK/segb.mp4" | awk '{print $1}') ))
[ "$NJ" = "$N" ] || { printf '\033[31m✗\033[0m the joined film has %s frames, not %s\n' "$NJ" "$N" >&2; [ "$KEEP" = 1 ] || cleanup; exit 1; }
if awk -v j="$SZJ" -v s="$SZAB" 'BEGIN{d=(j-s)/s; exit !(d>=-0.02 && d<=0.05)}'; then
  copy_note="stream copy confirmed (the film is the two halves' own bytes, +$(awk -v j="$SZJ" -v s="$SZAB" 'BEGIN{printf "%.1f", (j-s)/1048576}') MB of container)"
else
  copy_note="joined size is $(awk -v j="$SZJ" 'BEGIN{printf "%.1f", j/1048576}') MB against $(awk -v j="$SZAB" 'BEGIN{printf "%.1f", j/1048576}') MB of halves — suspicious for a stream copy"
fi

# ── the sidecar: patch and re-render work on the joined film exactly as on a whole one ─────────────────────────
python3 - "$WORK/sega.mp4.render.json" "$WORK/segb.mp4.render.json" "$OUT" "$KCUT" "$N" <<'PY'
import json, os, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
out, k, n = sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
side = dict(a)
# a half's sidecar says where its page is relative to the .split folder it sat in; the joined film's
# sidecar sits beside the film, so the page is said from there (bin/vh patch resolves it that way).
# Both ends in one namespace — the plain spelled paths, no realpath: on macOS $TMPDIR is spelled
# /var/folders/… while its realpath is /private/var/folders/… (one component longer), and a relative
# path computed across the two does not survive a physical ".." walk through the symlink.
page = side.get("page", "")
if page and not os.path.isabs(page):
    where = os.path.dirname(os.path.abspath(out))
    spelled = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), page))
    project = os.path.dirname(spelled)                       # the page's folder, as spelled
    if (where + os.sep).startswith(project + os.sep):        # the film inside the project: say it from the film
        side["page"] = os.path.relpath(spelled, where)
    else:                                                    # outside: the spelled absolute path, like render.mjs
        side["page"] = spelled
side.update({
  "note": "how this video was made (tools/kaggle/render-split.sh: two halves joined without re-encoding); a patch or re-render should match these",
  "frames": n, "span": a["span"][:1] + b["span"][1:], "first_frame": 0,
  "chunks": a["chunks"] + b["chunks"],
  "split": {"tool": "render-split", "seam_frame": k, "halves": [a["frames"], b["frames"]], "gpu": [a["encoder"].get("gpu"), b["encoder"].get("gpu")]},
  "seconds": round(a.get("seconds", 0) + b.get("seconds", 0), 1),
})
json.dump(side, open(out + ".render.json", "w"), indent=1)
open(out + ".render.json", "a").write("\n")
PY

T1=$(date +%s)
printf '\033[32m✓\033[0m %s: %s frames in %s s — %s\n' "$OUT" "$NJ" "$((T1-T0))" "$copy_note"
printf '    how it was made: %s.render.json (bin/vh patch and bin/vh mux take it from here)\n' "$OUT"
[ "$KEEP" = 1 ] || cleanup
exit 0
