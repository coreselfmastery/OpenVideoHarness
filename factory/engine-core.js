// groq-film-factory · engine-core — the page-contract film engine (engines/CONTRACT.md of OpenVideoHarness).
// Every frame is a pure function of t: no Math.random, no Date, no performance.now, no state carried
// between frames. All randomness comes from hash(i)/noise1(x), so the same t always draws the same
// picture — the determinism gate (bin/vh determinism) and render-split's two-half render rely on it.
//
// The film is data: film.json (palette, scenes, timing knobs) + audio/timeline.en.json (the narration
// lines, as bin/vh tts writes them). Sound sets the picture's length: shots are cut on the lines.

(function () {
"use strict";

// ───────────────────────────────────────────── numbers & easing
const TAU = Math.PI * 2;
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a, b, u) => a + (b - a) * u;
const seg = (t, a, b) => (b > a ? clamp((t - a) / (b - a)) : t >= b ? 1 : 0);      // 0 until a, 1 from b
const eOut = (u) => 1 - Math.pow(1 - clamp(u), 3);
const eIn = (u) => Math.pow(clamp(u), 3);
const eInOut = (u) => { u = clamp(u); return u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2; };
const eSine = (u) => (1 - Math.cos(Math.PI * clamp(u))) / 2;
const eOutBack = (u, s = 1.7) => { u = clamp(u); return 1 + (s + 1) * Math.pow(u - 1, 3) + s * Math.pow(u - 1, 2); };
const show = (t, at, d = 0.4) => eOut(seg(t, at, at + d));
const win = (t, a, b, fi = 0.4, fo = 0.4) => Math.min(eOut(seg(t, a, a + fi)), 1 - eIn(seg(t, b - fo, b)));

// randomness that is the same for the same arguments (hard rule 1)
const hash = (i) => { const s = Math.sin(i * 127.1 + 311.7) * 43758.5453; return s - Math.floor(s); };
const hash2 = (i, j) => hash(i * 7.31 + j * 157.7);
const noise1 = (x) => { const i = Math.floor(x), f = x - i; return lerp(hash(i), hash(i + 1), f * f * (3 - 2 * f)); };
const noise2 = (x, y) => noise1(x + 37.19 * y);
const r3 = (x) => Math.round(x * 1000) / 1000;
const isNum = (x) => typeof x === "number" && Number.isFinite(x);

// ───────────────────────────────────────────── state
let FILM = null;            // film.json
let W = 1920, H = 1080;      // CSS px (the canvas is W×H at devicePixelRatio)
let PR = 1;                 // the device pixel ratio frame() re-applies after every reset
let X = null;                // the 2D context
let DUR = 0;                 // the film's length, s
let LINES = {}, LINE_IDS = [];
let SHOT_T = [], SHOT = null;      // the cut list; the shot being drawn
let CAPS = [];                     // caption cards [{text, start, end, lines:[...]}]
let CHAPTER_T = [];                // [{t, title}]
let COVER_T = [];                  // [{id, t, title, cam}]
let CUES = [];                     // [{id, ref, t}]
let TIMELINE_FILE = null;
let REC = null;                    // the events/reads recorder while sampling
let EVENTS = [], TEXTS = [];
let FONT_MISSING = [];

// palette + fonts resolved once (with defaults so a broken film.json still renders)
const PAL = {};
const FONTS = { display: "Archivo Black", body: "Inter", serif: "Fraunces", mono: "JetBrains Mono" };
function resolvePalette(p) {
  const d = {
    bg0: "#070B14", bg1: "#0D1526", ink: "#F4F1EA", dim: "#8A94A6",
    accent: "#38BDF8", accent2: "#818CF8", ok: "#34D399", bad: "#F87171",
    grad: ["#070B14", "#0E1B33", "#0A2540"],
  };
  Object.assign(PAL, d, p || {});
  if (!Array.isArray(PAL.grad) || PAL.grad.length < 2) PAL.grad = d.grad;
  PAL.rgb = {}; for (const k of ["ink", "dim", "accent", "accent2", "ok", "bad"]) {
    const m = /^#([0-9a-f]{6})$/i.exec(String(PAL[k] || "")); if (!m) continue;
    PAL.rgb[k] = [parseInt(m[1].slice(0, 2), 16), parseInt(m[1].slice(2, 4), 16), parseInt(m[1].slice(4, 6), 16)];
  }
  // the broad centre lift: a lightened grad[1] wash that keeps the middle of the frame
  // above blackdetect's floor (bin/vh check: under 2% of pixels over luma 25 = black)
  const m1 = /^#([0-9a-f]{6})$/i.exec(String(PAL.grad[1] || ""));
  if (m1) {
    let [r, g, b] = [parseInt(m1[1].slice(0, 2), 16), parseInt(m1[1].slice(2, 4), 16), parseInt(m1[1].slice(4, 6), 16)];
    const y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    const k = y > 1 ? 58 / y : 2.5;                 // lift grad[1] to luma ≈ 58
    r = Math.min(255, Math.round(r * k)); g = Math.min(255, Math.round(g * k)); b = Math.min(255, Math.round(b * k));
    PAL.lift = [r, g, b];
  } else {
    PAL.lift = [70, 84, 120];
  }
}
function rgba(name, a) {
  const c = PAL.rgb[name] || [255, 255, 255];
  return `rgba(${c[0]},${c[1]},${c[2]},${a})`;
}

// ───────────────────────────────────────────── text
// font stacks by role; the sizes are CSS px and never under the 44 px floor (FILM.minText)
const F = {
  kick:   (s = 46) => `700 ${s}px ${FONTS.body}, sans-serif`,
  body:   (s = 48, w = 400) => `${w} ${s}px ${FONTS.body}, sans-serif`,
  bold:   (s = 64) => `800 ${s}px ${FONTS.body}, sans-serif`,
  display:(s = 120) => `400 ${s}px ${FONTS.display}, sans-serif`,
  serif:  (s = 84) => `italic 600 ${s}px ${FONTS.serif}, serif`,
  mono:   (s = 64, w = 500) => `${w} ${s}px ${FONTS.mono}, monospace`,
};
function setFont(f) { X.font = f; }
function tw(s) { return X.measureText(String(s)).width; }
function wrap(s, maxW, maxLines = 3) {   // greedy wrap on spaces; hard-split a word wider than maxW
  const out = []; let line = "";
  for (const w of String(s).split(/\s+/).filter(Boolean)) {
    const t = line ? line + " " + w : w;
    if (tw(t) <= maxW || !line) { if (tw(t) > maxW && !line && tw(w) > maxW) { /* one long word */ }
      line = t; if (tw(w) > maxW) { out.push(line); line = ""; } }
    else { out.push(line); line = w; }
  }
  if (line) out.push(line);
  if (out.length > maxLines) { const keep = out.slice(0, maxLines - 1); const last = out.slice(maxLines - 1).join(" ");
    keep.push(last); return keep; }
  return out;
}
function fitFont(s, role, size, maxW, maxLines, minSize = 44) {  // shrink until the text fits maxLines of maxW
  let sz = size;
  while (sz > minSize) { setFont(role(sz)); const ls = wrap(s, maxW, maxLines); if (ls.length <= maxLines) return { size: sz, lines: ls }; sz = Math.max(minSize, sz - 4); }
  setFont(role(sz)); return { size: sz, lines: wrap(s, maxW, maxLines) };
}
function drawLines(lines, cx, y, lh, fill, align = "center") {  // centered block starting at top y
  X.textAlign = align === "center" ? "center" : align; X.textBaseline = "top"; X.fillStyle = fill;
  lines.forEach((ln, i) => X.fillText(ln, cx, y + i * lh));
}
function read(text, start, end) { if (REC && text) REC.reads.push({ text: String(text), start: r3(start), end: r3(end) }); }
function event(kind, t, x, dur) { if (REC && SHOT) REC.events.push({ t: r3(t), kind, shot: SHOT.id, x: Math.round(x ?? W / 2), ...(dur ? { dur } : {}) }); }

// ───────────────────────────────────────────── backgrounds (palette-driven, deterministic)
let GRAIN = null;   // precomputed noise tiles, built once in ready
function buildGrain() {
  GRAIN = [];
  for (let v = 0; v < 4; v++) {
    const c = document.createElement("canvas"); c.width = c.height = 160;
    const g = c.getContext("2d"), im = g.createImageData(160, 160), d = im.data;
    for (let i = 0; i < d.length; i += 4) { const n = Math.floor(hash(i * 0.217 + v * 53.7) * 255); d[i] = d[i + 1] = d[i + 2] = n; d[i + 3] = 255; }
    g.putImageData(im, 0, 0); GRAIN.push(c);
  }
}
function grain(t, amt) {
  if (!amt || !GRAIN) return;
  X.save(); X.globalAlpha = amt; X.globalCompositeOperation = "overlay";
  const k = Math.floor(t * 30) % GRAIN.length, ox = Math.floor(hash(k * 3.1) * 160), oy = Math.floor(hash(k * 7.9) * 160);
  for (let y = -oy; y < H; y += 160) for (let x = -ox; x < W; x += 160) X.drawImage(GRAIN[k], x, y);
  X.restore();
}
function bgWash(t, drift = 1) {   // the base: 3 drifting radial gradients, a screen-blend lift, a deep vignette
  const g = PAL.grad, u = t * 0.011 * drift;
  X.fillStyle = PAL.bg0; X.fillRect(0, 0, W, H);
  const blobs = [
    [W * (0.22 + 0.10 * noise1(u)), H * (0.28 + 0.12 * noise1(u + 9.2)), Math.max(W, H) * 0.75, g[1], 0.92],
    [W * (0.80 + 0.08 * noise1(u + 3.7)), H * (0.20 + 0.10 * noise1(u + 5.1)), Math.max(W, H) * 0.65, g[2] || g[1], 0.85],
    [W * (0.62 + 0.12 * noise1(u + 8.3)), H * (0.85 + 0.08 * noise1(u + 1.9)), Math.max(W, H) * 0.70, g[1], 0.6],
  ];
  for (const [x, y, r, col, a] of blobs) {
    const gr = X.createRadialGradient(x, y, 0, x, y, r);
    gr.addColorStop(0, col); gr.addColorStop(1, "rgba(0,0,0,0)");
    X.globalAlpha = a; X.fillStyle = gr; X.fillRect(0, 0, W, H);
  }
  X.globalAlpha = 1;
  // the lift, ON TOP of the blobs with screen blending: adds light without flattening
  // the gradient composition. Keeps the middle of the frame above blackdetect's floor
  // (bin/vh check: a run with under 2% of pixels over luma 25 reads as black).
  const [lr, lg, lb] = PAL.lift;
  X.globalCompositeOperation = "screen";
  const lift = X.createRadialGradient(W / 2, H * 0.46, 0, W / 2, H * 0.46, Math.max(W, H) * 0.72);
  lift.addColorStop(0, `rgba(${lr},${lg},${lb},0.50)`);
  lift.addColorStop(0.60, `rgba(${lr},${lg},${lb},0.30)`);
  lift.addColorStop(1, "rgba(0,0,0,0)");
  X.fillStyle = lift; X.fillRect(0, 0, W, H);
  X.globalCompositeOperation = "source-over";
  const v = X.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.40, W / 2, H / 2, Math.max(W, H) * 0.80);
  v.addColorStop(0, "rgba(0,0,0,0)"); v.addColorStop(1, "rgba(0,0,0,0.40)");
  X.fillStyle = v; X.fillRect(0, 0, W, H);
}
function bgParticles(t, n = 80, spread = 1, alpha = 1) {   // the drifting field (hash-seeded positions)
  for (let i = 0; i < n; i++) {
    const sp = 0.5 + hash(i * 1.7) * 1.6;
    const x = W * (hash(i) * 1.3 - 0.15) + 60 * noise1(t * 0.05 * sp + i * 3.3) - 30;
    const y = H * (hash(i * 2.3) * 1.3 - 0.15) + 60 * noise1(t * 0.045 * sp + i * 7.1) - 30;
    const r = 1.2 + hash(i * 3.1) * 2.6, big = hash(i * 5.9) > 0.93;
    const a = (big ? 0.34 : 0.12 + hash(i * 4.7) * 0.13) * alpha;
    X.beginPath(); X.arc(x, y, big ? r * 1.9 : r, 0, TAU);
    X.fillStyle = hash(i * 6.1) > 0.72 ? rgba("accent", a) : (hash(i * 6.1) > 0.4 ? rgba("accent2", a) : `rgba(244,241,234,${a})`);
    X.fill();
  }
}
function bgGrid(t, alpha = 0.05) {   // the slow parallax grid
  X.save(); X.strokeStyle = `rgba(244,241,234,${alpha})`; X.lineWidth = 1;
  const step = 96, off = (t * 6) % step;
  for (let x = -step + off; x < W + step; x += step) { X.beginPath(); X.moveTo(x, 0); X.lineTo(x, H); X.stroke(); }
  for (let y = -step + ((t * 3.5) % step); y < H + step; y += step) { X.beginPath(); X.moveTo(0, y); X.lineTo(W, y); X.stroke(); }
  X.restore();
}
function lightSweep(t, at, dur = 0.9, alpha = 0.10) {   // one diagonal band of light, once
  const u = seg(t, at, at + dur); if (u <= 0 || u >= 1) return;
  const x = lerp(-500, W + 500, eInOut(u));
  X.save(); X.globalCompositeOperation = "screen"; X.translate(x, 0); X.rotate(-0.28);
  const g = X.createLinearGradient(-160, 0, 160, 0);
  g.addColorStop(0, "rgba(255,255,255,0)"); g.addColorStop(0.5, `rgba(255,255,255,${alpha})`); g.addColorStop(1, "rgba(255,255,255,0)");
  X.fillStyle = g; X.fillRect(-160, -H, 320, H * 3); X.restore();
}
function underline(cx, y, w, u, color, h = 10) {   // the accent bar that sweeps in
  const ww = w * eInOut(u);
  X.fillStyle = color; X.fillRect(cx - ww / 2, y, ww, h);
}

