"use client";

import { ArrowRight } from "lucide-react";
import { useEffect, useRef } from "react";

import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import { dictation, duoTheme, nothing } from "@/lib/bus";
import { cn } from "@/lib/utils";

import { Android, GitHub, TestFlight } from "./icons";

const H = 702;
const W = 490;

const POSES = [
  { id: "folded", title: "folded", size: "466 × 678", at: 0, theme: "standard" },
  { id: "open", title: "open", size: "951 × 669", at: 0.5, theme: "mechanical" },
  { id: "turned", title: "turned", size: "669 × 951", at: 1, theme: "classic" },
] as const;

const clamp = (v: number) => Math.min(1, Math.max(0, v));
const ease = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2);
const span = (p: number, a: number, b: number) => ease(clamp((p - a) / (b - a)));
const mix = (a: number, b: number, t: number) => a + (b - a) * t;

const poseAt = (p: number) => {
  if (p < 0.28) {
    return "folded";
  }

  return p < 0.75 ? "open" : "turned";
};

const Bodies = () => (
  <>
    <i className="body" />
    <i className="body" />
    <i className="body" />
    <i className="body" />
    <i className="body" />
  </>
);

const Screen = ({ first }: { first: string }) => (
  <>
    <div className="status">
      <b>9:41</b>
      <i />
    </div>
    <div className="demo" data-demo>
      <div className="thread" data-thread aria-live="off">
        <p className="in">{first}</p>
      </div>
      <div className="field empty" data-field>
        <span />
        <i className="caret" />
      </div>
      <div className="kb" aria-hidden="true" />
    </div>
  </>
);

