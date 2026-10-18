// patch: draw frames a–b of a film again and put them back, without rendering the rest. For a film made by bin/vh
// render: its <film>.render.json says how (the page, fps, device pixel ratio, capture, encoder settings) and its keyframes
// fall every --gop frames, so the video can be cut on them. The frames from the keyframe at or before a up to the next
// keyframe after b are rendered again with the same settings (tools/film/render.mjs --frames — an nvenc film on nvenc
// again, its --gpu with it), the film's packets before and after are copied as they are, the three are joined, and the
// film's other tracks (sound, subtitles) go back on.
//
// usage: node tools/film/patch.mjs <film.mp4> --browser <chrome> (--frames a-b | --seconds s-e) [--sidecar f.render.json]
//          [--page film.html] [--out f.mp4] [--in-place] [--workers 4] [--verify seams|full] [--min-psnr 40] [--keep]
//        (bin/vh patch finds the browser as bin/vh render does)
//
//   --frames a-b     the film's frames a to b, both in (numbered from 0, as bin/vh check and ffmpeg count them)
//   --seconds s-e    the frames shown from s up to e seconds (frame k when s ≤ k / fps < e)
//   --sidecar f      how the film was rendered: default <film>.render.json. A film that bin/vh mux put sound on keeps the
//                    render's video as it is, so the render's sidecar (out/film.mp4.render.json) describes it too
//   --page f         the page to draw: default the sidecar's
//   --out f          default <film>.patched.mp4 beside the film; --in-place replaces the film (and its sidecar) once every
//                    check has passed
//   --verify         seams (default): decode one GOP either side of the new frames in both films and compare; full: also
//                    decode the whole new film for errors (minutes for a long 4K film)
//   --min-psnr 40    the frames rendered again but outside a–b (to the keyframes) must come back like the film's, at least
//                    this many dB: less means the page now draws them differently (an edit that reaches further than a–b,
//                    another browser), and the joins at the keyframes would show
//   --keep           keep the work folder (.<out>.patch/) to look at
//
// Room: about twice the film's size free beside the output (the film is cut, joined and its tracks put back before the
// parts go). One patch of an output at a time (<out>.patch.lock), and none while bin/vh render is writing the film.
// Checks, every run: the new film has as many frames as the old one; every packet outside the frames rendered again is
// the same bytes (and decoded, the frames next to the joins are the same pixels: PSNR infinite); the joined part decodes
// without an error; the new frames' encoder setup (SPS/PPS) is the film's. Exit: 0 patched and checked · 1 a check failed
// (the new film is kept for a look, never put in place) · 2 could not start (no sidecar, the film does not match it,
// frames outside the film, the page does not draw). Ctrl-C stops the render and deletes the work folder.
import fs from "node:fs";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";

