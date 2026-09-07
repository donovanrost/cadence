import {fileURLToPath} from "node:url"
import commonjs from "@rollup/plugin-commonjs"
import vue from "@vitejs/plugin-vue"
import liveVuePlugin from "live_vue/vitePlugin"
import {defineConfig} from "vite"

export default defineConfig({
  root: "assets",
  resolve: {
    alias: {"@cadence/ui": fileURLToPath(new URL("../../frontend/packages/ui/src", import.meta.url))},
    dedupe: ["vue", "reka-ui"]
  },
  publicDir: "public",
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    origin: "http://127.0.0.1:5173"
  },
  plugins: [commonjs(), vue(), liveVuePlugin()],
  build: {
    outDir: "../priv/static/assets",
    emptyOutDir: false,
    manifest: true,
    rollupOptions: {
      input: "assets/js/app.js",
      output: {
        entryFileNames: "app.js",
        chunkFileNames: "chunks/[name]-[hash].js",
        assetFileNames: "[name][extname]"
      }
    }
  },
  optimizeDeps: {
    include: ["live_vue", "phoenix", "phoenix_html", "phoenix_live_view"]
  }
})
