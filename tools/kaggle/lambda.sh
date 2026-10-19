#!/usr/bin/env bash
# lambda.sh — run a HyperFrames film on AWS Lambda: the distributed road of the speed table (the
# engine cuts the film into chunks, Lambda workers draw them in parallel, the worker's ffmpeg
# encodes, the joined MP4 lands in the stack's S3 bucket). This wrapper maps the repo's project
# conventions onto the engine's own lambda commands, decides the same things render.sh decides
# (fps, quality, the composition's own size), and refuses early — with the exact install hint —
# when the machine cannot run it, instead of failing deep inside a Step Functions call.
#
#   tools/kaggle/lambda.sh <project> [--tier draft|final] [--fps 24|30|60] [--width N --height N]
#          [--chunk-size N] [--max-parallel-chunks N] [--output-key K] [--variables JSON | --variables-file f]
#          [--stack-name S] [--region R] [--profile P] [--no-wait] [--json] [--dry-run]
#   tools/kaggle/lambda.sh deploy   [--stack-name S] [--region R] [--profile P] [--concurrency N] [--memory MB]
#          [--chrome-source sparticuz|chrome-headless-shell] [--skip-build]      # once per AWS account
#   tools/kaggle/lambda.sh policies [--out iam.json]    # the IAM policy the stack's role needs
#   tools/kaggle/lambda.sh progress <renderId | executionArn> [--stack-name S] [--region R] [--profile P]
#
# What it needs, checked before anything runs (on Kaggle none of this exists — that is fine, the
# same machine keeps render.sh and render-split.sh; this road is a machine with an AWS account):
#   the aws CLI with working credentials, the AWS SAM CLI, bun (the handler ZIP is built with it),
#   and @hyperframes/aws-lambda beside the CLI (the engine prints the npm line when it is missing).
#
# What it decides (the same policies as render.sh, on the engine's lambda surface):
#   width/height  the composition's own data-width/data-height — `lambda render` refuses to guess;
#                 --width/--height override (the engine supersamples with --output-resolution)
#   fps           the composition's own data-fps kept when it is 24 or 30; anything else (or no
#                 declaration) renders at 30 — the biggest speed lever, and lambda accepts only
#                 24 | 30 | 60. --fps overrides (60 keeps every frame of a 60 fps spec)
#   quality       --tier draft → --quality draft (the cheap review round), --tier final →
#                 --quality high (the master); no tier → the engine's own default (standard)
#   chunks        left to the engine (240 frames a chunk, 16 chunks in parallel by default);
#                 --chunk-size / --max-parallel-chunks pass straight through
#
# Examples:
#   tools/kaggle/lambda.sh deploy                                        # once
#   tools/kaggle/lambda.sh policies --out /tmp/iam.json                  # what the role may do
#   tools/kaggle/lambda.sh projects/26-launch --tier draft               # a review round on Lambda
#   tools/kaggle/lambda.sh projects/26-launch --tier final --no-wait     # fire and poll later
#   tools/kaggle/lambda.sh progress hf-render-abcd1234
#
# The honest numbers are in tools/kaggle/README.md: a Lambda worker has no GPU and no NVENC — the
# win is chunks in parallel (a strong vCPU × 16 in flight), not per-frame speed; the costs are the
# one-time deploy and the per-render upload of the project into S3.
set -euo pipefail
unset CDPATH
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

case "${1:-}" in
  -h|--help) sed -n '2,44p' "$0"; exit 0 ;;
  "") sed -n '2,44p' "$0" >&2; exit 1 ;;
esac
SUB=$1; shift

