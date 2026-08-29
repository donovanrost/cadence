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
  `CommsTransportNew contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/CommsTransportNew.vue")
const source = await readFile(componentPath, "utf8")
const breadcrumbsImport =
  'import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"\n'
const breadcrumbNavClass =
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
const pageHeaderImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const reconstructPageHeaderSource = (value) =>
  value
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

assert.match(source, /^import CadenceField from "\.\/ui\/components\/CadenceField\.vue"$/m)
assert.match(source, /^import CadenceFormActions from "\.\/ui\/components\/CadenceFormActions\.vue"$/m)
assert.match(
  source,
  /^import CadenceFormSectionHeader from "\.\/ui\/components\/CadenceFormSectionHeader\.vue"$/m,
)
assert.equal(source.match(/<CadenceField\b/g)?.length, 7)
assert.equal(source.match(/<CadenceFormSectionHeader\b/g)?.length, 7)
assert.equal(source.match(/<CadenceFormActions\b/g)?.length, 1)
assert.equal(source.match(/<input\b/g)?.length, 5, "all five native inputs stay in the feature")
assert.equal(source.match(/<select\b/g)?.length, 6, "all six native selects stay in the feature")
assert.match(
  source,
  /<div class="fieldset mb-3">\n            <label :for="form\.fields\.transport_kind\.provider_managed_id">\n              <input\n                :id="form\.fields\.transport_kind\.provider_managed_id \?\? undefined"/,
  "the provider-managed hidden transport-kind shell stays manual",
)
assert.match(
  source,
  /<div v-if="field\.type === 'checkbox'" class="fieldset mb-3">\n                  <label class="flex cursor-pointer items-start gap-3">\n                    <input type="hidden" :name="field\.name" value="false">\n                    <input[\s\S]*?type="checkbox"[\s\S]*?<\/label>\n                <\/div>/,
  "the hidden-false and checkbox shell stays manual",
)

const extractionLedger = [
  {
    name: "display name",
    indent: "        ",
    open: `        <CadenceField
          :control-id="form.fields.display_name.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.display_name.label"
          label-class="hud-label block mb-1.5"
        >`,
    oldOpen: '        <div class="fieldset mb-3">',
    controlId: "form.fields.display_name.id",
    label: '            <span class="hud-label block mb-1.5">{{ form.fields.display_name.label }}</span>',
  },
  {
    name: "configuration owner",
    indent: "        ",
    open: `        <CadenceField
          :control-id="form.fields.origin.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.origin.label"
          label-class="hud-label block mb-1.5"
        >`,
    oldOpen: '        <div class="fieldset mb-3">',
    controlId: "form.fields.origin.id",
    label: '            <span class="hud-label block mb-1.5">{{ form.fields.origin.label }}</span>',
  },
  {
    name: "direct transport kind",
    indent: "        ",
    open: `        <CadenceField
          v-if="selectedOrigin === 'direct'"
          :control-id="form.fields.transport_kind.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.transport_kind.label"
          label-class="hud-label block mb-1.5"
        >`,
    oldOpen: `        <div v-if="selectedOrigin === 'direct'" class="fieldset mb-3">`,
    controlId: "form.fields.transport_kind.id",
    label:
      '            <span class="hud-label block mb-1.5">{{ form.fields.transport_kind.label }}</span>',
  },
  {
    name: "mission provider",
    indent: "          ",
    open: `          <CadenceField
            :control-id="form.fields.mission_provider_id.id"
            wrapper-class="fieldset mb-3"
            :label="form.fields.mission_provider_id.label"
            label-class="hud-label block mb-1.5"
          >`,
    oldOpen: '          <div class="fieldset mb-3">',
    controlId: "form.fields.mission_provider_id.id",
    label: `              <span class="hud-label block mb-1.5">
                {{ form.fields.mission_provider_id.label }}
              </span>`,
  },
  {
    name: "dynamic non-checkbox configuration field",
    indent: "                ",
    open: `                <CadenceField
                  v-else
                  :control-id="field.id"
                  wrapper-class="fieldset mb-3"
                  :label="field.label"
                  label-class="hud-label block mb-1.5"
                >`,
    oldOpen: '                <div v-else class="fieldset mb-3">',
    controlId: "field.id",
    label: '                    <span class="hud-label block mb-1.5">{{ field.label }}</span>',
    help: true,
  },
  {
    name: "service profile",
    indent: "            ",
    open: `            <CadenceField
              :control-id="form.fields.service_profile_id.id"
              wrapper-class="fieldset mb-3"
              :label="form.fields.service_profile_id.label"
              label-class="hud-label block mb-1.5"
            >`,
    oldOpen: '            <div class="fieldset mb-3">',
    controlId: "form.fields.service_profile_id.id",
    label: `                <span class="hud-label block mb-1.5">
                  {{ form.fields.service_profile_id.label }}
                </span>`,
  },
  {
    name: "delivery profile",
    indent: "            ",
    open: `            <CadenceField
              :control-id="form.fields.delivery_profile_id.id"
              wrapper-class="fieldset mb-3"
              :label="form.fields.delivery_profile_id.label"
              label-class="hud-label block mb-1.5"
            >`,
    oldOpen: '            <div class="fieldset mb-3">',
    controlId: "form.fields.delivery_profile_id.id",
    label: `                <span class="hud-label block mb-1.5">
                  {{ form.fields.delivery_profile_id.label }}
                </span>`,
  },
]

const formChromeImports = [
  'import CadenceFormActions from "./ui/components/CadenceFormActions.vue"',
  'import CadenceFormSectionHeader from "./ui/components/CadenceFormSectionHeader.vue"',
]
const actionWrapperClass = "flex items-center gap-3 border-t border-base-300/60 pt-5"
const occurrences = (value, fragment) => value.split(fragment).length - 1
const detailsFrameImport =
  'import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"\n'

const peelCadenceDetailsFrame = (value, label) => {
  assert.equal(occurrences(value, detailsFrameImport), 1, `${label} details import count`)
  assert.equal(value.match(/<CadenceDetailsFrame\b/g)?.length ?? 0, 1, `${label} details opening count`)
  assert.equal(occurrences(value, "</CadenceDetailsFrame>"), 1, `${label} details closing count`)

  const peeled = value
    .replace(detailsFrameImport, "")
    .replace("<CadenceDetailsFrame", "<details")
    .replace("</CadenceDetailsFrame>", "</details>")

  assert.doesNotMatch(peeled, /CadenceDetailsFrame/)
  return peeled
}

const peelCadenceBreadcrumbs = (value, label) => {
  const importCount = occurrences(value, breadcrumbsImport)
  const openingCount = occurrences(value, "<CadenceBreadcrumbs>")
  const closingCount = occurrences(value, "</CadenceBreadcrumbs>")

  if (importCount === 0) {
    assert.equal(openingCount, 0, `${label} has no unimported breadcrumb opening`)
    assert.equal(closingCount, 0, `${label} has no unimported breadcrumb closing`)
    return value
  }

  assert.equal(importCount, 1, `${label} has one exact breadcrumb import`)
  assert.equal(openingCount, 1, `${label} has one exact breadcrumb opening`)
  assert.equal(closingCount, 1, `${label} has one exact breadcrumb closing`)

  const openingMatch = value.match(/^( *)<CadenceBreadcrumbs>$/m)
  assert.ok(openingMatch, `${label} has an explicitly bounded breadcrumb opening`)
  const indent = openingMatch[1]
  const wrapperOpening = `${indent}<CadenceBreadcrumbs>`
  const wrapperClosing = `${indent}</CadenceBreadcrumbs>`
  const nativeOpening = `${indent}<nav
