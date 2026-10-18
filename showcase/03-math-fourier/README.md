# Showcase 03: Building a square wave from sine waves (math / ManimGX)

https://github.com/user-attachments/assets/c2368f76-b157-4a48-9945-8048a515efd4

**Full video:** [03-math-explainer.mp4](https://github.com/ZLHad/OpenVideoHarness/releases/download/media/03-math-explainer.mp4) (GitHub release; `tools/fetch_media.sh` puts it at `media/final.mp4`) · **Contact sheet:** [media/sheet.png](media/sheet.png)

| | |
|---|---|
| Type / route | `math` → `video-types/01-math-science-explainer.md`, engine ManimGX (built on Manim CE 2026-09-28; migrated to ManimGX 2026-10-18, see NOTES.md) |
| Output | 1920x1080, 30 fps, **25.0 s** (750 frames), h264 in limited-range BT.709 + a stereo AAC soundtrack (English narration, a piano score and the partial sums made audible, mix profile `explainer`, added after the picture was finished: [Soundtrack](#soundtrack)), a soft en subtitle track, 2.9 MB |
| Engine | Now **ManimGX 0.1.1** (Python 3.14.8, uv; Rust/wgpu core, Typst math, no LaTeX). Original build: Manim CE v0.21.0, Python 3.12.2, Cairo renderer, MacTeX |
| Render time | CE (M3 Max): final 24.3 s, draft ~22 s. ManimGX (2-core CPU, lavapipe): final 1080p30 **40.3 s**, draft 480p15 **10.9 s**; on a GPU (e.g. Kaggle T4) faster again |
| Review iterations | 4 renders (v1 → v2 → v3 → **v4 = final**). Each had a contact sheet, strips of the key moves, a horn crop and a bbox audit; one fresh-context reviewer pass came between v3 and v4. Critiques are in [NOTES.md](NOTES.md) |
| Agent wall time | ~20 min to the first delivered cut (v3), plus the reviewer-fix round |

**Reviewer pass:** a fresh-context reviewer subagent (playbook/02 layer 5) judged v3 from its frames alone and said "don't ship as-is". v4 applies its four fixes:
1. The zoom is now strictly sequential: the parent shrinks, then the magnifier box fades in, then the panel grows. The panel sits under the parent, so it no longer blacks out the corner being magnified.
2. The final hold goes from 1.5 s to 2.5 s, so the video is 25.0 s.
3. Grey `1` / `−1` ticks on the parent graph put the jump of 2 on screen, so "≈ 9% of the jump" can be checked.
4. `N = 7` gets its own beat before the sweep, which now runs 15.5–16.7 s.

Fixing (1) exposed a real engine bug in my code: `always_redraw` loses `z_index` (see friction #1).

## The request this was built from

> Topic: "Building a square wave from sine waves": Fourier series partial sums of a square wave, showing the 1st, 3rd, 5th… harmonics adding up (epicycles or stacked sines are both fine), ending with the Gibbs overshoot (~9%) near the jump as a small payoff.
> 18–25 seconds, 1920x1080, 30 fps, SILENT: minimal on-screen text; one LaTeX equation (the series) introduced whole, dimmed, then highlighted term by term; short labels.
> Follow the type doc: black background, one colour per math entity held for the whole video, geometry before algebra, holds after each move, no bounce/glow/particles, place objects via a grid helper, print bounding boxes to check overlaps. Verify the maths (coefficients 4/(πn) for odd n; Gibbs ≈ 8.95% of the jump) and log it in NOTES.md.
> Review loop: render -ql while iterating, contact sheets via ffmpeg (bin/vh sheet), check against TASTE_CHECKLIST.md, log critiques in NOTES.md; final render at 1080p. Approval gates skipped by the user; BRIEF/STORYBOARD/STYLE still written before coding.

## What's in the video
- **Opening:** a grey square wave appears. One blue sine, `(4/π) sin x`, already roughly follows it, then turns yellow: it becomes the running sum.
- **Equation:** the series appears whole, dims to 30%, then lights up term by term. Each new odd harmonic is drawn in blue on the axis (1/n as tall, n× as fast), stacked onto the yellow sum and absorbed. Its term in the equation turns from blue to yellow at the same moment.
- **Many terms:** `⋯` lights, `N = 7` appears, and N runs to 25.
- **Zoom:** the parent graph shrinks left and a magnifier box appears on the jump at x = 2π. A zoom panel grows out of the box.
- **Gibbs payoff:** a red line marks the horn peak at 1.179, with the plateau at 1 and ticks at ±1 on the parent. N runs to 99; the horn gets thinner but not shorter. A brace labels it "≈ 9% of the jump".

Colour contract (STYLE.md): target grey, harmonic-being-added blue `#58C4DD`, running sum yellow `#FFFF00`, overshoot red `#FC6255`.

## Soundtrack

The picture was made and finished silent, as briefed; English narration, a piano score and a sonification of the partial sums were fitted to it afterwards (2026-10-01). The picture's timing is fixed and the audio fits it; the picture still carries the maths, and the voice says where to look.

- **Narration** (`audio/script.txt`, eight lines written from the storyboard's reads): "Take a square wave. / One sine comes close. / Add odd sines, each one smaller. / Sine 3x: a third as tall. / 5x, 7x, and the corners sharpen. / It squares up, except at the jump. / More terms only make the overshoot thinner. / About nine percent of the jump."
  - The facts are the ones on screen and in `tools/verify_math.py`: odd harmonics sin(nx)/n, and 8.95 % said as "about nine percent". 1.179 is left to the screen.
  - Voice: Gemini TTS, voice Iapetus, directed as `Clear, curious math explainer; brisk conversational pace, no dramatic pauses`, plus a short direction per line. It was chosen from three candidates on the same lines, by speech-recognition similarity and pitch range. A "calm, thinking aloud" direction had made it far too slow.
  - Timing: each line starts on a hand-made grid (`audio/vo_grid.json`, from the reads and the play() timings) and ends before the next read. For example, "except at the jump" lands on the spikes and the zoom, and "…thinner" lands inside the N 25 → 99 sweep.
  - The narration is AI-synthesized (Gemini TTS, with an inaudible SynthID watermark). The lossless master `audio/voiceover.en.flac` is committed because the takes cannot be regenerated byte for byte.
- **Score** (`audio/score.json`, `bin/vh music` with instrument parts): felt piano over soft strings and a low D drone, no drums, D major at 75 BPM, starting 0.3 s into the film (the equation's entrance at 4.3 s is a bar head).
  - The piano answers the harmonics. D4's partials spell D, A, F# and a flat C, so the piano plays A on the 3rd harmonic's merge (10.2 s), F# on the 5th (12.5 s) and C on the 7th (14.4 s): a D7 colour that leans into G for the "N → 25" sweep.
  - It hushes to Dsus2 for the zoom, sits on an unresolved Bm7 under the horn, and lands a D major chord with the brace (21.8 s).
- **Sonification** (`tools/foley.py`, tagged `"layer": "sonification"`): a tone on D4 whose waveform is the curve on screen.
  - The grey square wave sounds as it draws (a hollow, clarinet-like tone), then the pure sine.
  - Each new harmonic sounds alone while it draws (n·f0, quieter, as it is 1/n as tall). The sum S3 / S5 / S7 swells as each one merges.
  - A sweep uses the scene's own term weights for N 7 → 25.
  - Plus a soft `air` as the zoom panel grows, and a bell on "≈ 9% of the jump".
  - The maintainer heard a version with and one without the tones, and chose this one, with the music a bit lower (2026-10-01).
- **Mix** (`bin/vh mix … profile=explainer`, see playbook/04-audio.md 混音): the narration is the programme. Its eight lines are levelled toward the median line (raw span 5.5 LU → 2.2 LU); the music is ridden under each line to 13 LU below the voice, with a 1–4 kHz carve only as deep as the words need, and comes back half way in the pauses. The tones are the signal class: 8.4 LU under the voice on median, about where they were in the first candidate (9.0), so with the music lower they now sit above it. The whoosh is a detail and the bell a hero; the SFX share one short room and get a presence carve where they cover words. One static gain to −14.0 LUFS; true peak −1.65 dBTP in the WAV, −1.51 dBTP after the AAC encode.
- **"The music a bit lower"**: under the lines the music went from 8.3 LU below the voice in the first candidate (median; the worst line 4.9) to 13.1 (the worst 13.0), and in the pauses from 0.2–6 LU to 7–13 LU below the narration level. It is not buried: the low D drone stays 13 dB over the voice below 90 Hz, the piano and strings sit 10–15 dB under the voice from 90 Hz to 2.8 kHz, and every line is inside the profile's 11–18 LU range.
- **QA** (`bin/vh qa` on the WAV, the gate; `--stems` adds the mix report):
  - no digital silence (only 0–0.23 s, before the first sound), dropouts or pumping. The three click warnings are consonants in the narration take. There are no onset cues: every sound here swells, so each sits at or below −18 dB, where the cue check skips it;
  - mix report: targets met. VMR 13.0–13.9 LU on seven lines and 16.9 on the first, where the music has barely started (median 13.1; profile range 11–18). The masking check reads the narration's word timings: 3 of 45 words (7 %) are under the 6 dB presence floor, inside the 10 % limit, so it only warns ("and", "the" at 13.3–13.4 s, under S5 and the 7th harmonic, and "the" at 17.3 s, under the music). Tones median −8.4 LU re the voice (range −12…−4). Warnings: the music rises 4.6–6.5 LU in three pauses (two are the score's designed swells into D∞ and the payoff); S3 and S5 come within 6 dB of the voice at 1–4 kHz;
  - the mp4 passes the scan. `bin/vh check` flags only the black background at 0–2.7 s and 17.6–18.3 s (thin lines on 3b1b black, flagged the same in the silent original); no freeze, no silence.
- **Subtitles**: the soft track `audio/captions.en.srt` (tagged eng), one cue per line.
- **Word timings** (2026-10-01): Gemini's transcription of the existing takes (tts.py's own alignment, gemini-3.5-transcribe, no re-synthesis) put every line's words and a speech-recognition check into the timeline. `bin/vh captions showcase/03-math-fourier en` adds the words to `audio/captions.json` and writes `audio/captions.en.lines.srt` (one cue per wrapped line). `audio/captions.en.srt` did not change and the mix is byte-identical, so `media/final.mp4` is unchanged. On the first pass 6 of the 8 lines are under 0.9 similarity, mostly "sine" heard as "sign" and "nine percent" as "9%"; after the re-check with a custom vocabulary no line stays flagged. NOTES.md lists the spots to listen to.
- The maintainer listened to the first candidate mixes on 2026-10-01; this profile mix has not been listened to yet. NOTES.md lists what to listen for.

Rebuild (from the repo root; needs uv and ffmpeg):
```bash
showcase/03-math-fourier/tools/build_audio.sh                   # → audio/mix.wav, audio/stems/, audio/qa.txt
tools/fetch_media.sh 03-                                        # the film from the GitHub release "media" (--mux reads its picture)
showcase/03-math-fourier/tools/build_audio.sh --mux out.mp4     # … plus out.mp4 = the picture of media/final.mp4 + that mix + en subtitles
```
The script decodes the narration master and cuts each line from it (`audio/vo/en/`), then runs `tools/foley.py`, `bin/vh sfx lib`, `bin/vh music` (delayed 0.3 s, with its beat map shifted), `bin/vh mix … profile=explainer`, `bin/vh qa` and, with `--mux`, `bin/vh mux` (the picture is copied, not re-encoded, and the moov goes first so a browser can start playing at once), then measures the true peak of the AAC encode and mixes again with a lower ceiling if it is over −1.5 dBTP. Every run gives the same bytes. Committed: `audio/script.txt`, `audio/vo_grid.json`, `audio/voiceover.en.flac`, `audio/timeline*.json`, `audio/captions.*`, `audio/score.json`, `audio/events.json`, `audio/music.beats.json`, `tools/foley.py`, `tools/build_audio.sh`. The WAVs, stems and reports are regenerated and ignored (`audio/.gitignore`).

**Colour.** Manim CE's output was `yuv420p` with no colour tags and BT.601 limited-range pixels, which Chromium reads as BT.709: the running sum's `#FFFF00` showed as (255, 240, 0). `media/final.mp4` was re-encoded once, with the soundtrack, to limited-range BT.709 with all four colour tags: x264 `slow`, CRF 17, the same 750 frames at 30 fps (25.000 s; the old file's timestamps drifted to 24.999 s). The yellow now decodes as (254, 254, 1); see NOTES.md. ManimGX (2026-10-18) already writes limited-range tagged pixels (matrix smpte170m / transfer sRGB / primaries bt709), so the delivery re-encode to BT.709 that the soundtrack mix does anyway is the only remaining step.

## Files
- `BRIEF.md`, `STYLE.md` (entity-colour map, 6×6 grid), `STORYBOARD.md` (shots, reads with timings), `NOTES.md` (maths verification + review log incl. the reviewer pass), `LESSONS.md`
- `scenes/fourier.py` (scene; `live()` = z-index-preserving `always_redraw`), `scenes/style.py` (palette, grid helper, bbox audit, polyline/clip helpers), `tools/verify_math.py`, `pyproject.toml`
- Soundtrack: `audio/` (script, line grid, narration master, timelines, captions, score, events, beat map), `tools/foley.py`, `tools/build_audio.sh` (see [Soundtrack](#soundtrack))

Reproduce (from a project folder created by `bin/vh new math <slug>` with these files copied in; ManimGX since 2026-10-18):
```bash
uv sync            # or: uv init --bare --python 3.14 && uv add manimgx
uv run --with scipy python tools/verify_math.py                        # scipy on demand (uv --with); numpy ships with the env
uv run manimgx render -r 854x480 --fps 15 scenes/fourier.py FourierSquareWave   # draft (10.9 s wall on 2-core CPU)
uv run manimgx inspect scenes/fourier.py FourierSquareWave                      # storyboard + layout checks (exit 1 on problems)
uv run manimgx render -r 1920x1080 --fps 30 scenes/fourier.py FourierSquareWave # final; writes scenes/FourierSquareWave.mp4
# ManimGX writes limited-range tagged pixels (matrix smpte170m); the delivery re-encode to BT.709 happens when the soundtrack is mixed (below)
```
Then, in this repo: copy `picture.mp4` over `showcase/03-math-fourier/media/final.mp4`, put the soundtrack on it with `showcase/03-math-fourier/tools/build_audio.sh --mux /tmp/final.mp4` (it refuses to write over the file it reads the picture from), and move `/tmp/final.mp4` over `media/final.mp4`.

## What the harness docs helped with
- **Routing and the type doc** (`CLAUDE.md` route table → `video-types/01`). The whole visual grammar came from here: one colour per entity, the equation shown whole, dimmed, then lit term by term, and the parent graph kept visible at 30–40% while zoomed. The "one colour per entity" rule forced the key design choice: blue means "being added", yellow means "already in the sum", and no rainbow harmonics.
- **3b1b Gotchas plus `equations.md` / `equation-derivations.md`.** The multi-string `MathTex` split and the dim-and-reveal pattern worked on the first try. `animation-design-thinking.md`'s tempo-variation rule justified compressing the repeated add-a-harmonic move.
- **Code2Video anchor grid** (`prompts/stage3.py`, `base_class.py`). It turns placement into choosing cells: `A1–A5` equation, `A6` counter, `C1–E3` parent, `B4–F6` zoom panel.
- **`playbook/01-pipeline.md` reads.** Writing reads with start and end times made the 24 s budget explicit before any code; the first render came in at 23.93 s.
- **`playbook/02-verification.md` plus `bin/vh sheet/gif/check`.** Strips caught the colour blend in the merge. The fresh-context reviewer (layer 5) caught what I had normalised: the zoom blackout, the unshown jump of 2 behind "9%", and the short final hold. Layer 5 earned its place.

## Friction points (most important first)
Status notes: several of these were fixed in the harness while this showcase was being made. They are marked **[fixed during run]** with where the fix landed.

1. **NEW: `always_redraw` silently drops `z_index`.** `Mobject.become()` copies points and style, not `z_index`, so a live mobject keeps the z of its first `func()` result forever; an empty placeholder means z = 0. Here it caused three bugs:
   - the reviewer's zoom blackout (the panel's black fill drew over the parent by add order);
   - the grey target drawn above the yellow sum for the whole of v1–v3;
   - a z-order fix of mine for the merge that did nothing.

   It isn't in the 3b1b Gotchas, `troubleshooting.md` or the type doc's 自查重点. Fix: `live(func)` in `scenes/fourier.py`.
2. **[fixed during run] No path for silent videos.** `CLAUDE.md` hard rule 2, `video-types/01` step 5 and its prompt block all assumed narration, and `bin/vh new` pasted the voiceover line. CLAUDE.md rule 2, the type doc and the prompt block now have a silent branch.
3. **[fixed during run] `engines/README.md` › Manim CE.** `uv init` created a nested `.git`, `main.py`, `README.md` and `.python-version`. It also installed an unneeded `manim-voiceover`, and nothing mentioned the pydub `SyntaxWarning` spam. It now says `uv init --bare`, makes voiceover optional, and sets `PYTHONWARNINGS`.
4. **[fixed during run] fps mismatch.** The prompt block said 30 fps, but the final command was `-qh`/`-qk`, which is 60 fps. `-qh --fps 30` is now documented in engines/README and the prompt block.
5. **[fixed during run] The `play(rate_func=…)` override gotcha** is now in `video-types/01` 自查重点.
6. **Grid wording still assumes a lecture column.** `video-types/01` 工作流 step 4 still says "在右侧动画区定义 6×6 锚点网格", but a silent, full-frame explainer has no lecture column. The doc also doesn't say how grid placement coexists with data-coordinate objects (curves, braces, magnifier boxes). `engines/README.md` now points to this showcase's `scenes/style.py` for a grid and bbox-audit implementation, which covers the practical side.
7. **Checklist and template conflicts, partly fixed.** `TASTE_CHECKLIST.md` #10 now exempts the type doc's pure black. `templates/BRIEF.md` still says "no pure #000/#fff unless chosen". #6's "84 px / 44 px" is still undefined for Manim `font_size` and math: em size, cap height, or bbox?
8. **[fixed during run] `bin/vh check` on dark explainers.** It now prints a caveat. With the new sequenced zoom it also flags 17.6–18.3 s as black (only the small parent is on screen), which is expected.
9. **[fixed during run] `bin/vh sheet` overwrote its output.** It used to write a fixed `check/sheet.png`; it now takes `[out]` and defaults to a timestamped name. Note for scripts: anything that copies `check/sheet.png` afterwards now picks up a stale file (this happened to me once).
10. **[fixed during run] Pacing for short cuts.** `video-types/01` 审美要点 now has a line for videos under 30 s.
11. **Rule collisions inside the 3b1b references, no stated precedence:**
    - `visual-design-principles.md` #17 says Menlo for all `Text()`; the type doc says CMU Serif. I avoided `Text()` entirely.
    - #16 reserves a bottom-20% caption zone.
    - `troubleshooting.md` says "always FadeOut titles"; the type doc says "dim, never delete".
12. **[fixed during run] Determinism recipe for Manim.** `playbook/02` now has `--format png -n A,B` plus a hash comparison. Re-run here after the `live()` change: 21/21 frames identical.

## Known imperfections
- Row A is empty for the first 4.3 s, until the equation arrives. It's a density ramp; moving the graph would add a move with no meaning.
- At N = 99 the brace's lower tip touches the tiny ringing at the panel's right edge. The brace ends at y = 1 by design.
