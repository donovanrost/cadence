import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {execFileSync} from "node:child_process"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {expectedNodeVersion, loadSfc} from "./reka_adapter_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `CRUD/session field migration contracts use pinned Node ${expectedNodeVersion}`,
)

const baseIdentity = "7643e25b78faf8bf09d7bc3497de88db3b46715a"
const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryDirectory = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const breadcrumbsImport =
  'import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"\n'
const breadcrumbNavClass =
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
const cadenceFieldImport = 'import CadenceField from "./ui/components/CadenceField.vue"\n'
const cadenceDetailsFrameImport =
  'import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"\n'

const occurrences = (source, fragment) => source.split(fragment).length - 1
const digest = (source) => createHash("sha256").update(source).digest("hex")
const peelCadenceDetailsFrames = (source, expectedCount, label) => {
  const expectedImportCount = expectedCount > 0 ? 1 : 0

  assert.equal(occurrences(source, cadenceDetailsFrameImport), expectedImportCount, `${label} details import count`)
  assert.equal(source.match(/<CadenceDetailsFrame\b/g)?.length ?? 0, expectedCount, `${label} details opening count`)
  assert.equal(occurrences(source, "</CadenceDetailsFrame>"), expectedCount, `${label} details closing count`)

  const peeled = source
    .replace(cadenceDetailsFrameImport, "")
    .split("<CadenceDetailsFrame")
    .join("<details")
    .split("</CadenceDetailsFrame>")
    .join("</details>")

  assert.doesNotMatch(peeled, /CadenceDetailsFrame/)
  return peeled
}

const peelCadenceBreadcrumbs = (source, label) => {
  const importCount = occurrences(source, breadcrumbsImport)
  const openingCount = occurrences(source, "<CadenceBreadcrumbs>")
  const closingCount = occurrences(source, "</CadenceBreadcrumbs>")

  if (importCount === 0) {
    assert.equal(openingCount, 0, `${label} has no unimported breadcrumb opening`)
    assert.equal(closingCount, 0, `${label} has no unimported breadcrumb closing`)
    return source
  }

  assert.equal(importCount, 1, `${label} has one exact breadcrumb import`)
  assert.equal(openingCount, 1, `${label} has one exact breadcrumb opening`)
  assert.equal(closingCount, 1, `${label} has one exact breadcrumb closing`)

  const openingMatch = source.match(/^( *)<CadenceBreadcrumbs>$/m)
  assert.ok(openingMatch, `${label} has an explicitly bounded breadcrumb opening`)
  const indent = openingMatch[1]
  const wrapperOpening = `${indent}<CadenceBreadcrumbs>`
  const wrapperClosing = `${indent}</CadenceBreadcrumbs>`
  const nativeOpening = `${indent}<nav
${indent}  aria-label="Breadcrumb"
${indent}  class="${breadcrumbNavClass}"
${indent}>`

  assert.equal(occurrences(source, wrapperOpening), 1, `${label} opening indentation is exact`)
  assert.equal(occurrences(source, wrapperClosing), 1, `${label} closing indentation is exact`)

  const peeled = source
    .replace(breadcrumbsImport, "")
    .replace(wrapperOpening, nativeOpening)
    .replace(wrapperClosing, `${indent}</nav>`)

  assert.equal(occurrences(peeled, "CadenceBreadcrumbs"), 0, `${label} breadcrumb peel is exact`)
  return peeled
}

const singleLineLabel = (indent, expression) =>
  `${indent}    <span class="hud-label block mb-1.5">{{ ${expression} }}</span>`

const multilineLabel = (indent, expression) =>
  `${indent}    <span class="hud-label block mb-1.5">
${indent}      {{ ${expression} }}
${indent}    </span>`

const field = (name, indent, controlId, labelExpression, labelSource) => ({
  name,
  indent,
  controlId,
  labelExpression,
  labelSource,
})

const missionFields = [
  field(
    "display name",
    "      ",
    "form.fields.display_name.id",
    "form.fields.display_name.label",
    singleLineLabel("      ", "form.fields.display_name.label"),
  ),
  field(
    "slug",
    "      ",
    "form.fields.slug.id",
    "form.fields.slug.label",
    singleLineLabel("      ", "form.fields.slug.label"),
  ),
]

