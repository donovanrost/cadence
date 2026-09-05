import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { defineConfig, lazyPlugins } from "vite-plus";
import federationConfig from "./module-federation.config";

export default defineConfig({
  plugins: lazyPlugins(() => [vue(), federation(federationConfig)]),
  server: {
    host: "127.0.0.1",
    port: 4177,
    strictPort: true,
  },
  build: {
    target: "chrome89",
  },
});
