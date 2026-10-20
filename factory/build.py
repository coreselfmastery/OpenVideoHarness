"""Project builder — turns an enriched film dict into an OpenVideoHarness project.

Layout (what the page contract + render-split expect):

    projects/<slug>/
      index.html          the page (data-duration / data-fps / data-start on purpose)
      engine-core.js      copied from factory/
      engine-scenes.js    copied from factory/
      fonts/*.woff2       copied from factory/fonts/
      film.json           the engine's data (palette, scenes, timing knobs)
      audio/script.txt    @id line per narration row
      audio/score.json    the code-composed score
      audio/events.json   sfx placements
      renders/            draft + master land here
      out/                mix.wav, reports
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

FACTORY_ASSETS = Path(__file__).resolve().parent

INDEX_TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=__W__, height=__H__">
<title>__TITLE__</title>
<style>
  /* Bundled OFL fonts (factory/fonts/) — url() faces, loaded explicitly in ready(). */
  @font-face { font-family: "Archivo Black"; src: url(fonts/ArchivoBlack-400.woff2) format("woff2"); font-weight: 400; }
  @font-face { font-family: "Inter"; src: url(fonts/Inter-400.woff2) format("woff2"); font-weight: 400; }
  @font-face { font-family: "Inter"; src: url(fonts/Inter-600.woff2) format("woff2"); font-weight: 600; }
  @font-face { font-family: "Inter"; src: url(fonts/Inter-800.woff2) format("woff2"); font-weight: 800; }
  @font-face { font-family: "Fraunces"; src: url(fonts/Fraunces-600i.woff2) format("woff2"); font-weight: 600; font-style: italic; }
  @font-face { font-family: "JetBrains Mono"; src: url(fonts/JetBrainsMono-500.woff2) format("woff2"); font-weight: 500; }
  @font-face { font-family: "JetBrains Mono"; src: url(fonts/JetBrainsMono-700.woff2) format("woff2"); font-weight: 700; }
  html, body { margin: 0; width: __W__px; height: __H__px; overflow: hidden; background: __BG__; }
  #film { position: absolute; left: 0; top: 0; width: __W__px; height: __H__px; }
</style>
</head>
<!-- data-duration / data-fps / data-start: render-split reads these to cut the film
     on scene boundaries; the engine itself only trusts film.json + the timeline. -->
<body data-duration="__DUR__" data-fps="__FPS__" data-width="__W__" data-height="__H__">
__CUTS__
<canvas id="film" width="__W__" height="__H__"></canvas>
<script src="engine-core.js"></script>
<script src="engine-scenes.js"></script>
</body>
</html>
"""


