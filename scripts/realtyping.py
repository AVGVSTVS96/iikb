"""Real people's typing for scripts/eval, downloaded once into the folder given and written as three small files there.

taps.txt       source, split, person, the words they meant, and their taps: Google's TSI (16 people on a Pixel 6 Pro typing the
               MacKenzie phrases, each tap matched to its letter) and Vertanen & Kristensson's noisy phone typing (a
               Nexus 4 and an iPhone 4, Enron mobile emails), both CC BY 4.0. Each tap is in key pitches from the q key's
               center, so it lands on iikb's grid where it landed on theirs. A word's space tap follows a slash, measured
               from the space bar's center, across in halves of its width and down in key pitches, since the bars
               differ in width and a thumb aims at the bar.
typed.txt      split, person, the sentence they meant, and what they typed, capitals kept: Aalto's ITE typing dataset (CC BY 4.0),
               people on their own phones whose keyboards were seen to make no autocorrection or prediction.
autocorrect.txt  split, the text before the word, the word typed, what the phone's own autocorrect made it, and the word
               meant: the same dataset's autocorrections on iPhones and Androids.

Each person is in one split: dev to tune against, test to report.
"""

import csv, hashlib, io, json, os, re, sys, urllib.request, zipfile
from collections import defaultdict

folder = sys.argv[1]
TSI = "https://raw.githubusercontent.com/google-research-datasets/tap-typing-with-touch-sensing-images/main/"
VERTANEN = "https://zenodo.org/records/24225302/files/vertanen_noisy_typing_iui2023.zip"
ITE = "https://zenodo.org/records/12528163/files/ite_typing_dataset.zip"
SAMPLE = 3000
csv.field_size_limit(1 << 30)


class Remote(io.RawIOBase):
    """A file over HTTP range requests, so a few tables come out of ITE's 7.3 GB zip without the rest."""

    def __init__(self, url):
        self.url, self.pos = url, 0
        with urllib.request.urlopen(urllib.request.Request(url, method="HEAD")) as response:
            self.size = int(response.headers["Content-Length"])

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, offset, whence=0):
        self.pos = [offset, self.pos + offset, self.size + offset][whence]
        return self.pos

    def readinto(self, buffer):
        end = min(self.size, self.pos + len(buffer))
        if end <= self.pos:
            return 0
        request = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{end - 1}"})
        with urllib.request.urlopen(request) as response:
            data = response.read()
        buffer[: len(data)] = data
        self.pos += len(data)
        return len(data)


def fetch(name, url):
    path = os.path.join(folder, name)
    if not os.path.exists(path):
        urllib.request.urlretrieve(url, path + ".part")
        os.rename(path + ".part", path)
    return path


def rank(key):
    return hashlib.sha256(key.encode()).hexdigest()


def split(person):
    return "test" if int(rank(person), 16) % 2 else "dev"


def place(x, y, q, w, a):
    return f"{(x - q[0]) / (w[0] - q[0]):.3f},{(y - q[1]) / (a[1] - q[1]):.3f}"


def tsi():
    keys = json.load(open(fetch("tsi-keyboard.json", TSI + "keyboard_data.json")))["keys_info"]
    center = {k.lower(): (v["key_center_x"], v["key_center_y"]) for k, v in keys.items()}
    prompts = {}
    for row in csv.DictReader(open(fetch("tsi-prompts.csv", TSI + "prompt_data.csv"))):
        if row["prompt_type"] == "phrase":
            prompts[(row["participant_id"], row["task_id"], row["trial_id"])] = row["prompt"]
    first = defaultdict(dict)
    for row in csv.DictReader(open(fetch("tsi-touches.csv", TSI + "touch_data.csv"))):
        trial = (row["participant_id"], row["task_id"], row["trial_id"])
        if trial not in prompts:
            continue
        index, time = int(row["ref_char_index_in_prompt"]), int(row["timestamp_ms"])
        point = (float(row["first_frame_touch_x"]), float(row["first_frame_touch_y"]))
        if index not in first[trial] or time < first[trial][index][0]:
            first[trial][index] = (time, point)
    lines = []
    for trial, prompt in sorted(prompts.items()):
        text = prompt.lower().rstrip(".")
        words, taps, current = text.split(" "), [], []
        for index, character in enumerate(text):
            tap = first[trial].get(index)
            point = place(*tap[1], center["q"], center["w"], center["a"]) if tap else None
            if character == " ":
                space = keys["SPACE"]
                bar = (space["key_center_x"], space["key_center_y"], space["key_width"] / 2, center["a"][1] - center["q"][1])
                taps.append(" ".join(current) + (f"/{(tap[1][0] - bar[0]) / bar[2]:.3f},{(tap[1][1] - bar[1]) / bar[3]:.3f}" if tap else ""))
                current = []
            elif point:
                current.append(point)
        taps.append(" ".join(current))
        if all(re.fullmatch(r"[a-z]+", word) for word in words):
            lines.append(f"tsi\t{split('tsi/' + trial[0])}\t{trial[0]}\t{' '.join(words)}\t{'|'.join(taps)}")
    return lines


