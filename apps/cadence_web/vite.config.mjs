import {fileURLToPath} from "node:url"
import commonjs from "@rollup/plugin-commonjs"
import vue from "@vitejs/plugin-vue"
import liveVuePlugin from "live_vue/vitePlugin"
import {defineConfig} from "vite"

// Each worktree's dev server needs its own port so its LiveView pages load
// their own code; config/dev.exs reads the same variable for live_vue.
const devPort = Number(process.env.CADENCE_LIVE_VUE_VITE_PORT || 5173)

export default defineConfig(({command}) => ({
  root: "assets",
  base: command === "build" ? "/assets/" : "/",
  resolve: {
    alias: {"@cadence/ui": fileURLToPath(new URL("../../frontend/packages/ui/src", import.meta.url))},
    // Reka checks date classes by identity; its date library must be the same copy.
    dedupe: ["vue", "reka-ui", "@internationalized/date"]
  },
  publicDir: "public",
  server: {
    host: "127.0.0.1",
    port: devPort,
    strictPort: true,
    origin: `http://127.0.0.1:${devPort}`
  },
  plugins: [commonjs(), vue(), liveVuePlugin()],
  build: {
    outDir: "../priv/static/assets",
    emptyOutDir: false,
    cssCodeSplit: false,
    manifest: true,
    rollupOptions: {
      input: "assets/js/app.js",
      // Phoenix may digest the entry URL. A shared hashed runtime keeps lazy chunks
      // on the same module instance and LiveView connection as the initial entry.
      preserveEntrySignatures: "strict",
      output: {
        entryFileNames: "app.js",
        chunkFileNames: "chunks/[name]-[hash].js",
        // Tailwind owns app.css; preserve the separate component stylesheet.
        assetFileNames: asset => asset.names.some(name => name.endsWith(".css"))
          ? "components.css"
          : "[name][extname]"
      }
    }
  },
  optimizeDeps: {
    include: ["live_vue", "phoenix", "phoenix_html", "phoenix_live_view"]
  }
}))
