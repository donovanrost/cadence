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
  server: { middlewareMode: true, hmr: false },
  logLevel: "error",
});
try {
  const { readSettingsModel, settingsContribution } =
    await server.ssrLoadModule("/src/settings.ts");
  for (const model of JSON.parse(process.argv[2])) {
    const context = {
      organizationId: model.organization_id,
      missionId: model.mission_id,
      resourceId: model.dashboard_id,
    };
    assert.deepEqual(readSettingsModel(model, context), model);
    const props = settingsContribution.read({ sequence: 0, phase: "ready", model }, context);
    const app = createSSRApp(settingsContribution.component, {
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
    const html = await renderToString(app);
    const window = new Window();
    try {
      window.document.body.innerHTML = html;
      const doc = window.document;
      assert.ok(doc.getElementById("dashboard-settings-feature"));
      assert.equal(doc.getElementById("settings-name").value, model.name);
      assert.equal(doc.getElementById("settings-defaults").value, model.defaults_json);
      assert.equal(doc.querySelectorAll("#settings-shares>li").length, model.shares.rows.length);
      assert.equal(
        doc.querySelectorAll("#settings-snapshot-list>li").length,
        model.snapshots.rows.length,
      );
      assert.equal(
        doc.querySelectorAll("#settings-deployments>li").length,
        model.deployments.rows.length,
      );
      assert.equal(!!doc.getElementById("settings-archived"), model.lifecycle === "archived");
      assert.equal(
        doc.getElementById("settings-export").getAttribute("href"),
        "/missions/" +
          encodeURIComponent(model.mission_id) +
          "/ops/dashboards/" +
          encodeURIComponent(model.dashboard_id) +
          "/export",
      );
    } finally {
      await window.happyDOM.close();
    }
    assert.throws(() => readSettingsModel(model, { ...context, resourceId: "foreign-dashboard" }));
    assert.throws(() => readSettingsModel({ ...model, revision: 0 }, context));
    assert.throws(() => readSettingsModel({ ...model, component: "UnapprovedComponent" }, context));
    assert.throws(() => readSettingsModel({ ...model, defaults_json: "[]" }, context));
  }
  console.log("Persisted settings producer/consumer contract passed.");
} finally {
  await server.close();
}
