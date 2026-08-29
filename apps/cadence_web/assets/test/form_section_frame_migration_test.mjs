#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {readFile, readdir} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

import {
  expectedNodeVersion,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"
import {
  formSectionFrameCallerNames,
  formSectionFrameClass,
  formSectionFrameImport,
  formSectionFrameMigrations,
  formSectionFramePredecessorCommit,
  formSectionFrameSha256,
  peelCadenceFormSectionFrame,
} from "./form_section_frame_test_support.mjs"

const scenarios = Object.freeze([
  "the exact predecessor resolves as a commit and is an ancestor of current HEAD",
  "exactly the eight audited callers import and use the transparent section frame",
  "the frozen base has exactly 28 eligible section roots with the header first",
  "all eight callers reconstruct their frozen predecessor bytes and SHA-256 values exactly",
  "the eight real caller SFCs parse and compile with the pinned Vue compiler",
])

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
assert.equal(process.execPath, pinnedNode)
assert.equal(process.versions.node, expectedNodeVersion)
assert.equal(scenarios.length, 5)
assert.notEqual(formSectionFramePredecessorCommit, "HEAD")

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const git = args => execFileSync("git", ["-C", repositoryRoot, ...args], {encoding: "utf8"})
const occurrences = (source, fragment) => source.split(fragment).length - 1
const frozenSource = migration =>
  git(["show", `${formSectionFramePredecessorCommit}:${migration.repositoryPath}`])

assert.equal(
  git(["cat-file", "-t", formSectionFramePredecessorCommit]).trim(),
  "commit",
  "the frozen predecessor resolves exactly as a commit",
)
assert.equal(
  git(["rev-parse", "--verify", `${formSectionFramePredecessorCommit}^{commit}`]).trim(),
  formSectionFramePredecessorCommit,
  "the frozen predecessor resolves to its exact commit object",
)
assert.doesNotThrow(
  () => git(["merge-base", "--is-ancestor", formSectionFramePredecessorCommit, "HEAD"]),
  "the frozen predecessor is an ancestor of current HEAD",
)

assert.equal(formSectionFrameMigrations.length, 8, "all eight callers are inventoried")
assert.equal(
  formSectionFrameMigrations.reduce((total, migration) => total + migration.roots.length, 0),
  28,
  "all 28 eligible roots are inventoried",
)
assert.deepEqual(
  [...formSectionFrameCallerNames].sort(),
  [
    "CommsGroundStationForm.vue",
    "CommsProviderNew.vue",
    "CommsRoutingNew.vue",
    "CommsTransportNew.vue",
    "ProviderAccountNew.vue",
    "SpacecraftEdit.vue",
    "SpacecraftNew.vue",
    "SpacecraftTypeNew.vue",
  ],
  "the migration ledger is exactly the eight named callers",
)

const eligibleRootLines = source => {
  const roots = []
  for (const opening of source.matchAll(/<section\b[^>]*>/g)) {
    const classAttribute = opening[0].match(/\bclass="([^"]*)"/)
    if (!classAttribute || !classAttribute[1].split(/\s+/).includes(formSectionFrameClass)) continue

    const remainder = source.slice(opening.index + opening[0].length)
    const firstTag = remainder.match(/^\s*<([A-Za-z][\w-]*)\b/)
    assert.equal(firstTag?.[1], "CadenceFormSectionHeader", "each eligible root keeps its header first")
    roots.push(source.slice(0, opening.index).split("\n").length)
  }
  return roots
}

const currentVueFiles = (await readdir(vueDirectory)).filter(file => file.endsWith(".vue")).sort()
const currentSources = await Promise.all(
  currentVueFiles.map(async file => ({
    file,
    repositoryPath: `apps/cadence_web/assets/vue/${file}`,
    source: await readFile(resolve(vueDirectory, file), "utf8"),
  })),
)
const importedCallers = currentSources
  .filter(({source}) => occurrences(source, formSectionFrameImport) > 0)
  .map(({file}) => file)
  .sort()
const currentCallerSources = currentSources.filter(({file}) => formSectionFrameCallerNames.includes(file))

assert.deepEqual(
  importedCallers,
  [...formSectionFrameCallerNames].sort(),
  "exactly the eight audited callers import the section frame",
)
assert.equal(
  currentSources.reduce((total, {source}) => total + occurrences(source, formSectionFrameImport), 0),
  8,
  "the current Vue source tree has exactly eight section-frame imports",
)
assert.equal(
  currentSources.reduce(
    (total, {source}) => total + (source.match(/<CadenceFormSectionFrame\b/g)?.length ?? 0),
    0,
  ),
  28,
  "the current Vue source tree has exactly 28 section-frame openings",
)
assert.equal(
  currentSources.reduce((total, {source}) => total + occurrences(source, "</CadenceFormSectionFrame>"), 0),
  28,
  "the current Vue source tree has exactly 28 section-frame closings",
)
assert.equal(
  currentCallerSources.reduce((total, {source}) => total + (source.match(/<section\b/g)?.length ?? 0), 0),
  0,
  "no eligible caller retains a native section opening",
)

for (const migration of formSectionFrameMigrations) {
  const predecessor = frozenSource(migration)
  const current = await readFile(resolve(repositoryRoot, migration.repositoryPath), "utf8")
  const predecessorRoots = eligibleRootLines(predecessor)

  assert.deepEqual(
    predecessorRoots,
    migration.roots.map(frameRoot => frameRoot.boundary),
    `${migration.file} has exactly its frozen eligible root boundaries`,
  )
  assert.equal(
    git(["rev-parse", `${formSectionFramePredecessorCommit}:${migration.repositoryPath}`]).trim(),
    migration.predecessorBlobId,
    `${migration.file} keeps its frozen predecessor blob object`,
  )
  assert.equal(Buffer.byteLength(predecessor), migration.predecessorByteLength)
  assert.equal(formSectionFrameSha256(predecessor), migration.predecessorSha256)
  assert.equal(
    peelCadenceFormSectionFrame(current, migration.file),
    predecessor,
    `${migration.file} reconstructs its exact frozen predecessor bytes`,
  )
  assert.equal(
    formSectionFrameSha256(peelCadenceFormSectionFrame(current, migration.file)),
    migration.predecessorSha256,
    `${migration.file} inverse peel preserves its frozen predecessor SHA-256`,
  )
}

const {compileScript, compileTemplate, parse} = integrationRequire("@vue/compiler-sfc")
for (const migration of formSectionFrameMigrations) {
  const componentPath = resolve(repositoryRoot, migration.repositoryPath)
  const source = await readFile(componentPath, "utf8")
  const parsed = parse(source, {filename: componentPath})

  assert.deepEqual(parsed.errors, [], `${migration.file} parses with the pinned Vue compiler`)
  assert.ok(parsed.descriptor.scriptSetup, `${migration.file} retains script setup`)
  assert.ok(parsed.descriptor.template, `${migration.file} retains its template`)
  assert.doesNotThrow(
    () => compileScript(parsed.descriptor, {id: `cadence-form-section-${migration.file}`}),
    `${migration.file} compiles as a real SFC script`,
  )
  assert.deepEqual(
    compileTemplate({
      source: parsed.descriptor.template.content,
      filename: componentPath,
      id: `cadence-form-section-template-${migration.file}`,
    }).errors,
    [],
    `${migration.file} compiles as a real SFC template`,
  )
}

console.log(
  `form_section_frame_migration_test passed (8 callers, 28 roots + exact ${formSectionFramePredecessorCommit} reconstructions)`,
)