${indent}  aria-label="Breadcrumb"
${indent}  class="${breadcrumbNavClass}"
${indent}>`

  assert.equal(occurrences(value, wrapperOpening), 1, `${label} opening indentation is exact`)
  assert.equal(occurrences(value, wrapperClosing), 1, `${label} closing indentation is exact`)

  const peeled = value
    .replace(breadcrumbsImport, "")
    .replace(wrapperOpening, nativeOpening)
    .replace(wrapperClosing, `${indent}</nav>`)

  assert.equal(occurrences(peeled, "CadenceBreadcrumbs"), 0, `${label} breadcrumb peel is exact`)
  return peeled
}

const cardImport = 'import CadenceCard from "./ui/components/CadenceCard.vue"\n'
const rawReviewShell = `        <section
          :id="form.review.configuration_summary_id"
          class="card bg-base-200 border border-base-300"
        >
          <div class="card-body p-0">`
const dataRowImport = 'import CadenceDataRow from "./ui/components/CadenceDataRow.vue"\n'
const migratedDataRowOpening = `                <CadenceDataRow
                  v-for="row in form.provider_derived.configuration.rows"
                  :key="row.label"
                  row-class="hud-data-row"
                  label-class="hud-data-label"
                  :label="row.label"
                >`
const foundationDataRowOpening = `                <div
                  v-for="row in form.provider_derived.configuration.rows"
                  :key="row.label"
                  class="hud-data-row"
                >
                  <span class="hud-data-label">{{ row.label }}</span>`

const reconstructCards = (value) => {
  assert.equal(occurrences(value, cardImport), 1, "the transport imports CadenceCard once")
  assert.equal(
    value.match(/<CadenceCard\b/g)?.length ?? 0,
    1,
    "the transport has exactly one migrated p-6 card opening boundary",
  )
  assert.equal(
    occurrences(value, "</CadenceCard>"),
    1,
    "the transport has exactly one migrated p-6 card closing boundary",
  )
  assert.equal(
    occurrences(value, 'body-class="card-body p-6"'),
    1,
    "the transport has exactly one migrated p-6 card body boundary",
  )
  assert.equal(occurrences(value, rawReviewShell), 1, "the raw p-0 review card stays exact")

  let openingCount = 0
  let reconstructed = value.replace(cardImport, "")

  reconstructed = reconstructed.replace(
    /^([ \t]*)<CadenceCard\b([^>]*)>\n/gm,
    (_opening, indentation, rawAttributes) => {
      openingCount += 1
      assert.equal(
        occurrences(rawAttributes, 'body-class="card-body p-6"'),
        1,
        "the transport card boundary owns one exact body class",
      )

      const sectionAttributes = rawAttributes
        .replace(/\n[ \t]*body-class="card-body p-6"/, "")
        .replace(/ body-class="card-body p-6"/, "")

      assert.doesNotMatch(sectionAttributes, /body-class=/)
      return (
        `${indentation}<section${sectionAttributes}>\n` +
        `${indentation}  <div class="card-body p-6">\n`
      )
    },
  )

  assert.equal(openingCount, 1, "the transport reconstructs its one card opening")

  let closingCount = 0
  reconstructed = reconstructed.replace(/^([ \t]*)<\/CadenceCard>$/gm, (_closing, indentation) => {
    closingCount += 1
    return `${indentation}  </div>\n${indentation}</section>`
  })

  assert.equal(closingCount, 1, "the transport reconstructs its one card closing")
  assert.equal(occurrences(reconstructed, rawReviewShell), 1, "the pre-card source keeps the raw p-0 card")
  assert.doesNotMatch(reconstructed, /CadenceCard/, "the pre-card source has no residual primitive")
  return reconstructed
}

const reconstructDataRow = (value) => {
  assert.equal(occurrences(value, dataRowImport), 1, "the transport imports CadenceDataRow once")
  assert.equal(
    occurrences(value, migratedDataRowOpening),
    1,
    "the transport has exactly one migrated data-row opening boundary",
  )
  assert.equal(
    occurrences(value, "</CadenceDataRow>"),
    1,
    "the transport has exactly one migrated data-row closing boundary",
  )

  const reconstructed = value
    .replace(dataRowImport, "")
    .replace(migratedDataRowOpening, foundationDataRowOpening)
    .replace("</CadenceDataRow>", "</div>")

  assert.doesNotMatch(reconstructed, /CadenceDataRow/, "the pre-data-row source has no residual primitive")
  return reconstructed
}

const formChromeHeader = (
  key,
  numberExpression,
  titleExpression,
  {indent = 8, multilineNumber = false, dividerClass = "flex-1 h-px bg-base-300/60"} = {},
) => ({key, numberExpression, titleExpression, indent, multilineNumber, dividerClass})
const formChromeHeaders = [
  formChromeHeader("identity", "form.sections.identity.number", "form.sections.identity.title"),
  formChromeHeader("origin", "form.sections.origin.number", "form.sections.origin.title"),
  formChromeHeader("source", "form.sections.source.number", "form.sections.source.title"),
  formChromeHeader("direct configuration", "section.number", "section.title", {indent: 10}),
  formChromeHeader(
    "provider capability",
    "form.sections.provider_capability.number",
    "form.sections.provider_capability.title",
    {indent: 10, multilineNumber: true},
  ),
  formChromeHeader(
    "provider derived",
    "form.provider_derived.number",
    "form.provider_derived.title",
    {indent: 10, dividerClass: "h-px flex-1 bg-base-300/60"},
  ),
  formChromeHeader(
    "review",
    "form.sections.review.number",
    "form.sections.review.title",
    {dividerClass: "h-px flex-1 bg-base-300/60"},
  ),
]

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

const reconstructFormChrome = (value) => {
  assert.equal(
    occurrences(value, "<CadenceFormSectionHeader\n"),
    formChromeHeaders.length,
    "all seven transport form-section headers stay in the reconstruction ledger",
  )
  assert.equal(
    occurrences(value, `<CadenceFormActions wrapper-class="${actionWrapperClass}">`),
    1,
    "the transport action row stays in the reconstruction ledger",
  )

  let reconstructed = value
  for (const importLine of formChromeImports) {
    assert.equal(occurrences(reconstructed, `${importLine}\n`), 1)
    reconstructed = reconstructed.replace(`${importLine}\n`, "")
  }

  for (const entry of formChromeHeaders) {
    const migrated = migratedHeader(entry)
    assert.equal(occurrences(reconstructed, migrated), 1, `${entry.key} reconstructs once`)
    reconstructed = reconstructed.replace(migrated, foundationHeader(entry))
  }

  const actionsOpen = `      <CadenceFormActions wrapper-class="${actionWrapperClass}">`
  assert.equal(occurrences(reconstructed, actionsOpen), 1)
  reconstructed = reconstructed.replace(actionsOpen, `      <div class="${actionWrapperClass}">`)
  assert.equal(occurrences(reconstructed, "      </CadenceFormActions>"), 1)
  reconstructed = reconstructed.replace("      </CadenceFormActions>", "      </div>")

  return reconstructed
}

let reconstructedSource = reconstructDataRow(
  reconstructCards(
    reconstructPageHeaderSource(
      peelCadenceBreadcrumbs(
        peelCadenceDetailsFrame(
          peelCadenceNoticeFrames(
            peelCadencePageTitle(source, "CommsTransportNew.vue"),
            "CommsTransportNew.vue",
          ),
          "CommsTransportNew.vue",
        ),
        "CommsTransportNew.vue",
      ),
    ),
  ),
).replace(
  'import CadenceField from "./ui/components/CadenceField.vue"\n',
  "",
)

for (const entry of extractionLedger) {
  const start = reconstructedSource.indexOf(entry.open)
  assert.notEqual(start, -1, `${entry.name} has its exact ledger opening`)
  const close = `\n${entry.indent}</CadenceField>`
  const end = reconstructedSource.indexOf(close, start + entry.open.length)
  assert.notEqual(end, -1, `${entry.name} has its exact ledger closing`)
  let controls = reconstructedSource.slice(start + entry.open.length, end)
  let oldHelp = ""

  if (entry.help) {
    const help = `