// ───────────────────────────────────────────── the narration model (bin/vh tts timeline)
const letters = (s) => String(s).normalize("NFKC").replace(/[\s\p{P}\p{S}]/gu, "").toLowerCase();
function initTimeline(tl, problems) {
  (Array.isArray(tl.segments) ? tl.segments : []).forEach((s, i) => {
    if (!s || !s.id || !isNum(s.start) || !isNum(s.end)) return problems.push(`timeline line ${i + 1}: no id, start or end`);
    if (LINES[s.id]) return problems.push(`timeline line ${i + 1}: the id ${s.id} is used twice`);
    const words = (s.words || []).filter((w) => w && isNum(w.start));
    LINES[s.id] = {
      id: s.id, a: s.start, b: s.end, text: String(s.text ?? s.en ?? s.zh ?? ""),
      words: words.map((w) => ({ w: String(w.w ?? ""), a: w.start, b: isNum(w.end) ? w.end : w.start })),
    };
    LINE_IDS.push(s.id);
  });
  if (!LINE_IDS.length) problems.push("the timeline has no lines (segments)");
}
// when each word of a line is spoken: even spread for line-level providers (edge), else the aligned words
function wordTimes(L) {
  const ws = String(L.text).split(/\s+/).filter(Boolean);
  if (!ws.length) return [];
  if (L.words.length >= Math.max(2, Math.floor(ws.length * 0.6))) {
    return L.words.map((w) => ({ w: w.w, a: w.a, b: w.b }));
  }
  const totalChars = ws.reduce((n, w) => n + w.length + 1, 0); let acc = 0;
  return ws.map((w) => { const a = L.a + (L.b - L.a) * (acc / totalChars); acc += w.length + 1;
    const b = L.a + (L.b - L.a) * (acc / totalChars); return { w, a, b }; });
}

