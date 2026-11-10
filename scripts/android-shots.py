#!/usr/bin/env python3
"""Runs on the Mac, inside the emulator's lock (scripts/android-shots): every screen of iikb on the Android emulator,
light and dark, under the names scripts/parity gives iOS's, with the same steps as UITests/ParityShots and the same
made-up data, into <work>/out/<screen>-<appearance>.png. The app's files, settings and microphone permission go back
as they were at the end, so other agents' runs find the emulator as they left it.

python3 android-shots.py <work> [section…]   (<work>/demo holds shots/demo/make.py's files)
"""
import html
import json
import os
import re
import struct
import subprocess
import sys
import threading
import time
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ADB = os.path.expanduser("~/Library/Android/sdk/platform-tools/adb")
PACKAGE = "com.shahidy.iikb"
IME = f"{PACKAGE}/.keyboard.IikbService"
DATA = f"/data/data/{PACKAGE}"
STAGE = "/data/local/tmp/iikb-shots"
FOUNDATION = 978307200
PROMPT = "Type something with iikb"
SECTIONS = ["layers", "typing", "held", "swipe", "menu", "emoji", "gif", "clipboard", "transcripts", "dictation",
            "app", "chats", "hint", "replacement"]

# iOS's apps in the made-up data, as the Android apps that do the same job (AppNames shows a missing one by its
# package's last part, so each reads as its app).
APPS = {
    "com.apple.MobileSMS": "com.google.android.apps.messaging", "net.whatsapp.WhatsApp": "com.whatsapp",
    "com.tinyspeck.chatlyio": "com.Slack", "com.anthropic.claude": "com.anthropic.claude",
    "com.google.Gmail": "com.google.android.gm", "com.apple.mobilenotes": "com.google.android.keep",
    "com.atebits.Tweetie2": "com.x", "com.apple.mobilesafari": "com.android.chrome",
    "com.apple.reminders": "com.google.android.apps.tasks",
}

work = sys.argv[1] if len(sys.argv) > 1 else "."
out = os.path.join(work, "out")
demo = os.path.join(work, "demo")
wanted = sys.argv[2:] or SECTIONS
appearance = "light"


def adb(*args):
    return subprocess.run([ADB, *args], capture_output=True, stdin=subprocess.DEVNULL).stdout


def sh(command):
    return adb("shell", command).decode(errors="replace")


def tap(x, y, settle=0.35):
    sh(f"input tap {int(x)} {int(y)}")
    time.sleep(settle)


def touch(action, x, y):
    sh(f"input motionevent {action} {int(x)} {int(y)}")


def swipe(x0, y0, x1, y1, ms=400, settle=1.0):
    sh(f"input swipe {int(x0)} {int(y0)} {int(x1)} {int(y1)} {ms}")
    time.sleep(settle)


def shot(name, settle=1.2, screen=None):
    time.sleep(settle)
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, f"{name}-{appearance}.png"), "wb") as file:
        file.write(screen.png() if screen else adb("exec-out", "screencap", "-p"))
    print("shot", name, appearance, flush=True)


def caret_shot(name, nudge, tries=4):
    """A shot of Home's field with its caret drawn: the caret blinks, and a screen takes longer to read than it's off,
    so each try first `nudge`s it, which restarts its blink lit, and keeps the shot whose field has the caret's
    accent-blue pixels, which nothing else there has."""
    def blue(screen):
        rows = range(round(screen.height * 0.13), round(screen.height * 0.3), 2)
        return sum(1 for y in rows for x in range(0, screen.width, 2)
                   if (lambda p: p[2] > 180 and p[2] - p[0] > 90)(screen.pixel(x, y)))
    for attempt in range(tries):
        nudge()
        screen = Screen()
        if blue(screen) > 8 or attempt == tries - 1:
            return shot(name, 0, screen)


class Screen:
    """The screen's pixels, from screencap's raw RGBA after its 16-byte header."""

    def __init__(self):
        self.data = adb("exec-out", "screencap")
        self.width, self.height = struct.unpack("<II", self.data[:8])

    def png(self):
        stride = self.width * 4
        rows = b"".join(b"\0" + self.data[16 + y * stride:16 + (y + 1) * stride] for y in range(self.height))
        chunk = lambda kind, body: struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))
        header = struct.pack(">IIBBBBB", self.width, self.height, 8, 6, 0, 0, 0)
        return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b"")

    def pixel(self, x, y):
        at = 16 + (y * self.width + x) * 4
        return self.data[at:at + 3]

    def runs(self, cells, threshold=10, gap=6):
        """Stretches of `cells` (index, pixel, background) unlike the background, joined across gaps of a few pixels
        (a glyph's antialiased edge can match the background)."""
        found = []
        for index, pixel, background in cells:
            if sum(abs(a - b) for a, b in zip(pixel, background)) > threshold:
                if found and index - found[-1][1] <= gap:
                    found[-1][1] = index
                else:
                    found.append([index, index])
        return found

    def signature(self):
        """The screen below the status bar, to tell whether a scroll moved anything."""
        top = 16 + 160 * self.width * 4
        return hash(self.data[top:])


