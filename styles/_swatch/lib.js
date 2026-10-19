// lib.js — shared helpers for style swatch scenes. Everything here is a pure function of its arguments
// (t, seed, options). Caches only memoise deterministic results (textures, layouts), so frame N renders the same
// whether it is drawn first, last or alone. Scenes receive this module as `lib`; see README.md for the API table.

// ───────────────────────── frame, timing, content spec ─────────────────────────
export const W = 1920, H = 1080, FPS = 30, DUR = 5, FRAMES = 150, POSTER_T = 3.0;
/** Shared content spec (seconds). Every swatch follows it so the gallery compares like with like. */
export const SPEC = { establish: [0, 0.8], title: [0.8, 2.6], motif: [2.0, 4.0], outro: [4.0, 5.0], poster: 3.0 };
export const TITLE_EN = "Every frame is code.";
export const TITLE_ZH = "每一帧，都是代码。";
/** The 3-element motif, left to right: outline → storyboard → draft. */
export const MOTIF = [
  { key: "outline", en: "Outline", zh: "大纲" },
  { key: "storyboard", en: "Storyboard", zh: "分镜" },
  { key: "draft", en: "Draft", zh: "初版" },
];

/** A rectangle value object: { x0, y0, x1, y1, x, y, w, h, cx, cy } — the shape particles' `area` and marker()'s `box` take. */
export function box(x0, y0, x1, y1) { return { x0, y0, x1, y1, x: x0, y: y0, w: x1 - x0, h: y1 - y0, cx: (x0 + x1) / 2, cy: (y0 + y1) / 2 }; }
/** action: EBU R95 90 % graphics-safe (text ≥ 96 px from the sides, ≥ 54 px from top/bottom). title: 80 % title-safe. */
export const SAFE = { action: box(96, 54, W - 96, H - 54), title: box(192, 108, W - 192, H - 108) };

/** 6×6 anchor grid over the action-safe box, cells A1 (top-left) … F6 (bottom-right): letter = column, digit = row. */
export function anchor(name, area = SAFE.action) {
  const c = name.toUpperCase().charCodeAt(0) - 65, r = parseInt(name.slice(1), 10) - 1;
  return { x: area.x0 + (c + 0.5) * area.w / 6, y: area.y0 + (r + 0.5) * area.h / 6 };
}
/** n evenly spaced slot centres across a band (default: 3 motif slots on the horizontal centre line). */
export function slots(n = 3, { area = SAFE.title, y = H / 2, gap = 0 } = {}) {
  const w = (area.w - gap * (n - 1)) / n;
  return Array.from({ length: n }, (_, i) => ({ x: area.x0 + i * (w + gap) + w / 2, y, w }));
}

export const frame = (t) => Math.round(t * FPS);
/** Hold time on a lower frame rate ("on twos" = step(t, 15)); returns the start time of the held step. */
export const step = (t, fps = 12) => Math.floor(frame(t) * fps / FPS + 1e-9) / fps;

// ───────────────────────── math ─────────────────────────
export const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
export const lerp = (a, b, u) => a + (b - a) * u;
export const invlerp = (a, b, x) => (x - a) / (b - a);
export const remap = (x, a, b, c, d) => lerp(c, d, invlerp(a, b, x));
/** 0→1 progress of t across [a, b], clamped. */
export const seg = (t, a, b) => clamp((t - a) / (b - a));
export const smoothstep = (a, b, x) => { const u = clamp((x - a) / (b - a)); return u * u * (3 - 2 * u); };
export const fract = (x) => x - Math.floor(x);
export const TAU = Math.PI * 2;
/** Opacity window: fade in over fi after a, fade out over fo before b. */
export const env = (t, a, b, fi = 0.3, fo = 0.3) => Math.min(fi > 0 ? seg(t, a, a + fi) : (t >= a ? 1 : 0), fo > 0 ? 1 - seg(t, b - fo, b) : (t < b ? 1 : 0));

// ───────────────────────── seeded hash, rng, noise ─────────────────────────
const _f64 = new Float64Array(1), _u32 = new Uint32Array(_f64.buffer);
function mix32(h, k) { k = Math.imul(k, 0xcc9e2d51); k = (k << 15) | (k >>> 17); k = Math.imul(k, 0x1b873593); h ^= k; h = (h << 13) | (h >>> 19); return (Math.imul(h, 5) + 0xe6546b64) | 0; }
function fmix32(h) { h ^= h >>> 16; h = Math.imul(h, 0x85ebca6b); h ^= h >>> 13; h = Math.imul(h, 0xc2b2ae35); h ^= h >>> 16; return h >>> 0; }
/** 32-bit hash of any numbers (bit-exact on every machine: uses the IEEE-754 bits, not Math.sin). */
export function hash32(...xs) {
  let h = 0x9e3779b9 ^ xs.length;
  for (let x of xs) { _f64[0] = x + 0; h = mix32(h, _u32[0]); h = mix32(h, _u32[1]); }
  return fmix32(h);
}
/** hash(...) → [0, 1). Use hash(seed, i, frame(t)) for per-element, per-frame randomness. */
export const hash = (...xs) => hash32(...xs) / 4294967296;
/** Signed variant → [-1, 1). */
export const hashS = (...xs) => hash(...xs) * 2 - 1;
/** mulberry32 stream. Only for setup-time generation or inside one call; never keep one alive across frames. */
export function rng(seed = 1) {
  let a = hash32(seed) | 0;
  return () => { a = (a + 0x6d2b79f5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
const fade5 = (u) => u * u * u * (u * (u * 6 - 15) + 10);
/** 1D gradient noise in [-1, 1]. */
export function noise1(x, seed = 0) {
  const i = Math.floor(x), f = x - i;
  const g0 = hashS(seed, i), g1 = hashS(seed, i + 1);
  return 2 * lerp(g0 * f, g1 * (f - 1), fade5(f));
}
/** 2D gradient (Perlin-style) noise in about [-1, 1]. */
export function noise2(x, y, seed = 0) {
  const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi;
  const g = (ix, iy, dx, dy) => { const a = hash(seed, ix, iy) * TAU; return Math.cos(a) * dx + Math.sin(a) * dy; };
  const u = fade5(xf), v = fade5(yf);
  const n0 = lerp(g(xi, yi, xf, yf), g(xi + 1, yi, xf - 1, yf), u);
  const n1 = lerp(g(xi, yi + 1, xf, yf - 1), g(xi + 1, yi + 1, xf - 1, yf - 1), u);
  return lerp(n0, n1, v) * 1.414;
}
/** Fractal sum of noise2. */
export function fbm2(x, y, { octaves = 4, lacunarity = 2, gain = 0.5, seed = 0 } = {}) {
  let s = 0, a = 1, f = 1, n = 0;
  for (let o = 0; o < octaves; o++) { s += a * noise2(x * f, y * f, seed + o * 101); n += a; a *= gain; f *= lacunarity; }
  return s / n;
}

// ───────────────────────── easing ─────────────────────────
/** cubic-bezier(x1, y1, x2, y2) → u ↦ eased u, same curve as CSS / After Effects. */
export function bezier(x1, y1, x2, y2) {
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
  const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  const sx = (s) => ((ax * s + bx) * s + cx) * s, sy = (s) => ((ay * s + by) * s + cy) * s, dx = (s) => (3 * ax * s + 2 * bx) * s + cx;
  return (u) => {
    if (u <= 0) return 0; if (u >= 1) return 1;
    let s = u;
    for (let i = 0; i < 8; i++) { const e = sx(s) - u; if (Math.abs(e) < 1e-7) return sy(s); const d = dx(s); if (Math.abs(d) < 1e-6) break; s -= e / d; }
    let lo = 0, hi = 1; s = u;
    for (let i = 0; i < 40; i++) { const x = sx(s); if (Math.abs(x - u) < 1e-7) break; if (x < u) lo = s; else hi = s; s = (lo + hi) / 2; }
    return sy(s);
  };
}
/** Named curves (playbook/03-motion-design.md §1). Enter with out*, exit with in*, move between points with inOut*. */
export const ease = {
  linear: (u) => clamp(u),
  outExpo: bezier(0.16, 1, 0.3, 1), outQuint: bezier(0.22, 1, 0.36, 1), outCubic: bezier(0.33, 1, 0.68, 1),
  inCubic: bezier(0.32, 0, 0.67, 0), inExpo: bezier(0.7, 0, 0.84, 0),
  inOutCubic: bezier(0.65, 0, 0.35, 1), inOutQuart: bezier(0.76, 0, 0.24, 1), inOutSine: bezier(0.37, 0, 0.63, 1),
  outBack: bezier(0.34, 1.56, 0.64, 1),
  /** steps(n): hard frames for typing, counters, stop-motion. */
  steps: (n) => (u) => Math.min(1, Math.floor(clamp(u) * n) / n),
};
const CSS_EASE = { ease: [0.25, 0.1, 0.25, 1], "ease-in": [0.42, 0, 1, 1], "ease-out": [0, 0, 0.58, 1], "ease-in-out": [0.42, 0, 0.58, 1] };
const _easeCache = new Map();
/**
 * Any easing spec → function: a lib.ease name ("outExpo"), a [x1,y1,x2,y2] array, a CSS string
 * ("cubic-bezier(0.76,0,0.24,1)", "ease-out", "linear", "steps(4)"), or a function. Unknown → fallback.
 */
export function easeOf(e, fallback = ease.outExpo) {
  if (typeof e === "function") return e;
  if (Array.isArray(e) && e.length === 4) return bezier(...e.map(Number));
  if (typeof e !== "string") return fallback;
  if (ease[e] && e !== "steps") return ease[e];
  if (_easeCache.has(e)) return _easeCache.get(e);
  const s = e.trim().toLowerCase(); let f = null, m;
  if (s === "linear") f = ease.linear;
  else if (CSS_EASE[s]) f = bezier(...CSS_EASE[s]);
  else if ((m = s.match(/^cubic-bezier\(([^)]*)\)$/))) { const v = m[1].split(",").map(Number); if (v.length === 4 && v.every(Number.isFinite)) f = bezier(...v); }
  else if ((m = s.match(/^steps\((\d+)/))) f = ease.steps(+m[1]);
  _easeCache.set(e, f || fallback);
  return f || fallback;
}
/** Eased progress across [a, b]. */
export const tween = (t, a, b, e = ease.outExpo) => easeOf(e)(seg(t, a, b));

/**
 * Closed-form spring step response: 0 for tau ≤ 0, settles at 1. Pure function of tau — no integration, no state.
 * Give either { w, zeta } (natural frequency rad/s, damping ratio) or { stiffness, damping, mass } (Remotion-style),
 * plus optional v0 (initial velocity toward the target, units/s). zeta = 1: no overshoot; 0.8–0.85: ~1–1.5 %.
 */
export function spring(tau, { w = 12, zeta = 1, stiffness, damping, mass = 1, v0 = 0 } = {}) {
  if (tau <= 0) return 0;
  if (stiffness != null) { w = Math.sqrt(stiffness / mass); zeta = (damping ?? 10) / (2 * Math.sqrt(stiffness * mass)); }
  const x0 = -1;
  if (Math.abs(zeta - 1) < 1e-6) return 1 + Math.exp(-w * tau) * (x0 + (v0 + w * x0) * tau);
  if (zeta < 1) {
    const wd = w * Math.sqrt(1 - zeta * zeta);
    return 1 + Math.exp(-zeta * w * tau) * (x0 * Math.cos(wd * tau) + ((v0 + zeta * w * x0) / wd) * Math.sin(wd * tau));
  }
  const s = w * Math.sqrt(zeta * zeta - 1), r1 = -zeta * w + s, r2 = -zeta * w - s;
  const c2 = (v0 - r1 * x0) / (r2 - r1), c1 = x0 - c2;
  return 1 + c1 * Math.exp(r1 * tau) + c2 * Math.exp(r2 * tau);
}
/** Retargeting without state: v(t) = v0 + Σ Δv_i · spring(t − t_i). keys = [{t, v}, …]. */
export function springTrack(t, keys, opts) {
  let v = keys[0].v;
  for (let i = 1; i < keys.length; i++) v += (keys[i].v - keys[i - 1].v) * spring(t - keys[i].t, opts);
  return v;
}

// ───────────────────────── colour & tokens ─────────────────────────
/** Deep get with fallback: tok(tokens, "palette.accent", "#f00"). */
export function tok(tokens, path, fallback) {
  let o = tokens;
  for (const k of path.split(".")) { if (o == null || typeof o !== "object") return fallback; o = o[k]; }
  return o ?? fallback;
}
/**
 * Palette colour from tokens.palette (or tokens.colors): color(tokens, "fg"), color(tokens, "extra.2").
 * Values may be "#hex" or { hex: "#…" }. Missing → fallback (magenta by default, so a typo is visible).
 */
export function color(tokens, name, fallback = "#ff00ff") {
  const p = (tokens && (tokens.palette || tokens.colors)) || {};
  let v = String(name).includes(".") ? tok(p, String(name), undefined) : p[name];
  if (v === undefined && name === "fg") v = p.ink ?? p.text;   // presets that name their foreground ink or text (pastel-ui)
  if (typeof v === "string") return v;
  if (v && typeof v === "object") return v.hex || v.value || fallback;
  return fallback;
}
/** Every colour in the palette, flattened in order (bg, fg, accent, …extra). */
export function palette(tokens) {
  const p = (tokens && (tokens.palette || tokens.colors)) || {}, out = [];
  const add = (v) => { if (typeof v === "string") out.push(v); else if (Array.isArray(v)) v.forEach(add); else if (v && typeof v === "object") add(v.hex || v.value); };
  Object.values(p).forEach(add);
  return out;
}
export function rgb(hex) {
  let h = String(hex).replace("#", "");
  if (h.length === 3) h = h.split("").map((c) => c + c).join("");
  const n = parseInt(h.slice(0, 6), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
export const rgba = (hex, a = 1) => { const [r, g, b] = rgb(hex); return `rgba(${r},${g},${b},${a})`; };
export function mixColor(a, b, u) {
  const A = rgb(a), B = rgb(b), c = A.map((x, i) => Math.round(lerp(x, B[i], clamp(u))));
  return "#" + c.map((x) => x.toString(16).padStart(2, "0")).join("");
}
/** Relative luminance 0..1 (for picking ink on a background). */
export function luminance(hex) {
  const l = rgb(hex).map((c) => { c /= 255; return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); });
  return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2];
}

// ───────────────────────── creative pack: colour ─────────────────────────
function hexToHsl(hex) {
  const [r0, g0, b0] = rgb(hex).map((c) => c / 255);
  const mx = Math.max(r0, g0, b0), mn = Math.min(r0, g0, b0), d = mx - mn;
  let h = 0;
  if (d > 0) {
    if (mx === r0) h = ((g0 - b0) / d + (g0 < b0 ? 6 : 0)) / 6;
    else if (mx === g0) h = ((b0 - r0) / d + 2) / 6;
    else h = ((r0 - g0) / d + 4) / 6;
  }
  const l = (mx + mn) / 2, s = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1));
  return [h, s, l];
}
function hslToHex(h, s, l) {
  h = ((h % 1) + 1) % 1; s = clamp(s); l = clamp(l);
  const f = (n) => { const k = (n + h * 12) % 12, a = s * Math.min(l, 1 - l); return l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1)); };
  return "#" + [f(0), f(8), f(4)].map((c) => Math.round(clamp(c) * 255).toString(16).padStart(2, "0")).join("");
}
/**
 * Colour harmony from one seed colour: `count` colours in the same family — "analogous" (neighbours on the wheel),
 * "complementary", "split", "triad", "tetrad", "mono" (one hue, lightness spread). Seeded jitter keeps steps from
 * feeling mechanical; deterministic, so the palette from a draft is the palette in the delivery render.
 */
