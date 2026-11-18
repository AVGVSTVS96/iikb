# The space bar trackpad's lines

Holding the space bar and moving up or down moves the caret a line, as Apple's keyboard does, wherever iikb knows how the field wraps. A third-party keyboard is told only the text around the caret (`UITextDocumentProxy`), never where the field wraps, so iikb uses the first of these that works:

1. **The field's accessibility** (`FieldLines`): the field's text and the rectangle of each character. It answers in the simulator, whose test runner turns accessibility on, but not on an iPhone.
2. **A measured field** (`MeasuredField`, [`fields.json`](../Packages/KeyboardModules/Sources/FullKeyboard/Resources/fields.json)): the width the app's field wraps its text at on each Duo screen, and its font, so `HostLayout` wraps the text as the field does. `width` is the text container's, with TextKit's default 5pt padding each side, as UITextView has.
3. **Sentences** everywhere else.

The TestFlight build leaves out the private calls that name the app and read its field, so there up and down always move by sentence.

## Where each row comes from

Every row is in window points at the default text size, with the keyboard up, in a thread's composer holding text, with no reply bar or attachments.

- **Messages** (`com.apple.MobileSMS`), measured: in the iOS 27.3 iPhone Duo simulator, a probe loaded into Messages typed 200 characters into a conversation's composer through `UIKeyInput` and read the text view's frame, insets, font and every character's caret rect; screenshots matched the line breaks on all four screens. SF 17 in the ShortBody style, following Dynamic Type. On the open screens the composer is the thread pane's, so it's narrow; Messages' New Message sheet is laid out differently and has no row.
- **Telegram** (`ph.telegra.Telegraph`), from its source (Telegram-iOS 24638bc6): text from the input panel's left inset + 66 to its width − right inset − 90, with the Duo's safe insets from the table Telegram ships. SF 17, following Dynamic Type while "use system font" is on, its default. Not checked on a screen.
- **Signal** (`org.whispersystems.signal`), from its source (Signal-iOS a690a26d): the folded screens, and open portrait assuming a compact width there; open landscape has no row, since whether Signal splits the screen there wasn't established. SF 17 body. Not checked on a screen.

Other apps move by sentence for now: closed-source apps publish nothing to measure them by, and web pages wrap as each page says.
