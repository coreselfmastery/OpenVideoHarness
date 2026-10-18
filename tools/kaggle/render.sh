#!/usr/bin/env bash
# render.sh — a HyperFrames render with every speed setting the machine allows, and nothing that
# would change the film: fps, workers, the capture path and the encoder are chosen from what
# tools/kaggle/setup.sh probed (run it once first; it writes .kaggle/env.sh). Sound is not a HyperFrames
# thing: bin/vh mux puts the mix on after, as with any HyperFrames render in this repo.
#
#   tools/kaggle/render.sh <project> [options]        <project>: the folder with index.html
#
#   Options this script takes (everything else is passed to `hyperframes render` unchanged):
#     --tier draft|final  the review round in one word. draft = `--quality draft` + NVENC tuned for
#                         iteration (preset p4, cq 28 — a fast, good-enough look); final = `--quality
#                         delivery` + NVENC at its best (preset p7, cq 19). Not just the encoder: the
#                         tier is exported as OVH_KAGGLE_TIER, which .kaggle/ffmpeg-gpu.sh reads to
#                         retune the h264_nvenc the engine runs. Without --tier the engine's own
#                         --quality mapping stands (x264-equivalent presets) and NVENC is not retuned
#     --workers N         override the worker policy below
#     --fps N             override the fps policy below (a film written at 60 keeps its frames only with it)
#     --no-gpu            encode on the CPU (libx264) even though setup.sh found NVENC
#     --no-fast-capture   render through screenshots, not the drawElement fast capture
#     --detach            run in the background (HYPERFRAMES_RENDER_DETACHED=1); the log path, the pid
#                         file and the stop command are printed. The last 5 logs are kept, older ones go
#
#   Examples:
#     tools/kaggle/render.sh projects/26-launch --tier draft              # review pass (fast)
#     tools/kaggle/render.sh projects/26-launch --tier final              # the master
#     tools/kaggle/render.sh projects/26-launch --quality draft --output-resolution 4k
#     tools/kaggle/render.sh projects/26-launch --fps 60                  # a 60 fps film keeps its 60
#
# The policies (each one is a measured trap in HyperFrames 0.8.82 — engines/README.md's HyperFrames
# section and tools/kaggle/README.md have the numbers):
#   fps       30 is the default, the single biggest speed lever (about half the frames of 60). The
#             composition's own data-fps is kept when it is 30 or less (a film written at 24 stays 24);
#             when it declares more than 30 this script still renders 30 and says so — pass --fps to
#             keep every frame of a 60 fps spec. After the render the film itself is read back (ffprobe)
#             and the fps, the size, the frame count and the encoder it actually came out with are
#             checked against what was asked: a flag asked for is not a flag applied, and the card
#             says which one held and which fell back (the size is checked too, unless the caller's
#             own --output-resolution / --width / --height passed through and changed it).
#   workers   under 240 s: 1 (a single worker keeps the streaming encode; multi-worker short films
#             buffer every frame to disk first). 240 s and up: HyperFrames auto — with the fast capture
#             that is the parallel router's 3 workers, and an explicit --workers here would switch the
#             router off (it only routes when the count was left to auto). Software rendering: measured,
#             min(one per spare core, one per 6 GB free, 6) — the free memory is read from the cgroup
#             (Kaggle) or /proc/meminfo, so a nearly-full box asks for fewer browsers, not an OOM.
#   encoder   --gpu when NVENC probed OK: HyperFrames encodes with h264_nvenc at the --quality's own
#             constant-quality level, on the second T4 (.kaggle/ffmpeg-gpu.sh pins it there), so the
#             browser keeps GPU 0. bin/vh deliver still re-encodes the platform copy on the CPU.
#   capture   --browser-gpu and --experimental-fast-capture only when setup.sh saw hardware WebGL AND
#             the composition clears the engine's own compile gates: a CSS 3D context, mix-blend-mode,
#             a background-image on the composition's ancestors, or shader transitions each make 0.8.82
#             quietly fall back to screenshots even with the flag on (its compiler detects them; this
#             script scans the same patterns first — the ancestor walk included, not a loose guess —
#             says which one it found, and names the env that overrides it: HF_FAST_CAPTURE_3D /
#             HF_FAST_CAPTURE_BLEND / HF_FAST_CAPTURE_ANCESTOR_BG / PRODUCER_EXPERIMENTAL_FAST_CAPTURE).
#   streaming the engine's streaming encode has a duration cap that, when anything enables it, silently
#             switches a long film to disk-buffered capture (the slow path). This script always sets the
#             cap above the film's own length, so streaming cannot be switched off under it.
#   cache     HYPERFRAMES_EXTRACT_CACHE_DIR is pointed into the project (renders/.hf-extract-cache), so
#             a composition with <video> sources extracts its frames once and a re-render — next session
#             included, on Kaggle — reuses them instead of slicing the same videos again.
set -euo pipefail
unset CDPATH
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

