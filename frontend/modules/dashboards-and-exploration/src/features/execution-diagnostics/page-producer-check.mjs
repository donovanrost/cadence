import {
  fixtureRows,
  fixtureString,
  fixtureRecord,
} from "../../../../../test-support/json-fixture.ts";
import { required } from "../../../../../test-support/required.ts";
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
  const { executionDiagnosticsContribution: contribution } =
    /** @type {typeof import("../../execution-diagnostics.ts")} */ (
      await server.ssrLoadModule("/src/execution-diagnostics.ts")
    );
  for (const raw of fixtureRows(process.argv[2])) {
    const rawModel = fixtureRecord(raw.model);
    const context = {
      organizationId: fixtureString(rawModel.organization_id),
      missionId: fixtureString(rawModel.mission_id),
      resourceId: fixtureString(rawModel.dashboard_id),
    };
    const props = contribution.read(raw, context);
    const state = required(props.state);
    assert.throws(() => contribution.read(state, { ...context, resourceId: "foreign" }));
    // oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks the SFC constructor at this registration or render boundary.
    const app = createSSRApp(contribution.component, {
      ...props,
      port: {
        execute() {
          throw Error("Unexpected effect");
        },
        navigate() {
          throw Error("Unexpected navigation");
        },
      },
      refresh() {
        throw Error("Unexpected refresh");
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
      assert.ok(doc.getElementById("execution-diagnostics-page"));
      assert.ok(doc.getElementById("diagnostics-inspect"));
      assert.equal(
        required(doc.getElementById("diagnostics-loaded-at")).getAttribute("datetime"),
        state.model.loaded_at,
      );
      assert.equal(
        required(
          doc.getElementById(`diagnostics-collection-${state.selection.collection}`),
        ).getAttribute("aria-current"),
        "true",
      );
      assert.equal(
        !!doc.getElementById("diagnostics-publication-changed"),
        state.publication_changed,
      );
      const viewer = new URL(
        required(required(doc.getElementById("diagnostics-viewer")).getAttribute("href")),
        "http://cadence.test",
      );
      assert.equal(
        viewer.pathname,
        `/missions/${encodeURIComponent(context.missionId)}/ops/dashboards/${encodeURIComponent(context.resourceId)}`,
      );
      assert.deepEqual(Object.fromEntries(viewer.searchParams), state.runtime_query);
    } finally {
      await window.happyDOM.close();
    }
  }
  console.log("Diagnostics page producer-to-Vue contract passed.");
} finally {
  await server.close();
}
