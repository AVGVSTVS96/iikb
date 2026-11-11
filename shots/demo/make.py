#!/usr/bin/env python3
# Writes a made-up week or so of iikb use into a folder, for screenshots that must show no one's real typing, messages
# or clipboard: touches.json (the iPhone Duo's four screens), typing.jsonl, transcripts.jsonl with recordings/<id>.wav,
# mac.json (Keystroke's version 3 file), clipboard.json and app-names.json (AppName's answers, so no shot waits on the App
# Store), each in the shape scripts/sim's fill copies (shots/demo/env). Everything is the same on every run but the dates, which
# count back from now (IIKB_NOW when set, in seconds since 1970), so Today, "2h" and "Yesterday" hold whenever the shots are taken.
# python3 shots/demo/make.py <folder>
import json
import math
import os
import random
import struct
import sys
import time
import uuid
from datetime import datetime, timedelta

FOUNDATION = 978307200  # 2001-01-01, where Swift's Date counts from
NOW = float(os.environ.get("IIKB_NOW") or time.time())
TODAY = datetime.fromtimestamp(NOW).replace(hour=0, minute=0, second=0, microsecond=0)
ROWS = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
INDENT = [0, 0.5, 1.5]
FREQUENCY = dict(
    zip(
        "etaoinshrdlcumwfgypbvkjxqz",
        [12.7, 9.1, 8.2, 7.5, 7.0, 6.7, 6.3, 6.1, 6.0, 4.3, 4.0, 2.8, 2.8, 2.4, 2.4, 2.2, 2.0, 2.0, 1.9, 1.5, 1.0, 0.8,
         0.15, 0.15, 0.1, 0.07],
    )
)


def day(date):
    return date.strftime("%Y-%m-%d")


# The touch model, as KeyboardCore's TouchModel learns it (Correction/TouchModel.swift): each key's taps, where its
# last 30 and last 3 center, and how well each predicted the key.
PRIOR_SPREAD, PRIOR_WEIGHT, RECENT, LATELY, NOW_TAPS, SWITCHING = 0.2, 10.0, 48, 30.0, 3.0, 0.01


def touches():
    return {"count": 0.0, "meanX": 0.0, "meanY": 0.0, "scatterXX": 0.0, "scatterXY": 0.0, "scatterYY": 0.0}


def drift():
    return {"count": 0.0, "x": 0.0, "y": 0.0}


def spread(keys):
    weight = PRIOR_WEIGHT - 3
    prior = weight * PRIOR_SPREAD * PRIOR_SPREAD
    xx, xy, yy, count = prior, 0.0, prior, 0.0
    for t in keys:
        shrink = t["count"] / (1 + t["count"])
        xx += t["scatterXX"] + shrink * t["meanX"] ** 2
        xy += t["scatterXY"] + shrink * t["meanX"] * t["meanY"]
        yy += t["scatterYY"] + shrink * t["meanY"] ** 2
        count += t["count"]
    scale = 1 / (weight + count)
    return xx * scale, xy * scale, yy * scale


def posterior(t, s):
    n = t["count"]
    kappa = 1 + n
    shrink = n / kappa
    weight = PRIOR_WEIGHT - 3
    dof = PRIOR_WEIGHT + n - 1
    scale = (kappa + 1) / (kappa * dof)
    return {
        "mean": (shrink * t["meanX"], shrink * t["meanY"]),
        "kappa": kappa,
        "dof": dof,
        "xx": (weight * s[0] + t["scatterXX"] + shrink * t["meanX"] ** 2) * scale,
        "xy": (weight * s[1] + t["scatterXY"] + shrink * t["meanX"] * t["meanY"]) * scale,
        "yy": (weight * s[2] + t["scatterYY"] + shrink * t["meanY"] ** 2) * scale,
    }


def aiming(p, d):
    kappa = 1 + d["count"]
    mean = ((p["mean"][0] + d["count"] * d["x"]) / kappa, (p["mean"][1] + d["count"] * d["y"]) / kappa)
    rescale = (kappa + 1) / kappa * p["kappa"] / (p["kappa"] + 1)
    return {**p, "mean": mean, "kappa": kappa, "xx": p["xx"] * rescale, "xy": p["xy"] * rescale, "yy": p["yy"] * rescale}


