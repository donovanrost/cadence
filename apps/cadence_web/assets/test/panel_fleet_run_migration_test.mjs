import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

import {peelCadenceOpsViewport} from "./ops_viewport_test_support.mjs"
import {integrationRequire} from "./reka_adapter_test_support.mjs"

assert.equal(process.version, "v24.16.0", "run with pinned Node 24.16.0")

const testDirectory = dirname(fileURLToPath(import.meta.url))
const relativePath = "../vue/OpsFleetPlanningRun.vue"
const filename = resolve(testDirectory, relativePath)
const source = await readFile(filename, "utf8")
const {parse} = integrationRequire("@vue/compiler-sfc")

const count = (value, needle) => value.split(needle).length - 1

const replaceExactlyOnce = (value, before, after, label) => {
  assert.equal(count(value, before), 1, `${label}: expected exactly one source boundary`)
  return value.replace(before, after)
}

const replaceAt = (value, start, before, after, label) => {
  const index = value.indexOf(before, start)
  assert.notEqual(index, -1, `${label}: missing ${before}`)
  return value.slice(0, index) + after + value.slice(index + before.length)
}

const importLine = 'import CadencePanel from "./ui/components/CadencePanel.vue"\n'
const cadenceFieldImport = 'import CadenceField from "./ui/components/CadenceField.vue"\n'
const cadenceDetailsFrameImport =
  'import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"\n'
const cadencePageHeaderFrameImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const cadencePageHeaderFrameOpen = '<CadencePageHeaderFrame variant="ops">'
const cadencePageHeaderFrameClose = "</CadencePageHeaderFrame>"
const opsPageHeaderOpen =
  '<header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">'

const cadenceFields = [
  {expression: "repair_form.fields.horizon_start", indent: 14},
  {expression: "repair_form.fields.horizon_end", indent: 14}
]

const peelCadenceDetailsFrames = (value) => {
  assert.equal(count(value, cadenceDetailsFrameImport), 1, `${relativePath}: details import count`)
  assert.equal(count(value, "<CadenceDetailsFrame"), 1, `${relativePath}: details opening count`)
  assert.equal(count(value, "</CadenceDetailsFrame>"), 1, `${relativePath}: details closing count`)

  const peeled = value
    .replace(cadenceDetailsFrameImport, "")
    .replace("<CadenceDetailsFrame", "<details")
    .replace("</CadenceDetailsFrame>", "</details>")

  assert.doesNotMatch(peeled, /CadenceDetailsFrame/)
  return peeled
}

const peelCadenceFields = value => {
  assert.equal(count(value, cadenceFieldImport), 1, `${relativePath}: CadenceField import count`)
  assert.equal(count(value, "<CadenceField\n"), 2, `${relativePath}: CadenceField open count`)
  assert.equal(count(value, "</CadenceField>"), 2, `${relativePath}: CadenceField close count`)

  let predecessorCompatibleSource = value.replace(cadenceFieldImport, "")

  for (const field of cadenceFields) {
    const spaces = " ".repeat(field.indent)
    const migratedOpening = `${spaces}<CadenceField
${spaces}  :control-id="${field.expression}.id"
${spaces}  wrapper-class="fieldset mb-3"
${spaces}  :label="${field.expression}.label"
${spaces}  label-class="hud-label block mb-1.5"
${spaces}>`
    const migratedClosing = `\n${spaces}</CadenceField>`

    assert.equal(
      count(predecessorCompatibleSource, migratedOpening),
      1,
      `${relativePath}: ${field.expression} exact CadenceField opening`
    )

    const start = predecessorCompatibleSource.indexOf(migratedOpening)
    const closeStart = predecessorCompatibleSource.indexOf(
      migratedClosing,
      start + migratedOpening.length
    )
    assert.notEqual(
      closeStart,
      -1,
      `${relativePath}: ${field.expression} exact CadenceField closing`
    )

    const controls = predecessorCompatibleSource
      .slice(start + migratedOpening.length, closeStart)
      .replaceAll(`\n${spaces}  `, `\n${spaces}    `)
    const original = `${spaces}<div class="fieldset mb-3">
${spaces}  <label :for="${field.expression}.id">
${spaces}    <span class="hud-label block mb-1.5">
${spaces}      {{ ${field.expression}.label }}
${spaces}    </span>${controls}
${spaces}  </label>
${spaces}</div>`

    predecessorCompatibleSource =
      predecessorCompatibleSource.slice(0, start) +
      original +
      predecessorCompatibleSource.slice(closeStart + migratedClosing.length)
  }

  assert.equal(
    count(predecessorCompatibleSource, "CadenceField"),
    0,
    `${relativePath}: predecessor source has no residual CadenceField`
  )

  return predecessorCompatibleSource
}

