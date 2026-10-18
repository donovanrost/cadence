import {
  readPublication,
  publicationOutputDirectory,
  publicationBase,
} from "../../tools/publication-metadata.ts";
import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { resolve } from "node:path";
import { defineConfig, lazyPlugins, type ViteUserConfig } from "vite-plus";
import federationConfig from "./module-federation.config";

const publicationManifest = {
  additionalData: ({ stats }: { stats: Record<string, unknown> }) => {
    if (!Object.hasOwn(stats, "assetAnalysis")) return stats;
    const publicationStats = { ...stats };
    delete publicationStats.assetAnalysis;
    return publicationStats;
  },
};
const publication = readPublication(import.meta.dirname);
const publicationRoot = publicationOutputDirectory(publication);

function publicationOutputPlugin() {
  return {
    name: "cadence-ops-console-publication-output",
    enforce: "post" as const,
    apply: "build" as const,
    config(config: ViteUserConfig) {
      config.build ??= {};
      config.build.manifest = false;
    },
  };
}

export default defineConfig({
  define: {
    "process.env.NODE_ENV": JSON.stringify("production"),
  },
  base: publicationBase(publication),
  build: {
    target: "chrome89",
    outDir: publicationRoot,
    emptyOutDir: true,
    manifest: false,
    rollupOptions: { input: resolve(import.meta.dirname, "src/federated-application.ts") },
  },
  plugins:
    lazyPlugins(() => [
      vue(),
      federation({ ...federationConfig, manifest: publicationManifest, publicPath: "auto" }),
      publicationOutputPlugin(),
    ]) ?? [],
});
