#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {readFile, readdir} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {expectedNodeVersion, integrationRequire} from "./reka_adapter_test_support.mjs"
import {
  opsPageBodyFrameCallerNames,
  opsPageBodyFrameClass,
  opsPageBodyFrameImport,
  opsPageBodyFrameMigrations,
  opsPageBodyFramePath,
  opsPageBodyFramePredecessorCommit,
  opsPageBodyFrameSha256,
  peelCadenceOpsPageBodyFrame,
} from "./ops_page_body_frame_test_support.mjs"

const scenarios = Object.freeze([
  "the exact predecessor resolves and is an ancestor of current HEAD",
  "exactly two callers import and use the page-body frame",
  "the frozen base has exactly two native wrappers and no third eligible match",
  "both callers reconstruct their frozen predecessor bytes, blobs, and SHA-256 values exactly",
  "the real successor callers parse after the bounded import and wrapper migration",
])

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
assert.equal(process.execPath, pinnedNode, "Ops page-body migration uses the pinned Node executable")
assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `Ops page-body migration uses pinned Node ${expectedNodeVersion}`,
)
assert.equal(scenarios.length, 5)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const gitText = args => execFileSync("git", ["-C", repositoryRoot, ...args], {encoding: "utf8"})
const frozenSource = migration => gitText(["show", `${opsPageBodyFramePredecessorCommit}:${migration.repositoryPath}`])
const occurrences = (source, fragment) => source.split(fragment).length - 1

assert.equal(
  gitText(["cat-file", "-t", opsPageBodyFramePredecessorCommit]).trim(),
  "commit",
  "the frozen page-body predecessor resolves as a commit",
)
assert.equal(
  gitText(["rev-parse", "--verify", `${opsPageBodyFramePredecessorCommit}^{commit}`]).trim(),
  opsPageBodyFramePredecessorCommit,
  "the frozen page-body predecessor resolves to the requested object",
)
assert.doesNotThrow(
  () => gitText(["merge-base", "--is-ancestor", opsPageBodyFramePredecessorCommit, "HEAD"]),
  "the frozen page-body predecessor is an ancestor of current HEAD",
)

assert.equal(opsPageBodyFrameMigrations.length, 1, "the page-body ledger has exactly one caller")
assert.deepEqual(
  [...opsPageBodyFrameCallerNames].sort(),
  ["OpsDashboardDirectory.vue"],
  "the page-body ledger is exactly the surviving caller",
)

const currentVueFiles = (await readdir(vueDirectory, {recursive: true}))
  .filter(file => file.endsWith(".vue"))
  .sort()
const currentSources = await Promise.all(
  currentVueFiles.map(async file => ({
    file,
    source: await readFile(resolve(vueDirectory, file), "utf8"),
  })),
)
const importedCallers = currentSources
  .filter(({source}) => occurrences(source, opsPageBodyFrameImport) > 0)
  .map(({file}) => file)
  .sort()

assert.deepEqual(
  importedCallers,
  ["OpsDashboardDirectory.vue"],
  "exactly one surviving caller imports CadenceOpsPageBodyFrame",
)
assert.equal(
  currentSources.reduce((total, {source}) => total + occurrences(source, opsPageBodyFrameImport), 0),
  1,
  "the Vue source tree has exactly one page-body frame import",
)
assert.equal(
  currentSources.reduce(
    (total, {source}) => total + (source.match(/<CadenceOpsPageBodyFrame\b/g)?.length ?? 0),
    0,
  ),
  1,
  "the Vue source tree has exactly one page-body frame opening",
)
assert.equal(
  currentSources.reduce(
    (total, {source}) => total + (source.match(/<\/CadenceOpsPageBodyFrame>/g)?.length ?? 0),
    0,
  ),
  1,
  "the Vue source tree has exactly one page-body frame closing",
)
assert.equal(
  currentSources.reduce((total, {source}) => total + occurrences(source, `<div class="${opsPageBodyFrameClass}">`), 0),
  0,
  "no eligible native page-body wrapper remains in current Vue sources",
)

const predecessorVueFiles = gitText([
  "ls-tree",
  "-r",
  "--name-only",
  opsPageBodyFramePredecessorCommit,
  "apps/cadence_web/assets/vue",
])
  .trim()
  .split("\n")
  .filter(file => file.endsWith(".vue"))
  .map(file => file.slice("apps/cadence_web/assets/vue/".length))
  .sort()
const historicalEligibleRoots = predecessorVueFiles.flatMap(file => {
  const source = gitText(["show", `${opsPageBodyFramePredecessorCommit}:apps/cadence_web/assets/vue/${file}`])
  const count = occurrences(source, `<div class="${opsPageBodyFrameClass}">`)
  return count > 0 && currentVueFiles.includes(file) ? [{file, count}] : []
})

assert.equal(
  historicalEligibleRoots.reduce((total, {count}) => total + count, 0),
  1,
  "the surviving frozen base has exactly one original eligible native page-body wrapper",
)
assert.deepEqual(
  historicalEligibleRoots,
  [
    {file: "OpsDashboardDirectory.vue", count: 1},
  ],
  "the frozen base wrappers are exactly the two audited callers",
)
assert.ok(
  currentVueFiles.includes(opsPageBodyFramePath.slice("apps/cadence_web/assets/vue/".length)),
  "the successor includes the new page-body frame path",
)

const {parse} = integrationRequire("@vue/compiler-sfc")
for (const migration of opsPageBodyFrameMigrations) {
  const current = await readFile(resolve(vueDirectory, migration.file), "utf8")
  const predecessor = frozenSource(migration)

  assert.equal(
    gitText(["rev-parse", `${opsPageBodyFramePredecessorCommit}:${migration.repositoryPath}`]).trim(),
    migration.predecessorBlobId,
    `${migration.file} keeps its frozen predecessor blob object`,
  )
  assert.equal(Buffer.byteLength(predecessor), migration.predecessorByteLength)
  assert.equal(opsPageBodyFrameSha256(predecessor), migration.predecessorSha256)
  assert.equal(
    peelCadenceOpsPageBodyFrame(current, migration.file),
    predecessor,
    `${migration.file} reconstructs its exact frozen predecessor bytes`,
  )
  assert.equal(
    opsPageBodyFrameSha256(peelCadenceOpsPageBodyFrame(current, migration.file)),
    migration.predecessorSha256,
    `${migration.file} inverse peel preserves its frozen predecessor SHA-256`,
  )
  assert.deepEqual(parse(current, {filename: migration.repositoryPath}).errors, [])
}

console.log(`ops_page_body_frame_migration_test passed (${scenarios.length} exact-DOM scenarios)`)
