import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  elementAttributes,
  expectedNodeVersion,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"
import {peelCadenceNoticeFrames} from "./notice_frame_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `Comms provider/routing CadenceField contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const breadcrumbsImport =
  'import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"\n'
const breadcrumbNavClass =
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
const providerPath = resolve(testDirectory, "../vue/CommsProviderNew.vue")
const routingPath = resolve(testDirectory, "../vue/CommsRoutingNew.vue")
const [providerSource, routingSource] = await Promise.all([
  readFile(providerPath, "utf8"),
  readFile(routingPath, "utf8"),
])
const pageHeaderImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const reconstructPageHeaderSource = (source) =>
  source
    .replace(pageHeaderImport, "")
    .replace(
      '<CadencePageHeaderFrame variant="compact">',
      '<header class="border-b border-primary/20 pb-4">',
    )
    .replace(
      '<CadencePageHeaderFrame variant="ops">',
      '<header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">',
    )
    .replace("</CadencePageHeaderFrame>", "</header>")

for (const source of [providerSource, routingSource]) {
  assert.match(source, /^import CadenceField from "\.\/ui\/components\/CadenceField\.vue"$/m)
  assert.match(source, /^import CadenceFormActions from "\.\/ui\/components\/CadenceFormActions\.vue"$/m)
  assert.match(
    source,
    /^import CadenceFormSectionHeader from "\.\/ui\/components\/CadenceFormSectionHeader\.vue"$/m,
  )
  assert.doesNotMatch(source, /(?:^|\s)class="fieldset mb-3"/)
}

assert.equal(providerSource.match(/<CadenceField\b/g)?.length, 5)
assert.equal(providerSource.match(/<CadenceFormSectionHeader\b/g)?.length, 3)
assert.equal(providerSource.match(/<CadenceFormActions\b/g)?.length, 1)
assert.equal(providerSource.match(/<input\b/g)?.length, 3)
assert.equal(providerSource.match(/<select\b/g)?.length, 3)
assert.equal(routingSource.match(/<CadenceField\b/g)?.length, 6)
assert.equal(routingSource.match(/<CadenceFormSectionHeader\b/g)?.length, 3)
assert.equal(routingSource.match(/<CadenceFormActions\b/g)?.length, 1)
assert.equal(routingSource.match(/<input\b/g)?.length, 2)
assert.equal(routingSource.match(/<select\b/g)?.length, 4)

const indentControl = (control) =>
  control
    .split("\n")
    .map((line) => `  ${line}`)
    .join("\n")

const formChromeImports = [
  'import CadenceFormActions from "./ui/components/CadenceFormActions.vue"',
  'import CadenceFormSectionHeader from "./ui/components/CadenceFormSectionHeader.vue"',
]
const actionWrapperClass = "flex items-center gap-3 border-t border-base-300/60 pt-5"
const occurrences = (source, fragment) => source.split(fragment).length - 1

const peelCadenceBreadcrumbs = (source, label) => {
  const importCount = occurrences(source, breadcrumbsImport)
  const openingCount = occurrences(source, "<CadenceBreadcrumbs>")
  const closingCount = occurrences(source, "</CadenceBreadcrumbs>")

  if (importCount === 0) {
    assert.equal(openingCount, 0, `${label} has no unimported breadcrumb opening`)
    assert.equal(closingCount, 0, `${label} has no unimported breadcrumb closing`)
    return source
  }

  assert.equal(importCount, 1, `${label} has one exact breadcrumb import`)
  assert.equal(openingCount, 1, `${label} has one exact breadcrumb opening`)
  assert.equal(closingCount, 1, `${label} has one exact breadcrumb closing`)

  const openingMatch = source.match(/^( *)<CadenceBreadcrumbs>$/m)
  assert.ok(openingMatch, `${label} has an explicitly bounded breadcrumb opening`)
  const indent = openingMatch[1]
  const wrapperOpening = `${indent}<CadenceBreadcrumbs>`
  const wrapperClosing = `${indent}</CadenceBreadcrumbs>`
  const nativeOpening = `${indent}<nav
${indent}  aria-label="Breadcrumb"
${indent}  class="${breadcrumbNavClass}"
${indent}>`

  assert.equal(occurrences(source, wrapperOpening), 1, `${label} opening indentation is exact`)
  assert.equal(occurrences(source, wrapperClosing), 1, `${label} closing indentation is exact`)

  const peeled = source
    .replace(breadcrumbsImport, "")
    .replace(wrapperOpening, nativeOpening)
    .replace(wrapperClosing, `${indent}</nav>`)

  assert.equal(occurrences(peeled, "CadenceBreadcrumbs"), 0, `${label} breadcrumb peel is exact`)
  return peeled
}

