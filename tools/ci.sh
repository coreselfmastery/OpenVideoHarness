#!/usr/bin/env bash
# ci.sh — the repo's own checks: the same run locally before a push and in GitHub Actions (.github/workflows/ci.yml).
#
#   tools/ci.sh                      everything the installed tools allow (shellcheck, pyflakes, ffmpeg are optional locally)
#   tools/ci.sh --smoke              only the bin/vh smoke tests
#   tools/ci.sh --committed          check HEAD in a clean temporary checkout: what a push sends, not the working tree
#   VH_BASH=/bin/bash tools/ci.sh    run bin/vh and the syntax checks under another bash (macOS ships bash 3.2)
#
# Why each group exists: the v0.2.1 review found macOS-only sed/stat/md5 flags that broke every Linux user, a
# doc/CLI mismatch, and a CLI that exited 0 on typos. These checks keep those from coming back.
# Exit status: the number of failed checks (0 = all passed).
set -uo pipefail
unset CDPATH   # an exported one could send this relative cd elsewhere (as in bin/vh)
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
ROOT=$(pwd)
VH_BASH=${VH_BASH:-bash}
fails=0
ok() { printf '\033[32m✓\033[0m %s\n' "$*"; }
bad() { printf '\033[31m✗\033[0m %s\n' "$*"; fails=$((fails + 1)); }
skipped=""
skip() { printf '\033[33m-\033[0m %s (skipped: %s)\n' "$1" "$2"; skipped="$skipped${skipped:+, }$1"; }
files() { git ls-files "$@" | grep -v -E '^references/|(^|/)node_modules/|\.min\.js$'; }

static_checks() {
  local f n out
  # shell: parse with the bash that will run it, lint, and ban commands that only exist on one platform
  n=0; while IFS= read -r f; do "$VH_BASH" -n "$f" || { bad "bash -n $f"; n=$((n + 1)); }; done < <(files bin/vh '*.sh')
  [ $n = 0 ] && ok "shell syntax ($("$VH_BASH" -c 'echo $BASH_VERSION'))"
  if command -v shellcheck >/dev/null; then
    if out=$(files bin/vh '*.sh' | xargs shellcheck -S warning 2>&1); then ok "shellcheck -S warning"; else echo "$out"; bad "shellcheck"; fi
  else skip "shellcheck" "not installed; CONTRIBUTING.md shows how to run it through uv"; fi
  # BSD-only or GNU-only flags, matched where a command starts: a statement start, a pipe, after if / while / until / do /
  # then / else, after `{`, `(`, `!` or a case arm, and behind a wrapper (xargs, sudo, exec, env, time, nohup, nice, command)
  # with its flags, VAR=value tokens or arguments. A small quote-aware scanner blanks comments, single-quoted strings,
  # double-quoted strings without $ or backticks, and heredoc bodies first (line numbers kept): a heredoc opens only at a
  # `<<name` outside quotes and comments with whitespace before it (not `<<<`, `1<<n` or a `<<EOF` in a comment), and its
  # terminator is matched ignoring leading tabs and trailing blanks, so a stray `<<` cannot blank the rest of a file.
  # A line may opt out with a trailing "# portable-ok: <why>"
  local np='(^|[;&|(){}!`]|\$\()[[:space:]]*((if|while|until|do|then|else|elif|xargs|sudo|exec|env|time|nohup|nice|command)([[:space:]]+(-[^[:space:]]*|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|[A-Za-z0-9_.{}-]+))*[[:space:]]+)*(sed -i|stat -[cf] |md5 -q|md5sum|readlink -f|grep -[a-zA-Z]*P|date -[djv] |xargs -r|find [^;|]*-printf|base64 -D|sort -V|tac( |$))'   # portable-ok: the list itself
  local awkprog=''; IFS= read -r -d '' awkprog <<'AWK' || true   # a heredoc, not $(…): the awk text has a backtick
BEGIN { term = "" }
term != "" { t = $0; sub(/^\t+/, "", t); sub(/[ \t]+$/, "", t); if (t == term) term = ""; print ""; next }
/portable-ok/ { print ""; next }
{ line = $0; out = ""; q = ""; buf = ""; n = length(line); i = 1
  while (i <= n) {
    c = substr(line, i, 1)
    if (q == "") {
      if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t;]/)) break
      if (c == "\\") { out = out c substr(line, i + 1, 1); i += 2; continue }
      if (c == "'" || c == "\"") { q = c; buf = ""; i++; continue }
      if (c == "<" && substr(line, i, 2) == "<<" && substr(line, i + 2, 1) != "<" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t]/)) {
        rest = substr(line, i + 2); sub(/^-/, "", rest)
        if (match(rest, /^["']?[A-Za-z_][A-Za-z0-9_]*/)) { term = substr(rest, RSTART, RLENGTH); gsub(/["']/, "", term) }
      }
      out = out c; i++
    } else {
      if (q == "\"" && c == "\\") { buf = buf c substr(line, i + 1, 1); i += 2; continue }
      if (c == q) { out = out ((q == "\"" && buf ~ /[$`]/) ? q buf q : q q); q = ""; i++; continue }
      buf = buf c; i++
    }
  }
  print out }
AWK
  out=$(while IFS= read -r f; do awk "$awkprog" "$f" | grep -n -E "$np" | sed "s#^#$f:#"; done < <(files bin/vh '*.sh'))
  if [ -n "$out" ]; then echo "$out"; bad "non-portable shell commands (use a helper that works with both BSD and GNU tools)"
  else ok "no BSD-only / GNU-only shell commands"; fi
  # python: compile everything, then pyflakes when available
  n=0; while IFS= read -r f; do python3 -m py_compile "$f" 2>/dev/null || { bad "py_compile $f"; n=$((n + 1)); }; done < <(files 'tools/*.py' 'styles/_swatch/*.py' 'styles/*/swatch.py')
  [ $n = 0 ] && ok "python syntax"
  if python3 -m pyflakes --version >/dev/null 2>&1; then
    if out=$(files 'tools/*.py' 'styles/_swatch/*.py' 'styles/*/swatch.py' | xargs python3 -m pyflakes 2>&1); then ok "pyflakes"; else echo "$out"; bad "pyflakes"; fi
  else skip "pyflakes" "not installed; CONTRIBUTING.md shows how to run it through uv"; fi
  # Blender style scenes: the static check render.sh runs before Blender (no os, subprocess, open, random, handlers …),
  # and the GPL header every file that imports bpy carries (engines/blender.md, "许可证")
  n=0; while IFS= read -r f; do
    python3 styles/_swatch/blender_prep.py scan "$f" || { bad "blender_prep.py scan $f"; n=$((n + 1)); }
  done < <(files 'styles/*/swatch.py')
  out=$(files '*.py' | python3 -c '
import ast, sys
BLENDER = {"bpy", "bmesh", "mathutils", "bpy_extras", "gpu", "gpu_extras", "freestyle", "bl_math", "idprop", "aud", "imbuf", "blf", "bgl"}
for f in sys.stdin.read().splitlines():
    src = open(f, encoding="utf-8").read()
    try: tree = ast.parse(src, f)
    except SyntaxError: continue
    mods = {a.name.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.Import) for a in n.names}
    mods |= {(n.module or "").split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.ImportFrom)}
    if mods & BLENDER and "SPDX-License-Identifier: GPL-3.0-or-later" not in "".join(src.splitlines(True)[:3]): print(f)
')
  [ -z "$out" ] || { echo "$out" | sed 's/$/: imports a Blender module but has no GPL-3.0-or-later SPDX header in its first 3 lines/'; n=$((n + 1)); bad "GPL header on Blender scripts"; }
  [ $n = 0 ] && ok "Blender scenes: static check and GPL headers"
  # js: node --check detects ES modules by syntax (node ≥ 22)
  n=0; while IFS= read -r f; do node --check "$f" 2>/dev/null || { node --check "$f"; bad "node --check $f"; n=$((n + 1)); }; done < <(files '*.js' '*.mjs')
  [ $n = 0 ] && ok "js syntax"
  # media: videos live in the GitHub release "media" (tools/media.txt, tools/fetch_media.sh), so a clone stays small;
  # the style swatches (about 1 MB each, read by the tools) are the one exception. No file over 8 MB either.
  out=$(files | while IFS= read -r f; do
      lc=$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]')   # [[ ]], not case: bash 3.2 can't parse case inside $( ); lower-cased: .GIF too
      if [[ ! "$f" =~ ^styles/[^/]+/media/swatch\.mp4$ && "$lc" =~ \.(mp4|mov|webm|mkv|gif)$ ]]; then echo "$f: a video (put it in the media release, see tools/fetch_media.sh)"; continue; fi
      if [ -f "$f" ]; then s=$(wc -c < "$f"); [ "$s" -gt 8000000 ] && echo "$f: $((s / 1000000)) MB, over 8 MB"; fi
    done)
  if [ -n "$out" ]; then echo "$out"; bad "videos or large files in git"; else ok "no videos or files over 8 MB in git"; fi
}

doc_checks() {
  local head
  head=$(head -3 AGENTS.md)
  if [ "$(tail -n +4 AGENTS.md)" = "$(cat CLAUDE.md)" ] && [ -n "$head" ]; then ok "AGENTS.md generated from CLAUDE.md"
  else bad "AGENTS.md is out of sync with CLAUDE.md: run bin/vh sync-agents"; fi
  # every `bin/vh <command>` in the docs exists, and CLAUDE.md's command list names exactly the commands bin/vh dispatches
  if python3 - <<'PY'
import re, subprocess, sys
src = open("bin/vh", encoding="utf-8").read()
block = src[src.index('case "${1:-help}" in'):]
block = block[:block.index("\nesac")]
cmds = {c for pat in re.findall(r"(?:^|;;)\s*([a-z|-]+)\)", block, re.M) for c in pat.split("|") if c and not c.startswith("-")}
cmds.discard("help")
listed = set(re.search(r"命令行：(.+)", open("CLAUDE.md", encoding="utf-8").read()).group(1).split(" · "))
bad = []
if listed != cmds:
    bad.append(f"CLAUDE.md command list vs bin/vh dispatch: missing {sorted(cmds - listed)}, unknown {sorted(listed - cmds)}")
docs = subprocess.run(["git", "ls-files", "*.md"], capture_output=True, text=True).stdout.split()
for d in docs:   # commands written as code: inside `backticks` or a fenced block (prose like "bin/vh · QA tools" is a label)
    if d.startswith("references/") or d == "CHANGELOG.md":
        continue
    fence = False
    for n, line in enumerate(open(d, encoding="utf-8"), 1):
        if line.lstrip().startswith("```"):
            fence = not fence; continue
        for code in [line] if fence else re.findall(r"`([^`]*)`", line):
            for c in re.findall(r"bin/vh ([a-z][a-z-]*)", code):
                if c not in cmds and c != "help":
                    bad.append(f"{d}:{n}: bin/vh {c} is not a command")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
  then ok "docs name only real bin/vh commands"; else bad "docs vs bin/vh commands"; fi
}

readpath_report() {   # how much an agent reads before it starts, per effort level and type: printed as a baseline, no limit yet
  local out
  if out=$(python3 tools/readpath.py 2>&1); then printf '%s\n' "$out" | sed 's/^/  /'; ok "read path printed above (a baseline; no limit yet)"
  else echo "$out"; bad "tools/readpath.py"; fi
}

vh() { "$VH_BASH" "$ROOT/bin/vh" "$@"; }
smoke_checks() {
  local slug="ci-smoke-$$" dir t rc langs a h o
  vh help >/dev/null && vh --help >/dev/null && ok "bin/vh help exits 0" || bad "bin/vh help"
  vh no-such-command >/dev/null 2>&1; rc=$?; [ $rc = 1 ] && ok "unknown command exits 1" || bad "unknown command exited $rc"
  t=$(mktemp -d "${TMPDIR:-/tmp}/vh-ci.XXXXXX")   # a throwaway HOME: an old bin/vh would install the skill for a bad target
  HOME="$t" vh install-skill no-such-target >/dev/null 2>&1; rc=$?; [ $rc = 1 ] && ok "install-skill rejects unknown targets" || bad "install-skill bad target exited $rc"
  rm -rf "$t"
  vh types >/dev/null && vh effort quick >/dev/null && vh style list >/dev/null && ok "types · effort · style list" || bad "types / effort / style list"
  # effort: the table comes from playbook/01, the caps and the floors from CLAUDE.md (a renamed heading must not drop them)
  a=$(vh effort studio 2>&1)
  case "$a" in *"独立评审"*"评审有上限"*"任何档位都不降"*"bin/vh check"*) ok "effort studio prints its column, the review caps and the floors" ;;
    *) bad "effort studio: table, caps or floors missing" ;; esac
  # -h prints a usage and exits 0 without running the command (setup -h used to install everything, sync-agents -h rewrote
  # AGENTS.md, and others took -h as a video, project or preset name). Every dispatched command without a help of its own
  # is tried, on a copy of bin/vh whose ROOT has only tools/ and with uv and npm stubbed out: if the check ever broke, setup
  # would stop at its first cd and nothing would be downloaded
  local cmds n
  cmds=$(python3 - <<'PY'
import re, sys
src = open("bin/vh", encoding="utf-8").read()
block = src[src.index('case "${1:-help}" in'):]
block = block[:block.index("\nesac")]
cmds = {c for pat in re.findall(r"(?:^|;;)\s*([a-z|-]+)\)", block, re.M) for c in pat.split("|") if c and not c.startswith("-")} - {"help"}
own = set(re.search(r'case "\$1" in ([a-z|-]+)\) ;;   # these print their own', src).group(1).split("|"))
if own - cmds: sys.exit(f"own-help list names commands bin/vh does not dispatch: {sorted(own - cmds)}")
print(" ".join(sorted(cmds - own)))
PY
) || bad "bin/vh's own-help list"
  t=$(mktemp -d "${TMPDIR:-/tmp}/vh-ci.XXXXXX"); mkdir "$t/bin" "$t/stub"; cp bin/vh "$t/bin/vh"; ln -s "$ROOT/tools" "$t/tools"
  printf '#!/bin/sh\nexit 1\n' > "$t/stub/uv"; cp "$t/stub/uv" "$t/stub/npm"; chmod +x "$t/stub/uv" "$t/stub/npm"
  rc=0; for a in $cmds "style check"; do
    for h in -h --help; do
      # shellcheck disable=SC2086   # "style check" is two words on purpose
      o=$(HOME="$t" PATH="$t/stub:$PATH" "$VH_BASH" "$t/bin/vh" $a "$h" 2>&1) && case "$o" in "usage: bin/vh $a "*) continue ;; esac
      bad "bin/vh $a $h: '$(printf '%s' "$o" | head -1)'"; rc=1
    done
  done; rm -rf "$t"
  n=$(printf '%s\n' $cmds | grep -c .)
  if [ $rc = 1 ]; then :; elif [ "$n" -gt 5 ]; then ok "-h and --help print a usage for the $n commands without a help of their own, and style check"
  else bad "only $n commands found in bin/vh's dispatch for the -h check"; fi
  # a project: effort and style are written in, and the quick gate waiver is recorded
  dir=$(ls -d "$ROOT"/projects/*-"$slug" 2>/dev/null); [ -z "$dir" ] || rm -rf "$dir"
  if vh new math "$slug" --effort quick --style dark-math >/dev/null; then
    dir=$(ls -d "$ROOT"/projects/*-"$slug")
    grep -q '^- Effort: quick' "$dir/BRIEF.md" && grep -q 'Effort: quick' "$dir/REVIEW.md" && [ -f "$dir/style-refs/dark-math/STYLE.md" ] \
      && grep -q '^- Style refs (repo presets): `styles/dark-math`' "$dir/BRIEF.md" && ! grep -q '^## Style preset' "$dir/BRIEF.md" \
      && ok "bin/vh new --effort quick --style" || bad "bin/vh new: effort or style not written into the project"
    # the type doc is named, not pasted, and the marker tools/vhdraw.py reads for the type is there
    grep -q '^- Type doc: `video-types/01-math-science-explainer.md`' "$dir/BRIEF.md" && grep -q '^<!-- from 01-math-science-explainer.md -->$' "$dir/BRIEF.md" \
      && ! grep -q '^+ TYPE:' "$dir/BRIEF.md" && ok "bin/vh new names the type doc and keeps the type marker" || bad "bin/vh new: Type doc line or type marker missing"
    rm -rf "$dir"
  else bad "bin/vh new math"; fi
  # --engine canvas-film: the canvas engine's template instead of the type's engine (nothing to install), 16:9 for any type
  t=$(mktemp -d "${TMPDIR:-/tmp}/vh-ci.XXXXXX")
  if vh new short cf --engine canvas-film --dir "$t" >/dev/null; then
    dir=$(ls -d "$t"/*-cf)
    [ -f "$dir/film.html" ] && [ -f "$dir/src/50-shots.js" ] && [ -f "$dir/audio/timeline.zh.json" ] && [ -f "$dir/ENGINE_README.md" ] && [ ! -e "$dir/index.html" ] \
      && grep -q '^- Output: 1920x1080,' "$dir/BRIEF.md" && grep -q '^- Engine: canvas-film' "$dir/BRIEF.md" \
      && ok "bin/vh new --engine canvas-film copies the engine's template at 1920x1080" || bad "bin/vh new --engine canvas-film: the template or the BRIEF's Output and Engine lines are missing"
  else bad "bin/vh new short --engine canvas-film"; fi
  vh new short cf2 --engine canvas-film --aspect 9:16 --dir "$t" >/dev/null 2>&1; rc=$?
  vh new short cf3 --engine no-such --dir "$t" >/dev/null 2>&1; a=$?
  [ $rc = 1 ] && [ $a = 1 ] && [ -z "$(ls -d "$t"/*-cf2 "$t"/*-cf3 2>/dev/null)" ] && ok "bin/vh new refuses a vertical canvas-film and an unknown --engine" \
    || bad "bin/vh new --engine: --aspect 9:16 exited $rc, an unknown engine $a"
  rm -rf "$t"
  # tts picks the uv dependencies from --provider too (a fake uv prints the command instead of running it)
  t=$(mktemp -d "${TMPDIR:-/tmp}/vh-ci.XXXXXX"); printf '#!/bin/sh\necho "$*"\n' > "$t/uv"; chmod +x "$t/uv"
  a=$(PATH="$t:$PATH" vh tts "$t" --provider edge --lang en; PATH="$t:$PATH" vh tts "$t" --provider=dashscope)
  case "$a" in *"--with edge-tts "*"--provider edge"*"--with dashscope "*) ok "tts --provider picks the provider's dependencies" ;;
    *) bad "tts --provider: uv got '$a'" ;; esac
  rm -rf "$t"
  # tts: a Gemini 429 that names a per-day quota fails at once, though it asks for 30 s; a per-minute one is still waited
  # out and retried; one naming no daily quota fails at once only past 90 s (a stub on 127.0.0.1; waits recorded, not slept)
  if a=$(GEMINI_API_KEY=ci-stub python3 - 2>&1 <<'PY'
import importlib.util, json, os, threading
os.environ["no_proxy"] = "127.0.0.1"   # urlopen would send the stub's requests through an http_proxy
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
spec = importlib.util.spec_from_file_location("tts", "tools/audio/tts.py"); tts = importlib.util.module_from_spec(spec); spec.loader.exec_module(tts)
def body(*ids, delay="30s"):
    return json.dumps({"error": {"code": 429, "status": "RESOURCE_EXHAUSTED", "details": [
        {"@type": "type.googleapis.com/google.rpc.QuotaFailure", "violations": [{"quotaMetric": "generativelanguage.googleapis.com/x", "quotaId": i} for i in ids]},
        {"@type": "type.googleapis.com/google.rpc.RetryInfo", "retryDelay": delay}]}}).encode()
answers = []
class Stub(BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers["Content-Length"])); code, b = answers.pop(0)
        self.send_response(code); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
srv = ThreadingHTTPServer(("127.0.0.1", 0), Stub); threading.Thread(target=srv.serve_forever, daemon=True).start()
tts.GEMINI_API = f"http://127.0.0.1:{srv.server_address[1]}"
waits = []; tts.time.sleep = waits.append
minute, day = "GenerateRequestsPerMinutePerProjectPerModel", "GenerateRequestsPerDayPerProjectPerModel"
answers[:] = [(429, body(minute, day)), (200, b"{}")]
try:
    tts.gemini_call("interactions", {}); raise SystemExit(f"a per-day 429 was retried (waits {waits})")
except tts.GeminiError as e:
    assert not waits and len(answers) == 1 and day in str(e) and "--resume" in str(e), (waits, str(e))
answers[:] = [(429, body(minute)), (429, body(minute)), (200, b'{"ok": 1}')]
assert tts.gemini_call("interactions", {}) == {"ok": 1} and waits == [31.0, 31.0], waits
answers[:] = [(429, body(minute, delay="120s")), (200, b"{}")]; waits.clear()
try:
    tts.gemini_call("interactions", {}); raise SystemExit("a 429 asking for 120 s was retried")
except tts.GeminiError:
    assert not waits and len(answers) == 1, waits
PY
); then ok "tts: a Gemini 429 naming a per-day quota fails at once; a per-minute one is retried; past 90 s fails at once"
  else bad "tts: Gemini 429 handling: $a"; fi
  # recipes: every recipe's frontmatter validates, list filters agree with the files, bad values are errors
  vh recipes check >/dev/null && ok "recipes check (frontmatter, README index, sketches)" || bad "bin/vh recipes check"
  a=$(vh recipes list --intent carry,enter --energy 5 --engine three --ids)
  if python3 - "$a" <<'PY'
import pathlib, re, sys   # the expectation, read straight from the files with plain regexes (not tools/recipes.py)
want = set()
for p in pathlib.Path("recipes").glob("*/*.md"):
    t = p.read_text(encoding="utf-8")
    f = lambda k: re.findall(r"[a-z0-9-]+", (re.search(rf"^{k}: (.*)$", t, re.M) or [None, ""])[1])
    e = [int(x) for x in f("energy")]
    if p.parent.name != "sequences" and e and {"carry", "enter"} & set(f("intent")) and min(e) <= 5 <= max(e) and "three" in f("engines"):
        want.add(f("id")[0])
got = set(sys.argv[1].split())
sys.exit(0 if want and got == want else 1)
PY
  then ok "recipes list --intent --energy --engine match the files"; else bad "recipes list filters: got '$(echo $a)'"; fi
  vh recipes list --intent no-such-intent >/dev/null 2>&1; rc=$?; [ $rc = 2 ] && ok "recipes list rejects an unknown vocabulary value" || bad "recipes list --intent no-such-intent exited $rc"
  t=$(mktemp -d "${TMPDIR:-/tmp}/vh-ci.XXXXXX")
  sed 's/^id: .*/id: ci-copy/' recipes/seam/flash-cut.md > "$t/ok.md"; sed 's/^energy: .*/energy: 9/' "$t/ok.md" > "$t/bad.md"
  a=$(vh recipes check "$t/bad.md" 2>&1); rc=$?
  vh recipes check "$t/ok.md" >/dev/null && [ $rc = 1 ] && case "$a" in *energy*) true ;; *) false ;; esac \
    && ok "recipes check passes a valid copy and names the bad field" || bad "recipes check on a copy (bad one exited $rc)"
  sed 's/^qa: .*/qa: {peak:4}/' "$t/ok.md" > "$t/yaml.md"   # YAML reads {peak:4} as one key, "peak:4"
  a=$(vh recipes check "$t/yaml.md" 2>&1); rc=$?
  [ $rc = 1 ] && case "$a" in *"space after"*) true ;; *) false ;; esac \
    && ok "recipes check refuses frontmatter that YAML would read differently" || bad "recipes check on {peak:4} exited $rc"
  vh recipes check --json >/dev/null 2>&1; rc=$?
  [ $rc = 2 ] && ok "recipes check treats an option as bad usage" || bad "recipes check --json exited $rc"
  rm -rf "$t"
  if ! command -v ffmpeg >/dev/null; then skip "mux / gif smoke" "ffmpeg not installed"; return; fi
  # subtitle languages come from the file name, never from folders (a home dir like /home/zhang used to tag everything chi)
  t=$(mktemp -d "${TMPDIR:-/tmp}/vh-ci.XXXXXX"); mkdir -p "$t/zhang/en.v1.2"
  ffmpeg -nostdin -v error -f lavfi -i color=c=black:s=64x64:d=1 -pix_fmt yuv420p -f mp4 "$t/zhang/en.v1.2/final" \
    && ffmpeg -nostdin -v error -f lavfi -i sine=d=0.5 "$t/a.wav" \
    && printf '1\n00:00:00,000 --> 00:00:00,900\nhi\n' | tee "$t/zhang/captions.en.srt" "$t/zhang/captions.zh.srt" "$t/zhang/en.v1.2/subs.srt" >/dev/null
  if vh mux "$t/zhang/en.v1.2/final" "$t/a.wav" "$t/out.mp4" "$t/zhang/captions.en.srt" "$t/zhang/captions.zh.srt" "$t/zhang/en.v1.2/subs.srt" >/dev/null; then
    langs=$(ffprobe -v error -select_streams s -show_entries stream_tags=language -of csv=p=0 "$t/out.mp4" | tr '\n' ' ')
    [ "$langs" = "eng chi und " ] && ok "mux tags subtitle languages by file name" || bad "mux subtitle languages: got '$langs', want 'eng chi und'"
    a=$(ffprobe -v error -select_streams a -show_entries stream=duration -of csv=p=0 "$t/out.mp4"); python3 -c "import sys; sys.exit(0 if abs(float('$a') - 1) < 0.05 else 1)" \
      && ok "mux pads short audio to the video length" || bad "mux audio duration $a, want 1.0"
  else bad "bin/vh mux"; fi
  # no subtitle files: an empty array under set -u, which bash before 4.4 (macOS /bin/bash) treats as unbound
  vh mux "$t/zhang/en.v1.2/final" "$t/a.wav" "$t/out-nosubs.mp4" >/dev/null && [ -s "$t/out-nosubs.mp4" ] \
    && ok "mux without subtitle files" || bad "bin/vh mux without subtitle files"
  vh gif "$t/zhang/en.v1.2/final" 64 5 >/dev/null && [ -f "$t/zhang/en.v1.2/final.gif" ] && ok "gif names the output after the file, not a dotted folder" || bad "bin/vh gif output name"
  # bin/vh deliver: a 2 s master with sound and a subtitle track, cut to fit 0.5 MB (a ceiling worked out from the size),
  # a keyframe every 2 s, BT.709 tags, the tracks copied, the PSNR measured; a limit too small to hold a picture is refused
  ffmpeg -nostdin -v error -f lavfi -i "testsrc2=s=320x180:r=30:d=2" -f lavfi -i "sine=d=2" -c:v libx264 -crf 10 -pix_fmt yuv420p \
    -color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709 -c:a aac -shortest "$t/m0.mp4" \
    && vh mux "$t/m0.mp4" "$t/a.wav" "$t/master.mp4" "$t/zhang/captions.zh.srt" >/dev/null
  a=$(vh deliver "$t/master.mp4" --max-gb 0.0005 --samples 2 2>&1); rc=$?
  if [ $rc = 0 ] && [ -s "$t/master.upload.mp4" ] && printf '%s' "$a" | grep -q 'PSNR against the master' && python3 - "$t/master.upload.mp4" <<'PY'
import json, os, subprocess, sys
f = sys.argv[1]
st = json.loads(subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-of", "json", f], capture_output=True, text=True).stdout)["streams"]
v = next(s for s in st if s["codec_type"] == "video")
keys = [l.split(",")[0] for l in subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "packet=pts_time,flags", "-of", "csv=p=0", f],
                                                capture_output=True, text=True).stdout.split() if "K" in l.split(",")[1]]
