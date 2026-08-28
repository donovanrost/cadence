import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {integrationRequire} from "./reka_adapter_test_support.mjs"

assert.equal(process.versions.node, "24.16.0", "migration contracts use pinned Node 24.16.0")

const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueDirectory = resolve(testDirectory, "../vue")
const {parse} = integrationRequire("@vue/compiler-sfc")
const cadenceFieldImport = 'import CadenceField from "./ui/components/CadenceField.vue"\n'
const cadenceValidationMessageImport =
  'import CadenceValidationMessage from "./ui/components/CadenceValidationMessage.vue"\n'
const cadenceValidationMessageCounts = new Map([["OpsFleetPlanningPolicy.vue", 16]])
const cadencePanelImport = 'import CadencePanel from "./ui/components/CadencePanel.vue"\n'
const cadencePageHeaderFrameImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const cadencePageHeaderFrameOpen = '<CadencePageHeaderFrame variant="ops">'
const cadencePageHeaderFrameClose = "</CadencePageHeaderFrame>"
const cadenceTableFrameImport =
  'import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"\n'
const opsPageHeaderOpen =
  '<header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">'

const cadenceFieldsByFile = new Map([
  [
    "OpsFleetPlanningPolicy.vue",
    [
      {expression: "policy_form.fields.max_contacts", indent: 16},
      {expression: "policy_form.fields.max_estimated_cost_micros", indent: 16},
      {expression: "policy_form.fields.currency", indent: 16},
      {expression: "policy_form.fields.critical_contact_reserve", indent: 16},
      {expression: "policy_form.fields.automation_mode", indent: 16},
      {expression: "approval_form.reason", indent: 10},
      {expression: "grant_form.fields.service_identity_id", indent: 12},
      {expression: "grant_form.fields.maximum_horizon_hours", indent: 14},
      {expression: "grant_form.fields.maximum_contacts", indent: 14},
      {expression: "grant_form.fields.maximum_execution_concurrency", indent: 14},
      {expression: "grant_form.fields.valid_days", indent: 14},
      {expression: "grant_form.fields.approval_reason", indent: 12},
      {expression: "revocation_form.fields.automation_grant_id", indent: 12},
      {expression: "revocation_form.fields.reason", indent: 12}
    ]
  ]
])

