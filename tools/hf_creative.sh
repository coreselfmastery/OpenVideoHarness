#!/usr/bin/env bash
# hf_creative.sh — the HyperFrames creative layer: one command per creative move. The pack itself lives in
#   styles/_swatch/lib.js (verified block by block by the catalog-fx test card, engines/hyperframes-creative.md):
#   4 more 2D transitions, 7 GLSL shader transitions, 4 post effects, kinetic type, seeded particles, text markers
#   and colour harmony — all pure functions of t, all seeded, all byte-deterministic on the delivery renderer.
#
# usage: tools/hf_creative.sh --fx                 list the creative pack (what lib.js gives a scene, with call lines)
#        tools/hf_creative.sh --palette <hex> [--scheme analogous|complementary|split|triad|tetrad|mono]
#                              [--count N] [--seed N]
#                                                 print a harmony palette from one seed colour (runs lib.js itself,
#                                                 so what you print is what the scene will draw — no copy of the math)
#        tools/hf_creative.sh --styles             list the style presets (styles/, each with a verified swatch)
#        tools/hf_creative.sh --blocks ["<query>"] browse/search the HyperFrames block registry (local semantic ranking)
#        tools/hf_creative.sh --add <block> <project-dir>
#                                                 install a registry block into a HyperFrames project (bin/vh hf-init)
#        tools/hf_creative.sh --demo [--final]     render the catalog-fx test card (draft by default; every creative-pack
#                                                 block in a labelled cell + three shader transitions full frame)
#
#   The binary for --blocks/--add resolves to $HYPERFRAMES_BIN, else the project's own
#   node_modules/.bin/hyperframes (hf-init pins 0.8.82), else npx hyperframes@${HYPERFRAMES_VERSION:-0.8.82}.
#   --demo runs styles/_swatch/render.sh catalog-fx (same tiers and checks as every other swatch).
#
# Exit status: 0 the thing ran · 1 the underlying command failed · 2 bad usage (unknown option, missing argument).
# The repo's standing env applies (bin/vh hf-init): HYPERFRAMES_SKIP_SKILLS=1 DO_NOT_TRACK=1 are set here too.
set -uo pipefail
unset CDPATH

usage() { sed -n '3,27p' "$0"; }
die() { printf '\033✗\033 %s\n' "$*" >&2; exit 2; }
ok()  { printf '\033✓\033 %s\n' "$*"; }

cmd=""; hex=""; scheme="analogous"; count=5; seed=1; query=""; block=""; dir=""; final=0
while [ $# -gt 0 ]; do
  case "$1" in
    --fx) [ -z "$cmd" ] && cmd=fx || die "one mode at a time" ;;
    --palette) [ -z "$cmd" ] && cmd=palette || die "one mode at a time"; hex=${2:?}; shift ;;
    --palette=*) [ -z "$cmd" ] && cmd=palette || die "one mode at a time"; hex=${1#*=} ;;
    --scheme) scheme=${2:?}; shift ;; --scheme=*) scheme=${1#*=} ;;
    --count) count=${2:?}; shift ;; --count=*) count=${1#*=} ;;
    --seed) seed=${2:?}; shift ;; --seed=*) seed=${1#*=} ;;
    --styles) [ -z "$cmd" ] && cmd=styles || die "one mode at a time" ;;
    --blocks) [ -z "$cmd" ] && cmd=blocks || die "one mode at a time"; [ $# -ge 2 ] && [ "${2#-}" = "$2" ] && { query=$2; shift; } ;;
    --add) [ -z "$cmd" ] && cmd=add || die "one mode at a time"; block=${2:?}; shift ;;
    --demo) [ -z "$cmd" ] && cmd=demo || die "one mode at a time" ;;
    --final) final=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option $1 (see --help)" ;;
    *) [ "$cmd" = add ] && [ -z "$dir" ] && dir=$1 || die "unexpected argument: $1" ;;
  esac; shift
done
[ -n "$cmd" ] || { usage >&2; exit 2; }
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) || exit 2

# ── --fx: the creative pack at a glance (keep in sync with styles/_swatch/lib.js; the catalog-fx card renders it)
if [ "$cmd" = fx ]; then
  cat <<'EOF'
lib.js creative pack — every helper is a pure function of t, seeded and cached (styles/_swatch/lib.js).
Verify visually:  styles/_swatch/render.sh catalog-fx          (the test card, one cell per helper)
Doctrine:         engines/hyperframes-creative.md

transitions (2D, full frame — same shape as wipe/iris/whip: (ctx, u, drawA, drawB, opts))
  dissolve(u, A, B, {cell, seed})      seeded block dissolve
  push(u, A, B, {dir})                 A slides out, B slides in
  blinds(u, A, B, {bands, angle, stagger})
  zoomDip(u, A, B, {zoom})             dip-through-black beat cut (no flash)

GLSL transitions (per-pixel; SwiftShader on the delivery path, deterministic)
  const fx = lib.shaderTransition("dissolve"); ctx.drawImage(fx.render(u, canvasA, canvasB), 0, 0)
  names: dissolve glitch zoomBlur kaleido shockwave lightLeak warpMorph
  (half-size FX canvas: { width: lib.W/2, height: lib.H/2 } — upscales cleanly, ~4x faster)

post effects
  glow(ctx, src, {radius, strength, threshold})      bloom (half-res blur + screen)
  duotone(ctx, src, {dark, light, amount})           luminance → two-colour ramp (SVG filter)
  lightLeak(ctx, t, {color, seed, amount})           drifting analog leak (screen blend)
  shimmer(ctx, t, src, {period, width, angle})       light sweep over src's pixels, loops at period