def write_script_txt(proj: Path, script: list[tuple[str, str]]) -> None:
    d = proj / "audio"; d.mkdir(parents=True, exist_ok=True)
    lines = []
    prev_block = None
    for i, (lid, text) in enumerate(script):
        # blank line every ~4 rows -> --join block keeps prosody local and retryable
        if prev_block is not None and i % 4 == 0:
            lines.append("")
        lines.append(f"@{lid} {text}")
        prev_block = lid
    (d / "script.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_score(proj: Path, score: dict) -> None:
    d = proj / "audio"; d.mkdir(parents=True, exist_ok=True)
    (d / "score.json").write_text(json.dumps(score, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


def copy_engine(proj: Path) -> None:
    for name in ("engine-core.js", "engine-scenes.js"):
        shutil.copy2(FACTORY_ASSETS / name, proj / name)
    src = FACTORY_ASSETS / "fonts"; dst = proj / "fonts"
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)


def write_film_json(proj: Path, film: dict, lead: float, tail: float, timeline_file: str = "audio/timeline.en.json") -> None:
    data = {
        "slug": film["slug"], "title": film["title"],
        "width": 1920, "height": 1080, "fps": 30,
        "palette": film["palette"], "grain": film.get("grain", 0.05),
        "lead": lead, "tail": tail,
        "fadeIn": 0.35, "fadeOut": 0.7,
        "timeline": timeline_file,
        "scenes": film["scenes"],
    }
    (proj / "film.json").write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


def write_index_html(proj: Path, film: dict, duration: float, fps: int, starts: list[float]) -> None:
    """The page, with the split's cut points declared as data-start (scene starts)."""
    pal = film["palette"]
    cuts = "\n".join(
        f'  <span data-start="{s:.3f}"></span>' for s in starts
    )
    html = (INDEX_TEMPLATE
            .replace("__TITLE__", film["title"])
            .replace("__DUR__", f"{duration:.3f}")
            .replace("__FPS__", str(fps))
            .replace("__W__", "1920").replace("__H__", "1080")
            .replace("__BG__", pal["bg0"])
            .replace("__CUTS__", cuts))
    (proj / "index.html").write_text(html, encoding="utf-8")


def write_events(proj: Path, events: list[dict]) -> None:
    d = proj / "audio"; d.mkdir(parents=True, exist_ok=True)
    (d / "events.json").write_text(json.dumps(events, indent=1) + "\n", encoding="utf-8")


def build_project(film: dict, projects_dir: Path) -> Path:
    """Write everything the TTS step needs (script, score, engine, film.json skeleton)."""
    proj = projects_dir / film["slug"]
    proj.mkdir(parents=True, exist_ok=True)
    (proj / "renders").mkdir(exist_ok=True)
    (proj / "out").mkdir(exist_ok=True)
    copy_engine(proj)
    write_script_txt(proj, film["script"])
    write_score(proj, film["score"])
    # placeholder index (real timing lands after TTS) so the folder is inspectable
    write_index_html(proj, film, 0.0, 30, [])
    return proj


def read_timeline(proj: Path) -> dict:
    return json.loads((proj / "audio" / "timeline.en.json").read_text(encoding="utf-8"))


def finalize_project(proj: Path, film: dict, lead: float, tail: float, target: float = 120.0) -> dict:
    """After TTS: compute the final length, write film.json + index.html with cuts."""
    tl = read_timeline(proj)
    dur = float(tl["duration"])
    total = dur + tail
    write_film_json(proj, film, lead=0.0, tail=tail)
    # scene starts for the split: intro (0) + every line start (lead already inside tl) + outro
    starts = [0.0]
    for seg in sorted(tl.get("segments", []), key=lambda s: s["start"]):
        s = float(seg["start"])
        if s > 0.05 and s < total - 0.5:
            starts.append(round(s, 3))
    starts.append(round(dur, 3))  # the outro card
    write_index_html(proj, film, total, 30, sorted(set(starts)))
    return {"timeline_duration": round(dur, 3), "total": round(total, 3), "tail": round(tail, 3),
            "lead": round(lead, 3), "starts": sorted(set(starts))}


def build_sfx_events(film: dict, tl: dict, lead: float) -> list[dict]:
    """Tasteful, sparse: a riser into the title, a whoosh per cut, ticks/pops where the scene earns them."""
    segs = sorted(tl.get("segments", []), key=lambda s: s["start"])
    by_id = {s["id"]: s for s in segs}
    ev: list[dict] = []
    last_t = -10.0

    def add(t: float, sfx: str, min_gap: float = 1.2) -> None:
        nonlocal last_t
        if t < 0.1:
            return
        if t - last_t < min_gap:
            return
        ev.append({"t": round(t, 2), "sfx": sfx})
        last_t = t

    add(0.25, "riser", 0)
    add(max(0.4, lead - 0.35), "impact", 0)
    for sc in film["scenes"]:
        lid = sc.get("line")
        kind = sc.get("kind")
        if not lid or lid not in by_id:
            continue
        a = float(by_id[lid]["start"])
        if kind == "title":
            add(a + 0.30, "swoosh_tonal", 1.5)
        elif kind in ("statement", "compare"):
            add(a + 0.12, "whoosh")
        elif kind == "quote":
            add(a + 0.15, "shimmer", 1.5)
        elif kind == "particles":
            add(a + 0.15, "air", 1.5)
        elif kind == "list":
            for i in range(len(sc.get("items", []))):
                add(a + 0.30 + i * sc.get("step", 0.42), "tick", 0.18)
        elif kind == "stats":
            for i in range(len(sc.get("items", []))):
                add(a + 0.35 + i * 0.38 + 1.0, "pop", 0.25)
    outro_t = float(segs[-1]["end"]) if segs else lead
    add(outro_t + 0.35, "ding", 0)
    return ev
