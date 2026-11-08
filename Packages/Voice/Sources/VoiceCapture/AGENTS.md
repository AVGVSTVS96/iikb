# VoiceCapture

Voice typing's microphone (`Microphone`), the `Recording` it makes, how the iPhone's microphones hear (`Capture`), and which microphone does (`MicrophoneChoices`). On KeyboardStore alone, so it can't see the models: VoiceModels is on it, and `Listener` joins the two in the app (App/Voice/AGENTS.md).

## The microphone

- The `Microphone` records a dictation as a `Recording` the moment the keyboard asks (by opening `iikb://dictate`, or with its start signal while the microphone is kept on).
- It's Automatic unless a microphone is picked in Settings › Microphone (`PickedMicrophone`, by port UID, or by name for Bluetooth, whose microphone has another UID than its speaker). Automatic is the iPhone's own microphones, or a plugged-in wired headset; never Bluetooth, which would put a speaker or AirPods on a call and drop music to call quality.
- The iPhone's own microphones hear as a front cardioid (`Capture.aim`), which iOS forms from more than one of them, in `.measurement` mode: on one, the folded Duo in portrait lost seconds of speech at a time. Anything else hears in `.default` mode as iOS picks. Each transcript keeps `cardioid` or nothing in `capture`.
- It never runs Apple's voice processing. Voice processing takes the sound from a Bluetooth speaker or AirPlay to the iPhone, pauses music apps and ducks the rest, and gave no sound at all on 19 of 436 dictations, Nov 4 to 7, against 3 of 381 without it (`scripts/voicehealth.py`); each deaf one turned the microphone off, so the next dictation opened the app. So the microphone mixes with whatever plays, wherever it plays, and changes no one's sound. Sound from the iPhone's own speaker is heard along with you.
- Only a picked Bluetooth microphone allows HFP, with `.bluetoothHighQualityRecording` first (AirPods that record at full quality stay off a call), and only while it's connected; picked and away, the iPhone's hears, and a device coming or going restarts the engine onto the right one, in the same recording.
- Listing what's connected sets the session's category without making it active, and never allows Bluetooth's microphone.
- An incoming call that rings doesn't stop it (`setPrefersNoInterruptionsFromSystemAlerts`). When another app takes the microphone (an answered call, say), what was said is written down, the microphone goes off, and it comes back on by itself once iOS says that app is done (`shouldResume`), held by Home's switch if it was. Where iOS won't start it from the background, the next dictation opens the app.

It's resilient, not lossy:
- A route or format change under the engine, or the media services reset, starts the engine again into the same recording; only a failed restart ends the dictation.
- The reset swaps in a new engine even with the microphone off, and a start that fails tries once more on a new engine.
- A failed `open` leaves the audio session inactive.
- The recording takes channel 0 of each buffer, the signal the meter reads.
- A finished recording of a second or more with no sample past 100/32767, or no sound at all, means the input went deaf, so the microphone goes off, Home's switch or not (the next tap opens the app), and the keyboard is told to tap the mic again.
- The microphone stops and starts again by choice only while iikb is in front (`Microphone.inFront`): from the background iOS refuses the new start, and on Nov 6 his microphone went off after each dictation that switched the way it hears. Each `restart` says why (`// restart:`), and a probe ends with `Probe.end`, which leaves iikb running while the microphone is on; coretest's `ArchitectureTests` holds both.
- A dictation being written holds a background task, with an expiration handler, from its stop to its last word.