// ───────────────────────────────────────────── shots: the cut list, built from film.json × the timeline
function buildShots(problems) {
  const scenes = Array.isArray(FILM.scenes) ? FILM.scenes : [];
  const byLine = new Map(scenes.map((s) => [s.line || null, s]));
  const intro = scenes.find((s) => !s.line && (s.at === undefined || s.at === "start"));
  const outro = scenes.find((s) => !s.line && s.at === "end");
  SHOT_T = [];
  // the intro card runs until the first line speaks (the timeline's starts already carry --lead)
  const first = LINE_IDS.length ? LINES[LINE_IDS[0]].a : (isNum(FILM.lead) ? FILM.lead : 0);
  if (first > 0.35) {
    SHOT_T.push({ a: 0, b: first, id: "intro", kind: intro ? intro.kind : "title", o: intro || byLine.get(LINE_IDS[0]) || { kind: "title" }, din: 0.5, dout: 0.4, tin: "cross" });
  }
  for (const id of LINE_IDS) {
    const L = LINES[id]; const sc = byLine.get(id);
    if (!sc) { problems.push(`no scene in film.json for narration line "${id}"`); continue; }
    SHOT_T.push({ a: L.a, b: L.b + (isNum(FILM.hang) ? FILM.hang : 0.15), id, kind: sc.kind || "statement", o: sc, din: 0.45, dout: 0.45, tin: "cross",
      chapter: sc.chapter || null });
  }
  // merge: never let a shot start before the previous ends (overlaps from trimmed silences)
  for (let i = 1; i < SHOT_T.length; i++) if (SHOT_T[i].a < SHOT_T[i - 1].b) SHOT_T[i].a = SHOT_T[i - 1].b;
  const last = SHOT_T.length ? SHOT_T[SHOT_T.length - 1].b : 0;
  const tail = isNum(FILM.tail) ? FILM.tail : 2.5;
  if (tail > 0.05) {
    const lastShot = SHOT_T[SHOT_T.length - 1];
    if (lastShot && lastShot.kind === "outro") {
      lastShot.b = last + tail;   // the o1 outro card holds through the tail (its pulse keeps breathing)
    } else {
      const o = outro || { kind: "outro" };   // explicit tail card, or a plain one
      SHOT_T.push({ a: last, b: last + tail, id: "outro", kind: o.kind || "outro", o, din: 0.5, dout: 0.6, tin: "cross" });
    }
  }
  if (SHOT_T.length) SHOT_T[SHOT_T.length - 1].b = Math.max(SHOT_T[SHOT_T.length - 1].b, DUR);
  if (!SHOT_T.length) problems.push("the film has no shots (no scenes, no lines)");
}
function shotAt(t) { let i = 0; while (i + 1 < SHOT_T.length && t >= SHOT_T[i + 1].a) i++; return i; }

