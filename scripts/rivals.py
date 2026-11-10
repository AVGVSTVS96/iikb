"""scripts/rivals.txt said by macOS voices, written by iikb (Parakeet v3 and its text path, as scripts/voiceloop runs
them), Wispr Flow and Aqua Voice, and scored against what a good dictation types.

Runs on the Mac, where the voices, Parakeet and the rivals' logins are. Wispr Flow is reached through the desktop
app's own login (github.com/mathisarends/whisprflow-re, kept in the data folder), Aqua Voice through its API
(api.aquavoice.com/v1/dictations, its key in ~/.config/rivalbench/aqua-key), each at its default settings. Every
answer is kept in the data folder by the clip's sound, so a rival hears each clip once and only iikb runs again.

Scores, per system and per kind: exact (the text a good dictation types, its last period and spacing aside), words
(the right words, case and punctuation aside) and words wrong against the nearest right answer.
"""

import concurrent.futures, hashlib, json, os, re, shutil, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = Path(os.environ.get("RIVALS_DATA", Path.home() / ".local/share/iikb/rivals"))
LEXICON = ROOT / "Packages/KeyboardModules/Sources/KeyboardEnglish/Resources/en.lexicon"
VOICES = ["Samantha", "Daniel"]
IIKB = {"iikb": ["casual", "asSaid", "numbered", "on"], "iikb clean": ["casual", "clean", "numbered", "on"], "iikb formal": ["formal", "clean", "numbered", "on"]}
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
    for line in (ROOT / "scripts/rivals.txt").read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            kind, said, right = line.split(" | ")
            out.append(dict(kind=kind, said=said, right=[r.replace("\\n", "\n") for r in right.split(" || ")]))
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
        subprocess.run([DATA / "tool/.build/release/VoiceBench", pending, "dictation", "100"], check=True, stdout=subprocess.DEVNULL)
        with cache_path.open("a") as f:
            for r in rows(pending / "outputs/dictation-100.jsonl"):
                f.write(json.dumps(dict(sound=r["id"], text=r["text"])) + "\n")
                cache[r["id"]] = r["text"]
        shutil.rmtree(pending)
    return {c["sound"]: cache[c["sound"]] for c in clips}


def text_stage():
    """Tools/VoiceBench/Text on a package of KeyboardCore alone, as scripts/voiceloop builds it."""
    pkg = ROOT / "build/voicetext"
    (pkg / "Sources/VoiceText").mkdir(parents=True, exist_ok=True)
    for link, target in [(pkg / "Sources/KeyboardCore", ROOT / "Packages/KeyboardModules/Sources/KeyboardCore"),
                         (pkg / "Sources/VoiceText/main.swift", ROOT / "Tools/VoiceBench/Text/main.swift")]:
        if not link.is_symlink():
            link.symlink_to(target)
    (pkg / "Package.swift").write_text("""// swift-tools-version: 6.2
import PackageDescription

let package = Package(name: "VoiceText", platforms: [.macOS(.v26)], targets: [
    .target(name: "KeyboardCore", exclude: ["AGENTS.md"]),
    .executableTarget(name: "VoiceText", dependencies: ["KeyboardCore"]),
])
""")
    built = subprocess.run(["swift", "build", "-c", "release", "--package-path", pkg], capture_output=True, text=True)
    if built.returncode:
        sys.exit(built.stdout + built.stderr)
    return pkg / ".build/release/VoiceText"


def typed(tool, heard, settings):
    vocabulary = DATA / "vocabulary.json"
    vocabulary.write_text('{"terms": []}')
    given = "".join(json.dumps(dict(id=s, heard=t)) + "\n" for s, t in heard.items())
    done = subprocess.run([tool, LEXICON, vocabulary, "-", *settings], input=given, capture_output=True, text=True, check=True)
    return {r["id"]: r["typed"] for r in map(json.loads, filter(None, done.stdout.split("\n")))}


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
    tool = text_stage()
    answers = {name: typed(tool, heard, settings) for name, settings in IIKB.items()}
    answers["Wispr Flow"] = cached("wispr", said, wispr, workers=1)
    answers["Aqua Voice"] = aqua_defaults(said)
    systems = [*IIKB, *RIVALS]
    results = [dict(kind=c["kind"], said=c["said"], voice=c["voice"], right=c["right"], parakeet=heard[c["sound"]],
                    **{s: answers[s].get(c["sound"]) for s in systems}) for c in said]
    for r in results:
        r["scores"] = {s: scored(r[s], r["right"]) for s in systems}
    (DATA / "results.jsonl").write_text("".join(json.dumps(r) + "\n" for r in results))

    kinds = list(dict.fromkeys(c["kind"] for c in all_cases))
    print(f"\n{len(all_cases)} cases x {len(VOICES)} voices; exact / right words / words wrong")
    print(f"{'':12}" + "".join(f"{s:>22}" for s in systems))
    for kind in [None, *kinds]:
        line = f"{kind or 'all':12}"
        for s in systems:
            got = [r["scores"][s] for r in results if r["scores"][s] and kind in (None, r["kind"])]
            if not got:
                line += f"{'-':>22}"
                continue
            line += f"{sum(g['exact'] for g in got) / len(got):>8.0%}{sum(g['words'] for g in got) / len(got):>6.0%}{sum(g['wrong'] for g in got) / len(got):>8.1%}"
        print(line)


if __name__ == "__main__":
    main()
