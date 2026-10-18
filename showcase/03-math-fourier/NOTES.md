# NOTES

## Facts checked (tools/verify_math.py, scipy quad + sici)
- [x] Square wave f(x) = sign(sin x), period 2π, values ±1, jump height 2. Fourier sine coefficients b_n = (1/π)∫_{-π}^{π} f(x) sin(nx) dx: numeric 1.273240, 0, 0.424413, 0, 0.254648, 0, 0.181891, 0, 0.141471 for n = 1..9 = **4/(πn) for odd n, 0 for even n**. Verified.
- [x] Series on screen: f(x) = (4/π)(sin x + sin3x/3 + sin5x/5 + sin7x/7 + ⋯). Matches b_n.
- [x] Gibbs limit: peak of S_N → (2/π)·Si(π) = **1.178980**; overshoot 0.178980 = **8.949% of the jump (2)**. On screen: "1.179" and "≈ 9% of the jump". Verified.
- [x] Peak of S_N at N = 1, 3, 5, 7, 9, 25, 49, 99, 199: 1.27324, 1.20042, 1.18836, 1.18423, 1.18233, 1.17947, 1.17911, 1.17901, 1.17899; located at x = π/(N+1). So on screen the horn at N = 25 and N = 99 both touch the 1.179 line to within 0.0005 (< 1 px in the zoom panel: 1 y-unit = 1050 px there). Horn width shrinks ∝ 1/N. Verified.
- [x] Counter N = highest odd harmonic currently in the yellow sum (2·ceil(w) − 1 for the continuous term count w). During the sweeps a fractional last term fades in; N shows the term being faded in.

