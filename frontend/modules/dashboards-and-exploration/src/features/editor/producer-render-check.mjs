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
  // GridStack 10 publishes ESM with extensionless internal imports.
  ssr: { noExternal: ["@cadence/ui", "gridstack"] },
  logLevel: "error",
});
try {
  const { editorContribution } = await server.ssrLoadModule("/src/editor.ts");
  const { default: RuntimeDefaultsFields } = await server.ssrLoadModule(
    "/src/features/editor/RuntimeDefaultsFields.vue",
  );
  const { readObservableChoices } = await server.ssrLoadModule(
    "/src/features/editor/validation.ts",
  );
  for (const choices of JSON.parse(process.argv[3] || "[]")) {
    const context = {
      organizationId: choices.organization_id,
      missionId: choices.mission_id,
      resourceId: choices.dashboard_id,
    };
    assert.equal(
      readObservableChoices(
        choices,
        context,
        choices.document_version,
        choices.query,
        choices.staging_revision,
      ).options.length,
      choices.options.length,
    );
  }
  for (const page of JSON.parse(process.argv[2])) {
    assert.equal(page.id, editorContribution.id);
    assert.equal(page.slot, editorContribution.slot);
    assert.equal(page.version, editorContribution.version);
    const props = editorContribution.read(page.data, page.context);
    const app = createSSRApp(editorContribution.component, {
      ...props,
      port: {
        execute() {
          throw Error("Unexpected effect");
        },
        navigate() {},
        guardNavigation() {
          return () => {};
        },
      },
      refresh: async () => {},
    });
    app.config.warnHandler = (message) => {
      throw Error(message);
    };
    const html = await renderToString(app),
      window = new Window();
    try {
      window.document.body.innerHTML = html;
      const doc = window.document;
      assert.ok(doc.getElementById("dashboard-editor-feature"));
      assert.equal(
        doc.getElementById("editor-version").textContent,
        `Draft v${page.data.model.document_version}`,
      );
      assert.equal(doc.getElementById("editor-name").value, page.data.model.name);
      assert.equal(
        doc.querySelectorAll("[data-editor-widget]").length,
        page.data.model.placements.length,
      );
      assert.equal(
        doc.getElementById("editor-directory").getAttribute("href"),
        `/missions/${encodeURIComponent(page.data.model.mission_id)}/ops/dashboards`,
      );
      assert.ok(doc.getElementById("editor-runtime"));
      doc.body.innerHTML = await renderToString(
        createSSRApp(RuntimeDefaultsFields, {
          modelValue: props.state.model.runtime_defaults_json,
        }),
      );
      assert.deepEqual(
        JSON.parse(doc.getElementById("editor-runtime-json").value),
        JSON.parse(page.data.model.runtime_defaults_json),
      );
      const defaults = JSON.parse(page.data.model.runtime_defaults_json);
      assert.equal(doc.getElementById("editor-runtime-time-mode").value, defaults.time?.mode ?? "");
      assert.equal(
        doc.getElementById("editor-runtime-data-realm").value,
        defaults.data?.realm ?? "",
      );
    } finally {
      await window.happyDOM.close();
    }
  }
  console.log("Editor producer/renderer contract passed.");
} finally {
  await server.close();
}