export function harmony(base, { scheme = "analogous", count = 5, jitter = 0.015, seed = 1 } = {}) {
  const [h, s, l] = hexToHsl(base);
  const offsets = {
    analogous: [0, 1 / 12, -1 / 12, 1 / 6, -1 / 6, 1 / 4],
    complementary: [0, 0.5, 0.08, 0.58, 0.25, 0.75],
    split: [0, 0.42, 0.58, 0.21, 0.79, 0.5],
    triad: [0, 1 / 3, 2 / 3, 1 / 6, 0.5, 5 / 6],
    tetrad: [0, 0.25, 0.5, 0.75, 0.125, 0.625],
    mono: [0],
  }[scheme] || [0];
  const out = [];
  for (let i = 0; i < count; i++) {
    const j = (hash(seed, i, scheme.length) - 0.5) * 2 * jitter;
    if (scheme === "mono") out.push(hslToHex(h, s * (1 - 0.14 * (i % 3)), clamp(l + (i - (count - 1) / 2) * 0.14, 0.08, 0.94)));
    else out.push(hslToHex(h + offsets[i % offsets.length] + j, s * (i % 2 ? 0.9 : 1), clamp(l + (i > 2 ? -0.06 * (i - 2) : 0.04 * i), 0.08, 0.94)));
  }
  return out;
}
/** Gradient lookup: ramp([[0, "#0a0e2a"], [0.55, "#5b2a86"], [1, "#ff9a3c"]], u) → interpolated hex. Stops need not start at 0 or end at 1. */
export function ramp(stops, u) {
  const S = [...stops].sort((a, b) => a[0] - b[0]);
  const x = clamp(u);
  if (x <= S[0][0]) return S[0][1];
  for (let i = 1; i < S.length; i++) {
    if (x <= S[i][0]) { const [p0, c0] = S[i - 1], [p1, c1] = S[i]; return mixColor(c0, c1, (x - p0) / Math.max(1e-9, p1 - p0)); }
  }
  return S[S.length - 1][1];
}

