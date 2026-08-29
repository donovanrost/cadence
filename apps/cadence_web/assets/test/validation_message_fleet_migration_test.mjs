import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  expectedNodeVersion,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"
import {peelCadenceInlineWarnings} from "./inline_warning_test_support.mjs"
import {
  opsViewportCallerNames,
  peelCadenceOpsViewport,
} from "./ops_viewport_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `fleet validation-message contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const inlineWarningClass = "border-l-2 border-warning px-3 text-xs text-warning"
const cadenceCollapsibleImports = Object.freeze([
  'import CadenceCollapsible from "./ui/reka/CadenceCollapsible.vue"\n',
  'import CadenceCollapsibleContent from "./ui/reka/CadenceCollapsibleContent.vue"\n',
  'import CadenceCollapsibleTrigger from "./ui/reka/CadenceCollapsibleTrigger.vue"\n',
])
const frozenPolicyDetailsOpening = '<details :open="policy_form.open">'
const validationImport =
  'import CadenceValidationMessage from "./ui/components/CadenceValidationMessage.vue"\n'
const cadenceDetailsFrameImport =
  'import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"\n'
const validationClass = "mt-1.5 text-sm text-error"
const countExact = (source, value) => source.split(value).length - 1
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
    assert.equal(countExact(source, importLine), 1, `${name}: exact collapsible import count`)
  }
  assert.equal(countExact(source, policyCollapsibleOpening), 1, `${name}: exact collapsible opening`)
  assert.equal(countExact(source, policyCollapsibleClosing), 1, `${name}: exact collapsible closing`)

  let peeled = source
  for (const importLine of cadenceCollapsibleImports) peeled = peeled.replace(importLine, "")
  peeled = peeled
    .replace(policyCollapsibleOpening, policyNativeOpening)
    .replace(policyCollapsibleClosing, "        </details>")

  assert.doesNotMatch(peeled, /CadenceCollapsible(?:Content|Trigger)?/)
  assert.equal(countExact(peeled, `        ${frozenPolicyDetailsOpening}`), 1)
  return peeled
}

const cadenceDetailsFrameCounts = Object.freeze({
  "OpsFleetPlanningNew.vue": 1,
  "OpsFleetPlanningPolicy.vue": 3,
})
const peelCadenceDetailsFrames = (source, expectedCount, label) => {
  const expectedImportCount = expectedCount > 0 ? 1 : 0

  assert.equal(countExact(source, cadenceDetailsFrameImport), expectedImportCount, `${label} details import count`)
  assert.equal(source.match(/<CadenceDetailsFrame\b/g)?.length ?? 0, expectedCount, `${label} details opening count`)
  assert.equal(countExact(source, "</CadenceDetailsFrame>"), expectedCount, `${label} details closing count`)

  const peeled = source
    .replace(cadenceDetailsFrameImport, "")
    .split("<CadenceDetailsFrame")
    .join("<details")
    .split("</CadenceDetailsFrame>")
    .join("</details>")

  assert.doesNotMatch(peeled, /CadenceDetailsFrame/)
  return peeled
}

const migration = (expression, indent, multiline = false) => ({
  expression,
  indent,
  multiline,
})

const files = [
  {
    name: "OpsFleetPlanningNew.vue",
    sha256: "89843f0cf1a384f9ad0146c02f14235c555427b666626f4c9da5bf9651b219f2",
    migrations: [
      migration("form.fields.horizon_start", 16, true),
      migration("form.fields.horizon_end", 16, true),
    ],
  },
  {
    name: "OpsFleetPlanningPolicy.vue",
    sha256: "15490978eb784f125e690d9db33f19ce020ac73f2af6bc2e6e1572aa88aba320",
    migrations: [
      migration("policy_form.fields[fieldKey]", 18, true),
      migration("policy_form.fields.max_contacts", 20),
      migration("policy_form.fields.max_estimated_cost_micros", 20),
      migration("policy_form.fields.currency", 20),
      migration("policy_form.fields.critical_contact_reserve", 20),
      migration("policy_form.fields.automation_mode", 20),
      migration("policy_form.fields[fieldKey]", 18),
      migration("approval_form.reason", 14),
      migration("grant_form.fields.service_identity_id", 16),
      migration("grant_form.fields.maximum_horizon_hours", 18),
      migration("grant_form.fields.maximum_contacts", 18),
      migration("grant_form.fields.maximum_execution_concurrency", 18),
      migration("grant_form.fields.valid_days", 18),
      migration("grant_form.fields.approval_reason", 16),
      migration("revocation_form.fields.automation_grant_id", 16),
      migration("revocation_form.fields.reason", 16),
    ],
  },
]

