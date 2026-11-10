# FullKeyboard

iikb's own keyboard, on KeyboardUI and KeyboardStore, and the only target that links `KeyboardArbiter`, the private API.

- `FullKeyboardViewController`: the extension's principal class. Forwards events to the engine, renders, runs ranking jobs.
- Its panels besides `EmojiPanel`:
  - `GifPanel` searches KLIPY (`Klipy`, its key in `Resources/Keys/klipy.key`, kept out of git; one request out at a time, `GifSearch`) and puts a tapped GIF on the clipboard (`GifClipboard`), since a keyboard can only type text, or drags a held one into the app's field.
  - `ClipboardPanel` shows what `ClipboardStore` kept of what you copied, links as one-line badges (`LinkBadge`) in a section ahead of the rest, read when the keyboard appears and when the panel opens, on a queue of its own, never the main thread. iOS refuses that read silently unless Settings › Apps › iikb › Paste from Other Apps is Allow.
  - `TranscriptsPanel` shows what you dictated, from the copy the app writes for it (`TranscriptFeed`), in `ClipboardPanel`'s rows.
- `MenuView`: the menu in the keys' place (docs/design.md, "The menu"), with cut, copy and paste in the bar (`SuggestionBar.Edit`, through `UIPasteboard` and the engine). Its shelves are the clipboard, Transcripts and GIF panels themselves, laid out as their one-row results; a shelf's name opens its panel.
- `ClipPreview`: what holding a clip, a transcript or a GIF shows, as its context menu's preview.
- `ClipTitle`: how a clip's row, card, link badge and preview write it by its kind: a link as its site's icon (`LinkIcons`) and site, its badge adding how long ago; an address, a number or a color after its glyph.
- `Sources`: the sources you add in the app (docs/sources.md). Each gets the field you type in as JSON, off the main thread, and its hint stands in for the suggestions until tapped. Only with Full Access, never password or code fields.
- `Chats` and `ChatPanel`: the chats of the extensions you add in the app (docs/extensions.md), from the menu's Chats shelf (`ChatShelf`), with Full Access. A chat grows the keyboard once and fills it with the keys down, on iOS's own glass edge to edge as the keys are, the chats as KeyboardUI's `ChatTabs` in the bar (and atop the chat with the keys up); tapping its `MessageField` brings the keys up under it at the same height. Its paperclip brings `ChatPhotos`' grid of your newest photos up in the keys' place instead (`PhotoGrid`, PhotoKit with the access the app asked for, which the keyboard shares; iOS's own picker stays on "Loading…" inside a keyboard): each photo tapped is attached in the box, made a JPEG of at most 2048 pixels without being decoded whole, and kept beside the unsent messages (`UnsentStore.keep`) until its message is sent. Paste in the box attaches copied photos the same way. The messages are KeyboardUI's `ChatThread`, real text you hold to select and copy, whose links open through the host app. While it's open the engine types into its `LineDocument` in place of the app's field, with a send return key, so suggestions, autocorrect and the mic work there; return sends to the open chat.
- A panel opened from the menu (Clipboard, Transcripts, GIFs) fills the keys' place until you tap its field, which brings the keys up with it above them; back steps out a level at a time, to the menu. The open chat's messages are asked for again as each answer comes (the extension holds the request until they change), only while the panel is open; switching back to a chat shows its last answer at once, and the list and each chat's last 40 messages are kept on disk as the keyboard goes away, so a new keyboard shows them at once while it asks again. Sources aren't told what you write there. A chat open as the keyboard goes away opens again in the next keyboard in the same field, with its line, keys and drafts, so dictating into it can go through the app and back. It's kept on disk (`KeptChat`), not in memory: iOS ends the keyboard's process while the app is in front, and at its memory limit, 177 MB on the Duo (its JetsamEvent reports, Nov 9).
- `KeyboardHost`: the app the keyboard is in, from the moment it appears (docs/sources.md, "Which app you're typing in").

## Opening apps and knowing the host

- Apps can't be opened from a keyboard through public API; iikb walks the responder chain to the host's `UIApplication`, as Wispr Flow and others do.
- Since iOS 26.4 a keyboard's own properties don't name the app you were typing in, and a keyboard can't reopen it. So `KeyboardHost` matches its host's process ID to the app UIKit's keyboard arbiter names, which the C target `KeyboardArbiter` switches on as the keyboard loads, and names it in the dictation link (App/Voice/AGENTS.md).

Host identity is keyboard-wide context, not voice typing's alone: `KeyboardHost` resolves it on appearance and UIKit text/selection events, and whatever gains from knowing the app takes it from there.
- Sources receive its bundle ID (`app`, empty when unknown).
- Language ranking learns per-app word and next-word counts over shared vocabulary.
- Emoji choices and GIF recents prefer this app's picks.
- Typing stats count each hour under its app.
- Dictation is written in the Writing Style picked for it, else the default (`KeyboardSettings.dictation(in:)`): the app styles it for the transcript's app, and the engine sets its capitals for `TypingEngine.app`.
- Voice typing returns to it, and leaves for the app only when it is an app iOS can reopen, never a share sheet or another host leaving would close (`KeyboardHost.returns(to:)`, LaunchServices), and each transcript keeps the app it was typed into (`Dictation.host`), for Transcripts and Stats › Dictation.

Counts and picks stay local; the GIF service receives no host ID. App identity cannot establish clipboard origin or a conversation. A new use goes through `FullKeyboardViewController.hostApp`, never a lookup of its own.