const files = [
  {
    name: "OpsDataSources.vue",
    panels: 3,
    sha256: "43d992e51884e03f1dca0e87c726f9b3fcfae9b1e887ba8b4fe09565ad9b242a",
    rawVariants: ['          <aside class="space-y-4">'],
    migrations: [
      {
        componentOpen: `            <CadencePanel
              class="card bg-base-200 border border-base-300"
              header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
            >`,
        sectionOpen: '            <section class="card bg-base-200 border border-base-300">',
        slotOpen: "              <template #header>",
        headerOpen: `              <div
                class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
              >`,
        slotClose: "              </template>",
        headerClose: "              </div>",
        componentClose: "            </CadencePanel>",
        sectionClose: "            </section>",
      },
      {
        componentOpen: `            <CadencePanel
              class="card bg-base-200 border border-base-300"
              header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
            >`,
        sectionOpen: '            <section class="card bg-base-200 border border-base-300">',
        slotOpen: "              <template #header>",
        headerOpen: `              <div
                class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
              >`,
        slotClose: "              </template>",
        headerClose: "              </div>",
        componentClose: "            </CadencePanel>",
        sectionClose: "            </section>",
      },
      {
        componentOpen: `            <CadencePanel
              v-for="list in [
                page.activity.binding_events,
                page.activity.source_events,
                page.activity.health_events
              ]"
              :key="list.id"
              class="card bg-base-200 border border-base-300"
              header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
            >`,
        sectionOpen: `            <section
              v-for="list in [
                page.activity.binding_events,
                page.activity.source_events,
                page.activity.health_events
              ]"
              :key="list.id"
              class="card bg-base-200 border border-base-300"
            >`,
        slotOpen: "              <template #header>",
        headerOpen: `              <div
                class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
              >`,
        slotClose: "              </template>",
        headerClose: "              </div>",
        componentClose: "            </CadencePanel>",
        sectionClose: "            </section>",
      },
    ],
  },
  {
    name: "OpsFleetPlanning.vue",
    panels: 3,
    opsPageHeader: true,
    sha256: "807d7a9b33db0044832785fc03655737f9e8885ce56bbecf2d20705185294644",
    importText: `${cadencePanelImport}\n`,
    rawVariants: [
      `  <section :id="page.id" class="h-full overflow-y-auto bg-base-100">
    <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">`,
      '        <aside class="space-y-5">',
    ],
    migrations: [
      {
        componentOpen: `      <CadencePanel
        id="fleet-planning-control-strip"
        class="grid border border-base-300 bg-base-200/20 md:grid-cols-4"
        header-class="border-b border-base-300 px-4 py-4 last:border-b-0 md:border-b-0 md:border-r md:last:border-r-0"
      >`,
        sectionOpen: `      <section
        id="fleet-planning-control-strip"
        class="grid border border-base-300 bg-base-200/20 md:grid-cols-4"
      >`,
        slotOpen: `        <template
          v-for="metric in control_metrics"
          :id="metric.id"
          :key="metric.id"
          #header
        >`,
        headerOpen: `        <div
          v-for="metric in control_metrics"
          :id="metric.id"
          :key="metric.id"
          class="border-b border-base-300 px-4 py-4 last:border-b-0 md:border-b-0 md:border-r md:last:border-r-0"
        >`,
        slotClose: "        </template>",
        headerClose: "        </div>",
        componentClose: "      </CadencePanel>",
        sectionClose: "      </section>",
      },
      {
        componentOpen: `        <CadencePanel
          class="min-w-0 border border-base-300 bg-base-200/15"
          header-class="flex items-center justify-between border-b border-base-300 px-4 py-3"
        >`,
        sectionOpen: '        <section class="min-w-0 border border-base-300 bg-base-200/15">',
        slotOpen: "          <template #header>",
        headerOpen:
          '          <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">',
        slotClose: "          </template>",
        headerClose: "          </div>",
        componentClose: "        </CadencePanel>",
        sectionClose: "        </section>",
      },
      {
        componentOpen: `          <CadencePanel
            :id="journey.id"
            class="border border-base-300 bg-base-200/15"
            header-class="border-b border-base-300 px-4 py-3"
          >`,
        sectionOpen:
          '          <section :id="journey.id" class="border border-base-300 bg-base-200/15">',
        slotOpen: "            <template #header>",
        headerOpen: '            <div class="border-b border-base-300 px-4 py-3">',
        slotClose: "            </template>",
        headerClose: "            </div>",
        componentClose: "          </CadencePanel>",
        sectionClose: "          </section>",
      },
    ],
  },
  {
    name: "OpsFleetPlanningPolicy.vue",
    panels: 2,
    opsPageHeader: true,
    sha256: "3ce5cb561e6c1495fd263b18c2c932fc19d200432d2e529fdef6eec7a09db711",
    rawVariants: ['    <aside class="min-w-0 space-y-5">'],
    migrations: [
      {
        componentOpen: `      <CadencePanel
        :id="page.manifest.id"
        class="border border-base-300 bg-base-200/15"
        header-class="flex flex-wrap items-center justify-between gap-3 border-b border-base-300 px-4 py-3"
      >`,
        sectionOpen:
          '      <section :id="page.manifest.id" class="border border-base-300 bg-base-200/15">',
        slotOpen: "        <template #header>",
        headerOpen:
          '        <div class="flex flex-wrap items-center justify-between gap-3 border-b border-base-300 px-4 py-3">',
        slotClose: "        </template>",
        headerClose: "        </div>",
        componentClose: "      </CadencePanel>",
        sectionClose: "      </section>",
      },
      {
        componentOpen: `      <CadencePanel
        :id="grant_ledger.id"
        class="border border-base-300 bg-base-200/15"
        header-class="flex items-center justify-between border-b border-base-300 px-4 py-3"
      >`,
        sectionOpen:
          '      <section :id="grant_ledger.id" class="border border-base-300 bg-base-200/15">',
        slotOpen: "        <template #header>",
        headerOpen:
          '        <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">',
        slotClose: "        </template>",
        headerClose: "        </div>",
        componentClose: "      </CadencePanel>",
        sectionClose: "      </section>",
      },
    ],
  },
  {
    name: "SpacecraftList.vue",
    panels: 2,
    sha256: "b322bffd1e6082c1d7f18a942c3a5879e2751beceb2e3d0f41175d2a11e25669",
    rawVariants: [],
    migrations: [
      {
        componentOpen: `    <CadencePanel
      id="spacecraft-vehicles-card"
      class="card border border-base-300 bg-base-200"
      header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
    >`,
        sectionOpen:
          '    <section id="spacecraft-vehicles-card" class="card border border-base-300 bg-base-200">',
        slotOpen: "      <template #header>",
        headerOpen:
          '      <div class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3">',
        slotClose: "      </template>",
        headerClose: "      </div>",
        componentClose: "    </CadencePanel>",
        sectionClose: "    </section>",
      },
      {
        componentOpen: `    <CadencePanel
      id="spacecraft-profiles-card"
      class="card border border-base-300 bg-base-200"
      header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
    >`,
        sectionOpen:
          '    <section id="spacecraft-profiles-card" class="card border border-base-300 bg-base-200">',
        slotOpen: "      <template #header>",
        headerOpen:
          '      <div class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3">',
        slotClose: "      </template>",
        headerClose: "      </div>",
        componentClose: "    </CadencePanel>",
        sectionClose: "    </section>",
      },
    ],
  },
]

