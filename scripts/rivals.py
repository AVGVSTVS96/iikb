"""Cleanup sentences said by macOS voices, written by iikb (Parakeet v3, Clean's model and the text path after them,
scripts/stages.py), Wispr Flow and Aqua Voice, and scored against what a good dictation types, in two sets kept apart: seen,
scripts/rivals.txt, which Clean's rules were written against, and held out, heldout.txt in the data folder, written
blind (by an agent that never read iikb's code or these sentences) and never shown to whoever works on Clean, so only
it says how Clean does on sentences nobody fitted it to. iikb's headline is Formal with Clean, picked before the
held-out set was ever run since its answers are written formally; Casual with Clean and As Said are shown beside it.

Runs on the Mac, where the voices, Parakeet and the rivals' logins are. Wispr Flow is reached through the desktop
app's own login (github.com/mathisarends/whisprflow-re, kept in the data folder) with that client's default options
(Casual, Verbatim editing, no dictionary: the account's own aren't sent), Aqua Voice through its API
(api.aquavoice.com/v1/dictations, its key in ~/.config/rivalbench/aqua-key) with the account's settings cleared. Every
answer is kept in the data folder by the clip's sound, so a rival hears each clip once and only iikb runs again.

Scores, per set, system and kind: exact (the text a good dictation types, its last period and spacing aside), words
(the right words, case and punctuation aside) and words wrong against the nearest right answer.
"""

import concurrent.futures, hashlib, json, os, re, shutil, subprocess, sys
from pathlib import Path

import stages

ROOT = Path(__file__).resolve().parent.parent
DATA = Path(os.environ.get("RIVALS_DATA", Path.home() / ".local/share/iikb/rivals"))
VOICES = ["Samantha", "Daniel"]
IIKB = {"iikb": ["formal", "clean", "numbered", "on"], "iikb casual": ["casual", "clean", "numbered", "on"], "iikb as said": ["casual", "asSaid", "numbered", "on"]}
SETS = {"seen": ROOT / "scripts/rivals.txt", "held out": DATA / "heldout.txt"}
RIVALS = ["Wispr Flow", "Aqua Voice"]


def digest(*parts):
    h = hashlib.sha256()
    for part in parts:
        h.update(part if isinstance(part, bytes) else str(part).encode())
    return h.hexdigest()[:20]


def rows(path):
    return [json.loads(line) for line in path.open()] if path.exists() else []


def cases():
    out = []
    for name, path in SETS.items():
        for line in path.read_text().splitlines() if path.exists() else []:
            if line.strip() and not line.startswith("#"):
                kind, said, right = line.split(" | ")
                out.append(dict(set=name, kind=kind, said=said, right=[r.replace("\\n", "\n") for r in right.split(" || ")]))
    return out


def clips(all_cases):
    """Each case said by each voice, as 16 kHz WAV, said once."""
    said = DATA / "said"
    said.mkdir(parents=True, exist_ok=True)
    out = []
    for case in all_cases:
        for voice in VOICES:
            path = said / f"{digest(voice, case['said'])}.wav"
            if not path.exists():
                subprocess.run(["say", "-v", voice, "--data-format=LEI16@16000", "-o", path, case["said"]], check=True)
            out.append(dict(case, voice=voice, path=path, sound=digest(path.read_bytes())))
    return out


def cached(name, clips, write, workers=4):
    """`write(path)` for each clip `name` hasn't answered yet, kept in cache/<name>.jsonl by the clip's sound."""
    cache_path = DATA / f"cache/{name}.jsonl"
    cache_path.parent.mkdir(exist_ok=True)
    cache = {r["sound"]: r["text"] for r in rows(cache_path)}
    missing = {c["sound"]: c["path"] for c in clips if c["sound"] not in cache}
    if missing:
        print(f"{name}: writing {len(missing)} clips", flush=True)
        with concurrent.futures.ThreadPoolExecutor(workers) as pool, cache_path.open("a") as f:
            for sound, text in zip(missing, pool.map(write, missing.values())):
                if text is not None:
                    f.write(json.dumps(dict(sound=sound, text=text)) + "\n")
                    cache[sound] = text
    return {c["sound"]: cache.get(c["sound"]) for c in clips}


