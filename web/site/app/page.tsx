import { ArrowRight, ArrowUpRight } from "lucide-react";

import { Chart } from "@/components/site/chart";
import { Code } from "@/components/site/code";
import { Fold } from "@/components/site/fold";
import { Footer } from "@/components/site/footer";
import { Header } from "@/components/site/header";
import { Android, GitHub, TestFlight } from "@/components/site/icons";
import { Body, Section } from "@/components/site/section";
import { KeyboardShot, Phone } from "@/components/site/shot";
import { Themes } from "@/components/site/themes";
import { Styles } from "@/components/site/voice";
import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { changes, count, day, facts } from "@/lib/data";
import { cn } from "@/lib/utils";

const REPO = "https://github.com/AVGVSTVS96/iikb";

const Big = ({ value, unit, className }: { value: string; unit: string; className?: string }) => (
  <b
    className={cn(
      "block text-[clamp(64px,9vw,120px)] leading-[0.9] font-bold tracking-[-0.055em]",
      className,
    )}
  >
    {value}
    <small className="ml-[0.04em] text-[0.42em] tracking-[-0.02em]">{unit}</small>
  </b>
);

const Fact = ({ value, unit, label }: { value: string; unit?: string; label: string }) => (
  <div className="grid content-start gap-2 border-t pt-4">
    <dt className="text-[clamp(34px,3.6vw,48px)] leading-none font-bold tracking-[-0.045em]">
      {value}
      {unit === undefined ? null : (
        <small className="text-[0.55em] tracking-[-0.02em]">{unit}</small>
      )}
    </dt>
    <dd className="text-[15px] text-pretty text-muted-foreground">{label}</dd>
  </div>
);

const TILES = [
  {
    name: "kb-gif",
    height: 968,
    title: "GIFs",
    line: "search as you type",
    alt: "GIF search for cat, results above the keys",
  },
  {
    name: "kb-emoji",
    height: 968,
    title: "Emoji",
    line: `${count(facts.emoji)}, by name`,
    alt: "Emoji search for pizza",
  },
  {
    name: "kb-clipboard",
    height: 680,
    title: "Clipboard",
    line: "links, pins, images",
    alt: "Clipboard history above the keys, links shown with their site’s icon",
  },
  {
    name: "kb-transcripts",
    height: 680,
    title: "Transcripts",
    line: "every dictation, kept",
    alt: "Recent transcripts above the keys",
  },
];

const DOCS = [
  ["Extensions", "chats in the keyboard", `${REPO}/blob/main/docs/extensions.md`],
  ["Sources", "hints from your own service", `${REPO}/blob/main/docs/sources.md`],
  ["Build a keyboard", "on iikb’s typing engine", `${REPO}/blob/main/docs/build-a-keyboard.md`],
] as const;

const GET = [
  {
    label: "iPhone · iPad · iOS 26+",
    title: "TestFlight beta",
    href: "https://testflight.apple.com/join/xSQ2sdYZ",
    cta: "Join",
    icon: TestFlight,
    primary: true,
  },
  {
    label: "Android 9+ · APK",
    title: "Android beta",
    href: "https://iikb-android.vercel.app",
    cta: "Download",
    icon: Android,
    primary: false,
  },
  {
    label: "MIT · open source",
    title: "Build it yourself",
    href: `${REPO}#build-it-yourself`,
    cta: "GitHub",
    icon: GitHub,
    primary: false,
  },
];

