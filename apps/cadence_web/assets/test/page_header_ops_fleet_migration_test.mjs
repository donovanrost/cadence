import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import test from "node:test"

assert.equal(
  process.versions.node,
  "24.16.0",
  "page-header migration test must run with pinned Node 24.16.0"
)

const parent = "4a087fc3426b3b21d7c447152e444752947da692"
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
  ["OpsFleetPlanningNew.vue", 2],
  ["OpsFleetPlanningPolicy.vue", 16]
])
const componentImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"'
const rawOpening =
  '<header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">'

const field = (expression, indent, {errors = false, multilineLabel = false} = {}) => ({
  expression,
  indent,
  errors,
  multilineLabel
})

const callers = [
  {
    file: "OpsFleetPlanningNew.vue",
    sha256: "2d59cf31792eca1f2ce3a6a681dc908883f1fa22ff6747c58831a7d7fd30edc6",
    indent: "    ",
    fields: [
      field("form.fields.horizon_start", 12, {errors: true}),
      field("form.fields.horizon_end", 12, {errors: true})
    ]
  },
  {
    file: "OpsFleetPlanningPolicy.vue",
    sha256: "a94e136f6fc5aa1948f6e49c3542ee7b9cab06fdc1875595fde5ac6da47eb597",
    indent: "  ",
    fields: [
      field("policy_form.fields.max_contacts", 16, {errors: true}),
      field("policy_form.fields.max_estimated_cost_micros", 16, {errors: true}),
      field("policy_form.fields.currency", 16, {errors: true}),
      field("policy_form.fields.critical_contact_reserve", 16, {errors: true}),
      field("policy_form.fields.automation_mode", 16, {errors: true}),
      field("approval_form.reason", 10, {errors: true}),
      field("grant_form.fields.service_identity_id", 12, {errors: true}),
      field("grant_form.fields.maximum_horizon_hours", 14, {errors: true}),
      field("grant_form.fields.maximum_contacts", 14, {errors: true}),
      field("grant_form.fields.maximum_execution_concurrency", 14, {errors: true}),
      field("grant_form.fields.valid_days", 14, {errors: true}),
      field("grant_form.fields.approval_reason", 12, {errors: true}),
      field("revocation_form.fields.automation_grant_id", 12, {errors: true}),
      field("revocation_form.fields.reason", 12, {errors: true})
    ]
  },
  {
    file: "OpsCommands.vue",
    sha256: "a67c549398fe9ff931dacf29ba8df9a77a5368f3ec017382159f42d857082d72",
    indent: "    "
  },
  {
    file: "OpsDashboardActivity.vue",
    sha256: "168768d85b04fd897070e2b32e82cc086e048f60d72ede368e2072102cd7c903",
    indent: "  ",
    migratedOpening: '  <CadencePageHeaderFrame v-if="surface === \'header\'" variant="ops">',
    parentOpening: `  <header
    v-if="surface === 'header'"
    class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7"
  >`
  },
  {
    file: "OpsFleetPlanning.vue",
    sha256: "b08d522dbcb02d1c9517b880f42f6fe81cac20d764726d2ac41d030b126282cb",
    indent: "    "
  },
  {
    file: "OpsFleetPlanningRun.vue",
    sha256: "bc18a24b2cfa2f3c829233af17ba68eff049eaf1f79e8a74db4b42d7575ca1ce",
    indent: "    ",
    fields: [
      field("repair_form.fields.horizon_start", 14, {multilineLabel: true}),
      field("repair_form.fields.horizon_end", 14, {multilineLabel: true})
    ]
  },
  {
    file: "OpsDashboardDirectory.vue",
    sha256: "bd99244b3b4fc0317c698edb691496e3a37aa59b346aeb690dc3b1b6a4f72449",
    indent: "    "
  },
  {
    file: "OpsDashboardSettings.vue",
    sha256: "543079a9f03969da1fdc425a6907f44b684a919dffa11a1c7632da65623f6112",
    indent: "    ",
    fields: [
      field("settings_form.fields.name", 10),
      field("settings_form.fields.description", 10, {multilineLabel: true}),
      field("settings_form.fields.tags", 10),
      field("settings_form.fields.defaults_json", 10, {multilineLabel: true}),
      field("share_form.fields.data_visibility", 12, {multilineLabel: true}),
      field("share_form.fields.expires_in_hours", 12, {multilineLabel: true}),
      field("snapshot_form.fields.data_visibility", 12, {multilineLabel: true})
    ]
  }
]

