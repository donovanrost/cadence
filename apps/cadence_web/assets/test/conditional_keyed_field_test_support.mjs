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