function drawShot(i, t) {
  const S = SHOT_T[i], prev = SHOT; SHOT = { i, id: S.id, t0: S.a, t1: S.b, lt: t - S.a, u: seg(t, S.a, S.b), o: S.o, din: S.din, dout: S.dout };
  X.save();
  try {
    const z = lerp(1, 1.06, eSine(SHOT.u));   // the held picture never freezes: a slow camera push
    X.translate(W / 2, H / 2); X.scale(z, z); X.translate(-W / 2, -H / 2);
    const fn = SCENES[S.kind] || SCENES.statement;
    fn(t, SHOT);
  } finally { X.restore(); SHOT = prev; }
}
function crossFade(i, t) {   // the transition: the old shot settles out, the new one settles in
  const S = SHOT_T[i], p = (t - S.a) / S.din;
  const prevI = i - 1;
  X.save(); X.globalAlpha = 1;
  try { X.globalAlpha = 1; drawShot(prevI, S.a + 0.001); } catch (e) {}
  X.restore();
  X.save(); X.globalAlpha = eInOut(p);
  try { drawShot(i, t); } catch (e) {}
  X.restore();
}
function picture(t) {
  const i = shotAt(t), S = SHOT_T[i];
  if (S.din > 0 && t - S.a < S.din && i > 0) crossFade(i, t);
  else drawShot(i, t);
  grain(t, isNum(FILM.grain) ? FILM.grain : 0.05);
}

