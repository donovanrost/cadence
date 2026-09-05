import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { resolve } from "node:path";
import { defineConfig, lazyPlugins, type ViteUserConfig } from "vite-plus";
import federationConfig from "./module-federation.config";

const federatedEntry = resolve(__dirname, "src/federated-application.ts");
const publicationManifest = {
  additionalData: ({ stats }: { stats: Record<string, unknown> }) => {
    if (!Object.hasOwn(stats, "assetAnalysis")) return stats;
    const publicationStats = { ...stats };
    delete publicationStats.assetAnalysis;
    return publicationStats;
  },
};
const publicationRoot = resolve(
  __dirname,
  "../../../apps/cadence_web/priv/static/assets/application-host/organization-admin",
);

function publicationOutputPlugin() {
  return {
    name: "cadence-organization-admin-publication-output",
    enforce: "post" as const,
    apply: "build" as const,
    config(config: ViteUserConfig) {
      config.build ??= {};
      config.build.manifest = false;
    },
  };
}

export default defineConfig({
  define: { "process.env.NODE_ENV": JSON.stringify("production") },
  base: "/assets/application-host/organization-admin/",
  build: {
    target: "chrome89",
    outDir: publicationRoot,
    emptyOutDir: true,
    manifest: false,
    rollupOptions: { input: federatedEntry },
  },
  plugins: lazyPlugins(() => [
    vue(),
    federation({
      ...federationConfig,
      manifest: publicationManifest,
      publicPath: "auto",
    }),
    publicationOutputPlugin(),
  ]),
});
