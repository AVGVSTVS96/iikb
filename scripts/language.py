"""Builds the word counts behind a downloadable language's lexicon, and the sentences that score it.

Usage: scripts/language.py words <id> <build>    the word counts, word<TAB>count, to stdout (scripts/lexicon <id>)
       scripts/language.py license <id> <build>  the notices for its sources, to stdout
       scripts/language.py phrases <id> <build>  writes the eval phrases and the held-out sentences
       scripts/language.py report <id> <build>   how many held-out words the counts know, the top words, what's missing

Words: Android's keyboard word lists (AOSP LatinIME dictionaries, Apache-2.0) say which words a keyboard offers and
how each is capitalized. FineWeb-2 (ODC-BY) adds words the lists lack ("WhatsApp", "selfie") when it uses them at
least as often as the median listed word, unless the word is spam, is mostly another language's (English, or one of
the other lists'), or is a worse spelling of a word kept ("etre" for "être", "daß" for "dass").
Counts: FineWeb-2's first shard, each word counted at most ten times a page so keyword-stuffed pages don't skew it.
Leipzig's news sentences (CC BY) are the check on the web: a word the web uses far more than the news does (by more
than all but 5% of listed words) is spam, and its count is held to what the news supports. A listed word FineWeb-2
never saw gets the middle count of its frequency class.
Capitals: a word only capitalized in its list keeps its capital unless the news writes it lowercase mid-sentence at
least half the time; an added word is capitalized when the news lowercases it no more often than it slips on the
list's capitalized words (German nouns, names).
French and Italian elide ("l'ami", "dell'anno"): what the list writes before at least three words ("l'", "dell'") is
its own word, as the engine types the word after the apostrophe on its own; "aujourd'hui" stays whole. Words joined
by hyphens ("peut-être") count as their parts, since a lexicon's words are letters and apostrophes.
Sentences: Mozilla Common Voice's sentence collector (CC0), never part of the counts: 500 short ones typed by
scripts/eval, and up to 5,000 more held out to measure how many words the counts know.
The build dir keeps the counts; the FineWeb-2 shard (about 5 GB) is deleted once counted, and the news is read as it downloads.
"""

import bisect
import gzip
import math
import os
import random
import re
import struct
import sys
import unicodedata
import urllib.request
from collections import Counter
from concurrent.futures import ProcessPoolExecutor

AOSP = "https://android.googlesource.com/platform/packages/inputmethods/LatinIME/+/refs/heads/main/dictionaries"
FINEWEB = "https://huggingface.co/datasets/HuggingFaceFW/fineweb-2/resolve/main/data"
LEIPZIG = "https://downloads.wortschatz-leipzig.de/corpora"
VOICE = "https://raw.githubusercontent.com/common-voice/common-voice/main/server/data"
LANGUAGES = {
    "es": dict(aosp=["es"], fineweb="spa_Latn", news="spa_news_2024", voice=["es/sentence-collector.txt"]),
    "fr": dict(aosp=["fr"], fineweb="fra_Latn", news="fra_news_2024", voice=["fr/sentence-collector.txt"], elides=True),
    "de": dict(aosp=["de"], fineweb="deu_Latn", news="deu_news_2024", voice=["de/sentence-collector.txt"]),
    "pt": dict(aosp=["pt_BR", "pt_PT"], fineweb="por_Latn", news="por_news_2024", voice=["pt/sentence-collector.txt"]),
    "it": dict(aosp=["it"], fineweb="ita_Latn", news="ita_news_2024", voice=["it/sentence-collector.txt", "it/frasi.txt"], elides=True),
    "sv": dict(aosp=["sv"], fineweb="swe_Latn", news="swe_news_2023", voice=["sv-SE/sentence-collector.txt"]),
}
ROW_GROUPS = 600
PER_PAGE = 10
TOKEN = re.compile(r"[^\W\d_]+(?:['’-][^\W\d_]+)*['’]?")
BREAK = re.compile(r"[.!?…:;\n\"«»“”„()\[\]]|^\s*$")
EN_LEXICON = os.path.join(os.path.dirname(__file__), "../Packages/KeyboardModules/Sources/KeyboardEnglish/Resources/en.lexicon")


def fetch(url, path):
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        urllib.request.urlretrieve(url, path + ".part")
        os.rename(path + ".part", path)
    return path


