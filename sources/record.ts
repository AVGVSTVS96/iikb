#!/usr/bin/env bun
import { appendFile } from "node:fs/promises";
import { parseArgs } from "node:util";

import { z } from "zod";

const Update = z.object({
  app: z.string().nullish(),
  field: z.string(),
  before: z.string(),
  after: z.string(),
  by: z.enum(["keyboard", "app"]),
  kind: z.string(),
  returnKey: z.string(),
  at: z.string(),
});

export type Update = z.infer<typeof Update>;

const ShortcutsAppOpened = z.object({ app: z.string() });

export type ShortcutsAppOpened = z.infer<typeof ShortcutsAppOpened>;

export const Input = z.union([Update, ShortcutsAppOpened]);

export interface Entry {
  readonly at: string;
  readonly event: "sent" | "typed";
  readonly text: string;
  readonly app?: string;
  readonly kind: string;
  readonly returnKey: string;
}

interface Typed {
  readonly update: Update;
  readonly app: string;
}

export interface State {
  readonly last: Typed | null;
  readonly typedSinceLastEntry: boolean;
  readonly appOpened: string;
}

export interface Recorded {
  readonly state: State;
  readonly entry: Entry | null;
}

export const start: State = { last: null, typedSinceLastEntry: false, appOpened: "" };

const text = (update: Update) => update.before + update.after;

const entry = ({ update, app }: Typed, event: Entry["event"]): Entry => ({
  at: update.at,
  event,
  text: text(update),
  ...(app !== "" && { app }),
  kind: update.kind,
  returnKey: update.returnKey,
});

const inSameField = (last: Typed | null, update: Update, host: string) => {
  if (last?.update.field !== update.field) {
    return false;
  }

  const bothNameTheirApp =
    "app" in update && "app" in last.update && last.app !== "" && host !== "";

  return !bothNameTheirApp || last.app === host;
};

const entryFor = (last: Typed | null, sent: boolean, left: boolean): Entry | null => {
  if (last === null) {
    return null;
  }

  if (sent) {
    return entry(last, "sent");
  }

  return left ? entry(last, "typed") : null;
};

export const record = (state: State, input: Update | ShortcutsAppOpened): Recorded => {
  if (!("field" in input)) {
    return { state: { ...state, appOpened: input.app }, entry: null };
  }

  const { last, typedSinceLastEntry, appOpened } = state;
  const host = "app" in input ? (input.app ?? "") : appOpened;
  const sameField = inSameField(last, input, host);
  const settled = last !== null && typedSinceLastEntry && text(last.update) !== "";
  const sent = settled && sameField && input.by === "app" && text(input) === "";

  return {
    state: {
      last: { update: input, app: host },
      typedSinceLastEntry: input.by === "keyboard" || (!sent && sameField && typedSinceLastEntry),
      appOpened,
    },
    entry: entryFor(last, sent, settled && !sameField),
  };
};

if (import.meta.main) {
  const { values } = parseArgs({
    options: {
      port: { type: "string", default: "2590" },
      out: { type: "string", default: "record.jsonl" },
    },
  });

  const token = process.env.RECORD_TOKEN ?? "";
  let state = start;

  Bun.serve({
    hostname: "127.0.0.1",
    port: Number(values.port),
    fetch: async (request) => {
      if (request.method !== "POST") {
        return new Response(null, { status: 405 });
      }

      if (token !== "" && request.headers.get("authorization") !== `Bearer ${token}`) {
        return new Response(null, { status: 401 });
      }

      const input = Input.safeParse(await request.json());

      if (!input.success) {
        return new Response(z.prettifyError(input.error), { status: 400 });
      }

      const recorded = record(state, input.data);
      ({ state } = recorded);

      if (recorded.entry) {
        await appendFile(values.out, `${JSON.stringify(recorded.entry)}\n`);
      }

      return Response.json({});
    },
  });
}