process.stdout.on("error", (e) => { if (e.code !== "EPIPE") throw e; });
const HERE = path.dirname(new URL(import.meta.url).pathname);
const HELP = fs.readFileSync(new URL(import.meta.url), "utf8").split("\nimport ")[0].replace(/^\/\/ ?/gm, "");
const argv = process.argv.slice(2);
if (!argv.length || argv.includes("-h") || argv.includes("--help")) { process.stdout.write(HELP.trimEnd() + "\n"); process.exit(argv.length ? 0 : 2); }
const die = (msg, code = 2) => { console.error("patch: " + msg); cleanUp(); process.exit(code); };
const o = { workers: 4, verify: "seams", minPsnr: 40 };
let film = null, frames = null, seconds = null, sidecarFile = null, pageArg = null, out = null, inPlace = false, keep = false, browser = null;
let work = null;
function cleanUp() { if (work && !keep) fs.rmSync(work, { recursive: true, force: true }); }
for (let i = 0; i < argv.length; i++) {
  const a = argv[i], [k, inline] = a.startsWith("--") && a.includes("=") ? [a.slice(0, a.indexOf("=")), a.slice(a.indexOf("=") + 1)] : [a, undefined];
  const val = () => { const v = inline !== undefined ? inline : argv[++i]; if (v === undefined) die(`${k} needs a value`); return v; };
  const pair = (v, what, whole) => {
    const m = v.match(/^\s*([\d.]+)\s*[-:–]\s*([\d.]+)\s*$/);
    if (!m) die(`${what}: write it as a-b`);
    const x = [+m[1], +m[2]];
    if (!x.every(Number.isFinite) || (whole && !x.every(Number.isInteger))) die(`${what}: ${v}: ${whole ? "whole frame numbers" : "seconds"}`);
    return x;
  };
  if (k === "--frames") { frames = pair(val(), k, true); if (frames[1] < frames[0]) die("--frames a-b with b ≥ a (both frames are in)"); }
  else if (k === "--seconds") { seconds = pair(val(), k, false); if (!(seconds[1] > seconds[0])) die("--seconds s-e with e > s"); }
  else if (k === "--sidecar") sidecarFile = val();
  else if (k === "--page") pageArg = val();
  else if (k === "--out") out = val();
  else if (k === "--in-place") inPlace = true;
  else if (k === "--keep") keep = true;
  else if (k === "--workers") { o.workers = Math.floor(Number(val())); if (!(o.workers >= 1)) die("--workers: a whole number ≥ 1"); }
  else if (k === "--verify") { o.verify = val(); if (!["seams", "full"].includes(o.verify)) die("--verify seams or full"); }
  else if (k === "--min-psnr") { o.minPsnr = Number(val()); if (!Number.isFinite(o.minPsnr)) die("--min-psnr: a number of dB"); }
  else if (k === "--browser") browser = val();
  else if (k.startsWith("-")) die(`unknown option ${k} (-h for the options)`);
  else if (film) die(`one film, got ${film} and ${a}`);
  else film = a;
}
if (!film) die("which film? (-h for the usage)");
if (!frames === !seconds) die("say which frames: --frames a-b or --seconds s-e");
if (!browser) die("no browser: pass --browser <chrome>, or run it as bin/vh patch");
if (inPlace && out) die("--out or --in-place, not both");
for (const tool of ["ffmpeg", "ffprobe"]) if (spawnSync(tool, ["-version"]).status !== 0) die(`${tool} is not installed`);
film = path.resolve(film);
if (!fs.existsSync(film) || !fs.statSync(film).isFile()) die(`no such film: ${film}`);
const rel = (f) => { const r = path.relative(process.cwd(), f); return r && !r.startsWith("..") ? r : f; };

// ---- how the film was made, and does the film match it ----
sidecarFile = path.resolve(sidecarFile || film + ".render.json");
if (!fs.existsSync(sidecarFile)) die(`no ${rel(sidecarFile)}: a patch needs to know how the film was rendered, which bin/vh render writes beside it. A film bin/vh mux made from a render: --sidecar <the render>.render.json`);
let side;
try { side = JSON.parse(fs.readFileSync(sidecarFile, "utf8")); } catch (e) { die(`${rel(sidecarFile)}: ${e.message}`); }
const enc = side.encoder || {};
for (const [k, v] of [["fps", side.fps], ["frames", side.frames], ["first_frame", side.first_frame], ["page", side.page], ["encoder.gop", enc.gop], ["encoder.crf", enc.crf], ["encoder.preset", enc.preset]])
  if (v === undefined || v === null) die(`${rel(sidecarFile)} has no ${k}: not a bin/vh render sidecar`);
