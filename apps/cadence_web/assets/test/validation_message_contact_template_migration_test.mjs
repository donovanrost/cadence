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

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
const inlineWarningClass = "border-l-2 border-warning px-3 text-xs text-warning"

assert.equal(process.execPath, pinnedNode)
assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `contact-template validation migration uses pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/OpsContactRequirementTemplate.vue")
const source = await readFile(componentPath, "utf8")
const sha256 = (value) => createHash("sha256").update(value).digest("hex")
const occurrences = (value, fragment) => value.split(fragment).length - 1
const cadenceDetailsFrameImport =
  'import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"\n'
const validationMessageImport =
  'import CadenceValidationMessage from "./ui/components/CadenceValidationMessage.vue"\n'
const validationMessageSite =
  /^( *)<CadenceValidationMessage v-for="error in template_form\.fields\.([a-z_]+)\.errors" :key="error">\{\{ error \}\}<\/CadenceValidationMessage>$/gm
const peelCadenceDetailsFrames = (value) => {
  assert.equal(occurrences(value, cadenceDetailsFrameImport), 1, "details import count")
  assert.equal(value.match(/<CadenceDetailsFrame\b/g)?.length ?? 0, 2, "details opening count")
  assert.equal(occurrences(value, "</CadenceDetailsFrame>"), 2, "details closing count")

  const peeled = value
    .replace(cadenceDetailsFrameImport, "")
    .split("<CadenceDetailsFrame")
    .join("<details")
    .split("</CadenceDetailsFrame>")
    .join("</details>")

  assert.doesNotMatch(peeled, /CadenceDetailsFrame/)
  return peeled
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
  "minimum_data_volume_bytes",
  "contact_count",
  "minimum_separation_seconds",
  "priority",
  "approval_mode",
  "maximum_occurrences_per_run",
  "maximum_lookback_hours",
  "rationale",
  "preferred_duration_seconds",
])

const sites = [...source.matchAll(validationMessageSite)]

assert.equal(occurrences(source, validationMessageImport), 1, "one local primitive import")
assert.equal(occurrences(source, "<CadenceValidationMessage "), 19, "exactly 19 opens")
assert.equal(occurrences(source, "</CadenceValidationMessage>"), 19, "exactly 19 closes")
assert.equal(sites.length, 19, "all 19 sites retain the exact v-for, key, and slot text")
assert.deepEqual(
  sites.map((match) => match[2]).sort(),
  [...templateFields].sort(),
  "each template field owns exactly one validation-message site",
)
assert.equal(
  occurrences(source, 'class="mt-1.5 text-sm text-error"'),
  0,
  "the contact template keeps no residual literal validation paragraph",
)

validationMessageSite.lastIndex = 0
let reconstructedSites = 0
const predecessorSource = peelCadenceDetailsFrames(
  peelCadenceInlineWarnings(source, "OpsContactRequirementTemplate.vue"),
)
  .replace(validationMessageImport, "")
  .replace(validationMessageSite, (_match, indent, field) => {
    reconstructedSites += 1
    return `${indent}<p v-for="error in template_form.fields.${field}.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>`
  })

assert.equal(reconstructedSites, 19, "all 19 validation wrappers reconstruct mechanically")
assert.doesNotMatch(predecessorSource, /CadenceValidationMessage/)
assert.equal(
  sha256(predecessorSource),
  "a4c289089de045d778e77bea54045bda04e749db1e369a49923e2e09c6cb1144",
  "the exact 19-site predecessor source reconstructs byte-for-byte",
)

