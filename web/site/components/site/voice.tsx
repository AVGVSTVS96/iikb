"use client";

import { ArrowUp } from "lucide-react";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { dictation } from "@/lib/bus";

const STYLES = [
  {
    id: "formal",
    title: "Formal.",
    text: "By the way, are you free tonight? The show is amazing, for real.",
  },
  {
    id: "excited",
    title: "Excited!",
    text: "By the way, are you free tonight? The show is amazing, for real!",
  },
  {
    id: "casual",
    title: "Casual",
    text: "By the way, are you free tonight? The show is amazing, for real",
  },
  {
    id: "veryCasual",
    title: "very casual",
    text: "btw, are you free tonight? the show is amazing, for real",
  },
  { id: "texting", title: "texting", text: "btw, r u free tn? the show is amazing, for real" },
  { id: "slang", title: "slang", text: "btw, r u free tn? the show is fire, fr" },
] as const;

export const Styles = () => {
  const [id, setId] = useState<string>("casual");
  const style = STYLES.find((s) => s.id === id) ?? STYLES[2];

  return (
    <div className="grid min-w-0 grid-rows-[auto_1fr] gap-4">
      <Tabs
        className="min-w-0"
        value={id}
        onValueChange={(v) => {
          setId(String(v));
        }}
      >
        <TabsList className="w-full justify-start overflow-x-auto [scrollbar-width:none]">
          {STYLES.map((s) => (
            <TabsTrigger key={s.id} value={s.id} className="h-8 flex-none px-3">
              {s.title}
            </TabsTrigger>
          ))}
        </TabsList>
      </Tabs>
      <Card className="min-h-[248px] justify-center">
        <CardContent className="grid gap-5">
          <p className="flex items-baseline gap-2.5 font-mono text-xs leading-relaxed text-muted-foreground">
            <span className="relative top-[-1px] size-[7px] flex-none rounded-full bg-live shadow-[0_0_0_3px_color-mix(in_srgb,var(--red)_22%,transparent)]" />
            by the way are you free tonight the show is amazing for real
          </p>
          <p className="min-h-[2.4em] text-[clamp(24px,2.4vw,30px)] leading-[1.2] font-medium tracking-[-0.025em]">
            {style.text}
          </p>
          <Button
            variant="ghost"
            className="-ml-2.5 justify-self-start font-mono text-xs text-muted-foreground"
            onClick={() => {
              scrollTo({ top: 0, behavior: "smooth" });
              setTimeout(() => {
                dictation.send(style.text);
              }, 500);
            }}
          >
            Dictate it on the Duo
            <ArrowUp data-icon="inline-end" />
          </Button>
        </CardContent>
      </Card>
    </div>
  );
};
