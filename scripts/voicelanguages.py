"""scripts/voicelanguages [--text <checkout>]: dictation in each language iikb types, from the sound to what the keyboard
types, scored per language on three sets:

fleurs: 120 sentences per language read by real people (Google's FLEURS dev split, CC BY 4.0), against their written
form: how well the words are heard, case and punctuation aside.
said: scripts/voicelanguages.txt, said by the language's macOS voices: punctuation said by name, fillers, numbers,
addresses and names, written beside the code that passes them.
heldout: ~/.local/share/iikb/heldout/languages.txt, the same kinds written blind (never read it while writing rules).

Each clip goes through Parakeet v3 as the app runs it (Tools/VoiceBench on the Mac, in a turn), once per clip and
version of that path (kept in the data folder's cache), then the text path here (Tools/VoiceBench/Text) three ways:
`en` as one typing English alone, `own` the language alone, `both` English and the language. `--text <checkout>`
builds the text path from another checkout, such as one at origin/main, to score what it typed before.
Data in ~/.local/share/iikb/voicelanguages, never the repo.
"""
import argparse, collections, hashlib, json, os, re, shutil, subprocess, sys, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = Path.home() / ".local/share/iikb/voicelanguages"
HELDOUT = Path.home() / ".local/share/iikb/heldout/languages.txt"
FLEURS = {"es": "es_419", "fr": "fr_fr", "de": "de_de", "pt": "pt_br", "it": "it_it", "sv": "sv_se", "en": "en_us"}
VOICES = {"es": ["Mónica", "Paulina"], "fr": ["Thomas", "Jacques"], "de": ["Anna", "Eddy (German (Germany))"],
          "pt": ["Luciana", "Joana"], "it": ["Alice", "Eddy (Italian (Italy))"], "sv": ["Alva"]}
MAC = "Developer/voicelang"
WAYS = {"en": lambda lang: ["en"], "own": lambda lang: [lang], "both": lambda lang: ["en", lang] if lang != "en" else ["en", "de"]}


def rows(path):
    return [json.loads(line) for line in path.open()] if path.exists() else []


def digest(*parts):
    h = hashlib.sha256()
    for part in parts:
        h.update(part if isinstance(part, bytes) else str(part).encode())
    return h.hexdigest()[:16]


def cases(path):
    out = []
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        lang, kind, say, typed = (p.strip() for p in line.split(" | ", 3))
        out.append(dict(lang=lang, kind=kind, say=say, right=[a.strip().replace("\\n", "\n") for a in typed.split(" || ")]))
    return out


def clips():
    """Every clip of every set: id, language, kind, what's said, the right answers, and its sound's key."""
    out = []
    for lang, folder in FLEURS.items():
        for line in (DATA / "fleurs" / folder / "refs.tsv").read_text().splitlines():
            name, ref = line.split("\t", 1)
            out.append(dict(set="fleurs", id=f"fleurs/{folder}/{name}", lang=lang, kind="read", right=[ref],
                            audio=f"fleurs/{folder}/{name}"))
    for name, path in [("said", ROOT / "scripts/voicelanguages.txt"), ("heldout", HELDOUT)]:
        if not path.exists():
            continue
        for case in cases(path):
            for voice in VOICES[case["lang"]]:
                key = digest(voice, case["say"])
                out.append(dict(set=name, id=f"{name}/{key}", lang=case["lang"], kind=case["kind"], right=case["right"],
                                say=case["say"], voice=voice, audio=f"said/{key}.aiff"))
    return out


def engine():
    tool = ROOT / "Tools/VoiceBench"
    files = [tool / "Package.swift", *sorted((tool / "Sources").rglob("*.swift"))]
    return digest(*(f"{f.relative_to(tool)}\n".encode() + f.read_bytes() for f in files))


