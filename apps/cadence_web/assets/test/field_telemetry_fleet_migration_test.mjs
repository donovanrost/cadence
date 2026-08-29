import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  expectedNodeVersion,
  installDom,
  loadSfc,
} from "./reka_adapter_test_support.mjs"
import {peelCompactTableFrames} from "./compact_table_frame_test_support.mjs"
import {peelCadenceInlineWarnings} from "./inline_warning_test_support.mjs"
import {
  opsViewportCallerNames,
  peelCadenceOpsViewport,
} from "./ops_viewport_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `Telemetry/fleet CadenceField contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const cadenceCollapsibleImports = Object.freeze([
  'import CadenceCollapsible from "./ui/reka/CadenceCollapsible.vue"\n',
  'import CadenceCollapsibleContent from "./ui/reka/CadenceCollapsibleContent.vue"\n',
  'import CadenceCollapsibleTrigger from "./ui/reka/CadenceCollapsibleTrigger.vue"\n',
])
const frozenPolicyDetailsOpening = '<details :open="policy_form.open">'
const cadenceFieldImport = 'import CadenceField from "./ui/components/CadenceField.vue"\n'
const cadenceDetailsFrameImport =
  'import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"\n'
const cadenceValidationMessageImport =
  'import CadenceValidationMessage from "./ui/components/CadenceValidationMessage.vue"\n'
const cadenceValidationMessageCounts = new Map([
  ["OpsFleetPlanningPolicy.vue", 16],
  ["OpsFleetPlanningNew.vue", 2],
])
const occurrences = (source, fragment) => source.split(fragment).length - 1
const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const policyCollapsibleOpening = `        <CadenceCollapsible
          :content-id="policy_form.id"
          :open="policy_form.open"
          client-seeded
          :seed-epoch="\`\${policy_form.id}:\${policy_form.open}\`"
          :unmount-on-hide="false"
        >
          <div>
            <CadenceCollapsibleTrigger>
              <button type="button" class="cursor-pointer px-4 py-3 text-sm font-semibold">
                {{ policy_form.summary }}
              </button>
            </CadenceCollapsibleTrigger>
            <CadenceCollapsibleContent>`
const policyNativeOpening = `        ${frozenPolicyDetailsOpening}
          <summary class="cursor-pointer px-4 py-3 text-sm font-semibold">
            {{ policy_form.summary }}
          </summary>`
const policyCollapsibleClosing = `            </CadenceCollapsibleContent>
          </div>
        </CadenceCollapsible>`

assert.equal(
  sha256(frozenPolicyDetailsOpening),
  "1c3488bb5db768112ced67f1d1fd2a24716270c13e7ecaf78d4a1afd4f102310",
  "the retired policy details opening remains frozen byte-for-byte",
)

const peelCadenceCollapsible = (source, name) => {
  if (name !== "OpsFleetPlanningPolicy.vue") return source

  for (const importLine of cadenceCollapsibleImports) {
    assert.equal(occurrences(source, importLine), 1, `${name}: exact collapsible import count`)
  }
  assert.equal(occurrences(source, policyCollapsibleOpening), 1, `${name}: exact collapsible opening`)
  assert.equal(occurrences(source, policyCollapsibleClosing), 1, `${name}: exact collapsible closing`)

  let peeled = source
  for (const importLine of cadenceCollapsibleImports) peeled = peeled.replace(importLine, "")
  peeled = peeled
    .replace(policyCollapsibleOpening, policyNativeOpening)
    .replace(policyCollapsibleClosing, "        </details>")

  assert.doesNotMatch(peeled, /CadenceCollapsible(?:Content|Trigger)?/)
  assert.equal(occurrences(peeled, `        ${frozenPolicyDetailsOpening}`), 1)
  return peeled
}

const spaces = (count) => " ".repeat(count)
const cadenceDetailsFrameCounts = Object.freeze({
  "OpsFleetPlanningNew.vue": 1,
  "OpsFleetPlanningPolicy.vue": 3,
  "OpsFleetPlanningRun.vue": 1,
})
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

const field = (controlId, label, indent, {errors = false, labelSource = null} = {}) => ({
  controlId,
  label,
  indent,
  errors,
  labelSource,
})

