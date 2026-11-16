"""Builds the corpora scripts/voicebench scores from Bassim's own dictations on the backup server, into voicebench/
beside the backup (never the repo: they're his voice and his words). Run it with
`uv run --with numpy scripts/voicecorpus.py [out]`; it writes three, and two more once he's given what they need:

real: every dictation Parakeet v3 wrote and iikb typed, with what it finally became as the reference: its transcript's
`field.final`, what the keyboard followed it to until its field was sent or changed, or else the span of what was sent
in the three hours after (the record source's log) that its words line up with. typed.jsonl is what iikb
typed, and clips.jsonl each clip's date, mic, how it was heard (its transcript's `capture`, voice processing, raw or a
front cardioid; or else its `voiceProcessing`; or, from before iikb kept either, whether it came after voice processing
went in), its room and speech levels (each a group voicescore splits by), where its final came from and whether he
edited it (`edit`: a final he left as typed is what the build of its day typed, so it scores agreement with that build,
not accuracy, and only an edited one says what he meant). A dictation whose words line up with nothing he sent is left
out, since it has no final; scripts/voicelabel can still pick it to be labelled. context.jsonl
is what scripts/voiceloop replays the rest of the iPhone's path with: what the model wrote on the iPhone, the kind of
field it went into (and its content type) and the text the keyboard saw before it there, as its transcript's `field`
kept them, or, from before iikb kept them, the kind and the text before it from the record source's log of that field.

loud: the real set's quiet dictations heard the commonest way (the front cardioid since Nov 7), those he labelled
by ear first and the rest picked by a hash of each id, mixed with the room of its loud ones heard that way (their stretches without speech) at that room's own level, the speech as loud as said
there and 6, 12 and 18 dB quieter (a whisper), each against his label, or else its final. Any quiet dictation can be
picked, not only ones the iPhone already got right, so the clean row is as hard as his real ones.

taps: every dictation Parakeet v3 finished on the iPhone that typed nothing, as a tap with nothing said does, so a
change that writes words there (filler such as "Yeah." or "Thank you.") shows. Its reference is the iPhone's nothing.

labelled: the dictations he labelled by ear (scripts/voicelabel, `heldout/labels.jsonl` beside the backup), each
against what he said: the one set that scores words wrong rather than words he went on to change.

`voicecorpus.py quieter <corpus> <percent>` makes the corpus's clips as said that much quieter in the same room, for
scripts/voicebench.

read: his dictations of `heldout/read.txt`'s lines (a script written blind, never seen by whoever tunes dictation),
each against what that line should type: his voice and rooms on text nothing was fitted to.
"""
import collections, datetime, difflib, hashlib, json, os, random, re, shutil, sys, wave
from pathlib import Path
import numpy as np

HOME = Path.home()
BACKUP = Path(os.environ.get("IIKB_BACKUP", HOME / ".local/share/iikb/backup"))
MIRROR = BACKUP / "mirror"
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else BACKUP.parent / "voicebench"
HELDOUT = BACKUP.parent / "heldout"
EPOCH = datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)
VOICE_PROCESSING = datetime.datetime(2026, 11, 3, 12, 24, tzinfo=datetime.timezone.utc)
LOUD_ROOM = -19
GATED = -90
TOKEN = re.compile(r"[A-Za-z0-9'’]+")


def words(text):
    return [m.group().lower().replace("’", "'") for m in TOKEN.finditer(text)]


def read(path):
    with wave.open(str(path)) as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32767


