#!/usr/bin/env bun
import { $ } from "bun";
import { z } from "zod";

const swiftTests = /(?:^|\/)(?:UITests|Tests)\/.*\.swift$/u;

const kinds = [
  {
    files: swiftTests,
    instead: "a raised time limit hides a slow test: make the test wait on what it waits for",
    kind: "raised",
    pattern: /\bexecutionTimeAllowance\s*=/u,
  },
  {
    files: /^scripts\/(?!landmines\.ts$)/u,
    instead: "a test that passes on a rerun is a flake to fix, not to retry",
    kind: "retries",
    pattern: /-retry-tests-on-failure|-test-iterations|-run-tests-until-failure/u,
  },
  {
    files: swiftTests,
    instead:
      "a sleep guesses how long real work takes and fails under load: wait on the element or the event (waitForExistence, an expectation, a predicate)",
    kind: "sleeps",
    pattern: /\b(?:Thread\.sleep|Task\.sleep|usleep|sleep)\(/u,
  },
] as const;

const allowancesFile = "scripts/landmines.json";

const allowances = z
  .partialRecord(z.enum(["raised", "retries", "sleeps"]), z.record(z.string(), z.int().min(1)))
  .parse(await Bun.file(allowancesFile).json());

const tracked = (await $`git ls-files`.text()).split("\n").filter(Boolean);

const checked = kinds.flatMap(({ files, instead, kind, pattern }) =>
  [
    ...new Set([
      ...tracked.filter((file) => files.test(file)),
      ...Object.keys(allowances[kind] ?? {}),
    ]),
  ].map(async (file) => {
    const text = tracked.includes(file) ? await Bun.file(file).text() : "";
    const hits = text.split("\n").flatMap((line, at) => (pattern.test(line) ? [at + 1] : []));
    const allowed = allowances[kind]?.[file] ?? 0;

    if (hits.length > allowed) {
      return `${file}:${hits.join(",")}: ${hits.length} ${kind}, at most ${allowed} allowed in ${allowancesFile}; ${instead}.`;
    }

    if (hits.length < allowed) {
      return `${file}: now ${hits.length} ${kind}; lower its ${kind} entry in ${allowancesFile} to ${hits.length}, or remove it at 0.`;
    }

    return "";
  }),
);

const problems = (await Promise.all(checked)).filter(Boolean);

for (const problem of problems) {
  console.error(problem);
}

process.exitCode = problems.length === 0 ? 0 : 1;
