import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  expectedNodeVersion,
  installDom,
  loadSfc,
} from "./reka_adapter_test_support.mjs"
import {
  opsViewportCallerNames,
  peelCadenceOpsViewport,
} from "./ops_viewport_test_support.mjs"
import {
  opsAuthorHeaderCallerNames,
  peelCadenceOpsAuthorHeader,
} from "./page_header_ops_author_test_support.mjs"
import {
  conditionalKeyedCadenceFieldCounts,
  peelConditionalKeyedCadenceFields,
} from "./conditional_keyed_field_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `dashboard/data CadenceField contracts use pinned Node ${expectedNodeVersion}`,
)

const migrationBase = "7643e25b78faf8bf09d7bc3497de88db3b46715a"
const componentImport = 'import CadenceField from "./ui/components/CadenceField.vue"'
const cadenceDetailsFrameImport =
  'import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"\n'
const cadenceCollapsibleImports = [
  'import CadenceCollapsible from "./ui/reka/CadenceCollapsible.vue"',
  'import CadenceCollapsibleContent from "./ui/reka/CadenceCollapsibleContent.vue"',
  'import CadenceCollapsibleTrigger from "./ui/reka/CadenceCollapsibleTrigger.vue"',
].join("\n") + "\n"
const disclosureSeedHelper = [
  "const disclosureSeedEpoch = (details: ProgressiveDetails) =>",
  '  `${details.id}:${details.open ? "open" : "closed"}`',
  "",
  "",
].join("\n")
const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueDirectory = resolve(testDirectory, "../vue")
const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const occurrences = (source, fragment) => source.split(fragment).length - 1
const disclosure = (form, openingSha256) => ({
  form,
  openingSha256,
  nativeOpening: [
    "<details",
    `          :id="${form}.details.id"`,
    `          :open="${form}.details.open"`,
    '          class="border border-base-300 bg-base-200/20 p-4"',
    "        >",
  ].join("\n"),
})
const dashboardLibraryDisclosures = Object.freeze([
  disclosure("create_form", "3c98a4d0cee5edea1d8f05eed91388a37c7228e28ba4302b8fe55ee3f1eb3104"),
  disclosure("version_form", "a17681f34775420252d7c0ec017c416311f646011bd37abafed1837ab7840bb7"),
])
const peelCadenceCollapsibles = (source, label) => {
  assert.equal(occurrences(source, cadenceCollapsibleImports), 1, `${label} collapsible imports`)
  assert.equal(occurrences(source, disclosureSeedHelper), 1, `${label} seed helper`)
  assert.equal(
    occurrences(source, "<CadenceCollapsible\n"),
    dashboardLibraryDisclosures.length,
    `${label} collapsible opening count`,
  )
  assert.equal(
    occurrences(source, "        </CadenceCollapsible>"),
    dashboardLibraryDisclosures.length,
    `${label} collapsible closing count`,
  )

  let peeled = source
  for (const boundary of dashboardLibraryDisclosures) {
    const migratedOpening = `        <CadenceCollapsible
          :content-id="${boundary.form}.id"
          :open="${boundary.form}.details.open"
          client-seeded
          :seed-epoch="disclosureSeedEpoch(${boundary.form}.details)"
          :unmount-on-hide="false"
        >
          <div
            :id="${boundary.form}.details.id"
            class="border border-base-300 bg-base-200/20 p-4"
          >
            <CadenceCollapsibleTrigger>
              <button
                :id="${boundary.form}.details.summary_id"
                type="button"
                class="cursor-pointer font-semibold"
              >{{ ${boundary.form}.details.summary }}</button>
            </CadenceCollapsibleTrigger>

            <CadenceCollapsibleContent>`
    const migratedClosing = `            </CadenceCollapsibleContent>
          </div>
        </CadenceCollapsible>`
    const nativeSummary = `          <summary
            :id="${boundary.form}.details.summary_id"
            class="cursor-pointer font-semibold"
          >{{ ${boundary.form}.details.summary }}</summary>`

    assert.equal(
      sha256(boundary.nativeOpening),
      boundary.openingSha256,
      `${label} preserves the retired ${boundary.form} opening-tag SHA-256`,
    )
    assert.equal(occurrences(peeled, migratedOpening), 1, `${label} ${boundary.form} opening`)

    const openingIndex = peeled.indexOf(migratedOpening)
    const contentStart = openingIndex + migratedOpening.length + 1
    const closingIndex = peeled.indexOf(migratedClosing, contentStart)
    assert.notEqual(closingIndex, -1, `${label} ${boundary.form} closing`)
    const callerForm = peeled.slice(contentStart, closingIndex)
    const nativeDisclosure =
      `        ${boundary.nativeOpening}\n` +
      `${nativeSummary}\n\n` +
      callerForm +
      "        </details>"

    peeled =
      peeled.slice(0, openingIndex) +
      nativeDisclosure +
      peeled.slice(closingIndex + migratedClosing.length)
  }

  peeled = peeled
    .replace(cadenceCollapsibleImports, "")
    .replace(disclosureSeedHelper, "")

  assert.doesNotMatch(peeled, /CadenceCollapsible|disclosureSeedEpoch/)
  return peeled
}
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
const shiftIndent = (source, spaces) =>
  source
    .split("\n")
    .map((line) => `${" ".repeat(spaces)}${line}`)
    .join("\n")

