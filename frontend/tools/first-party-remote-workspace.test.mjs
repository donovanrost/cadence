import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import test from "node:test";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  APPROVED_FIRST_PARTY_REMOTES,
  discoverFirstPartyRemotes,
} from "./first-party-remote-workspace.mjs";

async function workspaceFixture() {
  const root = await mkdtemp(join(tmpdir(), "cadence-first-party-workspace-"));
  const apps = join(root, "apps");
  await mkdir(apps, { recursive: true });
  /** @type {[string, string, string, string][]} */
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
    await writeFile(join(directory, "publication.json"), JSON.stringify({ remoteName, bundle }));
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

void test("rejects malformed publication metadata before building", async () => {
  const root = await workspaceFixture();
  try {
    await writeFile(
      join(root, "apps", "sample-remote", "publication.json"),
      JSON.stringify({ remoteName: "bad/name", bundle: "sample-remote" }),
    );
    await assert.rejects(
      () => discoverFirstPartyRemotes(root),
      /valid remoteName and bundle publication metadata/,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

void test("requires every named first-party remote in the real workspace", async () => {
  const result = await discoverFirstPartyRemotes(join(import.meta.dirname, ".."), {
    requireApproved: true,
  });

  assert.deepEqual(
    result.remotes
      .map(({ bundle, remoteName }) => ({ bundle, remoteName }))
      .sort((left, right) => left.bundle.localeCompare(right.bundle)),
    APPROVED_FIRST_PARTY_REMOTES.map(({ bundle, remoteName }) => ({ bundle, remoteName })).sort(
      (left, right) => left.bundle.localeCompare(right.bundle),
    ),
  );
});

void test("config movement and formatting cannot change discovered identities", async (t) => {
  const root = await workspaceFixture();
  t.after(() => rm(root, { recursive: true, force: true }));
  const before = await discoverFirstPartyRemotes(root);
  const directory = join(root, "apps", "sample-remote");
  await writeFile(
    join(directory, "module-federation.config.ts"),
    'export { default } from "./build/federation";',
  );
  await writeFile(
    join(directory, "vite.phoenix.config.ts"),
    '// Formatting and unrelated source strings are not metadata.\nconst name = "misleading";',
  );
  assert.deepEqual(await discoverFirstPartyRemotes(root), before);
});

void test("publication metadata rejects missing, extra, malformed, and duplicate identities", async (t) => {
  const root = await workspaceFixture();
  t.after(() => rm(root, { recursive: true, force: true }));
  const path = join(root, "apps", "sample-remote", "publication.json");
  for (const descriptor of [
    null,
    {},
    { remoteName: "cadence_sample", bundle: "../outside" },
    { remoteName: "cadence_sample", bundle: "sample", extra: true },
  ]) {
    await writeFile(path, JSON.stringify(descriptor));
    await assert.rejects(discoverFirstPartyRemotes(root), /valid remoteName and bundle/);
  }
  await writeFile(path, JSON.stringify({ remoteName: "cadence_host", bundle: "sample" }));
  await assert.rejects(
    discoverFirstPartyRemotes(root),
    /Duplicate first-party publication identity/,
  );
  await rm(path);
  await assert.rejects(discoverFirstPartyRemotes(root), /missing or unreadable/);
});
