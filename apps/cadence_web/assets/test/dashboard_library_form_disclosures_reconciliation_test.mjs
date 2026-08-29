import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  assertPinnedAdapterRuntime,
  flushVue,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"
import {peelCadenceOpsViewport} from "./ops_viewport_test_support.mjs"

const scenarios = Object.freeze([
  "the actual dashboard library SFC loads the real CadenceCollapsible adapter graph",
  "both disclosure roots retain caller-native div, button, form, controls, IDs, names, and actions",
  "click interaction updates both client-seeded disclosure states",
  "same-epoch replacement of every component prop preserves local disclosure state",
  "changed server-open epochs intentionally reseed both disclosure states",
  "unmountOnHide=false preserves each form and edited control identity and value",
  "create and version submit events retain their exact names and nested payloads",
  "the retired native opening tags and immediate predecessor source remain byte-frozen",
  "the component contains no disclosure hook or direct Reka import to colocate",
])

const separateGates = Object.freeze([
  "BROWSER GATE: keyboard, focus, layout, and hydration require real-browser verification",
  "LIVEVUE TRANSPORT GATE: server patch transport reconciliation requires integration verification",
  "CSRF GATE: native Phoenix submission and CSRF behavior require integration verification",
])

assert.equal(scenarios.length, 9)
assert.equal(separateGates.length, 3)

const migrationParent = "666f58ed058b033630bb2aeb4f572df5b23ae58c"
const parentSha256 = "152917fb9eaa8d5f15d9f2254fffc972800205372a6bfb81e35e23120a1125b0"
const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const packageLockPath = resolve(testDirectory, "../../package-lock.json")
const componentRelativePath = "apps/cadence_web/assets/vue/OpsDashboardLibrary.vue"
const componentPath = resolve(repositoryRoot, componentRelativePath)
const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const occurrences = (source, fragment) => source.split(fragment).length - 1
const cadenceCollapsibleImports = [
  'import CadenceCollapsible from "./ui/reka/CadenceCollapsible.vue"',
  'import CadenceCollapsibleContent from "./ui/reka/CadenceCollapsibleContent.vue"',
  'import CadenceCollapsibleTrigger from "./ui/reka/CadenceCollapsibleTrigger.vue"',
].join("\n") + "\n"
const disclosureSeedHelper = [
  "const disclosureSeedEpoch = (details: ProgressiveDetails) =>",
  '  `${details.id}:${details.open ? "open" : "closed"}`',
  "",
  "",
].join("\n")
const disclosure = (form, openingSha256) => ({
  form,
  openingSha256,
  nativeOpening: [
    "<details",
    `          :id="${form}.details.id"`,
    `          :open="${form}.details.open"`,
    '          class="border border-base-300 bg-base-200/20 p-4"',
    "        >",
  ].join("\n"),
})
const disclosures = Object.freeze([
  disclosure("create_form", "3c98a4d0cee5edea1d8f05eed91388a37c7228e28ba4302b8fe55ee3f1eb3104"),
  disclosure("version_form", "a17681f34775420252d7c0ec017c416311f646011bd37abafed1837ab7840bb7"),
])

const reconstructImmediateParent = (source) => {
  source = peelCadenceOpsViewport(source, "OpsDashboardLibrary.vue")
  assert.equal(occurrences(source, cadenceCollapsibleImports), 1)
  assert.equal(occurrences(source, disclosureSeedHelper), 1)
  assert.equal(occurrences(source, "<CadenceCollapsible\n"), disclosures.length)
  assert.equal(occurrences(source, "        </CadenceCollapsible>"), disclosures.length)

  let reconstructed = source
  for (const boundary of disclosures) {
    const migratedOpening = `        <CadenceCollapsible
          :content-id="${boundary.form}.id"
          :open="${boundary.form}.details.open"
          client-seeded
          :seed-epoch="disclosureSeedEpoch(${boundary.form}.details)"
          :unmount-on-hide="false"
        >
          <div
            :id="${boundary.form}.details.id"
            class="border border-base-300 bg-base-200/20 p-4"
          >
            <CadenceCollapsibleTrigger>
              <button
                :id="${boundary.form}.details.summary_id"
                type="button"
                class="cursor-pointer font-semibold"
              >{{ ${boundary.form}.details.summary }}</button>
            </CadenceCollapsibleTrigger>

            <CadenceCollapsibleContent>`
    const migratedClosing = `            </CadenceCollapsibleContent>
          </div>
        </CadenceCollapsible>`
    const nativeSummary = `          <summary
            :id="${boundary.form}.details.summary_id"
            class="cursor-pointer font-semibold"
          >{{ ${boundary.form}.details.summary }}</summary>`

    assert.equal(
      sha256(boundary.nativeOpening),
      boundary.openingSha256,
      `${boundary.form} retired native opening-tag hash`,
    )
    assert.equal(occurrences(reconstructed, migratedOpening), 1, `${boundary.form} opening`)

    const openingIndex = reconstructed.indexOf(migratedOpening)
    const contentStart = openingIndex + migratedOpening.length + 1
    const closingIndex = reconstructed.indexOf(migratedClosing, contentStart)
    assert.notEqual(closingIndex, -1, `${boundary.form} closing`)
    const callerForm = reconstructed.slice(contentStart, closingIndex)
    const nativeDisclosure =
      `        ${boundary.nativeOpening}\n` +
      `${nativeSummary}\n\n` +
      callerForm +
      "        </details>"

    reconstructed =
      reconstructed.slice(0, openingIndex) +
      nativeDisclosure +
      reconstructed.slice(closingIndex + migratedClosing.length)
  }

  reconstructed = reconstructed
    .replace(cadenceCollapsibleImports, "")
    .replace(disclosureSeedHelper, "")
  assert.doesNotMatch(reconstructed, /CadenceCollapsible|disclosureSeedEpoch/)
  return reconstructed
}

