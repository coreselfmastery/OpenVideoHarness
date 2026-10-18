# SPDX-License-Identifier: GPL-3.0-or-later
# It calls Blender's Python API, so it is distributed under the GPL (engines/blender.md, "许可证"); the rest of the repo is MIT.
"""Render a Blender swatch scene (styles/<slug>/swatch.py) to PNG frames. render.sh runs it inside Blender:

  blender -b --factory-startup --python-exit-code 1 --python styles/_swatch/blender_render.py -- \
      <scene_dir> <out_dir> --frames 0-149 [--quality final|draft|fast] [--fonts fonts.json] [--hud] \
      [--pct 100] [--device SPEC]

  --frames   a comma list of frames and ranges ("0-149", "149,90,12"), rendered in that order into
             <out_dir>/frame_NNNN.png
  --quality  final (default): the determinism anchor — Cycles on the CPU through the
             final-cpu profile (fixed samples, no time limit, no persistent data; the same
             pixels on every run and in any frame order);
             draft: the speed preview — Cycles on the GPU (CUDA first on Linux per the T4
             doctrine, Metal on a Mac) through the draft profile (adaptive 0.1, 120 s/frame
             cap, Simplify on);
             fast: final quality on the GPU — the final profile at full samples, for Kaggle
             T4 quality swatches (determinism anchor still available as --quality final)
  --fonts    the role → font file map that blender_fonts.py wrote (a .ttc face is extracted to its own file first)
  --hud      burn the frame number and time into the bottom edge (Blender's stamp; for checking only)
  --pct      resolution percentage (100 = 1920x1080; 200 = the 4K calibration pass, engines/blender.md "出 4K")
  --device   override the device for this run: cpu | auto | cuda | optix | cuda:1 | gpu:0 …
             (default: the quality's own choice above; tools/blender_perf.py, --device)

The Cycles settings themselves (bounces 6/3/3/4/2/4, indirect clamp 10, OIDN RGB+Albedo+
Normal, CPU compositor, AgX) come from tools/blender_perf.py — the performance layer —
and per-quality/per-scene overrides are applied on top (RENDER below; a swatch.py may
still carry {"final": {"samples": 32, …}} as before). Persistent data stays OFF here:
the swatch renderer must stay a pure function per frame (the teacup lesson, below); the
pipeline (tools/blender_run.sh --profile) is where persistent data is ON.

The scene module is plain Python. It imports bpy only where Blender runs it, so `python3 swatch.py --foley` works anywhere:
  FOLEY = [{"t", "sfx", "gain_db", "pan", …}]   the foley list (foley.mjs writes events.json from it)
  FONTS = {"role": "fontconfig pattern"}        e.g. {"zh": "Songti SC:weight=bold"}; env.fonts["zh"] is the loaded font
  RENDER = {"final": {…}, "draft": {…}}         optional overrides on top of the profile (samples, device, …)
  def build(env): …                             once per Blender process: the whole scene, from tokens and constants only
  def apply(t, env): …                          every animated property at t = k/30 s, set directly: a pure function of
                                                t. No keyframes, so no motion blur (a stop-motion camera has none), and
                                                no state carried from one frame to the next.
"""
import importlib.util, json, os, struct, sys, time, traceback, zlib
from types import SimpleNamespace

sys.dont_write_bytecode = True                 # importing swatch.py must not leave a __pycache__ in styles/<slug>/
_REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _REPO not in sys.path:                      # tools/blender_perf.py is the settings layer (repo root)
    sys.path.insert(0, _REPO)

import bpy
from tools.blender_perf import apply_profile

# mirror of lib.js (the content spec every swatch follows; styles/_swatch/README.md, "统一内容规格")
W, H, FPS, DUR, FRAMES, POSTER_T = 1920, 1080, 30, 5, 150, 3.0
SPEC = {"establish": (0, 0.8), "title": (0.8, 2.6), "motif": (2.0, 4.0), "outro": (4.0, 5.0), "poster": 3.0}
TITLE_EN = "Every frame is code."
TITLE_ZH = "每一帧，都是代码。"
MOTIF = [{"key": "outline", "en": "Outline", "zh": "大纲"},
         {"key": "storyboard", "en": "Storyboard", "zh": "分镜"},
         {"key": "draft", "en": "Draft", "zh": "初版"}]

# What the swatch flow layers on top of the perf profile (tools/blender_perf.py, the
# performance layer). final = the final-cpu profile (determinism anchor) at the shipped
# swatch calibration of 64 fixed samples; draft = the draft profile as is (32 adaptive,
# 120 s cap, Simplify); fast = the final profile on the GPU for Kaggle quality swatches.
RENDER_DEFAULTS = {
    "final": {"profile": "final-cpu", "device": "cpu", "samples": 64},
    "draft": {"profile": "draft", "device": "auto"},
    "fast": {"profile": "final", "device": "auto"},
}


def hash01(*xs):
    """[0, 1) from any numbers: the same on every machine (IEEE doubles hashed with crc32, like lib.hash)."""
    return zlib.crc32(struct.pack(f"<{len(xs)}d", *map(float, xs))) / 4294967296


def parse_frames(spec):
    out = []
    for part in spec.split(","):
        part = part.strip()
        if not part: continue
        if "-" in part[1:]:
            a, b = part.split("-", 1); out += list(range(int(a), int(b) + 1))
        else: out.append(int(part))
    bad = [k for k in out if not 0 <= k < FRAMES]
    if bad: raise SystemExit(f"[swatch] frames out of range 0–{FRAMES - 1}: {bad[:5]}")
    return out