${entry.indent}  <template v-if="field.help" #help>
${entry.indent}    <p class="-mt-1 mb-3 text-xs text-base-content/55">
${entry.indent}      {{ field.help }}
${entry.indent}    </p>
${entry.indent}  </template>`
    assert.ok(controls.endsWith(help), "dynamic help keeps the exact CadenceField slot ledger")
    controls = controls.slice(0, -help.length)
    oldHelp = `
${entry.indent}  <p v-if="field.help" class="-mt-1 mb-3 text-xs text-base-content/55">
${entry.indent}    {{ field.help }}
${entry.indent}  </p>`
  }

  const shiftedControls = controls.replaceAll(
    `\n${entry.indent}  `,
    `\n${entry.indent}    `,
  )
  const original = `${entry.oldOpen}
${entry.indent}  <label :for="${entry.controlId}">
${entry.label}${shiftedControls}
${entry.indent}  </label>${oldHelp}
${entry.indent}</div>`
  reconstructedSource =
    reconstructedSource.slice(0, start) +
    original +
    reconstructedSource.slice(end + close.length)
}

reconstructedSource = reconstructFormChrome(reconstructedSource)

assert.equal(
  createHash("sha256").update(reconstructedSource).digest("hex"),
  "0dd9bfdf2e943ea49f1254313c0a4828c9a337ac9a4e6a608f596d17bfa435e2",
  "removing the seven transparent field boundaries reconstructs the immutable base source",
)

const option = (label, value, disabled = false) => ({label, value, disabled})
const fieldIds = {
  display_name: "transport-display-name",
  origin: "transport-origin",
  transport_kind: "transport-kind",
  mission_provider_id: "transport-provider",
  service_profile_id: "transport-service-profile",
  delivery_profile_id: "transport-delivery-profile",
}
const field = (key, type, label, value, overrides = {}) => ({
  key,
  id: fieldIds[key],
  name: `transport[${key}]`,
  type,
  label,
  required: true,
  placeholder: null,
  options: [],
  value,
  provider_managed_id: null,
  ...overrides,
})
const configurationField = (key, type, label, value, overrides = {}) => ({
  key,
  wrapper_id: `transport-direct-configuration-field-${key.replaceAll("_", "-")}`,
  id: `transport-direct-configuration-input-${key.replaceAll("_", "-")}`,
  name: `transport[${key}]`,
  type,
  label,
  required: false,
  placeholder: null,
  help: null,
  step: null,
  min: null,
  max: null,
  default: "",
  value,
  options: [],
  visible: true,
  visible_when: null,
  ...overrides,
})

const initialValues = {
  display_name: "Relay TCP",
  origin: "direct",
  transport_kind: "tcp_socket",
  mission_provider_id: "provider-1",
  service_profile_id: "service-1",
  delivery_profile_id: "delivery-1",
  tcp_mode: "listen",
  host: "0.0.0.0",
  port: "5001",
  framing_mode: "raw",
  frame_size: "64",
  reconnect_policy: "always",
  tls_enabled: "false",
}

const formWithValues = (values) => ({
  id: "transport-form",
  selected_origin: values.origin,
  can_submit: true,
  sections: {
    identity: {id: "transport-identity-section", number: "01", title: "Identity"},
    origin: {id: "transport-origin-section", number: "02", title: "Origin"},
    source: {id: "transport-source-section", number: "03", title: "Source"},
    provider_capability: {id: "transport-capability-section", number: "04", title: "Capability"},
    review: {id: "transport-summary-section", number: "06", title: "Review"},
  },
  fields: {
    display_name: field("display_name", "text", "Display Name", values.display_name),
    origin: field("origin", "select", "Configuration Owner", values.origin, {
      options: [
        option("Direct — configured in Cadence", "direct"),
        option("Ground Station Provider", "provider_managed"),
      ],
    }),
    transport_kind: field("transport_kind", "select", "Transport Kind", values.transport_kind, {
      options: [option("TCP socket", "tcp_socket"), option("UDP", "udp")],
      provider_managed_id: "transport-kind-provider-managed",
    }),
    mission_provider_id: field(
      "mission_provider_id",
      "select",
      "Ground Network Provider",
      values.mission_provider_id,
      {
        placeholder: "Select a validated provider",
        options: [option("Deep Space Network · v4", "provider-1"), option("Near Space · v2", "provider-2")],
      },
    ),
    service_profile_id: field(
      "service_profile_id",
      "select",
      "Service Profile",
      values.service_profile_id,
      {
        placeholder: "Select service",
        options: [option("Realtime telemetry · v3", "service-1"), option("Realtime telemetry · v4", "service-2")],
      },
    ),
    delivery_profile_id: field(
      "delivery_profile_id",
      "select",
      "Delivery Profile",
      values.delivery_profile_id,
      {
        placeholder: "Select delivery",
        options: [option("Streaming to Cadence", "delivery-1"), option("Buffered delivery", "delivery-2")],
      },
    ),
  },
  origin_cards: [
    {value: "direct", label: "Direct", description: "Cadence owns the endpoint."},
    {
      value: "provider_managed",
      label: "Ground Station Provider",
      description: "Provider profiles own runtime setup.",
    },
  ],
  direct_configuration: {
    id: "transport-direct-configuration",
    kind: "transport_kind",
    description: "Cadence owns this endpoint, framing boundary, and reconnect behavior.",
    active: values.origin === "direct",
    sections: [
      {
        id: "transport-capability-section",
        fields_id: "transport-capability-section-fields",
        number: "04",
        title: "TCP Capability",
        description: null,
        fields: [
          configurationField("tcp_mode", "select", "TCP Mode", values.tcp_mode, {
            options: [option("Listen", "listen"), option("Connect", "connect")],
          }),
          configurationField("host", "text", "Host", values.host, {
            placeholder: "0.0.0.0",
            required: true,
            help: "Bind or remote host, depending on TCP mode.",
          }),
          configurationField("port", "number", "Port", values.port, {
            required: true,
            step: 1,
            min: 1,
            max: 65535,
          }),
        ],
      },
      {
        id: "transport-framing-section",
        fields_id: "transport-framing-section-fields",
        number: "05",
        title: "Framing",
        description: null,
        fields: [
          configurationField("framing_mode", "select", "Framing Mode", values.framing_mode, {
            options: [option("Raw", "raw"), option("Fixed size", "fixed_size")],
          }),
          configurationField("frame_size", "number", "Frame Size", values.frame_size, {
            step: 1,
            min: 1,
            visible: values.framing_mode === "fixed_size",
            visible_when: {field: "framing_mode", equals: "fixed_size"},
          }),
        ],
      },
      {
        id: "transport-reliability-section",
        fields_id: "transport-reliability-section-fields",
        number: "05B",
        title: "Reliability",
        description: null,
        fields: [
          configurationField(
            "reconnect_policy",
            "select",
            "Reconnect Policy",
            values.reconnect_policy,
            {
              options: [option("Always", "always"), option("Never", "never")],
              visible: values.tcp_mode === "connect",
              visible_when: {field: "tcp_mode", equals: "connect"},
            },
          ),
          configurationField("tls_enabled", "checkbox", "Enable TLS", values.tls_enabled),
        ],
      },
    ],
  },
  provider: {
    active: values.origin === "provider_managed",
    profile_fields_id: "transport-provider-profile-fields",
    ready_count: 2,
    selected: {
      display_name: "Deep Space Network",
      version: 4,
      status: "ready",
      status_label: "Profiles synced",
    },
    empty_state: {
      id: "transport-provider-empty-state",
      visible: false,
      message: "No validated providers.",
      action: {label: "Review providers", href: "/missions/mission-1/comms/providers"},
    },
    operator_summary: {
      id: "transport-provider-operator-summary",
      label: "Operator Summary",
      text: "Streaming to Cadence",
      endpoint: "127.0.0.1:5100",
    },
    derivation_error: null,
  },
  provider_derived: {
    active: values.origin === "provider_managed",
    id: "transport-provider-derived-section",
    number: "05",
    title: "Provider-Derived Runtime",
    description: "Runtime configuration remains provider-owned.",
    configuration: {
      id: "transport-provider-derived-configuration",
      rows: [{label: "Endpoint", value: "127.0.0.1:5100", mono: true}],
      empty_text: null,
    },
  },
  review: {
    configuration_summary_id: "transport-configuration-summary",
    ownership: {label: "Ownership", value: "Direct", source: "Cadence"},
    readiness: {
      label: "Readiness",
      status: "ready",
      value: "Ready to save",
      endpoint: "0.0.0.0:5001",
    },
    error: null,
    error_id: "transport-form-error",
    diagnostics: {
      id: "transport-admin-diagnostics",
      label: "Administrator Diagnostics",
      json_id: "transport-admin-diagnostics-json",
      json: "{}",
    },
  },
  actions: {
    submit: {id: "create-transport-button", label: "Create Transport"},
    cancel: {
      id: "cancel-transport-link",
      label: "Cancel",
      href: "/missions/mission-1/comms/transports",
    },
  },
})

const deepFreeze = (value) => {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value)
    Object.values(value).forEach(deepFreeze)
  }

  return value
}

const dom = installDom('<div id="transport-contract"></div>')
for (const globalName of [
  "Document",
  "ShadowRoot",
  "HTMLFormElement",
  "HTMLInputElement",
  "HTMLSelectElement",
  "FormData",
]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const {component: CommsTransportNew} = await loadSfc(componentPath)
const {createApp, defineComponent, h, nextTick, reactive} = integrationRequire("vue")
let currentValues = {...initialValues}
const liveProps = reactive({
  page: deepFreeze({
    id: "comms-transport-new-page",
    title: "New Transport",
    subtitle: "Describe a durable byte-moving capability.",
    breadcrumbs: [
      {label: "Mission One", href: "/missions/mission-1"},
      {label: "Transports", href: "/missions/mission-1/comms/transports"},
      {label: "New Transport", href: null},
    ],
  }),
  form: deepFreeze(formWithValues(currentValues)),
})
const emitted = {validate: [], save: []}
const Contract = defineComponent({
  setup() {
    return () =>
      h(CommsTransportNew, {
        page: liveProps.page,
        form: liveProps.form,
        onValidate: (payload) => emitted.validate.push(payload),
        onSave: (payload) => emitted.save.push(payload),
      })
  },
})

const host = dom.window.document.querySelector("#transport-contract")
const app = createApp(Contract)
app.mount(host)

const form = host.querySelector("#transport-form")
const control = (id) => host.querySelector(`#${id}`)
const assertFieldShell = (nativeControl, label, help = null) => {
  const nativeLabel = nativeControl.parentElement
  const wrapper = nativeLabel.parentElement
  assert.equal(wrapper.tagName, "DIV")
  assert.deepEqual(elementAttributes(wrapper), {class: "fieldset mb-3"})
  assert.deepEqual(elementAttributes(nativeLabel), {for: nativeControl.id})
  assert.deepEqual(
    [...nativeLabel.children].map((child) => child.tagName),
    ["SPAN", nativeControl.tagName],
  )
  assert.deepEqual(elementAttributes(nativeLabel.firstElementChild), {
    class: "hud-label block mb-1.5",
  })
  assert.equal(nativeLabel.firstElementChild.textContent, label)
  assert.deepEqual(
    [...wrapper.children].map((child) => child.tagName),
    help === null ? ["LABEL"] : ["LABEL", "P"],
  )
  if (help !== null) assert.equal(wrapper.lastElementChild.textContent.trim(), help)
  return wrapper
}

