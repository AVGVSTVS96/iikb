# iikb

An iOS custom keyboard (UIKit, Swift 6, iOS 26+) that types like Apple's and has its own look, with Raycast's keyboard as one reference (docs/design.md). MIT. Its name is iikb, lowercase always, in what people see and in code names and IDs alike (`brand/BRAND.md`, `copy/MESSAGING.md`).

## Modules

Each module keeps its own AGENTS.md beside its code, with what it holds and why. Read it before working in that module. What a module may import is set in `Packages/KeyboardModules/Package.swift`, `Packages/Voice/Package.swift` and the root `Package.swift`.

- `Packages/KeyboardModules/Sources/KeyboardCore`: everything the keyboard does (keys, layouts, typing, correction, swipe, dictation's text), so the extension and the web demo share it. Imports nothing, not even Foundation; it also compiles to WebAssembly. [KeyboardCore/AGENTS.md](Packages/KeyboardModules/Sources/KeyboardCore/AGENTS.md)
- `…/KeyboardEnglish`: the bundled English data and its loaders. On KeyboardCore and Foundation. [KeyboardEnglish/AGENTS.md](Packages/KeyboardModules/Sources/KeyboardEnglish/AGENTS.md)
- `…/KeyboardStore`: iikb's saved data and the app–keyboard channel, through `StoredFile`. On KeyboardCore and KeyboardEnglish. [KeyboardStore/AGENTS.md](Packages/KeyboardModules/Sources/KeyboardStore/AGENTS.md)
- `…/KeyboardUI`: UIKit parts any keyboard can build on, with no private API. On KeyboardCore and KeyboardEnglish. [KeyboardUI/AGENTS.md](Packages/KeyboardModules/Sources/KeyboardUI/AGENTS.md)
- `…/FullKeyboard`: iikb's own keyboard (the view controller, its panels, sources, the host app). On the four above, and the only target that links the private `KeyboardArbiter`. [FullKeyboard/AGENTS.md](Packages/KeyboardModules/Sources/FullKeyboard/AGENTS.md)
- `Packages/Voice/Sources/VoiceCapture`: voice typing's microphone and the `Recording` it makes. On KeyboardStore. [VoiceCapture/AGENTS.md](Packages/Voice/Sources/VoiceCapture/AGENTS.md)
- `…/VoiceModels`: the models that write a finished recording down, the Parakeets through FluidAudio and Apple's, and `CleanModel`, Clean's language model's download and memory. On VoiceCapture, VoiceEditor, KeyboardStore and FluidAudio. [VoiceModels/AGENTS.md](Packages/Voice/Sources/VoiceModels/AGENTS.md)
- `…/VoiceEditor`: Clean's language model on the iPhone's CPU through llama.cpp (`Editor`, `Weights`). On llama.cpp alone, nothing of iOS, so the bench and `scripts/clean` build its files on Linux too. [VoiceEditor/AGENTS.md](Packages/Voice/Sources/VoiceEditor/AGENTS.md)
- `App/`: the containing app, a folder per feature. On KeyboardEnglish, KeyboardStore, KeyboardUI, VoiceCapture and VoiceModels, never FullKeyboard. [App/AGENTS.md](App/AGENTS.md); voice typing in [App/Voice/AGENTS.md](App/Voice/AGENTS.md)
- `Keyboard/`: the extension target, a one-line subclass. On FullKeyboard.
- `Controls/`: the widget extension holding iikb Mic, a control for Control Center, the Lock Screen and the Action button that shows whether the app's microphone is on and turns it off (`Signal.micOff`), or opens the app with it on (`AppLink.mic`). On nothing of ours, so it doesn't carry the English data; it spells KeyboardStore's names itself (`ArchitectureTests`). Its App Intents metadata is committed in `Controls/Metadata.appintents`, since xtool can't make it: `scripts/build` fails when Xcode's differs and names the copy to commit.
- `Packages/KeyboardModules/Examples/MinimalKeyboard`: a keyboard with a look of its own on `TypingEngine`, in one file, for docs/build-a-keyboard.md (the guide for building on iikb). It's its own package target, so it reaches only public API. Neither `scripts/check` nor `scripts/coretest` builds it, so a change to that API needs it built on the Mac to keep the guide true.
- `Packages/KeyboardModules/Tools`: the builders of KeyboardEnglish's data (KeyboardEnglish/AGENTS.md).
- `Packages/KeyboardModules/Tests/KeyboardUITests`: `Evaluation`, the autocorrect scorer (scripts/AGENTS.md, "scripts/eval"), with `TextCheckerSource` (`UITextChecker`) as its baseline keyboard.
- `UITests/`: types through the real extension in the simulator.
- `android/`: iikb on Android, KeyboardCore built with the Swift SDK for Android under a Kotlin input method, as a sideloaded APK (`scripts/android`). [android/AGENTS.md](android/AGENTS.md)
- `web/`: iikb's page, iikb.vercel.app, and a WebAssembly build of KeyboardCore through `TypingEngine` that no page loads, kept to show KeyboardCore still compiles to it. [web/AGENTS.md](web/AGENTS.md)
- `sources/record.ts`: the record source (Bun): a log of every message you send and every field you leave with text you typed, with the host bundle ID the keyboard sends (docs/sources.md). `bun test sources/`.
- `extensions/`: extensions (Bun): `iikb.ts` serves one from `chats({ name, list, read, send })` (docs/extensions.md); hex serves its own from its hub. `bun test extensions/`.
- `server/backup.ts`: the backup server (KeyboardStore/AGENTS.md, "Backup").
- `scripts/`: build, install, simulator and measuring scripts. [scripts/AGENTS.md](scripts/AGENTS.md)
- `project.yml`: XcodeGen spec. The `.xcodeproj` is generated, never committed.

## Build and test

Development happens on a Linux box. Simulator builds, tests and screenshots run on GitHub's free Macs, never Bassim's; the iPhone build is made here, signed on the Mac and put on the install link and in hangar with `scripts/phone`, which says whether hangar installs it by itself or waits for his tap.
- `scripts/ci '<command>'` runs the command on one of GitHub's Macs on this checkout's tree, uncommitted changes included, prints the run's link and output, and copies its screenshots back to `shots/raw/` (scripts/AGENTS.md, "Simulators"). Runs go at once, each on its own Mac, up to five; past two waiting on GitHub, the next waits on this box, so main's check goes first.
- A change is checked here first: `scripts/coretest` for KeyboardCore, `scripts/check` for whether everything builds for the iPhone. Then it goes to main as soon as it's ready, and a push to main puts it on the install link by itself: hex's pipeline (`projects/pipeline` in hex) hears GitHub's push and runs `scripts/phone`, with `--now` when a commit in the push is a `fix`. A change is tried on the phone once it has a build with it: hangar installs it by itself while his Automatic installs is on, and otherwise waits for his tap (`scripts/phone` prints the build on each device the Mac reaches).
- Simulator checks run by default: a change gets the verify skill's row for what it touches, through `scripts/ci`, and is then checked on the iPhone. Every push to main that changes more than docs also runs `scripts/verify` there, the newest commit waiting while one runs.
- Device builds made by Xcode (Xcode Cloud's, or one run in Xcode) take the team from `Config/Team.xcconfig` (`DEVELOPMENT_TEAM = …`, not committed), which `scripts/sync` leaves in place on the Mac; the install link's build is signed through xtool instead (scripts/AGENTS.md, "scripts/phone").
- To prove a change works, follow the `verify` skill (`.claude/skills/verify`).
- Follow and use pstack's skills (the pstack Claude Code plugin) when doing work on iikb.

Prefer committing straight to main, merge parallel work like a zipper on new projects

TestFlight's public link gets the `beta` branch, a commit of main: Xcode Cloud builds every push to it (`ci_scripts/`, without private API). Bassim moves beta when he wants; when he hasn't for 24 hours and main has moved, a new beta is cut from main's latest by hex's `iikb-beta-cut` schedule (`schedules.json` in hex), which writes the testers' note to main first. `.github/workflows/beta.yml` only tags the commit beta left as `beta-prev`, so Xcode Cloud can refuse a beta that repeats the last one's note. The note is `TestFlight/WhatToTest.en-US.txt`; iikb's description there is `TestFlight/Description.en-US.txt`, which nothing sends to App Store Connect, so a change to it goes there by hand.

```sh
scripts/ci scripts/build                        # xcodegen and a build for the simulator, on GitHub's Mac
scripts/coretest                                # KeyboardCore's tests here on Linux, no Mac (about 25 s)
scripts/check                                   # this checkout built for the iPhone here on Linux, unsigned (a few minutes; one at a time)
scripts/public-review.ts [--all|--text <where>]  # a reviewer reads what iikb shows the public: what changed since origin/main, all of it, or text going elsewhere (stdin)
scripts/format [--check]                        # swift format on every tracked Swift file (.swift-format); --check is what scripts/check and CI run
scripts/clean                                   # Clean's language model on scripts/clean.txt, the fruit list first: each line through the app's Editor and shipped weights, then KeyboardCore, pass or fail, and fails until Weights.shipped's URL serves the file; scripts/phone puts no build that fails it on the install link
bun run check                                   # the TypeScript and JavaScript (after bun install): oxlint, oxfmt --check, tsc, bun test, as CI runs it
bun run fix                                     # oxlint's fixes, then oxfmt
scripts/phone                                   # main's last commit built, signed and put on the install link for the iPhone and iPad, then the build each device has (--rebuild even when nothing changed)
scripts/rollback                                # the build before the latest back on the install link and in hangar, whose Automatic installs put it on the iPhone; again goes forward. Revert the commit too, or the next build puts it back
scripts/backup <udid>                           # the iPhone's iikb data copied to ~/.local/share/iikb/backup here, never deleted, replaced files kept in versions/
scripts/restore <udid> [--at <time>|now] [name…]  # the backup put back on the iPhone, all of it or the files named, as it is or as it was at a time; leaves out a copy much smaller than one replaced in the day after an install left iikb a new, empty container (docs/backup.md)
scripts/ci scripts/verify                       # main's last commit on one iPhone Duo simulator: package and UI tests, light and dark, shots in shots/raw/verify/ (every push to main runs its parts side by side on four Macs, three when nothing that draws changed, none when only docs did; PARTS="typing dark" picks some)
scripts/ci scripts/test                         # KeyboardUI's package tests on the iPhone Duo simulator, without the autocorrect scorer
scripts/ci scripts/uitest                       # type through the real extension (the iPhone Duo by default)
```

The other commands (screenshots, probes on the iPhone, benchmarks, the data builders) are in scripts/AGENTS.md.

## Rules

Each rule with what enforces it. When an agent repeats a mistake, fix it at the highest level that works (a module boundary, then a type, then a check whose error names the fix) and add its row here; drop a row once its mistake can't happen. The why behind each rule, iOS facts included, is in the module doc named.

| Rule | Enforced by |
| --- | --- |
| `KeyboardCore` imports nothing, not even Foundation; platform services sit outside it behind Core protocols | Package.swift (no dependencies), `ArchitectureTests` |
| Keyboard behavior goes in `KeyboardCore`; `KeyboardUI` and `web/` only draw, play feedback and forward events, so the two never drift | judgment: nothing enforces it |
| `KeyboardUI` uses no private API; only `FullKeyboard` links `KeyboardArbiter` | Package.swift for `KeyboardArbiter`; judgment for anything called by name |
| The app never imports `FullKeyboard` | Package.swift, project.yml |
| Kept data reads and saves through `StoredFile`, which never saves over a file it couldn't read; any other file access says what it is, `// file: <what>` (KeyboardStore) | `StoredFile`, `ArchitectureTests` |
| Behavior follows real events (touches, `textDidChange`, `selectionDidChange`), not a clock. A timer is for what is timed by nature (key repeat, long-press, a source's 10 s to answer; the app's are in App/Voice/AGENTS.md) or a backup for an event that can be missed, like a retry after a failed read. Each timer's line says which it is, `// timer: <which>`, from `ArchitectureTests`' list, which a new one joins with its reason | `ArchitectureTests` |
| The engine reads the text only from its `TextState`; every edit goes through `TypingEngine.write`; automatic edits replace only characters the keyboard typed (KeyboardCore) | `TextState`, `TextStateStressTests` |
| A correctly typed real word is never changed; word frequencies only choose among what the fingers could have meant (KeyboardCore) | `TypingModelTests`, `scripts/eval` |
| A model's reply is typed only as an edit of what was said, holding no word or number that wasn't said: it reaches a field only through `DictationWriting.written(_:edited:)` (KeyboardCore) | `DictationEdit`, the only reader of a reply, with scripts/edits.txt in `FormatTests`; judgment for any other way to a field |
| Learning comes only from real events, and nothing in the model runs on a clock (KeyboardCore) | `TypingModelTests` |
| A change that moves the eval's numbers beats them and updates `scripts/eval.expected` in the same commit (scripts) | `scripts/eval` diffs every full run; `.github/workflows/eval.yml` runs it on each push to main that changes what it scores |
| Held-out sets (`~/.local/share/iikb/heldout/` on the server, the rivals' `heldout.txt` on the Mac) are never read while fixing what they score, never edited to suit a result, and only added to before the work they'll judge, by someone who hasn't read the code (scripts, "scripts/voiceloop" and "scripts/rivals") | judgment: nothing enforces it |
| Text that tunes or picks something never also checks it. Gates and regression files (`scripts/gate.txt`, `formats.txt`, `cleanup.txt`, FieldBench's cases, a test's made-up lexicon) gain each case with its fix, so a pass says only that fixed cases stay fixed; how often something works is quoted from public data or a held-out set (scripts) | judgment: nothing enforces it |
| A surface is done when it holds up beside the app that does the same job best (Messages for a chat, Spotlight for search), in screenshots at the phone's size, with its text and small details checked zoomed in. A new kind of input or view gets its own primitive built for its job, never the nearest existing one bent to fit (KeyboardUI, `PanelField`) | `PanelField` has no default; judgment, shots |
| Keys behave and sit as Apple's do, measured in the same simulator (`shots/`, `scripts/shotdiff.py`), never eyeballed; docs/design.md says where and why it moves a key off Apple's geometry | judgment, measured with `scripts/shotdiff.py` |
| The keyboard, the app's preview and Your Taps lay out the same keys (KeyboardCore) | `KeyboardGeometry`, `GeometryTests` |
| The bar's buttons are set out as the top row's keys are (KeyboardCore) | `BarLayoutTests` |
| Gaps between keys take taps (KeyboardUI) | `FirstTapTests` |
| Keycaps use SF Compact from the system font file (KeyboardUI) | judgment: nothing enforces it |
| The keyboard's height comes from Auto Layout content, never a plain height constraint (KeyboardUI) | judgment: nothing enforces it |
| Only `VoiceEditor` links llama.cpp, and it imports nothing of iOS, so the bench and the gate run the app's own files (VoiceEditor) | Packages/Voice/Package.swift; `scripts/clean` builds it on Linux |
| Clean's model goes on typing `scripts/clean.txt`, whatever weights ship (scripts) | `scripts/phone` runs `scripts/clean` |
| Recording never waits for a model: the `Microphone` knows nothing of `VoiceModel` (App/Voice) | Packages/Voice/Package.swift: VoiceModels is on VoiceCapture, so VoiceCapture can't import it |
| Never a Bluetooth microphone unless one is picked in Settings › Microphone (VoiceCapture) | judgment: nothing enforces it |
| A page opened from another in its tab has one Back, in the Duo's side bar with the tabs on every screen (App) | `backInSideBar(_:)`, `BackTests` |
| A new use of the host app goes through `FullKeyboardViewController.hostApp` (FullKeyboard) | judgment: nothing enforces it |
| Drawing never reads `textDocumentProxy`: only UIKit's calls in and taps do, keeping what drawing needs in `hostField`, since a late answer can draw after iOS tore the proxy down (FullKeyboard) | `ArchitectureTests` |
| Only main's last commit reaches the phone, or the build before it when Bassim asks for a rollback (`scripts/rollback`), and only through the link or hangar, by his tap or his Automatic installs: no agent installs on his devices, a device test (`scripts/chatdevice`) included, unless he asks; never linked against an iOS SDK below 27.1, though iikb runs on iOS 26 (scripts) | `scripts/phone`: builds main in its own worktree and only offers it, refuses without `backup.key` or linked against an iOS SDK below 27.1; judgment for the rest |
| Restore only once the device has a build from the link: an old build can't read a memory restored without its token | judgment: nothing enforces it |
| Comments only for a footgun from outside iikb the code can't show: one `WARNING:` line, with its link when there is one. Tests prove things: no fixed sleeps, test doubles, retries or raised timeouts | [Landmines](https://github.com/interfere-inc/landmines) in TypeScript (`oxlint.config.ts`); judgment in Swift |
| Every AGENTS.md names only code that exists, and no file keeps a conflict marker | `ArchitectureTests` |
| A change you'd notice in the app or keyboard carries a `Changelog:` trailer, one short line (App/Settings/ChangelogPage.swift). It shows on each platform whose files the commit changes: iPhone's Changelog and iikb.vercel.app (at its next deploy, web/AGENTS.md) for `scripts/iphone-paths.txt`, Android's for `android/`, KeyboardCore and KeyboardEnglish; a change worded differently for each is two commits | `scripts/phone`, `web/changes.ts`, android/app/build.gradle.kts |
| What the public sees (`TestFlight/`, the README, docs/, the site, Changelog lines, the app's words) passes a reviewer before it goes out | `scripts/hooks/pre-push` runs `scripts/public-review.ts` on every push to main (`git config core.hooksPath scripts/hooks`) |
