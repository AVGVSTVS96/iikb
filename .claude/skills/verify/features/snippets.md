# Snippets and Quicklinks

## Sub-features

A keyword typed at a word's start in any app ("!addr") becomes its snippet, Immediately or After Delimiter (Settings › Snippets › Expansion), never inside a word and only when the keyboard typed it. After the prefix the bar offers the keywords that go on from it. `{cursor}` puts the caret there; `{argument}`s are asked for first in the form panel, a field at a time, Next then Insert. The Snippet key (Custom Keys › Bottom Row, off by default) types the prefix. The Snippets panel (its menu shelf, or an action) types a tapped snippet, holding one offers Copy and Edit, and its field's `plus` is Create Snippet, which keeps the selection or the field's text with Full Access. The Quicklinks panel types a link, or opens it from its hold menu. Both are made in the app's Settings › Snippets and Quicklinks.

## How to get to it (user POV)

Type a keyword, or tap the Snippet key, in any field; More, then the Snippets shelf's name; or add Snippets and Quicklinks to Custom Keys › Actions.

## Driving it with XCUITest

`SnippetTypingTests` (UI, `SUITE=SnippetTypingTests scripts/paneltest`, shots in `shots/raw/panels/`) seeds two snippets and a quicklink (`-iikbSnippets`), types `!addr` from the Snippet key, fills a greeting's argument in the form, and taps and holds a snippet in the panel opened from the menu. `SnippetPagesTests` drives the app's pages. `SnippetTests` and `CustomKeysTests` (package, `scripts/coretest`) pin expansion, the fill, Create Snippet and the key's place in the bottom row.
