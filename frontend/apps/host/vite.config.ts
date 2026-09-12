import tailwindcss from "@tailwindcss/vite";
import vue from "@vitejs/plugin-vue";
import tidewave from "tidewave/vite-plugin";
import { defineConfig, lazyPlugins } from "vite-plus";
import { createDemoHostMiddleware } from "../../tools/demo-host-service";

const demoHostMiddleware = createDemoHostMiddleware("development");

export default defineConfig({
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    origin: "http://127.0.0.1:5173",
  },
  preview: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
  },
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
