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

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `CommsGroundStationForm contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/CommsGroundStationForm.vue")
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
const occurrences = (value, fragment) => value.split(fragment).length - 1

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
const extractionLedger = Object.freeze([
  "all five CadenceField boundaries remain one-for-one",
  "all three section headers reconstruct their exact native DOM",
  "the action row reconstructs its exact native wrapper",
  "native fields and validation events remain feature-owned",
  "native submit and redirect controls remain feature-owned",
  "the parent form retains submit prevention and save authority",
])

assert.match(source, /^import CadenceField from "\.\/ui\/components\/CadenceField\.vue"$/m)
assert.match(source, /^import CadenceFormActions from "\.\/ui\/components\/CadenceFormActions\.vue"$/m)
assert.match(
  source,
  /^import CadenceFormSectionHeader from "\.\/ui\/components\/CadenceFormSectionHeader\.vue"$/m,
)
assert.equal(extractionLedger.length, 6)
assert.equal(source.match(/<CadenceField\b/g)?.length, 5)
assert.equal(source.match(/<CadenceFormSectionHeader\b/g)?.length, 3)
assert.equal(source.match(/<CadenceFormActions\b/g)?.length, 1)
assert.equal(source.match(/<input\b/g)?.length, 4, "all four native inputs stay in the feature")
assert.equal(source.match(/<textarea\b/g)?.length, 1, "the native textarea stays in the feature")
assert.equal(source.match(/<button\b/g)?.length, 1, "the native submit button stays in the feature")
assert.equal(source.match(/\bv-model="groundStation\./g)?.length, 5)
assert.equal(source.match(/@input="validate"/g)?.length, 5)
assert.match(source, /<form :id="form\.id" class="space-y-8" @submit\.prevent="save">/)
assert.match(
  source,
  /<button :id="form\.actions\.submit\.id" type="submit" class="btn btn-primary">/,
)
assert.match(
  source,
  /:id="form\.actions\.cancel\.id"\n          :href="form\.actions\.cancel\.href"\n          data-phx-link="redirect"\n          data-phx-link-state="push"\n          class="btn btn-ghost"/,
)

let reconstructedSource = reconstructPageHeaderSource(
  peelCadenceBreadcrumbs(
    peelCadencePageTitle(source, "CommsGroundStationForm.vue"),
    "CommsGroundStationForm.vue",
  ),
).replace(
  /import CadenceField from "\.\/ui\/components\/CadenceField\.vue"\nimport CadenceFormActions from "\.\/ui\/components\/CadenceFormActions\.vue"\nimport CadenceFormSectionHeader from "\.\/ui\/components\/CadenceFormSectionHeader\.vue"\n/,
  "",
)
let reconstructedSectionHeaders = 0
reconstructedSource = reconstructedSource.replace(
  /        <CadenceFormSectionHeader\n          wrapper-class="flex items-center gap-3"\n          :number="form\.sections\.(\w+)\.number"\n          number-class="hud-label text-primary\/70"\n          :title="form\.sections\.\1\.title"\n          title-class="hud-label"\n          divider-class="flex-1 h-px bg-base-300\/60"\n        \/>/g,
  (_match, sectionKey) => {
    reconstructedSectionHeaders += 1

    return `        <div class="flex items-center gap-3">
          <span class="hud-label text-primary/70">{{ form.sections.${sectionKey}.number }}</span>
          <h2 class="hud-label">{{ form.sections.${sectionKey}.title }}</h2>
          <div class="flex-1 h-px bg-base-300/60"></div>
        </div>`
  },
)
let reconstructedActionRows = 0
reconstructedSource = reconstructedSource.replace(
  /      <CadenceFormActions wrapper-class="flex items-center gap-3 border-t border-base-300\/60 pt-5">\n([\s\S]*?)\n      <\/CadenceFormActions>/g,
  (_match, controls) => {
    reconstructedActionRows += 1
    return `      <div class="flex items-center gap-3 border-t border-base-300/60 pt-5">
