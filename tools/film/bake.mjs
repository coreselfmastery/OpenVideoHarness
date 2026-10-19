// bake: freeze a page's static scene into one lossless PNG — the pre-computed shared asset of the
// speed table. What the compositor would re-run every frame although it never changes (a backdrop-filter
// blur over static content, stacked glass, gradients under text) becomes one image the page's cheap
// twin simply blits, with the animated layer drawn live on top; the fixture pair
// tools/kaggle/fixture/css-cost is the worked example, and tools/kaggle/README.md has the measured gap.
//
// usage: node tools/film/bake.mjs <project | page.html> --browser <chrome> [--out scene.png]
//          [--at t] [--hide sel,sel…] [--dpr 1] [--soft-gl] [--real-clock] [--timeout 600]
//        (bin/vh bake finds the browser: CHROME_PATH, HyperFrames' chrome-headless-shell, then Chrome or Chromium)
//
//   --out scene.png   default <page-folder>/assets/scene.png
//   --at t            the moment to freeze (default 0); anything that only moves with t is invisible
//                     in the bake anyway once its layer is hidden — pick the t the static scene is final at
//   --hide sel,sel…   what belongs to the animated layer, hidden for the bake (a comma list of selectors,
//                     tried in order); default [data-bake-hide] — the page says what moves
//   --dpr 2           bake at twice the pixels (the twin page then shows it at half CSS size, or the
//                     render draws it at a --res tier)
//
// The bake is exactly one frame of the page with the hidden layer gone, captured lossless; a fresh
// bake of an unchanged page PSNR-matches the committed one (the kaggle test suite checks the fixture).
// Nothing is written into the page — the twin that uses the PNG is the author's half of the pattern.
// Exit: 0 baked · 1 the page failed (a throw, an error, a failed load) · 2 usage, no page, no browser.
import fs from "node:fs";
import path from "node:path";
import { openFilm } from "./host.mjs";

process.stdout.on("error", (e) => { if (e.code !== "EPIPE") throw e; });
const HELP = fs.readFileSync(new URL(import.meta.url), "utf8").split("\nimport ")[0].replace(/^\/\/ ?/gm, "");
const argv = process.argv.slice(2);
if (!argv.length || argv.includes("-h") || argv.includes("--help")) { process.stdout.write(HELP.trimEnd() + "\n"); process.exit(argv.length ? 0 : 2); }
const die = (msg) => { console.error("bake: " + msg); process.exit(2); };
const num = (v, k, min) => { const n = Number(v); if (!Number.isFinite(n) || n < min) die(`${k} wants a number ≥ ${min}, not ${JSON.stringify(v)}`); return n; };

let target = null, out = null, at = 0, hide = "[data-bake-hide]", dpr = 1, softGl = false, realClock = false, timeout = 600, browser = null;
for (let i = 0; i < argv.length; i++) {
  const a = argv[i], val = () => (argv[++i] ?? die(`${a} wants a value`));
  if (a === "--out" || a === "-o") out = val();
  else if (a === "--at") at = num(val(), a, 0);
  else if (a === "--hide") hide = val();
  else if (a === "--dpr") dpr = num(val(), a, 0.25);
  else if (a === "--browser" || a === "-b") browser = val();
  else if (a === "--soft-gl") softGl = true;
  else if (a === "--real-clock") realClock = true;
  else if (a === "--timeout") timeout = num(val(), a, 1);
  else if (a === "--force") { /* a page folder with renders/ is fine here: nothing is rendered */ }
  else if (a.startsWith("-")) die(`unknown option ${a} (-h for the usage)`);
  else if (target === null) target = a;
  else die(`what is ${JSON.stringify(a)}? one page or project (-h for the usage)`);
}
if (!target) die("which project or page? (-h for the usage)");
if (!browser) die("no browser: pass --browser <chrome>, or run it as bin/vh bake");

const film = await openFilm(target, { browser, dpr, softGl, realClock, timeout });
try {
  const hidden = await film.ev(
    `(() => { const sels = ${JSON.stringify(hide)}.split(",").map((s) => s.trim()).filter(Boolean);
       let n = 0, found = [];
       for (const s of sels) for (const el of document.querySelectorAll(s)) { el.style.setProperty("display", "none", "important"); n++; }
       for (const s of sels) if (document.querySelector(s)) found.push(s);
       return { n, found: found.join(",") }; })()`,
    "hiding the animated layer");
  if (!hidden.n) { console.error("bake: nothing matched " + JSON.stringify(hide) + " — mark the moving layer (data-bake-hide) or pass --hide sel"); process.exit(1); }
  const { png } = await film.frame(at);            // draw t with the layer hidden, capture, lossless
  out = out || path.join(path.dirname(film.page), "assets", "scene.png");
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, png);
  console.log(`baked ${out} (${(png.length / 1024).toFixed(0)} KiB, ${hidden.n} element(s) of [${hidden.found}] hidden, t=${at}s${film.duration != null ? ` of ${film.duration}s` : ""})`);
  const problems = film.problems();
  if (problems.length) { for (const p of problems) console.error("bake: " + p); process.exit(1); }
} finally {
  await film.close();
}
