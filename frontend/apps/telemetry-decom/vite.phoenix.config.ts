import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { resolve } from "node:path";
import { defineConfig, lazyPlugins } from "vite-plus";
import federationConfig from "./module-federation.config";

const cadenceVueSource = resolve(__dirname, "../../../apps/cadence_web/assets/vue");
const publicationRoot = resolve(
  __dirname,
  "../../../apps/cadence_web/priv/static/assets/application-host/telemetry-decom",
);

export default defineConfig({
  define: {
    "process.env.NODE_ENV": JSON.stringify("production"),
  },
  base: "/assets/application-host/telemetry-decom/",
  resolve: {
    alias: {
      "@cadence/cadence-web-vue": cadenceVueSource,
    },
  },
  build: {
    target: "chrome89",
    outDir: publicationRoot,
    emptyOutDir: true,
  },
  plugins: lazyPlugins(() => [vue(), federation(federationConfig)]),
});
