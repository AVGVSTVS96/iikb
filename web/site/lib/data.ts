import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";

import { z } from "zod";

const Facts = z.object({
  accuracy: z.object({
    iikb: z.number(),
    baseline: z.number(),
    phrases: z.number(),
    blockWords: z.number(),
    iikbCurve: z.array(z.number()),
    baselineCurve: z.array(z.number()),
  }),
  emoji: z.number(),
  lexiconWords: z.number(),
  tests: z.object({ core: z.number() }),
  voice: z.object({ writeSeconds: z.number(), speechSeconds: z.number() }),
});

const Change = z.object({ sha: z.string(), at: z.string(), text: z.string() });

const Changes = z.object({
  commits: z.number(),
  since: z.string(),
  head: z.object({ sha: z.string(), at: z.string() }),
  changes: z.array(Change),
});

const repo = path.join(process.cwd(), "../..");

export const facts = Facts.parse(
  JSON.parse(readFileSync(path.join(repo, "copy/facts.json"), "utf-8")),
);

export const changes = Changes.parse(
  JSON.parse(execFileSync("bun", ["web/changes.ts"], { cwd: repo, encoding: "utf-8" })),
);

export const day = (iso: string) =>
  new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" });

export const count = (n: number) => n.toLocaleString("en-US");
