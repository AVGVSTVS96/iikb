# web

The web demo and iikb's page.

- `site/` is iikb.vercel.app: Next.js exported as static files (`output: "export"`), every control a shadcn/ui component (`components/ui`, Base UI underneath, added with `bunx shadcn@latest add`), in Tailwind with the tokens in `app/globals.css`. It is a bun workspace of the repo, so `bun install` at the root installs it and `bun run check` lints and typechecks it.
  - `components/site/fold.tsx` is the hero: an iPhone Duo as a 3D rig that the page folds open and turns as it scrolls, its screens drawn live by `lib/keyboard.js` in the app's current look. The open screen spans both halves; the lid's half is a copy of the base's, kept in step while it folds.
  - `lib/themes.js` holds the five themes as `KeyboardCore/Keys/Themes.swift` paints them (keep the two in step); `components/site/keys.tsx` turns them into CSS and draws a keyboard without JavaScript, which the Themes section cycles through. `lib/wordmark.js` draws the footer's iikb in keycaps.
  - Numbers come from `copy/facts.json` and the changelog from git through `changes.ts`, both read at build time (`lib/data.ts`). Screenshots are in `site/public/shots/` (its README says how they are made).
  - Edges are solid 1px `border` in the `--border` token, never a translucent ring or a shadow standing in for one.
- `scripts/site` builds it into `web/dist`, which is deployed to Vercel as `iikb` (`vercel deploy --prod` from `web/dist`). `bun run site` runs it locally.
- `Sources/KeyboardWeb` exports a `Keyboard` class to JavaScript (JavaScriptKit BridgeJS) that forwards to `TypingEngine` the way `FullKeyboardViewController` does, against a page's text field. `demo/` is that WebAssembly demo's page code, built by `scripts/web`.
- `redirect/` is the old `hex-keyboard` project, sending its address to iikb.vercel.app.
