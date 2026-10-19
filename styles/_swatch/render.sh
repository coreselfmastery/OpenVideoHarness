#!/usr/bin/env bash
# render.sh — render one style swatch (5 s, 30 fps, 1920×1080 canvas) with the pinned HyperFrames, then
# write styles/<slug>/media/swatch.mp4 (1280×720 H.264, ≤ 1.5 MB) and media/poster.jpg (t = 3.0 s, ≤ 200 KB).
#
#   styles/_swatch/render.sh <slug> [--draft] [--fast] [--workers N] [--hud] [--png [--frames L]] [--stage-only] [--stamp] [--timeout S]
#
#   <slug>        a folder styles/<slug>/ with swatch.js + tokens.json, or a built-in: demo | catalog | catalog-fx | fontprobe,
#                 or a path containing "/" to a scene folder anywhere (slug = its basename; media/ goes inside it).
#                 A folder with swatch.py instead of swatch.js is a Blender scene (README.md, "Blender 场景")
#   --draft       HyperFrames --quality draft (faster, softer); outputs go to out/<slug>/media, never over styles/<slug>/media.
#                 Blender scenes: Cycles on the GPU with fewer samples instead of the CPU
#   --fast        with --draft only (HyperFrames scenes): iterate on the GPU — --browser-gpu (Chrome gl-egl hardware
#                 raster + drawElement fast capture where the GPU allows) and --gpu (NVENC where the ffmpeg build has
#                 it, else libx264). NOT byte-deterministic (GPU text raster varies per process), so it never replaces
#                 the --no-browser-gpu default above and determinism.sh keeps rendering the CPU path (engines/remotion-speed.md)
#   --workers N   parallel Chrome workers (default 2; 1 when another `hyperframes render` is already running);
#                 the count only changes the speed, the frames are byte-identical. Blender scenes: Blender processes
#                 (default 1: Cycles already uses every core), each rendering one contiguous chunk of the frames
#   --hud         burn a t / frame readout into the corner (for checking only; never ship it)
#   --png         ONLY render a lossless PNG sequence to styles/_swatch/out/<slug>/png-w<N>/ (see determinism.sh)
#   --frames L    Blender scenes, with --png: only these frames, in this order ("149,90,12"), into png-sample-w<N>/
#   --stamp       Blender scenes: print a checksum of everything the frames depend on, and exit (determinism.sh)
#   --stage-only  build the stage (see README) and print how to snapshot / preview it; no render
#   --timeout S   kill the render after S seconds (default 300 draft / 600 final; Blender 1800 / 7200); a render whose
#                 log stays silent for SWATCH_STALL seconds (default 120; Blender 300, as a cold Metal kernel compile
#                 prints nothing for ~110 s) is treated as hung and killed too
#
# Built-in scenes (demo, catalog, catalog-fx, fontprobe) write to styles/_swatch/out/<slug>/media/ instead of styles/<slug>/media/.
# HyperFrames runs with --no-browser-gpu (SwiftShader WebGL, 2D canvas and compositing on the CPU), its deterministic
# mode: on the GPU, Chrome rasterised text edges differently from process to process (a few dozen pixels, one level),
# x264 turned that into a different mp4 and poster on every run, and 1- and 2-worker renders took different capture
# paths. Frames are now the same bytes at any worker count and on every run (README.md, "确定性").
# Needs: node ≥ 22, ffmpeg/ffprobe, uv (contact sheet + music). Run `npm ci` in styles/_swatch once.
# Blender scenes need Blender (BLENDER=/path/to/blender, else `blender` on the PATH, else the macOS app) and fc-match,
# not HyperFrames; their frames go through the same checks, mix and encode as hf.mp4 does.
set -euo pipefail
SW="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SW/../.." && pwd)"
HF="$SW/node_modules/.bin/hyperframes"
FPS=30; DUR=5; FRAMES=150; POSTER_FRAME=90
MP4_LIMIT=1500000; JPG_LIMIT=200000          # bytes (decimal MB/KB, so both readings of "1.5 MB" hold)
ok=$'\033[32m✓\033[0m'; no=$'\033[31m✗\033[0m'; wa=$'\033[33m!\033[0m'
die() { echo "$no $*" >&2; exit 1; }
fsize() { wc -c < "$1" | tr -d ' '; }         # bytes; `stat` flags differ between BSD and GNU

slug=""; draft=0; fast=0; workers=""; hud=false; png=0; stage_only=0; timeout=""; frames=""; stamp_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    --draft) draft=1 ;; --fast) fast=1 ;; --hud) hud=true ;; --png) png=1 ;; --stage-only) stage_only=1 ;; --stamp) stamp_only=1 ;;
    --workers) workers=${2:?}; shift ;; --workers=*) workers=${1#*=} ;;
    --timeout) timeout=${2:?}; shift ;; --timeout=*) timeout=${1#*=} ;;
    --frames) frames=${2:?}; shift ;; --frames=*) frames=${1#*=} ;;
    -h|--help) awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
    -*) die "unknown option $1" ;;
    *) [ -z "$slug" ] && slug=$1 || die "one slug at a time" ;;
  esac; shift
