# SPDX-License-Identifier: GPL-3.0-or-later
# It calls Blender's Python API, so it is distributed under the GPL (engines/blender.md, "许可证"); the rest of the repo is MIT.
"""The Cycles performance layer for the Blender engine (engines/blender-perf.md).

Everything here was fact-locked against Blender 5.2.2 LTS on 2026-10-18: every property
name, enum and default below was read back from a live `blender -b` before this file
was written, and `check` re-proves it on any machine it runs on. Three legacy knobs
this harness is sometimes asked for do NOT exist in 5.2.2 and are documented, not set:
render tile_x/tile_y (Cycles is full-frame since 2.90), cycles.use_spatial_splits
(the BVH layout is automatic now), and simplify texture limit (removed with 4.0).

Library use (inside Blender, from a scene/render script):

    from tools.blender_perf import apply_profile, select_device
    report = apply_profile(scene, "final", device="cuda:1")

CLI use (also inside Blender; the script runs BEFORE the -a/-f render action, so one
process can apply a profile and render with it — verified live):

    blender -b build/scene.blend -o //../out/plate/f_#### -F PNG -s 0 -e 59 -a \
        --python tools/blender_perf.py -- apply --profile final --device cuda:1 \
        -- --cycles-device CUDA --cycles-print-stats

    subcommands: probe | apply | check | report
      probe            list compute devices and backends, then exit
      apply            apply a profile in this process (render afterwards with -a/-f)
      check            apply, then read back EVERY setting and assert it landed
      report           print the effective settings of the current scene

    --profile   draft | final | final-cpu      (draft 32spp/120s cap, final 128spp/600s
                 cap + adaptive 0.02, final-cpu the determinism anchor: CPU, fixed
                 128spp, no time limit, no persistent data)
    --device    auto | cpu | cuda | optix | hip | oneapi | metal | cuda:N | gpu:N
                auto = CUDA first on Linux (the T4 doctrine: no RT cores, OptiX has no
                BVH advantage there; RT-core owners pass optix explicitly), Metal first
                on macOS. cuda:N / gpu:N pins ONE GPU in-process (device use flags);
                the physical pin is CUDA_VISIBLE_DEVICES in tools/blender_run.sh.
    --simplify  force Simplify on (the VRAM emergency lever) regardless of profile
    --save      after apply, also save the .blend (build-stage use)
"""
import math
import sys

try:
    import bpy
except ImportError:
    sys.exit("blender_perf runs inside Blender: blender -b <file> --python tools/blender_perf.py -- <subcommand> …")

PROFILES = {
    # the three contracts. Shared by all: bounce budget 6/3/3/4/2/4, indirect clamp 10,
    # OIDN RGB+Albedo+Normal, CPU compositor, AgX; the differences are the determinism
    # trade-offs each one makes (engines/blender-perf.md, "哪个设置拿走了确定性").
    "draft": {
        "samples": 32, "adaptive": True, "adaptive_threshold": 0.1, "adaptive_min_samples": 0,
        "time_limit": 120.0, "prefilter": "ACCURATE", "denoise_quality": "HIGH",
        "simplify": True, "persistent": True, "device": "auto",
    },
    "final": {
        "samples": 128, "adaptive": True, "adaptive_threshold": 0.02, "adaptive_min_samples": 0,
        "time_limit": 600.0, "prefilter": "ACCURATE", "denoise_quality": "HIGH",
        "simplify": False, "persistent": True, "device": "auto",
    },
    "final-cpu": {
        "samples": 128, "adaptive": False, "adaptive_threshold": 0.02, "adaptive_min_samples": 0,
        "time_limit": 0.0, "prefilter": "ACCURATE", "denoise_quality": "HIGH",
        "simplify": False, "persistent": False, "device": "cpu",
    },
}
ALIASES = {"fast": "final", "cpu": "final-cpu", "deterministic": "final-cpu"}