await assertPinnedAdapterRuntime(packageLockPath)

const dom = installDom('<div id="app"></div>')
const [componentSource, componentSfc] = await Promise.all([
  readFile(componentPath, "utf8"),
  loadSfc(componentPath),
])
const parentSource = execFileSync("git", ["show", `${migrationParent}:${componentRelativePath}`], {
  cwd: repositoryRoot,
  encoding: "utf8",
})
const reconstructedParent = reconstructImmediateParent(componentSource)

assert.equal(componentSfc.source, componentSource)
assert.ok(componentSfc.component)
assert.equal(sha256(parentSource), parentSha256, "the immediate parent source hash is frozen")
assert.equal(sha256(reconstructedParent), parentSha256, "the inverse peel retains parent bytes")
assert.equal(reconstructedParent, parentSource, "the inverse peel reconstructs HEAD byte-for-byte")
assert.equal(occurrences(componentSource, "<CadenceCollapsible\n"), 2)
assert.equal(occurrences(componentSource, "<CadenceCollapsibleTrigger>"), 2)
assert.equal(occurrences(componentSource, "<CadenceCollapsibleContent>"), 2)
assert.doesNotMatch(componentSource, /<details(?:\s|>)/)
assert.equal(occurrences(componentSource, "<summary\n"), 1, "the unrelated item details stays intact")
assert.doesNotMatch(componentSource, /from "reka-ui"/)
assert.doesNotMatch(componentSource, /phx-hook|v-hook|onMounted|onBeforeUnmount/)

