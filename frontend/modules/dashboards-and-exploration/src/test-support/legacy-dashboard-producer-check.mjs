import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createSSRApp } from "vue";
import { renderToString } from "vue/server-renderer";
import { Window } from "happy-dom";
import { createServer } from "vite-plus";
import vue from "@vitejs/plugin-vue";

const server = await createServer({
  configFile: false,
  root: resolve(dirname(fileURLToPath(import.meta.url)), "../../../../apps/ops-console"),
  plugins: [vue()],
  ssr: { noExternal: ["gridstack"] },
  server: { middlewareMode: true, hmr: false },
  logLevel: "error",
});
try {
  const { OPS_COMPONENTS } = await server.ssrLoadModule("/src/ops-components.ts");
  for (const { presentation, path, query } of JSON.parse(process.argv[2])) {
    const app = createSSRApp(OPS_COMPONENTS[presentation.component], presentation.props);
    app.config.warnHandler = (message) => {
      throw Error(message);
    };
    const window = new Window();
    try {
      const doc = window.document;
      doc.body.innerHTML = await renderToString(app);
      const anchor = doc.querySelector("a");
      assert.ok(anchor);
      const url = new URL(anchor.getAttribute("href"), "https://cadence.test");
      assert.equal(url.pathname, path);
      assert.deepEqual(Object.fromEntries(url.searchParams), query);
      assert.equal(doc.querySelector("form, button, iframe"), null);
    } finally {
      await window.happyDOM.close();
    }
  }
  console.log("Legacy dashboard native producer and remote registry consumer passed.");
} finally {
  await server.close();
}