const displayName = control("transport-display-name")
const origin = control("transport-origin")
const transportKind = control("transport-kind")
const tcpMode = control("transport-direct-configuration-input-tcp-mode")
const hostInput = control("transport-direct-configuration-input-host")
const port = control("transport-direct-configuration-input-port")
const framingMode = control("transport-direct-configuration-input-framing-mode")
const tls = control("transport-direct-configuration-input-tls-enabled")

assertFieldShell(displayName, "Display Name")
assertFieldShell(origin, "Configuration Owner")
assertFieldShell(transportKind, "Transport Kind")
assertFieldShell(tcpMode, "TCP Mode")
assertFieldShell(hostInput, "Host", "Bind or remote host, depending on TCP mode.")
assertFieldShell(port, "Port")
assertFieldShell(framingMode, "Framing Mode")
assert.deepEqual(elementAttributes(displayName), {
  class: "w-full input",
  id: "transport-display-name",
  name: "transport[display_name]",
  required: "",
  type: "text",
  value: "Relay TCP",
})
assert.deepEqual(elementAttributes(transportKind), {
  class: "w-full select",
  id: "transport-kind",
  name: "transport[transport_kind]",
  required: "",
  value: "tcp_socket",
})

const checkboxFieldset = tls.closest(".fieldset")
const checkboxLabel = checkboxFieldset.querySelector("label")
const checkboxControls = checkboxLabel.querySelectorAll("input")
assert.deepEqual(elementAttributes(checkboxFieldset), {class: "fieldset mb-3"})
assert.deepEqual(elementAttributes(checkboxLabel), {
  class: "flex cursor-pointer items-start gap-3",
})
assert.deepEqual(
  [...checkboxLabel.children].map((child) => child.tagName),
  ["INPUT", "INPUT", "SPAN"],
)
assert.deepEqual(elementAttributes(checkboxControls[0]), {
  name: "transport[tls_enabled]",
  type: "hidden",
  value: "false",
})
assert.deepEqual(elementAttributes(checkboxControls[1]), {
  class: "checkbox checkbox-sm mt-0.5",
  id: "transport-direct-configuration-input-tls-enabled",
  name: "transport[tls_enabled]",
  type: "checkbox",
  value: "true",
})
assert.deepEqual(new dom.window.FormData(form).getAll("transport[tls_enabled]"), ["false"])

