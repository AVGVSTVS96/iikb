# Site screenshots

Simulator captures of main at b284ece1 (Nov 9), from the `shots` workflow (`.github/workflows/shots.yml`, `scripts/parity`), with made-up content. Each comes in `-light` and `-dark`, scaled to 804 px wide (402 pt at 2x).

| Asset | Capture | Crop |
| --- | --- | --- |
| `phone-menu-*` | `menu-*.png` | the whole screen |
| `phone-chat-*` | `panel-chat-*.png` | the whole screen |
| `kb-typing-*`, `kb-voice-*`, `kb-clipboard-*`, `kb-transcripts-*` | `keyboard-typing`, `dictation-listening`, `clipboard`, `transcripts` | from the keyboard's top edge, y = 1602 of 2622 |
| `kb-gif-*`, `kb-emoji-*` | `gif-search`, `emoji-search` | from the panel's top edge, y = 1170 of 2622 |

When the app's look changes, run the workflow again and crop the same way, keeping the names.
