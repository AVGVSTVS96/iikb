import type { NextConfig } from "next";

const config: NextConfig = {
  output: "export",
  images: { unoptimized: true },
  typescript: { ignoreBuildErrors: true },
  turbopack: { root: new URL("../..", import.meta.url).pathname },
};

export default config;
