"""Shared style for the Fourier square-wave scene: palette, 6x6 anchor grid, plotting helpers, bbox audit.

Everything here is a pure function of its arguments (no hidden state), so every frame is a pure
function of the ValueTrackers that the scene animates.
"""
from __future__ import annotations

import itertools
from pathlib import Path

import numpy as np
from manimgx import VMobject, ManimColor, config

# ── Palette: one colour per math entity, fixed for the whole video ─────────────
BG = ManimColor("#000000")
TARGET = ManimColor("#9A9A9A")  # square wave f(x)
HARM = ManimColor("#58C4DD")    # harmonic currently being added
SUM = ManimColor("#FFFF00")     # running partial sum S_N (+ included terms, counter N)
OVER = ManimColor("#FC6255")    # Gibbs overshoot
INK = ManimColor("#FFFFFF")     # operators only
AXIS_OPACITY = 0.28
DIM = 0.30                      # dimmed equation (type doc: 30%)
CONTEXT = 0.35                  # context layer while zoomed

PX_PER_UNIT = 1080 / 8.0        # 135 px per Manim unit at 1080p


# ── 6x6 anchor grid over the EBU safe box (96 px / 54 px margins) ──────────────
class Grid:
    rows = "ABCDEF"

    def __init__(self, x0=-6.4, x1=6.4, y_top=3.6, y_bot=-3.6, n=6):
        self.x0, self.x1, self.yt, self.yb, self.n = x0, x1, y_top, y_bot, n
        self.cw = (x1 - x0) / n
        self.ch = (y_top - y_bot) / n

    def _rc(self, name: str):
        return self.rows.index(name[0]), int(name[1:]) - 1

    def center(self, name: str) -> np.ndarray:
        r, c = self._rc(name)
        return np.array([self.x0 + (c + 0.5) * self.cw, self.yt - (r + 0.5) * self.ch, 0.0])

    def box(self, tl: str, br: str):
        """(xmin, xmax, ymin, ymax) of the block of cells tl..br."""
        r0, c0 = self._rc(tl)
        r1, c1 = self._rc(br)
        return (self.x0 + c0 * self.cw, self.x0 + (c1 + 1) * self.cw,
                self.yt - (r1 + 1) * self.ch, self.yt - r0 * self.ch)

    def rect(self, tl: str, br: str, pad=0.0):
        """Screen rect (cx, cy, w, h) of an area, shrunk by pad on every side."""
        xmin, xmax, ymin, ymax = self.box(tl, br)
        return ((xmin + xmax) / 2, (ymin + ymax) / 2, xmax - xmin - 2 * pad, ymax - ymin - 2 * pad)

    def at(self, mob, name: str):
        mob.move_to(self.center(name))
        return mob

    def area(self, mob, tl: str, br: str, pad=0.1, fit=True):
        cx, cy, w, h = self.rect(tl, br, pad)
        if fit and (mob.width > w or mob.height > h):
            mob.scale(min(w / mob.width, h / mob.height))
        mob.move_to([cx, cy, 0])
        return mob


GRID = Grid()


# ── Maths (verified in tools/verify_math.py) ───────────────────────────────────
def harmonic(x, n):
    """n-th odd harmonic of the unit square wave: (4 / (pi n)) sin(n x)."""
    return 4.0 / (np.pi * n) * np.sin(n * x)


def partial_sum(x, w):
    """Running sum with a continuous term count w: term k (n = 2k+1) enters with weight clip(w-k, 0, 1).
    w = 1 -> S_1, w = 2 -> S_3, w = 13 -> S_25, w = 50 -> S_99."""
    y = np.zeros_like(x)
    for k in range(int(np.ceil(w))):
        a = min(1.0, max(0.0, w - k))
        if a > 0:
            y += a * harmonic(x, 2 * k + 1)
    return y


def highest_n(w):
    return max(1, 2 * int(np.ceil(w - 1e-9)) - 1)


SQUARE_VERTS = [(-np.pi, -1), (0, -1), (0, 1), (np.pi, 1), (np.pi, -1),
                (2 * np.pi, -1), (2 * np.pi, 1), (3 * np.pi, 1)]


def square_polyline(x_reveal=np.inf):
    """Vertices of sign(sin x) on [-pi, 3pi] (vertical jump segments included), cut at x_reveal."""
    xs, ys = [SQUARE_VERTS[0][0]], [SQUARE_VERTS[0][1]]
    for (xa, ya), (xb, yb) in zip(SQUARE_VERTS, SQUARE_VERTS[1:]):
        if xb <= x_reveal:
            xs.append(xb); ys.append(yb)
        else:
            if xa < x_reveal and xb != xa:
                xs.append(x_reveal); ys.append(ya + (yb - ya) * (x_reveal - xa) / (xb - xa))
            break
    return np.array(xs, float), np.array(ys, float)


# ── Screen mapping and polyline construction ───────────────────────────────────
def lerp(a, b, t):
    return tuple(ai + (bi - ai) * t for ai, bi in zip(a, b))


def to_screen(xs, ys, data, scr):
    """data = (x0, x1, y0, y1) in maths units, scr = (cx, cy, w, h) in Manim units."""
    x0, x1, y0, y1 = data
    cx, cy, w, h = scr
    X = cx + (np.asarray(xs) - (x0 + x1) / 2) * w / (x1 - x0)
    Y = cy + (np.asarray(ys) - (y0 + y1) / 2) * h / (y1 - y0)
    return np.column_stack([X, Y, np.zeros_like(X)])


