import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { resolve } from "node:path";
import { defineConfig, lazyPlugins, type ViteUserConfig } from "vite-plus";
import federationConfig from "./module-federation.config";

const cadenceVueSource = resolve(__dirname, "../../../apps/cadence_web/assets/vue");
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
const publicationRoot = resolve(
  __dirname,
  "../../../apps/cadence_web/priv/static/assets/application-host/comms-overview",
);

function publicationOutputPlugin() {
  return {
    name: "cadence-comms-overview-publication-output",
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
  base: "/assets/application-host/comms-overview/",
  resolve: {
    alias: {
      "@cadence/cadence-web-vue": cadenceVueSource,
    },
  },
  build: {
    target: "chrome89",
    outDir: publicationRoot,
    emptyOutDir: true,
    manifest: false,
    rollupOptions: { input: federatedEntry },
  },
  plugins: lazyPlugins(() => [
    vue(),
    federation(publicationFederationConfig),
    publicationOutputPlugin(),
  ]),
});
