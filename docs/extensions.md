# Extensions

An extension is a service whose chats open from the keyboard's bar, in any app. iikb draws the panel: the chats in a row, the open one's latest messages, and a line the keys and the mic type into, with suggestions and autocorrect as in any field. Return sends. The extension says what chats there are, what's in them, and where your words go.

```
you, in any app
  │ tap Chats in the bar
  ▼
┌──────────────────────────────┐
│ DM  General  Extensions  …   │  chats, pinned first
│ hex: pushed 8a1ed50          │  latest messages
│ ▍Message DM               ⬆  │  the keys type here
│ suggestions             🎙   │
│ q w e r t y u i o p          │
└──────────────────────────────┘
  │ return sends to the open chat
  ▼
iikb ──► your extension ──► wherever it sends
     ◄── replies show as they come
```

## Writing one

One file of TypeScript, on Bun. `extensions/iikb.ts` serves it; you write three functions.

```ts
// extensions/notes.ts
import { chats } from "./iikb.ts";

export default chats({
  name: "notes",
  list: async () => [{ id: "inbox", name: "Inbox", pinned: true }],
  read: async (chat, after) => ({ version: "1", messages: [{ from: "me", text: "buy milk" }] }),
  send: async (chat, text, id) => { /* write it down */ },
});
```

- `list()`: the chats, `{ id, name, line?, pinned? }`. Pinned ones come first.
- `read(chat, after)`: the chat's messages, `{ from, text, pending? }`, oldest first, with a `version` that changes when they do. `from` is `me` for yours. With `after`, hold the answer until the messages are no longer at that version, or about 25 seconds, so a reply reaches the keyboard the moment it's written.
- `send(chat, text, id)`: your words. `id` names the message, so a retry after a lost answer can send it once.

```sh
IIKB_TOKEN=secret PORT=2593 bun extensions/notes.ts
```

It listens on `127.0.0.1`; put it behind `https` on your own devices, for example `tailscale serve --bg --set-path /notes 2593`.

`extensions/hex.ts` is the first: your hex sessions as chats, DM and General first, through hex's voice API.

## Adding one

In the iikb app: Settings › iikb › Extensions › Add Extension, with a name, an address and an optional token. Or open its link, which the app asks about first:

```
iikb://extension?name=hex&url=https%3A%2F%2Fexample.ts.net%2Fhex&token=secret
```

Extensions need Allow Full Access, as Sources do, and the same addresses: `https`, or `http` on your local network.

## What iikb asks

With `Authorization: Bearer <token>` when there's a token.

```
GET  <url>                      → { name, chats: [{ id, name, line?, pinned? }] }
GET  <url>/<chat>?after=<version> → { version, messages: [{ from, text, pending? }] }
POST <url>/<chat> { text, id }  → 2xx once it's sent
```

iikb asks for the open chat's messages again as soon as each answer comes, and stops when the panel closes. One that fails says so in the panel; picking the chat asks again. A message that can't be sent goes back into the line. An extension gets only what you write in its panel, never what you type in the app's field.