const formChromeHeader = (
  key,
  numberExpression,
  titleExpression,
  {indent = 8, multilineNumber = false, dividerClass = "flex-1 h-px bg-base-300/60"} = {},
) => ({key, numberExpression, titleExpression, indent, multilineNumber, dividerClass})

const migratedHeader = ({numberExpression, titleExpression, indent, dividerClass}) => {
  const spaces = " ".repeat(indent)
  return `${spaces}<CadenceFormSectionHeader
${spaces}  wrapper-class="flex items-center gap-3"
${spaces}  :number="${numberExpression}"
${spaces}  number-class="hud-label text-primary/70"
${spaces}  :title="${titleExpression}"
${spaces}  title-class="hud-label"
${spaces}  divider-class="${dividerClass}"
${spaces}/>`
}

const foundationHeader = ({numberExpression, titleExpression, indent, multilineNumber, dividerClass}) => {
  const spaces = " ".repeat(indent)
  const number = multilineNumber
    ? `
${spaces}    {{ ${numberExpression} }}
${spaces}  `
    : `{{ ${numberExpression} }}`

  return `${spaces}<div class="flex items-center gap-3">
${spaces}  <span class="hud-label text-primary/70">${number}</span>
${spaces}  <h2 class="hud-label">{{ ${titleExpression} }}</h2>
${spaces}  <div class="${dividerClass}"></div>
${spaces}</div>`
}

const reconstructFormChrome = (source, feature, headers) => {
  assert.equal(
    occurrences(source, "<CadenceFormSectionHeader\n"),
    headers.length,
    `${feature} keeps every form-section header in the reconstruction ledger`,
  )
  assert.equal(
    occurrences(source, `<CadenceFormActions wrapper-class="${actionWrapperClass}">`),
    1,
    `${feature} keeps its action row in the reconstruction ledger`,
  )

  let reconstructed = source
  for (const importLine of formChromeImports) {
    assert.equal(occurrences(reconstructed, `${importLine}\n`), 1)
    reconstructed = reconstructed.replace(`${importLine}\n`, "")
  }

  for (const entry of headers) {
    const migrated = migratedHeader(entry)
    assert.equal(occurrences(reconstructed, migrated), 1, `${feature} ${entry.key} reconstructs once`)
    reconstructed = reconstructed.replace(migrated, foundationHeader(entry))
  }

  const actionsOpen = `      <CadenceFormActions wrapper-class="${actionWrapperClass}">`
  assert.equal(occurrences(reconstructed, actionsOpen), 1)
  reconstructed = reconstructed.replace(actionsOpen, `      <div class="${actionWrapperClass}">`)
  assert.equal(occurrences(reconstructed, "      </CadenceFormActions>"), 1)
  reconstructed = reconstructed.replace("      </CadenceFormActions>", "      </div>")

  return reconstructed
}