const textField = ({id, name, label, type = "text", value = ""}) => ({
  id,
  name,
  type,
  label,
  value,
  required: true,
})
const selectField = ({id, name, label, value = ""}) => ({
  id,
  name,
  type: "select",
  label,
  value,
  required: true,
  placeholder: `Select ${label}`,
})
const componentProps = ({
  createOpen = true,
  versionOpen = false,
  pageCopy = "Initial server presentation",
} = {}) => ({
  page: {
    id: "dashboard-library-page",
    header: {
      id: "dashboard-library-header",
      eyebrow: "Operations",
      heading: "Dashboard library",
      copy: pageCopy,
    },
    list: {
      id: "dashboard-library-list",
      empty: {id: "dashboard-library-empty", copy: "No library items."},
    },
    paths: {dashboards: "/ops/dashboards", library: "/ops/dashboard-library"},
  },
  dashboard_options: [{label: "Canary dashboard", value: "dashboard-canary"}],
  library_options: [
    {label: "Canary widget", value: "library-item-canary", latest_version: 7},
  ],
  stage_form: {
    id: "stage-library-form",
    eyebrow: "Stage library item",
    fields: {
      dashboard_id: selectField({
        id: "stage-dashboard-id",
        name: "library_add[dashboard_id]",
        label: "Dashboard",
      }),
      item_id: selectField({
        id: "stage-item-id",
        name: "library_add[item_id]",
        label: "Library item",
      }),
      version: {
        ...textField({
          id: "stage-version",
          name: "library_add[version]",
          label: "Version",
          type: "number",
          value: "7",
        }),
        min: 1,
      },
    },
    action: {id: "stage-library-action", label: "Stage item"},
  },
  create_form: {
    id: "create-library-form",
    reset_revision: 0,
    details: {
      id: "create-library-details",
      summary_id: "create-library-summary",
      summary: "Create library item",
      open: createOpen,
    },
    fields: {
      name: textField({
        id: "create-name",
        name: "library_item[name]",
        label: "Name",
        value: "Seed name",
      }),
      description: textField({
        id: "create-description",
        name: "library_item[description]",
        label: "Description",
        type: "textarea",
        value: "Seed description",
      }),
      change_summary: textField({
        id: "create-change-summary",
        name: "library_item[change_summary]",
        label: "Change summary",
        value: "Seed create summary",
      }),
      widget_json: textField({
        id: "create-widget-json",
        name: "library_item[widget_json]",
        label: "Widget JSON",
        type: "textarea",
        value: '{"seed":"create"}',
      }),
    },
    action: {id: "create-library-action", label: "Create item"},
  },
  version_form: {
    id: "version-library-form",
    details: {
      id: "version-library-details",
      summary_id: "version-library-summary",
      summary: "Add library version",
      open: versionOpen,
    },
    fields: {
      item_id: selectField({
        id: "version-item-id",
        name: "library_version[item_id]",
        label: "Library item",
        value: "library-item-canary",
      }),
      change_summary: textField({
        id: "version-change-summary",
        name: "library_version[change_summary]",
        label: "Change summary",
        value: "Seed version summary",
      }),
      widget_json: textField({
        id: "version-widget-json",
        name: "library_version[widget_json]",
        label: "Widget JSON",
        type: "textarea",
        value: '{"seed":"version"}',
      }),
    },
    action: {id: "version-library-action", label: "Add version"},
  },
  library_items: [],
})

