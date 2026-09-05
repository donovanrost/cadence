import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { resolve } from "node:path";
import { defineConfig, lazyPlugins } from "vite-plus";
import federationConfig from "./module-federation.config";

const federatedEntry = resolve(__dirname, "src/federated-application.ts");
const publicationRoot = resolve(
  __dirname,
  "../../../apps/cadence_web/priv/static/assets/application-host/organization-admin"
);

export default defineConfig({
  define: { "process.env.NODE_ENV": JSON.stringify("production") },
  base: "/assets/application-host/organization-admin/",
  build: {
    target: "chrome89",
    outDir: publicationRoot,
    emptyOutDir: true,
    manifest: false,
    rollupOptions: { input: federatedEntry }
  },
  plugins: lazyPlugins(() => [
    vue(),
    federation({
      ...federationConfig,
      publicPath: "auto"
    })
  ])
});
