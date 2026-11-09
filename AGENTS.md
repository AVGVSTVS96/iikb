# iikb

An iOS custom keyboard (UIKit, Swift 6, iOS 26+) that types like Apple's and looks like Raycast's (docs/design.md). MIT. Its name is iikb, lowercase always, in what people see and in code names and IDs alike (`brand/BRAND.md`, `copy/MESSAGING.md`).

## Modules

Each module keeps its own AGENTS.md beside its code, with what it holds and why. Read it before working in that module. What a module may import is set in `Packages/KeyboardModules/Package.swift`, `Packages/Voice/Package.swift` and the root `Package.swift`.

- `Packages/KeyboardModules/Sources/KeyboardCore`: everything the keyboard does (keys, layouts, typing, correction, swipe, dictation's text), so the extension and the web demo share it. Imports nothing, not even Foundation; it also compiles to WebAssembly. [KeyboardCore/AGENTS.md](Packages/KeyboardModules/Sources/KeyboardCore/AGENTS.md)
- `…/KeyboardEnglish`: the bundled English data and its loaders. On KeyboardCore and Foundation. [KeyboardEnglish/AGENTS.md](Packages/KeyboardModules/Sources/KeyboardEnglish/AGENTS.md)
- `…/KeyboardStore`: iikb's saved data and the app–keyboard channel, through `StoredFile`. On KeyboardCore and KeyboardEnglish. [KeyboardStore/AGENTS.md](Packages/KeyboardModules/Sources/KeyboardStore/AGENTS.md)
- `…/KeyboardUI`: UIKit parts any keyboard can build on, with no private API. On KeyboardCore and KeyboardEnglish. [KeyboardUI/AGENTS.md](Packages/KeyboardModules/Sources/KeyboardUI/AGENTS.md)
- `…/FullKeyboard`: iikb's own keyboard (the view controller, its panels, sources, the host app). On the four above, and the only target that links the private `KeyboardArbiter`. [FullKeyboard/AGENTS.md](Packages/KeyboardModules/Sources/FullKeyboard/AGENTS.md)
- `Packages/Voice/Sources/VoiceCapture`: voice typing's microphone and the `Recording` it makes. On KeyboardStore. [VoiceCapture/AGENTS.md](Packages/Voice/Sources/VoiceCapture/AGENTS.md)
- `…/VoiceModels`: the models that write a finished recording down, the Parakeets through FluidAudio and Apple's. On VoiceCapture, KeyboardStore and FluidAudio. [VoiceModels/AGENTS.md](Packages/Voice/Sources/VoiceModels/AGENTS.md)
- `App/`: the containing app, a folder per feature. On KeyboardEnglish, KeyboardStore, KeyboardUI, VoiceCapture and VoiceModels, never FullKeyboard. [App/AGENTS.md](App/AGENTS.md); voice typing in [App/Voice/AGENTS.md](App/Voice/AGENTS.md)
- `Keyboard/`: the extension target, a one-line subclass. On FullKeyboard.
- `Controls/`: the widget extension holding iikb Mic, a control for Control Center, the Lock Screen and the Action button that shows whether the app's microphone is on and turns it off (`Signal.micOff`), or opens the app with it on (`AppLink.mic`). On nothing of ours, so it doesn't carry the English data; it spells KeyboardStore's names itself (`ArchitectureTests`). Its App Intents metadata is committed in `Controls/Metadata.appintents`, since xtool can't make it: `scripts/build` fails when Xcode's differs and names the copy to commit.
- `Packages/KeyboardModules/Examples/MinimalKeyboard`: a keyboard with a look of its own on `TypingEngine`, in one file, for docs/build-a-keyboard.md (the guide for building on iikb). It's its own package target, so it reaches only public API. Neither `scripts/check` nor `scripts/coretest` builds it, so a change to that API needs it built on the Mac to keep the guide true.
- `Packages/KeyboardModules/Tools`: the builders of KeyboardEnglish's data (KeyboardEnglish/AGENTS.md).
- `Packages/KeyboardModules/Tests/KeyboardUITests`: `Evaluation`, the autocorrect scorer (scripts/AGENTS.md, "scripts/eval"), with `TextCheckerSource` (`UITextChecker`) as its baseline keyboard.
- `UITests/`: types through the real extension in the simulator.
- `web/`: the web demo and iikb's page, on KeyboardCore through `TypingEngine`, deployed to iikb.vercel.app. [web/AGENTS.md](web/AGENTS.md)
- `sources/record.ts`: the record source (Bun): a log of every message you send and every field you leave with text you typed, with the host bundle ID the keyboard sends (docs/sources.md). `bun test sources/`.
- `extensions/`: extensions (Bun): `iikb.ts` serves one from `chats({ name, list, read, send })`, and `hex.ts` is the first, your hex sessions as chats (docs/extensions.md). `bun test extensions/`.
- `server/backup.ts`: the backup server (KeyboardStore/AGENTS.md, "Backup").
- `scripts/`: build, install, simulator and measuring scripts. [scripts/AGENTS.md](scripts/AGENTS.md)
- `project.yml`: XcodeGen spec. The `.xcodeproj` is generated, never committed.

## Build and test

Development happens on a Linux box. Simulator builds, tests and screenshots run on a Mac over ssh (`ssh mac`); the iPhone build is made here and installed through the Mac with `scripts/phone`.
- `scripts/mac <command>` syncs the tree to one of the Mac's three slots and runs the command there inside one of the Mac's turns (`turn`, two heavy runs at once across projects). Each slot has its own folder and its own simulators, so up to two runs go at once and the rest wait, and the Mac never runs more than three simulators, counting other projects'.
- A change is checked here first: `scripts/coretest` for KeyboardCore, `scripts/check` for whether everything builds for the iPhone. Then it goes to main and onto the phone with `scripts/phone` as soon as it's ready, since the phone is where changes are tried.
- The simulator is for what only it shows (a layout, a screen, typing through the real extension), one run at a time, and one to three agents test what landed together with `scripts/verify`, which always tests main's last commit.
- Device builds take the team from `Config/Team.xcconfig` (`DEVELOPMENT_TEAM = …`, not committed), which syncing leaves in place.
- To prove a change works, follow the `verify` skill (`.claude/skills/verify`).

Prefer committing straight to main, merge parallel work like a zipper on new projects

TestFlight's public link gets the `beta` branch, a commit of main Bassim OKs: Xcode Cloud builds every push to it (`ci_scripts/`, without private API), and after 24 hours with no push to beta, `.github/workflows/beta.yml` moves it to main's latest. Its testers' note and iikb's description there are `TestFlight/WhatToTest.en-US.txt` and `TestFlight/Description.en-US.txt`; App Store Connect takes the description from main's copy.

```sh
scripts/mac scripts/build                       # sync to the Mac, xcodegen, build for the simulator
scripts/coretest                                # KeyboardCore's tests here on Linux, no Mac (about 25 s)
scripts/check                                   # this checkout built for the iPhone here on Linux, unsigned (a few minutes; one at a time)
scripts/public-review.ts [--all|--text <where>]  # a reviewer reads what iikb shows the public: what changed since origin/main, all of it, or text going elsewhere (stdin)
scripts/format [--check]                        # swift format on every tracked Swift file (.swift-format); --check is what scripts/check and CI run
bun run check                                   # the TypeScript and JavaScript (after bun install): oxlint, oxfmt --check, tsc, bun test, as CI runs it
bun run fix                                     # oxlint's fixes, then oxfmt
scripts/phone [iPad]                            # main's last commit built, signed and installed on the iPhone, or the iPad (--reinstall renews the signing)
scripts/backup <udid>                           # the iPhone's iikb data copied to ~/.local/share/iikb/backup here, never deleted, replaced files kept in versions/ (scripts/phone runs it first)
scripts/restore <udid> [--at <time>|now] [name…]  # the backup put back on the iPhone, all of it or the files named, as it is or as it was at a time; leaves out a copy much smaller than one replaced in the day after an install left iikb a new, empty container (docs/backup.md)
scripts/mac scripts/verify                      # what landed, at once, on one iPhone Duo simulator: package and UI tests, light and dark, shots in shots/raw/verify/
scripts/mac scripts/test                        # KeyboardCore and KeyboardUI package tests on an iOS simulator
scripts/mac scripts/uitest                      # type through the real extension (the iPhone Duo by default)
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
| Behavior follows real events (touches, `textDidChange`, `selectionDidChange`). The keyboard's only timers are key repeat, long-press and a source's 10 s to answer; the app's are in App/Voice/AGENTS.md. Each timer's line says which it is, `// timer: <which>` | `ArchitectureTests` |
| The engine reads the text only from its `TextState`; every edit goes through `TypingEngine.write`; automatic edits replace only characters the keyboard typed (KeyboardCore) | `TextState`, `TextStateStressTests` |
| A correctly typed real word is never changed; word frequencies only choose among what the fingers could have meant (KeyboardCore) | `TypingModelTests`, `scripts/eval` |
| Learning comes only from real events, and nothing in the model runs on a clock (KeyboardCore) | `TypingModelTests` |
| A change that moves the eval's numbers beats them and updates `scripts/eval.expected` in the same commit (scripts) | `scripts/eval` diffs every full run |
| A surface is done when it holds up beside the app that does the same job best (Messages for a chat, Spotlight for search), in screenshots at the phone's size, with its text and small details checked zoomed in. A new kind of input or view gets its own primitive built for its job, never the nearest existing one bent to fit (KeyboardUI, `PanelField`) | `PanelField` has no default; judgment, shots |
| Keys behave and sit as Apple's do, measured in the same simulator (`shots/`, `scripts/shotdiff.py`), never eyeballed; docs/design.md says where and why it moves a key off Apple's geometry | judgment, measured with `scripts/shotdiff.py` |
| The keyboard, the app's preview and Your Taps lay out the same keys (KeyboardCore) | `KeyboardGeometry`, `GeometryTests` |
| The bar's buttons are set out as the top row's keys are (KeyboardCore) | `BarLayoutTests` |
| Gaps between keys take taps (KeyboardUI) | `FirstTapTests` |
| Keycaps use SF Compact from the system font file (KeyboardUI) | judgment: nothing enforces it |
| The keyboard's height comes from Auto Layout content, never a plain height constraint (KeyboardUI) | judgment: nothing enforces it |
| Recording never waits for a model: the `Microphone` knows nothing of `VoiceModel` (App/Voice) | Packages/Voice/Package.swift: VoiceModels is on VoiceCapture, so VoiceCapture can't import it |
| Never a Bluetooth microphone unless one is picked in Settings › Microphone (VoiceCapture) | judgment: nothing enforces it |
| A page opened from another in its tab has one Back, in the Duo's side bar with the tabs on every screen (App) | `backInSideBar(_:)`, `BackTests` |
| A new use of the host app goes through `FullKeyboardViewController.hostApp` (FullKeyboard) | judgment: nothing enforces it |
| Only main's last commit reaches the phone, never mid-dictation, never without backup, never linked below iOS 27.1 (scripts) | `scripts/phone`: builds main in its own worktree, waits for the dictation, refuses without `backup.key` or below 27.1 |
| Restore only after `scripts/phone`: an old build can't read a memory restored without its token | judgment: nothing enforces it |
| No comments unless they record a non-obvious fact | judgment: nothing enforces it |
| Every AGENTS.md names only code that exists, and no file keeps a conflict marker | `ArchitectureTests` |
| A change you'd notice in the app or keyboard carries a `Changelog:` trailer, one short line (App/Settings/ChangelogPage.swift) | judgment: nothing enforces it |
| What the public sees (`TestFlight/`, the README, docs/, the site, Changelog lines, the app's words) passes a reviewer before it goes out | `scripts/hooks/pre-push` runs `scripts/public-review.ts` on every push to main (`git config core.hooksPath scripts/hooks`) |
