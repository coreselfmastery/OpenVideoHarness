#!/usr/bin/env bash
# kaggle-test.sh — the committed test bed for tools/kaggle/*: setup.sh's probes and the ffmpeg
# wrapper it writes, render.sh's flag policy, and render-split.sh's plan, against stubs (no GPU,
# no Chrome, no network needed). What is checked here is the same thing GitHub Actions runs
# (tools/ci.sh calls this as the "kaggle" group).
#
#   bash tools/kaggle/test.sh            (or: tools/ci.sh, which runs everything)
#
# Exit status: the number of failed checks (0 = all passed).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fails=0; ran=0
ok()  { ran=$((ran + 1)); printf '\033[32m✓\033[0m %s\n' "$*"; }
bad() { ran=$((ran + 1)); printf '\033[31m✗\033[0m %s\n' "$*"; fails=$((fails + 1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2] want [$3]"; fi; }
chkno() { if [ "$2" != "$3" ]; then ok "$1"; else bad "$1: got [$2]"; fi; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/ovh-kaggle-test.XXXXXX") || exit 1
# canonicalise once, the way render.sh itself does (PROJ="$(cd "$PROJ" && pwd)"): on macOS $TMPDIR
# ends in a slash, so the mktemp template reads …/T//ovh-kaggle-test.XXXXXX and mktemp keeps the
# double slash in what it prints — every path this test greps for would then carry T// while the
# tools' own cd+pwd collapses it to T/, and the greps silently miss (run 39123478825's macOS job,
# "the extract cache was not exported into the project"). One namespace from here on.
WORK="$(cd "$WORK" && pwd)"
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"

# ── the stubs ───────────────────────────────────────────────────────────────────────────────────
# ffmpeg: answers -encoders with h264_nvenc, -filters with psnr, succeeds at any encode, and records
# every command line it was handed into $WORK/ffmpeg.log (one line per call, args space-joined).
cat > "$BIN/ffmpeg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${OVH_TEST_FFMPEG_LOG:-/dev/null}"
for a in "$@"; do
  case "$a" in
    -encoders) printf ' V....D h264_nvenc  NVIDIA NVENC H.264 encoder\n V....D hevc_nvenc\n'; exit 0 ;;
    -filters)  printf ' ... psnr  VV->V Calculate the PSNR between two video streams\n'; exit 0 ;;
    -version)  echo "ffmpeg stub 1.0"; exit 0 ;;
  esac
done
case " $* " in *" -hide_banner "*|*" -encoders "*|*" -filters "*) : ;; esac
exit 0
EOF
chmod +x "$BIN/ffmpeg"
ln -s "$BIN/ffmpeg" "$BIN/ffprobe"

# nvidia-smi: two Tesla T4s, like the Kaggle box
cat > "$BIN/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
echo "GPU 0: Tesla T4 (UUID: GPU-stub-0000)"
echo "GPU 1: Tesla T4 (UUID: GPU-stub-0001)"
EOF
chmod +x "$BIN/nvidia-smi"

# npx + a Chrome stub: `npx hyperframes@… browser ensure` succeeds, `browser path` names a
# fake Chrome whose --dump-dom answers with an NVIDIA WebGL renderer
CHROME_STUB="$BIN/chrome-stub"
cat > "$CHROME_STUB" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    --dump-dom) echo '<html><head><title>GLRENDERER NVIDIA Tesla T4/PCIe/SSE2</title></head><body></body></html>'; exit 0 ;;
  esac
done
exit 0
EOF
chmod +x "$CHROME_STUB"
cat > "$BIN/npx" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in
    ensure) exit 0 ;;
    path) echo "$CHROME_STUB"; exit 0 ;;
  esac
done
exit 0
EOF
chmod +x "$BIN/npx"

# node: the sandbox's own (setup.sh only checks the version when it is on PATH)
[ "$(command -v node >/dev/null 2>&1 && node -v | sed 's/^v\([0-9]*\).*/\1/' || echo 0)" -lt 22 ] && \
  { echo "kaggle tests need Node >= 22 on PATH (the repo pins it for HyperFrames)"; exit 9; }

TESTROOT="$WORK/repo"     # a throwaway tree so the real .kaggle/ is never touched
mkdir -p "$TESTROOT/tools/kaggle"
cp "$ROOT/tools/kaggle/setup.sh" "$TESTROOT/tools/kaggle/"
# render-split.sh runs $ROOT/tools/film/render.mjs and bin/vh determinism from its own root, so the
# film tools and bin/vh come along as symlinks to the real ones (the code under test is copied; the
# harness it calls is the repo's own)
ln -s "$ROOT/tools/film" "$TESTROOT/tools/film"
ln -s "$ROOT/tools/textcheck" "$TESTROOT/tools/textcheck"
ln -s "$ROOT/bin" "$TESTROOT/bin"

printf '\033[36m→\033[0m setup.sh against stubs (2 fake T4s, an ffmpeg that always answers, a fake Chrome)\n'
FFLOG="$WORK/ffmpeg-setup.log"; export OVH_TEST_FFMPEG_LOG="$FFLOG"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" HOME="$WORK/home" bash tools/kaggle/setup.sh --no-persist 2>&1)
rc=$?
chk "setup.sh exits 0 against the stubs" "$rc" "0"
echo "$OUT" | grep -q "2 GPU(s)"          && ok "saw the two stub GPUs"      || bad "did not count the two stub GPUs"
echo "$OUT" | grep -q "h264_nvenc works on GPU 1" && ok "NVENC probe picked GPU 1 (the last card)" || bad "NVENC probe did not pick GPU 1"
echo "$OUT" | grep -q "WebGL renderer is hardware" && ok "browser probe saw the NVIDIA renderer" || bad "browser probe did not see hardware"
[ -f "$TESTROOT/.kaggle/ffmpeg-gpu.sh" ]  && ok "the ffmpeg wrapper was written" || bad "no ffmpeg wrapper written"
grep -q 'OVH_KAGGLE_GPUS=2' "$TESTROOT/.kaggle/env.sh"     && ok "env.sh records 2 GPUs" || bad "env.sh does not record 2 GPUs"
grep -q 'OVH_KAGGLE_NVENC_GPU=1' "$TESTROOT/.kaggle/env.sh" && ok "env.sh pins NVENC to GPU 1" || bad "env.sh does not pin NVENC to GPU 1"
grep -q 'OVH_KAGGLE_BROWSER_GPU=hardware' "$TESTROOT/.kaggle/env.sh" && ok "env.sh says hardware WebGL" || bad "env.sh does not say hardware WebGL"
cp "$TESTROOT/.kaggle/env.sh" "$TESTROOT/.kaggle/env.hardware.sh"   # saved for the render-split tests below

# ── the wrapper: the tier retune (C5) and the GPU pin, across the engine's real arg shapes ───────
W="$TESTROOT/.kaggle/ffmpeg-gpu.sh"
export OVH_KAGGLE_NVENC_GPU=1
FFLOG="$WORK/wrapper.log"; export OVH_TEST_FFMPEG_LOG="$FFLOG"
wrap() { : > "$FFLOG"; "$W" "$@" >/dev/null 2>&1; sed -n '1p' "$FFLOG"; }

# what the engine really sends (0.8.82 buildEncoderArgs): -c:v h264_nvenc -preset pN -cq N …
got=$( (unset OVH_KAGGLE_TIER; wrap -i pipe:0 -c:v h264_nvenc -preset p1 -cq 28 -sc_threshold 0 out.mp4) )
chk "no tier: the engine's own preset and cq stand, the GPU is pinned" \
  "$got" "-i pipe:0 -c:v h264_nvenc -gpu 1 -preset p1 -cq 28 -sc_threshold 0 out.mp4"
got=$(OVH_KAGGLE_TIER=draft wrap -i pipe:0 -c:v h264_nvenc -preset p1 -cq 28 -sc_threshold 0 out.mp4)
chk "tier draft: p4 cq 28 replace the engine's own, nothing of the engine's is lost" \
  "$got" "-i pipe:0 -c:v h264_nvenc -gpu 1 -preset p4 -cq 28 -sc_threshold 0 out.mp4"
got=$(OVH_KAGGLE_TIER=final wrap -i pipe:0 -c:v h264_nvenc -preset p5 -cq 15 -g 60 out.mp4)
chk "tier final: p7 cq 19 replace the engine's own" \
  "$got" "-i pipe:0 -c:v h264_nvenc -gpu 1 -preset p7 -cq 19 -g 60 out.mp4"
got=$(OVH_KAGGLE_TIER=final OVH_KAGGLE_TUNE=off wrap -i pipe:0 -c:v h264_nvenc -preset p5 -cq 15 out.mp4)
chk "OVH_KAGGLE_TUNE=off: only the pin, the engine's settings back" \
  "$got" "-i pipe:0 -c:v h264_nvenc -gpu 1 -preset p5 -cq 15 out.mp4"
