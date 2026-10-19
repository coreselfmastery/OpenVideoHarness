// render: a page's film to an MP4 through the page contract (engines/CONTRACT.md), for the engines that are web pages
// and have no renderer of their own (the canvas engine; ClaudeAnimationBase also works, its render.mjs stays the
// documented path). Every frame of the span is drawn at t = k / fps in one of --workers browsers, each rendering a
// contiguous chunk, captured as JPEG (or PNG with --png) and piped into its own encoder (x264 by default; --encoder
// nvenc for an NVIDIA card). The chunks are joined without re-encoding. Video only: put the sound on with bin/vh mux.
//
// usage: node tools/film/render.mjs <project | page.html> --browser <chrome> [--out out/film.mp4] [--fps 30]
//          [--range a:b | --frames k0:k1] [--dpr 1] [--res 720p] [--tier draft|review|final] [--workers 4] [--crf 16] [--preset medium] [--gop 60] [--png]
//          [--quality 95] [--frame-timeout 120] [--force] [--real-clock] [--soft-gl] [--encoder x264|nvenc] [--gpu 0] [--gpus N]
//        (bin/vh render finds the browser: CHROME_PATH, HyperFrames' chrome-headless-shell, then Chrome or Chromium)
//
//   --out          default <project>/out/<page>.mp4; a lock file beside it stops a second render of the same file
//   --range a:b    only that span (frames a·fps up to b·fps); default the whole film
//   --frames k0:k1 only frames k0 up to k1 (k1 left out), frame k drawn at k / fps: exact, for bin/vh patch
//   --dpr 2        twice the pixels (4K for a 1920x1080 page)
//   --res 720p     the same page at a lower tier: the output's short side in lines (480p, 540p, 720p, 1080p —
//                  720 means 1280x720 for a landscape page, 720x1280 for a portrait one). The page keeps its
//                  own layout: Chrome draws it at a fractional deviceScaleFactor, so a 480p or 720p draft of a
//                  1080p film is the same picture at 20% / 44% of the pixels (a draft round drawn several times
//                  faster); the master is still the full-size render. It sets --dpr, and the two conflict
//   --tier t       the OpenHarness bridge: one word for the whole quality policy — draft = --res 480p and,
//                  when an NVIDIA card answers, h264_nvenc p4 cq 28 (round-robin over the cards); review =
//                  --res 720p, nvenc p5 cq 23; final = the master untouched: full size, x264, the determinism
//                  contract. Each part stays overridable: an explicit --res/--dpr/--encoder/--crf/--preset
//                  beats the tier for that part (no card / no NVENC build: the tier keeps x264, the crf rides)
//   --gop 60       a keyframe every 60 frames exactly, from the span's first frame (default 2 s of frames); the chunks
//                  are whole GOPs, so a later patch can cut the video on keyframes
//   --png          lossless frames into the encoder (slower, larger pipes); default JPEG at --quality 95
//   --force        render a HyperFrames composition this way too (by default: use npx hyperframes render, the measured path)
//   --encoder      x264 (default, the repo's film master) or nvenc: h264_nvenc on an NVIDIA card, same frame pipe and
//                  colour tags, --crf becomes NVENC's -cq (the same 0–51 scale), --preset maps onto NVENC's p1–p7
//                  (medium→p4, slow→p5 …; p1–p7 pass through). The sidecar records it, so bin/vh patch re-renders
//                  a patch of an nvenc film on nvenc again — the SPS/PPS check would refuse the mix anyway
//   --gpu N        with --encoder nvenc only: ffmpeg's own -gpu pin, which card encodes (tools/kaggle/render-split.sh
//                  gives each half of a film its own card; a card that also draws for Chrome costs the encode little,
//                  NVENC is its own block on the chip)
//   --gpus N       with --encoder nvenc only: spread the chunk encoders round-robin over N cards — worker w encodes
//                  on (gpu + w) % N. Default: every card nvidia-smi lists (both T4s on Kaggle: half the encode wall,
//                  and the encoders stop queueing behind gpu 0's browsers). --gpus 1 pins every chunk to --gpu
//
// The colour: Chrome's frames are full-range RGB; the encode converts them to limited-range BT.709 with all four colour
// tags (what bin/vh check expects). Beside the video, <out>.render.json records how it was made (size, fps, frames,
// span, encoder settings, chunks, browser), for a later patch or re-render to match. Exit: 0 rendered and checked ·
// 1 a frame failed, the encoder stopped, or the result has the wrong frame count or colour tags; also when the page
// reported an error while drawing (the video is written then, and the errors are listed) · 2 could not start.
// Ctrl-C (or SIGTERM) stops the encoders, deletes the chunks so far and the lock, and exits 130 (143).
// Before drawing it estimates the disk the render needs at its peak (the chunks and the joined copy): it stops (exit 2)
// when even a flat film would not fit, and says so when a heavy one might not.
import fs from "node:fs";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { findPage, openFilm, readPage } from "./host.mjs";
import { HOOK, check as checkGlyphs, collectDom, merge as mergeGlyphs, report as glyphReport } from "./glyphs.mjs";

