import { fixtureRows, fixtureContext } from "../../../../../test-support/json-fixture.ts";
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
  const { workspaceContribution } = /** @type {typeof import("../../workspace.ts")} */ (
    await server.ssrLoadModule("/src/workspace.ts")
  );
  for (const page of fixtureRows(process.argv[2])) {
    assert.equal(page.id, workspaceContribution.id);
    assert.equal(page.slot, workspaceContribution.slot);
    assert.equal(page.version, workspaceContribution.version);
    const props = workspaceContribution.read(page.data, fixtureContext(page.context));
    // oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks the SFC constructor at this registration or render boundary.
    const app = createSSRApp(workspaceContribution.component, {
      ...props,
      port: {
        execute() {
          throw Error("Unexpected effect");
        },
        navigate() {},
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
      if (props.requirement) {
        assert.ok(doc.getElementById("dashboard-publication-required"));
        assert.equal(
          !!doc.getElementById("dashboard-publication-editor"),
          props.requirement.author,
        );
        assert.equal(!!doc.getElementById("dashboard-workspace-feature"), false);
        continue;
      }
      const model = props.model;
      assert.ok(model);
      assert.ok(doc.getElementById("dashboard-workspace-feature"));
      assert.equal(required(doc.getElementById("dashboard-viewer-title")).textContent, model.name);
      assert.equal(
        required(doc.getElementById("dashboard-viewer-version")).textContent,
        `Published v${model.document_version}`,
      );
      assert.equal(
        fixtureValue(doc.getElementById("dashboard-viewer-mode")),
        model.context.time_mode,
      );
      assert.equal(!!doc.getElementById("dashboard-viewer-edit"), model.author);
      assert.equal(
        required(doc.getElementById("dashboard-viewer-directory")).getAttribute("href"),
        `/missions/${encodeURIComponent(model.mission_id)}/ops/dashboards`,
      );
    } finally {
      await window.happyDOM.close();
    }
  }
  console.log("Workspace viewer producer/renderer contract passed.");
} finally {
  await server.close();
}
