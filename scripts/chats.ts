#!/usr/bin/env bun
import { chats } from "../extensions/iikb.ts";
import type { Chat, Message } from "../extensions/iikb.ts";

interface Thread {
  readonly name: string;
  readonly pinned: boolean;
  readonly messages: Message[];
}

const threads = new Map<string, Thread>([
  [
    "dm",
    {
      name: "DM",
      pinned: true,
      messages: [
        { from: "me", text: "is the new build on my phone?" },
        {
          from: "hex",
          text: "Yes, build **611** is on your iPad and the Duo has `598`. Open iikb once and it picks up the rest.",
        },
      ],
    },
  ],
  [
    "general",
    {
      name: "General",
      pinned: true,
      messages: [{ from: "hex", text: "Nothing failed overnight. Three topics picked back up." }],
    },
  ],
  [
    "site",
    {
      name: "iikb site",
      pinned: false,
      messages: [{ from: "hex", text: "The site's hero folds on its hinge now." }],
    },
  ],
]);

let version = 1;
const waiting: (() => void)[] = [];

const changed = () => {
  version += 1;

  for (const wake of waiting.splice(0)) {
    wake();
  }
};

const nextChange = async () => {
  const { promise, resolve } = Promise.withResolvers<undefined>();

  waiting.push(() => {
    resolve(undefined);
  });
  await promise;
};

const chatOf = (id: string, { name, pinned, messages }: Thread): Chat => {
  const latest = messages.at(-1);

  return { id, name, pinned, ...(latest && { line: latest.text }) };
};

export default chats({
  name: "hex",
  list: async () => [...threads].map(([id, thread]) => chatOf(id, thread)),
  read: async (chat, after) => {
    if (after === String(version)) {
      await nextChange();
    }

    return { version: String(version), messages: threads.get(chat)?.messages ?? [] };
  },
  send: async (chat, text) => {
    threads.get(chat)?.messages.push({ from: "me", text });
    changed();
    threads
      .get(chat)
      ?.messages.push({ from: "hex", text: "On it. I'll post here when it's done." });
    changed();
  },
});
