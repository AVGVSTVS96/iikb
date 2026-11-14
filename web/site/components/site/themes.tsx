"use client";

import { useEffect, useRef, useState } from "react";

import { nothing, theme } from "@/lib/bus";
import { themeNames, themes } from "@/lib/themes.js";
import { cn } from "@/lib/utils";

import { Keys } from "./keys";

const NAMES = themeNames;
const TITLES = new Map(Object.entries(themes).map(([k, v]) => [k, v.title]));
const STAY = 3200;

export const Themes = () => {
  const [at, setAt] = useState(0);
  const [held, setHeld] = useState(false);
  const [seen, setSeen] = useState(false);
  const box = useRef<HTMLDivElement>(null);
  const list = useRef<HTMLOListElement>(null);
  const name = NAMES[at] ?? "standard";

  useEffect(() => {
    const el = box.current;

    if (!el) {
      return nothing;
    }

    const io = new IntersectionObserver(([e]) => {
      setSeen(e?.isIntersecting ?? false);
    });

    io.observe(el);

    return () => {
      io.disconnect();
    };
  }, []);

  useEffect(() => {
    theme.send(seen ? name : "");

    const el = list.current;
    const on = el?.children[at];

    if (el && on instanceof HTMLElement && el.scrollWidth > el.clientWidth) {
      el.scrollTo({ left: on.offsetLeft - 20, behavior: "smooth" });
    }
  }, [name, at, seen]);

  useEffect(() => {
    if (held || !seen || matchMedia("(prefers-reduced-motion: reduce)").matches) {
      return nothing;
    }

    const t = setTimeout(() => {
      setAt((i) => (i + 1) % NAMES.length);
    }, STAY);

    return () => {
      clearTimeout(t);
    };
  }, [at, held, seen]);

  return (
    <div
      ref={box}
      className="grid items-center gap-10 md:grid-cols-12 md:gap-6"
      onPointerEnter={() => {
        setHeld(true);
      }}
      onPointerLeave={() => {
        setHeld(false);
      }}
    >
      <ol
        ref={list}
        className="-mx-5 flex gap-x-5 overflow-x-auto px-5 pb-1 [mask-image:linear-gradient(90deg,transparent,#000_20px,#000_calc(100%-40px),transparent)] [scrollbar-width:none] md:col-span-4 md:mx-0 md:grid md:gap-1 md:overflow-visible md:px-0 md:[mask-image:none]"
        aria-label="Themes"
      >
        {NAMES.map((n, i) => (
          <li key={n}>
            <button
              type="button"
              aria-pressed={i === at}
              onClick={() => {
                setAt(i);
              }}
              className={cn(
                "relative py-1 text-left text-[clamp(22px,3vw,40px)] leading-tight font-bold tracking-[-0.04em] whitespace-nowrap text-faint transition-colors hover:text-muted-foreground",
                i === at && "text-foreground hover:text-foreground",
              )}
            >
              {TITLES.get(n)}
              {i === at && seen && !held ? (
                <span
                  key={at}
                  className="absolute right-0 -bottom-0.5 left-0 h-0.5 origin-left rounded-full bg-foreground"
                  style={{ animation: `grow ${STAY}ms linear forwards` }}
                />
              ) : null}
            </button>
          </li>
        ))}
      </ol>
      <div
        data-kb-theme={name}
        className="@container relative overflow-hidden rounded-3xl border bg-muted/60 p-4 md:col-span-8 md:p-10"
      >
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle,var(--border)_1px,transparent_1.3px)] [background-size:22px_22px]" />
        <div className="relative mx-auto max-w-[calc(var(--pt)*402)] overflow-hidden [--pt:min(1.5px,calc(100cqi/402))] rounded-[calc(var(--pt)*46)] shadow-[0_24px_48px_-28px_rgb(0_0_0/0.35)]">
          <Keys />
        </div>
      </div>
    </div>
  );
};
