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
  const { commandHistoryContribution: contribution, readCommandHistory } =
    await server.ssrLoadModule("/src/command-history.ts");
  for (const model of JSON.parse(process.argv[2])) {
    const context = {
      organizationId: model.organization_id,
      missionId: model.mission_id,
      resourceId: model.request.id,
    };
    assert.deepEqual(readCommandHistory(model, context), model);
    for (const key of Object.keys(context))
      assert.throws(() => readCommandHistory(model, { ...context, [key]: "foreign" }));
    const forbidden = () => {
      throw Error("Rendering must not navigate or execute");
    };
    const app = createSSRApp(contribution.component, {
      ...contribution.read(model, context),
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
      assert.ok(doc.getElementById("command-history"));
      assert.equal(doc.querySelector("main,form"), null);
      const ids = Array.from(doc.querySelectorAll("[id]"), (e) => e.id);
      assert.equal(new Set(ids).size, ids.length);
      for (const kind of ["release", "verifier"]) {
        assert.deepEqual(
          Array.from(doc.querySelectorAll(`[data-history-${kind}]`), (e) =>
            e.getAttribute(`data-history-${kind}`),
          ),
          model[`${kind}s`].entries.map((r) => r.id),
        );
        assert.equal(
          doc.querySelector(`[data-selected-${kind}]`)?.getAttribute(`data-selected-${kind}`) ??
            null,
          model.selection[kind]?.id ?? null,
        );
      }
      if (model.evidence.status === "ready") {
        assert.equal(
          doc.querySelector("[data-command-evidence]").getAttribute("data-command-evidence"),
          model.evidence.record.id,
        );
        if (model.evidence.record.kind === "telemetry_sample") {
          assert.equal(
            doc.getElementById("command-history-raw-value").textContent,
            model.evidence.record.raw_value_json,
          );
          assert.equal(
            doc.getElementById("command-history-engineering-value").textContent,
            model.evidence.record.engineering_value_json,
          );
        }
      }
    } finally {
      await window.happyDOM.close();
    }
  }
  console.log("Command history native producer and real Vue contract passed");
} finally {
  await server.close();
}