const probe = (f, args) => {
  const r = spawnSync("ffprobe", ["-v", "error", ...args, "-of", "json", f], { encoding: "utf8", maxBuffer: 1 << 30 });
  if (r.status !== 0) die(`ffprobe ${rel(f)}: ${(r.stderr || "").trim()}`);
  return JSON.parse(r.stdout || "{}");
};
const streams = (f) => probe(f, ["-show_streams", "-show_data_hash", "sha256"]).streams || [];
const filmStreams = streams(film), v = filmStreams.find((s) => s.codec_type === "video");
if (!v) die(`${rel(film)} has no video`);
const fps = side.fps, rate = v.r_frame_rate.split("/").map(Number), vfps = rate[0] / rate[1];
if (v.codec_name !== "h264") die(`${rel(film)} is ${v.codec_name}, not the H.264 bin/vh render writes`);
if (Math.abs(vfps - fps) > 1e-3) die(`${rel(film)} runs at ${vfps.toFixed(3)} fps, the sidecar says ${fps}: it is not that render's video`);
if (side.pixels && (v.width !== side.pixels[0] || v.height !== side.pixels[1])) die(`${rel(film)} is ${v.width}x${v.height}, the sidecar says ${side.pixels.join("x")}: it is not that render's video`);
// the frames in display order and which of them are keyframes (decode order differs where there are B-frames)
const pk = (f) => (probe(f, ["-select_streams", "v:0", "-show_entries", "packet=pts,flags"]).packets || []).map((p) => ({ pts: +p.pts, key: String(p.flags).includes("K") }));
const packets = pk(film), N = packets.length;
if (N !== side.frames) die(`${rel(film)} has ${N} frames, the sidecar ${side.frames}: it is not that render's video (or it was cut since)`);
const order = packets.map((p, i) => [p.pts, i]).sort((x, y) => x[0] - y[0]);
const display = new Array(N); order.forEach(([, i], d) => { display[i] = d; });
const keys = packets.map((p, i) => (p.key ? display[i] : -1)).filter((d) => d >= 0).sort((x, y) => x - y);
if (keys[0] !== 0) die(`${rel(film)} does not start on a keyframe`);

// ---- which frames ----
let [a, b] = frames || [Math.ceil(seconds[0] * fps - 1e-6), Math.min(N, Math.ceil(seconds[1] * fps - 1e-6)) - 1];   // seconds past the end: to the last frame
if (a < 0 || b >= N || b < a) die(`frames ${a}–${b}: the film has frames 0–${N - 1}`);
const A = keys.filter((k) => k <= a).pop(), B = keys.find((k) => k > b) ?? N;
const gop = enc.gop;
// the sidecar's page is relative to the sidecar's own folder (the render's video was beside it)
const page = path.resolve(pageArg || (path.isAbsolute(side.page) ? side.page : path.join(path.dirname(sidecarFile), side.page)));
if (!fs.existsSync(page)) die(`no page at ${rel(page)} (the sidecar's; --page names another)`);
const outFile = inPlace ? film : path.resolve(out || path.join(path.dirname(film), `${path.basename(film, path.extname(film))}.patched${path.extname(film)}`));
if (!inPlace && outFile === film) die("--out is the film itself: use --in-place");
const k0 = side.first_frame + A, k1 = side.first_frame + B;
console.log(`patch: ${rel(film)} · ${N} frames at ${fps} fps · frames ${a}–${b} (${(a / fps).toFixed(3)}–${((b + 1) / fps).toFixed(3)} s) asked; ` +
  `${A}–${B - 1} drawn again (keyframe to keyframe, ${B - A} frames) from ${rel(page)}`);
if (side.patches && side.patches.length) console.log(`  patched before: ${side.patches.map((p) => `${p.frames[0]}–${p.frames[1]}`).join(", ")}`);