def log_predictive(p, u, v):
    determinant = p["xx"] * p["yy"] - p["xy"] ** 2
    du, dv = u - p["mean"][0], v - p["mean"][1]
    distance = (p["yy"] * du * du - 2 * p["xy"] * du * dv + p["xx"] * dv * dv) / determinant
    return -math.log(2 * math.pi) - math.log(determinant) / 2 - (p["dof"] / 2 + 1) * math.log1p(distance / p["dof"])


def learn(key, u, v, s):
    whole = posterior(key["all"], s)
    scores = [log_predictive(p, u, v) for p in (whole, aiming(whole, key["lately"]), aiming(whole, key["now"]))]
    best = max(scores)
    odds = [w * math.exp(score - best) for w, score in zip(key["weights"], scores)]
    key["weights"] = [(1 - SWITCHING) * o / sum(odds) + SWITCHING / 3 for o in odds]
    t = key["all"]
    t["count"] += 1
    dx, dy = u - t["meanX"], v - t["meanY"]
    t["meanX"] += dx / t["count"]
    t["meanY"] += dy / t["count"]
    t["scatterXX"] += dx * (u - t["meanX"])
    t["scatterXY"] += dx * (v - t["meanY"])
    t["scatterYY"] += dy * (v - t["meanY"])
    for name, memory in (("lately", LATELY), ("now", NOW_TAPS)):
        d = key[name]
        d["count"] = d["count"] * (1 - 1 / memory) + 1
        d["x"] += (u - d["x"]) / d["count"]
        d["y"] += (v - d["y"]) / d["count"]


def place(label):
    """Where a key sits, -1 (left edge) to 1 (right edge), and its row; the space bar is row 3."""
    if label == " ":
        return 0.0, 3
    row = next(i for i, keys in enumerate(ROWS) if label in keys)
    return (ROWS[row].index(label) + INDENT[row] - 4.5) / 4.5, row


def rare(label):
    return label != " " and FREQUENCY[label] < 1


def layout(rng, taps, sx, sy, pull, wanders):
    """One screen's keys after `taps` taps: two thumbs that pull the edges in and land the top row low, each key a
    little its own way, a few keys aimed differently lately (`wanders`)."""
    counts = {label: round(taps * 0.82 * f / 100) for label, f in FREQUENCY.items()}
    counts[" "] = round(taps * 0.18)
    aims = {}
    for label in counts:
        c, row = place(label)
        if row == 3:
            aims[label] = (0.12 + rng.gauss(0, 0.02), -0.15 + rng.gauss(0, 0.02), 0.09, 0.15, 0.05)
            continue
        edge = 1 + 0.45 * c * c
        aims[label] = (
            pull * (-0.22 * c**3 - 0.05 * c) + rng.gauss(0, 0.035),
            pull * [0.17, 0.02, -0.05][row] + rng.gauss(0, 0.03),
            sx * edge * (1 + rng.gauss(0, 0.06)) * (1.25 if rare(label) else 1),
            sy * edge * (1 + rng.gauss(0, 0.06)) * (1.25 if rare(label) else 1),
            -0.2 * c,
        )
    order = [label for label, n in counts.items() for _ in range(n)]
    rng.shuffle(order)
    seen = {label: 0 for label in counts}
    keys = {}
    recent = {}
    for label in order:
        seen[label] += 1
        mx, my, dx, dy, r = aims[label]
        if label in wanders and seen[label] > counts[label] - 40:
            mx, my = mx + wanders[label][0], my + wanders[label][1]
        a, b = rng.gauss(0, 1), rng.gauss(0, 1)
        u = mx + dx * a
        v = my + dy * (r * a + math.sqrt(1 - r * r) * b)
        key = keys.setdefault(label, {"all": touches(), "lately": drift(), "now": drift(), "weights": [1 / 3] * 3})
        s = spread([keys[" "]["all"]] if label == " " else [k["all"] for name, k in keys.items() if name != " "])
        learn(key, u, v, s)
        recent.setdefault(label, []).append({"x": round(u, 3), "y": round(v, 3)})
    return keys, {label: taps[-RECENT:] for label, taps in recent.items()}


