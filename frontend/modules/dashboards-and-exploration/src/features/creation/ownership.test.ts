// @vitest-environment node
import { expect, test } from "vite-plus/test";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
test("creation owns its implementation and the historical entry delegates through the public export", () => {
  const dir = fileURLToPath(new URL(".", import.meta.url));
  for (const file of readdirSync(dir).filter(
    (file) => /\.(vue|ts)$/.test(file) && !file.includes(".test."),
  )) {
    const source = readFileSync(dir + file, "utf8");
    expect(source).not.toMatch(/apps\/ops-console|window\.dispatchEvent|application-bridge/);
  }
  const entry = readFileSync(
    new URL("../../../../../apps/ops-console/src/OpsDashboardNew.vue", import.meta.url),
    "utf8",
  );
  expect(entry).toContain("@cadence/dashboards-and-exploration/creation");
  expect(entry).not.toContain("<template>");
});
