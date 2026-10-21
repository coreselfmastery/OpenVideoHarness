"""Project builder v2 — the diffusion/kenburns film layout.

    projects/<slug>/
      film.json          the film (palette, grade, timing, shots with spans)
      shots.json         the shot list as the engines consume it
      audio/script.txt   @id line per narration row
      audio/score.json   the code-composed score
      audio/events.json  sfx placements
      stills/            one PNG per shot (kenburns engine / fallback)
      clips/             one MP4 per shot (diffusion or kenburns renders)
      renders/           the assembled master lands here
      out/               mix.wav, reports, contact sheet

No canvas engine, no index.html — the picture comes from the shot renderer
(diffusion on GPU, kenburns from AI stills anywhere).
"""
from __future__ import annotations

import json
from pathlib import Path


def write_script_txt(proj: Path, script: list[tuple[str, str]]) -> None:
    d = proj / "audio"; d.mkdir(parents=True, exist_ok=True)
    lines = []
    for i, (lid, text) in enumerate(script):
        if i and i % 4 == 0:          # block the requests: prosody stays local
            lines.append("")
        lines.append(f"@{lid} {text}")
    (d / "script.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_score(proj: Path, score: dict) -> None:
    d = proj / "audio"; d.mkdir(parents=True, exist_ok=True)
    (d / "score.json").write_text(json.dumps(score, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


def write_events(proj: Path, events: list[dict]) -> None:
    d = proj / "audio"; d.mkdir(parents=True, exist_ok=True)
    (d / "events.json").write_text(json.dumps(events, indent=1) + "\n", encoding="utf-8")


def build_shots(film: dict) -> list[dict]:
    """Normalize the blueprint's shots: prompt, motion language, seed per shot."""
    shots = []
    for i, sh in enumerate(film["shots"]):
        seed = 1000 + i * 7 + (film.get("seed", 311) % 97)
        shots.append({
            "id": sh["id"], "line": sh.get("line"), "motion": sh.get("motion", "in"),
            "prompt": sh["prompt"], "sfx": sh.get("sfx"), "seed": seed,
            "dip": bool(sh.get("dip")),
            "still": f"stills/{sh['id']}.png", "clip": f"clips/{sh['id']}.mp4",
            "start": None, "span": None,
        })
    return shots


def build_project(film: dict, projects_dir: Path) -> Path:
    proj = projects_dir / film["slug"]
    for d in ("audio", "stills", "clips", "renders", "out"):
        (proj / d).mkdir(parents=True, exist_ok=True)
    write_script_txt(proj, film["script"])
    write_score(proj, film["score"])
    shots = build_shots(film)
    write_shots(proj, shots)
    write_film_json(proj, film, shots)
    return proj


def write_shots(proj: Path, shots: list[dict]) -> None:
    (proj / "shots.json").write_text(json.dumps(shots, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


def read_shots(proj: Path) -> list[dict]:
    return json.loads((proj / "shots.json").read_text(encoding="utf-8"))


def write_film_json(proj: Path, film: dict, shots: list[dict], total: float = 0.0) -> None:
    data = {
        "slug": film["slug"], "title": film["title"],
        "seconds": float(film.get("seconds", 180.0)),
        "total": round(total, 3) if total else None,
        "fps": 30, "width": 1920, "height": 1080,
        "voice": film.get("voice", "en-US-ChristopherNeural"),
        "lead": float(film.get("lead", 4.0)), "tail": float(film.get("tail", 6.0)),
        "palette": film["palette"], "grade": film.get("grade", {}),
        "xfade": 0.6,
        "shots": [{k: sh[k] for k in ("id", "start", "span")} for sh in shots],
    }
    (proj / "film.json").write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


def read_timeline(proj: Path) -> dict:
    return json.loads((proj / "audio" / "timeline.en.json").read_text(encoding="utf-8"))


def plan_shot_spans(total: float, shots: list[dict], timeline: dict,
                    min_span: float = 3.2, snap: float = 0.5) -> list[float]:
    """Even boundaries over the film, snapped to narration line starts when close.

    Returns one span per shot (n entries), summing to exactly `total`.
    """
    line_starts = sorted({float(s["start"]) for s in timeline.get("segments", [])
                          if 0.5 < float(s["start"]) < total - 1.0})
    n = len(shots)
    prev, interior = 0.0, []
    for k in range(1, n):
        ideal = total * k / n
        best, best_d = ideal, snap
        hi = total - min_span * (n - k)          # leave room for the shots after us
        for s in line_starts:
            if s <= prev + min_span or s >= hi or s in interior:
                continue
            if abs(s - ideal) < best_d:
                best, best_d = s, abs(s - ideal)
        b = min(max(best, prev + min_span), hi)
        interior.append(round(b, 3))
        prev = b
    bounds = [0.0] + interior + [total]
    spans = [round(b, 3) for b in sorted(set(bounds))]
    spans = [round(spans[i + 1] - spans[i], 3) for i in range(len(spans) - 1)]
    while len(spans) < n:                        # collapsed bounds: split the longest
        i = max(range(len(spans)), key=lambda j: spans[j])
        spans[i:i + 1] = [round(spans[i] / 2, 3)] * 2
    drift = round(total - sum(spans), 3)         # exact-total insurance on the last shot
    if abs(drift) >= 0.002:
        for i in range(len(spans) - 1, -1, -1):
            if spans[i] + drift >= 1.0:
                spans[i] = round(spans[i] + drift, 3)
                break
    return spans


def finalize_project(proj: Path, film: dict, lead: float, tail: float, target: float = 180.0) -> dict:
    """After TTS: compute the final length, bind spans to shots, write film.json."""
    tl = read_timeline(proj)
    dur = float(tl["duration"])
    total = dur + tail
    shots = read_shots(proj)
    spans = plan_shot_spans(total, shots, tl)
    t = 0.0
    for sh, span in zip(shots, spans):
        sh["start"], sh["span"] = round(t, 3), span
        t += span
    write_shots(proj, shots)
    write_film_json(proj, film, shots, total=total)
    return {"timeline_duration": round(dur, 3), "total": round(total, 3), "tail": round(tail, 3),
            "lead": round(lead, 3), "spans": spans}


def build_sfx_events(film: dict, shots: list[dict], timeline: dict, lead: float, total: float) -> list[dict]:
    """Sparse and tasteful: a riser into the open, an impact at the first word,
    each shot's own hint at its first frame, a ding as the sun rises at the end."""
    ev: list[dict] = []
    last_t = -10.0

    def add(t: float, sfx: str, min_gap: float = 1.2, gain_db: float | None = None) -> None:
        nonlocal last_t
        if t < 0.1 or t > total - 0.2 or t - last_t < min_gap:
            return
        e = {"t": round(t, 2), "sfx": sfx}
        if gain_db is not None:
            e["gain_db"] = gain_db
        ev.append(e)
        last_t = t

    add(0.25, "riser", 0)
    add(max(0.4, lead - 0.35), "impact", 0, -3.0)
    for sh in shots:
        if not sh.get("sfx") or sh.get("start") is None:
            continue
        soft = {"tick": -6.0, "air": -4.0, "whoosh": -3.0, "shimmer": -4.0}.get(sh["sfx"])
        add(float(sh["start"]) + 0.12, sh["sfx"], 1.2, soft)
    add(total - 1.4, "ding", 0, -4.0)
    return ev
