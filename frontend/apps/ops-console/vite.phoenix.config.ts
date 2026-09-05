import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { resolve } from "node:path";
import { defineConfig, lazyPlugins } from "vite-plus";
import federationConfig from "./module-federation.config";

const publicationRoot = resolve(
  import.meta.dirname,
  "../../../apps/cadence_web/priv/static/assets/application-host/ops-console",
);

export default defineConfig({
  define: {
    "process.env.NODE_ENV": JSON.stringify("production"),
  },
  base: "/assets/application-host/ops-console/",
  build: {
    target: "chrome89",
    outDir: publicationRoot,
    emptyOutDir: true,
    manifest: false,
    rollupOptions: { input: resolve(import.meta.dirname, "src/federated-application.ts") },
  },
  plugins: lazyPlugins(() => [vue(), federation(federationConfig)]),
});
