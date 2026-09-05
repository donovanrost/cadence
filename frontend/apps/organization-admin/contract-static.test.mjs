import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import test from "node:test";
import { join } from "node:path";

const appRoot = import.meta.dirname;
const sourceRoot = join(appRoot, "src");
const entryFiles = ["federated-application.ts"];
const surfaceIds = [
  "organization_home",
  "provider_accounts",
  "provider_account_new",
  "provider_account_show",
  "notifications",
  "notifications_bell",
  "admin_home",
  "admin_runtime",
  "admin_organizations",
  "admin_organization_new",
  "admin_organization_show",
  "admin_organization_invite",
];

async function sourceFiles(directory) {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) files.push(...(await sourceFiles(path)));
    else if (/\.(js|ts|vue)$/.test(entry.name)) files.push(path);
  }
  return files;
}

void test("owns the complete post-auth component closure", async () => {
  for (const entry of entryFiles) {
    assert.equal(
      await fileExists(join(sourceRoot, entry)),
      true,
      `${entry} entry is missing`,
    );
  }

  for (const file of await sourceFiles(sourceRoot)) {
    const contents = await readFile(file, "utf8");
    assert.equal(
      contents.includes("apps/cadence_web/assets/vue"),
      false,
      `${file} imports the legacy Vue tree`,
    );
  }
});

void test("declares one app-level exposed renderer for every contributed surface", async () => {
  const federationConfig = await readFile(join(appRoot, "module-federation.config.ts"), "utf8");
  const manifest = await readFile(join(sourceRoot, "federated-application.ts"), "utf8");
  const contribution = await readFile(join(sourceRoot, "organization-admin-contract.ts"), "utf8");

  assert.match(federationConfig, /"\.\/Application": "\.\/src\/federated-application\.ts"/);
  assert.doesNotMatch(federationConfig, /"\.\/(?!Application)[^"]*"\s*:/);
  for (const surfaceId of surfaceIds) {
    assert.match(contribution, new RegExp(`surfaceId: "${surfaceId}"`));
    assert.match(manifest, new RegExp(`surfaceId: surface.surfaceId`));
  }
  assert.match(manifest, /exposedModule: "\.\/Application"/);
  assert.equal(new Set(surfaceIds).size, surfaceIds.length);
  assert.match(manifest, /applicationKey: "organization_admin"/);
  assert.match(manifest, /packageId: "cadence\.organization-admin"/);
  assert.match(
    manifest,
    /installableScopes: \["organization", "user", "admin"\]/,
  );
  assert.match(contribution, /scope: "organization"/);
  assert.match(contribution, /scope: "user"/);
  assert.match(contribution, /scope: "admin"/);
});

async function fileExists(path) {
  try {
    await readFile(path);
    return true;
  } catch (error) {
    if (error?.code === "ENOENT") return false;
    throw error;
  }
}