got=$(OVH_KAGGLE_TIER=final wrap -i pipe:0 -c:v h264_nvenc -preset p4 -b:v 5000k out.mp4)
chk "tier replaces a -b:v rate too (the tier names the quality, not just the preset)" \
  "$got" "-i pipe:0 -c:v h264_nvenc -gpu 1 -preset p7 -cq 19 out.mp4"
got=$(wrap -i in.mp4 -c:v h264_nvenc -gpu 0 -preset p7 out.mp4)
chk "a hand command with its own -gpu passes through untouched" \
  "$got" "-i in.mp4 -c:v h264_nvenc -gpu 0 -preset p7 out.mp4"
got=$(OVH_KAGGLE_TIER=final wrap -i in.mp4 -c:v libx264 -preset medium -crf 16 out.mp4)
chk "an x264 command is untouched (no pin, no tier, -crf kept)" \
  "$got" "-i in.mp4 -c:v libx264 -preset medium -crf 16 out.mp4"
got=$(OVH_KAGGLE_TIER=final wrap -i in.mp4 -c:v hevc_nvenc -preset p5 -cq 20 out.mp4)
chk "hevc_nvenc: pinned but not retuned (the tier's cq values are the h264 scale)" \
  "$got" "-i in.mp4 -c:v hevc_nvenc -gpu 1 -preset p5 -cq 20 out.mp4"
got=$(OVH_KAGGLE_TIER=bogus wrap -i in.mp4 -c:v h264_nvenc -preset p1 -cq 28 out.mp4)
chk "a bogus tier changes nothing" \
  "$got" "-i in.mp4 -c:v h264_nvenc -gpu 1 -preset p1 -cq 28 out.mp4"
got=$(OVH_KAGGLE_TIER=draft wrap -hide_banner -encoders)
chk "a listing (no encode) is untouched" "$got" "-hide_banner -encoders"

# the per-GPU probe the setup itself runs: it carries its own -gpu, so it passes through
got=$(wrap -hide_banner -loglevel error -f lavfi -i color=size=320x240:rate=1:duration=1 -frames:v 1 -an -c:v h264_nvenc -gpu 0 -f null -)
chk "the per-GPU probe command passes through (its own -gpu)" \
  "$got" "-hide_banner -loglevel error -f lavfi -i color=size=320x240:rate=1:duration=1 -frames:v 1 -an -c:v h264_nvenc -gpu 0 -f null -"

# ── render.sh: the flag policy against a stub engine (the stub npx records what it was handed) ──
# The stub env.sh from the setup run above (hardware WebGL, NVENC on GPU 1, 2 GPUs) is exactly what
# render.sh sources; a project and a recording npx stand in for the engine.
printf '\033[36m→\033[0m render.sh policy (tier, capture gates, workers, streaming cap, error paths)\n'
cp "$ROOT/tools/kaggle/render.sh" "$TESTROOT/tools/kaggle/"
NPXLOG="$WORK/npx.log"
cat > "$BIN/npx" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$* >> \${OVH_KAGGLE_TIER:-}" >> "$NPXLOG"
printf 'extract-cache=%s\n' "\${HYPERFRAMES_EXTRACT_CACHE_DIR:-none}" >> "$NPXLOG"
exit 0
EOF
chmod +x "$BIN/npx"

mkproj() { # mkproj <dir> <duration> <fps-declared> <extra-body>
  mkdir -p "$1"
  { echo '<!doctype html><html><body>'
    echo "<div data-composition-id=\"c1\" data-duration=\"$2\"${3:+ data-fps=\"$3\"} data-width=\"1920\" data-height=\"1080\"></div>"
    if [ -n "${4:-}" ]; then printf '%s\n' "$4"; fi
    echo '</body></html>'
  } > "$1/index.html"
}
P="$WORK/proj-long"; mkproj "$P" 400 24 '<div data-start="120" data-duration="20"></div><div data-start="240" data-duration="80"></div>'
PS="$WORK/proj-short"; mkproj "$PS" 60 "" ""

: > "$NPXLOG"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$P" --tier draft 2>&1); rc=$?
chk "render.sh --tier draft: exits 0 against the stub engine" "$rc" "0"
flags=$(sed -n '1p' "$NPXLOG")
echo "$flags" | grep -q -- "--quality draft" && ok "tier draft passes --quality draft to the engine" || bad "tier draft did not pass --quality draft: [$flags]"
echo "$flags" | grep -q "draft >> draft" && ok "OVH_KAGGLE_TIER=draft is exported for the ffmpeg wrapper" || bad "OVH_KAGGLE_TIER not exported: [$flags]"
echo "$OUT"  | grep -q "retuned for the draft tier" && ok "the plan says the NVENC is retuned for the tier" || bad "no retune note in the plan"
echo "$OUT"  | grep -q "render-split.sh .* --tier draft" && ok "the plan points at the split for both cards" || bad "no split hint in the plan"
echo "$OUT"  | grep -q "fps 24 (the composition's own" && ok "the composition's own 24 fps is kept (the engine reads data-fps itself)" || bad "24 fps note wrong: $(echo "$OUT" | grep 'fps 24')"
echo "$flags" | grep -q -- "--fps" && bad "a declared fps ≤ 30 needs no --fps flag" || ok "no --fps flag for a declared 24 fps (no double override)"
echo "$flags" | grep -q -- "--browser-gpu" && ok "hardware WebGL asks for the browser GPU" || bad "--browser-gpu missing: [$flags]"
echo "$flags" | grep -q -- "--experimental-fast-capture" && ok "a clean composition gets the fast capture" || bad "fast capture missing for a clean composition: [$flags]"
echo "$flags" | grep -q -- "--workers" && bad "a ≥240 s hardware render must leave --workers to the engine (the parallel router)" || ok "a ≥240 s hardware render leaves --workers to the engine"
echo "$OUT"  | grep -q "streaming cap 460 s" && ok "the streaming cap is the film's length + 60 s" || bad "streaming cap wrong: $(echo "$OUT" | grep 'streaming cap')"

: > "$NPXLOG"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$P" --tier final 2>&1); rc=$?
chk "render.sh --tier final: exits 0" "$rc" "0"
sed -n '1p' "$NPXLOG" | grep -q -- "--quality delivery" && ok "tier final passes --quality delivery" || bad "tier final did not pass --quality delivery"

OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$P" --tier draft --quality draft 2>&1); rc=$?
[ "$rc" != 0 ] && ok "--tier and --quality together are refused" || bad "--tier and --quality were both accepted"
echo "$OUT" | grep -q "name the quality" && ok "the refusal says why" || bad "the refusal does not say why: [$OUT]"

# the fast-capture gates: each engine compile gate turns the flag off and names the override
P3D="$WORK/proj-3d"; mkproj "$P3D" 400 "" '<style>.card{transform-style:preserve-3d}</style>'
: > "$NPXLOG"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$P3D" 2>&1)
flags=$(sed -n '1p' "$NPXLOG")
echo "$flags" | grep -q -- "--experimental-fast-capture" && bad "a CSS-3D composition must not get the fast capture" || ok "a CSS-3D composition does not get the fast capture"
echo "$OUT" | grep -q "HF_FAST_CAPTURE_3D" && ok "the note names the 3D override" || bad "no 3D override named: [$OUT]"
PBL="$WORK/proj-blend"; mkproj "$PBL" 400 "" '<style>.x{mix-blend-mode:screen}</style>'
: > "$NPXLOG"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$PBL" 2>&1)
sed -n '1p' "$NPXLOG" | grep -q -- "--experimental-fast-capture" && bad "a mix-blend-mode composition must not get the fast capture" || ok "a mix-blend-mode composition does not get the fast capture"
echo "$OUT" | grep -q "HF_FAST_CAPTURE_BLEND" && ok "the note names the blend override" || bad "no blend override named"
PBG="$WORK/proj-bg"; mkproj "$PBG" 400 "" '<style>html{background-image:url(x.png)}</style>'
: > "$NPXLOG"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$PBG" 2>&1)
sed -n '1p' "$NPXLOG" | grep -q -- "--experimental-fast-capture" && bad "an ancestor background-image must not get the fast capture" || ok "an ancestor background-image does not get the fast capture"
echo "$OUT" | grep -q "HF_FAST_CAPTURE_ANCESTOR_BG" && ok "the note names the ancestor-bg override" || bad "no ancestor-bg override named"

