# android

iikb on Android: the same keyboard, KeyboardCore built for Android with the Swift SDK for Android, under a Kotlin input method that draws and touches as iOS's KeyboardUI does. A sideloaded APK, signed with one release key so each build installs over the last.

- `Package.swift`, `Sources/KeyboardAndroid`: the bridge, a dynamic library `libiikb.so` on KeyboardCore alone (no Foundation but FoundationEssentials, for JSON). `Keyboard` forwards to `TypingEngine` as `FullKeyboardViewController` does; `Bridge.swift` holds the JNI functions Kotlin's `Native` declares; `HostDocument` is the app's field as a `TextDocument`, calling back into Kotlin's `Field` and turning the engine's counts in characters into Android's UTF-16. `Frame` is what Kotlin draws, as JSON.
- `Sources/CJNI`: `jni.h` from the NDK as a module.
- `app/`: the Android app (Kotlin, Compose for the app's pages, a plain `View` for the keys).
  - `keyboard/IikbService`: the input method. One event is one batch edit on the field, then a new `Frame`. Suggestions rank on a background thread (`suggestionJob`), as on iOS.
  - `keyboard/KeyboardView`: the bar and keys from the `Frame`, and touches read as `KeyboardView+Touches.swift` reads them; `KeyPainter` paints a key as `KeyView` does; `Glyphs` draws SF Symbols' names with paths of its own (SF Symbols and SF fonts are Apple's alone).
  - `keyboard/Field`: Android's `InputConnection` as the engine reads and edits it. A return the app takes as its action (send, search, go) goes to it as that action.
  - `keyboard/Voice`: voice typing in place, with Android's speech recognizer, typed through the engine as a dictation.
  - `Settings`: the settings, under the names iOS's `SettingsStore` keeps them.
  - `app/`: the app's pages.
- The English data (`KeyboardEnglish/Resources`) goes into the APK's assets uncompressed, and the engine reads it mapped, in place.

## Build

The toolchain is the Swift on the server (`swift --version`) and its Swift SDK for Android of the same version (`swift sdk list`), JDK 25, and the Android SDK in `~/Android/Sdk` with NDK r30 (`ndkVersion` in `app/build.gradle.kts`), linked into the Swift SDK by its `setup-android-sdk.sh`.

```sh
scripts/android                 # the signed release APK, built on the server
scripts/android --emulator      # and installed on the Mac's Android emulator
scripts/android --emulator drive.sh   # then drive.sh run on the Mac, holding the emulator's lock with the install
```

Gradle builds the Swift library first (`swiftLibrary`, arm64 only, 16 KB pages). The release key lives in `~/.local/share/iikb/android` (`release.properties` beside `release.jks`), never in git; a build without it is unsigned.

The server has no hardware virtualization, so the emulator runs on the Mac (`~/Library/Android/sdk`, AVD `iikb`), one at a time, closed when done. Agents share it: drive it only from a script given to `scripts/android --emulator`, or under `lockf /tmp/iikb-emulator.lock` on the Mac, so no other build is installed mid-test.
