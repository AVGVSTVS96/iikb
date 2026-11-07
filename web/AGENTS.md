# web

The web demo and iikb's page.

- `Sources/KeyboardWeb` exports a `Keyboard` class to JavaScript (JavaScriptKit BridgeJS) that forwards to `TypingEngine` the way `FullKeyboardViewController` does, against the page's text field.
- `site/` is iikb's page, built into `web/dist` by `scripts/site`: `page.js` wires it, `themes.js` holds the five themes as `KeyboardCore/Keys/Themes.swift` paints them (keep the two in step), `keyboard.js` draws the hero's keyboard, `wordmark.js` the footer's iikb in keycaps. Numbers come from `copy/facts.json`, the changelog from git through `changes.mjs`. `app.js`, `style.css` and the rest are the WebAssembly demo's (`scripts/web`).
- Deployed to Vercel as `iikb` (iikb.vercel.app) from `web/dist`, built by `scripts/web`.
- `redirect/` is the old `iikb` project, sending iikb.vercel.app there.