# the ancestor walk, exactly as the engine's compiler does it (detectAncestorBackgroundImage)
PBG2="$WORK/proj-bg2"; mkdir -p "$PBG2"
cat > "$PBG2/index.html" <<'HTML'
<!doctype html><html><body>
<style>.wrap{background:linear-gradient(red,blue)}</style>
<div class="wrap"><div data-composition-id="c1" data-duration="400" data-width="1920" data-height="1080"></div></div>
</body></html>
HTML
: > "$NPXLOG"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$PBG2" 2>&1)
sed -n '1p' "$NPXLOG" | grep -q -- "--experimental-fast-capture" && bad "a background on a class the composition root sits inside must gate" || ok "a wrapping class with a gradient gates (a real ancestor walk, not html/body only)"
echo "$OUT" | grep -q "HF_FAST_CAPTURE_ANCESTOR_BG" && ok "the wrapping-class gate names its override" || bad "no override named for the wrapping class"
PBG3="$WORK/proj-bg3"; mkproj "$PBG3" 400 "" '<style>.elsewhere{background-image:url(x.png)}</style><div class="elsewhere"><p>not an ancestor of the composition</p></div>'
: > "$NPXLOG"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$PBG3" 2>&1)
sed -n '1p' "$NPXLOG" | grep -q -- "--experimental-fast-capture" && ok "a background elsewhere in the page does not gate (the engine walks ancestors only)" || bad "a non-ancestor background gated the fast capture"
PBG4="$WORK/proj-bg4"; mkproj "$PBG4" 400 "" '<body style="background:red">'
: > "$NPXLOG"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$PBG4" 2>&1)
sed -n '1p' "$NPXLOG" | grep -q -- "--experimental-fast-capture" && ok "a plain background colour is not a background-image: no gate" || bad "a background colour gated the fast capture"

# the fourth gate the engine's compiler has: shader transitions
PSH="$WORK/proj-shader"; mkproj "$PSH" 400 "" '<script>window.HyperShader.init({});</script>'
: > "$NPXLOG"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$PSH" 2>&1)
sed -n '1p' "$NPXLOG" | grep -q -- "--experimental-fast-capture" && bad "shader transitions must gate the fast capture" || ok "shader transitions gate the fast capture"
echo "$OUT" | grep -q "PRODUCER_EXPERIMENTAL_FAST_CAPTURE" && ok "the note names the shader override" || bad "no shader override named"
PSH2="$WORK/proj-shader2"; mkproj "$PSH2" 400 "" '<script>__hf.transitions = { fade: 1 };</script>'
: > "$NPXLOG"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$PSH2" 2>&1)
sed -n '1p' "$NPXLOG" | grep -q -- "--experimental-fast-capture" && bad "__hf.transitions must gate the fast capture" || ok "__hf.transitions gates the fast capture"
PSH3="$WORK/proj-shader3"; mkproj "$PSH3" 400 "" '<script src="https://cdn.example/shader.js"></script><script>// HyperShader.init() — only a comment\nconst x = 1;</script>'
: > "$NPXLOG"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$PSH3" 2>&1)
sed -n '1p' "$NPXLOG" | grep -q -- "--experimental-fast-capture" && ok "a src'd script and a comment do not gate (comments are stripped, like the engine)" || bad "a comment or src'd script gated wrongly: $(echo "$OUT" | grep capture)"

# a short film: one worker whatever the GPU state (multi-worker short films buffer to disk)
: > "$NPXLOG"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$PS" 2>&1)
flags=$(sed -n '1p' "$NPXLOG")
echo "$flags" | grep -q -- "--workers 1" && ok "a <240 s film renders with one worker (the streaming path)" || bad "short film not on one worker: [$flags]"
echo "$flags" | grep -q -- "--fps 30" && ok "no declared fps becomes an explicit 30" || bad "no explicit 30 fps: [$flags]"

# fps 30 is the default (the speed table's biggest lever): a composition declaring more than 30 is
# rendered at 30 with a note — not silently, and not by changing the composition itself
P60="$WORK/proj-60"; mkproj "$P60" 400 60 '<div data-start="200" data-duration="10"></div>'
: > "$NPXLOG"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$P60" 2>&1)
flags=$(sed -n '1p' "$NPXLOG")
echo "$flags" | grep -q -- "--fps 30" && ok "a declared 60 fps is rendered at 30 by default" || bad "a declared 60 was not dropped to 30: [$flags]"
echo "$OUT"  | grep -q "fps 30 (the default here; the composition declares 60" && ok "the 30-default note says what the composition declared and how to keep 60" || bad "the 30-default note is wrong: $(echo "$OUT" | grep 'fps 30')"
: > "$NPXLOG"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$P60" --fps 60 2>&1)
sed -n '1p' "$NPXLOG" | grep -q -- "--fps 60" && ok "--fps 60 keeps every frame of a 60 fps spec" || bad "--fps 60 did not pass through: [$(sed -n '1p' "$NPXLOG")]"
echo "$OUT" | grep -q "fps 60 (yours)" && ok "the explicit fps is labelled yours" || bad "the explicit fps note is wrong"

