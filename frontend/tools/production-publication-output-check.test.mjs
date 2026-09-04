import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import test from "node:test";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { validateProductionPublication } from "./production-publication-output-check.mjs";

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
  await mkdir(join(root, "host"), { recursive: true });
  await writeFile(join(root, "host", "host.js"), "export const host = true;\n");
  await writeFile(join(root, "host", "plugin-host.css"), ".host { color: blue; }\n");
  await mkdir(join(root, "comms-overview"));
  await mkdir(join(root, "telemetry-decom"));
  await writeRemote(join(root, "comms-overview"), "cadence_comms_overview");
  await writeRemote(join(root, "telemetry-decom"), "cadence_telemetry_decom");
  return root;
}

void test("requires an exact host and allowed-remote publication root inventory", async () => {
  const root = await publicationFixture();
  try {
    const result = await validateProductionPublication(root);
    assert.equal(result.host.fileCount, 2);
    assert.equal(result.remotes.length, 2);

    await writeFile(join(root, "index.html"), "<!doctype html>\n");
    await assert.rejects(
      () => validateProductionPublication(root),
      /publication root inventory is not exactly/,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
