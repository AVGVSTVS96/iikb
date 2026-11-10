import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";

import { WordmarkSymbol } from "@/components/site/icons";
import { ThemeStyles } from "@/components/site/keys";

import "./globals.css";

const SITE = "https://iikb.vercel.app";

const DESCRIPTION =
  "Building the best iOS keyboard in the world. Adaptive typing, on-device dictation, and tools worth switching for. Open source for iPhone and iPad.";

export const metadata: Metadata = {
  metadataBase: new URL(SITE),
  title: "iikb · The best iOS keyboard. In the world.",
  description: DESCRIPTION,
  alternates: { canonical: "/" },
  icons: { icon: "/favicon.svg", apple: "/apple-touch-icon.png" },
  openGraph: {
    type: "video.other",
    siteName: "iikb",
    title: "iikb",
    description: DESCRIPTION,
    url: "/",
    images: [
      {
        url: "/og.png?v=3",
        width: 1200,
        height: 630,
        alt: "iikb. The best iOS keyboard. In the world.",
      },
    ],
    videos: [{ url: "/og.mp4?v=3", width: 1200, height: 630, type: "video/mp4" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "iikb",
    description: DESCRIPTION,
    images: [{ url: "/og.png?v=3", alt: "iikb. The best iOS keyboard. In the world." }],
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  colorScheme: "light dark",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#ffffff" },
    { media: "(prefers-color-scheme: dark)", color: "#000000" },
  ],
};

export default function RootLayout({ children }: Readonly<{ children: ReactNode }>) {
  return (
    <html lang="en">
      <head>
        <link
          rel="preload"
          href="/fonts/commit-mono-400.woff2"
          as="font"
          type="font/woff2"
          crossOrigin=""
        />
        <ThemeStyles />
      </head>
      <body>
        <WordmarkSymbol />
        {children}
      </body>
    </html>
  );
}
