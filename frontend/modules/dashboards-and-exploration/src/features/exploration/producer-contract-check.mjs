import { fixtureRows, fixtureString } from "../../../../../test-support/json-fixture.ts";
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
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
  const { readExploration, ExplorationPanel, ExplorationLegacyRedirect } =
    /** @type {typeof import("../../exploration.ts")} */ (
      await server.ssrLoadModule("/src/exploration.ts")
    );
  if (process.argv[3] === "legacy") {
    for (const props of fixtureRows(process.argv[2])) {
      // oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks the SFC constructor at this registration or render boundary.
      const app = createSSRApp(ExplorationLegacyRedirect, props);
      app.config.warnHandler = (message) => {
        throw Error(message);
      };
      const window = new Window();
      try {
        const doc = window.document;
        doc.body.innerHTML = await renderToString(app);
        assert.equal(doc.querySelector("form"), null);
        const anchor = doc.getElementById("exploration-open-workspace");
        assert.ok(anchor);
        const url = new URL(required(anchor.getAttribute("href")), "https://cadence.test");
        assert.equal(
          url.pathname,
          `/missions/${encodeURIComponent(fixtureString(props.mission_id))}/ops/explore`,
        );
        assert.deepEqual(Object.fromEntries(url.searchParams), props.query);
      } finally {
        await window.happyDOM.close();
      }
    }
    console.log("Legacy exploration producer/consumer contract passed.");
  } else {
    for (const raw of fixtureRows(process.argv[2])) {
      const context = {
        organizationId: fixtureString(raw.organization_id),
        missionId: fixtureString(raw.mission_id),
      };
      const model = readExploration(raw, context);
      assert.deepEqual(readExploration(model, context), model);
      assert.throws(() => readExploration(model, { ...context, missionId: "foreign" }));
      const noAction = () => {
        throw Error("Rendering must not execute or navigate");
      };
      // oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks the SFC constructor at this registration or render boundary.
      const app = createSSRApp(ExplorationPanel, {
        model,
        context,
        port: { execute: noAction, navigate: noAction },
        refresh: noAction,
      });
      app.config.warnHandler = (message) => {
        throw Error(message);
      };
      const html = await renderToString(app);
      const window = new Window();
      try {
        const doc = window.document;
        doc.body.innerHTML = html;
        assert.ok(doc.getElementById("exploration-feature"));
        assert.ok(doc.getElementById("exploration-query"));
        assert.equal(doc.querySelector("main"), null);
        const origin = doc.getElementById("exploration-open-origin");
        if (model.origin.status === "ready") {
          assert.ok(origin);
          assert.equal(
            origin.getAttribute("href"),
            `/missions/${encodeURIComponent(model.mission_id)}/ops/dashboards/${encodeURIComponent(model.origin.dashboard.id)}`,
          );
          assert.ok(
            required(doc.getElementById("exploration-origin")).textContent.includes(
              model.origin.dashboard.name,
            ),
          );
        } else {
          assert.equal(origin, null);
          assert.equal(
            !!doc.getElementById("exploration-origin-unavailable"),
            model.origin.status === "unavailable",
          );
        }
        assert.equal(
          doc.querySelectorAll("#exploration-results tbody tr").length,
          model.rows.length,
        );
        assert.equal(
          required(doc.getElementById("exploration-loaded-at")).getAttribute("datetime"),
          model.loaded_at,
        );
        const ids = Array.from(doc.querySelectorAll("[id]"), (node) => node.id);
        assert.equal(new Set(ids).size, ids.length);
        assert.equal(!!doc.getElementById("exploration-selection"), !!model.query.sample_id);
        if (model.inspection.status === "ready") {
          const sample = model.inspection.sample;
          assert.ok(doc.getElementById("exploration-sample-details"));
          assert.equal(
            required(doc.getElementById("exploration-sample-receipt")).getAttribute("datetime"),
            sample.receipt_time,
          );
          if (sample.generation_time)
            assert.equal(
              required(doc.getElementById("exploration-sample-generation")).getAttribute(
                "datetime",
              ),
              sample.generation_time,
            );
          for (const key of /** @type {const} */ (["raw_value", "engineering_value"]))
            if (sample[key].state === "ready")
              assert.equal(
                required(doc.getElementById(`exploration-sample-${key}`)).textContent,
                sample[key].text,
              );
          assert.equal(
            required(doc.getElementById("exploration-sample-source")).textContent,
            sample.source.data_source_id,
          );
          assert.equal(
            required(doc.getElementById("exploration-sample-binding")).textContent,
            sample.source.source_binding_id,
          );
        } else {
          assert.equal(doc.getElementById("exploration-sample-details"), null);
          if (model.query.sample_id) assert.ok(doc.getElementById("exploration-sample-state"));
        }
        for (const row of model.rows) {
          const element = doc.querySelector(`[data-observation-key="${row.key}"]`);
          assert.ok(element);
          if (row.time)
            assert.equal(
              required(element.querySelector("time")).getAttribute("datetime"),
              row.time,
            );
          if (row.sample_id)
            assert.equal(required(element.querySelector("button")).textContent, row.sample_id);
        }
      } finally {
        await window.happyDOM.close();
      }
    }
    console.log("Persisted exploration producer/consumer and Vue renderer contract passed.");
  }
} finally {
  await server.close();
}
