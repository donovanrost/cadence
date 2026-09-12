import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createSSRApp } from "vue";
import { renderToString } from "vue/server-renderer";
import { Window } from "happy-dom";
import { createServer } from "vite-plus";
import vue from "@vitejs/plugin-vue";
const server = await createServer({
  configFile: false,
  root: resolve(dirname(fileURLToPath(import.meta.url)), "../../.."),
  plugins: [vue()],
  server: { middlewareMode: true, hmr: false },
  logLevel: "error",
});
try {
  const { CommandMonitor, readCommandMonitor, OpsCommands } = await server.ssrLoadModule(
    "/src/mission-commands.ts",
  );
  if (process.argv[3] === "legacy") {
    for (const props of JSON.parse(process.argv[2])) {
      const window = new Window();
      try {
        const doc = window.document;
        doc.body.innerHTML = await renderToString(createSSRApp(OpsCommands, props));
        const anchor = doc.getElementById("commands-open-workspace");
        assert.ok(anchor);
        const url = new URL(anchor.getAttribute("href"), "https://cadence.test");
        assert.equal(
          url.pathname,
          `/missions/${encodeURIComponent(props.mission_id)}/ops/commands`,
        );
        assert.deepEqual(Object.fromEntries(url.searchParams), props.query);
        assert.equal(doc.querySelector("form,button,[data-command-request]"), null);
      } finally {
        await window.happyDOM.close();
      }
    }
    console.log("Legacy command monitor producer/consumer contract passed.");
  } else
    for (const model of JSON.parse(process.argv[2])) {
      const context = { organizationId: model.organization_id, missionId: model.mission_id };
      assert.deepEqual(readCommandMonitor(model, context), model);
      assert.throws(() => readCommandMonitor(model, { ...context, missionId: "foreign" }));
      const forbidden = () => {
        throw Error("Read-only rendering must not navigate or execute");
      };
      const app = createSSRApp(CommandMonitor, {
        model,
        context,
        port: { navigate: forbidden },
        refresh: forbidden,
      });
      app.config.warnHandler = (message) => {
        throw Error(message);
      };
      const window = new Window();
      try {
        const doc = window.document;
        doc.body.innerHTML = await renderToString(app);
        assert.ok(doc.getElementById("command-monitor"));
        assert.equal(doc.querySelector("main"), null);
        assert.equal(
          doc.querySelectorAll("#command-monitor-rows [data-command-request]").length,
          model.rows.length,
        );
        assert.equal(!!doc.getElementById("command-monitor-empty"), model.status === "empty");
        assert.equal(
          doc.getElementById("command-monitor-observed").getAttribute("datetime"),
          model.observed_at,
        );
        const ids = Array.from(doc.querySelectorAll("[id]"), (e) => e.id);
        assert.equal(new Set(ids).size, ids.length);
        for (const row of model.rows) {
          const node = doc.getElementById(`command-request-${encodeURIComponent(row.id)}`);
          assert.ok(node);
          for (const [attribute, records] of [
            ["data-command-queue", row.queue ? [row.queue] : []],
            ["data-command-release", row.release ? [row.release] : []],
            ["data-command-verifier", row.verifiers],
          ]) {
            assert.deepEqual(
              Array.from(node.querySelectorAll(`[${attribute}]`), (e) => e.getAttribute(attribute)),
              records.map((r) => r.id),
            );
          }
        }
      } finally {
        await window.happyDOM.close();
      }
    }
  console.log("Persisted command monitor producer/consumer and Vue renderer contract passed.");
} finally {
  await server.close();
}