process.stdout.on("error", (e) => { if (e.code !== "EPIPE") throw e; });
const HELP = fs.readFileSync(new URL(import.meta.url), "utf8").split("\nimport ")[0].replace(/^\/\/ ?/gm, "");
const argv = process.argv.slice(2);
if (!argv.length || argv.includes("-h") || argv.includes("--help")) { process.stdout.write(HELP.trimEnd() + "\n"); process.exit(argv.length ? 0 : 2); }
const die = (msg) => { console.error("render: " + msg); process.exit(2); };
const o = { fps: 30, dpr: 1, workers: 4, crf: 16, preset: "medium", quality: 95, frameTimeout: 120, encoder: "x264", gpu: 0 };
let res = null, dprSet = false;
const explicit = { res: false, dpr: false, encoder: false, crf: false, preset: false, gop: false };
let tier = null;
const NVENC_PRESETS = { ultrafast: "p1", superfast: "p1", veryfast: "p2", faster: "p3", fast: "p4", medium: "p4", slow: "p5", slower: "p6", veryslow: "p7", placebo: "p7" };
let target = null, out = null, range = null, frames = null, gop = null, png = false, force = false;
for (let i = 0; i < argv.length; i++) {
  const a = argv[i], [k, inline] = a.startsWith("--") && a.includes("=") ? [a.slice(0, a.indexOf("=")), a.slice(a.indexOf("=") + 1)] : [a, undefined];
  const val = () => { const v = inline !== undefined ? inline : argv[++i]; if (v === undefined) die(`${k} needs a value`); return v; };
  const num = (v, what, min) => { const x = Number(v); if (v === "" || !Number.isFinite(x) || x < min) die(`${what}: ${JSON.stringify(v)} is not a number ≥ ${min}`); return x; };
  if (k === "--out") out = val();
  else if (k === "--range") { range = val().split(":").map((v) => num(v, "--range", 0)); if (range.length !== 2 || range[1] <= range[0]) die("--range a:b, b > a"); }
  else if (k === "--frames") { frames = val().split(":").map((v) => num(v, "--frames", 0)); if (frames.length !== 2 || !frames.every(Number.isInteger) || frames[1] <= frames[0]) die("--frames k0:k1, whole frame numbers, k1 > k0"); }
  else if (k === "--fps") o.fps = num(val(), k, 1);
  else if (k === "--dpr") { o.dpr = num(val(), k, 0.25); dprSet = true; explicit.dpr = true; }
  else if (k === "--res") { res = val(); explicit.res = true; }
  else if (k === "--workers") o.workers = Math.floor(num(val(), k, 1));
  else if (k === "--crf") { o.crf = num(val(), k, 0); explicit.crf = true; }
  else if (k === "--preset") { o.preset = val(); explicit.preset = true; }
  else if (k === "--gop") { gop = Math.floor(num(val(), k, 1)); explicit.gop = true; }
  else if (k === "--quality") o.quality = Math.min(100, Math.floor(num(val(), k, 1)));
  else if (k === "--frame-timeout") o.frameTimeout = num(val(), k, 1);
  else if (k === "--png") png = true;
  else if (k === "--force") force = true;
  else if (k === "--browser") o.browser = val();
  else if (k === "--real-clock") o.realClock = true;
  else if (k === "--soft-gl") o.softGl = true;
  else if (k === "--tier") { const v = val(); if (v !== "draft" && v !== "review" && v !== "final") die(`--tier: draft, review or final, not ${JSON.stringify(v)}`); tier = v; }
  else if (k === "--encoder") { const v = val(); if (v !== "x264" && v !== "nvenc") die(`--encoder: x264 or nvenc, not ${JSON.stringify(v)}`); o.encoder = v; explicit.encoder = true; }
  else if (k === "--gpu") { const x = Number(val()); if (!Number.isInteger(x) || x < 0) die(`--gpu: a whole device number ≥ 0, not ${JSON.stringify(val())}`); o.gpu = x; }
  else if (k === "--gpus") { const x = Number(val()); if (!Number.isInteger(x) || x < 1) die(`--gpus: a whole number of cards ≥ 1, not ${JSON.stringify(val())}`); o.gpus = x; }
  else if (k.startsWith("-")) die(`unknown option ${k} (-h for the options)`);
  else if (target) die(`one project or page, got ${target} and ${a}`);
  else target = a;
}
if (!target) die("which project or page? (-h for the usage)");
if (range && frames) die("--range or --frames, not both");
if (res !== null && dprSet) die("--res or --dpr, not both (--res names the tier, --dpr the exact factor)");
// --tier, the OpenHarness bridge: one word that picks the whole draft/review/final
// policy (the same ladder tools/kaggle/render.sh uses for the HyperFrames path).
// Every part stays overridable: an explicit --res/--dpr/--encoder/--crf/--preset
// beats the tier's choice for that part. final IS the master: full size, x264,
// the byte-determinism contract.
if (tier === "draft" && res === null && !dprSet) res = "480p";
if (tier === "review" && res === null && !dprSet) res = "720p";
if (res !== null) {   // the tier: the short side of the video in lines, the page's own layout kept
  const m = String(res).match(/^(\d+)p?$/);
  if (!m) die(`--res: the short side in lines, like 480p, 720 or 1080p — not ${JSON.stringify(res)}`);
  const lines = +m[1];
  const info = readPage(findPage(target));
  const short = Math.min(info.width || 1920, info.height || 1080);
  const dpr = lines / short;
  if (dpr < 0.25) die(`--res ${m[1]}p on a ${info.width}x${info.height} page is dpr ${dpr.toFixed(3)}: under the 0.25 floor (a 1080p page bottoms out at ${Math.ceil(short * 0.25)}p)`);
  if (dpr > 1.0001) die(`--res ${m[1]}p on a ${info.width}x${info.height} page is dpr ${dpr.toFixed(3)}: more pixels than the page has (--res names a draft tier, fewer pixels; --dpr is the exact factor, and the engine's --output-resolution is the supersampler)`);
  o.dpr = dpr;
}
if (out && fs.existsSync(out) && fs.statSync(out).isDirectory()) die(`--out ${out} is a folder: name the video file (…/film.mp4)`);
if (out && !/\.(mp4|mov)$/i.test(out)) die(`--out ${out}: the video file, .mp4 (or .mov)`);
if (!o.browser) die("no browser: pass --browser <chrome>, or run it as bin/vh render");
for (const tool of ["ffmpeg", "ffprobe"]) if (spawnSync(tool, ["-version"]).status !== 0) die(`${tool} is not installed`);
if (o.encoder === "nvenc") {
  const enc = spawnSync("ffmpeg", ["-hide_banner", "-encoders"], { encoding: "utf8" });
  if (!/\bh264_nvenc\b/.test(enc.stdout || "")) die("this ffmpeg has no h264_nvenc compiled in: install a build with it (Ubuntu's apt ffmpeg has it) or render --encoder x264");
}
// The tier's draft/review encoders: NVENC when a card answers (a soft preference —
// no card or no NVENC build and the tier stays on x264 with the same settings),
// the same p4/cq28 and p5/cq23 ladder render.sh uses for the HyperFrames path.
if ((tier === "draft" || tier === "review") && !explicit.encoder) {
  const enc = spawnSync("ffmpeg", ["-hide_banner", "-encoders"], { encoding: "utf8" });
  const smi = spawnSync("nvidia-smi", ["-L"], { encoding: "utf8" });
  if (/\bh264_nvenc\b/.test(enc.stdout || "") && smi.status === 0) {
    o.encoder = "nvenc";
    if (!explicit.preset) o.preset = tier === "draft" ? "p4" : "p5";
    if (!explicit.crf) o.crf = tier === "draft" ? 28 : 23;
  } else if (!explicit.crf) {
    o.crf = tier === "draft" ? 28 : 23;   // the size ladder rides even on x264
  }
}
// NVENC across BOTH cards: with --encoder nvenc, chunk worker w encodes on gpu
// (o.gpu + w) % gpus. On a Kaggle 2xT4 that halves the encode wall and — more
// important — stops every encoder queueing behind the browsers on gpu 0. One
// card (or no nvidia-smi): worker w encodes on o.gpu exactly as before, so
// single-GPU behavior is byte-identical.
let nvencGpus = 1;
if (o.encoder === "nvenc") {
  if (o.gpus != null) nvencGpus = o.gpus;
  else {
    const smi = spawnSync("nvidia-smi", ["-L"], { encoding: "utf8" });
    nvencGpus = smi.status === 0 ? Math.max(1, (smi.stdout || "").split("\n").filter((l) => /GPU \d+:/i.test(l)).length) : 1;
  }
  if (nvencGpus < 1 || !Number.isInteger(nvencGpus)) die(`--gpus: a whole number of cards >= 1, not ${JSON.stringify(nvencGpus)}`);
}
const nvencPreset = /^p[1-7]$/.test(o.preset) ? o.preset : NVENC_PRESETS[o.preset] || "p4";
const workerGpu = (w) => (o.gpu + w) % nvencGpus;

