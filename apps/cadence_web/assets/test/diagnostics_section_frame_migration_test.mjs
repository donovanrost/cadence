import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {createHash} from "node:crypto"
import {readFile, readdir} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  diagnosticsSectionExcludedHeaderClass,
  diagnosticsSectionHeaderClass,
  diagnosticsSectionMigrations,
  diagnosticsSectionPredecessorCommit,
  diagnosticsSectionRootClass,
  peelCadenceDiagnosticsSectionFrame,
} from "./diagnostics_section_frame_test_support.mjs"

const scenarios = Object.freeze([
  "all predecessor Vue SFCs classify into the exact two-shell cohort and one semantic exclusion",
  "git show preserves both frozen predecessor byte lengths and SHA-256 values",
  "each migrated caller reconstructs to its predecessor source byte-for-byte",
  "the Telemetry Decom py-4 preflight exclusion remains byte-for-byte unchanged",
  "only the frozen cohort imports the presentation-only diagnostics section frame",
])

assert.equal(process.versions.node, "24.16.0", "expected pinned Node 24.16.0")
assert.equal(scenarios.length, 5)
assert.equal(diagnosticsSectionMigrations.length, 2)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const occurrences = (source, fragment) => source.split(fragment).length - 1
const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
const exactCompoundPattern = new RegExp(
  `<section\\b[^>]*class="${escapeRegExp(diagnosticsSectionRootClass)}"[^>]*>\\s*` +
    `<header class="${escapeRegExp(diagnosticsSectionHeaderClass)}">`,
  "g",
)
const excludedCompoundPattern = new RegExp(
  `<section\\b[^>]*class="${escapeRegExp(diagnosticsSectionRootClass)}"[^>]*>\\s*` +
    `<header class="${escapeRegExp(diagnosticsSectionExcludedHeaderClass)}">`,
  "g",
)
const countMatches = (source, pattern) => source.match(pattern)?.length ?? 0
const gitShow = (sourcePath) =>
  execFileSync(
    "git",
    [
      "-C",
      repositoryRoot,
      "show",
      `${diagnosticsSectionPredecessorCommit}:${sourcePath}`,
    ],
    {encoding: "utf8"},
  )

const predecessorVuePaths = execFileSync(
  "git",
  [
    "-C",
    repositoryRoot,
    "ls-tree",
    "-r",
    "--name-only",
    diagnosticsSectionPredecessorCommit,
  ],
  {encoding: "utf8"},
)
  .trim()
  .split("\n")
  .filter((sourcePath) => sourcePath.endsWith(".vue"))
  .sort()

assert.equal(predecessorVuePaths.length, 222, "the frozen inventory audits all 222 Vue SFCs")

const exactCohort = []
const exclusions = []
let rootClassCount = 0
let exactHeaderClassCount = 0
let excludedHeaderClassCount = 0

for (const sourcePath of predecessorVuePaths) {
  const source = gitShow(sourcePath)
  const exactCount = countMatches(source, exactCompoundPattern)
  const excludedCount = countMatches(source, excludedCompoundPattern)

  rootClassCount += occurrences(source, diagnosticsSectionRootClass)
  exactHeaderClassCount += occurrences(source, diagnosticsSectionHeaderClass)
  excludedHeaderClassCount += occurrences(source, diagnosticsSectionExcludedHeaderClass)
  if (exactCount > 0) exactCohort.push({sourcePath, count: exactCount})
  if (excludedCount > 0) exclusions.push({sourcePath, count: excludedCount})
}

assert.deepEqual(exactCohort, [
  {
    sourcePath: "apps/cadence_web/assets/vue/SpacecraftTelemetryDecom.vue",
    count: 1,
  },
  {
    sourcePath:
      "apps/cadence_web/assets/vue/application_host/ApplicationDiagnostics.vue",
    count: 1,
  },
])
assert.deepEqual(exclusions, [
  {
    sourcePath: "apps/cadence_web/assets/vue/SpacecraftTelemetryDecom.vue",
    count: 1,
  },
])
assert.equal(rootClassCount, 3)
assert.equal(exactHeaderClassCount, 2)
assert.equal(excludedHeaderClassCount, 1)