def args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = SimpleNamespace(scene=None, out=None, frames=f"0-{FRAMES - 1}", quality="final", fonts=None, hud=False,
                         pct=100, device=None)
    pos, i = [], 0
    while i < len(a):
        if a[i] in ("--frames", "--quality", "--fonts", "--pct", "--device"): setattr(o, a[i][2:], a[i + 1]); i += 2
        elif a[i] == "--hud": o.hud = True; i += 1
        else: pos.append(a[i]); i += 1
    if len(pos) != 2: raise SystemExit("usage: blender -b --python blender_render.py -- <scene_dir> <out_dir> [--frames …]")
    o.scene, o.out = pos
    if o.quality not in RENDER_DEFAULTS: raise SystemExit(f"[swatch] --quality is final, draft or fast, not {o.quality}")
    try: o.pct = int(o.pct)
    except ValueError: raise SystemExit(f"[swatch] --pct is a number, not {o.pct}")
    return o


_LEGACY_DEVICE = {"CPU": "cpu", "GPU": "auto"}   # swatch.py files and old RENDER dicts speak CPU/GPU


def setup_render(sc, q, hud, pct, device_spec):
    r = sc.render
    r.engine = "CYCLES"; r.resolution_x, r.resolution_y, r.resolution_percentage = W, H, pct
    r.fps, r.fps_base = FPS, 1.0
    r.image_settings.file_format = "PNG"; r.image_settings.color_mode = "RGB"
    r.image_settings.color_depth = "8"; r.image_settings.compression = 15
    r.film_transparent = False; r.use_motion_blur = False
    # the whole Cycles settings matrix (bounces, clamp, OIDN passes, AgX, CPU compositor,
    # seed policy) comes from the profile; the per-scene/per-quality overrides go on top
    spec = device_spec or q.get("device", "auto")
    spec = _LEGACY_DEVICE.get(spec, spec) if isinstance(spec, str) else spec
    dev, _rows = apply_profile(sc, q["profile"], device=spec)
    cy = sc.cycles
    if "samples" in q: cy.samples = q["samples"]
    if "adaptive_threshold" in q: cy.adaptive_threshold = q["adaptive_threshold"]
    if "denoise" in q: cy.use_denoising = q["denoise"]
    if hasattr(cy, "denoising_use_gpu"): cy.denoising_use_gpu = dev["backend"] != "CPU"
    # persistent data stays off in the SWATCH renderer: with it, Cycles kept state from
    # earlier frames (tabletop-miniature's teacup came out black on frames 27-44 of an
    # in-order render and grey when those frames were rendered alone), so a frame depended
    # on which frames came before it. determinism.sh caught it (frame 30, 24.5 dB). The
    # pipeline (tools/blender_run.sh --profile) is where persistent data is ON instead.
    r.use_persistent_data = False
    r.use_stamp = hud
    if hud:
        for k in dir(r):
            if k.startswith("use_stamp_"): setattr(r, k, k in ("use_stamp_frame", "use_stamp_time"))
        r.stamp_font_size = 28
    return dev


def load_fonts(path):
    fonts = {}
    if not path: return fonts
    for role, f in json.load(open(path)).items():
        fonts[role] = bpy.data.fonts.load(f["file"], check_existing=True)
        print(f"[swatch] font {role}: {f['pattern']} → {fonts[role].name} ({os.path.basename(f['source'])}"
              f"{', face %d' % f['index'] if f['index'] else ''})", flush=True)
    return fonts


def main():
    o = args()
    os.makedirs(o.out, exist_ok=True)
    spec = importlib.util.spec_from_file_location("swatch_scene", os.path.join(o.scene, "swatch.py"))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    for fn in ("build", "apply"):
        if not callable(getattr(mod, fn, None)): raise SystemExit(f"[swatch] swatch.py has no {fn}(env)")
    q = {**RENDER_DEFAULTS[o.quality], **getattr(mod, "RENDER", {}).get(o.quality, {})}
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    dev = setup_render(sc, q, o.hud, o.pct, o.device)
    env = SimpleNamespace(W=W, H=H, FPS=FPS, DUR=DUR, FRAMES=FRAMES, POSTER_T=POSTER_T, SPEC=SPEC, TITLE_EN=TITLE_EN,
                          TITLE_ZH=TITLE_ZH, MOTIF=MOTIF, tokens=json.load(open(os.path.join(o.scene, "tokens.json"))),
                          quality=o.quality, scene_dir=o.scene, fonts=load_fonts(o.fonts), scene=sc, hash=hash01)
    t0 = time.time(); mod.build(env)
    frames = parse_frames(o.frames)
    print(f"[swatch] built in {time.time() - t0:.1f}s · {o.quality}: {dev['backend']} {dev['devices'] or ''}"
          f"{' · ' + dev['note'] if dev['note'] else ''} · {sc.cycles.samples} samples, {o.pct}% · "
          f"{len(frames)} frame(s) → {o.out}", flush=True)
    for k in frames:
        t1 = time.time()
        sc.frame_set(k)                                   # no keyframes in the scene: this only sets the frame number
        mod.apply(k / FPS, env)
        sc.render.filepath = os.path.join(o.out, f"frame_{k:04d}.png")
        bpy.ops.render.render(write_still=True)
        print(f"[swatch] frame {k:3d} t={k / FPS:.3f} {time.time() - t1:5.1f}s", flush=True)


try:
    main()
except SystemExit as e:
    if e.code not in (None, 0): print(e.code if isinstance(e.code, str) else f"[swatch] exit {e.code}", flush=True)
    sys.exit(1 if e.code not in (None, 0) else 0)
except Exception:
    print("[swatch] ERROR in the Blender scene:\n" + traceback.format_exc(), flush=True)
    sys.exit(1)
