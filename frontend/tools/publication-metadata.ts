import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";

export type Publication = Readonly<{
  packageName: string;
  directory: string;
  remoteName: string;
  bundle: string;
}>;

function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function readJson(path: string): unknown {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (cause) {
    throw new Error(`Publication metadata is missing or unreadable: ${path}`, { cause });
  }
}

/** Used by both workspace discovery and the configs that produce the publication. */
export function readPublication(directory: string): Publication {
  const manifest = readJson(join(directory, "package.json"));
  const descriptor = readJson(join(directory, "publication.json"));
  if (
    !record(manifest) ||
    typeof manifest.name !== "string" ||
    !/^@cadence\/[a-z][a-z0-9-]*$/.test(manifest.name)
  )
    throw new Error(`Publication app ${directory} must declare a valid @cadence package name.`);
  if (
    !record(descriptor) ||
    Object.keys(descriptor).length !== 2 ||
    typeof descriptor.remoteName !== "string" ||
    !/^[a-z][a-z0-9_]*$/.test(descriptor.remoteName) ||
    typeof descriptor.bundle !== "string" ||
    !/^[a-z][a-z0-9-]*$/.test(descriptor.bundle)
  )
    throw new Error(
      `${manifest.name} must declare valid remoteName and bundle publication metadata.`,
    );
  return Object.freeze({
    packageName: manifest.name,
    directory: resolve(directory),
    remoteName: descriptor.remoteName,
    bundle: descriptor.bundle,
  });
}

export const publicationOutputDirectory = (publication: Publication): string =>
  resolve(
    publication.directory,
    "../../../apps/cadence_web/priv/static/assets/application-host",
    publication.bundle,
  );

export const publicationBase = (publication: Publication): string =>
  `/assets/application-host/${publication.bundle}/`;