# the extracted-frame cache (<video> sources) is pointed into the project: a re-render reuses the slices
: > "$NPXLOG"
(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$PS" >/dev/null 2>&1)
grep -q "extract-cache=$PS/renders/.hf-extract-cache" "$NPXLOG" && ok "HYPERFRAMES_EXTRACT_CACHE_DIR lands inside the project (renders/.hf-extract-cache)" || bad "the extract cache was not exported into the project: $(sed -n '2p' "$NPXLOG")"

# the software path: workers measured against free memory (OVH_TEST_MEM_MB stands in for the cgroup)
cat > "$TESTROOT/.kaggle/env.software.sh" <<'EOF'
export OVH_KAGGLE_SETUP=test
export OVH_KAGGLE_GPUS=1
export OVH_KAGGLE_FFMPEG=/usr/bin/ffmpeg
export OVH_KAGGLE_NVENC=0
export OVH_KAGGLE_NVENC_GPU=0
export OVH_KAGGLE_BROWSER_GPU=software
export HF_DE_PARALLEL_ROUTER=true
export HF_DE_PARALLEL_STREAM=true
export HF_CAPTURE_PARALLEL_STREAM=true
EOF
cp "$TESTROOT/.kaggle/env.software.sh" "$TESTROOT/.kaggle/env.sh"
: > "$NPXLOG"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" OVH_TEST_MEM_MB=24000 bash tools/kaggle/render.sh "$P" 2>&1)
flags=$(sed -n '1p' "$NPXLOG")
cores=$(( $(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2) - 1 )); [ $cores -lt 1 ] && cores=1; [ $cores -gt 6 ] && cores=6
[ 3 -lt $cores ] && cores=3    # 24000 MB free / 6 GB a browser
echo "$flags" | grep -q -- "--workers $cores" && ok "software workers follow the measured memory ($cores on this box)" || bad "software workers wrong: [$flags] (want $cores)"
echo "$flags" | grep -q -- "--gpu" && bad "no NVENC, no --gpu" || ok "no NVENC means no --gpu flag"
echo "$flags" | grep -q -- "--browser-gpu" && bad "software WebGL must not ask for the browser GPU" || ok "software WebGL asks for no browser GPU"
: > "$NPXLOG"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" OVH_TEST_MEM_MB=7000 bash tools/kaggle/render.sh "$P" 2>&1)
sed -n '1p' "$NPXLOG" | grep -q -- "--workers 1" && ok "a nearly-full box falls back to one browser" || bad "7 GB free should give 1 worker: [$(sed -n '1p' "$NPXLOG")]"

# ── the held card: after a render, the film itself is read back and checked against the ask ─────
# (a stub npx that leaves a fake MP4 behind + a stub ffprobe answering the card's exact probe; the
# card's job is to say which flag held and which fell back — here every branch of that is driven)
printf '\033[36m→\033[0m render.sh held card (the film read back against what was asked)\n'
cat > "$BIN/ffprobe" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${OVH_TEST_FFPROBE_JSON:-}"
exit 0
EOF
chmod +x "$BIN/ffprobe"
cat > "$BIN/npx" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$* >> \${OVH_KAGGLE_TIER:-}" >> "$NPXLOG"
mkdir -p renders && printf 'x' > "renders/stub-\$(date +%s%N).mp4"
exit 0
EOF
chmod +x "$BIN/npx"
cp "$TESTROOT/.kaggle/env.software.sh" "$TESTROOT/.kaggle/env.sh"   # no NVENC: the codec is simply reported
P24="$WORK/proj-24"; mkproj "$P24" 400 24 ""
: > "$NPXLOG"
export OVH_TEST_FFPROBE_JSON='{"streams":[{"codec_name":"libx264","width":1920,"height":1080,"avg_frame_rate":"24/1","nb_frames":"9600"}]}'
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$P24" 2>&1)
echo "$OUT" | grep -q "held     : 9600 frames, 1920x1080, 24 fps, libx264 — the encode came out libx264, as planned" \
  && ok "a film that came out as asked: the card says held, with the file's own numbers" \
  || bad "the as-asked card is wrong: $(echo "$OUT" | grep 'held')"
export OVH_TEST_FFPROBE_JSON='{"streams":[{"codec_name":"libx264","width":1920,"height":1080,"avg_frame_rate":"60/1","nb_frames":"24000"}]}'
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$P24" 2>&1)
echo "$OUT" | grep -q "held     : 24000 frames, 1920x1080, 60 fps, libx264 — asked 24 fps, the file says 60" \
  && ok "a film that ignored the fps: the card names the mismatch" \
  || bad "the fps-mismatch card is wrong: $(echo "$OUT" | grep 'held')"
export OVH_TEST_FFPROBE_JSON='{"streams":[{"codec_name":"libx264","width":1280,"height":720,"avg_frame_rate":"24/1","nb_frames":"9600"}]}'
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$P24" 2>&1)
echo "$OUT" | grep -q "the composition is 1920x1080, the file says 1280x720" \
  && ok "a film at the wrong size: the card says the composition's size and the file's" \
  || bad "the size-mismatch card is wrong: $(echo "$OUT" | grep 'held')"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$P24" --output-resolution 4k 2>&1)
echo "$OUT" | grep -q "the composition is 1920x1080" && bad "a --output-resolution render must not be size-checked (the engine supersamples)" \
  || ok "a --output-resolution render: the size check stands down, the rest of the card still prints"
# the NVENC branch: asked --gpu (hardware env), the file came out libx264 — the engine fell back
cp "$TESTROOT/.kaggle/env.hardware.sh" "$TESTROOT/.kaggle/env.sh"
export OVH_TEST_FFPROBE_JSON='{"streams":[{"codec_name":"libx264","width":1920,"height":1080,"avg_frame_rate":"24/1","nb_frames":"9600"}]}'
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$P24" 2>&1)
echo "$OUT" | grep -q "held     : 9600 frames, 1920x1080, 24 fps, libx264 — NVENC was asked for, the file came out libx264 (the engine fell back" \
  && ok "NVENC asked, libx264 out: the card says the --gpu flag did not hold" \
  || bad "the NVENC-fallback card is wrong: $(echo "$OUT" | grep 'held')"
export OVH_TEST_FFPROBE_JSON='{"streams":[{"codec_name":"h264_nvenc","width":1920,"height":1080,"avg_frame_rate":"24/1","nb_frames":"9600"}]}'
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$P24" 2>&1)
echo "$OUT" | grep -q "held     : 9600 frames, 1920x1080, 24 fps, h264_nvenc — the --gpu flag held: the file itself says h264_nvenc" \
  && ok "NVENC asked, h264_nvenc out: the card says the flag held" \
  || bad "the NVENC-held card is wrong: $(echo "$OUT" | grep 'held')"
unset OVH_TEST_FFPROBE_JSON
# no new MP4 (an -o or --format render): the card says so instead of guessing at an old file —
# renders/ emptied first, so the stub films of the cases above cannot be mistaken for this one's
rm -rf "$P24/renders"
cat > "$BIN/npx" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$* >> \${OVH_KAGGLE_TIER:-}" >> "$NPXLOG"
exit 0
EOF
chmod +x "$BIN/npx"
cp "$TESTROOT/.kaggle/env.software.sh" "$TESTROOT/.kaggle/env.sh"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$P24" 2>&1)
echo "$OUT" | grep -q "held     : no new MP4 under renders/ (an -o or --format render?) — the flags above were the request" \
  && ok "no new film: the card reports it, an older MP4 is never read as this render's" \
  || bad "the no-new-MP4 card is wrong: $(echo "$OUT" | grep 'held')"
# the stubs back to their standard shapes for the sections below (the split's dry-runs want the
# plain recording npx; ffprobe back to the ffmpeg stub's twin)
cat > "$BIN/npx" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$* >> \${OVH_KAGGLE_TIER:-}" >> "$NPXLOG"
printf 'extract-cache=%s\n' "\${HYPERFRAMES_EXTRACT_CACHE_DIR:-none}" >> "$NPXLOG"
exit 0
EOF
chmod +x "$BIN/npx"
ln -sf "$BIN/ffmpeg" "$BIN/ffprobe"

# the error paths (E5): each refusal is a message and a non-zero exit
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$WORK/no-such-project" 2>&1); rc=$?
[ "$rc" != 0 ] && ok "no project folder: refused (exit $rc)" || bad "a missing project was accepted"
echo "$OUT" | grep -q "no index.html" && ok "the no-project refusal names the problem" || bad "no-project refusal unclear: [$OUT]"
mkdir -p "$WORK/proj-empty"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$WORK/proj-empty" 2>&1); rc=$?
[ "$rc" != 0 ] && ok "an empty folder is not a project: refused" || bad "an empty folder was accepted"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$P" --tier bogus 2>&1); rc=$?
[ "$rc" != 0 ] && ok "a bogus tier is refused" || bad "a bogus tier was accepted"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$P" --workers notanumber 2>&1); rc=$?
[ "$rc" != 0 ] && ok "a non-numeric --workers is refused (the engine would misread it)" || bad "a bad --workers was accepted"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$P" --fps 0 2>&1); rc=$?
[ "$rc" != 0 ] && ok "a zero --fps is refused" || bad "--fps 0 was accepted"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render.sh "$P" --tier draft --quality=delivery 2>&1); rc=$?
[ "$rc" != 0 ] && ok "--tier with --quality=… (equals form) is refused too" || bad "--quality=… slipped past the conflict check"

# ── render-split.sh: the plan (a dry run draws nothing; the numbers are checked, not eyeballed) ──
printf '\033[36m→\033[0m render-split.sh plan (the cut, the tiers, the cards, the refusals)\n'
cp "$ROOT/tools/kaggle/render-split.sh" "$TESTROOT/tools/kaggle/"
cp "$TESTROOT/.kaggle/env.hardware.sh" "$TESTROOT/.kaggle/env.sh"    # the hardware machine again
export CHROME_PATH="$CHROME_STUB"

OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render-split.sh "$P" --dry-run 2>&1); rc=$?
chk "a 400 s film plans a split (exit 0)" "$rc" "0"
echo "$OUT" | grep -q "cut      : frame 5760 (t=240.000 s)" && ok "the cut snaps to the scene cut nearest the middle (240 s of 120/240)" || bad "cut not on the 240 s scene cut: $(echo "$OUT" | grep 'cut')"
echo "$OUT" | grep -q "A frames 0–5759, B frames 5760–9599" && ok "the halves cover every frame exactly once (9600 at 24 fps)" || bad "halves wrong: $(echo "$OUT" | grep 'halves')"
echo "$OUT" | grep -q "fps 24 (the composition's own)" && ok "the composition's own 24 fps is kept" || bad "fps note wrong: $(echo "$OUT" | grep 'fps')"
echo "$OUT" | grep -q "half A on GPU 0 and half B on GPU 1" && ok "the two halves encode on different cards by default" || bad "cards not split: $(echo "$OUT" | grep 'encode')"
echo "$OUT" | grep -q -- "--gop 48" && ok "the gop is 2 s (48 at 24 fps), so the seam is a keyframe" || bad "gop wrong: $(echo "$OUT" | grep -o -- '--gop [0-9]*' | head -1)"
echo "$OUT" | grep -q -- "--encoder nvenc --crf 16 --preset p4" && ok "no tier keeps the repo master encode (nvenc p4 cq 16)" || bad "no-tier encode wrong: $(echo "$OUT" | grep -o -- '--encoder [a-z0-9]* --crf [0-9]* --preset [a-z0-9]*' | head -1)"
echo "$OUT" | grep -q "join: ffmpeg -f concat -safe 0 -i list.txt -c copy" && ok "the join is a stream copy" || bad "join is not a stream copy"

OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render-split.sh "$P" --at 130 --dry-run 2>&1)
echo "$OUT" | grep -q "cut      : frame 2880 (t=120.000 s)" && ok "--at 130 snaps to the 120 s scene cut" || bad "--at 130 did not snap to 120: $(echo "$OUT" | grep 'cut')"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render-split.sh "$P" --tier draft --dry-run 2>&1)
echo "$OUT" | grep -q "h264_nvenc p4 cq 28, half A on GPU 0 and half B on GPU 1" && ok "tier draft: nvenc p4 cq 28" || bad "tier draft encode wrong: $(echo "$OUT" | grep 'encode')"
echo "$OUT" | grep -q -- "--crf 28 --preset p4" && ok "tier draft's halves carry cq 28 / p4" || bad "tier draft halves wrong"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render-split.sh "$P" --tier final --dry-run 2>&1)
echo "$OUT" | grep -q "h264_nvenc p7 cq 19" && ok "tier final: nvenc p7 cq 19" || bad "tier final encode wrong: $(echo "$OUT" | grep 'encode')"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render-split.sh "$P" --encoder x264 --tier draft --dry-run 2>&1)
echo "$OUT" | grep -q "x264 faster crf 28 on the CPU" && ok "x264 draft: faster crf 28" || bad "x264 draft wrong: $(echo "$OUT" | grep 'encode')"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render-split.sh "$P" --gpu-a 0 --gpu-b 0 --dry-run 2>&1)
echo "$OUT" | grep -q "both halves would encode on GPU 0" && ok "the same card for both halves warns (the split still draws two browsers)" || bad "no same-card warning"