def write(path, samples):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1), w.setsampwidth(2), w.setframerate(16_000)
        w.writeframes((np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes())


def frames(samples):
    """Each 20 ms frame's level, as Recording.leveled measures it."""
    n = len(samples) // 320
    return samples[: n * 320].reshape(n, 320).std(axis=1)


def levels(samples):
    """The room (10th percentile frame) and the speech (95th), in dBFS."""
    level = np.sort(frames(samples))
    db = lambda x: round(float(20 * np.log10(max(x, 1e-6))), 1)
    return db(level[len(level) // 10]), db(level[len(level) * 95 // 100])


def usual(clips):
    """How loud he usually sounds heard each way: the median speech of the clips with that `capture`."""
    return {way: np.median([c["speech_db"] for c in clips if c["capture"] == way]) for way in {c["capture"] for c in clips}}


def rooms(clips, voice):
    """Labels each clip's room loud when it's within 19 dB of how loud he usually sounds heard the same way (`voice`,
    from `usual`), which is -40 dBFS for iOS's own pick: the front cardioid adds no gain, so it hears his voice and his
    rooms 18 dB under that, and -40 dBFS alone called 45 of its 834 dictations loud where this calls 140."""
    for clip in clips:
        clip["room"] = "loud" if clip["room_db"] - voice[clip["capture"]] >= LOUD_ROOM else "quiet"
    return clips


def heard_most(clips):
    """The clips heard the commonest way, so a set mixed from them keeps one microphone's levels."""
    way = collections.Counter(c["capture"] for c in clips).most_common(1)[0][0]
    return [c for c in clips if c["capture"] == way]


def sent():
    """Everything sent, oldest first: the record source's log."""
    at = lambda s: datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    out = [("record", at(r["at"]), r["text"], r["kind"]) for r in map(json.loads, open(BACKUP.parent / "record.jsonl"))]
    return sorted(out, key=lambda c: c[1])


def locate(said, text):
    """The share of the dictation's words found in `text`, and the span of `text` they became: from the first to the
    last word lined up with it, in the biggest group of matches that sit together, widened over the dictation's own
    unmatched words at either edge."""
    found = words(text)
    blocks = [b for b in difflib.SequenceMatcher(None, said, found, autojunk=False).get_matching_blocks() if b.size]
    if not blocks:
        return 0, None
    groups = [[blocks[0]]]
    for before, block in zip(blocks, blocks[1:]):
        if block.b - (before.b + before.size) <= block.a - (before.a + before.size) + 8:
            groups[-1].append(block)
        else:
            groups.append([block])
    group = max(groups, key=lambda g: sum(b.size for b in g))
    first, last = group[0], group[-1]
    lo = max(first.b - first.a, 0)
    hi = min(last.b + last.size + len(said) - (last.a + last.size), len(found))
    spans = [m.span() for m in TOKEN.finditer(text)]
    if hi <= lo:
        return 0, None
    return sum(b.size for b in group) / len(said), (text[: spans[lo][0]], text[spans[lo][0] : spans[hi - 1][1]])


def final(transcript, candidates):
    """What the dictation became, where that came from, and the field it went into: its kind and the text before it,
    as the transcript kept them, or else from the first field in the record that holds that final (default a message
    field, empty before)."""
    at = EPOCH + datetime.timedelta(seconds=transcript["date"])
    near = [c for c in candidates if at - datetime.timedelta(seconds=60) <= c[1] <= at + datetime.timedelta(hours=3)]
    field = transcript.get("field")
    if field and not field.get("uncertain"):
        if "kind" in field:
            return field["final"], "field", field["kind"], field.get("before") or ""
        found = field["final"].strip() and next((c for c in near if field["final"].strip() in c[2]), None)
        before = found[2][: found[2].index(field["final"].strip())] if found else ""
        return field["final"], "field", found[3] if found else "text", before
    said = words(transcript.get("heard") or transcript["text"])
    if len(said) < 3:
        return None, None, None, None
    best = (0, None, None, None)
    for source, when, text, kind in near:
        share, span = locate(said, text)
        if share > best[0] + 0.02 or (abs(share - best[0]) <= 0.02 and span and best[1] and len(span[1]) > len(best[1][1])):
            best = (share, span, source, kind)
    return (best[1][1], best[2], best[3], best[1][0]) if best[0] >= 0.6 else (None, None, None, None)


def capture(transcript, date):
    """How it was heard: its transcript's `capture`, or else voice processing or iOS's own pick ("raw")."""
    return transcript.get("capture") or ("voiceProcessing" if transcript.get("voiceProcessing", date >= VOICE_PROCESSING) else "raw")


def said_typed(transcript):
    """What the iPhone typed for a dictation."""
    return (transcript.get("field") or {}).get("typed", transcript["text"])


def labels():
    """His labels by ear, the last for each dictation, without the ones he skipped as unclear."""
    path = HELDOUT / "labels.jsonl"
    kept = {r["id"]: r["text"] for r in map(json.loads, open(path))} if path.exists() else {}
    return {id: text for id, text in kept.items() if text is not None}


def lines(path, rows):
    path.write_text("".join(json.dumps(row) + "\n" for row in rows))


def real():
    folder = OUT / "real"
    shutil.rmtree(folder, ignore_errors=True)
    (folder / "audio").mkdir(parents=True)
    candidates = sent()
    clips, references, typed, context = [], [], [], []
    for t in map(json.loads, open(MIRROR / "app/transcripts.jsonl")):
        recording = MIRROR / f"app/recordings/{t['id']}.wav"
        if not t["typed"] or t.get("model") != "Parakeet v3" or not recording.exists():
            continue
        text, source, kind, before = final(t, candidates)
        samples = read(recording)
        if not text or len(samples) < 16_000:
            continue
        os.link(recording, folder / f"audio/{t['id']}.wav")
        date = EPOCH + datetime.timedelta(seconds=t["date"])
        room, speech = levels(samples)
        clips.append(dict(id=t["id"], audio_path=f"audio/{t['id']}.wav", date=date.isoformat(timespec="seconds"),
                          seconds=round(len(samples) / 16_000, 1), room_db=room, speech_db=speech,
                          capture=capture(t, date), mic=t.get("mic") or "unknown",
                          final=source, edit="as typed" if words(text) == words(said_typed(t)) else "edited"))
        references.append(dict(id=t["id"], text=text))
        typed.append(dict(id=t["id"], text=said_typed(t)))
        context.append(dict(id=t["id"], heard=t.get("heard") or t["text"], field=kind, content=(t.get("field") or {}).get("content"), before=before))
    lines(folder / "clips.jsonl", rooms(clips, usual(clips)))
    lines(folder / "references.jsonl", references)
    lines(folder / "typed.jsonl", typed)
    lines(folder / "context.jsonl", context)
    shutil.copy(MIRROR / "app/vocabulary.json", folder / "vocabulary.json")
    print(f"real: {len(clips)} dictations, {sum(c['room'] == 'loud' for c in clips)} in a loud room,",
          f"finals {', '.join(f'{s} {sum(c['final'] == s for c in clips)}' for s in ('field', 'record'))},",
          f"{sum(c['edit'] == 'edited' for c in clips)} of them edited")
    return folder, clips, {r["id"]: r["text"] for r in references}, {r["id"]: r["text"] for r in typed}, {c["id"]: c for c in context}


def room(folder, clips):
    """The loud dictations' stretches without speech, each frame within 6 dB of its recording's room, in runs of half a
    second or more less 40 ms at each end, each brought to the rooms' middle level and joined end to end: one room as
    loud as the middle one. Brought there together, the quietest rooms set the level and the cardioid's loud rooms,
    which span 20 dB, put a tenth of the bed over his voice (Nov 15: as said 42.52% wrong, against 1.10% on his own
    dictations in those rooms)."""
    middle = np.median([c["room_db"] for c in clips])
    parts = []
    for clip in clips:
        samples = read(folder / clip["audio_path"])
        level = frames(samples)
        quiet = np.append(level <= np.sort(level)[len(level) // 10] * 2, False)
        start = None
        for at, still in enumerate(quiet):
            if still and start is None:
                start = at
            elif not still and start is not None:
                if at - start >= 25:
                    parts.append(samples[(start + 2) * 320 : (at - 2) * 320] * 10 ** ((middle - clip["room_db"]) / 20))
                start = None
    return np.concatenate(parts)


def loud(folder, clips, references, typed, context, count=120):
    out = OUT / "loud"
    shutil.rmtree(out, ignore_errors=True)
    (out / "audio").mkdir(parents=True)
    clips = heard_most(clips)
    noisy = [c for c in clips if c["room"] == "loud"]
    bed = room(folder, noisy)
    said = float(np.median([c["speech_db"] for c in noisy]))
    heard = labels()
    clean = [c for c in clips if c["room"] == "quiet" and 3 <= c["seconds"] <= 30]
    picked = sorted(clean, key=lambda c: (c["id"] not in heard, hashlib.sha256(c["id"].encode()).digest()))[:count]
    rows, refs, contexts = [], [], []
    for clip in sorted(picked, key=lambda c: c["date"]):
        samples = read(folder / clip["audio_path"])
        samples = samples * 10 ** ((said - clip["speech_db"]) / 20)
        start = random.Random(clip["id"]).randrange(len(bed))
        noise = np.resize(np.roll(bed, -start), len(samples))
        for quieter in (None, 0, 6, 12, 18):
            mixed = samples * 10 ** (-(quieter or 0) / 20) + (0 if quieter is None else noise)
            mixed /= max(1, np.abs(mixed).max() / 0.99)
            name = f"{clip['id']}-{'clean' if quieter is None else quieter}"
            write(out / f"audio/{name}.wav", mixed)
            room_db, speech_db = levels(mixed)
            rows.append(dict(id=name, audio_path=f"audio/{name}.wav", source=clip["id"], date=clip["date"], room_db=room_db,
                             speech_db=speech_db, speech="clean" if quieter is None else f"-{quieter} dB" if quieter else "as said",
                             reference="label" if clip["id"] in heard else "final", edit=clip["edit"]))
            refs.append(dict(id=name, text=heard.get(clip["id"], references[clip["id"]])))
            contexts.append(dict(context[clip["id"]], id=name))
    lines(out / "clips.jsonl", rows)
    lines(out / "references.jsonl", refs)
    lines(out / "typed.jsonl", [dict(id=r["id"], text=typed[r["source"]]) for r in rows])
    lines(out / "context.jsonl", contexts)
    shutil.copy(folder / "vocabulary.json", out / "vocabulary.json")
    print(f"loud: {len(rows) // 5} of {len(clean)} quiet dictations ({sum(c['id'] in heard for c in picked)} labelled),",
          f"each clean and in a {levels(bed)[0]:.0f} dBFS room",
          f"({len(bed) / 16_000:.0f} s of it from {len(noisy)} dictations) said at {said:.0f} dBFS and 6, 12, 18 dB quieter")


def quieter(corpus, percent):
    """<corpus>/quieter-<percent>/: each clip's speech turned down to `percent`, its own room (its stretches without
    speech, looped) added back as it was, and rounded to 16 bits, as the iPhone's file of someone talking that quietly
    there would be. Turned down alone, a clip loses nothing that leveling can't multiply back, so it can't show what
    quiet speech costs. A clip with no half second without speech, or whose room voice processing gated to digital
    silence, is left out: it has no room to add back."""
    out = corpus / f"quieter-{percent}"
    shutil.rmtree(out, ignore_errors=True)
    (out / "audio").mkdir(parents=True)
    clips = [json.loads(line) for line in open(corpus / "clips.jsonl")]
    kept = []
    for clip in clips:
        samples = read(corpus / clip["audio_path"])
        clip["room_db"] = levels(samples)[0]
        try:
            bed = room(corpus, [clip])
        except ValueError:
            continue
        if clip["room_db"] <= GATED:
            continue
        noise = np.resize(np.roll(bed, -random.Random(clip["id"]).randrange(len(bed))), len(samples))
        write(out / clip["audio_path"], samples * percent / 100 + noise)
        kept.append(clip)
    lines(out / "clips.jsonl", kept)
    print(f"quieter-{percent}: {len(kept)} of {len(clips)} clips, the rest with no room to add back")


def taps():
    folder = OUT / "taps"
    shutil.rmtree(folder, ignore_errors=True)
    (folder / "audio").mkdir(parents=True)
    clips, context = [], []
    for t in map(json.loads, open(MIRROR / "app/transcripts.jsonl")):
        recording = MIRROR / f"app/recordings/{t['id']}.wav"
        if not t["typed"] or t["text"].strip() or t.get("model") != "Parakeet v3" or not recording.exists():
            continue
        os.link(recording, folder / f"audio/{t['id']}.wav")
        field = t.get("field") or {}
        date = EPOCH + datetime.timedelta(seconds=t["date"])
        clips.append(dict(id=t["id"], audio_path=f"audio/{t['id']}.wav", date=date.isoformat(timespec="seconds"),
                          seconds=round(t.get("seconds", 0), 1)))
        context.append(dict(id=t["id"], heard="", field=field.get("kind", "text"), content=field.get("content"),
                            before=field.get("before") or ""))
    lines(folder / "clips.jsonl", clips)
    lines(folder / "references.jsonl", [dict(id=c["id"], text="") for c in clips])
    lines(folder / "context.jsonl", context)
    shutil.copy(MIRROR / "app/vocabulary.json", folder / "vocabulary.json")
    print(f"taps: {len(clips)} dictations that typed nothing")


def heard_set(name, picked):
    """A set of his dictations each against a text given for it (`picked`: transcript → reference and its labels, or
    None), with the context the real set keeps, or for one with no final, a text field with nothing before it."""
    folder = OUT / name
    shutil.rmtree(folder, ignore_errors=True)
    (folder / "audio").mkdir(parents=True)
    candidates = sent()
    clips, references, typed, context = [], [], [], []
    for t in map(json.loads, open(MIRROR / "app/transcripts.jsonl")):
        recording = MIRROR / f"app/recordings/{t['id']}.wav"
        given = picked(t) if t["typed"] and t.get("model") == "Parakeet v3" and recording.exists() else None
        if not given:
            continue
        reference, groups = given
        samples = read(recording)
        os.link(recording, folder / f"audio/{t['id']}.wav")
        _, source, kind, before = final(t, candidates)
        date = EPOCH + datetime.timedelta(seconds=t["date"])
        room, speech = levels(samples)
        clips.append(dict(id=t["id"], audio_path=f"audio/{t['id']}.wav", date=date.isoformat(timespec="seconds"),
                          seconds=round(len(samples) / 16_000, 1), room_db=room, speech_db=speech,
                          capture=capture(t, date), final=source or "none", **groups))
        references.append(dict(id=t["id"], text=reference))
        typed.append(dict(id=t["id"], text=said_typed(t)))
        context.append(dict(id=t["id"], heard=t.get("heard") or t["text"], field=kind or "text",
                            content=(t.get("field") or {}).get("content"), before=before or ""))
    if not clips:
        shutil.rmtree(folder)
        return clips
    lines(folder / "clips.jsonl", rooms(clips, usual([json.loads(line) for line in open(OUT / "real/clips.jsonl")])))
    lines(folder / "references.jsonl", references)
    lines(folder / "typed.jsonl", typed)
    lines(folder / "context.jsonl", context)
    shutil.copy(MIRROR / "app/vocabulary.json", folder / "vocabulary.json")
    return clips


def labelled():
    heard = labels()
    clips = heard_set("labelled", lambda t: (heard[t["id"]], {}) if t["id"] in heard else None)
    print(f"labelled: {len(clips)} dictations he labelled by ear")


def reading():
    """Each dictation since heldout/read.txt was written that's one of its `say | typed` lines (its words line up with
    that line's, said or typed, at least 0.6 of the way) against what that line should type."""
    path = HELDOUT / "read.txt"
    if not path.exists():
        return
    script = [line.split(" | ") for line in path.read_text().splitlines() if line.strip() and not line.startswith("#")]
    since = datetime.datetime.fromtimestamp(path.stat().st_mtime, datetime.timezone.utc)

    def picked(t):
        if EPOCH + datetime.timedelta(seconds=t["date"]) < since:
            return None
        said = words(t.get("heard") or t["text"])
        share, typed = max((max(difflib.SequenceMatcher(None, said, words(form), autojunk=False).ratio() for form in (say, typed)), typed)
                           for say, typed in script)
        return (typed, {}) if share >= 0.6 else None

    clips = heard_set("read", picked)
    print(f"read: {len(clips)} dictations of heldout/read.txt's {len(script)} lines")


if __name__ == "__main__" and sys.argv[1:2] == ["quieter"]:
    quieter(Path(sys.argv[2]), int(sys.argv[3]))
elif __name__ == "__main__":
    loud(*real())
    taps()
    labelled()
    reading()