const rel = (f) => { const r = path.relative(process.cwd(), f); return r && !r.startsWith("..") ? r : f; };
let first;
try { first = await openFilm(target, { ...o, runtime: "auto", prelude: [HOOK] }); } catch (e) { die(e.message); }
if (first.kind === "hyperframes" && !force) {
  await first.close();
  die("this is a HyperFrames composition: render it with npx hyperframes render (its renderer is the path this repo measured); --force renders it through the page contract anyway");
}
if (!(first.duration > 0)) { await first.close(); die("the page gives no duration"); }
const fps = o.fps, last = Math.ceil(first.duration * fps - 1e-6);   // the film's frame count: its last frame is last - 1
const k0 = frames ? frames[0] : range ? Math.round(range[0] * fps) : 0;
const k1 = frames ? Math.min(frames[1], last) : !range || range[1] >= first.duration ? last : Math.round(range[1] * fps);
const n = k1 - k0;
if (n <= 0) { await first.close(); die(`no frames in ${frames ? `frames ${frames.join("–")}` : range ? range.join("–") + " s" : "the film"} (it is ${first.duration} s, ${last} frames)`); }
gop = gop || Math.round(2 * fps);
const stem = path.basename(first.page, path.extname(first.page));
const outFile = path.resolve(out || path.join(first.root, "out", `${stem}.mp4`));
try { fs.mkdirSync(path.dirname(outFile), { recursive: true }); } catch (e) { await first.close(); die(`cannot make ${rel(path.dirname(outFile))}: ${e.message}`); }