const spacecraftFields = [
  field(
    "display name",
    "        ",
    "form.fields.display_name.id",
    "form.fields.display_name.label",
    singleLineLabel("        ", "form.fields.display_name.label"),
  ),
  field(
    "SCID",
    "        ",
    "form.fields.scid.id",
    "form.fields.scid.label",
    singleLineLabel("        ", "form.fields.scid.label"),
  ),
  field(
    "spacecraft type",
    "        ",
    "form.fields.spacecraft_type_id.id",
    "form.fields.spacecraft_type_id.label",
    multilineLabel("        ", "form.fields.spacecraft_type_id.label"),
  ),
]

const sessionFields = [
  field(
    "email",
    "      ",
    "form.fields.email.id",
    "form.fields.email.label",
    singleLineLabel("      ", "form.fields.email.label"),
  ),
  field(
    "password",
    "      ",
    "form.fields.password.id",
    "form.fields.password.label",
    singleLineLabel("      ", "form.fields.password.label"),
  ),
]

const fixtures = Object.freeze([
  {
    filename: "CommsTransportNew.vue",
    repositoryPath: "apps/cadence_web/assets/vue/CommsTransportNew.vue",
    headSha256: "ecb5b7ec66cd67acac5df776f0c870cbdda91e89ef093cb2905ab800fcb221ee",
    expectedFrames: 7,
    frozenCandidates: 1,
    fields: [],
    skippedCandidates: 1,
  },
  {
    filename: "MissionNew.vue",
    repositoryPath: "apps/cadence_web/assets/vue/MissionNew.vue",
    headSha256: "f1f586afbdba3c6b3a95aaa69bab73ba28030b0bbc988ba289c4c4aa9de3df61",
    expectedFrames: 2,
    frozenCandidates: 2,
    fields: missionFields,
    skippedCandidates: 0,
  },
  {
    filename: "SpacecraftEdit.vue",
    repositoryPath: "apps/cadence_web/assets/vue/SpacecraftEdit.vue",
    headSha256: "1c2b731dc5fe85a6b8bca9b8db1b68220e5c0282467d50080767917761fb00eb",
    expectedFrames: 3,
    frozenCandidates: 3,
    fields: spacecraftFields,
    skippedCandidates: 0,
  },
  {
    filename: "SpacecraftNew.vue",
    repositoryPath: "apps/cadence_web/assets/vue/SpacecraftNew.vue",
    headSha256: "efba02ad7315dd0b229f608fdd3e59c78e2ba45903988f78b3f56db2f01ed47b",
    expectedFrames: 3,
    frozenCandidates: 3,
    fields: spacecraftFields,
    skippedCandidates: 0,
  },
  {
    filename: "UserSession.vue",
    repositoryPath: "apps/cadence_web/assets/vue/UserSession.vue",
    headSha256: "bbd10e94bb59da7af117ace4a273bdb55be68ea1b29e3813b168b511103dc13d",
    expectedFrames: 2,
    frozenCandidates: 2,
    fields: sessionFields,
    skippedCandidates: 0,
  },
])

const migratedOpening = (entry) =>
  `${entry.indent}<CadenceField
${entry.indent}  :control-id="${entry.controlId}"
${entry.indent}  wrapper-class="fieldset mb-3"
${entry.indent}  :label="${entry.labelExpression}"
${entry.indent}  label-class="hud-label block mb-1.5"
${entry.indent}>`

const reconstructField = (source, entry, filename) => {
  const opening = migratedOpening(entry)
  assert.equal(
    occurrences(source, opening),
    1,
    `${filename} inventories the ${entry.name} CadenceField opening exactly once`,
  )

  const start = source.indexOf(opening)
  const close = `\n${entry.indent}</CadenceField>`
  const end = source.indexOf(close, start + opening.length)
  assert.notEqual(end, -1, `${filename} inventories the ${entry.name} closing exactly once`)

  const callerOwnedControl = source.slice(start + opening.length, end)
  const originalControl = callerOwnedControl.replaceAll(
    `\n${entry.indent}  `,
    `\n${entry.indent}    `,
  )
  const original = `${entry.indent}<div class="fieldset mb-3">
${entry.indent}  <label :for="${entry.controlId}">
${entry.labelSource}${originalControl}
${entry.indent}  </label>
${entry.indent}</div>`

  return source.slice(0, start) + original + source.slice(end + close.length)
}

