"""The five discipline films — complete blueprints.

Each blueprint is fully deterministic on its own (script, scenes, palette, score,
metadata): if Groq is unreachable the factory ships exactly this. The AI director
(groq_client + director) enriches what is here — it never replaces it.

Script pacing: ~260-290 words of narration ≈ 108-118 s at edge-tts pace; the
builder pads with lead-in / tail to land the master at 120.0 s.
"""

from .films_part2 import FILMS_4_5  # noqa: F401  (kept in one namespace below)

FILMS_1_3 = []

# ────────────────────────────────────────────────────────────────────────────
# 1 · Discipline Beats Motivation — the science angle
FILMS_1_3.append({
    "slug": "discipline-beats-motivation",
    "title": "Discipline Beats Motivation",
    "voice": "en-US-AriaNeural",
    "premise": "Motivation is weather; discipline is climate. The science of showing up when you feel nothing.",
    "palette": {
        "bg0": "#060B18", "bg1": "#0E1B36", "ink": "#F4F1EA", "dim": "#8A94A6",
        "accent": "#38BDF8", "accent2": "#818CF8",
        "grad": ["#060B18", "#0C1E42", "#072A4A"],
    },
    "grain": 0.05,
    "lead": 3.2, "tail": 3.4,
    "script": [
        ("h1", "Motivation is a feeling. And feelings, by design, were never meant to last."),
        ("h2", "Your brain runs on dopamine. A spike, then a fall. Riding that spike is not a strategy. It's weather."),
        ("h3", "Discipline is climate. It is what still works on the morning you feel nothing at all."),
        ("s1", "Every January, the gym is full. By March, it is quiet again. The feeling came and went. The people who stayed built something the feeling cannot touch."),
        ("s2", "Two thousand years ago the Stoics already knew. We are what we repeatedly do. Excellence is not an act. It is a habit."),
        ("c1", "So stop negotiating with yourself at five in the morning. Three moves end the debate."),
        ("l1", "One. Decide once, in advance. The decision is made on Sunday, not at sunrise."),
        ("l2", "Two. Make the first step so small it is embarrassing. Two push-ups. One sentence. Open the book."),
        ("l3", "Three. Tie it to something you already do. After coffee, we write. After shoes, we run."),
        ("s3", "Motivation asks: how do I feel today? Discipline asks: what did I decide? Only one of those questions has a stable answer."),
        ("s4", "Every rep you finish is a vote for the person you are becoming. You do not need a unanimous election. You need a majority."),
        ("p1", "Show up on the grey days. Especially on the grey days. That is the entire secret."),
        ("o1", "Motivation will visit again. Enjoy it. Just don't build your life on a guest."),
    ],
    "scenes": [
        {"line": None, "at": "start", "kind": "title", "kick": "THE SCIENCE OF SHOWING UP", "title": "Discipline\nbeats motivation", "sub": None, "outlineLine": 2},
        {"line": "h1", "kind": "statement", "text": "Motivation is a feeling.", "em": ["feeling"]},
        {"line": "h2", "kind": "statement", "text": "Dopamine is a spike, then a fall. Riding it is not a strategy — it's weather.", "em": ["spike", "weather"]},
        {"line": "h3", "kind": "compare", "left": {"head": "Motivation", "big": "Weather", "note": "Comes and goes without asking you."}, "right": {"head": "Discipline", "big": "Climate", "note": "The system that holds on grey days."}},
        {"line": "s1", "kind": "stats", "items": [{"v": "100", "suffix": "%", "label": "gym full in January", "accent": "bad"}, {"v": "80", "suffix": "%", "label": "gone by March"}], "note": "The feeling left. The systems stayed.", "chapter": {"title": "The evidence"}},
        {"line": "s2", "kind": "quote", "text": "We are what we repeatedly do. Excellence, then, is not an act, but a habit.", "who": "Will Durant"},
        {"line": "c1", "kind": "statement", "text": "Stop negotiating at 5 a.m. Three moves end the debate.", "em": ["Three", "moves"], "chapter": {"title": "The three moves"}},
        {"line": "l1", "kind": "list", "head": "Decide once", "items": ["Decide once, in advance", "Sunday decides. Sunrise only obeys."]},
        {"line": "l2", "kind": "list", "head": "Start stupidly small", "items": ["Two push-ups. One sentence.", "Small enough that skipping feels absurd."]},
        {"line": "l3", "kind": "list", "head": "Anchor it", "items": ["After coffee, we write", "After shoes, we run"]},
        {"line": "s3", "kind": "compare", "left": {"head": "Motivation asks", "big": "How do I feel?", "note": "An answer that changes hourly."}, "right": {"head": "Discipline asks", "big": "What did I decide?", "note": "An answer that holds."}},
        {"line": "s4", "kind": "statement", "text": "Every rep is a vote for who you're becoming. You don't need unanimity — you need a majority.", "em": ["vote", "majority"], "chapter": {"title": "The vote"}},
        {"line": "p1", "kind": "particles", "word": "GREY DAYS", "sub": "Especially on the grey days."},
        {"line": "o1", "kind": "outro", "kick": "DISCIPLINE BEATS MOTIVATION", "cta": "Save this. Rebuild tomorrow.", "handle": "@coreselfmastery"},
    ],
    "score": {
        "bpm": 96, "key": "D", "mode": "minor", "seed": 101, "stereo": True, "space": "hall",
        "sections": [
            {"name": "intro", "bars": 6, "chords": ["i", "VI", "III", "VII", "VI", "IV"], "layers": ["pad"], "energy": 0.25},
            {"name": "build", "bars": 4, "chords": ["i", "VI", "III", "VII"], "layers": ["pad", "arp", "bass"], "energy": 0.5, "riser": True, "fill": True},
            {"name": "verse", "bars": 10, "chords": ["i", "VI", "III", "VII"], "layers": ["pad", "arp", "bass", "hats"], "energy": 0.7, "impact": True},
            {"name": "lift", "bars": 10, "chords": ["VI", "VII", "i", "i"], "layers": ["kick", "hats", "bass", "pad", "arp", "lead"], "energy": 0.9, "impact": True},
            {"name": "breathe", "bars": 4, "chords": ["III", "VI", "IV", "VII"], "layers": ["pad", "arp"], "energy": 0.45},
            {"name": "final", "bars": 10, "chords": ["i", "VI", "III", "VII"], "layers": ["kick", "hats", "bass", "pad", "arp", "lead"], "energy": 1.0, "impact": True},
            {"name": "outro", "bars": 8, "chords": ["VI", "IV", "i", "i", "i", "i", "i", "i"], "layers": ["pad"], "energy": 0.3},
        ],
        "parts": [
            {"inst": "piano", "figure": "sustain", "octave": 4, "gain_db": -7, "send": 0.4, "pan": -0.15},
            {"inst": "strings", "figure": "sustain", "octave": 4, "gain_db": -9, "send": 0.6, "pan": 0.2},
        ],
    },
    "metadata": {
        "titles": ["Discipline Beats Motivation (The Science of Showing Up)", "Why Motivation Fails and Discipline Doesn't", "The Science of Showing Up When You Feel Nothing"],
        "description": "Motivation is weather — it comes and goes without asking you. Discipline is climate. "
                       "In two minutes: why dopamine spikes always fall, the three moves that end the 5 a.m. debate, "
                       "and how every rep is a vote for the person you're becoming.",
        "tags": ["discipline", "motivation", "habits", "selfimprovement", "stoicism", "dopamine", "productivity", "mindset", "selfgrowth", "consistency", "willpower", "habitscience", "jamesclear", "atomic habits", "dailyroutine"],
    },
})