const countExact = (source, value) => source.split(value).length - 1

const replaceOnce = (source, before, after, label) => {
  assert.ok(source.includes(before), `${label} exists exactly where reconstruction expects it`)
  return source.replace(before, after)
}

const peelCadenceValidationMessages = (source, name) => {
  const expectedMessages = cadenceValidationMessageCounts.get(name) ?? 0
  const expectedImports = expectedMessages > 0 ? 1 : 0

  assert.equal(
    countExact(source, cadenceValidationMessageImport),
    expectedImports,
    `${name} has its expected CadenceValidationMessage import count before peeling`,
  )
  assert.equal(
    countExact(source, "<CadenceValidationMessage"),
    expectedMessages,
    `${name} has its expected CadenceValidationMessage opening count before peeling`,
  )
  assert.equal(
    countExact(source, "</CadenceValidationMessage>"),
    expectedMessages,
    `${name} has its expected CadenceValidationMessage closing count before peeling`,
  )

  let replacements = 0
  const predecessorCompatibleSource = source
    .replace(cadenceValidationMessageImport, "")
    .replace(
      /<CadenceValidationMessage(\s+v-for="error in [^"]+\.errors"\s+:key="error"\s*)>/g,
      (_, attributes) => {
        replacements += 1

        if (!attributes.includes("\n")) {
          return `<p${attributes} class="mt-1.5 text-sm text-error">`
        }

        const closingNewline = attributes.lastIndexOf("\n")
        const beforeClosingIndent = attributes.slice(0, closingNewline)
        const closingIndent = attributes.slice(closingNewline + 1)
        const previousNewline = beforeClosingIndent.lastIndexOf("\n")
        const attributeIndent = beforeClosingIndent.slice(previousNewline + 1).match(/^ */)[0]

        return `<p${beforeClosingIndent}\n${attributeIndent}class="mt-1.5 text-sm text-error"\n${closingIndent}>`
      },
    )
    .replaceAll("</CadenceValidationMessage>", "</p>")

  assert.equal(replacements, expectedMessages, `${name} peels every validation message`)
  assert.equal(
    countExact(predecessorCompatibleSource, "CadenceValidationMessage"),
    0,
    `${name} predecessor source has no residual CadenceValidationMessage`,
  )

  return predecessorCompatibleSource
}

