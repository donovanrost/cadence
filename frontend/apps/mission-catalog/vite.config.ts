import { developmentServer, developmentPreview } from "../../tools/dev-services.ts";
import { releaseBuildOutput, releaseOutputGuard } from "../../tools/release-build-output.mjs";
import tailwindcss from "@tailwindcss/vite";
import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { resolve } from "node:path";
import { defineConfig, lazyPlugins } from "vite-plus";
import federationConfig from "./module-federation.config";

const federatedEntry = resolve(import.meta.dirname, "src/federated-application.ts");
const releaseFederationConfig = {
  ...federationConfig,
  exposes: { "./Application": federatedEntry },
  hostInitInjectLocation: "entry" as const,
  manifest: {
    additionalData: ({ stats }: { stats: Record<string, unknown> }) => {
      if (!Object.hasOwn(stats, "assetAnalysis")) return stats;
      const publicationStats = { ...stats };
      delete publicationStats.assetAnalysis;
      return publicationStats;
    },
  },
};

function releaseOutputPlugin() {
  return {
    name: "cadence-mission-catalog-release-output",
    enforce: "post" as const,
    apply: "build" as const,
    config(config: { build?: { manifest?: boolean } }, { mode }: { mode: string }) {
      if (mode === "release") {
        config.build ??= {};
        config.build.manifest = false;
      }
    },
  };
}

export default defineConfig(({ command, mode }) => {
  const releaseBuild = mode === "release";
  const outputDirectory = releaseBuildOutput({ command, mode });

  return {
    base: releaseBuild ? "./" : "/",
    plugins:
      lazyPlugins(() => [
        ...(outputDirectory ? [releaseOutputGuard(outputDirectory)] : []),
        tailwindcss(),
        vue(),
        federation(
          releaseBuild ? { ...releaseFederationConfig, publicPath: "auto" } : federationConfig,
        ),
        releaseOutputPlugin(),
      ]) ?? [],
    server: { ...developmentServer("mission-catalog") },
    preview: developmentPreview("mission-catalog"),
    build: {
      target: "chrome89",
      ...(outputDirectory !== undefined
        ? {
            outDir: outputDirectory,
            emptyOutDir: true,
            manifest: false,
            rollupOptions: { input: federatedEntry },
          }
        : {}),
    },
  };
});
