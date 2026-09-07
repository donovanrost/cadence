import tailwindcss from "@tailwindcss/vite";
import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { isAbsolute, resolve } from "node:path";
import { defineConfig, lazyPlugins } from "vite-plus";
import federationConfig from "./module-federation.config";

const publicationRoot = resolve(
  import.meta.dirname,
  "../../../apps/cadence_web/priv/static/assets/application-host/ops-console",
);
const releaseOutputEnvironmentName = "CADENCE_RELEASE_OUTPUT_DIR";
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

function releaseOutputDirectory(): string {
  const output = process.env[releaseOutputEnvironmentName];
  if (!output || !isAbsolute(output)) {
    throw new Error(
      `${releaseOutputEnvironmentName} must be an absolute output directory for release builds.`,
    );
  }
  return output;
}

function releaseOutputPlugin() {
  return {
    name: "cadence-ops-console-release-output",
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

export default defineConfig(({ mode }) => {
  const releaseBuild = mode === "release";
  const outputDirectory = releaseBuild ? releaseOutputDirectory() : undefined;

  return {
    define: {
      "process.env.NODE_ENV": JSON.stringify("production"),
    },
    base: releaseBuild ? "./" : "/assets/application-host/ops-console/",
    build: {
      target: "chrome89",
      ...(releaseBuild
        ? {
            outDir: outputDirectory,
            emptyOutDir: true,
            manifest: false,
            rollupOptions: { input: federatedEntry },
          }
        : {}),
    },
    test: {
      environment: "happy-dom",
    },
    plugins: lazyPlugins(() => [
      tailwindcss(),
      vue(),
      federation(
        releaseBuild ? { ...releaseFederationConfig, publicPath: "auto" } : federationConfig,
      ),
      releaseOutputPlugin(),
    ]),
  };
});
