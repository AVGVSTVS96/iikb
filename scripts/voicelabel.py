"""scripts/voicelabel: a page on this server, over Tailscale, where Bassim labels his own dictations by ear, so
scripts/voiceloop can score words wrong against what he said rather than against what he kept (most finals are what
the build of their day typed, so they can't show a word it misheard that he let stand).

The first run picks the sample, kept in heldout/label-sample.json beside the backup: `count` (100 by default, about
half an hour of listening) of every dictation Parakeet v3 wrote and iikb typed words for, recording kept, by a hash of
each id, so any can be picked, those whose final was never found included. Each shows what the iPhone typed, to be made
what he said; labels go to heldout/labels.jsonl, the last for a dictation counting, and nothing in the repo. Never read
them while fixing dictation: they're held out.
"""
import hashlib, http.server, json, os, subprocess, sys, time
from pathlib import Path

BACKUP = Path(os.environ.get("IIKB_BACKUP", Path.home() / ".local/share/iikb/backup"))
MIRROR = BACKUP / "mirror/app"
HELDOUT = BACKUP.parent / "heldout"
SAMPLE, LABELS = HELDOUT / "label-sample.json", HELDOUT / "labels.jsonl"
PORT = 8642


def transcripts():
    return {t["id"]: t for t in map(json.loads, open(MIRROR / "transcripts.jsonl"))}


def sample(count):
    if not SAMPLE.exists():
        HELDOUT.mkdir(parents=True, exist_ok=True)
        eligible = [t["id"] for t in transcripts().values() if t["typed"] and t["text"].strip() and t.get("model") == "Parakeet v3"
                    and t.get("seconds", 1) >= 1 and (MIRROR / f"recordings/{t['id']}.wav").exists()]
        SAMPLE.write_text(json.dumps(sorted(eligible, key=lambda id: hashlib.sha256(id.encode()).digest())[:count]))
    return json.loads(SAMPLE.read_text())


def labels():
    return {r["id"]: r["text"] for r in map(json.loads, open(LABELS))} if LABELS.exists() else {}


PAGE = """<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>iikb labels</title>
<style>
:root{color-scheme:dark;font:17px/1.4 -apple-system,system-ui,sans-serif}
body{background:#000;color:#eee;max-width:640px;margin:0 auto;padding:20px}
p{color:#999;margin:0 0 16px}
audio{width:100%;margin:12px 0}
textarea{width:100%;box-sizing:border-box;min-height:9em;background:#111;color:#fff;border:1px solid #333;
border-radius:12px;padding:12px;font:inherit}
.row{display:flex;gap:8px;margin-top:12px}
button{flex:1;padding:12px;border-radius:12px;border:0;font:inherit;background:#222;color:#eee}
button.save{background:#fff;color:#000;font-weight:600}
</style>
<p>Listen, then make the text exactly the words you said: fix misheard, missing and extra words. Write numbers, emails
and links as you'd want them typed. Punctuation, capitals and um or uh don't count. Can't tell skips one you can't make
out. Return saves and goes on (shift-return for a new line).</p>
<b id=count></b>
<audio id=audio controls autoplay></audio>
<textarea id=text></textarea>
<div class=row><button id=back>Back</button><button id=skip>Can't tell</button><button class=save id=save>Save</button></div>
<script>
let clips = [], at = 0
const $ = id => document.getElementById(id)
function show() {
  const done = clips.filter(c => c.label !== undefined).length
  if (at >= clips.length) { $('count').textContent = `All ${clips.length} labelled. Thank you.`; return }
  const clip = clips[at]
  $('count').textContent = `${at + 1} of ${clips.length} (${done} done)`
  $('audio').src = `/audio/${clip.id}`
  $('text').value = clip.label ?? clip.typed
  $('text').focus()
}
async function save(text) {
  const clip = clips[at]
  await fetch('/label', {method: 'POST', body: JSON.stringify({id: clip.id, text})})
  clip.label = text
  at += 1
  show()
}
$('save').onclick = () => save($('text').value)
$('skip').onclick = () => save(null)
$('back').onclick = () => { at = Math.max(at - 1, 0); show() }
$('text').onkeydown = e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); save($('text').value) } }
fetch('/clips').then(r => r.json()).then(all => {
  clips = all
  at = Math.max(clips.findIndex(c => c.label === undefined), 0)
  show()
})
</script>"""


class Page(http.server.BaseHTTPRequestHandler):
    def reply(self, body, kind):
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/":
            self.reply(PAGE.encode(), "text/html; charset=utf-8")
        elif self.path == "/clips":
            said, kept = transcripts(), labels()
            rows = [dict(id=id, typed=(said[id].get("field") or {}).get("typed", said[id]["text"]), **({"label": kept[id]} if id in kept else {}))
                    for id in self.server.sample if id in said]
            self.reply(json.dumps(rows).encode(), "application/json")
        elif self.path.startswith("/audio/") and self.path[7:] in self.server.sample:
            self.reply((MIRROR / f"recordings/{self.path[7:]}.wav").read_bytes(), "audio/wav")
        else:
            self.send_error(404)

    def do_POST(self):
        given = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if self.path != "/label" or given["id"] not in self.server.sample:
            return self.send_error(404)
        with LABELS.open("a") as f:
            f.write(json.dumps(dict(id=given["id"], text=given["text"], at=time.strftime("%Y-%m-%dT%H:%M:%S"))) + "\n")
        self.reply(b"{}", "application/json")

    def log_message(self, *_):
        pass


def main():
    picked = sample(int(sys.argv[1]) if len(sys.argv) > 1 else 100)
    found = subprocess.run(["tailscale", "ip", "-4"], capture_output=True, text=True).stdout.split()
    host = found[0] if found else "127.0.0.1"
    server = http.server.ThreadingHTTPServer((host, PORT), Page)
    server.sample = picked
    print(f"{len(labels())} of {len(picked)} labelled; open http://{host}:{PORT} on the Mac or iPhone (Tailscale), ^C when done", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