ok = os.path.getsize(f) <= 500_000 and (v["pix_fmt"], v["color_range"], v["color_space"], v["color_transfer"], v["color_primaries"]) == ("yuv420p", "tv", "bt709", "bt709", "bt709")
ok = ok and [s["codec_type"] for s in st] == ["video", "audio", "subtitle"] and [round(float(k), 3) for k in keys] == [0.0]
sys.exit(0 if ok else 1)
PY
  then ok "deliver: the upload copy fits the size asked for, keeps BT.709 and the sound and subtitle tracks, and says its PSNR"
  else bad "deliver (exit $rc): $(printf '%s' "$a" | tail -c 600)"; fi
  a=$(vh deliver "$t/master.mp4" --for bilibili,youtube --out "$t/master.platform.mp4" --psnr off 2>&1); rc=$?
  case "$rc:$a" in 0:*"fits 8 GB with room"*"✓ Bilibili web"*"✓ YouTube"*) ok "deliver --for: a short master far under the limits is encoded at CRF alone, no VBV numbers past x264's range" ;;
    *) bad "deliver --for on a short master: exit $rc: $(printf '%s' "$a" | tail -c 500)" ;; esac
  a=$(vh deliver "$t/master.mp4" --max-gb 0.00001 2>&1); rc=$?
  case "$rc:$a" in 2:*"too little"*) ok "deliver: a limit that leaves no room for the picture is refused (exit 2)" ;; *) bad "deliver with a tiny limit: exit $rc: $a" ;; esac
  # bin/vh clean: a finished project's frames, render chunks, drafts and old takes go (to a stand-in Trash here, OVH_TRASH_DIR);
  # the film in out/final/, its covers, the review pages, the narration in use and its original, sources and docs stay
  c="$t/cl"; mkdir -p "$c/out/frames" "$c/out/.film.mp4.parts" "$c/out/final/covers" "$c/out/review" "$c/audio/takes" "$c/src" "$c/node_modules/x" "$t/home"
  for f in BRIEF.md film.html src/50-shots.js out/frames/a.png out/.film.mp4.parts/part000.mp4 out/draft1.mp4 out/film.mp4 out/film.mp4.render.json \
    out/final/film-4k.mp4 out/final/covers/a.png out/review/gate-1.html out/cues.json audio/voiceover.zh.wav audio/voiceover.zh.raw.wav \
    audio/voiceover.zh.v1.wav audio/music.wav audio/takes/b.wav audio/timeline.zh.json node_modules/x/i.js; do printf x > "$c/$f"; done
  a=$(vh clean "$c" 2>&1); rc=$?; [ -f "$c/out/draft1.mp4" ] && a="$a (draft still there)"
  b=$(OVH_TRASH_DIR="$t/home/trash" vh clean "$c" --yes --delete 2>&1); rc2=$?
  left=$(cd "$c" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | tr '\n' ' ')   # byte order: the runner's locale sorts otherwise
  want="BRIEF.md audio/timeline.zh.json audio/voiceover.zh.raw.wav audio/voiceover.zh.wav film.html out/cues.json out/final/covers/a.png out/final/film-4k.mp4 out/review/gate-1.html src/50-shots.js "
  if [ $rc = 0 ] && printf '%s' "$a" | grep -q '9 item(s)' && printf '%s' "$a" | grep -q '(draft still there)' && [ $rc2 = 0 ] && [ "$left" = "$want" ] \
    && [ "$(find "$t/home" -name '*.wav' | wc -l | tr -d ' ')" = 3 ] && [ "$(find "$t/home" -name '*.mp4' | wc -l | tr -d ' ')" = 2 ]
  then ok "clean: lists first; then the film, covers, review pages, the narration in use and the sources stay, the rest goes (old takes and renders to the Trash)"
  else bad "clean: exit $rc / $rc2, left: $left | $(printf '%s' "$a$b" | tail -c 700)"; fi
  # a cover video inside out/final/ is not the film, so out/final.mp4 is; a path kept inside a folder that goes stays
  c="$t/cl2"; mkdir -p "$c/out/final/covers" "$c/out/frames"
  for f in BRIEF.md out/final/covers/loop.mp4 out/final.mp4 out/draft.mp4 out/frames/a.png out/frames/keep.png; do printf x > "$c/$f"; done
  a=$(vh clean "$c" --keep out/frames/keep.png 2>&1); rc=$?
  if [ $rc = 0 ] && printf '%s' "$a" | grep -q 'the film: out/final.mp4' && printf '%s' "$a" | grep -q 'out/draft.mp4' && printf '%s' "$a" | grep -q 'out/frames/a.png' \
    && ! printf '%s' "$a" | grep -Eq 'keep\.png|  out/final\.mp4|loop\.mp4'
  then ok "clean: a cover video does not make the film a render; a path kept inside a folder that goes stays"
  else bad "clean on covers and a kept path (exit $rc): $(printf '%s' "$a" | tail -c 600)"; fi
  # spec: the file against the BRIEF's Output and Resolution lines (python3 only)
  mkdir -p "$t/sp/out"
  sp() { ffmpeg -nostdin -v error -f lavfi -i "color=c=0x202020:s=${1}:r=${2}:d=${5:-1},${3}" -pix_fmt yuv420p "$t/sp/out/$4.mp4"; }
  sp 320x180 30 "drawbox=x=40:y=40:w=80:h=40:c=white:t=fill,drawbox=x=200:y=100:w=60:h=40:c=orange:t=fill" ref
  sp 640x360 30 "drawbox=x=80:y=80:w=160:h=80:c=white:t=fill,drawbox=x=400:y=200:w=120:h=80:c=orange:t=fill" x2
  sp 640x360 30 "drawbox=x=80:y=80:w=160:h=80:c=white:t=fill,drawbox=x=400:y=200:w=120:h=80:c=orange:t=fill,noise=alls=30:allf=t+u" noisy
  sp 640x360 30 "drawbox=x=80:y=80:w=320:h=160:c=white:t=fill,drawbox=x=400:y=200:w=120:h=80:c=orange:t=fill" big
  sp 320x180 25 "drawbox=x=40:y=40:w=80:h=40:c=white:t=fill" fps25
  sp 160x90 15 "drawbox=x=20:y=20:w=40:h=20:c=white:t=fill" draft
  sp 320x180 30 "drawbox=x=40:y=40:w=80:h=40:c=white:t=fill" long 2
  brief() { printf '%s\n' '# BRIEF' '## Spec' "- Output: $1" "- Resolution: $2  <!-- 1080p | 4k -->" > "$t/sp/BRIEF.md"; }
  brief '320x180, 30 fps, exactly 1.0s (30 frames)' 1080p
  a=$(vh check "$t/sp/out/ref.mp4" 2>&1); rc=$?; b=$(vh check "$t/sp/out/x2.mp4" 2>&1); rb=$?; c=$(vh check "$t/sp/out/fps25.mp4" 2>&1); rcc=$?
  case "$rc:$a|$rb:$b|$rcc:$c" in 0:*"spec: 320x180, 30 fps, 30 frames"*"|1:"*"FAIL frame 640x360"*"Resolution: 1080p, 4k"*"|1:"*"FAIL 25.000 fps, the BRIEF says 30"*)
      ok "check compares the file with the BRIEF: size, a 4K the BRIEF doesn't list, frame rate" ;; *) bad "check against the BRIEF ($rc/$rb/$rcc): $a | $b | $c" ;; esac
  a=$(vh check "$t/sp/out/long.mp4" 2>&1); rc=$?; b=$(vh check "$t/sp/out/draft.mp4" 2>&1); rb=$?
  case "$rc:$a|$rb:$b" in 1:*"FAIL 2.000 s of picture, the BRIEF says exactly 1.0 s"*"|0:"*"WARN 160x90 is smaller than every delivery"*) ok "check: a wrong length fails; a smaller draft only warns" ;;
    *) bad "check length / draft ($rc/$rb): $a | $b" ;; esac
  brief '320x180, 30 fps, exactly 1.0s (30 frames)' '1080p、4k'; a=$(vh check "$t/sp/out/x2.mp4" 2>&1); rc=$?
  brief '320x180, 30 fps, {2–3}s' 1080p; b=$(vh check "$t/sp/out/ref.mp4" 2>&1); rb=$?
  brief '320x180, 30 fps, 约 5 s（150 帧）' 1080p; c=$(vh check "$t/sp/out/ref.mp4" 2>&1); rcc=$?
  case "$rc:$a|$rb:$b|$rcc:$c" in 0:*"spec: 640x360"*"|0:"*"WARN 1.0 s, outside the BRIEF's 2–3 s"*"|0:"*"spec: 320x180"*)
      case "$b$c" in *placeholders*|*FAIL*) bad "check: a range or an approximate length was misread: $b | $c" ;; *) ok "check reads 1080p、4k, warns outside a range, skips approximate lengths" ;; esac ;;
    *) bad "check: separators / range / approximate ($rc/$rb/$rcc): $a | $b | $c" ;; esac
  brief '320x180, 30 fps, exactly 1.0s (30 frames)' '1080p, 4k'
  # check: one odd frame in a moving clip fails with its time; the same clip without it, or with a two-frame flash, passes
  if command -v uv >/dev/null || python3 -c "import numpy" 2>/dev/null; then
    for a in "clean:0" "odd:eq(n,30)" "flash2:between(n,30,31)"; do
      ffmpeg -nostdin -v error -f lavfi -i testsrc=s=320x180:r=30:d=2 -vf "drawbox=c=red:t=fill:enable='${a#*:}'" -pix_fmt yuv420p "$t/${a%%:*}.mp4"; done
    a=$(vh check "$t/clean.mp4" 2>&1) && o=$(vh check "$t/flash2.mp4" 2>&1) && case "$a$o" in *"no isolated frames in 60"*"no isolated frames in 60"*) true ;; *) false ;; esac \
      && ok "check passes a clip without an odd frame, and a two-frame flash" || bad "check on clean / two-frame flash clips: $a $o"
    a=$(vh check "$t/odd.mp4" 2>&1); rc=$?
    case "$rc:$a" in 1:*"1 isolated frame(s) in 60: 1.000 s"*"--no-browser-gpu"*) ok "check fails on one odd frame and names its time" ;; *) bad "check on one odd frame (rc $rc): $a" ;; esac
    a=$(vh check "$t/odd.mp4" --allow 0.4,1.0 2>&1); rc=$?
    case "$rc:$a" in 0:*"no isolated frames in 60"*"declared (--allow): 1.000 s"*) ok "check --allow: a declared flash is listed and passes" ;; *) bad "check --allow (rc $rc): $a" ;; esac
    a=$(vh check "$t/odd.mp4" --allow 0.9-1.1 2>&1); rc=$?
    case "$rc:$a" in 0:*"declared (--allow): 1.000 s"*) ok "check --allow takes a span a-b" ;; *) bad "check --allow span (rc $rc): $a" ;; esac
    # an odd frame every 15 frames (a bounce landing on its still point once a cycle) is periodic motion, not a glitch
    ffmpeg -nostdin -v error -f lavfi -i color=c=0x404040:s=320x180:r=30:d=3 -vf "drawbox=x=100:y=60:w=60:h=60:c=white:t=fill:enable='eq(mod(n\,15)\,7)'" -pix_fmt yuv420p "$t/periodic.mp4"
    a=$(vh check "$t/periodic.mp4" 2>&1); rc=$?
    case "$rc:$a" in 0:*"no isolated frames in 90"*"periodic: 6 small frames, one every 15 frames (0.50 s)"*) ok "check: evenly spaced odd frames are periodic motion, said and not failed" ;; *) bad "check on periodic odd frames (rc $rc): $a" ;; esac
    # motion: 2 s of a moving pattern, then a hard cut to a pale still picture for 4 s: a cut that flashes and a still stretch
    ffmpeg -nostdin -v error -f lavfi -i testsrc2=s=320x180:r=30:d=2 -f lavfi -i color=c=0xE0E0E0:s=320x180:r=30:d=4 \
      -filter_complex "[0:v]lutyuv=y=val*0.4,format=yuv420p[a];[1:v]format=yuv420p[b];[a][b]concat=n=2:v=1[v]" -map "[v]" -pix_fmt yuv420p "$t/still.mp4"
    a=$(vh check "$t/still.mp4" 2>&1); rc=$?
    case "$rc:$a" in 0:*"motion: "*"1 hard cut(s)"*"static: 1 stretch(es) of 3 s or more"*"2.00–6.00 s (frozen)"*"cuts: 1 hard cut(s) from dark to bright"*"2.00 s"*) ok "check --motion: a still stretch and a cut from dark to bright are warnings, the exit status untouched" ;;
      *) bad "check on a still stretch and a bright cut (rc $rc): $a" ;; esac
    # the publishing copy in PACKAGING.md: a Bilibili description of 2100 characters is over its 2000 (said, not a failure)
    { printf '%s\n' '# PACKAGING' '## 发布文案' '### B站' '标题：一个够短的标题' '标签：科普, 物理' '简介：'; python3 -c "print('字' * 2100)"; printf '%s\n' '### YouTube' 'Title: short'; } > "$t/sp/PACKAGING.md"
    a=$(vh check "$t/sp/out/ref.mp4" 2>&1); rc=$?
    case "$rc:$a" in 0:*"over a platform's limit"*"B站: ✓ 标题 title 7 characters"*"✗ 简介 description 2100 characters (limit 2000"*"YouTube: ✓ 标题 title 5 characters"*) ok "check measures the publishing copy against the platforms' limits and says what is over" ;;
      *) bad "check on the publishing copy (rc $rc): $(printf '%s' "$a" | tail -c 600)" ;; esac
    rm -f "$t/sp/PACKAGING.md"
    a=$(vh check "$t/odd.mp4" --allow 1s 2>&1); rc=$?
    [ $rc = 1 ] && ok "check --allow with a typo fails instead of skipping the scan" || bad "check --allow 1s exited $rc: $a"
    a=$(vh check "$t/a.wav" 2>&1); rc=$?
    case "$rc:$a" in 0:*"isolated"*) bad "check on audio only mentions the frame scan: $a" ;; 0:*) ok "check on an audio file skips the frame scan quietly" ;; *) bad "check on audio only (rc $rc): $a" ;; esac
    # scale: a 2x render against its 1x reference (clips made by the spec tests below)
    a=$(vh check "$t/sp/out/x2.mp4" --against "$t/sp/out/ref.mp4" 2>&1); rc=$?; b=$(vh check "$t/sp/out/noisy.mp4" --against "$t/sp/out/ref.mp4" 2>&1); rb=$?
    case "$rc:$a|$rb:$b" in 0:*"the same picture throughout"*"|0:"*"the same picture throughout"*) ok "check --against: a correct 2x render and a noisy one pass" ;;
      *) bad "check --against on correct clips ($rc/$rb): $a | $b" ;; esac
    a=$(vh check "$t/sp/out/big.mp4" --against "$t/sp/out/ref.mp4" 2>&1); rc=$?
    case "$rc:$a" in 1:*"FAIL 0.00–1.00 s: the picture differs"*"scale-fail-0.000s.png"*"twice the"*) [ -s "$t/sp/out/check/scale-fail-0.000s.png" ] \
        && ok "check --against fails on an element drawn at twice the size, with a comparison image" || bad "check --against wrote no comparison image" ;;
      *) bad "check --against on a 2x element (rc $rc): $a" ;; esac
    a=$(vh check "$t/sp/out/x2.mp4" --against "$t/sp/out/fps25.mp4" 2>&1); rc=$?
    case "$rc:$a" in 1:*"FAIL different frame rate"*"twice the"*) bad "check --against on different cuts points at comparison images: $a" ;;
      1:*"FAIL different frame rate"*) ok "check --against refuses to compare different cuts" ;; *) bad "check --against on different cuts (rc $rc): $a" ;; esac
  else skip "check: isolated frames, --against" "needs uv or numpy"; fi
  rm -rf "$t"
}

