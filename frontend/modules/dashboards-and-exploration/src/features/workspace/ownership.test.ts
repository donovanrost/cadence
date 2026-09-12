// @vitest-environment node
import { expect, test } from "vite-plus/test";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
test("workspace production code has no dependency on the legacy Ops application or event bus", () => {
  const dir = fileURLToPath(new URL(".", import.meta.url));
  for (const name of readdirSync(dir).filter((n) => /\.(ts|vue)$/.test(n) && !n.includes("test"))) {
    const source = readFileSync(dir + name, "utf8");
    expect(source, name).not.toMatch(
      /apps\/ops-console|from ["']\.\/ops-events|cadence:ops-event|window\.dispatchEvent/,
    );
  }
  const legacy = readFileSync(
    new URL("../../../../../apps/ops-console/src/OpsDashboardShow.vue", import.meta.url),
    "utf8",
  );
  expect(legacy).toContain("@cadence/dashboards-and-exploration/workspace");
  expect(legacy).not.toContain("<template>");
});
