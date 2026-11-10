#!/usr/bin/env bun
import { deflateSync } from "node:zlib";

import { chats } from "../extensions/iikb.ts";
import type { Chat, Message } from "../extensions/iikb.ts";

const port = process.env.PORT ?? "2593";
const file = (name: string) => `http://localhost:${port}/files/${name}`;

const chunk = (kind: string, body: Uint8Array) => {
  const data = Buffer.concat([Buffer.from(kind), body]);
  const size = Buffer.alloc(4);
  const crc = Buffer.alloc(4);

  size.writeUInt32BE(body.length);
  crc.writeUInt32BE(Bun.hash.crc32(data));

  return Buffer.concat([size, data, crc]);
};

const png = (width: number, height: number, row: (y: number) => readonly number[]) => {
  const header = Buffer.alloc(13);

  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header.set([8, 2, 0, 0, 0], 8);

  const rows = Array.from({ length: height }, (_, y) =>
    Buffer.from([0, ...Array.from({ length: width }, () => row(y)).flat()]),
  );

  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(Buffer.concat(rows), { level: 6 })),
    chunk("IEND", new Uint8Array()),
  ]);
};

const SEA = 0.62;

const view = png(1200, 900, (y) => {
  const t = y / 900;

  if (t < SEA) {
    return [Math.trunc(70 + 160 * t), Math.trunc(90 + 90 * t), Math.trunc(170 - 40 * t)];
  }

  const u = (t - SEA) / (1 - SEA);

  return [Math.trunc(30 + 20 * u), Math.trunc(70 + 10 * u), Math.trunc(110 - 30 * u)];
});

const files = new Map([
  ["/files/view.png", new Response(view, { headers: { "Content-Type": "image/png" } })],
  [
    "/files/boarding-pass.pdf",
    new Response("%PDF-1.4\n%%EOF\n", { headers: { "Content-Type": "application/pdf" } }),
  ],
]);

interface Thread {
  readonly name: string;
  readonly line: string;
  readonly pinned: boolean;
  readonly messages: Message[];
}

const threads = new Map<string, Thread>([
  [
    "notes",
    {
      name: "Notes",
      line: "Pick up the **film** at 5",
      pinned: true,
      messages: [
        { from: "me", text: "Remind me what's left for Saturday" },
        {
          from: "notes",
          text: "Two things: pick up the **film** at 5, and send the photos to the group.",
        },
        { from: "me", text: "And the café?" },
        { from: "notes", text: "Booked for 11. It's the one on `Valencia`." },
        { from: "notes", text: "Want me to set a reminder?" },
      ],
    },
  ],
  [
    "design",
    {
      name: "Design",
      line: "The new bar looks right",
      pinned: false,
      messages: [
        { from: "design", text: "The new bar looks right in dark mode." },
        { from: "me", text: "Nice, ship it" },
      ],
    },
  ],
  [
    "trip",
    {
      name: "Trip",
      line: "Flights are booked",
      pinned: false,
      messages: [
        { from: "trip", text: "Flights are booked. *Window seats* both ways." },
        {
          from: "me",
          text: "",
          files: [
            { name: "boarding-pass.pdf", url: file("boarding-pass.pdf"), type: "application/pdf" },
          ],
        },
        {
          from: "trip",
          text: "The view from the room",
          files: [
            {
              name: "view.png",
              url: file("view.png"),
              type: "image/png",
              width: 1200,
              height: 900,
            },
          ],
        },
      ],
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

const chatOf = (id: string, { name, line, pinned }: Thread): Chat => ({ id, name, line, pinned });

const extension = chats({
  name: "Notes",
  list: async () => [...threads].map(([id, thread]) => chatOf(id, thread)),
  read: async (chat, after) => {
    if (after === String(version)) {
      await nextChange();
    }

    return { version: String(version), messages: threads.get(chat)?.messages ?? [] };
  },
  send: async (chat, text) => {
    const thread = threads.get(chat);

    thread?.messages.push({ from: "me", text });
    changed();

    setTimeout(() => {
      thread?.messages.push({ from: chat, text: `Got it: “${text}”.` });
      changed();
    }, 1200);
  },
});

export default {
  ...extension,
  fetch: async (request: Request) =>
    files.get(new URL(request.url).pathname)?.clone() ?? (await extension.fetch(request)),
};