# backend order for --device auto. CUDA before OptiX everywhere but macOS: on a T4
# (Turing, no RT cores) OptiX falls back to a software BVH and loses its only advantage,
# so CUDA is the correct default; owners of RT-core cards pass --device optix explicitly.
import platform
_BACKENDS = ("METAL",) if platform.system() == "Darwin" else ("CUDA", "OPTIX", "HIP", "ONEAPI")
_KINDS = ("NONE", "CUDA", "OPTIX", "HIP", "METAL", "ONEAPI")


def _prefs():
    return bpy.context.preferences.addons["cycles"].preferences


def select_device(scene, spec="auto"):
    """Choose the Cycles compute device. Returns a report dict; never raises.
    spec: auto | cpu | cuda | optix | hip | oneapi | metal | cuda:N | gpu:N"""
    cy = scene.cycles
    out = {"asked": spec, "backend": "CPU", "devices": [], "note": ""}
    kind, _, idx = spec.partition(":")
    kind = kind.upper()
    idx = int(idx) if idx.isdigit() else None
    if kind == "GPU":                      # gpu:N = "any GPU backend, the Nth one"
        kind, idx = "AUTO", idx
    if kind == "CPU":                       # checked before validation: CPU is a valid
        cy.device = "CPU"                  # spec but not a compute_device_type enum value
        out["note"] = (out["note"] + " " if out["note"] else "") + "CPU forced"
        return out
    if kind not in _KINDS and kind != "AUTO":
        kind = "AUTO"
        out["note"] = f"unknown device {spec!r}, fell back to auto"
    p = _prefs()
    order = (kind,) if kind != "AUTO" else _BACKENDS
    for k in order:
        try:
            p.compute_device_type = k
            if hasattr(p, "refresh_devices"):
                p.refresh_devices()
            else:
                p.get_devices()
        except (TypeError, RuntimeError):
            continue                        # e.g. METAL on Linux: not in the enum there
        gpus = [d for d in p.devices if d.type == k and d.type != "CPU"]
        if not gpus:
            continue
        if idx is None:
            for d in p.devices:
                d.use = d.type == k        # all GPUs of this backend, CPU off
            cy.device = "GPU"
            out.update(backend=k, devices=[d.name for d in gpus])
            return out
        if idx >= len(gpus):
            out["note"] = f"{k} has {len(gpus)} device(s); no #{idx}"
            continue
        for d in p.devices:
            d.use = False
        gpus[idx].use = True               # ONE GPU, in-process pin
        cy.device = "GPU"
        out.update(backend=k, devices=[gpus[idx].name], note=(out["note"] + " " if out["note"] else "") + f"pinned #{idx}")
        return out
    cy.device = "CPU"
    out["note"] = (out["note"] + " " if out["note"] else "") + "no GPU backend with devices; CPU"
    return out


def _eq(want, got):
    """Booleans strict; numbers compared at float32 RNA storage precision (0.02 comes
    back as 0.0199999995…), everything else by equality."""
    if isinstance(want, bool) or isinstance(got, bool):
        return want == got and isinstance(want, bool) == isinstance(got, bool)
    if isinstance(want, (int, float)) and isinstance(got, (int, float)):
        return math.isclose(want, got, rel_tol=1e-6, abs_tol=1e-9)
    return want == got


def _setp(rows, obj, prop, value):
    """Set one property, recording set / absent / rejected for the check table."""
    try:
        if not hasattr(obj, prop):
            rows.append((f"{type(obj).__name__}.{prop}", value, "ABSENT", False))
            return
        setattr(obj, prop, value)
        back = getattr(obj, prop)
        rows.append((f"{type(obj).__name__}.{prop}", value, back, _eq(value, back)))
    except (TypeError, AttributeError) as e:
        rows.append((f"{type(obj).__name__}.{prop}", value, f"REJECTED {e}", False))


