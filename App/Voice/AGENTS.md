# Voice typing

A keyboard can't use the microphone (no access, even with Full Access), so voice typing opens the app, which records in the background (`UIBackgroundModes` audio) after starting in the foreground, and hands the text back through the App Group (`Dictation`, KeyboardStore/AGENTS.md).

Voice typing is two steps that never wait on each other, joined by `Listener`: the `Microphone` records, and once you stop, `VoiceModel.write` writes the finished recording down. Recording never waits for a model: the `Microphone` knows nothing of `VoiceModel`, which takes only finished recordings (VoiceCapture, the microphone's module, can't import VoiceModels, which is on it), and the status carries recording and writing apart, so nothing can make a dictation wait to start.

## Opening the app and going back

- The keyboard opens the app by `iikb://dictate` (FullKeyboard/AGENTS.md, "Opening apps and knowing the host").
- The keyboard opens the app only from a host it can bring you back to (`KeyboardHost.returns(to:)`). A share sheet, a notification's reply, Spotlight, the screenshot editor and Photos' markup are no apps: leaving one closes it with what you'd written or drawn, and nothing reopens it (on Bassim's Duo, Nov 8, Telegram's share sheet over a screenshot and a Messages notification's reply both closed this way). There, with the mic off, the keyboard stays and says to turn the mic on in iikb first; with it on, dictation starts in place as anywhere. A keyboard sees only Apple's apps in LaunchServices, so that settles Apple's hosts; a third-party host is that app's share sheet or other extension when its bundle ID extends an app you've typed in (Apple has an extension's ID start with its app's), as `ph.telegra.Telegraph.Share` extends Telegram's. iOS lets no intent start a recording while iikb isn't already running (Apple's answer in developer.apple.com/forums/thread/815725), so Control Center or the Action button can't start it from inside the sheet either.
- `KeyboardHost` names the app you were typing in, in that link, and the app opens it once the microphone is on, with `LSApplicationWorkspace` (all private) or else the app's own link. Where it can't (Split View on the open Duo or an iPad, where iikb takes the other app's place), iikb stays on whatever page it was on.
- The app has no screen of its own for a dictation: the tab bar's accessory (`DictationBar`, where Music shows what's playing) shows the keyboard's recording capsule while you talk, the model writing, or why it couldn't, drawn from `Listener.shown`, so it goes by itself once nothing is recorded, written or failed, and nothing is left to dismiss. A full-screen screen presented on each link (until Nov 8) stuck on its red circle with Close in Split View, since it learned of the dictation only from a callback it could miss.
- `HostApp` sends you back to the app the keyboard named, unless that's iikb itself, which iOS would quit, losing a Parakeet still getting ready; then it keeps the microphone on for Keep Mic On so the next dictation starts from the keyboard without opening the app.
- No Live Activity is needed for this, and iikb starts none: iOS shows its own mic indicator.
- Once recording, the app may keep the microphone running in the background (Keep Mic On, up to Until Turned Off, as Wispr Flow's Flow Sessions do). While it does, the mic beside the suggestions starts and stops dictation with Darwin notifications, never opening the app.

## The microphone and the model

Each is a module of its own in Packages/Voice: the microphone in [VoiceCapture/AGENTS.md](../../Packages/Voice/Sources/VoiceCapture/AGENTS.md), the model in [VoiceModels/AGENTS.md](../../Packages/Voice/Sources/VoiceModels/AGENTS.md). The app writes what a model wrote in your style (`VoiceModel.write(_:for:)`, `DictationWriting`).

## The app's timers

The only ones (rule table, root AGENTS.md):
- Keep Mic On's countdown.
- The second a stop waits for quiet before it cuts.
- One clock reading: a Parakeet that takes over 0.5 s to write a second of silence is taken to be off the Neural Engine and loaded again, up to three times (`VoiceModel`).
