# STYLE

<!-- One page. Type doc (video-types/01) overrides template defaults: pure black bg, CMU Serif/LaTeX, 6x6 anchor grid. -->

## Canvas
- 1920x1080, 30 fps. ManimGX/CE frame = 14.222 x 8 units → 135 px/unit (same in both engines for 16:9).
- Safe box (EBU 90%): 96 px left/right, 54 px top/bottom → x ∈ [-6.40, 6.40], y ∈ [-3.60, 3.60] units.
- **Anchor grid** (Code2Video style, but over the whole safe box because there is no lecture column): 6 cols × 6 rows, rows A–F top→bottom, cols 1–6 left→right. Cell = 2.133 × 1.20 units (288 × 162 px).
  Cell centres: cols x = -5.33, -3.20, -1.07, 1.07, 3.20, 5.33; rows y = 3.0, 1.8, 0.6, -0.6, -1.8, -3.0.
- Placement only through `grid.at(mob, "B2")` / `grid.area(mob, "B1", "F6", fit=…)` in `scenes/style.py`. Exceptions (derived, not free-hand): labels via `next_to(object, …)` within one cell, and points computed from axes coordinates (curves, braces, magnifier box).
- Zones: row A = equation (A1–A5) + counter (A6). Rows B–F = graph. Final layout: parent graph shrinks into C1–E3 (≈ 39% frame width), zoom panel fills B4–F6.

## Palette (entity → colour, fixed for the whole video)
| token | hex | entity / use |
|---|---|---|
| bg | #000000 | background (type doc: pure black) |
| TARGET | #9A9A9A | the square wave f(x) and the symbol f(x) |
| HARM | #58C4DD | the harmonic currently being added, (4/πn)·sin(nx), and its term in the equation |
| SUM | #FFFF00 | the running partial sum S_N, every term already included, and the counter N |
| OVER | #FC6255 | the Gibbs overshoot: peak line, brace, "≈ 9%" label, 1.179 |
| INK | #FFFFFF | operators (=, +, brackets) only |
| AXIS | #FFFFFF @ 25% | x-axis, panel frame, magnifier lines (structure layer, 15–30%) |

Opacity layers: primary 1.0, context 0.35 (dimmed equation), structure 0.25.

## Type
- LaTeX only (`MathTex`/`Tex`, Computer Modern ≈ CMU Serif). No Pango `Text()`, so the 3b1b "Menlo for Text()" rule does not apply.
- Sizes (ManimGX font_size; same scale as CE): equation 46, counter 40, tick values 32, overshoot label 36. Check rendered glyph heights in the bbox audit.

## Motion tokens
| token | value |
|---|---|
| draw curve | reveal left→right, `linear`-ish `smooth`, 0.6–1.2 s |
| enter (text) | `Write` for the equation only; `FadeIn` for small labels, 0.4–0.6 s |
| morph (sum update) | `smooth`, 0.35–0.9 s (compresses with repetition) |
| layout move (zoom) | `smooth` (ease in-out), 1.2 s |
| hold after each move | ≥ 0.3 s; ≥ 1.0 s after first-of-kind reveals; 1.5 s final |
| register | no overshoot/bounce anywhere (the only "overshoot" is the maths) |

## Transitions
- One continuous shot. The only "transition" is the layout move into the zoom (parent shrinks left, magnifier box links to the panel). Dominant direction: left→right (curves draw left→right; zoom panel opens to the right).

## Banned
- Rainbow per-harmonic colours, glow, particles, bounce, idle wobble, bullet-list ending, title card, `Write()` on everything, text over the curves, Pango fonts.
