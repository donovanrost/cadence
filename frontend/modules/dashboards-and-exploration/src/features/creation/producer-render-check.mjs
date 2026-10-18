import { fixtureValue } from "../../../../../test-support/json-fixture.ts";
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
  ssr: { noExternal: ["@cadence/ui"] },
  logLevel: "error",
});
try {
  // Vite loads the checked module dynamically; its exported type supplies the SSR interop contract.
  const { creationContribution } = /** @type {typeof import("../../creation.ts")} */ (
    await server.ssrLoadModule("/src/creation.ts")
  );
  for (const raw of fixtureRows(process.argv[2])) {
    const props = creationContribution.read(
      { model: raw, sequence: 0, phase: "editing" },
      { organizationId: "producer-test", missionId: fixtureString(raw.mission_id) },
    );
    const model = props.state.model;
    // oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks the SFC constructor at this registration or render boundary.
    const app = createSSRApp(creationContribution.component, {
      ...props,
      port: {
        execute() {
          throw Error("Unexpected effect");
        },
        navigate() {},
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
      assert.ok(doc.getElementById("dashboard-new-form"));
      assert.equal(
        fixtureValue(doc.getElementById("dashboard-name")),
        model.source ? "Copy of " + model.source.name : "",
      );
      assert.equal(!!doc.getElementById("dashboard-document-json"), model.mode === "import");
      assert.equal(
        doc.getElementById("dashboard-clone-source")?.getAttribute("data-source-dashboard-id") ??
          null,
        model.source?.id ?? null,
      );
      assert.equal(
        required(doc.getElementById("dashboard-new-cancel")).getAttribute("href"),
        "/missions/" + encodeURIComponent(model.mission_id) + "/ops/dashboards",
      );
    } finally {
      await window.happyDOM.close();
    }
  }
  console.log("Creation producer/renderer contract passed.");
} finally {
  await server.close();
}
