import vue from "@vitejs/plugin-vue";
import tidewave from "tidewave/vite-plugin";
import { defineConfig, lazyPlugins } from "vite-plus";
import { createDemoAuthMiddleware } from "../../tools/demo-auth-service";
import { createDemoHostMiddleware } from "../../tools/demo-host-service";

const demoAuthMiddleware = createDemoAuthMiddleware("development");
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
  plugins: lazyPlugins(() => [
    tidewave(),
    {
      name: "cadence-demo-host-api",
      configureServer(server) {
        server.middlewares.use(demoAuthMiddleware);
        server.middlewares.use(demoHostMiddleware);
      },
    },
    vue(),
  ]),
});
