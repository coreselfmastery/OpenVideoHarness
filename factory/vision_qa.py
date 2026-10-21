"""Vision QA — a Groq vision model grades the rendered draft's contact sheet.

The rubric is production-minded: text legibility, contrast, composition,
caption readability, variety, artifacts. The verdict never blocks a delivery
by itself; it is recorded in the report and any score below SHIP_THRESHOLD
marks the film for a human look.
"""
from __future__ import annotations

import logging
from pathlib import Path
from typing import Optional

from .groq_client import GroqClient, GroqError

log = logging.getLogger("factory.vision_qa")

SHIP_THRESHOLD = 6.5

RUBRIC = """You are a strict video QA engineer reviewing a contact sheet of a 2-minute
motivational kinetic-typography video (1920x1080, dark cinematic style).
Tiles are in chronological order, left-to-right, top-to-bottom.

Grade each category 0-10 (10 = flawless):
- text: legibility, size, hierarchy of the on-screen typography
- contrast: text vs background separation everywhere, incl. captions
- composition: balance, alignment, use of the frame, nothing clipped
- captions: subtitle band readability, no overlap with key text
- variety: do the shots differ enough; any monotony or repetition
- artifacts: garbled text, missing glyphs, broken numbers, seams, flashes

Return ONLY JSON:
{"scores": {"text": n, "contrast": n, "composition": n, "captions": n, "variety": n, "artifacts": n},
 "overall": n,              // your holistic 0-10
 "verdict": "ship" | "fix", // "fix" only if a real defect would bother a viewer
 "issues": ["short, concrete problems, empty if none"]}"""


def grade_sheet(client: Optional[GroqClient], sheet_png: str | Path) -> dict:
    """Grade one contact sheet. Returns a QA dict; failures degrade to a noted skip."""
    p = Path(sheet_png)
    if client is None or not p.is_file():
        return {"skipped": True, "reason": "no client or no sheet", "overall": None, "verdict": "skip"}
    try:
        out = client.vision(RUBRIC, p, max_tokens=1200)
    except (GroqError, Exception) as e:  # noqa: BLE001
        log.warning("vision QA unavailable (%s) — recorded as skipped", e)
        return {"skipped": True, "reason": str(e)[:200], "overall": None, "verdict": "skip"}
    scores = out.get("scores") if isinstance(out, dict) else None
    if not isinstance(scores, dict):
        return {"skipped": True, "reason": "unparseable answer", "overall": None, "verdict": "skip"}
    clean = {}
    for k in ("text", "contrast", "composition", "captions", "variety", "artifacts"):
        try:
            clean[k] = round(float(scores.get(k, 0)), 1)
        except (TypeError, ValueError):
            clean[k] = None
    try:
        overall = round(float(out.get("overall", 0)), 1)
    except (TypeError, ValueError):
        overall = None
    verdict = out.get("verdict") if out.get("verdict") in ("ship", "fix") else "skip"
    issues = [str(i)[:160] for i in (out.get("issues") or []) if isinstance(i, str)][:6]
    return {"skipped": False, "scores": clean, "overall": overall, "verdict": verdict,
            "ship_ok": bool(overall is not None and overall >= SHIP_THRESHOLD), "issues": issues}