class Keys:
    """Where each key is, read off the screen: the rows from runs of key down two columns at the keys' left, then each
    row's keys from runs across it, near its top, above the glyphs. Nothing is measured once and kept, so a change to
    the keys' geometry moves the taps with it."""

    LETTERS = ["qwertyuiop", "asdfghjkl"]

    def __init__(self):
        screen = Screen()
        self.width, self.height = screen.width, screen.height
        edge = 3
        rows = []
        for column in (round(self.width * 0.057), round(self.width * 0.106)):
            cells = [(y, screen.pixel(column, y), screen.pixel(edge, y)) for y in range(self.height // 2, self.height)]
            rows += [run for run in screen.runs(cells) if 70 < run[1] - run[0] < 200]
        tops = []
        for top, bottom in sorted(rows):
            if not tops or top - tops[-1][0] > 40:
                tops.append((top, bottom))
        if len(tops) < 4:
            raise RuntimeError(f"found {len(tops)} rows of keys, not 4")
        self.rows = []
        for top, bottom in tops[-4:]:
            y = top + 14
            cells = [(x, screen.pixel(x, y), screen.pixel(edge, y)) for x in range(self.width)]
            keys = [((a + b) // 2, (top + bottom) // 2, b - a) for a, b in screen.runs(cells) if b - a > 40]
            self.rows.append(keys)
        self.top = tops[-4][0]
        self.pitch = tops[-3][0] - tops[-4][0]
        self.at = {}
        for row, letters in zip(self.rows, self.LETTERS):
            if len(row) == len(letters):
                self.at.update({letter: key[:2] for letter, key in zip(letters, row)})
        third, bottom = self.rows[2], self.rows[3]
        if len(third) == 9:
            self.at.update({"shift": third[0][:2], "delete": third[-1][:2]})
            self.at.update({letter: key[:2] for letter, key in zip("zxcvbnm", third[1:-1])})
        if len(bottom) == 4:
            self.at.update({"numbers": bottom[0][:2], "emoji": bottom[1][:2], "space": bottom[2][:2],
                            "return": bottom[3][:2]})
            self.space_width = bottom[2][2]
        missing = [key for key in "qwertyuiopasdfghjklzxcvbnm" if key not in self.at] + [
            key for key in ("shift", "delete", "numbers", "emoji", "space", "return") if key not in self.at]
        if missing:
            raise RuntimeError(f"keys not found: {missing}; rows {[len(row) for row in self.rows]}")
        # The bar sits a row's pitch above the letters, its More at the left edge and its mic at the right.
        self.bar = self.top - self.pitch * 0.55
        self.more = (self.at["q"][0], self.bar)
        self.mic = (self.at["p"][0], self.bar)

    def __getitem__(self, key):
        return self.at[key]

    def type(self, text, settle=0.8):
        for character in text:
            if character == " ":
                tap(*self["space"], 0.12)
            elif character.isupper():
                tap(*self["shift"], 0.12)
                tap(*self[character.lower()], 0.12)
            else:
                tap(*self[character], 0.12)
        time.sleep(settle)


def nodes():
    """Every node on screen, the keyboard's own window among them, as (text, description, (x0, y0, x1, y1))."""
    dump = adb("exec-out", "uiautomator", "dump", "--windows", "/dev/tty").decode(errors="replace")
    found = []
    for node in re.finditer(r"<node ([^>]*?)/?>", dump):
        attributes = dict(re.findall(r'([\w-]+)="([^"]*)"', node.group(1)))
        bounds = re.match(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]", attributes.get("bounds", ""))
        if bounds:
            found.append((html.unescape(attributes.get("text", "")), html.unescape(attributes.get("content-desc", "")),
                          tuple(int(n) for n in bounds.groups())))
    return found


def find(match, timeout=6.0, last=False, top=False):
    """The bounds of the first node (the lowest, `last`, or the highest, `top`) whose text is `match`, or passes it when
    it's a function."""
    test = match if callable(match) else (lambda text: text == match)
    end = time.time() + timeout
    while True:
        hits = [bounds for text, _, bounds in nodes() if text and test(text)]
        if hits:
            if last or top:
                return (max if last else min)(hits, key=lambda b: b[1])
            return hits[0]
        if time.time() > end:
            raise RuntimeError(f"nothing on screen reads {match if not callable(match) else 'as asked'}")
        time.sleep(0.5)


def center(bounds):
    return (bounds[0] + bounds[2]) / 2, (bounds[1] + bounds[3]) / 2


def tap_text(match, settle=1.5, last=False, top=False):
    tap(*center(find(match, last=last, top=top)), settle)


def tap_described(description, settle=1.5):
    """Taps the node a screen reader names `description`, for a button that's only a glyph."""
    end = time.time() + 6
    while True:
        hits = [bounds for _, desc, bounds in nodes() if desc == description]
        if hits:
            return tap(*center(hits[0]), settle)
        if time.time() > end:
            raise RuntimeError(f"nothing on screen is described as {description}")
        time.sleep(0.5)


def computer(section=None):
    """Stats on the Mac, picked from the device menu, at `section`."""
    tab("Stats")
    tap_described("Phone")
    tap_text("Mac")
    if section:
        tap_text(section)


# The made-up data, as Android's iikb keeps it: dates since 1970, Android's packages, the touch model inside the
# keyboard's memory, and the clipboard's history without iOS's store around it.
def staged():
    def lines(name):
        with open(os.path.join(demo, name)) as file:
            return [json.loads(line) for line in file if line.strip()]

    def write(name, text):
        with open(os.path.join(work, "stage", name), "w") as file:
            file.write(text)

    os.makedirs(os.path.join(work, "stage"), exist_ok=True)
    transcripts = []
    for said in lines("transcripts.jsonl"):
        if said.get("mic") == "iPhone Microphone":
            said["mic"] = "Phone Microphone"
        said["date"] = round(said["date"] + FOUNDATION, 3)
        if "app" in said:
            said["app"] = APPS.get(said["app"], said["app"])
        transcripts.append(said)
    write("transcripts.jsonl", "".join(json.dumps(t, separators=(",", ":")) + "\n" for t in transcripts))
    hours = lines("typing.jsonl")
    for hour in hours:
        hour["app"] = APPS.get(hour["app"], hour["app"])
    write("typing.jsonl", "".join(json.dumps(h, separators=(",", ":")) + "\n" for h in hours))
    with open(os.path.join(demo, "touches.json")) as file:
        touches = json.load(file)
    memory = {"counts": {}, "kept": [], "following": {}, "total": 0, "spacesAfterSpace": 0, "keysAfterSpace": 0,
              "touches": touches}
    write("typing-memory.json", json.dumps(memory, separators=(",", ":")))
    with open(os.path.join(demo, "clipboard.json")) as file:
        write("clipboard.json", json.dumps(json.load(file)["history"], separators=(",", ":")))
    # A Mac, as Stats keeps one you added: the list, and Keystroke's file as it last answered (scripts/sim fill's).
    write("computers.json", json.dumps([{"name": "Mac", "url": "http://mac.local:2593", "token": "t"}]))
    with open(os.path.join(demo, "mac.json")) as file:
        write("Mac.json", file.read())
    # The names the keyboard keeps for the apps it opens in (AppNames), which the emulator doesn't have; Apple's own are
    # stood in for by Android's (Keep for Notes), named by the emulator or by their package.
    with open(os.path.join(demo, "app-names.json")) as file:
        names = json.load(file)
    write("app-names.json", json.dumps({APPS[app]: name for app, name in names.items() if app in APPS and not app.startswith("com.apple.")}))
    adb("shell", f"rm -rf {STAGE} && mkdir -p {STAGE}/recordings")
    adb("push", os.path.join(work, "stage") + "/.", STAGE)
    adb("push", os.path.join(demo, "recordings") + "/.", f"{STAGE}/recordings")


def preferences(values):
    lines = ["<?xml version='1.0' encoding='utf-8' standalone='yes' ?>", "<map>"]
    for name, value in values.items():
        if isinstance(value, bool):
            lines.append(f'    <boolean name="{name}" value="{str(value).lower()}" />')
        elif isinstance(value, int):
            lines.append(f'    <long name="{name}" value="{value}" />')
        else:
            lines.append(f'    <string name="{name}">{html.escape(value, quote=True)}</string>')
    return "\n".join(lines + ["</map>", ""])


def seed(**settings):
    """iikb stopped and set as it first comes, with the made-up data and `settings` over the defaults. The clipboard's
    last-seen time is far ahead, so nothing another agent copied joins the made-up history."""
    sh(f"am force-stop {PACKAGE}")
    values = {"voiceModel": "v3", "clipboard.seen": 1 << 62, "klipyCustomer": klipy, "extensions": "[]",
              "sources": "[]", **settings}
    with open(os.path.join(work, "settings.xml"), "w") as file:
        file.write(preferences(values))
    adb("push", os.path.join(work, "settings.xml"), f"{STAGE}/settings.xml")
    owner = sh(f"stat -c %u:%g {DATA}").strip()
    sh(
        f"rm -f {DATA}/files/emoji-history.json {DATA}/files/*.next && "
        f"cp {STAGE}/transcripts.jsonl {STAGE}/typing.jsonl {STAGE}/typing-memory.json {STAGE}/clipboard.json {STAGE}/computers.json {DATA}/files/ && "
        f"rm -rf {DATA}/cache/computers && mkdir -p {DATA}/cache/computers && cp {STAGE}/Mac.json {DATA}/cache/computers/ && "
        f"cp {STAGE}/app-names.json {DATA}/cache/ && rm -rf {DATA}/cache/site-icons && "
        f"rm -rf {DATA}/no_backup/recordings && mkdir -p {DATA}/no_backup/recordings && "
        f"cp {STAGE}/recordings/*.wav {DATA}/no_backup/recordings/ && "
        f"cp {STAGE}/settings.xml {DATA}/shared_prefs/settings.xml && "
        f"chown -R {owner} {DATA}/files {DATA}/shared_prefs {DATA}/no_backup/recordings {DATA}/cache/computers {DATA}/cache/app-names.json && restorecon -R {DATA}"
    )


def launch(page=None, settle=2.5):
    sh(f"am force-stop {PACKAGE}")
    sh(f"ime set {IME}")
    sh("input keyevent KEYCODE_WAKEUP")
    extra = f" --es page {page}" if page else ""
    sh(f"am start -W -n {PACKAGE}/.app.MainActivity{extra}")
    time.sleep(settle)


def keyboard(text=""):
    """Home's field focused on iikb, `text` typed into it."""
    launch()
    tap_text(PROMPT, 2.0)
    keys = Keys()
    if text:
        keys.type(text)
    return keys


def layers():
    seed()
    keys = keyboard("Coffee at ")
    shot("keyboard-letters", 2)
    tap(*keys["shift"])
    shot("keyboard-shift")
    tap(*keys["shift"], 0.08)
    tap(*keys["shift"])
    shot("keyboard-caps")
    tap(*keys["shift"])
    tap(*keys["numbers"])
    shot("keyboard-numbers")
    tap(*keys["shift"])
    shot("keyboard-symbols")


def typing():
    seed(autoCorrection=True)
    keys = keyboard("Coffee at th")
    shot("keyboard-typing")
    tap(*keys["delete"], 0.15)
    tap(*keys["delete"], 0.15)
    keys.type("teh")
    shot("keyboard-autocorrect")
    tap(*keys["space"])
    shot("keyboard-autocorrected")


def held():
    """The pop-ups that last only while a finger is down, each shot as far into the hold as iOS's. The 123 menu's hold
    ends in a cancel, since lifting on it picks a layout, which iikb keeps."""
    seed()
    keys = keyboard("Coffee at ")
    touch("DOWN", *keys["g"])
    shot("keyboard-callout", 3)
    touch("UP", *keys["g"])
    time.sleep(0.6)
    touch("DOWN", *keys["e"])
    shot("keyboard-accents", 1.2)
    touch("UP", *keys["e"])
    time.sleep(0.6)
    x, y = keys["space"]
    touch("DOWN", x, y)
    time.sleep(1.2)
    left = x - keys.space_width * 0.4
    for step in range(1, 9):
        touch("MOVE", x + (left - x) * step / 8, y)
        time.sleep(0.05)
    time.sleep(0.8)

    def nudge():
        """The caret moved off the start and back, as the trackpad moves it a character a step."""
        touch("MOVE", left + keys.space_width * 0.3, y)
        time.sleep(0.15)
        touch("MOVE", left, y)
        time.sleep(0.1)

    caret_shot("keyboard-trackpad", nudge)
    touch("UP", left, y)
    time.sleep(0.6)
    x, y = keys["numbers"]
    touch("DOWN", x, y)
    time.sleep(1.5)
    above = keys.top + keys.pitch * 3 - 85 * 2.625
    for step in range(1, 9):
        touch("MOVE", x, y + (above - y) * step / 8)
        time.sleep(0.05)
    shot("keyboard-numbers-menu", 0.8)
    touch("CANCEL", x, above)
    time.sleep(0.6)


def swiped():
    """A word swiped slowly from t to o, shot mid-swipe with its trail, then the word it typed."""
    seed()
    keys = keyboard("Coffee at ")
    (x0, y0), (x1, y1) = keys["t"], keys["o"]
    touch("DOWN", x0, y0)
    steps = 24
    for step in range(1, steps + 1):
        touch("MOVE", x0 + (x1 - x0) * step / steps, y0)
        time.sleep(0.04)
        if step == steps * 2 // 3:
            shot("keyboard-swipe", 0)
    time.sleep(0.2)
    touch("UP", x1, y1)
    shot("keyboard-swiped", 1.2)


def menu():
    """The menu from its edits down to Theme and Stop Animation, a screenful at a time."""
    seed()
    keys = keyboard("Coffee at ")
    tap(*keys.more)
    find("Clipboard")
    shot("menu", 2)
    for page in range(2, 7):
        stop = [b for text, _, b in nodes() if text == "Squeeze"]
        if stop and stop[0][3] < keys.height - 200:
            break
        x = keys.width * 0.8
        y = keys.height - 300
        swipe(x, y, x, y - keys.height * 0.35, 900, 0.4)
        shot(f"menu-{page}", 1.5)


SEARCH = {"gif": "Search KLIPY", "clipboard": "Search clipboard", "transcripts": "Search transcripts"}
SHELF = {"gif": "GIFs", "clipboard": "Clipboard", "transcripts": "Transcripts"}


def open_panel(panel):
    keys = keyboard("Coffee at ")
    if panel == "emoji":
        tap(*keys["emoji"], 1.5)
    else:
        tap(*keys.more)
        tap_text(SHELF[panel], 2)
    return keys


def panel(name, search):
    """A panel opened from the menu (emoji from its key), then with the keys up, then searched, and in a launch of its
    own, with an item held."""
    seed()
    open_panel(name)
    shot(name, 5 if name == "gif" else 2)
    if name in SEARCH:
        tap_text(SEARCH[name], 1.5)
        shot(f"{name}-keys")
    keys = Keys()
    keys.type(search)
    shot(f"{name}-search", 5 if name == "gif" else 2)

    seed()
    keys = open_panel(name)
    if name == "emoji":
        # The first row is the recents, 👍 third, as on iOS; it sits on the keys' canvas, out of the node tree.
        x, y = thumbs(keys)
        touch("DOWN", x, y)
        shot("emoji-hold", 2.5)
        touch("CANCEL", x, y)
        return
    if name == "gif":
        time.sleep(4)
        item = next(b for _, description, b in nodes()
                    if description not in ("", "Back", "Switch input method") and b[1] > keys.height * 0.4)
    elif name == "clipboard":
        item = find(lambda text: "wikipedia ·" in text)
    else:
        item = find(lambda text: text.startswith("On my way, grabbing coffee"))
    x, y = center(item)
    touch("DOWN", x, y)
    time.sleep(1.2)
    touch("UP", x, y)
    shot(f"{name}-hold", 1.5)


def thumbs(keys):
    """The emoji panel's third cell in its first row, 👍 as on iOS. The panel is drawn on the keys' canvas, out of the
    node tree, so its top is where the keyboard's color ends going up its left edge, and its first row the first line
    below that crossing six or more emoji."""
    screen = Screen()
    edge = 3
    board = screen.pixel(edge, keys.top)
    top = keys.top
    while top > 0 and sum(abs(a - b) for a, b in zip(screen.pixel(edge, top - 1), board)) <= 6:
        top -= 1
    for y in range(top + 10, keys.top):
        cells = [(x, screen.pixel(x, y), board) for x in range(keys.width)]
        row = [run for run in screen.runs(cells, threshold=60, gap=4) if 20 < run[1] - run[0] < 140]
        if len(row) >= 6:
            middle = y + 30
            cells = [(x, screen.pixel(x, middle), board) for x in range(keys.width)]
            row = [run for run in screen.runs(cells, threshold=60, gap=4) if 20 < run[1] - run[0] < 140]
            return (row[2][0] + row[2][1]) / 2, middle
    raise RuntimeError("no row of emoji found")


def dictation():
    """The bar's mic recording, then writing: the emulator has no sound, so the second recording is kept under a
    second, which iikb writes rather than calling silent."""
    seed()
    keys = keyboard()
    tap(*keys.mic, 0)
    shot("dictation-listening", 2.5)
    tap(*keys.mic, 4)
    tap(*keys.mic, 0.6)
    tap(*keys.mic, 0)
    shot("dictation-writing", 0.4)
    time.sleep(3)


def scrolled(name, swipe_from=0.75, swipe_to=0.3):
    """Scrolls the page until a swipe moves nothing, then shoots it."""
    screen = Screen()
    for _ in range(30):
        before = screen.signature()
        swipe(screen.width / 2, screen.height * swipe_from, screen.width / 2, screen.height * swipe_to, 120, 1.2)
        screen = Screen()
        if screen.signature() == before:
            break
    shot(name, 0.5)


def tab(name):
    tap_text(name, 2, last=True)


PAGES_ALL = [
    ("home", lambda: None),
    ("typing", lambda: tap_text(PROMPT, 2)),
    ("settings", lambda: tab("Settings")),
    ("appearance", "appearance"),
    ("typing-settings", "typing"),
    ("feedback", "feedback"),
    ("voice", lambda: (tab("Settings"), tap_text("Voice"))),
    ("writing", "writing"),
    ("dictionary", "dictionary"),
    ("extensions", "extensions"),
    ("transcripts", lambda: tab("Transcripts")),
    ("transcript", lambda: (tab("Transcripts"), tap_text(lambda t: t.startswith("On my way, grabbing coffee")))),
    ("clipboard", lambda: tab("Clipboard")),
    ("overview", lambda: tab("Stats")),
    ("stats", lambda: (tab("Stats"), tap_text("Typing"))),
    ("stats-dictation", lambda: (tab("Stats"), tap_text("Dictation"))),
    ("overview-mac", lambda: computer()),
    ("stats-mac", lambda: computer("Typing")),
    ("stats-mac-dictation", lambda: computer("Dictation")),
    ("add-computer", lambda: (tab("Stats"), tap_text("Typing"), tap_described("Phone"), tap_text("Add Computer…"))),
    ("taps", lambda: (tab("Stats"), tap_text("Taps"))),
    ("taps-aim", lambda: (tab("Stats"), tap_text("Taps"), tap_text("Aim"), taps_key("e"))),
    ("sources", "sources"),
    ("access", "access"),
    ("privacy", "privacy"),
    ("changelog", "changelog"),
    ("about", "about"),
]
# Android's alone, shot at their top only.
ANDROID_PAGES = [
    # The pill, over the Links section's header in All.
    ("clipboard-links", lambda: (tab("Clipboard"), tap_text("Links", top=True))),
    ("sources-edit", lambda: tap_text("Add Source")),
    ("writing-eachapp", lambda: each_app()),
]
ANDROID_PAGE_ARGUMENTS = {"sources-edit": "sources", "writing-eachapp": "writing"}
# PAGES narrows the app's pages, by name.
PAGES = [p for p in PAGES_ALL if not os.environ.get("PAGES") or p[0] in os.environ["PAGES"].split()]
ANDROID_PAGES = [p for p in ANDROID_PAGES if not os.environ.get("PAGES") or p[0] in os.environ["PAGES"].split()]


def taps_key(letter):
    """Picks a key of the top row on Taps' map: the wide node under the mode pills, a keyboard of four rows, the top
    row ten keys across."""
    pill = find("Aim")
    width = int(sh("wm size").split()[-1].split("x")[0])
    x0, y0, x1, y1 = min((b for text, _, b in nodes() if b[1] >= pill[3] and b[2] - b[0] > width * 0.8),
                         key=lambda b: b[1])
    tap(x0 + (x1 - x0) * ("qwertyuiop".index(letter) + 0.5) / 10, y0 + (y1 - y0) / 8, 1.5)


def each_app():
    """Writing Style scrolled to Style in Each App, which lists the apps you've dictated into."""
    for _ in range(8):
        hits = [b for text, _, b in nodes() if text == "Style in Each App"]
        if hits:
            swipe(540, hits[0][1], 540, 450, 900, 1.2)
            return
        swipe(540, 1800, 540, 1000, 600, 1.0)
    raise RuntimeError("Writing Style has no Style in Each App")


def app():
    failed = []
    for name, opener in PAGES + ANDROID_PAGES:
        try:
            page(name, opener)
        except Exception as error:
            failed.append(f"app-{name}: {error}")
    if failed:
        raise RuntimeError("; ".join(failed))


def page(name, opener):
    """One of the app's pages, opened by its page argument or by taps, at its top and, for iOS's, at its end."""
    seed()
    launch(opener if isinstance(opener, str) else ANDROID_PAGE_ARGUMENTS.get(name))
    if callable(opener):
        opener()
    shot(f"app-{name}", 1.5)
    if name == "typing":
        scrolled("app-typing-end", 0.5, 0.15)
    elif name in dict(PAGES):
        scrolled(f"app-{name}-end")


# A stand-in extension for the chats: three chats, and a reply a second after you write.
THREADS = {
    "notes": [
        {"from": "me", "text": "Remind me what's left for Saturday"},
        {"from": "notes", "text": "Two things: pick up the **film** at 5, and send the photos to the group."},
        {"from": "me", "text": "And the café?"},
        {"from": "notes", "text": "Booked for 11. It's the one on `Valencia`."},
        {"from": "notes", "text": "Want me to set a reminder?"},
    ],
    "design": [{"from": "design", "text": "The new bar looks right in dark mode."}, {"from": "me", "text": "Nice, ship it"}],
    "trip": [
        {"from": "trip", "text": "Flights are booked. *Window seats* both ways."},
        {"from": "me", "text": "", "files": [{"name": "boarding-pass.pdf", "url": "files/boarding-pass.pdf", "type": "application/pdf"}]},
        {"from": "trip", "text": "The view from the room", "files": [
            {"name": "view.png", "url": "files/view.png", "type": "image/png", "width": 1200, "height": 900}]},
    ],
}


def picture(width=1200, height=900):
    """A made-up photo, a dusk sky over a sea, as a PNG."""
    rows = []
    for y in range(height):
        t = y / height
        if t < 0.62:
            color = (int(70 + 160 * t), int(90 + 90 * t), int(170 - 40 * t))
        else:
            u = (t - 0.62) / 0.38
            color = (int(30 + 20 * u), int(70 + 10 * u), int(110 - 30 * u))
        rows.append(b"\0" + bytes(color) * width)
    chunk = lambda kind, body: struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(b"".join(rows), 6)) + chunk(b"IEND", b"")


FILES = {"files/view.png": ("image/png", picture()), "files/boarding-pass.pdf": ("application/pdf", b"%PDF-1.4\n%%EOF\n")}
CHATS = [
    {"id": "notes", "name": "Notes", "line": "Pick up the **film** at 5", "pinned": True},
    {"id": "design", "name": "Design", "line": "The new bar looks right"},
    {"id": "trip", "name": "Trip", "line": "Flights are booked"},
]


class Extension(BaseHTTPRequestHandler):
    changed = threading.Condition()
    threads = {}
    versions = {}

    @classmethod
    def fresh(cls):
        cls.threads = json.loads(json.dumps(THREADS))
        cls.versions = {chat: 1 for chat in THREADS}
        return cls

    def answer(self, code, body=None, raw=None, kind="application/json"):
        data = raw if raw is not None else json.dumps(body).encode() if body is not None else b""
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path, _, query = self.path.partition("?")
        chat = path.strip("/")
        if chat in FILES:
            kind, data = FILES[chat]
            return self.answer(200, raw=data, kind=kind)
        if not chat:
            return self.answer(200, {"name": "Notes", "chats": CHATS})
        if chat not in self.threads:
            return self.answer(404)
        after = dict(part.split("=", 1) for part in query.split("&") if "=" in part).get("after")
        with self.changed:
            if after == str(self.versions[chat]):
                self.changed.wait(25)
            return self.answer(200, {"version": str(self.versions[chat]), "messages": self.threads[chat]})

    def do_POST(self):
        chat = self.path.strip("/")
        text = json.loads(self.rfile.read(int(self.headers["Content-Length"])))["text"]
        self.post(chat, {"from": "me", "text": text})
        threading.Timer(1.2, self.post, (chat, {"from": chat, "text": f"Got it: “{text}”."})).start()
        self.answer(204)

    def post(self, chat, message):
        with self.changed:
            self.threads[chat].append(message)
            self.versions[chat] += 1
            self.changed.notify_all()

    def log_message(self, *args):
        pass


# A stand-in source: a hint at any text that's running late.
class Source(BaseHTTPRequestHandler):
    def do_POST(self):
        update = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        late = "late" in update["before"] + update["after"]
        body = json.dumps({"hint": "Running late? Say when you’ll be there."} if late else {}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


class Quiet(ThreadingHTTPServer):
    """Leaves out the keyboard dropping a long poll as it closes."""

    def handle_error(self, request, address):
        pass


def serve(handler):
    """`handler` on a free port of the Mac's, which the emulator reaches as its own localhost."""
    server = Quiet(("127.0.0.1", 0), handler)
    port = server.server_address[1]
    threading.Thread(target=server.serve_forever, daemon=True).start()
    adb("reverse", f"tcp:{port}", f"tcp:{port}")
    servers.append((server, port))
    return f"http://localhost:{port}"


servers = []


def chats():
    seed(extensions=json.dumps([{"name": "Notes", "url": serve(Extension.fresh())}]))
    keys = keyboard()
    tap(*keys.more)
    tap_text(lambda text: text.startswith("Pick up the"), 3)
    shot("panel-chat", 1)
    tap_text("Message Notes", 1.5)
    keys = Keys()
    keys.type("ok")
    shot("panel-chat-typing", 0.5)
    tap(*keys["return"], 3.5)
    tap(keys.width / 2, keys.height * 0.3, 1.2)
    shot("panel-chat-answered", 0.5)
    tap_text("Trip", 3, top=True)
    shot("panel-chat-photo", 0.5)
    x, y = center(find("Trip", top=True))
    touch("DOWN", x, y)
    time.sleep(1.2)
    touch("UP", x, y)
    shot("panel-chat-tabs-menu", 0.8)


def hint():
    seed(sources=json.dumps([{"name": "Late Check", "url": serve(Source)}]))
    keyboard("Running late")
    shot("keyboard-hint", 3)


def replacement():
    """A text replacement typed: Android's personal dictionary's shortcut, as Settings › Typing sets one, typed in place
    on space with Auto-Correction on."""
    seed(autoCorrection=True)
    keys = keyboard()
    keys.type("omw ")
    shot("keyboard-replacement", 1)


def main():
    global appearance, klipy
    was_root = sh("id -u").strip() == "0"
    if not was_root:
        adb("root")
        time.sleep(2)
        adb("wait-for-device")
    night = "yes" if "yes" in sh("cmd uimode night") else "no"
    granted = "RECORD_AUDIO: granted=true" in sh(f"dumpsys package {PACKAGE} | grep RECORD_AUDIO")
    words = sh("content query --uri content://user_dictionary/words --projection shortcut:word")
    added_word = "shortcut=omw, word=On my way!" not in words
    backup = f"{STAGE}-backup"
    # The recordings move aside too: one without a transcript in the made-up ones would be written as iikb starts.
    sh(f"am force-stop {PACKAGE}; rm -rf {backup} && mkdir -p {backup} && cp -a {DATA}/files {DATA}/shared_prefs {backup}/ && "
       f"{{ [ ! -d {DATA}/no_backup/recordings ] || mv {DATA}/no_backup/recordings {backup}/recordings; }}")
    klipy = (re.search(r'name="klipyCustomer">([^<]+)<', sh(f"cat {DATA}/shared_prefs/settings.xml")) or [None, "iikb-shots"])[1]
    staged()
    try:
        sh(f"pm grant {PACKAGE} android.permission.RECORD_AUDIO")
        if added_word:
            sh("content insert --uri content://user_dictionary/words --bind word:s:'On my way!' --bind shortcut:s:omw "
               "--bind frequency:i:250 --bind locale:s:en_US --bind appid:i:0")
        steps = {
            "layers": layers, "typing": typing, "held": held, "swipe": swiped, "menu": menu,
            "emoji": lambda: panel("emoji", "pizza"), "gif": lambda: panel("gif", "cat"),
            "clipboard": lambda: panel("clipboard", "sight"), "transcripts": lambda: panel("transcripts", "the"),
            "dictation": dictation, "app": app, "chats": chats, "hint": hint, "replacement": replacement,
        }
        failed = []
        for appearance in ("light", "dark"):
            sh(f"cmd uimode night {'yes' if appearance == 'dark' else 'no'}")
            time.sleep(1)
            for section in wanted:
                try:
                    steps[section]()
                except Exception as error:
                    failed.append(f"{section} ({appearance}): {error}")
                    print("failed", section, appearance, error, flush=True)
                    sh("input keyevent KEYCODE_BACK")
        if failed:
            print("\n".join(["sections that failed:", *failed]), flush=True)
    finally:
        for server, port in servers:
            server.shutdown()
            adb("reverse", "--remove", f"tcp:{port}")
        sh(f"am force-stop {PACKAGE}")
        owner = sh(f"stat -c %u:%g {DATA}").strip()
        sh(f"rm -rf {DATA}/cache/computers")
        sh(f"[ -d {backup}/files ] && rm -rf {DATA}/files {DATA}/shared_prefs && cp -a {backup}/files {backup}/shared_prefs {DATA}/ && "
           f"chown -R {owner} {DATA}/files {DATA}/shared_prefs && rm -rf {DATA}/no_backup/recordings && "
           f"{{ [ ! -d {backup}/recordings ] || mv {backup}/recordings {DATA}/no_backup/recordings; }} && restorecon -R {DATA} && rm -rf {backup} {STAGE}")
        if not granted:
            sh(f"pm revoke {PACKAGE} android.permission.RECORD_AUDIO")
        if added_word:
            sh("content delete --uri content://user_dictionary/words --where \"shortcut='omw'\"")
        sh(f"cmd uimode night {night}")
        sh(f"ime set {IME}")
        if not was_root:
            adb("unroot")
            time.sleep(2)
            adb("wait-for-device")


klipy = None
if __name__ == "__main__":
    main()