assert.equal(
  files.reduce((total, file) => total + file.migrations.length, 0),
  18,
  "the frozen fleet validation-message ledger remains exactly 2 + 16",
)

const loadedSources = await Promise.all(
  files.map(async (file) => ({
    ...file,
    path: resolve(testDirectory, `../vue/${file.name}`),
    source: await readFile(resolve(testDirectory, `../vue/${file.name}`), "utf8"),
  })),
)

const migrationSource = ({expression, indent, multiline}, tag, includeClass) => {
  const spaces = " ".repeat(indent)
  const classSource = includeClass ? ` class="${validationClass}"` : ""

  if (!multiline) {
    return `${spaces}<${tag} v-for="error in ${expression}.errors" :key="error"${classSource}>{{ error }}</${tag}>`
  }

  const classLine = includeClass ? `\n${spaces}  class="${validationClass}"` : ""
  return `${spaces}<${tag}
${spaces}  v-for="error in ${expression}.errors"
${spaces}  :key="error"${classLine}
${spaces}>{{ error }}</${tag}>`
}

const reconstructPredecessor = (file) => {
  const opsViewportCompatibleSource = opsViewportCallerNames.includes(file.name)
    ? peelCadenceOpsViewport(file.source, file.name)
    : file.source
  assert.equal(countExact(file.source, validationImport), 1, `${file.name}: exact import count`)
  let reconstructed = peelCadenceDetailsFrames(
    peelCadenceCollapsible(
      peelCadenceInlineWarnings(opsViewportCompatibleSource, file.name),
      file.name,
    ),
    cadenceDetailsFrameCounts[file.name],
    file.name,
  ).replace(validationImport, "")

  for (const [index, entry] of file.migrations.entries()) {
    const migrated = migrationSource(entry, "CadenceValidationMessage", false)
    const predecessor = migrationSource(entry, "p", true)
    const label = `${file.name}: validation-message site ${index + 1}`

    assert.equal(countExact(reconstructed, migrated), 1, `${label} is byte-pinned`)
    reconstructed = reconstructed.replace(migrated, predecessor)
  }

  assert.equal(
    countExact(reconstructed, "CadenceValidationMessage"),
    0,
    `${file.name}: validation-message inverse is complete`,
  )
  return reconstructed
}

for (const file of loadedSources) {
  assert.equal(countExact(file.source, validationImport), 1, `${file.name}: one local import`)
  assert.equal(
    countExact(file.source, "<CadenceValidationMessage"),
    file.migrations.length,
    `${file.name}: exact migrated opening count`,
  )
  assert.equal(
    countExact(file.source, "</CadenceValidationMessage>"),
    file.migrations.length,
    `${file.name}: exact migrated closing count`,
  )
  assert.equal(
    countExact(file.source, validationClass),
    0,
    `${file.name}: no caller-owned validation class remains after the transparent migration`,
  )
  assert.equal(
    sha256(reconstructPredecessor(file)),
    file.sha256,
    `${file.name}: all validation-message sites reconstruct the exact predecessor bytes`,
  )
}

const dom = installDom(
  [
    '<div id="fleet-new-contract"></div>',
    '<div id="fleet-policy-contract"></div>',
    '<div id="fleet-policy-warning-contract"></div>',
  ].join(""),
)
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

