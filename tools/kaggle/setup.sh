#!/usr/bin/env bash
# setup.sh — the one command a Kaggle session (or any Linux GPU box) needs before rendering HyperFrames
# fast: prove what the machine can really do, cache what a render would otherwise download, and write
# .kaggle/env.sh + .kaggle/ffmpeg-gpu.sh for tools/kaggle/render.sh. Safe to re-run: it re-probes and
# rewrites both files. Nothing here needs sudo, and nothing it writes goes into git (.kaggle/ is ignored).
#
#   tools/kaggle/setup.sh [--no-persist] [--force-browser]
#
#   --no-persist     keep every cache where the OS puts it ($HOME, lost when a Kaggle session ends)
#                    instead of moving it under /kaggle/working/.cache, which a saved notebook keeps
#   --force-browser  download Chrome again even if one is cached (hyperframes browser ensure --force)
#
# What it probes (never assumed — each is the same probe HyperFrames 0.8.82 itself runs, so what passes
# here is what a render will really use):
#   1. Node ≥ 22         HyperFrames needs it; Kaggle images carry an older or no Node. A 22 LTS tarball
#                        from nodejs.org is unpacked into the cache and put on PATH by .kaggle/env.sh.
#   2. ffmpeg            the first ffmpeg around (PATH, the usual bin dirs) that has both h264_nvenc
#                        and the psnr filter; recorded in the env file.
#   3. Chrome            `hyperframes browser ensure` with the repo's pinned version, so the first
#                        render doesn't spend 5–10 minutes downloading it mid-render.
#   4. browser GPU       chrome-headless-shell is launched with HyperFrames' own hardware-GPU flags
#                        (ANGLE over EGL) and asked for its WebGL renderer: NVIDIA → hardware,
#                        SwiftShader / no WebGL → software. render.sh then knows whether --browser-gpu
#                        and the fast capture are safe to ask for.
#   5. NVENC per GPU     a 320×240 h264_nvenc encode on each GPU. With two T4s the encode is pinned to
#                        GPU 1 (the wrapper this script writes injects ffmpeg's own -gpu option), so the
#                        browser (GPU 0) and the encoder (GPU 1) never wait on each other.
#
# What it cannot do anything about: Kaggle's /dev/shm is small (HyperFrames launches Chrome with
# --disable-dev-shm-usage itself, so it is a doctor warning, not a render problem), and the GPU quota
# (about 30 h a week) — plan the draft/final passes around it.
set -euo pipefail
unset CDPATH
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PERSIST=1; FORCE_BROWSER=0
while [ $# -gt 0 ]; do case "$1" in
  --no-persist) PERSIST=0; shift ;;
  --force-browser) FORCE_BROWSER=1; shift ;;
  -h|--help) sed -n '2,31p' "$0"; exit 0 ;;
  *) echo "unknown option: $1 (try --help)"; exit 1 ;;
esac; done
c_ok=$'\033[32m✓\033[0m'; c_no=$'\033[31m✗\033[0m'; c_wa=$'\033[33m!\033[0m'
say() { printf '\033[36m→ %s\033[0m\n' "$*"; }
ok() { printf '%s %s\n' "$c_ok" "$*"; }
no() { printf '%s %s\n' "$c_no" "$*"; }
warn() { printf '%s %s\n' "$c_wa" "$*"; }
run_to() { # run_to <seconds> <cmd…>: killed after <seconds> when the coreutils timeout is there
  local s=$1; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"; else "$@"; fi
}

mkdir -p "$ROOT/.kaggle"

# ── the machine ─────────────────────────────────────────────────────────────────────────────────
# Kaggle keeps /kaggle/working across sessions when the notebook is saved; $HOME is fresh every time.
# Caches moved there (npm, Chrome, uv) survive a restart, and 20 GB of working space is plenty for
# them: Chrome about 200 MB, the npm cache a few hundred MB, uv up to about 700 MB.
KAGGLE=0
if [ -d /kaggle/working ] && [ -w /kaggle/working ]; then KAGGLE=1; fi
if [ "$KAGGLE" = 1 ] && [ "$PERSIST" = 1 ]; then
  CACHE=/kaggle/working/.cache
