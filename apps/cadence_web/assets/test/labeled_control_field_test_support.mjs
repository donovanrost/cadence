import assert from "node:assert/strict"

const spaces = (count) => " ".repeat(count)
const occurrences = (source, fragment) => source.split(fragment).length - 1

const boundary = (spec) => {
  const entry = {
    directives: [],
    wrapperClass: "fieldset mb-3",
    wrapperClassLiteral: true,
    controlIdLiteral: false,
    labelLiteral: false,
    labelClass: "hud-label block mb-1.5",
    labelClassLiteral: true,
    oldLabelFor: null,
    oldLabelText: null,
    oldSpanMultiline: false,
    help: false,
    errors: false,
    ...spec,
  }

  entry.directives = Object.freeze([...entry.directives])
  entry.oldSpanClass =
    entry.labelClassLiteral ? `class="${entry.labelClass}"` : `:class="${entry.labelClass}"`
  entry.oldSpanText =
    entry.oldLabelText ??
    (entry.labelLiteral ? entry.label : `{{ ${entry.label} }}`)
  return Object.freeze(entry)
}

export const labeledControlFieldMigrationBase =
  "6d1d2625fff833e8a4f24132a7e9606a4a0f6ca4"

export const labeledControlFieldFiles = Object.freeze([
  "AdminOrganizationShow.vue",
  "ApplicationHost.vue",
  "CatalogUploadForm.vue",
  "DashboardAbsoluteRangePane.vue",
  "DashboardRuntimeControls.vue",
  "DashboardTimeReplay.vue",
  "HistoricalWorkflowCorrectionForm.vue",
  "HistoricalWorkflowGroupForm.vue",
  "HistoricalWorkflowRequestForm.vue",
  "OpsActivationRequests.vue",
  "OpsAlarms.vue",
  "OpsCommands.vue",
  "OpsContactSchedule.vue",
  "OpsDashboardDirectory.vue",
  "OpsDashboardPlaylists.vue",
  "ProviderAccountShow.vue",
  "SpacecraftTelemetryDecom.vue",
])

