// @vitest-environment node
import { expect, test } from "vite-plus/test";
import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
test("directory production code stays feature-owned and the legacy remote delegates", () => {
  const feature = fileURLToPath(new URL(".", import.meta.url));
  for (const file of readdirSync(feature).filter(
    (name) => /\.(ts|vue)$/.test(name) && !name.includes("test"),
  )) {
    const source = readFileSync(join(feature, file), "utf8");
    expect(source).not.toMatch(
      /apps\/ops-console|cadence:ops-event|OPS_EVENT_BRIDGE|window\.dispatchEvent/,
    );
  }
  const adapter = readFileSync(
    new URL("../../../../../apps/ops-console/src/OpsDashboardDirectory.vue", import.meta.url),
    "utf8",
  );
  expect(adapter).toContain("@cadence/dashboards-and-exploration/directory");
  expect(adapter).not.toContain("<template>");
});