# ── prerequisites: named, checked, refused with the install hint — not failed at invoke time ────
need() { # need <binary> <the hint>
  command -v "$1" >/dev/null 2>&1 && return 0
  printf '\033[31m✗\033[0m no %s on PATH: %s\n' "$1" "$2" >&2
  exit 2
}
check_prereqs() {
  need aws "the AWS CLI (aws.amazon.com/cli); credentials via env vars, ~/.aws/credentials or SSO"
  need sam "the AWS SAM CLI (docs.aws.amazon.com/serverless-application-model)"
  need bun "bun (bun.sh) — hyperframes builds the Lambda handler ZIP with it"
  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    printf '\033[31m✗\033[0m the aws CLI has no working credentials (aws sts get-caller-identity fails)\n' >&2
    printf '       set AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY, pass --profile P, or log in with SSO\n' >&2
    exit 2
  fi
}

# ── the one parse: what this wrapper owns, the stack flags, everything else to the engine ───────
TIER=""; FPS_OPT=""; WIDTH=""; HEIGHT=""; OUT_KEY=""; POLICY_OUT=""; DRY=0; WAIT=1; JSON=0
stack=(); pass=()
while [ $# -gt 0 ]; do
  case "$1" in
    --tier) TIER=${2:?--tier needs draft or final}; shift ;;
    --tier=*) TIER=${1#*=} ;;
    --fps) FPS_OPT=${2:?--fps needs 24, 30 or 60}; shift ;;
    --fps=*) FPS_OPT=${1#*=} ;;
    --width) WIDTH=${2:?--width needs a number}; shift ;;
    --width=*) WIDTH=${1#*=} ;;
    --height) HEIGHT=${2:?--height needs a number}; shift ;;
    --height=*) HEIGHT=${1#*=} ;;
    --output-key) OUT_KEY=${2:?--output-key needs a key}; shift ;;
    --output-key=*) OUT_KEY=${1#*=} ;;
    --out) POLICY_OUT=${2:?--out needs a file}; shift ;;     # policies: where to save the IAM JSON
    --out=*) POLICY_OUT=${1#*=} ;;
    --no-wait) WAIT=0 ;;
    --wait) WAIT=1 ;;
    --json) JSON=1 ;;
    --dry-run) DRY=1 ;;
    --stack-name) stack+=(--stack-name "${2:?--stack-name needs a name}"); shift ;;
    --stack-name=*) stack+=(--stack-name="${1#*=}") ;;
    --region) stack+=(--region "${2:?--region needs a name}"); shift ;;
    --region=*) stack+=(--region="${1#*=}") ;;
    --profile) stack+=(--profile "${2:?--profile needs a name}"); shift ;;
    --profile=*) stack+=(--profile="${1#*=}") ;;
    -h|--help) sed -n '2,44p' "$0"; exit 0 ;;
    *) pass+=("$1") ;;
  esac
  shift
done
case "$TIER" in draft|final|"") ;; *) printf '\033[31m✗\033[0m --tier: draft or final, not "%s"\n' "$TIER" >&2; exit 1 ;; esac
for v in "$FPS_OPT" "$WIDTH" "$HEIGHT"; do
  if [ -z "$v" ]; then continue; fi
  case "$v" in *[!0-9]*|0) printf '\033[31m✗\033[0m --fps/--width/--height: whole numbers ≥ 1, not "%s"\n' "$v" >&2; exit 1 ;; esac
done
if [ -n "$FPS_OPT" ]; then
  case "$FPS_OPT" in 24|30|60) ;; *) printf '\033[31m✗\033[0m --fps: lambda accepts 24, 30 or 60, not "%s"\n' "$FPS_OPT" >&2; exit 1 ;; esac
fi
for a in ${pass[@]+"${pass[@]}"}; do
  case "$a" in --quality|-q|--quality=*) printf '\033[31m✗\033[0m --quality and --tier both name the quality: give one\n' >&2; exit 1 ;; esac
done

