#!/usr/bin/env bash
# session.sh — ONE command to boot a whole Kaggle session (or any Linux GPU box) for the video
# pipeline: machine check, the render stack (setup.sh), the MiniCPM-V vision-QA server on GPU 1,
# and an optional OpenHarness install. Safe to re-run: a running VLM server is detected and
# reused, never double-launched. What it writes lives under .kaggle/ (git-ignored).
#
#   tools/kaggle/session.sh [--skip-setup] [--no-vlm] [--vlm-only] [--openharness PATH]
#                            [--stop-vlm] [--vlm-timeout SECONDS] [--help]
#
#   --skip-setup     don't re-run tools/kaggle/setup.sh (it is safe to re-run, but the probes
#                    take ~a minute and a resumed session doesn't need them again)
#   --no-vlm         boot everything except the vision server (draft-only runs don't QA frames)
#   --vlm-only       only bring the VLM up (the render stack is already fine)
#   --openharness P  pip install -e P (the OpenHarness checkout) with the pip cache on the
#                    persistent volume, so a saved Kaggle notebook skips the re-download
#   --stop-vlm       stop the server this script started (SIGTERM, then SIGKILL)
#   --vlm-timeout S  how long to wait for the model to load (default 300 s; a cold 8B 4-bit
#                    model on a T4 can take 1-3 minutes to become ready)
#
# The VLM launch resolves in order (first that exists wins — nothing is downloaded by surprise):
#   1. a server already answering at $OPENHARNESS_MINICPM_BASE_URL (or the one a previous
#      session.sh started, remembered in .kaggle/vlm.env)  -> reused as-is
#   2. $VLM_LAUNCH_CMD  -> the exact command you want, run under nohup
#   3. llama-server on PATH + $VLM_GGUF (a local MiniCPM-V GGUF) -> llama-server -m … -ngl 99
#   4. ollama on PATH  -> ollama serve (+ ollama pull minicpm-v when the list is missing it)
#   5. vllm on PATH    -> vllm serve "${VLM_MODEL:-openbmb/MiniCPM-V-4_5}"
# Nothing runnable and no server up -> the known-good commands are printed and the script exits 2
# (the same hints the minicpm_vlm tool's check_server gives — one story, not two).
#
# GPU doctrine (engines/blender-perf.md): GPU 0 stays free for ManimGX + the render browsers;
# the VLM joins Blender and NVENC on GPU 1. Override with VLM_GPU=0 only if you know better.
#
# Ports: llama-server/vllm use 8001 (VLM_PORT to change); ollama is fixed at 11434.
# The OpenHarness side reads OPENHARNESS_MINICPM_BASE_URL / _MODEL — this script exports both
# into .kaggle/env.sh inside a managed block, so `source .kaggle/env.sh` is the only step left.
set -euo pipefail
unset CDPATH
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KAGGLE_DIR="$ROOT/.kaggle"
ENVF="$KAGGLE_DIR/env.sh"
VLM_PID_FILE="$KAGGLE_DIR/vlm.pid"
VLM_LOG="$KAGGLE_DIR/vlm.log"
VLM_ENV="$KAGGLE_DIR/vlm.env"          # the base_url+model of a server we started
VLM_TIMEOUT=300
SKIP_SETUP=0; WANT_VLM=1; VLM_ONLY=0; STOP_VLM=0; OH_PATH=""
while [ $# -gt 0 ]; do case "$1" in
  --skip-setup) SKIP_SETUP=1; shift ;;
  --no-vlm) WANT_VLM=0; shift ;;
  --vlm-only) VLM_ONLY=1; SKIP_SETUP=1; shift ;;
  --openharness) OH_PATH="${2:?--openharness needs a path}"; shift 2 ;;
  --stop-vlm) STOP_VLM=1; shift ;;
  --vlm-timeout) VLM_TIMEOUT="${2:?--vlm-timeout needs seconds}"; shift 2 ;;
  -h|--help) sed -n '2,37p' "$0"; exit 0 ;;
  *) echo "unknown option: $1 (try --help)"; exit 1 ;;
