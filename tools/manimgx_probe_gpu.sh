#!/usr/bin/env bash
# Confirm that ManimGX will really draw on the GPU (Kaggle T4 x2 etc.), and say why not if it won't.
#   checks, in order: nvidia-smi (GPUs present) -> libvulkan1 (the Vulkan loader) -> the NVIDIA ICD file
#   -> vulkaninfo (the loader can see the T4) -> a timed 1080p60 test render while sampling GPU
#   utilization. The utilization samples are the verdict: Vulkan apps do not appear in
#   nvidia-smi's CUDA process list, so a render that finishes fast but moves no GPU counter is
#   lavapipe (CPU) work, and the script says which fix applies (engines/manimgx.md, G5 table).
# usage: tools/manimgx_probe_gpu.sh [--skip-render]      (run from anywhere; needs uv, installs it if missing)
#   --skip-render   check the environment only, skip the test render (faster, weaker verdict)
# Exit status: 0 GPU render confirmed · 1 diagnosis printed (CPU fallback or misconfig; fix in the message)
#   · 2 could not run (no nvidia-smi, no uv and could not install it, test render failed).
# Writes its scratch scene and logs under a temp dir; nothing lands in the repo.
set -uo pipefail
unset CDPATH   # an exported one could send a relative cd elsewhere (as in bin/vh)
cd "$(dirname "$0")/.." || exit 2

say()  { printf '%s\n' "$*"; }
ok()   { printf '[ok] %s\n' "$*"; }
bad()  { printf '[!!] %s\n' "$*"; }
info() { printf '[--] %s\n' "$*"; }

skip_render=0
[ "${1:-}" = "--skip-render" ] && skip_render=1

TMP=$(mktemp -d /tmp/mgx-probe.XXXXXX) || exit 2
trap 'rm -rf "$TMP"' EXIT

# --- 1. the GPUs -----------------------------------------------------------------
if ! command -v nvidia-smi >/dev/null 2>&1; then
  bad "nvidia-smi not found: no NVIDIA driver in this environment (a Kaggle CPU session, or the GPU is not attached)."
  exit 2
fi
ok "nvidia-smi:"
nvidia-smi --query-gpu=index,name,memory.total,driver_version --format=csv,noheader | sed 's/^/     /'
ngpu=$(nvidia-smi --query-gpu=index --format=csv,noheader | wc -l)

# --- 2. the Vulkan loader (without it wgpu sees no NVIDIA device and ManimGX silently
#        falls back to the bundled lavapipe: the render works, on the CPU) --------------------------
# grep without -q: -q exits on first match and the producer dies of SIGPIPE, which pipefail
#        turns into a false "missing" (a race — the same run can flip the other way)
if ldconfig -p 2>/dev/null | grep 'libvulkan.so.1' >/dev/null; then
  ok "Vulkan loader present (libvulkan.so.1)"
else
  bad "Vulkan loader MISSING: ManimGX cannot see the T4 and will render on the CPU (lavapipe)."
  say  "     fix: sudo apt-get install -y libvulkan1 vulkan-tools"
  [ "$skip_render" = 1 ] || say "     (continuing with the render check anyway, to show the fallback in the numbers)"
fi

# --- 3. the NVIDIA ICD -------------------------------------------------------------
icd=""
for f in /usr/share/vulkan/icd.d/nvidia_icd.json /etc/vulkan/icd.d/nvidia_icd.json; do
  [ -f "$f" ] && icd=$f
done
if [ -n "$icd" ]; then
  ok "NVIDIA ICD: $icd"
else
  info "no nvidia_icd.json in the default paths; if vulkaninfo below shows no T4:"
  say  "     find it with: dpkg -L libnvidia-gl-$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1) 2>/dev/null | grep icd"
  say  "     then:        export VK_ICD_FILELIST=<that path>"
fi

# --- 4. can the loader enumerate the T4? -------------------------------------------
if command -v vulkaninfo >/dev/null 2>&1; then
  if vulkaninfo --summary 2>/dev/null | grep -i "T4\|NVIDIA" >/dev/null; then
    ok "vulkaninfo sees an NVIDIA device:"
    vulkaninfo --summary 2>/dev/null | grep -i -m3 "deviceName\|T4" | sed 's/^/     /'
  else
    bad "vulkaninfo runs but lists no NVIDIA device (loader or ICD problem; see the two fixes above)."
  fi
else
  info "vulkaninfo not installed (sudo apt-get install -y vulkan-tools); the render check below still decides."