case "${1:-}" in
  -h|--help) sed -n '2,58p' "$0"; exit 0 ;;
  "") sed -n '2,58p' "$0" >&2; exit 1 ;;
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

DETACH=0; NO_GPU=0; NO_FAST=0; TIER=""; WORKERS_OPT=""; FPS_OPT=""; pass=()
while [ $# -gt 0 ]; do
  case "$1" in
    --detach) DETACH=1 ;;
    --no-gpu) NO_GPU=1 ;;
    --no-fast-capture) NO_FAST=1 ;;
    --tier) TIER=${2:?--tier needs draft or final}; shift ;;
    --tier=*) TIER=${1#*=} ;;
    --workers) WORKERS_OPT=${2:?--workers needs a number}; shift ;;
    --workers=*) WORKERS_OPT=${1#*=} ;;
    -w) WORKERS_OPT=${2:?-w needs a number}; shift ;;
    --fps) FPS_OPT=${2:?--fps needs a number}; shift ;;
    --fps=*) FPS_OPT=${1#*=} ;;
    -f) FPS_OPT=${2:?-f needs a number}; shift ;;
    -h|--help) sed -n '2,58p' "$0"; exit 0 ;;
    *) pass+=("$1") ;;
  esac
  shift
done
case "$TIER" in
  draft|final|"") ;;
  *) printf '\033[31m✗\033[0m --tier: draft or final, not "%s"\n' "$TIER" >&2; exit 1 ;;
esac
for v in "$WORKERS_OPT" "$FPS_OPT"; do
  if [ -z "$v" ]; then continue; fi
  case "$v" in *[!0-9]*|0) printf '\033[31m✗\033[0m --workers/--fps: a whole number ≥ 1, not "%s" (the engine would misread it)\n' "$v" >&2; exit 1 ;; esac
done
for a in ${pass[@]+"${pass[@]}"}; do
  case "$a" in --quality|-q|--quality=*) printf '\033[31m✗\033[0m --quality and --tier both name the quality: give one\n' >&2; exit 1 ;; esac
done
case "$TIER" in draft) pass+=(--quality draft) ;; final) pass+=(--quality delivery) ;; esac

if [ ! -f "$PROJ/index.html" ]; then
  printf '\033[31m✗\033[0m no index.html in %s (a HyperFrames project is a folder with one; bin/vh hf-init scaffolds it)\n' "$PROJ" >&2
  exit 1
fi
PROJ="$(cd "$PROJ" && pwd)"

# the film's own length, frame rate and size, from the root composition (what `hyperframes render` itself reads)
meta=$(python3 - "$PROJ/index.html" <<'PY'
import json, re, sys
try: s = open(sys.argv[1], encoding="utf-8").read()
except OSError: sys.exit(0)
root = ""
for tag in re.findall(r'<[^>]*\bdata-composition-id\b[^>]*>', s):
    root = tag; break
def attr(name):
    m = re.search(r'\b' + name + r'="([\d.]+)"', root)
    return m.group(1) if m else ""
print(json.dumps({"duration": attr("data-duration"), "fps": attr("data-fps"),
                  "w": attr("data-width"), "h": attr("data-height")}))
PY
)
DUR=$(printf '%s' "$meta" | python3 -c 'import json,sys; print(json.load(sys.stdin)["duration"])')
DFPS=$(printf '%s' "$meta" | python3 -c 'import json,sys; print(json.load(sys.stdin)["fps"])')
PW=$(printf '%s' "$meta" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["w"] or 1920)')
PH=$(printf '%s' "$meta" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["h"] or 1080)')