const occurrences = (source, token) => source.split(token).length - 1
const sha256 = source => createHash("sha256").update(source).digest("hex")
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
  "the retired policy details opening remains frozen byte-for-byte"
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

const cadenceDetailsFrameCounts = Object.freeze({
  "OpsCommands.vue": 1,
  "OpsFleetPlanningNew.vue": 1,
  "OpsFleetPlanningPolicy.vue": 3,
  "OpsFleetPlanningRun.vue": 1
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

const peelCadenceValidationMessages = (source, name) => {
  const expectedMessages = cadenceValidationMessageCounts.get(name) ?? 0
  const expectedImports = expectedMessages > 0 ? 1 : 0

  assert.equal(
    occurrences(source, cadenceValidationMessageImport),
    expectedImports,
    `${name}: exact CadenceValidationMessage import count before peeling`
  )
  assert.equal(
    occurrences(source, "<CadenceValidationMessage"),
    expectedMessages,
    `${name}: exact CadenceValidationMessage opening count before peeling`
  )
  assert.equal(
    occurrences(source, "</CadenceValidationMessage>"),
    expectedMessages,
    `${name}: exact CadenceValidationMessage closing count before peeling`
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
      }
    )
    .replaceAll("</CadenceValidationMessage>", "</p>")

  assert.equal(replacements, expectedMessages, `${name}: every validation message is peeled`)
  assert.equal(
    occurrences(predecessorCompatibleSource, "CadenceValidationMessage"),
    0,
    `${name}: predecessor source has no residual CadenceValidationMessage`
  )

  return predecessorCompatibleSource
}

const peelCadenceFields = (source, caller) => {
  const fields = caller.fields ?? []
  const expectedImportCount = fields.length > 0 ? 1 : 0

  assert.equal(
    occurrences(source, cadenceFieldImport),
    expectedImportCount,
    `${caller.file}: exact CadenceField import count before peeling`
  )
  assert.equal(
    occurrences(source, "<CadenceField\n"),
    fields.length,
    `${caller.file}: exact CadenceField opening count before peeling`
  )
  assert.equal(
    occurrences(source, "</CadenceField>"),
    fields.length,
    `${caller.file}: exact CadenceField closing count before peeling`
  )

  let predecessorCompatibleSource = source.replace(cadenceFieldImport, "")

  for (const entry of fields) {
    const spaces = " ".repeat(entry.indent)
    const migratedOpening = `${spaces}<CadenceField
${spaces}  :control-id="${entry.expression}.id"
${spaces}  wrapper-class="fieldset mb-3"
${spaces}  :label="${entry.expression}.label"
${spaces}  label-class="hud-label block mb-1.5"
${spaces}>`
    const migratedClosing = `\n${spaces}</CadenceField>`

    assert.equal(
      occurrences(predecessorCompatibleSource, migratedOpening),
      1,
      `${caller.file}: ${entry.expression} has one exact CadenceField opening`
    )

    const start = predecessorCompatibleSource.indexOf(migratedOpening)
    const closeStart = predecessorCompatibleSource.indexOf(
      migratedClosing,
      start + migratedOpening.length
    )
    assert.notEqual(
      closeStart,
      -1,
      `${caller.file}: ${entry.expression} has one CadenceField closing`
    )

    let controls = predecessorCompatibleSource.slice(
      start + migratedOpening.length,
      closeStart
    )
    let errors = ""

    if (entry.errors) {
      const errorsOpen = `\n${spaces}  <template #errors>`
      const errorsClose = `\n${spaces}  </template>`
      const errorsStart = controls.lastIndexOf(errorsOpen)

      assert.notEqual(
        errorsStart,
        -1,
        `${caller.file}: ${entry.expression} keeps its exact error slot`
      )
      assert.ok(
        controls.endsWith(errorsClose),
        `${caller.file}: ${entry.expression} error slot closes last`
      )

      errors = controls
        .slice(errorsStart + errorsOpen.length, -errorsClose.length)
        .replaceAll(`\n${spaces}    `, `\n${spaces}  `)
      controls = controls.slice(0, errorsStart)
    } else {
      assert.doesNotMatch(controls, /<template #errors>/)
    }

    const shiftedControls = controls.replaceAll(`\n${spaces}  `, `\n${spaces}    `)
    const label = entry.multilineLabel
      ? `${spaces}    <span class="hud-label block mb-1.5">
${spaces}      {{ ${entry.expression}.label }}
${spaces}    </span>`
      : `${spaces}    <span class="hud-label block mb-1.5">{{ ${entry.expression}.label }}</span>`
    const original = `${spaces}<div class="fieldset mb-3">
${spaces}  <label :for="${entry.expression}.id">
${label}${shiftedControls}
${spaces}  </label>${errors}
${spaces}</div>`

    predecessorCompatibleSource =
      predecessorCompatibleSource.slice(0, start) +
      original +
      predecessorCompatibleSource.slice(closeStart + migratedClosing.length)
  }

  assert.equal(
    occurrences(predecessorCompatibleSource, "CadenceField"),
    0,
    `${caller.file}: predecessor source has no residual CadenceField`
  )

  return predecessorCompatibleSource
}

for (const caller of callers) {
  test(`${caller.file} has one ops page-header frame and reconstructs ${parent}`, async () => {
    const source = await readFile(new URL(`../vue/${caller.file}`, import.meta.url), "utf8")
    const migratedOpening =
      caller.migratedOpening ?? `${caller.indent}<CadencePageHeaderFrame variant="ops">`
    const parentOpening = caller.parentOpening ?? `${caller.indent}${rawOpening}`
    const migratedClosing = `${caller.indent}</CadencePageHeaderFrame>`
    const parentClosing = `${caller.indent}</header>`

    assert.equal(occurrences(source, componentImport), 1, "expected exactly one frame import")
    assert.equal(occurrences(source, "<CadencePageHeaderFrame"), 1, "expected one frame opening")
    assert.equal(occurrences(source, migratedOpening), 1, "expected the exact ops frame opening")
    assert.equal(occurrences(source, migratedClosing), 1, "expected one frame closing")
    assert.equal(occurrences(source, 'variant="ops"'), 1, "expected one ops variant")
    assert.doesNotMatch(source, /<header\b/, "expected no residual native header")

    const predecessorCompatibleSource = peelCadenceFields(
      peelCadenceValidationMessages(
        peelCadenceDetailsFrames(
          peelCadenceCollapsible(source, caller.file),
          cadenceDetailsFrameCounts[caller.file] ?? 0,
          caller.file
        ),
        caller.file
      ),
      caller
    )
    const reconstructed = predecessorCompatibleSource
      .replace(`${componentImport}\n`, "")
      .replace(migratedOpening, parentOpening)
      .replace(migratedClosing, parentClosing)

    assert.equal(
      occurrences(reconstructed, "CadencePageHeaderFrame"),
      0,
      "reconstruction must reverse only this migration"
    )
    assert.equal(
      sha256(reconstructed),
      caller.sha256,
      `reconstructed source must match ${parent}:${caller.file}`
    )
  })
}
