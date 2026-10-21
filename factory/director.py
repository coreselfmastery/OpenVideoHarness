"""The AI director, v2 — Groq passes over the shot list, each validated,
each falling back to the blueprint. The script and the score are the
blueprint's (deterministic); what Groq polishes is cinematography and
publish metadata.
"""
from __future__ import annotations

import logging
import re

from .groq_client import GroqClient

log = logging.getLogger("factory.director")

BANNED = re.compile(r"\b(text|watermark|logo|brand|caption|subtitle)\b", re.I)
STOP = set("a an the of in on at with his her their its and or into over under "
           "from for to is are was were very slow one only now then".split())


def _content_words(s: str) -> set[str]:
    return {w for w in re.findall(r"[a-z]{4,}", s.lower()) if w not in STOP}


def polish_shots(film: dict, client: GroqClient) -> list[dict]:
    """One pass: every shot prompt rewritten as art direction for a text-to-video
    model — keep the subject and the camera move, deepen the cinematography."""
    shots = film["shots"]
    lines = "\n".join(f'  "{s["id"]}": {{"motion": "{s["motion"]}", "prompt": {s["prompt"]!r}}}'
                      for s in shots)
    sys = ("You are a cinematographer rewriting shot prompts for a text-to-video diffusion "
           "model (LTX-Video). Keep each shot's SUBJECT and CAMERA MOVE exactly. Make the "
           "image richer: lens, light, atmosphere, texture, film language. 25-45 words per "
           "shot. No character names, no brands, no text-in-image. Return ONLY a JSON object "
           '{"<shot id>": "<new prompt>", ...} with every shot id present.')
    usr = (f"The film: {film['title']} — {film['premise']}\nLook: moody, disciplined, "
           f"cold blue hour with warm amber accents, photorealistic 35mm.\nShots:\n{lines}")
    try:
        data = client.chat_json([{"role": "system", "content": sys},
                                 {"role": "user", "content": usr}])
    except Exception as e:                              # noqa: BLE001
        log.warning("shot polish failed (%s) — blueprint prompts ship", e)
        return shots
    out = []
    for sh in shots:
        got = data.get(sh["id"])
        if not isinstance(got, str):
            got = None
        if got:
            got = " ".join(got.split())
            orig = _content_words(sh["prompt"])
            if (25 <= len(got) <= 320 and not BANNED.search(got)
                    and len(orig & _content_words(got)) >= max(2, len(orig) // 4)):
                sh = dict(sh, prompt=got)
            else:
                log.info("shot %s polish rejected (validation) — keeping blueprint", sh["id"])
        out.append(sh)
    log.info("shot polish: %d shots", sum(1 for a, b in zip(shots, out) if a["prompt"] != b["prompt"]))
    return out


def metadata(film: dict, client: GroqClient) -> dict:
    base = film.get("metadata", {})
    try:
        return client.chat_json([
            {"role": "system", "content": "You write YouTube metadata for cinematic "
                                          "motivational shorts. Return ONLY JSON."},
            {"role": "user", "content":
                f"Film: {film['title']} — {film['premise']}\n"
                'Return {"titles": [3 strings, <=90 chars], "description": string '
                "(2-4 sentences, no hashtags), \"tags\": [12-16 strings]}"},
        ]) or base
    except Exception as e:                              # noqa: BLE001
        log.warning("metadata pass failed (%s) — blueprint ships", e)
        return base


def enrich_film(film: dict, client: GroqClient, enabled: bool = True) -> dict:
    if not enabled:
        return dict(film)
    film = dict(film)
    film["shots"] = polish_shots(film, client)
    film["metadata"] = metadata(film, client)
    return film