flags=(); fps_note=""; workers_note=""; want_fps=""; want_size=""

# ── fps ─────────────────────────────────────────────────────────────────────────────────────────
if [ -n "$FPS_OPT" ]; then
  flags+=(--fps "$FPS_OPT"); fps_note="fps $FPS_OPT (yours)"; want_fps=$FPS_OPT
elif [ -z "$DFPS" ]; then
  flags+=(--fps 30); fps_note="fps 30 (no data-fps; HyperFrames' own default, made explicit)"; want_fps=30
elif awk -v d="$DFPS" 'BEGIN{exit !(d<=30)}'; then
  fps_note="fps $DFPS (the composition's own; kept, it is 30 or less)"; want_fps=$DFPS
else
  flags+=(--fps 30)
  fps_note="fps 30 (the default here; the composition declares $DFPS — pass --fps $DFPS to keep every frame of it)"
  want_fps=30
fi

# ── workers ─────────────────────────────────────────────────────────────────────────────────────
mem_avail_mb() { # free memory: the cgroup's room when there is one (Kaggle, CI), else /proc/meminfo.
  # OVH_TEST_MEM_MB stands in for it (tests); a misread yields 0, and 0 falls back to "do not guess".
  if [ -n "${OVH_TEST_MEM_MB:-}" ]; then echo "$OVH_TEST_MEM_MB"; return 0; fi
  local v="" cur=""
  if [ -r /sys/fs/cgroup/memory.max ] && [ -r /sys/fs/cgroup/memory.current ]; then
    v=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || true); cur=$(cat /sys/fs/cgroup/memory.current 2>/dev/null || true)
    case "$v" in ''|max|*[!0-9]*) v="" ;; *) case "$cur" in ''|*[!0-9]*) cur=0 ;; esac; echo $(( (v - cur) / 1048576 )); return 0 ;; esac
  fi
  if [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ] && [ -r /sys/fs/cgroup/memory/memory.usage_in_bytes ]; then
    v=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || true)
    cur=$(cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null || true)
    case "$v" in ''|*[!0-9]*) v="" ;; *) case "$cur" in ''|*[!0-9]*) cur=0 ;; esac; echo $(( (v - cur) / 1048576 )); return 0 ;; esac
  fi
  awk '/^MemAvailable:/ {print int($2/1024); exit}' /proc/meminfo 2>/dev/null || echo 0
}
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
  avail=$(mem_avail_mb)
  w=$((cores - 1)); if [ $w -lt 1 ]; then w=1; fi; if [ $w -gt 6 ]; then w=6; fi
  if [ "$avail" -gt 0 ]; then
    by_mem=$((avail / 6144)); if [ $by_mem -lt 1 ]; then by_mem=1; fi
    if [ $by_mem -lt $w ]; then w=$by_mem; fi
    workers_note="workers $w (software rendering: min($((cores-1)) cores, $((avail/1024)) GB free / 6 GB a browser, 6))"
  else
    workers_note="workers $w (software rendering: one Chrome per spare core, at most 6)"
  fi
  flags+=(--workers "$w")
fi

# ── encoder and capture ─────────────────────────────────────────────────────────────────────────
if [ "${OVH_KAGGLE_NVENC:-0}" = 1 ] && [ "$NO_GPU" = 0 ]; then
  flags+=(--gpu)
