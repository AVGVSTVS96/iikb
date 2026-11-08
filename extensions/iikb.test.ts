import { expect, test } from "bun:test";

import { answer } from "./iikb.ts";
import type { Chats } from "./iikb.ts";

const sent: [string, string, string][] = [];

const message = (index: number) => ({ from: index % 2 === 1 ? "me" : "notes", text: `${index}` });

const notes: Chats = {
  name: "notes",
  list: async () => [{ id: "a:1", name: "One", pinned: true }],
  read: async (chat, after) => ({
    version: `${chat}@${after ?? "now"}`,
    messages: Array.from({ length: 50 }, (_, index) => message(index)),
  }),
  send: async (chat, text, id) => {
    sent.push([chat, text, id]);
  },
};

const call = async (path: string, init?: RequestInit, token?: string) =>
  await answer(notes, new Request(`http://x${path}`, init), token);

const post = async (body: { text: string; id: string }) =>
  await call("/a%3A1", { method: "POST", body: JSON.stringify(body) });

test("the root lists the chats", async () => {
  expect(await (await call("/")).json()).toEqual({
    name: "notes",
    chats: [{ id: "a:1", name: "One", pinned: true }],
  });
});

test("a chat answers its latest messages, waiting with after", async () => {
  expect(await (await call("/a%3A1?after=7")).json()).toEqual({
    version: "a:1@7",
    messages: Array.from({ length: 40 }, (_, index) => message(index + 10)),
  });
});

test("a post sends its trimmed text with its id", async () => {
  const response = await post({ text: " hi ", id: "m1" });

  expect(response.status).toBe(204);
  expect(sent).toEqual([["a:1", "hi", "m1"]]);

  const blank = await post({ text: " ", id: "m2" });

  expect(blank.status).toBe(400);
});

test("a token is checked when there is one", async () => {
  const without = await call("/", {}, "secret");
  const withToken = await call("/", { headers: { authorization: "Bearer secret" } }, "secret");

  expect([without.status, withToken.status]).toEqual([401, 200]);
});

test("an extension's failure answers 502 with its message", async () => {
  const failing: Chats = {
    ...notes,
    list: async () => {
      throw new Error("hex is down");
    },
  };

  const response = await answer(failing, new Request("http://x/"));

  expect([response.status, await response.text()]).toEqual([502, "hex is down"]);
});