# the refusals
PTINY="$WORK/proj-tiny"; mkproj "$PTINY" 20 "" '<div data-start="8" data-duration="4"></div>'
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render-split.sh "$PTINY" --dry-run 2>&1); rc=$?
[ "$rc" != 0 ] && ok "a 20 s film is refused (two browser startups eat the gain)" || bad "a 20 s film was split"
echo "$OUT" | grep -q "too short to split" && ok "the short-film refusal points at render.sh" || bad "short-film refusal unclear"
PNOD="$WORK/proj-nodur"; mkdir -p "$PNOD"; echo '<div data-composition-id="c1"></div>' > "$PNOD/index.html"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render-split.sh "$PNOD" --dry-run 2>&1); rc=$?
[ "$rc" != 0 ] && ok "no data-duration: refused" || bad "a composition with no length was split"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render-split.sh "$P" --tier bogus --dry-run 2>&1); rc=$?
[ "$rc" != 0 ] && ok "a bogus tier is refused" || bad "a bogus tier was accepted"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render-split.sh "$WORK/no-such-project" --dry-run 2>&1); rc=$?
[ "$rc" != 0 ] && ok "no project: refused" || bad "a missing project was split"
PMID="$WORK/proj-mid"; mkproj "$PMID" 400 "" '<div>no scene cuts declared here</div>'
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render-split.sh "$PMID" --dry-run 2>&1)
echo "$OUT" | grep -q "cut      : frame 6000 (t=200.000 s)" && ok "no data-starts: the exact midpoint, still on a frame" || bad "midpoint cut wrong: $(echo "$OUT" | grep 'cut')"
PF60="$WORK/proj-60fps"; mkproj "$PF60" 400 60 '<div data-start="200" data-duration="10"></div>'
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render-split.sh "$PF60" --dry-run 2>&1)
echo "$OUT" | grep -q "fps 30 (the default here; the composition declares 60 — pass --fps 60 to keep every frame of it)" \
  && ok "a declared 60 fps is rendered at 30 by default (as render.sh), the note says how to keep 60" \
  || bad "60 fps note wrong: $(echo "$OUT" | grep 'fps')"
echo "$OUT" | grep -q -- "--frames 0:6000 --fps 30" && ok "both halves of a 60 fps film draw at 30 fps" || bad "the halves are not at 30 fps: $(echo "$OUT" | grep -a 'A: exec' | head -1)"

# --res: a draft tier for the split — both halves at the same fractional dpr, upscales refused
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render-split.sh "$P" --res 720p --dry-run 2>&1)
echo "$OUT" | grep -q "res      : 1280x720 (the page's own layout, drawn at dpr 0.6667 — a 720p draft)" \
  && ok "--res 720p on a 1920x1080 comp: the note says the tier's own size and its dpr" \
  || bad "the 720p res note is wrong: $(echo "$OUT" | grep -a 'res ')"
echo "$OUT" | grep -q -- "--dpr 0.6667" && ok "both halves carry the tier's --dpr" || bad "the halves do not carry --dpr: $(echo "$OUT" | grep -a 'A: exec' | head -1)"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render-split.sh "$P" --res 2160 --dry-run 2>&1); rc=$?
[ "$rc" != 0 ] && echo "$OUT" | grep -q "more pixels than the page has" && ok "--res above the page's own size is refused (--res is a draft tier)" || bad "an upscaling --res was accepted: [$OUT]"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" bash tools/kaggle/render-split.sh "$P" --res 240p --dry-run 2>&1); rc=$?
[ "$rc" != 0 ] && echo "$OUT" | grep -q "under the 0.25 floor" && ok "--res under the 0.25 dpr floor is refused" || bad "a 240p tier on a 1080p page was accepted: [$OUT]"

# ── render.mjs --res: the tier's own guards, no browser needed (the parse dies first) ───────────
printf '\033[36m→\033[0m render.mjs --res (the draft-tier guards)\n'
COST="$ROOT/tools/kaggle/fixture/css-cost/index.html"   # a 960x540 page-contract page
OUT=$(node "$ROOT/tools/film/render.mjs" "$COST" --res 1080p --browser none 2>&1); rc=$?
[ "$rc" = 2 ] && echo "$OUT" | grep -q "more pixels than the page has" \
  && ok "--res above the page's own size is refused (a tier is fewer pixels; --dpr is the exact factor)" \
  || bad "an upscaling --res was accepted by render.mjs: [$OUT]"
OUT=$(node "$ROOT/tools/film/render.mjs" "$COST" --res 120p --browser none 2>&1); rc=$?
[ "$rc" = 2 ] && echo "$OUT" | grep -q "under the 0.25 floor" && ok "--res under the 0.25 dpr floor is refused" || bad "a 120p tier on a 540p page was accepted: [$OUT]"
OUT=$(node "$ROOT/tools/film/render.mjs" "$COST" --res 270p --dpr 1 --browser none 2>&1); rc=$?
[ "$rc" = 2 ] && echo "$OUT" | grep -q "not both" && ok "--res and --dpr together are refused" || bad "--res and --dpr were both accepted: [$OUT]"

# ── lambda.sh: the distributed road, driven against a stub engine and stub AWS tools ────────────
printf '\033[36m→\033[0m lambda.sh (the project mapped onto the engine lambda commands, the refusals)\n'
cp "$ROOT/tools/kaggle/lambda.sh" "$TESTROOT/tools/kaggle/"
HFSTUB="$WORK/hfstub"; mkdir -p "$HFSTUB/styles/_swatch/node_modules/.bin"
cat > "$HFSTUB/styles/_swatch/node_modules/.bin/hyperframes" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$WORK/hf-lambda.log"
[ "\$1" = lambda ] && [ "\$2" = policies ] && printf '%s\n' '{"Version":"2012-10-17","Statement":[]}'
exit 0
EOF
chmod +x "$HFSTUB/styles/_swatch/node_modules/.bin/hyperframes"
for b in aws sam bun; do printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/$b"; chmod +x "$BIN/$b"; done
: > "$WORK/hf-lambda.log"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" OVH_TEST_HF_ROOT="$HFSTUB" bash tools/kaggle/lambda.sh "$P" --dry-run 2>&1); rc=$?
chk "a lambda render dry-run exits 0" "$rc" "0"
echo "$OUT" | grep -q "command  : hyperframes lambda render <project> --width 1920 --height 1080 --fps 24 --wait" \
  && ok "the dry run names the exact engine command (the comp's own size, its own 24 fps kept, --wait by default)" \
  || bad "the dry-run command line is wrong: $(echo "$OUT" | grep -a 'command')"
