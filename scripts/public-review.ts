#!/usr/bin/env bun
import { $ } from "bun";
import { z } from "zod";

interface Piece {
  readonly where: string;
  readonly text: string;
}

const SURFACES: readonly (readonly [RegExp, string])[] = [
  [
    /^TestFlight\/WhatToTest\./u,
    "TestFlight's What to Test, which every tester reads when a build arrives, people who joined from the public link included",
  ],
  [
    /^TestFlight\/Description\./u,
    "TestFlight's description of iikb, on the public link's page and in the TestFlight app",
  ],
  [/^README\.md$/u, "the README, the front page of github.com/AVGVSTVS96/iikb"],
  [/^docs\/privacy\.md$/u, "iikb's privacy policy, linked from TestFlight"],
  [/^docs\/(?!design\.md$).+\.md$/u, "a guide on GitHub, linked from the README"],
  [/^web\/site\/(?:index\.html|page\.js|keyboard\.js)$/u, "iikb.vercel.app, iikb's page"],
  [/^copy\//u, "the words and numbers iikb.vercel.app shows"],
  [/^App\/Settings\/changelog\.tsv$/u, "the app's Changelog page"],
];

const APP_CODE = /^(?:App|Controls|Keyboard|Packages\/[^/]+\/Sources)\/.+\.swift$/u;
const WORDS = /"[^"\n]*[A-Za-z][^"\n]* [^"\n]*"/u;
const NO_COMMIT = "0000000000000000000000000000000000000000";
const TRAILERS = "--format=%(trailers:key=Changelog,valueonly)";
const MESSAGES = "--format=%B%n---";

const IPHONE = (await Bun.file(new URL("iphone-paths.txt", import.meta.url)).text())
  .split("\n")
  .filter((line) => line !== "" && !line.startsWith("#"));

const CHANGELOGS = [
  {
    where:
      "Changelog lines for iPhone: the iOS app's Changelog page and the changelog on iikb.vercel.app",
    paths: IPHONE,
  },
  {
    where:
      "Changelog lines for Android: the Android app's Changelog page, read by people on Android",
    paths: [
      "android",
      "Packages/KeyboardModules/Sources/KeyboardCore",
      "Packages/KeyboardModules/Sources/KeyboardEnglish",
    ],
  },
] as const;

const Verdict = z.object({
  ok: z.boolean(),
  findings: z.array(z.object({ where: z.string(), problem: z.string(), instead: z.string() })),
});

const Output = z.object({ structured_output: Verdict });

const PROMPT = `iikb is an open-source iOS keyboard and app, with an Android port, built in public at github.com/AVGVSTVS96/iikb by Bassim Shahidy. What follows is about to go out where the public reads it: testers who joined TestFlight from a public link, people visiting iikb.vercel.app, developers reading the repo on GitHub. Each piece says where it shows up.

Review it as the people who will read it there. Bassim's bar for iikb's public words: they speak for iikb to strangers, never to or about him personally; nothing private (people, accounts, phone numbers, addresses, health, legal or money matters); no frustration or anger; and few words ("so many words on pages" annoys him). copy/MESSAGING.md is the project's guide to its public words, and the repo in your working directory is there to check any claim against.

Pass it when every piece is fit to go out. For each thing that isn't, say where it is, what's wrong, and the text you'd put there instead.`;

const surfaceOf = (path: string) => SURFACES.find(([pattern]) => pattern.test(path))?.[1];

const addedLines = async (base: string, head: string, path: string, keep: RegExp) => {
  const diff = await $`git diff ${base} ${head} -- ${path}`.text();

  return diff
    .split("\n")
    .filter((line) => line.startsWith("+") && !line.startsWith("+++"))
    .map((line) => line.slice(1).trim())
    .filter((line) => keep.test(line) && !line.startsWith("//"))
    .join("\n");
};

const pieceOf = async (base: string, head: string, path: string): Promise<Piece | null> => {
  const surface = surfaceOf(path);

  if (surface !== undefined) {
    return {
      where: `${path}, shown in ${surface}`,
      text: await $`git diff ${base} ${head} -- ${path}`.text(),
    };
  }

  if (APP_CODE.test(path) && !path.includes("/Tests/")) {
    const text = await addedLines(base, head, path, WORDS);

    return text === ""
      ? null
      : { where: `${path}: lines added to code the app or keyboard runs`, text };
  }

  if (path === "project.yml") {
    const text = await addedLines(base, head, path, /UsageDescription|DisplayName/u);

    return text === ""
      ? null
      : { where: "project.yml: an iOS permission prompt or the app's name", text };
  }

  return null;
};