// ---- one patch at a time, never while a render writes the film, and room for the work ----
const alive = (pid) => { try { process.kill(pid, 0); return true; } catch (e) { return e.code === "EPERM"; } };
const held = (f) => { try { const pid = +fs.readFileSync(f, "utf8"); return pid > 0 && alive(pid) ? pid : 0; } catch { return 0; } };
if (held(film + ".lock")) die(`bin/vh render (pid ${held(film + ".lock")}) is writing ${rel(film)}: wait for it`);
const lock = outFile + ".patch.lock";
for (let tries = 0; ; tries++) {   // taken by whoever writes it first (wx); one whose pid is gone is stale and taken over
  try { fs.writeFileSync(lock, String(process.pid), { flag: "wx" }); break; } catch (e) { if (e.code !== "EEXIST") die(`cannot write ${rel(lock)}: ${e.message}`); }
  let pid = 0, age = 0;
  try { pid = +fs.readFileSync(lock, "utf8"); age = Date.now() - fs.statSync(lock).mtimeMs; } catch { continue; }   // gone meanwhile: try again
  if ((pid ? alive(pid) : age < 10000) || tries >= 4) die(`another patch${pid ? ` (pid ${pid})` : ""} is writing ${rel(outFile)}: wait for it, or delete ${rel(lock)} if it is gone`);
  try { fs.unlinkSync(lock); } catch { /* another took it over first: try again */ }
}
const unlock = () => { try { if (+fs.readFileSync(lock, "utf8") === process.pid) fs.unlinkSync(lock); } catch { /* gone */ } };
process.on("exit", unlock);
// the film's packets are written about twice over before the parts go (cut, joined, tracks put back): room for that
const filmBytes = fs.statSync(film).size;
const free = process.env.OVH_FREE_BYTES ? +process.env.OVH_FREE_BYTES : (() => { try { const st = fs.statfsSync(path.dirname(outFile)); return st.bavail * st.bsize; } catch { return Infinity; } })();
if (2.2 * filmBytes > free) die(`about ${(2.2 * filmBytes / 1e9).toFixed(1)} GB free is needed beside ${rel(outFile)} to cut and join a ${(filmBytes / 1e9).toFixed(1)} GB film; ${(free / 1e9).toFixed(1)} GB is`);

// ---- render the span again, exactly as before ----
work = path.join(path.dirname(outFile), `.${path.basename(outFile)}.patch`);
fs.rmSync(work, { recursive: true, force: true }); fs.mkdirSync(work, { recursive: true });
let child = null;
for (const [sig, code] of [["SIGINT", 130], ["SIGTERM", 143]]) process.once(sig, () => {
  console.error(`patch: stopped (${sig}); the work folder is deleted, the film is as it was`);
  if (child) child.kill(sig);
  keep = false; cleanUp(); process.exit(code);
});
const piece = path.join(work, "piece.mp4");
const capture = String(side.capture || "jpeg q95"), q = capture.match(/jpeg q(\d+)/);
const rargs = [path.join(HERE, "render.mjs"), page, "--browser", browser, "--frames", `${k0}:${k1}`, "--fps", String(fps), "--dpr", String(side.dpr || 1),
  "--crf", String(enc.crf), "--preset", String(enc.preset), "--gop", String(gop), "--workers", String(o.workers), "--out", piece,
  ...(enc.codec === "h264_nvenc" ? ["--encoder", "nvenc", "--gpu", String(enc.gpu ?? 0)] : []),
  ...(capture === "png" ? ["--png"] : ["--quality", q ? q[1] : "95"]), ...(side.real_clock ? ["--real-clock"] : []), ...(side.soft_gl ? ["--soft-gl"] : []), ...(side.kind === "hyperframes" ? ["--force"] : [])];
const T0 = Date.now();
const code = await new Promise((ok) => {
  child = spawn(process.execPath, rargs, { stdio: ["ignore", "pipe", "pipe"] });
  const show = (d) => { for (const l of String(d).split("\n").filter(Boolean)) console.log("  " + l); };
  child.stdout.on("data", show); child.stderr.on("data", show);
  child.on("close", (c, s) => ok(c ?? s));
});
child = null;
if (code !== 0) die(`rendering frames ${A}–${B - 1} failed (render exit ${code}); the film is as it was`, code === 2 ? 2 : 1);
const pside = JSON.parse(fs.readFileSync(piece + ".render.json", "utf8"));
if (pside.frames !== B - A) die(`the page drew ${pside.frames} frames for ${A}–${B - 1}, not ${B - A}: it is shorter now than the film (${rel(page)}). Render the film again`, 1);
const notes = [];
if (side.browser && pside.browser !== side.browser) notes.push(`the film was rendered in ${side.browser}, these frames in ${pside.browser}: text and edges can differ a little (the PSNR below shows how much)`);