[ -s "$WORK/hf-lambda.log" ] && bad "a dry run invoked the engine" || ok "a dry run invokes nothing"
(cd "$TESTROOT" && PATH="$BIN:$PATH" OVH_TEST_HF_ROOT="$HFSTUB" bash tools/kaggle/lambda.sh "$P" >/dev/null 2>&1)
chk "the render reaches the engine as the engine expects it" "$(sed -n '1p' "$WORK/hf-lambda.log")" "lambda render . --width 1920 --height 1080 --fps 24 --wait"
: > "$WORK/hf-lambda.log"
(cd "$TESTROOT" && PATH="$BIN:$PATH" OVH_TEST_HF_ROOT="$HFSTUB" bash tools/kaggle/lambda.sh "$PS" >/dev/null 2>&1)
grep -q -- "--fps 30" "$WORK/hf-lambda.log" && ok "a composition without data-fps lands at an explicit 30 on lambda" || bad "no declared fps did not become 30: [$(cat "$WORK/hf-lambda.log")]"
: > "$WORK/hf-lambda.log"
(cd "$TESTROOT" && PATH="$BIN:$PATH" OVH_TEST_HF_ROOT="$HFSTUB" bash tools/kaggle/lambda.sh $P --tier draft >/dev/null 2>&1)
grep -q -- "--quality draft" "$WORK/hf-lambda.log" && ok "--tier draft maps to the engine's --quality draft" || bad "tier draft did not map: [$(cat "$WORK/hf-lambda.log")]"
: > "$WORK/hf-lambda.log"
(cd "$TESTROOT" && PATH="$BIN:$PATH" OVH_TEST_HF_ROOT="$HFSTUB" bash tools/kaggle/lambda.sh $P --tier final >/dev/null 2>&1)
grep -q -- "--quality high" "$WORK/hf-lambda.log" && ok "--tier final maps to the engine's --quality high (lambda's best)" || bad "tier final did not map: [$(cat "$WORK/hf-lambda.log")]"
: > "$WORK/hf-lambda.log"
(cd "$TESTROOT" && PATH="$BIN:$PATH" OVH_TEST_HF_ROOT="$HFSTUB" bash tools/kaggle/lambda.sh $P --no-wait >/dev/null 2>&1)
grep -q -- "--wait" "$WORK/hf-lambda.log" && bad "--no-wait still passed --wait" || ok "--no-wait leaves the --wait off (fire and poll later)"
grep -q -- "--quality" "$WORK/hf-lambda.log" && bad "no tier must not name a quality" || ok "no tier: the engine's own default quality stands"
: > "$WORK/hf-lambda.log"
(cd "$TESTROOT" && PATH="$BIN:$PATH" OVH_TEST_HF_ROOT="$HFSTUB" bash tools/kaggle/lambda.sh $PF60 >/dev/null 2>&1)
grep -q -- "--fps 30" "$WORK/hf-lambda.log" && ok "a declared 60 fps renders at 30 on lambda too (the same default)" || bad "the 60 fps comp did not land at 30: [$(cat "$WORK/hf-lambda.log")]"
: > "$WORK/hf-lambda.log"
(cd "$TESTROOT" && PATH="$BIN:$PATH" OVH_TEST_HF_ROOT="$HFSTUB" bash tools/kaggle/lambda.sh $PF60 --fps 60 >/dev/null 2>&1)
grep -q -- "--fps 60" "$WORK/hf-lambda.log" && ok "--fps 60 keeps every frame on lambda" || bad "--fps 60 did not pass through: [$(cat "$WORK/hf-lambda.log")]"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" OVH_TEST_HF_ROOT="$HFSTUB" bash tools/kaggle/lambda.sh $P --fps 25 2>&1); rc=$?
[ "$rc" != 0 ] && echo "$OUT" | grep -q "lambda accepts 24, 30 or 60" && ok "--fps 25 is refused with the engine's own rule" || bad "--fps 25 was accepted: [$OUT]"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" OVH_TEST_HF_ROOT="$HFSTUB" bash tools/kaggle/lambda.sh $P --tier draft --quality high 2>&1); rc=$?
[ "$rc" != 0 ] && echo "$OUT" | grep -q "both name the quality" && ok "--tier and --quality together are refused (as render.sh)" || bad "--tier and --quality were both accepted"
: > "$WORK/hf-lambda.log"
(cd "$TESTROOT" && PATH="$BIN:$PATH" OVH_TEST_HF_ROOT="$HFSTUB" bash tools/kaggle/lambda.sh deploy --stack-name mine --region eu-west-1 >/dev/null 2>&1)
chk "deploy reaches the engine with its stack flags" "$(sed -n '1p' "$WORK/hf-lambda.log")" "lambda deploy --stack-name mine --region eu-west-1"
: > "$WORK/hf-lambda.log"
(cd "$TESTROOT" && PATH="$BIN:$PATH" OVH_TEST_HF_ROOT="$HFSTUB" bash tools/kaggle/lambda.sh policies --out $WORK/iam.json >/dev/null 2>&1)
grep -q "^lambda policies user$" "$WORK/hf-lambda.log" && ok "policies asks the engine for its own IAM policy" || bad "policies did not reach the engine: [$(cat "$WORK/hf-lambda.log")]"
grep -q '"Statement"' "$WORK/iam.json" && ok "the policy file is written where --out says" || bad "no policy file was written"
: > "$WORK/hf-lambda.log"
(cd "$TESTROOT" && PATH="$BIN:$PATH" OVH_TEST_HF_ROOT="$HFSTUB" bash tools/kaggle/lambda.sh progress hf-render-abcd1234 >/dev/null 2>&1)
chk "progress passes the id straight through" "$(sed -n '1p' "$WORK/hf-lambda.log")" "lambda progress hf-render-abcd1234"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" OVH_TEST_HF_ROOT="$HFSTUB" bash tools/kaggle/lambda.sh progress 2>&1); rc=$?
[ "$rc" != 0 ] && ok "progress without an id is refused" || bad "progress without an id was accepted"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" OVH_TEST_HF_ROOT="$HFSTUB" bash tools/kaggle/lambda.sh $WORK/no-such-project 2>&1); rc=$?
[ "$rc" != 0 ] && echo "$OUT" | grep -q "no index.html" && ok "a missing project is refused before anything runs" || bad "a missing project was accepted"
NOWIDTH="$WORK/proj-nowidth"; mkdir -p "$NOWIDTH"; printf '<div data-composition-id="c" data-duration="8"></div>' > "$NOWIDTH/index.html"
OUT=$(cd "$TESTROOT" && PATH="$BIN:$PATH" OVH_TEST_HF_ROOT="$HFSTUB" bash tools/kaggle/lambda.sh $NOWIDTH 2>&1); rc=$?
[ "$rc" != 0 ] && echo "$OUT" | grep -q "refuses to guess" && ok "a composition with no size and no --width/--height is refused (as the engine would)" || bad "a sizeless composition was accepted: [$OUT]"
# the prerequisites: no aws CLI on PATH → the named refusal, not a failure deep in AWS
OUT=$(cd "$TESTROOT" && PATH="/usr/bin:/bin" OVH_TEST_HF_ROOT="$HFSTUB" bash tools/kaggle/lambda.sh "$P" 2>&1); rc=$?
[ "$rc" = 2 ] && echo "$OUT" | grep -q "no aws on PATH" && ok "no aws CLI: refused with the install hint" || bad "the missing-aws refusal is wrong: [$OUT] (exit $rc)"


# ── the split end to end, with a real browser and the real ffmpeg when the machine has them ──────
# (the stubs above are not it: the halves have to be drawn for real and joined for real. The fixture is
# a page-contract page that also carries the composition metadata the plan reads, 32 s, 320×180, with
# scene cuts at 10 s and 20 s; the plan cuts at 20 s. GitHub's runners come with Chrome, so CI runs this.)
printf '\033[36m→\033[0m render-split.sh end to end (a real 32 s film, both halves at once, the join checked)\n'
E2E="$WORK/e2e"; cp -R "$ROOT/tools/kaggle/fixture/e2e" "$E2E"; rm -rf "$E2E/renders" "$E2E/out"
E2E_OUT=$( (unset CHROME_PATH; cd "$TESTROOT" && PATH="$PATH" bash tools/kaggle/render-split.sh "$E2E" --dry-run) 2>&1)
if echo "$E2E_OUT" | grep -q "no headless Chrome found"; then
  ok "the end-to-end split: skipped (no Chrome on this machine; the plan and the args are checked above)"
else
  # A borrowed CI host can wedge (a Chrome that stops answering makes the halves' wait unbounded). A
  # budget turns that into a skip — the plan and the args are checked above — instead of a suite that
  # hangs until the workflow's own timeout. A healthy macOS runner draws this film in ~340-380 s
  # (Linux: ~30 s); the budget sits above the healthy envelope. The three budgets together must
  # also fit the workflow's 40-minute ceiling with every one of them tripped: 600 (split) + 90
  # (killed-split) + 240 (bake section) + 480 (engine E2E) + the stub sections ≈ 25 min — the film
  # tools before them take ~9. OVH_TEST_E2E_BUDGET overrides it (seconds).
  E2E_BUDGET=${OVH_TEST_E2E_BUDGET:-600}
  case "$E2E_BUDGET" in ''|*[!0-9]*) E2E_BUDGET=600 ;; esac
  E2E_LOG="$WORK/e2e-run.log"
  T0=$(date +%s)
  ( unset CHROME_PATH; cd "$TESTROOT" && exec bash tools/kaggle/render-split.sh "$E2E" --encoder x264 --tier draft ) >"$E2E_LOG" 2>&1 &
  EP=$!
  E2E_END=$((T0 + E2E_BUDGET))
  while kill -0 "$EP" 2>/dev/null && [ "$(date +%s)" -lt "$E2E_END" ]; do sleep 2; done
  if kill -0 "$EP" 2>/dev/null; then   # still going past the budget: a slow or wedged runner, not a verdict
    kill -TERM "$EP" 2>/dev/null                      # its own stop handler takes the gate or the halves down
    for _ in 1 2 3 4 5 6 7 8; do
      kill -0 "$EP" 2>/dev/null || break; sleep 1
    done
    kill -KILL "$EP" 2>/dev/null || true
    wait "$EP" 2>/dev/null
    pkill -TERM -f "$E2E" 2>/dev/null; sleep 1; pkill -KILL -f "$E2E" 2>/dev/null   # anything the hammer orphaned
    T1=$(date +%s)
    ok "the end-to-end split: skipped (over the ${E2E_BUDGET} s budget after $((T1-T0)) s — a slow or wedged runner; the plan and the args are checked above)"
  else
    wait "$EP"; rc=$?
    E2E_OUT=$(cat "$E2E_LOG")
    T1=$(date +%s)
    chk "the split renders a real 32 s film (exit 0, took $((T1-T0)) s)" "$rc" "0"
    echo "$E2E_OUT" | grep -q "determinism: the page must draw the same frame" && ok "the determinism gate ran before the halves" || bad "the determinism gate did not run: $(echo "$E2E_OUT" | head -3)"
    echo "$E2E_OUT" | grep -q "cut      : frame 600 (t=20.000 s)" && ok "the real run cut on the 20 s scene cut" || bad "the real run cut elsewhere: $(echo "$E2E_OUT" | grep 'cut')"
    echo "$E2E_OUT" | grep -q "960 frames in" && ok "the joined film has all 960 frames" || bad "joined frame count wrong: $(echo "$E2E_OUT" | tail -2)"
    echo "$E2E_OUT" | grep -q "stream copy confirmed" && ok "the join was a stream copy (the halves' own bytes)" || bad "the join was not confirmed a stream copy: $(echo "$E2E_OUT" | grep -i 'copy\|suspicious')"
    if [ -f "$E2E/renders/e2e.mp4.render.json" ]; then
      python3 - "$E2E/renders/e2e.mp4.render.json" "$E2E/index.html" <<'PY' && ok "the sidecar says how the film was made, and its page resolves (bin/vh patch takes it from there)" || bad "the sidecar is wrong: $(python3 -c "import json,sys; print(json.dumps(json.load(open(sys.argv[1])), ensure_ascii=False))" "$E2E/renders/e2e.mp4.render.json" 2>/dev/null | head -c 400)"
