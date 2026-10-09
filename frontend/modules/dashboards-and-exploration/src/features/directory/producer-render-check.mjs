import {
  fixtureRecord,
  fixtureRows,
  fixtureString,
} from "../../../../../test-support/json-fixture.ts";
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
  const { directoryContribution } = /** @type {typeof import("../../directory.ts")} */ (
    await server.ssrLoadModule("/src/directory.ts")
  );
  for (const raw of fixtureRows(process.argv[2])) {
    const model = fixtureRecord(raw.model);
    const props = directoryContribution.read(raw, {
      organizationId: "producer-test",
      missionId: fixtureString(model.mission_id),
    });
    // oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks the SFC constructor at this registration or render boundary.
    const app = createSSRApp(directoryContribution.component, {
      ...props,
      port: {
        execute: () => {
          throw Error("Unexpected effect");
        },
        navigate() {},
      },
      refresh: async () => {},
    });
    app.config.warnHandler = (message) => {
      throw Error(message);
    };
    const html = await renderToString(app);
    const window = new Window();
    try {
      window.document.body.innerHTML = html;
      assert.ok(window.document.getElementById("dashboard-directory-feature"));
      const read = props.page.model;
      if (read.total === 0 && read.filters.query === "" && !read.filters.archived) {
        assert.ok(window.document.getElementById("dashboard-directory-first-run"));
        continue;
      }
      assert.ok(window.document.getElementById("dashboard-directory-search"));
      for (const row of read.rows) {
        const item = window.document.getElementById("dashboard-" + row.id);
        assert.ok(item);
        assert.equal(item.getAttribute("data-starred"), String(row.starred));
        const link = item.querySelector("a");
        if (row.archived) assert.equal(link, null);
        else
          assert.equal(
            link?.getAttribute("href"),
            "/missions/" +
              encodeURIComponent(read.mission_id) +
              "/ops/dashboards/" +
              encodeURIComponent(row.id),
          );
      }
    } finally {
      await window.happyDOM.close();
    }
  }
  console.log("Directory producer/renderer contract passed.");
} finally {
  await server.close();
}