# scaffolding and the decision pictures (bin/vh storyboard, rhythm, style compare/apply, cover-preview, music --roll/--length)
# the gate ① record (tools/gatecheck.py): a standard project made from the templates is refused by bin/vh render (before
# any browser) and failed by bin/vh check until REVIEW.md has the decision and DECISIONS.md the concept; the user's
# waiver counts unless it sits under gate ② or ③; quick is not checked
gate_checks() {
  local t p a b c d rc rc2 rc3
  t=$(mktemp -d "${TMPDIR:-/tmp}/vh-ci.XXXXXX")
  vh new math ci-gate --dir "$t" >/dev/null 2>&1; p=$(ls -d "$t"/*-ci-gate 2>/dev/null)
  if [ -z "$p" ] || [ ! -f "$p/REVIEW.md" ]; then bad "gate checks: bin/vh new made no project"; rm -rf "$t"; return; fi
  a=$(vh render "$p" 2>&1); rc=$?
  c=$(vh render "$p" --range 0:1 2>&1)
  mkdir -p "$p/out/review/sketch" && printf '<!doctype html><title>a concept sketch</title>\n' > "$p/out/review/sketch/index.html"
  d=$(vh render "$p/out/review/sketch/index.html" 2>&1)
  case "$rc:$a" in 1:*"no record of gate ①"*"the person's words"*"the decision"*"DECISIONS.md: the concept 立意 row"*"--range a:b"*)
    case "$c|$d" in *"no record of gate"*) bad "render of a part or of a sketch page was held by the gate: $c | $d" ;;
      *) ok "gate record: render refuses a whole standard film made from the templates, naming the lines to write; a part (--range) and a sketch page under out/ still render" ;; esac ;;
    *) bad "render without the gate record (exit $rc): $(printf '%s' "$a" | head -c 600)" ;; esac
  if command -v ffmpeg >/dev/null; then
    mkdir -p "$p/out" && ffmpeg -nostdin -v error -f lavfi -i color=c=0x303030:s=320x180:r=30:d=2 -pix_fmt yuv420p "$p/out/film.mp4"
    b=$(vh check "$p/out/film.mp4" 2>&1); rc2=$?
    case "$rc2:$b" in 1:*"✗"*"no record of gate ①"*) ok "gate record: check fails a standard film without it" ;; *) bad "check without the gate record (exit $rc2): $(printf '%s' "$b" | head -c 400)" ;; esac
  else skip "check without the gate record" "no ffmpeg"; fi
  python3 - "$p" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
r = (p / "REVIEW.md").read_text(encoding="utf-8")
(p / "REVIEW.md").write_text(r.replace("## 关卡 ③ 初版\n", "## 关卡 ③ 初版\n- 用户授权跳过（2026-10-12）。原话：“初版不用给我看”\n", 1), encoding="utf-8")
PY
  python3 tools/gatecheck.py "$p" >/dev/null; rc=$?
  python3 - "$p" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
r = (p / "REVIEW.md").read_text(encoding="utf-8").replace("- 定了：{…}　改了：{…}", "- 定了：立意卡 B　改了：结尾短一点", 1).replace('- 原话："……"', '- 原话："选 B，结尾再短一点"', 1)
(p / "REVIEW.md").write_text(r, encoding="utf-8")
d = (p / "DECISIONS.md").read_text(encoding="utf-8").replace("| concept 立意 | {own / review / delegate} | {待定 / 已定（关卡 ①）} |", "| concept 立意 | own | 已定（关卡 ①）：B |", 1)
(p / "DECISIONS.md").write_text(d, encoding="utf-8")
PY
  a=$(python3 tools/gatecheck.py "$p"); rc2=$?
  cp "$ROOT/templates/REVIEW.md" "$ROOT/templates/DECISIONS.md" "$p/" && python3 - "$p" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
r = (p / "REVIEW.md").read_text(encoding="utf-8")
(p / "REVIEW.md").write_text(r.replace("## 关卡 ① 立意和大纲\n", "## 关卡 ① 立意和大纲\n- 用户授权跳过（2026-10-12）。原话：“你直接做，中间不用我看”\n", 1), encoding="utf-8")
PY
  b=$(python3 tools/gatecheck.py "$p"); rc3=$?
  if [ $rc = 1 ] && [ $rc2 = 0 ] && [ $rc3 = 0 ] && printf '%s' "$a" | grep -q "gate ① decided" && printf '%s' "$b" | grep -q "waived in the user's own words (2026-10-12"
  then ok "gate record: the decision and the concept row pass; the user's waiver passes under gate ①, not under gate ③ alone"
  else bad "gate record with the lines filled in ($rc/$rc2/$rc3): $a | $b"; fi
  python3 -c "import sys, re; f = sys.argv[1]; s = open(f, encoding='utf-8').read(); open(f, 'w', encoding='utf-8').write(re.sub(r'(?m)^- Effort: standard', '- Effort: quick', s))" "$p/BRIEF.md" && cp "$ROOT/templates/REVIEW.md" "$p/"
  a=$(python3 tools/gatecheck.py "$p"); rc=$?
  [ $rc = 0 ] && printf '%s' "$a" | grep -q "Effort quick" && ok "gate record: a quick project is not checked" || bad "gate record on quick (exit $rc): $a"
  rm -rf "$t"
}

decision_checks() {
  local t p a rc out
  t=$(mktemp -d "${TMPDIR:-/tmp}/vh-ci.XXXXXX")
  # new: --dir and $OVH_PROJECTS make the project outside the harness; quick does not promise a review stop
  a=$(vh new math ci-dir --dir "$t/elsewhere" --effort quick 2>&1); rc=$?
  p=$(ls -d "$t"/elsewhere/*-ci-dir 2>/dev/null)
  if [ $rc = 0 ] && [ -n "$p" ] && [ -z "$(ls -d "$ROOT"/projects/*-ci-dir 2>/dev/null)" ]; then ok "new --dir makes the project in that folder"; else bad "new --dir: rc $rc, made '$p'"; fi
  if [ -z "$p" ] || [ ! -d "$p" ]; then   # everything below writes into $p: never let it fall back to /
    bad "decision checks stopped: no project to work in"; rm -rf "$t"; return; fi
  case "$a" in *"stops for your review"*) bad "new --effort quick still says it stops for review" ;; *"renders straight through"*) ok "new --effort quick does not promise a review stop" ;;
    *) bad "new --effort quick: no next-step line in '$a'" ;; esac
  OVH_PROJECTS="$t/env" vh new math ci-env >/dev/null 2>&1 && [ -f "$(ls -d "$t"/env/*-ci-env 2>/dev/null)/BRIEF.md" ] && ok "OVH_PROJECTS sets where projects go" || bad "OVH_PROJECTS ignored"
  vh new math ci-x --aspect 16:9 >/dev/null 2>&1; rc=$?; [ $rc = 1 ] && ok "new --aspect is refused for a non-HyperFrames type" || bad "new math --aspect exited $rc"
  vh new short ci-x --aspect 4:3 >/dev/null 2>&1; rc=$?; [ $rc = 1 ] && ok "new --aspect rejects 4:3" || bad "new --aspect 4:3 exited $rc"
  a=$(vh new short ci-x --aspect 4:5 --res 4k 2>&1); rc=$?; [ $rc = 1 ] && case "$a" in *"no 4K preset for 4:5"*) true ;; *) false ;; esac \
    && ok "new refuses 4K for a 4:5 frame (HyperFrames has no preset)" || bad "new --aspect 4:5 --res 4k (rc $rc): $a"
  a=$(vh new math ci-x --aspect 9:16 2>&1); rc=$?; case "$rc:$a" in 1:*"ManimGX 竖屏"*) ok "new --aspect on a ManimGX type points to the vertical setup (-r 1080x1920)" ;; *) bad "new math --aspect (rc $rc): $a" ;; esac
  mkdir -p "$t/hfi"; a=$(vh hf-init "$t/hfi" landscape-4k 2>&1); rc=$?; b=$(vh hf-init "$t/hfi" 2:3 2>&1); rb=$?
  case "$rc:$a|$rb:$b" in 1:*"4K is a render flag"*"|1:"*"unknown frame 2:3"*) [ -z "$(ls -A "$t/hfi")" ] && ok "hf-init refuses a 4K preset and an unknown frame before scaffolding" || bad "hf-init wrote files after refusing" ;;
    *) bad "hf-init frame check ($rc/$rb): $a | $b" ;; esac
  # 4:5: the BRIEF's lines (a pinned version that does not exist makes the scaffold fail fast, offline too; new goes on without it)
  a=$(HYPERFRAMES_VERSION=0.0.0-ci OVH_PROJECTS="$t/a45" vh new short ci-45 --aspect 4:5 2>&1); d=$(ls -d "$t"/a45/*-ci-45 2>/dev/null)
  if [ -n "$d" ] && grep -q '^- Output: 1080x1350,' "$d/BRIEF.md" && grep -q '^- Watch on: phone' "$d/BRIEF.md" && grep -q '画幅 4:5（1080x1350' "$d/BRIEF.md"; then
    case "$a" in *"retry later: bin/vh hf-init"*" 4:5"*) ok "new --aspect 4:5 writes the BRIEF's frame lines, and a failed scaffold's retry hint keeps 4:5" ;; *) bad "new --aspect 4:5 retry hint: $a" ;; esac
  else bad "new --aspect 4:5 BRIEF: $a"; fi
  a=$(vh new handdrawn ci-x --res 4k 2>&1); rc=$?; [ $rc = 1 ] && case "$a" in *"no 4K output"*) true ;; *) false ;; esac && ok "new --res 4k is refused for the hand-drawn engine" || bad "new handdrawn --res 4k exited $rc: $a"
  a=$(vh new short ci-x --watch tv 2>&1); rc=$?; [ $rc = 1 ] && case "$a" in *"unknown --watch"*) true ;; *) false ;; esac && ok "new --watch rejects an unknown target" || bad "new --watch tv exited $rc: $a"
  a=$(vh new short ci-x --watch feed 2>&1); rc=$?; [ $rc = 1 ] && case "$a" in *"already --watch phone"*) true ;; *) false ;; esac && ok "new refuses a feed target for a vertical frame" || bad "new short --watch feed exited $rc: $a"
  a=$(vh new promo ci-x --watch phone 2>&1); rc=$?; [ $rc = 1 ] && case "$a" in *"--watch feed"*) true ;; *) false ;; esac && ok "new refuses a phone target for a landscape frame" || bad "new promo --watch phone exited $rc: $a"
  vh new math ci-x --watch phone >/dev/null 2>&1; rc=$?; [ $rc = 1 ] && ok "new refuses a phone target for a ManimGX (landscape) type" || bad "new math --watch phone exited $rc"
  for bad_style in "dark-math,_swatch" "Dark-Math" "../styles/ink-wash" ","; do
    vh new math ci-x --style "$bad_style" >/dev/null 2>&1; rc=$?; [ $rc = 1 ] || bad "new --style '$bad_style' exited $rc"; done
  ok "new --style rejects a bad name anywhere in the list, paths and an empty list"
  [ -z "$(ls -d "$ROOT"/projects/*-ci-x 2>/dev/null)" ] || bad "a refused new left a project behind"
  # new: where it is watched and the output resolution land in the BRIEF (defaults from the frame, flags override)
  if grep -q '^- Watch on: desktop' "$p/BRIEF.md" && grep -q '^- Resolution: 1080p' "$p/BRIEF.md" \
    && OVH_PROJECTS="$t/w" vh new math ci-w --watch feed --res 4k >/dev/null 2>&1 \
    && grep -q '^- Watch on: feed' "$(ls -d "$t"/w/*-ci-w)/BRIEF.md" && grep -q '^- Resolution: 1080p, 4k' "$(ls -d "$t"/w/*-ci-w)/BRIEF.md" \
    && OVH_PROJECTS="$t/w2" vh new edit ci-e --res 4K >/dev/null 2>&1 && grep -q '^- Watch on: phone' "$(ls -d "$t"/w2/*-ci-e)/BRIEF.md" \
    && grep -q '^- Resolution: 1080p, 4k' "$(ls -d "$t"/w2/*-ci-e)/BRIEF.md"; then ok "new writes Watch on and Resolution into the BRIEF (defaults, flags, the 4K alias)"
  else bad "new: Watch on / Resolution missing or wrong in the BRIEF"; fi
  # style apply: presets are references; two attach side by side, re-attaching one adds nothing; by name under OVH_PROJECTS
  vh style apply blueprint "$p" >/dev/null && vh style apply ink-wash "$p" >/dev/null && OVH_PROJECTS="$t/elsewhere" vh style apply ink-wash ci-dir >/dev/null
  if grep -q '^- Style refs (repo presets): `styles/blueprint`, `styles/ink-wash`  <!--' "$p/BRIEF.md" && ! grep -q '^## Style preset' "$p/BRIEF.md" \
    && [ "$(grep -c '^> 参考的风格预设：`styles/blueprint`、`styles/ink-wash`' "$p/STYLE.md")" = 1 ] && [ "$(grep -c '风格参考 · ' "$p/DECISIONS.md")" = 2 ] \
    && [ -f "$p/style-refs/blueprint/tokens.json" ] && [ -f "$p/style-refs/ink-wash/STYLE.md" ]; then ok "style apply attaches presets as references, side by side, without repeats"
  else bad "style apply: references missing, repeated, or an instruction block pasted into the BRIEF"; fi
  # a comma list in one call, and a project made the old way (STYLE_PRESET.md + a pasted block + the 为底 pointer) keeps its base as a reference
  if OVH_PROJECTS="$t/m" vh new math ci-m >/dev/null 2>&1; then
    q=$(ls -d "$t"/m/*-ci-m)
    cp "$ROOT/styles/cutout-jazz/STYLE.md" "$q/STYLE_PRESET.md"; cp "$ROOT/styles/cutout-jazz/tokens.json" "$q/style.tokens.json"
    printf '\n\n## Style preset: cutout-jazz\n\n```text\nold block\n```\n' >> "$q/BRIEF.md"
    { printf '> 本项目以风格预设 `styles/cutout-jazz` 为底：先读 `STYLE_PRESET.md`。\n\n'; cat "$q/STYLE.md"; } > "$q/STYLE.md.new" && mv "$q/STYLE.md.new" "$q/STYLE.md"
    vh style apply blueprint,ink-wash "$q" >/dev/null 2>&1
    if [ -f "$q/style-refs/cutout-jazz/STYLE.md" ] && [ -f "$q/style-refs/cutout-jazz/tokens.json" ] && [ ! -e "$q/STYLE_PRESET.md" ] \
      && grep -q '^- Style refs (repo presets): `styles/cutout-jazz`, `styles/blueprint`, `styles/ink-wash`' "$q/BRIEF.md" \
      && ! grep -q '^## Style preset' "$q/BRIEF.md" && ! grep -q '为底' "$q/STYLE.md" && [ "$(grep -c '风格参考 · ' "$q/DECISIONS.md")" = 3 ]; then
      ok "style apply a,b: one call attaches both; an old base preset becomes a reference"
    else bad "style apply: comma list or migration of an old project's preset failed"; fi
  else bad "new math ci-m failed"; fi
  vh style apply no-such-style "$p" >/dev/null 2>&1; rc=$?; [ $rc = 1 ] && ok "style apply rejects an unknown preset" || bad "style apply unknown preset exited $rc"
  # readcheck: a budget, and the timed text of a composition without a browser
  a=$(vh readcheck --budget 3.2)
  case "$a" in *"normal pace"*"up to 14 CJK"*"one brisk read"*"up to 16 CJK"*"up to 28 CJK"*) ok "readcheck --budget: the pace's target, the floor, subtitles" ;; *) bad "readcheck --budget 3.2 said: $a" ;; esac
  # no fixed seconds: under one brisk read (CJK/7 + other/20 + 0.8 s, at least 1.5 s) FAILs; under the pace's target only WARNs
  tl=$(mktemp -d "${TMPDIR:-/tmp}/vh-ci.XXXXXX")
  printf '%s' '[{"id":"a","text":"CLAUDE.md router","start":0,"end":1.6,"read":"label"},{"id":"b","text":"CLAUDE.md router","start":0,"end":1.6},' \
    '{"id":"c","text":"CLAUDE.md router","start":0,"end":1.6,"pace":"brisk"}]' > "$tl/label.json"
  a=$(vh readcheck "$tl/label.json"); rc=$?
  case "$rc:$a" in 0:*"OK   a"*"lab"*"WARN b"*"normal  1.63s"*"OK   c"*"pace normal, default"*"3/3 pass · 1 WARN"*)
      ok "readcheck: under the pace's target is a WARN (exit 0); a label and a brisk text need one read" ;; *) bad "readcheck WARN band (rc $rc): $a" ;; esac
  printf '%s' '[{"id":"f","text":"CLAUDE.md router","start":0,"end":1.2},{"id":"g","text":"短","start":2,"end":2.9}]' > "$tl/flash.json"
  a=$(vh readcheck "$tl/flash.json"); rc=$?
  case "$rc:$a" in 1:*"FAIL f"*"floor  1.55s"*"FAIL g"*"floor  1.50s"*"2 FAIL"*) ok "readcheck: under the floor FAILs, and nothing passes under 1.5 s" ;; *) bad "readcheck floor (rc $rc): $a" ;; esac
  printf '%s\n' '# BRIEF' '- Pace: relaxed  <!-- relaxed | normal | brisk -->' > "$tl/BRIEF.md"
  a=$(vh readcheck "$tl/label.json"); b=$(vh readcheck "$tl/label.json" --pace brisk); rc=$?
  case "$a" in *"WARN b"*"relaxed  2.00s"*"pace relaxed, Pace in"*)
      case "$rc:$b" in 0:*"OK   b"*"pace brisk, --pace"*) ok "readcheck takes the pace from the BRIEF, and --pace overrides it" ;; *) bad "readcheck --pace brisk (rc $rc): $b" ;; esac ;;
    *) bad "readcheck with a BRIEF Pace: $a" ;; esac
  printf '%s' '[{"id":"x","text":"t","start":0,"end":2,"pace":"fast"}]' > "$tl/badpace.json"
  vh readcheck "$tl/badpace.json" >/dev/null 2>&1; rc=$?
  [ $rc = 2 ] && ok "readcheck refuses a pace that is not relaxed, normal or brisk" || bad "readcheck with a pace of \"fast\" exited $rc"
  # a project's audio/captions.json (what bin/vh captions writes) is the narration: the subtitle rule, unless --mode says otherwise
  mkdir -p "$tl/cap/audio"
  printf '%s' '[{"id":"a","start":0,"end":2.4,"zh":["慢慢地说一句话"]},{"id":"b","start":2.4,"end":3.1,"zh":["这一句太短"]}]' > "$tl/cap/audio/captions.json"
  a=$(vh readcheck "$tl/cap"); rc=$?; b=$(vh readcheck "$tl/cap" --mode onscreen)
  case "$rc:$a" in 1:*"OK   a·zh"*"need   1.80s"*"FAIL b·zh"*"readcheck (subtitle)"*)
      case "$b" in *"readcheck (onscreen"*) ok "readcheck <project> judges its captions by the subtitle rule; --mode still decides" ;; *) bad "readcheck <project> --mode onscreen: $b" ;; esac ;;
    *) bad "readcheck on a project's captions (rc $rc): $a" ;; esac
  # an exported CDPATH must not move bin/vh's own cd (run as bin/vh, its folder is relative)
  mkdir -p "$tl/cdpath/bin"
  a=$(cd "$ROOT" && CDPATH="$tl/cdpath" "$VH_BASH" bin/vh effort standard 2>&1); rc=$?
  [ $rc = 0 ] && printf '%s' "$a" | grep -q '人工关卡' && ok "bin/vh ignores an exported CDPATH" || bad "bin/vh under a CDPATH (exit $rc): $(printf '%s' "$a" | head -3)"
  rm -rf "$tl"
  printf '%s\n' '<html><body><div id="root" data-composition-id="m" data-start="0" data-duration="10">' \
    '<section id="s" class="clip" data-start="0" data-duration="10"><h1 id="t">script-driven</h1></section>' \
    '<div id="c1" class="clip" data-start="1" data-duration="4"><span>四个汉字</span></div>' \
    '<div id="c2" class="clip" data-start="6" data-duration="1.2">太短了的字</div></div><script>var x="<div>";</script></body></html>' > "$p/index.html"
  a=$(vh readcheck "$p/index.html"); rc=$?
  case "$rc:$a" in 1:*"OK   c1"*"FAIL c2"*"pace relaxed, Pace in"*"NOT checked: 1 text block"*) ok "readcheck reads a composition's clips and the new project's Pace (a math project: relaxed; and says what it left out)" ;; *) bad "readcheck index.html (rc $rc): $a" ;; esac
  vh readcheck --export "$p" >/dev/null && grep -q '"id": "c2"' "$p/texts.json" && { vh readcheck "$p" --export >/dev/null 2>&1; [ $? = 2 ]; } \
    && ok "readcheck --export writes texts.json and will not overwrite it" || bad "readcheck --export"
  # HyperFrames timing the way HyperFrames resolves it: "id", "id+n", a sub-composition's <template>, a typo'd reference
  mkdir -p "$t/rel/sub"
  printf '%s\n' '<html><body><div id="root" data-composition-id="m" data-start="0" data-duration="12">' \
    '<div id="a" data-start="1" data-duration="3"><h1>第一句标题文字</h1></div>' \
    '<div id="b" data-start="a" data-duration="0.8"><p>第二句</p></div>' '<div id="c" data-start="b + 0.5" data-duration="1"><p>第三句</p></div>' \
    '<div id="x" data-start="typo" data-duration="1"><p>没有这个片段</p></div>' \
    '<div id="host" data-start="6" data-duration="4" data-composition-src="sub/child.html"></div></div></body></html>' > "$t/rel/index.html"
  printf '%s\n' '<template id="t"><div data-composition-id="child" data-duration="4">' \
    '<div id="k1" data-start="0.5" data-duration="1"><span>子合成里的字</span></div></div></template>' > "$t/rel/sub/child.html"
  a=$(vh readcheck "$t/rel/index.html")
  case "$a" in *"a "*"1.00–   4.00s"*"b "*"4.00–   4.80s"*"c "*"5.30–   6.30s"*"k1"*"6.50–   7.50s"*"NOT checked"*"typo"*)
      case "$a" in *"every timed text"*) bad "readcheck claims it checked everything: $a" ;; *) ok "readcheck resolves relative starts and sub-composition templates" ;; esac ;;
    *) bad "readcheck relative / template timing: $a" ;; esac
  # with the project's own hyperframes the spans are HyperFrames' (a stand-in prints its timeline), from a relative path too
  mkdir -p "$t/rel/node_modules/.bin"
  cat > "$t/rel/node_modules/.bin/hyperframes" <<'SH'
#!/bin/sh
echo '{"timeline": {"tracks": [{"rows": [{"id": "a", "absStart": 2, "absEnd": 5.5, "file": "index.html"}]}]}}'
SH
  chmod +x "$t/rel/node_modules/.bin/hyperframes"
  a=$(cd "$t" && vh readcheck rel/index.html)
  case "$a" in *"a "*"2.00–   5.50s"*"HyperFrames' own timeline"*) ok "readcheck takes the spans from the project's hyperframes timeline" ;;
    *) bad "readcheck with a project hyperframes: $a" ;; esac
  if ! command -v uv >/dev/null || ! command -v ffmpeg >/dev/null; then skip "storyboard · rhythm · style compare · cover-preview · music --roll" "needs uv and ffmpeg"; rm -rf "$t"; return; fi
  # a small project: 3 shots (one over the type's 5 s, one unsure), a video, narration, captions (one too short) and a score
  printf '%s\n' '# BRIEF' '<!-- from 02-knowledge-short.md -->' > "$p/BRIEF.md"; rm -f "$p/texts.json"
  printf '%s\n' '[{"id": "S1", "start": 0, "end": 2, "segment": "hook", "reads": "a title"},' \
    '{"id": "S2", "start": 2, "end": 8.5, "segment": "body", "reads": ["a long shot", "second read"], "unsure": "too slow?"},' \
    '{"id": "S3", "start": 8.5, "end": 10, "segment": "body", "reads": "the end"}]' > "$p/shots.json"
  ffmpeg -nostdin -v error -f lavfi -i testsrc=s=320x180:d=10:r=10 -pix_fmt yuv420p "$p/out/final.mp4"
  printf '%s\n' '{"segments": [{"id": "l1", "text": "first line of narration", "start": 0.2, "end": 3.9}, {"id": "l2", "text": "second", "start": 4.2, "end": 9.5}]}' > "$p/audio/timeline.json"
  printf '%s\n' '[{"id": "l1", "start": 0.2, "end": 3.9, "en": ["first line of narration"]}, {"id": "l2", "start": 4.2, "end": 5.0, "en": ["second"]}]' > "$p/audio/captions.json"
  printf '%s\n' '{"bpm": 120, "key": "C", "mode": "major", "seed": 1, "sections": [{"name": "a", "bars": 2, "chords": ["I", "V"], "layers": ["pad"]},' \
    '{"name": "b", "bars": 3, "chords": ["vi", "IV", "V"], "layers": ["pad"]}], "parts": [{"inst": "piano", "pattern": [[0, 1, "c0"], [1, 1, "c2"], [2, 2, "c1"]]}]}' > "$p/audio/score.json"
  if vh music "$p/audio/score.json" "$p/audio/music.wav" --length auto --roll >/dev/null; then
    a=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$p/audio/music.wav")
    python3 -c "import json, sys; b = json.load(open(sys.argv[1])); sys.exit(0 if abs(float(sys.argv[2]) - 10) < 0.01 and b['fade']['end'] == 10.0 and max(b['beats']) < 10 else 1)" "$p/audio/music.beats.json" "$a" \
      && ok "music --length auto ends where the last bar ends, with a fade" || bad "music --length auto: $a s, beat map $(head -c 200 "$p/audio/music.beats.json")"
    [ -s "$p/audio/music.roll/overview.png" ] && [ -s "$p/audio/music.roll/01-piano-0.png" ] && ok "music --roll draws an overview and a page per part" || bad "music --roll pictures missing"
    vh music "$p/audio/score.json" "$t/m7.wav" --length 7 >/dev/null && a=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$t/m7.wav") \
      && python3 -c "import sys; sys.exit(0 if abs(float(sys.argv[1]) - 7) < 0.01 else 1)" "$a" && ok "music --length 7 trims the render to 7 s" || bad "music --length 7 gave '$a' s"
  else bad "bin/vh music --length auto --roll"; fi
  # at 60 bpm a bar is 4 s: the fade still starts on a beat, 1-3 s before the end
  printf '%s\n' '{"bpm": 60, "key": "C", "mode": "major", "seed": 1, "sections": [{"name": "a", "bars": 4, "chords": ["I", "V", "vi", "IV"], "layers": ["pad"]}]}' > "$t/s60.json"
  vh music "$t/s60.json" "$t/m60.wav" --length 9.5 >/dev/null \
    && python3 -c "import json, sys; f = json.load(open(sys.argv[1]))['fade']; s = f['start']; sys.exit(0 if s == round(s) and 6.5 <= s <= 8.5 and f['end'] == 9.5 else 1)" "$t/m60.beats.json" \
    && ok "music --length at 60 bpm fades from a beat" || bad "music --length 9.5 at 60 bpm: $(head -c 300 "$t/m60.beats.json" 2>/dev/null)"
  # a section stop, a cresc and a pickup (motif-era scores): --roll draws them, --length fades from a beat and keeps the stop: hit
  printf '%s\n' '{"bpm": 100, "key": "D", "mode": "major", "seed": 1, "sections": [{"name": "a", "bars": 2, "chords": ["I", "V"], "stop": {"at": "2:3", "keep": ["pad"]}},' \
    '{"name": "b", "bars": 2, "chords": ["IV", "I"]}], "parts": [{"inst": "strings", "id": "pad", "figure": "sustain", "octave": 3, "gain_db": -14},' \
    '{"inst": "brass", "sections": ["a"], "octave": 4, "by_section": {"a": {"cresc": [-8, 0]}}, "pattern": [[0, 1, "d1"], [1, 1, "d3"], [2, 1, "d5"], [3, 1, "d3"]]},' \
    '{"inst": "celesta", "sections": ["b"], "octave": 5, "loop": 2, "pattern": [[-1, 1, "d5"], [0, 2, "d1"], [2, 2, "d3"]]}]}' > "$t/stop.json"
  if vh music "$t/stop.json" "$t/stop.wav" --roll --length 8 >/dev/null && [ -s "$t/stop.roll/overview.png" ] && [ -s "$t/stop.roll/03-celesta-0.png" ] \
    && python3 -c "import json, sys; b = json.load(open(sys.argv[1])); f = b['fade']; sys.exit(0 if f['end'] == 8.0 and any(abs(f['start'] - x) < 1e-6 for x in b['beats']) and [h['t'] for h in b['hits'] if h['what'] == 'stop:a'] == [3.6] else 1)" "$t/stop.beats.json"
  then ok "music --roll and --length with a section stop, a cresc and a pickup"; else bad "music with a stop: $(head -c 300 "$t/stop.beats.json" 2>/dev/null)"; fi
  # storyboard: a page per segment + an overview; the unsure and the long shot are flagged; the same input, the same bytes
  # review.json is tools/review.py's shape: a gate JSON that includes it builds the page
  if vh storyboard "$p" >/dev/null && mkdir -p "$p/out/review" \
    && printf '%s\n' '{"summary": "ci", "decisions": [], "include": "out/check/storyboard/review.json"}' > "$p/out/review/gate-2.json" \
    && a=$(vh review "$p" 2 2>&1) && grep -q '"frame": "out/check/storyboard/frames/S2.png"' "$p/out/check/storyboard/review.json"; then
    case "$a" in *"2 segment(s)"*"3 shot(s)"*"S2"*) ok "storyboard review.json feeds bin/vh review through include" ;; *) bad "review with include said: $a" ;; esac
  else bad "storyboard review.json + bin/vh review: $a"; fi
  # a duplicate id stops it; a shot the video never reaches gets a grey tile, not the clamped last frame
  printf '%s\n' '[{"id": "D", "start": 0, "end": 1}, {"id": "D", "start": 1, "end": 2}]' > "$t/dup.json"
  vh storyboard "$p" --shots "$t/dup.json" >/dev/null 2>&1; rc=$?; [ $rc != 0 ] && ok "storyboard rejects a duplicate shot id" || bad "storyboard took a duplicate id"
  printf '%s\n' '[{"id": "P1", "start": 0, "end": 4}, {"id": "P2", "start": 4, "end": 9}, {"id": "P3", "start": 9, "end": 14}]' > "$t/past.json"
  a=$(vh storyboard "$p" --shots "$t/past.json" --out "$t/sbpast" 2>&1)
  case "$a" in *"past the end of out/final.mp4"*"P3"*) [ ! -f "$t/sbpast/frames/P3.png" ] && ok "storyboard leaves a shot past the end of the video grey" || bad "storyboard grabbed a frame past the end" ;;
    *) bad "storyboard past the end: $a" ;; esac
  # inside a uv project (bin/vh new math suggests uv init) the tools still run: uv must not sync that project
  mkdir -p "$t/uvp" && printf '%s\n' '[project]' 'name = "uvp"' 'version = "0"' 'dependencies = ["this-package-does-not-exist-xyz==1.0"]' > "$t/uvp/pyproject.toml"
  (cd "$t/uvp" && vh storyboard "$p" >/dev/null 2>&1) && [ ! -e "$t/uvp/uv.lock" ] && ok "bin/vh's uv runs ignore the project they are started in" || bad "uv run synced the surrounding project"
  # 26 shots at 6 a page split evenly (5 5 5 5 6), not 6 6 6 6 and a page of 2
  python3 -c "import json; print(json.dumps([{'id': 'E%02d' % i, 'start': i * 0.3, 'end': i * 0.3 + 0.3} for i in range(26)]))" > "$t/even.json"
  vh storyboard "$p" --shots "$t/even.json" --out "$t/sbeven" >/dev/null 2>&1 \
    && python3 -c "import json, sys; i = json.load(open(sys.argv[1])); sys.exit(0 if [len(x['shots']) for x in i['pages']] == [5, 5, 5, 5, 6] else 1)" "$t/sbeven/index.json" \
    && ok "storyboard splits 26 shots 5-5-5-5-6" || bad "storyboard page split: $(head -c 400 "$t/sbeven/index.json" 2>/dev/null)"
  if vh storyboard "$p" >/dev/null && cp "$p/out/check/storyboard/overview.png" "$t/ov1.png" && vh storyboard "$p" >/dev/null; then
    [ -s "$p/out/check/storyboard/01-hook.png" ] && [ -s "$p/out/check/storyboard/02-body.png" ] \
      && python3 -c "import json, sys; i = json.load(open(sys.argv[1])); p = i['pages'][1]; sys.exit(0 if p['unsure'] == ['S2'] and p['long'] == ['S2'] and i['limit_s'] == 5 else 1)" "$p/out/check/storyboard/index.json" \
      && ok "storyboard: a page per segment, the unsure and the too-long shot flagged" || bad "storyboard pages or flags: $(cat "$p/out/check/storyboard/index.json")"
    cmp -s "$t/ov1.png" "$p/out/check/storyboard/overview.png" && ok "storyboard is deterministic" || bad "storyboard gave different bytes on a second run"
  else bad "bin/vh storyboard"; fi
  a=$(vh rhythm "$p")
  case "$a" in *"S2 6.5 s > 5 s"*"l2"*"0.8 s < 1.8 s"*) [ -s "$p/out/check/rhythm.png" ] && ok "rhythm: long shot and short caption in red" || bad "rhythm.png missing" ;; *) bad "rhythm said: $a" ;; esac
  vh rhythm "$p" --segment body >/dev/null && [ -s "$p/out/check/rhythm-body.png" ] && ok "rhythm --segment zooms in" || bad "rhythm --segment"
  printf '%s\n' '{"segments": [{"id": "e1", "text": "an English line", "start": 0.5, "end": 2.0}]}' > "$p/audio/timeline.en.json"
  a=$(vh rhythm "$p" --lang en)
  case "$a" in *"from: "*"audio/timeline.en.json"*) ok "rhythm --lang en reads timeline.en.json" ;; *) bad "rhythm --lang en: $a" ;; esac
  vh style compare blueprint,ink-wash --out "$t/sc.png" >/dev/null && vh style compare blueprint,ink-wash --frame 2 --out "$t/sc2.png" >/dev/null && [ -s "$t/sc.png" ] && [ -s "$t/sc2.png" ] \
    && ok "style compare: posters and swatch frames" || bad "bin/vh style compare"
  vh style compare blueprint,no-such >/dev/null 2>&1; rc=$?; [ $rc != 0 ] && ok "style compare rejects an unknown preset" || bad "style compare accepted an unknown preset"
  out=$(vh cover-preview "$ROOT/styles/blueprint/media/poster.jpg" --out "$t/cover.png")
  case "$out" in *"smallest text"*"title stroke "*" px at the smallest slot"*|*"no text line found"*) [ -s "$t/cover.png" ] && ok "cover-preview draws the feed sizes and a legibility line (with the title's stroke width at the smallest slot)" || bad "cover-preview wrote nothing" ;; *) bad "cover-preview said: $out" ;; esac
  rm -rf "$t"
}

# the review desk (bin/vh desk, tools/desk/README.md): its reader on the committed fixtures (zh, and en with a NOTES.md
# whose table is missing, which must come back as text), a server on a free port (the page, the data, a 206 range, and
# what it refuses), a submission that wakes bin/vh desk wait and lands verbatim in REVIEW.md, the watcher's timeout,
# bin/vh new --lang, and bin/vh review's language default
desk_start() { # desk_start <project> <log>: bin/vh desk on a free port in the background; sets desk_pid and desk_url
  local i a; desk_url=""
  "$VH_BASH" "$ROOT/bin/vh" desk "$1" --port 0 > "$2" 2>&1 & desk_pid=$!   # bin/vh execs python: $! is the server
  for i in $(seq 150); do   # up to 30 s; stop early if the server exits
    desk_url=$(sed -n 's#^desk: \(http://127\.0\.0\.1:[0-9]*/\).*#\1#p' "$2"); [ -n "$desk_url" ] && return 0
    kill -0 "$desk_pid" 2>/dev/null || break; sleep 0.2; done
  if kill -0 "$desk_pid" 2>/dev/null; then a="no address after 30 s, still running"; kill "$desk_pid" 2>/dev/null; wait "$desk_pid" 2>/dev/null
  else wait "$desk_pid"; a="exited with $?"; fi
  bad "desk server for $(basename "$1") did not start ($a); its output: $(tr '\n' ' ' < "$2" | head -c 800)$([ -s "$2" ] || echo '(none)')"
  return 1
}
desk_checks() {
  local t pid wpid url i rc a
  t=$(mktemp -d "${TMPDIR:-/tmp}/vh-ci.XXXXXX")
  vh desk data tools/desk/fixtures/zh > "$t/zh.json" && vh desk data tools/desk/fixtures/en > "$t/en.json"
  if python3 - "$t/zh.json" "$t/en.json" <<'PY'
import json, sys
zh, en = (json.load(open(p, encoding="utf-8")) for p in sys.argv[1:3])
bad = []
def want(cond, what):
    if not cond: bad.append(what)
o = zh["outline"]
want(zh["lang"] == "zh" and zh["project"]["title"] == "一杯水的旅程" and zh["project"]["effort"] == "studio", "zh: lang, title, effort")
want([x["title"] for x in o] == ["拧开水龙头", "水厂和管道", "落进杯子"] and [x["tag"] for x in o] == ["起", "承", "合"], "zh: outline titles and tags")
want([(x["t0"], x["t1"]) for x in o] == [(0, 8), (8, 16), (16, 24)], "zh: outline times")
c = {r["id"]: r for r in zh["captions"]["rows"]}
want(zh["captions"]["kind"] == "caption" and len(c) == 5 and c["c03"]["term"] == "沉淀" and c["c03"]["seg"] == "2", "zh: captions, terms, segments")
want((c["c05"]["t0"], c["c05"]["t1"]) == (16, 24) and c["c04"]["facts"] == ["#1"], "zh: bars → seconds past the beat map, fact refs")
f = {x["id"]: x for x in zh["facts"]}
want(f["#3"]["dropped"] and not f["#1"]["dropped"] and f["#1"]["onscreen"] and [x["done"] for x in zh["fact_todo"]] == [False, True], "zh: facts, struck rows, to-verify")
a = zh["agent_decided"]
want([x["superseded"] for x in a] == [False, True, False] and a[1]["note"] == "（关卡 ① 后作废）" and a[2]["group"] == "关卡 ① 之后", "zh: DECISIONS strikethrough and groups")
h = zh["history"]
want(len(h) == 1 and h[0]["quotes"][0]["text"].startswith("大纲按内容分段") and [n["k"] for n in h[0]["notes"]] == ["定了", "改了"], "zh: REVIEW history")
r = zh["rounds"]
want([x["id"] for x in r] == ["1"] and r[0]["data"]["listen"][0]["t"] == 7.5 and r[0]["data"]["least_sure"][1] == {"id": "", "note": "配乐会不会太甜"}, "zh: the gate page and its listen prompts")
want([s["label"] for s in zh["music"]["sections"]] == ["拧开", "管道", "杯子"], "zh: music section labels from the gate JSON")
want([s["seg"] for s in zh["shots"]["items"]] == ["1", "2", "3"], "zh: shots matched to the outline")
sb = next((d for d in zh["docs"] if d["file"] == "STORYBOARD.md"), None)
want(sb and sb["sections"][0]["title"] == "Shots" and "<li>S1" in sb["sections"][0]["html"] and not zh["warnings"], "zh: STORYBOARD.md (no table) as formatted text")
want(en["lang"] == "en" and [x["title"] for x in en["outline"]][0] == "Open the tap" and en["outline"][0]["tag"] == "setup", "en: lang, outline from English headers")
c = {r["id"]: r for r in en["captions"]["rows"]}
want(en["captions"]["kind"] == "narration" and c["n3"]["seg"] == "3" and c["n2"]["term"] == "settling" and c["n1"]["t0"] == 0.5, "en: narration table")
notes = next((d for d in en["docs"] if d["file"] == "NOTES.md"), {"sections": []})
want(en["facts"] == [] and any("NOTES.md" in w for w in en["warnings"]) and any("water in city pipes" in s["html"] for s in notes["sections"]), "en: NOTES.md without its table comes back as text, with a warning")
want(en["agent_decided"][1]["superseded"] and en["history"][0]["quotes"][0]["text"] == "Name the parts by what happens in them." and en["rounds"] == [], "en: DECISIONS, REVIEW, no gate page")
if bad:
    print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
  then ok "desk reads the zh and en fixtures (outline, captions and terms, bars, facts, ledger, history, gate extras), and a doc without its table as text"
  else bad "desk reader on tools/desk/fixtures"; fi
  # this round is the page bin/vh review made last (.current), else the last in review order, never the newest file;
  # one language rule; markdown in bounded time;
  # the newest submission within one second is the highest -n. (A file, not a heredoc inside $(…): bash 3.2 counts the
  # parentheses in the heredoc's body.)
  cat > "$t/order.py" <<'PY'
import json, os, shutil, subprocess, sys, time
sys.path.insert(0, "tools/desk")
import feedback, reader
bad = []
def want(cond, what):
    if not cond: bad.append(what)
t0 = time.time()
for s in ("*a " * 20000, "[" * 60000, "**a " * 15000, "~~a " * 15000, "`" * 30000, "a](b " * 12000):
    reader.render_md(s)
want(time.time() - t0 < 3, f"long lines took {time.time() - t0:.1f} s")
try:
    h = reader.render_md(">" * 3000 + " x")
    want(h.count("<blockquote>") <= reader.MAX_QUOTE_DEPTH + 1 and h.endswith("x</p>" + "</blockquote>" * h.count("<blockquote>")), "3000 nested quotes")
except RecursionError:
    bad.append("3000 nested quotes: RecursionError")
want(reader.render_md("a *b* c") == "<p>a <em>b</em> c</p>" and reader.render_md("**b** ~~c~~") == "<p><strong>b</strong> <del>c</del></p>", "inline markup")
d = os.path.join(sys.argv[1], "order")
shutil.copytree("tools/desk/fixtures/zh", d)
g = os.path.join(d, "out", "review")
shutil.copy(os.path.join(g, "gate-1.json"), os.path.join(g, "gate-1b.json"))
os.utime(os.path.join(g, "gate-1.json"), (time.time() + 60, time.time() + 60))   # the earlier page touched later
r = reader.read_project(d)
want([x["id"] for x in r["rounds"]] == ["1", "1b"] and r["lang"] == "zh", f"order after a touch: {[x['id'] for x in r['rounds']]}, lang {r['lang']}")
j = json.load(open(os.path.join(g, "gate-1b.json"), encoding="utf-8"))
json.dump(dict(j, lang="en"), open(os.path.join(g, "gate-1b.json"), "w", encoding="utf-8"))
want(reader.read_project(d)["lang"] == "en", "this round's gate JSON lang should override the BRIEF")
fd = os.path.join(g, "feedback")
os.makedirs(fd)
for n in ("1b-20261004-030440", "1b-20261004-030440-2", "1b-20261004-030440-10"):
    json.dump({"round": "1b", "submitted_at": "2026-10-04T03:04:40", "n": n}, open(os.path.join(fd, n + ".json"), "w"))
want(feedback.latest(d)[1]["n"] == "1b-20261004-030440-10", f"latest within one second: {feedback.latest(d)[1]}")
# the page bin/vh review made last is this round (out/review/.current), whatever the stop order or its name
c = os.path.join(sys.argv[1], "current")
shutil.copytree("tools/desk/fixtures/zh", c)
cg = os.path.join(c, "out", "review")
def publish(n):
    shutil.copy(os.path.join(cg, "gate-1.json"), os.path.join(cg, f"gate-{n}.json"))
    return subprocess.run([sys.executable, "tools/review.py", c, n], capture_output=True, text=True).returncode
cur = lambda: reader.read_project(c)["rounds"][-1]["id"]   # noqa: E731
for seq, page in ((["2", "1b"], "1b"), (["3", "E3b"], "E3b"), (["final"], "final"), (["2B"], "2B")):
    rcs = [publish(n) for n in seq]
    want(rcs == [0] * len(seq) and cur() == page, f"published {seq} (exit {rcs}): this round is {cur()}, not {page}")
fd2 = os.path.join(cg, "feedback")
os.makedirs(fd2)
for rid in ("2B", "E3b"):
    json.dump({"round": rid, "submitted_at": "2026-10-04T12:00:00"}, open(os.path.join(fd2, f"{rid}-20261004-120000.json"), "w"))
want([f.name for f, _ in feedback.pending(c)] == ["2B-20261004-120000.json"], f"pending follows .current: {[f.name for f, _ in feedback.pending(c)]}")
os.remove(os.path.join(cg, "gate-2B.json"))   # .current names a page that is gone: the review order decides
want(cur() == "3", f"with .current pointing at a removed page: {cur()}")
# bin/vh review: the page as spelled on disk (APFS finds gate-1d.json for 1D); no gate: this round, not the newest
# file; ids of 1-24 characters; a gate file that links out of the project is not read
shutil.copy(os.path.join(cg, "gate-1.json"), os.path.join(cg, "gate-1d.json"))
rv = lambda *a: subprocess.run([sys.executable, "tools/review.py", c, *a], capture_output=True, text=True)   # noqa: E731
r = rv("1D")
names = os.listdir(cg)
want(r.returncode == 0 and open(os.path.join(cg, ".current")).read().strip() == "1d" and "gate-1d.html" in names and "gate-1D.html" not in names,
     f"review 1D for gate-1d.json: exit {r.returncode}, .current {open(os.path.join(cg, '.current')).read().strip()!r}, {sorted(n for n in names if n.endswith('.html'))}")
publish("E3b")
os.utime(os.path.join(cg, "gate-3.json"), (time.time() + 60, time.time() + 60))
r = rv()
want(r.returncode == 0 and "gate-E3b.html" in r.stderr and "gate-3.json is newer" in r.stderr, f"review with no gate: {r.returncode} {r.stderr[-300:]}")
r = rv("a" * 25)
want(r.returncode == 2 and "1 to 24" in r.stderr, f"a 25-character id: {r.returncode} {r.stderr}")
shutil.copy(os.path.join(cg, "gate-1.json"), os.path.join(sys.argv[1], "outside.json"))
os.symlink(os.path.join(sys.argv[1], "outside.json"), os.path.join(cg, "gate-9.json"))
want("9" not in [x["id"] for x in reader.read_project(c)["rounds"]] and rv("9").returncode == 2, "a gate file linking out of the project was read")
# writers in several processes at once: each _write has its own temp file, .consumed's read-modify-write is locked
code = ("import sys; sys.path.insert(0, 'tools/desk'); import feedback; from pathlib import Path\n"
        "d, k = sys.argv[1], sys.argv[2]\n"
        "for i in range(40):\n"
        "    feedback._write(Path(d) / 'out' / 'review' / 'feedback' / '.listening', k)\n"
        "    feedback.mark_consumed(d, [f'{k}-{i}.json'])\n")
procs = [subprocess.Popen([sys.executable, "-c", code, c, f"w{k}"], stderr=subprocess.PIPE, text=True) for k in range(8)]
errs = [(p.wait(), p.stderr.read()) for p in procs]
parts = [n for n in os.listdir(fd2) if n.endswith(".part")]
want(all(rc == 0 for rc, _ in errs) and len([n for n in feedback.consumed(c) if n.startswith("w")]) == 320 and not parts,
     f"8 concurrent writers: exits {[rc for rc, _ in errs]}, {len(feedback.consumed(c))} names, leftovers {parts}, {[e[-200:] for _, e in errs if e][:1]}")
if bad:
    print("; ".join(bad))
sys.exit(1 if bad else 0)
PY
  if a=$(python3 "$t/order.py" "$t"); then ok "desk: this round is the page bin/vh review made last (1b after 2, E3b after 3, final, 2B; pending follows it), else review order (a touched file doesn't win); the gate JSON's lang overrides the BRIEF; long and deeply nested markdown in bounded time; -10 after -2"
    ok "review: 1D renders gate-1d.json as 1d; no gate renders this round (and names a newer file); ids over 24 characters and gate links out of the project are refused; 8 concurrent writers all exit 0 with every name kept"
  else bad "desk order / lang / markdown / latest / review ids / concurrent writers: $a"; fi
  # a server on a free port, on a copy (a submission writes into the project); a hidden file, a link to it, an upper-case
  # .ENV and an SVG with a script in it: none may be served same-origin
  cp -R tools/desk/fixtures/zh "$t/p" && printf '<img src=x onerror=alert(1)>\n' >> "$t/p/STORYBOARD.md"
  printf 'KEY=secret\n' > "$t/p/.env" && ln -s .env "$t/p/visible.txt" && printf 'KEY=secret\n' > "$t/p/keys.ENV"
  printf '<svg xmlns="http://www.w3.org/2000/svg"><script>fetch("/")</script></svg>\n' > "$t/p/ref.svg"
  if ! desk_start "$t/p" "$t/srv.log"; then rm -rf "$t"; return; fi
  pid=$desk_pid; url=$desk_url
  cat > "$t/client.py" <<'PY'
import http.client, json, socket, sys, urllib.parse
u = urllib.parse.urlsplit(sys.argv[1]); proj = sys.argv[2]; what = sys.argv[3]
def req(method, path, body=None, headers=None):
    c = http.client.HTTPConnection(u.hostname, u.port, timeout=10)
    h = {"Host": f"127.0.0.1:{u.port}"}
    h.update(headers or {})
    c.request(method, path, body=body, headers=h)
    r = c.getresponse(); data = r.read(); c.close()
    return r.status, r.headers, data
bad = []
def want(cond, msg):
    if not cond: bad.append(msg)
s, _, page = req("GET", "/")
token = page.decode().split('name="desk-token" content="')[1].split('"')[0]
fb = lambda **k: json.dumps(dict({"round": "1", "lang": "zh", "decisions": {"look": "L2"}, "defaulted": [], "general": "",
    "items": [{"target": "seg:1", "status": "change", "label": "大纲 第 1 段", "text": "开头再快一点 ``` 第 0 帧就要有水声"}]}, **k)).encode()
H = {"Content-Type": "application/json", "X-Desk-Token": token}
if what == "serve":
    s, _, d = req("GET", "/api/data")
    d = json.loads(d) if s == 200 else {}
    sb = next((x for x in d.get("docs", []) if x["file"] == "STORYBOARD.md"), {"sections": [], "intro": ""})
    html = sb["intro"] + "".join(x["html"] for x in sb["sections"])
    want(s == 200 and d["project"]["slug"] == "p" and "&lt;img src=x" in html and "<img src=x" not in html, f"GET /api/data: {s}, markup in a doc escaped")
    raw = open(proj + "/NOTES.md", "rb").read()
    s, h, body = req("GET", "/p/NOTES.md", headers={"Range": "bytes=2-9"})
    want(s == 206 and h["Content-Range"] == f"bytes 2-9/{len(raw)}" and body == raw[2:10], f"Range: {s} {h.get('Content-Range')}")
    s, h, body = req("GET", "/p/NOTES.md")
    want(s == 200 and body == raw and h["Accept-Ranges"] == "bytes", f"whole file: {s}")
    for p in ("/p/NOTES.md", "/p/ref.svg"):   # opened in the browser, a project page runs in an opaque origin
        csp = req("GET", p)[1].get("Content-Security-Policy", "")
        want(csp.startswith("sandbox") and "allow-same-origin" not in csp, f"{p} not sandboxed: {csp!r}")
    for p in ("/p/%2e%2e/BRIEF.md", "/p/..%2f..%2fetc/passwd", "/p/out/review/.desk.json", "/p/nope.md", "/BRIEF.md",
              "/p/.env", "/p/visible.txt", "/p/keys.ENV", "/p/keys.env"):
        want(req("GET", p)[0] == 404, f"{p} served")
    want(req("POST", "/api/feedback", fb(defaulted=5), H)[0] == 400, "defaulted: 5")
    want(req("POST", "/api/feedback", fb(lang=[1]), H)[0] == 400, "lang: [1]")
    want(req("POST", "/api/feedback", b"[" * 200000, H)[0] == 400, "200,000 nested arrays")
    want(req("POST", "/api/feedback", fb(), dict(H, **{"X-Desk-Token": "tök€n".encode("utf-8")}))[0] == 403, "a non-ASCII token")
    sk = socket.create_connection((u.hostname, u.port), timeout=10)   # a body shorter than its Content-Length
    sk.sendall(f"POST /api/feedback HTTP/1.1\r\nHost: 127.0.0.1:{u.port}\r\nContent-Type: application/json\r\n"
               f"X-Desk-Token: {token}\r\nContent-Length: 100\r\n\r\n".encode() + b'{"round": "1"}')
    sk.shutdown(socket.SHUT_WR)
    resp = sk.recv(200)
    sk.close()
    want(resp.split(b" ")[1:2] == [b"400"], f"a short body: {resp[:40]!r}")
    want(req("GET", "/api/data", headers={"Host": "evil.test"})[0] == 403, "another Host answered")
    want(req("POST", "/api/feedback", fb(), {"Content-Type": "application/json"})[0] == 403, "a post without the token")
    want(req("POST", "/api/feedback", fb(), dict(H, Origin="http://evil.test"))[0] == 403, "a post from another origin")
    want(req("POST", "/api/feedback", fb(), dict(H, **{"Content-Type": "text/plain"}))[0] == 415, "a post that isn't JSON")
    want(req("POST", "/api/feedback", fb(round="9"), H)[0] == 400, "a round with no gate page")
    want(req("POST", "/api/feedback", fb(decisions={"look": "L9"}), H)[0] == 400, "an option the gate page doesn't have")
    want(req("POST", "/api/feedback", fb(items=[{"target": "x", "status": "ok"}]), H)[0] == 400, "a bad target")
    want(json.loads(req("GET", "/api/status")[2])["listening"] is False, "listening before the watcher")
elif what == "status":
    print(json.loads(req("GET", "/api/status")[2])["listening"])
elif what == "post":   # no watcher: argv[4] is the comment
    s, _, d = req("POST", "/api/feedback", fb(items=[{"target": "seg:2", "status": "change", "label": "大纲 第 2 段", "text": sys.argv[4]}]), H)
    want(s == 200, f"post: {s} {d[:200]}")
else:
    want(json.loads(req("GET", "/api/status")[2])["listening"] is True, "the page doesn't see the watcher")
    s, _, d = req("POST", "/api/feedback", fb(), H)
    want(s == 200 and json.loads(d)["listening"] is True and json.loads(d)["saved"].startswith("out/review/feedback/1-"), f"submit: {s} {d[:200]}")
if bad:
    print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
  if a=$(python3 "$t/client.py" "$url" "$t/p" serve); then ok "desk server: page, data with markup escaped, a 206 range, project files sandboxed; refuses other hosts, paths out of the project, hidden files (also through a link, any case), posts without the token, from another origin or not JSON, an unknown round, option or target; malformed bodies and tokens get 400/403"
  else bad "desk server: $a"; fi
  "$VH_BASH" "$ROOT/bin/vh" desk wait "$t/p" --timeout 30 > "$t/wait.out" 2>&1 & wpid=$!
  for i in $(seq 50); do [ -f "$t/p/out/review/feedback/.listening" ] && break; sleep 0.2; done
  a=$(python3 "$t/client.py" "$url" "$t/p" submit); rc=$?
  wait "$wpid"; i=$?
  if [ $rc = 0 ] && [ $i = 0 ] && grep -q '第 0 帧就要有水声' "$t/wait.out" && [ ! -e "$t/p/out/review/feedback/.listening" ] \
    && python3 - "$t/p/REVIEW.md" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^## 审阅台反馈 · 关卡 1 · .*?(?=^## )", s, re.M | re.S)
sys.exit(0 if m and "开头再快一点 ``` 第 0 帧就要有水声" in m.group(0) and "\n````text\n" in m.group(0)
         and s.index("## 审阅台反馈") < s.index("## 授权跳过怎么记") and "决定 look：L2" in m.group(0) else 1)
PY
  then ok "desk: a submission wakes bin/vh desk wait (exit 0) and goes into REVIEW.md verbatim, fenced, before the template's reference sections"
  else bad "desk submit + wait: client '$a' rc $rc, wait rc $i: $(head -c 300 "$t/wait.out")"; fi
  a=$(vh desk feedback "$t/p" --round 1) && case "$a" in *"第 0 帧就要有水声"*"json: "*) true ;; *) false ;; esac \
    && vh desk feedback "$t/p" --json | python3 -c "import json, sys; d = json.load(sys.stdin); sys.exit(0 if d['decisions'] == {'look': 'L2'} and d['project'] == 'p' else 1)" \
    && ok "desk feedback prints the latest submission (text and --json)" || bad "desk feedback: $a"
  # a submission made while no watcher runs (after a timeout, say) is handed over by the next wait at once, and only once;
  # what desk feedback printed counts as handed over too
  a=$(python3 "$t/client.py" "$url" "$t/p" post "提前到的一条" && vh desk wait "$t/p" --timeout 20 2>&1); rc=$?
  vh desk wait "$t/p" --timeout 1 >/dev/null 2>&1; i=$?
  case "$rc:$i:$a" in 0:3:*"提前到的一条"*) ok "desk wait hands over a submission made before it was armed, at once and only once" ;;
    *) bad "desk wait with a submission already there: rc $rc, then $i: $(printf '%s' "$a" | head -c 300)" ;; esac
  a=$(python3 "$t/client.py" "$url" "$t/p" post "第三条" && vh desk feedback "$t/p")
  vh desk wait "$t/p" --timeout 1 >/dev/null 2>&1; rc=$?
  case "$rc:$a" in 3:*"第三条"*) ok "desk feedback counts what it printed as handed over" ;; *) bad "desk feedback then wait: rc $rc: $(printf '%s' "$a" | head -c 300)" ;; esac
  # a copy of the project carries the running server's .desk.json and a .listening that names another folder: neither counts
  cp -R "$t/p" "$t/p2" && printf '{"pid": %s, "since": 0, "until": 99999999999, "project": "%s"}\n' "$$" "$t/p" > "$t/p2/out/review/feedback/.listening"
  if desk_start "$t/p2" "$t/srv2.log"; then
    a=$(python3 "$t/client.py" "$desk_url" "$t/p2" status)
    [ "$a" = False ] && ok "desk: a copied project starts its own server, and a .listening from another folder doesn't count" || bad "desk on a copy: listening said '$a'"
    kill "$desk_pid"; wait "$desk_pid" 2>/dev/null
  fi
  a=$(vh desk "$t/p" --port 0 2>&1); case "$a" in *"already serving p"*) ok "desk: a second start points to the running server" ;; *) bad "desk second start: $a" ;; esac
  kill "$pid"; wait "$pid" 2>/dev/null
  [ ! -e "$t/p/out/review/.desk.json" ] && ok "desk: stopping the server removes out/review/.desk.json" || bad "desk left .desk.json behind"
  vh desk wait "$t/p" --timeout 1 > /dev/null 2>&1; rc=$?; [ $rc = 3 ] && ok "desk wait exits 3 on timeout" || bad "desk wait --timeout 1 exited $rc"
  # the language: bin/vh new --lang writes the BRIEF line; bin/vh review takes it when the gate JSON has no lang
  if OVH_PROJECTS="$t/new" vh new math ci-lang --lang en >/dev/null 2>&1 && grep -q '^- Review language: en ' "$t"/new/*-ci-lang/BRIEF.md \
    && OVH_PROJECTS="$t/new" vh new math ci-zh >/dev/null 2>&1 && grep -q '^- Review language: zh ' "$t"/new/*-ci-zh/BRIEF.md; then
    vh new math ci-x --lang fr >/dev/null 2>&1; rc=$?; [ $rc = 1 ] && ok "new --lang writes Review language (default zh) and rejects fr" || bad "new --lang fr exited $rc"
  else bad "new --lang: Review language not written"; fi
  cp -R tools/desk/fixtures/zh "$t/rz" && cp -R tools/desk/fixtures/zh "$t/re" && sed 's/^- Review language: zh /- Review language: en /' tools/desk/fixtures/zh/BRIEF.md > "$t/re/BRIEF.md"
  sed 's/^{/{"lang": "en",/' tools/desk/fixtures/zh/out/review/gate-1.json > "$t/rz/out/review/gate-1b.json"
  if vh review "$t/rz" 1 >/dev/null 2>&1 && vh review "$t/re" 1 >/dev/null 2>&1 && vh review "$t/rz" 1b >/dev/null 2>&1 \
    && grep -q '<html lang="zh-CN">' "$t/rz/out/review/gate-1.html" && grep -q '<html lang="en">' "$t/re/out/review/gate-1.html" \
    && grep -q '<html lang="en">' "$t/rz/out/review/gate-1b.html"
  then ok "review: the gate JSON's lang, else the BRIEF's Review language (the desk's rule), and the desk's extra keys pass"; else bad "review language rule"; fi
  rm -rf "$t"
}

# bin/vh textcheck on its fixture (tools/textcheck/fixture/index.html: one read per case), with whatever headless Chrome
# the machine has (GitHub's runners come with Chrome); skipped without one
textcheck_checks() {
  local t a rc
  t=$(mktemp -d "${TMPDIR:-/tmp}/vh-ci.XXXXXX")
  a=$(vh textcheck tools/textcheck/fixture --out "$t/out" 2>&1); rc=$?
  case "$rc:$a" in 2:*"needs a headless Chrome"*) skip "textcheck" "no Chrome, Chromium or chrome-headless-shell"; rm -rf "$t"; return ;; esac
  if [ $rc = 1 ] && python3 - "$t/out/textcheck.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
got = {r["text"]: (r["status"], sorted(f for f in ((r.get("worst") or {}).get("flags") or []) if f != "unstable")) for r in d["reads"]}
want = {"CLEAR": ("ok", []), "COVERED": ("fail", ["covered"]), "FAINT": ("fail", ["contrast"]), "OUTLINED": ("ok", []), "KINETIC": ("ok", []),
        "TWO · PARTS": ("ok", []), "GONE": ("fail", ["outside"]), "HIDDEN": ("fail", ["caption"]), "LATE": ("ok", []), "NOWHERE": ("not drawn", [])}
bad = [f"{k}: got {got.get(k)}, want {v}" for k, v in want.items() if got.get(k) != v]
late = [r for r in d["reads"] if r["text"] == "LATE"]
if not late or late[0].get("missingAt") != [0.4]: bad.append(f"LATE: missing at {late[0].get('missingAt') if late else None}, want [0.4]")
flagged = [e["text"] for e in d["extra"] if e["flagged"]]
if flagged != ["ghost"]: bad.append(f"outside the registry: flagged {flagged}, want ['ghost']")
bright = [c["text"] for c in d["captions"] if c["worst"]["close"] > 0.12]
if bright != ["a caption over a bright band"]: bad.append(f"captions over a bright picture: {bright}")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
  then ok "textcheck: covered, faint, out-of-frame and captioned-over reads fail (exit 1); outlined, kinetic and split reads pass; a late read, a faint line outside the registry and a caption over a bright band warn"
  else bad "textcheck on its fixture (exit $rc): $(printf '%s' "$a" | tail -c 1200)"; fi
  # without the contract: nothing can be drawn on demand, so exit 2 and say what to add
  sed 's/window.__vh = { draw, texts: TEXTS };//' tools/textcheck/fixture/index.html > "$t/index.html"
  a=$(vh textcheck "$t" --out "$t/out2" 2>&1); rc=$?
  case "$rc:$a" in 2:*"window.film = { frame"*) ok "textcheck without the page contract exits 2 and names the line to add" ;;
    *) bad "textcheck without the contract: exit $rc: $(printf '%s' "$a" | tail -c 800)" ;; esac
  # the same fixture written with the page contract (window.film) instead of window.__vh: the same verdicts
  sed 's/window.__vh = { draw, texts: TEXTS };/window.film = { frame: draw, duration: 4, texts: TEXTS };/' tools/textcheck/fixture/index.html > "$t/index.html"
  a=$(vh textcheck "$t" --out "$t/out3" 2>&1); rc=$?
  if [ $rc = 1 ] && python3 -c "import json, sys; d = json.load(open(sys.argv[1], encoding='utf-8')); s = {r['text']: r['status'] for r in d['reads']}; sys.exit(0 if (s.get('CLEAR'), s.get('COVERED'), s.get('NOWHERE')) == ('ok', 'fail', 'not drawn') else 1)" "$t/out3/textcheck.json"
  then ok "textcheck reads window.film as it reads window.__vh"; else bad "textcheck with window.film (exit $rc): $(printf '%s' "$a" | tail -c 800)"; fi
  # the interface over the scene (window.film.ui and frame(t, { layer: "scene" })): a dashed line across the bar and a
  # busy picture under the caption are said, each once, the shaded and grainy paper is not; a warning, exit 0. A page whose
  # scene layer draws the interface too is said so, not checked
  a=$(vh textcheck tools/textcheck/fixture/ui.html --out "$t/out4" 2>&1); rc=$?
  if [ $rc = 0 ] && python3 -c "import json, sys; d = json.load(open(sys.argv[1])); g = [(s['name'], s['from'], s['to'], s['busy']) for s in d['ui']['spans']]; sys.exit(0 if g == [('chapter bar', 2.5, 3.5, False), ('caption', 4.5, 5.5, True)] else 1)" "$t/out4/textcheck.json"
  then ok "textcheck: a line crossing the chapter bar and a busy picture under the caption are said (scene drawn alone, shading and grain left out), exit 0"
  else bad "textcheck on the interface fixture (exit $rc): $(printf '%s' "$a" | tail -c 800)"; fi
  mkdir -p "$t/ig" && sed 's/if (!(o \&\& o.layer === "scene")) ui(t);/ui(t);/' tools/textcheck/fixture/ui.html > "$t/ig/index.html"
  a=$(vh textcheck "$t/ig" --out "$t/out5" 2>&1); rc=$?
  case "$rc:$a" in 0:*'frame(t, { layer: "scene" }) drew the chapter bar too'*) ok "textcheck: a page whose scene layer draws its interface too is said so, and that pass skipped" ;;
    *) bad "textcheck on a page that ignores the scene layer (exit $rc): $(printf '%s' "$a" | tail -c 600)" ;; esac
  rm -rf "$t"
}

# bin/vh frames (tools/film): frames drawn through the page contract (engines/CONTRACT.md) on its fixtures, with
# whatever headless Chrome the machine has; the HyperFrames adapter only where its runtime is installed
film_checks() {
  local t a rc
  t=$(mktemp -d "${TMPDIR:-/tmp}/vh-ci.XXXXXX")
  a=$(vh frames tools/film/fixture --at 0.5,2.5 --out "$t/a" 2>&1); rc=$?
  case "$rc:$a" in 2:*"needs a headless Chrome"*) skip "frames" "no Chrome, Chromium or chrome-headless-shell"; rm -rf "$t"; return ;; esac
  vh frames tools/film/fixture --at 2.5 --out "$t/b" >/dev/null 2>&1
  if [ $rc = 0 ] && cmp -s "$t/a/index-t0002.500.png" "$t/b/index-t0002.500.png" && printf '%s' "$a" | grep -q "read Math.random" \
     && python3 -c "import struct, sys; d = open(sys.argv[1], 'rb').read(); sys.exit(0 if struct.unpack('>II', d[16:24]) == (320, 180) else 1)" "$t/b/index-t0002.500.png"
  then ok "frames: a page's frame at t is the same after another frame or alone (the clock holds Math.random at t, and says so), at its meta viewport size; ready is called as a method"
  else bad "frames on its fixture (exit $rc): $(printf '%s' "$a" | tail -c 800)"; fi
  a=$(vh frames tools/film/fixture/throws.html --at 1,2.5 --out "$t/c" 2>&1); rc=$?
  case "$rc:$a" in 1:*"t=2.5 s"*"no picture after 2 s"*) ok "frames: a frame that throws exits 1 and names its t" ;; *) bad "frames on a throwing page: exit $rc: $(printf '%s' "$a" | tail -c 600)" ;; esac
  a=$(vh frames tools/film/fixture/late.html --at 1,2.5 --out "$t/c2" 2>&1); rc=$?
  case "$rc:$a" in 1:*"a late error"*) ok "frames: an error a frame leaves behind (a timer) still fails the run" ;; *) bad "frames on a late error: exit $rc: $(printf '%s' "$a" | tail -c 600)" ;; esac
  a=$(vh frames tools/film/fixture/loaderr.html --at 1 --out "$t/c3" 2>&1); rc=$?
  case "$rc:$a" in 1:*"while loading: failed to load missing.png"*) ok "frames: a request that fails while loading fails the run" ;; *) bad "frames on a failed load: exit $rc: $(printf '%s' "$a" | tail -c 600)" ;; esac
  a=$(vh frames tools/film/fixture/nofilm.html --at 1 --out "$t/d" 2>&1); rc=$?
  case "$rc:$a" in 2:*"no window.film"*) ok "frames: a page without window.film exits 2" ;; *) bad "frames on a page without the contract: exit $rc: $(printf '%s' "$a" | tail -c 600)" ;; esac
  a=$(vh frames tools/film/fixture --at 5 --out "$t/e" 2>&1); rc=$?
  case "$rc:$a" in 2:*"outside the film"*) ok "frames: a time outside the film exits 2" ;; *) bad "frames outside the film: exit $rc: $(printf '%s' "$a" | tail -c 600)" ;; esac
  if command -v ffmpeg >/dev/null; then
    a=$(vh frames tools/film/fixture --strip 1:1.5 --fps 10 --out "$t/f" 2>&1); rc=$?
    if [ $rc = 0 ] && [ -s "$t/f/index-strip-1-1.5.jpg" ] && [ "$(ls "$t/f/index-strip-1-1.5" | wc -l | tr -d ' ')" = 5 ]; then ok "frames --strip: every frame of a span and one picture of them"
    else bad "frames --strip (exit $rc): $(printf '%s' "$a" | tail -c 600)"; fi
  fi
  a=$(vh determinism tools/film/fixture --samples 2 --out "$t/g" 2>&1); rc=$?
  case "$rc:$a" in 0:*"without the host's clock the frames differ"*"holds, every frame identical"*) ok "determinism: a page that reads Math.random holds under the host's clock, and is told it leans on it" ;;
    *) bad "determinism on its fixture: exit $rc: $(printf '%s' "$a" | tail -c 700)" ;; esac
  a=$(vh determinism tools/film/fixture/stateful.html --samples 2 --out "$t/h" 2>&1); rc=$?
  case "$rc:$a" in 1:*"does not hold"*) ok "determinism: a frame that depends on the frames before it does not hold (exit 1)" ;;
    *) bad "determinism on a stateful page: exit $rc: $(printf '%s' "$a" | tail -c 700)" ;; esac
  if command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null; then
    a=$(vh render tools/film/fixture --workers 2 --gop 30 --out "$t/r/film.mp4" 2>&1); rc=$?
    if [ $rc = 0 ] && python3 - "$t/r/film.mp4" <<'PY'
import json, subprocess, sys
f = sys.argv[1]
st = json.loads(subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=nb_frames,width,height,pix_fmt,color_range,color_space",
                                "-of", "json", f], capture_output=True, text=True).stdout)["streams"][0]
keys = [l.split(",")[0] for l in subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "packet=pts_time,flags", "-of", "csv=p=0", f],
                                                capture_output=True, text=True).stdout.split() if "K" in l.split(",")[1]]
side = json.load(open(f + ".render.json"))
ok = (st["nb_frames"], st["width"], st["height"], st["pix_fmt"], st["color_range"], st["color_space"]) == ("90", 320, 180, "yuv420p", "tv", "bt709")
ok = ok and [round(float(k), 3) for k in keys] == [0.0, 1.0, 2.0] and side["frames"] == 90 and side["encoder"]["gop"] == 30
sys.exit(0 if ok else 1)
PY
    then ok "render: every frame, BT.709 tv range, a keyframe exactly every --gop frames across the chunks, and how it was made beside it"
    else bad "render on its fixture (exit $rc): $(printf '%s' "$a" | tail -c 700)"; fi
    a=$(vh render tools/film/fixture --out "$t/r/film.mp4" 2>&1); rc=$?
    [ $rc = 0 ] && ok "render: a second render of the same file after the first one ended is not locked out" || bad "render again (exit $rc): $(printf '%s' "$a" | tail -c 400)"
    a=$(OVH_FREE_BYTES=1000 vh render tools/film/fixture --out "$t/r/full.mp4" 2>&1); rc=$?
    case "$rc:$a" in 2:*"needed at the peak"*"GB free on that disk"*) ok "render: a disk too full for even a flat film stops it before a frame is drawn (exit 2)" ;;
      *) bad "render on a full disk: exit $rc: $(printf '%s' "$a" | tail -c 400)" ;; esac
    # bin/vh patch: the fixture rendered from 0.5 s with a keyframe every 20 frames (not a whole number of milliseconds) in
    # a folder whose name a filter graph would choke on; then its square turned blue from 1.4 s up to 1.7 s (the film's
    # frames 27–35) and those frames put back: 20–39 drawn again, the rest the film's own bytes and times. Naming only 27–29
    # leaves 30–35 changed outside the span: refused, the film untouched. A film without its sidecar is refused at once
    mkdir -p "$t/p, x" && cp tools/film/fixture/index.html "$t/p, x/index.html"
    vh render "$t/p, x" --range 0.5:2.5 --gop 20 --workers 2 --out "$t/p, x/out/film.mp4" >/dev/null 2>&1
    sed 's/x.fillStyle = "#fc0";/x.fillStyle = t >= 1.4 \&\& t < 1.7 ? "#0cf" : "#fc0";/' tools/film/fixture/index.html > "$t/p, x/index.html"
    s0=$(cksum < "$t/p, x/out/film.mp4")
    a=$(vh patch "$t/p, x/out/film.mp4" --frames 27-29 2>&1); rc=$?
    b=$(vh patch "$t/p, x/out/film.mp4" --frames 27-35 --verify full 2>&1); rc2=$?
    if [ $rc = 1 ] && printf '%s' "$a" | grep -q 'frames 30–35 are outside 27–29' && [ -s "$t/p, x/out/film.failed.mp4" ] && [ "$(cksum < "$t/p, x/out/film.mp4")" = "$s0" ] \
      && [ $rc2 = 0 ] && printf '%s' "$b" | grep -q '20–39 drawn again' && printf '%s' "$b" | grep -q 'frames: 60 (the film: 60) ✓' \
      && printf '%s' "$b" | grep -q "packets outside 20–39: 40 the film's own ✓" && python3 - "$t/p, x/out/film.patched.mp4" <<'PY'
import json, subprocess, sys
f = sys.argv[1]
def px(t):   # the square's colour at the film's t (the page's t + 0.5): blue inside the page's 1.4–1.7 s, yellow outside
    r = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(t), "-i", f, "-frames:v", "1", "-vf", f"crop=8:8:{int(36 + 80 * (t + 0.5))}:106,scale=1:1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True)
    return tuple(r.stdout[:3])
side = json.load(open(f + ".render.json"))
blue, yellow = px(1.0), px(0.7)
sys.exit(0 if blue[2] > blue[0] + 80 and yellow[0] > yellow[2] + 80 and side["patches"][0]["frames"] == [27, 35] and side["page"] == "../index.html" else 1)
PY
    then ok "patch: frames put back between keyframes, every packet outside them the film's own; an edit reaching past the frames named is refused, the film untouched"
    else bad "patch on the fixture: exit $rc / $rc2: $(printf '%s' "$a$b" | tail -c 900)"; fi
    cp "$t/p, x/out/film.mp4" "$t/p, x/out/bare.mp4"
    a=$(vh patch "$t/p, x/out/bare.mp4" --frames 1-2 2>&1); rc=$?
    case "$rc:$a" in 2:*"no "*"bare.mp4.render.json"*) ok "patch: a film without its sidecar is refused at once (exit 2)" ;; *) bad "patch without a sidecar: exit $rc: $(printf '%s' "$a" | tail -c 400)" ;; esac
  fi
  if node -e 'import("./tools/film/host.mjs").then((m) => process.exit(m.findRuntime(process.cwd()) ? 0 : 1))' 2>/dev/null; then
    mkdir -p "$t/hf"
    cat > "$t/hf/index.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;background:#000}.clip{position:absolute;inset:0}</style></head>
<body><div id="root" data-composition-id="main" data-start="0" data-duration="2" data-width="320" data-height="180">
<div class="clip" data-start="0" data-duration="1" data-track-index="1" style="background:#c33"></div>
<div class="clip" data-start="1" data-duration="1" data-track-index="1" style="background:#3c3"></div>
</div></body></html>
HTML
    a=$(vh frames "$t/hf" --at 0.5,1.5 --out "$t/hf/out" 2>&1); rc=$?
    if [ $rc = 0 ] && printf '%s' "$a" | grep -q "HyperFrames runtime" && python3 - "$t/hf/out" <<'PY'
import sys, zlib, struct
def first_pixel(f):   # the PNG's first pixel, enough to tell the two clips apart
    d = open(f, "rb").read(); i = 8; idat = b""
    while i < len(d):
        n, kind = struct.unpack(">I4s", d[i:i + 8]); body = d[i + 8:i + 8 + n]; i += 12 + n
        if kind == b"IHDR": bpp = {2: 3, 6: 4}[body[9]]
        if kind == b"IDAT": idat += body
    row = zlib.decompress(idat)
    return tuple(row[1:1 + bpp][:3])
a, b = first_pixel(sys.argv[1] + "/index-t0000.500.png"), first_pixel(sys.argv[1] + "/index-t0001.500.png")
sys.exit(0 if a[0] > 150 and a[1] < 100 and b[1] > 150 and b[0] < 100 else 1)
PY
    then ok "frames: a HyperFrames composition without window.film is drawn by its own runtime (clips shown by their data-start)"
    else bad "frames with the HyperFrames runtime (exit $rc): $(printf '%s' "$a" | tail -c 600)"; fi
  else skip "frames on a HyperFrames composition" "no HyperFrames runtime installed (styles/_swatch: npm ci)"; fi
  # the canvas-film engine's template (engines/canvas-film): two frames draw, each the same PNG drawn first and drawn after
  # the other (12.8 s is inside a page turn); a cue whose word is gone stops it in ready at once, naming the shot and the
  # cue; its reads and captions pass textcheck
  local c="$ROOT/engines/canvas-film/template" s0 pid left seen alive
  a=$(vh frames "$c" --at 4.9,12.8 --out "$t/cf1" 2>&1); rc=$?
  # a machine without the template's CJK faces (the Linux runner) draws in a fallback and says so, which is exit 1; that
  # alone is fine here, as the frames are still compared
  if [ $rc = 1 ] && printf '%s' "$a" | grep -q 'fonts this machine does not have' \
    && ! printf '%s\n' "$a" | grep -E 'while loading:|^  t=[0-9.]+ s:|just after the last frame' | grep -qv 'fonts this machine does not have'; then rc=0; fi
  vh frames "$c" --at 12.8,4.9 --out "$t/cf2" >/dev/null 2>&1
  if [ $rc = 0 ] && cmp -s "$t/cf1/film-t0004.900.png" "$t/cf2/film-t0004.900.png" && cmp -s "$t/cf1/film-t0012.800.png" "$t/cf2/film-t0012.800.png"
  then ok "canvas-film: the template draws, and a frame is the same PNG drawn first or after another (one inside a transition too)"
  else bad "canvas-film template frames (exit $rc): $(printf '%s' "$a" | tail -c 800)"; fi
  mkdir "$t/cfb" && cp -R "$c/." "$t/cfb/" && sed 's/"@a2:第二张"/"@a2:第三张"/' "$c/src/50-shots.js" > "$t/cfb/src/50-shots.js"
  s0=$SECONDS; a=$(vh frames "$t/cfb" --at 1 --out "$t/cfb/out" 2>&1); rc=$?
  case "$rc:$a" in
    2:*'shot S02 (o.two), cue "@a2:第三张"'*'it now reads'*) if [ $((SECONDS - s0)) -lt 60 ]; then ok "canvas-film: a cue whose word is gone stops it in ready ($((SECONDS - s0)) s), naming the shot, the cue and the line as it reads now"
      else bad "canvas-film: the broken cue was reported after $((SECONDS - s0)) s, not at once"; fi ;;
    *) bad "canvas-film with a broken cue: exit $rc: $(printf '%s' "$a" | tail -c 800)" ;;
  esac
  a=$(vh textcheck "$c" --out "$t/cftc" 2>&1); rc=$?
  [ $rc = 0 ] && ok "canvas-film: textcheck passes the template's reads and captions" || bad "textcheck on the canvas-film template (exit $rc): $(printf '%s' "$a" | tail -c 800)"
  mkdir "$t/cfq" && cp -R "$c/." "$t/cfq/"
  a=$(vh cues "$t/cfq" --save 2>&1); rc=$?
  python3 - "$t/cfq/audio/timeline.zh.json" <<'PY'
import json, sys
p = sys.argv[1]; tl = json.load(open(p, encoding="utf-8"))
for s in tl["segments"]:
    if s["id"] in ("b1", "b2"):   # a new take: the last two lines 0.4 s later
        s["start"] = round(s["start"] + 0.4, 3); s["end"] = round(s["end"] + 0.4, 3)
        for w in s.get("words", []): w["start"] = round(w["start"] + 0.4, 3); w["end"] = round(w["end"] + 0.4, 3)
tl["duration"] = round(tl["duration"] + 0.4, 3)
json.dump(tl, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
  b=$(vh cues "$t/cfq" 2>&1); rc2=$?
  if [ $rc = 0 ] && [ $rc2 = 0 ] && grep -q '"timeline_sha256": "[0-9a-f]\{64\}"' "$t/cfq/out/cues.json" && printf '%s' "$a" | grep -q 'S02.o.one *@a2:第一张' \
    && printf '%s' "$b" | grep -q 'another take of the narration): 7 moved, 0 new, 0 gone' && printf '%s' "$b" | grep -q 'S03.at .*(+0.400)'
  then ok "cues: the template's cues in order, saved with the timeline's sha256; a new take says which moved and by how much"
  else bad "cues on the canvas-film template: exit $rc / $rc2: $(printf '%s' "$a$b" | tail -c 800)"; fi
  a=$(vh cues "$ROOT/tools/film/fixture/index.html" 2>&1); rc=$?
  [ $rc = 2 ] && printf '%s' "$a" | grep -q 'gives no window.film.cues' && ok "cues: a page without window.film.cues exits 2 and says so" || bad "cues on a page without cues: exit $rc: $a"
  # covers picked by cue: the template's cover A is drawn into out/covers; a longer opening (every line 0.4 s later) moves
  # its time with the narration, and the picture it takes stays the same (only the grain, a function of t, differs)
  mkdir "$t/cov" && cp -R "$c/." "$t/cov/"
  a=$(vh frames "$t/cov" --covers --out "$t/cov/c1" 2>&1); rc=$?
  python3 - "$t/cov/audio/timeline.zh.json" <<'PY'
import json, sys
p = sys.argv[1]; tl = json.load(open(p, encoding="utf-8"))
for s in tl["segments"]:
    s["start"] = round(s["start"] + 0.4, 3); s["end"] = round(s["end"] + 0.4, 3)
    for w in s.get("words", []): w["start"] = round(w["start"] + 0.4, 3); w["end"] = round(w["end"] + 0.4, 3)
tl["duration"] = round(tl["duration"] + 0.4, 3)
json.dump(tl, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
  b=$(vh frames "$t/cov" --covers --out "$t/cov/c2" 2>&1)
  t1=$(printf '%s' "$a" | sed -n 's/.*(cover A at \([0-9.]*\) s.*/\1/p'); t2=$(printf '%s' "$b" | sed -n 's/.*(cover A at \([0-9.]*\) s.*/\1/p')
  same=1; if command -v ffmpeg >/dev/null; then
    p=$(ffmpeg -v info -nostdin -i "$t/cov/c1/A.png" -i "$t/cov/c2/A.png" -lavfi psnr -f null - 2>&1 | sed -n 's/.*average:\([0-9.inf]*\).*/\1/p')
    python3 -c "import sys; v = sys.argv[1]; sys.exit(0 if v == 'inf' or float(v or 0) >= 30 else 1)" "$p" || same=0
  fi
  if [ -s "$t/cov/c1/A.png" ] && [ -n "$t1" ] && python3 -c "import sys; sys.exit(0 if abs(float(sys.argv[2]) - float(sys.argv[1]) - 0.4) < 0.002 else 1)" "$t1" "$t2" && [ $same = 1 ]
  then ok "covers: drawn into out/covers by cue; a longer opening moves the cover with the narration (+0.4 s) to the same picture"
  else bad "covers on the canvas-film template (exit $rc; $t1 → $t2, psnr ${p:-}): $(printf '%s' "$a$b" | tail -c 600)"; fi
  mkdir "$t/chp" && cp -R "$c/." "$t/chp/"
  a=$(vh cues "$t/chp" --chapters 2>&1); rc=$?
  if [ $rc = 0 ] && printf '%s' "$a" | grep -q '^  0:00 挂在字上' && printf '%s' "$a" | grep -q '^  0:11 翻一页' && printf '%s' "$a" | grep -q 'at least three'; then ok "cues --chapters: the engine's chapters as a description's list, half a second early, with YouTube's conditions"
  else bad "cues --chapters: exit $rc: $(printf '%s' "$a" | tail -c 500)"; fi
  # bin/vh fonts check on a font with only "A" and "B" (tools/film/fixture/fonts/ab.ttf): from 1 s the canvas draws a "C" and
  # U+10FFFD, the DOM a "D"; before that everything is in the font. render says the same, without failing
  a=$(vh fonts check "$ROOT/tools/film/fixture/glyphs.html" --out "$t/fo" 2>&1); rc=$?
  b=$(vh fonts check "$ROOT/tools/film/fixture/glyphs.html" --at 0.5 --out "$t/fo" 2>&1); rc2=$?
  if [ $rc = 1 ] && printf '%s' "$a" | grep -q 'not in "Fix AB", drawn in .*: C D' && printf '%s' "$a" | grep -q 'no font on this machine has 1 character.*U+10FFFD' \
    && [ $rc2 = 0 ] && printf '%s' "$b" | grep -q 'all in "Fix AB"'
  then ok "fonts check: characters a font lacks are named, on a canvas and in the DOM (another font draws them, or none: exit 1); none, exit 0"
  else bad "fonts check on its fixture: exit $rc / $rc2: $(printf '%s' "$a$b" | tail -c 900)"; fi
  if command -v ffmpeg >/dev/null; then
    a=$(vh render "$ROOT/tools/film/fixture/glyphs.html" --workers 2 --gop 30 --out "$t/fo/g.mp4" 2>&1); rc=$?
    [ $rc = 0 ] && printf '%s' "$a" | grep -q '2 workers' && printf '%s' "$a" | grep -q 'glyphs: characters not drawn in the font' && printf '%s' "$a" | grep -q 'C D' \
      && ok "render: says which characters were drawn in another font, or in none (two workers' findings as one), and still renders" \
      || bad "render on the glyph fixture: exit $rc: $(printf '%s' "$a" | tail -c 700)"
  fi
  if command -v uv >/dev/null; then
    a=$(vh fonts subset "$ROOT/tools/film/fixture/glyphs.html" --font "$ROOT/tools/film/fixture/fonts/ab.ttf" --family "Fix AB" --out "$t/fs" 2>&1); rc=$?
    [ $rc = 0 ] && [ -s "$t/fs/OVHFixtureAB-Regular.subset.woff2" ] && printf '%s' "$a" | grep -q 'src: url(".*OVHFixtureAB-Regular.subset.woff2") format("woff2")' \
      && ok "fonts subset: a font cut to the project's characters as woff2, with its src line" || bad "fonts subset: exit $rc: $(printf '%s' "$a" | tail -c 600)"
    a=$(vh fonts list --all 2>&1); rc=$?
    [ $rc = 0 ] && printf '%s' "$a" | tail -1 | grep -q '^fonts: [0-9]* face(s)' && ok "fonts list: the faces on this machine by their local() names" || bad "fonts list: exit $rc: $(printf '%s' "$a" | tail -c 400)"
  else skip "fonts subset and list" "no uv"; fi
  mkdir "$t/cfr" && cp -R "$c/." "$t/cfr/"
  a=$(vh readcheck "$t/cfr" 2>&1); rc=$?
  if [ $rc = 0 ] && [ -s "$t/cfr/out/texts.json" ] && printf '%s' "$a" | grep -q 'subtitle'; then ok "canvas-film: readcheck <project> judges the page's reads and captions (window.film.texts, written to out/texts.json)"
  else bad "readcheck on a canvas-film project (exit $rc): $(printf '%s' "$a" | tail -c 800)"; fi
  # Ctrl-C while a page is loading: the browser's profile folder goes too (Node would otherwise die without cleaning up)
  printf '%s\n' '<!doctype html><title>hang</title><script>window.film = { duration: 2, ready: new Promise(() => {}), frame() {} };</script>' > "$t/hang.html"
  mkdir -p "$t/tmpd"
  TMPDIR="$t/tmpd" "$VH_BASH" "$ROOT/bin/vh" frames "$t/hang.html" --at 1 --out "$t/hang-out" >/dev/null 2>&1 & pid=$!
  for _ in $(seq 1 120); do ls -d "$t/tmpd"/vh-textcheck-* >/dev/null 2>&1 && break; sleep 0.25; done
  seen=$(ls -d "$t/tmpd"/vh-textcheck-* 2>/dev/null | wc -l | tr -d ' ')   # a browser was up: otherwise this tests nothing
  sleep 1; kill -INT "$pid" 2>/dev/null; wait "$pid"; rc=$?; sleep 1
  left=$(ls -d "$t/tmpd"/vh-textcheck-* 2>/dev/null | wc -l | tr -d ' '); alive=$(pgrep -f "$t/tmpd" | wc -l | tr -d ' ')
  [ "$seen" -ge 1 ] && [ "$rc" = 130 ] && [ "$left" = 0 ] && [ "$alive" = 0 ] && ok "frames stopped with Ctrl-C ends (exit 130), leaving no browser profile and no Chrome behind" \
    || bad "frames after Ctrl-C: a browser seen $seen, exit $rc, $left profile folder(s) and $alive Chrome process(es) left"
  pkill -KILL -f "$t/tmpd" 2>/dev/null
  # Ctrl-C after the last browser closed (determinism comparing its frames, synchronous work): the process ends at once,
  # not after the comparisons (a signal listener left in place would hold the signal until the event loop turned again)
  printf '%s\n' '<!doctype html><canvas id="c" width="64" height="36"></canvas><script>const x = document.getElementById("c").getContext("2d");' \
    'window.film = { duration: 2, frame(t) { x.fillStyle = `rgb(${Math.floor(Math.random() * 255)},90,${Math.floor(t * 100)})`; x.fillRect(0, 0, 64, 36); } };</script>' > "$t/rnd.html"
  "$VH_BASH" "$ROOT/bin/vh" determinism "$t/rnd.html" --at "$(seq -s, 0.02 0.02 1.9 | sed 's/,$//')" --out "$t/rnd-out" >/dev/null 2>&1 & pid=$!
  seen=0; for _ in $(seq 1 600); do if pgrep -P "$pid" -f psnr >/dev/null 2>&1; then seen=1; break; fi; kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  if [ $seen = 1 ]; then kill -INT "$pid" 2>/dev/null; wait "$pid"; rc=$?
    [ "$rc" = 130 ] && ok "determinism stopped with Ctrl-C while comparing ends at once (exit 130)" || bad "determinism after Ctrl-C while comparing: exit $rc (it went on)"
  else wait "$pid" 2>/dev/null; skip "Ctrl-C while determinism compares" "the comparisons were not caught running"; fi
  rm -rf "$t"
}

