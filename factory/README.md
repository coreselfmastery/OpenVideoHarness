# factory — the discipline film factory (lives inside OpenVideoHarness)

**Production-ready 2-minute videos about discipline, made on Kaggle's 2×T4, with Groq as the creative AI.**

The factory is a thin, sturdy layer on top of [OpenVideoHarness](https://github.com/coreselfmastery/OpenVideoHarness)
(the video-as-code workbench: page-contract rendering, TTS, code-composed music, mixing, delivery checks)
and speaks its language end to end — `--tier final`, `render-split` across both T4s, `bin/vh check`, the works.

```
blueprint ──▶ Groq director ──▶ edge-tts narration ──▶ adaptive timing (120.0 s exact)
   │         (script polish,      (free, fast)           │
   │          scene art,                                   ▼
   │          score mood,                        code-composed score + SFX
   │          publish metadata)                          │
   │                                                    ▼
   │                                    3-bus mix at −14 LUFS + audio QA
   │                                                    │
   │                                    720p draft → contact sheet → Groq vision QA
   │                                                    │
   ▼                                                    ▼
 deterministic engine ◀────────────────────  final 1080p render, both T4s
 (page-contract canvas:                            (NVENC p7/cq19, one card per half,
  8 scene kinds, palettes,                          determinism gate, stream-copy join)
  kinetic typography, captions)                              │
                                                    mux → check → YouTube copy → metadata
```

## The five films

| # | Film | Angle | Voice | Palette |
|---|------|-------|-------|---------|
| 1 | **Discipline Beats Motivation** | the science of showing up | Aria | deep navy · electric cyan |
| 2 | **The 1% Rule** | compounding math (1.01^365 = 37.8) | Guy | black · gold |
| 3 | **Deep Work** | focus as the rarest skill | Christopher | charcoal · emerald |
| 4 | **Discipline Is Freedom** | the Stoic paradox | Jenny | oxblood · crimson |
| 5 | **66 Days** | the habit myth, corrected | Michelle | indigo · violet |

Every blueprint is **deterministic and complete on its own** — script (word-budgeted for a 120 s
master), one scene plan per narration line, palette, score, publish metadata. The Groq director
enriches; it never replaces. With no API key at all, the factory still ships all five films.

## Run it on Kaggle

1. Open the notebook: `../notebook/discipline-films.ipynb` (or the kernel on Kaggle).
2. Settings: **Accelerator → GPU T4 x2**, **Internet → On**.
3. Run all. Cold boot ~5–10 min (Node 22, Chrome, NVENC probes — cached in `/kaggle/working`
   afterwards); the five films then take ~60–100 min total.
4. Outputs land in `/kaggle/working/discipline-films/`: `-final.mp4` masters (1080p30, BT.709,
   −14 LUFS), YouTube copies, covers, `metadata.json` (titles/description/tags), `report.json`.

### Changing things

- **Groq model** — `GROQ_TEXT_MODEL`/`GROQ_VISION_MODEL` or the preference lists in the
  notebook's config cell; `"auto"` resolves against the live `/models` at boot. A brand-new
  model goes at the front of a list, and that's the whole change.
- **Topic/content** — `factory/films_part1.py` / `films_part2.py` (the blueprints).
- **The look** — `factory/engine-core.js` (backgrounds, captions, timing) and
  `factory/engine-scenes.js` (the eight scene kinds).
- **Quality tier** — `FINAL_TIER = "beast"` for the 720p one-tier ship grade (~2× faster).

## What's inside

```
factory/
  engine-core.js     the page-contract engine (pure function of t — passes bin/vh determinism)
  engine-scenes.js   the eight scene kinds: title · statement · stats · compare · list · quote · particles · outro
  films_part1.py     films 1–3 (scripts, scenes, palettes, scores, metadata)
  films_part2.py     films 4–5
  groq_client.py     httpx-only Groq client: chat, JSON mode, vision, retries, model auto-detect
  director.py        the four AI passes — every one validated, every one falls back to the blueprint
  vision_qa.py       contact-sheet QA rubric through a Groq vision model
  build.py           project builder (index.html with data-start cuts, script.txt, score, events)
  pipeline.py        the orchestrator: stage timing, adaptive gap retry, per-film isolation
  fonts/             bundled OFL fonts (Archivo Black, Inter, Fraunces, JetBrains Mono)
tests/
  engine_harness.js  boots the engine with a synthetic timeline and draws every frame (no browser needed)
notebook/
  discipline-films.ipynb   the runnable Kaggle kernel
  kernel-metadata.json
```

## Validation already done (locally, before any push)

- engine harness: all five films, every frame + cut boundary drawn, contract exports verified
- real-Chrome renders at 1080p (title/statement/stats/quote/list scenes) + VLM inspection: 8–10/10
- real edge-tts narration, adaptive timing landing the master at **exactly 120.0 s**
- all five music scores rendered by OpenVideoHarness's score engine (schema-valid)
- SFX placement, 3-bus mix at −14 LUFS, audio QA green (0 dropouts / 0 pumping / 0 clicks)
- `bin/vh check` on a muxed excerpt: spec ✓, no black/freeze/silence ✓, colour tags ✓

## License

MIT (the repo's code). Bundled fonts are under their own OFL licenses in `factory/fonts/`.


> This module lives inside the OpenVideoHarness checkout (the notebook clones one repo).
> A standalone mirror repo, coreselfmastery/groq-film-factory, exists on GitHub for the day
> the PAT's repository list is widened — copy this directory over verbatim.
