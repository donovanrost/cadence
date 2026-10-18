import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "vite-plus/test";
import { SpacecraftReadiness as publicComponent } from "../../spacecraft";
import SpacecraftReadiness from "./SpacecraftReadiness.vue";

test("the historical entry delegates to the host-owned feature through its public API", () => {
  expect(publicComponent).toBe(SpacecraftReadiness);
  const source = readFileSync(
    resolve(
      dirname(fileURLToPath(import.meta.url)),
      "../../../../../spacecraft/src/SpacecraftReadiness.vue",
    ),
    "utf8",
  );
  expect(source).toContain('import { SpacecraftReadiness } from "@cadence/plugin-host/spacecraft"');
  expect(source).toContain("export default SpacecraftReadiness;");
  expect(source).not.toContain("<template>");
});
