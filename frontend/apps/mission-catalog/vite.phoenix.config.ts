import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { resolve } from "node:path";
import { defineConfig, lazyPlugins, type ViteUserConfig } from "vite-plus";
import federationConfig from "./module-federation.config";

const federatedEntry = resolve(__dirname, "src/federated-application.ts");
const publicationRoot = resolve(
  __dirname,
  "../../../apps/cadence_web/priv/static/assets/application-host/mission-catalog",
);
const publicationManifest = {
  additionalData: ({ stats }: { stats: Record<string, unknown> }) => {
    if (!Object.hasOwn(stats, "assetAnalysis")) return stats;
    const publicationStats = { ...stats };
    delete publicationStats.assetAnalysis;
    return publicationStats;
  },
};

function publicationOutputPlugin() {
  return {
    name: "cadence-mission-catalog-publication-output",
    enforce: "post",
    apply: "build",
    config(config: ViteUserConfig) {
      config.build ??= {};
      config.build.manifest = false;
    },
  };
}

export default defineConfig({
  define: { "process.env.NODE_ENV": JSON.stringify("production") },
  base: "/assets/application-host/mission-catalog/",
  build: {
    target: "chrome89",
    outDir: publicationRoot,
    emptyOutDir: true,
    rollupOptions: { input: federatedEntry },
  },
  plugins: lazyPlugins(() => [
    vue(),
    federation({
      ...federationConfig,
      exposes: { "./Application": federatedEntry },
      manifest: publicationManifest,
      publicPath: "auto",
    }),
    publicationOutputPlugin(),
  ]),
});