// one render per output file: a second one would interleave its chunks with ours. A lock whose render is gone (its pid
// no longer runs) is deleted and taken afresh; an empty one is a render that has not written its pid yet, unless it is old
const lock = outFile + ".lock";
const alive = (pid) => { try { process.kill(pid, 0); return true; } catch (e) { return e.code === "EPERM"; } };
function takeLock() {
  for (let tries = 0; tries < 5; tries++) {
    try { fs.writeFileSync(lock, String(process.pid), { flag: "wx" }); return null; } catch (e) {
      if (e.code !== "EEXIST") return `cannot write ${rel(lock)}: ${e.message}`;
      let pid = 0, age = 0;
      try { pid = +fs.readFileSync(lock, "utf8"); age = Date.now() - fs.statSync(lock).mtimeMs; } catch { continue; }   // gone meanwhile
      if (pid ? alive(pid) : age < 10000) return `another render${pid ? ` (pid ${pid})` : ""} is writing ${rel(outFile)}; wait for it, or delete ${rel(lock)} if it is gone`;
      try { fs.unlinkSync(lock); } catch { /* another render took it over first: try again */ }
    }
  }
  return `could not take ${rel(lock)}`;
}
// the disk: the chunks and the joined copy are on it together before the chunks go, so about twice the video at the peak.
// x264 at these CRFs has made 0.04 bits a pixel (a flat test page) to 0.4 (4K 3D with grain): refuse only when even 0.01
// does not fit, say so when 0.06–0.4 might not (OVH_FREE_BYTES pretends that much is free: for tests)
const free = process.env.OVH_FREE_BYTES ? +process.env.OVH_FREE_BYTES : (() => { try { const s = fs.statfsSync(path.dirname(outFile)); return s.bavail * s.bsize; } catch { return Infinity; } })();
const pxs = Math.round(first.width * o.dpr) * Math.round(first.height * o.dpr) * n, gb = (b) => (b / 1e9).toFixed(b < 1e8 ? 3 : 1);
if (2 * pxs * 0.01 / 8 > free) { await first.close(); die(`at least ${gb(2 * pxs * 0.01 / 8)} GB needed at the peak for ${n} frames at ${Math.round(first.width * o.dpr)}x${Math.round(first.height * o.dpr)} (likely ${gb(2 * pxs * 0.06 / 8)}–${gb(2 * pxs * 0.4 / 8)}), ${gb(free)} GB free on that disk`); }
if (2 * pxs * 0.4 / 8 > free) console.log(`  disk: about ${gb(2 * pxs * 0.06 / 8)}–${gb(2 * pxs * 0.4 / 8)} GB needed at the peak (more for grain, 3D, photos), ${gb(free)} GB free: it may not fit`);
const busy = takeLock();
if (busy) { await first.close(); die(busy); }
const unlock = () => { try { if (+fs.readFileSync(lock, "utf8") === process.pid) fs.unlinkSync(lock); } catch { /* already gone */ } };
process.on("exit", unlock);