kinetic type (with lib.layoutText + ctx.fillStyle set first)
  drawKinetic(ctx, lay, t, {mode: rise|pop|wave|cascade|jitter, stagger, dur})
  glyphAnim(i, n, t, opts)                           the per-glyph primitive (compose your own)

particles (seeded, clip to area — box() or {x,y,w,h}; seamless loops)
  particles(ctx, t, {mode: drift|rise|fall|orbit|stream, n, seed, area, size, life, color(s), twinkle})
  fall = confetti (colours default to a seeded harmony of color)

text markers (box from a layout: lib.box(lay.x0, lay.y - lay.ascent, lay.x1, lay.y + lay.descent))
  marker(ctx, box, t, {mode: highlight|underline|circle|strike|brackets, color, draw, hold})

colour
  harmony("#E4572E", {scheme, count, seed})          analogous|complementary|split|triad|tetrad|mono
  ramp([[0, "#0a0e2a"], [1, "#ff9a3c"]], u)          gradient lookup → hex
  box(x0, y0, x1, y1)                                the rect value object areas/markers take
EOF
  exit 0
fi

# ── --palette: run lib.js's own harmony() — the printed palette is exactly what a scene draws
if [ "$cmd" = palette ]; then
  [[ "$hex" =~ ^#?[0-9a-fA-F]{6}$ ]] || die "palette takes a 6-digit hex colour, not '$hex'"
  [[ "$scheme" =~ ^(analogous|complementary|split|triad|tetrad|mono)$ ]] || die "unknown scheme '$scheme' (analogous|complementary|split|triad|tetrad|mono)"
  [[ "$count" =~ ^[1-9][0-9]*$ ]] || die "--count takes a whole number ≥ 1"
  [[ "$seed" =~ ^[0-9]+$ ]] || die "--seed takes a number"
  node --input-type=module -e '
    import * as lib from "'"$ROOT"'/styles/_swatch/lib.js";
    const cols = lib.harmony("'"${hex#\#}"'".replace(/^#?/, "#"), { scheme: "'"${scheme}"'", count: '"$count"', seed: '"$seed"' });
    console.log(cols.join(" "));
    console.log(cols.map((c) => `  ${c}  luminance ${lib.luminance(c).toFixed(3)}`).join("\n"));
  ' || die "lib.js harmony() failed — is styles/_swatch/lib.js intact?"
  exit 0
fi

# ── --styles: the style presets
if [ "$cmd" = styles ]; then
  [ -d "$ROOT/styles" ] || die "no styles/ directory"
  for d in "$ROOT"/styles/*/; do
    s=$(basename "$d"); [ "$s" = "_swatch" ] && continue
    [ -f "$d/swatch.js" ] || [ -f "$d/swatch.py" ] || continue
    if [ -f "$d/media/swatch.mp4" ]; then echo "$s"; else echo "$s (no rendered swatch yet)"; fi
  done
  exit 0
fi

# ── binary resolution for the registry commands (same ladder as tools/hf_speed.sh)
HF_VER=${HYPERFRAMES_VERSION:-0.8.82}
if [ "$cmd" = blocks ] || [ "$cmd" = add ]; then
  if [ -n "${HYPERFRAMES_BIN:-}" ]; then
    command -v "${HYPERFRAMES_BIN%% *}" >/dev/null 2>&1 || die "HYPERFRAMES_BIN not executable: $HYPERFRAMES_BIN"
    HF=("${HYPERFRAMES_BIN%% *}"); HF[0]=$(cd "$(dirname "${HF[0]}")" && pwd)/$(basename "${HF[0]}")
  elif [ -n "$dir" ] && [ -x "$dir/node_modules/.bin/hyperframes" ]; then HF=("$dir/node_modules/.bin/hyperframes")
  elif [ -x "$ROOT/styles/_swatch/node_modules/.bin/hyperframes" ]; then HF=("$ROOT/styles/_swatch/node_modules/.bin/hyperframes")
  elif command -v npx >/dev/null 2>&1; then HF=(npx --yes "hyperframes@$HF_VER")
  else die "hyperframes not found: HYPERFRAMES_BIN, a project pin (bin/vh hf-init), or npx"; fi
fi

# ── --blocks: browse/search the registry
if [ "$cmd" = blocks ]; then
  if [ -n "$query" ]; then
    (cd "$ROOT" && exec env HYPERFRAMES_SKIP_SKILLS=1 DO_NOT_TRACK=1 "${HF[@]}" catalog --query "$query")
  else
    (cd "$ROOT" && exec env HYPERFRAMES_SKIP_SKILLS=1 DO_NOT_TRACK=1 "${HF[@]}" catalog)
  fi
  exit $?
fi

# ── --add: install a block into a project
if [ "$cmd" = add ]; then
  [ -n "$block" ] || die "--add takes a block name (browse with --blocks)"
  [ -n "$dir" ] || die "--add takes a project directory (bin/vh hf-init <dir>)"
  [ -d "$dir" ] || die "no such directory: $dir"
  [ -f "$dir/index.html" ] || die "$dir has no index.html — not a HyperFrames project (bin/vh hf-init <dir>)"
  dir=$(cd "$dir" && pwd) || exit 2
  (cd "$dir" && exec env HYPERFRAMES_SKIP_SKILLS=1 DO_NOT_TRACK=1 "${HF[@]}" add "$block")
  exit $?
fi

# ── --demo: the test card (draft by default; --final for the delivery-quality pass)
if [ "$cmd" = demo ]; then
  flags=(--draft); [ "$final" = 1 ] && flags=()
  (cd "$ROOT/styles/_swatch" && exec ./render.sh catalog-fx "${flags[@]}")
  exit $?
fi
