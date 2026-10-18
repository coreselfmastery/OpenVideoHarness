#!/usr/bin/env bash
# Rebuild this film's soundtrack from source: foley (tools/foley.py → audio/events.json + audio/sfx/), the score
# (audio/score.json → bin/vh music), the mix (bin/vh mix profile=promo, −14 LUFS), the audio QA with the mix report, and
# optionally the mux onto the picture.
#   showcase/00-promo-launch-film/tools/build_audio.sh                  → audio/mix.wav, audio/stems/, audio/qa.txt
#   showcase/00-promo-launch-film/tools/build_audio.sh --mux out.mp4    … and out.mp4 = media/final.mp4's picture + the mix
# Needs uv, ffmpeg and the repo's bin/vh. The same sources give the same bytes: the profile mix has no ffmpeg filter in
# its signal path and seeds its room.
set -euo pipefail
FILM=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VH="$FILM/../../bin/vh"
A="$FILM/audio"
DUR=20 FPS=30 FADE=0.4          # the film's length; the score ends on a held chord, faded over the last FADE s inside the mix
PROFILE=promo                   # playbook/04-audio.md, 混音: no narration, so the music is the anchor
MUSIC_DB=-5                     # the starting balance the SFX are judged from (the music level this film was built at)
TP=-1.65                        # the mix's true-peak ceiling; lowered when the AAC encode peaks over −1.5 dBTP (step 5)
out=""
while [ $# -gt 0 ]; do
  case $1 in
    --mux) out=${2:?--mux needs an output path}; shift ;;
    *) echo "usage: $0 [--mux out.mp4]" >&2; exit 2 ;;
  esac
  shift
done
calc() { python3 -c "print(round($1, 3))"; }
if [ -n "$out" ]; then   # the picture is read from media/final.mp4: writing over it while reading it would destroy it
  [ -f "$FILM/media/final.mp4" ] || { echo "no $FILM/media/final.mp4: the film is in the GitHub release \"media\"; run tools/fetch_media.sh 00- from the repo root" >&2; exit 2; }
  case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
  if [ -e "$out" ] && [ "$out" -ef "$FILM/media/final.mp4" ]; then   # the same file however it is spelled (case, symlink, link)
    echo "--mux: write to another file, then move it over media/final.mp4" >&2; exit 2
  fi
fi

# 1 foley: the custom sounds + the event list, and the 21 built-ins beside them (the mix places every event itself)
uv run -q --no-project --with numpy --with scipy python "$FILM/tools/foley.py"   # --no-project: run from 03's folder, uv would sync its ManimGX env
"$VH" sfx lib "$A/sfx" >/dev/null
# 2 music: render the score (it starts with the film: no offset)
"$VH" music "$A/score.json" "$A/music.wav" >/dev/null
# 3 mix: profile promo. The music's 3 s loudness is the anchor; each SFX event is classed (its "role" in events.json,
#   else its name) and moved half way to its class's range; one short room behind the SFX; cut to the film inside the
#   mix with a FADE s fade (so an SFX past the end fades too); one static gain to −14 LUFS, true peak ≤ TP.
mix() {
  "$VH" mix "$A/mix.wav" profile=$PROFILE music="$A/music.wav" events="$A/events.json" lib="$A/sfx" \
    dur=$DUR fade=$FADE music_db=$MUSIC_DB tp="$TP" stems="$A/stems" > "$A/mix.log" || { cat "$A/mix.log"; exit 1; }
  tail -1 "$A/mix.log"
}
# 4 QA on the mix (the gate): silence, dropouts, pumping (the score's own dips, known from the music stem, excluded),
#   clicks, every cue (score hits + SFX events) within one frame, and the mix report (qa mix)
qa() { # $1 = file, $2 = report
  local rc=0
  "$VH" qa "$1" "$A/music.beats.json" "$A/events.json" --fps $FPS --to "$(calc "$DUR - $FADE")" --stems "$A/stems" --out "$2" \
    > "$2.log" 2>&1 || rc=$?
  tail -1 "$2.log"; return $rc
}
mix
rc=0; qa "$A/mix.wav" "$A/qa.txt" || rc=$?
# 5 optional: the picture of media/final.mp4 (its video stream, copied) + the mix as AAC 192k. The encode raises the true
#   peak by an amount that depends on the content, so it is measured with the mixer's own 4× meter; over −1.5 dBTP the mix
#   is made again with its ceiling below its own true peak by the overshoot + 0.1 dB (at most 3 times), then the mp4 gets
#   the scan and the cue check too (its cue problems only warn, unless the whole encode is off: a mux offset). A mix that
#   fails its QA is not muxed.
if [ -n "$out" ] && [ "$rc" != 0 ]; then
  echo "  not muxed: the mix failed its QA (see $A/qa.txt)" >&2
elif [ -n "$out" ]; then
  k=0
  while :; do
    "$VH" mux "$FILM/media/final.mp4" "$A/mix.wav" "$out" >/dev/null
    etp=$(uv run -q --no-project --with numpy --with scipy python -c "import sys; sys.path.insert(0, sys.argv[1]); import mix; print(f'{mix.true_peak(mix.load(sys.argv[2])):.2f}')" \
          "$FILM/../../tools/audio" "$out")
    python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) <= -1.5 else 1)" "$etp" && break
    [ $k -lt 3 ] || { echo "the AAC encode still peaks at $etp dBTP after 3 new mixes (tp=$TP)" >&2; exit 1; }
    k=$((k + 1)); TP=$(python3 -c "import json, sys; m = json.load(open(sys.argv[3]))['tp']
print(f'{min(float(sys.argv[1]), m) - (float(sys.argv[2]) + 1.5) - 0.1:.2f}')" "$TP" "$etp" "$A/stems/meta.json")
    echo "  the AAC encode peaks at $etp dBTP: mixing again with tp=$TP"
    mix; qa "$A/mix.wav" "$A/qa.txt" || { echo "  not muxed: the new mix failed its QA (see $A/qa.txt)" >&2; rm -f "$out"; exit 1; }
  done
  echo "  $out: AAC true peak $etp dBTP (mix tp $TP)"
  qa "$out" "$A/qa_mp4.txt" || rc=$?
fi
exit "$rc"
