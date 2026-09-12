import {
  developmentServer,
  developmentPreview,
  developmentOrigin,
} from "../../tools/dev-services.ts";
import tailwindcss from "@tailwindcss/vite";
import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { defineConfig, lazyPlugins } from "vite-plus";
import federationConfig from "./module-federation.config";

export default defineConfig(({ command }) => ({
  base:
    command === "serve"
      ? `${developmentOrigin("contract-probe")}/`
      : `${developmentOrigin("contract-probe")}/releases/current/`,
  server: { ...developmentServer("contract-probe"), cors: true },
  preview: developmentPreview("contract-probe"),
  build: {
    target: "chrome89",
    outDir: "dist/current",
  },
  plugins: lazyPlugins(() => [tailwindcss(), vue(), federation(federationConfig)]) ?? [],
}));
