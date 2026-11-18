"""The iPhone owner's own typing for scripts/eval (OwnerTyping.swift), written from the record and the backup on this box
into the folder given, which never leaves it. Two windows of days, each a folder:

text.txt     what was sent in the window, oldest first: the app, a tab, and a sentence's words. From the record
             (sources/record.ts), its messages sent (not fields left, whose text may stop mid-word), with what dictation typed
             taken out, and each sentence cut wherever a word holds more than letters and apostrophes.
memory.json  the keyboard's typing memory as the iPhone had it when the window began (typing-memory.json),
en.network   and its personal next-word network, so neither has learned a word of the window's text.
taps.txt     a key, a tab, and where the owner's taps for it land, in key cells from its center, as the touch model kept
             them on the folded iPhone Duo's letters when the window ended.

dev is what a change is tuned against; test is the later window, the number to report. The windows are fixed, so the
same backup always gives the same folders; moving them is a change to eval.expected.

Usage: scripts/owner.py <folder> [record.jsonl [backup]]
"""

import json, os, re, shutil, sys
from datetime import datetime, timezone

WINDOWS = {"dev": ("2026-11-06", "2026-11-11"), "test": ("2026-11-11", "2026-11-16")}
KINDS = {"text", "webSearch", "twitter"}
LAYOUT = "phone-portrait-letters"
SINCE_2001 = 978307200

folder = sys.argv[1]
record = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.local/share/iikb/record.jsonl")
backup = sys.argv[3] if len(sys.argv) > 3 else os.path.expanduser("~/.local/share/iikb/backup")


def moment(day):
    return datetime.fromisoformat(day).replace(tzinfo=timezone.utc).timestamp()


def copies(path):
    """Every copy of a backed-up file, mirror or replaced, with when the iPhone wrote it."""
    found = [f"{backup}/mirror/{path}"] + [f"{entry.path}/{path}" for entry in os.scandir(f"{backup}/versions")]
    return [(os.path.getmtime(p), p) for p in found if os.path.exists(p)]


def copy_at(path, time):
    """The copy the iPhone had at `time`: the newest written before it."""
    before = [copy for copy in copies(path) if copy[0] <= time]
    return max(before)[1] if before else None


def words(text):
    return re.findall(r"[a-z']+", text.lower().replace("’", "'"))


def sentences(text):
    """Runs of plain words, cut at sentence ends, line breaks and any word with more than letters and apostrophes."""
    for part in re.split(r"[.!?\n]+", text.replace("’", "'")):
        run = []
        for token in part.split():
            word = token.strip("\"“”()[]{},;:*_~").lower()
            if re.fullmatch(r"[a-z]+('[a-z]+)*", word):
                run.append(word)
            else:
                if run:
                    yield run
                run = []
        if run:
            yield run


def dictated():
    """What dictation typed, with when, so it can be taken out of the record."""
    out = []
    with open(f"{backup}/mirror/app/transcripts.jsonl") as file:
        for line in file:
            entry = json.loads(line)
            field = entry.get("field") or {}
            for text in {entry.get("text", ""), field.get("typed", ""), field.get("final", "")}:
                text = re.sub(r"\s+", " ", text).strip()
                if len(text.split()) >= 2:
                    out.append((entry["date"] + SINCE_2001, text))
    return out


def sent(start, end, dictations):
    said = [words(text) for when, text in dictations if when < end]
    shingles = {tuple(w[i:i + 4]) for w in said for i in range(len(w) - 3)}
    kept = []
    with open(record) as file:
        for line in file:
            entry = json.loads(line)
            at = datetime.fromisoformat(entry["at"].replace("Z", "+00:00")).timestamp()
            if entry["event"] != "sent" or entry.get("kind", "text") not in KINDS or not start <= at < end:
                continue
            text = entry["text"]
            for when, dictation in dictations:
                if at - 86400 <= when <= at + 60 and dictation in text:
                    text = text.replace(dictation, "\n")
            for run in sentences(text):
                grams = [tuple(run[i:i + 4]) for i in range(len(run) - 3)]
                if not grams or sum(g in shingles for g in grams) <= 0.3 * len(grams):
                    kept.append(f"{entry.get('app', '')}\t{' '.join(run)}")
    return kept


dictations = dictated()
for split, (first, last) in WINDOWS.items():
    start, end = moment(first), moment(last)
    out = f"{folder}/{split}"
    os.makedirs(out, exist_ok=True)
    memory = copy_at("keyboard/support/typing-memory.json", start)
    network = copy_at("group/Library/Personal/en.network", start)
    touches = copy_at("group/Library/touches.json", end)
    if not (memory and network and touches):
        sys.exit(f"the backup has no memory, personal network or taps for {split}")
    shutil.copyfile(memory, f"{out}/memory.json")
    shutil.copyfile(network, f"{out}/en.network")
    with open(touches) as file:
        recent = json.load(file)["recent"][LAYOUT]
    with open(f"{out}/taps.txt", "w") as file:
        for key, taps in sorted(recent.items()):
            file.write(f"{key}\t{' '.join(f'{t['x']},{t['y']}' for t in taps)}\n")
    lines = sent(start, end, dictations)
    with open(f"{out}/text.txt", "w") as file:
        file.write("\n".join(lines) + "\n")
    print(f"{split}: {len(lines)} sentences, {sum(len(l.split('\t')[1].split()) for l in lines)} words", file=sys.stderr)