const directPayload = (values) => ({
  transport: {
    display_name: values.display_name,
    origin: "direct",
    transport_kind: values.transport_kind,
    tcp_mode: values.tcp_mode,
    host: values.host,
    port: values.port,
    framing_mode: values.framing_mode,
    ...(values.framing_mode === "fixed_size" ? {frame_size: values.frame_size} : {}),
    ...(values.tcp_mode === "connect" ? {reconnect_policy: values.reconnect_policy} : {}),
    tls_enabled: values.tls_enabled,
  },
})
const patchForm = async (overrides) => {
  currentValues = {...currentValues, ...overrides}
  liveProps.form = deepFreeze(formWithValues(currentValues))
  await nextTick()
}

displayName.value = "Relay TCP Edited"
displayName.dispatchEvent(new dom.window.Event("input", {bubbles: true}))
await nextTick()
currentValues = {...currentValues, display_name: "Relay TCP Edited"}
assert.deepEqual(emitted.validate.at(-1), directPayload(currentValues))

liveProps.form = deepFreeze(formWithValues(initialValues))
await nextTick()
assert.equal(displayName.value, "Relay TCP Edited", "a stale patch does not erase local typing")
await patchForm({})
assert.strictEqual(control("transport-display-name"), displayName)
assert.strictEqual(control("transport-origin"), origin)
assert.strictEqual(control("transport-kind"), transportKind)