assert.equal(fixtures.length, 5, "all five owned real SFCs are pinned")
assert.equal(
  fixtures.reduce((count, fixture) => count + fixture.frozenCandidates, 0),
  11,
  "the frozen CRUD/session cohort contains exactly eleven candidates",
)
assert.equal(
  fixtures.reduce((count, fixture) => count + fixture.fields.length, 0),
  10,
  "exactly ten compatible shells are migrated in this cohort",
)
assert.equal(
  fixtures.reduce((count, fixture) => count + fixture.skippedCandidates, 0),
  1,
  "exactly one incompatible candidate stays manual",
)

let compiledSfcCount = 0
let importCount = 0
let frameCount = 0

for (const fixture of fixtures) {
  const componentPath = resolve(vueDirectory, fixture.filename)
  const source = await readFile(componentPath, "utf8")
  const baseSource = execFileSync("git", ["show", `${baseIdentity}:${fixture.repositoryPath}`], {
    cwd: repositoryDirectory,
    encoding: "utf8",
  })

  assert.equal(digest(baseSource), fixture.headSha256, `${fixture.filename} base hash is frozen`)
  assert.equal(
    occurrences(source, cadenceFieldImport),
    1,
    `${fixture.filename} imports the real CadenceField resolver exactly once`,
  )
  assert.equal(
    source.match(/<CadenceField\b/g)?.length ?? 0,
    fixture.expectedFrames,
    `${fixture.filename} has its exact CadenceField opening-frame count`,
  )
  assert.equal(
    occurrences(source, "</CadenceField>"),
    fixture.expectedFrames,
    `${fixture.filename} has its exact CadenceField closing-frame count`,
  )
  assert.doesNotMatch(
    source,
    /<div class="fieldset(?: mb-3)?">\n[ \t]*<label :for="[^"]+">\n[ \t]*<span\b/,
    `${fixture.filename} has no residual eligible literal field shell`,
  )

  const loaded = await loadSfc(componentPath)
  assert.ok(
    loaded.component,
    `${fixture.filename} compiles with the actual local CadenceField SFC resolver`,
  )
  compiledSfcCount += 1

  let reconstructedSource = peelCadenceBreadcrumbs(
    peelCadenceDetailsFrames(
      source,
      fixture.filename === "CommsTransportNew.vue" ? 1 : 0,
      fixture.filename,
    ),
    fixture.filename,
  )
  if (fixture.fields.length > 0) {
    reconstructedSource = reconstructedSource.replace(cadenceFieldImport, "")
    for (const entry of fixture.fields) {
      reconstructedSource = reconstructField(reconstructedSource, entry, fixture.filename)
    }
  }

  assert.equal(
    reconstructedSource,
    baseSource,
    `${fixture.filename} reconstructs its immutable base source byte-for-byte`,
  )
  assert.equal(
    digest(reconstructedSource),
    fixture.headSha256,
    `${fixture.filename} reconstruction preserves its immutable base SHA-256`,
  )

  importCount += occurrences(source, cadenceFieldImport)
  frameCount += source.match(/<CadenceField\b/g)?.length ?? 0
}

assert.equal(compiledSfcCount, 5, "all five real owned SFCs compile")
assert.equal(importCount, 5, "the cohort has exactly five CadenceField imports")
assert.equal(frameCount, 17, "the cohort has exactly seventeen total CadenceField frames")

const transportSource = await readFile(resolve(vueDirectory, "CommsTransportNew.vue"), "utf8")
assert.match(
  transportSource,
  /<div class="fieldset mb-3">\n            <label :for="form\.fields\.transport_kind\.provider_managed_id">\n              <input\n                :id="form\.fields\.transport_kind\.provider_managed_id \?\? undefined"\n                :name="form\.fields\.transport_kind\.name"\n                type="hidden"/,
  "the no-span provider-managed hidden field stays in its manual literal shell",
)
assert.match(
  transportSource,
  /<div v-if="field\.type === 'checkbox'" class="fieldset mb-3">\n                  <label class="flex cursor-pointer items-start gap-3">\n                    <input type="hidden" :name="field\.name" value="false">\n                    <input[\s\S]*?type="checkbox"[\s\S]*?<\/label>\n                <\/div>/,
  "the checkbox hidden-false pair and its plain label stay manual",
)

const sessionSource = await readFile(resolve(vueDirectory, "UserSession.vue"), "utf8")
assert.equal(
  occurrences(
    sessionSource,
    '      <input type="hidden" :name="form.csrf.name" :value="form.csrf.value" hidden>',
  ),
  1,
  "the caller-owned CSRF hidden input stays outside CadenceField",
)

console.log("field_crud_session_migration_test passed")
