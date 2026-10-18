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

const federatedEntry = resolve(__dirname, "src/federated-application.ts");
const publicationFederationConfig = {
  ...federationConfig,
  manifest: {
    additionalData: ({ stats }: { stats: Record<string, unknown> }) => {
      if (!Object.hasOwn(stats, "assetAnalysis")) return stats;
      const publicationStats = { ...stats };
      delete publicationStats.assetAnalysis;
      return publicationStats;
    },
  },
  publicPath: "auto",
};
const publication = readPublication(import.meta.dirname);
const publicationRoot = publicationOutputDirectory(publication);

function publicationOutputPlugin() {
  return {
    name: "cadence-comms-publication-output",
    enforce: "post",
    apply: "build",
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
    rollupOptions: { input: federatedEntry },
  },
  plugins:
    lazyPlugins(() => [
      vue(),
      federation(publicationFederationConfig),
      publicationOutputPlugin(),
    ]) ?? [],
});
