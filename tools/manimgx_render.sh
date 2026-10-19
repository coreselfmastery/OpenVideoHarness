#!/usr/bin/env bash
# Render a ManimGX scene unless it is already rendered: a content hash of the scene (the .py files
#   beside it, the scene name, the render flags, the manimgx and Python versions) names the render,
#   and a matching <output>.render.json beside an existing MP4 is a cache hit — the render is
#   skipped and the file is used as is. Change an animation, a flag or the engine version and the
#   hash moves: it renders again. This is the "skip unchanged scenes between drafts" lever
#   (engines/manimgx-advanced.md, H2); the engine itself does not compare scene versions.
# usage: tools/manimgx_render.sh [--force] <scene.py> <Scene> [manimgx render flags…]
#   e.g. tools/manimgx_render.sh scenes/fourier.py FourierScene -r 854x480 --fps 15 --preset veryfast
#   --force   render again and refresh the manifest (the storyboard PNG is not versioned: it is
#             rewritten only on a real render)
#   Runs `uv run manimgx render` from the scene's directory (uv finds the project's pyproject.toml
#   upwards; bin/vh new math scaffolds one). Output: -o/--output if given, else <Scene>.mp4 beside
#   the scene. The manifest lands beside the output as <output>.render.json.
# Exit status: 0 cache hit or rendered · 1 the render failed (manifest not written) ·
#   2 could not start (file not found, not a uv project, no uv).
# The text-layout cache inside the engine is separate (MANIMGX_CACHE_DIR, engines/manimgx-advanced.md H1).
set -uo pipefail
unset CDPATH

force=0
if [ "${1:-}" = "--force" ]; then force=1; shift; fi
[ $# -ge 2 ] || { sed -n '3,15p' "$0"; exit 2; }
scene_path=$1; scene_name=$2; shift 2
flags=()
while [ $# -gt 0 ]; do flags+=("$1"); shift; done

[ -f "$scene_path" ] || { printf 'scene not found: %s\n' "$scene_path" >&2; exit 2; }
scene_dir=$(cd "$(dirname "$scene_path")" && pwd) || exit 2
scene_file=$scene_dir/$(basename "$scene_path")

if ! command -v uv >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/uv" ]; then
  printf 'uv not found: curl -LsSf https://astral.sh/uv/install.sh | sh\n' >&2; exit 2
fi
uv_run() {
  if command -v uv >/dev/null 2>&1; then uv run "$@"; else "$HOME/.local/bin/uv" run "$@"; fi
}

# the versions are part of the hash: an engine upgrade re-renders
gx_ver=$( ( cd "$scene_dir" && uv_run manimgx --version ) 2>/dev/null | tail -1 ) || exit 2
[ -n "$gx_ver" ] || { printf 'not a ManimGX project (no uv project around %s)\n' "$scene_dir" >&2; exit 2; }
py_ver=$( ( cd "$scene_dir" && uv_run python --version ) 2>/dev/null | tail -1 )

# output path: -o/--output if given (relative to the scene dir), else <Scene>.mp4 beside the scene
out_flag=""
for ((i = 0; i < ${#flags[@]}; i++)); do
  case "${flags[i]}" in
    -o|--output) out_flag=${flags[i + 1]:-} ;;
    -o=*|--output=*) out_flag=${flags[i]#*=} ;;
  esac
done
output=$( cd "$scene_dir" && printf '%s/%s' "$(pwd)" "${out_flag:-$scene_name.mp4}" )
manifest=$output.render.json

# the hash: the scene file and every .py beside it, the scene name, the flags, the versions
hash_stream() {
  local f
  printf 'scene=%s\n' "$scene_name"
  printf 'flags=%s\n' "${flags[*]:-}"
  printf '%s\n%s\n' "$gx_ver" "$py_ver"
  for f in "$scene_file" "$scene_dir"/*.py; do
    [ -f "$f" ] || continue
    printf 'file=%s\n' "$(basename "$f")"
    sha256sum "$f" | cut -d' ' -f1
  done
}
new_hash=$(hash_stream | sha256sum | cut -c1-16)

hit() {  # manifest matches, hash matches, output exists and is not empty (system python3: no uv spin-up)
  [ -s "$output" ] && [ -f "$manifest" ] \
    && [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hash"])' "$manifest" 2>/dev/null)" = "$new_hash" ]
}

if [ $force = 0 ] && hit; then
  printf 'cache hit: %s (hash %s, %s) — render skipped\n' "$output" "$new_hash" "$gx_ver"
  exit 0
fi

printf 'rendering (hash %s, %s)…\n' "$new_hash" "$gx_ver"
( cd "$scene_dir" && uv_run manimgx render "$(basename "$scene_path")" "$scene_name" "${flags[@]}" ) \
  || { printf 'render failed; manifest not written\n' >&2; exit 1; }
[ -s "$output" ] || { printf 'render exited 0 but %s is missing\n' "$output" >&2; exit 1; }

# manifest: what was rendered, from what, when (args via files to keep the JSON honest)
cmdfile=$(mktemp) || exit 1
printf '%s\n' "$scene_name" > "$cmdfile"
printf '%s\n' "${flags[@]:-}" >> "$cmdfile"
( cd "$scene_dir" && uv_run python - "$manifest" "$new_hash" "$output" "$gx_ver" "$py_ver" "$cmdfile" "$scene_dir" << 'PYEOF'
import datetime, json, os, sys
manifest, digest, output, gx, py, cmdfile, scene_dir = sys.argv[1:8]
cmd = [l.rstrip("\n") for l in open(cmdfile)]
files = sorted(f for f in os.listdir(scene_dir) if f.endswith(".py"))
json.dump({
    "hash": digest,
    "engine": gx,
    "python": py,
    "scene": cmd[0],
    "flags": cmd[1:],
    "hashed_files": files,
    "output": os.path.basename(output),
    "bytes": os.path.getsize(output),
    "rendered_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
}, open(manifest, "w"), indent=2, ensure_ascii=False)
PYEOF
) || exit 1
rm -f "$cmdfile"
printf 'rendered: %s (hash %s, manifest %s)\n' "$output" "$new_hash" "$manifest"
