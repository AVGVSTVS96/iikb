# android

iikb on Android: the same keyboard, KeyboardCore built for Android with the Swift SDK for Android, under a Kotlin input method that draws and touches as iOS's KeyboardUI does. A sideloaded APK, signed with one release key so each build installs over the last.

- `Package.swift`, `Sources/KeyboardAndroid`: the bridge, a dynamic library `libiikb.so` on KeyboardCore alone (no Foundation but FoundationEssentials, for JSON). `Keyboard` forwards to `TypingEngine` as `FullKeyboardViewController` does; `Bridge.swift` holds the JNI functions Kotlin's `Native` declares; `HostDocument` is the app's field as a `TextDocument`, calling back into Kotlin's `Field` and turning the engine's counts in characters into Android's UTF-16. `Frame` is what Kotlin draws, as JSON. `Clips` holds the clipboard's `ClipboardHistory`, `Gifs` the GIF panel's `GifSearch` and `GifRecents`, `Swatch` a theme's A and B keycaps, `Line` an open chat's `LineDocument`, which `Keyboard.typing` puts in the app's field's place, and `Sources` the sources' `SourceFeed`s.
- `Sources/CJNI`: `jni.h` from the NDK as a module.
- `app/`: the Android app (Kotlin, Compose for the app's pages, a plain `View` for the keys).
  - `keyboard/IikbService`: the input method. One event is one batch edit on the field, then a new `Frame`. Suggestions rank on a background thread (`suggestionJob`), as on iOS.
  - `keyboard/KeyboardView`: the bar and keys from the `Frame`, and touches read as `KeyboardView+Touches.swift` reads them; `KeyPainter` paints a key as `KeyView` does; `Glyphs` draws SF Symbols' names with paths of its own (SF Symbols and SF fonts are Apple's alone).
  - `keyboard/Overlay`: the menu and the panels opened from it (`Menu`, `ClipboardPanel`, `TranscriptsPanel`, `GifPanel`, `LookRows`), drawn with Compose over `KeyboardView`, in the keys' place or, with the keys up, in the bar's. `EmojiPanel` stays on the keys' canvas.
  - `keyboard/Clips`: the clipboard's history, one per process, so the keyboard and the app's Clipboard tab share it. The keyboard keeps a clip by the time Android says it was copied, never one an app marks sensitive or one copied in a password or incognito field.
  - `keyboard/Klipy`, `keyboard/Gifs`: KLIPY's GIFs, its key copied into the assets from `Resources/Keys/klipy.key` at build time (out of git); a tapped GIF goes on the clipboard through the app's `FileProvider`, never into the history.
  - `Services`: the extensions and sources you added, kept in the settings prefs under iOS's names; `iikb://extension` and `iikb://source` links add one from `MainActivity`, after asking.
  - `keyboard/Sources`: what each source is told (docs/sources.md), as iOS's `Sources`: KeyboardCore's `SourceFeed` picks each update, posted off the main thread, and the hint shows in the suggestions' place until tapped. A field's id is new each time the keyboard starts in it, as iOS's `documentIdentifier`; password fields and those asking for no learning (an incognito tab) are never sent.
  - The personal dictionary: Android's `UserDictionary`, which only the keyboard in use may read, stands in for iOS's supplementary lexicon (`Native.learnLexicon`): a word's shortcut is a Text Replacement, a word without one is kept as yours. Settings › Typing opens Android's page for it.
  - `keyboard/Chats`, `keyboard/ChatPanel`: the extensions' chats: listed while the menu is out, the open one asked for again as each answer comes. While a chat is open the keys type into its line, return sends it, and the chats sit as pills in the bar (`KeyboardView.chats`). `iikb://extension` links add one from `MainActivity`; `res/xml/network.xml` allows http only on `localhost` and `.local`, as iOS does.
  - Backup: Android's own Auto Backup, to the phone's Google account, takes the files and settings (`allowBackup`), all but `noBackupFilesDir` (recordings, the voice model) and the cache. iOS's backup server (docs/backup.md) is a personal build's, so the APK, which goes to other people, has none.
  - `keyboard/Field`: Android's `InputConnection` as the engine reads and edits it. A return the app takes as its action (send, search, go) goes to it as that action.
  - `voice/`: voice typing, in the keyboard itself, since Android lets a keyboard use the microphone (see "Voice typing").
  - `keyboard/MicBar`: the bar's mic, as docs/design.md's "The mic" and KeyboardUI's `SuggestionBar` and `MicButton` draw it: the recording capsule (`Waveform`) with its cancel, the stop animation Settings › Appearance picks (Squeeze, Drain or Card), a cancelled recording turned to dust (`Dust`), the waiting dictations' cards (`PendingStack`), and the Record Key in the bottom row when it's on. Its motion runs on `Motion`'s springs and UIKit curves, on a clock that follows Android's animator duration scale, so Developer options › Animator duration scale slows it to watch frame by frame.
  - `Transcripts`: every dictation, one store the keyboard and the app share (see "Voice typing").
  - `Settings`: the settings, under the names iOS's `SettingsStore` keeps them.
  - `Vocabulary`: your Dictionary, iOS's `vocabulary.json`, which `corrected` puts on a dictation.
  - `app/`: the app's pages, in iOS's look (`Style`, `Rows`, `Symbols` for its SF Symbols): `Home`, the Settings list and its pages (`SettingsPages`, `KeyboardPages`, `WritingStyle` with Style in Each App, `Dictionary`, `ServicesPage` for Extensions and Sources). `App`'s `TabBar` is the iPhone's tab bar, a floating capsule of filled glyphs over their names. `Core` asks the engine what they show (`Sources/KeyboardAndroid/App.swift`): the Keyboard pages' preview, a `KeyboardView` on a keyboard of its own over an empty `PreviewField`; Writing Style's examples; which layout settings apply on this screen; taps learned. Settings › Changelog reads `changelog.json`, which the build writes from `Changelog:` trailers as scripts/phone does for iOS.
