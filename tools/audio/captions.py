"""Captions from a TTS timeline → SRT (zh / en / bilingual) + captions.json for engines.

usage (via bin/vh captions): python tools/audio/captions.py <project_dir> [--lang zh|en] [--zh-max 16] [--en-max 42] [--media-end S]
                                                            [--cards] [--cps 9] [--skip-lint]
(--zh-max counts full-width characters, a half-width one as half; --en-max counts characters, spaces included)

Reads audio/timeline.<lang>.json (or audio/timeline.json) written by bin/vh tts. Writes into <project>/audio/:
  captions.zh.srt, captions.en.srt (when that side exists), captions.bi.srt (zh line + en line) and
  captions.json: [{"id","start","end","zh":[lines],"en":[lines]}] — engines burn captions in from this file
  (HyperFrames / p5 / ManimGX read it; every caption stays a pure function of t).
Soft subtitle tracks for players/platforms: bin/vh mux <video> <audio> <out> audio/captions.zh.srt audio/captions.en.srt
Vertical video: pass --zh-max 11 (72 px in the 810 px safe box).
Word timing (timeline from bin/vh tts … --align gemini, elevenlabs or minimax): each captions.json item also gets
  "words": [{"w","start","end"}] (narrated side, absolute seconds) for karaoke / pop-in captions, and
  captions.<lang>.lines.srt splits every caption into one cue per wrapped line, each starting when its first word is
  spoken, so a long line no longer sits on screen as a two-line block for its whole duration.
Minimum duration: a caption shorter than the subtitle floor (readcheck.SUB_FLOOR, 1.8 s; a one-line "Take a square
  wave." is spoken in 1.1 s) has its end moved into the silence after it, never its start: up to 1.8 s, or as far as the
  next caption's start minus 0.1 s, or the end of the media, whichever comes first. The media end is the length of the
  picture, which runs past the last spoken word: --media-end S, else the composition's root data-duration in
  <project>/index.html, else the length of <project>/media/final.mp4 (ffprobe), else the timeline's "duration".
  Every file above carries the extended end (the .lines.srt too: its last line ends with the caption), and captions.json
  keeps the spoken end as "speech_end" on the items it moved. A caption the gap cannot lengthen to 1.8 s is listed on
  stdout (bin/vh readcheck <project> --mode subtitle fails it too). The timeline itself is not touched.
  audio/captions.args.json keeps the mode, widths, --cps and --media-end of the run, and bin/vh pace makes the captions again
  with them.
Breaks (tools/audio/capbreak.py): at word boundaries (jieba, which bin/vh captions brings through uv when it can; without
  it Latin words and numbers stay whole and a break may fall between any two Chinese characters), chosen by dynamic
  programming: the fewest lines, then even widths, breaks after a comma or a pause, none that leaves 把/是… at a line's end
  or 了/的… at its start, no word or two stranded after a pause. audio/capbreaks.json (a list of phrases, or {line id:
  [phrases]}) starts a new piece at each phrase (in wrapped captions, only where a caption needs more than one line).
--cards: one line per caption instead of a block of wrapped lines: each narration line is cut into cards at the same
  breaks, never across a sentence end (。？！…, and a Latin . ? ! that no ASCII letter or digit follows), each card timed
  from its first word (0.1 s early), the last one held 0.8 s into the pause; pauses show as a space and the closing
  punctuation goes (？！… stay). A card shorter than its minimum is joined to the next card of the same sentence when the
  two fit on one line, else to the one before it, else it borrows the pause after it. A card that would start after the
  media end is left out and listed. The narrated language only (captions.<lang>.srt and captions.json, each item with
  its "part"; the files only the other mode writes, captions.*.lines.srt, captions.bi.srt and the other language's
  .srt, are removed, so an old one is not muxed by mistake).
Minimum, in both modes: readcheck's subtitle rule with --cps in place of its 9 a second for Chinese: the floor (1.8 s),
  or Chinese at --cps characters a second (half-width ones count half), or any other text at 20 a second, whichever is
  longer. Two captions less than 0.25 s apart touch (the first runs on to the second), so the caption band does not
  blink for a frame.
A timeline that fails bin/vh timeline (tools/audio/timeline_lint.py: lines out of order, word times out of place, words
  that do not spell the line) is refused, exit 1, since the captions take their times from it: --skip-lint goes on.
"""
import argparse, json, math, re, subprocess, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from readcheck import SUB_CPS_CJK, SUB_CPS_LATIN, SUB_FLOOR, composition_duration, is_cjk   # readcheck's subtitle rule, shared