def apply_profile(scene, profile, device=None, simplify_override=None, rows=None):
    """Apply one profile to the scene. Returns (device_report, rows); rows is the
    same read-back table `check` prints, so library callers get the audit for free."""
    name = ALIASES.get(profile, profile)
    if name not in PROFILES:
        raise KeyError(f"profile is one of {sorted(PROFILES)} (+ aliases {sorted(ALIASES)}), not {profile!r}")
    q = PROFILES[name]
    own = rows is None
    if own:
        rows = []
    r, cy, vs = scene.render, scene.cycles, scene.view_settings

    # 1. device first: denoising_use_gpu below depends on it
    dev = select_device(scene, device if device is not None else q["device"])

    # 2. engine + the shared no-compromise core
    _setp(rows, r, "engine", "CYCLES")
    _setp(rows, cy, "max_bounces", 6)
    _setp(rows, cy, "diffuse_bounces", 3)
    _setp(rows, cy, "glossy_bounces", 3)
    _setp(rows, cy, "transmission_bounces", 4)
    _setp(rows, cy, "volume_bounces", 2)
    _setp(rows, cy, "transparent_max_bounces", 4)
    _setp(rows, cy, "sample_clamp_indirect", 10.0)
    _setp(rows, cy, "sample_clamp_direct", 0.0)
    _setp(rows, cy, "use_denoising", True)
    _setp(rows, cy, "denoiser", "OPENIMAGEDENOISE")
    _setp(rows, cy, "denoising_input_passes", "RGB_ALBEDO_NORMAL")
    _setp(rows, cy, "denoising_prefilter", q["prefilter"])
    _setp(rows, cy, "denoising_quality", q["denoise_quality"])
    _setp(rows, cy, "denoising_use_gpu", dev["backend"] != "CPU") if hasattr(cy, "denoising_use_gpu") else None
    _setp(rows, r, "compositor_device", "CPU")        # headless-safe: no GL context needed
    if hasattr(r, "compositor_denoise_device"):
        _setp(rows, r, "compositor_denoise_device", "CPU")
    _setp(rows, cy, "seed", 0)
    _setp(rows, cy, "use_animated_seed", True)

    # 3. sampling / time budget
    _setp(rows, cy, "samples", q["samples"])
    _setp(rows, cy, "use_adaptive_sampling", q["adaptive"])
    _setp(rows, cy, "adaptive_threshold", q["adaptive_threshold"])
    _setp(rows, cy, "adaptive_min_samples", q["adaptive_min_samples"])
    _setp(rows, cy, "time_limit", q["time_limit"])

    # 4. memory / VRAM levers
    _setp(rows, r, "use_persistent_data", q["persistent"])
    simp = q["simplify"] if simplify_override is None else simplify_override
    _setp(rows, r, "use_simplify", simp)
    if simp:
        for prop, val in (("simplify_subdivision", 2), ("simplify_subdivision_render", 2),
                          ("simplify_child_particles", 0.5), ("simplify_child_particles_render", 0.5)):
            _setp(rows, r, prop, val)

    # 5. color management: view_transform BEFORE look (the look list depends on it)
    _setp(rows, vs, "view_transform", "AgX")
    _setp(rows, vs, "look", "AgX - Medium High Contrast")
    return dev, rows


def _pbr_advisory(scene):
    """Anti-blockout rule (AGENTS.md): materials should be Principled BSDF. Advisory only.
    Audits bpy.data.materials (Scene has no materials collection; orphans count too)."""
    bad = []
    for m in bpy.data.materials:
        nt = getattr(m, "node_tree", None)
        if nt is None:
            continue
        if not any(n.type == "BSDF_PRINCIPLED" for n in nt.nodes):
            bad.append(m.name)
    return bad


