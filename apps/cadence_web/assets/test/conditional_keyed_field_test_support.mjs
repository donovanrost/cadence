import assert from "node:assert/strict"

const spaces = (count) => " ".repeat(count)
const occurrences = (source, fragment) => source.split(fragment).length - 1

const boundary = ({
  file,
  indent,
  directives,
  controlId,
  label,
  oldOpening,
  errors = false,
}) => ({
  file,
  indent,
  directives,
  controlId,
  label,
  oldOpening,
  errors,
})

export const conditionalKeyedCadenceFieldBoundaries = Object.freeze([
  boundary({
    file: "OpsContactRequirementTemplate.vue",
    indent: 16,
    directives: [`v-if="template.schedule_type === 'fixed_interval'"`],
    controlId: "template_form.fields.interval_minutes.id",
    label: "template_form.fields.interval_minutes.label",
    oldOpening:
      `                <div v-if="template.schedule_type === 'fixed_interval'" class="fieldset mb-3">`,
    errors: true,
  }),
  boundary({
    file: "OpsContactRequirementTemplate.vue",
    indent: 16,
    directives: [`v-if="template.schedule_type === 'daily'"`],
    controlId: "template_form.fields.time_utc.id",
    label: "template_form.fields.time_utc.label",
    oldOpening: `                <div v-if="template.schedule_type === 'daily'" class="fieldset mb-3">`,
    errors: true,
  }),
  boundary({
    file: "OpsContactRequirementTemplate.vue",
    indent: 16,
    directives: [
      `v-if="['minimum_duration', 'minimum_data_volume'].includes(template.success_measure)"`,
    ],
    controlId: "template_form.fields.minimum_duration_seconds.id",
    label: "template_form.fields.minimum_duration_seconds.label",
    oldOpening: `                <div
                  v-if="['minimum_duration', 'minimum_data_volume'].includes(template.success_measure)"
                  class="fieldset mb-3"
                >`,
    errors: true,
  }),
  boundary({
    file: "OpsContactRequirementTemplate.vue",
    indent: 16,
    directives: [`v-if="template.success_measure === 'minimum_data_volume'"`],
    controlId: "template_form.fields.minimum_data_volume_bytes.id",
    label: "template_form.fields.minimum_data_volume_bytes.label",
    oldOpening:
      `                <div v-if="template.success_measure === 'minimum_data_volume'" class="fieldset mb-3">`,
    errors: true,
  }),
  boundary({
    file: "OpsDataOperations.vue",
    indent: 14,
    directives: [
      `v-for="fieldKey in primaryRequestFieldKeys"`,
      `:key="request_form.fields[fieldKey].id"`,
    ],
    controlId: "request_form.fields[fieldKey].id",
    label: "request_form.fields[fieldKey].label",
    oldOpening: `              <div
                v-for="fieldKey in primaryRequestFieldKeys"
                :key="request_form.fields[fieldKey].id"
                class="fieldset mb-3"
              >`,
  }),
  boundary({
    file: "OpsDataOperations.vue",
    indent: 16,
    directives: [
      `v-for="fieldKey in sourceRangeFieldKeys"`,
      `:key="request_form.fields[fieldKey].id"`,
    ],
    controlId: "request_form.fields[fieldKey].id",
    label: "request_form.fields[fieldKey].label",
    oldOpening: `                <div
                  v-for="fieldKey in sourceRangeFieldKeys"
                  :key="request_form.fields[fieldKey].id"
                  class="fieldset mb-3"
                >`,
  }),
  boundary({
    file: "OpsFleetPlanningPolicy.vue",
    indent: 16,
    directives: [
      `v-for="fieldKey in searchPolicyFieldKeys"`,
      `:key="policy_form.fields[fieldKey].id"`,
    ],
    controlId: "policy_form.fields[fieldKey].id",
    label: "policy_form.fields[fieldKey].label",
    oldOpening: `                <div
                  v-for="fieldKey in searchPolicyFieldKeys"
                  :key="policy_form.fields[fieldKey].id"
                  class="fieldset mb-3"
                >`,
    errors: true,
  }),
  boundary({
    file: "OpsFleetPlanningPolicy.vue",
    indent: 16,
    directives: [
      `v-for="fieldKey in automationPolicyFieldKeys"`,
      `:key="policy_form.fields[fieldKey].id"`,
    ],
    controlId: "policy_form.fields[fieldKey].id",
    label: "policy_form.fields[fieldKey].label",
    oldOpening: `                <div
                  v-for="fieldKey in automationPolicyFieldKeys"
                  :key="policy_form.fields[fieldKey].id"
                  class="fieldset mb-3"
                >`,
    errors: true,
  }),
  boundary({
    file: "OpsDashboardNew.vue",
    indent: 8,
    directives: [`v-if="form.document_json !== null"`],
    controlId: "form.document_json.id",
    label: "form.document_json.label",
    oldOpening: `        <div v-if="form.document_json !== null" class="fieldset mb-3">`,
  }),
])

