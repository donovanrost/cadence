import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const config = await readFile(new URL("./vite.phoenix.config.ts", import.meta.url), "utf8");
const federation = await readFile(
  new URL("./module-federation.config.ts", import.meta.url),
  "utf8",
);

test("publication config uses the mission-catalog asset boundary", () => {
  assert.match(config, /application-host\/mission-catalog/);
  assert.match(config, /CADENCE_RELEASE_OUTPUT_DIR|publicationRoot/);
  assert.match(federation, /cadence_mission_catalog/);
  assert.match(federation, /"\.\/Application"/);
  assert.doesNotMatch(federation, /CatalogImportRunShow/);
});