const routingHeaders = [
  formChromeHeader("intent", "form.sections.intent.number", "form.sections.intent.title"),
  formChromeHeader("transport", "form.sections.transport.number", "form.sections.transport.title"),
  formChromeHeader("policy", "form.sections.policy.number", "form.sections.policy.title"),
]
const providerHeaders = [
  formChromeHeader("binding", "form.sections.binding.number", "form.sections.binding.title"),
  formChromeHeader(
    "resource scope",
    "form.sections.resource_scope.number",
    "form.sections.resource_scope.title",
    {multilineNumber: true},
  ),
  formChromeHeader(
    "delivery policy",
    "form.sections.delivery_policy.number",
    "form.sections.delivery_policy.title",
    {multilineNumber: true},
  ),
]

const reconstructRoutingSource = (source) => {
  let reconstructedFields = 0
  const reconstructed = reconstructPageHeaderSource(
    peelCadenceBreadcrumbs(source, "CommsRoutingNew.vue"),
  )
    .replace('import CadenceField from "./ui/components/CadenceField.vue"\n', "")
    .replace(
      /        <CadenceField\n          :control-id="form\.fields\.(\w+)\.id"\n          wrapper-class="fieldset mb-3"\n          :label="form\.fields\.\1\.label"\n          label-class="hud-label block mb-1\.5"\n        >\n([\s\S]*?)\n        <\/CadenceField>/g,
      (_match, fieldKey, control) => {
        reconstructedFields += 1
        return `        <div class="fieldset mb-3">
          <label :for="form.fields.${fieldKey}.id">
            <span class="hud-label block mb-1.5">{{ form.fields.${fieldKey}.label }}</span>
${indentControl(control)}
          </label>
        </div>`
      },
    )

  assert.equal(reconstructedFields, 6, "all routing fields reconstruct one-for-one")
  return reconstructFormChrome(reconstructed, "routing", routingHeaders)
}

const reconstructProviderSource = (source) => {
  let reconstructedFields = 0
  let reconstructed = reconstructPageHeaderSource(
    peelCadenceBreadcrumbs(
      peelCadenceNoticeFrames(source, "CommsProviderNew.vue"),
      "CommsProviderNew.vue",
    ),
  ).replace(
    'import CadenceField from "./ui/components/CadenceField.vue"\n',
    "",
  )

  reconstructed = reconstructed.replace(
    /        <CadenceField\n          v-for="field in fieldsFor\(([^)]+)\)"\n          :key="field\.key"\n          :control-id="field\.id"\n          wrapper-class="fieldset mb-3"\n          :label="field\.label"\n          label-class="hud-label block mb-1\.5"\n        >\n([\s\S]*?)\n        <\/CadenceField>/g,
    (_match, section, control) => {
      reconstructedFields += 1
      return `        <div
          v-for="field in fieldsFor(${section})"
          :key="field.key"
          class="fieldset mb-3"
        >
          <label :for="field.id">
            <span class="hud-label block mb-1.5">{{ field.label }}</span>
${indentControl(control)}
          </label>
        </div>`
    },
  )

  reconstructed = reconstructed.replace(
    /          <CadenceField\n            v-for="field in fieldsForKeys\(([^)]+)\)"\n            :key="field\.key"\n            :control-id="field\.id"\n            wrapper-class="fieldset mb-3"\n            :label="field\.label"\n            label-class="hud-label block mb-1\.5"\n          >\n([\s\S]*?)\n          <\/CadenceField>/g,
    (_match, fieldKeys, control) => {
      reconstructedFields += 1
      return `          <div
            v-for="field in fieldsForKeys(${fieldKeys})"
            :key="field.key"
            class="fieldset mb-3"
          >
            <label :for="field.id">
              <span class="hud-label block mb-1.5">{{ field.label }}</span>
${indentControl(control)}
            </label>
          </div>`
    },
  )

  reconstructed = reconstructed.replace(
    /        <CadenceField\n          :control-id="form\.fields\.(\w+)\.id"\n          wrapper-class="fieldset mb-3"\n          :label="form\.fields\.\1\.label"\n          label-class="hud-label block mb-1\.5"\n        >\n([\s\S]*?)\n        <\/CadenceField>/g,
    (_match, fieldKey, control) => {
      reconstructedFields += 1
      const label =
        fieldKey === "deadline_behavior"
          ? `            <span class="hud-label block mb-1.5">
              {{ form.fields.${fieldKey}.label }}
            </span>`
          : `            <span class="hud-label block mb-1.5">{{ form.fields.${fieldKey}.label }}</span>`

      return `        <div class="fieldset mb-3">
          <label :for="form.fields.${fieldKey}.id">
${label}
${indentControl(control)}
          </label>
        </div>`
    },
  )

  assert.equal(reconstructedFields, 5, "all provider field call sites reconstruct one-for-one")
  return reconstructFormChrome(reconstructed, "provider", providerHeaders)
}

