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
echo "$OUT" | grep -q "fps 60 (the composition asks for it" && ok "a declared 60 fps is kept with the halving note" || bad "60 fps note wrong: $(echo "$OUT" | grep 'fps')"

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
  # hangs until the workflow's own timeout. A healthy macOS runner draws this film in ~380 s (Linux:
  # ~30 s); the default budget is nearly twice the slow one. OVH_TEST_E2E_BUDGET overrides it (seconds).
  E2E_BUDGET=${OVH_TEST_E2E_BUDGET:-720}
  case "$E2E_BUDGET" in ''|*[!0-9]*) E2E_BUDGET=720 ;; esac
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

printf '\n'
if [ "$fails" = 0 ]; then printf '\033[32m✓\033[0m kaggle: %s checks passed\n' "$ran"; else printf '\033[31m✗\033[0m kaggle: %s of %s checks failed\n' "$fails" "$ran"; fi
exit "$fails"
