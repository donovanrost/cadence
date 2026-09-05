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

function releaseOutputDirectory(): string {
  const output = process.env[releaseOutputEnvironmentName];
  if (!output || !isAbsolute(output)) {
    throw new Error(
      `${releaseOutputEnvironmentName} must be an absolute output directory for release builds.`,
    );
  }
  return output;
}

export default defineConfig(({ mode }) => {
  const releaseBuild = mode === "release";
  const outputDirectory = releaseBuild ? releaseOutputDirectory() : undefined;

  return {
    define: {
      "process.env.NODE_ENV": JSON.stringify("production"),
    },
    base: "/assets/application-host/ops-console/",
    build: {
      target: "chrome89",
      ...(releaseBuild
        ? {
            outDir: outputDirectory,
            emptyOutDir: true,
            manifest: false,
            rollupOptions: { input: resolve(import.meta.dirname, "src/federated-application.ts") },
          }
        : {}),
    },
    plugins: lazyPlugins(() => [vue(), federation(federationConfig)]),
  };
});