# bin/vh timeline (the narration timeline's checks) and bin/vh remap, and the refusal in bin/vh captions
timeline_checks() {
  local t a rc
  t=$(mktemp -d "${TMPDIR:-/tmp}/vh-ci.XXXXXX")
  a=$(vh timeline showcase/02-short-leo-doppler zh 2>&1); rc=$?
  [ $rc = 0 ] && printf '%s' "$a" | grep -q "timeline: sound" && ok "timeline: showcase 02's narration is sound" || bad "timeline on showcase 02: exit $rc: $a"
  mkdir -p "$t/p/audio"
  python3 - "$t/p/audio/timeline.zh.json" <<'PY'
import json, sys
tl = json.load(open("showcase/02-short-leo-doppler/audio/timeline.zh.json", encoding="utf-8"))
s = tl["segments"][1]; s["words"][2]["start"] = s["words"][1]["start"] - 0.5   # a word time out of order
s = tl["segments"][3]; s["words"][0]["w"] = "宾果"                               # an aligner that spelled a word its own way
json.dump(tl, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
  a=$(vh timeline "$t/p" zh 2>&1); rc=$?
  case "$rc:$a" in 1:*"out of order"*"the words read"*) ok "timeline: a word time out of order and a word spelled differently from the text are problems (exit 1)" ;;
    *) bad "timeline on a broken timeline: exit $rc: $a" ;; esac
  a=$(vh captions "$t/p" zh 2>&1); rc=$?
  b=$(vh captions "$t/p" zh --skip-lint 2>&1); rc2=$?
  c=$(vh captions "$t/p" zh --skip-lint --media-end 30 2>&1); rc3=$?
  if [ $rc = 1 ] && printf '%s' "$a" | grep -q "timed wrong" && [ $rc2 = 0 ] && [ $rc3 = 0 ] && [ -s "$t/p/audio/captions.json" ]; then ok "captions: refuses a timeline that fails its checks, and goes on with --skip-lint (before or after --media-end)"
  else bad "captions on a broken timeline: exit $rc ($a) / with --skip-lint exit $rc2 ($b) / --skip-lint --media-end exit $rc3 ($c)"; fi
  # captions at word boundaries (jieba through uv): a long line without a comma is cut between words, one-line cards never
  # cross a sentence end, and the break table starts a card at its phrase
  if command -v uv >/dev/null && uv run -q --no-project --with jieba python -c "import jieba" >/dev/null 2>&1; then
    mkdir -p "$t/cw/audio" && printf '# BRIEF\n' > "$t/cw/BRIEF.md"
    python3 - "$t/cw/audio/timeline.zh.json" <<'PY'
