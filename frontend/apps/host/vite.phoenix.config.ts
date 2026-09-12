import { readPublication, publicationOutputDirectory } from "../../tools/publication-metadata.ts";
import vue from "@vitejs/plugin-vue";
import { resolve } from "node:path";
import { defineConfig, lazyPlugins } from "vite-plus";

const publication = readPublication(import.meta.dirname);
const publicationRoot = publicationOutputDirectory(publication);

export default defineConfig({
  define: {
    "process.env.NODE_ENV": JSON.stringify("production"),
  },
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
  plugins:
    lazyPlugins(() => [
      vue(),
      {
        name: "cadence-remove-node-origin-fallback",
        enforce: "post",
        transform(code, id) {
          if (!id.endsWith("/phoenix-catalog-client.ts")) return null;
          const next = code.replace(
            /return typeof window === "undefined" \? "http:\/\/localhost\/" : window\.location\.origin;/,
            "return window.location.origin;",
          );
          if (next === code)
            throw new Error("Phoenix production build could not remove its Node origin fallback.");
          return { code: next, map: null };
        },
      },
    ]) ?? [],
});
