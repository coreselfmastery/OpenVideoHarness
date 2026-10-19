#!/usr/bin/env bash
# Install and prove the blender-mcp-ultra chain (engines/blender-mcp-ultra.md): the MCP gateway,
#   and — with --headless — a real Blender round trip: socket server in `blender -b`, token auth,
#   a scene query, an object create, a guard check (AST blocklist must refuse `import os`),
#   and a tiny Cycles render whose PNG we can verify. Everything it needs it installs or clones;
#   scratch lives in a temp dir; the Blender it starts, it stops.
# usage: tools/blender_mcp_setup.sh [--check] [--headless] [--blender PATH] [--addon-from PATH]
#   --check       install/verify the gateway only, and count the MCP tools it registers
#                 (this needs no Blender at all — the gateway builds its 248-tool registry locally)
#   --headless    the full round trip on top of --check: starts a throwaway `blender -b` socket
#                 server on port 9894 (not 9876, so a running session is never disturbed) and
#                 exercises it over the framed BMCP protocol, the same wire the gateway uses.
#   --blender     path to the blender binary (default: `command -v blender`; brew links it)
#   --addon-from  path to a carlosh7/blender-mcp checkout (default: shallow clone into
#                 ~/.cache/blender-mcp-setup/addon — the PyPI wheel does not ship the addon)
# Exit status: 0 chain verified (tool count, and with --headless: auth + guard + render)
#   · 1 a step failed, the message says which and where to look (engines/blender-mcp-ultra.md)
#   · 2 could not run (no python3, no install route for the gateway, no blender/addon for --headless).
# The GUI addon install (Edit > Preferences > Add-ons) is documented in the engine guide;
#   this script only needs the addon source on disk, it never registers the GUI addon.
set -uo pipefail
unset CDPATH   # an exported one could send a relative cd elsewhere (as in bin/vh)
cd "$(dirname "$0")/.." || exit 2

say()  { printf '%s\n' "$*"; }
ok()   { printf '[ok] %s\n' "$*"; }
bad()  { printf '[!!] %s\n' "$*"; }
info() { printf '[--] %s\n' "$*"; }

mode=check
BLENDER=""
ADDON_FROM=""
PERF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) mode=check ;;
    --headless) mode=headless ;;
    --blender) shift; BLENDER="${1:-}" ;;
    --addon-from) shift; ADDON_FROM="${1:-}" ;;
    --perf) shift; PERF="${1:-}" ;;
    *) bad "unknown flag: $1"; say "usage: tools/blender_mcp_setup.sh [--check] [--headless] [--blender PATH] [--addon-from PATH] [--perf draft]"; exit 2 ;;
  esac
  shift
done