const peelPageHeaderFrame = (value) => {
  assert.equal(count(value, cadencePageHeaderFrameImport), 1, `${relativePath}: page header import count`)
  assert.equal(count(value, cadencePageHeaderFrameOpen), 1, `${relativePath}: page header open count`)
  assert.equal(count(value, cadencePageHeaderFrameClose), 1, `${relativePath}: page header close count`)

  const predecessorCompatibleSource = value
    .replace(cadencePageHeaderFrameImport, "")
    .replace(cadencePageHeaderFrameOpen, opsPageHeaderOpen)
    .replace(cadencePageHeaderFrameClose, "</header>")

  assert.equal(
    count(predecessorCompatibleSource, "CadencePageHeaderFrame"),
    0,
    `${relativePath}: predecessor source has no residual CadencePageHeaderFrame`
  )

  return predecessorCompatibleSource
}

const panels = [
  {
    label: "horizon",
    indent: "      ",
    headerClass:
      "grid gap-3 border-b border-base-300 px-4 py-3 md:grid-cols-[1fr_auto] md:items-end",
    migratedOpen:
      '      <CadencePanel :id="page.horizon.id" class="border border-base-300 bg-base-200/15" header-class="grid gap-3 border-b border-base-300 px-4 py-3 md:grid-cols-[1fr_auto] md:items-end">',
    baseOpen:
      '      <section :id="page.horizon.id" class="border border-base-300 bg-base-200/15">'
  },
  {
    label: "coverage",
    indent: "          ",
    headerClass:
      "grid grid-cols-[minmax(12rem,1fr)_7rem_7rem_8rem] border-b border-base-300 px-4 py-2 font-mono text-[0.58rem] uppercase tracking-wider text-base-content/45",
    migratedOpen:
      '          <CadencePanel :id="page.coverage.id" class="border border-base-300 bg-base-200/15" header-class="grid grid-cols-[minmax(12rem,1fr)_7rem_7rem_8rem] border-b border-base-300 px-4 py-2 font-mono text-[0.58rem] uppercase tracking-wider text-base-content/45">',
    baseOpen:
      '          <section :id="page.coverage.id" class="border border-base-300 bg-base-200/15">'
  },
  {
    label: "decision inspector",
    indent: "          ",
    headerClass: "flex items-end justify-between border-b border-base-300 px-4 py-3",
    migratedOpen: `          <CadencePanel
            :id="page.decision_inspector.id"
            class="border border-base-300 bg-base-200/15"
            header-class="flex items-end justify-between border-b border-base-300 px-4 py-3"
          >`,
    baseOpen: `          <section
            :id="page.decision_inspector.id"
            class="border border-base-300 bg-base-200/15"
          >`
  },
  {
    label: "exception queue",
    indent: "          ",
    headerClass: "border-b border-warning/25 px-4 py-3",
    migratedOpen: `          <CadencePanel
            v-if="page.exception_queue.visible"
            :id="page.exception_queue.id"
            class="border border-warning/35 bg-warning/[0.035]"
            header-class="border-b border-warning/25 px-4 py-3"
          >`,
    baseOpen: `          <section
            v-if="page.exception_queue.visible"
            :id="page.exception_queue.id"
            class="border border-warning/35 bg-warning/[0.035]"
          >`
  },
  {
    label: "resource pressure",
    indent: "          ",
    headerClass: "border-b border-base-300 px-4 py-3",
    migratedOpen: `          <CadencePanel
            :id="page.resource_pressure.id"
            class="border border-base-300 bg-base-200/15"
            header-class="border-b border-base-300 px-4 py-3"
          >`,
    baseOpen: `          <section
            :id="page.resource_pressure.id"
            class="border border-base-300 bg-base-200/15"
          >`
  },
  {
    label: "automation",
    indent: "          ",
    headerClass: "border-b border-base-300 px-4 py-3",
    migratedOpen: `          <CadencePanel
            v-if="page.automation.visible"
            class="border border-base-300 bg-base-200/15"
            header-class="border-b border-base-300 px-4 py-3"
          >`,
    baseOpen: `          <section
            v-if="page.automation.visible"
            class="border border-base-300 bg-base-200/15"
          >`
  }
]