## Creative decisions
- 2026-09-28 Stacked sines, not epicycles — reason: 24 s, silent; one graph lets the equation and the curve share colours term by term; epicycles need a second representation to explain.
- 2026-09-28 Colours by entity, not by harmonic: every harmonic is blue while being added and yellow once absorbed (avoids the banned rainbow; blue→yellow *is* the "adding" read).
- 2026-09-28 Pure black bg although `templates/TASTE_CHECKLIST.md` #10 flags pure black: the type doc (`video-types/01`) prescribes #000000 and takes precedence.
- 2026-09-28 Grid spans the whole safe box (no lecture column as in Code2Video's right-side grid). Curves/braces/magnifier are placed in *data* coordinates of grid-placed plot rects; only text and plot rects go through `GRID`.
- 2026-09-28 Zoom = inset panel (parent shrinks to C1–E3 and stays, magnifier box + link lines), not a camera zoom — follows the type doc's "parent stays visible, 30–40% of frame" and avoids Cairo stroke widths scaling with camera zoom.
- 2026-09-28 D5/D7 run faster than the type doc's "play 1–3 s + 0.5–2 s hold": third and fourth repetition of the same move, per 3b1b `animation-design-thinking.md` "tempo variation". Every hold ≥ 0.2 s.
- 2026-09-28 Equation font 46 (glyph x-height ≈ 25 px, bbox 133 px with fractions). TASTE #6 "≥ 44 px auxiliary" is interpreted as cap/fraction line height; math needs its own rule (see showcase README friction list).
- 2026-10-01 **Soundtrack fitted to the finished picture** (README › Soundtrack): English narration + piano score + a sonification of the partial sums.
  - **The narration is AI-synthesized (Gemini TTS, voice Iapetus, with a SynthID watermark)**: disclose it where the film is published.
  - Lines are written from the storyboard's reads, and the facts are copied from this file: sin(nx)/n, odd n only, 8.95 % said as "about nine percent". The Gibbs value 1.179 is left to the screen.
  - Voice: Iapetus beat Sadaltager (it misheard "One" as "And", 0.86) and a library tutor voice (flatter pitch range, 10.9 vs 14.2 semitones). The first direction, "calm and curious, thinking aloud", gave 1.5 words/s with long pauses ("The recipe: … odd … sines" took 6.3 s). "Brisk conversational pace, no dramatic pauses" fixed it, and the lines were cut down to fit the windows.
  - Placement: a line grid (`audio/vo_grid.json`) with `bin/vh tts … --beats`. The `over` line was synthesized on 19.15 s and then moved to 19.0 s, the same take rebuilt sample by sample, so it ends by 21.8 s when the brace appears. No line needed speeding up.
  - Alignment: the Gemini transcribe quota had run out on 09-30, so a local whisper-large-v3-turbo check, scored with tts.py's own aligner, stood in: 1.00 for square, more, except and over; sine, recipe and third heard as "sign" (a homophone), and gibbs as "9%" (1.00 by sound). The Gemini word timings came on 10-01 (next bullet).
  - 2026-10-01 **Word timings**: the Gemini alignment (gemini-3.5-transcribe) ran on the existing takes, with no re-synthesis. A one-off script, align_existing.py (not in the repo), calls tts.py's own transcribe → align_lines → asr_record and writes the same fields `--align gemini` would; `--min-sim 0.9`, with "sine, sines, 3x, 5x, 7x" added to the re-check vocabulary. Every line's `words` and `asr` are in `audio/timeline.en.json` (and its copy `timeline.json`). Tries at 08:21 and 12:12 got one call each through, on 02's first line, before the daily quota refused them; it ran at 14:38 with a new API key. When the quota resets was not settled: the 429 counted down to 08:00 here, while Google's docs say the daily quota resets at midnight Pacific (15:00 here in summer time), so the morning's note that it "was used up again within 21 minutes of its reset" may be wrong.
  - Similarity per line, first pass → re-check with the vocabulary (only lines under 0.9 are re-checked): square 0.75 → 1.00 (heard "took a square wave"), sine 0.50 → 1.00 ("Once sign comes close,"), recipe 0.67 → 1.00 ("and odd signs, each one smaller."), third 0.67 → 1.00 ("sin 3x a third is tall."), more 0.83 → 1.00 ("5x, 13x, and the corners sharpen."), except 1.00, over 1.00, gibbs 0.73 → 1.00 ("about 9% of the jump."). No line stays flagged. The vocabulary pulls the re-check toward the script, so 1.00 there only says the audio can be heard as the script, not that it was said right.
  - **Listen to** (the six lines under 0.9 on the first pass): more 12.3–13.1 s, "7x" heard as "13x"; square 0.4–0.5 s, "Take" heard as "took"; recipe 4.8–5.1 s, "Add" heard as "and"; third 10.1–10.2 s, "as" heard as "is". The rest is the recogniser, not the take: sine and sign sound the same, "One sine" runs together into "Once sign", and "nine percent" comes back as "9%". A line that is really wrong can only be fixed by re-recording it.
  - `bin/vh captions showcase/03-math-fourier en` added the `words` to `captions.json` and wrote `captions.en.lines.srt`: the one two-line caption (over) splits at 21.10 s, where "thinner." starts. `captions.en.srt` is byte-identical, so `media/final.mp4` was not re-muxed.
  - `tools/build_audio.sh` again: mix.wav and every stem are byte-identical to before the alignment (mix.wav md5 cbadba57…). The mix report's masking check now reads words instead of 0.4 s chunks (11 % of 45 chunks): 3 of 45 words (7 %) are under the 6 dB presence floor, inside the 10 % limit, so it only warns. They are "the" at 17.30 s (−1.0 dB, the music), and "the" at 13.40 s (+1.6 dB) and "and" at 13.30 s (+5.8 dB) under S5 and the 7th harmonic: the same three the local Whisper times had found. The mix is unchanged.
  - Score: 75 BPM (24 frames a beat), D major, delayed 0.3 s so 4.3 s is a bar head. Without drums a chord 0.1–0.2 s off a picture change reads as phrasing; the frame-exact moments are carried by the sonification.
  - Sonification: on D4, so its partials (D, A, F#, a flat C) belong to the D major bed. The tones are designed at −20…−26 dB. A version without them was made too; the maintainer heard both and chose the tones, with the music a bit lower (2026-10-01).
  - First candidate's mix: `duck=voice duck_ratio=1.6`; qa found no silence, dropouts or pumping. The mix lab measured its VMR at 8.3 LU median, 4.9 on the worst line, with the music rising to within 0.2–6 LU of the voice in the pauses.
  - Listen for (the maintainer heard the first candidate, not this profile mix): do the tones read as "the sum you see" or as test tones / hum under the voice? The 5th and 7th harmonics are close to masked, and the bell on "≈ 9%" is covered by the piano's D chord that lands with it. Now that the music is lower, do the tones sit too far forward?
- 2026-10-01 **Final mix: profile `explainer`** (`bin/vh mix … profile=explainer`, playbook/04-audio.md 混音), chosen by the maintainer after the candidates. It replaces the ffmpeg chain (`duck=voice`, sidechain compression) and the old workaround of running every bus past the film and cutting afterwards; the cut and the fade happen inside the mix (`dur=25 fade=0.5`), and every run gives the same bytes (checked).
  - Toolchain for the byte-identical rebuilds (the mix WAV and, with `--mux`, the mp4): ffmpeg 8.0.1, Python 3.14.7, numpy 2.5.3, scipy 1.18.1 (through uv 0.10.0, macOS on Apple Silicon). Other versions can change the low bits of the mix and of the AAC stream.
  - The narration is the anchor: eight lines levelled toward the median (raw span 5.5 LU → 2.2 LU), peaks held at anchor +10.5 dB (31 peaks, up to 1.8 dB). The music is ridden under each line to VMR 13 LU (13.0–13.9 on seven lines; 16.9 on the first, where the score has barely started) with a presence carve of up to 7 dB (5.7 dB on average under speech); its static gain is −3.1 dB.
  - "The music a bit lower", checked: under the lines it went from 8.3 LU below the voice (median; the worst line 4.9) to 13.1 (13.0), and in the pauses from 0.2–6 LU to 7–13 LU below the narration level. The music bus is −24.9 LUFS in the −14 LUFS mix (−19.5 in the first candidate). It is not buried: per line, the drone is 13 dB over the voice in the 44–88 Hz octave, and the piano and strings sit 10–15 dB under the voice from 88 Hz to 2.8 kHz (octave bands, median of the eight lines); no line is near the profile's 18 LU ceiling. On laptop speakers, which don't play the drone's octave, the bed will sound quieter than on headphones.
  - SFX: the nine tones are the signal class, median −8.4 LU re the voice (range −12…−4), about where they were in the first candidate (−9.0), so now 4–5 LU above the music under the lines. The whoosh is a detail (−11.8), the bell a hero (−7.0). One short room (dry/wet +12.6 dB); a presence carve of up to 8 dB where they cover words.
  - Master: static gain +2.05 dB and a true-peak limiter on 15 peaks (up to 0.7 dB): −14.00 LUFS, −1.65 dBTP in the WAV, −1.51 dBTP after the AAC encode (ffmpeg ebur128: −14.0 LUFS).
  - `bin/vh qa`: no silence (only 0–0.23 s, before the first sound), dropouts or pumping. No cues: the sounds swell, so they sit at or below −18 dB, which the cue check skips. Three click warnings, all consonants in the narration take (the voice alone has them on the same samples).
  - Mix report: targets met. Warnings: the music rises 4.6–6.5 LU in three pauses (7.34–8.20, and the score's designed swells into D∞ at 14.67 and the payoff at 21.80); S3 (10.2 s) and S5 (12.5 s) come within 6 dB of the voice at 1–4 kHz.
- 2026-10-01 **Colour: re-encoded to limited-range BT.709.** Manim's render was `yuv420p` with no colour tags and BT.601 limited-range pixels; Chromium reads an untagged HD file as BT.709, so the running sum's `#FFFF00` showed as (255, 240, 0). Re-encoded once, with the new soundtrack, from the committed final:
  `ffmpeg -i final.mp4 -map 0:v:0 -vf "setpts=N/30/TB,scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int,format=yuv420p,setparams=range=tv:colorspace=bt709:color_primaries=bt709:color_trc=bt709" -c:v libx264 -preset slow -crf 17 -r 30 -movflags +faststart out.mp4`
  - ffmpeg treats the untagged input as BT.601 limited, which is what it is. `setpts=N/30/TB` puts the 750 frames on an exact 30 fps grid: the old file's timestamps drifted to 24.999 s.
  - `accurate_rnd+full_chroma_int`: with swscale's default flags the yellow came back as (252, 253, 0) (Y 217 instead of 219 before the encode); with them, (254, 254, 1).
  - Check: 750 frames at 30 fps, 25.000 s; all four tags (`tv`, `bt709` ×3). Over the interior of the yellow in frames 495 and 690 (3346 pixels, eroded 5 × 5 so chroma edges don't count), the original decoded with its true matrix is (255, 255, 0); read as BT.709 it is (255, 240, 0), 5.4 levels off on average (max 16); the new file decoded with its tags is (254, 254, 1), 1.4 levels off. RGB PSNR against the original, frame by frame: 43.0 dB at worst, so no frame moved.
  - Size: CRF 17 makes the video 2.22 MB (−5 % against the old 2.34 MB); with the AAC track the mp4 is 2.85 MB.

## Self-review log

[v1 · whole piece 0–23.9 s] sheet: out/check/v1_sheet.png, strips: v1_strip_add3.png (9.2–11.0 s), v1_strip_zoom.png (17.1–18.9 s), frame v1_final.png. Render -ql 22 s wall.
- bbox audit: no unexpected overlaps; all boxes inside the safe box (panel right edge 1797 px < 1824). Only "peak_line × brace" touches (0 px high, brace ends on the line by design).
- `bin/vh check`: `black_start 0 → 2.47 s` = false positive (thin grey curve on pure black, >98% black pixels); freeze 22.33 → end = intended final hold.
- #13/#17 PASS: add-harmonic strip reads: blue ⅓-size wave on the axis → rides onto the yellow → yellow absorbs it.
- #10 FAIL (minor): during the merge, blue under a half-faded yellow gives 1–2 greenish frames → fade blue in [0.1, 0.55] of the merge instead of [0.4, 1].
- #4 FAIL: zoom strip frames 3–4 — the panel grows while the parent is still large, so the panel's black background covers the parent's right plateau → split the move: parent shrinks over [0, 0.7], panel opens over [0.3, 1.0] (two trackers).
- #2 FAIL (minor): zoom panel y-range 0.45–1.45 leaves the lower 45% nearly empty; the horn is only ~130 px tall → tighten to 0.62–1.34 (horn ≈ 190 px).
- #6 FAIL (minor): tick values (32) and the Gibbs label (36) are small once the GIF is scaled to 640 px → 38 and 42.
- Considered, kept: rows A empty for the first 4.3 s (graph sits low until the equation arrives). Density ramp; moving the graph would add a move with no meaning.
- others PASS

[v2 · 8.1–11.0 s and 17.0–19.0 s] strips: out/check/v2_strip_merge3.png, v2_strip_zoom.png, frame v2_final.png
- #4 PASS now: parent shrinks first, panel grows out of the magnifier box; horn ≈ 190 px tall, labels readable at 640 px.
- #15 FAIL: early blue fade (v1 fix) makes the yellow arrive at an unmarked place (blue already gone) → keep blue until late (fade in [0.6, 1]) but draw it UNDER the yellow during the merge (z-index 3 → 1.5), so the opaque yellow covers it; no blended colour.
- others PASS

[v3 = final · 0–24.0 s, 1080p30] sheet: out/check/final_sheet.png, strips final_strip_{D3,Dinf,zoom,F}.png, crop final_crop_horn.png, stills final_t*.png
- merge strip (v3_strip_merge3.png): yellow slides onto the blue, thin blue edges visible until covered → PASS.
- ffprobe 1920x1080, 30/1, 23.999 s, h264, no audio stream. `bin/vh check`: black 0–2.77 s (false positive, see v1), freeze 22.40 s → end (intended 1.6 s final hold).
- determinism: `-n 30,31 --format png` frames byte-identical to the full PNG render (21/21).
- Known minor: brace's lower tip touches the N = 99 ringing at the panel's right edge (by design the brace ends at y = 1); rows A empty for the first 4.3 s.

[reviewer pass · fresh-context subagent (playbook/02 layer 5) on the v3 frames] verdict: **don't ship as-is**. Fixes applied in v4:
- Zoom glitch 17.6–18.0 s: the panel's opaque fill blacked out the corner being magnified while the parent was still shrinking. → E is now strictly sequential: parent shrinks 17.2–17.8, magnifier box fades in on the settled parent 17.8–18.0, panel + links grow from the box 18.0–18.7, hold to 18.9; panel fill/curves layered UNDER the parent and the box.
  - Root cause found while fixing: `Mobject.become()` (used by `always_redraw`) copies points and style but **not z_index**, so each live curve kept the z_index of its first `func()` result (mostly an empty VMobject at z = 0). The panel fill therefore sat at the same layer as the parent's yellow and was drawn over it by add order; the grey target (z = 1) was drawn *above* the yellow sum all video; and the v3 "blue under yellow during the merge" z-trick never took effect (the v3 improvement came from the fade timing alone). → `live()` wrapper = always_redraw + `set_z_index(new.z_index)` on every update; explicit layers documented in fourier.py.
- Final hold 1.6 s → 2.6 s (total 24.0 → 25.0 s), so "≈ 9% of the jump" is fully readable for ~2.8 s.
- "9%" didn't match what's on screen (only 1 and 1.179 were visible; the jump of 2 never was). → grey ticks `1` and `−1` on the always-visible parent graph, appearing at 18.9 s with the panel's `1`. Parent shrunk to 0.42× and shifted +0.25 so the `−1` label stays inside the safe box (bbox audit: tick_-1 x 130–183 px ≥ 96).
- N = 7 read too short → `N = 7` held 15.3–15.5, sweep moved to 15.5–16.7 s (1.2 s).

[v4 = final · 0–25.0 s, 1080p30] sheet: out/check/final_sheet.png (= out/check/final-sheet-011502.png), strips: final_strip_zoom.png (17.1–19.0 at 10 fps), final_strip_Dinf.png, v4_strip_merge3.png, crop: final_crop_horn.png
- ffprobe 1920x1080, 30/1, 24.999 s. bbox audit: no unexpected overlaps, nothing outside the safe box.
- `bin/vh check`: black 0–2.77 s and 17.57–18.33 s (the new sequenced zoom has ~0.8 s where only the small parent + faint box are on screen; > 98% black pixels) and freeze 22.40 → end = intended hold. All false positives for a pure-black explainer; the updated `bin/vh check` now prints that caveat itself.
- merge strip: opaque yellow now really slides over the blue (blue underneath, fades late) → PASS.
- determinism re-checked after the `live()` change: `-n 33,35 --format png` frames byte-identical to the full render (21/21).
- Could not fix / left as is: row A empty for the first 4.3 s; the brace's lower tip touches the N = 99 ringing at the panel's right edge (brace ends at y = 1 by design).

## Asset ledger
| file | source | licence |
|---|---|---|
| (none) | all visuals generated by `scenes/fourier.py` | original |
| audio/voiceover.en.flac (narration) | Gemini 3.8 Flash TTS, voice Iapetus, synthesized 2026-09-30; SynthID watermark | AI-synthesized, used under Google's terms; disclose on publication |
| audio/score.json → the music | composed here; rendered by `bin/vh music` (synthesis only, no samples) | original |
| 10 sonification sounds (target square, sums, harmonics, sweep, bell) | `tools/foley.py`, synthesized | original |
| built-in SFX (air) | `bin/vh sfx lib` (`tools/audio/sfx.py`) | MIT, part of this repo |

## 2026-10-18 · Engine migration (Manim CE → ManimGX)

- The repo's math engine is now **ManimGX 0.1.1** (Rust/wgpu GPU core; CE's Python API; built-in Typst math; no LaTeX/ffmpeg/cairo/pango). This showcase was re-validated end-to-end on it: draft + final renders, `manimgx inspect` (no layout problems in 41 samples), bbox audits unchanged, pixel-checked frames at t = 1…23 s (grey target, blue harmonics, yellow sums, red Gibbs elements, zoom panel all correct). Code changes: see LESSONS.md › 2026-10-18 (three edits: star import + numpy, `Path` alias, `rate_functions.*` → package-level).
- Render wall times (2-core CPU, lavapipe): draft 480p15 10.9 s; final 1080p30 40.3 s. Expect faster on GPU (Vulkan; e.g. Kaggle T4).
- Colour: ManimGX output is limited-range **tagged** (matrix smpte170m, transfer sRGB, primaries bt709) — no more untagged-BT.601 pixels (the 2026-10-01 entry below stays as the CE-era record). Delivery re-encode to BT.709 still happens in the soundtrack mix, as before.
- The 2026-09-28 CE-era entries above are kept as the historical record of how the film was originally built; they still describe CE behaviour correctly.
