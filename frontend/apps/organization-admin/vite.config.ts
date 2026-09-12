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
  hostInitInjectLocation: "entry" as const,
  publicPath: "auto" as const,
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
    name: "cadence-organization-admin-release-output",
    enforce: "post" as const,
    apply: "build" as const,
    config(config: ViteUserConfig) {
      config.build ??= {};
      config.build.manifest = false;
    },
  };
}

export default defineConfig(({ command, mode }) => {
  const releaseBuild = mode === "release";
  const outputDirectory = releaseBuildOutput({ command, mode });

  return {
    base: releaseBuild
      ? "./"
      : command === "serve"
        ? `${developmentOrigin("organization-admin")}/`
        : `${developmentOrigin("organization-admin")}/releases/current/`,
    define: {
      __CADENCE_REMOTE_RELEASE__: JSON.stringify(releaseBuild ? "release" : "development"),
    },
    server: { ...developmentServer("organization-admin"), cors: true },
    preview: developmentPreview("organization-admin"),
    build: {
      target: "chrome89",
      outDir: outputDirectory ?? "dist/current",
      ...(releaseBuild
        ? { emptyOutDir: true, manifest: false, rollupOptions: { input: federatedEntry } }
        : {}),
    },
    test: { environment: "happy-dom" },
    plugins:
      lazyPlugins(() => [
        ...(outputDirectory ? [releaseOutputGuard(outputDirectory)] : []),
        tailwindcss(),
        vue(),
        federation(releaseBuild ? releaseFederationConfig : federationConfig),
        ...(releaseBuild ? [releaseOutputPlugin()] : []),
      ]) ?? [],
  };
});
