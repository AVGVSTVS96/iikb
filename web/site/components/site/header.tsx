"use client";

import { Menu } from "lucide-react";
import { useEffect, useState } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";

import { GitHub, Wordmark } from "./icons";

const LINKS = [
  ["Duo", "#duo"],
  ["Themes", "#themes"],
  ["Typing", "#typing"],
  ["Voice", "#voice"],
  ["Chats", "#chats"],
  ["Changelog", "#changelog"],
] as const;

export const Header = () => {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => {
      setScrolled(scrollY > 8);
    };

    onScroll();
    addEventListener("scroll", onScroll, { passive: true });

    return () => {
      removeEventListener("scroll", onScroll);
    };
  }, []);

  return (
    <header
      className={cn(
        "sticky top-0 z-50 border-b border-transparent bg-background/80 backdrop-blur-xl backdrop-saturate-150 transition-colors",
        scrolled && "border-border",
      )}
    >
      <div className="mx-auto flex h-16 w-full max-w-[1200px] items-center gap-8 px-5 md:px-10 xl:px-0">
        <a href="#top" aria-label="iikb home" className="text-foreground">
          <Wordmark className="h-[22px] w-auto" />
        </a>
        <nav aria-label="Main" className="hidden items-center gap-0.5 md:flex">
          {LINKS.map(([label, href]) => (
            <a
              key={href}
              href={href}
              className={cn(buttonVariants({ variant: "ghost" }), "text-muted-foreground")}
            >
              {label}
            </a>
          ))}
        </nav>
        <div className="ml-auto flex items-center gap-2">
          <DropdownMenu>
            <DropdownMenuTrigger
              aria-label="Sections"
              className={cn(
                buttonVariants({ variant: "ghost", size: "icon" }),
                "text-muted-foreground md:hidden",
              )}
            >
              <Menu className="size-[18px]" />
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="min-w-40">
              {LINKS.map(([label, href]) => (
                <DropdownMenuItem key={href} render={<a href={href} />}>
                  {label}
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>
          <a
            href="https://github.com/AVGVSTVS96/iikb"
            aria-label="iikb on GitHub"
            className={cn(
              buttonVariants({ variant: "ghost", size: "icon" }),
              "text-muted-foreground",
            )}
          >
            <GitHub className="size-[18px]" />
          </a>
          <a href="#get" className={buttonVariants({ size: "lg" })}>
            Get iikb
          </a>
        </div>
      </div>
    </header>
  );
};
