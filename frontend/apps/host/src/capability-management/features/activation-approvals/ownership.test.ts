import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "vite-plus/test";
import { OpsActivationRequests as publicComponent } from "../../index";
import OpsActivationRequests from "./OpsActivationRequests.vue";
test("Ops delegates activation approvals through the host public API", () => {
  expect(publicComponent).toBe(OpsActivationRequests);
  const source = readFileSync(
    resolve(
      dirname(fileURLToPath(import.meta.url)),
      "../../../../../ops-console/src/OpsActivationRequests.vue",
    ),
    "utf8",
  );
  expect(source).toContain("@cadence/plugin-host/capability-management");
  expect(source).not.toContain("<template>");
});