const field = (expression, indent, multilineLabel = false) => ({
  expression,
  indent,
  multilineLabel,
})

const components = Object.freeze([
  {
    file: "OpsDashboardLibrary.vue",
    sha256: "7e12954bd4c849f927d533be615822b4445a173dfd051987595cdb4bca69656a",
    fields: [
      field("stage_form.fields.dashboard_id", 10, true),
      field("stage_form.fields.item_id", 10),
      field("stage_form.fields.version", 10),
      field("create_form.fields.name", 12),
      field("create_form.fields.description", 12, true),
      field("create_form.fields.change_summary", 12, true),
      field("create_form.fields.widget_json", 12, true),
      field("version_form.fields.item_id", 12),
      field("version_form.fields.change_summary", 12, true),
      field("version_form.fields.widget_json", 12, true),
    ],
  },
  {
    file: "OpsDashboardSettings.vue",
    sha256: "ebe6c13a079a87c673a02d2e682cb5501b1323525608d37df72c2207439a1f60",
    fields: [
      field("settings_form.fields.name", 10),
      field("settings_form.fields.description", 10, true),
      field("settings_form.fields.tags", 10),
      field("settings_form.fields.defaults_json", 10, true),
      field("share_form.fields.data_visibility", 12, true),
      field("share_form.fields.expires_in_hours", 12, true),
      field("snapshot_form.fields.data_visibility", 12, true),
    ],
  },
  {
    file: "OpsDashboardNew.vue",
    sha256: "d2022be7b608d52fbbdc9c853601c6e9798ef009cb181fd55776598b4666440a",
    fields: [field("form.name", 8), field("form.description", 8)],
  },
])

const reconstructField = (source, {expression, indent, multilineLabel}, file) => {
  const spaces = " ".repeat(indent)
  const migratedOpen = `${spaces}<CadenceField
${spaces}  :control-id="${expression}.id"
${spaces}  wrapper-class="fieldset mb-3"
${spaces}  :label="${expression}.label"
${spaces}  label-class="hud-label block mb-1.5"
${spaces}>`
  const migratedClose = `\n${spaces}</CadenceField>`

  assert.equal(
    occurrences(source, migratedOpen),
    1,
    `${file}: ${expression} has one exact CadenceField opening`,
  )

  const start = source.indexOf(migratedOpen)
  const controlStart = start + migratedOpen.length + 1
  const closeStart = source.indexOf(migratedClose, controlStart)
  assert.notEqual(closeStart, -1, `${file}: ${expression} has one CadenceField closing`)

  const control = source.slice(controlStart, closeStart)
  assert.match(
    control,
    new RegExp(`^${spaces}  <(?:input|select|textarea)\\b`),
    `${file}: ${expression} keeps its native control in the caller slot`,
  )

  const label = multilineLabel
    ? `${spaces}    <span class="hud-label block mb-1.5">
${spaces}      {{ ${expression}.label }}
${spaces}    </span>`
    : `${spaces}    <span class="hud-label block mb-1.5">{{ ${expression}.label }}</span>`
  const original = `${spaces}<div class="fieldset mb-3">
${spaces}  <label :for="${expression}.id">
${label}
${shiftIndent(control, 2)}
${spaces}  </label>
${spaces}</div>`

  return (
    source.slice(0, start) +
    original +
    source.slice(closeStart + migratedClose.length)
  )
}