assert.equal(
  createHash("sha256").update(reconstructProviderSource(providerSource)).digest("hex"),
  "e51a55749ea3eea4bf561b5a25b329ba613a063118da5fc4497efe3b33b2edae",
  "removing provider CadenceField boundaries reconstructs the base source exactly",
)
assert.equal(
  createHash("sha256").update(reconstructRoutingSource(routingSource)).digest("hex"),
  "5aa23bd7fe64e3a0a89e6e5dad2b2f49ce10a6619c720eb4d04af569eb208c67",
  "removing routing CadenceField boundaries reconstructs the base source exactly",
)

const deepFreeze = (value) => {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value)
    Object.values(value).forEach(deepFreeze)
  }

  return value
}

const assertFieldWrappers = (host, expectedCount) => {
  const wrappers = [...host.querySelectorAll("form .fieldset")]
  assert.equal(wrappers.length, expectedCount)
  assert.deepEqual(
    wrappers.map(elementAttributes),
    Array.from({length: expectedCount}, () => ({class: "fieldset mb-3"})),
  )
  assert.deepEqual(
    wrappers.map((wrapper) => [...wrapper.childNodes].map((child) => child.nodeName)),
    Array.from({length: expectedCount}, () => ["LABEL"]),
  )

  for (const wrapper of wrappers) {
    const label = wrapper.querySelector("label")
    const control = label.querySelector("input, select, textarea")
    assert.deepEqual([...label.childNodes].map((child) => child.nodeName), [
      "SPAN",
      control.nodeName,
    ])
    assert.deepEqual(elementAttributes(label), {for: control.id})
    assert.deepEqual(elementAttributes(label.firstElementChild), {
      class: "hud-label block mb-1.5",
    })
  }
}

