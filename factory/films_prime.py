"""Discipline Prime — the 3-minute flagship film.

One blueprint, many engines: the same script, score and shot list drive
 - diffusion video (LTX-Video) on the Kaggle 2x T4 box, one worker per GPU
 - AI stills + camera motion (kenburns) anywhere else — same cut, same mix

Everything here is deterministic on its own; the Groq director only polishes
shot prompts (validated, blueprint as fallback) and publish metadata.

Timing contract: seconds = 180.0 (lead 4.0 + narration ~168-170 + tail ~6).
"""

# The one recurring character — identical wording in every shot keeps the
# generated face as consistent as image/diffusion models allow.
MAN = "a fit man in his late twenties, short dark hair, trimmed beard"

# The look — appended to every still prompt.
STYLE_STILL = ("Cinematic film still, 35mm anamorphic lens, low-key moody lighting, "
               "photorealistic, ultra-detailed, shallow depth of field, cold blue-hour "
               "palette with warm amber accents, subtle film grain, no text, no watermark, "
               "no logos, no brands.")

# Camera language per motion token — appended to the diffusion prompt.
CAMERA = {
    "in":       "slow dolly-in, steady cinematic camera move",
    "out":      "slow dolly-out, steady cinematic camera move",
    "left":     "slow lateral tracking shot moving left",
    "right":    "slow lateral tracking shot moving right",
    "up":       "slow tilt-up camera move",
    "down":     "slow tilt-down camera move",
    "in-left":  "slow diagonal dolly-in moving slightly left",
    "in-right": "slow diagonal dolly-in moving slightly right",
    "out-up":   "slow pull-back and tilt-up crane shot",
}