def touch_model(rng, screens):
    model = {"layouts": {}, "recent": {}}
    for signature, taps, sx, sy, pull, wanders in screens:
        model["layouts"][signature], model["recent"][signature] = layout(rng, taps, sx, sy, pull, wanders)
    return model


# The hours typed, as the keyboard shares them (KeyboardCore's TypingHour), over six weeks with two days off.
APPS = [
    ("com.apple.MobileSMS", "Messages", 30), ("net.whatsapp.WhatsApp", "WhatsApp", 14),
    ("com.tinyspeck.chatlyio", "Slack", 14), ("com.anthropic.claude", "Claude", 10), ("com.google.Gmail", "Gmail", 8),
    ("com.apple.mobilenotes", "Notes", 8), ("com.atebits.Tweetie2", "X", 7), ("com.apple.mobilesafari", "Safari", 5),
    ("com.apple.reminders", "Reminders", 2), ("", "", 2),
]
HOURS = [8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]
# Today runs up to the hour it is now, its day moved earlier when that's before its first six hours have passed, so
# shots taken early in the morning still have today's typing to show.
EARLY = min(0, datetime.fromtimestamp(NOW).hour - (HOURS[0] + 6))


def typing(rng):
    lines = []
    for back in range(41, -1, -1):
        date = TODAY - timedelta(days=back)
        weekend = date.weekday() >= 5
        busy = rng.uniform(0.6, 1.4) * (0.7 if weekend else 1)
        hours = sorted(rng.sample(HOURS, rng.randint(5, 9)))
        for hour in hours:
            for app in {pick(rng, weekend) for _ in range(rng.randint(1, 3))}:
                characters = int(rng.lognormvariate(5.6, 0.6) * busy)
                wpm = rng.gauss(41, 7)
                words = round(characters / 5.7)
                deletes = round(characters * rng.uniform(0.05, 0.1))
                picked = round(words * rng.uniform(0.03, 0.08))
                corrected = round(words * rng.uniform(0.01, 0.04))
                tally = {
                    "keys": round(characters * 0.94) + deletes,
                    "characters": characters,
                    "deletes": deletes,
                    "words": words,
                    "corrected": corrected,
                    "undone": round(corrected * 0.12),
                    "picked": picked,
                    "emoji": rng.randint(0, 3) if app in ("com.apple.MobileSMS", "net.whatsapp.WhatsApp") else 0,
                }
                at = hour + EARLY if back == 0 else hour
                if back in (23, 31) or (back == 0 and not 0 <= at <= datetime.fromtimestamp(NOW).hour):
                    continue
                lines.append(
                    {"day": day(date), "hour": at, "app": app, "tally": tally,
                     "seconds": round(characters / 5 / max(wpm, 18) * 60, 3)}
                )
    return lines


def pick(rng, weekend):
    apps = [(app, w * (0.2 if weekend and app == "com.tinyspeck.chatlyio" else 1)) for app, _, w in APPS]
    return rng.choices([a for a, _ in apps], [w for _, w in apps])[0]