else
  CACHE="$HOME/.cache"; PERSIST=0
fi
mkdir -p "$CACHE"
if [ "$KAGGLE" = 1 ]; then
  ok "Kaggle session (caches under $CACHE, kept by a saved notebook)"
else
  warn "not a Kaggle session: caches stay in $HOME; --no-persist on Kaggle does the same"
fi

gpus=0; gpu_names=""
if command -v nvidia-smi >/dev/null 2>&1; then
  gpu_names=$(nvidia-smi -L 2>/dev/null || true)
  gpus=$(printf '%s\n' "$gpu_names" | grep -c '^GPU ' || true)
fi
if [ "$gpus" -gt 0 ]; then
  ok "$gpus GPU(s), first: $(printf '%s\n' "$gpu_names" | head -1 | sed 's/^GPU [0-9]*: //')"
else
  warn "no NVIDIA GPU visible (nvidia-smi): Chrome renders on the CPU (SwiftShader) and the encode stays on libx264"
fi

mem_mb() { # the memory that governs this box: the cgroup limit when there is one (Kaggle, CI, HyperFrames'
  # own [SystemMemory] line), else /proc/meminfo. v2/v1 cgroup files are bytes; MemTotal is kB. 0 when
  # nothing can be read. (An earlier version divided bytes by 1024 and read a 4 GB box as 4 TB, which
  # put an 8 GB heap cap on it and thrashed the GC — the unit split below is the fix.)
  local v="" unit=b
  if [ -r /sys/fs/cgroup/memory.max ]; then v=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || true); fi
  if [ -z "$v" ] || [ "$v" = "max" ]; then
    if [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then v=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || true); fi
  fi
  if [ -z "$v" ] || [ "$v" = "max" ]; then v=$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || true); unit=k; fi
  case "$v" in ''|max|*[!0-9]*) echo 0 ;; *) if [ "$unit" = b ]; then echo $(( v / 1048576 )); else echo $(( v / 1024 )); fi ;; esac
}
TOTAL_MB=$(mem_mb)

# ── caches that survive a Kaggle restart ────────────────────────────────────────────────────────
# A symlink, so every tool keeps finding them where it always looked (~/.npm, ~/.cache/puppeteer …):
# bin/vh looks for the Chrome in ~/.cache/puppeteer, npm in ~/.npm, uv in ~/.cache/uv.
persist_dir() { # persist_dir <path> <name>: move <path> into the cache and leave a symlink behind
  local p=$1 name=$2 dest
  if [ "$PERSIST" != 1 ] || [ -L "$p" ]; then return 0; fi
  dest="$CACHE/$name"
  if [ -e "$p" ]; then
    if [ ! -e "$dest" ]; then mv "$p" "$dest"; ln -s "$dest" "$p"; fi
  else
    mkdir -p "$dest"; ln -s "$dest" "$p"
  fi
}
if [ "$PERSIST" = 1 ]; then
  say "moving the render caches under $CACHE (a saved Kaggle notebook keeps them)"
  mkdir -p "$HOME/.cache"
  persist_dir "$HOME/.npm" npm
  persist_dir "$HOME/.cache/puppeteer" puppeteer
  persist_dir "$HOME/.cache/hyperframes" hyperframes
  persist_dir "$HOME/.cache/uv" uv
  ok "caches: npm · puppeteer (Chrome) · hyperframes · uv now live under $CACHE"
fi

