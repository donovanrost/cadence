import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  expectedNodeVersion,
  flushVue,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"
import {
  conditionalKeyedCadenceFieldBoundaries,
  conditionalKeyedCadenceFieldCounts,
  conditionalKeyedFrozenHeadSha256,
  peelConditionalKeyedCadenceFields,
} from "./conditional_keyed_field_test_support.mjs"

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"

assert.equal(process.execPath, pinnedNode)
assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `conditional/keyed CadenceField contracts use pinned Node ${expectedNodeVersion}`,
)
assert.equal(conditionalKeyedCadenceFieldBoundaries.length, 9, "the owned cohort has nine boundaries")

const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueDirectory = resolve(testDirectory, "../vue")
const files = Object.freeze([
  "OpsContactRequirementTemplate.vue",
  "OpsDataOperations.vue",
  "OpsFleetPlanningPolicy.vue",
  "OpsDashboardNew.vue",
])
const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const occurrences = (source, fragment) => source.split(fragment).length - 1
const phxAttributes = (source) =>
  source.match(/\b(?:phx-|data-phx-)[a-z-]+/g)?.sort() ?? []

const dom = installDom(
  [
    '<div id="contact-conditional-contract"></div>',
    '<div id="data-keyed-contract"></div>',
    '<div id="fleet-keyed-contract"></div>',
    '<div id="dashboard-conditional-contract"></div>',
  ].join(""),
)
for (const globalName of [
  "Document",
  "ShadowRoot",
  "HTMLAnchorElement",
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

const loaded = new Map(
  await Promise.all(
    files.map(async (file) => [file, await loadSfc(resolve(vueDirectory, file))]),
  ),
)
const {createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")

for (const file of files) {
  const {component, descriptor, source} = loaded.get(file)
  const predecessor = peelConditionalKeyedCadenceFields(source, file)

  assert.equal(typeof component.setup, "function", `${file}: the real caller SFC compiles`)
  assert.ok(descriptor.scriptSetup, `${file}: script setup remains real`)
  assert.ok(descriptor.template, `${file}: template remains real`)
  assert.equal(
    occurrences(source, 'import CadenceField from "./ui/components/CadenceField.vue"'),
    1,
    `${file}: the existing CadenceField import remains singular`,
  )
  assert.equal(
    sha256(predecessor),
    conditionalKeyedFrozenHeadSha256[file],
    `${file}: newest-first inverse reconstructs exact 9aa1522 source bytes`,
  )
  assert.deepEqual(
    phxAttributes(source),
    phxAttributes(predecessor),
    `${file}: the nine field boundaries gain or lose no PHX attributes`,
  )
}

const assertLegacyBoundary = (controlId, label, errors = []) => {
  const control = dom.window.document.getElementById(controlId)
  assert.ok(
    control instanceof dom.window.HTMLInputElement ||
      control instanceof dom.window.HTMLTextAreaElement,
    `${controlId}: caller-owned native control is mounted`,
  )

  const labelElement = control.parentElement
  const wrapper = labelElement?.parentElement
  assert.ok(labelElement instanceof dom.window.HTMLLabelElement, `${controlId}: label remains native`)
  assert.ok(wrapper instanceof dom.window.HTMLDivElement, `${controlId}: wrapper remains one div`)
  assert.equal(wrapper.className, "fieldset mb-3", `${controlId}: wrapper class is exact`)
  assert.equal(labelElement.htmlFor, controlId, `${controlId}: label association is exact`)
  assert.equal(labelElement.children.length, 2, `${controlId}: label has only span and control`)
  assert.strictEqual(labelElement.children[1], control, `${controlId}: caller control keeps DOM identity`)
  assert.deepEqual(
    [...wrapper.children].slice(1).map((element) => element.outerHTML),
    errors.map((error) => `<p class="mt-1.5 text-sm text-error">${error}</p>`),
    `${controlId}: caller-owned validation nodes keep order and shape`,
  )

  const expected =
    `<div class="fieldset mb-3"><label for="${controlId}">` +
    `<span class="hud-label block mb-1.5">${label}</span>${control.outerHTML}</label>` +
    errors.map((error) => `<p class="mt-1.5 text-sm text-error">${error}</p>`).join("") +
    "</div>"
  assert.equal(
    wrapper.outerHTML,
    expected,
    `${controlId}: migrated and predecessor serialized DOM are byte-identical`,
  )

  return control
}

const dispatchValue = async (control, value, eventType = "input") => {
  control.value = value
  control.dispatchEvent(new dom.window.Event(eventType, {bubbles: true}))
  await flushVue(nextTick)
}

const templateFields = Object.freeze([
  "spacecraft_id",
  "schedule_type",
  "anchor_at",
  "time_utc",
  "interval_minutes",
  "window_offset_minutes",
  "window_duration_minutes",
  "contact_intent",
  "success_measure",
  "minimum_duration_seconds",
  "preferred_duration_seconds",
  "minimum_data_volume_bytes",
  "contact_count",
  "minimum_separation_seconds",
  "priority",
  "approval_mode",
  "maximum_occurrences_per_run",
  "maximum_lookback_hours",
  "rationale",
])
const contactFieldTypes = Object.freeze({
  spacecraft_id: "select",
  schedule_type: "select",
  anchor_at: "datetime-local",
  time_utc: "time",
  interval_minutes: "number",
  window_offset_minutes: "number",
  window_duration_minutes: "number",
  contact_intent: "text",
  success_measure: "select",
  minimum_duration_seconds: "number",
  preferred_duration_seconds: "number",
  minimum_data_volume_bytes: "number",
  contact_count: "number",
  minimum_separation_seconds: "number",
  priority: "select",
  approval_mode: "select",
  maximum_occurrences_per_run: "number",
  maximum_lookback_hours: "number",
  rationale: "textarea",
})
const contactOptions = Object.freeze({
  spacecraft_id: [{label: "SC-1", value: "spacecraft-1"}],
  schedule_type: [
    {label: "Fixed interval", value: "fixed_interval"},
    {label: "Daily", value: "daily"},
  ],
  success_measure: [
    {label: "Minimum duration", value: "minimum_duration"},
    {label: "Minimum data volume", value: "minimum_data_volume"},
  ],
  priority: [{label: "High", value: "high"}],
  approval_mode: [{label: "Manual", value: "manual"}],
})
const contactValues = Object.fromEntries(
  templateFields.map((field) => [
    field,
    field === "spacecraft_id"
      ? "spacecraft-1"
      : field === "schedule_type"
        ? "fixed_interval"
        : field === "success_measure"
          ? "minimum_data_volume"
          : field === "priority"
            ? "high"
            : field === "approval_mode"
              ? "manual"
              : contactFieldTypes[field] === "number"
                ? "1"
                : "server-value",
  ]),
)
const contactErrorFields = new Set([
  "interval_minutes",
  "time_utc",
  "minimum_duration_seconds",
  "minimum_data_volume_bytes",
])
const contactProps = {
  page: {
    id: "contact-template-page",
    back: {href: "/ops/contact-requirements", icon: "icon-back", label: "Back"},
    header: {eyebrow: "Ops", title: "Contact templates", copy: "Server copy"},
  },
  ledger: {
    eyebrow: "Templates",
    copy: "Server ledger copy",
    count: 0,
    count_label: "0 templates",
    list_id: "contact-template-list",
    stream_empty_id: "contact-template-empty",
    empty: null,
  },
  authorization: {organization_admin: true, admin_required: null},
  template_form: {
    panel_id: "contact-template-panel",
    id: "contact-template-form",
    header: {eyebrow: "Create", copy: "Server form copy"},
    fields: Object.fromEntries(
      templateFields.map((field) => [
        field,
        {
          id: `contact-${field}`,
          name: `template[${field}]`,
          type: contactFieldTypes[field],
          label: `Label ${field}`,
          required: ["interval_minutes", "time_utc"].includes(field),
          min: contactFieldTypes[field] === "number" ? 1 : null,
          step: field === "time_utc" ? "60" : null,
          options: contactOptions[field] ?? [],
          value: contactValues[field],
          errors: contactErrorFields.has(field) ? [`error-${field}`] : [],
        },
      ]),
    ),
    outcome_details: {id: "contact-template-outcome", summary: "Outcome"},
    catchup_details: {id: "contact-template-catchup", summary: "Catchup"},
    submit: {id: "contact-template-submit", label: "Create template"},
  },
  templates: [],
}

const requestKeys = Object.freeze([
  "workflow",
  "run_id",
  "realm",
  "data_source_id",
  "source_binding_id",
  "point_ids",
  "source_from",
  "source_to",
  "reason",
  "confirmed",
])
const primaryRequestFieldKeys = Object.freeze([
  "run_id",
  "realm",
  "data_source_id",
  "source_binding_id",
  "point_ids",
])
const sourceRangeFieldKeys = Object.freeze(["source_from", "source_to"])
const requestForm = ({values = {}, ids = {}} = {}) => ({
  id: "historical-request-form",
  values: Object.fromEntries(
    requestKeys.map((key) => [
      key,
      values[key] ?? (key === "workflow" ? "repair" : key === "confirmed" ? "false" : `${key}-value`),
    ]),
  ),
  fields: Object.fromEntries(
    requestKeys.map((key) => [
      key,
      {
        id: ids[key] ?? `request-${key}`,
        name: `historical_workflow_request[${key}]`,
        type: key === "workflow" ? "select" : key === "confirmed" ? "checkbox" : "text",
        label: `Label ${key}`,
        placeholder: primaryRequestFieldKeys.includes(key) ? `Placeholder ${key}` : null,
        options: key === "workflow" ? [{label: "Repair", value: "repair"}] : [],
      },
    ]),
  ),
  hidden_fields: [],
  error: null,
  submit: {id: "historical-request-submit", label: "Record request"},
})
const dataPage = {
  id: "data-operations-page",
  selected_group_id: null,
  groups_empty: true,
  navigation: {},
}

const policyField = (
  key,
  {id = `policy-${key}`, type = "number", value = "1", required = true, min = 0} = {},
) => ({
  id,
  name: `policy[${key}]`,
  type,
  label: `Label ${key}`,
  required,
  min,
  options:
    type === "select"
      ? [
          {label: "Advisory", value: "advisory"},
          {label: "Bounded automatic", value: "bounded_automatic"},
        ]
      : [],
  value,
  errors:
    [...searchPolicyFieldKeys, ...automationPolicyFieldKeys].includes(key)
      ? [`error-${key}`]
      : [],
})
const policyCheckbox = (key, value) => ({
  id: `policy-${key}`,
  name: `policy[${key}]`,
  type: "checkbox",
  label: `Label ${key}`,
  value,
  errors: [],
})
const searchPolicyFieldKeys = Object.freeze([
  "max_horizon_hours",
  "requirement_concurrency",
  "provider_search_concurrency",
  "reuse_freshness_seconds",
])
const automationPolicyFieldKeys = Object.freeze([
  "execution_concurrency",
  "max_repair_attempts",
  "repair_horizon_hours",
])
const policyForm = ({values = {}, ids = {}} = {}) => {
  const field = (key, options = {}) =>
    policyField(key, {
      ...options,
      id: ids[key] ?? options.id ?? `policy-${key}`,
      value: values[key] ?? options.value ?? "1",
    })

  return {
    panel_id: "fleet-policy-editor",
    id: "fleet-policy-form",
    open: true,
    summary: "Create policy",
    fields: {
      max_horizon_hours: field("max_horizon_hours", {min: 1}),
      requirement_concurrency: field("requirement_concurrency", {min: 1}),
      provider_search_concurrency: field("provider_search_concurrency", {min: 1}),
      reuse_freshness_seconds: field("reuse_freshness_seconds"),
      max_contacts: field("max_contacts", {min: 1}),
      max_estimated_cost_micros: field("max_estimated_cost_micros", {required: false}),
      currency: field("currency", {type: "text", value: "USD", required: false, min: null}),
      critical_contact_reserve: field("critical_contact_reserve"),
      automation_mode: field("automation_mode", {
        type: "select",
        value: "bounded_automatic",
        required: false,
        min: null,
      }),
      execution_concurrency: field("execution_concurrency", {min: 1}),
      max_repair_attempts: field("max_repair_attempts"),
      repair_horizon_hours: field("repair_horizon_hours", {min: 1}),
      automatic_submission: policyCheckbox("automatic_submission", true),
      distinct_provider_required: policyCheckbox("distinct_provider_required", true),
      distinct_station_required: policyCheckbox("distinct_station_required", false),
      distinct_service_pool_required: policyCheckbox("distinct_service_pool_required", true),
    },
    redundancy: {id: "fleet-policy-redundancy", summary: "Redundancy"},
    submit: {id: "fleet-policy-submit", label: "Save policy"},
  }
}
const fleetStaticProps = {
  page: {
    back: {href: "/ops/planning", icon: "icon-back", label: "Back"},
    header: {eyebrow: "Policy", title: "Fleet policy", copy: "Server copy"},
    state: {id: "fleet-policy-state", label: "Draft", class: "badge"},
    manifest: {
      id: "fleet-policy-manifest",
      version_label: "not configured",
      content_sha256: null,
      sections: [],
      empty: null,
    },
  },
  approval_form: null,
  authorization: {organization_admin: true, admin_required: null},
  grant_ledger: {
    id: "fleet-policy-grants",
    list_id: "fleet-policy-grant-list",
    empty: {id: "fleet-policy-grant-empty", copy: "No grants"},
    active_count: 0,
    active_label: "0 active",
  },
  grant_form: null,
  revocation_form: null,
  automation_grants: [],
}

const dashboardPage = {
  id: "dashboard-new-page",
  mode: "import",
  eyebrow: "Dashboard",
  heading: "Import dashboard",
  description: "Server copy",
  source: null,
  import_guidance: null,
  cancel: {id: "dashboard-cancel", label: "Cancel", href: "/dashboards"},
}
const dashboardForm = ({document = true, documentValue = '{"version":1}'} = {}) => ({
  id: "dashboard-form",
  name: {
    id: "dashboard-name",
    name: "dashboard[name]",
    type: "text",
    label: "Name",
    value: "Dashboard name",
    required: true,
  },
  description: {
    id: "dashboard-description",
    name: "dashboard[description]",
    type: "text",
    label: "Description",
    value: "Dashboard description",
    required: false,
  },
  document_json: document
    ? {
        id: "dashboard-document-json",
        name: "dashboard[document_json]",
        type: "textarea",
        label: "Dashboard document",
        value: documentValue,
        required: true,
      }
    : null,
  submit: {id: "dashboard-submit", label: "Save dashboard"},
})

const contactValidations = []
const dataValidations = []
const fleetValidations = []
const dashboardValidations = []
const currentRequestForm = ref(requestForm())
const currentPolicyForm = ref(policyForm())
const currentDashboardForm = ref(dashboardForm())

const DataOracle = defineComponent({
  setup() {
    return () =>
      h(loaded.get("OpsDataOperations.vue").component, {
        page: dataPage,
        request_form: currentRequestForm.value,
        selected_group: null,
        data_operation_groups: [],
        onValidateRequest: (payload) => dataValidations.push(payload),
      })
  },
})
const FleetOracle = defineComponent({
  setup() {
    return () =>
      h(loaded.get("OpsFleetPlanningPolicy.vue").component, {
        ...fleetStaticProps,
        policy_form: currentPolicyForm.value,
        onValidatePolicy: (payload) => fleetValidations.push(payload),
      })
  },
})
const DashboardOracle = defineComponent({
  setup() {
    return () =>
      h(loaded.get("OpsDashboardNew.vue").component, {
        page: dashboardPage,
        form: currentDashboardForm.value,
        onValidate: (payload) => dashboardValidations.push(payload),
      })
  },
})

const apps = [
  createApp(loaded.get("OpsContactRequirementTemplate.vue").component, {
    ...contactProps,
    onValidateTemplate: (payload) => contactValidations.push(payload),
  }),
  createApp(DataOracle),
  createApp(FleetOracle),
  createApp(DashboardOracle),
]
const hosts = [
  "contact-conditional-contract",
  "data-keyed-contract",
  "fleet-keyed-contract",
  "dashboard-conditional-contract",
]

try {
  for (const [index, app] of apps.entries()) {
    app.mount(dom.window.document.getElementById(hosts[index]))
    await flushVue(nextTick)
  }

  const interval = assertLegacyBoundary("contact-interval_minutes", "Label interval_minutes", [
    "error-interval_minutes",
  ])
  const minimumDuration = assertLegacyBoundary(
    "contact-minimum_duration_seconds",
    "Label minimum_duration_seconds",
    ["error-minimum_duration_seconds"],
  )
  const minimumVolume = assertLegacyBoundary(
    "contact-minimum_data_volume_bytes",
    "Label minimum_data_volume_bytes",
    ["error-minimum_data_volume_bytes"],
  )
  assert.equal(dom.window.document.getElementById("contact-time_utc"), null)

  await dispatchValue(interval, "17")
  assert.strictEqual(dom.window.document.getElementById("contact-interval_minutes"), interval)
  assert.equal(contactValidations.at(-1).template.interval_minutes, "17")
  await dispatchValue(minimumDuration, "31")
  assert.strictEqual(
    dom.window.document.getElementById("contact-minimum_duration_seconds"),
    minimumDuration,
  )
  assert.equal(contactValidations.at(-1).template.minimum_duration_seconds, "31")
  await dispatchValue(minimumVolume, "4096")
  assert.strictEqual(
    dom.window.document.getElementById("contact-minimum_data_volume_bytes"),
    minimumVolume,
  )
  assert.equal(contactValidations.at(-1).template.minimum_data_volume_bytes, "4096")

  const schedule = dom.window.document.getElementById("contact-schedule_type")
  await dispatchValue(schedule, "daily", "change")
  assert.equal(dom.window.document.getElementById("contact-interval_minutes"), null)
  const time = assertLegacyBoundary("contact-time_utc", "Label time_utc", ["error-time_utc"])
  await dispatchValue(time, "12:45")
  assert.strictEqual(dom.window.document.getElementById("contact-time_utc"), time)
  assert.equal(contactValidations.at(-1).template.time_utc, "12:45")
  await dispatchValue(schedule, "fixed_interval", "change")
  assert.equal(dom.window.document.getElementById("contact-time_utc"), null)
  const recreatedInterval = assertLegacyBoundary(
    "contact-interval_minutes",
    "Label interval_minutes",
    ["error-interval_minutes"],
  )
  assert.notStrictEqual(recreatedInterval, interval, "fixed interval removal recreates its native node")

  const successMeasure = dom.window.document.getElementById("contact-success_measure")
  await dispatchValue(successMeasure, "", "change")
  assert.equal(dom.window.document.getElementById("contact-minimum_duration_seconds"), null)
  assert.equal(dom.window.document.getElementById("contact-minimum_data_volume_bytes"), null)
  await dispatchValue(successMeasure, "minimum_data_volume", "change")
  assert.notStrictEqual(
    assertLegacyBoundary(
      "contact-minimum_duration_seconds",
      "Label minimum_duration_seconds",
      ["error-minimum_duration_seconds"],
    ),
    minimumDuration,
    "minimum-duration removal recreates its native node",
  )
  assert.notStrictEqual(
    assertLegacyBoundary(
      "contact-minimum_data_volume_bytes",
      "Label minimum_data_volume_bytes",
      ["error-minimum_data_volume_bytes"],
    ),
    minimumVolume,
    "minimum-volume removal recreates its native node",
  )

  const dataNodes = Object.fromEntries(
    [...primaryRequestFieldKeys, ...sourceRangeFieldKeys].map((key) => [
      key,
      assertLegacyBoundary(`request-${key}`, `Label ${key}`),
    ]),
  )
  await dispatchValue(dataNodes.run_id, "run-updated")
  assert.strictEqual(dom.window.document.getElementById("request-run_id"), dataNodes.run_id)
  assert.equal(
    dataValidations.at(-1).historical_workflow_request.run_id,
    "run-updated",
  )
  await dispatchValue(dataNodes.source_from, "2026-08-29T00:00:00Z")
  assert.strictEqual(dom.window.document.getElementById("request-source_from"), dataNodes.source_from)
  assert.equal(
    dataValidations.at(-1).historical_workflow_request.source_from,
    "2026-08-29T00:00:00Z",
  )

  const currentRequestValues = {
    run_id: "run-updated",
    source_from: "2026-08-29T00:00:00Z",
  }
  currentRequestForm.value = requestForm({values: currentRequestValues})
  await flushVue(nextTick)
  for (const [key, node] of Object.entries(dataNodes)) {
    assert.strictEqual(
      dom.window.document.getElementById(`request-${key}`),
      node,
      `${key}: same keyed request field retains native identity`,
    )
  }
  currentRequestForm.value = requestForm({
    values: currentRequestValues,
    ids: {run_id: "request-run_id-v2", source_from: "request-source_from-v2"},
  })
  await flushVue(nextTick)
  assert.equal(dom.window.document.getElementById("request-run_id"), null)
  assert.equal(dom.window.document.getElementById("request-source_from"), null)
  assert.notStrictEqual(dom.window.document.getElementById("request-run_id-v2"), dataNodes.run_id)
  assert.notStrictEqual(dom.window.document.getElementById("request-source_from-v2"), dataNodes.source_from)
  assert.strictEqual(dom.window.document.getElementById("request-realm"), dataNodes.realm)
  assert.strictEqual(dom.window.document.getElementById("request-source_to"), dataNodes.source_to)

  const fleetNodes = Object.fromEntries(
    [...searchPolicyFieldKeys, ...automationPolicyFieldKeys].map((key) => [
      key,
      assertLegacyBoundary(`policy-${key}`, `Label ${key}`, [`error-${key}`]),
    ]),
  )
  await dispatchValue(fleetNodes.max_horizon_hours, "33")
  assert.strictEqual(
    dom.window.document.getElementById("policy-max_horizon_hours"),
    fleetNodes.max_horizon_hours,
  )
  assert.equal(fleetValidations.at(-1).policy.max_horizon_hours, "33")
  await dispatchValue(fleetNodes.execution_concurrency, "7")
  assert.strictEqual(
    dom.window.document.getElementById("policy-execution_concurrency"),
    fleetNodes.execution_concurrency,
  )
  assert.equal(fleetValidations.at(-1).policy.execution_concurrency, "7")

  const currentPolicyValues = {max_horizon_hours: "33", execution_concurrency: "7"}
  currentPolicyForm.value = policyForm({values: currentPolicyValues})
  await flushVue(nextTick)
  for (const [key, node] of Object.entries(fleetNodes)) {
    assert.strictEqual(
      dom.window.document.getElementById(`policy-${key}`),
      node,
      `${key}: same keyed policy field retains native identity`,
    )
  }
  currentPolicyForm.value = policyForm({
    values: currentPolicyValues,
    ids: {
      max_horizon_hours: "policy-max_horizon_hours-v2",
      execution_concurrency: "policy-execution_concurrency-v2",
    },
  })
  await flushVue(nextTick)
  assert.equal(dom.window.document.getElementById("policy-max_horizon_hours"), null)
  assert.equal(dom.window.document.getElementById("policy-execution_concurrency"), null)
  assert.notStrictEqual(
    dom.window.document.getElementById("policy-max_horizon_hours-v2"),
    fleetNodes.max_horizon_hours,
  )
  assert.notStrictEqual(
    dom.window.document.getElementById("policy-execution_concurrency-v2"),
    fleetNodes.execution_concurrency,
  )
  assert.strictEqual(
    dom.window.document.getElementById("policy-requirement_concurrency"),
    fleetNodes.requirement_concurrency,
  )
  assert.strictEqual(
    dom.window.document.getElementById("policy-max_repair_attempts"),
    fleetNodes.max_repair_attempts,
  )

  const dashboardDocument = assertLegacyBoundary(
    "dashboard-document-json",
    "Dashboard document",
  )
  await dispatchValue(dashboardDocument, '{"updated":true}')
  assert.strictEqual(
    dom.window.document.getElementById("dashboard-document-json"),
    dashboardDocument,
  )
  assert.deepEqual(dashboardValidations.at(-1), {
    dashboard: {
      name: "Dashboard name",
      description: "Dashboard description",
      document_json: '{"updated":true}',
    },
  })
  currentDashboardForm.value = dashboardForm({document: false})
  await flushVue(nextTick)
  assert.equal(dom.window.document.getElementById("dashboard-document-json"), null)
  currentDashboardForm.value = dashboardForm({documentValue: '{"updated":true}'})
  await flushVue(nextTick)
  const recreatedDashboardDocument = assertLegacyBoundary(
    "dashboard-document-json",
    "Dashboard document",
  )
  assert.notStrictEqual(
    recreatedDashboardDocument,
    dashboardDocument,
    "dashboard conditional removal recreates its caller-owned textarea",
  )

  assert.equal(
    Object.values(conditionalKeyedCadenceFieldCounts).reduce((total, count) => total + count, 0),
    9,
    "all nine source boundaries are represented in the frozen inverse ledger",
  )
} finally {
  for (const app of apps.reverse()) app.unmount()
  dom.window.close()
}

console.log(
  "field_conditional_keyed_migration_test passed (9 boundaries, 4 real mounted SFCs, exact DOM, conditional and keyed identity)",
)