for (const migration of diagnosticsSectionMigrations) {
  const predecessor = gitShow(migration.sourcePath)
  const current = await readFile(resolve(repositoryRoot, migration.sourcePath), "utf8")
  const reconstructed = peelCadenceDiagnosticsSectionFrame(current, migration.sourcePath)

  assert.equal(migration.predecessorCommit, diagnosticsSectionPredecessorCommit)
  assert.equal(Buffer.byteLength(predecessor), migration.predecessorByteLength)
  assert.equal(sha256(predecessor), migration.predecessorSha256)
  assert.equal(reconstructed, predecessor, `${migration.file} reconstructs byte-for-byte`)
  assert.equal(sha256(reconstructed), migration.predecessorSha256)
}

const extractSection = (source, marker) => {
  const start = source.indexOf(marker)
  assert.notEqual(start, -1, `${marker} exists`)

  const sectionTags = /<\/?section\b[^>]*>/g
  sectionTags.lastIndex = start
  let depth = 0

  for (let match = sectionTags.exec(source); match; match = sectionTags.exec(source)) {
    depth += match[0].startsWith("</") ? -1 : 1
    if (depth === 0) return source.slice(start, match.index + match[0].length)
  }

  assert.fail(`${marker} has an exact closing section`)
}

const spacecraftMigration = diagnosticsSectionMigrations[0]
const predecessorSpacecraft = gitShow(spacecraftMigration.sourcePath)
const currentSpacecraft = await readFile(
  resolve(repositoryRoot, spacecraftMigration.sourcePath),
  "utf8",
)
const preflightMarker = '<section\n            :id="preflight.id"'
const predecessorExclusion = extractSection(predecessorSpacecraft, preflightMarker)
const currentExclusion = extractSection(currentSpacecraft, preflightMarker)

assert.equal(Buffer.byteLength(predecessorExclusion), 3211)
assert.equal(sha256(predecessorExclusion), "42334a596ec30366597753698ea184acf3cd85e08bb3cad36c6dba35307dfff5")
assert.equal(currentExclusion, predecessorExclusion)
assert.match(currentExclusion, /:data-preflight-state="preflight\.state"/)
assert.match(currentExclusion, new RegExp(escapeRegExp(diagnosticsSectionExcludedHeaderClass)))

const walkVueFiles = async (directory) => {
  const entries = await readdir(directory, {withFileTypes: true})
  const nested = await Promise.all(
    entries.map(async (entry) => {
      const entryPath = resolve(directory, entry.name)
      if (entry.isDirectory()) return walkVueFiles(entryPath)
      return entry.isFile() && entry.name.endsWith(".vue") ? [entryPath] : []
    }),
  )
  return nested.flat()
}

const currentVueSources = await Promise.all(
  (await walkVueFiles(vueDirectory)).map(async (sourcePath) => ({
    file: sourcePath.slice(vueDirectory.length + 1),
    source: await readFile(sourcePath, "utf8"),
  })),
)
assert.deepEqual(
  currentVueSources
    .filter(({source}) => /^import CadenceDiagnosticsSectionFrame\b/m.test(source))
    .map(({file}) => file)
    .sort(),
  diagnosticsSectionMigrations.map(({file}) => file).sort(),
)
assert.equal(
  currentVueSources.reduce(
    (total, {source}) => total + (source.match(/<CadenceDiagnosticsSectionFrame\b/g)?.length ?? 0),
    0,
  ),
  2,
)
assert.equal(
  currentVueSources.reduce((total, {source}) => total + countMatches(source, exactCompoundPattern), 0),
  0,
)
assert.deepEqual(
  currentVueSources
    .filter(({source}) => countMatches(source, excludedCompoundPattern) > 0)
    .map(({file}) => file),
  ["SpacecraftTelemetryDecom.vue"],
)

console.log(`diagnostics_section_frame_migration_test passed (${scenarios.length} scenarios)`)
