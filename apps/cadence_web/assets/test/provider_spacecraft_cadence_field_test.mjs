import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {peelCadencePageTitle} from "./page_title_test_support.mjs"
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
  `Provider and spacecraft CadenceField contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const breadcrumbsImport =
  'import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"\n'
const breadcrumbNavClass =
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
const providerPath = resolve(testDirectory, "../vue/ProviderAccountNew.vue")
const spacecraftPath = resolve(testDirectory, "../vue/SpacecraftTypeNew.vue")
const [providerSource, spacecraftSource] = await Promise.all([
  readFile(providerPath, "utf8"),
  readFile(spacecraftPath, "utf8"),
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

const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const shiftIndent = (source, spaces) =>
  source
    .split("\n")
    .map((line) =>
      spaces >= 0 ? `${" ".repeat(spaces)}${line}` : line.slice(Math.min(-spaces, line.length)),
    )
    .join("\n")

const formChromeImports =
  'import CadenceFormActions from "./ui/components/CadenceFormActions.vue"\n' +
  'import CadenceFormSectionHeader from "./ui/components/CadenceFormSectionHeader.vue"\n'
const actionOpen =
  '      <CadenceFormActions wrapper-class="flex items-center gap-3 border-t border-base-300/60 pt-5">'
const originalActionOpen =
  '      <div class="flex items-center gap-3 border-t border-base-300/60 pt-5">'
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

const reconstructFormChromeSource = (
  source,
  {featureName, dividerClass, multilineNumberExpressions},
) => {
  assert.equal(occurrences(source, formChromeImports), 1, `${featureName} owns both imports`)

  let reconstructed = source.replace(formChromeImports, "")
  let reconstructedHeaders = 0
  reconstructed = reconstructed.replace(
    /^( +)<CadenceFormSectionHeader\n +wrapper-class="flex items-center gap-3"\n +:number="([^"]+)\.number"\n +number-class="hud-label text-primary\/70"\n +:title="\2\.title"\n +title-class="hud-label"\n +divider-class="([^"]+)"\n +\/>$/gm,
    (_match, indent, expression, actualDividerClass) => {
      reconstructedHeaders += 1
      assert.equal(
        actualDividerClass,
        dividerClass,
        `${featureName} preserves the ${expression} divider class order`,
      )

      const number = multilineNumberExpressions.has(expression)
        ? `${indent}  <span class="hud-label text-primary/70">
${indent}    {{ ${expression}.number }}
${indent}  </span>`
        : `${indent}  <span class="hud-label text-primary/70">{{ ${expression}.number }}</span>`

      return `${indent}<div class="flex items-center gap-3">
${number}
${indent}  <h2 class="hud-label">{{ ${expression}.title }}</h2>
${indent}  <div class="${dividerClass}"></div>
${indent}</div>`
    },
  )

  assert.equal(
    reconstructedHeaders,
    4,
    `all four ${featureName} section headers reconstruct one-for-one`,
  )
  assert.equal(occurrences(reconstructed, actionOpen), 1, `${featureName} action row reconstructs`)
  assert.equal(occurrences(reconstructed, "      </CadenceFormActions>"), 1)

  return reconstructed
    .replace(actionOpen, originalActionOpen)
    .replace("      </CadenceFormActions>", "      </div>")
}

const reconstructProviderSource = (source) => {
  let reconstructed = reconstructFormChromeSource(
    reconstructPageHeaderSource(
      peelCadenceBreadcrumbs(
        peelCadenceNoticeFrames(source, "ProviderAccountNew.vue"),
        "ProviderAccountNew.vue",
      ),
    ),
    {
    featureName: "provider",
    dividerClass: "h-px flex-1 bg-base-300/60",
    multilineNumberExpressions: new Set([
      "form.sections.credential_registry",
      "form.sections.organization_guardrails",
    ]),
    },
  ).replace(
    'import CadenceField from "./ui/components/CadenceField.vue"\n',
    "",
  )
  let configurationFields = 0
  reconstructed = reconstructed.replace(
    /              <CadenceField\n                v-if="visible\(field\)"\n                :id="field\.wrapper_id"\n                :control-id="field\.id"\n                wrapper-class="fieldset mb-3"\n                :label="fieldLabel\(field\)"\n                label-class="hud-label mb-1\.5 block"\n              >\n([\s\S]*?)\n                <template #help>\n([\s\S]*?)\n                <\/template>\n              <\/CadenceField>/g,
    (_match, controls, help) => {
      configurationFields += 1
      return `              <div
                v-if="visible(field)"
                :id="field.wrapper_id"
                class="fieldset mb-3"
              >
                <label :for="field.id">
                  <span class="hud-label mb-1.5 block">{{ fieldLabel(field) }}</span>
