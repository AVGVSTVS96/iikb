# Emoji: the bar and the emoji keyboard

## Sub-features

The word being typed, or the one just typed, offers its emoji in the bar, left of the mic: in the last slot, or beside the three suggestions where the bar has room (the open Duo), as many as fit and the rest a swipe left away. They're the emoji picked by hand for that word in `emoji.txt`, or for its singular, where a word can list none, then every emoji whose name or keywords hold the word; what you picked before comes first. A tap replaces the word, or after a space follows it.

The emoji key beside space (on iPad, the bar's emoji tool) puts Apple's emoji keyboard in the keys' place, its "Search Emoji" field in the bar's: pages of emoji scrolling sideways, Frequently Used first, then Apple's categories, over ABC, the nine categories and delete. A category's tap shows its page; ABC brings the letters back; delete deletes in the app. A tap types the emoji into the app and leaves the keyboard up; holding one with skin tones offers them, and the pick is remembered. A tap on the field brings the letters up to type into it, with one row of results between, which finds emoji by CLDR name and keyword; delete with the search empty deletes in the app; the emoji key or return goes back to the pages.

## How to get to it (user POV)

Type "pizza" in any text field with iikb up; or tap the emoji key between 123 and space. Settings › Keyboard › Layout › Emoji Key takes the key away, leaving the bar's emoji.

## Driving it with XCUITest

`VoiceTests` types "pizza" and checks 🍕 sits left of the mic. `PanelTests` (UI, `scripts/looktest`) opens the emoji keyboard from its key, taps Food & Drink and its first emoji, 🍇, into the app, deletes it with the keyboard's delete, searches "pizza" with the keys its field brings up, and goes back to the pages and the letters, screenshotting each step. `AppleEmojiShots` (`scripts/appleemoji`) shoots Apple's own beside it. `EmojiTests` and `PanelTests` (package) pin the bar's matches, the pages, the search's ranking, skin tones, Apple's measured geometry, and what the keys do while a panel is open.
