import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import test from "node:test";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { discoverFirstPartyRemotes } from "./first-party-remote-workspace.mjs";

async function workspaceFixture() {
  const root = await mkdtemp(join(tmpdir(), "cadence-first-party-workspace-"));
  const apps = join(root, "apps");
  await mkdir(apps, { recursive: true });
  const packages = [
    ["host", "@cadence/plugin-host", "cadence_host", "host"],
    ["sample-remote", "@cadence/sample-remote", "cadence_sample_remote", "sample-remote"],
  ];
  for (const [directoryName, packageName, remoteName, bundle] of packages) {
    const directory = join(apps, directoryName);
    await mkdir(directory, { recursive: true });
    await writeFile(
      join(directory, "package.json"),
      JSON.stringify({ name: packageName, scripts: { "build:phoenix": "vp build" } }),
    );
    await writeFile(join(directory, "module-federation.config.ts"), `name: "${remoteName}"`);
    await writeFile(
      join(directory, "vite.phoenix.config.ts"),
      `outDir: "application-host/${bundle}"`,
    );
  }
  return root;
}

void test("discovers every Phoenix-buildable first-party remote with strict identities", async () => {
  const root = await workspaceFixture();
  try {
    const result = await discoverFirstPartyRemotes(root);
    assert.equal(result.host.packageName, "@cadence/plugin-host");
    assert.deepEqual(
      result.remotes.map(({ packageName, bundle, remoteName }) => ({
        packageName,
        bundle,
        remoteName,
      })),
      [
        {
          packageName: "@cadence/sample-remote",
          bundle: "sample-remote",
          remoteName: "cadence_sample_remote",
        },
      ],
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

void test("rejects a publication app without a generated federation identity", async () => {
  const root = await workspaceFixture();
  try {
    await writeFile(
      join(root, "apps", "sample-remote", "module-federation.config.ts"),
      "export default {};",
    );
    await assert.rejects(
      () => discoverFirstPartyRemotes(root),
      /Module Federation name is missing/,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