def parakeet(all_clips):
    """What Parakeet wrote for each clip, saying and writing on the Mac only the clips the cache lacks."""
    cache_path = DATA / f"cache/parakeet-{engine()}.jsonl"
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache = {r["audio"]: r["text"] for r in rows(cache_path)}
    missing = [c for c in all_clips if c["audio"] not in cache]
    if missing:
        print(f"parakeet: writing {len(missing)} of {len(all_clips)} clips on the Mac", flush=True)
        say = [c for c in missing if "say" in c]
        if say:
            script = "".join(f"[ -f {c['audio']} ] || say -v {sh(c['voice'])} -o {c['audio']} {sh(c['say'])}\n" for c in say)
            subprocess.run(["ssh", "mac", f"mkdir -p ~/{MAC}/said && cd ~/{MAC} && sh"], input=script, text=True, check=True)
        subprocess.run(["rsync", "-a", "--exclude", "*.tsv", f"{DATA}/fleurs/", f"mac:{MAC}/fleurs/"], check=True)
        subprocess.run(["rsync", "-aL", "--delete", "--exclude", ".build", "--exclude", "Text", f"{ROOT}/Tools/VoiceBench/",
                        f"mac:{MAC}/benchtool/"], check=True)
        listing = "".join(json.dumps(dict(id=c["audio"], audio_path=c["audio"])) + "\n" for c in missing)
        subprocess.run(["ssh", "mac", f"cat > ~/{MAC}/clips.jsonl"], input=listing, text=True, check=True)
        subprocess.run(["ssh", "mac", f"cd ~/{MAC} && swift build -c release --package-path benchtool >/dev/null && "
                        f"~/.local/bin/turn benchtool/.build/release/VoiceBench ~/{MAC} dictation"], check=True,
                       stdin=subprocess.DEVNULL)
        written = subprocess.run(["ssh", "mac", f"cat ~/{MAC}/outputs/dictation.jsonl"], capture_output=True, text=True,
                                 check=True).stdout
        new = [json.loads(line) for line in written.splitlines() if line]
        with cache_path.open("a") as f:
            f.writelines(json.dumps(dict(audio=r["id"], text=r["text"])) + "\n" for r in new)
        cache.update({r["id"]: r["text"] for r in new})
    return {c["id"]: cache[c["audio"]] for c in all_clips}


def sh(text):
    return "'" + text.replace("'", "'\\''") + "'"


def lexicons():
    """The published word lists the manifest names, as scripts/eval languages downloads them."""
    folder = ROOT / "build/languages"
    folder.mkdir(parents=True, exist_ok=True)
    manifest = ROOT / "Packages/KeyboardModules/Sources/KeyboardStore/Resources/Languages/manifest.json"
    for entry in json.load(manifest.open())["lexicons"]:
        path = folder / f"{entry['id']}.lexicon"
        if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
            urllib.request.urlretrieve(entry["url"], path)
    return folder


def text_tool(root):
    """Tools/VoiceBench/Text of `root`, built on a package of its KeyboardCore alone, as scripts/voiceloop builds it."""
    pkg = ROOT / "build" / f"voicetext-{digest(str(root))}"
    (pkg / "Sources/VoiceText").mkdir(parents=True, exist_ok=True)
    for link, target in [(pkg / "Sources/KeyboardCore", root / "Packages/KeyboardModules/Sources/KeyboardCore"),
                         (pkg / "Sources/VoiceText/main.swift", root / "Tools/VoiceBench/Text/main.swift")]:
        if not link.is_symlink():
            link.symlink_to(target)
    (pkg / "Package.swift").write_text("""// swift-tools-version: 6.2
import PackageDescription

let package = Package(name: "VoiceText", targets: [
    .target(name: "KeyboardCore", exclude: ["AGENTS.md"]),
    .executableTarget(name: "VoiceText", dependencies: ["KeyboardCore"]),
])
""")
    built = subprocess.run(["swift", "build", "-c", "release", "--build-system", "native", "-Xswiftc",
                            "-no-whole-module-optimization", "--package-path", pkg], capture_output=True, text=True)
    if built.returncode:
        sys.exit(built.stdout + built.stderr)
    return pkg / ".build/release/VoiceText"