# ── the launcher: the project's own install first (as render.sh), else the repo's pinned one, else npx.
# OVH_TEST_HF_ROOT points the pinned-install lookup at a stub tree (tests).
HF_ROOT="${OVH_TEST_HF_ROOT:-$ROOT}"
hf() {   # run the engine (a normal call: its output can be redirected and the script goes on)
  if [ -n "${PROJ:-}" ] && [ -x "$PROJ/node_modules/.bin/hyperframes" ]; then
    "$PROJ/node_modules/.bin/hyperframes" "$@"
  elif [ -x "$HF_ROOT/styles/_swatch/node_modules/.bin/hyperframes" ]; then
    "$HF_ROOT/styles/_swatch/node_modules/.bin/hyperframes" "$@"
  else
    npx --yes "hyperframes@${HYPERFRAMES_VERSION:-0.8.82}" "$@"
  fi
}
hf_exec() {   # exec the engine (signals reach it directly, as render.sh's exec does). `exec hf …`
  if [ -n "${PROJ:-}" ] && [ -x "$PROJ/node_modules/.bin/hyperframes" ]; then    # cannot work: exec
    exec "$PROJ/node_modules/.bin/hyperframes" "$@"                             # replaces the process
  elif [ -x "$HF_ROOT/styles/_swatch/node_modules/.bin/hyperframes" ]; then     # image, and a function
    exec "$HF_ROOT/styles/_swatch/node_modules/.bin/hyperframes" "$@"           # is not an executable
  else
    exec npx --yes "hyperframes@${HYPERFRAMES_VERSION:-0.8.82}" "$@"
  fi
}

# ── the four verbs ──────────────────────────────────────────────────────────────────────────────
join_cmd() { # join_cmd <leading> <rest…>: one space-joined string (a printf %s that never shifts)
  local out="$1"; shift
  local a; for a in "$@"; do out="$out $a"; done
  printf '%s' "$out"
}
case "$SUB" in
  deploy)
    [ "$DRY" = 1 ] || check_prereqs
    printf '\033[36m→\033[0m deploy the lambda stack (CloudFormation through SAM; a few minutes)\n'
    printf '\033[36m→\033[0m command  : %s\n' "$(join_cmd "hyperframes lambda deploy" ${stack[@]+"${stack[@]}"} ${pass[@]+"${pass[@]}"})"
    [ "$DRY" = 1 ] && { printf '\033[36m→\033[0m dry run — nothing was invoked\n'; exit 0; }
    hf_exec lambda deploy ${stack[@]+"${stack[@]}"} ${pass[@]+"${pass[@]}"}
    ;;
  policies)
    [ "$DRY" = 1 ] || need aws "the AWS CLI (the policy is written for a role or a user in your account)"
    if [ -n "$POLICY_OUT" ]; then
      [ "$DRY" = 1 ] && { printf '\033[36m→\033[0m dry run — would write %s\n' "$POLICY_OUT"; exit 0; }
      hf lambda policies user ${stack[@]+"${stack[@]}"} > "$POLICY_OUT"
      printf '\033[32m✓\033[0m %s\n' "$POLICY_OUT"
    else
      [ "$DRY" = 1 ] && { printf '\033[36m→\033[0m dry run — would print the user policy\n'; exit 0; }
      hf lambda policies user ${stack[@]+"${stack[@]}"}
    fi
    exit 0   # this verb returns (no exec): without this the fall-through reads it as a project
    ;;
  progress)
    [ -n "${pass[0]:-}" ] || { printf '\033[31m✗\033[0m progress needs a render id or an execution ARN\n' >&2; exit 1; }
    [ "$DRY" = 1 ] || need aws "the AWS CLI (progress asks Step Functions)"
    hf_exec lambda progress ${pass[@]+"${pass[@]}"} ${stack[@]+"${stack[@]}"}
    ;;
  -*)
    printf '\033[31m✗\033[0m the project folder (or deploy / policies / progress) comes first: tools/kaggle/lambda.sh <project> [options]\n' >&2
    exit 1
    ;;
esac