fi
capture_note="screenshots (no hardware WebGL: the fast capture is slower than that on a software GPU)"
if [ "${OVH_KAGGLE_BROWSER_GPU:-software}" = hardware ]; then
  flags+=(--browser-gpu)
  if [ "$NO_FAST" = 0 ]; then
    # the engine's own compile gates, scanned before asking: 0.8.82 turns the fast capture off for these
    # even when the flag is on (its compiler detects them; the HF_FAST_CAPTURE_* envs are its overrides,
    # PRODUCER_EXPERIMENTAL_FAST_CAPTURE the shader one). The patterns below are the engine's own
    # (producer/src compileStage: detectThreeDTransformUsage, detectMixBlendModeUsage,
    # detectAncestorBackgroundImage — a real walk of the composition root's ancestors, not a guess —
    # and detectShaderTransitionUsage over the inline scripts with their comments stripped).
    gate=$(python3 - "$PROJ/index.html" <<'PY'
import re, sys
from html.parser import HTMLParser
try: s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
except OSError: print("read-failed"); sys.exit(0)
THREE_D = r'transform-style\s*:\s*preserve-3d|backface-visibility\s*:|perspective\s*:\s*[0-9]|perspective\s*\(|matrix3d\s*\(|rotate3d\s*\(|\btransformPerspective\b'
if re.search(THREE_D, s, re.I): print("3d"); sys.exit(0)
if re.search(r'mix-blend-mode\s*:', s, re.I): print("blend"); sys.exit(0)
BG = re.compile(r'(?:^|;|\{)\s*background(?:-image)?\s*:[^;}]*(?:\bgradient\s*\(|url\s*\()', re.I)
VOID = {"br", "img", "input", "meta", "link", "hr", "source", "wbr", "area", "base", "col", "embed", "track"}
class Dom(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True); self.stack = []; self.roots = []; self.html = None
    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        node = {"tag": tag, "id": d.get("id") or "", "cls": (d.get("class") or "").split(),
                "style": d.get("style") or "", "parent": self.stack[-1] if self.stack else None}
        self.stack.append(node)
        if tag == "html": self.html = node
        if "data-composition-id" in d: self.roots.append(node)
        if tag in VOID: self.stack.pop()
    def handle_startendtag(self, tag, attrs): pass
    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, -1, -1):
            if self.stack[i]["tag"] == tag:
                del self.stack[i:]; break
d = Dom(); d.feed(s)
if d.roots:   # no composition root: the engine's own check returns false, and so does this
    anc, seen = [], set()
    n = d.roots[0]
    while n is not None:
        if id(n) not in seen: seen.add(id(n)); anc.append(n)
        n = n["parent"]
    if d.html is not None and id(d.html) not in seen: anc.append(d.html)
    for el in anc:                                    # inline style="" on an ancestor
        if el["style"] and BG.search("{" + el["style"] + "}"): print("ancestor_bg"); sys.exit(0)
    def compound_hits(sel, el):
        sel = re.sub(r'::?[a-zA-Z-]+(\([^)]*\))?', "", sel)     # :hover and friends
        m = re.match(r'^([a-zA-Z][\w-]*)?((?:[.#][\w-]+)*)$', sel)
        if not m: return False
        if m.group(1) and el["tag"] != m.group(1).lower(): return False
        for part in re.findall(r'[.#][\w-]+', m.group(2) or ""):
            if part[0] == "." and part[1:] not in el["cls"]: return False
            if part[0] == "#" and el["id"] != part[1:]: return False
        return True
    for style_html in re.findall(r'<style\b[^>]*>(.*?)</style>', s, re.I | re.S):
        for rule in re.finditer(r'([^{}]+)\{([^}]*)\}', style_html):
            if not BG.search("{" + rule.group(2) + "}"): continue
            for raw in rule.group(1).split(","):
                sel = raw.strip()
                if not sel or sel.startswith("@"): continue
                if re.match(r'^(?:html|:root)$', sel, re.I): print("ancestor_bg"); sys.exit(0)
                last = re.split(r'[>\s+~]+', sel)[-1]      # the compound that names the element
                if any(compound_hits(last, el) for el in anc): print("ancestor_bg"); sys.exit(0)
SHADER = re.compile(r'\b(?:(?:window|globalThis)\s*\.\s*)?HyperShader\s*\.\s*init\s*\(|\b__hf\s*\.\s*transitions\s*=')
def strip_js(c):
    c = re.sub(r'/\*.*?\*/', ' ', c, flags=re.S)
    return re.sub(r'//[^\n]*', ' ', c)
for m in re.finditer(r'<script\b([^>]*)>(.*?)</script>', s, re.I | re.S):
    if re.search(r'\bsrc\s*=', m.group(1), re.I): continue
    if SHADER.search(strip_js(m.group(2))): print("shader"); sys.exit(0)