fi

# --- 5. the render itself: 1080p60 while sampling GPU utilization -------------------
uv_bin=$(command -v uv || true)
if [ -z "$uv_bin" ] && [ -x "$HOME/.local/bin/uv" ]; then uv_bin=$HOME/.local/bin/uv; fi
if [ -z "$uv_bin" ]; then
  info "uv not found; installing it to ~/.local/bin (curl -LsSf https://astral.sh/uv/install.sh | sh)…"
  if curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 && [ -x "$HOME/.local/bin/uv" ]; then
    uv_bin=$HOME/.local/bin/uv
    ok "uv installed"
  else
    bad "could not install uv; install it by hand and re-run."
    exit 2
  fi
fi

if [ "$skip_render" = 1 ]; then
  say "[--] --skip-render: environment checked above; run without it for the render verdict."
  if ldconfig -p 2>/dev/null | grep 'libvulkan.so.1' >/dev/null; then exit 0; else exit 1; fi
fi

cat > "$TMP/probe_scene.py" << 'EOF'
import manimgx as m

class ProbeScene(m.Scene):
    def construct(self) -> None:
        t = m.Text("GPU probe", font_size=64)
        eq = m.MathTex(r"\sum_{n=1}^{99} \frac{4}{\pi(2n{-}1)}", font_size=48)
        eq.next_to(t, m.DOWN, buff=0.7)
        sq = m.Square(side_length=2.0, color=m.BLUE, fill_opacity=0.4)
        sq.next_to(eq, m.DOWN, buff=0.7)
        self.play(m.Write(t), run_time=0.5)
        self.play(m.Create(eq), run_time=0.9)
        self.play(m.GrowFromCenter(sq), run_time=0.8)
        self.play(m.Rotate(sq, m.PI / 3), run_time=0.8)
        self.wait(0.5)
EOF

# utilization samples: Vulkan apps do not show in --query-compute-apps; watch the counters instead
( for _ in $(seq 1 90); do
    nvidia-smi --query-gpu=index,utilization.gpu,memory.used --format=csv,noheader,nounits 2>/dev/null
    sleep 1
  done ) > "$TMP/gpu.log" &
MON=$!
t0=$(date +%s.%N)
# uv tool run (uvx): an ephemeral environment, no project needed — the documented form for a
# first render on a fresh machine (manimgx's own quickstart); the wheel (~52 MB) downloads once.
"$uv_bin" tool run --python 3.14 manimgx render -r 1920x1080 --fps 60 --preset ultrafast \
  "$TMP/probe_scene.py" ProbeScene -o "$TMP/probe.mp4" > "$TMP/render.log" 2>&1
rc=$?
t1=$(date +%s.%N)
kill "$MON" 2>/dev/null; wait "$MON" 2>/dev/null
wall=$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.1f", b - a }')

if [ $rc -ne 0 ] || [ ! -s "$TMP/probe.mp4" ]; then
  bad "test render failed (exit $rc); last lines:"
  tail -5 "$TMP/render.log" | sed 's/^/     /'
  exit 2
fi
engine=$(grep -o 'rendered in [0-9.]* s' "$TMP/render.log" | head -1 || true)
ok "test render: 3.5 s of 1080p60 in ${wall} s wall${engine:+ ($engine)}"

# verdict: did any GPU's counter move during the render?
peak=$(sort -t, -k2 -rn "$TMP/gpu.log" 2>/dev/null | head -1 || true)
peak_util=$(printf '%s' "$peak" | cut -d, -f2 | tr -d ' ' || true)
if [ -n "$peak_util" ] && [ "$peak_util" -ge 15 ] 2>/dev/null; then
  ok "GPU was used while rendering (peak utilization ${peak_util}%: $peak)."
  say  "VERDICT: T4 VULKAN OK — ManimGX renders on the GPU."
  say  "        (${ngpu} GPU(s); multiple render processes all use the first one — engines/manimgx.md, GPU section.)"
  exit 0
else
  bad "GPU counters did not move while rendering (peak sample: ${peak:-none})."
  say  "VERDICT: LAVAPIPE FALLBACK — the render worked but drew on the CPU."
  if ! ldconfig -p 2>/dev/null | grep -q 'libvulkan.so.1'; then
    say  "        fix: sudo apt-get install -y libvulkan1 vulkan-tools   (then re-run this probe)"
  else
    say  "        fix: check the ICD path above (VK_ICD_FILELIST), then re-run this probe"
  fi
  exit 1
fi