// ───────────────────────────────────────────── captions + the interface
function buildCaptions() {
  CAPS = [];
  for (const id of LINE_IDS) {
    const L = LINES[id];
    if (L.o && L.o.nocap) continue;
    const text = L.text.replace(/\s+/g, " ").trim();
    if (!text) continue;
    const parts = splitCaptions(text);   // 1-2 cards per line, cut at punctuation / ~46 chars
    const wt = wordTimes(L); const chars = parts.reduce((n, p) => n + p.length, 0);
    let acc = 0;
    for (const p of parts) {
      const u0 = acc / chars; acc += p.length;
      const u1 = acc / chars;
      let a = lerp(L.a, L.b, u0), b = lerp(L.a, L.b, u1);
      const near = wt.find((w) => w.w && letters(p).startsWith(letters(w.w).slice(0, 3)));
      if (near) a = Math.min(a, near.a);
      CAPS.push({ text: p, start: a, end: b, line: id });
    }
  }
  // keep them apart, and let short cards breathe
  for (let i = 0; i < CAPS.length; i++) {
    const c = CAPS[i];
    if (i + 1 < CAPS.length) c.end = Math.min(c.end, CAPS[i + 1].start - 0.02);
    if (c.end - c.start < 1.0) c.end = Math.min(c.end + (1.0 - (c.end - c.start)), i + 1 < CAPS.length ? CAPS[i + 1].start - 0.02 : c.end + 2);
  }
}
function splitCaptions(text) {
  if (text.length <= 46) return [text];
  const cuts = [...text.matchAll(/[^.!?]+[.!?]*\s+/g)].map((m) => m[0].length);
  let acc = 0; const parts = [];
  const hardAt = (from) => {   // next wrap point near the middle
    let best = -1, lo = 1e9; const mid = text.length / 2;
    for (const c of cuts) { const at = acc + c; if (at >= 18 && at <= text.length - 12 && Math.abs(at - mid) < lo) { lo = Math.abs(at - mid); best = at; } }
    if (best > 0) return best;
    const sp = text.indexOf(" ", Math.floor(text.length * 0.45)); return sp > 0 ? sp + 1 : text.length;
  };
  let at = hardAt(0); parts.push(text.slice(0, at).trim()); parts.push(text.slice(at).trim());
  return parts.filter(Boolean).slice(0, 2);
}
function captionBand(t) {
  const c = CAPS.find((c) => t >= c.start && t < c.end);
  if (!c || !SHOT || SHOT.id === "intro") return;
  const a = eOut(seg(t, c.start, c.start + 0.28)), d = 1 - eIn(seg(t, c.end - 0.22, c.end));
  const al = Math.min(a, d); if (al <= 0.002) return;
  setFont(F.body(46, 600));
  const lines = wrap(c.text, 1500, 2);
  const lh = 62, y0 = H - 132 - (lines.length - 1) * lh;
  X.save(); X.globalAlpha = al * 0.55;
  for (let i = 0; i < lines.length; i++) {   // the soft plates behind each line (readable over anything)
    const w = tw(lines[i]);
    roundRect(W / 2 - w / 2 - 26, y0 + i * lh - 12, w + 52, 70, 16); X.fillStyle = "rgba(4,7,14,0.62)"; X.fill();
  }
  X.restore();
  X.save(); X.globalAlpha = al; drawLines(lines, W / 2, y0, lh, PAL.ink);
  X.restore();
}
function roundRect(x, y, w, h, r) { X.beginPath(); X.moveTo(x + r, y); X.arcTo(x + w, y, x + w, y + h, r); X.arcTo(x + w, y + h, x, y + h, r); X.arcTo(x, y + h, x, y, r); X.arcTo(x, y, x + w, y, r); X.closePath(); }
function chapterBar(t) {
  const bar = isNum(FILM.barFrom) ? FILM.barFrom : (CHAPTER_T.length ? CHAPTER_T[0].t : 0);
  if (t < bar) return;
  const y = H - 8, u = clamp((t - bar) / Math.max(0.001, DUR - bar));
  X.fillStyle = "rgba(244,241,234,0.12)"; X.fillRect(0, y, W, 4);
  X.fillStyle = PAL.accent; X.fillRect(0, y, W * u, 4);
  for (const c of CHAPTER_T) { if (c.t > bar && c.t < DUR - 1) { X.fillStyle = "rgba(4,7,14,0.9)"; X.fillRect(c.t / DUR * W - 2, y - 3, 4, 10); } }
}
function shade(a) { if (a <= 0.002) return; X.fillStyle = `rgba(0,0,0,${clamp(a, 0, 1)})`; X.fillRect(0, 0, W, H); }