const components = Object.fromEntries(
  await Promise.all(
    loadedSources.map(async (file) => [file.name, (await loadSfc(file.path)).component]),
  ),
)
const {createApp} = integrationRequire("vue")

const formField = (
  namespace,
  key,
  {type = "number", value = "1", errors = [], options = []} = {},
) => ({
  id: `${namespace}-${key}`,
  name: `${namespace}[${key}]`,
  type,
  label: `${namespace} ${key}`,
  required: true,
  min: 0,
  options,
  value,
  errors,
})

const checkboxField = (namespace, key) => ({
  id: `${namespace}-${key}`,
  name: `${namespace}[${key}]`,
  type: "checkbox",
  label: `${namespace} ${key}`,
  value: false,
  errors: [],
})

const newErrors = ["new horizon start error", "new horizon end error"]
const newProps = {
  header: {
    id: "fleet-new-page",
    back: {id: "fleet-new-back", label: "Back", icon: "hero-arrow-left"},
    title: "Plan fleet run",
    copy: "Server-owned fleet run copy",
  },
  policy_state: {active: true, required: null},
  form: {
    id: "fleet-new-form",
    fields: {
      horizon_start: {
        ...formField("fleet_run", "horizon_start", {
          type: "datetime-local",
          value: "2026-08-28T10:00",
          errors: [newErrors[0]],
        }),
      },
      horizon_end: {
        ...formField("fleet_run", "horizon_end", {
          type: "datetime-local",
          value: "2026-08-28T11:00",
          errors: [newErrors[1]],
        }),
      },
      include_recurring: checkboxField("fleet_run", "include_recurring"),
    },
    snapshot: {label: "Snapshot", copy: "Immutable snapshot"},
    submit: {id: "fleet-new-submit", label: "Create"},
  },
  preview: null,
  paths: {planning: "/ops/fleet", policy: "/ops/fleet/policy"},
}

const policyErrors = [
  "policy search-loop error",
  "policy max-contacts error",
  "policy max-cost error",
  "policy currency error",
  "policy reserve error",
  "policy automation-mode error",
  "policy automation-loop error",
  "policy approval error",
  "grant service error",
  "grant horizon error",
  "grant contacts error",
  "grant concurrency error",
  "grant days error",
  "grant approval error",
  "revocation grant error",
  "revocation reason error",
]

const policyFields = {
  max_horizon_hours: formField("policy", "max_horizon_hours", {errors: [policyErrors[0]]}),
  requirement_concurrency: formField("policy", "requirement_concurrency"),
  provider_search_concurrency: formField("policy", "provider_search_concurrency"),
  reuse_freshness_seconds: formField("policy", "reuse_freshness_seconds"),
  max_contacts: formField("policy", "max_contacts", {errors: [policyErrors[1]]}),
  max_estimated_cost_micros: formField("policy", "max_estimated_cost_micros", {
    errors: [policyErrors[2]],
  }),
  currency: formField("policy", "currency", {
    type: "text",
    value: "USD",
    errors: [policyErrors[3]],
  }),
  critical_contact_reserve: formField("policy", "critical_contact_reserve", {
    errors: [policyErrors[4]],
  }),
  automation_mode: formField("policy", "automation_mode", {
    type: "select",
    value: "advisory",
    options: [{label: "Advisory", value: "advisory"}],
    errors: [policyErrors[5]],
  }),
  execution_concurrency: formField("policy", "execution_concurrency", {
    errors: [policyErrors[6]],
  }),
  max_repair_attempts: formField("policy", "max_repair_attempts"),
  repair_horizon_hours: formField("policy", "repair_horizon_hours"),
  automatic_submission: checkboxField("policy", "automatic_submission"),
  distinct_provider_required: checkboxField("policy", "distinct_provider_required"),
  distinct_station_required: checkboxField("policy", "distinct_station_required"),
  distinct_service_pool_required: checkboxField("policy", "distinct_service_pool_required"),
}

