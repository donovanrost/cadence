import { fixtureRows, fixtureContext } from "../../../../../test-support/json-fixture.ts";
import { required } from "../../../../../test-support/required.ts";
import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createServer } from "vite-plus";
import vue from "@vitejs/plugin-vue";
import { Window } from "happy-dom";
import { createSSRApp } from "vue";
import { renderToString } from "vue/server-renderer";

// Renders real Phoenix dashboard pages (view and edit) through the compiled contribution.
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
  const { dashboardContribution } = /** @type {typeof import("../../workspace.ts")} */ (
    await server.ssrLoadModule("/src/workspace.ts")
  );
  for (const envelope of fixtureRows(process.argv[2])) {
    assert.equal(envelope.id, dashboardContribution.id);
    assert.equal(envelope.slot, dashboardContribution.slot);
    assert.equal(envelope.version, dashboardContribution.version);
    const props = dashboardContribution.read(envelope.data, fixtureContext(envelope.context));
    // oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks the SFC constructor at this registration or render boundary.
    const app = createSSRApp(dashboardContribution.component, {
      ...props,
      port: {
        execute() {
          throw Error("Unexpected effect");
        },
        navigate() {},
        guardNavigation: () => () => {},
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
      const page = props.page;
      assert.ok(doc.getElementById("ops-dashboard-show-page"));
      if (!page.snapshot) {
        assert.ok(doc.body.textContent?.includes("Not published yet"));
        continue;
      }
      if (page.snapshot.placements.length)
        assert.ok(doc.querySelector(`[data-workspace-snapshot="${page.snapshot.dashboard_id}"]`));
      assert.equal(!!doc.querySelector('[aria-label="Dashboard editing"]'), page.mode === "edit");
      assert.ok(required(doc.getElementById("dashboard-time-range")));
    } finally {
      await window.happyDOM.close();
    }
  }
  console.log("Dashboard page producer/renderer contract passed.");
} finally {
  await server.close();
}