# Dictations: days and minutes back, what was said, and where it went (None: not typed).
SAID = [
    (0, 12, "On my way, grabbing coffee first. Want anything?", "com.apple.MobileSMS"),
    (0, 48, "Can we push the design review to Thursday afternoon? I want another pass on the onboarding flow before we "
     "show it.", "com.tinyspeck.chatlyio"),
    (0, 125, "Remind me to renew the car registration before the end of the month.", "com.apple.reminders"),
    (0, 280, "Groceries: oat milk, lemons, two avocados, sourdough, and whatever looks good for dinner.",
     "com.apple.mobilenotes"),
    (1, 30, "Running ten minutes late, save me a seat.", "net.whatsapp.WhatsApp"),
    (1, 190, "Thanks for sending this over. I read through it last night and I think the second option is the stronger "
     "one, mostly because it keeps the setup short. Happy to talk it through tomorrow.", "com.google.Gmail"),
    (1, 400, "Explain the difference between a mutex and a semaphore like I'm new to concurrency.",
     "com.anthropic.claude"),
    (1, 520, "Happy birthday! Hope the trip is amazing, send pictures.", "com.apple.MobileSMS"),
    (2, 60, "The sunset from the pier tonight was unreal.", "com.atebits.Tweetie2"),
    (2, 300, "Sounds good, let's do seven.", "com.apple.MobileSMS"),
    (2, 640, "Idea for the weekend: rent bikes, ride the coast, lunch somewhere with a view.", None),
    (3, 90, "I'll take a look this afternoon and leave comments on the pull request.", "com.tinyspeck.chatlyio"),
    (3, 410, "Book a table for four on Saturday around eight, somewhere quiet.", "com.apple.mobilenotes"),
    (4, 200, "Did you end up watching the finale? No spoilers, I'm two episodes behind.", "net.whatsapp.WhatsApp"),
    (4, 560, "Write a short packing list for three days of hiking with one night of camping.", "com.anthropic.claude"),
    (5, 150, "Call the dentist Monday morning to move the appointment.", "com.apple.reminders"),
    (6, 75, "Can you send me the recipe for that lemon pasta? It was so good.", "com.apple.MobileSMS"),
    (6, 330, "Quick update: the build is green again and the release notes are drafted. I'll tag it once the last "
     "review is in.", "com.tinyspeck.chatlyio"),
    (7, 240, "Meet at the north entrance of the park at ten.", "net.whatsapp.WhatsApp"),
    (8, 120, "Notes from the call: ship the beta Friday, collect feedback over the weekend, decide on pricing next week.",
     "com.apple.mobilenotes"),
    (9, 500, "Just landed, heading to the hotel now.", "com.apple.MobileSMS"),
    (10, 180, "What's a good way to keep basil alive indoors?", "com.anthropic.claude"),
    (11, 360, "Love this, thanks for sharing.", "com.atebits.Tweetie2"),
    (12, 90, "Can you pick up the package from the front desk if you get home first?", "com.apple.MobileSMS"),
    (13, 420, "Following up on last week's thread: we're good to go on the new layout.", "com.google.Gmail"),
    (15, 200, "Pancakes this Sunday? I'll bring the berries.", "net.whatsapp.WhatsApp"),
    (17, 300, "Reminder to water the plants and take out recycling.", "com.apple.reminders"),
    (19, 150, "That talk was great, the part about small teams really stuck with me.", "com.tinyspeck.chatlyio"),
]


def transcripts(rng):
    said = []
    for back, minutes, text, app in SAID:
        at = NOW - minutes * 60 if back == 0 else (TODAY - timedelta(days=back)).timestamp() + 9 * 3600 + minutes * 60
        words = len(text.split())
        said.append(
            {
                "id": str(uuid.uuid5(uuid.NAMESPACE_URL, "iikb-demo:" + text)).upper(),
                "date": round(at - FOUNDATION, 3),
                "text": text,
                "seconds": round(words / rng.uniform(135, 175) * 60 + rng.uniform(0.6, 1.4), 2),
                "typed": app is not None,
                "model": "Parakeet v3",
                "mic": "iPhone Microphone",
                "voiceProcessing": False,
                **({"app": app} if app else {}),
            }
        )
    return sorted(said, key=lambda t: t["date"])


def wav():
    """A tenth of a second of silence, as Recording writes one: 16 kHz, 16-bit, mono."""
    data = bytes(3200)
    return (
        b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVEfmt " + struct.pack("<IHHIIHH", 16, 1, 1, 16000, 32000, 2, 16)
        + b"data" + struct.pack("<I", len(data)) + data
    )


# What was copied, minutes back, newest first; the address is pinned.
COPIED = [
    (6, "Meet at Sightglass on 7th, 4pm?", False),
    (41, "https://en.wikipedia.org/wiki/International_Typographic_Style", False),
    (110, "#FF6B00", False),
    (180, "https://www.youtube.com/watch?v=aircAruvnKk", False),
    (300, "https://github.com/swiftlang/swift/pull/80000", False),
    (1500, "oat milk\nlemons\ntwo avocados\nsourdough", False),
    (1560, "(415) 555-0132", False),
    (2900, "hello@example.com", True),
    (4400, "https://x.com/vercel/status/1985000000000000001?s=46", False),
    (8800, "The best way to get a project done faster is to start sooner.", False),
]


