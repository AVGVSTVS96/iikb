import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

const root = path.join(import.meta.dir, "..");
const RESOURCES = "Packages/KeyboardModules/Sources/KeyboardEnglish/Resources";
const THEMES = "Packages/KeyboardModules/Sources/KeyboardCore/Keys/Themes.swift";
const PHRASES = "Packages/KeyboardModules/Tests/KeyboardUITests/phrases.txt";
const LEXICON_ENTRY_BYTES = 8;

const read = (file: string) => readFileSync(path.join(root, file), "utf-8");

const lines = (file: string) =>
  read(file)
    .split("\n")
    .filter((line) => line !== "");

const groups = (text: string, pattern: RegExp, where: string) => {
  const found = pattern.exec(text)?.groups;

  if (!found) {
    throw new Error(`${where} no longer says ${pattern}`);
  }

  return found;
};

const said = (file: string, pattern: RegExp) => groups(read(file), pattern, file);

const number = (value: string | undefined) => {
  const parsed = Number(value);

  if (value === undefined || Number.isNaN(parsed)) {
    throw new Error(`"${value}" isn't a number`);
  }

  return parsed;
};

const evals = lines("scripts/eval.expected");

const evalLine = (prefix: string) => {
  const line = evals.find((candidate) => candidate.startsWith(prefix));

  if (line === undefined) {
    throw new Error(`scripts/eval.expected has no "${prefix}"`);
  }

  return line;
};

const total = (keyboard: string) => {
  const line = evalLine(`EVAL thumbs keyboard=${keyboard} total:`);
  const where = `scripts/eval.expected's ${keyboard} total`;

  return {
    words: number(groups(line, /words=(?<n>\d+)/u, where).n),
    raw: number(groups(line, /raw=(?<n>[\d.]+)%/u, where).n),
    autocorrect: number(groups(line, /autocorrect=(?<n>[\d.]+)%/u, where).n),
  };
};

const curve = (keyboard: string) =>
  [...evalLine(`EVAL thumbs keyboard=${keyboard} per 500 words`).matchAll(/\/(?<n>[\d.]+)%/gu)].map(
    (match) => number(match.groups?.n),
  );

const themeCount = said(THEMES, /enum ThemeName[^{]*\{\s*case (?<names>[^\n]+)/u).names?.split(
  ",",
).length;

const themes = [...read(THEMES).matchAll(/case \.\w+: "(?<title>[^"]+)"/gu)]
  .map((match) => match.groups?.title ?? "")
  .slice(0, themeCount);

const settings = read(
  "Packages/KeyboardModules/Sources/KeyboardCore/Typing/KeyboardSettings.swift",
);

const strengths = [
  ...settings
    .slice(settings.indexOf("public var strength"))
    .matchAll(/case \.(?<name>\w+): (?<share>[\d.]+)/gu),
].flatMap(({ groups: strength }) =>
  strength?.name === "off" ? [] : [{ name: strength?.name, share: number(strength?.share) }],
);

const emojiWords = lines(`${RESOURCES}/emoji.txt`).filter(
  (line) => (line.split("\t")[1] ?? "") !== "",
).length;

const emoji = lines(`${RESOURCES}/emoji-search.txt`).filter((line) => !line.startsWith("#")).length;

const lexicon = readFileSync(path.join(root, RESOURCES, "en.lexicon"));

if (lexicon.subarray(0, 4).toString() !== "HXL1") {
  throw new Error("en.lexicon isn't HXL1");
}

let lexiconWords = 0;

for (
  let offset = LEXICON_ENTRY_BYTES;
  offset + LEXICON_ENTRY_BYTES <= lexicon.length;
  offset += LEXICON_ENTRY_BYTES
) {
  if (lexicon[offset + 1] !== 0) {
    lexiconWords += 1;
  }
}

const count = (dir: string, pattern: RegExp) => {
  let found = 0;

  for (const file of new Bun.Glob("**/*.swift").scanSync(path.join(root, dir))) {
    found += read(path.join(dir, file)).match(pattern)?.length ?? 0;
  }

  return found;
};

const phrases = lines(PHRASES);
const baseline = total("baseline");
const learning = total("learning");
const phraseWords = phrases.join(" ").split(/\s+/u).length;

if (baseline.words !== learning.words || learning.words !== 2 * phraseWords) {
  throw new Error("the thumbs run isn't the phrase set typed twice");
}

const speech = said("PROGRESS.md", /writes (?<speech>[\d.]+) s of speech in (?<write>[\d.]+) s/u);
const shares = strengths.map((strength) => strength.share);

const facts = {
  name: "iikb",
  site: "https://iikb.vercel.app",
  repo: "https://github.com/AVGVSTVS96/iikb",
  license: "MIT",
  iosMinimum: number(said("project.yml", /iOS: "(?<version>\d+)/u).version),
  accuracy: {
    source: "scripts/eval.expected, EVAL thumbs (KeyboardUITests/Evaluation.biasedThumbs)",
    phrases: phrases.length,
    words: learning.words,
    blockWords: number(
      groups(evalLine("EVAL thumbs keyboard=learning per"), /per (?<n>\d+) words/u, "eval").n,
    ),
    baseline: baseline.autocorrect,
    iikb: learning.autocorrect,
    baselineCurve: curve("baseline"),
    iikbCurve: curve("learning"),
  },
  missesToMoveAKey: 3,
  themes,
  haptics: {
    levels: strengths.length,
    softest: Math.min(...shares),
    strongest: Math.max(...shares),
  },
  emoji,
  emojiWords,
  lexiconWords,
  tests: {
    core: count("Packages/KeyboardModules/Tests/KeyboardCoreTests", /@Test\b/gu),
    ui:
      count("Packages/KeyboardModules/Tests/KeyboardUITests", /@Test\b/gu) +
      count("UITests", /func test\w*\(/gu),
    coreSeconds: number(
      said("PROGRESS.md", /runs KeyboardCore's tests on Linux in about (?<seconds>\d+) s/u).seconds,
    ),
  },
  voice: {
    downloadMB: number(
      said(
        "Packages/Voice/Sources/VoiceModels/VoiceModel.swift",
        /Downloads once, about (?<mb>\d+) MB/u,
      ).mb,
    ),
    speechSeconds: number(speech.speech),
    writeSeconds: number(speech.write),
  },
};

said(
  "Packages/KeyboardModules/Tests/KeyboardCoreTests/TypingModelTests.swift",
  /(?<test>theSameMissThreeTimesRunningMovesTheKey)/u,
);

writeFileSync(path.join(import.meta.dir, "facts.json"), `${JSON.stringify(facts, null, 2)}\n`);

console.log(JSON.stringify(facts, null, 2));