export const labeledControlFieldBoundaries = Object.freeze([
  boundary({
    file: "AdminOrganizationShow.vue",
    line: 297,
    indent: 8,
    controlId: "service_identity_display_name",
    controlIdLiteral: true,
    label: "Display name",
    labelLiteral: true,
    labelClass: "hud-label mb-1.5 block",
    oldLabelText: "Display name",
  }),
  boundary({
    file: "AdminOrganizationShow.vue",
    line: 310,
    indent: 8,
    controlId: "service_identity_service_identity_id",
    controlIdLiteral: true,
    label: "ID (optional)",
    labelLiteral: true,
    labelClass: "hud-label mb-1.5 block",
    oldLabelText: "ID (optional)",
  }),
  boundary({
    file: "ApplicationHost.vue",
    line: 527,
    indent: 14,
    controlId: "field.input_id",
    label: "field.label",
    wrapperClass: "fieldset mb-3",
    labelClass: "hud-label mb-1.5 block",
    help: true,
    errors: true,
  }),
  boundary({
    file: "ApplicationHost.vue",
    line: 687,
    indent: 10,
    controlId: "declarative_surface.packet_bindings.form.source_endpoint.id",
    label: "declarative_surface.packet_bindings.form.source_endpoint.label",
    labelClass: "hud-label mb-1.5 block",
    oldSpanMultiline: true,
  }),
  boundary({
    file: "CatalogUploadForm.vue",
    line: 205,
    indent: 12,
    directives: ['v-for="field in form.primary_fields"', ':key="field.key"'],
    controlId: "field.id",
    label: "field.label",
    wrapperClass: "field.wrapper_class",
    wrapperClassLiteral: false,
    labelClass: "field.label_class",
    labelClassLiteral: false,
    oldLabelFor: ':for="field.id"',
    errors: true,
  }),
  boundary({
    file: "CatalogUploadForm.vue",
    line: 236,
    indent: 10,
    directives: ['v-for="field in form.secondary_fields"', ':key="field.key"'],
    controlId: "field.id",
    label: "field.label",
    wrapperClass: "field.wrapper_class",
    wrapperClassLiteral: false,
    labelClass: "field.label_class",
    labelClassLiteral: false,
    oldLabelFor: ':for="field.id"',
    errors: true,
  }),
  boundary({
    file: "DashboardAbsoluteRangePane.vue",
    line: 22,
    indent: 6,
    controlId: "props.form.from.attrs.id",
    label: "props.form.from.label.text",
    wrapperClass: "props.form.from.wrapper_class",
    wrapperClassLiteral: false,
    labelClass: "props.form.from.label.class",
    labelClassLiteral: false,
  }),
  boundary({
    file: "DashboardAbsoluteRangePane.vue",
    line: 29,
    indent: 8,
    controlId: "props.form.to.field.attrs.id",
    label: "props.form.to.field.label.text",
    wrapperClass: "props.form.to.field.wrapper_class",
    wrapperClassLiteral: false,
    labelClass: "props.form.to.field.label.class",
    labelClassLiteral: false,
  }),
  boundary({
    file: "DashboardRuntimeControls.vue",
    line: 130,
    indent: 12,
    directives: [
      'v-for="field in runtime_controls.form.source.fields"',
      ':key="String(field.attrs.id)"',
    ],
    controlId: "String(field.attrs.id)",
    label: "field.label.text",
    wrapperClass: "field.wrapper_class",
    wrapperClassLiteral: false,
    labelClass: "field.label.class",
    labelClassLiteral: false,
  }),
  boundary({
    file: "DashboardRuntimeControls.vue",
    line: 159,
    indent: 12,
    directives: [
      'v-for="field in runtime_controls.form.representation.fields"',
      ':key="String(field.attrs.id)"',
    ],
    controlId: "String(field.attrs.id)",
    label: "field.label.text",
    wrapperClass: "field.wrapper_class",
    wrapperClassLiteral: false,
    labelClass: "field.label.class",
    labelClassLiteral: false,
  }),
  boundary({
    file: "DashboardRuntimeControls.vue",
    line: 188,
    indent: 12,
    directives: [
      'v-for="field in runtime_controls.form.semantics.fields"',
      ':key="String(field.attrs.id)"',
    ],
    controlId: "String(field.attrs.id)",
    label: "field.label.text",
    wrapperClass: "field.wrapper_class",
    wrapperClassLiteral: false,
    labelClass: "field.label.class",
    labelClassLiteral: false,
  }),
  boundary({
    file: "DashboardTimeReplay.vue",
    line: 72,
    indent: 8,
    controlId: "String(presentation.body.form.replay_run.attrs.id)",
    label: "presentation.body.form.replay_run.label.text",
    wrapperClass: "presentation.body.form.replay_run.wrapper_class",
    wrapperClassLiteral: false,
    labelClass: "presentation.body.form.replay_run.label.class",
    labelClassLiteral: false,
    oldSpanMultiline: true,
  }),
  boundary({
    file: "HistoricalWorkflowCorrectionForm.vue",
    line: 119,
    indent: 4,
    controlId: "presentation.new_run.id",
    label: "presentation.new_run.label.text",
    wrapperClass: "presentation.new_run.wrapper_class",
    wrapperClassLiteral: false,
    labelClass: "presentation.new_run.label.class",
    labelClassLiteral: false,
    oldSpanMultiline: true,
    errors: true,
  }),
  boundary({
    file: "HistoricalWorkflowCorrectionForm.vue",
    line: 143,
    indent: 6,
    directives: ['v-for="field in presentation.source_fields"', ':key="field.id"'],
    controlId: "field.id",
    label: "field.label.text",
    wrapperClass: "field.wrapper_class",
    wrapperClassLiteral: false,
    labelClass: "field.label.class",
    labelClassLiteral: false,
    errors: true,
  }),
  boundary({
    file: "HistoricalWorkflowGroupForm.vue",
    line: 211,
    indent: 4,
    controlId: "presentation.reason.control.attrs.id",
    label: "presentation.reason.label.text",
    wrapperClass: "presentation.reason.wrapper_class",
    wrapperClassLiteral: false,
    labelClass: "presentation.reason.label.class",
    labelClassLiteral: false,
    errors: true,
  }),
  boundary({
    file: "HistoricalWorkflowRequestForm.vue",
    line: 121,
    indent: 6,
    directives: ['v-for="field in presentation.request_context.fields"', ':key="field.key"'],
    controlId: "field.control.attrs.id",
    label: "field.label.text",
    wrapperClass: "field.wrapper_class",
    wrapperClassLiteral: false,
    labelClass: "field.label.class",
    labelClassLiteral: false,
    errors: true,
  }),
  boundary({
    file: "HistoricalWorkflowRequestForm.vue",
    line: 146,
    indent: 8,
    directives: [
      'v-for="field in presentation.request_context.group.fields"',
      ':key="field.key"',
    ],
    controlId: "field.control.attrs.id",
    label: "field.label.text",
    wrapperClass: "field.wrapper_class",
    wrapperClassLiteral: false,
    labelClass: "field.label.class",
    labelClassLiteral: false,
    errors: true,
  }),
  boundary({
    file: "HistoricalWorkflowRequestForm.vue",
    line: 166,
    indent: 6,
    directives: ['v-for="field in presentation.source_window.fields"', ':key="field.key"'],
    controlId: "field.control.attrs.id",
    label: "field.label.text",
    wrapperClass: "field.wrapper_class",
    wrapperClassLiteral: false,
    labelClass: "field.label.class",
    labelClassLiteral: false,
    errors: true,
  }),
  boundary({
    file: "OpsActivationRequests.vue",
    line: 191,
    indent: 10,
    controlId: "form.reason.id",
    label: "form.reason.label",
  }),
  boundary({
    file: "OpsAlarms.vue",
    line: 210,
    indent: 8,
    controlId: "filters.fields.severity.id",
    label: "filters.fields.severity.label",
  }),
  boundary({
    file: "OpsAlarms.vue",
    line: 230,
    indent: 8,
    controlId: "filters.fields.state.id",
    label: "filters.fields.state.label",
  }),
  boundary({
    file: "OpsAlarms.vue",
    line: 250,
    indent: 8,
    controlId: "filters.fields.spacecraft_id.id",
    label: "filters.fields.spacecraft_id.label",
  }),
  boundary({
    file: "OpsAlarms.vue",
    line: 270,
    indent: 8,
    controlId: "filters.fields.query.id",
    label: "filters.fields.query.label",
  }),
  boundary({
    file: "OpsCommands.vue",
    line: 275,
    indent: 8,
    controlId: "filters.fields.status.id",
    label: "filters.fields.status.label",
  }),
  boundary({
    file: "OpsCommands.vue",
    line: 295,
    indent: 8,
    controlId: "filters.fields.target.id",
    label: "filters.fields.target.label",
  }),
  boundary({
    file: "OpsCommands.vue",
    line: 315,
    indent: 8,
    controlId: "filters.fields.query.id",
    label: "filters.fields.query.label",
  }),
  boundary({
    file: "OpsContactSchedule.vue",
    line: 397,
    indent: 14,
    controlId: "search.fields.spacecraft.id",
    label: "search.fields.spacecraft.label",
  }),
  boundary({
    file: "OpsContactSchedule.vue",
    line: 418,
    indent: 14,
    controlId: "search.fields.route.id",
    label: "search.fields.route.label",
  }),
  boundary({
    file: "OpsContactSchedule.vue",
    line: 439,
    indent: 14,
    controlId: "search.fields.starts_at.id",
    label: "search.fields.starts_at.label",
  }),
  boundary({
    file: "OpsContactSchedule.vue",
    line: 453,
    indent: 14,
    controlId: "search.fields.ends_at.id",
    label: "search.fields.ends_at.label",
  }),
  boundary({
    file: "OpsDashboardDirectory.vue",
    line: 231,
    indent: 8,
    controlId: "filters.fields.query.id",
    label: "filters.fields.query.label",
  }),
  boundary({
    file: "OpsDashboardDirectory.vue",
    line: 246,
    indent: 8,
    controlId: "filters.fields.lifecycle.id",
    label: "filters.fields.lifecycle.label",
  }),
  boundary({
    file: "OpsDashboardDirectory.vue",
    line: 266,
    indent: 8,
    controlId: "filters.fields.tag.id",
    label: "filters.fields.tag.label",
  }),
  boundary({
    file: "OpsDashboardDirectory.vue",
    line: 286,
    indent: 8,
    controlId: "filters.fields.sort.id",
    label: "filters.fields.sort.label",
  }),
  boundary({
    file: "OpsDashboardPlaylists.vue",
    line: 225,
    indent: 10,
    controlId: "form.name.id",
    label: "form.name.label",
  }),
  boundary({
    file: "OpsDashboardPlaylists.vue",
    line: 238,
    indent: 10,
    controlId: "form.description.id",
    label: "form.description.label",
  }),
  boundary({
    file: "OpsDashboardPlaylists.vue",
    line: 250,
    indent: 10,
    controlId: "form.dashboard_ids.id",
    label: "form.dashboard_ids.label",
  }),
  boundary({
    file: "OpsDashboardPlaylists.vue",
    line: 267,
    indent: 10,
    controlId: "form.dwell_seconds.id",
    label: "form.dwell_seconds.label",
  }),
  boundary({
    file: "ProviderAccountShow.vue",
    line: 393,
    indent: 14,
    directives: ['v-for="fieldKey in grantFieldOrder"', ':key="fieldKey"'],
    controlId: "grant_form.fields[fieldKey].id",
    label: "grant_form.fields[fieldKey].label",
  }),
  boundary({
    file: "SpacecraftTelemetryDecom.vue",
    line: 360,
    indent: 14,
    controlId: "revision.field.id",
    label: "revision.field.label",
  }),
])

