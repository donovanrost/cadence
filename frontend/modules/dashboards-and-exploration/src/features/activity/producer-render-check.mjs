import { required } from "../../../../../test-support/required.ts";
import { fixtureRows, fixtureString } from "../../../../../test-support/json-fixture.ts";
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
  // Vite loads the checked module dynamically; its exported type supplies the SSR interop contract.
  const { activityContribution } = /** @type {typeof import("../../activity.ts")} */ (
    await server.ssrLoadModule("/src/activity.ts")
  );
  for (const raw of fixtureRows(process.argv[2])) {
    const props = activityContribution.read(
      { model: raw, sequence: 0, phase: "ready" },
      {
        organizationId: fixtureString(raw.organization_id),
        missionId: fixtureString(raw.mission_id),
        resourceId: fixtureString(raw.dashboard_id),
      },
    );
    const model = props.state.model;
    // oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks the SFC constructor at this registration or render boundary.
    const app = createSSRApp(activityContribution.component, {
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
      assert.ok(doc.getElementById("dashboard-activity-feature"));
      assert.equal(
        required(doc.getElementById("activity-selected-title")).textContent.trim(),
        `Version ${model.selected.version}`,
      );
      assert.equal(doc.querySelectorAll("#activity-versions > li").length, model.versions.length);
      assert.equal(doc.querySelectorAll("#activity-events > li").length, model.events.length);
      assert.equal(!!doc.getElementById("activity-restore"), model.author && !model.archived);
      assert.equal(!!doc.getElementById("activity-older-versions"), model.next_version !== null);
    } finally {
      await window.happyDOM.close();
    }
  }
  console.log("Activity producer/renderer contract passed.");
} finally {
  await server.close();
}