// ---- the same encoder setup? Joined streams share one SPS/PPS ----
const ps = streams(piece).find((s) => s.codec_type === "video");
const failures = [];
if (ps.extradata_hash !== v.extradata_hash || ps.width !== v.width || ps.height !== v.height || ps.pix_fmt !== v.pix_fmt || ps.profile !== v.profile || ps.level !== v.level)
  die(`the new frames' encoder setup is not the film's (SPS/PPS ${ps.extradata_hash === v.extradata_hash ? "same" : "differ"}, ${ps.profile}/${ps.level} vs ${v.profile}/${v.level}): ` +
    `another ${v.codec_name === "h264_nvenc" ? "NVENC session (driver or ffmpeg changed?)" : "x264 or other settings"}; joining them would make a broken film. Render the film again instead`, 1);

// ---- cut the film on its keyframes, join the three, put the other tracks back ----
const ff = (args, what) => {
  const r = spawnSync("ffmpeg", ["-v", "error", "-nostdin", "-y", ...args], { encoding: "utf8", maxBuffer: 1 << 28 });
  if (r.status !== 0) die(`${what}: ${(r.stderr || r.error || "").toString().trim()}`, 1);
  return r;
};
const cuts = [A, B].filter((k) => k > 0 && k < N);
const parts = [];
if (cuts.length) {
  ff(["-i", film, "-map", "0:v:0", "-c", "copy", "-f", "segment", "-segment_frames", cuts.join(","), "-reset_timestamps", "1", path.join(work, "seg%d.mp4")], "cutting the film");
  const segs = fs.readdirSync(work).filter((f) => /^seg\d+\.mp4$/.test(f)).sort((x, y) => parseInt(x.slice(3)) - parseInt(y.slice(3))).map((f) => path.join(work, f));
  const count = (f) => pk(f).length;
  const before = A > 0 ? segs[0] : null, after = B < N ? segs[segs.length - 1] : null;
  if ((before && count(before) !== A) || (after && count(after) !== N - B)) die("the film did not cut on its keyframes as expected", 1);
  if (before) parts.push(before);
  parts.push(piece);
  if (after) parts.push(after);
} else parts.push(piece);
// each part's length in frames: an MP4's own duration is rounded to its movie timescale (1/1000 s), which would move the
// part after it by a few ticks when a GOP is not a whole number of milliseconds (--gop 20 at 30 fps)
const frameCount = new Map(parts.map((f) => [f, f === piece ? B - A : A > 0 && f === parts[0] ? A : N - B]));
fs.writeFileSync(path.join(work, "list.txt"), parts.map((f) => `file '${path.basename(f)}'\nduration ${(frameCount.get(f) / fps).toFixed(9)}`).join("\n") + "\n");
const video = path.join(work, "video.mp4");
const others = filmStreams.filter((s) => s.codec_type !== "video");
ff(["-f", "concat", "-safe", "0", "-i", path.join(work, "list.txt"), "-map", "0:v", "-c", "copy", ...(others.length ? [] : ["-movflags", "+faststart"]), video], "joining");
for (const f of fs.readdirSync(work)) if (/^seg\d+\.mp4$/.test(f)) fs.rmSync(path.join(work, f));   // the cut film: its packets are in video.mp4 now
const joined = path.join(work, `joined${path.extname(outFile) || ".mp4"}`);
if (others.length) {
  // the film's own sound and subtitle tracks, as they were (their language and default flags too)
  const disp = others.flatMap((s, i) => ["-disposition:" + (i + 1), Object.entries(s.disposition || {}).filter(([, x]) => x).map(([d]) => d).join("+") || "0"]);
  ff(["-i", video, "-i", film, "-map", "0:v", ...others.map((s) => ["-map", `1:${s.index}`]).flat(), "-c", "copy", "-map_metadata", "1", ...disp, "-movflags", "+faststart", joined], "putting the other tracks back");
  // the MP4 muxer switches the first subtitle track on when none is on: a film made with bin/vh mux --subs-off had them
  // all off, so clear the enabled bit of its subtitle tracks again, as bin/vh mux does
  const subs = others.filter((s) => s.codec_type === "subtitle");
  if (subs.length && subs.every((s) => !(s.disposition || {}).default)) { try { subtitlesOff(joined); } catch (e) { die(`switching the subtitle tracks off again: ${e.message}`, 1); } }
  fs.rmSync(video);
} else fs.renameSync(video, joined);

