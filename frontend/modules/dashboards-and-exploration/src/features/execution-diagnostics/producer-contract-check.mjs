import { fixtureRows, fixtureString } from "../../../../../test-support/json-fixture.ts";
import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createServer } from "vite-plus";
import vue from "@vitejs/plugin-vue";
import { checkRenderer } from "./producer-render-check.mjs";
const server = await createServer({
  configFile: false,
  root: resolve(dirname(fileURLToPath(import.meta.url)), "../../.."),
  plugins: [vue()],
  server: { middlewareMode: true, hmr: false },
  logLevel: "error",
});
try {
  const { readExecutionDiagnostics } =
    /** @type {typeof import("../../execution-diagnostics.ts")} */ (
      await server.ssrLoadModule("/src/execution-diagnostics.ts")
    );
  for (const raw of fixtureRows(process.argv[2])) {
    const context = {
      organizationId: fixtureString(raw.organization_id),
      missionId: fixtureString(raw.mission_id),
      resourceId: fixtureString(raw.dashboard_id),
    };
    const model = readExecutionDiagnostics(raw, context);
    assert.deepEqual(model, raw);
    assert.throws(() => readExecutionDiagnostics(model, { ...context, missionId: "foreign" }));
    await checkRenderer(server, model, context);
  }
  console.log("Persisted execution diagnostics contract passed (including the Vue renderer).");
} finally {
  await server.close();
}
