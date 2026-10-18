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
const releaseFederationConfig = {
  ...federationConfig,
  exposes: { "./Application": federatedEntry },
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
    name: "cadence-telemetry-decom-release-output",
    enforce: "post",
    apply: "build",
    config(config: ViteUserConfig) {
      config.build ??= {};
      config.build.manifest = false;
    },
  };
}

export default defineConfig(({ command, mode }) => {
  const releaseBuild = mode === "release";
  const outputDirectory = releaseBuildOutput({ command, mode });

  const releaseSlot = mode === "previous" ? "previous" : "current";
  const releaseId = releaseSlot === "previous" ? "2026.08.22.1" : "2026.08.22.2";
  const base = releaseBuild
    ? "./"
    : command === "serve"
      ? `${developmentOrigin("telemetry-decom")}/`
      : `${developmentOrigin("telemetry-decom")}/releases/${releaseSlot}/`;

  return {
    base,
    define: {
      __CADENCE_REMOTE_RELEASE__: JSON.stringify(
        command === "serve" ? "development" : releaseBuild ? "release" : releaseId,
      ),
    },
    server: { ...developmentServer("telemetry-decom"), cors: true },
    preview: developmentPreview("telemetry-decom"),
    build: {
      target: "chrome89",
      outDir: outputDirectory ?? `dist/${releaseSlot}`,
      ...(releaseBuild
        ? {
            emptyOutDir: true,
            manifest: false,
            rollupOptions: { input: federatedEntry },
          }
        : {}),
    },
    test: {
      environment: "happy-dom",
    },
    plugins:
      lazyPlugins(() => [
        ...(outputDirectory ? [releaseOutputGuard(outputDirectory)] : []),
        tailwindcss(),
        vue(),
        federation(
          releaseBuild ? { ...releaseFederationConfig, publicPath: "auto" } : federationConfig,
        ),
        ...(releaseBuild ? [releaseOutputPlugin()] : []),
      ]) ?? [],
  };
});
