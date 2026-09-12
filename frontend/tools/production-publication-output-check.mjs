import { createHash } from "node:crypto";
import { lstat, readFile, readdir } from "node:fs/promises";
import { extname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import {
  assertCssReferences,
  assertImportReferences,
  validateFederationOutput,
} from "./frontend-release-output-check.mjs";
import { discoverFirstPartyRemotes } from "./first-party-remote-workspace.mjs";

const publicationRoot = resolve(
  import.meta.dirname,
  "../../apps/cadence_web/priv/static/assets/application-host",
);
const repositoryRoot = resolve(import.meta.dirname, "../..");
const hostFiles = new Set(["host.js"]);
// Explicitly reviewed producer outputs; never derive this allowlist from the artifact being checked.
const authoritativeHostJavascriptDigests = new Set([
  // Reviewed fixed preflight guidance in the host bridge; two identical pinned builds.
  "67e88fede201e7c1b264707229b3b530baea77c2ed5dcc6e33c30f68053cbbd5",
  // Reviewed route-scoped page chrome injection and heading level; two identical pinned builds.
  "d25c815d2df0a75d51affb35484ad820843056584e8f32c09f520a1651338667",
  // Reviewed host navigation callback and stale-bridge enforcement; two identical pinned builds.
  "5833897c38ef7237883805c8f037ad6e3b9f5a0a4ea72313afcc96a02eb3f035",
  "6b5012fd41011960b83ea5de1a0afc51592beb66055ab5b5b8b0292117f9f343",
  // Shared design-system consolidation: two identical pinned build:phoenix runs.
  "2f6b02fbac438b374f8ee5af736b953d8f0e7dbdf96d058cd00c1c9c31cfc0e5",
  // Reviewed mounted-boundary metadata; two identical pinned build:phoenix runs.
  "d05e3fd0e993aa512018627ea68f8772e5fc7c8860d3958428c5575a2b322a55",
]);

function fail(message) {
  throw new Error(`Production publication check failed: ${message}`);
}

async function outputFiles(directory, outputRoot) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      const nested = await outputFiles(path, outputRoot);
      if (nested.length === 0) {
        fail(
          `empty or nested publication directory ${relative(outputRoot, path).split(sep).join("/")}`,
        );
      }
      files.push(...nested);
    } else if (entry.isFile()) files.push(path);
    else fail(`unsupported publication entry ${relative(outputRoot, path).split(sep).join("/")}`);
  }
  return files;
}

function assertHostReferences(source, name) {
  const forbidden = [
    ["demo-auth service", /\bdemo[-_]?auth(?:[-_]?service)?\b/i],
    ["contract probe", /(?:\bcontract[-_]?probe\b|cadence[._-]contract[._-]probe)/i],
    [
      "development URL",
      /\bhttps?:\/\/(?:localhost|127(?:\.\d{1,3}){3}|\[::1\])(?::\d+)?(?:[/?#"'`),;\s]|$)/i,
    ],
    [
      "Vite client or HMR reference",
      /(?:import\.meta\.hot|\/[@]vite\/client|vite\/client|hotUpdate|__vite__hot)/i,
    ],
    ["source-map reference", /(?:sourceMappingURL|\.map(?:["'`?#),]|$))/i],
    [
      "standalone application reference",
      /\bsrc\/main\.ts\b|\bStandaloneApp\b|standalone[-_.]?(?:main|bootstrap|entry)/i,
    ],
    [
      "deployment-specific release reference",
      /(?:\/releases\/|MF_BUILD_VERSION|process\.env\.NODE_ENV)/i,
    ],
    [
      "mutable fallback URL",
      /\b(?:fallback(?:Url|Href)?|artifactBaseUrl)\b\s*(?:[:=])\s*["'`](?:https?:\/\/|\/)/i,
    ],
  ];
  for (const [label, pattern] of forbidden) {
    if (pattern.test(source)) fail(`${name} contains a forbidden ${label}`);
  }
}

function isAuthoritativeHostJavascript(name, source, files) {
  return (
    name === "host.js" &&
    files.size === hostFiles.size &&
    [...hostFiles].every((file) => files.has(file)) &&
    authoritativeHostJavascriptDigests.has(
      createHash("sha256").update(source, "utf8").digest("hex"),
    )
  );
}

async function validateHostPublication(root) {
  const stats = await lstat(root).catch(() => fail(`host publication is unavailable: ${root}`));
  if (stats.isSymbolicLink()) fail("host publication directory must not be a symlink");
  if (!stats.isDirectory()) fail("host publication path must be a directory");

  const paths = await outputFiles(root, root);
  const files = new Set(paths.map((path) => relative(root, path).split(sep).join("/")));
  if (files.size !== hostFiles.size || [...hostFiles].some((path) => !files.has(path))) {
    fail(`host publication inventory is not exactly ${[...hostFiles].sort().join(", ")}`);
  }

  for (const path of paths) {
    const name = relative(root, path).split(sep).join("/");
    const source = await readFile(path, "utf8").catch(() => fail(`${name} is unreadable`));
    assertHostReferences(source, name);
    if (name.endsWith(".js")) {
      const authoritativeHostPublication = isAuthoritativeHostJavascript(name, source, files);
      assertImportReferences(source, name, files, root, new Set(), {
        authoritativeHostPublication,
        generatedModuleFederation: authoritativeHostPublication,
      });
    }
    if (extname(name).toLowerCase() === ".css") assertCssReferences(source, name, files, root);
  }
  return { outputRoot: root, fileCount: paths.length };
}

export async function validateProductionPublication(root = publicationRoot) {
  const { remotes: publicationBundles } = await discoverFirstPartyRemotes(
    join(repositoryRoot, "frontend"),
    { requireApproved: true },
  );
  const stats = await lstat(root).catch(() => fail(`publication root is unavailable: ${root}`));
  if (stats.isSymbolicLink()) fail("publication root must not be a symlink");
  if (!stats.isDirectory()) fail("publication root must be a directory");

  const entries = await readdir(root, { withFileTypes: true });
  const publicationEntries = new Set(["host", ...publicationBundles.map(({ bundle }) => bundle)]);
  const entryNames = new Set(entries.map((entry) => entry.name));
  if (
    entryNames.size !== publicationEntries.size ||
    [...publicationEntries].some((name) => !entryNames.has(name)) ||
    entries.some((entry) => !entry.isDirectory())
  ) {
    fail(
      `publication root inventory is not exactly ${[...publicationEntries]
        .sort((left, right) => left.localeCompare(right))
        .join(", ")}`,
    );
  }

  const host = await validateHostPublication(join(root, "host"));
  const remotes = [];
  for (const { bundle, remoteName } of publicationBundles) {
    remotes.push(
      await validateFederationOutput(join(root, bundle), remoteName, {
        repositoryRootInput: repositoryRoot,
        requireExternal: false,
        allowedDeploymentPath: bundle,
      }),
    );
  }
  return { host, remotes };
}

const isMain =
  process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url));
if (isMain) {
  validateProductionPublication()
    .then(({ host, remotes }) => {
      console.log(
        `Production publication check passed: host ${host.fileCount} files; ${remotes
          .map(
            ({ outputRoot, fileCount }) =>
              `${relative(publicationRoot, outputRoot)} ${fileCount} files`,
          )
          .join(", ")}.`,
      );
    })
    .catch((error) => {
      console.error(error instanceof Error ? error.message : error);
      process.exitCode = 1;
    });
}
