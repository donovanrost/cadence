import { fixtureValue, fixtureDisabled } from "../../../../../test-support/json-fixture.ts";
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
  const { libraryContribution } = /** @type {typeof import("../../library.ts")} */ (
    await server.ssrLoadModule("/src/library.ts")
  );
  for (const raw of fixtureRows(process.argv[2])) {
    const props = libraryContribution.read(
      { model: raw, sequence: 0, phase: "ready" },
      {
        organizationId: fixtureString(raw.organization_id),
        missionId: fixtureString(raw.mission_id),
      },
    );
    const model = props.state.model;
    // oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks the SFC constructor at this registration or render boundary.
    const app = createSSRApp(libraryContribution.component, {
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
      assert.ok(doc.getElementById("dashboard-library-feature"));
      assert.equal(doc.querySelectorAll("#library-items>li").length, model.items.length);
      assert.equal(!!doc.getElementById("library-selected"), model.selected !== null);
      if (model.selected) {
        assert.equal(
          required(doc.getElementById("library-selected-name")).textContent.trim(),
          model.selected.item.name,
        );
        assert.equal(
          doc.querySelectorAll("#library-consumers>li").length,
          model.selected.consumers.rows.length,
        );
        assert.equal(
          fixtureValue(doc.getElementById("library-widget-json")),
          model.selected.widget_json,
        );
      }
      assert.equal(
        fixtureDisabled(doc.getElementById("library-add-to-draft")),
        !model.selected || !model.target,
      );
    } finally {
      await window.happyDOM.close();
    }
  }
  console.log("Library producer/renderer contract passed.");
} finally {
  await server.close();
}
