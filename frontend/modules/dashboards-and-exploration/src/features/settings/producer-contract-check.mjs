import { fixtureValue } from "../../../../../test-support/json-fixture.ts";
import { required } from "../../../../../test-support/required.ts";
import { fixtureRows, fixtureString } from "../../../../../test-support/json-fixture.ts";
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
  // Vite loads the checked module dynamically; its exported type supplies the SSR interop contract.
  const { readSettingsModel, settingsContribution } =
    /** @type {typeof import("../../settings.ts")} */ (
      await server.ssrLoadModule("/src/settings.ts")
    );
  for (const raw of fixtureRows(process.argv[2])) {
    const context = {
      organizationId: fixtureString(raw.organization_id),
      missionId: fixtureString(raw.mission_id),
      resourceId: fixtureString(raw.dashboard_id),
    };
    assert.deepEqual(readSettingsModel(raw, context), raw);
    const props = settingsContribution.read({ sequence: 0, phase: "ready", model: raw }, context);
    const model = props.state.model;
    // oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks the SFC constructor at this registration or render boundary.
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
      assert.equal(fixtureValue(doc.getElementById("settings-name")), model.name);
      assert.equal(fixtureValue(doc.getElementById("settings-defaults")), model.defaults_json);
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
        required(doc.getElementById("settings-export")).getAttribute("href"),
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
