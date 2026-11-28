import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import test from "node:test";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { validateProductionPublication } from "./production-publication-output-check.mjs";

/** @param {string} root @param {string} remoteName */
async function writeRemote(root, remoteName) {
  await mkdir(join(root, "assets"), { recursive: true });
  await writeFile(join(root, "assets", "application.js"), "export const application = true;\n");
  await writeFile(join(root, "assets", "publication.css"), ".publication { color: green; }\n");
  await writeFile(
    join(root, "remoteEntry.js"),
    "export { application } from './assets/application.js';\n",
  );
  await writeFile(
    join(root, "mf-manifest.json"),
    JSON.stringify({
      id: remoteName,
      name: remoteName,
      metaData: { publicPath: "auto", remoteEntry: { path: "", name: "remoteEntry.js" } },
      shared: [
        {
          name: "vue",
          assets: { js: { async: [], sync: ["remoteEntry.js"] }, css: { async: [], sync: [] } },
        },
      ],
      exposes: [
        {
          name: "./Application",
          assets: {
            js: { async: ["assets/application.js"], sync: [] },
            css: { async: [], sync: ["assets/publication.css"] },
          },
        },
      ],
    }),
  );
  await writeFile(
    join(root, "mf-stats.json"),
    JSON.stringify({
      buildOutput: [
        { fileName: "assets/application.js" },
        { fileName: "assets/publication.css" },
        { fileName: "remoteEntry.js" },
      ],
    }),
  );
}

async function publicationFixture() {
  const root = await mkdtemp(join(tmpdir(), "cadence-production-publication-check-"));
  for (const [bundle, remoteName] of /** @type {const} */ ([
    ["ops-console", "cadence_ops_console"],
  ])) {
    await mkdir(join(root, bundle));
    await writeRemote(join(root, bundle), remoteName);
  }
  return root;
}

void test("requires an exact allowed-remote publication root inventory", async () => {
  const root = await publicationFixture();
  try {
    const result = await validateProductionPublication(root);
    assert.equal(result.remotes.length, 1);

    await writeFile(join(root, "index.html"), "<!doctype html>\n");
    await assert.rejects(
      () => validateProductionPublication(root),
      /publication root inventory is not exactly/,
    );
    await rm(join(root, "index.html"));

    await mkdir(join(root, "ops-console", "empty-directory"));
    await assert.rejects(
      () => validateProductionPublication(root),
      /empty or nested publication directory/,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

void test("refuses a publication that contains or references the test-only surface fixture", async () => {
  const root = await publicationFixture();
  try {
    await writeFile(
      join(root, "ops-console", "assets", "application.js"),
      'export const key = "surface-fixture";\n',
    );
    await assert.rejects(
      () => validateProductionPublication(root),
      /references the test-only surface fixture/,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