- The English data (`KeyboardEnglish/Resources`) goes into the APK's assets uncompressed, and the engine reads it mapped, in place.

## Voice typing

As on iOS (App/Voice/AGENTS.md), recording and writing never wait on each other: `Microphone` records 16 kHz mono with Android's speech-recognition source and knows nothing of the models, and once you stop, `Dictation` hands the finished `Recording` to the model, one at a time in the order said, while the next records. What the model heard is styled in Settings › Writing Style for the app it was said for (`Native.written`, the iOS app's `DictationWriting.typed`), then typed through the engine as `KeyboardEvent.dictated`, but only into the field it was said in (`fieldCount`); said elsewhere, it's only kept.

- The model is picked in Settings › Voice (`voiceModel`): Parakeet v3, the default, or Android's own recognizer in Apple's place. Android's never stands in for Parakeet.
- Parakeet v3 is NVIDIA's parakeet-tdt-0.6b-v3, int8, run on the CPU by sherpa-onnx (its Android library from GitHub's releases, `settings.gradle.kts`; one `libsherpa-onnx-jni.so` with ONNX Runtime linked in). It downloads on first use, about 670 MB from Hugging Face at a pinned revision, each file checked against its SHA-256 and resumed where it stopped (`ModelFiles`), into the files Android doesn't back up. A dictation made while it downloads or loads is saved and written once it's ready; the bar shows its card and what it waits for.
- It loads as a dictation starts and is let go once nothing is left to write, since it holds the encoder's 650 MB.
- Silero's voice-activity model downloads with it: a recording in which it hears no one is written as nothing, where Parakeet would write "Yeah." (sherpa-onnx gives no word confidence, which iOS also checks).
- Android's recognizer listens itself rather than writing a finished recording, so its dictations keep no sound.
- `Transcripts` keeps every dictation as a JSON line in `files/transcripts.jsonl` (`Transcript`: id, date in seconds since 1970, the text typed, seconds, whether it was typed, the model, the app's package, what the model heard when the style changed it, and whether it was recovered), and Parakeet's sound beside it as `no_backup/recordings/<id>.wav`, up to 512 MB. A recording without a transcript, left by a keyboard that ended first, is written the next time it starts, and never typed.

## Build

The toolchain is the Swift on the server (`swift --version`) and its Swift SDK for Android of the same version (`swift sdk list`), JDK 25, and the Android SDK in `~/Android/Sdk` with NDK r30 (`ndkVersion` in `app/build.gradle.kts`), linked into the Swift SDK by its `setup-android-sdk.sh`.

```sh
scripts/android                 # the signed release APK, built on the server
scripts/android --emulator      # and installed on the Mac's Android emulator
scripts/android --emulator drive.sh   # then drive.sh run on the Mac, holding the emulator's lock with the install
```

Gradle builds the Swift library first (`swiftLibrary`, arm64 only, 16 KB pages). The release key lives in `~/.local/share/iikb/android` (`release.properties` beside `release.jks`), never in git; a build without it is unsigned.

The server has no hardware virtualization, so the emulator runs on the Mac (`~/Library/Android/sdk`, AVD `iikb`), one at a time, closed when done. Agents share it: drive it only from a script given to `scripts/android --emulator`, or under `lockf -k /tmp/iikb-emulator.lock` on the Mac (without `-k`, lockf deletes the file as it ends, and two runs can each hold a lock on a different file), so no other build is installed mid-test.