print("clear")
PY
)
    case "$gate" in
      clear) flags+=(--experimental-fast-capture); capture_note="drawElement fast capture (hardware WebGL, and the composition clears the engine's 3D / blend / ancestor-background / shader gates)" ;;
      3d) capture_note="screenshots (the composition uses a CSS 3D context: the engine turns the fast capture off for it — HF_FAST_CAPTURE_3D=true is its override)" ;;
      blend) capture_note="screenshots (the composition uses mix-blend-mode: the engine turns the fast capture off for it — HF_FAST_CAPTURE_BLEND=true is its override)" ;;
      ancestor_bg) capture_note="screenshots (an ancestor of the composition carries a background-image: the engine turns the fast capture off for it — HF_FAST_CAPTURE_ANCESTOR_BG=true is its override)" ;;
      shader) capture_note="screenshots (the composition uses shader transitions: the engine turns the fast capture off for them — PRODUCER_EXPERIMENTAL_FAST_CAPTURE=true is its override)" ;;
      *) capture_note="screenshots (could not scan the composition for the fast-capture gates; being safe)" ;;
    esac
  else
    capture_note="screenshots (--no-fast-capture)"
  fi
fi

# what the film should come out as, for the read-back card below — the size only while nothing that
# passes through to the engine changes it (--output-resolution supersamples, --width/--height set it)
want_size="${PW}x${PH}"
for a in ${pass[@]+"${pass[@]}"}; do
  case "$a" in --output-resolution|--output-resolution=*|--width|--width=*|--height|--height=*) want_size="" ;; esac
done

# ── streaming cap: always above the film's own length (C6/D7) ───────────────────────────────────
stream_note=""
if [ -n "$DUR" ]; then
  CAP=$(python3 -c "import math; print(math.ceil($DUR)+60)")
  export PRODUCER_STREAMING_ENCODE_MAX_DURATION_SECONDS=$CAP
  stream_note="streaming cap $CAP s (the film is $DUR s; nothing can switch it to disk-buffered capture)"
fi

# ── disk: warn before a render that cannot finish (E8) ──────────────────────────────────────────
free_kb=$(df -Pk "$PROJ" 2>/dev/null | awk 'NR==2{print $4}' || echo 0)
if [ -n "$DUR" ] && [ "$free_kb" -gt 0 ]; then
  DFPS_N=${DFPS:-30}
  nframes=$(python3 -c "import math; print(math.ceil($DUR*($DFPS_N or 30)-1e-6))" 2>/dev/null || echo 0)
  if [ "$nframes" -gt 0 ]; then
    need_kb=$(python3 -c "print(int(2*$nframes*$PW*$PH*0.06/8/1024))" 2>/dev/null || echo 0)
    if [ "$need_kb" -gt 0 ] && [ "$free_kb" -lt "$need_kb" ]; then
      printf '\033[33m!\033[0m only %s GB free under %s; a %s-frame %sx%s render may want about %s GB at its peak (streaming keeps it lower)\n' \
        "$(awk -v k="$free_kb" 'BEGIN{printf "%.1f", k/1048576}')" "$PROJ" "$nframes" "$PW" "$PH" "$(awk -v k="$need_kb" 'BEGIN{printf "%.1f", k/1048576}')" >&2
    fi
    if [ "$free_kb" -lt 512000 ]; then
      printf '\033[31m✗\033[0m only %s MB free under %s: not enough to render on\n' "$((free_kb / 1024))" "$PROJ" >&2
      exit 2
    fi
  fi
fi

# ── the launcher ────────────────────────────────────────────────────────────────────────────────
if [ -x "$PROJ/node_modules/.bin/hyperframes" ]; then
  cmd=("$PROJ/node_modules/.bin/hyperframes")
else
  cmd=(npx --yes "hyperframes@${HYPERFRAMES_VERSION:-0.8.82}")   # bin/vh hf-init pins it into the project
fi
if [ -n "$TIER" ]; then export OVH_KAGGLE_TIER=$TIER; else unset OVH_KAGGLE_TIER || true; fi

