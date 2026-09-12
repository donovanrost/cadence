import tailwindcss from "@tailwindcss/vite";
import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { defineConfig, lazyPlugins } from "vite-plus";
import federationConfig from "./module-federation.config";

export default defineConfig(({ command }) => ({
  base: command === "serve" ? "http://127.0.0.1:4175/" : "http://127.0.0.1:4175/releases/current/",
  server: {
    host: "127.0.0.1",
    port: 4175,
    strictPort: true,
    cors: true,
    origin: "http://127.0.0.1:4175",
  },
  build: {
    target: "chrome89",
    outDir: "dist/current",
  },
  plugins: lazyPlugins(() => [tailwindcss(), vue(), federation(federationConfig)]) ?? [],
}));
