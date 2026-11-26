import { developmentServer, developmentPreview } from "../../tools/dev-services.ts";
import tailwindcss from "@tailwindcss/vite";
import vue from "@vitejs/plugin-vue";
import { fileURLToPath } from "node:url";
import { defineConfig, lazyPlugins } from "vite-plus";

// Phoenix serves /console/* and stays the browser origin in development; it loads
// modules from this server cross-origin (see ARCHITECTURE.md "Serving").
const phoenixOutput = fileURLToPath(
  new URL("../../../apps/cadence_web/priv/static/console", import.meta.url),
);

export default defineConfig({
  base: "/console/",
  resolve: {
    alias: [
      // Transitional: pre-package import paths resolve to the "@/ui" surface. Remove once unused.
      ...["@/ui/index.ts", "@/lib/index.ts", "@/lib/format.ts"].map((find) => ({
        find,
        replacement: fileURLToPath(new URL("./src/ui.ts", import.meta.url)),
      })),
      { find: "@", replacement: fileURLToPath(new URL("./src", import.meta.url)) },
    ],
  },
  server: { ...developmentServer("console"), cors: true },
  preview: developmentPreview("console"),
  build: { outDir: phoenixOutput, emptyOutDir: true, target: "es2022" },
  test: { environment: "happy-dom", include: ["src/**/*.test.ts"] },
  plugins: lazyPlugins(() => [tailwindcss(), vue()]) ?? [],
});
