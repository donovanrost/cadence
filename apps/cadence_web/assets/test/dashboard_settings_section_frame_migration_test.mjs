#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {readFile, readdir} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  dashboardSettingsSectionFrameCallerNames,
  dashboardSettingsSectionFrameClass,
  dashboardSettingsSectionFrameImport,
  dashboardSettingsSectionFrameMigrations,
  dashboardSettingsSectionFramePath,
  dashboardSettingsSectionFramePredecessorCommit,
  dashboardSettingsSectionFrameSha256,
  peelCadenceDashboardSettingsSectionFrame,
} from "./dashboard_settings_section_frame_test_support.mjs"

const scenarios = Object.freeze([
  "the exact predecessor resolves as a commit and is an ancestor of HEAD",
  "the frozen base has exactly two eligible native section roots in one caller",
  "the current caller has exactly two transparent frame roots and no residual eligible native roots",
  "the caller reconstructs its frozen predecessor blob, bytes, and SHA-256 exactly",
  "the bounded inverse peel removes only the new frame before older layers",
])

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
assert.equal(process.execPath, pinnedNode, "the migration uses the pinned Node executable")
assert.equal(process.versions.node, "24.16.0", "the migration uses pinned Node 24.16.0")
assert.equal(scenarios.length, 5)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const gitText = (args) => execFileSync("git", ["-C", repositoryRoot, ...args], {encoding: "utf8"})
const frozenSource = (migration) =>
  gitText(["show", `${dashboardSettingsSectionFramePredecessorCommit}:${migration.repositoryPath}`])
const occurrences = (source, fragment) => source.split(fragment).length - 1
const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
const nativeRootPattern = new RegExp(
  `<section\\b[^>]*class="${escapeRegExp(dashboardSettingsSectionFrameClass)}"[^>]*>`,
  "g",
)
const eligibleNativeRootPattern = new RegExp(
  `<section\\b[^>]*:id="page\\.(?:sharing|snapshots)\\.id"[^>]*` +
    `class="${escapeRegExp(dashboardSettingsSectionFrameClass)}"[^>]*>`,
  "g",
)

assert.equal(
  gitText(["cat-file", "-t", dashboardSettingsSectionFramePredecessorCommit]).trim(),
  "commit",
  "the frozen predecessor resolves exactly as a commit",
)
assert.equal(
  gitText([
    "rev-parse",
    "--verify",
    `${dashboardSettingsSectionFramePredecessorCommit}^{commit}`,
  ]).trim(),
  dashboardSettingsSectionFramePredecessorCommit,
  "the frozen predecessor resolves to the requested commit",
)
assert.doesNotThrow(
  () =>
    gitText(["merge-base", "--is-ancestor", dashboardSettingsSectionFramePredecessorCommit, "HEAD"]),
  "the frozen predecessor is an ancestor of current HEAD",
)

assert.equal(dashboardSettingsSectionFrameMigrations.length, 1)
assert.deepEqual(dashboardSettingsSectionFrameCallerNames, ["OpsDashboardSettings.vue"])
assert.ok(
  (await readdir(resolve(vueDirectory, "ui/components"))).includes(
    dashboardSettingsSectionFramePath.split("/").at(-1),
  ),
  "the successor includes the new section-frame component",
)

const predecessorVueFiles = gitText([
  "ls-tree",
  "-r",
  "--name-only",
  dashboardSettingsSectionFramePredecessorCommit,
  "apps/cadence_web/assets/vue",
])
  .trim()
  .split("\n")
  .filter((file) => file.endsWith(".vue"))
  .sort()

const historicalExactClassRoots = predecessorVueFiles.flatMap((file) => {
  const source = gitText(["show", `${dashboardSettingsSectionFramePredecessorCommit}:${file}`])
  const count = (source.match(nativeRootPattern) ?? []).length
  return count > 0 ? [{file: file.slice("apps/cadence_web/assets/vue/".length), count}] : []
})

assert.deepEqual(
  historicalExactClassRoots,
  [
    {file: "OpsContactRequirementNew.vue", count: 1},
    {file: "OpsDashboardActivity.vue", count: 1},
    {file: "OpsDashboardSettings.vue", count: 2},
  ],
  "the frozen exact-class inventory retains two semantic near-match exclusions",
)

const historicalEligibleRoots = predecessorVueFiles.flatMap((file) => {
  const source = gitText(["show", `${dashboardSettingsSectionFramePredecessorCommit}:${file}`])
  const count = (source.match(eligibleNativeRootPattern) ?? []).length
  return count > 0 ? [{file: file.slice("apps/cadence_web/assets/vue/".length), count}] : []
})

assert.deepEqual(
  historicalEligibleRoots,
  [{file: "OpsDashboardSettings.vue", count: 2}],
  "the frozen base has exactly the two audited native section roots",
)

const currentVueFiles = (await readdir(vueDirectory, {recursive: true}))
  .filter((file) => file.endsWith(".vue"))
  .sort()
const currentSources = await Promise.all(
  currentVueFiles.map(async (file) => ({
    file,
    source: await readFile(resolve(vueDirectory, file), "utf8"),
  })),
)

assert.deepEqual(
  currentSources
    .filter(({source}) => occurrences(source, dashboardSettingsSectionFrameImport) > 0)
    .map(({file}) => file),
  ["OpsDashboardSettings.vue"],
  "exactly one audited caller imports the section frame",
)
assert.equal(
  currentSources.reduce(
    (total, {source}) => total + occurrences(source, dashboardSettingsSectionFrameImport),
    0,
  ),
  1,
)
assert.equal(
  currentSources.reduce(
    (total, {source}) =>
      total + (source.match(/<CadenceDashboardSettingsSectionFrame\b/g)?.length ?? 0),
    0,
  ),
  2,
)
assert.equal(
  currentSources.reduce(
    (total, {source}) => total + (source.match(/<\/CadenceDashboardSettingsSectionFrame>/g)?.length ?? 0),
    0,
  ),
  2,
)
assert.equal(
  currentSources.reduce((total, {source}) => total + (source.match(eligibleNativeRootPattern) ?? []).length, 0),
  0,
  "no eligible native section root remains in current Vue sources",
)

for (const migration of dashboardSettingsSectionFrameMigrations) {
  const predecessor = frozenSource(migration)
  const current = await readFile(resolve(repositoryRoot, migration.repositoryPath), "utf8")

  assert.equal(
    gitText([
      "rev-parse",
      `${dashboardSettingsSectionFramePredecessorCommit}:${migration.repositoryPath}`,
    ]).trim(),
    migration.predecessorBlobId,
    `${migration.file} keeps its frozen predecessor blob object`,
  )
  assert.equal(Buffer.byteLength(predecessor), migration.predecessorByteLength)
  assert.equal(dashboardSettingsSectionFrameSha256(predecessor), migration.predecessorSha256)
  assert.equal(
    peelCadenceDashboardSettingsSectionFrame(current, migration.file),
    predecessor,
    `${migration.file} reconstructs its exact frozen predecessor bytes`,
  )
  assert.equal(
    dashboardSettingsSectionFrameSha256(
      peelCadenceDashboardSettingsSectionFrame(current, migration.file),
    ),
    migration.predecessorSha256,
    `${migration.file} inverse peel preserves its frozen predecessor SHA-256`,
  )
  assert.equal(
    occurrences(current, `class="${dashboardSettingsSectionFrameClass}"`),
    0,
    `${migration.file} keeps the canonical class in the transparent frame only`,
  )
}

console.log(`dashboard_settings_section_frame_migration_test passed (${scenarios.length} scenarios)`)