const files = [
  {
    name: "OpsTelemetryExplore.vue",
    wrapperClass: "fieldset",
    expectedFrames: 16,
    headSha256: "c43aa0c440a8d3915b3f4d1cbd2ed2804a34f6eae7014248bcdf526e8ab58e12",
    fields: [
      field("filter_form.fields.point_id.id", "filter_form.fields.point_id.label", 12),
      field("filter_form.fields.spacecraft_id.id", "filter_form.fields.spacecraft_id.label", 12),
      field("filter_form.fields.time_mode.id", "filter_form.fields.time_mode.label", 12),
      field("filter_form.fields.from.id", "filter_form.fields.from.label", 12),
      field("filter_form.fields.to.id", "filter_form.fields.to.label", 12),
      field("filter_form.fields.order.id", "filter_form.fields.order.label", 12),
      field("filter_form.fields.limit.id", "filter_form.fields.limit.label", 14),
      field("filter_form.fields.realm.id", "filter_form.fields.realm.label", 12),
      field("filter_form.fields.logical_source.id", "filter_form.fields.logical_source.label", 12),
      field("filter_form.fields.data_source_id.id", "filter_form.fields.data_source_id.label", 12),
      field("filter_form.fields.source_binding_id.id", "filter_form.fields.source_binding_id.label", 12),
      field("filter_form.fields.selection_view.id", "filter_form.fields.selection_view.label", 12),
      field("filter_form.fields.validity_state.id", "filter_form.fields.validity_state.label", 12),
      field("authoring.form.fields.dashboard_id.id", "authoring.form.fields.dashboard_id.label", 16),
      field("authoring.form.fields.widget_type.id", "authoring.form.fields.widget_type.label", 16),
      field("authoring.form.fields.title.id", "authoring.form.fields.title.label", 16),
    ],
  },
  {
    name: "OpsFleetPlanningPolicy.vue",
    wrapperClass: "fieldset mb-3",
    expectedFrames: 14,
    headSha256: "728c4c48d4d50ae61e186aa109e1728c61ca9920ea2a74bcd53b4b5ca9c81a50",
    fields: [
      field("policy_form.fields.max_contacts.id", "policy_form.fields.max_contacts.label", 16, {errors: true}),
      field("policy_form.fields.max_estimated_cost_micros.id", "policy_form.fields.max_estimated_cost_micros.label", 16, {errors: true}),
      field("policy_form.fields.currency.id", "policy_form.fields.currency.label", 16, {errors: true}),
      field("policy_form.fields.critical_contact_reserve.id", "policy_form.fields.critical_contact_reserve.label", 16, {errors: true}),
      field("policy_form.fields.automation_mode.id", "policy_form.fields.automation_mode.label", 16, {errors: true}),
      field("approval_form.reason.id", "approval_form.reason.label", 10, {errors: true}),
      field("grant_form.fields.service_identity_id.id", "grant_form.fields.service_identity_id.label", 12, {errors: true}),
      field("grant_form.fields.maximum_horizon_hours.id", "grant_form.fields.maximum_horizon_hours.label", 14, {errors: true}),
      field("grant_form.fields.maximum_contacts.id", "grant_form.fields.maximum_contacts.label", 14, {errors: true}),
      field("grant_form.fields.maximum_execution_concurrency.id", "grant_form.fields.maximum_execution_concurrency.label", 14, {errors: true}),
      field("grant_form.fields.valid_days.id", "grant_form.fields.valid_days.label", 14, {errors: true}),
      field("grant_form.fields.approval_reason.id", "grant_form.fields.approval_reason.label", 12, {errors: true}),
      field("revocation_form.fields.automation_grant_id.id", "revocation_form.fields.automation_grant_id.label", 12, {errors: true}),
      field("revocation_form.fields.reason.id", "revocation_form.fields.reason.label", 12, {errors: true}),
    ],
  },
  {
    name: "OpsFleetPlanningNew.vue",
    wrapperClass: "fieldset mb-3",
    expectedFrames: 2,
    headSha256: "70c42aac0f05430c49830350d2187a9f9f39daf23ebdf57f8aef7b5537de53cf",
    fields: [
      field("form.fields.horizon_start.id", "form.fields.horizon_start.label", 12, {errors: true}),
      field("form.fields.horizon_end.id", "form.fields.horizon_end.label", 12, {errors: true}),
    ],
  },
  {
    name: "OpsFleetPlanningRun.vue",
    wrapperClass: "fieldset mb-3",
    expectedFrames: 2,
    headSha256: "55469e3dcb8c31fbbc777f4b90dc28d7368a6d86c215c3c7453a664c61aa94c6",
    fields: [
      field("repair_form.fields.horizon_start.id", "repair_form.fields.horizon_start.label", 14, {
        labelSource: `                  <span class="hud-label block mb-1.5">
                    {{ repair_form.fields.horizon_start.label }}
                  </span>`,
      }),
      field("repair_form.fields.horizon_end.id", "repair_form.fields.horizon_end.label", 14, {
        labelSource: `                  <span class="hud-label block mb-1.5">
                    {{ repair_form.fields.horizon_end.label }}
                  </span>`,
      }),
    ],
  },
]