def aosp(build, language):
    listed = {}
    for name in LANGUAGES[language]["aosp"]:
        path = os.path.join(build, f"aosp-{name}.gz")
        if not os.path.exists(path):
            import base64
            with urllib.request.urlopen(f"{AOSP}/{name}_wordlist.combined.gz?format=TEXT") as response:
                data = base64.b64decode(response.read())
            with open(path, "wb") as file:
                file.write(data)
        with gzip.open(path, "rt", encoding="utf-8") as file:
            for line in file:
                if not line.startswith(" word="):
                    continue
                fields = dict(field.split("=", 1) for field in line.strip().split(","))
                if "not_a_word" in fields:
                    continue
                word = unicodedata.normalize("NFC", fields["word"]).replace("’", "'")
                listed[word] = max(listed.get(word, 0), int(fields["f"]))
    return listed


def elided(build, language):
    """For a language that elides, what it elides ("l'", "qu'", "dell'"): the heads its word list writes before at least
    three words ("l'anno", "l'uso", ...), so "aujourd'hui" stays a word; otherwise None."""
    if LANGUAGES[language].get("elides"):
        heads = Counter(word.lower().partition("'")[0] + "'" for word in aosp(build, language) if "'" in word[:-1])
        return {head for head, n in heads.items() if n >= 3}


def tokens(text, heads):
    last = 0
    for match in TOKEN.finditer(text):
        initial = last == 0 or BREAK.search(text, last, match.start()) is not None
        last = match.end()
        word = match.group().replace("’", "'")
        head, _, tail = word.partition("'")
        if heads and tail and head.lower() + "'" in heads:
            yield head + "'", initial
            word, initial = tail, False
        yield word, initial
        if "-" in word:
            for part in word.split("-"):
                yield part, False


def count_group(args):
    path, group, heads = args
    import pyarrow.parquet as pq
    texts = pq.ParquetFile(path).read_row_group(group, columns=["text"]).column(0).to_pylist()
    every = Counter()
    for text in texts:
        page = Counter(word for word, _ in tokens(unicodedata.normalize("NFC", text), heads))
        every.update({word: min(n, PER_PAGE) for word, n in page.items()})
    return every


