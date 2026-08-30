import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { resolve } from "node:path";
import { defineConfig, lazyPlugins } from "vite-plus";
import federationConfig from "./module-federation.config";

const cadenceVueSource = resolve(__dirname, "../../../apps/cadence_web/assets/vue");

export default defineConfig(({ command, mode }) => {
  const releaseSlot = mode === "previous" ? "previous" : "current";
  const releaseId = releaseSlot === "previous" ? "2026.08.22.1" : "2026.08.22.2";
  const base =
    command === "serve"
      ? "http://127.0.0.1:4174/"
      : `http://127.0.0.1:4174/releases/${releaseSlot}/`;

  return {
    base,
    resolve: {
      alias: {
        "@cadence/cadence-web-vue": cadenceVueSource,
      },
    },
    define: {
      __CADENCE_REMOTE_RELEASE__: JSON.stringify(command === "serve" ? "development" : releaseId),
    },
    server: {
      host: "127.0.0.1",
      port: 4174,
      strictPort: true,
      cors: true,
      origin: "http://127.0.0.1:4174",
    },
    build: {
      target: "chrome89",
      outDir: `dist/${releaseSlot}`,
    },
    test: {
      environment: "happy-dom",
    },
    plugins: lazyPlugins(() => [vue(), federation(federationConfig)]),
  };
});