export const labeledControlFieldCounts = Object.freeze(
  Object.fromEntries(
    labeledControlFieldFiles.map((file) => [
      file,
      labeledControlFieldBoundaries.filter((entry) => entry.file === file).length,
    ]),
  ),
)

export const labeledControlFieldFrozenFingerprints = Object.freeze({
  "AdminOrganizationShow.vue": {
    byteLength: 10940,
    blobId: "f0295491362350daf535e06731bc4b0dd2b0682d",
    sha256: "fd8deae26562c2b6b68c186416946d6513ee5134c975daadc7972a3442478a9a",
  },
  "ApplicationHost.vue": {
    byteLength: 35661,
    blobId: "5753df2f06de687b622a4aafe0394382d264badf",
    sha256: "5e9e6c109b027ab7e05e18ec0dd9dbb1cebd842e6b0682cf3dbcdc4bf580dd62",
  },
  "CatalogUploadForm.vue": {
    byteLength: 10040,
    blobId: "df23df6baf59198246f52c687ee2837b2451934e",
    sha256: "ea2bc17e5e1ddf3cfd4a53de6b28d64768b32d342832319532a5b6275f009618",
  },
  "DashboardAbsoluteRangePane.vue": {
    byteLength: 1690,
    blobId: "380117e56ec3e02122b7f424644af4b396c9f534",
    sha256: "0120e0ef314b0a8950b73355ae73f9f502f3280c2369e3cf99f6dffc98bf943c",
  },
  "DashboardRuntimeControls.vue": {
    byteLength: 7290,
    blobId: "3501d74648986b6c9f0da8bf41800c55bb1e0b1d",
    sha256: "1e5c01b5e432558a5fee073de8100b138ed4df937886ef1186201ffd74492c47",
  },
  "DashboardTimeReplay.vue": {
    byteLength: 2521,
    blobId: "fc5a1d599fef2b6fe76ba6d307cff8d2691091e8",
    sha256: "1a09967df6e813c3ddef8408f877655a669a1816f37ca5600900471de4b2fc16",
  },
  "HistoricalWorkflowCorrectionForm.vue": {
    byteLength: 4827,
    blobId: "dc07cdb2b4458c5fdf8a73362dd90644294b9697",
    sha256: "4ee874f1e6b9501a8e8132ee9eddfb97eadc3dbaa524e34120b2ef2dd278e72b",
  },
  "HistoricalWorkflowGroupForm.vue": {
    byteLength: 7472,
    blobId: "4fb993d67b78881f2966a6a4cdea7e8eae0362fa",
    sha256: "869b66f0f343706f660d7f82b36af5fadd9557d43682bce26db29db3cb0a071b",
  },
  "HistoricalWorkflowRequestForm.vue": {
    byteLength: 5241,
    blobId: "cc826f86fbd6b7a67a0519e5a7546945ce0cf4f7",
    sha256: "847ff4e509d162838e9f9fdf0f1ba22b369be680a139df2f22526c0dd7167ea0",
  },
  "OpsActivationRequests.vue": {
    byteLength: 6169,
    blobId: "930db5e43d197d985e5ede1361d8f6bfd29bd1ae",
    sha256: "36bc3405332eb8dcfb64b54a35723696025500955db6b0ae8ff8571c72172819",
  },
  "OpsAlarms.vue": {
    byteLength: 11066,
    blobId: "971433827bb1bb27103464eb05ed394397a7e7c6",
    sha256: "85c6eb8ec3d61a3ba24cd148f3caebd2c727db86c018a29f17059b2328968998",
  },
  "OpsCommands.vue": {
    byteLength: 13026,
    blobId: "e19681d78700be01e05053c0aaf1f2e7d5bfdadc",
    sha256: "602e53a14c19dea061dc5effd7e9a88a47ff61a351dc01fc35b5801750e381e0",
  },
  "OpsContactSchedule.vue": {
    byteLength: 25596,
    blobId: "d83a5f746542bb392f410ea201f4b909fa9038c1",
    sha256: "96aae5c5b05c02673dd07dd60977ca66c737d5eaf69d3815bba403b981aa1110",
  },
  "OpsDashboardDirectory.vue": {
    byteLength: 12728,
    blobId: "df41ef2e6a43bc845ab2bd1660d4eb299b81ef86",
    sha256: "b0d8a3817de160ff80094df2f3ee8795705bbeeab2ca177a17b7f693b3284bba",
  },
  "OpsDashboardPlaylists.vue": {
    byteLength: 8979,
    blobId: "9ffa2ad94d35189ca9274aff1839ef79d9e36c10",
    sha256: "ce33f46be8b032c48cf7ea9905b1d0ef603a99cdabd4f6915acff0b32b661154",
  },
  "ProviderAccountShow.vue": {
    byteLength: 17750,
    blobId: "3e7312e852989633b075c55a1b507162210a7b05",
    sha256: "29362c28e5e217afcb4380e75899735e5a961980de008689e43254b975f7d62d",
  },
  "SpacecraftTelemetryDecom.vue": {
    byteLength: 22605,
    blobId: "3e0a9a08d825d7cbe299ea92a760e12321e4be48",
    // Discarded audit transcription, not repository drift: 47ea4ad281b2e36efb1c687cc0c0c7ba81ca5f0e6de265509709b8317cf5fb8.
    sha256: "47ea4ad281b2e36efb1c687cc0c0c7ba81ca5f0e6de2655097095b8317cf5fb8",
  },
})