assert.equal(
  files.reduce((count, file) => count + file.expectedFrames, 0),
  34,
  "the frozen telemetry/fleet ledger remains 16 + 14 + 2 + 2",
)

const dom = installDom('<div id="telemetry-fleet-field-contract"></div>')
for (const globalName of [
  "Document",
  "ShadowRoot",
  "HTMLFormElement",
  "HTMLInputElement",
  "HTMLSelectElement",
  "HTMLTextAreaElement",
  "HTMLOptionElement",
]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const loadedFiles = await Promise.all(
  files.map(async (file) => ({
    ...file,
    path: resolve(testDirectory, `../vue/${file.name}`),
    loaded: await loadSfc(resolve(testDirectory, `../vue/${file.name}`)),
  })),
)

const migratedOpening = (entry, wrapperClass) => {
  const indent = spaces(entry.indent)
  return `${indent}<CadenceField
${indent}  :control-id="${entry.controlId}"
${indent}  wrapper-class="${wrapperClass}"
${indent}  :label="${entry.label}"
${indent}  label-class="hud-label block mb-1.5"
${indent}>`
}

const peelCadenceValidationMessages = (source, name) => {
  const expectedMessages = cadenceValidationMessageCounts.get(name) ?? 0
  const expectedImports = expectedMessages > 0 ? 1 : 0

  assert.equal(
    occurrences(source, cadenceValidationMessageImport),
    expectedImports,
    `${name}: exact CadenceValidationMessage import count before peeling`,
  )
  assert.equal(
    occurrences(source, "<CadenceValidationMessage"),
    expectedMessages,
    `${name}: exact CadenceValidationMessage opening count before peeling`,
  )
  assert.equal(
    occurrences(source, "</CadenceValidationMessage>"),
    expectedMessages,
    `${name}: exact CadenceValidationMessage closing count before peeling`,
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

  assert.equal(replacements, expectedMessages, `${name}: every validation message is peeled`)
  assert.equal(
    occurrences(predecessorCompatibleSource, "CadenceValidationMessage"),
    0,
    `${name}: predecessor source has no residual CadenceValidationMessage`,
  )

  return predecessorCompatibleSource
}

const reconstructSource = (file, source) => {
  const compactTableCompatibleSource = peelCompactTableFrames(source, file.name)
  source = opsViewportCallerNames.includes(file.name)
    ? peelCadenceOpsViewport(compactTableCompatibleSource, file.name)
    : compactTableCompatibleSource
  let reconstructed = peelCadenceValidationMessages(
    peelCadenceDetailsFrames(
      peelCadenceCollapsible(peelCadenceInlineWarnings(source, file.name), file.name),
      cadenceDetailsFrameCounts[file.name] ?? 0,
      file.name,
    ),
    file.name,
  )
  assert.equal(occurrences(reconstructed, cadenceFieldImport), 1, `${file.name}: exact import count`)
  reconstructed = reconstructed.replace(cadenceFieldImport, "")

  for (const entry of file.fields) {
    const indent = spaces(entry.indent)
    const opening = migratedOpening(entry, file.wrapperClass)
    const closing = `\n${indent}</CadenceField>`
    const start = reconstructed.indexOf(opening)

    assert.notEqual(start, -1, `${file.name}: ${entry.controlId} opening is pinned`)
    assert.equal(occurrences(reconstructed, opening), 1, `${file.name}: ${entry.controlId} opens once`)

    const end = reconstructed.indexOf(closing, start + opening.length)
    assert.notEqual(end, -1, `${file.name}: ${entry.controlId} closing is pinned`)

    let controls = reconstructed.slice(start + opening.length, end)
    let errors = ""

    if (entry.errors) {
      const errorsOpen = `\n${indent}  <template #errors>`
      const errorsClose = `\n${indent}  </template>`
      const errorsStart = controls.lastIndexOf(errorsOpen)

      assert.notEqual(errorsStart, -1, `${file.name}: ${entry.controlId} keeps its error slot`)
      assert.ok(controls.endsWith(errorsClose), `${file.name}: ${entry.controlId} error slot closes last`)

      errors = controls
        .slice(errorsStart + errorsOpen.length, -errorsClose.length)
        .replaceAll(`\n${indent}    `, `\n${indent}  `)
      controls = controls.slice(0, errorsStart)
    } else {
      assert.doesNotMatch(controls, /<template #errors>/)
    }

    const shiftedControls = controls.replaceAll(`\n${indent}  `, `\n${indent}    `)
    const labelSource = entry.labelSource ??
      `${indent}    <span class="hud-label block mb-1.5">{{ ${entry.label} }}</span>`
    const original = `${indent}<div class="${file.wrapperClass}">
${indent}  <label :for="${entry.controlId}">
${labelSource}${shiftedControls}
${indent}  </label>${errors}
${indent}</div>`

    reconstructed =
      reconstructed.slice(0, start) + original + reconstructed.slice(end + closing.length)
  }

  assert.equal(occurrences(reconstructed, "CadenceField"), 0, `${file.name}: inverse is complete`)
  return reconstructed
}

for (const file of loadedFiles) {
  const {component, descriptor, source} = file.loaded

  assert.equal(typeof component.setup, "function", `${file.name}: real SFC compiles with local resolvers`)
  assert.ok(descriptor.scriptSetup, `${file.name}: setup script remains present`)
  assert.ok(descriptor.template, `${file.name}: template remains present`)
  assert.equal(occurrences(source, cadenceFieldImport), 1, `${file.name}: one real CadenceField import`)
  assert.equal(
    occurrences(source, "<CadenceField\n"),
    file.expectedFrames,
    `${file.name}: exact CadenceField opening-frame count`,
  )
  assert.equal(
    occurrences(source, "</CadenceField>"),
    file.expectedFrames,
    `${file.name}: exact CadenceField closing-frame count`,
  )
  assert.equal(file.fields.length, file.expectedFrames, `${file.name}: every frame is ledgered`)
  assert.doesNotMatch(
    source,
    /<div class="fieldset(?: mb-3)?">\n\s*<label :for=/,
    `${file.name}: no eligible literal standard shell remains`,
  )

  assert.equal(
    sha256(reconstructSource(file, source)),
    file.headSha256,
    `${file.name}: inverse migration reconstructs the HEAD source byte-for-byte`,
  )
}

const sourceFor = (name) => loadedFiles.find((file) => file.name === name).loaded.source
const telemetrySource = sourceFor("OpsTelemetryExplore.vue")
const policySource = sourceFor("OpsFleetPlanningPolicy.vue")
const newSource = sourceFor("OpsFleetPlanningNew.vue")
const runSource = sourceFor("OpsFleetPlanningRun.vue")

assert.equal(
  telemetrySource.match(/<input v-model="filterValues\.[^"]+" type="hidden" name="explore\[[^\]]+\]">/g)?.length,
  9,
  "telemetry hidden reconciliation inputs remain caller-owned",
)
assert.match(
  policySource,
  /<div\n\s+v-for="fieldKey in searchPolicyFieldKeys"\n\s+:key="policy_form\.fields\[fieldKey\]\.id"\n\s+class="fieldset mb-3"\n\s+>\n\s+<label :for="policy_form\.fields\[fieldKey\]\.id">/,
  "the nonliteral search-policy loop remains manual",
)
assert.match(
  policySource,
  /<div\n\s+v-for="fieldKey in automationPolicyFieldKeys"\n\s+:key="policy_form\.fields\[fieldKey\]\.id"\n\s+class="fieldset mb-3"\n\s+>\n\s+<label :for="policy_form\.fields\[fieldKey\]\.id">/,
  "the nonliteral automation-policy loop remains manual",
)
assert.match(
  policySource,
  /<div v-if="policy\.automation_mode !== 'advisory'" class="fieldset mb-3">\n\s+<label class="flex cursor-pointer items-start gap-3">\n\s+<input type="hidden" :name="policy_form\.fields\.automatic_submission\.name" value="false">/,
  "the conditional checkbox hidden-false pair remains manual",
)
assert.match(
  policySource,
  /v-for="fieldKey in redundancyPolicyFieldKeys"[\s\S]*?class="fieldset mb-3"[\s\S]*?<label class="flex cursor-pointer items-start gap-3">[\s\S]*?<input type="hidden" :name="policy_form\.fields\[fieldKey\]\.name" value="false">/,
  "the redundancy checkbox hidden-false loop remains manual",
)
assert.match(
  newSource,
  /<div class="fieldset mb-3">\n\s+<label class="flex cursor-pointer items-start gap-3">\n\s+<input type="hidden" :name="form\.fields\.include_recurring\.name" value="false">/,
  "the new-run checkbox hidden-false pair remains manual",
)
assert.doesNotMatch(runSource, /<div class="fieldset mb-3">/, "repair-run has no residual literal shell")

dom.window.close()
console.log("field_telemetry_fleet_migration_test passed")
