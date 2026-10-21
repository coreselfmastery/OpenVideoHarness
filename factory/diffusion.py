"""The picture engines.

 engine=diffusion  LTX-Video 2B text-to-video, one worker process per GPU
                  (both T4s render in parallel, resume-safe, per-shot retry
                  ladder: 768x512/35 -> 640x384/30 -> 512x320/25 steps).
 engine=kenburns   one AI still per shot + a slow camera move (assemble.py).
                  Stills come from the z-ai CLI here, from SD 1.5 on a GPU
                  box — the fill-in engine for any shot diffusion misses.

engine="auto" picks diffusion when torch can see a GPU, kenburns otherwise.
The film always ships: any shot diffusion can't make, kenburns finishes.
"""
from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional

from .assemble import kenburns_clip
from .films_prime import CAMERA, STYLE_STILL

log = logging.getLogger("factory.diffusion")

NEGATIVE = ("text, watermark, logo, subtitle, cartoon, anime, illustration, painting, "
            "drawing, deformed, disfigured, extra limbs, blurry, low quality, worst quality, "
            "jpeg artifacts, oversaturated")

DIFFUSION_STYLE = ("cinematic, photorealistic, 35mm film, moody low-key lighting, "
                   "shallow depth of field, high detail")


def gpu_count() -> int:
    try:
        import torch
        return torch.cuda.device_count()
    except Exception:                                   # noqa: BLE001 — no torch, no GPU
        return 0


def shot_durs(spans: list[float], xfade: float) -> list[float]:
    """Clip durations pre-compensated for their share of the crossfades.

    Every boundary between two neighbouring shots adds one xfade; each shot
    carries half of it, so sum(durs) - (n-1)*xfade = sum(spans) = total.
    """
    n = len(spans)
    if n <= 1:
        return list(spans)
    return [s + (xfade / 2 if i > 0 else 0.0) + (xfade / 2 if i < n - 1 else 0.0)
            for i, s in enumerate(spans)]


# ── stills ────────────────────────────────────────────────────────────────
def _zai_available() -> bool:
    return subprocess.run(["which", "z-ai"], capture_output=True).returncode == 0


def zai_still(prompt: str, out: Path, size: str = "1344x768") -> Optional[Path]:
    """z-ai image CLI with a hard process-group kill on timeout — the node
    CLI sometimes parks after writing the file, holding stdout open."""
    import os
    import signal
    for attempt in range(3):
        try:
            p = subprocess.Popen(["z-ai", "image", "-p", f"{prompt}. {STYLE_STILL}",
                                  "-o", str(out), "-s", size],
                                 stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 text=True, start_new_session=True)
            try:
                p.communicate(timeout=150)
            except subprocess.TimeoutExpired:
                os.killpg(os.getpgid(p.pid), signal.SIGKILL)
                p.communicate()
                raise RuntimeError("z-ai CLI timeout")
            if out.exists() and out.stat().st_size > 20_000:
                return out
            raise RuntimeError(f"z-ai produced no image (rc={p.returncode})")
        except Exception as e:                          # noqa: BLE001
            log.warning("z-ai still %s attempt %d: %s", out.name, attempt + 1, e)
            time.sleep(4)
    return None


def sd15_still(prompt: str, out: Path, width: int = 640, height: int = 384,
               steps: int = 28) -> Optional[Path]:
    """SD 1.5 on the GPU — the diffusion box's own fill-in still maker."""
    _ensure_deps()
    try:
        import torch
        from diffusers import StableDiffusionPipeline
        pipe = StableDiffusionPipeline.from_pretrained(
            "Lykon/realistic-vision-v51", torch_dtype=torch.float16, safety_checker=None)
        pipe = pipe.to("cuda")
        img = pipe(f"{prompt}. {STYLE_STILL}", negative_prompt=NEGATIVE,
                   width=width, height=height, num_inference_steps=steps,
                   generator=torch.Generator("cuda").manual_seed(42)).images[0]
        pipe.to("cpu")
        del pipe
        out.parent.mkdir(parents=True, exist_ok=True)
        img.save(out)
        return out
    except Exception as e:                              # noqa: BLE001
        log.warning("sd15 still failed: %s", e)
        return None


def ensure_still(proj: Path, shot: dict, provider: str = "auto") -> Optional[Path]:
    still = proj / shot["still"]
    if still.exists() and still.stat().st_size > 20_000:
        return still
    if provider == "auto":
        provider = "zai" if _zai_available() else "sd15"
    order = [provider] + [p for p in ("zai", "sd15") if p != provider]
    fns = {"zai": zai_still, "sd15": sd15_still}
    for name in order:
        got = fns[name](shot["prompt"], still)
        if got:
            return got
    return None


# ── diffusion (LTX-Video, both GPUs) ──────────────────────────────────────
DEPS = ["diffusers>=0.32", "transformers>=4.44", "accelerate", "sentencepiece",
        "protobuf", "imageio", "imageio-ffmpeg"]