import json, sys
def line(i, t0, text):
    cs = [c for c in text if c not in "，。"]; ws, t = [], t0
    for c in cs: ws.append({"w": c, "start": round(t, 3), "end": round(t + 0.2, 3)}); t += 0.2
    return {"id": i, "zh": text, "start": t0, "end": round(t, 3), "words": ws}
segs = [line("c1", 0.0, "今天我们一起来看看这台机器到底是怎么工作的"), line("c2", 6.0, "说到第一张，卡片落下。说到第二张，第二张跟上。")]
json.dump({"lang": "zh", "duration": 12.0, "segments": segs}, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
    printf '["卡片落下"]\n' > "$t/cw/audio/capbreaks.json"
    a=$(vh captions "$t/cw" zh --cards 2>&1); rc=$?
    if [ $rc = 0 ] && printf '%s' "$a" | grep -q 'word boundaries by jieba' && PYTHONWARNINGS=ignore uv run -q --no-project --with jieba python - "$t/cw/audio/captions.json" <<'PY'
import json, logging, sys, jieba
jieba.setLogLevel(logging.ERROR)
cards = json.load(open(sys.argv[1], encoding="utf-8"))
c1 = [c["zh"][0] for c in cards if c["id"] == "c1"]; c2 = [c["zh"][0] for c in cards if c["id"] == "c2"]
text = "今天我们一起来看看这台机器到底是怎么工作的"
bounds, pos = set(), 0
for w in jieba.lcut(text): pos += len(w); bounds.add(pos)
cuts, pos = [], 0
for c in c1[:-1]: pos += len(c); cuts.append(pos)
ok = len(c1) >= 2 and "".join(c1) == text and all(x in bounds for x in cuts)
ok = ok and not any("落下" in c and "第二张" in c for c in c2) and any(c.startswith("卡片落下") for c in c2)
sys.exit(0 if ok else 1)
PY
    then ok "captions --cards: cut between words (jieba), never across a sentence end, a card starting at the break table's phrase"
    else bad "captions --cards (exit $rc): $(printf '%s' "$a" | tail -c 500) $(cat "$t/cw/audio/captions.zh.srt" 2>/dev/null | tr '\n' '|' | tail -c 400)"; fi
    # numbers, times and links stay whole at a narrow width (jieba cuts them at their , and :)
    if a=$(PYTHONWARNINGS=ignore uv run -q --no-project --with jieba python - "$ROOT/tools/audio" 2>&1 <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import capbreak, captions
bad = []
for text, w, keep in (("价格从1,000,000元涨到2,500,000元", 8, ("1,000,000", "2,500,000")), ("价格从1,000,000元涨到", 6, ("1,000,000",)),
                      ("会议定在12:30开始，别迟到", 6, ("12:30",)), ("在12:30:45开始", 6, ("12:30:45",)),
                      ("网址是https://example.com/a/b，记下来。", 8, ("https://example.com/a/b",)), ("网址是https://a.example.com:8080/x/y，记下", 6, ("https://a.example.com:8080/x/y",))):
    for got in ([r for _, r in capbreak.pieces(text, w, True)], captions.wrap_zh(text, w)):
        if not all(any(k in g for g in got) for k in keep): bad.append(f"{text} at {w}: {got}")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
    ); then ok "captions: 2,500,000, 12:30 and a link stay whole at a narrow width, in cards and wrapped lines"
    else bad "captions split a number, a time or a link: $a"; fi
  else skip "captions at word boundaries" "no uv to bring jieba"; fi
  # cards in English stay within --en-max characters and end at . ! ?; half-width ? ! end a Chinese sentence; a card that
  # would start after the media end is left out, and no card ends before it starts
  mkdir -p "$t/ce/audio" "$t/ch/audio" && printf '# BRIEF\n' > "$t/ce/BRIEF.md" && cp "$t/ce/BRIEF.md" "$t/ch/BRIEF.md"
  python3 - "$t" <<'PY'
import json, re, sys
d = sys.argv[1]
def seg(i, lang, text, t0, dt):
    ws, t = [], t0
    for w in (re.findall(r"[A-Za-z0-9']+", text) if lang == "en" else [c for c in text if c.strip() and c not in "?!，。"]):
        ws.append({"w": w, "start": round(t, 3), "end": round(t + dt, 3)}); t += dt
    return {"id": i, lang: text, "start": t0, "end": round(t, 3), "words": ws}
en = "The quick brown fox jumps over the lazy dog and keeps on running. Version 3.5 is out! Is it fast? It is"
json.dump({"lang": "en", "duration": 30.0, "segments": [seg("e1", "en", en, 0.0, 0.3)]}, open(f"{d}/ce/audio/timeline.en.json", "w"))
json.dump({"lang": "zh", "duration": 25.0, "segments": [seg("h1", "zh", "真的吗?我不信!你再说一遍", 0.0, 0.25), seg("h2", "zh", "这一句在画面结束以后才开始", 20.0, 0.25)]},
          open(f"{d}/ch/audio/timeline.zh.json", "w"), ensure_ascii=False)
PY
  a=$(vh captions "$t/ce" en --cards 2>&1); rc=$?
  b=$(vh captions "$t/ch" zh --cards --media-end 19 2>&1); rc2=$?
  if [ $rc = 0 ] && [ $rc2 = 0 ] && printf '%s' "$b" | grep -q "left out, starts after the media end" && python3 - "$t" <<'PY'
import json, sys
d = sys.argv[1]
en = [c["en"][0] for c in json.load(open(f"{d}/ce/audio/captions.json"))]
zh = json.load(open(f"{d}/ch/audio/captions.json", encoding="utf-8"))
ok = all(len(c) <= 42 for c in en) and not any(". " in c or "! " in c or "? " in c for c in en) and "Version 3.5 is out!" in en
ok = ok and [c["zh"][0] for c in zh][:2] == ["真的吗?", "我不信!"] and all(c["id"] == "h1" and c["end"] > c["start"] for c in zh)
sys.exit(0 if ok else 1)
PY
  then ok "captions --cards: English within --en-max and cut at . ! ? (3.5 whole), half-width ? ! end a Chinese sentence, a card after the media end left out"
  else bad "captions --cards in English / half-width / media end (exit $rc, $rc2): $(printf '%s' "$a $b" | tail -c 400) $(head -c 600 "$t/ce/audio/captions.json" 2>/dev/null)"; fi
  # check: an SRT beside the video with an entry too short to read is listed (a warning, not a failure)
  if command -v ffmpeg >/dev/null; then
    mkdir -p "$t/sc" && ffmpeg -nostdin -v error -f lavfi -i color=c=0x303030:s=320x180:r=30:d=3 -pix_fmt yuv420p "$t/sc/film.mp4"
    printf '1\n00:00:00,500 --> 00:00:01,300\n这一句只亮了零点八秒\n\n2\n00:00:01,300 --> 00:00:03,200\n这句够长\n' > "$t/sc/film.zh.srt"
    a=$(vh check "$t/sc/film.mp4" 2>&1); rc=$?
    case "$a" in *"subtitles · film.zh.srt: 1 of 2 entries are shorter than it takes to read them"*"0.80 s, needs 1.80 s"*) ok "check lists subtitle entries too short to read, from the SRT beside the film" ;;
      *) bad "check on a short subtitle (rc $rc): $(printf '%s' "$a" | tail -c 500)" ;; esac
  fi
  python3 - "$t" <<'PY'