done
[ -n "$slug" ] || die "usage: styles/_swatch/render.sh <slug> [--draft] [--fast] [--workers N] [--hud] [--png [--frames L]] [--stage-only] [--stamp] [--timeout S]"
[ -z "$workers" ] || [[ "$workers" =~ ^[1-9][0-9]*$ ]] || die "--workers takes a whole number ≥ 1, not '$workers'"
[ $fast = 0 ] || { [ $draft = 1 ] || die "--fast goes with --draft (the shipped swatch path stays on the CPU: determinism)"; }
SRCDIR=""
case "$slug" in */*) [ -d "$slug" ] || die "no such directory: $slug"; SRCDIR="$(cd "$slug" && pwd)"; slug=$(basename "$SRCDIR") ;; esac
[[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "slug must be lowercase letters, digits and dashes: $slug"
command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null || die "ffmpeg/ffprobe not found"

builtin=0; [ -z "$SRCDIR" ] && case "$slug" in demo|catalog|catalog-fx|fontprobe) builtin=1 ;; esac
if [ $builtin = 1 ]; then SRC="$SW/$slug"; MEDIA="$SW/out/$slug/media"
elif [ -n "$SRCDIR" ]; then SRC="$SRCDIR"; MEDIA="$SRC/media"        # a scene folder anywhere (drafts, tests)
else SRC="$ROOT/styles/$slug"; MEDIA="$SRC/media"; fi
# drafts never overwrite a shipped swatch: they go to out/<slug>/media (final renders, without --draft, write styles/<slug>/media)
[ $draft = 1 ] && [ $builtin = 0 ] && [ -z "$SRCDIR" ] && MEDIA="$SW/out/$slug/media"
# the engine: swatch.js renders in HyperFrames (Chrome); a folder with only swatch.py is a Blender scene (Cycles)
engine=hf; [ $builtin = 0 ] && [ ! -f "$SRC/swatch.js" ] && [ -f "$SRC/swatch.py" ] && engine=blender
[ $fast = 0 ] || [ $engine = hf ] || die "--fast is for HyperFrames scenes (swatch.js): a Blender draft already renders on the GPU"
[ -f "$SRC/tokens.json" ] || die "missing $SRC/tokens.json"
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SRC/tokens.json" 2>/dev/null || die "$SRC/tokens.json is not valid JSON"
if [ $engine = hf ]; then
  [ -f "$SRC/swatch.js" ] || die "missing $SRC/swatch.js (or swatch.py for a Blender scene)"
  [ -x "$HF" ] || die "HyperFrames not installed: (cd styles/_swatch && npm ci)"
  # (plain `node --check file.js` misses ESM syntax errors in Node 22; stdin + --input-type=module does not)
  if ! err=$(node --input-type=module --check < "$SRC/swatch.js" 2>&1); then
    echo "$err" | grep -E "^\[stdin\]:|SyntaxError" | head -3 >&2; die "syntax error in $SRC/swatch.js"; fi
  [ -z "$frames" ] && [ $stamp_only = 0 ] || die "--frames and --stamp are for Blender scenes (swatch.py)"
  [ "$(uname)" = Darwin ] || echo "$wa swatch fonts are macOS system fonts (fonts.css local() faces): on $(uname) they fall back, so this output will differ from the published media (see the font table in styles/_swatch/README.md, or render the fontprobe built-in)" >&2
else
  BL=${BLENDER:-}
  [ -n "$BL" ] || BL=$(command -v blender 2>/dev/null || true)
  [ -n "$BL" ] || { [ -x /Applications/Blender.app/Contents/MacOS/Blender ] && BL=/Applications/Blender.app/Contents/MacOS/Blender; } || true
  [ -n "$BL" ] && [ -x "$BL" ] || die "Blender not found: install it (macOS: brew install --cask blender) or set BLENDER=/path/to/blender"
  python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])" "$SRC/swatch.py" || die "syntax error in $SRC/swatch.py"
  # agent-written bpy runs with the user's rights: read it before running it (blender_prep.py scan; engines/blender.md, "安全")
  python3 "$SW/blender_prep.py" scan "$SRC/swatch.py" || die "$SRC/swatch.py uses something a Blender scene may not (above)"
  [ $stage_only = 0 ] || die "--stage-only is for HyperFrames scenes: a Blender scene has no stage (render a few frames with --png --frames)"
  [ -z "$frames" ] || [ $png = 1 ] || die "--frames goes with --png"
fi
export PYTHONDONTWRITEBYTECODE=1                    # importing swatch.py must not leave a __pycache__ in styles/<slug>/

OUT="$SW/out/$slug"; STAGE="$SW/out/stage/$slug"; LOCK="$SW/out/stage/$slug.lock"
bl_stamp() { # a checksum of everything a Blender scene's frames depend on: the Blender build, the scene folder's files
  # (names and bytes; not its media, docs, audio or foley list) and the renderer. Not the machine's fonts: a font update
  # needs a fresh final render before determinism.sh means anything
  { "$BL" --version 2>/dev/null | sed -n '1,4p'
    find "$SRC" -type f ! -path "$SRC/media/*" ! -path '*/__pycache__/*' ! -name '*.md' ! -name '*.wav' ! -name score.json \
      ! -name events.json ! -name .DS_Store | LC_ALL=C sort | while IFS= read -r f; do printf '%s\n' "${f#"$SRC"/}"; cat "$f"; done
    cat "$SW/blender_render.py" "$SW/blender_prep.py"; } | cksum | cut -d' ' -f1
}
if [ $stamp_only = 1 ]; then bl_stamp; exit 0; fi
mkdir -p "$SW/out/stage" "$OUT" "$MEDIA"
mkdir "$LOCK" 2>/dev/null || die "another render of '$slug' holds $LOCK (remove it if that render is dead)"
HFPID=""; SBX=""            # SBX: the sandbox profile bl_profile writes (macOS)
cleanup() {
  [ -n "$HFPID" ] && kill -0 "$HFPID" 2>/dev/null && { kill -TERM -- "-$HFPID" 2>/dev/null || kill -TERM "$HFPID" 2>/dev/null || true; }
  rmdir "$LOCK" 2>/dev/null || true
  case "$SBX" in */vh-sandbox.*/blender.sb) rm -rf "${SBX%/*}" ;; esac     # bl_profile's temp folder, also after a timeout
}
trap cleanup EXIT; trap 'exit 130' INT TERM

