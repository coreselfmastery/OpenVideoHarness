#!/usr/bin/env python3
"""LTX-Video worker — one GPU, its interleave of the film's shots.

Run by factory/diffusion.py with CUDA_VISIBLE_DEVICES pinned to one card.
Resume-safe (existing clips are skipped). Per-shot retry ladder:

    768x512 / N steps  ->  640x384 / N-5  ->  512x320 / N-10  ->  give up

Escalation: if shots keep coming back degenerate (the known T5-XXL fp16
NaN behaviour on pre-Hopper cards), the pipeline is reloaded once with the
text encoder in fp32 under CPU offload — slower, numerically safe.

Prints one progress line per event; the factory logs them as [gpuK].
"""
import argparse
import json
import sys
import time
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def load_pipeline(model: str, safe_encoder: bool = False):
    import torch
    import diffusers
    from transformers import T5EncoderModel

    cls = getattr(diffusers, "LTXVideoPipeline", None) or diffusers.LTXPipeline
    if safe_encoder:
        te = T5EncoderModel.from_pretrained(model, torch_dtype=torch.float32,
                                            subfolder="text_encoder")
        pipe = cls.from_pretrained(model, text_encoder=te, torch_dtype=torch.float16)
    else:
        pipe = cls.from_pretrained(model, torch_dtype=torch.float16)
    try:
        pipe = pipe.to("cuda")
    except Exception:                                   # OOM at load — offload
        pipe.enable_model_cpu_offload()
    return pipe


def frames_ok(frames) -> bool:
    """Degenerate-frame guard: black / white / NaN frames mean retry."""
    import numpy as np
    idx = [len(frames) // 4, len(frames) // 2, 3 * len(frames) // 4]
    for i in idx:
        a = np.asarray(frames[i], dtype=np.float32)
        if a.std() < 2.5 or a.mean() < 2.0 or a.mean() > 253.0:
            return False
    return True


def export(frames, path: Path, fps: int) -> None:
    from diffusers.utils import export_to_video
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        export_to_video(frames, str(path), fps=fps, quality=8)
    except TypeError:                                   # older diffusers: no quality kw
        export_to_video(frames, str(path), fps=fps)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--proj", required=True)
    ap.add_argument("--gpu-index", type=int, default=0)
    ap.add_argument("--num-gpus", type=int, default=1)
    ap.add_argument("--steps", type=int, default=30)
    ap.add_argument("--frames", type=int, default=121)
    ap.add_argument("--width", type=int, default=768)
    ap.add_argument("--height", type=int, default=512)
    ap.add_argument("--model", default="Lightricks/LTX-Video")
    a = ap.parse_args()

    proj = Path(a.proj)
    all_shots = json.loads((proj / "shots.json").read_text(encoding="utf-8"))
    mine = [s for i, s in enumerate(all_shots)
            if i % a.num_gpus == a.gpu_index and s.get("span")
            and not (proj / s["clip"]).exists()]
    if not mine:
        print("nothing to do (all clips exist)")
        return

    import torch
    from factory.diffusion import NEGATIVE, diffusion_prompt

    print(f"worker gpu{a.gpu_index}/{a.num_gpus}: {len(mine)} shots, "
          f"{torch.cuda.get_device_name(0)}", flush=True)
    pipe = load_pipeline(a.model)
    safe_mode, degenerate = False, 0

    for shot in mine:
        ladder = [
            dict(width=a.width, height=a.height, steps=a.steps),
            dict(width=640, height=384, steps=max(20, a.steps - 5)),
            dict(width=512, height=320, steps=max(16, a.steps - 10)),
        ]
        clip = proj / shot["clip"]
        t0 = time.time()
        done = False
        for attempt, cfg in enumerate(ladder):
            seed = int(shot.get("seed", 1000)) + attempt
            try:
                gen = torch.Generator("cuda").manual_seed(seed)
                out = pipe(prompt=diffusion_prompt(shot), negative_prompt=NEGATIVE,
                           width=cfg["width"], height=cfg["height"],
                           num_frames=a.frames, num_inference_steps=cfg["steps"],
                           guidance_scale=3.0, generator=gen)
                frames = out.frames[0]
                if torch.is_tensor(frames):
                    frames = [(f.permute(1, 2, 0).cpu().numpy()).astype("uint8") for f in frames]  # noqa: E501
                if not frames_ok(frames):
                    degenerate += 1
                    print(f"DEGENERATE {shot['id']} seed={seed} frames={len(frames)}", flush=True)
                    if not safe_mode and degenerate >= 3:
                        safe_mode = True
                        print("ESCALATE reloading with fp32 text encoder + cpu offload", flush=True)
                        del pipe
                        torch.cuda.empty_cache()
                        pipe = load_pipeline(a.model, safe_encoder=True)
                    if attempt < len(ladder) - 1:
                        continue
                    raise RuntimeError("degenerate frames at every rung")
                export(frames, clip, fps=24)
                (proj / "clips" / f"{shot['id']}.json").write_text(json.dumps(
                    {"seed": seed, "engine": "ltx-video", "w": cfg["width"],
                     "h": cfg["height"], "steps": cfg["steps"],
                     "s": round(time.time() - t0, 1)}))
                print(f"OK {shot['id']} {time.time() - t0:.1f}s "
                      f"{cfg['width']}x{cfg['height']}x{cfg['steps']} seed={seed}", flush=True)
                done = True
                break
            except Exception as e:                      # noqa: BLE001 — the ladder decides
                msg = str(e).replace("\n", " ")[:140]
                print(f"RETRY {shot['id']} rung{attempt} -> {msg}", flush=True)
                torch.cuda.empty_cache()
                if "out of memory" not in msg.lower() and "degenerate" not in msg.lower():
                    traceback.print_exc()
        if not done:
            print(f"FAIL {shot['id']} — kenburns will fill it", flush=True)
        torch.cuda.empty_cache()
    print("worker done", flush=True)


if __name__ == "__main__":
    main()