import json, sys
d = sys.argv[1]
line = lambda i, t0, text, ws: {"id": i, "text": text, "start": t0, "end": round(t0 + sum(w[1] for w in ws), 3), "words": [
    {"w": w, "start": round(t0 + sum(x[1] for x in ws[:k]), 3), "end": round(t0 + sum(x[1] for x in ws[:k + 1]), 3)} for k, (w, _) in enumerate(ws)]}
for name, gap in (("old", 0.5), ("new", 1.5)):   # the new take has 1 s more before the second line
    json.dump({"lang": "zh", "segments": [line("a", 0.0, "风吹过", [("风", 0.4), ("吹过", 1.1)]), line("b", 1.5 + gap, "纸飞走了", [("纸", 0.5), ("飞走了", 1.5)])]},
              open(f"{d}/{name}.json", "w", encoding="utf-8"), ensure_ascii=False)
json.dump([{"t": 0.2, "sfx": "wind"}, {"t": 2.6, "sfx": "paper", "gain_db": -6}, {"name": "x", "start": 1.8, "end": 4.5}], open(f"{d}/events.json", "w"))
PY
  a=$(vh remap "$t/events.json" --from "$t/old.json" --to "$t/new.json" 2>&1); rc=$?
  if [ $rc = 0 ] && python3 -c "import json, sys; e = json.load(open(sys.argv[1])); sys.exit(0 if (e[0]['t'], e[1]['t'], e[1]['gain_db'], e[2]['start'], e[2]['end']) == (0.2, 3.6, -6, 2.4, 5.5) else 1)" "$t/events.json" && [ -s "$t/events.json.bak" ]
  then ok "remap: seconds inside a line move with its words, in a gap in proportion, after the end with the last word; other numbers stay; the original kept as .bak"
  else bad "remap: exit $rc: $a $(cat "$t/events.json" 2>/dev/null)"; fi
  a=$(vh remap "$t/events.json" --from "$t/old.json" --to "$t/new.json" 2>&1); rc=$?
  [ $rc = 2 ] && printf '%s' "$a" | grep -q "is there already" && ok "remap: refuses to overwrite an earlier remap's .bak" || bad "remap with a .bak there: exit $rc: $a"
  python3 - "$t" <<'PY'