# ── render: the project is the subcommand slot (a verb was consumed above; anything else is a path)
PROJ=$SUB
[ -f "$PROJ/index.html" ] || { printf '\033[31m✗\033[0m no index.html in %s (a HyperFrames project is a folder with one)\n' "$PROJ" >&2; exit 1; }
PROJ="$(cd "$PROJ" && pwd)"

# the film's own size and frame rate, from the root composition (what render.sh reads too)
meta=$(python3 - "$PROJ/index.html" <<'PY'
import json, re, sys
try: s = open(sys.argv[1], encoding="utf-8").read()
except OSError: sys.exit(0)
root = ""
for tag in re.findall(r'<[^>]*\bdata-composition-id\b[^>]*>', s):
    root = tag; break
def attr(name):
    m = re.search(r'\b' + name + r'="([\d.]+)"', root)
    return m.group(1) if m else ""
print(json.dumps({"fps": attr("data-fps"), "w": attr("data-width"), "h": attr("data-height")}))
PY
)
DFPS=$(printf '%s' "$meta" | python3 -c 'import json,sys; print(json.load(sys.stdin)["fps"])')
PW=$(printf '%s' "$meta" | python3 -c 'import json,sys; print(json.load(sys.stdin)["w"])')
PH=$(printf '%s' "$meta" | python3 -c 'import json,sys; print(json.load(sys.stdin)["h"])')

flags=()
[ -n "$WIDTH" ] || WIDTH=$PW
[ -n "$HEIGHT" ] || HEIGHT=$PH
[ -n "$WIDTH" ] && [ -n "$HEIGHT" ] || { printf '\033[31m✗\033[0m the composition declares no data-width/data-height and no --width/--height was given: lambda render refuses to guess\n' >&2; exit 1; }
flags+=(--width "$WIDTH" --height "$HEIGHT")

if [ -n "$FPS_OPT" ]; then
  flags+=(--fps "$FPS_OPT"); fps_note="fps $FPS_OPT (yours)"
elif [ "$DFPS" = 24 ] || [ "$DFPS" = 30 ]; then
  flags+=(--fps "$DFPS"); fps_note="fps $DFPS (the composition's own; kept, lambda takes 24 | 30 | 60)"
else
  flags+=(--fps 30)
  if [ -n "$DFPS" ]; then fps_note="fps 30 (the default here; the composition declares $DFPS — pass --fps 60 to keep every frame of it)"
  else fps_note="fps 30 (no data-fps; the engine's own default, made explicit)"; fi
fi

case "$TIER" in
  draft) flags+=(--quality draft) ;;
  final) flags+=(--quality high) ;;
  "")    : ;;   # the engine's own default (standard)
esac
[ -n "$OUT_KEY" ] && flags+=(--output-key "$OUT_KEY")
[ "$WAIT" = 1 ] && flags+=(--wait)
[ "$JSON" = 1 ] && flags+=(--json)

printf '\033[36m→\033[0m project  : %s (%sx%s%s)\n' "$PROJ" "$WIDTH" "$HEIGHT" "$(if [ -n "$DFPS" ]; then printf ', %s fps declared' "$DFPS"; fi)"
printf '\033[36m→\033[0m %s\n' "$fps_note"
[ -n "$TIER" ] && printf '\033[36m→\033[0m quality : %s (--tier %s)\n' "$([ "$TIER" = draft ] && echo draft || echo high)" "$TIER"
printf '\033[36m→\033[0m command  : %s\n' "$(join_cmd "hyperframes lambda render <project>" ${flags[@]+"${flags[@]}"} ${stack[@]+"${stack[@]}"} ${pass[@]+"${pass[@]}"})"

if [ "$DRY" = 1 ]; then
  printf '\033[36m→\033[0m dry run — nothing was invoked (deploy first: tools/kaggle/lambda.sh deploy)\n'
  exit 0
fi
check_prereqs
cd "$PROJ"
hf_exec lambda render . ${flags[@]+"${flags[@]}"} ${stack[@]+"${stack[@]}"} ${pass[@]+"${pass[@]}"}
