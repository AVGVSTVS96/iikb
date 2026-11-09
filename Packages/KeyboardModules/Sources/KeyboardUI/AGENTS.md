# KeyboardUI

UIKit, the parts any keyboard can build on, with no private API. Keyboard behavior lives in KeyboardCore; this module only draws, plays feedback and forwards events.

## The keys

- `KeyboardView`: one view owns all touches: rollover, slide-off, callouts, long-press accents, the spacebar trackpad, iPad flicks, and swipes.
  - A touch that began on a letter in the letters layer and has gone 0.8 key widths from where it began, past the neighboring key a tap's drift never reaches, stops being a key, collects its path from every coalesced sample, and sends `.swipe` when it lifts or when another finger lands.
  - `TrailView` draws the thin fading line behind it in the theme's prominent color, never touching the keys.
  - The top row takes taps over the bar's bottom edge (docs/design.md, "Where taps land"), so a reach for it types its key, never picking a suggestion or opening a panel.
- `HostText`: the body font most fields draw in, so the trackpad moves the caret a character for as far as the character is wide. Up and down move a sentence for each row of keys the finger crosses (`Sentences`, in KeyboardCore).
- `KeyView`.
- `KeyHaptics`: Apple's keyboard haptic values, played with public Core Haptics on an engine the keyboard owns. While any app records, iOS mutes every app's haptics unless the recording session allows them, so `Listener` does, or Keep Mic On silences the keys.

## The bar

- `SuggestionBar`: Apple's three suggestions, the last giving way to the word's emoji when it has some, as many as fit and the rest a swipe away, the More button at its left, and `MicButton`, a round button always at its right end, set out as the top row's keys are (`BarLayout`, KeyboardCore).
- The mic: tap to dictate (opening the app while its microphone is off), tap again to stop. Nothing in the keyboard turns the microphone off, only Home's switch or Keep Mic On running out.
  - While the app listens the mic grows into a red capsule over the suggestions holding the time and a waveform of the levels it publishes, after a cancel button, which throws away what's being recorded so it's never typed (`Dictation`'s `cancel`; Transcripts still keeps it).
  - Once you stop, dictations still waiting for the model stack as cards, the next with its length, beside what it's doing.
  - Stopping plays the stop animation Settings › Appearance picks (`StopAnimation`): Squeeze (the bars rush into the mic, a ring and a check while it writes), Drain (the red pours into the mic, which glows while it writes) or Card (the recording folds into a card that lifts off the keyboard's top). With the Record Key the bar has no capsule, so each plays across the waveform and the key: Squeeze rushes the bars left toward the key as it squeezes; Drain sinks the bars and runs the key's red down out of it; Card folds the waveform into its card as the key gives. The menu picks it, and the theme, in place (FullKeyboard's `LookStrip`), kept through `SettingsStore` so the app's Appearance page shows it at once. Cancelling turns the recording to dust (`Dust`).
- `BarButton`: the More button, which opens the menu (FullKeyboard's `MenuView`), and on iPad the emoji tool. The emoji panel opens from the emoji key beside space on iPhone, which Settings can take away.
- `EditPill`: cut, copy and paste, out of the More button over the suggestions while the menu is out (`SuggestionBar.Edit`).
- `PanelView`: a panel above the keys or in their place: a `PanelContent`'s results over a back button and the field the keys type into. Each panel names its field (`PanelField`), with no default: `.search` is iOS's one-line search field; a field for anything else is the panel's own view, built for that job as iOS's own field for it is (Chats' `MessageField`, Messages' composer), never search made to look like it. `EmojiPanel` is the emoji one.
- `ChatTabs`: chats as tabs in one capsule of iOS's Liquid Glass (`UIGlassEffect`, which draws inside a keyboard), the open one on a sliding platter, held for iOS's menu of all of them.
- `ChatThread`: a chat's messages as Messages lays them out, each a `MessageBubble` whose text is a non-editable `UITextView`: holding it selects with iOS's handles and edit menu, markdown and bare web addresses are links, a tap opens one through its owner (a keyboard can't open a link itself) and holding one offers Open Link and Copy Link. A message's photos are `ImageBubble`s, decoded at 480 px since iOS ends a keyboard past its memory limit (177 MB on the Duo): a tap opens one as large as the thread (`PhotoView`), and holding one is iOS's context menu, the photo larger over Copy, which copies the original. Decoded photos stay in a capped cache while the keyboard runs, and a file's `width` and `height` give its bubble its shape before it comes. Its other files are their names. With `MessageField` it's a whole chat any keyboard can build on; Chats is iikb's.

## For the app

- `KeyboardPreviewView`: the keyboard as some settings make it look, drawn by the keyboard's own views, for the app's preview.
- `KeycapSwatchView`: a theme's A and B keys, for its picker.
- `TapMapView`: the keyboard drawn with what the touch model learned (Heat, Aim, Accuracy), and `TapCharts` (the heat ramp, a key's close-up and the thumbs' pull arrows).

## iOS facts

- Keycaps use SF Compact, loaded from the system font file, because that is what the system keyboard uses (verified by glyph metrics) and UIKit has no public name for it. It falls back to SF Pro.
- iOS 26 ignores a plain height constraint on the input view; the height comes from Auto Layout content (`keyboardHeightConstraint`).
- A third-party keyboard can't draw above its own area, so top-row pop-ups are clamped into the space above the keys, where they draw over the bar.
- iOS doesn't deliver touches that land on fully transparent pixels of a third-party keyboard. `KeyboardInputView` has an invisible fill (alpha 0.001, pixel-identical in screenshots) so gaps between keys still take taps; `FirstTapTests` checks it.
