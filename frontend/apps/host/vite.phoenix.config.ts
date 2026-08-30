import vue from "@vitejs/plugin-vue";
import { resolve } from "node:path";
import { defineConfig, lazyPlugins } from "vite-plus";

const publicationRoot = resolve(
  __dirname,
  "../../../apps/cadence_web/priv/static/assets/application-host/host",
);

export default defineConfig({
  build: {
    target: "chrome89",
    outDir: publicationRoot,
    emptyOutDir: true,
    lib: {
      entry: resolve(__dirname, "src/phoenix-main.ts"),
      formats: ["es"],
      fileName: () => "host.js",
    },
    rollupOptions: {
      output: {
        entryFileNames: "host.js",
      },
    },
  },
  plugins: lazyPlugins(() => [vue()]),
});