const grantField = (key, options = {}) => formField("grant", key, options)
const revocationField = (key, options = {}) => formField("revocation", key, options)
const policyProps = {
  page: {
    back: {href: "/ops/fleet", icon: "hero-arrow-left", label: "Back"},
    header: {eyebrow: "Policy", title: "Fleet policy", copy: "Server-owned policy copy"},
    state: {id: "policy-state", label: "Draft", class: "badge"},
    manifest: {
      id: "policy-manifest",
      version_label: "v1",
      content_sha256: null,
      sections: [],
      empty: null,
    },
  },
  policy_form: {
    panel_id: "policy-form-panel",
    id: "policy-form",
    open: true,
    summary: "Edit policy",
    fields: policyFields,
    redundancy: {id: "policy-redundancy", summary: "Redundancy"},
    submit: {id: "policy-submit", label: "Save"},
  },
  approval_form: {
    panel_id: "approval-panel",
    id: "approval-form",
    reason: formField("approval", "reason", {
      type: "textarea",
      value: "approve",
      errors: [policyErrors[7]],
    }),
    submit: {id: "approval-submit", label: "Approve"},
  },
  authorization: {organization_admin: true, admin_required: null},
  grant_ledger: {
    id: "grant-ledger",
    list_id: "grant-list",
    empty: {id: "grant-empty", copy: "No grants"},
    active_count: 0,
    active_label: "0 active",
  },
  grant_form: {
    panel_id: "grant-panel",
    id: "grant-form",
    fields: {
      service_identity_id: grantField("service_identity_id", {
        type: "select",
        value: "service-1",
        options: [{label: "Service 1", value: "service-1"}],
        errors: [policyErrors[8]],
      }),
      maximum_horizon_hours: grantField("maximum_horizon_hours", {
        errors: [policyErrors[9]],
      }),
      maximum_contacts: grantField("maximum_contacts", {errors: [policyErrors[10]]}),
      maximum_execution_concurrency: grantField("maximum_execution_concurrency", {
        errors: [policyErrors[11]],
      }),
      valid_days: grantField("valid_days", {errors: [policyErrors[12]]}),
      approval_reason: grantField("approval_reason", {
        type: "textarea",
        value: "bounded authority",
        errors: [policyErrors[13]],
      }),
    },
    submit: {id: "grant-submit", label: "Issue"},
  },
  revocation_form: {
    panel_id: "revocation-panel",
    id: "revocation-form",
    fields: {
      automation_grant_id: revocationField("automation_grant_id", {
        type: "select",
        value: "grant-1",
        options: [{label: "Grant 1", value: "grant-1"}],
        errors: [policyErrors[14]],
      }),
      reason: revocationField("reason", {
        type: "textarea",
        value: "revoke",
        errors: [policyErrors[15]],
      }),
    },
    submit: {id: "revocation-submit", label: "Revoke"},
  },
  automation_grants: [],
}

const newApp = createApp(components["OpsFleetPlanningNew.vue"], newProps)
const policyApp = createApp(components["OpsFleetPlanningPolicy.vue"], policyProps)
newApp.mount(dom.window.document.querySelector("#fleet-new-contract"))
policyApp.mount(dom.window.document.querySelector("#fleet-policy-contract"))