def corpus(build, language):
    path = os.path.join(build, "fineweb.tsv")
    if not os.path.exists(path):
        config = LANGUAGES[language]
        shard = fetch(f"{FINEWEB}/{config['fineweb']}/train/000_00000.parquet", os.path.join(build, "fineweb.parquet"))
        every = Counter()
        import pyarrow.parquet as pq
        groups = pq.ParquetFile(shard).metadata.num_row_groups
        heads = elided(build, language)
        jobs = [(shard, group, heads) for group in range(0, groups, groups // ROW_GROUPS)]
        with ProcessPoolExecutor(int(os.environ.get("JOBS", "6"))) as pool:
            for counted in pool.map(count_group, jobs, chunksize=4):
                every.update(counted)
        with open(path + ".part", "w") as file:
            for word, total in every.most_common():
                if total >= 3:
                    file.write(f"{word}\t{total}\n")
        os.rename(path + ".part", path)
        os.remove(shard)
    every = {}
    with open(path) as file:
        for line in file:
            word, total = line.rstrip("\n").split("\t")[:2]
            every[word] = int(total)
    return every


def news(build, language):
    """Each word's count in a year of the language's news (Leipzig, 1M sentences), all and mid-sentence."""
    path = os.path.join(build, "news.tsv")
    if not os.path.exists(path):
        import tarfile
        url = f"{LEIPZIG}/{LANGUAGES[language]['news']}_1M.tar.gz"
        every, mid, heads = Counter(), Counter(), elided(build, language)
        request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(request) as response, tarfile.open(fileobj=response, mode="r|gz") as archive:
            for member in archive:
                if member.name.endswith("-sentences.txt"):
                    for line in archive.extractfile(member):
                        text = unicodedata.normalize("NFC", line.decode("utf-8").partition("\t")[2])
                        for word, initial in tokens(text, heads):
                            every[word] += 1
                            mid[word] += not initial
                    break
        with open(path + ".part", "w") as file:
            file.writelines(f"{word}\t{n}\t{mid[word]}\n" for word, n in every.most_common())
        os.rename(path + ".part", path)
    every, mid = {}, {}
    with open(path, encoding="utf-8") as file:
        for line in file:
            word, n, inner = line.rstrip("\n").split("\t")
            every[word], mid[word] = int(n), int(inner)
    return every, mid


def english():
    """Each English word's probability, read from en.lexicon's trie (KeyboardCore's Lexicon.swift)."""
    data = open(EN_LEXICON, "rb").read()
    found = {}
    stack = [(0, "")]
    while stack:
        index, spelling = stack.pop()
        offset = 8 + index * 8
        letter, word, _, flags, first = struct.unpack_from("<BBBBI", data, offset)
        if index:
            spelling += chr(letter)
            if word:
                found[spelling] = math.exp(-word / 10)
        child = first
        while child:
            stack.append((child, spelling))
            child = 0 if data[8 + child * 8 + 3] & 1 else child + 1
    return found


def words(build, language):
    listed = aosp(build, language)
    web = corpus(build, language)
    press, press_mid = news(build, language)

    def seen(table, lower):
        return sum(table.get(form, 0) for form in {lower, lower.capitalize()})

    usage = Counter()
    for lower in {word.lower() for word in listed}:
        for ch in set(lower):
            usage[ch] += seen(web, lower)
    alphabet = {ch for ch, n in usage.items() if ch.isalpha() and n >= sum(web.values()) / 100000}

    def spelled(word):
        return (word[0].isalpha() and word in (word.lower(), word.lower().capitalize())
                and all(ch in alphabet or ch == "'" for ch in word.lower()))

    heads = elided(build, language) or set()
    forms = {}
    for word, f in listed.items():
        head, _, tail = word.lower().partition("'")
        if spelled(word) and not (tail and head + "'" in heads):
            forms.setdefault(word.lower(), []).append((word, f))

    web_total, press_total = sum(web.values()), sum(press.values())
    scale = press_total / web_total
    press_rate = sorted(seen(press, lower) / (seen(web, lower) * scale)
                        for lower in forms if seen(web, lower) * scale >= 10)
    floor = press_rate[len(press_rate) // 20]

    def count(lower):
        return min(seen(web, lower), (seen(press, lower) + 1) / scale / floor)

    def lowercase_share(lower):
        mid = seen(press_mid, lower)
        return press_mid.get(lower, 0) / mid if mid >= 10 else None

    capital_only = sorted(share for lower, spellings in forms.items()
                          if all(w[0].isupper() for w, _ in spellings) and (share := lowercase_share(lower)) is not None)
    slips = capital_only[len(capital_only) * 49 // 50]

    def capitalized(lower, listed_cases):
        share = lowercase_share(lower)
        if listed_cases:
            return listed_cases == {True} and (share is None or share < 0.5)
        return share is not None and share <= slips

    by_class = {}
    for lower, spellings in forms.items():
        if seen(web, lower):
            by_class.setdefault(max(f for _, f in spellings), []).append(count(lower))
    middle = {f: sorted(counts)[len(counts) // 2] for f, counts in by_class.items()}

    counts = {}
    for lower, spellings in forms.items():
        f = max(f for _, f in spellings)
        counts[lower] = (count(lower) or middle[min(middle, key=lambda g: (abs(g - f), -g))],
                         capitalized(lower, {w[0].isupper() for w, _ in spellings}))

    def key(word):
        plain = "".join(ch for ch in unicodedata.normalize("NFD", word) if not unicodedata.combining(ch))
        return plain.rstrip("'").replace("ß", "ss").replace("œ", "oe")

    variants = {}
    for lower in forms:
        variants.setdefault(key(lower), []).append(lower)

    def ranks(table):
        order = sorted(table.items(), key=lambda item: -item[1])
        found = {}
        for rank, (word, _) in enumerate(order):
            found.setdefault(word.lower(), rank)
        return found

    en = english()
    elsewhere = {}
    for other in LANGUAGES:
        if other != language:
            for word, rank in ranks(aosp(build, other)).items():
                elsewhere[word] = min(elsewhere.get(word, rank), rank)
    ascending = sorted(n for n, _ in counts.values())
    threshold = sorted(seen(web, lower) for lower in forms)[len(forms) // 2]
    added = 0
    for word in web:
        lower = word.lower()
        if lower in counts or len(lower) < 2 or not spelled(word) or seen(web, lower) < threshold:
            continue
        elision = lower in heads
        if word[-1] == "'" and not (elision or heads and len(lower) > 2):
            continue
        if not elision and seen(press, lower) + press.get(lower.upper(), 0) < seen(web, lower) * scale * floor:
            continue
        form = lower.capitalize() if capitalized(lower, set()) else lower
        if any(press.get(form, 0) * 10 < seen(press, other) for other in variants.get(key(lower), [])):
            continue
        if elsewhere.get(lower, len(ascending)) * 10 < len(ascending) - bisect.bisect_right(ascending, seen(web, lower)):
            continue
        if seen(web, lower) / web_total * 2 < en.get(lower, 0):
            continue
        counts[lower] = (seen(web, lower), capitalized(lower, set()))
        variants.setdefault(key(lower), []).append(lower)
        added += 1

    for lower, (n, capital) in sorted(counts.items(), key=lambda item: -item[1][0]):
        print(f"{lower.capitalize() if capital else lower}\t{round(n)}")
    print(f"{language}: {len(counts)} words ({added} added), letters {''.join(sorted(alphabet))}, a word the web uses "
          f"{1 / floor:.0f}x more than the news is spam; added from {threshold} uses; capitals kept up to {slips:.1%} lowercase", file=sys.stderr)


def license(language):
    config = LANGUAGES[language]
    lists = ", ".join(f"{AOSP}/{name}_wordlist.combined.gz" for name in config["aosp"])
    print(f"""{language}.lexicon is built by scripts/lexicon {language} (scripts/language.py) from three sources. iikb's own code is
MIT (see LICENSE at the repository root); the word list and counts inside {language}.lexicon carry these notices.

Words: Android's keyboard word list (AOSP LatinIME), {lists}
Copyright (C) The Android Open Source Project, licensed under the Apache License, Version 2.0,
https://www.apache.org/licenses/LICENSE-2.0. Its words and their capitals are used, and its frequency classes for
words the text below never has.

Counts and newer words: FineWeb-2 by Hugging Face, {config["fineweb"]}, the first of its files,
https://huggingface.co/datasets/HuggingFaceFW/fineweb-2, under the Open Data Commons Attribution License (ODC-By) v1.0,
https://opendatacommons.org/licenses/by/1-0/, and subject to Common Crawl's Terms of Use,
https://commoncrawl.org/terms-of-use. {language}.lexicon contains counts derived from it.

Capitals, and a check that keeps words of web spam out: Leipzig Corpora Collection, {config["news"]}_1M,
https://wortschatz.uni-leipzig.de/en/download, © Universität Leipzig / Sächsische Akademie der Wissenschaften / InfAI,
under Creative Commons Attribution (CC BY), https://creativecommons.org/licenses/by/4.0/. {language}.lexicon contains
counts derived from it.""")


def sentences(build, language):
    lines = []
    for name in LANGUAGES[language]["voice"]:
        path = fetch(f"{VOICE}/{name}", os.path.join(build, "voice-" + name.replace("/", "-")))
        with open(path, encoding="utf-8") as file:
            lines += [unicodedata.normalize("NFC", line.strip()).replace("’", "'") for line in file if line.strip()]
    return sorted(set(lines))


def phrases(build, language, out):
    lines = sentences(build, language)
    random.Random(language).shuffle(lines)
    word = re.compile(r"[^\W\d_]+(?:'[^\W\d_]+)*")
    typed = []
    for line in lines:
        text = line.strip().rstrip(".!?").strip()
        if 3 <= len(text.split()) <= 9 and all(word.fullmatch(w) for w in text.split()):
            typed.append(text)
        if len(typed) == 500:
            break
    with open(out, "w") as file:
        file.write("\n".join(typed) + "\n")
    held = [line for line in lines if line.strip().rstrip(".!?").strip() not in set(typed)][:5000]
    with open(os.path.join(build, "heldout.txt"), "w") as file:
        file.write("\n".join(held) + "\n")


def report(build, language, words_path):
    known = {}
    with open(words_path) as file:
        for line in file:
            word, count = line.rstrip("\n").split("\t")
            known[word.lower()] = (word, float(count))
    held = open(os.path.join(build, "heldout.txt"), encoding="utf-8").read()
    total, hits, missing, wrong_case = 0, 0, Counter(), Counter()
    heads = elided(build, language)
    for line in held.splitlines():
        for word, initial in tokens(line, heads):
            if "-" in word:
                continue
            total += 1
            entry = known.get(word.lower())
            if entry:
                hits += 1
                if not initial and word != entry[0] and word[0].isupper() != entry[0][0].isupper() and word == word.lower():
                    wrong_case[f"{word}→{entry[0]}"] += 1
            else:
                missing[word] += 1
    top = sorted(known.values(), key=lambda e: -e[1])[:40]
    print(f"{language}: {len(known)} words; held-out tokens {total}, known {hits / total:.2%}")
    print("top:", " ".join(w for w, _ in top))
    print("missing:", " ".join(f"{w}×{n}" for w, n in missing.most_common(60)))
    print("lowercase in text, capitalized in lexicon:", " ".join(f"{w}×{n}" for w, n in wrong_case.most_common(25)))


if __name__ == "__main__":
    command, language, build = sys.argv[1:4]
    if language not in LANGUAGES:
        sys.exit(f"unknown language {language}; one of {' '.join(LANGUAGES)}")
    if command == "words":
        words(build, language)
    elif command == "license":
        license(language)
    elif command == "phrases":
        phrases(build, language, sys.argv[4])
    elif command == "report":
        report(build, language, sys.argv[4])
