"""Building a square wave from sine waves (Fourier partial sums + Gibbs overshoot).

Silent, 1920x1080 @ 30 fps, 25.0 s.  Render (ManimGX):
    uv run manimgx render -r 854x480 --fps 15 scenes/fourier.py FourierSquareWave    # draft
    uv run manimgx render -r 1920x1080 --fps 30 scenes/fourier.py FourierSquareWave   # final

Every drawn curve is an always_redraw of closed-form maths evaluated from ValueTrackers, so each
frame is a pure function of the tracker values at that time (no per-frame state, no randomness).
Timings follow STORYBOARD.md (shot letters in the comments).
"""
import sys
from pathlib import Path as FsPath   # aliased: `from manimgx import *` exports a Path mobject class

sys.path.insert(0, str(FsPath(__file__).resolve().parent))

import numpy as np  # noqa: E402  (manimgx does not re-export numpy the way manim did)
from manimgx import *  # noqa: E402,F403
from style import (  # noqa: E402
    GRID, TARGET, HARM, SUM, OVER, INK, BG, AXIS_OPACITY, DIM, CONTEXT,
    harmonic, partial_sum, highest_n, square_polyline, lerp, to_screen,
    data_rect_on_screen, reveal, clip_runs, curve_mob, audit,
)

config.background_color = BG

# ── Geometry (all derived from the grid) ────────────────────────────────────────
X0, X1 = -PI, 3 * PI
MAIN_DATA = (X0, X1, -1.5, 1.5)
ZOOM_DATA = (2 * PI - 0.25, 2 * PI + 0.95, 0.62, 1.34)     # rising jump at x = 2*pi, top corner
_bx = GRID.rect("B1", "F6")                                # graph zone, rows B–F
BIG = (_bx[0], _bx[1], 12.4, 5.4)
_sx = GRID.rect("C1", "E3")                                # parent after the zoom (≈37% of frame width)
SMALL = (_sx[0] + 0.25, _sx[1], BIG[2] * 0.42, BIG[3] * 0.42)   # +0.25: room for the 1 / −1 ticks
PANEL = GRID.rect("B4", "F6", pad=0.2)                     # zoom panel
MAIN_XS = np.linspace(X0, X1, 4001)
ZOOM_XS = np.linspace(ZOOM_DATA[0], ZOOM_DATA[1], 1601)
PEAK = 1.178980                                            # (2/pi) Si(pi), tools/verify_math.py
STROKE = 5.0


def late(t0, t1=1.0, f=smooth):
    """Rate function that runs f only inside [t0, t1] of the play() (lets one play() stagger parts)."""
    return lambda t: f(min(1.0, max(0.0, (t - t0) / (t1 - t0))))


def live(func):
    """always_redraw + z_index: Mobject.become() copies points and style but NOT z_index, so a plain
    always_redraw keeps the z_index of its first func() result forever."""
    mob = func()

    def update(m):
        new = func()
        m.become(new)
        m.set_z_index(new.z_index)
    mob.add_updater(update)
    return mob


