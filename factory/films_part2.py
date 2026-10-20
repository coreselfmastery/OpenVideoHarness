"""Films 4 and 5 — the philosophy film and the habit-science film."""

FILMS_4_5 = []

# ────────────────────────────────────────────────────────────────────────────
# 4 · Discipline Is Freedom — the Stoic paradox
FILMS_4_5.append({
    "slug": "discipline-is-freedom",
    "title": "Discipline Is Freedom",
    "voice": "en-US-JennyNeural",
    "premise": "The Stoic paradox: the constraints you choose are the ones that set you free.",
    "palette": {
        "bg0": "#140507", "bg1": "#2A0A0F", "ink": "#F5ECE8", "dim": "#9A7E7E",
        "accent": "#E2483D", "accent2": "#F2914D",
        "grad": ["#140507", "#2A0A0F", "#3B1016"],
    },
    "grain": 0.05,
    "lead": 3.0, "tail": 3.4,
    "script": [
        ("h1", "Everyone wants freedom. Almost nobody connects it to the alarm clock. The Stoics did."),
        ("q1", "No person is free who is not master of themselves. Epictetus wrote that as a slave, two thousand years ago — a man owned by Rome, ruling his own mind."),
        ("s1", "Here is the paradox nobody escapes: skip the training, and the body sets the limits. Ignore the budget, and the bills set the schedule. Avoid the hard talk, and the fear does the talking."),
        ("c1", "Undisciplined freedom is just a longer chain with a softer name."),
        ("s2", "A pilot's checklist is not a cage. It is why the pilot is alive to fly again. Constraints chosen on purpose are not the opposite of freedom. They are the machinery of it."),
        ("p1", "Choose your hard."),
        ("s3", "The body offers two pains. The pain of discipline — measured, scheduled, chosen. Or the pain of regret — unpayable, unscheduled, permanent. There is no third option on the menu."),
        ("s4", "Four-thirty in the morning looks like punishment until you notice who's awake at that hour by choice: the athlete, the founder, the writer mid-chapter. Nobody chained them there."),
        ("s5", "The Stoics trained like athletes because they knew the truth about the will: it is a muscle, and comfort is the rust that eats it."),
        ("c2", "So choose the constraint that buys the freedom. The alarm is not the trap. Hitting snooze — that's the trap."),
        ("o1", "Master the morning, or be mastered by it. The chain is real either way. There is no third door."),
    ],
    "scenes": [
        {"line": None, "at": "start", "kind": "title", "kick": "THE STOIC PARADOX", "title": "Discipline\nis freedom", "sub": None, "outlineLine": 2},
        {"line": "h1", "kind": "statement", "text": "Everyone wants freedom. Almost nobody connects it to the alarm clock.", "em": ["freedom", "alarm"]},
        {"line": "q1", "kind": "quote", "text": "No person is free who is not master of themselves.", "who": "Epictetus — himself a slave"},
        {"line": "s1", "kind": "list", "head": "Skip it, and it chooses you", "items": ["Skip the training — the body sets the limits", "Ignore the budget — the bills set the schedule", "Avoid the hard talk — the fear does the talking"], "step": 0.5, "chapter": {"title": "The paradox"}},
        {"line": "c1", "kind": "statement", "text": "Undisciplined freedom is just a longer chain with a softer name.", "em": ["longer", "chain"]},
        {"line": "s2", "kind": "statement", "text": "A pilot's checklist is not a cage. Constraints chosen on purpose are the machinery of freedom.", "em": ["machinery"]},
        {"line": "p1", "kind": "particles", "word": "CHOOSE YOUR HARD", "sub": "Both doors cost. Only one pays.", "chapter": {"title": "Two pains"}},
        {"line": "s3", "kind": "compare", "left": {"head": "Pain of discipline", "big": "Chosen", "note": "Measured. Scheduled. Ends."}, "right": {"head": "Pain of regret", "big": "Unpayable", "note": "Permanent. Unscheduled. Stays."}},
        {"line": "s4", "kind": "stats", "items": [{"v": "4:30", "label": "a.m., by choice", "count": False}], "note": "The athlete. The founder. The writer mid-chapter. Nobody chained them there."},
        {"line": "s5", "kind": "statement", "text": "The will is a muscle. Comfort is the rust that eats it.", "em": ["muscle", "rust"]},
        {"line": "c2", "kind": "statement", "text": "The alarm is not the trap. Snooze is the trap.", "em": ["Snooze", "trap"]},
        {"line": "o1", "kind": "outro", "kick": "DISCIPLINE IS FREEDOM", "cta": "Pick your hard tonight.", "handle": "@coreselfmastery"},
    ],
    "score": {
        "bpm": 104, "key": "G", "mode": "minor", "seed": 404, "stereo": True, "space": "hall",
        "sections": [
            {"name": "intro", "bars": 4, "chords": ["i", "VI", "III", "VII"], "layers": ["pad"], "energy": 0.25},
            {"name": "build", "bars": 4, "chords": ["i", "VI", "III", "VII"], "layers": ["pad", "taiko", "bass"], "energy": 0.5, "riser": True},
            {"name": "verse", "bars": 12, "chords": ["i", "VI", "III", "VII"], "layers": ["pad", "taiko", "bass", "hats"], "energy": 0.7, "impact": True},
            {"name": "checklist", "bars": 12, "chords": ["VI", "VII", "i", "i"], "layers": ["taiko", "bass", "pad", "lead"], "energy": 0.9, "impact": True},
            {"name": "hard", "bars": 6, "chords": ["III", "VI", "IV", "VII", "i", "i"], "layers": ["pad", "arp"], "energy": 0.4},
            {"name": "final", "bars": 12, "chords": ["i", "VI", "III", "VII"], "layers": ["kick", "taiko", "hats", "bass", "pad", "lead"], "energy": 1.0, "impact": True, "riser": True},
            {"name": "outro", "bars": 8, "chords": ["VI", "IV", "i", "i", "i", "i", "i", "i"], "layers": ["pad"], "energy": 0.28},
        ],
        "parts": [
            {"inst": "strings", "id": "low", "figure": "sustain", "octave": 3, "gain_db": -8, "send": 0.55, "pan": -0.2},
            {"inst": "strings", "id": "ost", "figure": "ostinato", "octave": 5, "gain_db": -12, "send": 0.5, "pan": 0.25, "params": {"marcato": True}},
        ],
    },
    "metadata": {
        "titles": ["Discipline Is Freedom (The Stoic Paradox)", "The Two Pains on Life's Menu", "Why the Stoics Loved the Alarm Clock"],
        "description": "Epictetus wrote 'no person is free who is not master of themselves' — as a slave. "
                       "Two minutes on the Stoic paradox: chosen constraints, the pilot's checklist, "
                       "the pain of discipline versus the pain of regret. There is no third door.",
        "tags": ["stoicism", "discipline", "freedom", "epictetus", "philosophy", "self discipline", "mindset", "selfmastery", "morning routine", "choose your hard", "regret", "selfimprovement", "personal growth", "marcus aurelius", "willpower"],
    },
})