FILM_PRIME = {
    "slug": "discipline-prime",
    "title": "The Hour No One Sees",
    "premise": "4:59 AM. Discipline isn't built in the spotlight — it's built in the dark, "
               "in the unglamorous middle, Tuesday after Tuesday. Three cinematic minutes "
               "on the hour that quietly builds a life.",
    "seconds": 180.0,
    "voice": "en-US-ChristopherNeural",
    "lead": 4.0,
    "tail": 6.0,
    "gap": 0.42,
    "palette": {
        "bg0": "#05090F", "bg1": "#0D1626", "ink": "#F2EFE7", "dim": "#8A94A6",
        "accent": "#F2B33D", "accent2": "#38BDF8",
        "grad": ["#05090F", "#0B1B33", "#123252"],
    },
    "grade": {  # the assemble-stage look
        "contrast": 1.06, "saturation": 1.04, "temperature": 0.92,   # cool the whole frame
        "shadow_tint": "#0E2036", "highlight_tint": "#FFD9A0",
        "vignette": 0.22, "grain": 0.05,
    },
    "script": [
        ("h1", "Four fifty-nine in the morning. The world is asleep. Nobody is watching."),
        ("h2", "Which is why this hour matters. Discipline isn't built in the spotlight. It's built in the dark."),
        ("s1", "Yesterday, motivation had you planning a new life. But motivation is a visitor. It leaves before morning."),
        ("s2", "What remains is the decision you made. The alarm is not a question. It's an appointment with yourself."),
        ("c1", "So you rise. Not because you feel like it. Because you said you would. That's the whole secret."),
        ("s3", "Cold water on your face. The day hasn't given you a reason. You bring your own."),
        ("s4", "Shoes laced. Door shut behind you. The street belongs to you and the streetlights now."),
        ("g1", "Every step in the dark is a deposit into someone the daylight hasn't met."),
        ("s5", "No one claps out here. There's no music swelling. Only breath, and pavement, and repetition."),
        ("c2", "This is the part nobody ever posts. The unglamorous middle. Tuesday after Tuesday after Tuesday."),
        ("s6", "While the world hits snooze, you compound. Quietly. The math doesn't need an audience."),
        ("s7", "One percent today. Invisible today. Unstoppable eventually."),
        ("g2", "Discipline isn't a feeling you wait for. It's a promise you keep — especially when it costs you."),
        ("s8", "Comfort arrives dressed as reason. Sleep in. Skip once. You've earned it, surely."),
        ("c3", "But you know what the first exception is. Not the last mistake — the first step back to zero."),
        ("s9", "So you sit down and do the work. Line after line. Rep after rep."),
        ("s10", "Then something strange happens. The work isn't lighter. You are stronger."),
        ("g3", "Sixty-six days in, you stop forcing it. The machine runs on you now — and carries you through empty days."),
        ("s11", "The body you wanted was forged in hours like this. So was the skill. The calm."),
        ("c4", "One day somebody asks how you changed. You won't know where to begin."),
        ("s12", "Never a single moment. Only this hour, repeated, until it added up to a life."),
        ("g4", "The sun is rising. Same streets, same city. You are not the same in them."),
        ("s13", "Not because you won something. Because you kept something. Day after day, when quitting was forgivable."),
        ("c5", "Talent decides where you start. Discipline decides where you stop."),
        ("o1", "Tomorrow, the alarm rings again. Four fifty-nine. Dark. Silent. Yours."),
        ("o2", "Get up anyway. Keep the promise again. And watch what ordinary hours become."),
    ],
    # 36 shots ≈ 5 s each. line = narration row this shot is bound to (timing snaps
    # near that line's start); motion drives kenburns + becomes camera language for
    # diffusion; sfx = event placed at the shot's first frame.
    "shots": [
        {"id": "sh01", "line": None, "motion": "in",
         "prompt": f"Extreme close-up of a vintage analog alarm clock in a pitch-black bedroom, hands at 4:59, faint cold blue moonlight from a window, dust in the air.",
         "sfx": "tick"},
        {"id": "sh02", "line": "h1", "motion": "left",
         "prompt": "A vast sleeping city at 4 AM seen from a high apartment window, sodium streetlights in the fog, cold blue haze, rooftops descending into darkness.",
         "sfx": "air"},
        {"id": "sh03", "line": "h1", "motion": "in",
         "prompt": f"{MAN} lying awake in bed in a dark bedroom, eyes open staring at the ceiling, grey sheets, dim streetlight through half-closed blinds.",
         "sfx": None},
        {"id": "sh04", "line": "h2", "motion": "in",
         "prompt": f"A hand switching on a small bedside lamp, a cone of warm amber light cutting through a dark bedroom, hard shadows, moody chiaroscuro.",
         "sfx": None},
        {"id": "sh05", "line": "s1", "motion": "out",
         "dip": True,
         "prompt": "A crowded race start at golden hour, runners in bright jerseys full of energy, warm overexposed nostalgic light, shot like a fond memory.",
         "sfx": None},
        {"id": "sh06", "line": "s1", "motion": "right",
         "prompt": "The same city street now empty and dark at night, cold blue tones, a single flickering streetlamp, wet asphalt reflecting nothing.",
         "sfx": "whoosh"},
        {"id": "sh07", "line": "s2", "motion": "in",
         "prompt": f"Close-up of {MAN}'s hand firmly pressing the top of a ringing analog alarm clock, decisive gesture, hard side light in a dark room.",
         "sfx": "impact"},
        {"id": "sh08", "line": "c1", "motion": "up",
         "prompt": f"Silhouette of {MAN} sitting up on the edge of the bed, head bowed, rim light from streetlights cutting through venetian blinds, dark room.",
         "sfx": None},
        {"id": "sh09", "line": "s3", "motion": "in",
         "dip": True,
         "prompt": f"{MAN} splashing cold water on his face at a dark bathroom mirror, water droplets frozen mid-air, hard cold side light, dark tiles.",
         "sfx": None},
        {"id": "sh10", "line": "s3", "motion": "out",
         "prompt": "Macro shot of water drops falling from a man's jaw into a white porcelain sink, black background, single hard light, glistening droplets.",
         "sfx": None},
        {"id": "sh11", "line": "s4", "motion": "in",
         "prompt": f"Close-up of {MAN}'s hands lacing worn running shoes in a dark hallway, one bare bulb casting a warm pool of light, shallow focus.",
         "sfx": None},
        {"id": "sh12", "line": "s4", "motion": "left",
         "prompt": "An apartment door closing shut seen from a dim stairwell, cold fluorescent light, painted concrete stairs, moody emptiness.",
         "sfx": "whoosh"},
        {"id": "sh13", "line": "s4", "motion": "out",
         "dip": True,
         "prompt": f"Very wide shot of {MAN} in a dark grey hoodie beginning a run down an empty suburban street at 5 AM, breath visible in cold air, streetlights receding into darkness.",
         "sfx": "air"},
        {"id": "sh14", "line": "g1", "motion": "right",
         "prompt": "Aerial top-down view of a lone runner on a long empty road cutting through dark fields before dawn, cold blue moonlight, tiny figure, immense negative space.",
         "sfx": None},
        {"id": "sh15", "line": "s5", "motion": "right",
         "prompt": f"Side tracking shot of {MAN} running mid-stride on a rain-slicked road at pre-dawn blue hour, asphalt reflections, mist, motion energy.",
         "sfx": "whoosh"},
        {"id": "sh16", "line": "s5", "motion": "in",
         "prompt": "Extreme close-up of breath vapor in freezing air, backlit by a distant streetlamp, blue night tones, drifting fog particles.",
         "sfx": None},
        {"id": "sh17", "line": "s5", "motion": "in",
         "prompt": "Low angle close-up of worn running shoes striking wet pavement, water splashing from each footstrike, streetlight bokeh, dark background.",
         "sfx": None},
        {"id": "sh18", "line": "c2", "motion": "left",
         "prompt": f"The long shadow of {MAN} running along a tall concrete wall in morning haze, single hard light source, minimal composition.",
         "sfx": None},
        {"id": "sh19", "line": "c2", "motion": "down",
         "dip": True,
         "prompt": "An empty gym interior before opening hours, one hanging lamp, chalk dust hanging in the air, a loaded barbell on the floor, darkness all around.",
         "sfx": None},
        {"id": "sh20", "line": "c2", "motion": "in",
         "prompt": f"Close-up of {MAN}'s hands gripping a knurled barbell in chalk dust clouds, hard directional light, dark gym, tension in the knuckles.",
         "sfx": "whoosh"},
        {"id": "sh21", "line": "s6", "motion": "in",
         "prompt": "A round wall clock above a dark gym, hands sweeping through the hours, window light slowly shifting from night blue to dawn gold.",
         "sfx": "tick"},
        {"id": "sh22", "line": "s7", "motion": "out",
         "dip": True,
         "prompt": "A desk late at night: laptop glow on notebooks, a coffee cup gone cold, city lights bokeh through the window behind, one small lamp.",
         "sfx": None},
        {"id": "sh23", "line": "g2", "motion": "in",
         "prompt": "Macro shot of a pen writing steady lines on paper by lamplight, ink glistening, handwriting filling the page, dark warm surroundings.",
         "sfx": None},
        {"id": "sh24", "line": "g2", "motion": "up",
         "prompt": f"{MAN} seen from behind hunched at a desk in a dark room, face lit only by the screen, focused stillness, monitor glow on his shoulders.",
         "sfx": None},
        {"id": "sh25", "line": "s8", "motion": "in",
         "prompt": "A hand placing a smartphone face-down on a wooden desk, decisively, warm lamp light, dark cozy room, the temptation removed.",
         "sfx": None},
        {"id": "sh26", "line": "c3", "motion": "in",
         "prompt": f"Close-up of {MAN}'s eyes in a dark room reflecting the pale light of a distant screen, steady determined gaze, extreme detail.",
         "sfx": None},
        {"id": "sh27", "line": "s9", "motion": "left",
         "prompt": "A wall calendar with weeks of days crossed off in pen, pages fanned by a breeze from an open window at night, lamplight.",
         "sfx": "tick"},
        {"id": "sh28", "line": "s10", "motion": "up",
         "prompt": "A barbell being lifted from the gym floor in a single shaft of morning light, dust particles ignited, plates glinting, dark background.",
         "sfx": "impact"},
        {"id": "sh29", "line": "g3", "motion": "right",
         "prompt": f"{MAN} running up a long hill road in early daylight, stronger stride, sweat on his brow, softer golden light, haze over fields.",
         "sfx": "whoosh"},
        {"id": "sh30", "line": "g4", "motion": "out",
         "dip": True,
         "prompt": "Sunrise breaking over a city skyline seen from an empty street, gold light flooding upward through blue, long dramatic shadows.",
         "sfx": "riser"},
        {"id": "sh31", "line": "g4", "motion": "in-right",
         "prompt": f"{MAN} standing at the top of an outdoor staircase overlook above the city at sunrise, hood down, towel over his shoulder, breathing deep, gold rim light.",
         "sfx": None},
        {"id": "sh32", "line": "s11", "motion": "in",
         "prompt": f"{MAN} at the same bathroom mirror months later, steadier posture, calm eyes, morning light now filling the room instead of darkness.",
         "sfx": None},
        {"id": "sh33", "line": "c4", "motion": "left",
         "prompt": f"A morning crowd rushing along a busy sidewalk while {MAN} walks calmly among them in the other direction, subtle confidence, golden hour.",
         "sfx": None},
        {"id": "sh34", "line": "c5", "motion": "out-up",
         "prompt": f"Wide silhouette of {MAN} standing on a grassy ridge at dawn, sun cresting the horizon behind him, city below in mist, heroic minimal composition.",
         "sfx": "shimmer"},
        {"id": "sh35", "line": "o1", "motion": "in",
         "prompt": "The dark bedroom again: the analog alarm clock showing 4:59, a faint pre-dawn smile of light on the wall, quiet anticipation.",
         "sfx": "tick"},
        {"id": "sh36", "line": "o2", "motion": "out",
         "prompt": "The sun fully risen over the waking city, warm golden light washing over rooftops, gentle lens flare, a new day begun.",
         "sfx": "ding"},
    ],
    "score": {
        "bpm": 92, "key": "D", "mode": "minor", "seed": 311, "stereo": True, "space": "hall",
        "sections": [   # 69 bars x 2.6087 s = 180.0 s exactly
            {"name": "intro",  "bars": 6,  "chords": ["i", "VI", "III", "VII", "VI", "IV"],              "layers": ["pad"],                          "energy": 0.22},
            {"name": "build",  "bars": 8,  "chords": ["i", "VI", "III", "VII", "i", "VI", "III", "VII"], "layers": ["pad", "arp", "bass"],           "energy": 0.45, "riser": True, "fill": True},
            {"name": "verse",  "bars": 14, "chords": ["i", "VI", "III", "VII"],                          "layers": ["pad", "arp", "bass", "hats"],   "energy": 0.62, "impact": True},
            {"name": "lift",   "bars": 14, "chords": ["VI", "VII", "i", "i"],                            "layers": ["kick", "hats", "bass", "pad", "arp", "lead"], "energy": 0.88, "impact": True},
            {"name": "breathe","bars": 6,  "chords": ["III", "VI", "IV", "VII", "VI", "IV"],             "layers": ["pad", "arp"],                   "energy": 0.40},
            {"name": "final",  "bars": 14, "chords": ["i", "VI", "III", "VII"],                          "layers": ["kick", "hats", "bass", "pad", "arp", "lead"], "energy": 1.00, "impact": True},
            {"name": "outro",  "bars": 7,  "chords": ["VI", "IV", "i", "i", "i", "i", "i"],              "layers": ["pad"],                          "energy": 0.25},
        ],
        "parts": [
            {"inst": "piano",   "figure": "sustain", "octave": 4, "gain_db": -7, "send": 0.4, "pan": -0.15},
            {"inst": "strings", "figure": "sustain", "octave": 4, "gain_db": -9, "send": 0.6, "pan": 0.2},
        ],
    },
    "metadata": {
        "titles": [
            "The Hour No One Sees — Discipline (3 Minute Cinematic Film)",
            "4:59 AM — The Hour Where Discipline Is Built",
            "Nobody Is Watching — A Short Film About Discipline",
        ],
        "description": "4:59 AM. The world is asleep and nobody is watching — which is exactly why "
                       "this hour matters. A three-minute cinematic short about discipline: rising "
                       "without motivation, the unglamorous middle, the quiet compounding nobody "
                       "claps for, and the sunrise you earn by keeping a promise to yourself. "
                       "Made with AI-generated cinematography, an original score and foley.",
        "tags": ["discipline", "motivation", "selfimprovement", "mindset", "habits", "stoicism",
                 "consistency", "hardwork", "5ammorning", "selfgrowth", "grind", "discipline motivation",
                 "cinematic short film", "ai film", "core self mastery"],
    },
}
