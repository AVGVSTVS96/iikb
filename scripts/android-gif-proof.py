#!/usr/bin/env python3
"""On a CI emulator with adb on PATH: iikb's APK installed, a GIF tapped in its GIF panel inside Google Messages' compose
box, and shots of the panel and of the box after. Reuses android-shots.py's finders.

python3 android-gif-proof.py <apk> <out>
"""
import importlib.util
import os
import subprocess
import sys
import time

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("shots", os.path.join(here, "android-shots.py"))
shots = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shots)
shots.ADB = "adb"
apk, out = sys.argv[1:3]
os.makedirs(out, exist_ok=True)
sh, tap, nodes = shots.sh, shots.tap, shots.nodes


def shot(name):
    time.sleep(1.5)
    with open(os.path.join(out, name + ".png"), "wb") as file:
        file.write(shots.adb("exec-out", "screencap", "-p"))
    print("shot", name, flush=True)


def texts():
    return [text for text, _, _ in nodes() if text]


subprocess.run(["adb", "install", "-r", apk], check=True)
sh("settings put global disable_window_blurs 1")
sh(f"ime enable {shots.IME}; ime set {shots.IME}")
sh("pm grant com.shahidy.iikb android.permission.RECORD_AUDIO")
sh("am start -a android.intent.action.SENDTO -d sms:5551234")
time.sleep(8)
for _ in range(4):
    dismiss = [b for text, _, b in nodes() if text in ("Not now", "Skip", "No thanks", "Maybe later", "Got it", "Close app")]
    if not dismiss:
        break
    tap(*shots.center(dismiss[0]), 2)
shot("1-messages")
field = [b for text, _, b in nodes() if text in ("Text message", "RCS message", "Message")]
tap(*shots.center(field[0]), 2.5)
keys = shots.Keys()
tap(*keys.more)
shots.tap_text("GIFs", 2)
time.sleep(6)
shot("2-gif-panel")
item = next(b for _, description, b in nodes()
            if description not in ("", "Back", "Switch input method") and b[1] > keys.height * 0.4)
tap(*shots.center(item), 4)
shot("3-after-tap")
after = texts()
print("texts after tap:", after, flush=True)
copied = any("Copied" in text for text in after)
print("fell back to copy" if copied else "no copy notice: the GIF went into the box", flush=True)
sys.exit(1 if copied else 0)
