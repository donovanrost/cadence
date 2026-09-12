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
  logLevel: "error",
});
try {
  const { libraryContribution } = await server.ssrLoadModule("/src/library.ts");
  for (const model of JSON.parse(process.argv[2])) {
    const props = libraryContribution.read(
      { model, sequence: 0, phase: "ready" },
      { organizationId: model.organization_id, missionId: model.mission_id },
    );
    const app = createSSRApp(libraryContribution.component, {
      ...props,
      port: {
        execute() {
          throw Error("Unexpected effect");
        },
        navigate() {},
      },
    });
    app.config.warnHandler = (message) => {
      throw Error(message);
    };
    const html = await renderToString(app),
      window = new Window();
    try {
      window.document.body.innerHTML = html;
      const doc = window.document;
      assert.ok(doc.getElementById("dashboard-library-feature"));
      assert.equal(doc.querySelectorAll("#library-items>li").length, model.items.length);
      assert.equal(!!doc.getElementById("library-selected"), model.selected !== null);
      if (model.selected) {
        assert.equal(
          doc.getElementById("library-selected-name").textContent.trim(),
          model.selected.item.name,
        );
        assert.equal(
          doc.querySelectorAll("#library-consumers>li").length,
          model.selected.consumers.rows.length,
        );
        assert.equal(doc.getElementById("library-widget-json").value, model.selected.widget_json);
      }
      assert.equal(
        doc.getElementById("library-add-to-draft").disabled,
        !model.selected || !model.target,
      );
    } finally {
      await window.happyDOM.close();
    }
  }
  console.log("Library producer/renderer contract passed.");
} finally {
  await server.close();
}