transportKind.value = "udp"
transportKind.dispatchEvent(new dom.window.Event("change", {bubbles: true}))
await nextTick()
currentValues = {...currentValues, transport_kind: "udp"}
assert.deepEqual(emitted.validate.at(-1), directPayload(currentValues))
await patchForm({})
assert.strictEqual(control("transport-kind"), transportKind)

transportKind.value = "tcp_socket"
transportKind.dispatchEvent(new dom.window.Event("change", {bubbles: true}))
await nextTick()
currentValues = {...currentValues, transport_kind: "tcp_socket"}
assert.deepEqual(emitted.validate.at(-1), directPayload(currentValues))
await patchForm({})

tcpMode.value = "connect"
tcpMode.dispatchEvent(new dom.window.Event("change", {bubbles: true}))
await nextTick()
currentValues = {...currentValues, tcp_mode: "connect"}
assert.deepEqual(emitted.validate.at(-1), {
  transport: {
    display_name: currentValues.display_name,
    origin: "direct",
    transport_kind: "tcp_socket",
    tcp_mode: "connect",
    host: "0.0.0.0",
    port: "5001",
    framing_mode: "raw",
    tls_enabled: "false",
  },
})
const reconnectPolicy = control("transport-direct-configuration-input-reconnect-policy")
assertFieldShell(reconnectPolicy, "Reconnect Policy")
await patchForm({})
assert.strictEqual(control("transport-direct-configuration-input-reconnect-policy"), reconnectPolicy)