# ── Node ≥ 22 ───────────────────────────────────────────────────────────────────────────────────
node_major() { local v; v=$(node -v 2>/dev/null || true); v=${v#v}; case "$v" in ''|*[!0-9.]*) echo 0 ;; *) echo "${v%%.*}" ;; esac; }
NODE_BIN=""
if command -v node >/dev/null 2>&1 && [ "$(node_major)" -ge 22 ]; then
  ok "Node $(node -v) (≥ 22, what HyperFrames asks for)"
else
  if command -v node >/dev/null 2>&1; then warn "Node $(node -v) is older than 22"; else warn "no Node on PATH"; fi
  say "fetching the Node 22 LTS tarball from nodejs.org (no sudo, no apt)"
  arch=$(uname -m)
  case "$arch" in
    x86_64) arch=x64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) no "don't know a Node tarball for $(uname -m): install Node ≥ 22 yourself and re-run"; exit 1 ;;
  esac
  # grep reads all of its input here (no -q): with set -o pipefail, a -q that stops early would kill
  # the command feeding the pipe with SIGPIPE and fail the whole probe (141) on a large -encoders list
  sums=$(curl -fsSL -m 60 https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt)
  dist=$(printf '%s\n' "$sums" | grep -o "node-v22[0-9.]*-linux-$arch.tar.xz")
  dist=${dist%%$'\n'*}
  if [ -z "$dist" ]; then no "could not read the Node 22 download index (offline?)"; exit 1; fi
  if [ ! -d "$CACHE/node/$dist" ]; then
    mkdir -p "$CACHE/node"
    curl -fSL -m 600 -o "$CACHE/node/$dist.tar.xz" "https://nodejs.org/dist/latest-v22.x/$dist"
    (cd "$CACHE/node" && tar -xJf "$dist.tar.xz" && rm -f "$dist.tar.xz")
  fi
  NODE_BIN="$CACHE/node/$dist/bin"
  PATH="$NODE_BIN:$PATH"
  ok "Node $(node -v) from $CACHE/node/$dist (env.sh puts it on PATH)"
fi