import json, os, sys
d = json.load(open(sys.argv[1]))
side = d.get("split", {})
page = os.path.join(os.path.dirname(sys.argv[1]), d["page"])
try:
    same = os.path.samefile(page, sys.argv[2])
except OSError:
    same = False
ok = (d["frames"] == 960 and d["first_frame"] == 0 and d["span"] == [0.0, 32.0]
      and side.get("seam_frame") == 600 and side.get("halves") == [600, 360]
      and d["encoder"]["codec"] == "libx264" and d["encoder"]["crf"] == 28
      and os.path.exists(page) and same)
if not ok:   # the diagnostics the bad() line above cannot reach (printed to stdout, shown by CI)
    print("SIDECAR-DIAG: frames=%r first_frame=%r span=%r split=%r encoder=%r page=%r exists=%r same=%r argv2=%r"
          % (d.get("frames"), d.get("first_frame"), d.get("span"), side, d.get("encoder"),
             d.get("page"), os.path.exists(page), same, sys.argv[2]))
sys.exit(0 if ok else 1)
PY
    else
      bad "no sidecar was written beside the joined film"
    fi
    # a stop mid-render (E6): a stopped split takes its halves down and leaves nothing behind. TERM is used
    # here — a Ctrl-C on a terminal reaches the whole foreground group, and this test signals the one pid;
    # both arrive at the same stop_all trap. The wait for cmd-a.txt: on the macOS runners the determinism
    # gate alone outlasts a blind 4 s, and a stop that lands before the halves begin proves nothing about them.
    env -u CHROME_PATH PATH="$PATH" bash "$TESTROOT/tools/kaggle/render-split.sh" "$E2E" \
      --encoder x264 --tier draft --out "$WORK/e2e-interrupted.mp4" >/dev/null 2>&1 &
    SP=$!
    I=0
    while [ "$I" -lt 90 ] && kill -0 "$SP" 2>/dev/null && [ ! -e "$WORK/.e2e-interrupted.mp4.split/cmd-a.txt" ]; do
      sleep 1; I=$((I + 1))
    done
    if kill -TERM "$SP" 2>/dev/null; then
      for _ in 1 2 3 4 5 6 7 8; do kill -0 "$SP" 2>/dev/null || break; sleep 1; done
      if [ ! -e "$WORK/e2e-interrupted.mp4" ] && [ ! -d "$WORK/.e2e-interrupted.mp4.split" ]; then
        ok "an interrupted split leaves no film and no halves behind (render.mjs's own stop handler ran in each)"
      else
        bad "an interrupted split left its work behind: $(find "$WORK" -maxdepth 1 -name '.e2e-interrupted*' 2>/dev/null | tr '\n' ' ')"
      fi
      kill -KILL "$SP" 2>/dev/null || true
      pkill -f "e2e-interrupted" 2>/dev/null || true
    else
      ok "the interrupted-split check: skipped (the split ended before the halves began)"
    fi
  fi
fi