def clipboard():
    items = [{"content": {"text": {"_0": text}}, "found": round(NOW - minutes * 60, 3), "pinned": pinned}
             for minutes, text, pinned in COPIED]
    return {"history": {"saved": items[::-1]}, "seen": 0, "refused": False}


# The Mac, as Keystroke counts it: more typing than the iPhone, some dictation.
MAC_APPS = {"cursor": ("Cursor", 5200), "slack": ("Slack", 2100), "notes": ("Notes", 900), "mail": ("Mail", 640)}


def mac(rng):
    days = {}
    histogram = {}
    for back in range(41, -1, -1):
        date = TODAY - timedelta(days=back)
        weekend = date.weekday() >= 5
        if back in (23, 30) or (weekend and rng.random() < 0.5):
            continue
        typed = {"keystrokes": 0, "chars": 0, "words": 0, "backspaces": 0, "activeMs": 0, "timedChars": 0, "timedMs": 0,
                 "inserts": 0, "hourChars": [0] * 24, "peakWpm": 0}
        voice = {**typed, "hourChars": [0] * 24}
        for hour in range(9, 24) if back else range(max(0, 9 + EARLY), datetime.fromtimestamp(NOW).hour + 1):
            if rng.random() < (0.35 if weekend else 0.75):
                chars = int(rng.lognormvariate(7.1, 0.5))
                wpm = rng.gauss(68, 9)
                typed["chars"] += chars
                typed["words"] += round(chars / 5.8)
                typed["backspaces"] += round(chars * 0.08)
                typed["keystrokes"] += round(chars * 1.09)
                typed["activeMs"] += round(chars / 5 / wpm * 60000)
                typed["hourChars"][hour] += chars
                typed["peakWpm"] = max(typed["peakWpm"], round(wpm + rng.uniform(15, 35), 1))
                band = str(int(wpm // 5 * 5))
                histogram[band] = histogram.get(band, 0) + rng.randint(3, 9)
            if rng.random() < 0.18:
                chars = int(rng.lognormvariate(5.3, 0.5))
                voice["chars"] += chars
                voice["words"] += round(chars / 5.6)
                voice["timedChars"] += chars
                voice["timedMs"] += round(chars / 5.6 / 150 * 60000)
                voice["inserts"] += 1
                voice["hourChars"][hour] += chars
        days[day(date)] = {"typed": typed, "voice": voice}
    return {
        "version": 3,
        "days": days,
        "wpmHistogram": histogram,
        "sources": {key: {"name": name, "words": words} for key, (name, words) in MAC_APPS.items()},
    }


def main(folder):
    rng = random.Random(2593)
    os.makedirs(os.path.join(folder, "recordings"), exist_ok=True)
    def write(name, value, lines=False):
        with open(os.path.join(folder, name), "w") as file:
            if lines:
                file.writelines(json.dumps(line, separators=(",", ":")) + "\n" for line in value)
            else:
                json.dump(value, file, separators=(",", ":"))

    write("touches.json", touch_model(rng, [
        ("phone-portrait-letters", 9200, 0.17, 0.14, 0.85, {"o": (-0.14, 0.04), "n": (0.1, -0.08)}),
        ("phone-portrait-letters-open", 5100, 0.14, 0.15, 0.8, {"o": (-0.12, 0.03)}),
        ("phone-landscape-letters-open", 2600, 0.13, 0.17, 0.7, {}),
        ("phone-landscape-letters", 700, 0.15, 0.17, 0.8, {}),
    ]))
    write("typing.jsonl", typing(rng), lines=True)
    said = transcripts(rng)
    write("transcripts.jsonl", said, lines=True)
    for transcript in said:
        with open(os.path.join(folder, "recordings", transcript["id"] + ".wav"), "wb") as file:
            file.write(wav())
    write("clipboard.json", clipboard())
    write("mac.json", mac(rng))
    write("app-names.json", {app: name for app, name, _ in APPS if app})


if __name__ == "__main__":
    main(sys.argv[1])