def wispr(path):
    script = ("import sys, json; from pathlib import Path; from wisprflow import WisprClient\n"
              "c = WisprClient.from_desktop(session_path=Path.home() / 'Library/Application Support/Wispr Flow/session.json')\n"
              "print(json.dumps(c.transcribe(sys.argv[1]).plaintext))")
    done = subprocess.run(["uv", "run", "-q", "--project", DATA / "whisprflow-re", "python", "-c", script, path],
                          capture_output=True, text=True)
    if done.returncode:
        print(f"Wispr Flow: {done.stderr.strip().splitlines()[-1]}", file=sys.stderr)
        return None
    return json.loads(done.stdout)


AQUA_KEY = Path.home() / ".config/rivalbench/aqua-key"


def aqua_settings(body):
    """Sets the account's dictionary, replacements and instructions (`body`, PATCH /v1/customizations) and returns
    them as they were, so the bench hears Aqua at its defaults and the account gets its own back."""
    key = AQUA_KEY.read_text().strip()
    api = ["-H", f"Authorization: Bearer {key}", "https://api.aquavoice.com/v1/customizations"]
    was = json.loads(subprocess.run(["curl", "-s", *api], capture_output=True, text=True, check=True).stdout)
    subprocess.run(["curl", "-s", "-X", "PATCH", "-H", "Content-Type: application/json", "-d", json.dumps(body), *api],
                   capture_output=True, check=True)
    return {"operations": [{"type": "custom_instructions_set", "text": was["custom_instructions"]},
                           {"type": "dictionary_replace", "words": was["dictionary"]},
                           *({"type": "replacement_set", "from": r["from"], "to": r["to"]} for r in was["replacements"])]}


def aqua_defaults(said):
    """Aqua's answers, the account at its defaults while it hears the clips it hasn't."""
    cache = {r["sound"] for r in rows(DATA / "cache/aqua.jsonl")}
    if all(c["sound"] in cache for c in said):
        return cached("aqua", said, aqua)
    key = AQUA_KEY.read_text().strip()
    api = ["-H", f"Authorization: Bearer {key}", "https://api.aquavoice.com/v1/customizations"]
    was = json.loads(subprocess.run(["curl", "-s", *api], capture_output=True, text=True, check=True).stdout)
    own = aqua_settings({"operations": [{"type": "custom_instructions_set", "text": ""},
                                        {"type": "dictionary_replace", "words": []},
                                        *({"type": "replacement_remove", "from": r["from"]} for r in was["replacements"])]})
    try:
        return cached("aqua", said, aqua)
    finally:
        aqua_settings(own)


def aqua(path):
    key = AQUA_KEY.read_text().strip()
    done = subprocess.run(["curl", "-s", "https://api.aquavoice.com/v1/dictations", "-H", f"Authorization: Bearer {key}",
                           "-F", f"audio=@{path}", "-F", "language=en"], capture_output=True, text=True)
    answer = json.loads(done.stdout or "{}")
    if "text" not in answer:
        print(f"Aqua Voice: {answer}", file=sys.stderr)
        return None
    return answer["text"]


def parakeet(clips):
    """Parakeet v3 as iikb's dictation runs it (Tools/VoiceBench), for the clips this version of it hasn't written."""
    tool = ROOT / "Tools/VoiceBench"
    files = [tool / "Package.swift", *sorted((tool / "Sources").rglob("*.swift"))]
    version = digest(*(f"{f.relative_to(tool)}\n".encode() + f.read_bytes() for f in files))
    cache_path = DATA / f"cache/parakeet-{version}.jsonl"
    cache_path.parent.mkdir(exist_ok=True)
    cache ={r["sound"]: r["text"] for r in rows(cache_path)}
    missing = {c["sound"]: c["path"] for c in clips if c["sound"] not in cache}
    if missing:
        print(f"parakeet: writing {len(missing)} clips", flush=True)
        subprocess.run(["rsync", "-aL", "--delete", "--exclude", ".build", "--exclude", "Text", f"{tool}/", DATA / "tool"], check=True)
        subprocess.run(["swift", "build", "-c", "release", "--package-path", DATA / "tool"], check=True, stdout=subprocess.DEVNULL)
        pending = DATA / "pending"
        shutil.rmtree(pending, ignore_errors=True)
        (pending / "audio").mkdir(parents=True)
        for sound, path in missing.items():
            shutil.copy(path, pending / f"audio/{sound}.wav")
        (pending / "clips.jsonl").write_text("".join(json.dumps(dict(id=s, audio_path=f"audio/{s}.wav")) + "\n" for s in missing))
        subprocess.run([DATA / "tool/.build/release/VoiceBench", pending, "dictation"], check=True, stdout=subprocess.DEVNULL)
        with cache_path.open("a") as f:
            for r in rows(pending / "outputs/dictation.jsonl"):
                f.write(json.dumps(dict(sound=r["id"], text=r["text"])) + "\n")
                cache[r["id"]] = r["text"]
        shutil.rmtree(pending)
    return {c["sound"]: cache[c["sound"]] for c in clips}