const oldWrapperOpening = (entry) => {
  const indent = spaces(entry.indent)
  const attributes = [
    ...entry.directives,
    entry.wrapperClassLiteral
      ? `class="${entry.wrapperClass}"`
      : `:class="${entry.wrapperClass}"`,
  ]

  if (attributes.length === 1) return `${indent}<div ${attributes[0]}>`
  return `${indent}<div\n${attributes.map((attribute) => `${indent}  ${attribute}`).join("\n")}\n${indent}>`
}

const prop = (name, value, literal) =>
  literal ? `${name}="${value}"` : `:${name}="${value}"`

export const labeledControlFieldMigratedOpening = (entry) => {
  const indent = spaces(entry.indent + 2)
  const directiveSource = entry.directives
    .map((directive) => `${indent}  ${directive}\n`)
    .join("")
  const controlIdSource = entry.oldLabelFor
    ? `${indent}  ${prop("control-id", entry.controlId, entry.controlIdLiteral)}\n`
    : ""

  return `${indent}<CadenceField\n${directiveSource}${controlIdSource}${indent}  ${prop("wrapper-class", entry.wrapperClass, entry.wrapperClassLiteral)}\n${indent}  ${prop("label", entry.label, entry.labelLiteral)}\n${indent}  ${prop("label-class", entry.labelClass, entry.labelClassLiteral)}\n${indent}>`
}

