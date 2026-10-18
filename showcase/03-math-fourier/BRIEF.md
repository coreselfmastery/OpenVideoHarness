# BRIEF

<!-- Gate 1 skipped: the user authorised "no approval gates" for this README showcase. File still written as the reference for self-review. -->

> 2026-10-01: the picture below was made and finished silent, as briefed. English narration, a piano score and a sonification of the partial sums were fitted to it afterwards (README › Soundtrack), and the video was re-encoded to limited-range BT.709 at the same time (NOTES); the timings here are unchanged.

## Spec
- Output: 1920x1080, 30 fps, target 23–24 s (18–25 s allowed), ~700 frames
- Engine: ManimGX 0.1.1 (Rust/wgpu core; was Manim CE 0.21.0 Cairo until 2026-10-18), single scene `FourierSquareWave`
- Platform / audience: README showcase GIF/MP4 for OpenVideoHarness; autoplay, **muted**. Audience: curious undergrad / engineer who has heard "any signal is a sum of sines" but never watched it happen.
- Language: en (math notation carries the content), narration: **none** while the picture was made (silent); English narration added afterwards (README › Soundtrack)
- Deliverables: final.mp4, preview.gif (640 px, 15 fps, < 6 MB), sheet.png

## Content
- Spine (one line): A square wave looks nothing like a sine, but stacking odd sines of size 1/n squares it up, except at the jump, where a ~9% horn never goes away.
- Recurring motif: the yellow running sum; every new blue harmonic lands on it and becomes yellow.
- What the viewer should know at the end: (1) the square wave is the sum (4/π)(sin x + sin 3x/3 + sin 5x/5 + ...); (2) each extra odd harmonic makes the corners sharper; (3) near the jump the partial sums always overshoot by ≈ 9% of the jump (Gibbs), no matter how many terms.
- Source material: standard result. Coefficients and Gibbs constant re-derived numerically in `tools/verify_math.py` (log in NOTES.md).

## Style
- Refs: 3Blue1Brown "But what is a Fourier series?" (colour discipline, dim-and-highlight), Mathologer (clean single-graph builds).
- Explicitly NOT: epicycle spirograph eye-candy, rainbow per-harmonic colours, glow, particles, bounce, bullet-list ending, title card.
- Palette: bg #000000 (type doc overrides template's "no pure black"), target grey #9A9A9A, harmonic blue #58C4DD, running sum yellow #FFFF00, overshoot red #FC6255. Neutral white #FFFFFF only for operators (+, =, brackets).
- Type: LaTeX Computer Modern (= CMU Serif) for everything; no Pango `Text()`.

## Motion defaults (override per type doc)
Each move 0.5–1.4 s followed by a hold ≥ 0.3 s; first occurrence of a pattern gets the long timings, repeats are compressed (tempo variation). Curves draw left→right. Rate functions: `smooth` for morphs, `ease_out_cubic` for entrances. No bounce/elastic, no idle loops, no crossfades between scenes (it is one continuous shot).

## Text rules
One equation (the series). Other text: a counter `N = …`, tick values `1` and `1.179`, and one label `≈ 9% of the jump`. ≤ 5 words per block; each block visible ≥ 2.5 s. Everything inside the 96/54 px safe box.

## Determinism
Every frame is a pure function of ValueTrackers driven by the play() timeline; curves recomputed from closed-form sums each frame (no stored per-frame state, no randomness).

## Process
1. STORYBOARD.md with reads + timings (gate 2 skipped by user; file still written).
2. No audio while the picture was made: timings come from the storyboard, not from a voiceover. (The narration added later was fitted to these timings.)
3. Build with `-ql`; per iteration: contact sheet + strips of the add-a-harmonic move and the zoom move + a crop of the horn; bounding boxes printed; critique vs TASTE_CHECKLIST in NOTES.md.
4. Uncertain facts go in NOTES.md.
5. Final at 1080p30 (`manimgx render -r 1920x1080 --fps 30`; default fps is 60), gif, sheet.

## Acceptance
- [ ] 18–25 s, 1920x1080, 30 fps; the picture render has no audio stream (the soundtrack is muxed on afterwards)
- [ ] every number on screen matches tools/verify_math.py (4/π, 1/n, 1.179, 8.95% ≈ 9%)
- [ ] each entity keeps one colour for the whole video
- [ ] equation appears whole, dims, then lights term by term in sync with the graph
- [ ] no overlaps reported by the bbox audit; nothing outside the safe box
- [ ] final frame = the horn that stays at 1.179 while N grows (the "what you now know" frame)

## TYPE
+ TYPE: 3b1b-style explainer. ManimGX, 1920x1080 30fps (`render -r 1920x1080 --fps 30`), bg #000000, math in New Computer Modern (built-in Typst). Audience: undergrad.
Bind one color per math entity for the whole video; symbol and its geometry share it: {target f(x): #9A9A9A, harmonic sin(nx)/n: #58C4DD, running sum: #FFFF00, overshoot: #FC6255}.
Open on the concrete puzzle with the core object on screen; say why it matters within 30s. Concrete example before the general rule.
Geometry first, then the equation. Equations appear whole, dim to 30%, then light up and get colored term by term.
Keep the parent diagram visible (dimmed) when zooming into details; dim old layers, never delete them mid-argument.
After a question card, hold 2.5s. Each play() 1–3s, then a 0.5–2s hold. No bounce, glow, particles, or bullet-list ending.
Place objects only via a 6x6 anchor grid (A1–F6) in the animation area; print all bounding boxes and check overlaps before rendering.
~~Narration via the engine's built-in say/word-cues.~~ Silent video: no narration, no cues. (Picture phase; the narration added on 2026-10-01 follows the picture, not the other way round.)

<!-- from 01-math-science-explainer.md -->
