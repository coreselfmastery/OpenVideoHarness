#!/usr/bin/env node
// Engine smoke harness: boots the page-contract engine against a synthetic
// timeline with a no-op canvas, then draws frames across the whole film,
// including every cut boundary and the fades. Catches runtime errors,
// missing-font logs, under-floor text, and contract violations — everything
// except the actual pixels (those get the real-Chrome test).
"use strict";
const fs = require("fs");
const path = require("path");

const PROJ = process.argv[2];
if (!PROJ) { console.error("usage: node engine_harness.js <project-dir>"); process.exit(2); }
const root = path.resolve(PROJ);

// ── the fake DOM ────────────────────────────────────────────────────────────
// A class, not a Proxy: record() wraps X.fillText around Object.getPrototypeOf(X),
// so the methods the engine calls must live on the prototype.
class FakeCtx2D {
  constructor(canvas) { this.canvas = canvas; this._font = "400 16px Inter"; }
  get font() { return this._font; }
  set font(v) { this._font = String(v); }
  measureText(s) {
    const m = /([\d.]+)px/.exec(this._font);
    const size = m ? parseFloat(m[1]) : 16;
    return { width: String(s).length * size * 0.52 + size * 0.1 };
  }
  createImageData(w, h) { return { data: new Uint8ClampedArray(w * h * 4), width: w, height: h }; }
  createRadialGradient() { return { addColorStop() {} }; }
  createLinearGradient() { return { addColorStop() {} }; }
  reset() { this._font = "400 16px Inter"; }
  setTransform() {} clearRect() {} save() {} restore() {}
  translate() {} scale() {} rotate() {}
  fillRect() {} strokeRect() {}
  beginPath() {} closePath() {} arc() {} arcTo() {} ellipse() {}
  moveTo() {} lineTo() {} fill() {} stroke() {}
  fillText() {} strokeText() {}
  drawImage() {} putImageData() {}
}
function makeCanvas(w, h) {
  const cv = { width: w || 300, height: h || 150, style: {}, getContext: () => new FakeCtx2D(cv) };
  return cv;
}

const consoleErrors = [];
const realErr = console.error;
console.error = (...a) => { consoleErrors.push(a.map(String).join(" ")); realErr(...a); };

global.window = global;
global.devicePixelRatio = 1;
global.document = {
  getElementById: () => mainCanvas,
  createElement: () => makeCanvas(),
  fonts: (() => {
    const faces = ["Archivo Black", "Inter", "Fraunces", "JetBrains Mono"].map((f) => ({ family: f, weight: "400", load: () => Promise.resolve() }));
    faces.load = () => Promise.resolve();
    faces[Symbol.iterator] = function* () { yield* faces.map((f) => ({ ...f })); };
    return faces;
  })(),
};
global.fetch = async (url) => {
  const p = path.join(root, url);
  if (!fs.existsSync(p)) throw new Error(`fetch 404: ${url}`);
  return { ok: true, json: async () => JSON.parse(fs.readFileSync(p, "utf8")) };
};

const mainCanvas = makeCanvas(1920, 1080);

// ── load the engine ─────────────────────────────────────────────────────────
const code = fs.readFileSync(path.join(root, "engine-core.js"), "utf8") +
             "\n" + fs.readFileSync(path.join(root, "engine-scenes.js"), "utf8");
(0, eval)(code);

(async () => {
  let failures = 0;
  const fail = (m) => { failures++; console.error("FAIL " + m); };
  try {
    await global.window.film.ready;
  } catch (e) {
    console.error("BOOT FAILED:", e.message);
    process.exit(1);
  }
  const f = global.window.film;
  const dur = f.duration;
  console.log(`boot OK · duration ${dur.toFixed(2)}s · ${f.covers.length} covers · ${f.chapters.length} chapters`);
  if (!(dur > 100)) fail(`duration ${dur} suspiciously short`);
  if (dur > 660) fail(`duration ${dur} suspiciously long`); // raised for the 10-minute masters (600 s by design)
  for (const c of f.chapters) if (String(c.title) === "[object Object]") fail("chapter title is an object");

  // frame at: every 0.5 s + all cut boundaries ± 1 frame + the very ends
  const starts = [];
  const html = fs.readFileSync(path.join(root, "index.html"), "utf8");
  for (const m of html.matchAll(/data-start="([\d.]+)"/g)) starts.push(parseFloat(m[1]));
  const at = new Set([0, dur - 0.02, 0.5, 1.0]);
  for (let t = 0; t < dur; t += 0.5) at.add(t);
  for (const s of starts) { at.add(s - 1 / 30); at.add(s); at.add(s + 1 / 30); }
  let drew = 0;
  for (const t of [...at].sort((a, b) => a - b)) {
    if (t < 0 || t >= dur) continue;
    try { f.frame(t); f.frame(t, { layer: "scene" }); drew += 2; }
    catch (e) { fail(`frame(${t.toFixed(3)}) threw: ${e.message}`); break; }
  }
  console.log(`drew ${drew} frames at ${at.size} sample points`);
  // ui boxes + covers
  try { for (const t of [2, dur / 2, dur - 1]) f.ui(t); }
  catch (e) { fail(`ui(t) threw: ${e.message}`); }
  for (const c of f.covers) {
    try { f.cover(c.id); } catch (e) { fail(`cover(${c.id}) threw: ${e.message}`); }
  }
  // the contract exports
  if (!Array.isArray(f.texts) || f.texts.length < 10) fail(`texts export thin: ${f.texts.length}`);
  if (!Array.isArray(f.events) || f.events.length < 10) fail(`events export thin: ${f.events.length}`);
  if (!f.chapters.length) fail("no chapters");
  // recorded errors from the engine itself (fonts, under-floor text, throwing shots)
  const engineErrs = consoleErrors.filter((e) => e.startsWith("engine:"));
  for (const e of engineErrs) fail("engine logged: " + e.slice(0, 160));

  console.log(`texts: ${f.texts.length} · events: ${f.events.length} · chapters: ${f.chapters.map((c) => c.title).join(" | ")}`);
  console.log(failures ? `\n${failures} FAILURES` : "\nHARNESS PASS");
  process.exit(failures ? 1 : 0);
})();