${shiftIndent(controls, 2)}
                </label>
${shiftIndent(help, -2)}
              </div>`
    },
  )

  let sectionFields = 0
  reconstructed = reconstructed.replace(
    /        <CadenceField\n          v-for="field in fieldsFor\(([^)]+)\)"\n          :key="field\.key"\n          :control-id="field\.id"\n          wrapper-class="fieldset mb-3"\n          :label="fieldLabel\(field\)"\n          label-class="hud-label mb-1\.5 block"\n        >\n([\s\S]*?)\n        <\/CadenceField>/g,
    (_match, section, controls) => {
      sectionFields += 1
      return `        <div
          v-for="field in fieldsFor(${section})"
          :key="field.key"
          class="fieldset mb-3"
        >
          <label :for="field.id">
            <span class="hud-label mb-1.5 block">{{ fieldLabel(field) }}</span>
${shiftIndent(controls, 2)}
          </label>
        </div>`
    },
  )

  assert.equal(configurationFields, 1, "the provider configuration shell reconstructs once")
  assert.equal(sectionFields, 3, "the three provider section shells reconstruct once each")
  return reconstructed
}

const multilineSpacecraftLabels = new Set([
  "downlink_protocol",
  "uplink_protocol",
  "secondary_header_length",
  "insert_zone_length",
  "truncated_primary_header",
])

const reconstructSpacecraftSource = (source) => {
  let reconstructed = reconstructFormChromeSource(
    reconstructPageHeaderSource(
      peelCadenceBreadcrumbs(
        peelCadencePageTitle(source, "SpacecraftTypeNew.vue"),
        "SpacecraftTypeNew.vue",
      ),
    ),
    {
    featureName: "spacecraft type",
    dividerClass: "flex-1 h-px bg-base-300/60",
    multilineNumberExpressions: new Set(["form.sections.frame_parameters"]),
    },
  ).replace(
    'import CadenceField from "./ui/components/CadenceField.vue"\n',
    "",
  )
  let reconstructedFields = 0
  reconstructed = reconstructed.replace(
    /        <CadenceField\n(?:          v-if="([^"]+)"\n)?          :control-id="form\.fields\.(\w+)\.id"\n          wrapper-class="fieldset mb-3"\n          :label="form\.fields\.\2\.label"\n          label-class="hud-label block mb-1\.5"\n        >\n([\s\S]*?)\n        <\/CadenceField>/g,
    (_match, condition, fieldKey, control) => {
      reconstructedFields += 1
      const opening = condition
        ? `        <div v-if="${condition}" class="fieldset mb-3">`
        : '        <div class="fieldset mb-3">'
      const label = multilineSpacecraftLabels.has(fieldKey)
        ? `            <span class="hud-label block mb-1.5">
              {{ form.fields.${fieldKey}.label }}
            </span>`
        : `            <span class="hud-label block mb-1.5">{{ form.fields.${fieldKey}.label }}</span>`

      return `${opening}
          <label :for="form.fields.${fieldKey}.id">
