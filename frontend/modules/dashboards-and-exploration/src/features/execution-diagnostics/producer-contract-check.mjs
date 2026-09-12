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
  const { readExecutionDiagnostics } = await server.ssrLoadModule("/src/execution-diagnostics.ts");
  for (const model of JSON.parse(process.argv[2])) {
    const context = {
      organizationId: model.organization_id,
      missionId: model.mission_id,
      resourceId: model.dashboard_id,
    };
    assert.deepEqual(readExecutionDiagnostics(model, context), model);
    assert.throws(() => readExecutionDiagnostics(model, { ...context, missionId: "foreign" }));
    await checkRenderer(server, model, context);
  }
  console.log("Persisted execution diagnostics contract passed (including the Vue renderer).");
} finally {
  await server.close();
}
