import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { join } from "node:path";
import { APPROVED_FIRST_PARTY_REMOTES, discoverFirstPartyRemotes } from "./first-party-remote-workspace.mjs";

const frontendRoot = join(import.meta.dirname, "..");
const expectedApplications = new Map([
  ["organization-admin", { applicationKey: "organization_admin", packageId: "cadence.organization_admin" }],
  ["mission-catalog", { applicationKey: "mission_catalog", packageId: "cadence.mission-catalog" }],
  ["spacecraft", { applicationKey: "spacecraft", packageId: "cadence.spacecraft" }],
  ["telemetry-decom", { applicationKey: "telemetry_decom", packageId: "cadence.telemetry-applications" }],
  ["comms-overview", { applicationKey: "comms_overview", packageId: "cadence.comms_overview" }],
  ["ops-console", { applicationKey: "ops_console", packageId: "cadence.ops_console" }],
]);

test("the six approved first-party remotes have complete manifest and federation contracts", async () => {
  assert.deepEqual(
    APPROVED_FIRST_PARTY_REMOTES.map(({ directoryName, bundle, remoteName }) => ({
      directoryName,
      bundle,
      remoteName,
    })),
    [...expectedApplications.keys()].map((directoryName) => ({
      directoryName,
      bundle: directoryName,
      remoteName: `cadence_${directoryName.replaceAll("-", "_")}`,
    })),
  );

  for (const [directoryName, expected] of expectedApplications) {
    const directory = join(frontendRoot, "apps", directoryName);
    const packageJson = JSON.parse(await readFile(join(directory, "package.json"), "utf8"));
    const federation = await readFile(join(directory, "module-federation.config.ts"), "utf8");
    const federatedApplication = await readFile(
      join(directory, "src", "federated-application.ts"),
      "utf8",
    );

    assert.equal(typeof packageJson.name, "string");
    assert.equal(typeof packageJson.scripts?.["build:phoenix"], "string");
    assert.match(federation, new RegExp(`name:\\s*["']cadence_${directoryName.replaceAll("-", "_")}["']`));
    assert.match(federation, /exposes:\s*\{[\s\S]*["']\.\/Application["']\s*:/);
    assert.match(federatedApplication, /defineApplicationManifest/);
    assert.match(federatedApplication, /FEDERATED_APPLICATION_MANIFEST_SCHEMA/);
    assert.match(federatedApplication, /APPLICATION_HOST_CONTRACT/);
    assert.match(federatedApplication, new RegExp(`applicationKey:\\s*["']${expected.applicationKey}["']`));
    assert.match(federatedApplication, new RegExp(`packageId:\\s*["']${expected.packageId}["']`));
    assert.match(federatedApplication, /placement:\s*["'](?:application_workspace|ops_workspace)["']/);
    assert.match(federatedApplication, /renderer:\s*\{[\s\S]*exposedModule:/);
  }
});

test("real-workspace publication discovery admits exactly the six approved remote identities", async () => {
  const { host, remotes } = await discoverFirstPartyRemotes(frontendRoot, {
    requireApproved: true,
  });

  assert.equal(host.packageName, "@cadence/plugin-host");
  assert.deepEqual(
    remotes
      .map(({ bundle, remoteName }) => ({ bundle, remoteName }))
      .sort((left, right) => left.bundle.localeCompare(right.bundle)),
    [...expectedApplications.keys()]
      .map((directoryName) => ({
        bundle: directoryName,
        remoteName: `cadence_${directoryName.replaceAll("-", "_")}`,
      }))
      .sort((left, right) => left.bundle.localeCompare(right.bundle)),
  );
});
