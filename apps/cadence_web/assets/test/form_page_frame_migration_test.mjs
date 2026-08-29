#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {readFile, readdir} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

import {
  expectedNodeVersion,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"
import {
  formPageFrameCallerNames,
  formPageFrameClass,
  formPageFrameImport,
  formPageFrameMigrations,
  formPageFramePredecessorCommit,
  formPageFrameSha256,
  peelCadenceFormPageFrame,
} from "./form_page_frame_test_support.mjs"

const scenarios = Object.freeze([
  "the exact predecessor resolves as a commit and is an ancestor of current HEAD",
  "exactly the four audited callers import and use the transparent frame",
  "the frozen base has exactly the four eligible max-w-2xl roots",
  "all four callers reconstruct their frozen predecessor bytes and SHA-256 values exactly",
  "the four real caller SFCs parse and compile with the pinned Vue compiler",
])

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
assert.equal(process.execPath, pinnedNode)
assert.equal(process.versions.node, expectedNodeVersion)
assert.equal(scenarios.length, 5)
assert.notEqual(formPageFramePredecessorCommit, "HEAD")

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const occurrences = (source, fragment) => source.split(fragment).length - 1
const git = args => execFileSync("git", ["-C", repositoryRoot, ...args], {encoding: "utf8"})
const frozenSource = migration =>
  git(["show", `${formPageFramePredecessorCommit}:${migration.repositoryPath}`])

assert.equal(
  git(["cat-file", "-t", formPageFramePredecessorCommit]).trim(),
  "commit",
  "the frozen predecessor resolves exactly as a commit",
)
assert.equal(
  git(["rev-parse", "--verify", `${formPageFramePredecessorCommit}^{commit}`]).trim(),
  formPageFramePredecessorCommit,
  "the frozen predecessor resolves to its exact commit object",
)
assert.doesNotThrow(
  () => git(["merge-base", "--is-ancestor", formPageFramePredecessorCommit, "HEAD"]),
  "the frozen predecessor is an ancestor of current HEAD",
)

assert.equal(formPageFrameMigrations.length, 4)
assert.deepEqual(
  [...formPageFrameCallerNames].sort(),
  [
    "CatalogDatabaseNew.vue",
    "CommsGroundStationForm.vue",
    "CommsRoutingNew.vue",
    "SpacecraftTypeNew.vue",
  ],
  "the migration ledger is exactly the four named callers",
)

const currentVueFiles = (await readdir(vueDirectory, {recursive: true}))
  .filter(file => file.endsWith(".vue"))
  .sort()
const currentSources = await Promise.all(
  currentVueFiles.map(async file => ({
    file,
    repositoryPath: `apps/cadence_web/assets/vue/${file}`,
    source: await readFile(resolve(vueDirectory, file), "utf8"),
  })),
)
const importedCallers = currentSources
  .filter(({source}) => occurrences(source, formPageFrameImport) > 0)
  .map(({file}) => file)
  .sort()

assert.deepEqual(
  importedCallers,
  [...formPageFrameCallerNames].sort(),
  "exactly the four audited callers import the form page frame",
)
assert.equal(
  currentSources.reduce((total, {source}) => total + occurrences(source, formPageFrameImport), 0),
  4,
  "the current Vue source tree has exactly four form page frame imports",
)
assert.equal(
  currentSources.reduce(
    (total, {source}) => total + (source.match(/<CadenceFormPageFrame\b/g)?.length ?? 0),
    0,
  ),
  4,
  "the current Vue source tree has exactly four form page frame openings",
)
assert.equal(
  currentSources.reduce((total, {source}) => total + occurrences(source, "</CadenceFormPageFrame>"), 0),
  4,
  "the current Vue source tree has exactly four form page frame closings",
)
assert.equal(
  currentSources.reduce(
    (total, {source}) => total + occurrences(source, `<div class="${formPageFrameClass}">`),
    0,
  ),
  0,
  "no eligible native max-w-2xl root remains in current Vue sources",
)

const predecessorVueFiles = git([
  "ls-tree",
  "-r",
  "--name-only",
  formPageFramePredecessorCommit,
  "apps/cadence_web/assets/vue",
])
  .trim()
  .split("\n")
  .filter(file => file.endsWith(".vue"))
const predecessorEligibleRoots = predecessorVueFiles.flatMap(repositoryPath => {
  const source = git(["show", `${formPageFramePredecessorCommit}:${repositoryPath}`])
  const rootMatches = source.match(/^  <div\b[^>]*class="space-y-6 max-w-2xl"[^>]*>$/gm) ?? []
  return rootMatches.length === 1 ? [repositoryPath.split("/").at(-1)] : []
})
assert.deepEqual(
  predecessorEligibleRoots.sort(),
  [...formPageFrameCallerNames].sort(),
  "the frozen base has exactly the four audited max-w-2xl roots and excludes near variants",
)

for (const migration of formPageFrameMigrations) {
  const predecessor = frozenSource(migration)
  const current = await readFile(resolve(repositoryRoot, migration.repositoryPath), "utf8")

  assert.equal(
    git(["rev-parse", `${formPageFramePredecessorCommit}:${migration.repositoryPath}`]).trim(),
    migration.predecessorBlobId,
    `${migration.file} keeps its frozen predecessor blob object`,
  )
  assert.equal(Buffer.byteLength(predecessor), migration.predecessorByteLength)
  assert.equal(formPageFrameSha256(predecessor), migration.predecessorSha256)
  assert.equal(
    peelCadenceFormPageFrame(current, migration.file),
    predecessor,
    `${migration.file} reconstructs its exact frozen predecessor bytes`,
  )
  assert.equal(
    formPageFrameSha256(peelCadenceFormPageFrame(current, migration.file)),
    migration.predecessorSha256,
    `${migration.file} inverse peel preserves its frozen predecessor SHA-256`,
  )
  assert.equal(
    occurrences(current, migration.opening),
    1,
    `${migration.file} has one exact frame opening with caller-owned root attrs`,
  )
}

const dom = installDom('<main id="form-page-frame-migration"></main>')
for (const globalName of [
  "Document",
  "ShadowRoot",
  "HTMLFormElement",
  "HTMLInputElement",
  "HTMLSelectElement",
  "HTMLButtonElement",
]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}
const {compileScript, compileTemplate, parse} = integrationRequire("@vue/compiler-sfc")

for (const migration of formPageFrameMigrations) {
  const componentPath = resolve(repositoryRoot, migration.repositoryPath)
  const source = await readFile(componentPath, "utf8")
  const parsed = parse(source, {filename: componentPath})

  assert.deepEqual(parsed.errors, [], `${migration.file} parses with the pinned Vue compiler`)
  assert.ok(parsed.descriptor.scriptSetup, `${migration.file} retains script setup`)
  assert.ok(parsed.descriptor.template, `${migration.file} retains its template`)
  assert.doesNotThrow(
    () => compileScript(parsed.descriptor, {id: `cadence-form-page-${migration.file}`}),
    `${migration.file} compiles as a real SFC script`,
  )
  assert.deepEqual(
    compileTemplate({
      source: parsed.descriptor.template.content,
      filename: componentPath,
      id: `cadence-form-page-template-${migration.file}`,
    }).errors,
    [],
    `${migration.file} compiles as a real SFC template`,
  )
}

dom.window.close()
console.log(
  `form_page_frame_migration_test passed (${formPageFrameMigrations.length} callers + exact ${formPageFramePredecessorCommit} reconstructions)`,
)