def report(scene):
    r, cy, vs = scene.render, scene.cycles, scene.view_settings
    keys = {
        "engine": r.engine, "device": cy.device, "samples": cy.samples,
        "adaptive": (cy.use_adaptive_sampling, cy.adaptive_threshold, cy.adaptive_min_samples),
        "time_limit": cy.time_limit, "bounces": (cy.max_bounces, cy.diffuse_bounces, cy.glossy_bounces,
                     cy.transmission_bounces, cy.volume_bounces, cy.transparent_max_bounces),
        "clamp": (cy.sample_clamp_indirect, cy.sample_clamp_direct),
        "denoise": (cy.use_denoising, cy.denoiser, cy.denoising_input_passes, cy.denoising_prefilter,
                     getattr(cy, "denoising_quality", "n/a"), getattr(cy, "denoising_use_gpu", "n/a")),
        "persistent": r.use_persistent_data, "simplify": r.use_simplify,
        "compositor": (r.compositor_device, getattr(r, "compositor_denoise_device", "n/a")),
        "color": (vs.view_transform, vs.look), "seed": (cy.seed, cy.use_animated_seed),
    }
    return keys


def _parse_argv():
    """Lenient: sys.argv after `--` is shared with Blender's own Cycles options
    (--cycles-device …), so unknown tokens are ignored, never fatal."""
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"cmd": None, "profile": None, "device": None, "simplify": None, "save": False}
    i = 0
    while i < len(a):
        t = a[i]
        if t in ("probe", "apply", "check", "report") and o["cmd"] is None:
            o["cmd"] = t
        elif t in ("--profile", "-p") and i + 1 < len(a):
            o["profile"] = a[i + 1]; i += 1
        elif t in ("--device", "-d") and i + 1 < len(a):
            o["device"] = a[i + 1]; i += 1
        elif t == "--simplify":
            o["simplify"] = True
        elif t == "--save":
            o["save"] = True
        i += 1
    return o


def main():
    o = _parse_argv()
    sc = bpy.context.scene
    if o["cmd"] == "probe":
        for k in _BACKENDS + ("CPU",):
            dev = select_device(sc, "cpu" if k == "CPU" else k.lower())
            print(f"{k:6s} devices={dev['devices'] or '-'}{' · ' + dev['note'] if dev['note'] else ''}")
        print(f"platform={sys.platform} backends_auto={'>'.join(_BACKENDS)}")
        return 0
    if o["cmd"] == "report":
        for k, v in report(sc).items():
            print(f"{k:11s} {v}")
        return 0
    if o["cmd"] in ("apply", "check"):
        if not o["profile"]:
            print("apply/check need --profile draft|final|final-cpu"); return 2
        dev, rows = apply_profile(sc, o["profile"], device=o["device"], simplify_override=o["simplify"])
        bad = 0
        for key, want, got, okk in rows:
            mark = "ok " if okk else "FAIL"
            if not okk:
                bad += 1
            print(f"[{mark}] {key:42s} want={want!r} got={got!r}")
        print(f"device: backend={dev['backend']} {dev['devices'] or ''}{' · ' + dev['note'] if dev['note'] else ''}")
        unpbr = _pbr_advisory(sc)
        if unpbr:
            print(f"advisory: {len(unpbr)} material(s) without a Principled BSDF (anti-blockout rule, AGENTS.md): {unpbr[:5]}")
        if o["cmd"] == "check":
            print(f"check: {len(rows) - bad}/{len(rows)} settings landed" + ("" if bad else " — profile verified") + (f"; {bad} FAILED" if bad else ""))
            if bad:
                return 1
        if o["save"]:
            bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath) if bpy.data.filepath else None
            print(f"saved {bpy.data.filepath}")
        return 0
    print(__doc__.split("subcommands:")[0] + "subcommands: probe | apply | check | report  (see engines/blender-perf.md)")
    return 2


if __name__ == "__main__" and "--" in sys.argv:
    _rc = main() or 0
    # success falls through: Blender continues to the -a/-f render action in this same
    # process (that is the whole point of the launcher chain). Failure stops Blender
    # here, before any pixel is rendered with wrong settings; combine with
    # --python-exit-code 1 to propagate the code to the shell.
    if _rc:
        sys.exit(_rc)
