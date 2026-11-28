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
  // Reviewed the team-to-develop merge (#198; ui/apogee-spa a3a151bfa + develop 2d8951f11): the checker's
  // tokenizer finds the same 2 federation-loader templates as before and nothing new; identical digest from
  // two pinned build:publication runs. Reviewed by devops; approved by the director.
  "228b53d50153c9fb6d8024ce2201c6ccec00770cb5143db1759fcacd05edbdc5",
  // Reviewed Vue 3.5.41 -> 3.5.45 runtime update (HIGH-advisory bump), replacing 851ab38c…: the
  // checker's tokenizer finds the same 2 federation-loader templates as before and nothing new;
  // identical digest from two pinned build:phoenix runs. Reviewed by director from devops evidence.
  "ce9db1bca93ac77d48fd10600311a278e24731c02020a380ee591845f0a50405",
  // Reviewed shared bounded diagnostics and remote correlation references; two identical pinned builds.
  "6b138c303964a2da533b9089df51045995af4d860e4e586fcb4781d5b3ca5a04",
  // Reviewed optional-prop forwarding and typed frontend readers; two identical pinned Phoenix builds.
  "6516c6c54a7f191ef86bbb8e4872bb1a8653149907d9245e424121c2a8adef9a",
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
  // Deleted the legacy application-host page, spacecraft/catalog/activation pages and their host
  // snapshot (#667); the tokenizer finds the same 2 federation-loader templates and nothing new;
  // two identical build:publication runs.
  "66010ec52223a1b517db8a418a2467f2bb76f496f7a323b8baf699e9c6c4f06a",
  // Reviewed the legacy command pages leaving the host (#708): the checker's tokenizer finds the same
  // federation-loader templates as before and nothing new; identical digest from two pinned builds.
  "9abee26081b155ff81513ba8a75a7b6bd305b50bc256aecfda9fe4281fe98cac",
  // Deleted the legacy /ops landing route and its BrowserHost branch (#668): the checker's tokenizer
  // finds the same 2 federation-loader templates and nothing new; two identical build:publication runs.
  "a23d806ee0689c9e2008835f8665c00a4ba15b8cb1fedd199b1cbe0e9f0b9fd4",
  // Deleted the mission-catalog and spacecraft remotes and their host pages (#671): the checker's
  // tokenizer finds the same 2 federation-loader templates and nothing new; two identical
  // build:publication runs.
  "4b0d27189f70101494408e662a1cf1bbf97adc401c9875b0616aa6e7b58c55bd",
  // Legacy Communications removal (#128) after the catalog and spacecraft removals (#671).
  // Two pinned builds produced the same bundle with only the two existing federation loader templates.
  "d3e1fc7ef14078a949f77569cf21909da8196219675c8f29a8bf1c63f97b91cc",
  // Deleted the data operations host pages and module (#702): the checker's tokenizer finds the
  // same 2 federation-loader templates and nothing new; two identical build:publication runs.
  "8bdaa24a47856e1ad621bd133408d37f018aef52dfadf054105441b674da8c60",
  // Deleted the telemetry-decom remote and the spacecraft application-surface route (#669b): the
  // tokenizer finds the same 2 federation-loader templates; two identical build:publication runs.
  "d519e5a2d1cc846e984f04176aa58374a554b7c3c8418e2c3e7f470c299c3bc1",
  // Deleted the legacy timeline, explore and alarms pages (#666, #142, #143): the checker's
  // tokenizer finds the same 2 federation-loader templates; two identical build:publication runs.
  "b7ce844f23417117d0f7f7c6c9aa4df21b76dda6b3b0fc6b6ca4e6717befb0ef",
]);

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

/** @param {string} source @param {string} name */
function assertHostReferences(source, name) {
  /** @type {[string, RegExp][]} */
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

/** @param {string} name @param {string} source @param {Set<string>} files */
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

/** @param {string} root */
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

  await assertNoSurfaceFixture(root);
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
