"""The stages of iikb's dictation after Parakeet, each the app's own Swift built as a small CLI, for the benches
(scripts/rivals, scripts/voiceloop) and the gate on Clean's model (scripts/clean), on the Mac or here on Linux:

    heard ─▶ VoiceEdit: Packages/Voice/Sources/VoiceEditor with the weights the app ships (edit_stage, edited)
          ─▶ VoiceText: KeyboardCore, which takes the model's reply or types without it (text_stage, typed) ─▶ typed
"""

import hashlib, json, os, platform, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = Path.home() / ".local/share/iikb"
LEXICON = ROOT / "Packages/KeyboardModules/Sources/KeyboardEnglish/Resources/en.lexicon"


def built(pkg, product, *flags, env=None):
    done = subprocess.run(["swift", "build", "-c", "release", *flags, "--package-path", pkg], capture_output=True,
                          text=True, env=env)
    if done.returncode:
        sys.exit(done.stdout + done.stderr)
    return pkg / f".build/release/{product}"


def linked(pkg, links):
    for link, target in links:
        link.parent.mkdir(parents=True, exist_ok=True)
        if not link.is_symlink():
            link.symlink_to(target)


def llama(pkg):
    """The llama target for a bench package, and the build's flags. On the Mac it's the app's own xcframework, its URL
    and checksum read from Packages/Voice/Package.swift, the one place that names llama.cpp's release. Here it's that
    release built for this machine (scripts/llama), found through pkg-config."""
    manifest = (ROOT / "Packages/Voice/Package.swift").read_text()
    if platform.system() == "Darwin":
        url, checksum = re.search(r'name: "llama",\s*url: "([^"]+)",\s*checksum: "([^"]+)"', manifest).groups()
        return f'.binaryTarget(name: "llama", url: "{url}", checksum: "{checksum}")', [], None
    prefix = Path(subprocess.run([ROOT / "scripts/llama"], capture_output=True, text=True, check=True).stdout.strip())
    (pkg / "Sources/llama").mkdir(parents=True, exist_ok=True)
    (pkg / "Sources/llama/shim.h").write_text("#include <llama.h>\n")
    (pkg / "Sources/llama/module.modulemap").write_text('module llama [system] {\n    header "shim.h"\n    export *\n}\n')
    env = dict(os.environ, PKG_CONFIG_PATH=str(prefix / "lib/pkgconfig"))
    return '.systemLibrary(name: "llama", pkgConfig: "llama")', ["-Xlinker", "-rpath", "-Xlinker", str(prefix / "lib")], env


def edit_stage():
    """VoiceEdit built in build/voiceedit: the app's Sources/VoiceEditor, Tools/VoiceBench/Edit's main.swift and
    llama(). Returns the binary."""
    pkg = ROOT / "build/voiceedit"
    linked(pkg, [(pkg / "Sources/VoiceEditor", ROOT / "Packages/Voice/Sources/VoiceEditor"),
                 (pkg / "Sources/VoiceEdit/main.swift", ROOT / "Tools/VoiceBench/Edit/main.swift")])
    target, flags, env = llama(pkg)
    (pkg / "Package.swift").write_text(f"""// swift-tools-version: 6.2
import PackageDescription

let package = Package(name: "VoiceEdit", platforms: [.macOS(.v26)], targets: [
    {target},
    .target(name: "VoiceEditor", dependencies: ["llama"], exclude: ["AGENTS.md"],
            swiftSettings: [.treatAllWarnings(as: .error)]),
    .executableTarget(name: "VoiceEdit", dependencies: ["VoiceEditor"]),
])
""")
    return built(pkg, "VoiceEdit", *flags, env=env)


def weights(tool):
    """The weights the app ships (`VoiceEdit --weights`), fetched once into DATA/weights/<sha256>.gguf and checked
    before the file gets its name."""
    shipped = json.loads(subprocess.run([tool, "--weights"], capture_output=True, text=True, check=True).stdout)
    path = DATA / f"weights/{shipped['sha256']}.gguf"
    if not path.exists():
        part = path.with_suffix(".part")
        part.parent.mkdir(parents=True, exist_ok=True)
        print(f"downloading {shipped['name']}, {shipped['bytes'] / 1e6:.0f} MB, once", file=sys.stderr)
        subprocess.run(["curl", "-fL", "-C", "-", "-o", part, shipped["url"]], check=True)
        digest = hashlib.sha256()
        with part.open("rb") as f:
            while chunk := f.read(1 << 24):
                digest.update(chunk)
        if digest.hexdigest() != shipped["sha256"]:
            part.unlink()
            sys.exit(f"{shipped['url']} isn't the weights Weights.shipped names")
        part.rename(path)
    return path


def edited(heard):
    """`heard` ({id: text}) through VoiceEdit: {id: VoiceEdit's row}, `edited` in it when the model gave a reply."""
    tool = edit_stage()
    given = "".join(json.dumps(dict(id=id, heard=text)) + "\n" for id, text in heard.items())
    done = subprocess.run([tool, weights(tool)], input=given, capture_output=True, text=True)
    if done.returncode:
        sys.exit(done.stderr)
    return {r["id"]: r for r in map(json.loads, filter(None, done.stdout.split("\n")))}


def text_stage():
    """Tools/VoiceBench/Text built in build/voicetext on a package of KeyboardCore alone, as scripts/coretest builds
    its tests: optimized but file by file, so a change to KeyboardCore rebuilds in about 30 s rather than 95 (SwiftPM's
    default build system fails without whole-module optimization)."""
    pkg = ROOT / "build/voicetext"
    linked(pkg, [(pkg / "Sources/KeyboardCore", ROOT / "Packages/KeyboardModules/Sources/KeyboardCore"),
                 (pkg / "Sources/VoiceText/main.swift", ROOT / "Tools/VoiceBench/Text/main.swift")])
    (pkg / "Package.swift").write_text("""// swift-tools-version: 6.2
import PackageDescription

let package = Package(name: "VoiceText", platforms: [.macOS(.v26)], targets: [
    .target(name: "KeyboardCore", exclude: ["AGENTS.md"]),
    .executableTarget(name: "VoiceText", dependencies: ["KeyboardCore"]),
])
""")
    return built(pkg, "VoiceText", "--build-system", "native", "-Xswiftc", "-no-whole-module-optimization")


def typed(tool, heard, settings, replies={}):
    """What iikb types for each `heard` ({id: text}) at the start of a message with `settings` (style, editing, lists,
    auto-capitalization), given the model's `replies` ({id: text or None}): {id: (text, whether it typed the reply)}."""
    vocabulary = ROOT / "build/vocabulary.json"
    vocabulary.parent.mkdir(exist_ok=True)
    vocabulary.write_text('{"terms": []}')
    given = "".join(json.dumps(dict(id=id, heard=text, edited=replies.get(id))) + "\n" for id, text in heard.items())
    done = subprocess.run([tool, LEXICON, vocabulary, "-", *settings], input=given, capture_output=True, text=True, check=True)
    return {r["id"]: (r["typed"], r.get("edited", False)) for r in map(json.loads, filter(None, done.stdout.split("\n")))}
