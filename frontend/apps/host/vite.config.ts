import { developmentServer, developmentPreview } from "../../tools/dev-services.ts";
import tailwindcss from "@tailwindcss/vite";
import vue from "@vitejs/plugin-vue";
import tidewave from "tidewave/vite-plugin";
import { defineConfig, lazyPlugins } from "vite-plus";
import { createDemoHostMiddleware } from "../../tools/demo-host-service";

const demoHostMiddleware = createDemoHostMiddleware("development");

export default defineConfig({
  server: { ...developmentServer("host") },
  preview: developmentPreview("host"),
  build: {
    target: "chrome89",
  },
  test: {
    environment: "happy-dom",
  },
  plugins:
    lazyPlugins(() => [
      tailwindcss(),
      tidewave(),
      {
        name: "cadence-demo-host-api",
        configureServer(server) {
          server.middlewares.use(demoHostMiddleware);
        },
      },
      vue(),
    ]) ?? [],
});