printf '\033[36m→\033[0m project  : %s (%s s, %sx%s%s)\n' "$PROJ" "$(if [ -n "$DUR" ]; then printf '%s' "$DUR"; else printf 'length unknown'; fi)" "$PW" "$PH" "$(if [ -n "$DFPS" ]; then printf ', %s fps declared' "$DFPS"; fi)"
if [ "${OVH_KAGGLE_BROWSER_GPU:-software}" = hardware ]; then
  printf '\033[36m→\033[0m browser  : GPU 0, hardware WebGL (%s)\n' "${OVH_KAGGLE_WEBGL_RENDERER:-probed OK}"
else
  printf '\033[36m→\033[0m browser  : CPU (SwiftShader software rendering)\n'
fi
if [ "${OVH_KAGGLE_NVENC:-0}" = 1 ] && [ "$NO_GPU" = 0 ]; then
  tier_note=""
  [ -n "$TIER" ] && tier_note=", retuned for the $TIER tier by .kaggle/ffmpeg-gpu.sh (OVH_KAGGLE_TUNE=off keeps the engine's own)"
  printf '\033[36m→\033[0m encode   : GPU %s, h264_nvenc at the --quality level%s (bin/vh deliver still re-encodes the platform copy on the CPU)\n' "${OVH_KAGGLE_NVENC_GPU:-0}" "$tier_note"
else
  printf '\033[36m→\033[0m encode   : CPU (libx264)\n'
fi
printf '\033[36m→\033[0m capture  : %s\n' "$capture_note"
printf '\033[36m→\033[0m %s\n' "$fps_note"
printf '\033[36m→\033[0m %s\n' "$workers_note"
[ -n "$stream_note" ] && printf '\033[36m→\033[0m %s\n' "$stream_note"
if [ -n "$DUR" ] && awk -v d="$DUR" 'BEGIN{exit !(d>=240)}' && [ "${OVH_KAGGLE_GPUS:-0}" -gt 1 ]; then
  printf '\033[36m→\033[0m both cards: tools/kaggle/render-split.sh %s --tier %s draws two halves at once, one NVENC each\n' "$PROJ" "${TIER:-final}"
fi
printf '\033[36m→\033[0m command  : %s\n' "$(printf '%s ' "${cmd[@]}" render . ${flags[@]+"${flags[@]}"} ${pass[@]+"${pass[@]}"})"

# the engine's extracted-frame cache (<video> sources) into the project: a re-render reuses the slices
# (renders/ is bin/vh clean's own territory, so a finished project takes the cache with it)
if [ -z "${HYPERFRAMES_EXTRACT_CACHE_DIR:-}" ]; then
  export HYPERFRAMES_EXTRACT_CACHE_DIR="$PROJ/renders/.hf-extract-cache"
fi

cd "$PROJ"
if [ "$DETACH" = 1 ]; then
  mkdir -p out renders
  # keep the last 5 logs: a long session of detached renders should not fill the disk with them
  i=0; for old in $(ls -1t out/render-*.log 2>/dev/null | awk 'NR>5'); do rm -f "$old"; i=$((i+1)); done
  [ "$i" = 0 ] || printf '\033[36m→\033[0m rotated %s old render log(s) away (5 kept)\n' "$i"
  log="$PROJ/out/render-$(date +%Y%m%d-%H%M%S).log"
  HYPERFRAMES_RENDER_DETACHED=1 nohup "${cmd[@]}" render . ${flags[@]+"${flags[@]}"} ${pass[@]+"${pass[@]}"} >"$log" 2>&1 &
  pid=$!
  echo "$pid" > "$PROJ/out/render.pid"
  printf '\033[32m✓\033[0m detached — pid %s, log: %s\n' "$pid" "$log"
  printf '  watch : tail -f %s\n' "$log"
  printf '  stop  : kill %s   (or: kill $(cat %s))\n' "$pid" "$PROJ/out/render.pid"