def _ensure_deps() -> None:
    """The diffusion stack installs itself when missing (Kaggle has internet);
    the notebook that drives this factory predates the engine, so the engine
    carries its own requirements."""
    try:
        import diffusers  # noqa: F401
        import transformers  # noqa: F401
        import imageio_ffmpeg  # noqa: F401
        return
    except ImportError:
        pass
    log.info("installing the diffusion stack: %s", " ".join(DEPS))
    subprocess.run([sys.executable, "-m", "pip", "install", "-q", *DEPS],
                   check=True, stdin=subprocess.DEVNULL)


def render_diffusion(proj: Path, shots: list[dict], steps: int = 30,
                     num_frames: int = 121, width: int = 768, height: int = 512,
                     timeout: int = 45 * 60) -> dict:
    """Spawn one worker per GPU; each renders its interleave of the shots."""
    _ensure_deps()
    n_gpu = gpu_count()
    if n_gpu == 0:
        raise RuntimeError("diffusion engine requested but no CUDA device is visible")
    worker = Path(__file__).resolve().parent / "worker_ltx.py"
    procs: list[subprocess.Popen] = []
    for k in range(n_gpu):
        env = dict(os.environ, CUDA_VISIBLE_DEVICES=str(k),
                   PYTHONUNBUFFERED="1", HF_HUB_ENABLE_HF_TRANSFER="0")
        cmd = [sys.executable, str(worker), "--proj", str(proj), "--gpu-index", str(k),
               "--num-gpus", str(n_gpu), "--steps", str(steps), "--frames", str(num_frames),
               "--width", str(width), "--height", str(height)]
        procs.append(subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE,
                                      stderr=subprocess.STDOUT, text=True, bufsize=1))
    import selectors
    sel = selectors.DefaultSelector()
    for k, p in enumerate(procs):
        if p.stdout:
            sel.register(p.stdout, selectors.EVENT_READ, k)
    t0 = time.time()
    while sel.get_map() and time.time() - t0 < timeout:
        for key, _ in sel.select(timeout=1.0):
            line = key.fileobj.readline()                # buffered -> returns fast
            if line:
                log.info("[gpu%d] %s", key.data, line.rstrip())
            else:                                       # EOF — worker exited
                sel.unregister(key.fileobj)
                k = key.data
                rc = procs[k].wait()
                if rc != 0:
                    log.error("[gpu%d] worker exited rc=%d", k, rc)
    for key in list(sel.get_map()):                     # timeout — sweep
        k = sel.get_map()[key].data
        procs[k].kill()
        log.error("[gpu%d] worker timed out after %ss", k, timeout)
        sel.unregister(sel.get_map()[key].fileobj)
    made = [s["id"] for s in shots if (proj / s["clip"]).exists()]
    return {"engine": "diffusion", "gpus": n_gpu, "clips": made,
            "missing": [s["id"] for s in shots if not (proj / s["clip"]).exists()]}


# ── kenburns ──────────────────────────────────────────────────────────────
def render_kenburns(proj: Path, shots: list[dict],
                     only: Optional[list[str]] = None, stills_provider: str = "auto") -> dict:
    made, missing = [], []
    for shot in shots:
        if only and shot["id"] not in only:
            continue
        clip = proj / shot["clip"]
        if clip.exists() and clip.stat().st_size > 10_000:
            made.append(shot["id"])
            continue
        still = ensure_still(proj, shot, stills_provider)
        if still is None:
            missing.append(shot["id"])
            log.error("no still for %s — shot will be skipped", shot["id"])
            continue
        kenburns_clip(still, clip, shot.get("motion", "in"), float(shot["span"]))
        made.append(shot["id"])
    return {"engine": "kenburns", "clips": made, "missing": missing}


# ── the entry point ───────────────────────────────────────────────────────
def render_shots(proj: Path, engine: str = "auto", timeout: int = 45 * 60) -> dict:
    shots = json.loads((proj / "shots.json").read_text(encoding="utf-8"))
    shots = [s for s in shots if s.get("span")]
    if engine == "auto":
        engine = "diffusion" if gpu_count() else "kenburns"
    log.info("engine: %s (%d shots)", engine, len(shots))
    if engine == "diffusion":
        try:
            report = render_diffusion(proj, shots, timeout=timeout)
            missing = report.get("missing") or []
            if missing:                                 # kenburns finishes the film
                log.warning("diffusion missed %d shots — kenburns fill: %s",
                            len(missing), ",".join(missing))
                fill = render_kenburns(proj, shots, only=missing)
                report["clips"] += fill["clips"]
                report["missing"] = [i for i in fill["missing"]]
                report["fill"] = fill["clips"]
            return report
        except Exception as e:                          # noqa: BLE001
            log.error("diffusion engine failed (%s) — kenburns for everything", e)
    return render_kenburns(proj, shots)


def diffusion_prompt(shot: dict) -> str:
    """Blueprint prompt + camera language + style, for the LTX worker."""
    cam = CAMERA.get(shot.get("motion", "in"), CAMERA["in"])
    return f"{shot['prompt']}. {cam}. {DIFFUSION_STYLE}"