export default function Page() {
  const { accuracy, voice, tests, lexiconWords } = facts;

  return (
    <>
      <Header />
      <main id="top">
        <Fold />

        <Section id="themes" index="01" title="themeable to the keycap.">
          <Body>
            <Themes />
          </Body>
        </Section>

        <Section id="typing" index="02" title="it learns your thumbs.">
          <Body className="grid gap-10">
            <div className="grid items-start gap-10 sm:grid-cols-2 sm:gap-6">
              <div className="grid content-start gap-2">
                <Big value={String(accuracy.iikb)} unit="%" className="mb-3 text-pick" />
                <p className="text-[17px]">words right with off-target thumbs</p>
                <p className="font-mono text-xs text-muted-foreground">
                  {accuracy.baseline}% nearest key + Apple’s spell checker
                </p>
              </div>
              <div className="grid content-start gap-2">
                <Big value="88.2" unit="%" className="mb-3" />
                <p className="text-[17px]">
                  swipes read right the first time, level with Apple’s keyboard
                </p>
                <p className="font-mono text-xs text-muted-foreground">
                  Apple’s: 88.0% on the same 400 real swipes
                </p>
              </div>
            </div>
            <Card>
              <CardContent className="px-5 pt-3 md:px-7">
                <Chart
                  ours={accuracy.iikbCurve}
                  theirs={accuracy.baselineCurve}
                  block={accuracy.blockWords}
                />
              </CardContent>
            </Card>
            <p className="font-mono text-xs text-muted-foreground">
              {count(accuracy.phrases)} phrases typed twice with simulated off-target taps.{" "}
              <a
                href={`${REPO}/blob/main/PROGRESS.md`}
                className="text-foreground underline decoration-border underline-offset-4 hover:decoration-foreground whitespace-nowrap"
              >
                How it’s measured
              </a>
            </p>
          </Body>
        </Section>

        <Section id="voice" index="03" title="say it. it writes like you.">
          <Body className="grid gap-12">
            <dl className="grid gap-6 sm:grid-cols-3">
              <Fact
                value={String(voice.writeSeconds)}
                unit=" s"
                label={`to write ${voice.speechSeconds} s of talking, on an iPhone`}
              />
              <Fact value="$0" label="no word limit, no account" />
              <Fact value="on‑device" label="NVIDIA Parakeet, on the iPhone’s Neural Engine" />
            </dl>
            <div className="grid grid-cols-1 items-stretch gap-6 md:grid-cols-2">
              <KeyboardShot
                name="kb-voice"
                height={680}
                alt="iikb recording: a red bar with the time and a live waveform above the keys"
              />
              <Styles />
            </div>
          </Body>
        </Section>

        <Section id="menu" index="04" title="everything, a tap away.">
          <Body className="grid items-start gap-6 md:grid-cols-[minmax(0,4fr)_minmax(0,6fr)]">
            <div className="md:sticky md:top-24">
              <Phone
                name="phone-menu"
                alt="iikb’s menu: cut, copy and paste, then shelves of clipboard links, transcripts, GIFs and themes"
              />
            </div>
            <div className="grid gap-4 sm:grid-cols-2 md:gap-6">
              {TILES.map((t) => (
                <Card key={t.name} className="gap-4 pb-0">
                  <CardHeader className="gap-0.5">
                    <CardTitle className="text-[17px] tracking-[-0.02em]">{t.title}</CardTitle>
                    <p className="font-mono text-xs text-muted-foreground">{t.line}</p>
                  </CardHeader>
                  <KeyboardShot
                    name={t.name}
                    height={t.height}
                    alt={t.alt}
                    className="mt-auto px-2 [&_img]:rounded-b-none"
                  />
                </Card>
              ))}
            </div>
          </Body>
        </Section>

        <Section
          id="chats"
          index="05"
          title="plug your chats into the keyboard."
          lede="Read, dictate and send from any app. A chat service is one TypeScript file."
        >
          <Body className="grid items-start gap-10 md:grid-cols-[minmax(0,4fr)_minmax(0,6fr)] md:gap-6">
            <div className="md:sticky md:top-24">
              <Phone
                name="phone-chat"
                alt="A chat open in iikb: tabs for each chat, the messages, and a message box"
              />
            </div>
            <div className="grid gap-8">
              <Card className="gap-0 py-0">
                <div className="flex justify-between border-b px-4 py-3 font-mono text-xs text-muted-foreground">
                  <span>extensions/notes.ts</span>
                  <span>bun</span>
                </div>
                <Code />
              </Card>
              <nav aria-label="Build on iikb" className="grid">
                {DOCS.map(([title, line, href]) => (
                  <a
                    key={title}
                    href={href}
                    className="group grid grid-cols-[minmax(0,1fr)_auto_auto] items-center gap-4 border-t py-4 last:border-b"
                  >
                    <b className="text-[17px] font-medium">{title}</b>
                    <span className="font-mono text-xs text-muted-foreground max-sm:hidden">
                      {line}
                    </span>
                    <ArrowUpRight className="size-4 text-faint transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5 group-hover:text-foreground" />
                  </a>
                ))}
              </nav>
            </div>
          </Body>
        </Section>

        <Section id="changelog" index="06" title="shipping daily.">
          <Body className="grid gap-10">
            <dl className="grid grid-cols-2 gap-6 md:grid-cols-4">
              <Fact value={count(changes.commits)} label="commits" />
              <Fact value={day(changes.since)} label="first commit" />
              <Fact value={count(tests.core)} label="tests" />
              <Fact value={count(lexiconWords)} label="words known" />
            </dl>
            <Card className="gap-0 py-0">
              <ol>
                {changes.changes.slice(0, 8).map((c, i) => (
                  <li key={`${c.sha}${i}`}>
                    {i > 0 ? <Separator /> : null}
                    <div className="grid grid-cols-[minmax(0,1fr)_auto] items-baseline gap-x-4 gap-y-1 px-4 py-3.5 md:grid-cols-[72px_minmax(0,1fr)_auto] md:px-5">
                      <time className="font-mono text-xs text-faint max-md:order-2">
                        {day(c.at)}
                      </time>
                      <span className="text-[15px] max-md:col-span-2 max-md:order-1 md:text-base">
                        {c.text}
                      </span>
                      <a
                        href={`${REPO}/commit/${c.sha}`}
                        className="justify-self-end font-mono text-xs text-faint hover:text-pick max-md:order-3"
                      >
                        {c.sha}
                      </a>
                    </div>
                  </li>
                ))}
              </ol>
            </Card>
            <a
              href={`${REPO}/commits/main`}
              className={cn(
                buttonVariants({ variant: "ghost" }),
                "-ml-2.5 justify-self-start font-mono text-xs text-muted-foreground",
              )}
            >
              Every commit
              <ArrowRight data-icon="inline-end" />
            </a>
          </Body>
        </Section>

        <Section id="get" index="07" title="get iikb.">
          <Body className="grid gap-6">
            <div className="grid gap-4 md:grid-cols-3">
              {GET.map((g) => (
                <Card key={g.title} className="gap-3 px-6 py-6 md:min-h-[220px]">
                  <Badge variant="secondary" className="font-mono font-normal">
                    {g.label}
                  </Badge>
                  <h3 className="text-[clamp(24px,2.4vw,30px)] leading-[1.05] font-bold tracking-[-0.035em]">
                    {g.title}
                  </h3>
                  <a
                    href={g.href}
                    className={cn(
                      buttonVariants({ variant: g.primary ? "default" : "outline", size: "lg" }),
                      "mt-auto h-10 gap-2 self-start px-4",
                    )}
                  >
                    <g.icon className="size-4" />
                    {g.cta}
                  </a>
                </Card>
              ))}
            </div>
            <p className="font-mono text-xs text-muted-foreground">
              English for now, swipe typing included.
            </p>
          </Body>
        </Section>
      </main>
      <Footer head={{ sha: changes.head.sha, day: day(changes.head.at) }} />
    </>
  );
}
