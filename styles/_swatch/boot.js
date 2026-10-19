// Style swatch runtime: loads the scene named by the `style` variable, its tokens and fonts, then draws
// scene.renderAt(t) on every HyperFrames seek. Scene authors never edit this file; see README.md.
import * as lib from "./lib.js";

const BUILTIN = new Set(["demo", "catalog", "catalog-fx", "fontprobe"]);  // scenes that live inside styles/_swatch/
const canvas = document.getElementById("c");
const ctx = canvas.getContext("2d", { alpha: false, willReadFrequently: false });
const vars = readVars();
const STYLE = String(vars.style || "demo").trim();
const HUD = vars.hud === true || vars.hud === "true" || vars.hud === 1;
const BASE = BUILTIN.has(STYLE) ? `./${STYLE}/` : `./scenes/${STYLE}/`;
const state = { style: STYLE, base: BASE, tokens: null, scene: null, error: null, fontsFailed: [], fontsLoaded: [], fontsMissing: [] };
window.__swatch = state;

function readVars() {
  try { const v = window.__hyperframes && window.__hyperframes.getVariables && window.__hyperframes.getVariables(); if (v && typeof v === "object") return v; } catch (e) {}
  return window.__hfVariables || {};
}

function log(level, msg) { try { console[level](`[swatch] ${msg}`); } catch (e) {} }

// Full-frame magenta card: a broken scene must never look like a frozen or empty frame.
// render.sh treats a magenta-dominant sample as a failure.
function errorCard(where, err) {
  const msg = String((err && (err.stack || err.message)) || err).split("\n").slice(0, 6);
  ctx.reset();
  ctx.fillStyle = "#ff00ff"; ctx.fillRect(0, 0, lib.W, lib.H);
  ctx.fillStyle = "#ffffff"; ctx.font = '700 64px "Menlo", monospace'; ctx.textBaseline = "top";
  ctx.fillText(`SWATCH ERROR · ${STYLE} · ${where}`, 96, 96);
  ctx.font = '400 30px "Menlo", monospace';
  msg.forEach((l, i) => ctx.fillText(l.slice(0, 110), 96, 220 + i * 46));
}

function hud(t, f) {
  ctx.save();                                              // NOT ctx.reset(): that would wipe the frame
  ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalAlpha = 1; ctx.globalCompositeOperation = "source-over"; ctx.filter = "none";
  ctx.shadowBlur = 0; ctx.shadowColor = "transparent"; ctx.letterSpacing = "0px";
  ctx.font = '400 26px "Menlo", monospace'; ctx.textBaseline = "alphabetic"; ctx.textAlign = "left";
  const s = `${STYLE}  t ${t.toFixed(2)}  f ${String(f).padStart(3, "0")}`;
  const w = ctx.measureText(s).width;
  ctx.fillStyle = "rgba(0,0,0,0.6)"; ctx.fillRect(24, lib.H - 62, w + 28, 40);
  ctx.fillStyle = "#ffd400"; ctx.fillText(s, 38, lib.H - 32);
  ctx.restore();
}

const seen = new Set();
function draw(time) {
  const f = Math.max(0, Math.min(lib.FRAMES - 1, Math.round(time * lib.FPS)));
  const t = f / lib.FPS;                                   // quantized: renderAt only ever sees k/30
  if (state.error) { errorCard(state.error.where, state.error.err); return; }
  ctx.reset();                                             // clears pixels AND all state: no leakage between frames
  try { state.scene.renderAt(t, ctx, state.tokens, lib); }
  catch (err) {
    const msg = String(err && err.message || err);
    if (!seen.has(msg)) { seen.add(msg); log("error", `renderAt threw (first at t=${t.toFixed(3)}; later frames with the same error are not logged): ${err && err.stack || err}`); }
    errorCard(`renderAt(${t.toFixed(2)})`, err); return;
  }
  if (HUD) hud(t, f);
}

async function stylesheetLoaded(id) {
  const link = document.getElementById(id);
  if (!link || link.sheet) return;
  await new Promise((r) => { link.addEventListener("load", r, { once: true }); link.addEventListener("error", r, { once: true }); });
}

// Load every @font-face whose family is named anywhere in the tokens, plus the lib fallbacks and scene.fonts.
async function loadFonts(tokens, extra) {
  const text = JSON.stringify(tokens || {}) + " " + (extra || []).join(" ") + " " + lib.FALLBACK_FAMILIES.join(" ");
  const jobs = [];
  for (const face of document.fonts) {
    const fam = face.family.replace(/^["']|["']$/g, "");
    if (!text.includes(fam)) continue;
    jobs.push(face.load().then(() => state.fontsLoaded.push(`${fam} ${face.weight} ${face.style}`),
      () => state.fontsFailed.push(`${fam} ${face.weight} ${face.style}`)));
  }
  await Promise.all(jobs);
  await document.fonts.ready;
}

async function boot() {
  try {
    await stylesheetLoaded("fontcss");
    const res = await fetch(BASE + "tokens.json");
    if (!res.ok) throw new Error(`${BASE}tokens.json → HTTP ${res.status}`);
    state.tokens = await res.json();
    const scene = await import(BASE + "swatch.js");
    if (typeof scene.renderAt !== "function") throw new Error(`${BASE}swatch.js does not export renderAt(t, ctx, tokens, lib)`);
    state.scene = scene;
    await loadFonts(state.tokens, scene.fonts);
    if (typeof scene.setup === "function") await scene.setup(ctx, state.tokens, lib);
    // Warm pass: draw a spread of frames so any font, image or cache first touched inside renderAt is loaded
    // before the first captured frame (otherwise worker 1 and worker 4 could draw frame 90 differently).
    for (const t of [0, 0.9, 1.8, 2.7, 3.0, 3.6, 4.5, lib.DUR - 1 / lib.FPS]) {
      ctx.reset();
      try { scene.renderAt(t, ctx, state.tokens, lib); }
      catch (err) { log("error", `renderAt(${t.toFixed(2)}) threw during warm-up: ${err && err.stack || err}`); break; }   // the frame itself will show the error card
    }
    await document.fonts.ready;
    state.fontsMissing = lib.tokenFamilies(state.tokens).filter((f) => !lib.fontAvailable(f));
    if (state.fontsMissing.length) log("warn", `token font families not available (falling back): ${state.fontsMissing.join(", ")}`);
    if (state.fontsFailed.length) log("warn", `@font-face local() faces not found: ${state.fontsFailed.join(" | ")}`);
  } catch (err) {
    state.error = { where: "load/setup", err };
    log("error", `${STYLE}: ${err && err.stack || err}`);
  }
  window.__swatchDraw = draw;
  draw(window.__swatchT || 0);
  window.__swatchResolve && window.__swatchResolve();
}

boot();
