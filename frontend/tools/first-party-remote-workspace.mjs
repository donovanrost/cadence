import { readFile, readdir } from "node:fs/promises";
import { join, resolve } from "node:path";

const DEFAULT_FRONTEND_ROOT = resolve(import.meta.dirname, "..");
const PACKAGE_NAME_PATTERN = /^@cadence\/[a-z][a-z0-9-]*$/;
const REMOTE_NAME_PATTERN = /^[a-z][a-z0-9_]*$/;
const BUNDLE_PATTERN = /^[a-z][a-z0-9-]*$/;

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
 * Discovers publication-capable first-party apps from their own build and
 * federation config. A package is admitted only when it declares the Phoenix
 * build script and both generated-output identities; unknown output remains a
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
    if (!packageJson || typeof packageJson !== "object") continue;
    if (!packageJson.scripts || typeof packageJson.scripts["build:phoenix"] !== "string") continue;

    const packageName = packageJson.name;
    if (typeof packageName !== "string" || !PACKAGE_NAME_PATTERN.test(packageName)) {
      throw new Error(`Publication app ${entry.name} must declare a valid @cadence package name.`);
    }

    const federationConfig = await readText(join(directory, "module-federation.config.ts"));
    const phoenixConfig = await readText(join(directory, "vite.phoenix.config.ts"));
    const remoteName = matchRequired(
      federationConfig,
      /\bname:\s*["']([^"']+)["']/,
      `${packageName} Module Federation name`,
    );
    const bundle = matchRequired(
      phoenixConfig,
      /application-host\/([A-Za-z0-9_-]+)["'`)]?/,
      `${packageName} Phoenix publication bundle`,
    );

    if (!REMOTE_NAME_PATTERN.test(remoteName)) {
      throw new Error(`${packageName} has an invalid Module Federation name.`);
    }
    if (!BUNDLE_PATTERN.test(bundle)) {
      throw new Error(`${packageName} has an invalid Phoenix publication bundle.`);
    }

    remotes.push({ packageName, directory, bundle, remoteName });
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

async function readText(path) {
  return readFile(path, "utf8").catch(() => {
    throw new Error(`Publication app config is missing or unreadable: ${path}`);
  });
}

async function readJson(path) {
  try {
    return JSON.parse(await readFile(path, "utf8"));
  } catch {
    return undefined;
  }
}

function matchRequired(source, pattern, label) {
  const match = pattern.exec(source);
  if (!match?.[1]) throw new Error(`${label} is missing.`);
  return match[1];
}