CUE_GAP = 0.1   # seconds left between an extended caption and the next one
TOUCH = 0.25    # captions closer than this touch: no one-frame blink between them
LEAD, HOLD = 0.1, 0.8   # --cards: a card shows this much before its first word; the last of a line stays this far into the pause
sys.path.insert(0, str(Path(__file__).resolve().parent))
import capbreak

def ts(t: float) -> str:
    ms = int(round(t * 1000)); h, ms = divmod(ms, 3600000); m, ms = divmod(ms, 60000); s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"

def wrap_zh(text: str, n: int, line_id=None, table=None):
    """Wrap Chinese to <= n full-width units per line (ASCII counts as half), at word boundaries chosen by
    tools/audio/capbreak.py: Latin words, numbers and (with jieba) Chinese words never split, breaks after punctuation
    preferred, lines of even width."""
    text = text.strip()
    if not text:
        return []
    if capbreak.width(text) <= n:
        return [text]
    return [capbreak.display(raw, False) for _, raw in capbreak.pieces(text, n, False, line_id, table)]

def wrap_en(text: str, n: int):
    words, lines, cur = text.split(), [], ""
    for w in words:
        if cur and len(cur) + 1 + len(w) > n:
            lines.append(cur); cur = w
        else:
            cur = f"{cur} {w}".strip()
    return lines + ([cur] if cur else [])

def srt(items, key_fn):
    blocks, i = [], 1
    for c in items:
        lines = key_fn(c)
        if lines:
            blocks.append(f"{i}\n{ts(c['start'])} --> {ts(c['end'])}\n" + "\n".join(lines) + "\n"); i += 1
    return "\n".join(blocks)

def _positive(x):
    return float(x) if isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x) and x > 0 else None

def find_media_end(project, timeline_duration, explicit=None):
    """(seconds, where it came from) for the end of the media, the first of: --media-end, the root data-duration of
    <project>/index.html, the length of <project>/media/final.mp4, the timeline's duration; (None, "") when none is known."""
    if _positive(explicit):
        return float(explicit), "--media-end"
    html = project / "index.html"
    if html.is_file():
        try:
            d = _positive(composition_duration(html))
        except OSError:
            d = None
        if d: return d, "index.html data-duration"
    final = project / "media" / "final.mp4"
    if final.is_file():
        try:
            out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(final)],
                                 capture_output=True, text=True, timeout=60).stdout.strip()
            d = _positive(float(out))
        except (OSError, subprocess.SubprocessError, ValueError):
            d = None
        if d: return d, "media/final.mp4"
    d = _positive(timeline_duration)
    return (d, "timeline duration") if d else (None, "")

def need_of(lines, cps):
    """The time a caption must show, readcheck's subtitle rule (readcheck.subtitle_check) with cps for Chinese: the floor,
    or Chinese at cps characters a second (half-width ones count half), or other text at 20 a second."""
    text = "".join(lines) if any(is_cjk(c) for x in lines for c in x) else " ".join(lines)
    if any(is_cjk(c) for c in text):
        n, rate = capbreak.width(text.strip()), cps or SUB_CPS_CJK
    else:
        n, rate = float(len(text.strip())), SUB_CPS_LATIN
    return max(SUB_FLOOR, n / rate)

def touch(items):
    """Captions less than TOUCH apart: the first runs on to the next, so the band never blinks off for a frame."""
    live = sorted((c for c in items if c["zh"] or c["en"]), key=lambda c: c["start"])
    n = 0
    for a, b in zip(live, live[1:]):
        if 0 < b["start"] - a["end"] < TOUCH:
            a["end"] = b["start"]; n += 1
    return n

