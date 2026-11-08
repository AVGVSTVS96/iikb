#!/usr/bin/env bun
/**
 * hex: talk to your hex sessions from the keyboard, DM and General first, through hex's voice API.
 *
 *   HEX_URL=http://127.0.0.1:8790 [VOICE_TOKEN=…] IIKB_TOKEN=secret bun extensions/hex.ts
 */
import { chats } from "./iikb.ts";

const HEX = process.env["HEX_URL"] ?? "http://127.0.0.1:8790";
const PINNED = ["DM", "General"];

interface Thread { id: string; name: string; where: string; line?: string; at: string }
interface Turn { from: "me" | "hex"; text: string }
interface Chat { version: number; turns: Turn[]; waiting: { text: string }[] }

const hex = async <T>(path: string, init?: RequestInit): Promise<T> => {
  const token = process.env["VOICE_TOKEN"];
  const response = await fetch(HEX + path, {
    ...init,
    headers: { "content-type": "application/json", ...(token && { authorization: `Bearer ${token}` }) },
  });
  if (!response.ok) throw new Error((await response.text()) || `hex answered ${response.status}`);
  return (response.status === 204 ? undefined : await response.json()) as T;
};

const thread = (id: string) => `/tasks/${encodeURIComponent(id)}/chat`;

export default chats({
  name: "hex",

  list: async () => {
    const { tasks } = await hex<{ tasks: Thread[] }>("/tasks");
    const rank = (row: Thread) => (PINNED.includes(row.where) ? PINNED.indexOf(row.where) : PINNED.length);
    return tasks
      .toSorted((a, b) => rank(a) - rank(b) || b.at.localeCompare(a.at))
      .map((row) => ({ id: row.id, name: row.name, line: row.line, pinned: PINNED.includes(row.where) }));
  },

  read: async (chat, after) => {
    const { version, turns, waiting } = await hex<Chat>(thread(chat) + (after ? `?after=${after}` : ""));
    return {
      version: String(version),
      messages: [
        ...turns.map((turn) => ({ from: turn.from, text: turn.text })),
        ...waiting.map((sent) => ({ from: "me", text: sent.text, pending: true })),
      ],
    };
  },

  send: (chat, text, id) => hex(thread(chat), { method: "POST", body: JSON.stringify({ text, key: `app-${id}` }) }),
});
