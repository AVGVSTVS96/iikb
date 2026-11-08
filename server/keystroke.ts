import path from "node:path";

import { z } from "zod";

const HOURS_IN_DAY = 24;

const channel = () => ({
  keystrokes: 0,
  chars: 0,
  words: 0,
  backspaces: 0,
  activeMs: 0,
  peakWpm: 0,
  timedChars: 0,
  timedMs: 0,
  inserts: 0,
  hours: Array.from({ length: HOURS_IN_DAY }, () => 0),
  hourChars: Array.from({ length: HOURS_IN_DAY }, () => 0),
  hourActiveMs: Array.from({ length: HOURS_IN_DAY }, () => 0),
});

type Channel = ReturnType<typeof channel>;

interface Day {
  date: string;
  typed: Channel;
  voice: Channel;
}

const TypingHour = z.object({
  day: z.string().regex(/^\d{4}-\d{2}-\d{2}$/u),
  hour: z
    .number()
    .int()
    .min(0)
    .max(HOURS_IN_DAY - 1),
  seconds: z.number(),
  tally: z.object({
    keys: z.number(),
    characters: z.number(),
    words: z.number(),
    deletes: z.number(),
  }),
});

const Transcript = z.object({
  date: z.number(),
  seconds: z.number(),
  text: z.string(),
});

const FOUNDATION_EPOCH = Date.UTC(2001, 0, 1);

const lines = async <T>(schema: z.ZodType<T>, file: string): Promise<T[]> => {
  const text = await Bun.file(file)
    .text()
    .catch(() => "");

  return text.split("\n").flatMap((line) => {
    try {
      const parsed = schema.safeParse(JSON.parse(line));

      return parsed.success ? [parsed.data] : [];
    } catch {
      return [];
    }
  });
};

const two = (n: number) => String(n).padStart(2, "0");

const localDay = (date: Date) =>
  `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())}`;

const add = (counts: number[], index: number, amount: number) => {
  counts[index] = (counts[index] ?? 0) + amount;
};

export const keystroke = async (mirror: string) => {
  const days: Record<string, Day> = {};
  const day = (date: string) => (days[date] ??= { date, typed: channel(), voice: channel() });

  const hours = await lines(TypingHour, path.join(mirror, "group/Library/typing.jsonl"));

  for (const { day: date, hour, seconds, tally } of hours) {
    const { typed } = day(date);
    const ms = Math.round(seconds * 1000);

    typed.keystrokes += tally.keys;
    typed.chars += tally.characters;
    typed.words += tally.words;
    typed.backspaces += tally.deletes;
    typed.activeMs += ms;
    add(typed.hours, hour, tally.keys);
    add(typed.hourChars, hour, tally.characters);
    add(typed.hourActiveMs, hour, ms);
  }

  const transcripts = await lines(Transcript, path.join(mirror, "app/transcripts.jsonl"));
  const total = { words: 0, chars: 0, inserts: 0, lastSeen: 0 };

  for (const { date, seconds, text } of transcripts.filter((said) => said.text !== "")) {
    const at = new Date(FOUNDATION_EPOCH + date * 1000);
    const { voice } = day(localDay(at));
    const count = text.split(/\s+/u).filter((word) => word !== "").length;
    const ms = Math.round(seconds * 1000);

    voice.chars += text.length;
    voice.words += count;
    voice.timedChars += text.length;
    voice.timedMs += ms;
    voice.inserts += 1;
    add(voice.hours, at.getHours(), 1);
    add(voice.hourChars, at.getHours(), text.length);
    add(voice.hourActiveMs, at.getHours(), ms);
    total.words += count;
    total.chars += text.length;
    total.inserts += 1;
    total.lastSeen = Math.max(total.lastSeen, at.getTime());
  }

  return {
    version: 3,
    createdAt: Math.min(
      Date.now(),
      ...Object.keys(days).map((date) => new Date(`${date}T00:00:00`).getTime()),
    ),
    paused: false,
    days,
    wpmHistogram: {},
    sources: total.inserts > 0 ? { iikb: { name: "iikb", ...total } } : {},
    sourceOverrides: {},
  };
};