# ────────────────────────────────────────────────────────────────────────────
# 5 · 66 Days — the habit myth, corrected
FILMS_4_5.append({
    "slug": "the-66-day-machine",
    "title": "66 Days",
    "voice": "en-US-MichelleNeural",
    "premise": "The 21-day habit rule is a myth. The real number is messier — and better news.",
    "palette": {
        "bg0": "#0C0818", "bg1": "#1A1136", "ink": "#F3F0FA", "dim": "#8E86AE",
        "accent": "#A78BFA", "accent2": "#7DD3FC",
        "grad": ["#0C0818", "#1C1240", "#251A55"],
    },
    "grain": 0.05,
    "lead": 3.2, "tail": 3.4,
    "script": [
        ("h1", "You've heard it takes twenty-one days to build a habit. That number was invented by a plastic surgeon, and it's wrong."),
        ("s1", "The twenty-one-day rule came from observations of patients adjusting to new faces in the nineteen-fifties. It was about looking in mirrors, not building lives."),
        ("s2", "Then University College London tracked real people building real habits. The median was sixty-six days. The honest range ran from eighteen to two hundred fifty-four."),
        ("p1", "Sixty-six days. Not a finish line — a median."),
        ("s3", "Here is the better news hidden in that number. Missing one day made no measurable difference. None. The curve forgives the single miss. It only punishes quitting."),
        ("c1", "So the machine needs three things, and motivation is not one of them."),
        ("l1", "Same time, same place. Context is the ignition — the habit starts fastest where the environment already expects it."),
        ("l2", "Make it obvious. The guitar on the stand, not in the case. The book on the pillow, not the shelf."),
        ("l3", "Never miss twice. One miss is life. Two in a row is the start of a new habit — the wrong one."),
        ("s4", "Automaticity climbs like a curve, not a switch. Somewhere around week nine, the argument in your head goes quiet. The behavior just... happens."),
        ("s5", "Want it faster? Stack one habit on another. After the morning coffee, two minutes of stretching. The chain starts carrying itself."),
        ("o1", "Day one is today. Day sixty-six is already on the calendar. The only variable is whether you show up between them."),
    ],
    "scenes": [
        {"line": None, "at": "start", "kind": "title", "kick": "THE HABIT MYTH, CORRECTED", "title": "66\nDays", "sub": None, "outlineLine": 2},
        {"line": "h1", "kind": "statement", "text": "It takes 21 days to build a habit.", "em": ["21", "days"], "strike": ["21"]},
        {"line": "s1", "kind": "quote", "text": "The 21-day rule came from 1950s patients adjusting to new faces in mirrors.", "who": "Dr. Maxwell Maltz, plastic surgeon"},
        {"line": "s2", "kind": "stats", "items": [{"v": "66", "label": "the median, in days"}, {"v": "254", "label": "the honest upper range"}], "note": "University College London, real people, real habits.", "chapter": {"title": "The real number"}},
        {"line": "p1", "kind": "particles", "word": "A MEDIAN", "sub": "Not a finish line."},
        {"line": "s3", "kind": "statement", "text": "Missing one day changed nothing. The curve forgives the single miss. It only punishes quitting.", "em": ["forgives", "quitting"], "chapter": {"title": "The good news"}},
        {"line": "c1", "kind": "statement", "text": "The machine needs three things. Motivation isn't one of them.", "em": ["three"], "chapter": {"title": "The machine"}},
        {"line": "l1", "kind": "list", "head": "One", "items": ["Same time, same place", "Context is the ignition"]},
        {"line": "l2", "kind": "list", "head": "Two", "items": ["Make it obvious", "The guitar on the stand, not in the case"]},
        {"line": "l3", "kind": "list", "head": "Three", "items": ["Never miss twice", "One miss is life. Two is a new habit — the wrong one."]},
        {"line": "s4", "kind": "stats", "items": [{"v": "~9", "suffix": " wks", "label": "when the inner argument goes quiet", "count": False}], "note": "Automaticity climbs like a curve, not a switch.", "chapter": {"title": "The quiet"}},
        {"line": "s5", "kind": "statement", "text": "Stack one habit on another. The chain carries itself.", "em": ["chain"]},
        {"line": "o1", "kind": "outro", "kick": "66 DAYS", "cta": "Day one is today.", "handle": "@coreselfmastery"},
    ],
    "score": {
        "bpm": 92, "key": "E", "mode": "minor", "seed": 505, "stereo": True, "space": "plate",
        "sections": [
            {"name": "intro", "bars": 5, "chords": ["i", "VI", "III", "VII", "VI"], "layers": ["pad"], "energy": 0.25},
            {"name": "myth", "bars": 5, "chords": ["i", "VI", "III", "VII", "VI"], "layers": ["pad", "arp"], "energy": 0.45},
            {"name": "truth", "bars": 12, "chords": ["i", "VI", "III", "VII"], "layers": ["pad", "arp", "bass", "hats"], "energy": 0.65, "impact": True},
            {"name": "relief", "bars": 6, "chords": ["III", "VII", "VI", "IV", "i", "i"], "layers": ["pad", "bell"], "energy": 0.4},
            {"name": "machine", "bars": 12, "chords": ["i", "VI", "III", "VII"], "layers": ["kick", "hats", "bass", "pad", "arp"], "energy": 0.85, "impact": True, "riser": True},
            {"name": "outro", "bars": 8, "chords": ["VI", "IV", "i", "i", "i", "i", "i", "i"], "layers": ["pad", "bell"], "energy": 0.3},
        ],
        "parts": [
            {"inst": "marimba", "figure": "arp-up", "octave": 4, "gain_db": -10, "send": 0.3, "pan": 0.2},
            {"inst": "piano", "figure": "sustain", "octave": 4, "gain_db": -7, "send": 0.4, "pan": -0.15},
        ],
    },
    "metadata": {
        "titles": ["The 21-Day Habit Rule Is a Myth (It's 66)", "66 Days: What Habit Science Actually Says", "Never Miss Twice — The Real Habit Rule"],
        "description": "The 21-day rule came from a 1950s plastic surgeon's patients looking in mirrors. "
                       "UCL tracked real habits: median 66 days, range 18-254 — and missing one day changes nothing. "
                       "The three-part machine that builds habits without motivation.",
        "tags": ["habits", "66 days", "habit formation", "atomic habits", "21 day myth", "discipline", "consistency", "selfimprovement", "behavioral science", "ucl study", "phillippa lally", "never miss twice", "automaticity", "routine building", "selfgrowth"],
    },
})
