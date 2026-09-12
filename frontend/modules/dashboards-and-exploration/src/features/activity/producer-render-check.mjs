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
  const { activityContribution } = await server.ssrLoadModule("/src/activity.ts");
  for (const model of JSON.parse(process.argv[2])) {
    const props = activityContribution.read(
      { model, sequence: 0, phase: "ready" },
      {
        organizationId: model.organization_id,
        missionId: model.mission_id,
        resourceId: model.dashboard_id,
      },
    );
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
        doc.getElementById("activity-selected-title").textContent.trim(),
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