${label}
${shiftIndent(control, 2)}
          </label>
        </div>`
    },
  )

  assert.equal(reconstructedFields, 8, "all eight spacecraft field shells reconstruct")
  return reconstructed
}

assert.match(providerSource, /^import CadenceField from "\.\/ui\/components\/CadenceField\.vue"$/m)
assert.equal(providerSource.match(/<CadenceField\b/g)?.length, 4)
assert.match(
  providerSource,
  /^import CadenceFormActions from "\.\/ui\/components\/CadenceFormActions\.vue"$/m,
)
assert.match(
  providerSource,
  /^import CadenceFormSectionHeader from "\.\/ui\/components\/CadenceFormSectionHeader\.vue"$/m,
)
assert.equal(providerSource.match(/<CadenceFormSectionHeader\b/g)?.length, 4)
assert.equal(providerSource.match(/<CadenceFormActions\b/g)?.length, 1)
assert.match(
  providerSource,
  /<input\n        v-for="fieldKey in form\.hidden_field_keys"[\s\S]*?type="hidden"/,
  "provider hidden inputs remain feature-owned",
)
assert.equal(
  sha256(reconstructProviderSource(providerSource)),
  "f199298a5f14de4fbd9a4ad2a063ba649b5cc9b2eb1ea2920091deed74840660",
  "removing the four transparent provider boundaries reconstructs the base source",
)

assert.match(spacecraftSource, /^import CadenceField from "\.\/ui\/components\/CadenceField\.vue"$/m)
assert.equal(spacecraftSource.match(/<CadenceField\b/g)?.length, 8)
assert.match(
  spacecraftSource,
  /^import CadenceFormActions from "\.\/ui\/components\/CadenceFormActions\.vue"$/m,
)
assert.match(
  spacecraftSource,
  /^import CadenceFormSectionHeader from "\.\/ui\/components\/CadenceFormSectionHeader\.vue"$/m,
)
assert.equal(spacecraftSource.match(/<CadenceFormSectionHeader\b/g)?.length, 4)
assert.equal(spacecraftSource.match(/<CadenceFormActions\b/g)?.length, 1)
assert.match(
  spacecraftSource,
  /<input\n              :id="application\.id"\n              type="checkbox"[\s\S]*?@change="toggleApplication\(application\.key, \$event\)"/,
  "spacecraft application checkboxes remain feature-owned",
)
assert.equal(
  sha256(reconstructSpacecraftSource(spacecraftSource)),
  "c1e5504f4313279925024590f893428ed1d99352a49bfc513354531c16dcb7f1",
  "removing the eight transparent spacecraft boundaries reconstructs the base source",
)

const deepFreeze = (value) => {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value)
    Object.values(value).forEach(deepFreeze)
  }

  return value
}

const option = (label, value, disabled = false) => ({label, value, disabled})
const providerField = (key, type, value, overrides = {}) => ({
  key,
  id: `provider_${key}`,
  name: `provider_account[${key}]`,
  type,
  label: key.replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase()),
  required: false,
  placeholder: null,
  min: null,
  max: null,
  step: null,
  options: [],
  value,
  ...overrides,
})

const providerInitial = {
  account_id: "account-7",
  provider_type: "kratos",
  backend_type: "rest",
  endpoint_url: "https://rest.example.test",
  notes: "Primary provider",
  protocol_mode: "https",
  conditional_token: "token-7",
  credential: "credential-7",
  max_requests: "25",
}

const providerForm = (values) => ({
  id: "provider-account-form",
  hidden_field_keys: ["account_id"],
  sections: {
    network_identity: {
      id: "provider-network",
      number: "01",
      title: "Network Identity",
      field_keys: ["provider_type", "backend_type"],
    },
    credential_registry: {
      id: "provider-credentials",
      number: "03",
      title: "Credentials",
      field_keys: ["credential"],
    },
    organization_guardrails: {
      id: "provider-guardrails",
      number: "04",
      title: "Guardrails",
      field_keys: ["max_requests"],
    },
  },
  fields: {
    account_id: providerField("account_id", "hidden", values.account_id),
    provider_type: providerField("provider_type", "select", values.provider_type, {
      label: "Provider Type",
      required: true,
      options: [option("Kratos", "kratos"), option("Atlas", "atlas")],
    }),
    backend_type: providerField("backend_type", "select", values.backend_type, {
      label: "Backend Type",
      required: true,
      options: [option("REST", "rest"), option("GraphQL", "graphql")],
    }),
    credential: providerField("credential", "text", values.credential, {
      label: "Credential",
      required: true,
      placeholder: "Secret reference",
    }),
    max_requests: providerField("max_requests", "number", values.max_requests, {
      label: "Maximum Requests",
      min: 1,
      max: 100,
      step: "1",
    }),
  },
  connector: {
    options: [option("Kratos", "kratos"), option("Atlas", "atlas")],
    selected: {
      id: "selected-provider",
      form_value: values.provider_type,
      provider_type: values.provider_type,
      client_key: `${values.provider_type}-client`,
      label: `${values.provider_type} connector`,
      description: "Server-selected connector",
    },
    configuration: {
      id: "provider-configuration",
      kind: values.provider_type,
      description: "Configure the selected provider.",
      sections: [
        {
          id: "provider-protocol",
          fields_id: "provider-protocol-fields",
          number: "02",
          title: "Protocol",
          description: "Native provider controls.",
          fields: [
            providerField("endpoint_url", "url", values.endpoint_url, {
              required: true,
              presentations: {
                rest: {label: "REST Endpoint", placeholder: "https://rest.example.test"},
                graphql: {label: "GraphQL Endpoint", placeholder: "https://graphql.example.test"},
              },
            }),
            providerField("notes", "textarea", values.notes, {
              label: "Notes",
              placeholder: "Provider notes",
              help: "Visible only to operators.",
            }),
            providerField("protocol_mode", "select", values.protocol_mode, {
              label: "Protocol Mode",
              options: [option("HTTPS", "https"), option("TCP", "tcp")],
            }),
            providerField("conditional_token", "text", values.conditional_token, {
              label: "Kratos Token",
              wrapper_id: "kratos-token-field",
              visible_when: {field: "provider_type", equals: "kratos"},
            }),
          ],
        },
      ],
    },
    boundary: {id: "provider-boundary", text: "Server owns provider selection."},
  },
  credential_note: {id: "credential-note", text: "Credentials remain server-owned."},
  actions: {
    submit: {id: "provider-submit", label: "Save Provider"},
    cancel: {id: "provider-cancel", label: "Cancel", href: "/provider-accounts"},
  },
})

const spacecraftField = (key, type, value, label) => ({
  id: `spacecraft_${key}`,
  name: `spacecraft_type[${key}]`,
  type,
  label,
  required: key !== "insert_zone_length",
  value,
})

const spacecraftInitial = {
  display_name: "Flight Profile",
  downlink_protocol: "tm",
  uplink_protocol: "tc",
  frame_size: "1115",
  secondary_header_length: "4",
  insert_zone_length: "0",
  truncated_primary_header: "false",
  ocf_length: "4",
  applications: {telemetry: "1"},
}

const spacecraftForm = (values) => ({
  id: "spacecraft-type-form",
  sections: {
    identity: {id: "spacecraft-identity", number: "01", title: "Identity", description: null},
    protocols: {id: "spacecraft-protocols", number: "02", title: "Protocols", description: null},
    frame_parameters: {
      id: "spacecraft-frame",
      number: "03",
      title: "Frame Parameters",
      description: "Protocol-dependent frame controls.",
    },
    applications: {
      id: "spacecraft-applications",
      number: "04",
      title: "Applications",
      description: "Select mission applications.",
    },
  },
  fields: {
    display_name: spacecraftField("display_name", "text", values.display_name, "Display Name"),
    downlink_protocol: spacecraftField(
      "downlink_protocol",
      "select",
      values.downlink_protocol,
      "Downlink Protocol",
    ),
    uplink_protocol: spacecraftField(
      "uplink_protocol",
      "select",
      values.uplink_protocol,
      "Uplink Protocol",
    ),
    frame_size: spacecraftField("frame_size", "number", values.frame_size, "Frame Size"),
    secondary_header_length: spacecraftField(
      "secondary_header_length",
      "number",
      values.secondary_header_length,
      "Secondary Header Length",
    ),
    insert_zone_length: spacecraftField(
      "insert_zone_length",
      "number",
      values.insert_zone_length,
      "Insert Zone Length",
    ),
    truncated_primary_header: spacecraftField(
      "truncated_primary_header",
      "select",
      values.truncated_primary_header,
      "Truncated Primary Header",
    ),
    ocf_length: spacecraftField("ocf_length", "select", values.ocf_length, "OCF Length"),
    applications: {
      id: "spacecraft-application-fields",
      name: "spacecraft_type[applications]",
      value: {...values.applications},
    },
  },
  actions: {
    submit: {id: "spacecraft-submit", label: "Save Spacecraft Type"},
    cancel: {id: "spacecraft-cancel", label: "Cancel", href: "/missions/mission-1/spacecraft"},
  },
})

const spacecraftOptions = deepFreeze({
  downlink_protocols: [option("TM", "tm"), option("AOS", "aos")],
  uplink_protocols: [option("TC", "tc"), option("COP-1", "cop1")],
  truncated_primary_headers: [option("No", "false"), option("Yes", "true")],
  operational_control_fields: [option("4 octets", "4"), option("None", "0")],
  frame_fields: {
    secondary_header_length: ["tm"],
    insert_zone_length: ["aos"],
    truncated_primary_header: ["tm"],
  },
})

const applications = deepFreeze([
  {
    id: "application-telemetry",
    key: "telemetry",
    name: "spacecraft_type[applications][telemetry]",
    value: "1",
    label: "Telemetry",
    description: "Decode telemetry frames.",
    available: true,
    availability_label: null,
  },
  {
    id: "application-commanding",
    key: "commanding",
    name: "spacecraft_type[applications][commanding]",
    value: "1",
    label: "Commanding",
    description: "Encode command frames.",
    available: false,
    availability_label: "Unavailable",
  },
])

const dom = installDom(
  '<div id="provider-contract"></div><div id="spacecraft-contract"></div>',
)
for (const globalName of [
  "Document",
  "ShadowRoot",
  "HTMLFormElement",
  "HTMLInputElement",
  "HTMLSelectElement",
  "HTMLTextAreaElement",
]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const [{component: ProviderAccountNew}, {component: SpacecraftTypeNew}] = await Promise.all([
  loadSfc(providerPath),
  loadSfc(spacecraftPath),
])
const {createApp, defineComponent, h, nextTick, reactive} = integrationRequire("vue")

const providerProps = reactive({
  page: deepFreeze({
    id: "provider-page",
    heading: "New Provider Account",
    subtitle: "Configure a provider.",
    breadcrumbs: [{label: "Providers", href: null}],
  }),
  form: deepFreeze(providerForm(providerInitial)),
})
const providerEmitted = {validate: [], save: []}
const ProviderContract = defineComponent({
  setup() {
    return () =>
      h(ProviderAccountNew, {
        page: providerProps.page,
        form: providerProps.form,
        onValidate: (payload) => providerEmitted.validate.push(payload),
        onSave: (payload) => providerEmitted.save.push(payload),
      })
  },
})

const providerHost = dom.window.document.querySelector("#provider-contract")
const providerApp = createApp(ProviderContract)
providerApp.mount(providerHost)

const providerBoundary = providerHost.querySelector("#provider-boundary")
assert.equal(providerBoundary.tagName, "DIV")
assert.deepEqual(elementAttributes(providerBoundary), {
  class: "border-l-2 border-info/60 bg-info/10 px-4 py-3 text-sm text-base-content/70",
  id: "provider-boundary",
})
assert.deepEqual([...providerBoundary.childNodes].map((node) => node.nodeName), ["#text"])
assert.equal(providerBoundary.textContent.trim(), "Server owns provider selection.")

const providerWrappers = [...providerHost.querySelectorAll("form .fieldset")]
assert.equal(providerWrappers.length, 8, "every rendered provider field uses the foundation")
assert.ok(providerWrappers.every((wrapper) => wrapper.className === "fieldset mb-3"))
assert.ok(
  providerWrappers.every((wrapper) => {
    const label = wrapper.firstElementChild
    const control = label?.querySelector("input, select, textarea")
    return label?.tagName === "LABEL" && label.htmlFor === control?.id
  }),
)
assert.deepEqual(
  [...providerHost.querySelectorAll("form input, form select, form textarea")].map(
    (control) => control.tagName,
  ),
  ["INPUT", "SELECT", "SELECT", "INPUT", "TEXTAREA", "SELECT", "INPUT", "INPUT", "INPUT"],
  "the hidden input and native input/select/textarea order remains exact",
)
assert.equal(providerHost.querySelector('input[type="hidden"]').id, "provider_account_id")
assert.equal(providerHost.querySelector("#provider_notes").nextSibling, null)
assert.equal(
  providerHost.querySelector("#provider_notes").closest("label").nextElementSibling.textContent.trim(),
  "Visible only to operators.",
)

const providerNativeNodes = [
  ...providerHost.querySelectorAll("form input, form select, form textarea"),
]
const providerServerValues = {...providerInitial, credential: "server-credential"}
providerProps.form = deepFreeze(providerForm(providerServerValues))
await nextTick()
assert.deepEqual(
  [...providerHost.querySelectorAll("form input, form select, form textarea")],
  providerNativeNodes,
  "provider server reconciliation preserves every native node",
)
assert.equal(providerHost.querySelector("#provider_credential").value, "server-credential")

const endpoint = providerHost.querySelector("#provider_endpoint_url")
endpoint.value = "https://flight.example.test"
endpoint.dispatchEvent(new dom.window.Event("input", {bubbles: true}))
await nextTick()
assert.equal(providerEmitted.validate.at(-1).provider_account.endpoint_url, endpoint.value)

const notes = providerHost.querySelector("#provider_notes")
notes.value = "Flight provider"
notes.dispatchEvent(new dom.window.Event("input", {bubbles: true}))
await nextTick()
assert.equal(providerEmitted.validate.at(-1).provider_account.notes, notes.value)

const backend = providerHost.querySelector("#provider_backend_type")
backend.value = "graphql"
backend.dispatchEvent(new dom.window.Event("change", {bubbles: true}))
await nextTick()
assert.equal(endpoint.closest("label").querySelector("span").textContent, "GraphQL Endpoint")
assert.equal(endpoint.placeholder, "https://graphql.example.test")

const providerType = providerHost.querySelector("#provider_provider_type")
providerType.value = "atlas"
providerType.dispatchEvent(new dom.window.Event("change", {bubbles: true}))
await nextTick()
assert.equal(providerHost.querySelector("#kratos-token-field"), null)
providerType.value = "kratos"
providerType.dispatchEvent(new dom.window.Event("change", {bubbles: true}))
await nextTick()
assert.ok(providerHost.querySelector("#kratos-token-field"))

const providerSubmit = new dom.window.Event("submit", {bubbles: true, cancelable: true})
providerHost.querySelector("#provider-account-form").dispatchEvent(providerSubmit)
assert.equal(providerSubmit.defaultPrevented, true)
assert.deepEqual(providerEmitted.save, [
  {
    provider_account: {
      ...providerServerValues,
      endpoint_url: "https://flight.example.test",
      notes: "Flight provider",
      backend_type: "graphql",
    },
  },
])

const spacecraftProps = reactive({
  page: deepFreeze({
    id: "spacecraft-page",
    title: "New Spacecraft Type",
    subtitle: "Configure a flight profile.",
    breadcrumbs: [{label: "Spacecraft", href: null}],
  }),
  form: deepFreeze(spacecraftForm(spacecraftInitial)),
  options: spacecraftOptions,
  applications,
})
const spacecraftEmitted = {validate: [], save: []}
const SpacecraftContract = defineComponent({
  setup() {
    return () =>
      h(SpacecraftTypeNew, {
        page: spacecraftProps.page,
        form: spacecraftProps.form,
        options: spacecraftProps.options,
        applications: spacecraftProps.applications,
        onValidate: (payload) => spacecraftEmitted.validate.push(payload),
        onSave: (payload) => spacecraftEmitted.save.push(payload),
      })
  },
})

const spacecraftHost = dom.window.document.querySelector("#spacecraft-contract")
const spacecraftApp = createApp(SpacecraftContract)
spacecraftApp.mount(spacecraftHost)

assert.equal(spacecraftHost.querySelectorAll("form .fieldset").length, 7)
assert.ok(spacecraftHost.querySelector("#spacecraft_secondary_header_length"))
assert.ok(spacecraftHost.querySelector("#spacecraft_truncated_primary_header"))
assert.equal(spacecraftHost.querySelector("#spacecraft_insert_zone_length"), null)
assert.equal(spacecraftHost.querySelectorAll('input[type="checkbox"]').length, 2)
assert.equal(
  spacecraftHost.querySelector("#application-telemetry").closest("label").className,
  "flex items-start gap-3 rounded border p-3 transition-colors border-base-300 bg-base-100/40 border-l-2 border-l-primary/40 hover:border-l-primary cursor-pointer",
)
assert.equal(spacecraftHost.querySelector("#application-commanding").disabled, true)

const spacecraftNativeNodes = [
  ...spacecraftHost.querySelectorAll("form input, form select"),
]
const spacecraftServerValues = {...spacecraftInitial, display_name: "Server Flight Profile"}
spacecraftProps.form = deepFreeze(spacecraftForm(spacecraftServerValues))
await nextTick()
assert.deepEqual(
  [...spacecraftHost.querySelectorAll("form input, form select")],
  spacecraftNativeNodes,
  "spacecraft server reconciliation preserves every visible native node",
)
assert.equal(spacecraftHost.querySelector("#spacecraft_display_name").value, "Server Flight Profile")

const displayName = spacecraftHost.querySelector("#spacecraft_display_name")
displayName.value = "Flight Profile A"
displayName.dispatchEvent(new dom.window.Event("input", {bubbles: true}))
await nextTick()
assert.equal(spacecraftEmitted.validate.at(-1).spacecraft_type.display_name, "Flight Profile A")

const downlink = spacecraftHost.querySelector("#spacecraft_downlink_protocol")
downlink.value = "aos"
downlink.dispatchEvent(new dom.window.Event("change", {bubbles: true}))
await nextTick()
assert.equal(spacecraftHost.querySelector("#spacecraft_secondary_header_length"), null)
assert.equal(spacecraftHost.querySelector("#spacecraft_truncated_primary_header"), null)
assert.ok(spacecraftHost.querySelector("#spacecraft_insert_zone_length"))

const telemetry = spacecraftHost.querySelector("#application-telemetry")
telemetry.checked = false
telemetry.dispatchEvent(new dom.window.Event("change", {bubbles: true}))
await nextTick()
assert.deepEqual(spacecraftEmitted.validate.at(-1).spacecraft_type.applications, {})

const spacecraftSubmit = new dom.window.Event("submit", {bubbles: true, cancelable: true})
spacecraftHost.querySelector("#spacecraft-type-form").dispatchEvent(spacecraftSubmit)
assert.equal(spacecraftSubmit.defaultPrevented, true)
assert.deepEqual(spacecraftEmitted.save, [
  {
    spacecraft_type: {
      ...spacecraftServerValues,
      display_name: "Flight Profile A",
      downlink_protocol: "aos",
      applications: {},
    },
  },
])

providerApp.unmount()
spacecraftApp.unmount()
assert.equal(providerHost.children.length, 0)
assert.equal(spacecraftHost.children.length, 0)
dom.window.close()

console.log("provider_spacecraft_cadence_field_test passed")