# ────────────────────────────────────────────────────────────────────────────
# 2 · The 1% Rule — compounding
FILMS_1_3.append({
    "slug": "the-1-percent-rule",
    "title": "The 1% Rule",
    "voice": "en-US-GuyNeural",
    "premise": "1.01 to the power of 365 is 37.8. Compounding punishes and rewards in silence.",
    "palette": {
        "bg0": "#0B0803", "bg1": "#201507", "ink": "#F5EFE2", "dim": "#9A8B72",
        "accent": "#F2B33D", "accent2": "#E8834A",
        "grad": ["#0B0803", "#241605", "#3A2408"],
    },
    "grain": 0.055,
    "lead": 3.0, "tail": 3.2,
    "script": [
        ("h1", "One percent better every day for one year. Do the math before you feel the math."),
        ("s1", "If you improve one percent each day for a year, you don't end up three hundred sixty-five percent better. You end up thirty-seven times better."),
        ("s2", "The same math runs in reverse. One percent worse each day takes you almost all the way to zero."),
        ("c1", "Compounding doesn't announce itself. There is no daily applause. That silence is the filter."),
        ("s3", "Think of an ice cube in a freezing room. You turn the heat up. Twenty-eight degrees. Twenty-nine. Thirty. Nothing. And then thirty-two — it melts."),
        ("p1", "The work was never wasted. It was storing."),
        ("s4", "This is the valley of disappointment. Early effort returns almost nothing visible, while the curve is still flat. Most people quit inside the valley."),
        ("s5", "The plateau of latent potential is not a punishment. It is a battery. Every rep you don't see is charging the drop you will."),
        ("c2", "So measure trajectory, not position. Am I slightly better this week than last week? That is the only question the math rewards."),
        ("s6", "Intensity gets applause. Consistency gets results. A brutal Tuesday workout you repeat for a year beats a heroic one you never repeat."),
        ("s7", "Warren Buffett calls it the snowball. Start with a handful of wet snow. What matters is finding the hill — and refusing to get off."),
        ("o1", "One percent. Today. Again tomorrow. And again the day after. The curve does the rest in silence."),
    ],
    "scenes": [
        {"line": None, "at": "start", "kind": "title", "kick": "COMPOUNDING", "title": "The 1%\nRule", "sub": "Small gains. Ridiculous math.", "outlineLine": 2},
        {"line": "h1", "kind": "statement", "text": "1% better every day for one year.", "em": ["1%", "year"]},
        {"line": "s1", "kind": "stats", "items": [{"v": "1.01", "label": "daily gain"}, {"v": "37.8", "label": "after 365 days"}], "note": "1.01 ^ 365 = 37.8"},
        {"line": "s2", "kind": "stats", "items": [{"v": "0.99", "label": "daily loss"}, {"v": "0.03", "label": "after 365 days", "accent": "bad"}], "note": "0.99 ^ 365 = 0.03", "chapter": {"title": "The math"}},
        {"line": "c1", "kind": "statement", "text": "Compounding doesn't announce itself. The silence is the filter.", "em": ["silence", "filter"]},
        {"line": "s3", "kind": "stats", "items": [{"v": "31", "suffix": "°F", "label": "nothing happens"}, {"v": "32", "suffix": "°F", "label": "everything moves"}], "note": "All the earlier degrees were loading the jump.", "chapter": {"title": "The ice cube"}},
        {"line": "p1", "kind": "particles", "word": "STORING", "sub": "The work is never wasted — it's charging."},
        {"line": "s4", "kind": "quote", "text": "The valley of disappointment: where effort looks like it returns nothing.", "who": "James Clear, Atomic Habits"},
        {"line": "s5", "kind": "statement", "text": "The plateau of latent potential is not a punishment. It's a battery.", "em": ["battery"], "chapter": {"title": "The valley"}},
        {"line": "c2", "kind": "compare", "left": {"head": "Position asks", "big": "Where am I?", "note": "Flat. Discouraging. Loud."}, "right": {"head": "Trajectory asks", "big": "Where am I going?", "note": "Compounding. Quiet. Decisive."}},
        {"line": "s6", "kind": "compare", "left": {"head": "Intensity", "big": "Applause", "note": "One heroic workout you never repeat."}, "right": {"head": "Consistency", "big": "Results", "note": "A decent Tuesday, repeated for a year."}},
        {"line": "s7", "kind": "quote", "text": "Life is like a snowball. The important thing is finding wet snow and a really long hill.", "who": "Warren Buffett"},
        {"line": "o1", "kind": "outro", "kick": "THE 1% RULE", "cta": "1% today. Again tomorrow.", "handle": "@coreselfmastery"},
    ],
    "score": {
        "bpm": 84, "key": "F", "mode": "minor", "seed": 202, "stereo": True, "space": "hall",
        "sections": [
            {"name": "intro", "bars": 6, "chords": ["i", "VI", "III", "VII", "VI", "IV"], "layers": ["pad"], "energy": 0.25},
            {"name": "build", "bars": 4, "chords": ["i", "VI", "III", "VII"], "layers": ["pad", "arp", "bass"], "energy": 0.5, "riser": True},
            {"name": "math", "bars": 8, "chords": ["i", "VI", "III", "VII"], "layers": ["pad", "arp", "bass", "hats"], "energy": 0.7, "impact": True},
            {"name": "ice", "bars": 8, "chords": ["VI", "IV", "i", "i"], "layers": ["pad", "bell", "arp"], "energy": 0.55},
            {"name": "valley", "bars": 6, "chords": ["III", "VII", "VI", "IV", "i", "i"], "layers": ["pad", "bell"], "energy": 0.35},
            {"name": "final", "bars": 8, "chords": ["i", "VI", "III", "VII"], "layers": ["kick", "hats", "bass", "pad", "arp", "lead"], "energy": 0.95, "impact": True, "riser": True},
            {"name": "outro", "bars": 6, "chords": ["VI", "IV", "i", "i", "i", "i"], "layers": ["pad", "bell"], "energy": 0.3},
        ],
        "parts": [
            {"inst": "piano", "figure": "sustain", "octave": 4, "gain_db": -6, "send": 0.45, "pan": -0.1},
            {"inst": "upright", "figure": "walking", "octave": 3, "gain_db": -11, "pan": 0.25},
        ],
    },
    "metadata": {
        "titles": ["The 1% Rule (Why Small Gains Win Everything)", "1.01^365 = 37.8: The Math of Discipline", "The Ice Cube at 32 Degrees"],
        "description": "1% better every day for a year is not 365% better — it's 37.8x. "
                       "Two minutes on compounding, ice cubes, and the valley where most people quit: "
                       "why trajectory beats position and consistency beats intensity.",
        "tags": ["1percent", "compounding", "atomic habits", "james clear", "discipline", "consistency", "habits", "selfimprovement", "growth mindset", "kaizen", "small habits", "motivation", "productivity", "long term", "selfgrowth"],
    },
})