# Scoring

NUMBERS = {w: str(i) for i, w in enumerate(
    "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen "
    "eighteen nineteen twenty".split())} | {w: str(20 + 10 * i) for i, w in enumerate("thirty forty fifty sixty seventy eighty ninety".split(), 1)}


def words(text):
    text = re.sub(r"\b([ap])\.\s?m\.", r"\1m", text.lower().replace("’", "'"))
    tokens = re.findall(r"[a-z0-9]+(?:[.':@/,%-][a-z0-9]+)*", text)
    return [NUMBERS.get(t, re.sub(r":00$", "", t)) for t in tokens if t != "o'clock"]


def shape(text):
    """The text as it reads, its spacing, blank lines, curly apostrophes, bullet glyph and last period aside."""
    text = re.sub(r"\s*\n\s*", "\n", re.sub(r"[ \t]+", " ", text.replace("’", "'")))
    return re.sub(r"(?m)^[-*•] ", "• ", text).strip().rstrip(".").strip()


def distance(a, b):
    row = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        prev, row[0] = row[0], i
        for j, y in enumerate(b, 1):
            prev, row[j] = row[j], min(row[j] + 1, row[j - 1] + 1, prev + (x != y))
    return row[-1]


def scored(text, right):
    if text is None:
        return None
    wrong = min(distance(words(r), words(text)) / max(len(words(r)), 1) for r in right)
    return dict(exact=any(shape(text) == shape(r) for r in right), words=wrong == 0, wrong=wrong)


def main():
    all_cases = cases()
    said = clips(all_cases)
    heard = parakeet(said)
    replies = {sound: row.get("edited") for sound, row in stages.edited(heard).items()}
    tool = stages.text_stage()
    typed = {name: stages.typed(tool, heard, settings, replies) for name, settings in IIKB.items()}
    answers = {name: {sound: text for sound, (text, _) in rows.items()} for name, rows in typed.items()}
    answers["Wispr Flow"] = cached("wispr", said, wispr, workers=1)
    answers["Aqua Voice"] = aqua_defaults(said)
    systems = [*IIKB, *RIVALS]
    results = [dict(set=c["set"], kind=c["kind"], said=c["said"], voice=c["voice"], right=c["right"], parakeet=heard[c["sound"]],
                    **{s: answers[s].get(c["sound"]) for s in systems}) for c in said]
    for r in results:
        r["scores"] = {s: scored(r[s], r["right"]) for s in systems}
    (DATA / "results.jsonl").write_text("".join(json.dumps(r) + "\n" for r in results))

    kinds = list(dict.fromkeys(c["kind"] for c in all_cases))
    for name in [n for n in SETS if any(c["set"] == n for c in all_cases)]:
        here = [r for r in results if r["set"] == name]
        print(f"\n{name}: {len(here) // len(VOICES)} cases x {len(VOICES)} voices; exact / right words / words wrong")
        print(f"{'':12}" + "".join(f"{s:>22}" for s in systems))
        for kind in [None, *kinds]:
            line = f"{kind or 'all':12}"
            for s in systems:
                got = [r["scores"][s] for r in here if r["scores"][s] and kind in (None, r["kind"])]
                if not got:
                    line += f"{'-':>22}"
                    continue
                line += f"{sum(g['exact'] for g in got) / len(got):>8.0%}{sum(g['words'] for g in got) / len(got):>6.0%}{sum(g['wrong'] for g in got) / len(got):>8.1%}"
            print(line)

    for name, rows in typed.items():
        print(f"{name}: the model's reply typed for {sum(taken for _, taken in rows.values())} of {len(rows)} clips")


if __name__ == "__main__":
    main()
