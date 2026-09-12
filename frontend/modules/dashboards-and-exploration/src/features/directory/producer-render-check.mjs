import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createServer } from "vite-plus";
import vue from "@vitejs/plugin-vue";
import { Window } from "happy-dom";
import { createSSRApp } from "vue";
import { renderToString } from "vue/server-renderer";
const server = await createServer({
  configFile: false,
  root: resolve(dirname(fileURLToPath(import.meta.url)), "../../.."),
  plugins: [vue()],
  server: { middlewareMode: true, hmr: false },
  ssr: { noExternal: ["@cadence/ui"] },
  logLevel: "error",
});
try {
  const { directoryContribution } = await server.ssrLoadModule("/src/directory.ts");
  for (const model of JSON.parse(process.argv[2])) {
    const props = directoryContribution.read(
      { model, sequence: 0, phase: "editing" },
      { organizationId: "producer-test", missionId: model.mission_id },
    );
    const app = createSSRApp(directoryContribution.component, {
      ...props,
      port: {
        execute: () => {
          throw Error("Unexpected effect");
        },
        navigate() {},
      },
      refresh: async () => {},
    });
    app.config.warnHandler = (message) => {
      throw Error(message);
    };
    const html = await renderToString(app);
    const window = new Window();
    try {
      window.document.body.innerHTML = html;
      assert.ok(window.document.getElementById("dashboard-directory-feature"));
      assert.ok(window.document.getElementById("directory_query"));
      for (const row of model.rows) {
        const card = window.document.getElementById("dashboard-" + row.id);
        assert.ok(card);
        assert.equal(card.getAttribute("data-dashboard-directory-starred"), String(row.starred));
        const open = window.document.getElementById("open-" + row.id);
        if (row.lifecycle === "active")
          assert.equal(
            open?.getAttribute("href"),
            "/missions/" +
              encodeURIComponent(model.mission_id) +
              "/ops/dashboards/" +
              encodeURIComponent(row.id) +
              (row.published_version === null && model.author ? "/edit" : ""),
          );
        else assert.equal(open, null);
      }
    } finally {
      await window.happyDOM.close();
    }
  }
  console.log("Directory producer/renderer contract passed.");
} finally {
  await server.close();
}