const shiftLeft = (source, count, label) =>
  source
    .split("\n")
    .map((line) => {
      assert.ok(line === "" || line.startsWith(spaces(count)), `${label}: slot indentation is exact`)
      return line === "" ? line : line.slice(count)
    })
    .join("\n")

const oldSpan = (entry) => {
  const indent = spaces(entry.indent)
  if (entry.oldSpanMultiline) {
    return `${indent}    <span ${entry.oldSpanClass}>\n${indent}      ${entry.oldSpanText}\n${indent}    </span>`
  }
  return `${indent}    <span ${entry.oldSpanClass}>${entry.oldSpanText}</span>`
}

const extractSlot = (body, entry, slotName) => {
  const indent = spaces(entry.indent + 2)
  const open = `\n${indent}  <template #${slotName}>\n`
  const start = body.indexOf(open)
  if (start === -1) return {body, sibling: ""}

  const contentStart = start + open.length
  const close = `\n${indent}  </template>`
  const closeStart = body.indexOf(close, contentStart)
  assert.notEqual(closeStart, -1, `${entry.file}:${entry.line} ${slotName} slot closes exactly`)
  const content = body.slice(contentStart, closeStart)
  const after = body.slice(closeStart + close.length)
  return {
    body: body.slice(0, start) + after,
    sibling: `${slotName === "help" || entry.help ? "\n\n" : "\n"}${shiftLeft(
      content,
      4,
      `${entry.file}:${entry.line} ${slotName}`,
    )}`,
  }
}

