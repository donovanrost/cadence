import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";

const root = new URL("./src/", import.meta.url);
const requiredPages = [
  "MissionList.vue",
  "MissionTable.vue",
  "MissionNew.vue",
  "MissionOverview.vue",
  "MissionApplications.vue",
  "MissionApplicationsPage.vue",
  "CatalogArtifactShow.vue",
  "CatalogArtifactShowPage.vue",
  "CatalogDatabaseNew.vue",
  "CatalogDatabaseShow.vue",
  "CatalogDatabaseTable.vue",
  "CatalogImportRunShow.vue",
  "CatalogIndex.vue",
  "CatalogRevisionShow.vue",
  "CatalogUploadForm.vue",
];

async function filesUnder(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const path = join(directory.pathname, entry.name);
    if (entry.isDirectory()) files.push(...(await filesUnder(new URL(`file://${path}/`))));
    else if (/\.(vue|ts|js)$/.test(entry.name)) files.push(path);
  }
  return files;
}

test("mission and catalog pages are self-contained first-party remote code", async () => {
  for (const page of requiredPages) {
    await readFile(new URL(page, root), "utf8");
  }

  const source = (
    await Promise.all((await filesUnder(root)).map((path) => readFile(path, "utf8")))
  ).join("\n");

  const legacyVueImport = ["apps", "cadence_web", "assets", "vue"].join("/");
  const phoenixUploadPackage = ["live", "vue"].join("_");
  assert.doesNotMatch(source, new RegExp(legacyVueImport));
  assert.doesNotMatch(source, new RegExp(`from ["']${phoenixUploadPackage}["']`));
  assert.match(source, /@cadence\/ui/);
});