const dom = installDom(
  [
    '<div id="fixed-duration-contract"></div>',
    '<div id="daily-volume-contract"></div>',
    '<div id="contact-template-warning-contract"></div>',
  ].join(""),
)
const loaded = await loadSfc(componentPath)
const {createApp, nextTick} = integrationRequire("vue")
const fieldTypes = Object.freeze({
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
  minimum_data_volume_bytes: "number",
  contact_count: "number",
  minimum_separation_seconds: "number",
  priority: "select",
  approval_mode: "select",
  maximum_occurrences_per_run: "number",
  maximum_lookback_hours: "number",
  rationale: "textarea",
  preferred_duration_seconds: "number",
})
const selectOptions = Object.freeze({
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

const scenarioValues = (scheduleType, successMeasure) =>
  Object.fromEntries(
    templateFields.map((field) => [
      field,
      field === "spacecraft_id"
        ? "spacecraft-1"
        : field === "schedule_type"
          ? scheduleType
          : field === "success_measure"
            ? successMeasure
            : field === "priority"
              ? "high"
              : field === "approval_mode"
                ? "manual"
                : field === "rationale"
                  ? "Server rationale"
                  : fieldTypes[field] === "number"
                    ? "1"
                    : "server-value",
    ]),
  )

const scenarioProps = (scheduleType, successMeasure) => {
  const values = scenarioValues(scheduleType, successMeasure)
  const fields = Object.fromEntries(
    templateFields.map((field) => [
      field,
      {
        id: `contact-template-${field}`,
        name: `template[${field}]`,
        type: fieldTypes[field],
        label: `Label ${field}`,
        required: false,
        min: null,
        step: field === "time_utc" ? "60" : null,
        options: selectOptions[field] ?? [],
        value: values[field],
        errors: [`error-${field}`],
      },
    ]),
  )

  return {
    values,
    props: {
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
        fields,
        outcome_details: {id: "contact-template-outcome", summary: "Outcome"},
        catchup_details: {id: "contact-template-catchup", summary: "Catchup"},
        submit: {id: "contact-template-submit", label: "Create template"},
      },
      templates: [],
    },
  }
}

const visibleFields = (scheduleType, successMeasure) =>
  templateFields.filter((field) => {
    if (field === "interval_minutes") return scheduleType === "fixed_interval"
    if (field === "time_utc") return scheduleType === "daily"
    if (field === "minimum_data_volume_bytes") return successMeasure === "minimum_data_volume"
    return true
  })

const mountScenario = async (hostId, scheduleType, successMeasure) => {
  const {props, values} = scenarioProps(scheduleType, successMeasure)
  const validations = []
  const creations = []
  const host = dom.window.document.querySelector(`#${hostId}`)
  const app = createApp(loaded.component, {
    ...props,
    onValidateTemplate: (payload) => validations.push(payload),
    onCreateTemplate: (payload) => creations.push(payload),
  })

  app.mount(host)
  await nextTick()

  const expectedFields = visibleFields(scheduleType, successMeasure)
  const messages = [...host.querySelectorAll("p")].filter(
    (element) => element.getAttribute("class") === "mt-1.5 text-sm text-error",
  )

  assert.equal(messages.length, expectedFields.length)
  assert.deepEqual(
    messages.map((element) => element.textContent).sort(),
    expectedFields.map((field) => `error-${field}`).sort(),
  )

  for (const message of messages) {
    assert.equal(
      message.outerHTML,
      `<p class="mt-1.5 text-sm text-error">${message.textContent}</p>`,
      "the actual compiled consumer renders the exact predecessor paragraph DOM",
    )
  }

  assert.equal(host.querySelectorAll("form#contact-template-form").length, 1)
  for (const field of expectedFields) {
    const control = host.querySelector(`#contact-template-${field}`)
    assert.ok(control, `${field} keeps its native control ID`)
    assert.equal(control.getAttribute("name"), `template[${field}]`, `${field} keeps its name`)
  }

  assert.equal(
    host.querySelector("#requirement-template-admin-required"),
    null,
    "the actual admin caller omits the inline authorization warning",
  )

  return {app, creations, host, validations, values}
}

const mounted = []
let warningApp
try {
  const fixedDuration = await mountScenario(
    "fixed-duration-contract",
    "fixed_interval",
    "minimum_duration",
  )
  mounted.push(fixedDuration)
  const dailyVolume = await mountScenario(
    "daily-volume-contract",
    "daily",
    "minimum_data_volume",
  )
  mounted.push(dailyVolume)

  const mountedErrorFields = new Set(
    mounted.flatMap(({host}) =>
      [...host.querySelectorAll("p")]
        .filter((element) => element.getAttribute("class") === "mt-1.5 text-sm text-error")
        .map((element) => element.textContent.replace(/^error-/, "")),
    ),
  )
  assert.deepEqual(
    [...mountedErrorFields].sort(),
    [...templateFields].sort(),
    "the two mutually exclusive mounted states exercise all 19 sites",
  )

  const contactIntent = fixedDuration.host.querySelector("#contact-template-contact_intent")
  contactIntent.value = "updated-contact-intent"
  contactIntent.dispatchEvent(new dom.window.Event("input", {bubbles: true}))
  await nextTick()

  const expectedValues = {...fixedDuration.values, contact_intent: "updated-contact-intent"}
  assert.deepEqual(fixedDuration.validations, [{template: expectedValues}])

  const form = fixedDuration.host.querySelector("#contact-template-form")
  const submitEvent = new dom.window.Event("submit", {bubbles: true, cancelable: true})
  form.dispatchEvent(submitEvent)
  await nextTick()

  assert.equal(submitEvent.defaultPrevented, true)
  assert.deepEqual(fixedDuration.creations, [{template: expectedValues}])

  const {props: warningProps} = scenarioProps("fixed_interval", "minimum_duration")
  warningApp = createApp(loaded.component, {
    ...warningProps,
    authorization: {
      organization_admin: false,
      admin_required: {
        id: "requirement-template-admin-required",
        copy: "Organization administrator authority is required to manage recurring demand.",
      },
    },
    template_form: null,
  })
  const warningHost = dom.window.document.querySelector("#contact-template-warning-contract")
  warningApp.mount(warningHost)
  await nextTick()

  const warning = warningHost.querySelector("#requirement-template-admin-required")
  assert.ok(warning instanceof dom.window.HTMLParagraphElement)
  assert.equal(warning.className, inlineWarningClass)
  assert.equal(
    warning.textContent,
    "Organization administrator authority is required to manage recurring demand.",
  )
  assert.equal(warning.children.length, 0, "the warning copy remains a caller-owned text node")
} finally {
  warningApp?.unmount()
  for (const {app} of mounted) app.unmount()
  dom.window.close()
}

console.log(
  "validation_message_contact_template_migration_test passed (19 sites, exact predecessor, 2 mounted states, authorization warning)",
)