// ───────────────────────── fonts & text ─────────────────────────
const GENERIC = new Set(["serif", "sans-serif", "monospace", "cursive", "fantasy", "system-ui"]);
const ROLE_FALLBACK = {
  display: ["Helvetica Neue", "PingFang SC", "sans-serif"], body: ["Helvetica Neue", "PingFang SC", "sans-serif"],
  zh: ["PingFang SC", "Hiragino Sans GB", "sans-serif"], mono: ["Menlo", "PingFang SC", "monospace"],
  serif: ["Songti SC", "Times New Roman", "serif"],
};
/** Families always preloaded by the runtime (the fallbacks above). */
export const FALLBACK_FAMILIES = ["Helvetica Neue", "PingFang SC", "Hiragino Sans GB", "Menlo", "Songti SC"];
function roleSpec(tokens, role) {
  const f = tokens && (tokens.fonts || tokens.type || tokens.typography);
  const v = f ? f[role] : undefined;
  if (Array.isArray(v) || typeof v === "string") return { family: v };
  return v && typeof v === "object" ? v : {};
}
function familyList(v) {
  const arr = Array.isArray(v) ? v : typeof v === "string" ? v.split(",") : [];
  return arr.map((s) => String(s).trim().replace(/^["']|["']$/g, "")).filter(Boolean);
}
/** CSS family list for a role from tokens.fonts[role] (array, "A, B" string, or {family|stack: …}) + safe fallbacks. */
export function fontStack(tokens, role = "display") {
  const spec = roleSpec(tokens, role);
  const fams = familyList(spec.family ?? spec.stack ?? spec.families);
  for (const x of ROLE_FALLBACK[role] || ROLE_FALLBACK.body) if (!fams.includes(x)) fams.push(x);
  return fams.map((q) => (GENERIC.has(q) ? q : `"${q}"`)).join(", ");
}
/**
 * CSS font shorthand for canvas: font(tokens, "display", 120) → '700 120px "Helvetica Neue", …'.
 * Role defaults (tokens.fonts[role].weight / .style / .stretch) apply unless opts override them.
 */
export function font(tokens, role, size, opts = {}) {
  const spec = roleSpec(tokens, role);
  const weight = opts.weight ?? spec.weight ?? 400, style = opts.style ?? spec.style ?? "normal";
  return `${style === "italic" ? "italic " : ""}${weight} ${size}px ${fontStack(tokens, role)}`;
}
/** Tracking (letter-spacing) for a role in px: tokens.fonts[role].tracking is in em (e.g. -0.02). */
export const tracking = (tokens, role, size, override) => (override ?? roleSpec(tokens, role).tracking ?? 0) * size;
/** Set ctx.font (+ stretch) for a role. Returns the size for chaining. */
export function setFont(ctx, tokens, role, size, opts = {}) {
  ctx.font = font(tokens, role, size, opts);
  const st = opts.stretch ?? roleSpec(tokens, role).stretch;
  ctx.fontStretch = st || "normal";
  ctx.letterSpacing = "0px";
  return size;
}
/** True if a family renders with its own glyphs (not a fallback). Compares widths against two generic fallbacks. */
export function fontAvailable(family, sample = "mmmmmmmmmmlli WWW 0123 永每帧") {
  const c = layer("__font_probe", 8, 8);
  const w = (f) => { c.font = `400 64px ${f}`; return c.measureText(sample).width; };
  const q = `"${String(family).replace(/"/g, "")}"`;
  return w(`${q}, monospace`) !== w("monospace") || w(`${q}, serif`) !== w("serif");
}
/** Every family named in tokens.fonts (all roles), de-duplicated. */
export function tokenFamilies(tokens) {
  const f = (tokens && (tokens.fonts || tokens.type || tokens.typography)) || {};
  const out = [];
  for (const role of Object.keys(f)) { const sp = roleSpec(tokens, role); for (const x of familyList(sp.family ?? sp.stack ?? sp.families)) if (!GENERIC.has(x) && !out.includes(x)) out.push(x); }
  return out;
}
let _seg;
/** Split into user-perceived characters (emoji, combining marks and CJK safe). */
export function graphemes(str) {
  _seg = _seg || new Intl.Segmenter(undefined, { granularity: "grapheme" });
  return Array.from(_seg.segment(String(str)), (s) => s.segment);
}
export const isCJK = (ch) => /[⺀-鿿豈-﫿＀-￯　-〿]/.test(ch);
const NO_LINE_START = "，。、；：？！）」』》〉”’,.;:?!)%";

const _layoutCache = new Map();
/**
 * Measured single-line layout with per-glyph boxes. Uses ctx.font as currently set.
 * opts: { x, y (baseline), align: "left"|"center"|"right", tracking (px) }.
 * Returns { glyphs: [{ ch, i, x, y, w, cx }], width, ascent, descent, x0, x1 }. Kerning is kept (positions come from
 * measured prefixes), so drawing glyph by glyph matches fillText of the whole string.
 */
export function layoutText(ctx, str, { x = 0, y = 0, align = "left", tracking: tr = 0 } = {}) {
  const key = `${ctx.font}|${ctx.fontStretch}|${tr}|${str}`;
  let base = _layoutCache.get(key);
  if (!base) {
    const ls = ctx.letterSpacing; ctx.letterSpacing = "0px";
    const gs = graphemes(str); let acc = "";
    const glyphs = gs.map((ch, i) => { const gx = ctx.measureText(acc).width + i * tr; acc += ch; return { ch, i, x: gx, w: ctx.measureText(ch).width }; });
    const m = ctx.measureText(str);
    base = { glyphs, width: m.width + Math.max(0, gs.length - 1) * tr, ascent: m.actualBoundingBoxAscent, descent: m.actualBoundingBoxDescent,
      fontAscent: m.fontBoundingBoxAscent, fontDescent: m.fontBoundingBoxDescent };
    ctx.letterSpacing = ls;
    _layoutCache.set(key, base);
  }
  const ox = x - (align === "center" ? base.width / 2 : align === "right" ? base.width : 0);
  return { ...base, x0: ox, x1: ox + base.width, y,
    glyphs: base.glyphs.map((g) => ({ ...g, x: ox + g.x, y, cx: ox + g.x + g.w / 2 })) };
}
/**
 * Draw a layout glyph by glyph. fn(glyph, index) may return { alpha, dx, dy, scale, sx, sy, rot, fill, stroke, lineWidth, ch }
 * or null to skip the glyph. A replacement `ch` (scramble) is centred in the original glyph's slot, so width never jumps.
 */
export function drawGlyphs(ctx, lay, fn = () => ({})) {
  ctx.save();
  ctx.textAlign = "center"; ctx.textBaseline = "alphabetic"; ctx.letterSpacing = "0px";
  const baseFill = ctx.fillStyle, baseAlpha = ctx.globalAlpha;
  for (const g of lay.glyphs) {
    const s = fn(g, g.i);
    if (s === null || s === false) continue;
    const o = s || {}; const a = o.alpha ?? 1;
    if (a <= 0) continue;
    const ch = o.ch ?? g.ch;
    if (!ch || ch === " ") continue;
    // sx/sy default to scale. 0 is a real scale (a scale-in from nothing), not "unset"; a zero or non-finite scale draws
    // nothing (canvas silently ignores scale(∞ or NaN) and would draw the glyph at full size).
    const sc = o.scale ?? 1, sx = o.sx ?? sc, sy = o.sy ?? sc;
    if (!(sx * sy) || !Number.isFinite(sx * sy)) continue;
    ctx.save();
    ctx.globalAlpha = baseAlpha * a;
    ctx.translate(g.cx + (o.dx || 0), g.y + (o.dy || 0));
    if (o.rot) ctx.rotate(o.rot);
    if (sx !== 1 || sy !== 1) ctx.scale(sx, sy);
    ctx.fillStyle = o.fill ?? baseFill;
    if (o.fill !== "none") ctx.fillText(ch, 0, 0);
    if (o.stroke) { ctx.strokeStyle = o.stroke; ctx.lineWidth = o.lineWidth || 2; ctx.strokeText(ch, 0, 0); }
    ctx.restore();
  }
  ctx.restore();
}
/** Draw a whole string with tracking (simple case). */
export function drawText(ctx, str, x, y, { align = "left", tracking: tr = 0 } = {}) {
  drawGlyphs(ctx, layoutText(ctx, str, { x, y, align, tracking: tr }));
}
/** Largest font size in [min, max] at which str fits maxWidth. setSize(size) must set ctx.font. */
export function fitText(ctx, str, maxWidth, setSize, { min = 12, max = 400, tracking: trEm = 0 } = {}) {
  let lo = min, hi = max;
  for (let i = 0; i < 18; i++) { const mid = (lo + hi) / 2; setSize(mid); const w = ctx.measureText(str).width + trEm * mid * (graphemes(str).length - 1); if (w > maxWidth) hi = mid; else lo = mid; }
  setSize(lo); return lo;
}
/** Word wrap for Latin, per-character wrap for CJK (no line may start with ，。、 etc.). Uses ctx.font. */
export function wrapText(ctx, str, maxWidth) {
  const tokens = []; let buf = "";
  for (const ch of graphemes(str)) {
    if (isCJK(ch)) { if (buf) tokens.push(buf); buf = ""; tokens.push(ch); }
    else if (ch === " ") { tokens.push(buf + " "); buf = ""; }
    else buf += ch;
  }
  if (buf) tokens.push(buf);
  const lines = []; let line = "";
  for (const tk of tokens) {
    const test = line + tk;
    if (line && ctx.measureText(test.trimEnd()).width > maxWidth && !NO_LINE_START.includes(tk[0])) { lines.push(line.trimEnd()); line = tk.trimStart(); }
    else line = test;
  }
  if (line) lines.push(line.trimEnd());
  return lines;
}

export const GLYPHS_LATIN = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#$%&*+=<>/\\|";
export const GLYPHS_CJK = "田由甲申电里男町画界留略番疆口回目日曰旦旧白百自首囗囚国图团围圆";
/**
 * Decode / scramble, seeded and frame-quantized. Glyph i starts scrambling at start + i·stagger and locks to its
 * real character settle seconds later. The random glyph changes `rate` times per second (rate should divide 30:
 * 30, 15, 10, 6, 5). Returns [{ ch, final, state: "hidden"|"scramble"|"done", u }] aligned with graphemes(str).
 */
export function scrambleGlyphs(str, t, { start = 0, stagger = 0.03, settle = 0.35, rate = 15, seed = 1,
  charset = GLYPHS_LATIN, charsetCJK = GLYPHS_CJK, before = "hidden" } = {}) {
  const k = Math.floor(frame(t) * rate / FPS + 1e-9);
  return graphemes(str).map((ch, i) => {
    if (/\s/.test(ch)) return { ch, final: ch, state: "done", u: 1 };
    const t0 = start + i * stagger;
    if (t < t0) return before === "hidden" ? { ch: "", final: ch, state: "hidden", u: 0 } : { ch: pick(ch, i, k), final: ch, state: "scramble", u: 0 };
    if (t >= t0 + settle) return { ch, final: ch, state: "done", u: 1 };
    return { ch: pick(ch, i, k), final: ch, state: "scramble", u: (t - t0) / settle };
  });
  function pick(ch, i, k) { const cs = isCJK(ch) ? charsetCJK : charset; return cs[Math.floor(hash(seed, i, k) * cs.length)]; }
}
/** String form of scrambleGlyphs (hidden glyphs become spaces). */
export const scramble = (str, t, opts) => scrambleGlyphs(str, t, opts).map((g) => g.ch || " ").join("");
/** Typewriter: visible prefix at t, cps characters per second, frame-quantized. */
export function typewriter(str, t, { start = 0, cps = 20 } = {}) {
  const gs = graphemes(str); const n = Math.floor(Math.max(0, frame(t) - frame(start)) * cps / FPS + 1e-9);
  return gs.slice(0, Math.min(gs.length, n)).join("");
}

// ───────────────────────── creative pack: kinetic type ─────────────────────────
/**
 * Per-glyph choreography: the drawGlyphs style object for glyph i of n at time t. Modes: "rise" (spring up from
 * below), "pop" (spring scale-in), "wave" (travelling sine, loops forever), "cascade" (tumble in with rotation),
 * "jitter" (seeded boil, quantized to `rate` steps/s so it boils instead of vibrating). All pure functions of t;
 * `w`/`zeta` are the spring's (see spring()).
 */
export function glyphAnim(i, n, t, { mode = "rise", start = 0, stagger = 0.05, dur = 0.55, seed = 1, rate = 8,
  amp = 1, w = 13, zeta = 0.72 } = {}) {
  const t0 = start + i * stagger, u = seg(t, t0, t0 + dur);
  switch (mode) {
    case "pop": return { alpha: clamp(u * 3), scale: spring(u * dur, { w, zeta }) };
    case "wave": { const ph = t * 5 - i * 0.55; return { dy: -Math.sin(ph) * 14 * amp, alpha: 1 }; }
    case "cascade": { const s = spring(u * dur, { w: w + 2, zeta }); return { alpha: clamp(u * 2.5), dy: -70 * amp * (1 - s), rot: (1 - s) * -0.6 * amp, scale: 0.6 + 0.4 * s }; }
    case "jitter": { const k = step(t, rate); return { dx: hashS(seed, i, k) * 2.4 * amp, dy: hashS(seed, i, k + 101) * 2.4 * amp, alpha: 1 }; }
    default: { const s = spring(u * dur, { w, zeta }); return { alpha: clamp(u * 3), dy: (1 - s) * 90 * amp }; }   // rise
  }
}
/** A whole laid-out line under one choreography: set ctx.fillStyle first, then drawKinetic(ctx, lay, t, { mode: "rise", stagger: 0.04 }). */
export function drawKinetic(ctx, lay, t, { mode = "rise", fill, ...opts } = {}) {
  const n = lay.glyphs.length;
  drawGlyphs(ctx, lay, (g, i) => { const s = glyphAnim(i, n, t, { mode, ...opts }); return fill ? { ...s, fill } : s; });
}

// ───────────────────────── layers (offscreen canvases) ─────────────────────────
const _layers = new Map();
/** A named full-size offscreen canvas, cleared and state-reset on every call. Names are global: prefix yours. */
export function layer(name, w = W, h = H) {
  let c = _layers.get(name);
  if (!c || c.width !== w || c.height !== h) { c = document.createElement("canvas"); c.width = w; c.height = h; _layers.set(name, c); }
  const x = c.getContext("2d"); x.reset(); return x;
}
/** Run draw(ctx) into a fresh layer and return its canvas (to composite, mask, filter or feed a shader). */
export function offscreen(name, draw, w = W, h = H) { const x = layer(name, w, h); draw(x); return x.canvas; }

// ───────────────────────── textures ─────────────────────────
const _tex = new Map();
function cached(key, make) { let v = _tex.get(key); if (!v) { v = make(); _tex.set(key, v); } return v; }

/**
 * Film grain over the whole frame. Mid-grey noise tiles blended with `mode` (overlay by default), tile choice and
 * offset seeded by the frame step, refreshed `fps` times per second (24 = film cadence on a 30 fps timeline).
 */
export function grain(ctx, t, { amount = 0.08, size = 1, fps = 24, seed = 7, mode = "overlay", tiles = 6 } = {}) {
  if (amount <= 0) return;
  const T = 256;
  const set = cached(`grain:${seed}:${tiles}`, () => Array.from({ length: tiles }, (_, k) => {
    const c = document.createElement("canvas"); c.width = c.height = T;
    const x = c.getContext("2d"), img = x.createImageData(T, T), r = rng(hash32(seed, k));
    for (let i = 0; i < T * T; i++) { const v = 128 + ((r() + r() + r()) / 3 - 0.5) * 2 * 150; img.data[i * 4] = img.data[i * 4 + 1] = img.data[i * 4 + 2] = clamp(v, 0, 255); img.data[i * 4 + 3] = 255; }
    x.putImageData(img, 0, 0); return c;
  }));
  const s = Math.floor(frame(t) * fps / FPS + 1e-9);
  const tile = set[hash32(seed, s, 1) % tiles];
  ctx.save();
  const pat = ctx.createPattern(tile, "repeat");
  pat.setTransform(new DOMMatrix().translate(Math.floor(hash(seed, s, 2) * T), Math.floor(hash(seed, s, 3) * T)).scale(size));
  ctx.globalCompositeOperation = mode; ctx.globalAlpha = clamp(amount);
  ctx.fillStyle = pat; ctx.fillRect(0, 0, W, H);
  ctx.restore();
}

/** Static paper: base tone + low-frequency blotches + tooth + fibres. Generated once per option set, then cached. */
export function paper(ctx, { tone = "#f1ece1", amount = 1, blotch = 0.06, tooth = 0.025, fiber = 0.5, seed = 3 } = {}) {
  const key = `paper:${tone}:${blotch}:${tooth}:${fiber}:${seed}`;
  const c = cached(key, () => {
    const w = 960, h = 540, cv = document.createElement("canvas"); cv.width = w; cv.height = h;
    const x = cv.getContext("2d"), [R, G, B] = rgb(tone);
    // 1) blotches: fbm on a coarse grid, upscaled smoothly (cheap, and they are low-frequency anyway)
    const bw = 240, bh = 135, bc = document.createElement("canvas"); bc.width = bw; bc.height = bh;
    const bx = bc.getContext("2d"), bi = bx.createImageData(bw, bh);
    for (let j = 0; j < bh; j++) for (let i = 0; i < bw; i++) {
      const m = 1 + fbm2(i / 40, j / 40, { octaves: 4, seed }) * blotch, k = (j * bw + i) * 4;
      bi.data[k] = clamp(R * m, 0, 255); bi.data[k + 1] = clamp(G * m, 0, 255); bi.data[k + 2] = clamp(B * m, 0, 255); bi.data[k + 3] = 255;
    }
    bx.putImageData(bi, 0, 0); x.imageSmoothingQuality = "high"; x.drawImage(bc, 0, 0, w, h);
    // 2) tooth: per-pixel seeded noise
    const img = x.getImageData(0, 0, w, h), r = rng(seed + 5);
    for (let k = 0; k < img.data.length; k += 4) { const m = 1 + (r() - 0.5) * 2 * tooth; img.data[k] *= m; img.data[k + 1] *= m; img.data[k + 2] *= m; }
    x.putImageData(img, 0, 0);
    // 3) fibres
    const rf = rng(seed + 17), dark = rgba(mixColor(tone, "#000000", 0.35), 0.10 * fiber), light = rgba(mixColor(tone, "#ffffff", 0.6), 0.18 * fiber);
    x.lineCap = "round";
    for (let f = 0; f < 900 * fiber; f++) {
      const px = rf() * w, py = rf() * h, a = rf() * TAU, len = 3 + rf() * 14;
      x.strokeStyle = rf() < 0.5 ? dark : light; x.lineWidth = 0.35 + rf() * 0.5;
      x.beginPath(); x.moveTo(px, py); x.quadraticCurveTo(px + Math.cos(a) * len * 0.5 + (rf() - 0.5) * 4, py + Math.sin(a) * len * 0.5 + (rf() - 0.5) * 4, px + Math.cos(a) * len, py + Math.sin(a) * len); x.stroke();
    }
    return cv;
  });
  ctx.save(); ctx.globalAlpha = clamp(amount); ctx.imageSmoothingQuality = "high"; ctx.drawImage(c, 0, 0, W, H); ctx.restore();
}

/**
 * Halftone: dots whose area follows darkness. src is a canvas (luminance is sampled; dark = big dot) or a function
 * (x, y) → darkness 0..1. opts: { cell, angle (deg), color, shape: "dot"|"square"|"line", scale, invert, rect: {x,y,w,h} }.
 */
export function halftone(ctx, src, { cell = 12, angle = 45, color: col = "#111", shape = "dot", scale = 1, invert = false, rect = { x: 0, y: 0, w: W, h: H } } = {}) {
  let sample = src;
  if (typeof src !== "function") {
    const sw = Math.max(1, Math.ceil(rect.w / (cell / 2))), sh = Math.max(1, Math.ceil(rect.h / (cell / 2)));
    const sx = layer("__halftone_sample", sw, sh); sx.imageSmoothingQuality = "high";
    sx.drawImage(src, rect.x, rect.y, rect.w, rect.h, 0, 0, sw, sh);
    const d = sx.getImageData(0, 0, sw, sh).data;
    sample = (x, y) => {
      const i = clamp(Math.floor((x - rect.x) / rect.w * sw), 0, sw - 1), j = clamp(Math.floor((y - rect.y) / rect.h * sh), 0, sh - 1), k = (j * sw + i) * 4;
      const a = d[k + 3] / 255, l = (0.2126 * d[k] + 0.7152 * d[k + 1] + 0.0722 * d[k + 2]) / 255;
      return a * (1 - l);
    };
  }
  const a = angle * Math.PI / 180, ux = Math.cos(a) * cell, uy = Math.sin(a) * cell, vx = -uy, vy = ux;
  const cx = rect.x + rect.w / 2, cy = rect.y + rect.h / 2, R = Math.ceil(Math.hypot(rect.w, rect.h) / 2 / cell) + 1;
  ctx.save(); ctx.fillStyle = col; ctx.strokeStyle = col; ctx.beginPath();
  for (let j = -R; j <= R; j++) for (let i = -R; i <= R; i++) {
    const x = cx + i * ux + j * vx, y = cy + i * uy + j * vy;
    if (x < rect.x - cell || y < rect.y - cell || x > rect.x + rect.w + cell || y > rect.y + rect.h + cell) continue;
    let d = clamp(sample(x, y)); if (invert) d = 1 - d; d *= scale;
    if (d <= 0.01) continue;
    if (shape === "square") { const s = cell * Math.sqrt(d); ctx.rect(x - s / 2, y - s / 2, s, s); }
    else if (shape === "line") { const hw = cell * d * 0.5; ctx.moveTo(x - vx / 2 - ux * hw / cell, y - vy / 2 - uy * hw / cell); ctx.lineTo(x + vx / 2 - ux * hw / cell, y + vy / 2 - uy * hw / cell); ctx.lineTo(x + vx / 2 + ux * hw / cell, y + vy / 2 + uy * hw / cell); ctx.lineTo(x - vx / 2 + ux * hw / cell, y - vy / 2 + uy * hw / cell); ctx.closePath(); }
    else { const r = cell * 0.7071 * Math.sqrt(d); ctx.moveTo(x + r, y); ctx.arc(x, y, r, 0, TAU); }
  }
  ctx.fill(); ctx.restore();
}

/** CRT / video scanlines. roll = px per second the pattern drifts; flicker = per-frame alpha jitter (seeded). */
export function scanlines(ctx, t, { spacing = 4, thickness = 1.5, alpha = 0.25, color: col = "#000", roll = 0, flicker = 0, seed = 5 } = {}) {
  const tile = cached(`scan:${spacing}:${thickness}:${col}`, () => {
    const c = document.createElement("canvas"); c.width = 4; c.height = spacing;
    const x = c.getContext("2d"); x.fillStyle = col; x.fillRect(0, 0, 4, thickness); return c;
  });
  ctx.save();
  const pat = ctx.createPattern(tile, "repeat");
  pat.setTransform(new DOMMatrix().translate(0, ((t * roll) % spacing + spacing) % spacing));
  ctx.globalAlpha = clamp(alpha * (1 + flicker * hashS(seed, frame(t))));
  ctx.fillStyle = pat; ctx.fillRect(0, 0, W, H);
  ctx.restore();
}

/** Radial vignette: transparent inside `inner` (fraction of the half-diagonal), `strength` alpha at the corners. */
export function vignette(ctx, { strength = 0.5, inner = 0.55, color: col = "#000", cx = W / 2, cy = H / 2 } = {}) {
  const r = Math.hypot(W, H) / 2, g = ctx.createRadialGradient(cx, cy, r * inner, cx, cy, r);
  g.addColorStop(0, rgba(col, 0)); g.addColorStop(1, rgba(col, strength));
  ctx.save(); ctx.fillStyle = g; ctx.fillRect(0, 0, W, H); ctx.restore();
}

/**
 * Ink bleed approximation: draw(ctx) into a layer, then blur + turbulence-displace + alpha-threshold it with the SVG
 * filter #ovh-ink. spread = blur px (how far ink creeps; keep it ≤ half the thinnest stroke or thin strokes vanish),
 * rough = edge displacement, sharp = edge hardness, seed = turbulence seed (change it per frame step for "boiling"
 * edges: seed: step(t, 8) * 8 + 1).
 */
export function inkBleed(ctx, draw, { spread = 2.5, rough = 1, freq = 0.04, seed = 1, sharp = 4 } = {}) {
  const src = offscreen("__ink_src", draw);
  const set = (id, attrs) => { const el = document.getElementById(id); if (el) for (const k in attrs) el.setAttribute(k, String(attrs[k])); };
  set("ovh-ink-turb", { baseFrequency: freq, seed: Math.round(seed) });
  set("ovh-ink-blur", { stdDeviation: spread });
  set("ovh-ink-disp", { scale: spread * 1.6 * rough });
  set("ovh-ink-alpha", { slope: sharp, intercept: -(sharp - 1) * 0.3 });   // edge sits near 30 % of the blurred alpha: ink spreads outward
  ctx.save(); ctx.filter = "url(#ovh-ink)"; ctx.drawImage(src, 0, 0); ctx.restore();
}
/** Roughen edges (hand-cut paper, woodcut): displaces whatever draw() paints. */
export function roughen(ctx, draw, { amount = 6, freq = 0.06, seed = 1 } = {}) {
  const src = offscreen("__rough_src", draw);
  const t = document.getElementById("ovh-rough-turb"), d = document.getElementById("ovh-rough-disp");
  if (t) { t.setAttribute("baseFrequency", String(freq)); t.setAttribute("seed", String(Math.round(seed))); }
  if (d) d.setAttribute("scale", String(amount));
  ctx.save(); ctx.filter = "url(#ovh-rough)"; ctx.drawImage(src, 0, 0); ctx.restore();
}
/** RGB split / misregistration: composites the red, green and blue channels of src with offsets. */
export function rgbSplit(ctx, src, { r = [4, 0], g = [0, 0], b = [-4, 0] } = {}) {
  const ch = (name, hex, [dx, dy]) => { const x = layer(name); x.drawImage(src, 0, 0); x.globalCompositeOperation = "multiply"; x.fillStyle = hex; x.fillRect(0, 0, W, H); x.globalCompositeOperation = "destination-in"; x.drawImage(src, 0, 0); return [x.canvas, dx, dy]; };
  const parts = [ch("__rgb_r", "#ff0000", r), ch("__rgb_g", "#00ff00", g), ch("__rgb_b", "#0000ff", b)];
  ctx.save(); ctx.fillStyle = "#000"; ctx.fillRect(0, 0, W, H); ctx.globalCompositeOperation = "lighter";
  for (const [c, dx, dy] of parts) ctx.drawImage(c, dx, dy);
  ctx.restore();
}

// ───────────────────────── creative pack: post effects ─────────────────────────
/**
 * Bloom/glow: src blurred at half resolution and screened back over the frame (only adds light). threshold 0..1 adds a
 * brightness/contrast pre-pass so only highlights bloom (approximate — canvas filters, not per-pixel JS, so it stays
 * fast); radius is the full-res blur diameter. Feed it the frame so far (or a src layer) before grain/vignette.
 */
export function glow(ctx, src, { radius = 26, strength = 0.7, threshold = 0 } = {}) {
  if (strength <= 0) return;
  const hw = Math.max(2, W >> 1), hh = Math.max(2, H >> 1);
  const x = layer("__glow", hw, hh);
  const th = clamp(threshold, 0, 0.9);
  x.filter = th > 0 ? `brightness(${(1 / (1 - th)).toFixed(3)}) contrast(${(1 + th * 3).toFixed(2)}) blur(${Math.max(1, radius / 2)}px)` : `blur(${Math.max(1, radius / 2)}px)`;
  x.drawImage(src, 0, 0, hw, hh);
  x.filter = "none";
  ctx.save(); ctx.globalCompositeOperation = "screen"; ctx.globalAlpha = clamp(strength);
  ctx.imageSmoothingQuality = "high"; ctx.drawImage(x.canvas, 0, 0, W, H); ctx.restore();
}
/**
 * Duotone: src luminance remapped onto a dark→light two-colour ramp through the SVG filter #ovh-duotone (the browser's
 * filter pipeline — no per-pixel JS). amount < 1 blends the toned result over src.
 */
export function duotone(ctx, src, { dark = "#101d42", light = "#ffd9a0", amount = 1 } = {}) {
  const d = rgb(dark), l = rgb(light);
  const set = (id, a, b) => { const el = document.getElementById(id); if (el) el.setAttribute("tableValues", `${(a / 255).toFixed(4)} ${(b / 255).toFixed(4)}`); };
  set("ovh-duo-r", d[0], l[0]); set("ovh-duo-g", d[1], l[1]); set("ovh-duo-b", d[2], l[2]);
  const fx = layer("__duo"); fx.filter = "url(#ovh-duotone)"; fx.drawImage(src, 0, 0); fx.filter = "none";
  ctx.save(); ctx.globalAlpha = clamp(amount); ctx.drawImage(fx.canvas, 0, 0); ctx.restore();
}
/**
 * Analog light leak: a warm seeded glow drifts and flickers across the frame (screen blend — it only adds light, never
 * darkens). Position and flicker are seeded noise of t, never the clock.
 */
export function lightLeak(ctx, t, { color: col = "#ff8a3c", seed = 3, amount = 0.45, scale = 1.35 } = {}) {
  if (amount <= 0) return;
  const flick = 0.6 + 0.4 * noise1(t * 2.6, seed + 11);
  const cx = W * (0.5 + 0.45 * noise1(t * 0.33, seed)), cy = H * (0.4 + 0.3 * noise1(t * 0.21, seed + 5));
  const r = Math.hypot(W, H) * 0.4 * scale, a = clamp(amount) * flick;
  const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
  g.addColorStop(0, rgba(col, 0.9 * a)); g.addColorStop(0.45, rgba(col, 0.32 * a)); g.addColorStop(1, rgba(col, 0));
  ctx.save(); ctx.globalCompositeOperation = "screen"; ctx.fillStyle = g; ctx.fillRect(0, 0, W, H); ctx.restore();
}
/**
 * Shimmer sweep: a soft diagonal light band crosses the frame once every `period` seconds, phase-locked to t (pure,
 * loops cleanly at the period). With src, the band relights only src's pixels (src's alpha masks the band); without
 * src it is a plain band of light over the frame.
 */
export function shimmer(ctx, t, src, { period = 4, width: bw = 260, angle = 18, amount = 0.5, color: col = "#ffffff" } = {}) {
  const a = angle * Math.PI / 180, px = Math.cos(a), py = -Math.sin(a);
  const xc = -bw + fract(t / period) * (W + 2 * bw);
  const band = layer("__shim");
  const g = band.createLinearGradient(xc - bw * px, H / 2 - bw * py, xc + bw * px, H / 2 + bw * py);
  g.addColorStop(0, rgba(col, 0)); g.addColorStop(0.5, rgba(col, clamp(amount))); g.addColorStop(1, rgba(col, 0));
  band.fillStyle = g; band.fillRect(0, 0, W, H);
  if (src) { band.globalCompositeOperation = "destination-in"; band.drawImage(src, 0, 0); }
  ctx.save(); ctx.globalCompositeOperation = "screen"; ctx.drawImage(band.canvas, 0, 0); ctx.restore();
}

// ───────────────────────── shapes ─────────────────────────
/** Hand-drawn polyline: points get seeded wobble; pass seed: step(t, 8) to make it "boil" 8× per second. */
export function wobblePath(ctx, pts, { amp = 2, seg: segLen = 18, seed = 1, close = false } = {}) {
  const P = close ? [...pts, pts[0]] : pts; let k = 0;
  ctx.beginPath();
  for (let i = 0; i < P.length - 1; i++) {
    const [x0, y0] = P[i], [x1, y1] = P[i + 1], n = Math.max(1, Math.ceil(Math.hypot(x1 - x0, y1 - y0) / segLen));
    for (let s = 0; s <= n; s++) {
      if (i > 0 && s === 0) continue;
      const u = s / n, x = lerp(x0, x1, u) + amp * hashS(seed, k, 1), y = lerp(y0, y1, u) + amp * hashS(seed, k, 2); k++;
      if (i === 0 && s === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
  }
  if (close) ctx.closePath();
}
/** Partial stroke of a polyline: draws the first u (0..1) of its length (for "drawing on" lines). */
export function strokePartial(ctx, pts, u) {
  const L = []; let tot = 0;
  for (let i = 1; i < pts.length; i++) { const l = Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]); L.push(l); tot += l; }
  let left = clamp(u) * tot; ctx.beginPath(); ctx.moveTo(pts[0][0], pts[0][1]);
  for (let i = 1; i < pts.length && left > 0; i++) { const f = Math.min(1, left / L[i - 1]); ctx.lineTo(lerp(pts[i - 1][0], pts[i][0], f), lerp(pts[i - 1][1], pts[i][1], f)); left -= L[i - 1]; }
  ctx.stroke();
}

// ───────────────────────── creative pack: particles ─────────────────────────
/**
 * Seeded particle field. Every particle's whole life — spawn, path, size, twinkle — is a pure function of t, so any
 * frame renders alone and 1 worker draws the same bytes as 3 (determinism.sh). `area` is a lib.box() (SAFE.action by
 * default); the field clips to it. modes:
 *   drift   slow dust with a sine sway; positions wrap inside area, so it loops seamlessly
 *   rise    embers: accelerate upward, fade in/out over each `life` s cycle (no seam — every cycle is identical)
 *   fall    confetti: coloured rectangles (colors, or a seeded harmony of color), rotating and swaying as they fall
 *   orbit   stardust ring around area's centre
 *   stream  points flowing along dir, fading in at the start and out at the end of each pass
 */
export function particles(ctx, t, { mode = "drift", n = 90, seed = 7, area = SAFE.action, size = [1.5, 4], speed = 26,
  life = 4, color: col = "#ffffff", colors, alpha = 0.65, dir = [0, -1], twinkle = 0.4, spread = 0.5, amp = 1 } = {}) {
  const A = area.x0 !== undefined ? area : box(area.x, area.y, area.x + area.w, area.y + area.h);   // box() or {x,y,w,h}
  const cs = colors || (mode === "fall" ? harmony(col, { count: 5, seed }) : [col]);
  const P = cached(`parts:${mode}:${seed}:${n}:${cs.join("")}`, () => Array.from({ length: n }, (_, i) => ({
    i, x0: A.x0 + hash(seed, i, 1) * A.w, y0: A.y0 + hash(seed, i, 2) * A.h,
    s: lerp(size[0], size[1], hash(seed, i, 3)), ph: hash(seed, i, 4) * TAU, v: 0.4 + 1.2 * hash(seed, i, 5),
    depth: hash(seed, i, 3), c: cs[i % cs.length],
  })));
  ctx.save();
  ctx.beginPath(); ctx.rect(A.x0, A.y0, A.w, A.h); ctx.clip();
  const L = Math.hypot(dir[0], dir[1]) || 1, dx = dir[0] / L, dy = dir[1] / L, px = -dy, py = dx;
  for (const p of P) {
    let x = p.x0, y = p.y0, a = alpha;
    if (mode === "drift") {
      x = A.x0 + fract((p.x0 - A.x0) / A.w + t * speed * 0.004 * p.v * dx) * A.w + Math.sin(t * 0.6 + p.ph) * 9 * amp;
      y = A.y0 + fract((p.y0 - A.y0) / A.h + t * speed * 0.004 * p.v * dy) * A.h + Math.cos(t * 0.5 + p.ph) * 6 * amp;
      x = clamp(x, A.x0, A.x1); y = clamp(y, A.y0, A.y1);
    } else if (mode === "rise" || mode === "fall") {
      const ph = fract(t / life + hash(seed, p.i, 9));
      const u = mode === "rise" ? ph * ph * (3 - 2 * ph) : ph;                     // embers accelerate as they rise
      y = mode === "rise" ? A.y1 + 20 - u * (A.h + 40) : A.y0 - 40 + u * (A.h + 80);
      x = p.x0 + Math.sin(ph * 6 + p.ph) * 26 * spread * amp;
      a = alpha * env(ph, 0, 1, 0.12, 0.22);
    } else if (mode === "orbit") {
      const ang = p.ph + t * speed / 300 * p.v + Math.sin(t * 0.5 + p.ph) * 0.1;
      const rr = Math.min(A.w, A.h) * 0.36 * (0.55 + 0.45 * p.depth) + Math.sin(t * 0.8 + p.ph * 3) * 8;
      x = A.cx + Math.cos(ang) * rr; y = A.cy + Math.sin(ang) * rr * 0.62;
    } else {                                                                        // stream
      const along = fract(t * speed / 400 * p.v + hash(seed, p.i, 7));
      const off = (hash(seed, p.i, 6) - 0.5) * Math.min(A.w, A.h) * spread;
      const travel = (along - 0.5) * Math.hypot(A.w, A.h) * 1.2;
      x = A.cx + px * off + dx * travel; y = A.cy + py * off + dy * travel;
      a = alpha * Math.sin(along * Math.PI);
    }
    if (twinkle > 0) a *= 1 - twinkle * (0.5 - 0.5 * Math.sin(t * (2 + p.depth * 3) + p.ph));
    if (a <= 0.004) continue;
    ctx.globalAlpha = clamp(a);
    if (mode === "fall") {
      ctx.save(); ctx.translate(x, y); ctx.rotate(p.ph + t * (1.2 + p.v) * (hash(seed, p.i, 8) < 0.5 ? 1 : -1));
      ctx.fillStyle = p.c; ctx.fillRect(-p.s * 1.6, -p.s * 0.8, p.s * 3.2, p.s * 1.6);
      ctx.restore();
    } else {
      ctx.fillStyle = p.c; ctx.beginPath(); ctx.arc(x, y, p.s, 0, TAU); ctx.fill();
    }
  }
  ctx.restore();
}

// ───────────────────────── creative pack: text markers ─────────────────────────
/**
 * Emphasis marks for one line of text (or any box — build one from a layout with
 * lib.box(lay.x0, lay.y - lay.ascent, lay.x1, lay.y + lay.descent)). mode: "highlight" (marker swipe behind the text —
 * draw it BEFORE the glyphs), "underline" (draw-on with a hand wobble baked in), "circle" (hand ellipse that draws on
 * and boils at 8 steps/s), "strike" (line through the middle), "brackets" (corner marks drawing on in rotation).
 * start / draw time the animation; hold ≥ 0 fades it out `hold` s after it lands.
 */
export function marker(ctx, box, t, { mode = "highlight", color: col = "#ffd400", start = 0, draw: dw = 0.35, hold = -1,
  seed = 4, width: lw = 9, inset = 8, alpha = 0.95, ease: e = ease.outCubic } = {}) {
  const p = easeOf(e)(clamp((t - start) / Math.max(1e-6, dw)));
  const out = hold >= 0 ? clamp(1 - (t - start - dw - hold) / 0.3) : 1;
  if (p <= 0 || out <= 0) return;
  const B = { x0: box.x0 - inset, y0: box.y0 - inset * 0.4, x1: box.x1 + inset, y1: box.y1 + inset * 0.6, w: box.w + 2 * inset, h: box.h + 1.6 * inset, cx: box.cx, cy: box.cy };
  ctx.save(); ctx.globalAlpha = alpha * out; ctx.strokeStyle = col; ctx.fillStyle = col;
  ctx.lineWidth = lw; ctx.lineCap = "round"; ctx.lineJoin = "round";
  if (mode === "highlight") {
    ctx.globalAlpha = alpha * out * 0.55;
    ctx.beginPath(); ctx.roundRect(B.x0, B.y0, B.w * p, B.h, Math.min(10, B.h / 4)); ctx.fill();
  } else if (mode === "underline") {
    ctx.lineWidth = Math.max(3, lw * 0.8);
    const y = B.y1;
    strokePartial(ctx, [[B.x0, y], [lerp(B.x0, B.x1, 0.3), y + 2.5], [lerp(B.x0, B.x1, 0.65), y - 2], [B.x1, y + 1]], p);
  } else if (mode === "circle") {
    const boil = seed + step(t, 8) * 97, pts = [];
    for (let k = 0; k <= 26; k++) {
      const a = (k / 26) * TAU - Math.PI / 2;
      pts.push([B.cx + Math.cos(a) * (B.w / 2 + 6) + hashS(boil, k) * 3, B.cy + Math.sin(a) * (B.h / 2 + 8) + hashS(boil, k + 50) * 3]);
    }
    ctx.lineWidth = Math.max(3, lw * 0.7);
    strokePartial(ctx, pts, p * 1.02);                                            // overlap the start so the loop closes
  } else if (mode === "strike") {
    ctx.lineWidth = Math.max(3, lw * 0.7);
    strokePartial(ctx, [[B.x0, box.cy], [B.x1, box.cy]], p);
  } else {                                                                        // brackets
    const L = Math.min(26, B.w * 0.22), k = clamp(p * 4);
    const corner = (x, y, sx, sy, q) => {
      if (k <= q) return; const u = clamp(k - q);
      ctx.beginPath(); ctx.moveTo(x + sx * L * Math.min(1, u * 2), y); ctx.lineTo(x, y); ctx.lineTo(x, y + sy * L * clamp(u * 2 - 1, 0, 1)); ctx.stroke();
    };
    corner(B.x0, B.y0, 1, 1, 0); corner(B.x1, B.y0, -1, 1, 1); corner(B.x1, B.y1, -1, -1, 2); corner(B.x0, B.y1, 1, -1, 3);
  }
  ctx.restore();
}

// ───────────────────────── transitions ─────────────────────────
// Each takes progress u (0→1; apply your own easing or pass `ease`) and two painters drawA(ctx) / drawB(ctx) that
// draw a FULL frame into the ctx they are given (a layer, not necessarily the main canvas).

/** Hard cut: A before u reaches 1 (or `at`), B after. */
export function cut(ctx, u, drawA, drawB, { at = 1 } = {}) { (u < at ? drawA : drawB)(ctx); }
/** Straight wipe. angle in degrees (0 = left→right, 90 = top→bottom); soft = edge feather px. */
export function wipe(ctx, u, drawA, drawB, { angle = 0, soft = 0, ease: e = ease.inOutCubic } = {}) {
  const p = easeOf(e)(clamp(u));
  if (p <= 0) return drawA(ctx);
  if (p >= 1) return drawB(ctx);
  drawA(ctx);
  const b = layer("__wipe_b"); drawB(b);
  const a = angle * Math.PI / 180, dx = Math.cos(a), dy = Math.sin(a);
  const half = (Math.abs(dx) * W + Math.abs(dy) * H) / 2 + soft;
  const pos = lerp(-half, half, p), cx = W / 2 + dx * pos, cy = H / 2 + dy * pos, s = Math.max(0.5, soft / 2);
  const g = b.createLinearGradient(cx - dx * s, cy - dy * s, cx + dx * s, cy + dy * s);
  g.addColorStop(0, "rgba(0,0,0,1)"); g.addColorStop(1, "rgba(0,0,0,0)");
  b.globalCompositeOperation = "destination-in"; b.fillStyle = g; b.fillRect(0, 0, W, H);
  ctx.save(); ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalAlpha = 1; ctx.globalCompositeOperation = "source-over"; ctx.drawImage(b.canvas, 0, 0); ctx.restore();
}
/**
 * Iris. mode "open": B grows inside a circle over A. mode "close": A shrinks into a circle over B (classic iris-out
 * to an end card). shape "circle" | "square"; feather in px.
 */
export function iris(ctx, u, drawA, drawB, { cx = W / 2, cy = H / 2, mode = "close", shape = "circle", feather = 0, ease: e = ease.inOutCubic } = {}) {
  const p = easeOf(e)(clamp(u));
  const R = Math.max(Math.hypot(cx, cy), Math.hypot(W - cx, cy), Math.hypot(cx, H - cy), Math.hypot(W - cx, H - cy)) + feather;
  const [under, over, r] = mode === "open" ? [drawA, drawB, p * R] : [drawB, drawA, (1 - p) * R];
  if (r <= 0.5) return under(ctx);
  if (r >= R) return over(ctx);
  under(ctx);
  const o = layer("__iris_over"); over(o);
  o.globalCompositeOperation = "destination-in";
  if (feather > 0 && shape === "circle") {
    const g = o.createRadialGradient(cx, cy, Math.max(0, r - feather), cx, cy, r);
    g.addColorStop(0, "rgba(0,0,0,1)"); g.addColorStop(1, "rgba(0,0,0,0)"); o.fillStyle = g; o.fillRect(0, 0, W, H);
  } else {
    o.fillStyle = "#000"; o.beginPath();
    if (shape === "square") o.rect(cx - r * 0.7071, cy - r * 0.7071, r * 1.4142, r * 1.4142); else o.arc(cx, cy, r, 0, TAU);
    o.fill();
  }
  ctx.save(); ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalAlpha = 1; ctx.globalCompositeOperation = "source-over"; ctx.drawImage(o.canvas, 0, 0); ctx.restore();
}
/**
 * Whip pan: A leaves and B arrives along dir with directional motion blur proportional to speed (sub-frame samples).
 * dir [1,0] = content moves right. samples "auto" = one sample per 3 px of smear (max 48); 1 = plain push. Pass duration (s) = the whip's real length so the blur
 * matches a `shutter` fraction of one frame.
 */
export function whip(ctx, u, drawA, drawB, { dir = [-1, 0], samples = "auto", shutter = 0.5, duration = 0.6, ease: e = ease.inOutQuart, dist } = {}) {
  const E = easeOf(e), p = E(clamp(u));
  if (u <= 0) return drawA(ctx);
  if (u >= 1) return drawB(ctx);
  const L = Math.hypot(dir[0], dir[1]) || 1, nx = dir[0] / L, ny = dir[1] / L, D = dist ?? (Math.abs(nx) * W + Math.abs(ny) * H);
  const A = offscreen("__whip_a", drawA), B = offscreen("__whip_b", drawB);
  const du = shutter / FPS / duration;                   // shutter window in u units (duration = whip length in s)
  const acc = layer("__whip_acc"); acc.fillStyle = "#000"; acc.fillRect(0, 0, W, H);
  const smear = Math.abs(E(clamp(u + du / 2)) - E(clamp(u - du / 2))) * D;   // blur length in px this frame
  const n = samples === "auto" ? clamp(Math.ceil(smear / 3), 1, 48) : Math.max(1, samples);
  for (let s = 0; s < n; s++) {
    const q = n === 1 ? p : E(clamp(u + (s / (n - 1) - 0.5) * du)), off = q * D;
    acc.globalAlpha = 1 / (s + 1);                       // running mean → equal weights
    const f = layer("__whip_f"); f.drawImage(A, nx * off, ny * off); f.drawImage(B, nx * (off - D), ny * (off - D));
    acc.drawImage(f.canvas, 0, 0);
  }
  ctx.save(); ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalAlpha = 1; ctx.globalCompositeOperation = "source-over"; ctx.drawImage(acc.canvas, 0, 0); ctx.restore();
}
/**
 * Sub-frame motion blur for anything: averages drawAt(t', ctx) over the shutter (fraction of a frame). Transparent
 * layers average correctly too: a sprite on a clear layer smears evenly, with no opaque first sample.
 */
export function motionBlur(ctx, t, drawAt, { samples = 8, shutter = 0.5 } = {}) {
  // a float16 accumulator where the browser has one (else 8-bit), so repeated blending doesn't drift in 8-bit rounding
  if (!_layers.has("__mb_acc")) { const c = document.createElement("canvas"); c.width = W; c.height = H; c.getContext("2d", { colorType: "float16" }); _layers.set("__mb_acc", c); }
  const acc = layer("__mb_acc");
  for (let s = 0; s < samples; s++) {
    const ts = t + (samples === 1 ? 0 : (s / (samples - 1) - 0.5) * shutter / FPS);
    const f = layer("__mb_f"); drawAt(ts, f);
    // running mean in premultiplied RGBA: acc · (1 − w) + f · w, w ≈ 1/(s+1) in 1/255 steps so both weights sum to 1
    // even in 8 bits. (source-over at 1/(s+1) only dims acc where f is opaque, so earlier samples stayed fully opaque
    // wherever later ones were transparent: a comet trail.)
    const k = Math.round(255 / (s + 1));
    if (s) { acc.globalCompositeOperation = "destination-in"; acc.globalAlpha = (255 - k) / 255; acc.fillRect(0, 0, acc.canvas.width, acc.canvas.height); }
    acc.globalCompositeOperation = "lighter"; acc.globalAlpha = k / 255; acc.drawImage(f.canvas, 0, 0);
  }
  ctx.save(); ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalAlpha = 1; ctx.drawImage(acc.canvas, 0, 0); ctx.restore();
}

// ───────────────────────── creative pack: transitions (2D) ─────────────────────────
// Four more full-frame A→B moves in the same shape as cut/wipe/iris/whip — all seeded, all pure in u.

/** Seeded block dissolve: cells of `cell` px flip from A to B in hash order (hard cells by design — the pixelly cut). */
export function dissolve(ctx, u, drawA, drawB, { seed = 1, cell = 26, ease: e = ease.inOutCubic } = {}) {
  const p = easeOf(e)(clamp(u));
  if (p <= 0) return drawA(ctx);
  if (p >= 1) return drawB(ctx);
  drawA(ctx);
  const B = layer("__diss_b"); drawB(B);
  ctx.save();
  ctx.beginPath();
  for (let j = 0, ny = Math.ceil(H / cell); j < ny; j++)
    for (let i = 0, nx = Math.ceil(W / cell); i < nx; i++)
      if (hash(seed, i, j) < p) ctx.rect(i * cell, j * cell, cell, cell);
  ctx.clip();
  ctx.drawImage(B.canvas, 0, 0);
  ctx.restore();
}
/** Push/slide: A leaves along dir while B enters from the opposite edge (dir [1,0] = content moves right). */
export function push(ctx, u, drawA, drawB, { dir = [1, 0], ease: e = ease.inOutCubic } = {}) {
  const p = easeOf(e)(clamp(u));
  const Lh = Math.hypot(dir[0], dir[1]) || 1, nx = dir[0] / Lh, ny = dir[1] / Lh;
  const D = Math.abs(nx) * W + Math.abs(ny) * H;
  ctx.save(); ctx.translate(-nx * D * p, -ny * D * p); drawA(ctx); ctx.restore();
  ctx.save(); ctx.translate(nx * D * (1 - p), ny * D * (1 - p)); drawB(ctx); ctx.restore();
}
/**
 * Blinds: B appears in `bands` parallel strips at `angle` deg, band 0 leading and the rest staggered behind it
 * (stagger 0 = in phase, 1 = strictly sequential). The strips clip B over A — no blur, no layers beyond one.
 */
export function blinds(ctx, u, drawA, drawB, { bands = 7, angle = 0, stagger = 0.5, ease: e = ease.inOutCubic } = {}) {
  const p = easeOf(e)(clamp(u));
  if (p <= 0) return drawA(ctx);
  if (p >= 1) return drawB(ctx);
  drawA(ctx);
  const B = layer("__blinds_b"); drawB(B);
  const a = angle * Math.PI / 180, R = Math.hypot(W, H) / 2 + 2, bw = 2 * R / bands;
  ctx.save();
  ctx.translate(W / 2, H / 2); ctx.rotate(a);
  ctx.beginPath();
  for (let i = 0; i < bands; i++) {
    const pi = clamp(p * (1 + stagger) - (bands > 1 ? i / (bands - 1) : 0) * stagger, 0, 1);
    if (pi > 0) ctx.rect(-R, -R + i * bw, 2 * R, pi * bw);
  }
  ctx.clip();
  ctx.setTransform(1, 0, 0, 1, 0, 0);                                             // clip stays in device space; draw B unrotated
  ctx.drawImage(B.canvas, 0, 0);
  ctx.restore();
}
/**
 * Dip-through: the first half scales A up toward `zoom` while fading, the second half lands B from `zoom`. The
 * beat-cut move that never flashes — the frame passes through near-black instead of white.
 */
export function zoomDip(ctx, u, drawA, drawB, { zoom = 1.5, ease: e = ease.inOutCubic } = {}) {
  const p = easeOf(e)(clamp(u));
  if (p >= 1) return drawB(ctx);
  const first = p < 0.5, q = first ? p / 0.5 : (p - 0.5) / 0.5;
  const s = first ? 1 + (zoom - 1) * q : zoom - (zoom - 1) * q;
  ctx.save();
  ctx.translate(W / 2 * (1 - s), H / 2 * (1 - s)); ctx.scale(s, s);
  ctx.globalAlpha = first ? 1 - q : q;
  (first ? drawA : drawB)(ctx);
  ctx.restore();
}

// ───────────────────────── optional WebGL ─────────────────────────
const FRAG_HEAD = `#version 300 es
precision highp float;
in vec2 v_uv;
out vec4 outColor;
uniform vec2 u_res;
uniform float u_time;
uniform float u_frame;
uniform sampler2D u_tex0;
uniform sampler2D u_tex1;
`;
/**
 * Fullscreen fragment shader on an offscreen WebGL2 canvas. frag is GLSL ES 3.00 BODY (header with v_uv, outColor,
 * u_res, u_time, u_frame, u_tex0, u_tex1 is prepended unless frag starts with #version).
 * const fx = lib.shader(src);  … in renderAt: ctx.drawImage(fx.render(t, { u_amount: 0.4 }, { u_tex0: someCanvas }), 0, 0);
 * Uniform values: number → float, [a,b] / [a,b,c] / [a,b,c,d] → vecN. Textures are canvases or images (uploaded per call,
 * v_uv (0,0) = bottom-left like GLSL; textures are flipped so they read upright).
 */
export function shader(frag, { width = W, height = H } = {}) {
  const canvas = document.createElement("canvas"); canvas.width = width; canvas.height = height;
  const gl = canvas.getContext("webgl2", { preserveDrawingBuffer: true, premultipliedAlpha: false, antialias: false, alpha: true });
  if (!gl) throw new Error("WebGL2 unavailable in this renderer");
  const compile = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error("shader: " + gl.getShaderInfoLog(s)); return s; };
  const prog = gl.createProgram();
  gl.attachShader(prog, compile(gl.VERTEX_SHADER, `#version 300 es\nin vec2 p; out vec2 v_uv; void main(){ v_uv = p * 0.5 + 0.5; gl_Position = vec4(p, 0.0, 1.0); }`));
  gl.attachShader(prog, compile(gl.FRAGMENT_SHADER, frag.trimStart().startsWith("#version") ? frag : FRAG_HEAD + frag));
  gl.bindAttribLocation(prog, 0, "p"); gl.linkProgram(prog);
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error("shader link: " + gl.getProgramInfoLog(prog));
  const buf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  const vao = gl.createVertexArray(); gl.bindVertexArray(vao); gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
  const texs = {};
  const texFor = (name) => texs[name] || (texs[name] = (() => { const tx = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, tx); for (const [k, v] of [[gl.TEXTURE_MIN_FILTER, gl.LINEAR], [gl.TEXTURE_MAG_FILTER, gl.LINEAR], [gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE], [gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE]]) gl.texParameteri(gl.TEXTURE_2D, k, v); return tx; })());
  return {
    canvas, gl,
    render(t = 0, uniforms = {}, textures = {}) {
      gl.viewport(0, 0, width, height); gl.useProgram(prog); gl.bindVertexArray(vao);
      const U = (n) => gl.getUniformLocation(prog, n);
      gl.uniform2f(U("u_res"), width, height); gl.uniform1f(U("u_time"), t); gl.uniform1f(U("u_frame"), frame(t));
      for (const [n, v] of Object.entries(uniforms)) {
        const loc = U(n); if (!loc) continue;
        if (typeof v === "number") gl.uniform1f(loc, v);
        else if (Array.isArray(v)) gl[`uniform${v.length}fv`](loc, v);
      }
      let unit = 0;
      for (const [n, img] of Object.entries(textures)) {
        gl.activeTexture(gl.TEXTURE0 + unit); gl.bindTexture(gl.TEXTURE_2D, texFor(n));
        gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true); gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img);
        gl.uniform1i(U(n), unit); unit++;
      }
      gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT); gl.drawArrays(gl.TRIANGLES, 0, 3);
      return canvas;
    },
  };
}

