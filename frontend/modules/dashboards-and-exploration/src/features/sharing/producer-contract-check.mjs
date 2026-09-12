import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createServer } from "vite-plus";
import vue from "@vitejs/plugin-vue";
import { createSSRApp } from "vue";
import { renderToString } from "vue/server-renderer";
import { Window } from "happy-dom";
const server = await createServer({
  configFile: false,
  root: resolve(dirname(fileURLToPath(import.meta.url)), "../../.."),
  plugins: [vue()],
  // GridStack 10 publishes ESM with extensionless internal imports.
  ssr: { noExternal: ["@cadence/ui", "gridstack"] },
  server: { middlewareMode: true, hmr: false },
  logLevel: "error",
});
try {
  const { shareContribution, snapshotContribution, readSharedView } =
    await server.ssrLoadModule("/src/sharing.ts");
  for (const model of JSON.parse(process.argv[2])) {
    const context = {
      organizationId: model.organization_id,
      missionId: model.mission_id,
      resourceId: model.id,
    };
    const registration = model.kind === "share" ? shareContribution : snapshotContribution;
    const props = registration.read(model, context);
    const app = createSSRApp(registration.component, {
      ...props,
      refresh: async () => {},
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
      assert.ok(doc.getElementById("shared-dashboard-feature"));
      assert.equal(!!doc.getElementById("shared-view-unpublished"), model.definition === null);
      assert.equal(!!doc.querySelector("[data-workspace-snapshot]"), model.canvas !== null);
      if (model.definition)
        assert.deepEqual(
          JSON.parse(doc.querySelector("#shared-view-definition pre").textContent),
          JSON.parse(model.definition.json),
        );
      if (model.canvas)
        assert.ok(doc.getElementById("shared-dashboard-feature").textContent.includes("28.4"));
      assert.equal(
        doc.getElementById("shared-view-directory").getAttribute("href"),
        "/missions/" + encodeURIComponent(model.mission_id) + "/ops/dashboards",
      );
    } finally {
      await window.happyDOM.close();
    }
    assert.throws(() => readSharedView(model, { ...context, resourceId: "foreign" }, model.kind));
    if (model.canvas)
      assert.throws(() =>
        readSharedView({ ...model, data_visibility: "definition_only" }, context, model.kind),
      );
  }
  console.log("Persisted shared view contract passed.");
} finally {
  await server.close();
}