else
  # a child, not an exec, so the film it leaves can be read back afterwards; the traps keep what the exec
  # gave: a signal addressed to this shell reaches the engine too (a terminal Ctrl-C hits both anyway —
  # the engine is in this shell's process group)
  # the moment the render begins, one second back (python: date -r FILE is BSD-only, date -d @N GNU-only) —
  # the film is read back by "newer than this", so a previous render's MP4 is never mistaken for this one's
  MSTART=$(python3 -c "import time; print(time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(time.time()-1)))")
  "${cmd[@]}" render . ${flags[@]+"${flags[@]}"} ${pass[@]+"${pass[@]}"} &
  RPID=$!
  trap 'kill -TERM "$RPID" 2>/dev/null || true' TERM
  trap 'kill -INT  "$RPID" 2>/dev/null || true' INT
  RRC=0
  wait "$RPID" 2>/dev/null || RRC=$?
  while kill -0 "$RPID" 2>/dev/null; do wait "$RPID" 2>/dev/null || RRC=$?; done
  trap - TERM INT
  [ "$RRC" -eq 0 ] || exit "$RRC"
  # ── what the film itself says: the flags were requests, this is what came out ───────────────
  # (ffprobe on the newest MP4 under renders/ younger than the render — the engine's default output;
  # an -o or --format render puts its file elsewhere, and the card says so instead of guessing)
  card=""
  film=""
  if command -v ffprobe >/dev/null 2>&1 && [ -d "$PROJ/renders" ]; then
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      if [ -z "$film" ] || [ "$f" -nt "$film" ]; then film=$f; fi
    done < <(find "$PROJ/renders" -maxdepth 1 -name '*.mp4' -newermt "${MSTART:-1970-01-01 00:00:00}" 2>/dev/null || true)
  fi
  if [ -n "$film" ]; then
    got=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,avg_frame_rate,nb_frames -of json "$film" 2>/dev/null || true)
    card=$(python3 - "$film" "${OVH_KAGGLE_NVENC:-0}" "$NO_GPU" "$want_fps" "$want_size" "$got" <<'PY'
import json, sys
film, nvenc, no_gpu, want_fps, want_size, raw = sys.argv[1:7]
try: streams = json.loads(raw or "{}").get("streams") or [{}]
except Exception: streams = [{}]
st = streams[0] or {}
if not st.get("codec_name"):
    print("unreadable: " + film); sys.exit(0)
rate = str(st.get("avg_frame_rate", "?"))
try:
    a, b = rate.split("/"); fps = int(a) / int(b)
except Exception:
    fps = None
codec, w, h, n = st.get("codec_name"), st.get("width"), st.get("height"), st.get("nb_frames")
fpss = str(round(fps, 2)).rstrip("0").rstrip(".") if fps is not None else rate
bits = "%s frames, %sx%s, %s fps, %s" % (n, w, h, fpss, codec)
miss = []                                   # every ask the file did not meet, in one honest line
if nvenc == "1" and no_gpu == "0":
    if codec == "h264_nvenc": held = "the --gpu flag held: the file itself says h264_nvenc"
    else:
        held = ""
        miss.append("NVENC was asked for, the file came out %s (the engine fell back — its log above says why)" % codec)
elif codec in ("libx264", "h264", "h264_nvenc"):
    held = "the encode came out %s, as planned" % codec
else:
    held = "the encode came out %s" % codec
if want_fps and fps is not None and abs(fps - float(want_fps)) > 0.1:
    miss.append("asked %s fps, the file says %s" % (want_fps, fpss))
if want_size and "%sx%s" % (w, h) != want_size:
    miss.append("the composition is %s, the file says %sx%s" % (want_size, w, h))
if miss:
    print("warn: %s — %s" % (bits, "; ".join(miss)))
elif held:
    print("ok: %s — %s" % (bits, held))
else:
    print("ok: %s" % bits)
PY
)
  elif command -v ffprobe >/dev/null 2>&1; then
    card="no-new-mp4"
  fi
  case "$card" in
    ok:*)    printf '\033[32m✓\033[0m held     : %s\n' "${card#ok: }" ;;
    warn:*)  printf '\033[33m!\033[0m held     : %s\n' "${card#warn: }" ;;
    no-new-mp4) printf '\033[36m→\033[0m held     : no new MP4 under renders/ (an -o or --format render?) — the flags above were the request\n' ;;
    unreadable:*) printf '\033[36m→\033[0m held     : (could not read the film back: %s)\n' "${card#unreadable: }" ;;
    "")  : ;;   # no ffprobe: the engine's own banner is the report
  esac
fi