const {createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")
const props = ref(componentProps())
const createPayloads = []
const versionPayloads = []

const DashboardLibraryOracle = defineComponent({
  name: "DashboardLibraryFormDisclosuresReconciliationOracle",
  setup() {
    return () =>
      h(componentSfc.component, {
        ...props.value,
        onCreateLibraryItem: (payload) => createPayloads.push(payload),
        onAddLibraryVersion: (payload) => versionPayloads.push(payload),
      })
  },
})

const app = createApp(DashboardLibraryOracle)
app.mount(dom.window.document.querySelector("#app"))
await flushVue(nextTick)

const document = dom.window.document
const createRoot = document.querySelector("#create-library-details")
const versionRoot = document.querySelector("#version-library-details")
const createTrigger = document.querySelector("#create-library-summary")
const versionTrigger = document.querySelector("#version-library-summary")
const createForm = document.querySelector("#create-library-form")
const versionForm = document.querySelector("#version-library-form")

for (const root of [createRoot, versionRoot]) {
  assert.ok(root instanceof dom.window.HTMLDivElement)
  assert.equal(root.className, "border border-base-300 bg-base-200/20 p-4")
  assert.deepEqual([...root.children].map((child) => child.tagName), ["BUTTON", "FORM"])
}
for (const trigger of [createTrigger, versionTrigger]) {
  assert.ok(trigger instanceof dom.window.HTMLButtonElement)
  assert.equal(trigger.type, "button")
  assert.equal(trigger.className, "cursor-pointer font-semibold")
}
for (const form of [createForm, versionForm]) {
  assert.ok(form instanceof dom.window.HTMLFormElement)
  assert.equal(form.className, "mt-4 space-y-3")
  assert.equal(form.getAttribute("action"), null)
}

assert.equal(createTrigger.parentElement, createRoot)
assert.equal(createForm.parentElement, createRoot)
assert.equal(versionTrigger.parentElement, versionRoot)
assert.equal(versionForm.parentElement, versionRoot)
assert.equal(createTrigger.getAttribute("aria-controls"), createForm.id)
assert.equal(versionTrigger.getAttribute("aria-controls"), versionForm.id)

const expectedNames = Object.freeze({
  "create-name": "library_item[name]",
  "create-description": "library_item[description]",
  "create-change-summary": "library_item[change_summary]",
  "create-widget-json": "library_item[widget_json]",
  "version-item-id": "library_version[item_id]",
  "version-change-summary": "library_version[change_summary]",
  "version-widget-json": "library_version[widget_json]",
})
for (const [id, name] of Object.entries(expectedNames)) {
  assert.equal(document.querySelector(`#${id}`).getAttribute("name"), name)
}
assert.equal(document.querySelector("#create-library-action").type, "submit")
assert.equal(document.querySelector("#version-library-action").type, "submit")

const editedValues = Object.freeze({
  "create-name": "Operator library item",
  "create-description": "Operator-authored description",
  "create-change-summary": "Operator create summary",
  "create-widget-json": '{"operator":"create"}',
  "version-item-id": "library-item-canary",
  "version-change-summary": "Operator version summary",
  "version-widget-json": '{"operator":"version"}',
})
const nativeNodes = new Map()
for (const [id, value] of Object.entries(editedValues)) {
  const control = document.querySelector(`#${id}`)
  nativeNodes.set(id, control)
  control.value = value
  control.dispatchEvent(
    new dom.window.Event(control instanceof dom.window.HTMLSelectElement ? "change" : "input", {
      bubbles: true,
    }),
  )
}
await flushVue(nextTick)

const assertDisclosureState = (root, trigger, form, open) => {
  assert.equal(root.getAttribute("data-state"), open ? "open" : "closed")
  assert.equal(trigger.getAttribute("data-state"), open ? "open" : "closed")
  assert.equal(form.getAttribute("data-state"), open ? "open" : "closed")
  assert.equal(trigger.getAttribute("aria-expanded"), String(open))
  assert.equal(form.hasAttribute("hidden"), !open)
}
const assertNativeIdentityAndValues = () => {
  assert.equal(document.querySelector("#create-library-details"), createRoot)
  assert.equal(document.querySelector("#version-library-details"), versionRoot)
  assert.equal(document.querySelector("#create-library-summary"), createTrigger)
  assert.equal(document.querySelector("#version-library-summary"), versionTrigger)
  assert.equal(document.querySelector("#create-library-form"), createForm)
  assert.equal(document.querySelector("#version-library-form"), versionForm)
  for (const [id, control] of nativeNodes) {
    assert.equal(document.querySelector(`#${id}`), control, `${id} keeps native identity`)
    assert.equal(control.value, editedValues[id], `${id} keeps its edited value`)
    assert.equal(control.getAttribute("name"), expectedNames[id], `${id} keeps its name`)
  }
}

assertDisclosureState(createRoot, createTrigger, createForm, true)
assertDisclosureState(versionRoot, versionTrigger, versionForm, false)
assertNativeIdentityAndValues()

createTrigger.click()
versionTrigger.click()
await flushVue(nextTick)
assertDisclosureState(createRoot, createTrigger, createForm, false)
assertDisclosureState(versionRoot, versionTrigger, versionForm, true)
assertNativeIdentityAndValues()

props.value = componentProps({pageCopy: "Same-epoch whole-prop replacement"})
await flushVue(nextTick)
assert.match(document.querySelector("#dashboard-library-header").textContent, /Same-epoch whole-prop replacement/)
assertDisclosureState(createRoot, createTrigger, createForm, false)
assertDisclosureState(versionRoot, versionTrigger, versionForm, true)
assertNativeIdentityAndValues()

createTrigger.click()
versionTrigger.click()
await flushVue(nextTick)
assertDisclosureState(createRoot, createTrigger, createForm, true)
assertDisclosureState(versionRoot, versionTrigger, versionForm, false)

props.value = componentProps({
  createOpen: false,
  versionOpen: true,
  pageCopy: "Changed server-open epochs",
})
await flushVue(nextTick)
assertDisclosureState(createRoot, createTrigger, createForm, false)
assertDisclosureState(versionRoot, versionTrigger, versionForm, true)
assertNativeIdentityAndValues()

assert.equal(
  createForm.dispatchEvent(new dom.window.Event("submit", {bubbles: true, cancelable: true})),
  false,
)
assert.equal(
  versionForm.dispatchEvent(new dom.window.Event("submit", {bubbles: true, cancelable: true})),
  false,
)
await flushVue(nextTick)
assert.deepEqual(createPayloads, [
  {
    library_item: {
      name: editedValues["create-name"],
      description: editedValues["create-description"],
      change_summary: editedValues["create-change-summary"],
      widget_json: editedValues["create-widget-json"],
    },
  },
])
assert.deepEqual(versionPayloads, [
  {
    library_version: {
      item_id: editedValues["version-item-id"],
      change_summary: editedValues["version-change-summary"],
      widget_json: editedValues["version-widget-json"],
    },
  },
])
assertNativeIdentityAndValues()

app.unmount()
dom.window.close()

console.log(
  `dashboard_library_form_disclosures_reconciliation_test passed (${scenarios.length} scenarios; ` +
    "JSDOM only, browser/LiveVue transport/CSRF remain separate gates)",
)
