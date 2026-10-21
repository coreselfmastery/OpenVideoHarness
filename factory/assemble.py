"""The picture, assembled — kenburns clips from stills + the final conform.

Two jobs:
 1. kenburns(still -> clip): one AI still per shot, a slow camera move
    (supersampled zoompan — the anti-jitter trick), exactly the shot's span.
 2. assemble(clips -> master): conform every shot to the film's clock with
    its transition baked in (straight cut, or a 0.45 s dip-to-black at
    chapter boundaries, plus the film's open/close fades), then one simple
    concat + grade pass.

Why concat and not a chained-xfade graph: ffmpeg 7.x deadlocks on chained
xfades (single xfade is fine, the chain stalls forever — verified live).
The concat demuxer over same-parameter clips never stalls, decodes once,
and dip-to-black at chapters reads more like film anyway. All ffmpeg, no
browser, no canvas; identical output on the sandbox and the Kaggle box
(which gets NVENC when the cards answer).
"""
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

log_sh = None  # (kept import-light; logging via pipeline)

W, H, FPS = 1920, 1080, 30
COLOR = ("-color_range", "tv", "-colorspace", "bt709",
         "-color_primaries", "bt709", "-color_trc", "bt709")

# camera moves -> (zoom expr, x expr, y expr) over eased progress [0,1]
EASE = "(0.5-0.5*cos(PI*(on/{Dm1})))"


def _moves(e: str) -> dict:
    cx = "(iw-iw/zoom)/2"
    cy = "(ih-ih/zoom)/2"
    return {
        "in":       (f"1+0.13*{e}",       cx,                              cy),
        "out":      (f"1.13-0.13*{e}",    cx,                              cy),
        "left":     ("1.14",              f"(iw-iw/zoom)*(1-{e})",          cy),
        "right":    ("1.14",              f"(iw-iw/zoom)*{e}",              cy),
        "up":       ("1.14",              cx,                              f"(ih-ih/zoom)*(1-{e})"),
        "down":     ("1.14",              cx,                              f"(ih-ih/zoom)*{e}"),
        "in-left":  (f"1+0.11*{e}",       f"(iw-iw/zoom)*(1-0.8*{e})",      cy),
        "in-right": (f"1+0.11*{e}",       f"(iw-iw/zoom)*(0.8*{e})",        cy),
        "out-up":   (f"1.15-0.15*{e}",    cx,                              f"(ih-ih/zoom)*(1-{e})"),
    }


def kenburns_clip(still: Path, out: Path, motion: str, dur: float,
                  fps: int = FPS, size: tuple[int, int] = (W, H), ffmpeg: str = "ffmpeg",
                  fade_in: float = 0.0, fade_out: float = 0.0) -> Path:
    """One still -> one clip with a slow camera move, eased, supersampled."""
    w, h = size
    frames = max(2, int(round(dur * fps)))
    e = EASE.format(Dm1=frames - 1)
    z, x, y = _moves(e).get(motion, _moves(e)["in"])
    vf = (
        f"crop='min(iw,ih*16/9)':'min(ih,iw*9/16)':'(iw-min(iw,ih*16/9))/2':'(ih-min(ih,iw*9/16))/2',"
        f"scale={w * 2 if w * 2 <= 4608 else 4608}:-2:flags=lanczos,"
        f"zoompan=z='{z}':x='{x}':y='{y}':d={frames}:s={w}x{h}:fps={fps}"
    )
    if fade_in > 0:
        vf += f",fade=t=in:st=0:d={fade_in:.2f}"
    if fade_out > 0:
        vf += f",fade=t=out:st={dur - fade_out:.3f}:d={fade_out:.2f}"
    vf += ",scale=out_range=tv,setparams=range=tv:colorspace=bt709:color_trc=bt709:color_primaries=bt709,format=yuv420p"
    cmd = [ffmpeg, "-y", "-nostdin", "-loglevel", "error", "-framerate", str(fps), "-i", str(still),
           "-vf", vf, "-frames:v", str(frames), "-r", str(fps)]
    cmd += _vcodec(ffmpeg) + list(COLOR) + [str(out)]
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(cmd, check=True, stdin=subprocess.DEVNULL)
    return out


def _probe_dur(path: Path, ffprobe: str = "ffprobe") -> float:
    p = subprocess.run([ffprobe, "-v", "error", "-show_entries", "format=duration",
                        "-of", "default=nw=1:nk=1", str(path)],
                       capture_output=True, text=True, check=True)
    return float(p.stdout.strip())


def nvenc_ok(ffmpeg: str = "ffmpeg") -> bool:
    if shutil.which("nvidia-smi") is None:
        return False
    p = subprocess.run([ffmpeg, "-hide_banner", "-encoders"], capture_output=True, text=True)
    return "h264_nvenc" in p.stdout