esac; done
c_ok=$'\033✓\033'; c_no=$'\033✗\033'; c_wa=$'\033!\033'
say() { printf '\033→ %s\033\n' "$*"; }
ok()  { printf '%s %s\n' "$c_ok" "$*"; }
no()  { printf '%s %s\n' "$c_no" "$*"; }
warn() { printf '%s %s\n' "$c_wa" "$*"; }

mkdir -p "$KAGGLE_DIR"

# ── the machine, one glance (cheap — monitor.sh is the deep view) ───────────────────────────────
gpus=0
if command -v nvidia-smi >/dev/null 2>&1; then
  gpus=$(nvidia-smi -L 2>/dev/null | grep -c '^GPU ' || true)
fi
if [ "$gpus" -gt 0 ]; then
  ok "$gpus GPU(s): $(nvidia-smi -L 2>/dev/null | head -1 | sed 's/^GPU [0-9]*: //')"
else
  warn "no NVIDIA GPU visible (nvidia-smi) — renders fall back to CPU/SwiftShader"
fi

# ── the render stack ────────────────────────────────────────────────────────────────────────────
if [ "$STOP_VLM" = 1 ]; then
  # The stack is not touched by --stop-vlm: it only manages the server this script started.
  :
elif [ "$SKIP_SETUP" = 0 ]; then
  say "setup.sh — Node, ffmpeg(+NVENC), Chrome, the browser-GPU probe (.kaggle/env.sh)"
  bash "$ROOT/tools/kaggle/setup.sh"
else
  ok "skipping setup.sh (--skip-setup / --vlm-only)"
fi

# ── OpenHarness install (optional) ──────────────────────────────────────────────────────────────
if [ -n "$OH_PATH" ]; then
  OH_PATH="$(cd "$OH_PATH" && pwd)"
  if [ -f "$OH_PATH/pyproject.toml" ]; then
    # The pip cache goes under /kaggle/working/.cache when that exists (a saved Kaggle notebook
    # keeps it), so the wheels are downloaded once, not once per session.
    PIPCACHE="${PIP_CACHE_DIR:-}"
    if [ -z "$PIPCACHE" ] && [ -d /kaggle/working ] && [ -w /kaggle/working ]; then
      PIPCACHE=/kaggle/working/.cache/pip; mkdir -p "$PIPCACHE"
    fi
    say "installing OpenHarness from $OH_PATH (pip -e)"
    if [ -n "$PIPCACHE" ]; then
      PIP_CACHE_DIR="$PIPCACHE" python3 -m pip install -q -e "$OH_PATH" || {
        no "pip install failed — check the output above"; exit 1; }
    else
      python3 -m pip install -q -e "$OH_PATH" || { no "pip install failed"; exit 1; }
    fi
    ok "openharness importable: $(python3 -c 'import openharness; print(openharness.__file__)' 2>/dev/null || echo 'verify with: python3 -c \"import openharness\"')"
  else
    no "--openharness path has no pyproject.toml: $OH_PATH"
    exit 1
  fi
fi

# ── helpers ────────────────────────────────────────────────────────────────────────────────────
probe_url() { # probe_url <url>: 0 when a server answers /models (curl -fsS, short timeout)
  command -v curl >/dev/null 2>&1 || return 1
  curl -fsS -m 5 -H 'Authorization: Bearer EMPTY' "$1/models" >/dev/null 2>&1
}
vlm_env_block() { # vlm_env_block <base_url> <model> -> the managed block for env.sh
  printf '# >>> session.sh vlm (managed — tools/kaggle/session.sh rewrites this block) >>>\n'
  printf "export OPENHARNESS_MINICPM_BASE_URL='%s'\n" "$1"
  printf "export OPENHARNESS_MINICPM_MODEL='%s'\n" "$2"
  printf "export OPENHARNESS_MINICPM_API_KEY='EMPTY'\n"
  printf '# <<< session.sh vlm <<<\n'
}
write_env_block() { # write_env_block <base_url> <model>: idempotent replace inside env.sh
  mkdir -p "$KAGGLE_DIR"
  touch "$ENVF"
  awk '
    /^# >>> session\.sh vlm / { skip=1; next }
    /^# <<< session\.sh vlm <<</ { skip=0; printed=1; next }
    !skip { print }
  ' "$ENVF" > "$ENVF.tmp"
  [ -s "$ENVF.tmp" ] || printf '# Written by tools/kaggle/session.sh (source it: source %s)\n' "$ENVF" > "$ENVF.tmp"
  vlm_env_block "$1" "$2" >> "$ENVF.tmp"
  mv "$ENVF.tmp" "$ENVF"
}
remember_vlm() { printf 'BASE_URL=%s\nMODEL=%s\n' "$1" "$2" > "$VLM_ENV"; }

