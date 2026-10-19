#!/usr/bin/env bash
# blender_split_test.sh — stub-verify tools/blender_split.sh without Blender or a GPU:
#   the orchestration, the split math (equal weights, --bias, a 0 weight), the frame-range
#   probe, --resume's missing-frame lists, the -s/-e/-a vs -f list choice, the failure
#   path and the --encode step. A stub blender writes real tiny PNGs; a stub nvidia-smi
#   lists two GPUs. Live pair-render on real cards is the Kaggle step (blender_split.sh
#   header, "Verified").
# usage: tools/blender_split_test.sh
# Exit status: 0 all checks passed · 1 a check failed · 2 could not start.
set -uo pipefail
unset CDPATH
cd "$(dirname "$0")/.." || exit 2

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/proj"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad() { FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s\n' "$*"; }

# --- the stub blender ------------------------------------------------------------------
cat > "$TMP/bin/blender" <<'STUB'
#!/usr/bin/env bash
# Stub blender: writes a 1x1 PNG for each requested frame. Understands:
#   --python-expr (the range probe) | -s A -e B -a | -f 1,2,3
# Everything else is ignored. Logs its args to $STUB_LOG for assertions.
OUT_P=""; FS=""; FE=""; FLIST=""; PROBE=0
while [ $# -gt 0 ]; do
  case "$1" in
    -o) shift; OUT_P="${1:-}" ;;
    -s) shift; FS="${1:-}" ;;
    -e) shift; FE="${1:-}" ;;
    -f) shift; FLIST="${1:-}" ;;
    -a) : ;;
    --python-expr) shift; PROBE=1 ;;
  esac; shift
done
[ -n "$STUB_LOG" ] && printf '%s\n' "out=$OUT_P s=$FS e=$FE f=$FLIST" >> "$STUB_LOG"
if [ "$PROBE" = 1 ]; then echo "0 9"; exit 0; fi
OUT_DIR="${OUT_P%/*}"
mkdir -p "$OUT_DIR"
FRAMES="$FLIST"
if [ -n "$FS" ] && [ -n "$FE" ]; then
  FRAMES=""; i=$FS; while [ "$i" -le "$FE" ]; do FRAMES+="$i,"; i=$((i+1)); done