const dom = installDom(`
  <div id="provider-contract"></div>
  <div id="routing-contract"></div>
`)
for (const globalName of [
  "Document",
  "ShadowRoot",
  "HTMLFormElement",
  "HTMLInputElement",
  "HTMLSelectElement",
  "HTMLOptionElement",
]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const [{component: CommsProviderNew}, {component: CommsRoutingNew}] = await Promise.all([
  loadSfc(providerPath),
  loadSfc(routingPath),
])
const {createApp, defineComponent, h, nextTick, reactive} = integrationRequire("vue")

const providerFieldKeys = [
  "display_name",
  "provider_account_grant_id",
  "permitted_resource_refs",
  "policy_mode",
  "maximum_earlier_start_shift_seconds",
  "maximum_later_start_shift_seconds",
  "maximum_earlier_end_shift_seconds",
  "maximum_later_end_shift_seconds",
  "minimum_retained_duration_seconds",
  "approved_station_substitutions",
  "deadline_behavior",
]
const providerField = (key, type, label, value, overrides = {}) => ({
  key,
  id: `provider_${key}`,
  name: `provider[${key}]`,
  type,
  label,
  required: false,
  placeholder: null,
  min: null,
  options: [],
  value,
  ...overrides,
})
const providerFormWithValues = (values) => ({
  id: "provider-form",
  sections: {
    binding: {
      id: "provider-binding-section",
      number: "01",
      title: "Provider binding",
      field_keys: ["display_name", "provider_account_grant_id"],
    },
    resource_scope: {
      id: "provider-resource-section",
      number: "02",
      title: "Resource scope",
      field_keys: ["permitted_resource_refs"],
    },
    delivery_policy: {
      id: "provider-policy-section",
      number: "03",
      title: "Delivery policy",
      field_keys: [],
    },
  },
  fields: {
    display_name: providerField("display_name", "text", "Display name", values.display_name, {
      required: true,
      placeholder: "Goldstone provider",
    }),
    provider_account_grant_id: providerField(
      "provider_account_grant_id",
      "select",
      "Provider account",
      values.provider_account_grant_id,
      {
        required: true,
        options: [
          {label: "NASA DSN", value: "grant-dsn"},
          {label: "KSAT", value: "grant-ksat"},
        ],
      },
    ),
    permitted_resource_refs: providerField(
      "permitted_resource_refs",
      "text",
      "Permitted resource refs",
      values.permitted_resource_refs,
      {placeholder: "dss-14,dss-43"},
    ),
    policy_mode: providerField("policy_mode", "select", "Policy mode", values.policy_mode, {
      required: true,
      options: [
        {label: "Approval required", value: "approval_required"},
        {label: "Bounded", value: "bounded"},
      ],
    }),
    maximum_earlier_start_shift_seconds: providerField(
      "maximum_earlier_start_shift_seconds",
      "number",
      "Maximum earlier start shift",
      values.maximum_earlier_start_shift_seconds,
      {min: 0},
    ),
    maximum_later_start_shift_seconds: providerField(
      "maximum_later_start_shift_seconds",
      "number",
      "Maximum later start shift",
      values.maximum_later_start_shift_seconds,
      {min: 0},
    ),
    maximum_earlier_end_shift_seconds: providerField(
      "maximum_earlier_end_shift_seconds",
      "number",
      "Maximum earlier end shift",
      values.maximum_earlier_end_shift_seconds,
      {min: 0},
    ),
    maximum_later_end_shift_seconds: providerField(
      "maximum_later_end_shift_seconds",
      "number",
      "Maximum later end shift",
      values.maximum_later_end_shift_seconds,
      {min: 0},
    ),
    minimum_retained_duration_seconds: providerField(
      "minimum_retained_duration_seconds",
      "number",
      "Minimum retained duration",
      values.minimum_retained_duration_seconds,
      {min: 0},
    ),
    approved_station_substitutions: providerField(
      "approved_station_substitutions",
      "text",
      "Approved station substitutions",
      values.approved_station_substitutions,
    ),
    deadline_behavior: providerField(
      "deadline_behavior",
      "select",
      "Deadline behavior",
      values.deadline_behavior,
      {
        required: true,
        options: [
          {label: "Reject", value: "reject"},
          {label: "Best effort", value: "best_effort"},
        ],
      },
    ),
  },
  conditional: {
    approval_guidance: {
      id: "provider-approval-guidance",
      active: true,
      visible_when: {field: "policy_mode", equals: "approval_required"},
      text: "Every provider change requires approval.",
    },
    bounded_policy: {
      id: "provider-bounded-policy",
      active: false,
      visible_when: {field: "policy_mode", equals: "bounded"},
      field_keys: [
        "maximum_earlier_start_shift_seconds",
        "maximum_later_start_shift_seconds",
        "maximum_earlier_end_shift_seconds",
        "maximum_later_end_shift_seconds",
        "minimum_retained_duration_seconds",
        "approved_station_substitutions",
      ],
    },
  },
  actions: {
    submit: {id: "provider-submit", label: "Save provider"},
    cancel: {id: "provider-cancel", label: "Cancel", href: "/missions/mission-1/comms/providers"},
  },
})

const initialProviderValues = {
  display_name: "DSN provider",
  provider_account_grant_id: "grant-dsn",
  permitted_resource_refs: "dss-14",
  policy_mode: "approval_required",
  maximum_earlier_start_shift_seconds: "60",
  maximum_later_start_shift_seconds: "120",
  maximum_earlier_end_shift_seconds: "180",
  maximum_later_end_shift_seconds: "240",
  minimum_retained_duration_seconds: "300",
  approved_station_substitutions: "dss-43",
  deadline_behavior: "reject",
}
const providerProps = reactive({
  page: deepFreeze({
    id: "provider-page",
    title: "New provider",
    subtitle: "Bind a provider account.",
    breadcrumbs: [{label: "Providers", href: null}],
  }),
  accounts: deepFreeze({
    empty: false,
    options: [],
    selected: {
      id: "provider-account-summary",
      ownership_label: "Account",
      display_name: "NASA DSN",
      version_label: "Version 4",
      badge: {status: "ready", label: "Ready"},
      restrictions: [{label: "Scope", summary: "Goldstone"}],
    },
    empty_state: {
      id: "provider-empty-state",
      heading: "No accounts",
      message: "Add an account first.",
      action: {id: "provider-empty-action", label: "Add account", href: "/accounts/new"},
    },
  }),
  notes: deepFreeze({
    secret_boundary: {id: "provider-secret-note", text: "Secrets remain server-owned."},
    resource_boundary: {id: "provider-resource-note", text: "Refs are mission-scoped."},
  }),
  form: deepFreeze(providerFormWithValues(initialProviderValues)),
})
const providerEmitted = {validate: [], save: []}
const ProviderContract = defineComponent({
  setup() {
    return () =>
      h(CommsProviderNew, {
        page: providerProps.page,
        accounts: providerProps.accounts,
        notes: providerProps.notes,
        form: providerProps.form,
        onValidate: (payload) => providerEmitted.validate.push(payload),
        onSave: (payload) => providerEmitted.save.push(payload),
      })
  },
})
const providerHost = dom.window.document.querySelector("#provider-contract")
const providerApp = createApp(ProviderContract)
providerApp.mount(providerHost)

assertFieldWrappers(providerHost, 5)
const providerApprovalGuidance = providerHost.querySelector("#provider-approval-guidance")
assert.equal(providerApprovalGuidance.tagName, "DIV")
assert.deepEqual(elementAttributes(providerApprovalGuidance), {
  class: "border-l-2 border-info/60 bg-info/10 px-4 py-3 text-sm text-base-content/70",
  id: "provider-approval-guidance",
})
assert.deepEqual(
  [...providerApprovalGuidance.childNodes].map((node) => node.nodeName),
  ["#text"],
)
assert.equal(providerApprovalGuidance.textContent.trim(), "Every provider change requires approval.")
assert.equal(providerHost.querySelector("#provider-bounded-policy"), null)
assert.deepEqual(
  [...providerHost.querySelectorAll("#provider_provider_account_grant_id option")].map((option) => [
    option.value,
    option.textContent,
  ]),
  [
    ["grant-dsn", "NASA DSN"],
    ["grant-ksat", "KSAT"],
  ],
)
assert.deepEqual(elementAttributes(providerHost.querySelector("#provider_display_name")), {
  class: "w-full input",
  id: "provider_display_name",
  name: "provider[display_name]",
  placeholder: "Goldstone provider",
  required: "",
  type: "text",
})

const providerDisplay = providerHost.querySelector("#provider_display_name")
providerDisplay.value = "Goldstone provider"
providerDisplay.dispatchEvent(new dom.window.Event("input", {bubbles: true}))
await nextTick()
assert.deepEqual(providerEmitted.validate.at(-1), {
  provider: {...initialProviderValues, display_name: "Goldstone provider"},
})

const providerPolicy = providerHost.querySelector("#provider_policy_mode")
providerPolicy.value = "bounded"
providerPolicy.dispatchEvent(new dom.window.Event("change", {bubbles: true}))
await nextTick()
const editedProviderValues = {
  ...initialProviderValues,
  display_name: "Goldstone provider",
  policy_mode: "bounded",
}
assert.deepEqual(providerEmitted.validate.at(-1), {provider: editedProviderValues})
assert.equal(providerHost.querySelector("#provider-approval-guidance"), null)
assert.ok(providerHost.querySelector("#provider-bounded-policy"))
assertFieldWrappers(providerHost, 11)
assert.equal(
  providerHost.querySelector("#provider_maximum_earlier_start_shift_seconds").getAttribute("min"),
  "0",
)

const providerControls = [...providerHost.querySelectorAll("#provider-form input, #provider-form select")]
assert.deepEqual(
  providerControls.map((control) => control.id),
  providerFieldKeys.map((key) => `provider_${key}`),
)

providerProps.form = deepFreeze(providerFormWithValues(editedProviderValues))
await nextTick()
const authoritativeProviderValues = {
  ...editedProviderValues,
  permitted_resource_refs: "dss-14,dss-43",
  deadline_behavior: "best_effort",
}
providerProps.form = deepFreeze(providerFormWithValues(authoritativeProviderValues))
await nextTick()
assert.deepEqual(
  [...providerHost.querySelectorAll("#provider-form input, #provider-form select")],
  providerControls,
  "provider prop reconciliation preserves every native control node",
)
assert.deepEqual(
  providerControls.map((control) => control.value),
  providerFieldKeys.map((key) => authoritativeProviderValues[key]),
)

const providerSubmitEvent = new dom.window.Event("submit", {bubbles: true, cancelable: true})
providerHost.querySelector("#provider-form").dispatchEvent(providerSubmitEvent)
assert.equal(providerSubmitEvent.defaultPrevented, true)
assert.deepEqual(providerEmitted.save, [{provider: authoritativeProviderValues}])

providerProps.accounts = deepFreeze({...providerProps.accounts, empty: true, selected: null})
await nextTick()
assert.equal(providerHost.querySelector("#provider-form"), null)
assert.ok(providerHost.querySelector("#provider-empty-state"))
providerApp.unmount()

const routingFieldKeys = [
  "display_name",
  "purpose_label",
  "spacecraft_id",
  "transport_ref",
  "direction",
  "role",
]
const routingField = (key, type, label, value) => ({
  id: `routing_rule_${key}`,
  name: `routing_rule[${key}]`,
  type,
  label,
  required: true,
  value,
})
const routingFormWithValues = (values) => ({
  id: "routing-rule-form",
  sections: {
    intent: {number: "01", title: "Intent"},
    transport: {number: "02", title: "Transport"},
    policy: {number: "03", title: "Policy"},
  },
  fields: Object.fromEntries(
    routingFieldKeys.map((key) => [
      key,
      routingField(
        key,
        ["display_name", "purpose_label"].includes(key) ? "text" : "select",
        key.replaceAll("_", " "),
        values[key],
      ),
    ]),
  ),
  actions: {
    submit: {id: "routing-rule-submit", label: "Save routing rule"},
    cancel: {id: "routing-rule-cancel", label: "Cancel", href: "/missions/mission-1/comms/routing"},
  },
})
const initialRoutingValues = {
  display_name: "Downlink science",
  purpose_label: "Telemetry",
  spacecraft_id: "sc-1",
  transport_ref: "transport-primary",
  direction: "downlink",
  role: "primary",
}
const routingProps = reactive({
  page: deepFreeze({
    id: "routing-page",
    title: "New routing rule",
    subtitle: "Choose the flight transport.",
    breadcrumbs: [{label: "Routing", href: null}],
  }),
  form: deepFreeze(routingFormWithValues(initialRoutingValues)),
  options: deepFreeze({
    spacecraft: [
      {label: "Odyssey", value: "sc-1"},
      {label: "Reconnaissance Orbiter", value: "sc-2"},
    ],
    transports: [
      {label: "Primary", value: "transport-primary"},
      {label: "Backup", value: "transport-backup"},
    ],
    directions: [
      {label: "Downlink", value: "downlink"},
      {label: "Uplink", value: "uplink"},
    ],
    roles: [
      {label: "Primary", value: "primary"},
      {label: "Backup", value: "backup"},
    ],
  }),
})
const routingEmitted = {validate: [], save: []}
const RoutingContract = defineComponent({
  setup() {
    return () =>
      h(CommsRoutingNew, {
        page: routingProps.page,
        form: routingProps.form,
        options: routingProps.options,
        onValidate: (payload) => routingEmitted.validate.push(payload),
        onSave: (payload) => routingEmitted.save.push(payload),
      })
  },
})
const routingHost = dom.window.document.querySelector("#routing-contract")
const routingApp = createApp(RoutingContract)
routingApp.mount(routingHost)

assertFieldWrappers(routingHost, 6)
const routingControls = [
  ...routingHost.querySelectorAll("#routing-rule-form input, #routing-rule-form select"),
]
assert.deepEqual(routingControls.map((control) => control.tagName), [
  "INPUT",
  "INPUT",
  "SELECT",
  "SELECT",
  "SELECT",
  "SELECT",
])
assert.deepEqual(
  [...routingHost.querySelectorAll("#routing_rule_spacecraft_id option")].map((option) => [
    option.value,
    option.textContent,
  ]),
  [
    ["sc-1", "Odyssey"],
    ["sc-2", "Reconnaissance Orbiter"],
  ],
)

routingControls[0].value = "Uplink commanding"
routingControls[0].dispatchEvent(new dom.window.Event("input", {bubbles: true}))
await nextTick()
const typedRoutingValues = {...initialRoutingValues, display_name: "Uplink commanding"}
assert.deepEqual(routingEmitted.validate.at(-1), {routing_rule: typedRoutingValues})

routingProps.form = deepFreeze(routingFormWithValues(initialRoutingValues))
await nextTick()
assert.equal(routingControls[0].value, "Uplink commanding", "a stale patch keeps newer typing")
assert.strictEqual(routingHost.querySelector("#routing_rule_display_name"), routingControls[0])

routingControls[2].value = "sc-2"
routingControls[2].dispatchEvent(new dom.window.Event("change", {bubbles: true}))
await nextTick()
const editedRoutingValues = {...typedRoutingValues, spacecraft_id: "sc-2"}
assert.deepEqual(routingEmitted.validate.at(-1), {routing_rule: editedRoutingValues})

routingProps.form = deepFreeze(routingFormWithValues(editedRoutingValues))
await nextTick()
const authoritativeRoutingValues = {
  ...editedRoutingValues,
  transport_ref: "transport-backup",
  direction: "uplink",
  role: "backup",
}
routingProps.form = deepFreeze(routingFormWithValues(authoritativeRoutingValues))
await nextTick()
assert.deepEqual(
  [...routingHost.querySelectorAll("#routing-rule-form input, #routing-rule-form select")],
  routingControls,
  "routing prop reconciliation preserves every native control node",
)
assert.deepEqual(
  routingControls.map((control) => control.value),
  routingFieldKeys.map((key) => authoritativeRoutingValues[key]),
)

const routingSubmitEvent = new dom.window.Event("submit", {bubbles: true, cancelable: true})
routingHost.querySelector("#routing-rule-form").dispatchEvent(routingSubmitEvent)
assert.equal(routingSubmitEvent.defaultPrevented, true)
assert.deepEqual(routingEmitted.save, [{routing_rule: authoritativeRoutingValues}])

routingApp.unmount()
assert.equal(providerHost.children.length, 0)
assert.equal(routingHost.children.length, 0)
dom.window.close()

console.log("comms_provider_routing_cadence_field_test passed")