const changed = async (base: string, head: string): Promise<Piece[]> => {
  const files = (await $`git diff --name-only ${base} ${head}`.text())
    .split("\n")
    .filter((path) => path !== "");

  const found = await Promise.all(files.map(async (path) => await pieceOf(base, head, path)));
  const pieces = found.filter((piece) => piece !== null);

  const changelogs = await Promise.all(
    CHANGELOGS.map(async ({ where, paths }) => ({
      where,
      text: (await $`git log ${TRAILERS} ${base}..${head} -- ${paths}`.text()).trim(),
    })),
  );

  pieces.push(...changelogs.filter(({ text }) => text !== ""));

  if (pieces.length === 0) {
    return [];
  }

  return [
    ...pieces,
    {
      where: "commit messages, public on GitHub",
      text: await $`git log ${MESSAGES} ${base}..${head}`.text(),
    },
  ];
};

const everything = async (): Promise<Piece[]> => {
  const files = (await $`git ls-files`.text())
    .split("\n")
    .filter((path) => surfaceOf(path) !== undefined);

  const pieces = await Promise.all(
    files.map(async (path) => ({
      where: `${path}, shown in ${surfaceOf(path)}`,
      text: await Bun.file(path).text(),
    })),
  );

  const changelogs = await Promise.all(
    CHANGELOGS.map(async ({ where, paths }) => ({
      where: `${where}, newest first`,
      text: await $`git log -n 200 ${TRAILERS} -- ${paths}`.text(),
    })),
  );

  return [...pieces, ...changelogs];
};

const review = async (pieces: readonly Piece[]) => {
  const work = pieces.map(({ where, text }) => `## ${where}\n\n${text.trim()}`).join("\n\n");

  const run = Bun.spawn(
    [
      "claude",
      "-p",
      "--safe-mode",
      "--model",
      "opus",
      "--effort",
      "high",
      "--no-session-persistence",
      "--tools",
      "Read,Grep,Glob",
      "--allowedTools",
      "Read,Grep,Glob",
      "--output-format",
      "json",
      "--json-schema",
      JSON.stringify(z.toJSONSchema(Verdict, { target: "draft-7" })),
    ],
    {
      stdin: new TextEncoder().encode(`${PROMPT}\n\n# The work\n\n${work}`),
      stdout: "pipe",
      stderr: "inherit",
    },
  );

  const out = await new Response(run.stdout).text();
  const parsed = Output.safeParse(JSON.parse(out === "" ? "{}" : out));

  if ((await run.exited) !== 0 || !parsed.success) {
    console.error(
      `public review: the reviewer didn't answer (exit ${run.exitCode})\n${out.slice(0, 2000)}`,
    );

    return false;
  }

  const { ok, findings } = parsed.data.structured_output;

  for (const { where, problem, instead } of findings) {
    console.error(`\n${where}\n  ${problem}\n  instead: ${instead}`);
  }

  console.error(
    ok ? "public review: fit to go out" : "\npublic review: fix the above before it goes out",
  );

  return ok;
};

const pushed = async (lines: string) => {
  const ranges = lines
    .split("\n")
    .map((line) => line.split(" "))
    .filter(
      ([, local, ref]) => ref === "refs/heads/main" && local !== undefined && local !== NO_COMMIT,
    );

  const found = await Promise.all(
    ranges.map(async ([, local = "", , remote = NO_COMMIT]) => {
      const base =
        remote === NO_COMMIT
          ? (await $`git merge-base ${local} origin/main`.text()).trim()
          : remote;

      return await changed(base, local);
    }),
  );

  return found.flat();
};

const piecesFor = async ([first, second]: readonly string[]): Promise<Piece[]> => {
  if (first === "--text") {
    return [{ where: second ?? "public text", text: await Bun.stdin.text() }];
  }

  if (first === "--all") {
    return await everything();
  }

  if (first === "--pre-push") {
    return await pushed(await Bun.stdin.text());
  }

  return await changed(first ?? "origin/main", second ?? "HEAD");
};

const pieces = await piecesFor(Bun.argv.slice(2));

process.exit(pieces.length === 0 || (await review(pieces)) ? 0 : 1);