framingMode.value = "fixed_size"
framingMode.dispatchEvent(new dom.window.Event("change", {bubbles: true}))
await nextTick()
currentValues = {...currentValues, framing_mode: "fixed_size"}
const framingValidation = directPayload(currentValues)
delete framingValidation.transport.frame_size
assert.deepEqual(emitted.validate.at(-1), framingValidation)
const frameSize = control("transport-direct-configuration-input-frame-size")
assertFieldShell(frameSize, "Frame Size")
await patchForm({})
assert.strictEqual(control("transport-direct-configuration-input-frame-size"), frameSize)

frameSize.value = "128"
frameSize.dispatchEvent(new dom.window.Event("input", {bubbles: true}))
await nextTick()
currentValues = {...currentValues, frame_size: "128"}
assert.deepEqual(emitted.validate.at(-1), directPayload(currentValues))
await patchForm({})

tls.checked = true
tls.dispatchEvent(new dom.window.Event("change", {bubbles: true}))
await nextTick()
currentValues = {...currentValues, tls_enabled: "true"}
assert.deepEqual(emitted.validate.at(-1), directPayload(currentValues))
assert.deepEqual(new dom.window.FormData(form).getAll("transport[tls_enabled]"), ["false", "true"])
await patchForm({})

const directNodeIds = [
  "transport-display-name",
  "transport-origin",
  "transport-kind",
  "transport-direct-configuration-input-tcp-mode",
  "transport-direct-configuration-input-host",
  "transport-direct-configuration-input-port",
  "transport-direct-configuration-input-framing-mode",
  "transport-direct-configuration-input-frame-size",
  "transport-direct-configuration-input-reconnect-policy",
  "transport-direct-configuration-input-tls-enabled",
]
const directNodes = directNodeIds.map(control)
await patchForm({display_name: "Authoritative Relay", host: "relay.example", port: "6000", tls_enabled: "false"})
assert.deepEqual(directNodeIds.map(control), directNodes, "direct native nodes survive reconciliation")
assert.equal(displayName.value, "Authoritative Relay")
assert.equal(hostInput.value, "relay.example")
assert.equal(port.value, "6000")
assert.equal(tls.checked, false)
assert.deepEqual(new dom.window.FormData(form).getAll("transport[tls_enabled]"), ["false"])

const directSubmit = new dom.window.Event("submit", {bubbles: true, cancelable: true})
form.dispatchEvent(directSubmit)
assert.equal(directSubmit.defaultPrevented, true)
assert.deepEqual(emitted.save, [directPayload(currentValues)])

await patchForm({
  origin: "provider_managed",
  mission_provider_id: "provider-1",
  service_profile_id: "service-1",
  delivery_profile_id: "delivery-1",
})
assert.strictEqual(control("transport-display-name"), displayName)
assert.strictEqual(control("transport-origin"), origin)
assert.equal(control("transport-direct-configuration-input-host"), null)

const hiddenKind = control("transport-kind-provider-managed")
const hiddenKindLabel = hiddenKind.parentElement
const hiddenKindFieldset = hiddenKindLabel.parentElement
assert.deepEqual(elementAttributes(hiddenKindFieldset), {class: "fieldset mb-3"})
assert.deepEqual(elementAttributes(hiddenKindLabel), {for: "transport-kind-provider-managed"})
assert.deepEqual([...hiddenKindLabel.children].map((child) => child.tagName), ["INPUT"])
assert.deepEqual(elementAttributes(hiddenKind), {
  class: "w-full input",
  id: "transport-kind-provider-managed",
  name: "transport[transport_kind]",
  type: "hidden",
  value: "tcp_socket",
})

const missionProvider = control("transport-provider")
const serviceProfile = control("transport-service-profile")
const deliveryProfile = control("transport-delivery-profile")
assertFieldShell(missionProvider, "Ground Network Provider")
assertFieldShell(serviceProfile, "Service Profile")
assertFieldShell(deliveryProfile, "Delivery Profile")
assert.deepEqual(
  [...serviceProfile.options].map(({textContent, value, disabled}) => ({
    label: textContent,
    value,
    disabled,
  })),
  [
    {label: "Select service", value: "", disabled: false},
    {label: "Realtime telemetry · v3", value: "service-1", disabled: false},
    {label: "Realtime telemetry · v4", value: "service-2", disabled: false},
  ],
)