class FourierSquareWave(Scene):
    def construct(self):
        FsPath("out/check/bbox_audit.txt").unlink(missing_ok=True)
        # ── trackers ───────────────────────────────────────────────────────────
        ax_o = ValueTracker(0)   # axis opacity factor
        rt = ValueTracker(0)     # target reveal 0..1
        w = ValueTracker(0)      # running sum: continuous number of terms
        yo = ValueTracker(0)     # running-sum opacity
        bn = ValueTracker(1)     # harmonic being added (n)
        bw = ValueTracker(0)     # running sum the harmonic is stacked on (frozen during lift)
        br = ValueTracker(0)     # harmonic reveal 0..1
        bl = ValueTracker(0)     # lift: 0 = on the axis, 1 = stacked on the sum
        bo = ValueTracker(0)     # harmonic opacity
        bc = ValueTracker(0)     # harmonic colour blue -> yellow (first term only)
        hz = ValueTracker(3)     # harmonic z-index: 3 = above the sum (draw/lift), 1.5 = under it (merge)
        z = ValueTracker(0)      # parent layout: 0 = full graph, 1 = small parent (C1–E3)
        zq = ValueTracker(0)     # zoom panel: 0 = the magnifier box itself, 1 = open panel (B4–F6)
        co = ValueTracker(0)     # counter opacity
        mo = ValueTracker(0)     # magnifier box opacity

        def main_rect():
            return lerp(BIG, SMALL, z.get_value())

        def main_alpha():         # parent becomes a context layer once zoomed
            return 1 - 0.35 * z.get_value()

        def width():
            return STROKE * (1 - 0.3 * z.get_value())

        # ── main graph ─────────────────────────────────────────────────────────
        # z layers (low → high): panel fill 0.1, panel curves 0.2–0.3, links 0.5, axis 0.8, parent target 1,
        # harmonic 1.5 (merge) or 3, parent sum 2, magnifier box 4, text 8. The parent sits ABOVE the panel.
        axis = live(lambda: Line(
            *to_screen([X0, X1], [0, 0], MAIN_DATA, main_rect()),
            stroke_color=INK, stroke_width=2, stroke_opacity=AXIS_OPACITY * ax_o.get_value()).set_z_index(0.8))

        def target_main():
            xs, ys = square_polyline(X0 + rt.get_value() * (X1 - X0))
            return curve_mob([to_screen(xs, ys, MAIN_DATA, main_rect())], TARGET, width(),
                             main_alpha()).set_z_index(1)

        def sum_main():
            if yo.get_value() <= 0:
                return VMobject().set_z_index(2)
            ys = partial_sum(MAIN_XS, w.get_value())
            return curve_mob([to_screen(MAIN_XS, ys, MAIN_DATA, main_rect())], SUM, width(),
                             yo.get_value() * main_alpha()).set_z_index(2)

        def harm_main():
            if bo.get_value() <= 0:
                return VMobject().set_z_index(hz.get_value())
            n = int(round(bn.get_value()))
            ys = bl.get_value() * partial_sum(MAIN_XS, bw.get_value()) + harmonic(MAIN_XS, n)
            xs, ys = reveal(MAIN_XS, ys, X0 + br.get_value() * (X1 - X0))
            color = interpolate_color(HARM, SUM, bc.get_value())
            return curve_mob([to_screen(xs, ys, MAIN_DATA, main_rect())], color, STROKE,
                             bo.get_value()).set_z_index(hz.get_value())

        target = live(target_main)
        ysum = live(sum_main)
        harm = live(harm_main)

        # ── zoom panel (exists only while z > 0) ───────────────────────────────
        def panel_alpha():
            return min(1.0, zq.get_value() / 0.12)

        def box_rect():
            return data_rect_on_screen(ZOOM_DATA, MAIN_DATA, main_rect())

        def panel_rect():
            return lerp(box_rect(), PANEL, zq.get_value())

        def rect_mob(r, **kw):
            return Rectangle(width=r[2], height=r[3], **kw).move_to([r[0], r[1], 0])

        def panel_bg():
            if panel_alpha() <= 0:
                return VMobject().set_z_index(0.1)
            return rect_mob(panel_rect(), fill_color=BG, fill_opacity=1, stroke_color=INK,
                            stroke_width=2, stroke_opacity=0.35 * panel_alpha()).set_z_index(0.1)

        def magnifier():          # box on the parent: fades in on its own, before the panel grows
            if mo.get_value() <= 0:
                return VMobject().set_z_index(4)
            return rect_mob(box_rect(), stroke_color=INK, stroke_width=2,
                            stroke_opacity=0.7 * mo.get_value()).set_z_index(4)

        def links():              # box corners -> panel corners, grow with the panel
            if panel_alpha() <= 0:
                return VMobject().set_z_index(0.5)
            b, p = box_rect(), panel_rect()
            return VGroup(*[
                Line([b[0] + b[2] / 2, b[1] + s * b[3] / 2, 0], [p[0] - p[2] / 2, p[1] + s * p[3] / 2, 0],
                     stroke_color=INK, stroke_width=1.5, stroke_opacity=0.3 * panel_alpha())
                for s in (1, -1)]).set_z_index(0.5)

        def target_zoom():
            if panel_alpha() <= 0:
                return VMobject().set_z_index(0.2)
            xs, ys = square_polyline()
            runs = clip_runs(xs, ys, ZOOM_DATA)
            return curve_mob([to_screen(a, b, ZOOM_DATA, panel_rect()) for a, b in runs], TARGET, STROKE,
                             panel_alpha()).set_z_index(0.2)

        def sum_zoom():
            if panel_alpha() <= 0:
                return VMobject().set_z_index(0.3)
            ys = partial_sum(ZOOM_XS, w.get_value())
            runs = clip_runs(ZOOM_XS, ys, ZOOM_DATA)
            return curve_mob([to_screen(a, b, ZOOM_DATA, panel_rect()) for a, b in runs], SUM, STROKE,
                             panel_alpha()).set_z_index(0.3)

        pbg, mag, lnk, tz, sz = (live(f) for f in (panel_bg, magnifier, links, target_zoom, sum_zoom))

        # ── equation: whole, then dim, then term by term ───────────────────────
        eq = MathTex(r"f(x)", r"=", r"\frac{4}{\pi}", r"\Big(", r"\sin x", r"+", r"\frac{\sin 3x}{3}",
                     r"+", r"\frac{\sin 5x}{5}", r"+", r"\frac{\sin 7x}{7}", r"+", r"\cdots", r"\Big)",
                     font_size=46, color=INK)
        GRID.area(eq, "A1", "A5")
        eq.set_z_index(8)
        F, EQ, FOUR_PI, LP, T1, P3, T3, P5, T5, P7, T7, PD, DOTS, RP = eq

        # ── counter N (highest harmonic in the yellow sum) ─────────────────────
        def counter_mob():
            m = MathTex(rf"N = {highest_n(w.get_value())}", font_size=40, color=SUM)
            GRID.at(m, "A6")
            return m.set_opacity(co.get_value()).set_z_index(8)
        counter = live(counter_mob)

        self.add(pbg, tz, sz, lnk, axis, target, ysum, harm, mag, counter)

        # ── A · 0.0–2.1  the target square wave ───────────────────────────────
        self.wait(0.2)
        self.play(ax_o.animate.set_value(1), rt.animate.set_value(1), run_time=1.2,
                  rate_func=ease_in_out_sine)
        self.wait(0.7)

        # ── B · 2.1–4.3  one sine already follows it; it becomes the running sum ──
        bn.set_value(1); bw.set_value(0); bl.set_value(0); br.set_value(0); bo.set_value(1)
        self.play(br.animate.set_value(1), run_time=1.2, rate_func=ease_in_out_sine)
        self.wait(0.6)
        self.play(bc.animate.set_value(1), run_time=0.4)
        w.set_value(1); yo.set_value(1); bo.set_value(0); bc.set_value(0)   # identical curve, swap owners

        # ── C · 4.3–6.9  the series, whole → hold → dim ────────────────────────
        self.play(Write(eq), run_time=1.0)
        audit("C equation written", {"equation": eq, "axis": axis, "target": target, "sum": ysum},
              allowed_overlaps=[("axis", "target"), ("axis", "sum"), ("target", "sum")])
        self.wait(1.1)
        self.play(eq.animate.set_opacity(DIM), run_time=0.5)

        # ── D1 · 6.9–8.1  f(x) is the grey wave; first term is the yellow curve ─
        self.play(F.animate.set_opacity(1).set_color(TARGET), EQ.animate.set_opacity(1), run_time=0.4)
        self.play(FOUR_PI.animate.set_opacity(1).set_color(SUM), LP.animate.set_opacity(1),
                  T1.animate.set_opacity(1).set_color(SUM), run_time=0.4)
        self.wait(0.4)

        # ── D3 / D5 / D7 · stack the next odd harmonic onto the running sum ────
        def add_term(k, plus, term, t_draw, h1, t_lift, t_merge, h2):
            n = 2 * k + 1
            bn.set_value(n); bw.set_value(k); bl.set_value(0); br.set_value(0); bo.set_value(1); bc.set_value(0)
            hz.set_value(3)
            # per-animation rate funcs (a play-level rate_func would override them all)
            self.play(plus.animate(rate_func=late(0, 0.4)).set_opacity(1),
                      term.animate(rate_func=late(0, 0.4)).set_opacity(1).set_color(HARM),
                      br.animate(rate_func=ease_in_out_sine).set_value(1), run_time=t_draw)
            self.wait(h1)
            self.play(bl.animate.set_value(1), run_time=t_lift, rate_func=smooth)
            hz.set_value(1.5)   # merge: opaque yellow slides over the blue, blue fades underneath (no blended colour)
            self.play(w.animate(rate_func=smooth).set_value(k + 1), bo.animate(rate_func=late(0.6, 1.0)).set_value(0),
                      term.animate(rate_func=smooth).set_color(SUM), run_time=t_merge)
            self.wait(h2)

        add_term(1, P3, T3, 0.8, 0.4, 0.9, 0.4, 0.4)     # D3 · 8.1–11.0
        add_term(2, P5, T5, 0.6, 0.3, 0.6, 0.35, 0.25)   # D5 · 11.0–13.1
        add_term(3, P7, T7, 0.5, 0.3, 0.5, 0.3, 0.2)     # D7 · 13.1–14.9

        # ── D∞ · 14.9–17.2  "…and so on": N = 7 read, then N runs 7 → 25 (15.5–16.7) ─
        self.play(PD.animate.set_opacity(1), DOTS.animate.set_opacity(1).set_color(SUM),
                  RP.animate.set_opacity(1), co.animate.set_value(1), run_time=0.4)
        self.wait(0.2)
        self.play(w.animate.set_value(13), run_time=1.2, rate_func=smooth)
        audit("D∞ N=25 full graph", {"equation": eq, "counter": counter, "axis": axis, "target": target,
                                     "sum": ysum},
              allowed_overlaps=[("axis", "target"), ("axis", "sum"), ("target", "sum")])
        self.wait(0.5)

        # ── E · 17.2–18.9  zoom into the rising jump at x = 2π (reviewer pass: strictly sequential) ──
        self.play(z.animate.set_value(1), eq.animate.set_opacity(CONTEXT), run_time=0.6, rate_func=smooth)  # 17.2–17.8
        self.play(mo.animate.set_value(1), run_time=0.2, rate_func=smooth)                                # 17.8–18.0
        self.play(zq.animate.set_value(1), run_time=0.7, rate_func=smooth)                                # 18.0–18.7
        self.wait(0.2)                                                                                    # 18.7–18.9

        # ── F · 18.9–24.0  the horn: 1.179 vs 1, thinner but never shorter ──────
        def zp(x, y):
            return to_screen([x], [y], ZOOM_DATA, PANEL)[0]

        peak_line = DashedLine(zp(ZOOM_DATA[0], PEAK), zp(ZOOM_DATA[1], PEAK), dash_length=0.12,
                               stroke_color=OVER, stroke_width=3).set_z_index(8)
        x_lab = ZOOM_DATA[1] - 0.03
        peak_val = MathTex(r"1.179", font_size=38, color=OVER)
        peak_val.next_to(zp(x_lab, PEAK), UP, buff=0.12).align_to(zp(x_lab, PEAK), RIGHT).set_z_index(8)
        one_val = MathTex(r"1", font_size=38, color=TARGET)
        one_val.next_to(zp(x_lab, 1.0), DOWN, buff=0.18).align_to(zp(x_lab, 1.0), RIGHT).set_z_index(8)
        def mp(x, y):             # point on the settled (small) parent
            return to_screen([x], [y], MAIN_DATA, SMALL)[0]

        ticks = VGroup(*[Line(mp(X0, y) + 0.12 * LEFT, mp(X0, y), stroke_color=TARGET, stroke_width=2)
                         for y in (1, -1)])
        tick_labels = VGroup(*[MathTex(t, font_size=34, color=TARGET).next_to(mp(X0, y) + 0.12 * LEFT, LEFT, buff=0.08)
                               for t, y in (("1", 1), ("-1", -1))])
        VGroup(ticks, tick_labels).set_z_index(8)
        self.play(Create(peak_line), FadeIn(peak_val), FadeIn(one_val), FadeIn(ticks), FadeIn(tick_labels),
                  run_time=0.6)
        self.wait(0.4)
        self.play(w.animate.set_value(50), run_time=1.6, rate_func=smooth)   # N: 25 -> 99
        self.wait(0.3)
        brace = BraceBetweenPoints(zp(x_lab, 1.0), zp(x_lab, PEAK), direction=LEFT, color=OVER,
                                   buff=0.05).set_z_index(8)
        gibbs = Tex(r"$\approx 9\%$ of the jump", font_size=42, color=OVER)
        gibbs.next_to(brace, LEFT, buff=0.12).set_z_index(8)
        self.play(FadeIn(brace), FadeIn(gibbs, shift=0.15 * LEFT), run_time=0.6)
        audit("F final", {"equation": eq, "counter": counter, "parent_target": target, "parent_sum": ysum,
                          "magnifier": mag, "panel": pbg, "peak_line": peak_line, "peak_val": peak_val,
                          "one_val": one_val, "brace": brace, "gibbs": gibbs, "zoom_sum": sz,
                          "tick_1": tick_labels[0], "tick_-1": tick_labels[1], "links": lnk},
              allowed_overlaps=[("parent_target", "parent_sum"), ("magnifier", "parent_target"),
                                ("magnifier", "parent_sum"), ("magnifier", "panel"),
                                ("panel", "peak_line"), ("panel", "peak_val"), ("panel", "one_val"),
                                ("panel", "brace"), ("panel", "gibbs"), ("panel", "zoom_sum"),
                                ("zoom_sum", "peak_line"), ("zoom_sum", "one_val"), ("zoom_sum", "brace"),
                                ("zoom_sum", "gibbs"), ("zoom_sum", "peak_val"), ("links", "panel"),
                                ("links", "magnifier"), ("links", "parent_target"), ("links", "parent_sum"),
                                ("links", "zoom_sum")])
        self.wait(2.6)   # reviewer pass: 1.5 s → 2.5 s so "≈ 9% of the jump" is readable ~3 s
