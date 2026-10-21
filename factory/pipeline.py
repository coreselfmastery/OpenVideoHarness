"""The pipeline v2 — one film from blueprint to delivered MP4, real engines.

Same contract as v1 (Factory / FactoryConfig / Report / make_film — the
Kaggle notebook drives it unchanged), new picture path:

    director -> build -> tts -> timing -> music -> sfx -> mix -> audio-qa
    -> SHOTS (LTX-Video on every GPU, kenburns fill) -> assemble (xfades,
    grade, grain) -> mux + check + deliver

Sound-first, as ever: the narration is synthesized before the picture, the
film's length is the voice's length plus the tail, every shot boundary lands
on a narration edge. A failed optional stage is recorded, never fatal; the
core stages mark the film failed and the factory moves on.
"""
from __future__ import annotations

import json
import logging
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from . import build
from .assemble import assemble_master, nvenc_ok
from .diffusion import render_shots
from .groq_client import GroqClient
from .vision_qa import grade_sheet

log = logging.getLogger("factory.pipeline")


@dataclass
class FactoryConfig:
    target_seconds: float = 180.0        # a film blueprint with "seconds" wins
    engine: str = "auto"                 # auto | diffusion | kenburns
    final_tier: str = "final"            # final (1080p) | beast (720p)
    draft_qa: bool = True                # contact sheet + Groq vision rubric
    gap: float = 0.42                    # narration line spacing (s)
    tail_min: float = 1.4
    tail_max: float = 12.0
    tail_target: float = 6.0
    music_db: float = -7.0
    lufs: float = -14.0
    xfade: float = 0.6
    width: int = 1920
    height: int = 1080
    fps: int = 30
    deliver_for: str = "youtube"
    shots_timeout: int = 6 * 3600        # diffusion gets the session, not 50 min
    stage_timeout: int = 45 * 60         # every non-engine stage
    keep_drafts: bool = True


@dataclass
class Report:
    slug: str
    title: str
    ok: bool = False
    stages: dict = field(default_factory=dict)
    files: dict = field(default_factory=dict)
    notes: list = field(default_factory=list)
    qa: dict = field(default_factory=dict)
    metadata: dict = field(default_factory=dict)
    error: Optional[str] = None
    seconds: float = 0.0

    def as_dict(self) -> dict:
        return {"slug": self.slug, "title": self.title, "ok": self.ok,
                "stages": self.stages, "files": self.files, "notes": self.notes,
                "qa": self.qa, "metadata": self.metadata, "error": self.error,
                "seconds": round(self.seconds, 1)}