function subtitlesOff(file) {   // every subtitle trak's tkhd: flags byte 3, bit 0 (enabled) cleared, in place; only moov is read
  const fd = fs.openSync(file, "r+");
  try {
    const total = fs.fstatSync(fd).size, head = Buffer.alloc(16);
    let at = 0, moov = null;
    while (at + 8 <= total) {   // the top-level boxes, by their headers alone (a film can be far over 2 GB)
      fs.readSync(fd, head, 0, 16, at);
      let n = head.readUInt32BE(0), h = 8; const t = head.toString("latin1", 4, 8);
      if (n === 1) { n = Number(head.readBigUInt64BE(8)); h = 16; } else if (n === 0) n = total - at;
      if (n < h) break;
      if (t === "moov") { moov = [at, n]; break; }
      at += n;
    }
    if (!moov) throw new Error("no moov box");
    const b = Buffer.alloc(moov[1]); fs.readSync(fd, b, 0, moov[1], moov[0]);
    const boxes = function* (a, e) {
      while (a + 8 <= e) {
        let n = b.readUInt32BE(a), h = 8; const t = b.toString("latin1", a + 4, a + 8);
        if (n === 1) { n = Number(b.readBigUInt64BE(a + 8)); h = 16; } else if (n === 0) n = e - a;
        if (n < h) break;
        yield [t, a + h, a + n]; a += n;
      }
    };
    const [, c, e] = [...boxes(0, b.length)][0];
    for (const [tt, tc, te] of boxes(c, e)) {
      if (tt !== "trak") continue;
      const kids = Object.fromEntries([...boxes(tc, te)].map(([k, kc, ke]) => [k, [kc, ke]]));
      const hdlr = kids.mdia ? [...boxes(...kids.mdia)].find(([k]) => k === "hdlr") : null;
      const kind = hdlr ? b.toString("latin1", hdlr[1] + 8, hdlr[1] + 12) : "";
      if (kids.tkhd && ["sbtl", "subt", "text"].includes(kind)) { const i = kids.tkhd[0] + 3; b[i] &= 0xfe; fs.writeSync(fd, b, i, 1, moov[0] + i); }
    }
  } finally { fs.closeSync(fd); }
}