${controls}
      </div>`
  },
)
let reconstructedFields = 0
reconstructedSource = reconstructedSource.replace(
  /        <CadenceField\n          :control-id="form\.fields\.(\w+)\.id"\n          wrapper-class="fieldset mb-3"\n          :label="form\.fields\.\1\.label"\n          label-class="hud-label block mb-1\.5"\n        >\n([\s\S]*?)\n        <\/CadenceField>/g,
  (_match, fieldKey, control) => {
    reconstructedFields += 1
    const originalControl = control
      .split("\n")
      .map((line) => `  ${line}`)
      .join("\n")

    return `        <div class="fieldset mb-3">
          <label :for="form.fields.${fieldKey}.id">
            <span class="hud-label block mb-1.5">{{ form.fields.${fieldKey}.label }}</span>
${originalControl}
          </label>
        </div>`
  },
)

assert.equal(reconstructedFields, 5, "all five field extractions reconstruct one-for-one")
assert.equal(
  reconstructedSectionHeaders,
  3,
  "all three section-header extractions reconstruct one-for-one",
)
assert.equal(reconstructedActionRows, 1, "the action-row extraction reconstructs one-for-one")
assert.equal(
  createHash("sha256").update(reconstructedSource).digest("hex"),
  "b7f80ed95e0adcace28277b6d31ef5c33d1ac8961ea47af048576feedb38173c",
  "removing the transparent field and form-chrome boundaries reconstructs the immutable canary source",
)

const deepFreeze = (value) => {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value)
    Object.values(value).forEach(deepFreeze)
  }

  return value
}

const field = (key, type, label, value, overrides = {}) => ({
  id: `ground_station_${key}`,
  name: `ground_station[${key}]`,
  type,
  label,
  required: false,
  disabled: false,
  placeholder: null,
  value,
  ...overrides,
})

const formWithValues = (values) => ({
  id: "ground-station-form",
  sections: {
    identity: {id: "ground-station-identity", number: "01", title: "Identity"},
    network: {id: "ground-station-network", number: "02", title: "Network"},
    metadata: {id: "ground-station-metadata", number: "03", title: "Metadata"},
  },
  fields: {
    ground_station_id: field(
      "ground_station_id",
      "text",
      "Ground Station ID",
      values.ground_station_id,
      {required: true, placeholder: "DSS-14"},
    ),
    display_name: field("display_name", "text", "Display Name", values.display_name, {
      required: true,
      placeholder: "Goldstone DSS-14",
    }),
    provider: field("provider", "text", "Provider", values.provider, {disabled: true}),
    region: field("region", "text", "Region", values.region),
    metadata_json: field("metadata_json", "textarea", "Metadata JSON", values.metadata_json, {
      placeholder: '{"antenna": "34m"}',
    }),
  },
  actions: {
    submit: {id: "ground-station-submit", label: "Save Ground Station"},
    cancel: {
      id: "ground-station-cancel",
      label: "Cancel",
      href: "/missions/mission-1/comms/ground-stations",
    },
  },
})

const initialValues = {
  ground_station_id: "dss-14",
  display_name: "Goldstone DSS-14",
  provider: "DSN",
  region: "goldstone",
  metadata_json: '{"antenna":"34m"}',
}
const dom = installDom('<div id="ground-station-contract"></div>')
for (const globalName of ["Document", "ShadowRoot", "HTMLInputElement", "HTMLTextAreaElement"]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}
const {component: CommsGroundStationForm} = await loadSfc(componentPath)
const {createApp, defineComponent, h, nextTick, reactive} = integrationRequire("vue")
const liveProps = reactive({
  page: deepFreeze({
    id: "ground-station-page",
    heading: "Edit Ground Station",
    subtitle: "Keep the flight network catalog current.",
    breadcrumbs: [
      {label: "Comms", href: "/missions/mission-1/comms"},
      {label: "Ground Stations", href: "/missions/mission-1/comms/ground-stations"},
      {label: "Edit", href: null},
    ],
  }),
  mode: "edit",
  form: deepFreeze(formWithValues(initialValues)),
})
const emitted = {validate: [], save: []}
const Contract = defineComponent({
  setup() {
    return () =>
      h(CommsGroundStationForm, {
        page: liveProps.page,
        mode: liveProps.mode,
        form: liveProps.form,
        onValidate: (payload) => emitted.validate.push(payload),
        onSave: (payload) => emitted.save.push(payload),
      })
  },
})

const host = dom.window.document.querySelector("#ground-station-contract")
const app = createApp(Contract)
app.mount(host)

const formElement = host.querySelector("#ground-station-form")
const sectionHeaders = [...formElement.querySelectorAll(":scope > section")].map(
  (section) => section.firstElementChild,
)
assert.deepEqual(
  sectionHeaders.map((header) => header.outerHTML),
  [
    '<div class="flex items-center gap-3"><span class="hud-label text-primary/70">01</span><h2 class="hud-label">Identity</h2><div class="flex-1 h-px bg-base-300/60"></div></div>',
    '<div class="flex items-center gap-3"><span class="hud-label text-primary/70">02</span><h2 class="hud-label">Network</h2><div class="flex-1 h-px bg-base-300/60"></div></div>',
    '<div class="flex items-center gap-3"><span class="hud-label text-primary/70">03</span><h2 class="hud-label">Metadata</h2><div class="flex-1 h-px bg-base-300/60"></div></div>',
  ],
  "all three extracted headers retain exact tags, class order, copy, and sibling order",
)

const actionWrapper = formElement.lastElementChild
const submitButton = host.querySelector("#ground-station-submit")
const cancelLink = host.querySelector("#ground-station-cancel")
assert.deepEqual(elementAttributes(actionWrapper), {
  class: "flex items-center gap-3 border-t border-base-300/60 pt-5",
})
assert.deepEqual([...actionWrapper.childNodes].map((node) => node.nodeName), ["BUTTON", "A"])
assert.deepEqual([...actionWrapper.children], [submitButton, cancelLink])
assert.strictEqual(submitButton.parentElement, actionWrapper)
assert.strictEqual(cancelLink.parentElement, actionWrapper)
assert.equal(submitButton.textContent.trim(), "Save Ground Station")
assert.equal(cancelLink.textContent, "Cancel")

const nativeControls = [...host.querySelectorAll("form input, form textarea")]
assert.deepEqual(
  nativeControls.map((control) => control.tagName),
  ["INPUT", "INPUT", "INPUT", "INPUT", "TEXTAREA"],
)
assert.deepEqual(
  nativeControls.map(elementAttributes),
  [
    {
      class: "w-full input",
      id: "ground_station_ground_station_id",
      name: "ground_station[ground_station_id]",
      placeholder: "DSS-14",
      required: "",
      type: "text",
    },
    {
      class: "w-full input",
      id: "ground_station_display_name",
      name: "ground_station[display_name]",
      placeholder: "Goldstone DSS-14",
      required: "",
      type: "text",
    },
    {
      class: "w-full input",
      disabled: "",
      id: "ground_station_provider",
      name: "ground_station[provider]",
      type: "text",
    },
    {
      class: "w-full input",
      id: "ground_station_region",
      name: "ground_station[region]",
      type: "text",
    },
    {
      class: "w-full textarea min-h-40 font-mono text-xs",
      id: "ground_station_metadata_json",
      name: "ground_station[metadata_json]",
      placeholder: '{"antenna": "34m"}',
    },
  ],
)
assert.deepEqual(nativeControls.map((control) => control.value), Object.values(initialValues))

const wrappers = [...host.querySelectorAll("form .fieldset")]
assert.equal(wrappers.length, 5)
assert.deepEqual(
  wrappers.map((wrapper) => [...wrapper.childNodes].map((child) => child.nodeName)),
  [["LABEL"], ["LABEL"], ["LABEL"], ["LABEL"], ["LABEL"]],
)
assert.deepEqual(
  wrappers.map((wrapper) =>
    [...wrapper.querySelector("label").childNodes].map((child) => child.nodeName),
  ),
  [["SPAN", "INPUT"], ["SPAN", "INPUT"], ["SPAN", "INPUT"], ["SPAN", "INPUT"], ["SPAN", "TEXTAREA"]],
)
assert.deepEqual(
  wrappers.map((wrapper) => elementAttributes(wrapper)),
  Array.from({length: 5}, () => ({class: "fieldset mb-3"})),
)
assert.deepEqual(
  wrappers.map((wrapper) => elementAttributes(wrapper.querySelector("label"))),
  nativeControls.map((control) => ({for: control.id})),
)
assert.deepEqual(
  wrappers.map((wrapper) => ({
    attrs: elementAttributes(wrapper.querySelector("span")),
    text: wrapper.querySelector("span").textContent,
  })),
  [
    {attrs: {class: "hud-label block mb-1.5"}, text: "Ground Station ID"},
    {attrs: {class: "hud-label block mb-1.5"}, text: "Display Name"},
    {attrs: {class: "hud-label block mb-1.5"}, text: "Provider"},
    {attrs: {class: "hud-label block mb-1.5"}, text: "Region"},
    {attrs: {class: "hud-label block mb-1.5"}, text: "Metadata JSON"},
  ],
)

const editedValues = {
  ground_station_id: "dss-43",
  display_name: "Canberra DSS-43",
  provider: "NASA DSN",
  region: "canberra",
  metadata_json: '{"antenna":"70m"}',
}

for (const [index, control] of nativeControls.entries()) {
  control.value = Object.values(editedValues)[index]
  control.dispatchEvent(new dom.window.Event("input", {bubbles: true}))
  await nextTick()
  assert.equal(emitted.validate.length, index + 1, "each native input emits one validation")
  assert.deepEqual(emitted.validate.at(-1), {
    ground_station: {
      ...initialValues,
      ...Object.fromEntries(Object.entries(editedValues).slice(0, index + 1)),
    },
  })
}

liveProps.form = deepFreeze(formWithValues(initialValues))
await nextTick()
assert.deepEqual(
  nativeControls.map((control) => control.value),
  Object.values(editedValues),
  "a stale server patch does not erase newer local typing",
)

liveProps.form = deepFreeze(formWithValues(editedValues))
await nextTick()
assert.deepEqual(nativeControls.map((control) => control.value), Object.values(editedValues))

const authoritativeValues = {
  ground_station_id: "dss-63",
  display_name: "Madrid DSS-63",
  provider: "NASA DSN",
  region: "madrid",
  metadata_json: '{"antenna":"34m"}',
}
liveProps.form = deepFreeze(formWithValues(authoritativeValues))
await nextTick()
assert.deepEqual(
  nativeControls.map((control) => control.value),
  Object.values(authoritativeValues),
  "an authoritative server patch reconciles after pending validation is acknowledged",
)
assert.deepEqual(
  [...host.querySelectorAll("form input, form textarea")],
  nativeControls,
  "server reconciliation preserves every native control node",
)

nativeControls[1].value = "Madrid Deep Space Complex"
nativeControls[1].dispatchEvent(new dom.window.Event("input", {bubbles: true}))
await nextTick()
const expectedSaveValues = {
  ...authoritativeValues,
  display_name: "Madrid Deep Space Complex",
}
assert.deepEqual(emitted.validate.at(-1), {ground_station: expectedSaveValues})

const submitEvent = new dom.window.Event("submit", {bubbles: true, cancelable: true})
formElement.dispatchEvent(submitEvent)
assert.equal(submitEvent.defaultPrevented, true)
assert.deepEqual(emitted.save, [{ground_station: expectedSaveValues}])

assert.deepEqual(
  elementAttributes(submitButton),
  {class: "btn btn-primary", id: "ground-station-submit", type: "submit"},
)
assert.deepEqual(
  elementAttributes(cancelLink),
  {
    class: "btn btn-ghost",
    "data-phx-link": "redirect",
    "data-phx-link-state": "push",
    href: "/missions/mission-1/comms/ground-stations",
    id: "ground-station-cancel",
  },
)

app.unmount()
assert.equal(host.children.length, 0)
dom.window.close()

console.log("comms_ground_station_form_foundation_test passed")