const parts = path.join(path.dirname(outFile), `.${path.basename(outFile)}.parts`);
fs.rmSync(parts, { recursive: true, force: true }); fs.mkdirSync(parts, { recursive: true });
const encoders = new Set();
for (const [sig, code] of [["SIGINT", 130], ["SIGTERM", 143]]) process.once(sig, () => {   // the lock goes on exit; the browsers and their profiles too (tools/textcheck/browser.mjs)
  console.error(`render: stopped (${sig}); the chunks so far are deleted`);
  for (const ff of encoders) ff.kill("SIGKILL");
  fs.rmSync(parts, { recursive: true, force: true });
  process.exit(code);
});
// chunks are whole GOPs, so every keyframe of the joined video falls on the grid k0 + m·gop (a patch can cut there)
const chunk = Math.ceil(Math.ceil(n / Math.max(1, Math.min(o.workers, n))) / gop) * gop, K = Math.ceil(n / chunk);
const chunks = Array.from({ length: K }, (_, w) => [k0 + w * chunk, Math.min(k1, k0 + (w + 1) * chunk)]).filter(([a, b]) => b > a);
const COLOR = "colorspace=bt709:color_primaries=bt709:color_trc=bt709:range=tv";
// x264's yuv420p needs an even width and height: an odd one (1366 x 768 at --dpr 1.5 is 2049 x 1152) loses its last column or row
const EVEN = "crop=trunc(iw/2)*2:trunc(ih/2)*2", px = [Math.round(first.width * o.dpr), Math.round(first.height * o.dpr)];
const vf = png ? `${EVEN},scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int,format=yuv420p,setparams=${COLOR}`
  : `${EVEN},scale=in_color_matrix=bt601:in_range=pc:out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int,format=yuv420p,setparams=${COLOR}`;
console.log(`render: ${rel(first.page)} · ${first.kind === "film" ? "window.film" : first.kind} · ${first.width}x${first.height}${o.dpr !== 1 ? ` @${o.dpr}x` : ""} · ` +
  `${n} frames at ${fps} fps (${(k0 / fps).toFixed(3)}–${(k1 / fps).toFixed(3)} s) · ${chunks.length} worker${chunks.length > 1 ? "s" : ""} · ${png ? "PNG" : `JPEG q${o.quality}`} → ${o.encoder === "nvenc" ? `h264_nvenc ${nvencPreset} cq ${o.crf}${nvencGpus > 1 ? ` on gpus ${Array.from(new Set(chunks.map((_, w) => workerGpu(w)))).sort().join("/")} round-robin` : ` (gpu ${o.gpu})`}` : `x264 crf ${o.crf} ${o.preset}`}, keyframe every ${gop} · ${first.version}`);
for (const p of first.loadProblems) console.log(`  while loading: ${p}`);
if (px[0] % 2 || px[1] % 2) console.log(`  note: ${px[0]}x${px[1]} pixels; x264 needs even sizes, so the video is ${px[0] - px[0] % 2}x${px[1] - px[1] % 2}`);