# ── ffmpeg with NVENC and the psnr filter ───────────────────────────────────────────────────────
# HyperFrames runs the system ffmpeg (HYPERFRAMES_FFMPEG_PATH wins, else the usual bin dirs — the PATH
# is not searched). Ubuntu's own build has both NVENC and psnr; a conda ffmpeg often has neither.
unset HYPERFRAMES_FFMPEG_PATH || true
say "looking for an ffmpeg with h264_nvenc (GPU encode) and the psnr filter (fast capture checks)"
FF=""; FF_H264=0
for c in "$(command -v ffmpeg || true)" /usr/bin/ffmpeg /opt/conda/bin/ffmpeg /usr/local/bin/ffmpeg /snap/bin/ffmpeg; do
  if [ -z "$c" ] || [ ! -x "$c" ]; then continue; fi
  case "$c" in "$ROOT"/.kaggle/*) continue ;; esac   # our own wrapper from a previous run
  if "$c" -hide_banner -encoders 2>/dev/null | grep h264_nvenc >/dev/null && "$c" -hide_banner -filters 2>/dev/null | grep ' psnr ' >/dev/null; then
    FF=$c; FF_H264=1; break
  fi
done
if [ -z "$FF" ]; then
  for c in "$(command -v ffmpeg || true)" /usr/bin/ffmpeg /opt/conda/bin/ffmpeg /usr/local/bin/ffmpeg /snap/bin/ffmpeg; do
    if [ -z "$c" ] || [ ! -x "$c" ]; then continue; fi
    case "$c" in "$ROOT"/.kaggle/*) continue ;; esac
    if "$c" -hide_banner -filters 2>/dev/null | grep ' psnr ' >/dev/null; then FF=$c; break; fi
  done
fi
if [ -n "$FF" ]; then
  if [ "$FF_H264" = 1 ]; then
    ok "$($FF -version | head -1) — has h264_nvenc and psnr"
  else
    warn "$FF has no h264_nvenc: renders encode on the CPU (libx264); apt-get install ffmpeg brings an NVENC build on Ubuntu"
  fi
else
  no "no usable ffmpeg at all: apt install ffmpeg (or brew install ffmpeg), then re-run"
  exit 1
fi

# ── NVENC, one probe per GPU ────────────────────────────────────────────────────────────────────
# The same 320×240 test encode HyperFrames runs before using a GPU encoder (its gpuEncoder.ts), with
# ffmpeg's own -gpu pin (see `ffmpeg -h encoder=h264_nvenc`), tried from the last GPU down: on 2×T4 the
# encode lands on GPU 1 and Chrome keeps GPU 0 to itself.
NVENC=0; NVENC_GPU=0
if [ "$FF_H264" = 1 ] && [ "$gpus" -gt 0 ]; then
  say "probing NVENC on each GPU (a 320×240 test encode, pinned per GPU)"
  i=$((gpus - 1))
  while [ $i -ge 0 ]; do
    if "$FF" -hide_banner -loglevel error -f lavfi -i color=size=320x240:rate=1:duration=1 -frames:v 1 -an \
         -c:v h264_nvenc -gpu "$i" -f null - >/dev/null 2>&1; then NVENC=1; NVENC_GPU=$i; break; fi
    i=$((i - 1))
  done
  if [ "$NVENC" = 1 ]; then
    if [ "$gpus" -gt 1 ] && [ "$NVENC_GPU" -eq 0 ]; then
      ok "h264_nvenc works on GPU 0 only (the higher-numbered GPU(s) did not answer, so the browser and the encoder share it)"
    else
      ok "h264_nvenc works on GPU $NVENC_GPU"
    fi
  else
    warn "h264_nvenc is compiled in but encodes on no GPU (the driver or the container blocks it): renders encode on the CPU"
  fi
fi

# ── Chrome, cached once ─────────────────────────────────────────────────────────────────────────
say "ensuring the Chrome HyperFrames renders with (hyperframes browser ensure, pinned)"
ensure_args=()
if [ "$FORCE_BROWSER" = 1 ]; then ensure_args=(--force); fi
(cd "$ROOT" && HYPERFRAMES_SKIP_SKILLS=1 DO_NOT_TRACK=1 npx --yes "hyperframes@${HYPERFRAMES_VERSION:-0.8.82}" browser ensure ${ensure_args[@]+"${ensure_args[@]}"}) \
  || no "hyperframes browser ensure failed (offline?); the first render will try the download itself"
CHROME="$(cd "$ROOT" && HYPERFRAMES_SKIP_SKILLS=1 DO_NOT_TRACK=1 npx --yes "hyperframes@${HYPERFRAMES_VERSION:-0.8.82}" browser path 2>/dev/null | tail -1 || true)"
BROWSER_GPU=software; WEBGL=""
if [ -n "$CHROME" ] && [ -x "$CHROME" ]; then
  say "asking that Chrome for its WebGL renderer (HyperFrames' own hardware flags: ANGLE over EGL)"
  PAGE='data:text/html,<script>var c=document.createElement("canvas");var gl=c.getContext("webgl");if(!gl){document.title="WEBGL-UNAVAILABLE";}else{var d=gl.getExtension("WEBGL_debug_renderer_info");document.title="GLRENDERER "+(d?gl.getParameter(d.UNMASKED_RENDERER_WEBGL):gl.getParameter(gl.RENDERER));}</script>'
  t=$(run_to 60 "$CHROME" --no-sandbox --disable-setuid-sandbox --disable-dev-shm-usage --enable-webgl --ignore-gpu-blocklist \
        --use-gl=angle --use-angle=gl-egl --enable-gpu-rasterization --disable-software-rasterizer --dump-dom "$PAGE" 2>/dev/null \
        | grep -o '<title>[^<]*</title>' | sed 's/<[^>]*>//g' || true)
  case "$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')" in
    *webgl-unavailable*|'')
      if [ -n "$t" ]; then warn "Chrome gets no WebGL context through EGL: the browser renders on the CPU (SwiftShader)"
      else warn "the WebGL probe did not run (Chrome did not answer): treating the browser as software, as HyperFrames' own probe would"; fi ;;
    *swiftshader*|*llvmpipe*|*software*)
      warn "Chrome's WebGL renderer is software ($t)" ;;
    *)
      BROWSER_GPU=hardware; WEBGL=$t; ok "Chrome's WebGL renderer is hardware: $t" ;;
  esac
else
  warn "could not find the Chrome binary to probe (browser ensure failed above?); renders will probe for themselves"
fi

# ── .kaggle/ffmpeg-gpu.sh and .kaggle/env.sh ────────────────────────────────────────────────────
if [ "$NVENC" = 1 ]; then
  WRAPPER="$ROOT/.kaggle/ffmpeg-gpu.sh"
  cat > "$WRAPPER" <<WRAP
#!/usr/bin/env bash
# Written by tools/kaggle/setup.sh — HyperFrames' ffmpeg (HYPERFRAMES_FFMPEG_PATH points here). Two
# jobs, and both only ever touch the engine's own render invocations (those never carry a -gpu of
# their own; a command line that has one was written by hand and passes through untouched):
#   1. every NVENC encode is pinned to GPU $NVENC_GPU: Chrome draws on GPU 0, this encodes on GPU
#      $NVENC_GPU, and neither waits on the other. -gpu is h264_nvenc's own option
#      (ffmpeg -h encoder=h264_nvenc).
#   2. OVH_KAGGLE_TIER (exported by tools/kaggle/render.sh --tier) retunes the h264_nvenc the engine
#      runs, replacing the -preset/-cq/-b:v it chose: beast → -preset p5 -cq 21 (THE one tier: one
#      ship-grade pass, the review class at a fraction of p7's wall), draft → -preset p4 -cq 28 (fast
#      to produce, good enough to judge), final → -preset p7 -cq 19 (the best Turing NVENC does).
#      The values the engine itself passes for these three options are swallowed; everything else
#      (gop, colour tags, filters, streams) is kept as the engine wrote it. OVH_KAGGLE_TUNE=off turns
#      the retuning off (the GPU pin stays).
GPU=\${OVH_KAGGLE_NVENC_GPU:-$NVENC_GPU}
REAL='$FF'
TIER=\${OVH_KAGGLE_TIER:-}
[ "\${OVH_KAGGLE_TUNE:-on}" = "off" ] && TIER=""
for a in "\$@"; do [ "\$a" = "-gpu" ] && exec "\$REAL" "\$@"; done
out=()
tuned=0        # an h264_nvenc whose engine tuning the tier replaced: its -preset/-cq/-b:v go
skip=0
for a in "\$@"; do
  if [ "\$skip" = 1 ]; then skip=0; continue; fi
  case "\$a" in
    h264_nvenc|*=h264_nvenc)
      out+=("\$a" -gpu "\$GPU")
      case "\$TIER" in
        beast) out+=(-preset p5 -cq 21); tuned=1 ;;
        draft) out+=(-preset p4 -cq 28); tuned=1 ;;
        final) out+=(-preset p7 -cq 19); tuned=1 ;;
      esac ;;
    hevc_nvenc|*=hevc_nvenc) out+=("\$a" -gpu "\$GPU") ;;
    -preset|-cq|-b:v)
      if [ "\$tuned" = 1 ]; then skip=1; else out+=("\$a"); fi ;;
    *) out+=("\$a") ;;
  esac
done
exec "\$REAL" "\${out[@]}"
WRAP
  chmod +x "$WRAPPER"
  ok "wrote the ffmpeg wrapper: NVENC encodes go to GPU $NVENC_GPU; --tier draft/final retunes them (OVH_KAGGLE_TUNE=off keeps the engine's own settings)"
fi

# The Node heap is only ever RAISED here (HyperFrames sizes workers against it, about 640 MB each plus
# headroom, and its own advice for multi-worker 4K renders is 8 GB): Node ≥ 22's default is 4 GB, so a
# box smaller than ~12 GB keeps the default instead of being handed a smaller cap, and a misread
# machine total cannot hand a small box a huge one.
HEAP=0
if [ "$TOTAL_MB" -ge 6000 ]; then HEAP=$(( TOTAL_MB / 3 )); fi
if [ "$HEAP" -gt 8192 ]; then HEAP=8192; fi
if [ "$HEAP" -le 4096 ]; then HEAP=0; fi
ENVF="$ROOT/.kaggle/env.sh"
{
  cat <<HDR
# Written by tools/kaggle/setup.sh. Source it before rendering with HyperFrames on this machine —
# tools/kaggle/render.sh does it for you; a bare \`npx hyperframes render\` only gets the tuning when
# you source it by hand first:
#   source "$ENVF"
# Every value below was probed, not assumed; re-run tools/kaggle/setup.sh after a session restart.
HDR
  printf 'export OVH_KAGGLE_SETUP=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'export OVH_KAGGLE_GPUS=%s\n' "$gpus"
  printf 'export OVH_KAGGLE_FFMPEG=%q\n' "$FF"
  printf 'export OVH_KAGGLE_NVENC=%s\n' "$NVENC"
  printf 'export OVH_KAGGLE_NVENC_GPU=%s\n' "$NVENC_GPU"
  printf 'export OVH_KAGGLE_BROWSER_GPU=%s\n' "$BROWSER_GPU"
  if [ -n "$WEBGL" ]; then printf 'export OVH_KAGGLE_WEBGL_RENDERER=%q\n' "$WEBGL"; fi
  cat <<'TAIL'
# the render flags HyperFrames 0.8.82 reads (engines/README.md, the HyperFrames section, has the why):
export HF_DE_PARALLEL_ROUTER=true        # the parallel fast-capture router; without it a long render runs 3x slower
export HF_DE_PARALLEL_STREAM=true        # multi-worker fast capture streams into the encoder instead of buffering on disk
export HF_CAPTURE_PARALLEL_STREAM=true   # the same for multi-worker screenshot capture (4K, shader-transition renders)
export HYPERFRAMES_SKIP_SKILLS=1         # no global skill install (bin/vh hf-init's rule)
export DO_NOT_TRACK=1
export HYPERFRAMES_NO_UPDATE_CHECK=1
TAIL
  if [ "$NVENC" = 1 ]; then
    printf 'export HYPERFRAMES_FFMPEG_PATH=%q   # the wrapper that pins NVENC to GPU %s\n' "$ROOT/.kaggle/ffmpeg-gpu.sh" "$NVENC_GPU"
  fi
  if [ "$HEAP" -gt 0 ]; then
    cat <<HEAP
# Node ≥ 22 defaults its old-space heap to 4 GB; this machine's $TOTAL_MB MB allows more, which
# multi-worker renders need (HyperFrames allows about 640 MB per worker plus headroom). An inherited
# NODE_OPTIONS is left alone.
if [ -z "\${NODE_OPTIONS:-}" ]; then export NODE_OPTIONS="--max-old-space-size=$HEAP"; fi
HEAP
  fi
  if [ -n "$NODE_BIN" ]; then
    printf 'NODE_DIR=%q\n' "$NODE_BIN"
    cat <<'NODEPATH'
case ":$PATH:" in
  *":$NODE_DIR:"*) ;;
  *) export PATH="$NODE_DIR:$PATH" ;;
esac
unset NODE_DIR
NODEPATH
  fi
} > "$ENVF"
ok "wrote .kaggle/env.sh"
if [ "$NVENC" = 1 ]; then printf '   (+ the ffmpeg wrapper it points at: .kaggle/ffmpeg-gpu.sh)\n'; fi

printf '\n'
say "summary — what a render on this machine will do"
if [ "$BROWSER_GPU" = hardware ]; then
  printf '  browser : GPU 0, hardware WebGL (%s)\n' "$WEBGL"
else
  printf '  browser : CPU (SwiftShader software WebGL)\n'
fi
if [ "$NVENC" = 1 ]; then
  printf '  encode  : GPU %s (h264_nvenc, quality set by --quality)\n' "$NVENC_GPU"
else
  printf '  encode  : CPU (libx264)\n'
fi
printf '  workers : chosen per film by tools/kaggle/render.sh (1 under 240 s, HyperFrames auto above)\n'
printf '\n'
say "next: tools/kaggle/render.sh <project> --quality draft   (README.md in this folder has the full flow)"