const peelBoundary = (source, entry) => {
  const indent = spaces(entry.indent + 2)
  const originalIndent = spaces(entry.indent)
  const opening = labeledControlFieldMigratedOpening(entry)
  const closing = `\n${indent}</CadenceField>`
  const label = `${entry.file}:${entry.line}`

  assert.equal(occurrences(source, opening), 1, `${label}: exact CadenceField opening count`)
  const start = source.indexOf(opening)
  const end = source.indexOf(closing, start + opening.length)
  assert.notEqual(end, -1, `${label}: exact CadenceField closing exists`)

  let body = source.slice(start + opening.length, end)
  let siblings = ""
  for (const slotName of ["help", "errors"]) {
    const slot = extractSlot(body, entry, slotName)
    body = slot.body
    siblings += slot.sibling
    if (entry[slotName]) {
      assert.notEqual(slot.sibling, "", `${label}: caller-owned ${slotName} slot exists`)
    } else {
      assert.equal(slot.sibling, "", `${label}: no ${slotName} slot is introduced`)
    }
  }

  assert.match(body, /\n[ ]+<(?:input|select|textarea)\b/, `${label}: native control remains in caller slot`)
  assert.doesNotMatch(body, /<label\b/, `${label}: caller slot has no nested label`)

  body = body.replace(/\n+$/, "")

  const original =
    `${oldWrapperOpening(entry)}\n` +
    `${originalIndent}  <label${entry.oldLabelFor ? ` ${entry.oldLabelFor}` : ""}>\n` +
    `${oldSpan(entry)}${body}\n` +
    `${originalIndent}  </label>${siblings}\n${originalIndent}</div>`

  return source.slice(0, start) + original + source.slice(end + closing.length)
}

export const peelLabeledControlFields = (source, file) => {
  const entries = labeledControlFieldBoundaries.filter((entry) => entry.file === file)
  assert.ok(entries.length > 0, `${file}: exact labeled-control cohort caller exists`)
  assert.equal(
    occurrences(source, 'import CadenceField from "./ui/components/CadenceField.vue"'),
    1,
    `${file}: one exact CadenceField import exists before peeling`,
  )
  assert.equal(
    occurrences(source, "<CadenceField\n"),
    entries.length,
    `${file}: every audited boundary has one CadenceField opening`,
  )
  assert.equal(
    occurrences(source, "</CadenceField>"),
    entries.length,
    `${file}: every audited boundary has one CadenceField closing`,
  )

  let peeled = source.replace('import CadenceField from "./ui/components/CadenceField.vue"\n', "")
  peeled = peeled.replace(/^(<script(?:\s[^>]*)?>)\n\n/, "$1\n")
  for (const entry of entries) peeled = peelBoundary(peeled, entry)

  assert.doesNotMatch(peeled, /CadenceField/, `${file}: inverse peel removes only this field layer`)
  return peeled
}

export const peelLabeledControlFieldsBeforeOlderLayers = (source, caller) => {
  const file = caller.replaceAll("\\", "/").split("/").at(-1)
  const entries = labeledControlFieldBoundaries.filter((entry) => entry.file === file)

  if (entries.length === 0) return source
  if (!source.includes('import CadenceField from "./ui/components/CadenceField.vue"')) {
    return source
  }

  return peelLabeledControlFields(source, file)
}

export const oldLabeledControlFieldOpening = oldWrapperOpening