# ── stage: a throwaway HyperFrames project root with exactly one composition. The shell files are copied
#    from styles/_swatch/, the style folder goes to scenes/<slug>/, and the `style` variable default is set
#    to <slug> so `hyperframes snapshot|preview` on the stage (which take no --variables) show this style.
if [ $engine = hf ]; then
rm -rf "$STAGE"; mkdir -p "$STAGE"
for f in index.html boot.js lib.js fonts.css hyperframes.json meta.json package.json; do cp "$SW/$f" "$STAGE/"; done
for d in demo catalog catalog-fx fontprobe; do [ -d "$SW/$d" ] && cp -R "$SW/$d" "$STAGE/"; done
[ -d "$SW/vendor" ] && cp -R "$SW/vendor" "$STAGE/"
if [ $builtin = 0 ]; then
  mkdir -p "$STAGE/scenes"
  rsync -a --exclude media --exclude '*.md' --exclude '.DS_Store' "$SRC/" "$STAGE/scenes/$slug/"
  if find "$STAGE/scenes/$slug" -name '*.html' | grep -q .; then die "styles/$slug/ must not contain .html files (one composition per root)"; fi
fi
python3 - "$STAGE/index.html" "$slug" <<'PY' || die "could not set the style default in the staged index.html"
import html, json, re, sys
p, slug = sys.argv[1], sys.argv[2]; s = open(p).read()
m = re.search(r"data-composition-variables='([^']*)'", s)
v = json.loads(html.unescape(m.group(1)))
for d in v:
    if d["id"] == "style": d["default"] = slug
open(p, "w").write(s[:m.start(1)] + json.dumps(v, ensure_ascii=False, separators=(",", ":")) + s[m.end(1):])
PY
if [ $stage_only = 1 ]; then
  echo "$ok stage ready: ${STAGE#$ROOT/}"
  echo "   snapshot: HYPERFRAMES_SKIP_SKILLS=1 $HF snapshot ${STAGE#$ROOT/} --no-browser-gpu --at 0.4,1.7,3.0,4.6 --describe false --output ${OUT#$ROOT/}/snapshots"
  echo "   preview : HYPERFRAMES_SKIP_SKILLS=1 $HF preview ${STAGE#$ROOT/}"
  echo "   (fonts: judge them on render.sh output, not snapshots)"
  exit 0
fi
fi

# ── render with a watchdog
if [ -z "$workers" ]; then
  if [ $engine = blender ]; then workers=1
  elif pgrep -f "hyperframes render" >/dev/null 2>&1; then workers=1; echo "$wa another hyperframes render is running → --workers 1"; else workers=2; fi
fi
if [ -z "$timeout" ]; then
  if [ $engine = blender ]; then { [ $draft = 1 ] && timeout=1800; } || timeout=7200
  else { [ $draft = 1 ] && timeout=300; } || timeout=600; fi
fi
STALL=${SWATCH_STALL:-$([ $engine = blender ] && echo 300 || echo 120)}
quality=$([ $draft = 1 ] && echo draft || echo delivery)
HFMP4="$OUT/hf.mp4"; LOG="$OUT/render.log"
rm -f "$HFMP4" "$LOG"
vars="{\"style\":\"$slug\",\"hud\":$hud}"