def typed(tool, root, heard, all_clips, way):
    given = "".join(json.dumps(dict(id=c["id"], heard=heard[c["id"]], languages=WAYS[way](c["lang"]))) + "\n"
                    for c in all_clips)
    vocabulary = DATA / "vocabulary.json"
    vocabulary.write_text('{"terms": []}')
    done = subprocess.run([tool, root / "Packages/KeyboardModules/Sources/KeyboardEnglish/Resources/en.lexicon", vocabulary,
                           "-", "casual", "light", "numbered", "on"], input=given, capture_output=True, text=True,
                          check=True, env=dict(os.environ, LANGUAGES=str(lexicons())))
    return {r["id"]: r for r in map(json.loads, filter(None, done.stdout.split("\n")))}


WORD = re.compile(r"\w+(?:[.,'’@_/-]\w+)*")


def words(text):
    return WORD.findall(text.lower().replace("’", "'"))


def wrong(said, right):
    """Word edits from `right` to `said`, and `right`'s length."""
    a, b = words(right), words(said)
    row = list(range(len(b) + 1))
    for i in range(1, len(a) + 1):
        prev, row[0] = row[0], i
        for j in range(1, len(b) + 1):
            prev, row[j] = row[j], min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] != b[j - 1]))
    return row[-1], len(a)


def exact(said, right):
    """The same text, spacing and a last period aside."""
    def plain(text):
        text = re.sub(r"[   ]+", " ", text).strip()
        text = re.sub(r" (?=[?!:;»%])|(?<=«) ", "", text)
        return text[:-1] if text.endswith(".") else text
    return plain(said) == plain(right)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--text", type=Path, default=ROOT)
    parser.add_argument("--misses", help="print each miss of a set, as set/lang")
    args = parser.parse_args()
    all_clips = clips()
    heard = parakeet(all_clips)
    tool = text_tool(args.text.resolve())
    results = {way: typed(tool, args.text.resolve(), heard, all_clips, way) for way in WAYS}
    table = collections.defaultdict(lambda: [0, 0, 0, 0])
    for way, out in results.items():
        for c in all_clips:
            said = out[c["id"]]["typed"]
            edits, length = min((wrong(said, r) for r in c["right"]), key=lambda e: e[0] / max(e[1], 1))
            for key in [(c["set"], c["lang"], way), (c["set"], c["lang"], way, c["kind"])]:
                t = table[key]
                t[0] += edits
                t[1] += length
                t[2] += any(exact(said, r) for r in c["right"])
                t[3] += 1
            if args.misses == f"{c['set']}/{c['lang']}" and way == "own" and not any(exact(said, r) for r in c["right"]):
                print(f"{c.get('say', '')}\n  heard {heard[c['id']]!r}\n  typed {said!r}\n  right {c['right'][0]!r}")
    print(f"{'set':<8}{'lang':<6}" + "".join(f"{w + ' wrong':>12}{w + ' exact':>12}" for w in WAYS))
    for s in ["fleurs", "said", "heldout"]:
        for lang in FLEURS:
            if (s, lang, "own") not in table:
                continue
            cells = "".join(f"{100 * table[s, lang, w][0] / max(table[s, lang, w][1], 1):>11.2f}%"
                            f"{100 * table[s, lang, w][2] / table[s, lang, w][3]:>11.1f}%" for w in WAYS)
            print(f"{s:<8}{lang:<6}{cells}")
    kinds = sorted({k[3] for k in table if len(k) == 4 and k[0] != "fleurs"})
    print("\nexact by kind, own language, said and heldout:")
    for s in ["said", "heldout"]:
        for kind in kinds:
            cells = "".join(f"{lang}:{100 * table[s, lang, 'own', kind][2] / table[s, lang, 'own', kind][3]:5.0f}%  "
                            for lang in VOICES if (s, lang, "own", kind) in table)
            if cells:
                print(f"  {s:<8}{kind:<10}{cells}")


if __name__ == "__main__":
    main()
