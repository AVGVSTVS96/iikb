"use client";

import { useEffect, useRef, useState } from "react";

import { buttonVariants } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { theme as themes } from "@/lib/bus";
import { cn } from "@/lib/utils";

import { GitHub, TestFlight, Wordmark } from "./icons";

const COLUMNS = [
  {
    title: "keyboard",
    links: [
      ["The Duo", "#duo"],
      ["Themes", "#themes"],
      ["Typing", "#typing"],
      ["Voice", "#voice"],
      ["Chats", "#chats"],
    ],
  },
  {
    title: "build",
    links: [
      ["Extensions", "https://github.com/AVGVSTVS96/iikb/blob/main/docs/extensions.md"],
      ["Sources API", "https://github.com/AVGVSTVS96/iikb/blob/main/docs/sources.md"],
      ["Build a keyboard", "https://github.com/AVGVSTVS96/iikb/blob/main/docs/build-a-keyboard.md"],
      ["Privacy", "https://github.com/AVGVSTVS96/iikb/blob/main/docs/privacy.md"],
    ],
  },
  {
    title: "project",
    links: [
      ["GitHub", "https://github.com/AVGVSTVS96/iikb"],
      ["Commits", "https://github.com/AVGVSTVS96/iikb/commits/main"],
      ["Android beta", "https://iikb-android.vercel.app"],
      ["MIT License", "https://github.com/AVGVSTVS96/iikb/blob/main/LICENSE"],
    ],
  },
  {
    title: "thanks",
    links: [
      ["NVIDIA Parakeet", "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3"],
      ["FluidAudio", "https://github.com/FluidInference/FluidAudio"],
      ["Raycast", "https://www.raycast.com/"],
    ],
  },
] as const;

export const Footer = ({ head }: { head: { sha: string; day: string } }) => {
  const canvas = useRef<HTMLCanvasElement>(null);
  const [tray, setTray] = useState("standard");

  useEffect(() => {
    let theme = "standard";
    let mark: { retheme: () => void } | undefined;
    let gone = false;

    const dark = matchMedia("(prefers-color-scheme: dark)");

    const onScheme = () => {
      mark?.retheme();
    };

    const unlisten = themes.listen((name) => {
      theme = name;
      setTray(name);
      mark?.retheme();
    });

    dark.addEventListener("change", onScheme);

    void (async () => {
      const { mountWordmark } = await import("@/lib/wordmark.js");

      if (!gone && canvas.current) {
        mark = mountWordmark(canvas.current, () => theme);
      }
    })();

    return () => {
      gone = true;
      unlisten();
      dark.removeEventListener("change", onScheme);
    };
  }, []);

  return (
    <footer className="border-t bg-secondary">
      <div className="mx-auto w-full max-w-[1200px] px-5 pt-16 md:px-10 md:pt-24 xl:px-0">
        <div className="grid grid-cols-2 gap-x-6 gap-y-10 md:grid-cols-12">
          <div className="col-span-2 grid content-start gap-5 md:col-span-4">
            <Wordmark className="h-8 w-auto self-start justify-self-start" />
            <p className="max-w-[16em] text-[15px] text-muted-foreground">
              The best iOS keyboard. In the world. That’s the bar.
            </p>
            <div className="flex gap-2">
              <a
                href="https://github.com/AVGVSTVS96/iikb"
                className={cn(buttonVariants({ variant: "outline" }), "gap-2")}
              >
                <GitHub className="size-4" />
                GitHub
              </a>
              <a
                href="https://testflight.apple.com/join/xSQ2sdYZ"
                className={cn(buttonVariants({ variant: "outline" }), "gap-2")}
              >
                <TestFlight className="size-4" />
                TestFlight
              </a>
            </div>
          </div>
          {COLUMNS.map((col) => (
            <nav
              key={col.title}
              aria-label={col.title}
              className="grid content-start gap-2.5 text-[15px] md:col-span-2"
            >
              <h3 className="mb-1 font-mono text-xs text-faint">{col.title}</h3>
              {col.links.map(([label, href]) => (
                <a
                  key={label}
                  href={href}
                  className="text-muted-foreground transition-colors hover:text-foreground"
                >
                  {label}
                </a>
              ))}
            </nav>
          ))}
        </div>
        <div
          data-kb-theme={tray}
          className="relative mt-16 rounded-[clamp(20px,3vw,36px)] bg-[var(--kb-bg)] dark:bg-[color-mix(in_srgb,var(--kb-bg)_35%,black)] p-[clamp(12px,2.4vw,32px)] transition-colors md:mt-28"
        >
          <canvas ref={canvas} className="keycaps" role="img" aria-label="iikb, in keycaps" />
          <svg className="keycaps-fallback" viewBox="0 0 147.2 72.7" aria-hidden="true">
            <use href="#wordmark" />
          </svg>
        </div>
        <Separator className="mt-6" />
        <div className="flex flex-col justify-between gap-1.5 py-6 font-mono text-xs text-faint sm:flex-row">
          <span>made on an iPhone Duo · MIT · iOS 26+ · Android beta</span>
          <a
            href={`https://github.com/AVGVSTVS96/iikb/commit/${head.sha}`}
            className="transition-colors hover:text-foreground"
          >
            main @ {head.sha} · {head.day}
          </a>
        </div>
      </div>
    </footer>
  );
};