def vertanen():
    path = fetch("vertanen.zip", VERTANEN)
    archive = zipfile.ZipFile(path)
    names = archive.namelist()
    picked = [
        n
        for n in names
        if re.search(r"phone/(vt_exp2/test_word/.*_space|vt_exp1/test_word/.*_feed|eyesfree_exp1/test_word/.*)\.log$", n)
    ]
    lines = []
    for name in sorted(picked):
        experiment = name.split("/")[-3]
        board = next(n for n in names if f"phone/{experiment}/keyboard_" in n)
        center = {}
        for line in archive.read(board).decode().splitlines():
            parts = line.split(";")
            if len(parts) == 5 and not line.startswith("#"):
                center[parts[0]] = (float(parts[1]), float(parts[2]))
        person = experiment + "/" + name.split("/")[-1].split("_")[0]
        for block in archive.read(name).decode().split("\n\n"):
            reference = re.search(r"^REF: (.*)$", block, re.M)
            inputs = re.findall(r"^IN: (.*)$", block, re.M)
            if not reference or not inputs:
                continue
            words = reference.group(1).split()
            if len(words) != len(inputs) or not all(re.fullmatch(r"[a-z]+", w) for w in words):
                continue
            taps = []
            for line in inputs:
                points = [tap.split(";")[0].split(",") for tap in line.split("|") if tap]
                taps.append(" ".join(place(float(x), float(y), center["q"], center["w"], center["a"]) for x, y, *_ in points))
            lines.append(f"vertanen\t{split('vertanen/' + person)}\t{person}\t{' '.join(words)}\t{'|'.join(taps)}")
    return lines


def words(text):
    """Words as typed, capitals kept, since a capital is part of what someone typed."""
    return re.findall(r"[A-Za-z0-9']+", re.sub("[’‘`´ʼ]", "'", text))


def ite():
    archive = zipfile.ZipFile(io.BufferedReader(Remote(ITE), buffer_size=1 << 20))
    tables = {}
    for name, member in [
        ("participants", "processed2020/english/participants_labeled.csv"),
        ("sections", "processed2020/english/test_sections_labeled.csv"),
        ("sentences", "processed2020/english/sentences.csv"),
        ("autocorrect", "ITE_words/ac_words_en.csv"),
    ]:
        path = os.path.join(folder, f"ite-{name}.csv")
        if not os.path.exists(path):
            with archive.open(member) as source, open(path + ".part", "wb") as out:
                while chunk := source.read(1 << 22):
                    out.write(chunk)
            os.rename(path + ".part", path)
        tables[name] = path
    plain = set()
    for row in csv.DictReader(open(tables["participants"])):
        if row["DEVICE"] == "mobile" and float(row["AC"] or 0) == 0 and float(row["PREDICTION"] or 0) == 0:
            plain.add(row["PARTICIPANT_ID"].split(".")[0])
    sentence = {row["SENTENCE_ID"]: row["SENTENCE"] for row in csv.DictReader(open(tables["sentences"]))}
    owner, typed = {}, []
    for row in csv.DictReader(open(tables["sections"])):
        person = row["PARTICIPANT_ID"].split(".")[0]
        owner[row["TEST_SECTION_ID"]] = person
        meant, said = [w.lower() for w in words(sentence.get(row["SENTENCE_ID"], ""))], words(row["USER_INPUT"])
        if person in plain and meant and said and abs(len(meant) - len(said)) <= 1:
            typed.append((split(person), person, " ".join(meant), " ".join(said)))
    corrected = []
    for row in csv.DictReader(open(tables["autocorrect"])):
        person = owner.get(row["TEST_SECTION_ID"])
        context, word = row["CURRENT_INPUT"], row["TYPED_WORD"].lower()
        spelled = context[-len(word):]
        phone, meant = row["AC_WORD"].lower(), row["ORIGINAL_WORD"].lower()
        if not person or not re.fullmatch(r"[a-z']+", word) or not re.fullmatch(r"[a-z']+", meant):
            continue
        if not context.lower().endswith(word) or distance(word, meant) > 2:
            continue
        corrected.append((split(person), " ".join(words(context[: -len(word)])), spelled, phone, meant))
    sample = lambda rows: sorted(set(rows), key=lambda row: rank("\t".join(row)))
    keep = lambda rows: [r for s in ("dev", "test") for r in sample([r for r in rows if r[0] == s])[:SAMPLE]]
    return ["\t".join(r) for r in keep(typed)], ["\t".join(r) for r in keep(corrected)]


def distance(a, b):
    """Damerau-Levenshtein (adjacent swaps)."""
    d = [[i + j if not i * j else 0 for j in range(len(b) + 1)] for i in range(len(a) + 1)]
    for i in range(1, len(a) + 1):
        for j in range(1, len(b) + 1):
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] != b[j - 1]))
            if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
                d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
    return d[-1][-1]


os.makedirs(folder, exist_ok=True)
typed, corrected = ite()
for name, lines in [("taps.txt", tsi() + vertanen()), ("typed.txt", typed), ("autocorrect.txt", corrected)]:
    with open(os.path.join(folder, name), "w") as out:
        out.write("\n".join(lines) + "\n")
    print(f"{name}: {len(lines)} lines")