// the interface's boxes at t (engines/CONTRACT.md ui(t) — bin/vh textcheck looks through them)
function uiBoxes(t) {
  const out = [];
  out.push({ name: "bar", box: [0, H - 12, W, H] });
  const c = CAPS.find((c) => t >= c.start && t < c.end);
  if (c && SHOT && SHOT.id !== "intro") { setFont(F.body(46, 600)); const lines = wrap(c.text, 1500, 2);
    const lh = 62, y0 = H - 132 - (lines.length - 1) * lh; let x0 = 1e9, x1 = 0;
    for (const ln of lines) { const w = tw(ln); x0 = Math.min(x0, W / 2 - w / 2 - 26); x1 = Math.max(x1, W / 2 + w / 2 + 26); }
    out.push({ name: "caption", box: [r3(x0), r3(y0 - 12), r3(x1), r3(y0 + (lines.length - 1) * lh + 58)] }); }
  return out;
}

// ───────────────────────────────────────────── the frame at t (the page contract)
function frame(t, o) {
  t = clamp(Number(t) || 0, 0, Math.max(0, DUR - 1e-6));
  X.setTransform(PR, 0, 0, PR, 0, 0);
  X.clearRect(0, 0, W, H);
  const scene = !!(o && o.layer === "scene");
  picture(t);
  if (!scene) { chapterBar(t); captionBand(t); }
  const fo = isNum(FILM.fadeOut) ? FILM.fadeOut : 0.6;
  const fi = isNum(FILM.fadeIn) ? FILM.fadeIn : 0.35;
  shade(Math.max(fi > 0 ? 1 - seg(t, 0, fi) : 0, fo > 0 ? seg(t, DUR - fo, DUR) : 0));
}
function draw(t, scene) {
  t = clamp(Number(t) || 0, 0, Math.max(0, DUR - 1e-6));
  X.setTransform(PR, 0, 0, PR, 0, 0);
  X.clearRect(0, 0, W, H);
  picture(t);
  if (!scene) { chapterBar(t); captionBand(t); }
  const fo = isNum(FILM.fadeOut) ? FILM.fadeOut : 0.6;
  const fi = isNum(FILM.fadeIn) ? FILM.fadeIn : 0.35;
  shade(Math.max(fi > 0 ? 1 - seg(t, 0, fi) : 0, fo > 0 ? seg(t, DUR - fo, DUR) : 0));
}

