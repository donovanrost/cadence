import {
  fixtureRows,
  fixtureString,
  fixtureRecord,
} from "../../../../../test-support/json-fixture.ts";
import { required } from "../../../../../test-support/required.ts";
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
    /** @type {typeof import("../../command-history.ts")} */ (
      await server.ssrLoadModule("/src/command-history.ts")
    );
  for (const raw of fixtureRows(process.argv[2])) {
    const context = {
      organizationId: fixtureString(raw.organization_id),
      missionId: fixtureString(raw.mission_id),
      resourceId: fixtureString(fixtureRecord(raw.request).id),
    };
    const model = readCommandHistory(raw, context);
    assert.deepEqual(model, raw);
    for (const key of Object.keys(context))
      assert.throws(() => readCommandHistory(model, { ...context, [key]: "foreign" }));
    const forbidden = () => {
      throw Error("Rendering must not navigate or execute");
    };
    // oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks this SFC constructor.
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
      for (const kind of /** @type {const} */ (["release", "verifier"])) {
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
          required(doc.querySelector("[data-command-evidence]")).getAttribute(
            "data-command-evidence",
          ),
          model.evidence.record.id,
        );
        if (model.evidence.record.kind === "telemetry_sample") {
          assert.equal(
            required(doc.getElementById("command-history-raw-value")).textContent,
            model.evidence.record.raw_value_json,
          );
          assert.equal(
            required(doc.getElementById("command-history-engineering-value")).textContent,
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