const expectedMessages = [
  {text: newErrors[0], controlId: "fleet_run-horizon_start", tag: "INPUT"},
  {text: newErrors[1], controlId: "fleet_run-horizon_end", tag: "INPUT"},
  {text: policyErrors[0], controlId: "policy-max_horizon_hours", tag: "INPUT"},
  {text: policyErrors[1], controlId: "policy-max_contacts", tag: "INPUT"},
  {text: policyErrors[2], controlId: "policy-max_estimated_cost_micros", tag: "INPUT"},
  {text: policyErrors[3], controlId: "policy-currency", tag: "INPUT"},
  {text: policyErrors[4], controlId: "policy-critical_contact_reserve", tag: "INPUT"},
  {text: policyErrors[5], controlId: "policy-automation_mode", tag: "SELECT"},
  {text: policyErrors[6], controlId: "policy-execution_concurrency", tag: "INPUT"},
  {text: policyErrors[7], controlId: "approval-reason", tag: "TEXTAREA"},
  {text: policyErrors[8], controlId: "grant-service_identity_id", tag: "SELECT"},
  {text: policyErrors[9], controlId: "grant-maximum_horizon_hours", tag: "INPUT"},
  {text: policyErrors[10], controlId: "grant-maximum_contacts", tag: "INPUT"},
  {
    text: policyErrors[11],
    controlId: "grant-maximum_execution_concurrency",
    tag: "INPUT",
  },
  {text: policyErrors[12], controlId: "grant-valid_days", tag: "INPUT"},
  {text: policyErrors[13], controlId: "grant-approval_reason", tag: "TEXTAREA"},
  {text: policyErrors[14], controlId: "revocation-automation_grant_id", tag: "SELECT"},
  {text: policyErrors[15], controlId: "revocation-reason", tag: "TEXTAREA"},
]
const messages = [
  ...dom.window.document.querySelectorAll("p.mt-1\\.5.text-sm.text-error"),
]

assert.equal(messages.length, 18, "the actual compiled fleet SFCs mount exactly 18 messages")
assert.deepEqual(
  messages.map((message) => message.textContent),
  expectedMessages.map(({text}) => text),
  "every source site renders its caller-owned slot text in document order",
)

for (const [index, expected] of expectedMessages.entries()) {
  const message = messages[index]
  const control = dom.window.document.getElementById(expected.controlId)
  const label = message.previousElementSibling

  assert.equal(
    message.outerHTML,
    `<p class="${validationClass}">${expected.text}</p>`,
    `${expected.text}: the migration adds no wrapper or slot anchor`,
  )
  assert.equal(message.attributes.length, 1, `${expected.text}: only the exact class is present`)
  assert.ok(control, `${expected.text}: the caller-owned native control remains mounted`)
  assert.equal(control.tagName, expected.tag, `${expected.text}: native control kind is unchanged`)
  assert.equal(label?.tagName, "LABEL", `${expected.text}: native label remains the prior sibling`)
  assert.equal(label?.htmlFor, expected.controlId, `${expected.text}: native label/control IDREF remains`)
  assert.ok(label?.contains(control), `${expected.text}: native control identity remains caller-owned`)
}

const policyHost = dom.window.document.querySelector("#fleet-policy-contract")
assert.equal(
  policyHost.querySelector(`p[class="${inlineWarningClass}"]`),
  null,
  "the actual admin policy caller omits the inline authorization warning",
)

const policyWarningApp = createApp(components["OpsFleetPlanningPolicy.vue"], {
  ...policyProps,
  policy_form: null,
  approval_form: null,
  authorization: {
    organization_admin: false,
    admin_required: {
      copy: "Organization administrator authority is required to change policy or grants.",
    },
  },
  grant_form: null,
  revocation_form: null,
})
const policyWarningHost = dom.window.document.querySelector("#fleet-policy-warning-contract")
policyWarningApp.mount(policyWarningHost)

const policyWarning = policyWarningHost.querySelector(`p[class="${inlineWarningClass}"]`)
assert.ok(policyWarning instanceof dom.window.HTMLParagraphElement)
assert.equal(policyWarning.hasAttribute("id"), false, "the fleet warning deliberately remains ID-less")
assert.equal(policyWarning.attributes.length, 1)
assert.equal(
  policyWarning.textContent,
  "Organization administrator authority is required to change policy or grants.",
)

newApp.unmount()
policyApp.unmount()
policyWarningApp.unmount()
assert.equal(dom.window.document.querySelectorAll("p.mt-1\\.5.text-sm.text-error").length, 0)
dom.window.close()

console.log(
  "validation_message_fleet_migration_test passed (18 exact sites across 2 SFCs, authorization warning)",
)
