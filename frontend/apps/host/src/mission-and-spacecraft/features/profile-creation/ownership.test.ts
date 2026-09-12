import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "vite-plus/test";
import { SpacecraftTypeNew as publicForm } from "../../spacecraft";
import SpacecraftTypeNew from "./SpacecraftTypeNew.vue";
test("the historical profile entry delegates to the host public API", () => {
  expect(publicForm).toBe(SpacecraftTypeNew);
  const source = readFileSync(
    resolve(
      dirname(fileURLToPath(import.meta.url)),
      "../../../../../spacecraft/src/SpacecraftTypeNew.vue",
    ),
    "utf8",
  );
  expect(source).toContain('import { SpacecraftTypeNew } from "@cadence/plugin-host/spacecraft"');
  expect(source).toContain("export default SpacecraftTypeNew;");
  expect(source).not.toContain("<template>");
});
