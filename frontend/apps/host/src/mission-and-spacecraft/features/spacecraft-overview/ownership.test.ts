import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "vite-plus/test";
import { SpacecraftShow as publicComponent } from "../../spacecraft";
import SpacecraftShow from "./SpacecraftShow.vue";

test("the historical entry delegates to the host-owned feature through its public API", () => {
  expect(publicComponent).toBe(SpacecraftShow);
  const source = readFileSync(
    resolve(
      dirname(fileURLToPath(import.meta.url)),
      "../../../../../spacecraft/src/SpacecraftShow.vue",
    ),
    "utf8",
  );
  expect(source).toContain('import { SpacecraftShow } from "@cadence/plugin-host/spacecraft"');
  expect(source).toContain("export default SpacecraftShow;");
  expect(source).not.toContain("<template>");
});
