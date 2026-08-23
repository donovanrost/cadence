import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { defineConfig, lazyPlugins } from "vite-plus";
import federationConfig from "./module-federation.config";

export default defineConfig(({ command, mode }) => {
  const releaseSlot = mode === "previous" ? "previous" : "current";
  const releaseId = releaseSlot === "previous" ? "2026.08.22.1" : "2026.08.22.2";
  const base =
    command === "serve"
      ? "http://127.0.0.1:4174/"
      : `http://127.0.0.1:4174/releases/${releaseSlot}/`;

  return {
    base,
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
    plugins: lazyPlugins(() => [vue(), federation(federationConfig)]),
  };
});