function buildChapters(problems) {
  CHAPTER_T = [];
  let n = 0;
  for (const S of SHOT_T) {   // a shot carries its chapter either as S.chapter or scene.o.chapter — once, not twice
    const ch = (S.chapter && S.chapter.title) ? S.chapter.title
             : (S.o && S.o.chapter && S.o.chapter.title) ? S.o.chapter.title : null;
    if (ch) CHAPTER_T.push({ t: r3(S.a), title: String(ch) });
  }
  if (!CHAPTER_T.length) {   // derived: a tick every ~30 s at the nearest shot start
    for (let t = 32; t < DUR - 20; t += 32) { const S = SHOT_T.find((s) => s.a >= t) || SHOT_T[SHOT_T.length - 1];
      if (S) CHAPTER_T.push({ t: r3(S.a), title: `Chapter ${++n}` }); }
  }
  CHAPTER_T.sort((a, b) => a.t - b.t);
}
function buildCovers() {
  const titleShot = SHOT_T.find((s) => s.id === "intro") || SHOT_T[0];
  const t = titleShot ? Math.min(titleShot.a + (titleShot.b - titleShot.a) * 0.55, DUR - 0.1) : 0.5;
  COVER_T = [{ id: "cover", t: r3(t), title: [FILM.title || ""], cam: { z: 1.06 } }];
  let n = 1;
  for (const c of CHAPTER_T.slice(1)) {
    const S = SHOT_T.find((s) => Math.abs(s.a - c.t) < 0.6) || SHOT_T[shotAt(c.t)];
    if (!S) continue;
    COVER_T.push({ id: `chapter-${n++}`, t: r3(Math.min(S.a + Math.min(1.6, (S.b - S.a) * 0.5), DUR - 0.1)), title: [c.title], cam: { z: 1.04 } });
  }
}
function cover(id) {
  const c = COVER_T.find((x) => x.id === String(id));
  if (!c) throw new Error(`engine: no cover "${id}"`);
  const t = clamp(c.t, 0, Math.max(0, DUR - 1e-6)), cam = c.cam || {};
  X.setTransform(PR, 0, 0, PR, 0, 0); X.clearRect(0, 0, W, H);
  X.save(); X.translate(W / 2 + (cam.x || 0), H / 2 + (cam.y || 0)); X.scale(cam.z || 1, cam.z || 1); X.translate(-W / 2, -H / 2);
  picture(t); X.restore();
  if (c.title && c.title.length) {   // a cover gets its title plate
    setFont(F.display(120)); const lines = wrap(c.title[0], 1600, 2); const lh = 140;
    const y0 = H / 2 - (lines.length - 1) * lh / 2 - 10;
    X.save(); X.globalAlpha = 0.72; X.fillStyle = "rgba(4,7,14,0.55)"; X.fillRect(0, y0 - 60, W, lines.length * lh + 90); X.restore();
    drawLines(lines, W / 2, y0, lh, PAL.ink);
  }
}

// ───────────────────────────────────────────── the record pass: texts/events by sampling every shot
function record() {
  REC = { events: [], reads: [], at: 0 };
  const fails = new Map();
  const P = Object.getPrototypeOf(X);
  const check = function (s) { if (!SHOT) return; const px = parseFloat((this.font.match(/([\d.]+)px/) || [])[1]) || 0;
    if (px < 44 - 0.5) console.error(`engine: text under the 44 px floor in shot ${SHOT.id}: "${String(s).slice(0, 30)}" ${Math.round(px)} px`); };
  X.fillText = function (s, ...a) { check.call(this, s); return P.fillText.call(this, s, ...a); };
  X.strokeText = function (s, ...a) { check.call(this, s); return P.strokeText.call(this, s, ...a); };
  try {
    for (const S of SHOT_T) for (const f of [0.05, 0.3, 0.55, 0.8, 0.97]) {
      const t = S.a + (S.b - S.a) * f;
      REC.at = t;
      try { drawShot(SHOT_T.indexOf(S), t); } catch (e) { if (!fails.has(S.id)) fails.set(S.id, `${t.toFixed(2)}s: ${e.message}`); }
    }
  } finally { delete X.fillText; delete X.strokeText; }
  const one = new Map();
  for (const e of REC.events) { const k = `${e.shot}|${e.kind}|${Math.round(e.t * 10)}`; if (!one.has(k)) one.set(k, e); }
  EVENTS = [...one.values()].concat(SHOT_T.slice(1).map((S) => ({ t: r3(S.a), kind: "cross", shot: S.id, x: Math.round(W / 2) })))
    .sort((p, q) => p.t - q.t);
  const seen = new Set();
  TEXTS = REC.reads.filter((r) => { const k = `${r.text}|${r.start}`; return !seen.has(k) && seen.add(k); }).sort((p, q) => p.start - q.start)
    .concat(CAPS.map((c) => ({ text: c.text, start: r3(c.start), end: r3(c.end), read: "subtitle" })));
  REC = null;
  if (fails.size) console.error(`engine: shots that throw: ${[...fails].map(([id, m]) => `${id} at ${m}`).join(" · ")}`);
}