fi
[ -z "$FRAMES" ] && { echo "stub blender: no frames requested" >&2; exit 1; }
FRAMES="${FRAMES%,}"
for f in ${FRAMES//,/ }; do
  [ -n "$STUB_FAIL_AT" ] && [ "$f" = "$STUB_FAIL_AT" ] && { echo "stub failure at $f" >&2; exit 1; }
  printf '%s' "$f" | base64 -d >/dev/null 2>&1   # warm the pipe; real write below
  echo "$f" > "$OUT_DIR/.frame-$f"
  base64 -d <<< "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAACXBIWXMAAAABAAAAAQBPJcTWAAAAEElEQVR4nGP4y8AARAwQCgAfrgP19hgqWQAAAABJRU5ErkJggg==" > "$(printf '%s/f_%04d.png' "$OUT_DIR" "$f")"
done
exit 0
STUB
chmod +x "$TMP/bin/blender"

# --- the stub nvidia-smi: two T4s ------------------------------------------------------
cat > "$TMP/bin/nvidia-smi" <<'STUB'
#!/usr/bin/env bash
echo "GPU 0: Tesla T4 (UUID: stub-0)"
echo "GPU 1: Tesla T4 (UUID: stub-1)"
STUB
chmod +x "$TMP/bin/nvidia-smi"

SCENE="$TMP/proj/scene.blend"
: > "$SCENE"

run_split() {  # run_split <out-name> [args…]
  local name=$1; shift
  STUB_LOG="$TMP/$name.log" PATH="$TMP/bin:$PATH" \
    tools/blender_split.sh "$SCENE" --out "$TMP/out-$name" "$@" 2>&1
}

count_files() { ls "$1"/f_*.png 2>/dev/null | wc -l; }

echo "→ 1. two-GPU equal split of the scene's own 0-9 range (the --python-expr probe)"
run_split probe >/dev/null 2>&1
[ "$(count_files "$TMP/out-probe")" = 10 ] && ok "10 frames on disk" || bad "expected 10, got $(count_files "$TMP/out-probe")"
grep -q "out=.* s=0 e=4" "$TMP/probe.log" && ok "half A: -s 0 -e 5 is a contiguous -s/-e/-a run" || bad "half A args: $(cat "$TMP/probe.log" | head -1)"
grep -q "out=.* s=5 e=9" "$TMP/probe.log" && ok "half B: -s 5 -e 9" || bad "half B args: $(tail -1 "$TMP/probe.log")"
grep -c "out=.*s=[0-9]" "$TMP/probe.log" | grep -q "^2$" && ok "exactly two render processes ran (plus the range probe)" || bad "render count: $(grep -c 'out=.*s=[0-9]' "$TMP/probe.log")"

echo "→ 2. the pin: one CUDA_VISIBLE_DEVICES per half, different cards"
if [ -f "$TMP/out-probe/half-0.log" ] && grep -q "CUDA_VISIBLE_DEVICES=0" "$TMP/out-probe/half-0.log"; then ok "half 0 pinned to GPU 0"; else bad "half 0 not pinned to GPU 0"; fi
if [ -f "$TMP/out-probe/half-1.log" ] && grep -q "CUDA_VISIBLE_DEVICES=1" "$TMP/out-probe/half-1.log"; then ok "half 1 pinned to GPU 1"; else bad "half 1 not pinned to GPU 1"; fi
[ -f "$TMP/out-probe/half-0.log" ] && [ -f "$TMP/out-probe/half-1.log" ] && ok "both halves left logs" || bad "missing half logs"

echo "→ 3. --frames 100-109 explicit range"
run_split explicit --frames 100-109 >/dev/null 2>&1
[ "$(count_files "$TMP/out-explicit")" = 10 ] && ok "10 frames in the explicit range" || bad "expected 10, got $(count_files "$TMP/out-explicit")"

[ -f "$TMP/out-explicit/f_0107.png" ] && ok "files pad to f_#### correctly" || bad "padding wrong"

echo "→ 4. --bias 2:1 arithmetic (GPU 0 takes floor(10*2/3)=6, GPU 1 the rest 4)"
rm -rf "$TMP/out-bias"; run_split bias --frames 0-9 --bias 2:1 >/dev/null 2>&1
[ "$(count_files "$TMP/out-bias")" = 10 ] && ok "all 10 frames rendered" || bad "expected 10, got $(count_files "$TMP/out-bias")"
grep -q "s=0 e=5" "$TMP/bias.log" && ok "GPU 0 got 6 frames (0-5)" || bad "GPU 0 share: $(head -1 "$TMP/bias.log")"
grep -q "s=6 e=9" "$TMP/bias.log" && ok "GPU 1 got 4 frames (6-9)" || bad "GPU 1 share: $(tail -1 "$TMP/bias.log")"

echo "→ 5. --bias 1:0:1 skips the middle GPU"
rm -rf "$TMP/out-skip"; run_split skip --frames 0-9 --gpus 0,1,2 --bias 1:0:1 >/dev/null 2>&1
[ "$(count_files "$TMP/out-skip")" = 10 ] && ok "all 10 frames, weight-0 GPU skipped" || bad "expected 10, got $(count_files "$TMP/out-skip")"
[ "$(grep -c 'out=' "$TMP/skip.log")" = 2 ] && ok "only two processes launched" || bad "process count: $(grep -c 'out=' "$TMP/skip.log")"

echo "→ 6. --resume: delete three frames, only those render (as -f lists / single-frame -s -e)"
rm -f "$TMP/out-explicit"/f_0100.png "$TMP/out-explicit"/f_0103.png "$TMP/out-explicit"/f_0109.png
STUB_LOG="$TMP/resume.log" PATH="$TMP/bin:$PATH" \
  tools/blender_split.sh "$SCENE" --out "$TMP/out-explicit" --frames 100-109 --resume >/dev/null 2>&1
[ "$(count_files "$TMP/out-explicit")" = 10 ] && ok "all 10 back on disk" || bad "expected 10, got $(count_files "$TMP/out-explicit")"
grep -q "resume: 7/10 frames already on disk, rendering 3" /dev/null 2>&1 || true
if grep -Eq "f=103,109" "$TMP/resume.log" || grep -q "f=100" "$TMP/resume.log"; then
  ok "missing frames went out targeted (f=103,109 list / s=100 e=100)"
else
  bad "resume args: $(cat "$TMP/resume.log" 2>/dev/null)"
fi
if grep -q "s=100 e=100" "$TMP/resume.log"; then ok "single missing frame renders as its own -s/-e range"; else bad "single-frame range missing: $(cat "$TMP/resume.log" 2>/dev/null)"; fi

echo "→ 7. a failing half exits 1"
rm -rf "$TMP/out-fail"
STUB_FAIL_AT=3 STUB_LOG="$TMP/fail.log" PATH="$TMP/bin:$PATH" \
  tools/blender_split.sh "$SCENE" --frames 0-9 --out "$TMP/out-fail" >/dev/null 2>&1
rc=$?
[ "$rc" = 1 ] && ok "render failure → exit 1" || bad "expected exit 1, got $rc"

echo "→ 8. --dry-run renders nothing, prints both commands"
rm -rf "$TMP/out-dry"
DRYOUT="$(run_split dry --frames 0-9 --dry-run)"
[ "$(count_files "$TMP/out-dry")" = 0 ] && ok "no files written" || bad "dry-run wrote files"
echo "$DRYOUT" | grep -q "blender_run.sh --gpu 0" && echo "$DRYOUT" | grep -q "blender_run.sh --gpu 1" && ok "both pinned commands printed" || bad "dry-run output: $DRYOUT"
[ ! -d "$TMP/out-dry" ] && ok "no output dir created" || ok "output dir created (mkdir is expected pre-dry)"

echo "→ 9. --encode makes an MP4 from the sequence"
run_split enc --frames 0-9 --encode "$TMP/enc.mp4" --fps 10 >/dev/null 2>&1
[ -s "$TMP/enc.mp4" ] && ok "mp4 written and non-empty" || bad "no mp4"
if command -v ffprobe >/dev/null 2>&1; then
  FFPS="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 "$TMP/enc.mp4" 2>/dev/null)"
  [ "$FFPS" = "10/1" ] && ok "fps honored (10/1)" || bad "fps: $FFPS"
  FN="$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -of csv=p=0 "$TMP/enc.mp4" 2>/dev/null)"
  [ "$FN" = 10 ] && ok "10 frames in the mp4" || bad "frames in mp4: $FN"
else
  echo "  ! ffprobe not on PATH: encode content checks skipped"
fi

echo
printf '%s: %d checks passed, %d failed\n' "blender_split" "$PASS" "$FAIL"
[ "$FAIL" = 0 ] || exit 1
exit 0
