import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { join } from "node:path";
import {
  APPROVED_FIRST_PARTY_REMOTES,
  discoverFirstPartyRemotes,
} from "./first-party-remote-workspace.mjs";

const frontendRoot = join(import.meta.dirname, "..");

test("the approved first-party remotes expose source-derived manifest identities", async () => {
  for (const { directoryName, bundle, remoteName } of APPROVED_FIRST_PARTY_REMOTES) {
    const directory = join(frontendRoot, "apps", directoryName);
    const packageJson = JSON.parse(await readFile(join(directory, "package.json"), "utf8"));
    const federation = await readFile(join(directory, "module-federation.config.ts"), "utf8");
    const federatedApplication = await readFile(
      join(directory, "src", "federated-application.ts"),
      "utf8",
    );
    const sourceIdentity = declaredIdentity(federatedApplication, directoryName);

    assert.equal(typeof packageJson.name, "string");
    assert.equal(typeof packageJson.scripts?.["build:phoenix"], "string");
    assert.match(federation, new RegExp(`name:\\s*["']${escapeRegExp(remoteName)}["']`));
    assert.match(federation, /exposes:\s*\{[\s\S]*["']\.\/Application["']\s*:/);
    assert.match(federatedApplication, /defineApplicationManifest/);
    assert.match(federatedApplication, /FEDERATED_APPLICATION_MANIFEST_SCHEMA/);
    assert.match(federatedApplication, /APPLICATION_HOST_CONTRACT/);
    assert.match(
      federatedApplication,
      new RegExp(`applicationKey:\\s*["']${escapeRegExp(sourceIdentity.applicationKey)}["']`),
    );
    assert.match(
      federatedApplication,
      new RegExp(`packageId:\\s*["']${escapeRegExp(sourceIdentity.packageId)}["']`),
    );
    assert.match(
      federatedApplication,
      /placement:\s*(?:["'](?:application_workspace|ops_workspace)["']|[A-Za-z_$][\w$]*\.placement)/,
    );
    assert.match(
      federatedApplication,
      /(?:renderer:\s*(?:\{[\s\S]*exposedModule:|[A-Za-z_$][\w$]*)|\brenderer\s*,)/,
    );

    const phoenixConfig = await readFile(join(directory, "vite.phoenix.config.ts"), "utf8");
    assert.match(phoenixConfig, new RegExp(`application-host/${escapeRegExp(bundle)}`));
  }

  const organizationAdmin = declaredIdentity(
    await readFile(
      join(frontendRoot, "apps", "organization-admin", "src", "federated-application.ts"),
      "utf8",
    ),
    "organization-admin",
  );
  assert.equal(organizationAdmin.packageId, "cadence.organization-admin");
});

test("real-workspace publication discovery admits exactly the approved remote identities", async () => {
  const { host, remotes } = await discoverFirstPartyRemotes(frontendRoot, {
    requireApproved: true,
  });

  assert.equal(host.packageName, "@cadence/plugin-host");
  assert.deepEqual(
    remotes
      .map(({ bundle, remoteName }) => ({ bundle, remoteName }))
      .sort((left, right) => left.bundle.localeCompare(right.bundle)),
    APPROVED_FIRST_PARTY_REMOTES.map(({ bundle, remoteName }) => ({ bundle, remoteName })).sort(
      (left, right) => left.bundle.localeCompare(right.bundle),
    ),
  );
});

function declaredIdentity(source, directoryName) {
  const applicationKey = source.match(/applicationKey:\s*["']([^"']+)["']/)?.[1];
  const packageId = source.match(/packageId:\s*["']([^"']+)["']/)?.[1];
  if (!applicationKey || !packageId) {
    throw new Error(`${directoryName} manifest must declare an application key and package id.`);
  }
  return { applicationKey, packageId };
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