const peelCadenceFields = (source, name) => {
  const fields = cadenceFieldsByFile.get(name) ?? []
  const expectedImportCount = fields.length > 0 ? 1 : 0

  assert.equal(
    countExact(source, cadenceFieldImport),
    expectedImportCount,
    `${name} has its expected CadenceField import count before peeling`,
  )
  assert.equal(
    countExact(source, "<CadenceField\n"),
    fields.length,
    `${name} has its exact CadenceField opening count before peeling`,
  )
  assert.equal(
    countExact(source, "</CadenceField>"),
    fields.length,
    `${name} has its exact CadenceField closing count before peeling`,
  )

  let predecessorCompatibleSource = source.replace(cadenceFieldImport, "")

  for (const field of fields) {
    const spaces = " ".repeat(field.indent)
    const migratedOpening = `${spaces}<CadenceField
${spaces}  :control-id="${field.expression}.id"
${spaces}  wrapper-class="fieldset mb-3"
${spaces}  :label="${field.expression}.label"
${spaces}  label-class="hud-label block mb-1.5"
${spaces}>`
    const migratedClosing = `\n${spaces}</CadenceField>`

    assert.equal(
      countExact(predecessorCompatibleSource, migratedOpening),
      1,
      `${name}: ${field.expression} has one exact CadenceField opening`,
    )

    const start = predecessorCompatibleSource.indexOf(migratedOpening)
    const closeStart = predecessorCompatibleSource.indexOf(
      migratedClosing,
      start + migratedOpening.length,
    )
    assert.notEqual(
      closeStart,
      -1,
      `${name}: ${field.expression} has one exact CadenceField closing`,
    )

    let controls = predecessorCompatibleSource.slice(
      start + migratedOpening.length,
      closeStart,
    )
    const errorsOpen = `\n${spaces}  <template #errors>`
    const errorsClose = `\n${spaces}  </template>`
    const errorsStart = controls.lastIndexOf(errorsOpen)

    assert.notEqual(
      errorsStart,
      -1,
      `${name}: ${field.expression} keeps its exact error slot`,
    )
    assert.ok(
      controls.endsWith(errorsClose),
      `${name}: ${field.expression} error slot closes last`,
    )

    const errors = controls
      .slice(errorsStart + errorsOpen.length, -errorsClose.length)
      .replaceAll(`\n${spaces}    `, `\n${spaces}  `)
    controls = controls.slice(0, errorsStart)

    const shiftedControls = controls.replaceAll(`\n${spaces}  `, `\n${spaces}    `)
    const original = `${spaces}<div class="fieldset mb-3">
${spaces}  <label :for="${field.expression}.id">
${spaces}    <span class="hud-label block mb-1.5">{{ ${field.expression}.label }}</span>${shiftedControls}
${spaces}  </label>${errors}
${spaces}</div>`

    predecessorCompatibleSource =
      predecessorCompatibleSource.slice(0, start) +
      original +
      predecessorCompatibleSource.slice(closeStart + migratedClosing.length)
  }

  assert.equal(
    countExact(predecessorCompatibleSource, "CadenceField"),
    0,
    `${name} predecessor source has no residual CadenceField`,
  )

  return predecessorCompatibleSource
}

const peelTableFrames = (source, name) => {
  const boundaries =
    name === "SpacecraftList.vue"
      ? [
          {
            componentOpen: '          <CadenceTableFrame id="spacecraft-vehicles-table">',
            tableOpen: '          <table id="spacecraft-vehicles-table" class="table">',
          },
          {
            componentOpen:
              '          <CadenceTableFrame id="spacecraft-profiles-preview-table">',
            tableOpen:
              '          <table id="spacecraft-profiles-preview-table" class="table">',
          },
        ]
      : []
  const importCount = boundaries.length > 0 ? 1 : 0

  assert.equal(
    countExact(source, cadenceTableFrameImport),
    importCount,
    `${name} has its expected CadenceTableFrame import count before peeling`,
  )
  assert.equal(
    countExact(source, "<CadenceTableFrame"),
    boundaries.length,
    `${name} has its expected CadenceTableFrame opening count before peeling`,
  )
  assert.equal(
    countExact(source, "</CadenceTableFrame>"),
    boundaries.length,
    `${name} has its expected CadenceTableFrame closing count before peeling`,
  )

  let predecessorCompatibleSource = source.replace(cadenceTableFrameImport, "")

  for (const [index, boundary] of boundaries.entries()) {
    predecessorCompatibleSource = replaceOnce(
      predecessorCompatibleSource,
      boundary.componentOpen,
      boundary.tableOpen,
      `${name} table frame ${index + 1} opening boundary`,
    )
  }

  predecessorCompatibleSource = predecessorCompatibleSource.replaceAll(
    "</CadenceTableFrame>",
    "</table>",
  )
  assert.equal(
    countExact(predecessorCompatibleSource, "CadenceTableFrame"),
    0,
    `${name} predecessor source has no residual CadenceTableFrame`,
  )

  return predecessorCompatibleSource
}

