import { expect, test } from "bun:test";

import { Input, record, start } from "./record.ts";
import type { Entry, ShortcutsAppOpened, State, Update } from "./record.ts";

let clock = 0;

const update = (before: string, by: Update["by"] = "keyboard", field = "a"): Update => {
  clock += 1;

  return {
    field,
    before,
    after: "",
    by,
    kind: "text",
    returnKey: "default",
    at: `2026-10-20T07:00:${String(clock).padStart(2, "0")}.000Z`,
  };
};

const after = (...inputs: (Update | ShortcutsAppOpened)[]): State => {
  let state = start;

  for (const input of inputs) {
    ({ state } = record(state, input));
  }

  return state;
};

const entries = (...updates: Update[]): Pick<Entry, "event" | "text">[] => {
  const out: Pick<Entry, "event" | "text">[] = [];
  let state = start;

  for (const next of updates) {
    const { state: nextState, entry } = record(state, next);
    state = nextState;

    if (entry) {
      out.push({ event: entry.event, text: entry.text });
    }
  }

  return out;
};

test("text the app empties after you typed it was sent", () => {
  expect(
    entries(update("", "app"), update("hey"), update("hey you"), update("", "app"), update("n")),
  ).toEqual([{ event: "sent", text: "hey you" }]);
});

test("a field you leave with text you typed was typed", () => {
  expect(
    entries(
      update("", "app"),
      update("note"),
      update("note", "app", "b"),
      update("x", "keyboard", "b"),
    ),
  ).toEqual([{ event: "typed", text: "note" }]);
});

test("the caret moving keeps what you typed", () => {
  expect(entries(update("", "app"), update("hey"), update("he", "app"), update("", "app"))).toEqual(
    [{ event: "sent", text: "he" }],
  );
});

test("text you didn't type is not yours", () => {
  expect(
    entries(update("draft from before", "app"), update("", "app"), update("", "app", "b")),
  ).toEqual([]);
});

test("text you erase yourself was not sent", () => {
  expect(entries(update("", "app"), update("ugh"), update(""), update("", "app"))).toEqual([]);
});

test("an entry keeps the app Shortcuts said you opened, and the time you last typed it", () => {
  const typed = update("on my way");
  const state = after({ app: "Messages" }, update("", "app"), typed, { app: "" });

  expect(record(state, update("", "app")).entry).toEqual({
    at: typed.at,
    event: "sent",
    text: "on my way",
    app: "Messages",
    kind: "text",
    returnKey: "default",
  });
});

test("text typed after you left the app has no app", () => {
  const state = after({ app: "Messages" }, { app: "" }, update("", "app"), update("hi"));

  expect(record(state, update("", "app")).entry?.app).toBeUndefined();
});

test("an update from a build that sends no app parses without one, and a Shortcuts post as one", () => {
  expect("app" in Input.parse(update("hi"))).toBe(false);
  expect(Input.parse({ app: "Messages" })).toEqual({ app: "Messages" });
  expect(Input.safeParse({ field: "a" }).success).toBe(false);
});