def cards(segments, lang, limit, cps, table, media_end):
    """One-line cards for the narrated side: ([{id, part, start, end, zh|en: [line], words?}], [cards left out because
    they start after the media end]). limit is in capbreak.width's units (ASCII counts half)."""
    other = "en" if lang == "zh" else "zh"
    out = []
    for si, s in enumerate(segments):
        text = (s.get(lang) or "").strip()
        if not text:
            continue
        T = capbreak.letter_times(text, s.get("words"), float(s["start"]), float(s["end"]))
        ps = capbreak.pieces(text, limit, True, s.get("id"), table)
        forced = set(capbreak.forced_starts(text, s.get("id"), table))   # a card the break table starts is never joined back
        for k, (ci, raw) in enumerate(ps):
            li = capbreak.letter_index(text, ci)
            at = T[li] if li < len(T) and T[li] is not None else float(s["start"])
            out.append({"id": s["id"], "part": k + 1, "seg": si, "sent": raw, "forced": ci in forced, "start": max(0.0, float(s["start"]) - LEAD, at - LEAD),
                        lang: [capbreak.display(raw, True)], other: [], "_last": k + 1 == len(ps), "_end": float(s["end"])})
    gone = []
    if media_end:   # a card that starts once the picture has ended never shows
        gone = [c for c in out if c["start"] >= media_end - 0.05]
        out = [c for c in out if c["start"] < media_end - 0.05]
    for k, c in enumerate(out):   # a card runs to the next card of its line; the last one into the pause
        nxt = out[k + 1]["start"] if k + 1 < len(out) else (media_end if media_end else c["_end"] + HOLD)
        c["end"] = max(min(c["_end"] + HOLD, nxt) if c["_last"] else nxt, c["start"] + 0.001)
    # short cards: joined to the next card of the same line and sentence when the two fit on one line, else to the one
    # before it (a short last card of a sentence); a card the break table starts is never joined to the one before
    ends = lambda c: re.search(r"[。？！?!….．]\W*$", c["sent"].strip())   # noqa: E731
    k = 0
    while k < len(out):
        a = out[k]
        if a["end"] - a["start"] >= need_of(a[lang], cps) - 1e-6:
            k += 1; continue
        if k + 1 < len(out):
            b = out[k + 1]
            joined = capbreak.display(a["sent"] + b["sent"], True)
            if a["seg"] == b["seg"] and not b["forced"] and not ends(a) and capbreak.width(joined) <= limit:
                a["sent"] += b["sent"]; a[lang] = [joined]; a["end"] = b["end"]; a["_last"] = b["_last"]
                del out[k + 1]
                continue
        if k > 0:
            z = out[k - 1]
            joined = capbreak.display(z["sent"] + a["sent"], True)
            if z["seg"] == a["seg"] and not a["forced"] and not ends(z) and capbreak.width(joined) <= limit:
                z["sent"] += a["sent"]; z[lang] = [joined]; z["end"] = a["end"]; z["_last"] = a["_last"]
                del out[k]
                continue
        k += 1
    items = [{"id": c["id"], "part": c["part"], "start": round(c["start"], 3), "end": round(c["end"], 3), "zh": c["zh"], "en": c["en"]} for c in out]
    for c, seg in zip(items, out):   # the words inside each card, for engines that pop words in
        ws = [w for w in (segments[seg["seg"]].get("words") or []) if c["start"] - 1e-6 <= float(w.get("start", -1)) < c["end"]]
        if ws: c["words"] = ws
    return items, [{"id": c["id"], "start": round(c["start"], 3), "text": c[lang][0]} for c in gone]

def extend_short(items, media_end=None, floor=SUB_FLOOR, gap=CUE_GAP, cps=None):
    """Give every caption shorter than `floor` seconds the missing time after its end, never before its start:
    up to start + floor, or the next caption's start - `gap`, or `media_end`, whichever is least; a caption is never
    shortened and never made to overlap. An item moved keeps its spoken end as "speech_end". Returns [(item, why)] for
    the captions still under `floor` (why: what stopped them), in time order. items are changed in place."""
    live = sorted((c for c in items if c["zh"] or c["en"]), key=lambda c: c["start"])
    still = []
    for i, c in enumerate(live):
        floor_c = need_of(c["zh"] or c["en"], cps) if cps else floor
        if c["end"] - c["start"] >= floor_c - 1e-6:
            continue
        limit, why = math.inf, ""
        if i + 1 < len(live):
            limit, why = live[i + 1]["start"] - gap, f"the next caption starts at {live[i + 1]['start']:g} s"
        if media_end is not None and media_end < limit:
            limit, why = media_end, f"the media ends at {media_end:g} s"
        want = math.ceil((c["start"] + floor_c) * 1000 - 1e-6) / 1000        # whole milliseconds: the SRT rounds to them
        end = min(want, math.floor(limit * 1000 + 1e-6) / 1000)
        if end > c["end"] + 1e-6:
            c["speech_end"], c["end"] = c["end"], round(end, 3)
        if c["end"] - c["start"] < floor_c - 1e-6:
            still.append((c, why))
    return still

