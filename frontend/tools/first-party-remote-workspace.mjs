import { record } from "../packages/plugin-sdk/src/admission.ts";
import { readPublication } from "./publication-metadata.ts";
import { readFile, readdir } from "node:fs/promises";
import { join, resolve } from "node:path";

const DEFAULT_FRONTEND_ROOT = resolve(import.meta.dirname, "..");

export const APPROVED_FIRST_PARTY_REMOTES = Object.freeze([
  {
    directoryName: "organization-admin",
    bundle: "organization-admin",
    remoteName: "cadence_organization_admin",
  },
  {
    directoryName: "mission-catalog",
    bundle: "mission-catalog",
    remoteName: "cadence_mission_catalog",
  },
  { directoryName: "spacecraft", bundle: "spacecraft", remoteName: "cadence_spacecraft" },
  {
    directoryName: "telemetry-decom",
    bundle: "telemetry-decom",
    remoteName: "cadence_telemetry_decom",
  },
  {
    directoryName: "comms-overview",
    bundle: "comms",
    remoteName: "cadence_comms",
  },
  { directoryName: "ops-console", bundle: "ops-console", remoteName: "cadence_ops_console" },
]);

/**
 * Discovers publication-capable first-party apps from their build script and
 * checked publication metadata. A package is admitted only when it declares the Phoenix
 * build script and both output identities; unknown output remains a
 * release-check failure rather than an implicit publication.
 */
export async function discoverFirstPartyRemotes(
  frontendRoot = DEFAULT_FRONTEND_ROOT,
  { requireApproved = frontendRoot === DEFAULT_FRONTEND_ROOT } = {},
) {
  const appsRoot = join(frontendRoot, "apps");
  const entries = await readdir(appsRoot, { withFileTypes: true });
  const remotes = [];

  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    if (!entry.isDirectory()) continue;

    const directory = join(appsRoot, entry.name);
    const packageJson = await readJson(join(directory, "package.json"));
    if (!record(packageJson)) continue;
    if (!record(packageJson.scripts) || typeof packageJson.scripts["build:phoenix"] !== "string")
      continue;

    remotes.push(readPublication(directory));
  }

  const host = remotes.find(({ packageName }) => packageName === "@cadence/plugin-host");
  if (!host)
    throw new Error("The first-party frontend workspace must provide @cadence/plugin-host.");

  const remoteEntries = remotes.filter(({ packageName }) => packageName !== "@cadence/plugin-host");
  const identities = new Set();
  for (const remote of remotes) {
    for (const identity of [remote.packageName, remote.bundle, remote.remoteName]) {
      if (identities.has(identity))
        throw new Error(`Duplicate first-party publication identity ${identity}.`);
      identities.add(identity);
    }
  }

  const result = { host, remotes: remoteEntries };
  if (requireApproved) assertApprovedFirstPartyRemoteCoverage(result);
  return result;
}

/** @param {{remotes: ReturnType<typeof readPublication>[]}} workspace */
export function assertApprovedFirstPartyRemoteCoverage({ remotes }) {
  const byBundle = new Map(remotes.map((remote) => [remote.bundle, remote]));
  const missing = APPROVED_FIRST_PARTY_REMOTES.filter(
    ({ bundle, remoteName }) => byBundle.get(bundle)?.remoteName !== remoteName,
  );
  if (missing.length > 0) {
    throw new Error(
      `The first-party frontend workspace is missing approved remotes: ${missing
        .map(({ directoryName }) => directoryName)
        .join(", ")}.`,
    );
  }
}

/** @param {string} path @returns {Promise<unknown>} */
async function readJson(path) {
  try {
    return JSON.parse(await readFile(path, "utf8"));
  } catch {
    return undefined;
  }
}
