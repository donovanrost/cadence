import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {peelCadenceStatTileBeforeOlderLayers} from "./stat_tile_test_support.mjs"

export const opsDataSourcesFieldPredecessorCommit =
  "c19bb1e9ac6f67968eb9a72e04736983fcb6ab2f"
export const opsDataSourcesFieldPredecessorByteLength = 65_754
export const opsDataSourcesFieldPredecessorSha256 =
  "216d258ab5725d7b7a6d5fe2f5cd79a9c091a42548c1b9611de214942a10c6ff"
export const opsDataSourcesFieldImport =
  'import CadenceField from "./ui/components/CadenceField.vue"\n'

const field = ({
  id,
  label,
  indent,
  tag,
  model,
  name,
  required = false,
  type = null,
  placeholder = null,
  options = null,
}) =>
  Object.freeze({id, label, indent, tag, model, name, required, type, placeholder, options})

export const opsDataSourcesFields = Object.freeze([
  field({
    id: "source_data_source_id",
    label: "Source ID",
    indent: 12,
    tag: "input",
    model: "registerSource.data_source_id",
    name: "source[data_source_id]",
    required: true,
    type: "text",
    placeholder: "rehearsal-questdb",
  }),
  field({
    id: "source_logical_source",
    label: "Logical source",
    indent: 12,
    tag: "select",
    model: "registerSource.logical_source",
    name: "source[logical_source]",
    required: true,
    options: "page.admin.registration.form.options.logical_source",
  }),
  field({
    id: "source_kind",
    label: "Ownership",
    indent: 12,
    tag: "select",
    model: "registerSource.kind",
    name: "source[kind]",
    required: true,
    options: "page.admin.registration.form.options.kind",
  }),
  field({
    id: "source_isolation_level",
    label: "Isolation",
    indent: 12,
    tag: "select",
    model: "registerSource.isolation_level",
    name: "source[isolation_level]",
    required: true,
    options: "page.admin.registration.form.options.isolation_level",
  }),
  field({
    id: "source_credentials_ref",
    label: "Credential ref",
    indent: 12,
    tag: "input",
    model: "registerSource.credentials_ref",
    name: "source[credentials_ref]",
    type: "text",
    placeholder: "cred-rehearsal-questdb",
  }),
  field({
    id: "source_credential_provider",
    label: "Credential provider",
    indent: 12,
    tag: "select",
    model: "registerSource.credential_provider",
    name: "source[credential_provider]",
    options: "page.admin.registration.form.options.credential_provider",
  }),
  field({
    id: "source_endpoint_ref",
    label: "Endpoint ref",
    indent: 12,
    tag: "input",
    model: "registerSource.endpoint_ref",
    name: "source[endpoint_ref]",
    type: "text",
    placeholder: "endpoint://customer/rehearsal",
  }),
  field({
    id: "source_material_env_profile",
    label: "Env material profile",
    indent: 12,
    tag: "input",
    model: "registerSource.material_env_profile",
    name: "source[material_env_profile]",
    type: "text",
    placeholder: "customer-rehearsal-questdb",
  }),
  field({
    id: "source_http_endpoint_env",
    label: "HTTP endpoint env",
    indent: 12,
    tag: "input",
    model: "registerSource.http_endpoint_env",
    name: "source[http_endpoint_env]",
    type: "text",
    placeholder: "CADENCE_CUSTOMER_QUESTDB_HTTP_ENDPOINT",
  }),
  field({
    id: "source_storage",
    label: "Storage",
    indent: 12,
    tag: "select",
    model: "registerSource.storage",
    name: "source[storage]",
    required: true,
    options: "page.admin.registration.form.options.storage",
  }),
  field({
    id: "binding_data_source_id",
    label: "Data source",
    indent: 24,
    tag: "select",
    model: "binding.data_source_id",
    name: "binding[data_source_id]",
    required: true,
    options: "page.admin.binding_form.source_options",
  }),
])

const occurrences = (source, fragment) => source.split(fragment).length - 1
const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const shiftIndent = (source, spaces) =>
  source
    .split("\n")
    .map((line) => `${" ".repeat(spaces)}${line}`)
    .join("\n")

const migratedOpening = (boundary) => {
  const spaces = " ".repeat(boundary.indent)

  return `${spaces}<CadenceField
${spaces}  control-id="${boundary.id}"
${spaces}  wrapper-class="fieldset mb-3"
${spaces}  label="${boundary.label}"
${spaces}  label-class="hud-label block mb-1.5"
${spaces}>`
}