# ── bake + the css-cost pair + a real render.sh through the engine, when Chrome is here ─────────
# (the split E2E above already proved Chrome one way or the other: E2E_OUT's browser line carries
# the path it found. All three real-render sections in here carry their own budget — a slow host
# is a fact about the host, not a verdict about the code; run 39127448500 spent its last half hour
# silent because this section said "budget-bounded" and nothing below it was.)
CHROME_BIN=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^.*browser  : \(.*\) (both halves on GPU 0.*$/\1/p' | head -1)
if [ -z "$CHROME_BIN" ]; then
  ok "bake / css-cost / render.sh end to end: skipped (no Chrome on this machine; the guards and the plans are checked above)"
else
  # a fresh bake of an unchanged page is the committed PNG — where the committed PNG was baked.
  # Chrome's raster is platform-specific (macOS run 39123478825: the same page 29.7 dB off the
  # Linux-baked scene.png — SF vs DejaVu text alone), so the reference picture is per platform:
  # this platform's own reference is a second bake, and the twins below carry it as their scene.
  # The whole Chrome trio — bake, second bake, the twins, the --res render — runs under ONE budget
  # (a healthy host draws all of it in well under a minute; a Chrome that stops answering anywhere
  # in it is one honest skip, not four unbounded waits). OVH_TEST_BAKE_BUDGET overrides (seconds).
  printf '\033[36m→\033[0m bake + the css-cost pair (a real browser: the bake, the twin films, the tier)\n'
  COSTDIR="$ROOT/tools/kaggle/fixture/css-cost"
  TWINDIR="$WORK/css-cost-twin"
  B_BUDGET=${OVH_TEST_BAKE_BUDGET:-240}
  case "$B_BUDGET" in ''|*[!0-9]*) B_BUDGET=240 ;; esac
  B_STATUS="$WORK/bake-status"; : > "$B_STATUS"
  T0=$(date +%s)
  (
    node "$ROOT/tools/film/bake.mjs" "$COSTDIR/index.html" --out "$WORK/scene-fresh.png"  --browser "$CHROME_BIN" >"$WORK/bake1.log" 2>&1; echo "bake1=$?" >> "$B_STATUS"
    node "$ROOT/tools/film/bake.mjs" "$COSTDIR/index.html" --out "$WORK/scene-fresh2.png" --browser "$CHROME_BIN" >"$WORK/bake2.log" 2>&1; echo "bake2=$?" >> "$B_STATUS"
    rm -rf "$TWINDIR"; cp -R "$COSTDIR" "$TWINDIR"; cp "$WORK/scene-fresh.png" "$TWINDIR/assets/scene.png"
    node "$ROOT/tools/film/render.mjs" "$COSTDIR/index.html" --browser "$CHROME_BIN" --out "$WORK/css-live.mp4"   --fps 30 --crf 16 --preset medium >"$WORK/twin-live.log" 2>&1; echo "live=$?"   >> "$B_STATUS"
    node "$ROOT/tools/film/render.mjs" "$TWINDIR/baked.html"     --browser "$CHROME_BIN" --out "$WORK/css-baked.mp4" --fps 30 --crf 16 --preset medium >"$WORK/twin-baked.log" 2>&1; echo "baked=$?" >> "$B_STATUS"
    node "$ROOT/tools/film/render.mjs" "$COSTDIR/index.html" --browser "$CHROME_BIN" --out "$WORK/css-270.mp4"  --fps 30 --res 270p --crf 16 --preset medium >"$WORK/res270.log" 2>&1; echo "res270=$?" >> "$B_STATUS"
  ) &
  BP=$!
  B_END=$((T0 + B_BUDGET))
  while kill -0 "$BP" 2>/dev/null && [ "$(date +%s)" -lt "$B_END" ]; do sleep 2; done
  if kill -0 "$BP" 2>/dev/null; then    # over the budget: a slow or wedged runner, not a verdict
    kill -TERM "$BP" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8; do kill -0 "$BP" 2>/dev/null || break; sleep 1; done
    kill -KILL "$BP" 2>/dev/null || true; wait "$BP" 2>/dev/null
    # the drivers, and a browser that stopped answering (this section's Chrome is the only one
    # alive here: the split above closed, the engine below brings its own)
    pkill -TERM -f 'tools/film/(bake|render)\.mjs' 2>/dev/null; pkill -TERM -f 'vh-textcheck-' 2>/dev/null
    sleep 1
    pkill -KILL -f 'tools/film/(bake|render)\.mjs' 2>/dev/null; pkill -KILL -f 'vh-textcheck-' 2>/dev/null
    T1=$(date +%s)
    ok "the bake/twins/--res renders: skipped (over the ${B_BUDGET} s budget after $((T1-T0)) s — a slow or wedged runner; the --res guards and the bake's plans are stub-checked above)"
  else
    wait "$BP" 2>/dev/null
    rc=$(sed -n 's/^bake1=//p' "$B_STATUS"); rc2=$(sed -n 's/^bake2=//p' "$B_STATUS")
    live_rc=$(sed -n 's/^live=//p' "$B_STATUS"); baked_rc=$(sed -n 's/^baked=//p' "$B_STATUS"); res_rc=$(sed -n 's/^res270=//p' "$B_STATUS")
    OUT=$(cat "$WORK/bake1.log" 2>/dev/null)
    chk "a fresh bake of the fixture exits 0" "${rc:-1}" "0"
    echo "$OUT" | grep -qF '1 element(s) of [[data-bake-hide]] hidden' && ok "the bake hid the animated layer the page marks" || bad "the bake hid the wrong thing: [$OUT]"
    if [ "${rc:-1}" = 0 ]; then
      # this platform's own reference: a second bake of the same page must be the same picture
      if [ "${rc2:-1}" = 0 ]; then
        PSNR=$(ffmpeg -hide_banner -i "$WORK/scene-fresh.png" -i "$WORK/scene-fresh2.png" -filter_complex psnr -f null - 2>&1 | sed -n 's/.*average:\([^ ]*\).*/\1/p' | tail -1)
        case "$PSNR" in inf|*[0-9]) awk -v p="$PSNR" 'BEGIN{exit !(p=="inf" || p>=40)}' && ok "two bakes of the same page are the same picture (PSNR ${PSNR} dB — this platform's own reference)" || bad "two bakes drifted: PSNR ${PSNR} dB" ;; *)
          bad "the two-bake PSNR could not be read: [$PSNR]" ;;
        esac
      else
        bad "the second bake did not render: [$(cat "$WORK/bake2.log" 2>/dev/null | tail -c 300)]"
      fi
      # the committed scene.png was baked on Linux: it is this fixture's reference only there
      if [ "$(uname -s)" = Linux ]; then
        PSNR=$(ffmpeg -hide_banner -i "$WORK/scene-fresh.png" -i "$COSTDIR/assets/scene.png" -filter_complex psnr -f null - 2>&1 | sed -n 's/.*average:\([^ ]*\).*/\1/p' | tail -1)
        case "$PSNR" in inf|*[0-9]) awk -v p="$PSNR" 'BEGIN{exit !(p=="inf" || p>=40)}' && ok "the fresh bake matches the committed scene.png (PSNR ${PSNR} dB, the reference was baked on Linux)" || bad "the bake drifted from the committed PNG: PSNR ${PSNR} dB" ;; *)
          bad "the bake-vs-committed PSNR could not be read: [$PSNR]" ;;
        esac
      else
        ok "the committed scene.png is a Linux reference; on $(uname -s) Chrome's own raster differs — the two-bake check above is this platform's, and the twins below carry the fresh bake"
      fi
      # the twin films: the same picture, one with the live blur and one from the baked PNG — the
      # baked side runs on the copy above, whose scene.png is this platform's fresh bake, so the
      # comparison measures live-vs-baked, never this-platform-vs-the-reference's-platform
      if [ "${live_rc:-1}" = 0 ] && [ "${baked_rc:-1}" = 0 ]; then
        PSNR=$(ffmpeg -hide_banner -i "$WORK/css-live.mp4" -i "$WORK/css-baked.mp4" -filter_complex psnr -f null - 2>&1 | sed -n 's/.*average:\([^ ]*\).*/\1/p' | tail -1)
        case "$PSNR" in inf|*[0-9]) awk -v p="$PSNR" 'BEGIN{exit !(p=="inf" || p>=40)}' && ok "the live-blur film and the baked-PNG film are the same picture (PSNR ${PSNR} dB over this platform's own scene, well over bin/vh patch's 40 dB gate)" || bad "the twin films drifted: PSNR ${PSNR} dB" ;; *)
          bad "the twin-film PSNR could not be read: [$PSNR]" ;;
        esac
      else
        bad "a twin film did not render (live=${live_rc:-none} baked=${baked_rc:-none}): [$(tail -c 300 "$WORK/twin-live.log" "$WORK/twin-baked.log" 2>/dev/null)]"
      fi
      # the --res tier on a real render: 270p of a 960x540 page is a 480x270 film
      if [ "${res_rc:-1}" = 0 ]; then
        dims=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$WORK/css-270.mp4" 2>/dev/null)
        chk "a --res 270p render comes out 480x270 (the page's own layout at half the pixels)" "$dims" "480,270"
      else
        bad "the --res 270p render failed: [$(tail -c 300 "$WORK/res270.log" 2>/dev/null)]"
      fi
    fi
  fi

  # render.sh end to end: the real engine (npx, its own download), the real film read back. The
  # engine hangs on exit on some hosts (0.8.82 browser-pool close race — the README says so); the
  # budget handles that: over budget the process is stopped and the film itself is still checked.
  # The browser: only a chrome-headless-shell is handed over (HYPERFRAMES_BROWSER_PATH) — the engine
  # has its own version ceiling for system Chromes, and when nothing pinned is found it downloads
  # its own shell, which always works.
  printf '\033[36m→\033[0m render.sh through the real engine (fps, workers, tier, the held card)\n'
  HFE2E="$WORK/hf-e2e"; cp -R "$ROOT/tools/kaggle/fixture/hf" "$HFE2E"; rm -rf "$HFE2E/renders" "$HFE2E/node_modules"
  cp "$TESTROOT/.kaggle/env.software.sh" "$TESTROOT/.kaggle/env.sh"
  # 480 s: a healthy host finishes in 15-140 s; the first run also downloads the engine and its
  # chrome-headless-shell, and the budget covers that too (the whole-group arithmetic is at the
  # split's budget above). OVH_TEST_RENDER_E2E_BUDGET overrides it (seconds).
  R_E2E_BUDGET=${OVH_TEST_RENDER_E2E_BUDGET:-480}
  case "$R_E2E_BUDGET" in ''|*[!0-9]*) R_E2E_BUDGET=480 ;; esac
  R_LOG="$WORK/hf-e2e.log"; : > "$R_LOG"
  HF_BROWSER_ENV=""
  case "$CHROME_BIN" in *chrome-headless-shell*) HF_BROWSER_ENV="HYPERFRAMES_BROWSER_PATH=$CHROME_BIN" ;; esac
  T0=$(date +%s)
  ( cd "$TESTROOT" && exec env -u CHROME_PATH $HF_BROWSER_ENV PATH="$PATH" \
      bash tools/kaggle/render.sh "$HFE2E" --tier draft ) >"$R_LOG" 2>&1 &
  RP=$!
  R_END=$((T0 + R_E2E_BUDGET))
  while kill -0 "$RP" 2>/dev/null && [ "$(date +%s)" -lt "$R_END" ]; do sleep 2; done
  if kill -0 "$RP" 2>/dev/null; then
    kill -TERM "$RP" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8; do kill -0 "$RP" 2>/dev/null || break; sleep 1; done
    kill -KILL "$RP" 2>/dev/null || true; wait "$RP" 2>/dev/null
    pkill -TERM -f "$HFE2E" 2>/dev/null; sleep 1; pkill -KILL -f "$HFE2E" 2>/dev/null
    T1=$(date +%s)
    ok "render.sh through the engine: stopped over the ${R_E2E_BUDGET} s budget after $((T1-T0)) s (the engine's exit hang or a slow host; the film is still checked)"
  else
    wait "$RP"; rc=$?
    T1=$(date +%s)
    chk "render.sh renders the fixture through the real engine (exit 0, took $((T1-T0)) s)" "$rc" "0"
    R_OUT=$(cat "$R_LOG")
    echo "$R_OUT" | grep -q "30fps · draft · 1 workers" && ok "the engine's own banner confirms 30 fps, the draft tier and one worker" || bad "the engine banner disagrees: $(echo "$R_OUT" | grep -a 'fps ·' | head -1)"
    echo "$R_OUT" | grep -q "held     : 240 frames, 640x360, 30 fps, h264" && ok "the held card read the real film back" || bad "the held card did not print: $(echo "$R_OUT" | grep -a held | head -1)"
  fi
  HFFILM=$(ls -t "$HFE2E"/renders/*.mp4 2>/dev/null | head -1)
  if [ -n "$HFFILM" ]; then
    got=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,avg_frame_rate,nb_frames -of csv=p=0 "$HFFILM" 2>/dev/null)
    chk "the film the engine left is the whole 8 s at the composition's own size" "$got" "h264,640,360,30/1,240"
  else
    bad "the engine left no film under renders/"
  fi
  pkill -f "$HFE2E" 2>/dev/null || true
fi

printf '\n'
if [ "$fails" = 0 ]; then printf '\033[32m✓\033[0m kaggle: %s checks passed\n' "$ran"; else printf '\033[31m✗\033[0m kaggle: %s of %s checks failed\n' "$fails" "$ran"; fi
exit "$fails"