const dom = installDom('<div id="dashboard-data-field-contract"></div>')
const loadedComponents = await Promise.all(
  components.map(async (component) => {
    const path = resolve(vueDirectory, component.file)
    const [source, loaded] = await Promise.all([readFile(path, "utf8"), loadSfc(path)])
    return {...component, source, loaded}
  }),
)

let totalFields = 0
for (const component of loadedComponents) {
  const {file, fields, loaded, source} = component
  const currentFrames = fields.length + (conditionalKeyedCadenceFieldCounts[file] ?? 0)
  assert.ok(loaded.component, `${file} compiles through the real local SFC resolver`)
  assert.ok(loaded.descriptor.scriptSetup, `${file} keeps its setup script`)
  assert.ok(loaded.descriptor.template, `${file} keeps its real template`)
  assert.equal(loaded.source, source, `${file} compiles the exact audited source`)
  assert.equal(occurrences(source, componentImport), 1, `${file} has one CadenceField import`)
  assert.equal(
    occurrences(source, "<CadenceField\n"),
    currentFrames,
    `${file} has its exact frozen CadenceField frame count`,
  )
  assert.equal(
    occurrences(source, 'wrapper-class="fieldset mb-3"'),
    currentFrames,
    `${file} sends the exact frozen wrapper class to every frame`,
  )
  assert.doesNotMatch(
    source,
    /^\s*<div class="fieldset(?: mb-3)?">\n\s*<label :for=/m,
    `${file} has no residual eligible literal field shell`,
  )

  let reconstructed = peelConditionalKeyedCadenceFields(source, file)
  reconstructed = opsAuthorHeaderCallerNames.includes(file)
    ? peelCadenceOpsAuthorHeader(reconstructed, file)
    : reconstructed
  reconstructed = opsViewportCallerNames.includes(file)
    ? peelCadenceOpsViewport(reconstructed, file)
    : reconstructed
  if (file === "OpsDashboardLibrary.vue") {
    reconstructed = peelCadenceCollapsibles(reconstructed, file)
  }
  reconstructed = peelCadenceDetailsFrames(
    reconstructed,
    file === "OpsDashboardLibrary.vue" ? 1 : 0,
    file,
  ).replace(`${componentImport}\n`, "")
  for (const migratedField of fields) {
    reconstructed = reconstructField(reconstructed, migratedField, file)
  }

  assert.equal(
    occurrences(reconstructed, "CadenceField"),
    0,
    `${file} reconstruction removes only the field migration`,
  )
  assert.equal(
    sha256(reconstructed),
    component.sha256,
    `${file} reconstructs ${migrationBase} byte-for-byte with unchanged SHA-256`,
  )
  totalFields += fields.length
}

assert.equal(totalFields, 19, "the frozen DASHBOARD cohort contains exactly 19 fields")

const dashboardNewSource = loadedComponents.find(
  ({file}) => file === "OpsDashboardNew.vue",
).source
const dashboardNewPredecessorSource = peelConditionalKeyedCadenceFields(
  dashboardNewSource,
  "OpsDashboardNew.vue",
)
assert.equal(
  occurrences(
    dashboardNewPredecessorSource,
    '<div v-if="form.document_json !== null" class="fieldset mb-3">',
  ),
  1,
  "the frozen conditional dashboard document exclusion reconstructs exactly",
)
assert.match(
  dashboardNewPredecessorSource,
  /<div v-if="form\.document_json !== null" class="fieldset mb-3">\n\s*<label :for="form\.document_json\.id">[\s\S]*?<textarea[\s\S]*?v-model="dashboard\.document_json"/,
  "the excluded conditional textarea and its reconciliation remain exact after the newest peel",
)

dom.window.close()
console.log("field_dashboard_data_migration_test passed")