TMP=$(mktemp -d "${TMPDIR:-/tmp}/bmcp-setup.XXXXXX") || exit 2
STARTED_PID=""
cleanup() {
  if [ -n "$STARTED_PID" ] && kill -0 "$STARTED_PID" 2>/dev/null; then
    kill "$STARTED_PID" 2>/dev/null
    wait "$STARTED_PID" 2>/dev/null
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

# --- 1. python3 (the probes and the headless server bootstrap are python) ----------
command -v python3 >/dev/null 2>&1 || { bad "python3 not found"; exit 2; }
PYVER_OK=$(python3 -c 'import sys; print(1 if sys.version_info >= (3, 9) else 0)')
[ "$PYVER_OK" = "1" ] || { bad "python3 is older than 3.9"; exit 2; }

# --- 2. the gateway (provides blender-mcp-server + blender-mcp) --------------------
GATEWAY="$(command -v blender-mcp-server || true)"
if [ -z "$GATEWAY" ] && [ -x "$HOME/.local/bin/blender-mcp-server" ]; then
  GATEWAY="$HOME/.local/bin/blender-mcp-server"
fi
if [ -z "$GATEWAY" ]; then
  info "gateway not found — installing blender-mcp-ultra (PyPI)"
  if command -v uv >/dev/null 2>&1; then
    uv tool install blender-mcp-ultra || { bad "uv tool install failed"; exit 2; }
  elif command -v pip3 >/dev/null 2>&1; then
    pip3 install --user blender-mcp-ultra || { bad "pip3 install --user failed"; exit 2; }
  else
    bad "no uv and no pip3: install one of them (engines/blender-mcp-ultra.md, install section)"
    exit 2
  fi
  GATEWAY="$(command -v blender-mcp-server || true)"
  [ -z "$GATEWAY" ] && [ -x "$HOME/.local/bin/blender-mcp-server" ] && GATEWAY="$HOME/.local/bin/blender-mcp-server"
  [ -n "$GATEWAY" ] || { bad "installed but blender-mcp-server is not on PATH; is ~/.local/bin on it?"; exit 2; }
fi
ok "gateway: $GATEWAY"
CLI="$(dirname "$GATEWAY")/blender-mcp"
if [ ! -x "$CLI" ] && command -v blender-mcp >/dev/null 2>&1; then CLI="$(command -v blender-mcp)"; fi
if [ -x "$CLI" ]; then
  "$CLI" --version 2>/dev/null | head -1 | sed 's/^/     /'
fi

# --- 3. doctor + tool count (no Blender needed: the registry is built locally) -----
if [ -x "$CLI" ]; then
  info "health check (blender-mcp --doctor):"
  "$CLI" --doctor 2>&1 | sed 's/^/     /' || true
fi

TOOLCOUNT=$(BMC_GATEWAY="$GATEWAY" python3 - "$TMP" <<'PY'
import json, os, subprocess, sys
tmp = sys.argv[1]
proc = subprocess.Popen([os.environ["BMC_GATEWAY"]], stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
_id = 0
def send(method, params=None, notify=False):
    global _id
    msg = {"jsonrpc": "2.0", "method": method}
    if params is not None: msg["params"] = params
    if not notify:
        _id += 1; msg["id"] = _id
    proc.stdin.write(json.dumps(msg) + "\n"); proc.stdin.flush()
    if notify: return None
    while True:
        line = proc.stdout.readline()
        if not line: raise RuntimeError("gateway closed stdout")
        d = json.loads(line)
        if d.get("id") == _id: return d["result"]
send("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                    "clientInfo": {"name": "setup", "version": "0"}})
send("notifications/initialized", notify=True)
tools, cursor = [], None
while True:
    r = send("tools/list", {"cursor": cursor} if cursor else {})
    tools += r["tools"]; cursor = r.get("nextCursor")
    if not cursor: break
proc.terminate()
print(len(tools))
PY
) || TOOLCOUNT=0
if [ "${TOOLCOUNT:-0}" -ge 200 ] 2>/dev/null; then
  ok "the gateway registers $TOOLCOUNT MCP tools with Blender closed (expected: 248)"
else
  bad "gateway registered only '${TOOLCOUNT:-0}' tools (expected ~248; gateway broken or too old)"
  say  "     look at: $GATEWAY — try reinstalling: uv tool install --force blender-mcp-ultra"
  exit 1
fi
say "     register it with Claude Code:  claude mcp add blender -- $GATEWAY"

if [ "$mode" = check ]; then
  say ""
  ok "CHECK PASSED — gateway installed and answering; run with --headless to prove the Blender round trip"
  exit 0
fi

# --- 4. blender binary --------------------------------------------------------------
if [ -n "$BLENDER" ]; then
  [ -x "$BLENDER" ] || { bad "--blender $BLENDER is not executable"; exit 2; }
elif command -v blender >/dev/null 2>&1; then
  BLENDER="$(command -v blender)"
else
  bad "blender not on PATH: pass --blender /path/to/blender (engines/blender.md pins 5.2 LTS)"
  exit 2
fi
ok "blender: $BLENDER"
BVER=$("$BLENDER" -b --factory-startup --python-expr "import bpy; print('BMCVER', bpy.app.version_string)" 2>/dev/null | sed -n 's/^BMCVER //p' | tail -1)
if [ -z "$BVER" ]; then
  bad "could not ask $BLENDER its version (it printed nothing to stdout)"
  exit 2
fi
BMAJ=$(printf '%s' "$BVER" | cut -d. -f1)
BMIN=$(printf '%s' "$BVER" | cut -d. -f2)
if [ "$BMAJ" -lt 4 ] || { [ "$BMAJ" = 4 ] && [ "$BMIN" -lt 2 ]; }; then
  bad "Blender $BVER is too old: blender-mcp-ultra needs 4.2+"
  exit 2
fi
ok "Blender $BVER (4.2+ required)"

# --- 5. addon source (the wheel does not ship addon/) ------------------------------
if [ -z "$ADDON_FROM" ]; then
  CACHE="$HOME/.cache/blender-mcp-setup/addon"
  if [ -f "$CACHE/addon/_axsock.py" ]; then
    ADDON_FROM="$CACHE"
    info "using cached addon source: $ADDON_FROM (rm -rf it to re-clone)"
  else
    info "shallow-cloning carlosh7/blender-mcp into $CACHE"
    command -v git >/dev/null 2>&1 || { bad "git not found: pass --addon-from PATH to a checkout"; exit 2; }
    rm -rf "$CACHE"
    mkdir -p "$(dirname "$CACHE")"
    git clone --depth 1 https://github.com/carlosh7/blender-mcp.git "$CACHE" >/dev/null 2>&1 || { bad "git clone failed"; exit 2; }
    ADDON_FROM="$CACHE"
  fi
fi
[ -f "$ADDON_FROM/addon/_axsock.py" ] || { bad "$ADDON_FROM/addon/_axsock.py not found — is that a carlosh7/blender-mcp checkout?"; exit 2; }
ok "addon source: $ADDON_FROM"

# --- 6. token (create it ourselves so the very first call authenticates; 0600) ------
TOKEN_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/blender-mcp/socket_token"
mkdir -p "$(dirname "$TOKEN_FILE")"
if [ -s "$TOKEN_FILE" ]; then
  ok "socket token already exists: $TOKEN_FILE (shared addon<->gateway)"
else
  python3 -c 'import secrets; print(secrets.token_hex(16))' > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  ok "socket token generated: $TOKEN_FILE (0600)"
fi

# --- 7. headless server on :9894 (not :9876 — never disturb a running session) -----
PORT=9894
if [ -n "$PERF" ]; then
  case "$PERF" in
    draft|final|final-cpu|fast|cpu|deterministic) ;;
    *) bad "--perf is draft | final | final-cpu, not $PERF"; exit 2 ;;
  esac
  PERF_BLOCK="import bpy
from tools.blender_perf import apply_profile
dev, _rows = apply_profile(bpy.context.scene, '$PERF')
print('[perf] exploration scene defaults: $PERF profile ->', dev, flush=True)
"
  ok "perf profile $PERF will be applied to the session scene before the server starts"
else
  PERF_BLOCK=""
fi
cat > "$TMP/server.py" <<PY
import sys
sys.path.insert(0, "$ADDON_FROM/addon")
sys.path.insert(0, "$PWD")
$PERF_BLOCK
import _axsock
_axsock.serve_forever(host="127.0.0.1", port=$PORT)
PY
"$BLENDER" -b --factory-startup --python "$TMP/server.py" > "$TMP/blender.log" 2>&1 < /dev/null &
STARTED_PID=$!
ok "headless socket server starting (pid $STARTED_PID, port $PORT)"

# --- 8. the round trip (framed BMCP, the gateway's own wire protocol) --------------
RESULT=$(BMC_PORT="$PORT" BMC_TOKEN_FILE="$TOKEN_FILE" BMC_OUT="$TMP" python3 - <<'PY'
import json, os, socket, struct, sys, time

port = int(os.environ["BMC_PORT"])
out_dir = os.environ["BMC_OUT"]

# wait for the port (blender takes a few seconds to boot)
deadline = time.time() + 60
while True:
    try:
        probe = socket.create_connection(("127.0.0.1", port), timeout=2)
        probe.close()
        break
    except OSError:
        if time.time() > deadline:
            print(json.dumps({"fatal": "port %d never opened (see blender.log)" % port}))
            sys.exit(0)
        time.sleep(0.5)

def call(command, args=None, token=None):
    s = socket.create_connection(("127.0.0.1", port), timeout=120)
    try:
        payload = json.dumps({"command": command, "args": args or {}, **({"token": token} if token else {})}).encode()
        s.sendall(b"BMCP" + struct.pack(">I", len(payload)) + payload)
        buf = b""
        while True:
            chunk = s.recv(65536)
            if not chunk:
                return {"fatal": "connection closed mid-answer"}
            buf += chunk
            if buf[:4] == b"BMCP":
                if len(buf) < 8:
                    continue
                (ln,) = struct.unpack(">I", buf[4:8])
                if len(buf) >= 8 + ln:
                    return json.loads(buf[8:8 + ln].decode())
            else:
                try:
                    return json.loads(buf.decode())
                except json.JSONDecodeError:
                    continue
    finally:
        s.close()

token = open(os.environ["BMC_TOKEN_FILE"]).read().strip()
res = {}

r = call("get_scene_info", token=token)
rr = r.get("result", r)   # the addon wraps answers as {"status": "success", "result": {...}}
res["scene_info"] = "ok" if "objects" in rr else "bad: " + json.dumps(r)[:120]

r = call("tool", {"tool_name": "object.create",
                  "params": {"type": "cube", "name": "BmcpSetupCube", "location": [0, 0, 1]}}, token=token)
res["object_create"] = "ok" if r.get("result", {}).get("success") or r.get("success") else "bad: " + json.dumps(r)[:120]

call("tool", {"tool_name": "render.set_engine", "params": {"engine": "CYCLES"}}, token=token)
call("tool", {"tool_name": "scene.render_settings",
              "params": {"resolution_x": 160, "resolution_y": 90, "samples": 8, "frame": 1}}, token=token)
png = os.path.join(out_dir, "smoke.png")
r = call("tool", {"tool_name": "render.render", "params": {"filepath": png}}, token=token)
res["render"] = "ok" if (os.path.isfile(png) and open(png, "rb").read(8) == b"\x89PNG\r\n\x1a\n") else "bad: " + json.dumps(r)[:120]

r = call("execute_code", {"code": "import os\nos.system('id')"}, token=token)
res["guard_blocks_os"] = "ok" if r.get("status") == "error" or "blocklist" in json.dumps(r).lower() or "bloqueado" in json.dumps(r).lower() else "bad: NOT BLOCKED: " + json.dumps(r)[:120]

r = call("get_scene_info")
res["auth_rejects_no_token"] = "ok" if r.get("status") == "error" and "unauthorized" in r.get("message", "") else "bad: " + json.dumps(r)[:120]

print(json.dumps(res))
PY
) || RESULT="{}"

FAILED=0
get_json_field() { printf '%s' "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$1', ''))" 2>/dev/null || true; }
for k in scene_info object_create render guard_blocks_os auth_rejects_no_token; do
  v=$(get_json_field "$k")
  if [ "$v" = ok ]; then
    ok "$k"
  else
    bad "$k -> ${v:-no answer}"
    FAILED=1
  fi
done
if printf '%s' "$RESULT" | grep -q '"fatal"'; then
  bad "$(printf '%s' "$RESULT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("fatal",""))' 2>/dev/null || true)"
  say "     blender log: $TMP/blender.log (kept? no — see rerun with BMCP_KEEP=1)"
  [ -n "${BMCP_KEEP:-}" ] && cp "$TMP/blender.log" ./blender-mcp-setup.blender.log
  exit 1
fi

say ""
if [ "$FAILED" = 0 ]; then
  ok "HEADLESS ROUND TRIP PASSED — gateway + addon + token auth + AST guard + Cycles render all verified"
  say  "     the exploration-phase workflow and the rules that still apply: engines/blender-mcp-ultra.md"
  exit 0
fi
bad "some steps failed — details above; engine guide: engines/blender-mcp-ultra.md (troubleshooting: versions, addon layout, port 9894)"
exit 1
