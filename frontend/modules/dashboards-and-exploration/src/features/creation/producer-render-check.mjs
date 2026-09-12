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
  const { creationContribution } = await server.ssrLoadModule("/src/creation.ts");
  for (const model of JSON.parse(process.argv[2])) {
    const props = creationContribution.read(
      { model, sequence: 0, phase: "editing" },
      { organizationId: "producer-test", missionId: model.mission_id },
    );
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
        doc.getElementById("dashboard-name").value,
        model.source ? "Copy of " + model.source.name : "",
      );
      assert.equal(!!doc.getElementById("dashboard-document-json"), model.mode === "import");
      assert.equal(
        doc.getElementById("dashboard-clone-source")?.getAttribute("data-source-dashboard-id") ??
          null,
        model.source?.id ?? null,
      );
      assert.equal(
        doc.getElementById("dashboard-new-cancel").getAttribute("href"),
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