export const conditionalKeyedCadenceFieldCounts = Object.freeze(
  Object.fromEntries(
    [...new Set(conditionalKeyedCadenceFieldBoundaries.map(({file}) => file))].map((file) => [
      file,
      conditionalKeyedCadenceFieldBoundaries.filter((boundaryEntry) => boundaryEntry.file === file)
        .length,
    ]),
  ),
)

export const conditionalKeyedFrozenHeadSha256 = Object.freeze({
  "OpsContactRequirementTemplate.vue":
    "11e6a3e35c3f4459d8643d0dc13e112ca4c267db78c8d0f4d3c37b661228f70e",
  "OpsDataOperations.vue": "b9a64a7de8dbf21c1c6312e043f6c4db90b1c9119e0435d5d31db4e0f1302306",
  "OpsFleetPlanningPolicy.vue":
    "17135c0f415581b6746006490a51e8b9da3bfed1b1fa1e999385f87572ae7fab",
  "OpsDashboardNew.vue": "5447b03c34036451c47d526fc09026e1cd6b5bf0e10d6f59322c9cec299de6bf",
})

const migratedOpening = (entry) => {
  const indent = spaces(entry.indent)
  const directiveSource = entry.directives.map((directive) => `${indent}  ${directive}\n`).join("")

  return `${indent}<CadenceField
${directiveSource}${indent}  :control-id="${entry.controlId}"
${indent}  wrapper-class="fieldset mb-3"
${indent}  :label="${entry.label}"
${indent}  label-class="hud-label block mb-1.5"
${indent}>`
}

const shiftLeft = (source, count, label) =>
  source
    .split("\n")
    .map((line) => {
      assert.ok(line.startsWith(spaces(count)), `${label}: nested source keeps its indentation`)
      return line.slice(count)
    })
    .join("\n")

const peelBoundary = (source, entry) => {
  const indent = spaces(entry.indent)
  const opening = migratedOpening(entry)
  const closing = `\n${indent}</CadenceField>`
  const label = `${entry.file}: ${entry.controlId}`

  assert.equal(occurrences(source, opening), 1, `${label}: exact newest opening count`)
  const start = source.indexOf(opening)
  const end = source.indexOf(closing, start + opening.length)
  assert.notEqual(end, -1, `${label}: exact newest closing exists`)

  let controls = source.slice(start + opening.length, end)
  let errors = ""

  if (entry.errors) {
    const errorsOpen = `\n${indent}  <template #errors>\n`
    const errorsClose = `\n${indent}  </template>`
    const errorsStart = controls.lastIndexOf(errorsOpen)

    assert.notEqual(errorsStart, -1, `${label}: caller-owned errors slot exists`)
    assert.ok(controls.endsWith(errorsClose), `${label}: errors slot closes last`)
    const errorSource = controls.slice(errorsStart + errorsOpen.length, -errorsClose.length)
    errors = `\n${shiftLeft(errorSource, 2, label)}`
    controls = controls.slice(0, errorsStart)
  } else {
    assert.doesNotMatch(controls, /<template #errors>/, `${label}: no errors slot is introduced`)
  }

  assert.match(
    controls,
    new RegExp(`^\\n${indent}  <(?:input|textarea)\\b`),
    `${label}: native control remains in the caller slot`,
  )

  const shiftedControls = controls.replaceAll("\n", "\n  ")
  const original = `${entry.oldOpening}
${indent}  <label :for="${entry.controlId}">
${indent}    <span class="hud-label block mb-1.5">{{ ${entry.label} }}</span>${shiftedControls}
${indent}  </label>${errors}
${indent}</div>`

  return source.slice(0, start) + original + source.slice(end + closing.length)
}

export const peelConditionalKeyedCadenceFields = (source, file) => {
  const entries = conditionalKeyedCadenceFieldBoundaries.filter((entry) => entry.file === file)
  let peeled = source

  for (const entry of entries) peeled = peelBoundary(peeled, entry)

  if (entries.length > 0) {
    assert.equal(
      entries.length,
      conditionalKeyedCadenceFieldCounts[file],
      `${file}: every conditional/keyed boundary is peeled newest-first`,
    )
    for (const entry of entries) {
      assert.equal(occurrences(peeled, migratedOpening(entry)), 0, `${file}: newest frame is absent`)
      assert.equal(occurrences(peeled, entry.oldOpening), 1, `${file}: predecessor shell is exact`)
    }
  }

  return peeled
}