import json, sys
d = sys.argv[1]   # two lines that meet at 1.0 s; the new take puts 0.8 s between them
L = lambda i, a, b, t: {"id": i, "text": t, "start": a, "end": b}
json.dump({"segments": [L("a", 0, 1, "风"), L("b", 1, 2, "纸")]}, open(f"{d}/old2.json", "w"))
json.dump({"segments": [L("a", 0, 1, "风"), L("b", 1.8, 2.8, "纸")]}, open(f"{d}/new2.json", "w"))
json.dump([{"t": 0.9}, {"t": 1.1}, {"t": 1.6}], open(f"{d}/ev2.json", "w"))
PY
  a=$(vh remap "$t/ev2.json" --from "$t/old2.json" --to "$t/new2.json" --out "$t/ev2o.json" 2>&1); rc=$?
  if [ $rc = 0 ] && python3 -c "import json, sys; sys.exit(0 if [e['t'] for e in json.load(open(sys.argv[1]))] == [0.9, 1.9, 2.4] else 1)" "$t/ev2o.json"
  then ok "remap: where two lines met and a pause came between them, a time on the later line moves with it"
  else bad "remap across a new pause: exit $rc: $a $(cat "$t/ev2o.json" 2>/dev/null)"; fi
  rm -rf "$t"
}

