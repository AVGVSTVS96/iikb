import { expect, test } from "bun:test";

import { type Chats, answer } from "./iikb.ts";

const sent: Array<[string, string, string]> = [];
const notes: Chats = {
  name: "notes",
  list: async () => [{ id: "a:1", name: "One", pinned: true }],
  read: async (chat, after) => ({
    version: `${chat}@${after ?? "now"}`,
    messages: Array.from({ length: 50 }, (_, index) => ({ from: index % 2 ? "me" : "notes", text: `${index}` })),
  }),
  send: async (chat, text, id) => {
    sent.push([chat, text, id]);
  },
};

const call = (path: string, init?: RequestInit, token?: string) => answer(notes, new Request(`http://x${path}`, init), token);

test("the root lists the chats", async () => {
  expect(await (await call("/")).json()).toEqual({ name: "notes", chats: [{ id: "a:1", name: "One", pinned: true }] });
});

test("a chat answers its latest messages, waiting with after", async () => {
  const { version, messages } = await (await call("/a%3A1?after=7")).json();
  expect(version).toBe("a:1@7");
  expect(messages.length).toBe(40);
  expect(messages.at(-1)).toEqual({ from: "me", text: "49" });
});

test("a post sends its trimmed text with its id", async () => {
  const response = await call("/a%3A1", { method: "POST", body: JSON.stringify({ text: " hi ", id: "m1" }) });
  expect(response.status).toBe(204);
  expect(sent).toEqual([["a:1", "hi", "m1"]]);
  expect((await call("/a%3A1", { method: "POST", body: JSON.stringify({ text: " " , id: "m2" }) })).status).toBe(400);
});

test("a token is checked when there is one", async () => {
  expect((await call("/", {}, "secret")).status).toBe(401);
  expect((await call("/", { headers: { authorization: "Bearer secret" } }, "secret")).status).toBe(200);
});

test("an extension's failure answers 502 with its message", async () => {
  const failing = { ...notes, list: async () => Promise.reject(new Error("hex is down")) };
  const response = await answer(failing, new Request("http://x/"));
  expect([response.status, await response.text()]).toEqual([502, "hex is down"]);
});