// ---- checks ----
const after = pk(joined);
if (after.length !== N) failures.push(`the new film has ${after.length} frames, not ${N}`);
const pmd5 = (f) => ff(["-i", f, "-map", "0:v:0", "-c", "copy", "-f", "framemd5", "-"], "hashing packets").stdout.split("\n").filter((l) => l && !l.startsWith("#")).map((l) => l.split(",").map((x) => x.trim()));
const oldP = pmd5(film), newP = pmd5(joined);
// in decode order, the first A packets are the frames before A and the last N - B those from B on (closed GOPs)
let same = 0, moved = 0;
for (let i = 0; i < N && i < newP.length; i++) {
  if (i >= A && i < B) continue;
  if (oldP[i][5] === newP[i][5] && oldP[i][1] === newP[i][1] && oldP[i][2] === newP[i][2]) same++; else moved++;
}
if (moved) failures.push(`${moved} packet(s) outside frames ${A}–${B - 1} are not the film's own (bytes or times)`);
// decoded, one GOP either side of the new frames: the same pixels outside them, no decode errors, and the PSNR inside
const w0 = Math.max(0, A - gop), w1 = Math.min(N, B + gop);
const dec = (f) => {
  const r = spawnSync("ffmpeg", ["-v", "error", "-nostdin", "-ss", (w0 / fps).toFixed(6), "-i", f, "-map", "0:v:0", "-frames:v", String(w1 - w0), "-f", "framemd5", "-"], { encoding: "utf8", maxBuffer: 1 << 28 });
  return { err: (r.stderr || "").trim(), md5: (r.stdout || "").split("\n").filter((l) => l && !l.startsWith("#")).map((l) => l.split(",").pop().trim()) };
};
const da = dec(film), db = dec(joined);
if (db.err) failures.push(`decoding frames ${w0}–${w1 - 1} of the new film: ${db.err.split("\n")[0]}`);
if (da.md5.length !== w1 - w0 || db.md5.length !== w1 - w0) failures.push(`decoding frames ${w0}–${w1 - 1}: got ${da.md5.length} and ${db.md5.length} frames`);
let pixDiff = 0;
for (let i = 0; i < Math.min(da.md5.length, db.md5.length); i++) { const f = w0 + i; if ((f < A || f >= B) && da.md5[i] !== db.md5[i]) pixDiff++; }
if (pixDiff) failures.push(`${pixDiff} frame(s) next to the joins decode to other pixels than the film's`);
// PSNR per frame over the new span, against the film: the frames outside a–b must come back as they were
// (run in the work folder, so the stats file's name needs no escaping in the filter graph whatever the folders are called)
const ps2 = spawnSync("ffmpeg", ["-v", "error", "-nostdin", "-ss", (A / fps).toFixed(6), "-i", film, "-ss", (A / fps).toFixed(6), "-i", joined,
  "-frames:v", String(B - A), "-lavfi", "[0:v][1:v]psnr=stats_file=psnr.log", "-f", "null", "-"], { encoding: "utf8", cwd: work });
// the filter graph can run a frame past -frames:v, so the stats file may have one line more: lines are taken by their
// frame number n (from 1), the first B - A of them, each once
const psnr = new Array(B - A).fill(NaN);
if (ps2.status === 0 && fs.existsSync(path.join(work, "psnr.log")))
  for (const l of fs.readFileSync(path.join(work, "psnr.log"), "utf8").split("\n")) {
    const n = +(l.match(/(?:^|\s)n:(\d+)/) || [])[1], m = l.match(/psnr_avg:(\S+)/);
    if (n >= 1 && n <= B - A && m) psnr[n - 1] = m[1] === "inf" ? Infinity : +m[1];
  }
// the one check that sees an edit reaching past a–b: no PSNR is a failure, not a pass
if (psnr.some(Number.isNaN)) failures.push(`the PSNR of frames ${A}–${B - 1} against the film could not be measured (ffmpeg: ${ps2.signal ? `stopped by ${ps2.signal}` :
  (ps2.stderr || "").toString().trim().split("\n")[0] || `exit ${ps2.status}, ${psnr.filter((x) => !Number.isNaN(x)).length} of ${B - A} frames`})`);
const span = (lo, hi) => psnr.slice(lo - A, hi - A + 1).filter((x) => !Number.isNaN(x));
const kept = [...span(A, a - 1), ...span(b + 1, B - 1)], asked = span(a, b);
const fmt = (x) => (x === Infinity ? "∞" : x.toFixed(1));
const minKept = kept.length ? Math.min(...kept) : null;
if (minKept !== null && minKept < o.minPsnr) {
  const off = []; psnr.forEach((x, i) => { const f = A + i; if ((f < a || f > b) && x < o.minPsnr) off.push(f); });
  const runs = []; for (const f of off) { const r = runs[runs.length - 1]; if (r && f === r[1] + 1) r[1] = f; else runs.push([f, f]); }
  failures.push(`frames ${runs.map(([x, y]) => (x === y ? `${x}` : `${x}–${y}`)).join(", ")} are outside ${a}–${b} but come back under ${o.minPsnr} dB (lowest ${fmt(minKept)}): ` +
    "the page draws them differently now (the edit reaches beyond the frames named, a transition shows the shot, another browser), and the joins would show. Name the frames the edit really covers");
}
if (o.verify === "full") {
  const r = spawnSync("ffmpeg", ["-v", "error", "-nostdin", "-i", joined, "-map", "0:v", "-map", "0:a?", "-f", "null", "-"], { encoding: "utf8" });
  if ((r.stderr || "").trim() || r.status !== 0) failures.push(`decoding the whole new film: ${(r.stderr || "").trim().split("\n")[0] || `exit ${r.status}`}`);
}