# bin/vh pace on a synthetic take (22.05 kHz): tone-burst "syllables" with known onsets, lines at 4 to 7 a second, a long
# pause inside a line and one the script asks for, gaps too short and too long, an ASR start placed 0.12 s late, one line's
# end and the next one's start put at the same instant inside the first one's last syllable (an aligner did that), and a
# "……" line. Then ASRs that are further off, a line with no audio, and the refusals. Checked against the known syllables,
# not against the tool's own numbers
pace_checks() {
  local t p v a rc
  if ! command -v uv >/dev/null || ! command -v ffmpeg >/dev/null; then skip "pace" "needs uv and ffmpeg"; return; fi
  t=$(mktemp -d "${TMPDIR:-/tmp}/vh-ci.XXXXXX"); p="$t/p"
  python3 - "$p/audio" <<'PY'
import json, math, struct, sys, wave
from pathlib import Path
a = Path(sys.argv[1]); a.mkdir(parents=True); SR = 22050
lines = [("a1", "一二三四五六七八，", 4.0, None, 0.05), ("a2", "九十百千万亿兆京。", 7.0, None, 1.6),    # id, text, per second,
         ("b1", "甲乙丙丁戊己庚辛壬癸。", 5.5, (5, 0.7), 0.4), ("b2", "好。", 3.0, None, 0.3),         # (after unit k, pause),
         ("b3", "子丑寅卯辰巳午未。", 5.0, (4, 0.6), 0.5), ("b4", "东南西北中发白。", 5.6, None, 0.0)]   # gap after the line
(a / "script.txt").write_text("@a1 一二三四五六七八，\n@a2 九十百千万亿兆京。\n\n@b1 甲乙丙丁戊己庚辛壬癸。\n@b2 好。\n"
                              "@b3 子丑寅卯<long pause>辰巳午未。\n@b3x ……\n@b4 东南西北中发白。\n", encoding="utf-8")
x, segs = [0.0] * int(0.4 * SR), []
for k, (sid, text, rate, pause, gap) in enumerate(lines):
    chars = [c for c in text if c not in "，。"]; burst = 0.75 / rate; words = []
    for j, c in enumerate(chars):
        t0, n, f0 = len(x) / SR, int(burst * SR), 140 + 15 * ((j * 7 + k * 3) % 5)
        x += [0.25 * math.sin(math.pi * i / n) ** 0.5 * (math.sin(2 * math.pi * f0 * i / SR) + 0.5 * math.sin(4 * math.pi * f0 * i / SR)) for i in range(n)]
        words.append({"w": c + (text[-1] if j == len(chars) - 1 else ""), "start": round(t0, 3), "end": round(len(x) / SR, 3)})
        if j + 1 < len(chars):
            x += [0.0] * int((1 / rate - burst + (pause[1] if pause and j + 1 == pause[0] else 0)) * SR)
    if sid == "a1":
        words[0]["start"] += 0.12                     # the ASR heard the first syllable late
    if sid == "b2":                                   # b1 ends and b2 starts at the same instant, 20 ms before b1's voice ends
        segs[-1]["words"][-1]["end"] = words[0]["start"] = segs[-1]["end"] = round(segs[-1]["end"] - 0.02, 3)
    if sid == "b4":                                   # "……": no words, its span is the pause
        segs.append({"id": "b3x", "zh": "……", "en": "", "text": "……", "start": segs[-1]["end"], "end": words[0]["start"]})
    segs.append({"id": sid, "zh": text, "en": "", "text": text, "start": words[0]["start"], "end": words[-1]["end"], "words": words})
    x += [0.0] * int(gap * SR)
x += [0.0] * int(0.5 * SR)
with wave.open(str(a / "voiceover.zh.wav"), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(struct.pack(f"<{len(x)}h", *(int(round(v * 32767)) for v in x)))
tl = json.dumps({"provider": "say", "lang": "zh", "duration": round(len(x) / SR, 3), "segments": segs}, ensure_ascii=False)
for f in ("timeline.zh.json", "timeline.json"):
    (a / f).write_text(tl, encoding="utf-8")
(a / "voiceover.wav").write_bytes((a / "voiceover.zh.wav").read_bytes())
PY
  cp -R "$p/audio" "$t/orig"
  # the onsets of the syllables in a take (10 ms frames above −40 dBFS) and the quiet before each: what every check below counts
  cat > "$t/onsets.py" <<'PY'
import subprocess, numpy as np
def onsets(wav, sr=22050):
    y = np.frombuffer(subprocess.run(["ffmpeg", "-v", "error", "-i", wav, "-f", "f32le", "-ac", "1", "-ar", str(sr), "-"],
                                     check=True, capture_output=True).stdout, "<f4")
    hop = sr // 100; n = len(y) // hop
    on = 10 * np.log10(np.mean(y[: n * hop].reshape(n, hop) ** 2, 1) + 1e-18) > -40
    up, down = (np.flatnonzero(np.diff(on.astype(int)) == 1) + 1) * 0.01, (np.flatnonzero(np.diff(on.astype(int)) == -1) + 1) * 0.01
    return up, np.array([up[0]] + [u - d for u, d in zip(up[1:], down)]), on
PY
  vh pace "$p" --dry-run >/dev/null && diff -r "$p/audio" "$t/orig" >/dev/null && ok "pace --dry-run writes nothing" || bad "pace --dry-run changed the project"
  if a=$(vh pace "$p" 2>&1) && a=$(PYTHONPATH="$t" uv run -q --no-project --with numpy python - "$p/audio" "$t/orig" 2>&1 <<'PY'
import json, sys
import numpy as np
from onsets import onsets
A, O = sys.argv[1], sys.argv[2]; bad = []
tl = json.load(open(f"{A}/timeline.zh.json", encoding="utf-8")); P = tl["pace"]; S = {s["id"]: s for s in tl["segments"]}
if open(f"{A}/voiceover.zh.raw.wav", "rb").read() != open(f"{O}/voiceover.zh.wav", "rb").read() or \
   open(f"{A}/timeline.zh.raw.json", "rb").read() != open(f"{O}/timeline.zh.json", "rb").read(): bad.append("the .raw files are not the original")
if open(f"{A}/voiceover.wav", "rb").read() != open(f"{A}/voiceover.zh.wav", "rb").read(): bad.append("voiceover.wav is not the paced copy")
ons, quiet, on = onsets(f"{A}/voiceover.zh.wav")
words = [w for s in tl["segments"] for w in s.get("words", [])]
if len(ons) != 42 or len(words) != 42: bad.append(f"{len(ons)} syllables in the paced take, {len(words)} words (42 each)")
else:
    err = np.abs(ons - [w["start"] for w in words])
    if err.max() > 0.035: bad.append(f"a mapped word {err.max():.3f} s from its syllable ({words[int(err.argmax())]['w']})")
L = {l["id"]: l for l in P["lines"]}
paced = [l for l in P["lines"] if l.get("note") not in ("short", "no words")]
sd = lambda k: float(np.std([l[k] for l in paced]))
if not sd("after") < 0.8 * sd("pace"): bad.append(f"spread of paces {sd('pace'):.2f} → {sd('after'):.2f}")
if not all(0.92 - 1e-9 <= l["tempo"] <= 1.18 + 1e-9 for l in P["lines"] if "tempo" in l) or L["b2"]["tempo"] != 1.0 or L["a1"]["tempo"] <= 1 \
   or L["a2"]["tempo"] >= 1 or L["b3x"].get("note") != "no words":
    bad.append(f"tempos {[(l['id'], l.get('tempo'), l.get('note')) for l in P['lines']]}")
def longest_quiet(s):
    q = on[int(s["start"] / 0.01): int(s["end"] / 0.01)]; best = cur = 0
    for v in q:
        cur = 0 if v else cur + 1; best = max(best, cur)
    return best * 0.01
if longest_quiet(S["b1"]) > 0.3 or longest_quiet(S["b3"]) < 0.5: bad.append(f"inner pauses: b1 {longest_quiet(S['b1']):.2f} (cap 0.26), b3 {longest_quiet(S['b3']):.2f} (asked for)")
gap = lambda i, j: S[j]["start"] - S[i]["end"]
if not (0.1 <= gap("a1", "a2") <= 0.2 and 1.1 <= gap("a2", "b1") <= 1.25 and 0.35 <= gap("b1", "b2") <= 0.45 and 0.45 <= gap("b3", "b4") <= 0.56):
    bad.append(f"gaps a1-a2 {gap('a1', 'a2'):.2f} (0.12), a2-b1 {gap('a2', 'b1'):.2f} (1.2), b1-b2 {gap('b1', 'b2'):.2f} (the take's 0.4),"
               f" b3-b4 {gap('b3', 'b4'):.2f} (the 0.5 a \"……\" line stands for)")
if not S["b3"]["end"] - 0.005 <= S["b3x"]["start"] <= S["b3x"]["end"] <= S["b4"]["start"] + 0.005: bad.append(f"the \"……\" line is not between b3 and b4: {S['b3x']}")
caps = json.load(open(f"{A}/captions.json", encoding="utf-8"))
if [c["start"] for c in caps] != [s["start"] for s in tl["segments"]]: bad.append("captions.json is not from the paced timeline")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
  ); then ok "pace: every syllable kept and every mapped word on it, paces closer within the clamp, an inner pause capped and an asked-for one kept, gaps in range, a \"……\" line's pause kept, originals kept, captions redone"
  else bad "pace on a synthetic take: $a"; fi
  cp "$p/audio/voiceover.zh.wav" "$t/once.wav"
  vh pace "$p" >/dev/null && cmp -s "$t/once.wav" "$p/audio/voiceover.zh.wav" && ok "pace runs again from the original take: the same bytes" || bad "pace: a second run gave a different take"
  vh pace "$p" --restore --dry-run >/dev/null 2>&1; rc=$?
  [ $rc = 2 ] && cmp -s "$t/once.wav" "$p/audio/voiceover.zh.wav" && ok "pace --restore --dry-run is refused" || bad "pace --restore --dry-run: exit $rc"
  vh pace "$p" --restore >/dev/null && cmp -s "$p/audio/voiceover.zh.wav" "$t/orig/voiceover.zh.wav" && cmp -s "$p/audio/timeline.zh.json" "$t/orig/timeline.zh.json" \
    && cmp -s "$p/audio/voiceover.wav" "$t/orig/voiceover.zh.wav" && cmp -s "$p/audio/timeline.json" "$t/orig/timeline.json" \
    && [ ! -e "$p/audio/voiceover.zh.raw.wav" ] && ok "pace --restore puts the original back" || bad "pace --restore"
  # ASRs further off: every start 0.2 s late and end 0.3 s early (f), a line break placed 0.1 s inside a2's last syllable (m),
  # the last line with no audio at all (s): no syllable lost or moved behind a pause, no crash
  for v in f m s; do mkdir "$t/$v" && cp -R "$t/orig" "$t/$v/audio"; done
  python3 - "$t" <<'PY'
import json, subprocess, sys
t = sys.argv[1]; F = "audio/timeline.zh.json"
def edit(v, fn):
    tl = json.load(open(f"{t}/{v}/{F}", encoding="utf-8")); fn(tl["segments"]); json.dump(tl, open(f"{t}/{v}/{F}", "w", encoding="utf-8"), ensure_ascii=False)
def late(segs):
    for s in segs:
        if s.get("words"):
            s["start"] = s["words"][0]["start"] = round(min(s["start"] + 0.2, s["words"][0]["end"]), 3)
            s["end"] = s["words"][-1]["end"] = round(max(s["end"] - 0.3, s["words"][-1]["start"]), 3)
def inside(segs):
    p, q = segs[1], segs[2]                           # a2 | b1
    p["end"] = p["words"][-1]["end"] = q["start"] = q["words"][0]["start"] = round(p["end"] - 0.1, 3)
edit("f", late); edit("m", inside)
b4 = json.load(open(f"{t}/s/{F}", encoding="utf-8"))["segments"][-1]["start"]
subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", f"{t}/orig/voiceover.zh.wav", "-t", f"{b4 - 0.05:.3f}", f"{t}/s/audio/voiceover.zh.wav"], check=True)
PY
  a=""; for v in f m s; do vh pace "$t/$v" >/dev/null 2>"$t/$v.err" || a="$a $v: $(tail -c 300 "$t/$v.err")"; done
  if [ -z "$a" ] && a=$(PYTHONPATH="$t" uv run -q --no-project --with numpy python - "$t" 2>&1 <<'PY'
import json, sys
from onsets import onsets
t = sys.argv[1]; bad = []
for v, want in (("f", 42), ("m", 42), ("s", 35)):
    ons, quiet, _ = onsets(f"{t}/{v}/audio/voiceover.zh.wav")
    if len(ons) != want: bad.append(f"{v}: {len(ons)} syllables, want {want}")
    elif v == "m" and quiet[15] > 0.1: bad.append(f"m: a2's last syllable moved behind a {quiet[15]:.2f} s pause")
L = {l["id"]: l for l in json.load(open(f"{t}/s/audio/timeline.zh.json", encoding="utf-8"))["pace"]["lines"]}
if L["b4"].get("note") != "nothing heard": bad.append(f"s: b4 {L['b4']}")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
  ); then ok "pace: ASR starts 0.2 s late and ends 0.3 s early, a line break inside a syllable, a line with no audio: every syllable kept, none moved"
  else bad "pace with an ASR further off:$a"; fi
  # more cases, each on its own copy: b1 with no audio (u), b1 and b2 spans swapped (o), word times only in the cache (c, and c2
  # without it), no script.txt (n), and a take of its own (t): a quiet breath before one line, three short loud syllables
  # opening the next
  for v in u o c c2 n; do mkdir "$t/$v" && cp -R "$t/orig" "$t/$v/audio"; done
  python3 - "$t" <<'PY'
import hashlib, json, math, struct, sys, wave
from pathlib import Path
t = sys.argv[1]; F = "audio/timeline.zh.json"
tl = json.load(open(f"{t}/orig/timeline.zh.json", encoding="utf-8")); S = {s["id"]: s for s in tl["segments"]}
b1 = S["b1"]                                          # b1's syllables zeroed (its timeline end sits 0.02 s before its voice ends)
with wave.open(f"{t}/orig/voiceover.zh.wav") as r:
    sr, pcm = r.getframerate(), bytearray(r.readframes(r.getnframes()))
z0, z1 = int((b1["words"][0]["start"] - 0.005) * sr), int((b1["words"][-1]["end"] + 0.025) * sr)
pcm[2 * z0: 2 * z1] = bytes(2 * (z1 - z0))
with wave.open(f"{t}/u/audio/voiceover.zh.wav", "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(bytes(pcm))
o = json.loads(json.dumps(tl)); a, b = o["segments"][2], o["segments"][3]
a["start"], a["end"], b["start"], b["end"] = b["start"], b["end"], a["start"], a["end"]
json.dump(o, open(f"{t}/o/{F}", "w", encoding="utf-8"), ensure_ascii=False)
for v in ("c", "c2"):                                 # word times removed; for c they are in the cache under the take's sha256
    c = json.loads(json.dumps(tl))
    for s in c["segments"]:
        s.pop("words", None)
    Path(f"{t}/{v}/{F}").write_text(json.dumps(c, ensure_ascii=False), encoding="utf-8")
sha = hashlib.sha256(open(f"{t}/orig/voiceover.zh.wav", "rb").read()).hexdigest()
Path(f"{t}/c/audio/pace.zh.asr.json").write_text(json.dumps({"sha256": sha, "engine": "whisper", "segments": [
    {"start": s["start"], "end": s["end"], **({"words": s["words"]} if s.get("words") else {})} for s in tl["segments"]]}), encoding="utf-8")
Path(f"{t}/n/audio/script.txt").unlink()
SR, x, segs, A = 22050, [0.0] * int(0.4 * 22050), [], Path(f"{t}/t/audio")
A.mkdir(parents=True)
def burst(dur, amp, f0):
    n = int(dur * SR); return [amp * math.sin(math.pi * i / n) ** 0.5 * (math.sin(2 * math.pi * f0 * i / SR) + 0.5 * math.sin(4 * math.pi * f0 * i / SR)) for i in range(n)]
for sid, text, plan in (("t1", "甲乙丙丁戊己庚辛。", [("breath",)] + [(0.15, 0.05)] * 8), ("t2", "子丑寅卯辰巳午未申酉戌亥。", [(0.09, 0.09)] * 3 + [(0.15, 0.05)] * 9),
                        ("t3", "东南西北中发白甲。", [(0.15, 0.05)] * 8)):
    words, chars = [], iter(text[:-1])
    for k, step in enumerate(plan):
        if step == ("breath",):
            x += burst(0.08, 0.0095, 300) + [0.0] * int(0.12 * SR); continue
        t0 = len(x) / SR; x += burst(step[0], 0.25, 150 + 10 * (k % 4))
        words.append({"w": next(chars), "start": round(t0, 3), "end": round(len(x) / SR, 3)}); x += [0.0] * int(step[1] * SR)
    words[-1]["w"] += "。"; segs.append({"id": sid, "zh": text, "en": "", "text": text, "start": words[0]["start"], "end": words[-1]["end"], "words": words})
    x += [0.0] * int(0.45 * SR)
with wave.open(str(A / "voiceover.zh.wav"), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(struct.pack(f"<{len(x)}h", *(int(round(v * 32767)) for v in x)))
(A / "timeline.zh.json").write_text(json.dumps({"provider": "say", "lang": "zh", "segments": segs}, ensure_ascii=False), encoding="utf-8")
(A / "script.txt").write_text("".join(f"@{s['id']} {s['text']}\n" for s in segs), encoding="utf-8")
PY
  cp -R "$t/c/audio" "$t/c.before"
  a=""; rc=0
  vh pace "$t/u" >"$t/u.out" 2>&1 || a="$a u: $(tail -c 300 "$t/u.out")"
  vh pace "$t/t" >"$t/t.out" 2>&1 || a="$a t: $(tail -c 300 "$t/t.out")"
  b=$(vh pace "$t/c" --dry-run 2>&1) && diff -r "$t/c/audio" "$t/c.before" >/dev/null || a="$a c --dry-run wrote or failed: $b"
  case "$b" in *"transcribed before"*) ;; *) a="$a c --dry-run did not use the cache: $b" ;; esac
  vh pace "$t/c" >/dev/null 2>&1 && cmp -s "$t/c/audio/timeline.zh.raw.json" "$t/c.before/timeline.zh.json" || a="$a c: the .raw timeline is not the original"
  b=$(vh pace "$t/c2" 2>&1); [ $? = 1 ] && case "$b" in *"no word times"*) ;; *) false ;; esac || a="$a c2 (no words, no cache): $b"
  b=$(vh pace "$t/o" 2>&1); [ $? = 1 ] && case "$b" in *"the timeline has"*"out of order"*) ;; *) false ;; esac || a="$a o (spans swapped, the lint): $b"
  b=$(vh pace "$t/o" --skip-lint 2>&1); [ $? = 1 ] && case "$b" in *"re-align the take"*) ;; *) false ;; esac || a="$a o (spans swapped, pace's own guard): $b"
  b=$(vh pace "$t/n" --dry-run 2>&1); case "$b" in *"no audio/script.txt"*) ;; *) a="$a n (no script.txt): $b" ;; esac
  b=$(PYTHONPATH="$t" uv run -q --no-project --with numpy python - "$t" 2>&1 <<'PY'
import json, sys
from onsets import onsets
t = sys.argv[1]; bad = []
raw = {s["id"]: s for s in json.load(open(f"{t}/orig/timeline.zh.json", encoding="utf-8"))["segments"]}
tl = json.load(open(f"{t}/u/audio/timeline.zh.json", encoding="utf-8")); S = {s["id"]: s for s in tl["segments"]}
L = {l["id"]: l for l in tl["pace"]["lines"]}
ons, _, _ = onsets(f"{t}/u/audio/voiceover.zh.wav")
g0 = raw["b1"]["end"] + 0.02 + 0.4 - raw["a2"]["end"]  # a2's voice to b2's, in the take (b2's timeline start is the shared one)
g1 = S["b2"]["start"] - S["a2"]["end"]
if len(ons) != 32 or L["b1"].get("note") != "nothing heard" or abs(g1 - g0) > 0.05 or S["b1"]["end"] - S["b1"]["start"] < 0.1 - 1e-9 \
   or S["b1"]["start"] < S["a2"]["end"]:
    bad.append(f"u: {len(ons)} syllables (32), b1 {L['b1']} at {S['b1']['start']}–{S['b1']['end']}, a2→b2 {g1:.2f} s (the take's {g0:.2f})")
P = {l["id"]: l for l in json.load(open(f"{t}/t/audio/timeline.zh.json", encoding="utf-8"))["pace"]["lines"]}
true = {"t1": 8 / 1.55, "t2": 12 / 2.29}            # syllables over first onset → last end; the breath is not speech
for k, v in true.items():
    if abs(P[k]["pace"] / v - 1) > 0.06: bad.append(f"t: {k} measured {P[k]['pace']:.2f}, true {v:.2f}")
c = json.load(open(f"{t}/c/audio/timeline.zh.json", encoding="utf-8"))
if sum(len(s.get("words", [])) for s in c["segments"]) != 42: bad.append("c: the cached word times did not reach the paced timeline")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
  ) || a="$a $b"
  if [ -z "$a" ]; then ok "pace: a line with no audio keeps its stretch of the take, a quiet breath is not speech and short loud syllables are, cached word times are used and the .raw stays the original, swapped spans and a missing script.txt are said"
  else bad "pace on the other cases:$a"; fi
  mkdir "$t/k" && cp -R "$t/orig" "$t/k/audio"
  a=$(vh pace "$t/k" --dry-run --target 6 --extra b2=0.3 zh 2>&1); rc=$?
  case "$rc:$a" in 0:*"(--target 6)"*) printf '%s\n' "$a" | grep -q '^  b2 .*→ 0\.59 s' && ok "pace --target, --extra and the language after the flags" || bad "pace --extra b2=0.3: $a" ;;
    *) bad "pace --target 6 … zh: exit $rc: $a" ;; esac
  a=$(env -u GEMINI_API_KEY "$VH_BASH" "$ROOT/bin/vh" pace "$t/k" --align gemini 2>&1); rc=$?
  [ $rc = 1 ] && diff -r "$t/k/audio" "$t/orig" >/dev/null && ok "pace --align gemini without a key stops before writing" || bad "pace --align gemini without a key: exit $rc, $a"
  a=$(vh pace "$t/k" --ref b3x --dry-run 2>&1); rc=$?
  case "$rc:$a" in 1:*"--ref b3x"*) ok "pace --ref on a line without words is refused" ;; *) bad "pace --ref b3x: exit $rc: $a" ;; esac
  python3 -c "import json, sys; t = json.load(open(sys.argv[1])); t['grid'] = {'beats': 'm.json'}; json.dump(t, open(sys.argv[1], 'w'))" "$t/k/audio/timeline.zh.json"
  a=$(vh pace "$t/k" 2>&1); rc=$?
  case "$rc:$a" in 1:*"beat grid"*) ok "pace refuses a timeline on a beat grid" ;; *) bad "pace on a beat grid: exit $rc: $a" ;; esac
  rm -rf "$t"
}

kaggle_checks() {   # tools/kaggle: the setup probes, the ffmpeg wrapper, the render policy, the split plan (all against stubs)
  if [ "$(command -v node >/dev/null 2>&1 && node -v | sed 's/^v\([0-9]*\).*/\1/' || echo 0)" -lt 22 ]; then
    skip "kaggle" "needs Node ≥ 22 on PATH (what HyperFrames pins)"; return 0
  fi
  local out rc
  out=$(bash "$ROOT/tools/kaggle/test.sh" 2>&1); rc=$?
  printf '%s\n' "$out" | sed 's/^/  /'
  if [ $rc = 0 ]; then ok "kaggle: the setup probes, the tier wrapper, the render policy and the split plan (against stubs)"
  else bad "kaggle checks: $rc failed (above)"; fi
}

case "${1:-all}" in
  --smoke) smoke_checks; pace_checks; timeline_checks; decision_checks; gate_checks; desk_checks; textcheck_checks; film_checks; kaggle_checks ;;
  --committed)   # exactly what a push would send: HEAD in a clean temporary checkout, uncommitted changes left out
    w="$(mktemp -d "${TMPDIR:-/tmp}/vh-ci.XXXXXX")/head"; git worktree add -q --detach "$w" HEAD || exit 2
    (cd "$w" && tools/ci.sh); rc=$?; git worktree remove --force "$w"; rmdir "$(dirname "$w")"; exit $rc ;;
  all) static_checks; doc_checks; readpath_report; smoke_checks; pace_checks; timeline_checks; decision_checks; gate_checks; desk_checks; textcheck_checks; film_checks; kaggle_checks ;;
  *) echo "usage: tools/ci.sh [--smoke | --committed]"; exit 2 ;;
esac
[ -n "$skipped" ] && printf '\033[33m! skipped, so not checked: %s\033[0m\n' "$skipped"   # said again at the end: a pass is not a pass of these
[ $fails = 0 ] && ok "all checks passed" || printf '\033[31m%s check(s) failed\033[0m\n' "$fails"
exit $fails