# ── --stop-vlm ─────────────────────────────────────────────────────────────────────────────────
if [ "$STOP_VLM" = 1 ]; then
  if [ -f "$VLM_PID_FILE" ] && kill -0 "$(cat "$VLM_PID_FILE")" 2>/dev/null; then
    pid=$(cat "$VLM_PID_FILE")
    say "stopping the VLM server (pid $pid)"
    kill -TERM "$pid" 2>/dev/null || true
    for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    kill -KILL "$pid" 2>/dev/null || true
    rm -f "$VLM_PID_FILE" "$VLM_ENV"
    ok "VLM server stopped"
  else
    ok "no VLM server of ours to stop (pid file missing or process gone)"
    rm -f "$VLM_PID_FILE"
  fi
  exit 0
fi

# ── the VLM server ─────────────────────────────────────────────────────────────────────────────
if [ "$WANT_VLM" = 1 ]; then
  # Defaults: llama-server/vllm on 8001; ollama moves to its own fixed 11434.
  VLM_PORT="${VLM_PORT:-8001}"
  BASE_CANDIDATE="${OPENHARNESS_MINICPM_BASE_URL:-}"
  if [ -z "$BASE_CANDIDATE" ] && [ -f "$VLM_ENV" ]; then
    BASE_CANDIDATE=$(sed -n 's/^BASE_URL=//p' "$VLM_ENV" | tail -1)
  fi

  if [ -n "$BASE_CANDIDATE" ] && probe_url "$BASE_CANDIDATE"; then
    ok "VLM server already up at $BASE_CANDIDATE — reusing, nothing relaunched"
    MODEL_NOW="${OPENHARNESS_MINICPM_MODEL:-$(sed -n 's/^MODEL=//p' "$VLM_ENV" | tail -1)}"
    write_env_block "$BASE_CANDIDATE" "${MODEL_NOW:-openbmb/MiniCPM-V-4_5}"
    remember_vlm "$BASE_CANDIDATE" "${MODEL_NOW:-openbmb/MiniCPM-V-4_5}"
  else
    # Nothing up. Resolve a launcher, in the documented order.
    CMD=(); BASE=""; MODEL="${VLM_MODEL:-openbmb/MiniCPM-V-4_5}"
    if [ -n "${VLM_LAUNCH_CMD:-}" ]; then
      # 2. the operator knows best: their exact command, split into words.
      # shellcheck disable=SC2206
      CMD=(${VLM_LAUNCH_CMD}); BASE="http://127.0.0.1:${VLM_PORT}/v1"
    elif command -v llama-server >/dev/null 2>&1 && [ -n "${VLM_GGUF:-}" ] && [ -f "$VLM_GGUF" ]; then
      # 3. llama.cpp with a local GGUF — the model name it reports is the file's basename.
      CMD=(llama-server -m "$VLM_GGUF" --host 127.0.0.1 --port "$VLM_PORT" -c 8192 -ngl 99)
      BASE="http://127.0.0.1:${VLM_PORT}/v1"; MODEL="$(basename "$VLM_GGUF")"
      [ -n "${VLM_MODEL:-}" ] && MODEL="$VLM_MODEL"
    elif command -v ollama >/dev/null 2>&1; then
      # 4. ollama: pull only when the list is missing the model (no surprise downloads).
      ollama list 2>/dev/null | grep -q minicpm-v || { say "ollama pull minicpm-v (first time only)"; ollama pull minicpm-v || true; }
      CMD=(ollama serve); BASE="http://127.0.0.1:11434/v1"; MODEL="minicpm-v"
    elif command -v vllm >/dev/null 2>&1; then
      # 5. vLLM serving the HF repo (it downloads on first use — that is vLLM's own contract).
      CMD=(vllm serve "${VLM_MODEL:-openbmb/MiniCPM-V-4_5}" --port "$VLM_PORT"); BASE="http://127.0.0.1:${VLM_PORT}/v1"
    else
      no "no VLM launcher found and no server up. Known-good options:"
      printf '  vLLM:      vllm serve openbmb/MiniCPM-V-4_5 --quantization awq --max-model-len 8192 --port 8001\n'
      printf '  llama.cpp: llama-server -m MiniCPM-V-4_5-Q4_K_M.gguf --host 127.0.0.1 --port 8001 -c 8192\n'
      printf '  Ollama:    ollama pull minicpm-v \&\& ollama serve\n'
      printf 'Set VLM_LAUNCH_CMD (or install one of the above, or VLM_GGUF=…), then re-run.\n'
      [ "$VLM_ONLY" = 1 ] || ok "everything else is up — the session is usable without vision QA"
      exit 2
    fi
    GPU="${VLM_GPU:-1}"   # doctrine: GPU 0 belongs to ManimGX + the browsers
    [ "$gpus" -le 1 ] && GPU=0
    say "starting: ${CMD[*]}  (GPU $GPU, log: $VLM_LOG)"
    [ -f "$VLM_LOG" ] && mv -f "$VLM_LOG" "$VLM_LOG.1"
    nohup env CUDA_VISIBLE_DEVICES="$GPU" "${CMD[@]}" > "$VLM_LOG" 2>&1 &
    echo $! > "$VLM_PID_FILE"
    ok "launched (pid $(cat "$VLM_PID_FILE")) — waiting up to ${VLM_TIMEOUT}s for the model to be ready"
    ready=0
    for _ in $(seq 1 "$VLM_TIMEOUT"); do
      probe_url "$BASE" && { ready=1; break; }
      kill -0 "$(cat "$VLM_PID_FILE")" 2>/dev/null || { no "server exited early — tail of $VLM_LOG:"; tail -5 "$VLM_LOG" || true; exit 1; }
      sleep 1
    done
    if [ "$ready" = 1 ]; then
      ok "VLM server ready at $BASE (model: $MODEL)"
      write_env_block "$BASE" "$MODEL"
      remember_vlm "$BASE" "$MODEL"
    else
      no "VLM server did not become ready in ${VLM_TIMEOUT}s (cold model loads can be slow — raise --vlm-timeout)"
      no "log tail:"; tail -5 "$VLM_LOG" || true
      exit 1
    fi
  fi
elif [ "$VLM_ONLY" = 1 ]; then
  warn "--vlm-only with --no-vlm: nothing to do"
fi

# ── the card ────────────────────────────────────────────────────────────────────────────────────
printf '\n'
say "session ready. Next steps:"
printf '  1. source .kaggle/env.sh          # renders (render.sh does this for you) + the VLM vars\n'
if [ -n "$OH_PATH" ]; then
  printf '  2. oh --resume                    # continue an OpenHarness session (auto-save snapshots)\n'
else
  printf '  2. oh "your video task"           # or: oh --resume to continue a saved session\n'
fi
printf '  3. tools/kaggle/monitor.sh --watch # the whole box on one glance while it runs\n'
printf '\n'
if [ "$gpus" -ge 2 ]; then
  say "GPU doctrine on this ${gpus}-GPU box: GPU 0 = ManimGX + render browsers, GPU 1 = Blender CUDA + NVENC + the VLM"
fi
say "the Kaggle 12 h cap: renders resume (render.sh --resume / blender_split.sh --resume); auto-save keeps the agent."