let failed = null, done = 0;
const glyphs = [];
const T0 = Date.now(), problems = [];
const within = (p, s, what) => { let timer; return Promise.race([p, new Promise((_, no) => { timer = setTimeout(() => no(new Error(`${what}: no picture after ${s} s (--frame-timeout)`)), s * 1000); })]).finally(() => clearTimeout(timer)); };
const progress = setInterval(() => { if (done) console.log(`  ${done} / ${n} frames · ${((Date.now() - T0) / 1000).toFixed(0)} s · about ${(((Date.now() - T0) / done) * (n - done) / 1000).toFixed(0)} s to go`); }, 15000);
progress.unref();

async function worker(w, [a, b]) {
  let film = w === 0 ? first : null;
  const file = path.join(parts, `part${String(w).padStart(3, "0")}.mp4`);
  const ff = spawn("ffmpeg", ["-v", "error", "-y", "-f", "image2pipe", "-framerate", String(fps), "-c:v", png ? "png" : "mjpeg", "-i", "-",
    "-vf", vf, ...o.encoder === "nvenc"
      ? ["-c:v", "h264_nvenc", "-preset", nvencPreset, "-cq", String(o.crf), "-gpu", String(workerGpu(w)), "-bf", "0",
         "-g", String(gop), "-keyint_min", String(gop), "-sc_threshold", "0", "-force_key_frames", `expr:eq(mod(n,${gop}),0)`]
      : ["-c:v", "libx264", "-preset", o.preset, "-crf", String(o.crf), "-g", String(gop), "-keyint_min", String(gop), "-sc_threshold", "0"],
    "-color_range", "tv", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-r", String(fps), file], { stdio: ["pipe", "ignore", "pipe"] });
  encoders.add(ff);
  let ffErr = ""; ff.stderr.on("data", (d) => { ffErr = (ffErr + d).slice(-2000); });
  const closed = new Promise((ok) => ff.on("close", (code, sig) => ok(code ?? sig)));
  // an encoder that stops early (a full disk, a frame it refuses) ends the render: nothing waits on a pipe no one reads
  let gone = false;
  const exited = new Promise((ok) => ff.once("exit", () => { gone = true; encoders.delete(ff); ok(); }));
  ff.stdin.on("error", () => { /* the encoder is gone: exited says so */ });
  let wrote = 0;
  try {
    if (!film) film = await openFilm(target, { ...o, runtime: "auto", prelude: [HOOK] });
    const capture = png ? { format: "png" } : { format: "jpeg", quality: o.quality };
    for (let k = a; k < b && !failed && !gone; k++) {
      const t = k / fps;
      const { png: img } = await within(film.frame(t, capture), o.frameTimeout, `t=${t.toFixed(3)} s`);
      const later = film.problems();
      if (later.length) problems.push(`t=${t.toFixed(3)} s: ${later.join(" | ")}`);
      if (!ff.stdin.write(img)) await Promise.race([new Promise((ok) => ff.stdin.once("drain", ok)), exited]);
      if (gone) break;
      wrote++; done++;
    }
  } catch (e) { failed = failed || e.message; }
  ff.stdin.end();
  // the characters this worker drew, each in the font it asked for? (tools/film/glyphs.mjs; a finding is reported, not fatal)
  // (canvas text is noted as it is drawn; the DOM's text as it stands after this worker's last frame)
  // (never in the way of the render: a minute at most, then it is said to be unchecked)
  if (film && !failed && !gone) {
    try { glyphs.push(await within((async () => { await collectDom(film); return checkGlyphs(film); })(), 60, "the glyph check")); }
    catch (e) { glyphs.push({ error: /no picture after/.test(e.message) ? "it did not finish within 60 s" : e.message }); }
  }
  const code = await closed;
  if (film) await film.close();
  if (!failed && (code !== 0 || wrote < b - a)) failed = `the encoder for frames ${a}–${b - 1} ${wrote < b - a ? `stopped after ${wrote} of them` : "failed"} (exit ${code}): ${ffErr.trim() || "no message"}`;
  return file;
}

const files = await Promise.all(chunks.map((c, w) => worker(w, c)));
clearInterval(progress);
if (failed) { fs.rmSync(parts, { recursive: true, force: true }); console.error(`render: ${failed}`); process.exit(1); }
fs.writeFileSync(path.join(parts, "list.txt"), files.map((f) => `file '${path.basename(f)}'`).join("\n") + "\n");
// joined inside the parts folder and moved onto <out> whole: a join cut short (Ctrl-C) never replaces an earlier video
const joined = path.join(parts, `joined${path.extname(outFile)}`);
const join = spawnSync("ffmpeg", ["-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", path.join(parts, "list.txt"), "-c", "copy", "-movflags", "+faststart", joined], { encoding: "utf8" });
if (join.status !== 0) { fs.rmSync(parts, { recursive: true, force: true }); console.error(`render: joining the chunks failed: ${(join.stderr || join.signal || "").toString().trim()}`); process.exit(1); }
fs.renameSync(joined, outFile);
// the frame count the MP4 records (counting by decoding would take minutes on a long 4K film)
const probe = spawnSync("ffprobe", ["-v", "error", "-select_streams", "v:0", "-show_entries",
  "stream=nb_frames,width,height,pix_fmt,color_range,color_space,color_primaries,color_transfer", "-of", "json", outFile], { encoding: "utf8" });
const st = JSON.parse(probe.stdout || "{}").streams?.[0] || {};
fs.rmSync(parts, { recursive: true, force: true });
const secs = (Date.now() - T0) / 1000;
const sidecar = {
  note: "how this video was made (bin/vh render); a patch or re-render should match these",
  // from the video's folder when the video is in the project (it moves with it), else where the page is
  page: (() => {   // first.root is a real path (host.mjs), so the video's folder is compared as one too (macOS /tmp is /private/tmp)
    const dir = fs.realpathSync(path.dirname(outFile)), page = path.join(first.root, path.basename(first.page));
    return (dir + path.sep).startsWith(first.root + path.sep) ? path.relative(dir, page) : first.page;
  })(),
  kind: first.kind, width: first.width, height: first.height, dpr: o.dpr, pixels: [st.width, st.height], fps, frames: n, tier,
  span: [+(k0 / fps).toFixed(6), +(k1 / fps).toFixed(6)], first_frame: k0, capture: png ? "png" : `jpeg q${o.quality}`,
  encoder: o.encoder === "nvenc"
    ? { codec: "h264_nvenc", crf: o.crf, preset: nvencPreset, gpu: o.gpu, gpus: nvencGpus, chunk_gpu: chunks.map((_, w) => workerGpu(w)), gop, keyint_min: gop, sc_threshold: 0, pix_fmt: st.pix_fmt, color: [st.color_range, st.color_space, st.color_primaries, st.color_transfer] }
    : { codec: "libx264", crf: o.crf, preset: o.preset, gop, keyint_min: gop, sc_threshold: 0, pix_fmt: st.pix_fmt, color: [st.color_range, st.color_space, st.color_primaries, st.color_transfer] },
  chunks: chunks.map(([a, b]) => [a, b]), browser: first.version, real_clock: !!o.realClock, soft_gl: !!o.softGl, seconds: +secs.toFixed(1),
};
fs.writeFileSync(outFile + ".render.json", JSON.stringify(sidecar, null, 1) + "\n");
const okCount = +st.nb_frames === n, okColor = st.pix_fmt === "yuv420p" && st.color_range === "tv" && st.color_space === "bt709";
console.log(`  ${rel(outFile)}: ${st.nb_frames} frames, ${st.width}x${st.height}, ${st.pix_fmt} ${st.color_range}/${st.color_space}, in ${secs.toFixed(0)} s` +
  ` (${(secs * 1000 / n).toFixed(0)} ms a frame); how it was made: ${rel(outFile + ".render.json")}`);
for (const p of problems) console.log(`  ${p}`);
{   // a character in another font than it asks for, or in none: said, not fatal
  const okG = glyphs.filter((g) => !g.error), errG = glyphs.filter((g) => g.error);
  const [lines, wrong] = okG.length ? glyphReport(mergeGlyphs(okG)) : [[], false];
  if (wrong) { console.log("  glyphs: characters not drawn in the font they ask for (bin/vh fonts check lists them all):"); for (const l of lines.filter((x) => /^[✗!]/.test(x))) console.log("    " + l); }
  if (errG.length) console.log(`  glyphs: ${errG.length} of ${glyphs.length} worker(s) could not check theirs (${errG[0].error}); bin/vh fonts check does it on its own`);
}
if (!okCount) console.log(`  the video has ${st.nb_frames} frames, not ${n}`);
if (!okColor) console.log(`  the colour tags are not yuv420p tv/bt709`);
if (problems.length || !okCount || !okColor) process.exit(1);
console.log("render: done · the sound goes on with bin/vh mux");
