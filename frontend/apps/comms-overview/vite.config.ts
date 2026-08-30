import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { resolve } from "node:path";
import { defineConfig, lazyPlugins } from "vite-plus";
import federationConfig from "./module-federation.config";

const cadenceVueSource = resolve(__dirname, "../../../apps/cadence_web/assets/vue");
const publicationRoot = resolve(
  __dirname,
  "../../../apps/cadence_web/priv/static/assets/application-host/comms-overview",
);

export default defineConfig({
  define: {
    "process.env.NODE_ENV": JSON.stringify("production"),
  },
  base: "/assets/application-host/comms-overview/",
  resolve: {
    alias: {
      "@cadence/cadence-web-vue": cadenceVueSource,
    },
  },
  server: {
    host: "127.0.0.1",
    port: 4176,
    strictPort: true,
    cors: true,
    origin: "http://127.0.0.1:4176",
  },
  preview: {
    host: "127.0.0.1",
    port: 4176,
    strictPort: true,
  },
  build: {
    target: "chrome89",
    outDir: publicationRoot,
    emptyOutDir: true,
  },
  test: {
    environment: "happy-dom",
  },
  plugins: lazyPlugins(() => [vue(), federation(federationConfig)]),
});