// ---- report, sidecar, and the film in place ----
const secs = (Date.now() - T0) / 1000;
console.log(`  frames: ${after.length} (the film: ${N})${after.length === N ? " ✓" : " ✗"}`);
console.log(`  packets outside ${A}–${B - 1}: ${same} the film's own${moved ? `, ${moved} not ✗` : " ✓"}; decoded ${w0}–${w1 - 1} around the joins: ${pixDiff ? `${pixDiff} frames differ ✗` : "the same pixels outside the new frames (PSNR ∞) ✓"}${db.err ? " · decode errors ✗" : ", no decode errors ✓"}`);
if (!psnr.some(Number.isNaN)) console.log(`  against the film: frames ${a}–${b} ${asked.length ? `${fmt(Math.min(...asked))}–${fmt(Math.max(...asked))} dB` : "—"} (what changed)` +
  (kept.length ? `; frames drawn again only to reach the keyframes at least ${fmt(minKept)} dB${minKept >= o.minPsnr ? " ✓" : " ✗"}` : ""));
if (o.verify === "full") console.log(`  the whole new film decodes${failures.some((f) => f.startsWith("decoding the whole")) ? " with errors ✗" : " without an error ✓"}`);
for (const n of notes) console.log(`  note: ${n}`);
await new Promise((r) => setImmediate(r));   // a Ctrl-C that came during the checks ends it here, the film as it was
const record = { frames: [a, b], drawn: [A, B - 1], at: new Date().toISOString().slice(0, 19) + "Z", browser: pside.browser, seconds: +secs.toFixed(1), min_psnr_kept: minKept === Infinity ? "inf" : minKept };
const sideFor = (videoFile) => {   // as bin/vh render writes it: the page relative to the video's folder when that is inside the page's
  const dir = fs.realpathSync(path.dirname(videoFile)), real = fs.realpathSync(page), root = path.dirname(real);
  return { ...side, page: (dir + path.sep).startsWith(root + path.sep) ? path.relative(dir, real) : real, patches: [...(side.patches || []), record] };
};
if (failures.length) {
  const kept2 = path.join(path.dirname(outFile), `${path.basename(film, path.extname(film))}.failed${path.extname(film)}`);
  fs.renameSync(joined, kept2);
  for (const f of failures) console.log(`  ✗ ${f}`);
  console.log(`patch: a check failed; the film is as it was, and the new one is in ${rel(kept2)} to look at`);
  cleanUp(); process.exit(1);
}
if (inPlace) {
  fs.renameSync(joined, film);   // the same folder: one rename, never a half-written film
  // the film's own sidecar: the one it had, or a new one beside it when --sidecar named a render it was made from (whose
  // video is not the one patched)
  const own = film + ".render.json";
  fs.writeFileSync(own, JSON.stringify(sideFor(film), null, 1) + "\n");
  console.log(`patch: done in ${secs.toFixed(0)} s · ${rel(film)} now has the new frames ${a}–${b}; ${rel(own)} lists the patch`);
} else {
  fs.renameSync(joined, outFile);
  fs.writeFileSync(outFile + ".render.json", JSON.stringify(sideFor(outFile), null, 1) + "\n");
  console.log(`patch: done in ${secs.toFixed(0)} s · ${rel(outFile)} (+ .render.json); the film is as it was`);
}
cleanUp();
