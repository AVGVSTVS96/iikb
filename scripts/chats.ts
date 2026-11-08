#!/usr/bin/env bun
/**
 * A stand-in extension for scripts/chattest: three chats of made-up messages, each answering what you send.
 *
 *   PORT=2597 bun scripts/chats.ts
 */
import { type Message, chats } from "../extensions/iikb.ts";

const threads: Record<string, Message[]> = {
  dm: [
    { from: "me", text: "is the new build on my phone?" },
    { from: "hex", text: "Yes, build **611** is on your iPad and the Duo has `598`. Open iikb once and it picks up the rest." },
  ],
  general: [{ from: "hex", text: "Nothing failed overnight. Three topics picked back up." }],
  site: [{ from: "hex", text: "The site's hero folds on its hinge now." }],
};
const names: Record<string, string> = { dm: "DM", general: "General", site: "iikb site" };
let version = 1;
let woken: Array<() => void> = [];

const changed = () => {
  version += 1;
  for (const wake of woken.splice(0)) wake();
};

export default chats({
  name: "hex",
  list: async () =>
    Object.keys(threads).map((id) => ({ id, name: names[id]!, pinned: id !== "site", line: threads[id]!.at(-1)!.text })),
  read: async (chat, after) => {
    if (after === String(version)) await new Promise<void>((wake) => woken.push(wake));
    return { version: String(version), messages: threads[chat] ?? [] };
  },
  send: async (chat, text) => {
    threads[chat]?.push({ from: "me", text });
    changed();
    threads[chat]?.push({ from: "hex", text: "On it. I'll post here when it's done." });
    changed();
  },
});