def line_cues(lines, words, start, end):
    """One cue per wrapped line: a line starts when its first character is spoken (matched by non-space character
    count, scaled when the two texts differ slightly, and interpolated inside a word that spans a line break) and runs
    until the next line starts. Cues never overlap and each lasts ≥ 0.1 s (less only when the caption is that short),
    so several lines inside one coarse ASR word no longer collapse into zero-length cues."""
    key = lambda x: re.sub(r"\s+", "", x)
    ll, wl = [len(key(l)) for l in lines], [len(key(w["w"])) for w in words]
    if len(lines) < 2 or not sum(ll) or not sum(wl):
        return [(start, end, lines)]
    starts, acc = [], 0
    for n in ll:
        pos, c, t = acc * sum(wl) / sum(ll), 0, words[-1]["start"]
        for w, k in zip(words, wl):
            if c + k > pos:
                t = w["start"] + (w["end"] - w["start"]) * (pos - c) / k; break
            c += k
        starts.append(min(max(t, starts[-1] if starts else start), end)); acc += n
    starts[0], gap = start, min(.1, (end - start) / len(lines))
    for i in range(1, len(starts)):                  # push apart lines that start together …
        starts[i] = max(starts[i], starts[i - 1] + gap)
    for i in range(len(starts) - 1, 0, -1):          # … and keep the last ones inside the caption
        starts[i] = min(starts[i], (starts[i + 1] if i + 1 < len(starts) else end) - gap)
    return [(starts[i], starts[i + 1] if i + 1 < len(lines) else end, [lines[i]]) for i in range(len(lines))]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("project"); ap.add_argument("--lang"); ap.add_argument("--zh-max", type=int, default=16)
    ap.add_argument("--en-max", type=int, default=42)
    ap.add_argument("--skip-lint", action="store_true", help="go on even when the timeline fails its checks (tools/audio/timeline_lint.py)")
    ap.add_argument("--media-end", type=float, metavar="S", help="the length of the picture in seconds, the limit for lengthening a caption "
                    "(default: index.html's data-duration, else media/final.mp4, else the timeline's duration)")
    ap.add_argument("--cards", action="store_true", help="one line per caption, cut at word boundaries and timed by the words")
    ap.add_argument("--cps", type=float, default=SUB_CPS_CJK, help="reading speed for the minimum time on screen, characters a second (half-width count half); default 9")
    a = ap.parse_args()
    if not (a.cps > 0):
        ap.error("--cps must be > 0")
    if a.media_end is not None and not (math.isfinite(a.media_end) and a.media_end > 0):
        ap.error("--media-end must be > 0 seconds")
    audio = Path(a.project).resolve() / "audio"
    tl_path = audio / f"timeline.{a.lang}.json" if a.lang else audio / "timeline.json"
    tl = json.loads(tl_path.read_text(encoding="utf-8"))
    sys.path.insert(0, str(Path(__file__).resolve().parent)); import timeline_lint
    if (lint := timeline_lint.lint(tl, a.lang or tl.get("lang"))) and not a.skip_lint:   # captions take their times from the words
        sys.exit(f"captions: {tl_path.name} has {len(lint)} problem(s), so the captions would be timed wrong:\n" + timeline_lint.report(lint)
                 + "\nfix the timeline (bin/vh tts again, or by hand), or pass --skip-lint to time the captions anyway")
    table = capbreak.load_breaks(audio)
    end_s, end_from = find_media_end(Path(a.project).resolve(), tl.get("duration"), a.media_end)
    narr = tl.get("lang") if tl.get("lang") in ("zh", "en") else (a.lang if a.lang in ("zh", "en") else "zh")
    if not any((s.get(narr) or "").strip() for s in tl["segments"]):   # a one-language script under the other --lang
        narr = "en" if narr == "zh" else "zh"
    left_out = []
    if a.cards:   # the limit in capbreak.width's units: --en-max counts characters, and width counts ASCII as half
        items, left_out = cards(tl["segments"], narr, a.zh_max if narr == "zh" else a.en_max / 2, a.cps, table, end_s)
    else:
        items = [{"id": s["id"], "start": s["start"], "end": s["end"],
                  "zh": wrap_zh(s.get("zh", ""), a.zh_max, s.get("id"), table), "en": wrap_en(s.get("en", ""), a.en_max),
                  **({"words": s["words"]} if s.get("words") else {})} for s in tl["segments"]]
    if end_from == "timeline duration" and (Path(a.project) / "media").is_dir() and not (Path(a.project) / "media" / "final.mp4").is_file():
        print("captions: media/final.mp4 is missing, so the media end falls back to the timeline's duration; for a showcase,"
              " tools/fetch_media.sh puts its film there (the videos are in the GitHub release \"media\")", file=sys.stderr)
    n_short = sum(1 for c in items if (c["zh"] or c["en"]) and c["end"] - c["start"] < need_of(c["zh"] or c["en"], a.cps) - 1e-6)
    still = extend_short(items, end_s, cps=a.cps)
    touched = touch(items)
    still = [(c, why) for c, why in still if c["end"] - c["start"] < need_of(c["zh"] or c["en"], a.cps) - 1e-6]   # touching may have mended one
    old = audio / "captions.json"
    try:
        was_cards = bool(old_items := json.loads(old.read_text(encoding="utf-8"))) and all("part" in c for c in old_items)
    except (OSError, ValueError, TypeError, AttributeError):
        was_cards = False
    moved = [c for c in items if "speech_end" in c]
    items = [{k: c[k] for k in ("id", "part", "start", "end", "speech_end", "zh", "en", "words") if k in c} for c in items]   # speech_end beside end
    (audio / "captions.json").write_text(json.dumps(items, ensure_ascii=False, indent=2), encoding="utf-8")
    # how they were made, so bin/vh pace makes them again the same way after it changes the take
    (audio / "captions.args.json").write_text(json.dumps({"cards": a.cards, "zh_max": a.zh_max, "en_max": a.en_max, "cps": a.cps, "media_end": a.media_end}) + "\n", encoding="utf-8")
    wrote = ["captions.json"]
    if not a.cards and any(c.get("words") for c in items) and any(c[narr] for c in items):   # word timing → one cue per wrapped line
        cues = [{"start": t0, "end": t1, "l": ls} for c in items if c[narr]
                for t0, t1, ls in (line_cues(c[narr], c["words"], c["start"], c["end"]) if c.get("words") else [(c["start"], c["end"], c[narr])])]
        (audio / f"captions.{narr}.lines.srt").write_text(srt(cues, lambda c: c["l"]), encoding="utf-8"); wrote.append(f"captions.{narr}.lines.srt")
    if any(c["zh"] for c in items):
        (audio / "captions.zh.srt").write_text(srt(items, lambda c: c["zh"]), encoding="utf-8"); wrote.append("captions.zh.srt")
    if any(c["en"] for c in items):
        (audio / "captions.en.srt").write_text(srt(items, lambda c: c["en"]), encoding="utf-8"); wrote.append("captions.en.srt")
    if not a.cards and any(c["zh"] for c in items) and any(c["en"] for c in items):
        (audio / "captions.bi.srt").write_text(srt(items, lambda c: c["zh"] + c["en"]), encoding="utf-8"); wrote.append("captions.bi.srt")
    removed = []
    if a.cards:   # what only the other mode writes: an old one would be muxed by mistake
        other = "en" if narr == "zh" else "zh"
        for name in ("captions.zh.lines.srt", "captions.en.lines.srt", "captions.bi.srt", f"captions.{other}.srt"):
            if (audio / name).is_file():
                (audio / name).unlink(); removed.append(name)
    zh_text = any(is_cjk(ch) for c in items for x in c["zh"] for ch in x)
    how = (f"{len(items)} one-line cards" if a.cards else f"{len(items)} captions") + (
        "" if not zh_text else ", word boundaries by jieba" if capbreak.HAVE_JIEBA else ", no jieba: a break may fall inside a Chinese word")
    print(f"timing from {tl_path.name} ({tl.get('lang', '?')} narration) → audio/" + ", ".join(wrote) + f" · {how}" + (f" · break table: {sum(len(v) for v in table.values())} phrase(s)" if table else ""))
    if removed:
        print(f"  removed {', '.join(removed)}: the wrapped mode's files, older than these cards (run without --cards to make them again)")
    if was_cards and not a.cards:
        print("  note: captions.json held one-line cards (--cards) and now holds wrapped captions; a canvas-film page that reads it"
              " (FILM.caption.from) refuses these: run bin/vh captions again with --cards")
    for c in left_out:
        print(f"  left out, starts after the media end ({end_s:g} s, {end_from}): {c['id']} at {c['start']:g} s \"{c['text']}\"")
    rule = f"the {SUB_FLOOR:g} s floor, or {a.cps:g} Chinese or {SUB_CPS_LATIN:g} other characters a second"
    if n_short:
        print(f"  {n_short} caption(s) under their minimum ({rule})" + (f": {len(moved)} extended into the gap after them ("
              + ", ".join(f"{c['id']}{'.' + str(c['part']) if 'part' in c else ''} +{c['end'] - c['speech_end']:.2f} s" for c in moved[:12]) + (" …" if len(moved) > 12 else "") + ")" if moved else "")
              + (f"; media end {end_s:g} s ({end_from})" if end_s else "; media end unknown"))
    if touched:
        print(f"  {touched} caption(s) run on to the next one, which starts less than {TOUCH:g} s after them (no blink between them)")
    for c, why in still:
        print(f"  still {c['end'] - c['start']:.2f} s, under its minimum: {c['id']}{'.' + str(c['part']) if 'part' in c else ''} ({c['start']:g}–{c['end']:g} s): {why}")

if __name__ == "__main__":
    main()
