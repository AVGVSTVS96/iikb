#!/usr/bin/env bun
import { z } from "zod";

import { chats } from "./iikb.ts";

const HEX = process.env.HEX_URL ?? "http://127.0.0.1:8790";
const PINNED = ["DM", "General"];

const Tasks = z.object({
  tasks: z.array(
    z.object({
      id: z.string(),
      name: z.string(),
      where: z.string(),
      line: z.string().optional(),
      at: z.string(),
    }),
  ),
});

const Chat = z.object({
  version: z.number(),
  turns: z.array(z.object({ from: z.enum(["me", "hex"]), text: z.string() })),
  waiting: z.array(z.object({ text: z.string() })),
});

const hex = async (path: string, init?: RequestInit) => {
  const token = process.env.VOICE_TOKEN ?? "";

  const response = await fetch(HEX + path, {
    ...init,
    headers: {
      "content-type": "application/json",
      ...(token !== "" && { authorization: `Bearer ${token}` }),
    },
  });

  if (!response.ok) {
    const said = await response.text();

    throw new Error(said === "" ? `hex answered ${response.status}` : said);
  }

  return response;
};

const read = async <T>(schema: z.ZodType<T>, path: string) => {
  const response = await hex(path);

  return schema.parse(await response.json());
};

const thread = (id: string) => `/tasks/${encodeURIComponent(id)}/chat`;

const rank = (where: string) => {
  const pinned = PINNED.indexOf(where);

  return pinned === -1 ? PINNED.length : pinned;
};

export default chats({
  name: "hex",

  list: async () => {
    const { tasks } = await read(Tasks, "/tasks");

    return tasks
      .toSorted((a, b) => rank(a.where) - rank(b.where) || b.at.localeCompare(a.at))
      .map((row) => ({
        id: row.id,
        name: row.name,
        ...(row.line !== undefined && { line: row.line }),
        pinned: PINNED.includes(row.where),
      }));
  },

  read: async (chat, after) => {
    const { version, turns, waiting } = await read(
      Chat,
      thread(chat) + (after === undefined || after === "" ? "" : `?after=${after}`),
    );

    return {
      version: String(version),
      messages: [
        ...turns.map((turn) => ({ from: turn.from, text: turn.text })),
        ...waiting.map((sent) => ({ from: "me", text: sent.text, pending: true })),
      ],
    };
  },

  send: async (chat, text, id) => {
    await hex(thread(chat), { method: "POST", body: JSON.stringify({ text, key: `app-${id}` }) });
  },
});