export const Fold = () => {
  const stageRef = useRef<HTMLElement>(null);

  useEffect(() => {
    const stage = stageRef.current;

    if (!stage) {
      return nothing;
    }

    const q = (s: string) => {
      const el = stage.querySelector(s);

      if (!(el instanceof HTMLElement)) {
        throw new TypeError(`fold: no ${s}`);
      }

      return el;
    };

    const pin = q(".pin");
    const hero = q(".hero-copy");
    const slot = q("[data-spot]");
    const duo = q("[data-duo]");
    const rig = q("[data-rig]");
    const lid = q("[data-lid]");
    const dial = q("[data-dial]");
    const view = q("[data-view]");
    const mirror = q("[data-mirror]");
    const cover = q("[data-cover]");

    let open = 0;
    let turn = 0;
    let dirty = true;
    let aim = { x: 0, y: 0 };
    const lean = { x: 0, y: 0 };
    let live = false;
    let raf = 0;
    let shown = "";
    let gone = false;
    let dictate: ((text: string) => Promise<void>) | undefined;

    const sync = new MutationObserver(() => {
      dirty = true;

      if (open > 0.002 && open <= 0.999) {
        wake();
      }
    });

    sync.observe(view, { subtree: true, childList: true, characterData: true, attributes: true });

    const progress = () => {
      const r = stage.getBoundingClientRect();

      return clamp(-r.top / Math.max(1, r.height - innerHeight));
    };

    const frame = () => {
      raf = 0;
      const p = progress();
      open = span(p, 0.1, 0.46);
      turn = span(p, 0.6, 0.9);
      lean.x += (aim.x - lean.x) * 0.08;
      lean.y += (aim.y - lean.y) * 0.08;
      const box = pin.getBoundingClientRect();
      const s = slot.getBoundingClientRect();
      const pad = innerWidth < 640 ? 16 : 40;
      const room = { w: box.width - pad * 2, h: box.height - dial.offsetHeight - pad * 2 - 64 };
      const fit = { w: mix(s.width, room.w, open), h: mix(s.height, room.h, open) };
      const wide = mix(W, 2 * W, open);
      const a = (Math.PI / 2) * turn;
      const cos = Math.cos(a);
      const sin = Math.sin(a);

      const scale =
        0.94 *
        Math.min(fit.w / (wide * cos + H * sin), fit.h / (wide * sin + H * cos)) *
        (1 - 0.22 * Math.sin(Math.PI * open));

      const x = mix(s.left - box.left + s.width / 2, box.width / 2, open);
      const y = mix(s.top - box.top + s.height / 2, 64 + pad + room.h / 2, open);
      duo.style.transform = `translate(${x}px, ${y}px) scale(${scale})`;
      const shift = (W / 2) * (1 - open);
      const left = shift - W;
      duo.style.setProperty("--left", `${left}px`);
      duo.style.setProperty("--wide", `${shift + Math.max(0, -W * Math.cos(Math.PI * open)) - left}px`);
      duo.style.setProperty("--turn", `${90 * turn}deg`);
      duo.hidden = false;
      const narrow = innerWidth < 760;
      const rx = mix(narrow ? 6 : 9, 5, open) - lean.y * 8;
      const ry = mix(narrow ? -14 : -22, -8, open) * (1 - turn * 0.6) + lean.x * 10;
      rig.style.transform = `perspective(3600px) rotateX(${rx}deg) rotateY(${ry}deg) rotateZ(${90 * turn}deg) translateX(${(W / 2) * (1 - open)}px)`;
      lid.style.transform = `rotateY(${-180 * (1 - open)}deg)`;
      duo.classList.toggle("whole", open > 0.999);
      view.classList.toggle("turned", turn >= 0.5);
      view.classList.toggle("swap", Math.abs(turn - 0.5) < 0.04);

      if (dirty && open > 0.002 && open <= 0.999) {
        dirty = false;
        mirror.innerHTML = view.innerHTML;
        mirror.className = view.className;
      }

      hero.style.opacity = String(1 - span(p, 0.03, 0.22));
      hero.style.transform = `translateY(${-40 * span(p, 0.03, 0.22)}px)`;
      hero.inert = p > 0.15;
      const now = poseAt(p);

      if (now !== shown) {
        shown = now;
        const look = POSES.find((pose) => pose.id === now)?.theme ?? "standard";
        pin.dataset.kbTheme = look;

        if (live) {
          duoTheme.send(look);
        }

        for (const b of dial.children) {
          b.setAttribute(
            "aria-selected",
            String(b instanceof HTMLElement && b.dataset.pose === now),
          );
        }
      }

      if (live && (Math.abs(aim.x - lean.x) > 0.001 || Math.abs(aim.y - lean.y) > 0.001)) {
        raf = requestAnimationFrame(frame);
      }
    };

    const wake = () => {
      if (!raf) {
        raf = requestAnimationFrame(frame);
      }
    };

    const onPointer = (e: PointerEvent) => {
      if (e.pointerType === "mouse") {
        aim = { x: e.clientX / innerWidth - 0.5, y: e.clientY / innerHeight - 0.5 };
      }

      wake();
    };

    const unlisten = dictation.listen((text) => {
      void dictate?.(text);
    });

    const seen = new IntersectionObserver(([e]) => {
      live = e?.isIntersecting ?? false;

      duoTheme.send(live ? (pin.dataset.kbTheme ?? "") : "");

      wake();
    });

    seen.observe(stage);
    addEventListener("pointermove", onPointer, { passive: true });
    addEventListener("scroll", wake, { passive: true });
    addEventListener("resize", wake);
    wake();

    void (async () => {
      const { mountKeyboard } = await import("@/lib/keyboard.js");

      if (gone) {
        return;
      }

      const folded = mountKeyboard(cover.querySelector("[data-demo]"), {
        active: () => open < 0.5,
      });

      mountKeyboard(view.querySelector("[data-demo]"), { active: () => open >= 0.5 });
      ({ dictate } = folded);
    })();

    return () => {
      gone = true;
      cancelAnimationFrame(raf);
      sync.disconnect();
      seen.disconnect();
      removeEventListener("pointermove", onPointer);
      removeEventListener("scroll", wake);
      removeEventListener("resize", wake);
      unlisten();
    };
  }, []);

  const goTo = (at: number) => {
    const stage = stageRef.current;

    if (!stage) {
      return;
    }

    const top = stage.offsetTop + at * (stage.offsetHeight - innerHeight);
    scrollTo({ top: at ? top + 2 : 0 });
  };

  return (
    <section ref={stageRef} className="stage" id="duo" aria-label="iikb on the iPhone Duo">
      <div className="pin" data-kb-theme="standard">
        <div className="hero-copy flex flex-col items-start gap-7">
          <a href="#chats" className="news group">
            <Badge
              variant="outline"
              className="h-7 gap-2 rounded-full pr-3 pl-1 font-mono text-xs font-normal text-muted-foreground"
            >
              <span className="rounded-full bg-pick px-2 py-0.5 text-white">new</span>
              Chats in the keyboard
              <ArrowRight className="size-3.5 transition-transform group-hover:translate-x-0.5" />
            </Badge>
          </a>
          <h1 className="max-w-[7.5em] text-[clamp(44px,min(7.2vw,11svh),108px)] leading-[0.92] font-bold tracking-[-0.055em]">
            the best iOS keyboard <span className="text-faint">in the world.</span>
          </h1>
          <p className="max-w-[24em] text-lg text-muted-foreground md:text-xl">
            It learns your thumbs, writes what you say, and keeps your clipboard, GIFs and emoji a
            tap away.
          </p>
          <div className="flex flex-wrap gap-2.5">
            <a
              href="https://testflight.apple.com/join/xSQ2sdYZ"
              className={cn(buttonVariants({ variant: "send", size: "key" }))}
            >
              <TestFlight />
              Get the beta
            </a>
            <a
              href="https://iikb-android.vercel.app"
              className={cn(buttonVariants({ variant: "key", size: "key" }))}
            >
              <Android />
              Android
            </a>
            <a
              href="https://github.com/AVGVSTVS96/iikb"
              className={cn(buttonVariants({ variant: "key", size: "key" }), "max-sm:hidden")}
            >
              <GitHub className="size-[17px]" />
              Source
            </a>
          </div>
        </div>
        <div className="slot" data-spot />
        <div className="duo" data-duo hidden>
          <div className="rig" data-rig>
            <div className="slab base">
              <Bodies />
              <div className="glass inner">
                <div className="full">
                  <div className="view" data-view>
                    <Screen first="wait, which keyboard is that?" />
                  </div>
                </div>
              </div>
            </div>
            <div className="slab lid" data-lid>
              <Bodies />
              <div className="glass inner" aria-hidden="true">
                <div className="full">
                  <div className="view" data-mirror />
                </div>
              </div>
              <div className="glass cover" data-cover>
                <Screen first="wait, which keyboard is that?" />
              </div>
            </div>
          </div>
        </div>
        <div className="dial" role="tablist" aria-label="Duo pose" data-dial>
          {POSES.map((pose) => (
            <button
              key={pose.id}
              type="button"
              role="tab"
              data-pose={pose.id}
              aria-selected={pose.id === "folded"}
              onClick={() => {
                goTo(pose.at);
              }}
            >
              <b>{pose.title}</b>
              <span>{pose.size}</span>
            </button>
          ))}
        </div>
      </div>
    </section>
  );
};