const assertNativeControl = (control, boundary, caller) => {
  const spaces = " ".repeat(boundary.indent + 2)
  const label = `${caller}: ${boundary.id}`

  assert.match(
    control,
    new RegExp(`^${spaces}<${boundary.tag}\\n`),
    `${label} keeps its native ${boundary.tag} physically in the caller slot`,
  )
  assert.equal(occurrences(control, `${spaces}  id="${boundary.id}"`), 1, `${label} exact id`)
  assert.equal(
    occurrences(control, `${spaces}  v-model="${boundary.model}"`),
    1,
    `${label} exact v-model`,
  )
  assert.equal(
    occurrences(control, `${spaces}  name="${boundary.name}"`),
    1,
    `${label} exact native name`,
  )
  assert.equal(
    occurrences(control, `${spaces}  class="w-full ${boundary.tag === "input" ? "input" : "select"}"`),
    1,
    `${label} exact native class`,
  )
  assert.equal(
    occurrences(control, `${spaces}  required`),
    boundary.required ? 1 : 0,
    `${label} exact required presence`,
  )

  if (boundary.type) {
    assert.equal(occurrences(control, `${spaces}  type="${boundary.type}"`), 1, `${label} exact type`)
  }
  if (boundary.placeholder) {
    assert.equal(
      occurrences(control, `${spaces}  placeholder="${boundary.placeholder}"`),
      1,
      `${label} exact placeholder`,
    )
  }
  if (boundary.options) {
    assert.equal(
      occurrences(control, `v-for="option in ${boundary.options}"`),
      1,
      `${label} exact server option source`,
    )
    assert.equal(occurrences(control, ':key="option.value"'), 1, `${label} exact option key`)
    assert.equal(occurrences(control, ':value="option.value"'), 1, `${label} exact option value`)
    assert.equal(occurrences(control, "{{ option.label }}"), 1, `${label} exact option label`)
  }
}

export const peelOpsDataSourcesCadenceFields = (source, caller = "OpsDataSources.vue") => {
  const file = caller.split("/").at(-1)
  assert.equal(file, "OpsDataSources.vue", `${caller} is the exact field-migration caller`)
  const statTileCompatibleSource = peelCadenceStatTileBeforeOlderLayers(source, caller)
  assert.equal(
    occurrences(statTileCompatibleSource, opsDataSourcesFieldImport),
    1,
    `${file} has one exact CadenceField import before peeling`,
  )
  assert.equal(
    occurrences(statTileCompatibleSource, "<CadenceField\n"),
    opsDataSourcesFields.length,
    `${file} has exactly eleven migrated field openings`,
  )
  assert.equal(
    occurrences(statTileCompatibleSource, "</CadenceField>"),
    opsDataSourcesFields.length,
    `${file} has exactly eleven migrated field closings`,
  )

  let predecessor = statTileCompatibleSource.replace(opsDataSourcesFieldImport, "")

  for (const boundary of opsDataSourcesFields) {
    const spaces = " ".repeat(boundary.indent)
    const opening = migratedOpening(boundary)
    const closing = `\n${spaces}</CadenceField>`

    assert.equal(
      occurrences(predecessor, opening),
      1,
      `${file}: ${boundary.id} has one exact CadenceField boundary`,
    )

    const start = predecessor.indexOf(opening)
    const controlStart = start + opening.length + 1
    const closeStart = predecessor.indexOf(closing, controlStart)
    assert.notEqual(closeStart, -1, `${file}: ${boundary.id} has one exact closing boundary`)

    const control = predecessor.slice(controlStart, closeStart)
    assertNativeControl(control, boundary, file)

    const original = `${spaces}<div class="fieldset mb-3">
${spaces}  <label for="${boundary.id}">
${spaces}    <span class="hud-label block mb-1.5">${boundary.label}</span>
${shiftIndent(control, 2)}
${spaces}  </label>
${spaces}</div>`

    predecessor =
      predecessor.slice(0, start) +
      original +
      predecessor.slice(closeStart + closing.length)
  }

  assert.doesNotMatch(predecessor, /CadenceField/)
  assert.equal(
    Buffer.byteLength(predecessor),
    opsDataSourcesFieldPredecessorByteLength,
    `${file} reconstructs the exact predecessor byte length`,
  )
  assert.equal(
    sha256(predecessor),
    opsDataSourcesFieldPredecessorSha256,
    `${file} reconstructs the frozen predecessor SHA-256`,
  )
  return predecessor
}