def _vcodec(ffmpeg: str = "ffmpeg") -> list[str]:
    return (["-c:v", "h264_nvenc", "-preset", "p7", "-cq", "19", "-rc", "vbr"]
            if nvenc_ok(ffmpeg) else ["-c:v", "libx264", "-crf", "17", "-preset", "faster"])


def normalize_clip(src: Path, out: Path, dur: float, fps: int = FPS,
                   size: tuple[int, int] = (W, H), fade_in: float = 0.0,
                   fade_out: float = 0.0) -> Path:
    """Conform one shot clip to the film's clock: speed, fps, size, length,
    and its baked transition (dip-to-black at chapters, film open/close).

    Diffusion clips come in at 24 fps / ~5.0 s; shots need up to ~6.5 s. A
    retime up to 1.35x reads as intentional slow-motion; beyond that we hold
    the last frame (a documentary beat) instead of dragging the motion.
    """
    w, h = size
    src_dur = _probe_dur(src)
    vf: list[str] = []
    if src_dur > dur * 1.02:                       # too long: play at 1x, trim the tail
        vf.append(f"trim=duration={dur + 0.02:.3f},setpts=PTS-STARTPTS")
    elif src_dur < dur * 0.98:                     # too short: slow into it, then hold
        m = dur / src_dur
        if m <= 1.35:
            vf.append(f"setpts={m:.4f}*PTS")
        else:
            vf.append("setpts=1.35*PTS")
            vf.append(f"tpad=stop_mode=clone:stop_duration={dur - src_dur * 1.35 + 0.05:.3f}")
    if fade_in > 0:
        vf.append(f"fade=t=in:st=0:d={fade_in:.2f}")
    if fade_out > 0:
        vf.append(f"fade=t=out:st={dur - fade_out:.3f}:d={fade_out:.2f}")
    vf.append(f"scale={w}:{h}:flags=lanczos:out_range=tv,setparams=range=tv:colorspace=bt709:color_trc=bt709:color_primaries=bt709,fps={fps},format=yuv420p")
    cmd = ["ffmpeg", "-y", "-nostdin", "-loglevel", "error", "-i", str(src), "-vf", ",".join(vf),
           "-an", "-t", f"{dur:.3f}"]
    cmd += _vcodec() + list(COLOR) + [str(out)]
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(cmd, check=True, stdin=subprocess.DEVNULL)
    return out


def shot_fades(shots: list[dict], i: int, n: int,
               dip: float = 0.45) -> tuple[float, float]:
    """(fade_in, fade_out) for shot i: film open/close + chapter dips."""
    fade_in = 0.8 if i == 0 else (dip if shots[i].get("dip") else 0.0)
    fade_out = 1.25 if i == n - 1 else (dip if i + 1 < n and shots[i + 1].get("dip") else 0.0)
    return fade_in, fade_out


def assemble_master(proj: Path, shots: list[dict], total: float, out: Path,
                    grade: dict, fps: int = FPS, size: tuple[int, int] = (W, H)) -> Path:
    """Conform every shot (transitions baked in) -> concat -> one grade pass."""
    w, h = size
    n = len(shots)
    norm_dir = out.parent / "norm"
    norm_dir.mkdir(parents=True, exist_ok=True)
    for i, sh in enumerate(shots):
        d = float(sh["span"])
        fi, fo = shot_fades(shots, i, n)
        dst = norm_dir / f"{sh['id']}.mp4"
        want = round(d * fps) / fps                # frame-exact target duration
        if not (dst.exists() and abs(_probe_dur(dst) - want) < 0.08):
            normalize_clip(proj / sh["clip"], dst, want, fps=fps, size=size,
                           fade_in=fi, fade_out=fo)

    lst = norm_dir / "list.txt"
    lst.write_text("".join(f"file '{norm_dir}/{sh['id']}.mp4'\n" for sh in shots),
                   encoding="utf-8")
    g = grade or {}
    look = (
        f"eq=contrast={g.get('contrast', 1.06)}:saturation={g.get('saturation', 1.04)},"
        f"colorbalance=rs=-0.02:bs=0.05:rh=0.04:gh=0.02:bh=-0.03,"
        f"vignette=PI/{5 if g.get('vignette', 0.22) else 99},"
        f"setparams=range=tv:colorspace=bt709:color_trc=bt709:color_primaries=bt709,format=yuv420p"
    )
    cmd = ["ffmpeg", "-y", "-nostdin", "-loglevel", "error", "-f", "concat", "-safe", "0",
           "-i", str(lst), "-vf", look, "-r", str(fps)]
    cmd += _vcodec() + list(COLOR) + ["-t", f"{total:.3f}", str(out)]
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(cmd, check=True, stdin=subprocess.DEVNULL)
    return out