const expectedHeaderClassCounts = new Map([
  [
    "grid gap-3 border-b border-base-300 px-4 py-3 md:grid-cols-[1fr_auto] md:items-end",
    1
  ],
  [
    "grid grid-cols-[minmax(12rem,1fr)_7rem_7rem_8rem] border-b border-base-300 px-4 py-2 font-mono text-[0.58rem] uppercase tracking-wider text-base-content/45",
    1
  ],
  ["flex items-end justify-between border-b border-base-300 px-4 py-3", 1],
  ["border-b border-warning/25 px-4 py-3", 1],
  ["border-b border-base-300 px-4 py-3", 2]
])

assert.equal(count(source, importLine), 1, `${relativePath}: CadencePanel import count`)
assert.equal(count(source, "<CadencePanel"), 6, `${relativePath}: CadencePanel open count`)
assert.equal(count(source, "</CadencePanel>"), 6, `${relativePath}: CadencePanel close count`)
assert.equal(count(source, "<template #header>"), 6, `${relativePath}: header slot count`)
assert.equal(count(source, "header-class="), 6, `${relativePath}: header-class count`)

for (const [headerClass, expectedCount] of expectedHeaderClassCounts) {
  assert.equal(
    count(source, `header-class="${headerClass}"`),
    expectedCount,
    `${relativePath}: ${headerClass}`
  )
}

const rawSectionHeader = `  <section
    :id="page.id"
    :aria-busy="planning"
    class="h-full overflow-y-auto bg-base-100"
  >
    <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">`

const predecessorCompatibleSource = peelPageHeaderFrame(
  peelCadenceFields(
    peelCadenceDetailsFrames(peelCadenceOpsViewport(source, "OpsFleetPlanningRun.vue")),
  ),
)

assert.equal(
  count(predecessorCompatibleSource, rawSectionHeader),
  1,
  `${relativePath}: raw section > header variant`
)
assert.equal(
  count(predecessorCompatibleSource, '        <aside class="min-w-0 space-y-5">'),
  1,
  `${relativePath}: raw aside root`
)

const {descriptor, errors} = parse(source, {filename})
assert.equal(errors.length, 0, `${relativePath}: Vue compiler errors: ${errors.join("\n")}`)
assert.ok(descriptor.template, `${relativePath}: missing template block`)

let reconstructed = predecessorCompatibleSource

for (const panel of panels) {
  const migratedPrefix = `${panel.migratedOpen}\n${panel.indent}  <template #header>\n`
  const basePrefix = `${panel.baseOpen}\n${panel.indent}  <div class="${panel.headerClass}">\n`

  reconstructed = replaceExactlyOnce(
    reconstructed,
    migratedPrefix,
    basePrefix,
    `${relativePath}: ${panel.label} opening`
  )

  const panelStart = reconstructed.indexOf(panel.baseOpen)
  reconstructed = replaceAt(
    reconstructed,
    panelStart + panel.baseOpen.length,
    `${panel.indent}  </template>`,
    `${panel.indent}  </div>`,
    `${relativePath}: ${panel.label} header closing`
  )
  reconstructed = replaceAt(
    reconstructed,
    panelStart + panel.baseOpen.length,
    `${panel.indent}</CadencePanel>`,
    `${panel.indent}</section>`,
    `${relativePath}: ${panel.label} panel closing`
  )
}

reconstructed = replaceExactlyOnce(
  reconstructed,
  importLine,
  "",
  `${relativePath}: CadencePanel import removal`
)

assert.equal(count(reconstructed, "CadencePanel"), 0, `${relativePath}: residual CadencePanel`)

const reconstructedSha256 = createHash("sha256").update(reconstructed).digest("hex")
assert.equal(
  reconstructedSha256,
  "72cc4095e79c29105ea5da26f73b9de3b7085ac8877d119420fa11e9f14d890b",
  `${relativePath}: reconstructed frozen-base SHA-256`
)

console.log("panel fleet run migration contract passed")