// ───────────────────────── creative pack: GLSL transitions ─────────────────────────
// Full-frame per-pixel A→B transitions, driven by progress u (0→1) — the same family as wipe/iris/whip, but every
// pixel decides for itself. They run on the offscreen WebGL2 canvas from shader() (u_tex0 = A, u_tex1 = B, already in
// the shader header); the delivery renderer's software Chrome draws them with SwiftShader, which is deterministic —
// the same bytes per run on the same machine (determinism.sh checks 1 worker against 3). Half-size FX canvases
// upscale cleanly when a scene needs the speed: shaderTransition(name, { width: W / 2, height: H / 2 }).

const GLSL_PRELUDE = `uniform float u;        // transition progress 0..1
uniform float u_seed;     // seeded variation
float th(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float tn(vec2 p){ vec2 i = floor(p), f = fract(p); vec2 s = f * f * (3.0 - 2.0 * f);
  return mix(mix(th(i), th(i + vec2(1.0, 0.0)), s.x), mix(th(i + vec2(0.0, 1.0)), th(i + vec2(1.0, 1.0)), s.x), s.y); }
`;

const GLSL_TRANSITIONS = {
  // Noise-threshold dissolve with a glowing edge riding the burn front.
  dissolve: `
void main(){
  vec2 p = v_uv * vec2(u_res.x / u_res.y, 1.0) * 6.0 + vec2(u_seed * 13.7, u_seed * 7.3);
  float n = tn(p) * 0.62 + tn(p * 2.9 + 17.0) * 0.38;
  float th0 = -0.08 + u * 1.16;
  float m = 1.0 - smoothstep(th0 - 0.07, th0 + 0.07, n);
  vec3 col = mix(texture(u_tex0, v_uv).rgb, texture(u_tex1, v_uv).rgb, m);
  float edge = (1.0 - smoothstep(0.0, 0.09, abs(n - th0))) * step(0.001, u) * step(u, 0.999);
  col += edge * 0.55 * vec3(1.0, 0.78, 0.42);
  outColor = vec4(col, 1.0);
}`,
  // Digital glitch: per-band displacement + RGB split + scanline flutter, bands landing on B at their own thresholds.
  glitch: `
void main(){
  float bands = 22.0;
  float yb = floor(v_uv.y * bands);
  float sq = floor(u * 9.0);
  float g = tn(vec2(yb * 7.31 + u_seed * 3.0, sq));
  float amt = smoothstep(0.0, 0.25, u) * (1.0 - smoothstep(0.75, 1.0, u));
  float shift = (g - 0.5) * 0.3 * amt;
  float m = step(g * 0.96 + 0.02, u);
  vec2 uv = v_uv + vec2(shift, 0.0);
  float ca = amt * 0.012;
  vec3 col = mix(texture(u_tex0, uv).rgb, texture(u_tex1, uv).rgb, m);
  col.r = mix(texture(u_tex0, uv + vec2(ca, 0.0)).r, texture(u_tex1, uv + vec2(ca, 0.0)).r, m);
  col.b = mix(texture(u_tex0, uv - vec2(ca, 0.0)).b, texture(u_tex1, uv - vec2(ca, 0.0)).b, m);
  float sl = 0.85 + 0.15 * th(vec2(v_uv.y * u_res.y * 0.7, sq));
  col *= mix(1.0, sl, amt);
  outColor = vec4(col, 1.0);
}`,
  // Dolly-through: both ends zoom the same way (A recedes, B arrives), radial smear + chromatic fringing mid-move.
  zoomBlur: `
void main(){
  vec2 c = v_uv - 0.5;
  float za = 1.0 + 0.5 * u;
  float zb = 1.5 - 0.5 * u;
  float m = smoothstep(0.3, 0.7, u);
  float blur = 0.09 * (1.0 - abs(2.0 * u - 1.0));
  vec3 acc = vec3(0.0);
  for (int i = 0; i < 6; i++) {
    float f = float(i) / 5.0;
    vec3 a = texture(u_tex0, c / (za * (1.0 - blur * f)) + 0.5).rgb;
    vec3 b = texture(u_tex1, c / (zb * (1.0 - blur * f)) + 0.5).rgb;
    acc += mix(a, b, m);
  }
  vec3 col = acc / 6.0;
  float ca = 0.006 * (1.0 - abs(2.0 * u - 1.0));
  col.r = mix(texture(u_tex0, c / (za * (1.0 + ca)) + 0.5).r, texture(u_tex1, c / (zb * (1.0 + ca)) + 0.5).r, m);
  col.b = mix(texture(u_tex0, c / (za * (1.0 - ca)) + 0.5).b, texture(u_tex1, c / (zb * (1.0 - ca)) + 0.5).b, m);
  outColor = vec4(col, 1.0);
}`,
  // Kaleidoscope fold: B arrives through six mirrored sectors that rotate open over the move.
  kaleido: `
void main(){
  vec2 c = v_uv - 0.5;
  c.x *= u_res.x / u_res.y;
  float r = length(c), a = atan(c.y, c.x);
  float seg = 3.14159265 / 3.0;
  float fold = abs(mod(a + u * 2.2 + u_seed, seg) - seg * 0.5) * 2.0 / seg;
  float rb = mix(r, fold * r * 1.15 + 0.05, u);
  float ab = mix(a, fold * 3.14159265 + u * 0.8, u);
  vec2 uvb = vec2(cos(ab), sin(ab)) * rb;
  uvb.x /= u_res.x / u_res.y;
  vec3 col = mix(texture(u_tex0, v_uv).rgb, texture(u_tex1, uvb + 0.5).rgb, smoothstep(0.25, 0.75, u));
  col *= 0.85 + 0.15 * sin(r * 40.0 - u * 6.0);
  outColor = vec4(col, 1.0);
}`,
  // Shockwave: a refracting ring expands from the centre; B shows inside the front, with a bright rim.
  shockwave: `
void main(){
  vec2 c = v_uv - 0.5;
  c.x *= u_res.x / u_res.y;
  float r = length(c);
  float R = u * 1.3;
  float d = (r - R) / 0.10;
  float ring = exp(-d * d);
  float inside = smoothstep(R - 0.10, R + 0.10, r);
  vec2 dir = r > 0.0001 ? c / r : vec2(0.0);
  vec2 uvB = clamp(v_uv - dir * ring * 0.05 * vec2(u_res.y / u_res.x, 1.0), vec2(0.0), vec2(1.0));
  vec3 col = mix(texture(u_tex1, uvB).rgb, texture(u_tex0, v_uv).rgb, inside);
  float glow = smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.8, 1.0, u));
  col += ring * (0.15 + 0.4 * glow) * vec3(1.0, 0.9, 0.7);
  outColor = vec4(col, 1.0);
}`,
  // Analog light leak: a ragged warm front sweeps left→right, revealing B behind the light.
  lightLeak: `
void main(){
  float rag = tn(vec2(v_uv.y * 24.0, u_seed + floor(u * 20.0))) * 0.05;
  float front = u * 1.3 - 0.15 + rag;
  float d = v_uv.x - front;
  float m = smoothstep(0.06, -0.06, d);
  vec3 col = mix(texture(u_tex0, v_uv).rgb, texture(u_tex1, v_uv).rgb, m);
  float e = d / 0.10;
  float band = exp(-e * e) * smoothstep(0.0, 0.1, u) * (1.0 - smoothstep(0.9, 1.0, u));
  col += band * 0.85 * vec3(1.0, 0.62, 0.25) + band * band * 0.4 * vec3(1.0, 0.8, 0.5);
  outColor = vec4(col, 1.0);
}`,
  // Warping morph: both scenes smear through a travelling noise warp that peaks mid-transition.
  warpMorph: `
void main(){
  float k = sin(u * 3.14159265);
  vec2 w = vec2(tn(v_uv * 5.0 + u_seed), tn(v_uv * 5.0 + 31.0 + u_seed)) - 0.5;
  vec2 uv = v_uv + w * k * 0.18;
  float m = smoothstep(0.1, 0.9, u + (tn(v_uv * 3.0 + 7.0) - 0.5) * 0.2);
  vec3 col = mix(texture(u_tex0, uv).rgb, texture(u_tex1, uv).rgb, m);
  col += (w.x + w.y) * k * 0.15;
  outColor = vec4(col, 1.0);
}`,
};

/** The ready-made GLSL transition names (lib.shaderTransition accepts any of these). */
export const SHADER_TRANSITIONS = Object.keys(GLSL_TRANSITIONS);

/**
 * A named GLSL transition as a one-liner: const fx = lib.shaderTransition("dissolve"); then inside renderAt,
 * ctx.drawImage(fx.render(u, canvasA, canvasB), 0, 0). u is the raw 0..1 progress (ease it yourself or let the scene
 * tween it); canvasA/canvasB are full-frame sources (offscreen() is the usual way to make them). Compiles once and is
 * cached per name+size. extra uniforms (u_seed, or a transition's own knobs) go in the third argument.
 */
export function shaderTransition(name, { width = W, height = H } = {}) {
  const body = GLSL_TRANSITIONS[name];
  if (!body) throw new Error(`shaderTransition: unknown '${name}' (have: ${SHADER_TRANSITIONS.join(", ")})`);
  const fx = cached(`sTrans:${name}:${width}x${height}`, () => shader(GLSL_PRELUDE + body, { width, height }));
  return {
    render(u, texA, texB, extra = {}) {
      const p = clamp(u);
      return fx.render(p, { u: p, u_seed: 1, ...extra }, { u_tex0: texA, u_tex1: texB });
    },
  };
}
