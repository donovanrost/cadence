import {
  developmentServer,
  developmentPreview,
  developmentOrigin,
} from "../../tools/dev-services.ts";
import { releaseBuildOutput, releaseOutputGuard } from "../../tools/release-build-output.mjs";
import tailwindcss from "@tailwindcss/vite";
import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { resolve } from "node:path";
import { defineConfig, lazyPlugins, type ViteUserConfig } from "vite-plus";
import federationConfig from "./module-federation.config";

const federatedEntry = resolve(__dirname, "src/federated-application.ts");

// Like the product remotes: no Vite manifest (.vite/) in a release; the packager refuses it.
function releaseOutputPlugin() {
  return {
    name: "cadence-contract-probe-release-output",
    enforce: "post" as const,
    apply: "build" as const,
    config(config: ViteUserConfig) {
      config.build ??= {};
      config.build.manifest = false;
    },
  };
}

export default defineConfig(({ command, mode }) => {
  // `--mode release` (build:release): a signed-release build for the console federation smoke's
  // release fixture, which builds it twice with CADENCE_FIXTURE_RELEASE_LABEL set (N-1 and N). The
  // release output check forbids this remote by design, so it never ships.
  const releaseBuild = mode === "release";
  const outputDirectory = releaseBuildOutput({ command, mode });
  return {
    base: releaseBuild
      ? "./"
      : command === "serve"
        ? `${developmentOrigin("contract-probe")}/`
        : `${developmentOrigin("contract-probe")}/releases/current/`,
    define: {
      __CADENCE_REMOTE_RELEASE__: JSON.stringify(
        command === "serve"
          ? "development"
          : releaseBuild
            ? (process.env["CADENCE_FIXTURE_RELEASE_LABEL"] ?? "release")
            : "current",
      ),
    },
    server: { ...developmentServer("contract-probe"), cors: true },
    preview: developmentPreview("contract-probe"),
    build: {
      target: "chrome89",
      outDir: outputDirectory ?? "dist/current",
      ...(releaseBuild
        ? { emptyOutDir: true, manifest: false, rollupOptions: { input: federatedEntry } }
        : {}),
    },
    plugins:
      lazyPlugins(() => [
        ...(outputDirectory ? [releaseOutputGuard(outputDirectory)] : []),
        tailwindcss(),
        vue(),
        federation(
          releaseBuild
            ? {
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
              }
            : federationConfig,
        ),
        ...(releaseBuild ? [releaseOutputPlugin()] : []),
      ]) ?? [],
  };
});
