import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: process.env.LERRO_STATIC_EXPORT === "1" ? "export" : undefined,
  images: {
    unoptimized: process.env.LERRO_STATIC_EXPORT === "1",
  },
  typescript: {
    tsconfigPath:
      process.env.LERRO_STATIC_EXPORT === "1" ? "tsconfig.pages.json" : undefined,
  },
};

export default nextConfig;
