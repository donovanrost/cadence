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
  narrowFormPageFrameCallerNames,
  narrowFormPageFrameClass,
  narrowFormPageFrameImport,
  narrowFormPageFrameMigrations,
  narrowFormPageFramePath,
  narrowFormPageFramePredecessorCommit,
  narrowFormPageFrameSha256,
  peelCadenceNarrowFormPageFrame,
} from "./narrow_form_page_frame_test_support.mjs"

const scenarios = Object.freeze([
  "the exact predecessor resolves as a commit and is an ancestor of current HEAD",
  "exactly the five audited callers import and use the transparent frame",
  "the frozen base has exactly five eligible narrow-form roots and excludes max-w-2xl and Ops space-y-5 shells",
  "all five callers reconstruct their frozen predecessor bytes and SHA-256 values exactly",
  "the five real caller SFCs parse and compile with the pinned Vue compiler",
])

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
assert.equal(process.execPath, pinnedNode)
assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `CadenceNarrowFormPageFrame migration uses pinned Node ${expectedNodeVersion}`,
)
assert.equal(scenarios.length, 5)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const occurrences = (source, fragment) => source.split(fragment).length - 1
const git = args => execFileSync("git", ["-C", repositoryRoot, ...args], {encoding: "utf8"})
const frozenSource = migration =>
  git(["show", `${narrowFormPageFramePredecessorCommit}:${migration.repositoryPath}`])

assert.equal(
  git(["cat-file", "-t", narrowFormPageFramePredecessorCommit]).trim(),
  "commit",
  "the frozen predecessor resolves exactly as a commit",
)
assert.equal(
  git(["rev-parse", "--verify", `${narrowFormPageFramePredecessorCommit}^{commit}`]).trim(),
  narrowFormPageFramePredecessorCommit,
  "the frozen predecessor resolves to its exact commit object",
)
assert.doesNotThrow(
  () => git(["merge-base", "--is-ancestor", narrowFormPageFramePredecessorCommit, "HEAD"]),
  "the frozen predecessor is an ancestor of current HEAD",
)

assert.equal(narrowFormPageFrameMigrations.length, 5)
assert.deepEqual(
  [...narrowFormPageFrameCallerNames].sort(),
  [
    "AdminOrganizationInvite.vue",
    "AdminOrganizationNew.vue",
    "MissionNew.vue",
    "SpacecraftEdit.vue",
    "SpacecraftNew.vue",
  ],
  "the migration ledger is exactly the five named callers",
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
  .filter(({source}) => occurrences(source, narrowFormPageFrameImport) > 0)
  .map(({file}) => file)
  .sort()

assert.deepEqual(
  importedCallers,
  [...narrowFormPageFrameCallerNames].sort(),
  "exactly the five audited callers import the narrow form frame",
)
assert.equal(
  currentSources.reduce((total, {source}) => total + occurrences(source, narrowFormPageFrameImport), 0),
  5,
  "the current Vue source tree has exactly five narrow form frame imports",
)
assert.equal(
  currentSources.reduce(
    (total, {source}) => total + (source.match(/<CadenceNarrowFormPageFrame\b/g)?.length ?? 0),
    0,
  ),
  5,
  "the current Vue source tree has exactly five narrow form frame openings",
)
assert.equal(
  currentSources.reduce(
    (total, {source}) => total + occurrences(source, "</CadenceNarrowFormPageFrame>"),
    0,
  ),
  5,
  "the current Vue source tree has exactly five narrow form frame closings",
)
assert.equal(
  currentSources.reduce(
    (total, {source}) => total + occurrences(source, `<div class="${narrowFormPageFrameClass}">`),
    0,
  ),
  0,
  "no eligible native narrow-form root remains in current Vue sources",
)
assert.deepEqual(
  currentSources
    .filter(({source}) => occurrences(source, narrowFormPageFrameImport) > 0)
    .filter(({source}) => /max-w-2xl|space-y-5/.test(source))
    .map(({file}) => file),
  [],
  "the audited frame excludes max-w-2xl callers and Ops space-y-5 shells",
)

const predecessorEligibleRoots = narrowFormPageFrameMigrations.flatMap(migration => {
  const source = frozenSource(migration)
  return occurrences(source, migration.predecessorOpening) > 0
    ? [migration.file]
    : []
})
assert.deepEqual(
  predecessorEligibleRoots.sort(),
  [...narrowFormPageFrameCallerNames].sort(),
  "the frozen base has exactly the five audited narrow-form roots",
)

for (const migration of narrowFormPageFrameMigrations) {
  const predecessor = frozenSource(migration)
  const current = await readFile(resolve(repositoryRoot, migration.repositoryPath), "utf8")

  assert.equal(
    git(["rev-parse", `${narrowFormPageFramePredecessorCommit}:${migration.repositoryPath}`]).trim(),
    migration.predecessorBlobId,
    `${migration.file} keeps its frozen predecessor blob object`,
  )
  assert.equal(Buffer.byteLength(predecessor), migration.predecessorByteLength)
  assert.equal(narrowFormPageFrameSha256(predecessor), migration.predecessorSha256)
  assert.equal(
    peelCadenceNarrowFormPageFrame(current, migration.file),
    predecessor,
    `${migration.file} reconstructs its exact frozen predecessor bytes`,
  )
  assert.equal(
    narrowFormPageFrameSha256(peelCadenceNarrowFormPageFrame(current, migration.file)),
    migration.predecessorSha256,
    `${migration.file} inverse peel preserves its frozen predecessor SHA-256`,
  )
}

const dom = installDom('<main id="narrow-form-page-frame-migration"></main>')
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

for (const migration of narrowFormPageFrameMigrations) {
  const componentPath = resolve(repositoryRoot, migration.repositoryPath)
  const source = await readFile(componentPath, "utf8")
  const parsed = parse(source, {filename: componentPath})

  assert.deepEqual(parsed.errors, [], `${migration.file} parses with the pinned Vue compiler`)
  assert.ok(parsed.descriptor.scriptSetup, `${migration.file} retains script setup`)
  assert.ok(parsed.descriptor.template, `${migration.file} retains its template`)
  assert.doesNotThrow(
    () => compileScript(parsed.descriptor, {id: `cadence-narrow-form-${migration.file}`}),
    `${migration.file} compiles as a real SFC script`,
  )
  assert.deepEqual(
    compileTemplate({
      source: parsed.descriptor.template.content,
      filename: componentPath,
      id: `cadence-narrow-form-template-${migration.file}`,
    }).errors,
    [],
    `${migration.file} compiles as a real SFC template`,
  )
}

dom.window.close()
console.log(
  `narrow_form_page_frame_migration_test passed (${narrowFormPageFrameMigrations.length} callers + exact ${narrowFormPageFramePredecessorCommit} reconstructions)`,
)
