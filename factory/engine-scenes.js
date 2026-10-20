// groq-film-factory · engine-scenes — the eight scene kinds. Each is a pure function of (t, S):
// S = { i, id, t0, t1, lt (s into the shot), u (0..1), o (the scene's params from film.json) }.
// They draw through the core module (window.__engine), so this file holds only looks, no machinery.
(function () {
"use strict";
const E = window.__engine;
const SC = E.SCENES_GET();

// a shared opening for most scenes: the background stack with per-scene variety (hash of the shot id)
function backdrop(t, S, opts) {
  const o = Object.assign({ particles: 80, grid: 0.04, drift: 1 }, opts || {});
  E.bgWash(t, o.drift);
  const v = E.hash(String(S.id).length * 7.3 + S.i * 13.7);
  if (v > 0.62) E.bgGrid(t, o.grid);
  E.bgParticles(t, o.particles, 1, 1);
}

// ───────────────────────────────────────── 1. title — the hero card
SC.title = function (t, S) {
  const o = S.o || {}, lt = S.lt;
  backdrop(t, S, { particles: 110 });
  const kick = o.kick || "", lines = String(o.title || "Discipline").split("\n").slice(0, 3);
  const cx = E.W / 2;
  let y = E.H * 0.30;
  if (kick) {   // the kicker drops in first
    const a = E.show(lt, 0.10, 0.5);
    if (a > 0.002) {
      E.setFont(E.F.kick(48));
      E.X.save(); E.X.globalAlpha = a; E.X.translate(0, (1 - a) * -26);
      E.X.textAlign = "center"; E.X.textBaseline = "top";
      E.X.fillStyle = E.PAL.accent;
      E.X.fillText(kick.toUpperCase().split("").join("\u2009"), cx, y);   // letter-spaced
      E.X.restore();
      E.read(kick, S.t0 + 0.1, S.t0 + 1.6);
    }
    y += 96;
  }
  const fit = E.fitFont(lines.join(" "), (s) => E.F.display(s), 168, 1680, lines.length, 96);
  const lh = fit.size * 1.06;
  lines.forEach((ln, i) => {
    const at = 0.28 + i * 0.16;
    const a = E.show(lt, at, 0.62);
    if (a <= 0.002) return;
    E.setFont(E.F.display(fit.size));
    E.X.save(); E.X.globalAlpha = a;
    E.X.translate(0, (1 - E.eOutBack(a, 1.2)) * 70);
    E.X.textAlign = "center"; E.X.textBaseline = "top";
    const outline = o.outlineLine === i + 1 || (i === 1 && lines.length > 1 && o.outline !== false && !o.outlineLine);
    if (outline) {   // the second line as the accent outline — contrast without a second colour
      E.X.lineWidth = Math.max(3, fit.size * 0.028); E.X.strokeStyle = E.PAL.accent;
      E.X.strokeText(ln, cx, y + i * lh);
    } else {
      E.X.fillStyle = E.PAL.ink; E.X.fillText(ln, cx, y + i * lh);
    }
    E.X.restore();
  });
  const yEnd = y + lines.length * lh;
  const uU = E.seg(lt, 0.5 + lines.length * 0.16, 0.5 + lines.length * 0.16 + 0.55);   // the underline sweeps
  if (uU > 0) E.underline(cx, yEnd + 36, 560, uU, E.PAL.accent, 10);
  if (o.sub) {
    const a = E.show(lt, 0.9 + lines.length * 0.16, 0.5);
    if (a > 0.002) { E.setFont(E.F.body(50, 400)); E.X.save(); E.X.globalAlpha = a * 0.92; E.drawLines([o.sub], cx, yEnd + 88, 64, E.PAL.dim); E.X.restore(); }
  }
  E.lightSweep(t, S.t0 + Math.min(1.4, (S.t1 - S.t0) * 0.5), 0.9, 0.08);
  E.read(lines.join(" "), S.t0 + 0.3, Math.min(S.t1, S.t0 + 0.3 + lines.join(" ").length * 0.06));
  if (lt > 0.05) E.event("swoosh", S.t0 + 0.30);
  if (uU > 0.5 && uU < 0.56) E.event("impact", S.t0 + 0.5 + lines.length * 0.16 + 0.3);
};

// ───────────────────────────────────────── 2. statement — the word-by-word reveal
SC.statement = function (t, S) {
  const o = S.o || {}, lt = S.lt;
  backdrop(t, S, { particles: 70 });
  const text = String(o.text || ""), em = new Set(o.em || []), strike = new Set(o.strike || []);
  const words = text.split(/\s+/).filter(Boolean);
  const span = Math.max(0.4, Math.min(2.6, (S.t1 - S.t0) * 0.55));
  const per = span / Math.max(1, words.length);
  const emText = [];
  // measure once for layout
  E.setFont(E.F.bold(84));
  let size = 84;
  const fit = E.fitFont(text, (s) => E.F.bold(s), 84, 1640, 3, 58);
  size = fit.size;
  const lh = size * 1.16;
  // word layout: wrap words into lines with their own reveal times
  const lines = [[]]; let lw = 0;
  E.setFont(E.F.bold(size));
  for (const w of words) {
    const ww = E.tw(w + " ");
    if (lw + ww > 1640 && lines[lines.length - 1].length) { lines.push([]); lw = 0; }
    lines[lines.length - 1].push(w); lw += ww;
  }
  const y0 = E.H / 2 - (lines.length - 1) * lh / 2 - size * 0.55;
  let wi = 0;
  for (let li = 0; li < lines.length; li++) {
    E.setFont(E.F.bold(size));
    const widths = lines[li].map((w) => E.tw(w + " "));
    const total = widths.reduce((a, b) => a + b, 0);
    let x = E.W / 2 - total / 2;
    for (let j = 0; j < lines[li].length; j++, wi++) {
      const w = lines[li][j];
      const at = 0.12 + wi * per;
      const a = E.show(lt, at, 0.42);
      const key = w.toLowerCase().replace(/[^\p{L}\p{N}']/gu, "");
      const isEm = em.has(key) || em.has(w);
      const isStrike = strike.has(key) || strike.has(w);
      if (a > 0.002) {
        E.X.save(); E.X.globalAlpha = a;
        E.X.translate(0, (1 - a) * 34);
        E.X.textAlign = "left"; E.X.textBaseline = "top";
        if (isEm) { E.X.fillStyle = E.PAL.accent; }
        else E.X.fillStyle = E.PAL.ink;
        E.X.fillText(w, x, y0 + li * lh);
        if (isStrike) {   // the myth, crossed out where it stands
          const su = E.seg(lt, at + 0.30, at + 0.30 + 0.35);
          if (su > 0) { E.X.strokeStyle = E.PAL.bad; E.X.lineWidth = Math.max(5, size * 0.075); E.X.lineCap = "round";
            const ww2 = E.tw(w);
            E.X.beginPath(); E.X.moveTo(x - 6, y0 + li * lh + size * 0.52);
            E.X.lineTo(x - 6 + ww2 * E.eInOut(su), y0 + li * lh + size * 0.52 - size * 0.06 * (1 - su)); E.X.stroke(); }
        }
        E.X.restore();
        if (isEm && a > 0.9) emText.push(w);
      }
      x += widths[j];
    }
  }
  const rEnd = 0.12 + words.length * per + 0.4;
  E.read(text, S.t0 + 0.12, Math.min(S.t1, S.t0 + rEnd));
  if (emText.length && lt > 0.2) E.event("pop", S.t0 + 0.12 + per, undefined, 0.2);
};

// ───────────────────────────────────────── 3. stats — the counting numbers
SC.stats = function (t, S) {
  const o = S.o || {}, lt = S.lt;
  backdrop(t, S, { particles: 60, grid: 0.05 });
  const items = (o.items || []).slice(0, 3);
  const n = Math.max(1, items.length);
  const cx = E.W / 2, gap = n > 1 ? 520 : 0;
  const baseX = cx - gap * (n - 1) / 2;
  items.forEach((it, i) => {
    const at = 0.15 + i * 0.38;
    const a = E.show(lt, at, 0.5);
    if (a <= 0.002) return;
    const x = baseX + i * gap;
    E.X.save(); E.X.globalAlpha = a;
    E.X.translate(0, (1 - E.eOutBack(a, 1.15)) * 46);
    const val = String(it.v ?? "");
    const size = n === 1 ? 210 : (n === 2 ? 170 : 150);
    E.setFont(E.F.mono(size, 700));
    // count up: digits roll in over 1.1 s
    const cu = E.eOut(E.seg(lt, at + 0.15, at + 0.15 + 1.1));
    let shown = val;
    if (it.count !== false && /^\d[\d.,]*$/.test(val)) {
      const target = parseFloat(val.replace(/,/g, ""));
      const dec = (val.split(".")[1] || "").length;
      const isFloat = val.includes(".");
      const cur = isFloat ? (target * cu) : Math.round(target * cu);
      shown = isFloat ? cur.toFixed(dec) : cur.toLocaleString("en-US");
    }
    E.X.textAlign = "center"; E.X.textBaseline = "top";
    E.X.fillStyle = it.accent === "bad" ? E.PAL.bad : (i === 0 && n > 1 ? E.PAL.ink : E.PAL.accent);
    E.X.fillText(shown + (it.suffix || ""), x, E.H * 0.32);
    if (it.prefix) { E.X.font = E.F.mono(64, 700); E.X.fillStyle = E.PAL.dim; E.X.fillText(it.prefix, x, E.H * 0.32 - 84); }
    E.setFont(E.F.body(50, 600));
    E.X.fillStyle = E.PAL.dim;
    const lls = E.wrap(String(it.label || ""), 460, 2);
    E.drawLines(lls, x, E.H * 0.32 + size + 44, 62, E.PAL.dim);
    E.X.restore();
    E.read(`${val}${it.suffix || ""} ${it.label || ""}`, S.t0 + at, Math.min(S.t1, S.t0 + at + 1.8));
    if (lt > at + 1.15 && lt < at + 1.45) E.event("pop", S.t0 + at + 1.15, x);
  });
  if (o.note) {
    const a = E.show(lt, 0.2 + items.length * 0.38, 0.5);
    if (a > 0.002) { E.setFont(E.F.body(48, 400)); E.X.save(); E.X.globalAlpha = a; E.drawLines(E.wrap(o.note, 1400, 2), cx, E.H * 0.74, 62, E.PAL.dim); E.X.restore(); }
  }
  E.lightSweep(t, S.t0 + 0.9, 0.9, 0.06);
};

// ───────────────────────────────────────── 4. compare — the two-sided truth
SC.compare = function (t, S) {
  const o = S.o || {}, lt = S.lt;
  backdrop(t, S, { particles: 55, grid: 0.05 });
  const cx = E.W / 2;
  // the divider
  const du = E.eInOut(E.seg(lt, 0.10, 0.7));
  if (du > 0) { E.X.strokeStyle = E.rgba("dim", 0.5); E.X.lineWidth = 3;
    E.X.beginPath(); E.X.moveTo(cx, E.H * 0.24 + (1 - du) * 0); E.X.lineTo(cx, E.H * 0.24); E.X.stroke();
    E.X.strokeStyle = E.rgba("dim", 0.35);
    E.X.beginPath(); E.X.moveTo(cx, E.H * 0.24); E.X.lineTo(cx, E.H * 0.24 + (E.H * 0.5) * du); E.X.stroke(); }
  const sides = [Object.assign({ color: "ink" }, o.left || {}), Object.assign({ color: "accent" }, o.right || {})];
  sides.forEach((sd, i) => {
    const at = 0.25 + i * 0.55;
    const a = E.show(lt, at, 0.55);
    if (a <= 0.002) return;
    const x = i === 0 ? cx - 470 : cx + 470;
    E.X.save(); E.X.globalAlpha = a; E.X.translate(0, (1 - a) * 30);
    E.setFont(E.F.kick(46));
    E.X.textAlign = "center"; E.X.textBaseline = "top"; E.X.fillStyle = E.PAL.dim;
    E.X.fillText(String(sd.head || "").toUpperCase(), x, E.H * 0.30);
    const fit = E.fitFont(String(sd.big || ""), (s) => E.F.display(s), 150, 850, 2, 76);
    E.setFont(E.F.display(fit.size));
    E.X.fillStyle = sd.color === "accent" ? E.PAL.accent : E.PAL.ink;
    E.drawLines(fit.lines, x, E.H * 0.38, fit.size * 1.05);
    if (sd.note) { E.setFont(E.F.body(50, 400)); E.drawLines(E.wrap(sd.note, 800, 3), x, E.H * 0.38 + fit.size * 1.05 * fit.lines.length + 36, 62, E.PAL.dim); }
    E.X.restore();
    E.read(`${sd.head}: ${sd.big}. ${sd.note || ""}`, S.t0 + at, Math.min(S.t1, S.t0 + at + 2.2));
    if (i === 1 && lt > at + 0.5) E.event("impact", S.t0 + at + 0.5, x);
  });
};

// ───────────────────────────────────────── 5. list — the numbered receipts
SC.list = function (t, S) {
  const o = S.o || {}, lt = S.lt;
  backdrop(t, S, { particles: 55 });
  const items = (o.items || []).slice(0, 4);
  const head = o.head || null;
  let y = E.H * (head ? 0.24 : 0.26);
  if (head) {
    const a = E.show(lt, 0.08, 0.5);
    if (a > 0.002) { E.setFont(E.F.kick(50)); E.X.save(); E.X.globalAlpha = a; E.X.translate(0, (1 - a) * -22);
      E.X.textAlign = "left"; E.X.textBaseline = "top"; E.X.fillStyle = E.PAL.accent;
      E.X.fillText(head.toUpperCase(), 220, y); E.X.restore();
      E.read(head, S.t0 + 0.1, S.t0 + 1.4); }
    y += 108;
  }
  const rowH = Math.min(148, (E.H * 0.66 - y) / Math.max(1, items.length));
  items.forEach((it, i) => {
    const at = 0.22 + i * (o.step || 0.42);
    const a = E.show(lt, at, 0.45);
    if (a <= 0.002) return;
    const yy = y + i * rowH;
    E.X.save(); E.X.globalAlpha = a; E.X.translate((1 - E.eOutBack(a, 1.5)) * -46, 0);
    E.setFont(E.F.mono(64, 700));
    E.X.textAlign = "left"; E.X.textBaseline = "top"; E.X.fillStyle = E.PAL.accent;
    E.X.fillText(String(i + 1).padStart(2, "0"), 220, yy);
    E.setFont(E.F.body(62, 600));
    E.X.fillStyle = E.PAL.ink;
    const ls = E.wrap(String(it), 1280, 2);
    E.drawLines(ls, 380, yy, 74, E.PAL.ink, "left");
    E.X.restore();
    const ru = E.seg(lt, at + 0.2, at + 0.55);   // the row rule
    if (ru > 0) { E.X.strokeStyle = E.rgba("accent", 0.35 * a); E.X.lineWidth = 2;
      E.X.beginPath(); E.X.moveTo(220, yy + rowH - 22); E.X.lineTo(220 + 1480 * E.eInOut(ru), yy + rowH - 22); E.X.stroke(); }
    E.read(String(it), S.t0 + at, Math.min(S.t1, S.t0 + at + 1.2));
    if (lt > at + 0.12 && lt < at + 0.5) E.event("tick", S.t0 + at + 0.15, 380);
  });
};

// ───────────────────────────────────────── 6. quote — the words of the ancients
SC.quote = function (t, S) {
  const o = S.o || {}, lt = S.lt;
  E.bgWash(t, 0.6);
  E.bgParticles(t, 40, 1, 0.7);
  const cx = E.W / 2;
  // the giant mark
  const qa = E.show(lt, 0.05, 0.7);
  if (qa > 0.002) { E.setFont(`italic 600 260px ${E.FONTS.serif}, serif`);
    E.X.save(); E.X.globalAlpha = qa * 0.22; E.X.fillStyle = E.PAL.accent;
    E.X.textAlign = "center"; E.X.textBaseline = "top"; E.X.fillText("\u201C", cx, E.H * 0.10); E.X.restore(); }
  const text = String(o.text || "");
  const fit = E.fitFont(text, (s) => `italic 600 ${s}px Fraunces, serif`, 88, 1480, 4, 56);
  const lh = fit.size * 1.28;
  const y0 = E.H / 2 - (fit.lines.length - 1) * lh / 2 - fit.size * 0.5;
  fit.lines.forEach((ln, i) => {   // line by line, rising
    const a = E.show(lt, 0.18 + i * 0.22, 0.6);
    if (a <= 0.002) return;
    E.setFont(`italic 600 ${fit.size}px Fraunces, serif`);
    E.X.save(); E.X.globalAlpha = a; E.X.translate(0, (1 - a) * 26);
    E.X.textAlign = "center"; E.X.textBaseline = "top"; E.X.fillStyle = E.PAL.ink;
    E.X.fillText(ln, cx, y0 + i * lh); E.X.restore();
  });
  if (o.who) {
    const a = E.show(lt, 0.4 + fit.lines.length * 0.22, 0.5);
    if (a > 0.002) { E.setFont(E.F.body(50, 600));
      E.X.save(); E.X.globalAlpha = a * 0.9; E.X.textAlign = "center"; E.X.textBaseline = "top";
      E.X.fillStyle = E.PAL.dim; E.X.fillText(`\u2014 ${o.who}`, cx, y0 + fit.lines.length * lh + 46); E.X.restore(); }
  }
  E.read(text, S.t0 + 0.2, Math.min(S.t1, S.t0 + 0.2 + text.length * 0.055));
  if (lt > 0.2 && lt < 0.6) E.event("shimmer", S.t0 + 0.25);
};

// ───────────────────────────────────────── 7. particles — the single word in the field
SC.particles = function (t, S) {
  const o = S.o || {}, lt = S.lt;
  E.bgWash(t, 1.4);
  E.bgParticles(t, 170, 1, 1.15);
  E.bgGrid(t, 0.05);
  const word = String(o.word || o.text || "");
  const fit = E.fitFont(word, (s) => E.F.display(s), 240, 1720, 1, 120);
  const cx = E.W / 2, cy = E.H / 2 - fit.size * 0.5;
  // letters reveal with tracking that settles
  const u = E.eOut(E.seg(lt, 0.12, 0.12 + 0.9));
  const track = lerp3(0.35, 0.02, u);
  E.setFont(E.F.display(fit.size));
  const total = [...word].reduce((n, ch) => n + E.X.measureText(ch).width + fit.size * track, 0) - fit.size * track;
  let x = cx - total / 2;
  const chars = [...word];
  chars.forEach((ch, i) => {
    const at = 0.12 + 0.9 * (i / Math.max(1, chars.length));
    const a = E.show(lt, at, 0.34);
    if (a <= 0.002) { x += E.X.measureText(ch).width + fit.size * track; return; }
    E.X.save(); E.X.globalAlpha = a; E.X.translate(0, (1 - a) * 40);
    E.X.textAlign = "left"; E.X.textBaseline = "top";
    if (o.outline) { E.X.lineWidth = Math.max(3, fit.size * 0.024); E.X.strokeStyle = E.PAL.accent; E.X.strokeText(ch, x, cy); }
    else { E.X.fillStyle = E.PAL.ink; E.X.fillText(ch, x, cy); }
    E.X.restore();
    x += E.X.measureText(ch).width + fit.size * track;
  });
  if (o.sub) {
    const a = E.show(lt, 1.1, 0.5);
    if (a > 0.002) { E.setFont(E.F.body(52, 400)); E.X.save(); E.X.globalAlpha = a; E.drawLines(E.wrap(o.sub, 1300, 2), cx, cy + fit.size + 60, 64, E.PAL.dim); E.X.restore(); }
  }
  E.read(word, S.t0 + 0.2, Math.min(S.t1, S.t0 + 1.4));
  if (lt > 0.2 && lt < 0.5) E.event("riser", S.t0 + 0.15);
  function lerp3(a, b, uu) { return a + (b - a) * uu; }
};

// ───────────────────────────────────────── 8. outro — the end card
SC.outro = function (t, S) {
  const o = S.o || {}, lt = S.lt;
  E.bgWash(t, 0.45);
  E.bgParticles(t, 45, 1, 0.6);
  const cx = E.W / 2;
  let y = E.H * 0.32;
  if (o.kick) { const a = E.show(lt, 0.10, 0.5);
    if (a > 0.002) { E.setFont(E.F.kick(46)); E.X.save(); E.X.globalAlpha = a * 0.9; E.X.textAlign = "center"; E.X.textBaseline = "top";
      E.X.fillStyle = E.PAL.accent; E.X.fillText(o.kick.toUpperCase(), cx, y); E.X.restore(); } y += 90; }
  const fit = E.fitFont(String(o.cta || "Save this. Rebuild tomorrow."), (s) => E.F.display(s), 118, 1560, 2, 72);
  const a2 = E.show(lt, 0.30, 0.6);
  if (a2 > 0.002) { E.setFont(E.F.display(fit.size)); E.X.save(); E.X.globalAlpha = a2; E.X.translate(0, (1 - a2) * 30);
    E.drawLines(fit.lines, cx, y, fit.size * 1.1, E.PAL.ink); E.X.restore();
    E.read(o.cta, S.t0 + 0.3, Math.min(S.t1, S.t0 + 2.4)); }
  y += fit.lines.length * fit.size * 1.1 + 54;
  if (o.handle) { const a = E.show(lt, 0.65, 0.5);
    if (a > 0.002) { E.setFont(E.F.mono(56, 700)); E.X.save(); E.X.globalAlpha = a; E.X.textAlign = "center"; E.X.textBaseline = "top";
      E.X.fillStyle = E.PAL.accent; E.X.fillText(o.handle, cx, y); E.X.restore(); } }
  // the breathing pulse
  const p = 0.5 + 0.5 * Math.sin(lt * TAU2 * 0.4);
  E.X.strokeStyle = E.rgba("accent", 0.10 + p * 0.12); E.X.lineWidth = 2;
  E.X.beginPath(); E.X.arc(cx, E.H * 0.5, 300 + p * 26, 0, TAU2); E.X.stroke();
  if (lt > 0.3 && lt < 0.7) E.event("ding", S.t0 + 0.35);
};
const TAU2 = Math.PI * 2;

})();
