"""The AI director — Groq-powered enrichment of the deterministic blueprints.

Four independent passes, each fully validated, each falling back to the
blueprint on any failure (network, model, schema, taste):

    1. script  — tighten the narration lines (word budget enforced)
    2. scenes  — emphasis words / accent choices per scene (schema-checked)
    3. score   — bpm/key/energy mood (bounded)
    4. metadata— titles/description/tags for publishing

Nothing here can break the render: unknown keys are dropped, every value is
clamped, and an all-zero or malformed answer is discarded line by line.
"""
from __future__ import annotations

import logging
import re
from typing import Any

from .groq_client import GroqClient, GroqError

log = logging.getLogger("factory.director")

MAX_LINE_GROWTH = 1.35          # a polished line may be at most 35% longer
ALLOWED_KEYS = {"kind", "em", "strike", "word", "sub", "note", "items", "left", "right",
                "head", "title", "kick", "cta", "handle", "who", "text", "outline", "chapter"}
KEYS = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def _words(s: str) -> list[str]:
    return re.findall(r"[A-Za-z0-9''\-]+", s)


class Director:
    def __init__(self, client: GroqClient, enabled: bool = True):
        self.client = client
        self.enabled = enabled

    # ── 1. script polish ──────────────────────────────────────────────────
    def polish_script(self, film: dict) -> list[tuple[str, str]]:
        """Return the (possibly) polished script as [(id, text), ...]."""
        original = film["script"]
        if not self.enabled:
            return list(original)
        sys = ("You are a ruthless script doctor for 120-second motivational YouTube shorts. "
               "Tighten each narration line: sharper verbs, concrete images, no cliches, "
               "keep the exact same meaning and facts. Keep every line's language English. "
               "Do NOT add or remove lines. Return JSON: {\"lines\": [{\"id\": \"...\", \"text\": \"...\"}]} "
               "with one entry per input line, ids exactly as given.")
        user = ("Film: %s\nPremise: %s\n\nLines:\n%s" % (
            film["title"], film["premise"],
            "\n".join(f"{lid}: {txt}" for lid, txt in original))).replace("{{", "{").replace("}}", "}")
        try:
            out = self.client.chat_json(
                [{"role": "system", "content": sys}, {"role": "user", "content": user}],
                temperature=0.4, max_tokens=3000)
            rows = out.get("lines") or []
        except (GroqError, Exception) as e:   # noqa: BLE001 — degrade, never block
            log.warning("script polish unavailable (%s) — blueprint lines ship as-is", e)
            return list(original)
        by_id = {r.get("id"): (r.get("text") or "").strip() for r in rows if isinstance(r, dict)}
        result = []
        changed = 0
        for lid, txt in original:
            new = by_id.get(lid, "").strip()
            if not new:
                result.append((lid, txt)); continue
            if len(_words(new)) > len(_words(txt)) * MAX_LINE_GROWTH + 2:
                log.info("script polish: line %s grew too much, kept original", lid)
                result.append((lid, txt)); continue
            if re.search(r"[\u4e00-\u9fff]", new):
                result.append((lid, txt)); continue
            changed += 1 if new != txt else 0
            result.append((lid, new))
        log.info("script polish: %s/%s lines touched", changed, len(original))
        return result

    # ── 2. scene enrichment ───────────────────────────────────────────────
    def enrich_scenes(self, film: dict, script: list[tuple[str, str]]) -> list[dict]:
        """Let Groq tune emphasis/accents inside the existing scene skeletons."""
        scenes = [dict(s) for s in film["scenes"]]
        if not self.enabled:
            return scenes
        line_scenes = [s for s in scenes if s.get("line")]
        sys = ("You art-direct kinetic-typography scenes for a dark, cinematic, premium YouTube short. "
               "For each narration line you get the scene kind and current params. Choose ONLY: "
               "\"em\": up to 3 words from the narration to color in the accent, "
               "\"strike\": up to 1 word to cross out in red (myth-busting only), "
               "\"sub\": an optional max-8-word caption-style subline (title/particles scenes only). "
               "Never invent numbers. Words must appear verbatim in the narration line. "
               'Return JSON: {"scenes": [{"line": "<id>", "em": ["..."], "strike": [], "sub": "..."}]}')
        user_lines = []
        for s in line_scenes:
            lid = s.get("line")
            txt = next((t for i, t in script if i == lid), "")
            user_lines.append(json_line(lid, s, txt) if False else f"{lid} [{s.get('kind')}]: {txt}")
        try:
            out = self.client.chat_json(
                [{"role": "system", "content": sys},
                 {"role": "user", "content": f"Film: {film['title']}\n\n" + "\n".join(user_lines)}],
                temperature=0.5, max_tokens=2000)
            rows = out.get("scenes") or []
        except Exception as e:  # noqa: BLE001
            log.warning("scene enrichment unavailable (%s) — blueprint scenes ship as-is", e)
            return scenes
        by_line = {r.get("line"): r for r in rows if isinstance(r, dict) and r.get("line")}
        for s in scenes:
            r = by_line.get(s.get("line"))
            if not r:
                continue
            txt = next((t for i, t in script if i == s.get("line")), "")
            words = {w.lower().strip(".,!?:;\"'()") for w in _words(txt)}
            em = [w for w in (r.get("em") or []) if isinstance(w, str) and w.lower().strip(".,!?:;\"'()") in words][:3]
            if em:
                s["em"] = em
            strike = [w for w in (r.get("strike") or []) if isinstance(w, str) and w.lower() in words][:1]
            if strike:
                s["strike"] = strike
            sub = r.get("sub")
            if isinstance(sub, str) and 0 < len(sub.split()) <= 8 and s.get("kind") in ("title", "particles"):
                s["sub"] = sub
        return scenes

    # ── 3. score mood ─────────────────────────────────────────────────────
    def tune_score(self, film: dict) -> dict:
        score = dict(film["score"])
        if not self.enabled:
            return score
        sys = ("You are a film composer choosing mood parameters for a code-synthesised score. "
               "Given the film premise and current score, answer with a small JSON: "
               '{"bpm": int (±12 of current), "key": one of C C# D D# E F F# G G# A A# B, '
               '"mode": "minor"|"major", "energy_bias": float 0.9-1.1 (section energy multiplier), '
               '"why": "one short sentence"}. Keep the drama curve; only tune the mood.')
        try:
            out = self.client.chat_json(
                [{"role": "system", "content": sys},
                 {"role": "user", "content": f"Film: {film['title']}\nPremise: {film['premise']}\nScore now: bpm={score.get('bpm')} key={score.get('key')} mode={score.get('mode')}"}],
                temperature=0.6, max_tokens=300)
            bpm = out.get("bpm")
            if isinstance(bpm, (int, float)) and abs(bpm - score.get("bpm", 90)) <= 14 and 60 <= bpm <= 120:
                score["bpm"] = int(bpm)
            key = out.get("key")
            if isinstance(key, str) and key in KEYS:
                score["key"] = key
            mode = out.get("mode")
            if mode in ("minor", "major"):
                score["mode"] = mode
            bias = out.get("energy_bias")
            if isinstance(bias, (int, float)) and 0.9 <= float(bias) <= 1.1:
                for sec in score.get("sections", []):
                    if isinstance(sec.get("energy"), (int, float)):
                        sec["energy"] = round(min(1.0, max(0.15, sec["energy"] * float(bias))), 3)
            log.info("score mood: %s (why: %s)", (score.get('bpm'), score.get('key'), score.get('mode')), out.get("why"))
        except Exception as e:  # noqa: BLE001
            log.warning("score tuning unavailable (%s) — blueprint score ships as-is", e)
        return score

    # ── 4. publish metadata ───────────────────────────────────────────────
    def metadata(self, film: dict, script: list[tuple[str, str]]) -> dict:
        meta = dict(film.get("metadata") or {})
        if not self.enabled:
            return meta
        sys = ("You write metadata for a 120-second YouTube short about discipline. "
               'Return JSON: {"titles": [3 strings, <=70 chars, high-CTR, no clickbait lies], '
               '"description": "2-3 sentences, includes what the viewer learns", '
               '"tags": [15 lowercase tags]}. Match the film\'s tone: cinematic, premium, direct.')
        try:
            out = self.client.chat_json(
                [{"role": "system", "content": sys},
                 {"role": "user", "content": f"Film: {film['title']}\nPremise: {film['premise']}\nScript:\n" + "\n".join(t for _, t in script)}],
                temperature=0.8, max_tokens=900)
            titles = [t for t in (out.get("titles") or []) if isinstance(t, str) and 10 <= len(t) <= 75][:3]
            if titles:
                meta["titles"] = titles
            desc = out.get("description")
            if isinstance(desc, str) and 60 <= len(desc) <= 600:
                meta["description"] = desc
            tags = [t for t in (out.get("tags") or []) if isinstance(t, str) and 2 <= len(t) <= 30][:15]
            if len(tags) >= 8:
                meta["tags"] = tags
        except Exception as e:  # noqa: BLE001
            log.warning("metadata pass unavailable (%s) — blueprint metadata ships as-is", e)
        return meta


def json_line(lid: str, scene: dict, txt: str) -> str:  # pragma: no cover (unused helper kept simple)
    return f"{lid} [{scene.get('kind')}]: {txt}"


def enrich_film(film: dict, client: GroqClient, enabled: bool = True) -> dict:
    """Run all four passes and return the enriched film dict (a fresh copy)."""
    d = Director(client, enabled=enabled)
    out = dict(film)
    script = d.polish_script(film)
    out["script"] = script
    out["scenes"] = d.enrich_scenes(film, script)
    out["score"] = d.tune_score(film)
    out["metadata"] = d.metadata(film, script)
    return out