def data_rect_on_screen(inner, data, scr):
    """Screen rect (cx, cy, w, h) of the data-space rectangle `inner` inside a plot."""
    p = to_screen([inner[0], inner[1]], [inner[2], inner[3]], data, scr)
    return ((p[0, 0] + p[1, 0]) / 2, (p[0, 1] + p[1, 1]) / 2, abs(p[1, 0] - p[0, 0]), abs(p[1, 1] - p[0, 1]))


def reveal(xs, ys, x_r):
    """Keep the part of a sampled curve with x <= x_r (plus the interpolated end point)."""
    if x_r >= xs[-1]:
        return xs, ys
    i = int(np.searchsorted(xs, x_r))
    if i == 0:
        return xs[:0], ys[:0]
    y_r = ys[i - 1] + (ys[i] - ys[i - 1]) * (x_r - xs[i - 1]) / (xs[i] - xs[i - 1])
    return np.append(xs[:i], x_r), np.append(ys[:i], y_r)


def _clip_segment(ax, ay, bx, by, x0, x1, y0, y1):
    """Liang-Barsky: returns clipped (ax, ay, bx, by, t0, t1) or None."""
    dx, dy = bx - ax, by - ay
    t0, t1 = 0.0, 1.0
    for p, q in ((-dx, ax - x0), (dx, x1 - ax), (-dy, ay - y0), (dy, y1 - ay)):
        if p == 0:
            if q < 0:
                return None
        else:
            r = q / p
            if p < 0:
                if r > t1:
                    return None
                t0 = max(t0, r)
            else:
                if r < t0:
                    return None
                t1 = min(t1, r)
    return ax + t0 * dx, ay + t0 * dy, ax + t1 * dx, ay + t1 * dy, t0, t1


def clip_runs(xs, ys, rect):
    """Split a polyline into runs that lie inside rect = (x0, x1, y0, y1)."""
    runs, cur = [], []
    for i in range(len(xs) - 1):
        seg = _clip_segment(xs[i], ys[i], xs[i + 1], ys[i + 1], *rect)
        if seg is None:
            if len(cur) > 1:
                runs.append(cur)
            cur = []
            continue
        ax, ay, bx, by, t0, t1 = seg
        if not cur or t0 > 0:
            if len(cur) > 1:
                runs.append(cur)
            cur = [(ax, ay)]
        cur.append((bx, by))
        if t1 < 1:
            runs.append(cur)
            cur = []
    if len(cur) > 1:
        runs.append(cur)
    return [(np.array([p[0] for p in r]), np.array([p[1] for p in r])) for r in runs]


def curve_mob(runs_screen, color, width, opacity=1.0):
    """VMobject made of straight-segment subpaths (dense sampling, so no smoothing artefacts)."""
    m = VMobject()
    for pts in runs_screen:
        if len(pts) < 2:
            continue
        m.start_new_path(pts[0])
        m.add_points_as_corners(pts[1:])
    m.set_fill(opacity=0)
    m.set_stroke(color=color, width=width, opacity=opacity)
    return m


# ── Bounding-box audit (SGA-style: print every box, flag overlaps / safe-box exits) ─
def _px_box(m):
    l, r = m.get_left()[0], m.get_right()[0]
    b, t = m.get_bottom()[1], m.get_top()[1]
    fx, fy = config.frame_width / 2, config.frame_height / 2
    return ((l + fx) * PX_PER_UNIT, (fy - t) * PX_PER_UNIT, (r + fx) * PX_PER_UNIT, (fy - b) * PX_PER_UNIT)


def audit(tag, named: dict, allowed_overlaps=(), out_dir="out/check"):
    """named: {name: mobject}. Prints px boxes (x0, y0, x1, y1; origin top-left, 1920x1080),
    flags boxes outside the 96/54 px safe box and any pairwise overlap not in allowed_overlaps."""
    lines = [f"== bbox audit: {tag}"]
    boxes = {}
    for name, m in named.items():
        if m is None or len(m.get_all_points()) == 0:
            continue
        x0, y0, x1, y1 = _px_box(m)
        boxes[name] = (x0, y0, x1, y1)
        flag = ""
        if x0 < 96 - 0.5 or x1 > 1920 - 96 + 0.5 or y0 < 54 - 0.5 or y1 > 1080 - 54 + 0.5:
            flag = "  <-- OUTSIDE SAFE BOX"
        lines.append(f"  {name:<14} x {x0:7.1f}–{x1:7.1f}  y {y0:7.1f}–{y1:7.1f}  ({x1-x0:5.0f}x{y1-y0:4.0f}px){flag}")
    allowed = {frozenset(p) for p in allowed_overlaps}
    for (a, ba), (b, bb) in itertools.combinations(boxes.items(), 2):
        ix = min(ba[2], bb[2]) - max(ba[0], bb[0])
        iy = min(ba[3], bb[3]) - max(ba[1], bb[1])
        if ix > 0 and iy > 0:
            ok = frozenset((a, b)) in allowed
            lines.append(f"  {'allowed' if ok else 'OVERLAP'}: {a} × {b} ({ix:.0f}x{iy:.0f}px)")
    text = "\n".join(lines)
    print(text)
    Path(out_dir).mkdir(parents=True, exist_ok=True)
    with open(Path(out_dir) / "bbox_audit.txt", "a") as f:
        f.write(text + "\n")
    return boxes