# ────────────────────────────────────────────────────────────────────────────
# 3 · Deep Work — focus as the rarest skill
FILMS_1_3.append({
    "slug": "deep-work-focus",
    "title": "Deep Work",
    "voice": "en-US-ChristopherNeural",
    "premise": "Attention is the new currency — and almost nobody can hold it, including you.",
    "palette": {
        "bg0": "#06120D", "bg1": "#0B241A", "ink": "#EFF5F0", "dim": "#7E968A",
        "accent": "#34D399", "accent2": "#5EEAD4",
        "grad": ["#06120D", "#0A2418", "#0C3326"],
    },
    "grain": 0.045,
    "lead": 3.4, "tail": 3.6,
    "script": [
        ("h1", "Two hours of undisturbed focus is now a competitive advantage. Not talent. Not tools. Focus."),
        ("s1", "The average knowledge worker checks email or messages every six minutes. Once interrupted, it takes over twenty minutes to return to full depth."),
        ("s2", "That is not a productivity problem. That is a training problem. Distraction is a muscle, and most of us have been training it daily for a decade."),
        ("c1", "Cal Newport gave it a name: deep work. Sustained, undistracted concentration on one hard thing. The skill that is getting rarer and more valuable every year."),
        ("l1", "Rule one. Block the time like a flight. Ninety minutes, calendar-visible, defended like a meeting with someone you can't cancel."),
        ("l2", "Rule two. Train boredom. Standing in line? Don't reach for the phone. Every time you cave, you teach your brain that discomfort is an emergency."),
        ("l3", "Rule three. End with a shutdown ritual. Write tomorrow's first task, close the laptop, say it out loud. The brain needs a door to close."),
        ("s3", "Attention residue is the tax: switch tasks, and part of your mind stays stuck on the last one. Ten shallow switches and there's almost no you left at the desk."),
        ("p1", "One screen. One task. One stretch of time."),
        ("s4", "Elite performers cap deliberate practice around four hours a day. Not because they're weak. Because depth is expensive, and recovery is part of the work."),
        ("o1", "Protect the next ninety minutes like they're money. Because they are."),
    ],
    "scenes": [
        {"line": None, "at": "start", "kind": "title", "kick": "THE RAREST SKILL OF THE CENTURY", "title": "Deep\nWork", "sub": "Focus is the new currency.", "outlineLine": 2},
        {"line": "h1", "kind": "statement", "text": "Two hours of undisturbed focus is a competitive advantage.", "em": ["undisturbed", "focus"]},
        {"line": "s1", "kind": "stats", "items": [{"v": "6", "suffix": " min", "label": "between message checks", "accent": "bad"}, {"v": "23", "suffix": " min", "label": "to refocus after an interruption"}], "note": "The average knowledge worker's day, measured.", "chapter": {"title": "The numbers"}},
        {"line": "s2", "kind": "statement", "text": "Distraction is a muscle. Most of us have trained it daily for a decade.", "em": ["muscle", "decade"]},
        {"line": "c1", "kind": "quote", "text": "Deep work: professional activities performed in a state of distraction-free concentration.", "who": "Cal Newport"},
        {"line": "l1", "kind": "list", "head": "Rule one", "items": ["Block time like a flight", "Ninety minutes, calendar-visible, defended"]},
        {"line": "l2", "kind": "list", "head": "Rule two", "items": ["Train boredom", "The line at the coffee shop is a rep"]},
        {"line": "l3", "kind": "list", "head": "Rule three", "items": ["End with a shutdown ritual", "Tomorrow's first task, written, then close the door"]},
        {"line": "s3", "kind": "statement", "text": "Attention residue: switch tasks, and part of your mind stays behind. Ten switches — almost no you left at the desk.", "em": ["residue"], "chapter": {"title": "The tax"}},
        {"line": "p1", "kind": "particles", "word": "ONE THING", "sub": "One screen. One task. One stretch of time."},
        {"line": "s4", "kind": "stats", "items": [{"v": "4", "suffix": " h", "label": "the elite ceiling of deliberate practice"}], "note": "Depth is expensive. Recovery is part of the work.", "chapter": {"title": "The ceiling"}},
        {"line": "o1", "kind": "outro", "kick": "DEEP WORK", "cta": "Protect the next 90 minutes.", "handle": "@coreselfmastery"},
    ],
    "score": {
        "bpm": 72, "key": "A", "mode": "minor", "seed": 303, "stereo": True, "space": "room",
        "sections": [
            {"name": "intro", "bars": 6, "chords": ["i", "VI", "III", "VII", "VI", "IV"], "layers": ["pad"], "energy": 0.2},
            {"name": "numbers", "bars": 6, "chords": ["i", "VI", "III", "VII"], "layers": ["pad", "bell"], "energy": 0.4},
            {"name": "rules", "bars": 10, "chords": ["i", "VI", "III", "VII"], "layers": ["pad", "bell", "arp"], "energy": 0.6, "impact": True},
            {"name": "tax", "bars": 6, "chords": ["VI", "IV", "i", "i"], "layers": ["pad"], "energy": 0.35},
            {"name": "one", "bars": 8, "chords": ["i", "III", "VII", "i"], "layers": ["pad", "bell", "arp", "hats"], "energy": 0.75, "riser": True},
            {"name": "outro", "bars": 8, "chords": ["VI", "IV", "i", "i", "i", "i", "i", "i"], "layers": ["pad", "bell"], "energy": 0.25},
        ],
        "parts": [
            {"inst": "piano", "figure": "sustain", "octave": 4, "gain_db": -6, "send": 0.35, "pan": -0.1, "params": {"tone": "felt"}},
            {"inst": "rain", "gain_db": -10, "pan": 0.1, "quiet": True},
        ],
    },
    "metadata": {
        "titles": ["Deep Work: The Rarest Skill of the Century", "Why You Can't Focus (And the 3 Rules That Fix It)", "Your Attention Is Worth More Than Your Talent"],
        "description": "The average knowledge worker checks messages every 6 minutes and needs 23 to refocus. "
                       "Two minutes on deep work: attention residue, the boredom muscle, the shutdown ritual — "
                       "and why elite performers cap hard focus at four hours a day.",
        "tags": ["deep work", "cal newport", "focus", "attention", "productivity", "discipline", "concentration", "work smarter", "digital minimalism", "distraction", "flow state", "studying", "deep focus", "time blocking", "selfimprovement"],
    },
})
