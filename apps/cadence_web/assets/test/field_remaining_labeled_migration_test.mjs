import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {integrationRequire, expectedNodeVersion} from "./reka_adapter_test_support.mjs"
import {
  labeledControlFieldBoundaries,
  labeledControlFieldCounts,
  labeledControlFieldFiles,
  labeledControlFieldFrozenFingerprints,
  labeledControlFieldMigrationBase,
  labeledControlFieldMigratedOpening,
  oldLabeledControlFieldOpening,
  peelLabeledControlFields,
} from "./labeled_control_field_test_support.mjs"

assert.equal(process.execPath, "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node")
assert.equal(process.versions.node, expectedNodeVersion)
assert.equal(labeledControlFieldFiles.length, 17, "the owned cohort has exactly 17 callers")
assert.equal(labeledControlFieldBoundaries.length, 40, "the owned cohort has exactly 40 boundaries")
assert.deepEqual(
  [...new Set(labeledControlFieldBoundaries.map(({file}) => file))],
  labeledControlFieldFiles,
  "the boundary ledger contains exactly the 17 named callers",
)
assert.equal(
  labeledControlFieldBoundaries.filter(({oldLabelFor}) => oldLabelFor !== null).length,
  2,
  "only the two frozen :for label topologies retain control-id",
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const sourcePath = (file) => resolve(vueDirectory, file)
const repositoryPath = (file) => `apps/cadence_web/assets/vue/${file}`
const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const occurrences = (source, fragment) => source.split(fragment).length - 1
const git = (args, options = {}) =>
  execFileSync("git", args, {cwd: repositoryRoot, ...options}).toString().trim()
const frozenSource = (file) =>
  execFileSync("git", ["show", `${labeledControlFieldMigrationBase}:${repositoryPath(file)}`], {
    cwd: repositoryRoot,
  }).toString("utf8")

assert.equal(
  git(["rev-parse", "--verify", `${labeledControlFieldMigrationBase}^{commit}`]),
  labeledControlFieldMigrationBase,
  "the frozen predecessor resolves as the exact supplied commit",
)
const head = git(["rev-parse", "HEAD"])
assert.doesNotThrow(
  () =>
    execFileSync("git", ["merge-base", "--is-ancestor", labeledControlFieldMigrationBase, head], {
      cwd: repositoryRoot,
      stdio: "ignore",
    }),
  "the frozen predecessor is an ancestor of HEAD without requiring HEAD equality",
)

const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const excludedFormPresentationPath = resolve(
  vueDirectory,
  "data_link_inspector/FormPresentation.vue",
)
const excludedFormPresentation = await readFile(excludedFormPresentationPath, "utf8")
assert.doesNotMatch(
  excludedFormPresentation,
  /CadenceField/,
  "nested data_link_inspector/FormPresentation.vue remains outside the cohort",
)

const preservedFragments = [
  'type="hidden"',
  'phx-update="stream"',
  "phx-hook=",
  "v-model=",
  "phx-debounce=",
  ":key=",
]

for (const file of labeledControlFieldFiles) {
  const current = await readFile(sourcePath(file), "utf8")
  const frozen = frozenSource(file)
  const fingerprint = labeledControlFieldFrozenFingerprints[file]
  const boundaries = labeledControlFieldBoundaries.filter((entry) => entry.file === file)

  assert.equal(boundaries.length, labeledControlFieldCounts[file], `${file}: boundary count is frozen`)
  assert.equal(Buffer.byteLength(frozen), fingerprint.byteLength, `${file}: frozen byte length`)
  assert.equal(sha256(frozen), fingerprint.sha256, `${file}: frozen SHA-256`)
  assert.equal(
    git(["rev-parse", `${labeledControlFieldMigrationBase}:${repositoryPath(file)}`]),
    fingerprint.blobId,
    `${file}: frozen blob ID`,
  )

  const frozenLines = frozen.toString("utf8").split("\n")
  for (const entry of boundaries) {
    const opening = oldLabeledControlFieldOpening(entry)
    assert.equal(
      frozenLines[entry.line - 1],
      opening.split("\n", 1)[0],
      `${file}:${entry.line}: exact eligible wrapper opening is frozen`,
    )
    const lineOffset =
      (entry.line === 1 ? "" : frozenLines.slice(0, entry.line - 1).join("\n") + "\n").length
    assert.equal(
      frozen.slice(lineOffset, lineOffset + opening.length),
      opening,
      `${file}:${entry.line}: full wrapper opening is frozen`,
    )
  }

  const parsed = parse(current, {filename: sourcePath(file)})
  assert.deepEqual(parsed.errors, [], `${file}: real SFC parses`)
  assert.ok(parsed.descriptor.scriptSetup, `${file}: script setup remains present`)
  assert.ok(parsed.descriptor.template, `${file}: template remains present`)
  assert.doesNotThrow(
    () => compileScript(parsed.descriptor, {id: `field-cohort-${file}`, inlineTemplate: true}),
    `${file}: real SFC compiles with the pinned Vue compiler`,
  )

  assert.equal(
    occurrences(current, 'import CadenceField from "./ui/components/CadenceField.vue"'),
    1,
    `${file}: existing CadenceField import is singular`,
  )
  assert.equal(
    occurrences(current, "<CadenceField\n"),
    boundaries.length,
    `${file}: every eligible boundary has one migrated opening`,
  )
  assert.equal(
    occurrences(current, "</CadenceField>"),
    boundaries.length,
    `${file}: every eligible boundary has one migrated closing`,
  )
  assert.equal(
    (current.match(/\bcontrol-id=/g) ?? []).length,
    boundaries.filter(({oldLabelFor}) => oldLabelFor !== null).length,
    `${file}: control-id is present only where the frozen label had :for`,
  )
  for (const entry of boundaries) {
    assert.equal(
      occurrences(current, labeledControlFieldMigratedOpening(entry)),
      1,
      `${file}:${entry.line}: exact migrated frame is present`,
    )
  }

  const reconstructed = peelLabeledControlFields(current, file)
  assert.equal(reconstructed, frozen.toString("utf8"), `${file}: inverse reconstruction is byte exact`)
  assert.equal(Buffer.byteLength(reconstructed), fingerprint.byteLength, `${file}: reconstructed byte length`)
  assert.equal(sha256(reconstructed), fingerprint.sha256, `${file}: reconstructed SHA-256`)
  assert.equal(
    git(["hash-object", "--no-filters", "--stdin"], {input: reconstructed}),
    fingerprint.blobId,
    `${file}: reconstructed blob ID`,
  )

  for (const fragment of preservedFragments) {
    assert.equal(
      occurrences(current, fragment),
      occurrences(reconstructed, fragment),
      `${file}: ${fragment} remains caller-owned and unchanged`,
    )
  }
}

const directiveBoundaries = labeledControlFieldBoundaries.filter(
  ({directives}) => directives.length > 0,
)
assert.equal(directiveBoundaries.length, 10, "all 10 keyed wrapper boundaries retain their directives")
assert.equal(
  labeledControlFieldBoundaries.filter(({help}) => help).length,
  1,
  "the one post-label help sibling uses the named help slot",
)
assert.equal(
  labeledControlFieldBoundaries.filter(({errors}) => errors).length,
  9,
  "all nine post-label validation sibling groups use the named errors slot",
)

console.log(
  "field_remaining_labeled_migration_test passed (17 callers, 40 boundaries, exact inverse fingerprints, 10 keyed frames)",
)
