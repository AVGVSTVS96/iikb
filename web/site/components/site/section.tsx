import type { ReactNode } from "react";

import { cn } from "@/lib/utils";

interface Props {
  id: string;
  index: string;
  title: string;
  lede?: string;
  className?: string;
  children: ReactNode;
}

export const Section = ({ id, index, title, lede, className, children }: Props) => (
  <section id={id} aria-labelledby={`${id}-title`} className="border-t">
    <div
      className={cn(
        "mx-auto w-full max-w-[1200px] px-5 py-20 md:px-10 md:py-28 xl:px-0",
        className,
      )}
    >
      <header className="mb-12 grid gap-4 md:mb-16 md:grid-cols-12 md:gap-6">
        <span className="font-mono text-xs text-muted-foreground md:col-span-2 md:border-t md:border-foreground md:pt-3">
          {index}
        </span>
        <div className="grid gap-4 md:col-span-10">
          <h2
            id={`${id}-title`}
            className="text-[clamp(38px,5.4vw,72px)] leading-[0.95] font-bold tracking-[-0.045em]"
          >
            {title}
          </h2>
          {lede === undefined ? null : (
            <p className="max-w-[34em] text-lg text-muted-foreground md:text-xl">{lede}</p>
          )}
        </div>
      </header>
      {children}
    </div>
  </section>
);

export const Body = ({ className, children }: { className?: string; children: ReactNode }) => (
  <div className={cn("md:ml-[calc((100%+24px)/12*2)]", className)}>{children}</div>
);
