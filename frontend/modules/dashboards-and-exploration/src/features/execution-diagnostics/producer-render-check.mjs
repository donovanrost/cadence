import { fixtureValue, fixtureRecord } from "../../../../../test-support/json-fixture.ts";
import { required } from "../../../../../test-support/required.ts";
import assert from "node:assert/strict";
import { createSSRApp } from "vue";
import { renderToString } from "vue/server-renderer";
import { Window } from "happy-dom";

/** Called with admitted native producer output.
 * @param {import("vite-plus").ViteDevServer} server
 * @param {ReturnType<typeof import("./validation.ts").readExecutionDiagnostics>} model
 * @param {import("@cadence/plugin-sdk/ops-pages").OpsPageContext} context */
export async function checkRenderer(server, model, context) {
  const loaded = fixtureRecord(await server.ssrLoadModule("/src/execution-diagnostics.ts"));
  const component = fixtureRecord(loaded.ExecutionDiagnosticsView);
  assert.equal(
    typeof component.ssrRender,
    "function",
    "Expected the compiled diagnostics renderer",
  );
  for (const collection of model.collections) {
    const selections = [
      collection.rows[0],
      ...collection.rows.filter((row) => row.kind === "plan_warning"),
    ];
    for (const selected of selections) {
      const app = createSSRApp(component, {
        model,
        context,
        selection: { collection: collection.id, row: selected?.id ?? null, filter: "" },
        onSelect() {
          throw Error("Rendering must not navigate or execute an inspection");
        },
      });
      app.config.warnHandler = (message) => {
        throw Error(message);
      };
      const html = await renderToString(app);
      const window = new Window();
      try {
        window.document.body.innerHTML = html;
        const doc = window.document;
        assert.ok(doc.getElementById("execution-diagnostics-feature"));
        assert.equal(doc.querySelector("main"), null);
        assert.equal(doc.querySelectorAll("nav button").length, 7);
        assert.equal(
          required(doc.getElementById("diagnostics-loaded-at")).getAttribute("datetime"),
          model.loaded_at,
        );
        assert.equal(
          !!doc.getElementById("diagnostics-unavailable"),
          collection.state === "unavailable",
        );
        assert.equal(
          !!doc.getElementById("diagnostics-local-warning"),
          collection.source === "process_local",
        );
        assert.equal(!!doc.getElementById("diagnostics-limited"), collection.limited);
        assert.equal(doc.querySelectorAll("#diagnostics-rows li").length, collection.rows.length);
        const ids = Array.from(doc.querySelectorAll("[id]"), (node) => node.id);
        assert.equal(new Set(ids).size, ids.length);
        if (selected) {
          assert.equal(fixtureValue(doc.getElementById("diagnostic-identity")), selected.identity);
          assert.equal(
            doc.querySelectorAll("[data-diagnostic-field]").length,
            selected.details.length,
          );
          for (const detail of selected.details) {
            assert.equal(
              required(
                doc.querySelector(`[data-diagnostic-field="${detail.key}"]`),
              ).textContent.trim(),
              detail.value === null
                ? "Not recorded"
                : detail.value === ""
                  ? "Empty"
                  : String(detail.value).trim(),
            );
          }
        }
      } finally {
        await window.happyDOM.close();
      }
    }
  }
}
