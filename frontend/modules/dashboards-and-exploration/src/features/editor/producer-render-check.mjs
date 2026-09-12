import {
  fixtureRows,
  fixtureString,
  fixtureNumber,
  fixtureContext,
  fixtureRecord,
} from "../../../../../test-support/json-fixture.ts";
import { fixtureValue } from "../../../../../test-support/json-fixture.ts";
import { required } from "../../../../../test-support/required.ts";
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
  const { editorContribution } = /** @type {typeof import("../../editor.ts")} */ (
    await server.ssrLoadModule("/src/editor.ts")
  );
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
  const { default: RuntimeDefaultsFields } =
    /** @type {typeof import("../../features/editor/RuntimeDefaultsFields.vue")} */ (
      await server.ssrLoadModule("/src/features/editor/RuntimeDefaultsFields.vue")
    );
  const { readObservableChoices } =
    /** @type {typeof import("../../features/editor/validation.ts")} */ (
      await server.ssrLoadModule("/src/features/editor/validation.ts")
    );
  for (const choices of fixtureRows(process.argv[3] || "[]")) {
    const context = {
      organizationId: fixtureString(choices.organization_id),
      missionId: fixtureString(choices.mission_id),
      resourceId: fixtureString(choices.dashboard_id),
    };
    assert.equal(
      readObservableChoices(
        choices,
        context,
        fixtureNumber(choices.document_version),
        fixtureString(choices.query),
        fixtureNumber(choices.staging_revision),
      ).options.length,
      Array.isArray(choices.options) ? choices.options.length : -1,
    );
  }
  for (const page of fixtureRows(process.argv[2])) {
    assert.equal(page.id, editorContribution.id);
    assert.equal(page.slot, editorContribution.slot);
    assert.equal(page.version, editorContribution.version);
    const props = editorContribution.read(page.data, fixtureContext(page.context));
    const model = props.state.model;
    // oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks the SFC constructor at this registration or render boundary.
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
        required(doc.getElementById("editor-version")).textContent,
        `Draft v${model.document_version}`,
      );
      assert.equal(fixtureValue(doc.getElementById("editor-name")), model.name);
      assert.equal(doc.querySelectorAll("[data-editor-widget]").length, model.placements.length);
      assert.equal(
        required(doc.getElementById("editor-directory")).getAttribute("href"),
        `/missions/${encodeURIComponent(model.mission_id)}/ops/dashboards`,
      );
      assert.ok(doc.getElementById("editor-runtime"));
      doc.body.innerHTML = await renderToString(
        // oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks the SFC constructor at this registration or render boundary.
        createSSRApp(RuntimeDefaultsFields, {
          modelValue: props.state.model.runtime_defaults_json,
        }),
      );
      assert.deepEqual(
        JSON.parse(fixtureValue(doc.getElementById("editor-runtime-json"))),
        JSON.parse(model.runtime_defaults_json),
      );
      const defaults = fixtureRecord(JSON.parse(model.runtime_defaults_json));
      assert.equal(
        fixtureValue(doc.getElementById("editor-runtime-time-mode")),
        defaults.time ? (fixtureRecord(defaults.time).mode ?? "") : "",
      );
      assert.equal(
        fixtureValue(doc.getElementById("editor-runtime-data-realm")),
        defaults.data ? (fixtureRecord(defaults.data).realm ?? "") : "",
      );
    } finally {
      await window.happyDOM.close();
    }
  }
  console.log("Editor producer/renderer contract passed.");
} finally {
  await server.close();
}