class Factory:
    def __init__(self, ovh_root: Path, factory_root: Path, work_root: Path,
                 groq: Optional[GroqClient] = None, config: Optional[FactoryConfig] = None):
        self.ovh = Path(ovh_root).resolve()
        self.factory_root = Path(factory_root).resolve()
        self.work = Path(work_root).resolve()
        self.work.mkdir(parents=True, exist_ok=True)
        self.projects = self.ovh / "projects"
        self.projects.mkdir(parents=True, exist_ok=True)
        self.groq = groq
        self.cfg = config or FactoryConfig()
        self.out_root = self.work / "films"
        self.out_root.mkdir(parents=True, exist_ok=True)

    # ── process plumbing ──────────────────────────────────────────────────
    def sh(self, cmd: str, timeout: Optional[int] = None, check: bool = True) -> subprocess.CompletedProcess:
        wrapped = (
            f'set -e; source "{self.ovh}/.kaggle/env.sh" 2>/dev/null || true; '
            f'cd "{self.ovh}"; {cmd}'
        )
        log.info("$ %s", cmd)
        p = subprocess.run(["bash", "-c", wrapped], capture_output=True, text=True,
                           timeout=timeout or self.cfg.stage_timeout, stdin=subprocess.DEVNULL)
        if p.stdout:
            log.debug("stdout: %s", p.stdout[-2000:])
        if p.returncode != 0 and check:
            log.error("stage failed (rc=%s): %s", p.returncode, p.stderr[-1500:])
            raise RuntimeError(f"command failed ({p.returncode}): {cmd[:160]}\n{p.stderr[-1200:]}")
        return p

    def _stage(self, rep: Report, name: str, fn, *a, optional: bool = False, **kw):
        t0 = time.time()
        try:
            out = fn(*a, **kw)
            rep.stages[name] = {"ok": True, "s": round(time.time() - t0, 1)}
            return out
        except Exception as e:  # noqa: BLE001
            rep.stages[name] = {"ok": False, "s": round(time.time() - t0, 1), "error": str(e)[:400]}
            if optional:
                rep.notes.append(f"{name} failed (non-fatal): {str(e)[:160]}")
                log.warning("stage %s failed (optional): %s", name, e)
                return None
            rep.error = f"{name}: {str(e)[:300]}"
            raise

    # ── stages ────────────────────────────────────────────────────────────
    def s_director(self, film: dict) -> dict:
        if self.groq is None:
            log.info("director: offline mode — blueprint ships as-is")
            return dict(film)
        from .director import enrich_film
        return enrich_film(film, self.groq, enabled=True)

    def s_tts(self, proj: Path, film: dict, gap: float) -> dict:
        voice = film.get("voice", "en-US-ChristopherNeural")
        lead = float(film.get("lead", 4.0))
        p = self.sh(f'bin/vh tts "{proj}" edge {voice} en --gap {gap} --lead {lead}')
        tl = build.read_timeline(proj)
        return {"timeline": tl, "log_tail": p.stdout[-600:]}

    def _adapt(self, proj: Path, film: dict, rep: Report, target: float) -> dict:
        """Measure the narration; one gap-retry if we're far from target; the tail."""
        cfg = self.cfg
        gap = float(film.get("gap", cfg.gap))
        tl = build.read_timeline(proj)
        dur = float(tl["duration"])
        n = len(tl.get("segments", [])) or 1
        want = target - cfg.tail_target
        if dur > want + 3.0:                      # too long: tighten the gaps once
            new_gap = max(0.22, gap - (dur - want) / max(1, n - 1))
            rep.notes.append(f"narration {dur:.1f}s > target; retry with gap {new_gap:.2f}s")
            self.s_tts(proj, film, round(new_gap, 2))
            tl = build.read_timeline(proj); dur = float(tl["duration"])
        elif dur < want - 7.0:                    # too short: breathe more
            new_gap = min(1.05, gap + (want - dur) / max(1, n - 1))
            rep.notes.append(f"narration {dur:.1f}s < target; retry with gap {new_gap:.2f}s")
            self.s_tts(proj, film, round(new_gap, 2))
            tl = build.read_timeline(proj); dur = float(tl["duration"])
        tail = min(max(target - dur, cfg.tail_min), cfg.tail_max)
        info = build.finalize_project(proj, film, lead=float(film.get("lead", 4.0)),
                                      tail=tail, target=target)
        rep.notes.append(f"length: narration {dur:.1f}s + tail {tail:.1f}s = {info['total']:.1f}s")
        return info

    def s_music(self, proj: Path, total: float) -> Path:
        out = proj / "audio" / "music.wav"
        self.sh(f'bin/vh music "{proj}/audio/score.json" "{out}" --length {total + 1.5:.1f}')
        return out

    def s_sfx(self, proj: Path, film: dict, shots: list, tl: dict, lead: float, total: float) -> Path:
        events = build.build_sfx_events(film, shots, tl, lead, total)
        build.write_events(proj, events)
        out = proj / "audio" / "sfx.wav"
        self.sh(f'bin/vh sfx place "{proj}/audio/events.json" "{out}" {total:.1f}')
        return out

    def s_mix(self, proj: Path) -> Path:
        out = proj / "out" / "mix.wav"
        self.sh(f'bin/vh mix "{out}" voice="{proj}/audio/voiceover.en.wav" music="{proj}/audio/music.wav" '
                f'sfx="{proj}/audio/sfx.wav" music_db={self.cfg.music_db} lufs={self.cfg.lufs}')
        return out

    def s_qa_audio(self, proj: Path) -> Optional[str]:
        p = self.sh(
            f'bin/vh qa "{proj}/out/mix.wav" "{proj}/audio/music.beats.json" "{proj}/audio/events.json" '
            f'--voice "{proj}/audio/voiceover.en.wav"', check=False)
        return p.stdout[-800:] if p.returncode == 0 else f"qa flagged issues:\n{p.stdout[-800:]}"

    def s_shots(self, proj: Path) -> dict:
        return render_shots(proj, engine=self.cfg.engine,
                            timeout=self.cfg.shots_timeout
                            if self.cfg.engine == "diffusion" else self.cfg.stage_timeout)

    def s_assemble(self, proj: Path, film: dict, info: dict, report: dict) -> Path:
        shots = build.read_shots(proj)
        shots = [s for s in shots if s.get("span")]
        have = [s for s in shots if (proj / s["clip"]).exists()]
        if len(have) < max(2, len(shots) * 2 // 3):
            raise RuntimeError(f"only {len(have)}/{len(shots)} shot clips exist — cannot assemble")
        # fill any straggler: span, no clip -> kenburns from a still
        from .diffusion import render_kenburns
        missing = [s["id"] for s in shots if not (proj / s["clip"]).exists()]
        if missing:
            log.warning("assembling with kenburns fill for: %s", ",".join(missing))
            render_kenburns(proj, shots, only=missing)
        total = float(info["total"])
        tier = self.cfg.final_tier
        w, h = (self.cfg.width, self.cfg.height) if tier != "beast" else (1280, 720)
        out = proj / "renders" / f"{film['slug']}-master.mp4"
        return assemble_master(proj, shots, total, out, film.get("grade", {}),
                               fps=self.cfg.fps, size=(w, h))

    def s_sheet(self, video: Path, proj: Path) -> Optional[Path]:
        out = proj / "out" / "sheet.png"
        p = self.sh(f'bin/vh sheet "{video}" 6 0.2 "{out}"', check=False)
        return out if out.exists() else None

    def s_vision(self, sheet: Optional[Path]) -> dict:
        if not self.cfg.draft_qa or sheet is None:
            return {"skipped": True}
        return grade_sheet(self.groq, sheet)

    def s_deliver(self, proj: Path, master: Path, slug: str) -> dict:
        final = self.out_root / f"{slug}-final.mp4"
        self.sh(f'bin/vh mux "{master}" "{proj}/out/mix.wav" "{final}"')
        chk = self.sh(f'bin/vh check "{final}"', check=False)
        delivered = None
        try:
            dy = self.out_root / f"{slug}-{self.cfg.deliver_for}.mp4"
            self.sh(f'bin/vh deliver "{final}" --for {self.cfg.deliver_for} --crf 16')
            for cand in (self.ovh / f"{slug}-{self.cfg.deliver_for}.mp4",
                         proj / "out" / f"{slug}-{self.cfg.deliver_for}.mp4",
                         Path.cwd() / f"{slug}-{self.cfg.deliver_for}.mp4"):
                if cand.exists():
                    delivered = cand
                    break
        except Exception as e:  # noqa: BLE001
            log.warning("deliver failed (non-fatal): %s", e)
        return {"final": str(final), "check_rc": chk.returncode,
                "check_tail": chk.stdout[-1000:], "delivered": str(delivered) if delivered else None}

    # ── the whole film ────────────────────────────────────────────────────
    def make_film(self, film: dict) -> Report:
        rep = Report(slug=film["slug"], title=film["title"])
        t0 = time.time()
        proj = self.projects / film["slug"]
        try:
            target = float(film.get("seconds", self.cfg.target_seconds))
            if abs(target - self.cfg.target_seconds) > 0.5:
                rep.notes.append(f"blueprint length {target:.0f}s overrides config "
                                 f"{self.cfg.target_seconds:.0f}s")

            enriched = self._stage(rep, "director", self.s_director, film, optional=True) or dict(film)
            rep.metadata = enriched.get("metadata") or {}

            self._stage(rep, "build", build.build_project, enriched, self.projects)
            self._stage(rep, "tts", self.s_tts, proj, enriched, float(enriched.get("gap", self.cfg.gap)))
            info = self._stage(rep, "timing", self._adapt, proj, enriched, rep, target)
            total = info["total"]
            tl = info.get("timeline") or build.read_timeline(proj)
            shots = build.read_shots(proj)

            self._stage(rep, "music", self.s_music, proj, total)
            self._stage(rep, "sfx", self.s_sfx, proj, enriched, shots, tl,
                        float(enriched.get("lead", 4.0)), total)
            self._stage(rep, "mix", self.s_mix, proj)
            self._stage(rep, "audio-qa", self.s_qa_audio, proj, optional=True)

            report = self._stage(rep, "shots", self.s_shots, proj) or {}
            master = self._stage(rep, "assemble", self.s_assemble, proj, enriched, info, report)

            sheet = self._stage(rep, "sheet", self.s_sheet, master, proj, optional=True)
            rep.qa = self._stage(rep, "vision-qa", self.s_vision, sheet, optional=True) or {}

            out = self._stage(rep, "deliver", self.s_deliver, proj, master, film["slug"])
            rep.files = {"final": out.get("final"), "delivered": out.get("delivered"),
                         "master": str(master), "mix": str(proj / "out" / "mix.wav"),
                         "sheet": str(proj / "out" / "sheet.png"),
                         "check": (out.get("check_rc"))}
            rep.ok = bool(out.get("final"))
        except Exception as e:  # noqa: BLE001
            rep.ok = False
            if not rep.error:
                rep.error = str(e)[:400]
            log.error("film %s failed: %s", film["slug"], e)
        finally:
            rep.seconds = time.time() - t0
        return rep

    def run_all(self, films: list[dict]) -> list[Report]:
        reps = []
        for i, film in enumerate(films, 1):
            log.info("── film %s/%s: %s ──", i, len(films), film["title"])
            rep = self.make_film(film)
            reps.append(rep)
            print(f"[{i}/{len(films)}] {'OK ' if rep.ok else 'FAIL'} {rep.title} "
                  f"in {rep.seconds:.0f}s — {rep.files.get('final') or rep.error}")
        self.write_report(reps)
        return reps

    def write_report(self, reps: list[Report]) -> Path:
        path = self.work / "report.json"
        data = {"films": [r.as_dict() for r in reps],
                "ok": sum(1 for r in reps if r.ok), "total": len(reps),
                "nvenc": nvenc_ok()}
        path.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        return path
