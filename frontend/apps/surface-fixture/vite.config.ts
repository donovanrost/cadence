// The console federation smoke's test-only remote (surface_fixture): release builds only. The
// release fixture builds it twice (CADENCE_FIXTURE_RELEASE_LABEL n-minus-1 and n) and signs both
// with the smoke's TEST key. It is not a publication remote (no build:phoenix) and production
// publication refuses any reference to it.
import { releaseBuildOutput, releaseOutputGuard } from "../../tools/release-build-output.mjs";
import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { resolve } from "node:path";
import { defineConfig, lazyPlugins, type ViteUserConfig } from "vite-plus";
import federationConfig from "./module-federation.config";

const federatedEntry = resolve(__dirname, "src/federated-application.ts");

// Like the product remotes: no Vite manifest (.vite/) in a release; the packager refuses it.
function releaseOutputPlugin() {
  return {
    name: "cadence-surface-fixture-release-output",
    enforce: "post" as const,
    apply: "build" as const,
    config(config: ViteUserConfig) {
      config.build ??= {};
      config.build.manifest = false;
    },
  };
}

export default defineConfig(({ command, mode }) => {
  const outputDirectory = releaseBuildOutput({ command, mode });
  return {
    base: "./",
    define: {
      __CADENCE_REMOTE_RELEASE__: JSON.stringify(
        process.env["CADENCE_FIXTURE_RELEASE_LABEL"] ?? "release",
      ),
    },
    build: {
      target: "chrome89",
      outDir: outputDirectory ?? "dist",
      emptyOutDir: true,
      manifest: false,
      rollupOptions: { input: federatedEntry },
    },
    plugins:
      lazyPlugins(() => [
        ...(outputDirectory ? [releaseOutputGuard(outputDirectory)] : []),
        vue(),
        federation({
          ...federationConfig,
          exposes: { "./Application": federatedEntry },
          publicPath: "auto",
          // Like the product remotes' releases: no asset analysis in the published stats.
          manifest: {
            additionalData: ({ stats }: { stats: Record<string, unknown> }) => {
              if (!Object.hasOwn(stats, "assetAnalysis")) return stats;
              const publicationStats = { ...stats };
              delete publicationStats.assetAnalysis;
              return publicationStats;
            },
          },
        }),
        releaseOutputPlugin(),
      ]) ?? [],
  };
});