hf_render() { # --no-browser-gpu: every frame is a pure function of t only when nothing in the pipeline depends on GPU state (header).
  # --draft --fast swaps in the GPU path (--browser-gpu --gpu): iteration speed over byte-determinism, drafts only.
  local gpu_flags=(--no-browser-gpu)
  [ $fast = 1 ] && gpu_flags=(--browser-gpu --gpu)
  cd "$STAGE" && exec env HYPERFRAMES_SKIP_SKILLS=1 DO_NOT_TRACK=1 "$HF" render . --fps $FPS --workers "$workers" \
    "${gpu_flags[@]}" --variables "$vars" "$@"
}
bl_render() { # $1 = frame folder, $2 = frame list ("0-149", "149,90,12"): the list cut into $workers contiguous chunks,
  # one fresh Blender per chunk, all at once (render.sh's --workers); each writes <folder>/frame_NNNN.png
  local dir=$1 chunk pids="" p k rc=0 q; q=$([ $draft = 1 ] && echo draft || echo final)
  set +m                    # this runs in run_watched's subshell: keep the Blenders in its process group, so a timeout kills them
  mkdir -p "$dir"
  while IFS= read -r chunk; do
    bl_run -b --factory-startup --python-exit-code 1 --python "$SW/blender_render.py" -- "$SRC" "$dir" \
      --frames "$chunk" --quality "$q" --fonts "$OUT/fonts.json" ${hudarg:+"$hudarg"} </dev/null &
    pids="$pids $!"
  done < <(python3 - "$2" "$workers" <<'PY'
import sys
fr = []
for p in sys.argv[1].split(","):
    if "-" in p[1:]: a, b = p.split("-", 1); fr += range(int(a), int(b) + 1)
    elif p.strip(): fr.append(int(p))
n = max(1, min(int(sys.argv[2]), len(fr))); k, m = divmod(len(fr), n); i = 0
for j in range(n):
    c = fr[i:i + k + (j < m)]; i += len(c); print(",".join(map(str, c)))
PY
)
  for p in $pids; do   # one chunk failing stops the others (each pid is its Blender: bl_run execs it)
    if ! wait "$p"; then rc=1; for k in $pids; do kill "$k" 2>/dev/null || true; done; fi
  done
  return $rc
}
hudarg=""; [ "$hud" = true ] && hudarg=--hud
sbq() { printf '"%s"' "$(printf '%s' "$1" | sed 's/[\\"]/\\&/g')"; }   # a path as a sandbox-profile string
bl_profile() { # the sandbox every Blender of this render runs in (macOS; written once, before run_watched starts the chunks,
  # and removed by cleanup). The AST scan
  # in blender_prep.py is a lint that catches mistakes; this is the boundary. No network, no handing URLs or Apple events to
  # other apps; writes only inside out/<slug>/ and Blender's own folder in the per-user cache, where Metal keeps its
  # compiled shaders (denied, every frame recompiles them: 13 s instead of 2 s). Final renders (CPU) also read nothing in
  # the home folder but the repo, the scene, the Blender install and ~/Library/Fonts, so ~/.ssh, ~/.zsh_secrets and the
  # like stay out of reach of the frames that get committed. Drafts (Metal) can't take that rule: with the home folder
  # unreadable, Metal crashes loading Cycles' cached kernels (in -[_MTLDevice recordBinaryArchiveUsage:]; allowing
  # ~/Library does not help). Their output stays in the git-ignored out/ and they have no network
  # The profile lives outside out/<slug>/ (which the scene may write), and bl_run refuses to start without it.
  local o c h r a; o=$(cd "$OUT" && pwd -P); mkdir -p "$o/.blender/home" "$o/.blender/tmp"; SBX=""
  [ "$(uname)" = Darwin ] && command -v sandbox-exec >/dev/null 2>&1 || return 0
  c=$(cd "$(getconf DARWIN_USER_CACHE_DIR)" && pwd -P); h=$(cd ~ && pwd -P)
  r=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$BL")   # Blender's own files: the .app bundle, or
  case "$r" in */Contents/MacOS/*) a=${r%%/Contents/MacOS/*} ;; *) a=$(dirname "$r") ;; esac   # the folder it sits in
  case "$h/" in "${a%/}"/*) die "Blender's install folder ($a) holds the home folder: a sandbox that reads it reads everything; install Blender elsewhere" ;; esac
  SBX="$(mktemp -d "${TMPDIR:-/tmp}/vh-sandbox.XXXXXX")/blender.sb"
  { echo '(version 1)'; echo '(allow default)'; echo '(deny network*)'; echo '(deny lsopen)'; echo '(deny appleevent-send)'
    echo '(deny file-write*)'
    echo "(allow file-write* (subpath $(sbq "$o")) (subpath $(sbq "$c/org.blenderfoundation.blender")) (literal \"/dev/null\") (literal \"/dev/dtracehelper\"))"
    if [ $draft = 0 ]; then
      echo "(deny file-read* (subpath $(sbq "$h")))"
      echo "(allow file-read* (subpath $(sbq "$(cd "$ROOT" && pwd -P)")) (subpath $(sbq "$(cd "$SRC" && pwd -P)")) (subpath $(sbq "$o"))" \
           "(subpath $(sbq "$a")) (literal $(sbq "$(cd "$(dirname "$BL")" && pwd -P)/$(basename "$BL")")) (subpath $(sbq "$h/Library/Fonts")))"
    fi
  } > "$SBX"
}
bl_run() { # Blender with no inherited environment (env -i: no API keys reach it through the environment), its HOME and
  # TMPDIR inside out/<slug>/.blender/, and on macOS inside the sandbox bl_profile wrote. It always runs in its own
  # background subshell, so it execs: the pid bl_render waits on and kills is Blender itself, not a shell around it
  local o; o=$(cd "$OUT" && pwd -P)
  set -- env -i PATH="$PATH" HOME="$o/.blender/home" TMPDIR="$o/.blender/tmp/" LANG=en_US.UTF-8 PYTHONDONTWRITEBYTECODE=1 "$BL" "$@"
  if [ "$(uname)" = Darwin ] && command -v sandbox-exec >/dev/null 2>&1; then
    [ -n "$SBX" ] && [ -f "$SBX" ] || { echo "[swatch] no sandbox profile: not starting Blender" >&2; exit 1; }
    exec sandbox-exec -f "$SBX" "$@"
  fi
  exec "$@"
}
run_hf() { run_watched hf_render "$@"; }
run_watched() { # $@ = a command, run in its own process group so a timeout kills Chrome or Blender too
  local rc=0 t0 now size last=-1 lastchg
  set -m
  ("$@") >>"$LOG" 2>&1 &
  HFPID=$!
  set +m
  t0=$(date +%s); lastchg=$t0
  while kill -0 "$HFPID" 2>/dev/null; do
    sleep 1; now=$(date +%s); size=$(fsize "$LOG" 2>/dev/null || echo 0)
    [ "$size" != "$last" ] && { last=$size; lastchg=$now; }
    if [ $((now - t0)) -gt "$timeout" ]; then
      kill -TERM -- "-$HFPID" 2>/dev/null || true; sleep 3; kill -KILL -- "-$HFPID" 2>/dev/null || true
      echo "$no render timed out after ${timeout}s (log: ${LOG#$ROOT/})"; tail -5 "$LOG"; HFPID=""; return 124; fi
    if [ $((now - lastchg)) -gt "$STALL" ]; then
      kill -TERM -- "-$HFPID" 2>/dev/null || true; sleep 3; kill -KILL -- "-$HFPID" 2>/dev/null || true
      echo "$no render log silent for ${STALL}s: treated as hung (CDN fetch? infinite loop in renderAt or apply?)"; tail -5 "$LOG"; HFPID=""; return 125; fi
  done
  wait "$HFPID" || rc=$?
  HFPID=""
  return $rc
}

T0=$(date +%s)
if [ $engine = blender ]; then  # the scene's fonts → files Blender can load (out/<slug>/fonts.json; a .ttc face is written out)
  uv run -q --no-project --with fonttools python "$SW/blender_prep.py" fonts "$SRC/swatch.py" "$OUT" || die "could not resolve the scene's FONTS"
fi
if [ $png = 1 ]; then       # lossless frames only (determinism checks); no mp4 / poster
  PNGDIR="$OUT/png-w$workers"; [ -n "$frames" ] && PNGDIR="$OUT/png-sample-w$workers"; rm -rf "$PNGDIR"
  echo "→ PNG sequence '$slug' (${workers} worker(s)$([ -n "$frames" ] && echo ", frames $frames")) → ${PNGDIR#$ROOT/}"
  rc=0
  if [ $engine = blender ]; then bl_profile; run_watched bl_render "$PNGDIR" "${frames:-0-$((FRAMES - 1))}" || rc=$?
  else run_hf --format png-sequence --output "$PNGDIR" || rc=$?; fi
  [ $rc = 0 ] || { echo "$no png-sequence render failed ($rc)"; tail -15 "$LOG"; exit 1; }
  np=$(find "$PNGDIR" -name '*.png' | wc -l | tr -d ' ')
  want=$FRAMES; [ -n "$frames" ] && want=$(python3 -c 'import sys
fr = set()
for p in sys.argv[1].split(","):
    if "-" in p[1:]: a, b = p.split("-", 1); fr.update(range(int(a), int(b) + 1))
    elif p.strip(): fr.add(int(p))
print(len(fr))' "$frames")
  [ "$np" = "$want" ] || die "$np PNG frames, expected $want"
  echo "$ok $np frames in $(( $(date +%s) - T0 ))s"; exit 0
fi
if [ $engine = blender ]; then
  # Cycles renders PNG frames (out/<slug>/frames, or frames-draft); they become the same 1080p BT.709 H.264 the
  # HyperFrames path writes, near-lossless (CRF 8, one thread: the same bytes every run), so everything below is shared
  FR="$OUT/frames$([ $draft = 1 ] && echo -draft || true)"; rm -rf "$FR"
  stamp=""; [ $draft = 1 ] || [ "$hud" = true ] || stamp=$(bl_stamp)   # taken before rendering: an edit made meanwhile must not match
  echo "→ rendering '$slug' in Blender ($([ $draft = 1 ] && echo "draft, GPU" || echo "final, CPU"), ${workers} process(es), timeout ${timeout}s)"
  rc=0; bl_profile; run_watched bl_render "$FR" "0-$((FRAMES - 1))" || rc=$?
  T1=$(date +%s)
  [ $rc = 0 ] || { echo "$no Blender exited with $rc — last lines of ${LOG#$ROOT/}:"; grep -h "\[swatch\]" "$LOG" | grep -v "\[swatch\] frame " | tail -15; tail -5 "$LOG"; exit 1; }
  np=$(find "$FR" -name 'frame_*.png' | wc -l | tr -d ' ')
  [ "$np" = "$FRAMES" ] || die "$np frames in ${FR#$ROOT/}, expected $FRAMES"
  ffmpeg -v error -y -framerate $FPS -i "$FR/frame_%04d.png" -frames:v $FRAMES \
    -vf "scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int,format=yuv420p,setparams=colorspace=bt709:color_primaries=bt709:color_trc=bt709:range=tv" \
    -c:v libx264 -preset slow -crf 8 -threads 1 \
    "$HFMP4" || die "could not encode the frames to ${HFMP4#$ROOT/}"
  [ -z "$stamp" ] || echo "$stamp" > "$FR/inputs.txt"   # determinism.sh compares fresh frames against these
else
  echo "→ rendering '$slug' (${quality}, ${workers} worker(s), timeout ${timeout}s)"
  rc=0; run_hf --quality "$quality" --output "$HFMP4" || rc=$?
  T1=$(date +%s)
  [ $rc = 0 ] || { echo "$no hyperframes exited with $rc — last lines of ${LOG#$ROOT/}:"; tail -15 "$LOG"; exit 1; }
  [ -s "$HFMP4" ] || die "hyperframes exited 0 but wrote no $HFMP4"
fi

# ── checks: frame count, drawn canvas, error card, frozen output
n=$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$HFMP4")
wh=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$HFMP4")
[ "$n" = "$FRAMES" ] || die "frame count $n ≠ $FRAMES in ${HFMP4#$ROOT/}"
[ "$wh" = "1920x1080" ] || die "render is $wh, expected 1920x1080"
fail=0; drew=0; sums=""
for f in 12 51 90 138; do     # t = 0.4 / 1.7 / 3.0 / 4.6 — one frame per content-spec segment
  crop=""; [ "$hud" = true ] && crop="crop=iw:ih-100:0:0,"      # keep the HUD strip out of the "did it draw" stats
  st=$(ffmpeg -v error -i "$HFMP4" -vf "select=eq(n\\,$f),${crop}signalstats,metadata=mode=print:file=-" -frames:v 1 -f null - 2>/dev/null | tr '\n' ' ')
  get() { echo "$st" | sed -n "s/.*lavfi.signalstats.$1=\([0-9.]*\).*/\1/p"; }
  yavg=$(get YAVG); ymin=$(get YMIN); ymax=$(get YMAX); uavg=$(get UAVG); vavg=$(get VAVG)
  [ -n "$yavg" ] || { echo "$no could not read frame $f"; fail=1; continue; }
  range=$(python3 -c "print(int(float('$ymax')-float('$ymin')))")
  printf "   frame %3d (t=%.1f)  YAVG %5.1f  Y range %3d  U %5.1f  V %5.1f\n" "$f" "$(python3 -c "print($f/$FPS)")" "$yavg" "$range" "$uavg" "$vavg"
  [ "$range" -ge 24 ] && drew=1
  if python3 -c "import sys; sys.exit(0 if float('$uavg')>175 and float('$vavg')>185 else 1)"; then
    # HyperFrames doesn't always forward console.error into the log, so save the card itself: its text is the stack
    ffmpeg -v error -y -i "$HFMP4" -vf "select=eq(n\\,$f)" -frames:v 1 "$OUT/error-frame-$f.png" 2>/dev/null
    grep -h "\[swatch\]" "$LOG" 2>/dev/null | head -5
    echo "$no frame $f is the magenta SWATCH ERROR card: the scene threw — read the stack on ${OUT#$ROOT/}/error-frame-$f.png"; fail=1; fi
  sums="$sums $(ffmpeg -v error -i "$HFMP4" -vf "select=eq(n\\,$f)" -frames:v 1 -f md5 - 2>/dev/null)"
done
[ $drew = 1 ] || { echo "$no every sampled frame is flat: the canvas never drew"; fail=1; }
[ "$(echo $sums | tr ' ' '\n' | sort -u | wc -l | tr -d ' ')" -gt 1 ] || { echo "$no sampled frames are identical: output is frozen (renderAt not called per seek?)"; fail=1; }
grep -h "\[swatch\]" "$LOG" 2>/dev/null | grep -v "\[swatch\] frame " | sort -u | head -10 | sed 's/^/   log: /' || true
[ $fail = 0 ] || exit 1
echo "$ok ${n} frames at ${wh}, canvas drew, no error card ($((T1 - T0))s render)"

# ── optional score → music, optional events.json → foley on the frame of each action, mixed with the swatch profile
AUDIO=""; MIXARGS=(); TP=-1.65
if [ $builtin = 0 ] && [ -f "$SRC/score.json" ]; then   # (SRC = styles/<slug> or the given folder)
  echo "→ music from ${SRC#$ROOT/}/score.json"
  "$ROOT/bin/vh" music "$SRC/score.json" "$OUT/music_raw.wav" >/dev/null
  MIXARGS+=(music="$OUT/music_raw.wav")
fi
if [ $builtin = 0 ] && [ -f "$SRC/events.json" ]; then  # [{"t", "sfx", "gain_db", "pan", "dist", "role"}]; own WAVs relative to the style folder
  echo "→ foley from ${SRC#$ROOT/}/events.json"
  "$ROOT/bin/vh" sfx lib "$OUT/sfxlib" >/dev/null       # rebuilt each time, so library fixes always reach the swatch
  MIXARGS+=(events="$SRC/events.json" lib="$OUT/sfxlib" root="$SRC")
fi
# profile=swatch (playbook/04-audio.md, 混音): the music is the anchor; each foley event moves half way to its class's
# level re the music's 3 s loudness (hero / detail / ambience / signal), one short room behind them, one static gain to
# −14 LUFS, true peak ≤ $1 dBTP. Cut to 5 s with the 0.45 s fade inside the mix, so an SFX past the end fades with the score.
mix_audio() {
  "$ROOT/bin/vh" mix "$OUT/music.wav" profile=swatch dur=$DUR fade=0.45 tp="$1" "${MIXARGS[@]}" stems="$OUT/stems" > "$OUT/mix.txt" \
    || { cat "$OUT/mix.txt"; die "bin/vh mix failed"; }
}
if [ ${#MIXARGS[@]} -gt 0 ]; then mix_audio "$TP"; AUDIO="$OUT/music.wav"; fi

# ── swatch.mp4: 1280×720, H.264 High, yuv420p, faststart; CRF climbs until it fits the size cap.
#    -threads 1: x264's VBV rate control (-maxrate/-bufsize) is not repeatable with frame threads — four encodes of the
#    same input spanned 1 493 473–1 503 291 B around the 1 500 000 B cap, flipping halftone-comic between CRF 24 and 26.
#    One thread gives the same bytes every time and costs about 3 s per pass at 720p.
MP4="$MEDIA/swatch.mp4"; TMP="$OUT/swatch.tmp.mp4"
encode() { # $1 = CRF → $TMP
  if [ -n "$AUDIO" ]; then
    ffmpeg -v error -y -i "$HFMP4" -i "$AUDIO" -map 0:v:0 -map 1:a:0 -vf "scale=1280:720:flags=lanczos,format=yuv420p" \
      -c:v libx264 -preset slow -profile:v high -crf "$1" -maxrate 2600k -bufsize 5200k -g 60 -r $FPS -threads 1 \
      -c:a aac -b:a 128k -ac 2 -t $DUR -movflags +faststart "$TMP"
  else
    ffmpeg -v error -y -i "$HFMP4" -vf "scale=1280:720:flags=lanczos,format=yuv420p" \
      -c:v libx264 -preset slow -profile:v high -crf "$1" -maxrate 2600k -bufsize 5200k -g 60 -r $FPS -threads 1 \
      -an -t $DUR -movflags +faststart "$TMP"
  fi
}
for crf in 18 20 22 24 26 28 30 32 34; do
  encode $crf; sz=$(fsize "$TMP"); [ "$sz" -le $MP4_LIMIT ] && break
done
[ "$sz" -le $MP4_LIMIT ] || die "swatch.mp4 is still $sz bytes at CRF $crf: reduce full-frame grain/noise"
# The AAC encode moves the true peak by an amount that depends on the content (−1.9…+1.4 dB at 128k on the swatches' first encodes, up to +2.4 on a heavily limited remix), so
# the encode is measured (the same 4× BS.1770 meter as the mix) and, while it peaks over −1.5 dBTP, the mix is made again
# with its ceiling set below the mix's own true peak (from stems/meta.json; a mix that never reached the limiter would
# not change if only the old ceiling were lowered) by the overshoot + 0.1 dB, and encoded again at the same CRF. At most
# 3 times, then it fails; the same bytes every run.
if [ -n "$AUDIO" ]; then
  k=0
  while :; do
    etp=$(uv run -q --no-project --with numpy --with scipy python -c "import sys; sys.path.insert(0, sys.argv[1]); import mix; print(f'{mix.true_peak(mix.load(sys.argv[2])):.2f}')" \
          "$ROOT/tools/audio" "$TMP")
    python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) <= -1.5 else 1)" "$etp" && break
    [ $k -lt 3 ] || die "the AAC encode still peaks at $etp dBTP after 3 new mixes (mix tp=$TP): over −1.5 dBTP"
    k=$((k + 1)); TP=$(python3 -c "import json, sys; m = json.load(open(sys.argv[3])).get('tp', float(sys.argv[1]))
print(f'{min(float(sys.argv[1]), m) - (float(sys.argv[2]) + 1.5) - 0.1:.2f}')" "$TP" "$etp" "$OUT/stems/meta.json")
    echo "   the AAC encode peaks at $etp dBTP: the mix again with tp=$TP"
    mix_audio "$TP"; encode $crf; sz=$(fsize "$TMP")
  done
  [ "$sz" -le $MP4_LIMIT ] || die "swatch.mp4 grew to $sz bytes with the new mix at CRF $crf"
fi

# ── audio QA over the whole clip (the fade-out tail excluded): the scan (silence, dropouts, pumping; the score's own
#    dips, known from the music stem, are not pumping), the cue check of every foley event and transient music hit, and
#    the mix report (qa mix). The WAV mix is the gate, and it runs before the mp4 goes into media/. The mp4 gets the scan
#    and the cue check (its cue problems only warn, unless the whole encode is off: a mux offset); the report reads the
#    stems, so it is not run twice. Without the beat map the scan would only look at ~1.0–2.2 s of a 5 s clip.
qa_gate() { # $1 = file, $2 = report
  if "$ROOT/bin/vh" qa "$1" "${QA_ARGS[@]}" --out "$2" > "$2.log" 2>&1; then
    echo "$ok audio qa passed on ${1#$ROOT/}: $(tail -1 "$2.log" | sed 's/ · full report.*//')"
  else   # what failed: OFF cues, hard misses, the scan's counts and runs (or the tail, when qa itself broke)
    { grep -E ' OFF |^FAIL|^✗|^\[[1-3]\]|^ +[0-9.]+- +[0-9.]+ s' "$2.log" || tail -5 "$2.log"; } | head -14 | sed 's/^/   /' || true
    die "audio qa failed on ${1#$ROOT/} — see ${2#$ROOT/}.log (typical fixes: a pad/sub bed under sparse bars, no hats-only sections; a cue lost under the score or not heard: raise its gain_db in FOLEY, or give it a role)"
  fi
}
if [ -n "$AUDIO" ]; then
  BEATS=-; [ -f "$OUT/music_raw.beats.json" ] && [ -f "$SRC/score.json" ] && BEATS="$OUT/music_raw.beats.json"
  QA_ARGS=("$BEATS"); [ -f "$SRC/events.json" ] && QA_ARGS+=("$SRC/events.json")   # foley onsets are cues, not clicks
  QA_ARGS+=(--fps "$FPS" --from 0.3 --to "$(python3 -c "print($DUR-0.5)")" --stems "$OUT/stems")
  qa_gate "$AUDIO" "$OUT/qa.txt"
fi
[ -z "$AUDIO" ] || qa_gate "$TMP" "$OUT/qa_mp4.txt"
mv "$TMP" "$MP4"
echo "$ok ${MP4#$ROOT/}  $(python3 -c "print(f'{$sz/1e6:.2f} MB')")  (crf $crf$([ -f "$SRC/score.json" ] && [ $builtin = 0 ] && echo ', +music')$([ -f "$SRC/events.json" ] && [ $builtin = 0 ] && echo ', +foley')$([ -n "$AUDIO" ] && echo ", mix tp $TP dBTP, encode $etp dBTP")$([ -z "$AUDIO" ] && echo ', silent'))"

# ── poster.jpg: frame 90 (t = 3.0 s) from the 1080p render, 1280×720, ≤ 200 KB
JPG="$MEDIA/poster.jpg"
for q in 2 3 4 5 6 7 8 10 12 15; do
  ffmpeg -v error -y -i "$HFMP4" -vf "select=eq(n\\,$POSTER_FRAME),scale=1280:720:flags=lanczos" -frames:v 1 -q:v $q "$JPG"
  psz=$(fsize "$JPG"); [ "$psz" -le $JPG_LIMIT ] && break
done
[ "$psz" -le $JPG_LIMIT ] || die "poster.jpg is still $psz bytes at q $q"
echo "$ok ${JPG#$ROOT/}  $((psz / 1000)) KB (q $q)"

# ── contact sheet for self-review (not shipped): 10 frames, t = 0.25 … 4.75
if command -v uv >/dev/null 2>&1 && uv run -q --no-project --with pillow python "$ROOT/tools/sheet.py" "$HFMP4" "$OUT/sheet.png" 5 2 384 >/dev/null 2>&1; then
  echo "$ok sheet ${OUT#$ROOT/}/sheet.png"
else
  ffmpeg -v error -y -i "$HFMP4" -vf "fps=2,scale=384:-1,tile=5x2" -frames:v 1 "$OUT/sheet.png" && echo "$ok sheet ${OUT#$ROOT/}/sheet.png (no timestamps)"
fi
echo "   total $(( $(date +%s) - T0 ))s · render log ${LOG#$ROOT/}"