const providerPayload = (values) => ({
  transport: {
    display_name: values.display_name,
    origin: "provider_managed",
    transport_kind: values.transport_kind,
    mission_provider_id: values.mission_provider_id,
    service_profile_id: values.service_profile_id,
    delivery_profile_id: values.delivery_profile_id,
  },
})

missionProvider.value = "provider-2"
missionProvider.dispatchEvent(new dom.window.Event("change", {bubbles: true}))
await nextTick()
currentValues = {...currentValues, mission_provider_id: "provider-2"}
assert.deepEqual(emitted.validate.at(-1), providerPayload(currentValues))
await patchForm({})

serviceProfile.value = "service-2"
serviceProfile.dispatchEvent(new dom.window.Event("change", {bubbles: true}))
await nextTick()
currentValues = {...currentValues, service_profile_id: "service-2"}
assert.deepEqual(emitted.validate.at(-1), providerPayload(currentValues))
await patchForm({})

deliveryProfile.value = "delivery-2"
deliveryProfile.dispatchEvent(new dom.window.Event("change", {bubbles: true}))
await nextTick()
currentValues = {...currentValues, delivery_profile_id: "delivery-2"}
assert.deepEqual(emitted.validate.at(-1), providerPayload(currentValues))
await patchForm({})
assert.deepEqual(
  [
    control("transport-provider"),
    control("transport-service-profile"),
    control("transport-delivery-profile"),
  ],
  [missionProvider, serviceProfile, deliveryProfile],
  "provider profile native nodes survive prop acknowledgements",
)

const noticeForm = formWithValues(currentValues)
noticeForm.provider.empty_state.visible = true
noticeForm.provider.derivation_error = "Provider derivation failed."
liveProps.form = deepFreeze(noticeForm)
await nextTick()

const providerEmptyState = control("transport-provider-empty-state")
assert.equal(providerEmptyState.tagName, "DIV")
assert.deepEqual(elementAttributes(providerEmptyState), {
  class: "border-l-2 border-warning/60 bg-warning/10 px-4 py-3 text-sm text-base-content/70",
  id: "transport-provider-empty-state",
})
assert.deepEqual(
  [...providerEmptyState.childNodes].map((node) => node.nodeName),
  ["#text", "A"],
)
assert.equal(providerEmptyState.childNodes[0].textContent.trim(), "No validated providers.")
const providerRedirect = providerEmptyState.querySelector("a")
assert.deepEqual(elementAttributes(providerRedirect), {
  class: "ml-1 text-primary hover:underline",
  "data-phx-link": "redirect",
  "data-phx-link-state": "push",
  href: "/missions/mission-1/comms/providers",
})
assert.equal(providerRedirect.textContent, "Review providers")

const providerDerivationError = control("transport-provider-derivation-error")
assert.equal(providerDerivationError.tagName, "DIV")
assert.deepEqual(elementAttributes(providerDerivationError), {
  class: "border-l-2 border-warning/60 bg-warning/10 px-4 py-3 text-sm text-base-content/70",
  id: "transport-provider-derivation-error",
})
assert.deepEqual(
  [...providerDerivationError.childNodes].map((node) => node.nodeName),
  ["#text"],
)
assert.equal(providerDerivationError.textContent.trim(), "Provider derivation failed.")

const reconciledNoticeForm = formWithValues(currentValues)
reconciledNoticeForm.provider.empty_state.visible = true
reconciledNoticeForm.provider.empty_state.message = "No validated providers remain."
reconciledNoticeForm.provider.derivation_error = "Provider derivation still failed."
liveProps.form = deepFreeze(reconciledNoticeForm)
await nextTick()
assert.strictEqual(control("transport-provider-empty-state").querySelector("a"), providerRedirect)
assert.equal(
  control("transport-provider-empty-state").childNodes[0].textContent.trim(),
  "No validated providers remain.",
)
assert.equal(
  control("transport-provider-derivation-error").textContent.trim(),
  "Provider derivation still failed.",
)

liveProps.form = deepFreeze(formWithValues(currentValues))
await nextTick()
assert.equal(control("transport-provider-empty-state"), null)
assert.equal(control("transport-provider-derivation-error"), null)

const providerSubmit = new dom.window.Event("submit", {bubbles: true, cancelable: true})
form.dispatchEvent(providerSubmit)
assert.equal(providerSubmit.defaultPrevented, true)
assert.deepEqual(emitted.save, [directPayload({...currentValues, origin: "direct"}), providerPayload(currentValues)])
assert.deepEqual(elementAttributes(control("create-transport-button")), {
  class: "btn btn-primary",
  id: "create-transport-button",
  type: "submit",
})
assert.deepEqual(elementAttributes(control("cancel-transport-link")), {
  class: "btn btn-ghost",
  "data-phx-link": "redirect",
  "data-phx-link-state": "push",
  href: "/missions/mission-1/comms/transports",
  id: "cancel-transport-link",
})

app.unmount()
assert.equal(host.children.length, 0)
dom.window.close()

console.log("comms_transport_cadence_field_test passed")
