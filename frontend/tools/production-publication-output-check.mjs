import { lstat, readFile, readdir } from "node:fs/promises";
import { join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { validateFederationOutput } from "./frontend-release-output-check.mjs";
import { discoverFirstPartyRemotes } from "./first-party-remote-workspace.mjs";

const publicationRoot = resolve(
  import.meta.dirname,
  "../../apps/cadence_web/priv/static/assets/application-host",
);
const repositoryRoot = resolve(import.meta.dirname, "../..");

/** @param {string} message @returns {never} */
function fail(message) {
  throw new Error(`Production publication check failed: ${message}`);
}

/** @param {string} directory @param {string} outputRoot @returns {Promise<string[]>} */
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

// The console federation smoke's test-only remote (frontend/apps/surface-fixture) is signed with the
// smoke's TEST key; a production publication must never contain or reference it (lead, 11-16).
const surfaceFixtureReference = /surface[-_. ]?fixture/i;

/** @param {string} root */
async function assertNoSurfaceFixture(root) {
  for (const path of await outputFiles(root, root)) {
    const name = relative(root, path).split(sep).join("/");
    if (surfaceFixtureReference.test(name)) fail(`${name} is the test-only surface fixture`);
    const source = await readFile(path, "utf8").catch(() => fail(`${name} is unreadable`));
    if (surfaceFixtureReference.test(source)) {
      fail(`${name} references the test-only surface fixture`);
    }
  }
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
  const publicationEntries = new Set(publicationBundles.map(({ bundle }) => bundle));
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

  await assertNoSurfaceFixture(root);
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
  return { remotes };
}

const isMain =
  process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url));
if (isMain) {
  validateProductionPublication()
    .then(({ remotes }) => {
      console.log(
        `Production publication check passed: ${remotes
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
