"""The Discipline Film Factory v2 — real engines.

One blueprint (films_prime), many picture engines:
LTX-Video diffusion on the Kaggle 2x T4 box, AI-still kenburns everywhere.
The audio stack (edge-tts narration, code-composed score, synthesized foley,
3-bus mix at -14 LUFS) is OpenVideoHarness's own and unchanged.
"""
from .films_prime import FILM_PRIME
from .pipeline import Factory, FactoryConfig, Report

# The notebook runs every film in this list; v2 is the 3-minute flagship.
FILMS = [FILM_PRIME]

__all__ = ["FILMS", "FILM_PRIME", "Factory", "FactoryConfig", "Report"]