const peelPageHeaderFrame = (source, name) => {
  assert.equal(countExact(source, cadencePageHeaderFrameImport), 1, `${name} page header import count`)
  assert.equal(countExact(source, cadencePageHeaderFrameOpen), 1, `${name} page header open count`)
  assert.equal(countExact(source, cadencePageHeaderFrameClose), 1, `${name} page header close count`)

  const predecessorCompatibleSource = source
    .replace(cadencePageHeaderFrameImport, "")
    .replace(cadencePageHeaderFrameOpen, opsPageHeaderOpen)
    .replace(cadencePageHeaderFrameClose, "</header>")

  assert.equal(
    countExact(predecessorCompatibleSource, "CadencePageHeaderFrame"),
    0,
    `${name} predecessor source has no residual CadencePageHeaderFrame`
  )

  return predecessorCompatibleSource
}

const replaceOnceAfter = (source, before, after, start, label) => {
  const index = source.indexOf(before, start)
  assert.notEqual(index, -1, `${label} exists after its panel opening`)

  return {
    source: source.slice(0, index) + after + source.slice(index + before.length),
    next: index + after.length,
  }
}

assert.equal(files.reduce((total, file) => total + file.panels, 0), 10)

for (const file of files) {
  const filename = resolve(vueDirectory, file.name)
  const source = await readFile(filename, "utf8")
  const parsed = parse(source, {filename})

  assert.deepEqual(parsed.errors, [], `${file.name} parses with the pinned Vue compiler`)
  assert.equal(countExact(source, cadencePanelImport), 1, `${file.name} has one exact import`)
  assert.equal(countExact(source, "<CadencePanel"), file.panels, `${file.name} open count`)
  assert.equal(countExact(source, "</CadencePanel>"), file.panels, `${file.name} close count`)
  assert.equal(countExact(source, "header-class="), file.panels, `${file.name} header-class count`)
  assert.equal(countExact(source, "#header"), file.panels, `${file.name} header slot count`)
  assert.equal(file.migrations.length, file.panels, `${file.name} frozen migration ledger count`)

  const fieldCompatibleSource = peelCadenceFields(
    peelCadenceValidationMessages(source, file.name),
    file.name,
  )
  const predecessorCompatibleSource = peelTableFrames(
    file.opsPageHeader ? peelPageHeaderFrame(fieldCompatibleSource, file.name) : fieldCompatibleSource,
    file.name,
  )

  for (const rawVariant of file.rawVariants) {
    assert.equal(
      countExact(predecessorCompatibleSource, rawVariant),
      1,
      `${file.name} keeps raw variant exactly once`
    )
  }

  let reconstructed = replaceOnce(
    predecessorCompatibleSource,
    file.importText ?? cadencePanelImport,
    "",
    `${file.name} CadencePanel import`,
  )

  for (const [index, migration] of file.migrations.entries()) {
    const label = `${file.name} panel ${index + 1}`
    let replacement = replaceOnceAfter(
      reconstructed,
      migration.componentOpen,
      migration.sectionOpen,
      0,
      `${label} opening boundary`,
    )
    reconstructed = replacement.source
    replacement = replaceOnceAfter(
      reconstructed,
      migration.slotOpen,
      migration.headerOpen,
      replacement.next,
      `${label} header opening boundary`,
    )
    reconstructed = replacement.source
    replacement = replaceOnceAfter(
      reconstructed,
      migration.slotClose,
      migration.headerClose,
      replacement.next,
      `${label} header closing boundary`,
    )
    reconstructed = replacement.source
    replacement = replaceOnceAfter(
      reconstructed,
      migration.componentClose,
      migration.sectionClose,
      replacement.next,
      `${label} closing boundary`,
    )
    reconstructed = replacement.source
  }

  assert.doesNotMatch(reconstructed, /CadencePanel/, `${file.name} reconstruction has no CadencePanel`)
  assert.equal(
    createHash("sha256").update(reconstructed).digest("hex"),
    file.sha256,
    `${file.name} reconstructs the frozen base byte-for-byte`,
  )
}

console.log("panel_ops_fleet_migration_test passed (10 exact panels across 4 SFCs)")