// ───────────────────────────────────────────── boot
async function loadJSON(url) {
  const r = await fetch(url, { cache: "no-store" });
  if (!r.ok) throw new Error(`engine: no ${url} (HTTP ${r.status})`);
  return r.json();
}
async function loadFonts() {
  const want = [
    `400 100px ${FONTS.display}`, `400 100px ${FONTS.body}`, `600 100px ${FONTS.body}`, `800 100px ${FONTS.body}`,
    `italic 600 100px ${FONTS.serif}`, `500 100px ${FONTS.mono}`, `700 100px ${FONTS.mono}`,
  ];
  const got = await Promise.allSettled(want.map((f) => document.fonts.load(f)));
  FONT_MISSING = want.filter((_, i) => got[i].status === "rejected");
}
async function boot() {
  FILM = await loadJSON("film.json");
  if (FILM.fonts) Object.assign(FONTS, FILM.fonts);
  resolvePalette(FILM.palette);
  W = FILM.width || 1920; H = FILM.height || 1080;
  const cv = document.getElementById("film");
  const pr = window.devicePixelRatio || 1;
  cv.width = Math.round(W * pr); cv.height = Math.round(H * pr);
  cv.style.width = W + "px"; cv.style.height = H + "px";
  X = cv.getContext("2d");
  PR = pr;
  X.setTransform(pr, 0, 0, pr, 0, 0);
  await loadFonts();
  buildGrain();
  const tlFile = FILM.timeline === null ? null : (FILM.timeline || "audio/timeline.en.json");
  const tl = tlFile ? await loadJSON(tlFile) : null;
  TIMELINE_FILE = tlFile;
  const problems = [];
  if (tl) initTimeline(tl, problems);
  DUR = tl ? (isNum(tl.duration) ? tl.duration : Math.max(0, ...Object.values(LINES).map((L) => L.b))) + (isNum(FILM.tail) ? FILM.tail : 2.5)
           : (isNum(FILM.duration) ? FILM.duration : 0);
  if (!(DUR > 0)) throw new Error(`engine: the film has no length${problems.length ? ":\n  " + problems.slice(0, 8).join("\n  ") : ""}`);
  buildShots(problems);
  buildCaptions();
  buildChapters(problems);
  buildCovers();
  if (problems.length) throw new Error(`engine: ${problems.length} problem(s) in film.json × timeline:\n  ` + problems.slice(0, 8).join("\n  "));
  record();
  if (FONT_MISSING.length) console.error(`engine: fonts that did not load (drawn in fallback): ${FONT_MISSING.join(", ")}`);
  return true;
}
const READY = boot();
READY.catch(() => {});   // the host reports the rejection when it awaits ready

window.film = {
  width: 1920, height: 1080,
  get width_() { return W; },
  ready: READY,
  frame,
  get duration() { return DUR; },
  get texts() { return TEXTS; },
  get events() { return EVENTS; },
  get chapters() { return CHAPTER_T.map((c) => ({ t: c.t, title: c.title })); },
  get cues() { return CUES; },
  get covers() { return COVER_T.map((c) => ({ id: c.id, t: c.t, title: (c.title || []).join(" / ") })); },
  cover(id) { cover(id); },
  ui: uiBoxes,
  get timeline() { return TIMELINE_FILE; },
};

// export for the scenes module + tests
window.__engine = { clamp, lerp, seg, eOut, eIn, eInOut, eSine, eOutBack, show, win, hash, hash2, noise1, r3,
  get FILM() { return FILM; }, get PAL() { return PAL; }, get FONTS() { return FONTS; }, get X() { return X; }, get W() { return W; }, get H() { return H; },
  get SHOT_T() { return SHOT_T; }, get LINES() { return LINES; }, get LINE_IDS() { return LINE_IDS; }, get DUR() { return DUR; },
  F, setFont, tw, wrap, fitFont, drawLines, read, event, rgba, bgWash, bgParticles, bgGrid, lightSweep, underline,
  roundRect, wordTimes, SCENES_GET() { return SCENES; } };
const SCENES = {};
})();
