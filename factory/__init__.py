"""groq-film-factory — production film pipeline on top of OpenVideoHarness.

The factory turns film blueprints (factory/films_part*.py) into finished,
platform-ready 2-minute videos on Kaggle's 2x T4 boxes:

    blueprint ──▶ AI director (Groq: script polish, scene data, score mood,
                  metadata) ──▶ OVH project (page-contract engine) ──▶ edge-tts
                  narration ──▶ code-composed score + sfx ──▶ mix (-14 LUFS)
                  ──▶ draft render + Groq vision QA ──▶ final render on both
                  T4s (render-split, NVENC p7 cq19) ──▶ mux, check, deliver.

Every Groq step degrades gracefully to the deterministic blueprint, so the
pipeline produces the films even with no API key at all.
"""

from .films_part1 import FILMS_1_3
from .films_part2 import FILMS_4_5

FILMS = FILMS_1_3 + FILMS_4_5

__all__ = ["FILMS"]
__version__ = "1.0.0"
