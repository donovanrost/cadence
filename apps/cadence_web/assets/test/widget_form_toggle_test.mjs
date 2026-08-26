import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {createRequire} from "node:module"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {loadSfc} from "./reka_adapter_test_support.mjs"

const expectedNodeVersion = "24.16.0"
const expectedRekaVersion = "2.10.3"
const integrationNodeModules =
  "/Users/donovanrost/projects/cadence/cadence-worktrees/livevue-poc/apps/cadence_web/node_modules"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `WidgetForm Toggle contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const cadenceTogglePath = resolve(testDirectory, "../vue/ui/reka/CadenceToggle.vue")
const paths = {
  component: resolve(testDirectory, "../vue/WidgetForm.vue"),
  fieldComponent: resolve(testDirectory, "../vue/ui/components/WidgetFormField.vue"),
  fieldTypes: resolve(testDirectory, "../vue/ui/components/widget_form_field.ts"),
  packageLock: resolve(testDirectory, "../../package-lock.json"),
  server: resolve(
    testDirectory,
    "../../lib/cadence_web/live/ops_dashboard_show_live/widget_form_components.ex",
  ),
  serverTest: resolve(
    testDirectory,
    "../../test/cadence_web/live/ops_dashboard_show_live/widget_form_components_test.exs",
  ),
  integrationRekaPackage: resolve(integrationNodeModules, "reka-ui/package.json"),
}

const [
  source,
  fieldSource,
  fieldTypesSource,
  packageLockSource,
  serverSource,
  serverTestSource,
  rekaPackageSource,
] = await Promise.all(Object.values(paths).map((path) => readFile(path, "utf8")))

const packageLock = JSON.parse(packageLockSource)
const rekaPackage = JSON.parse(rekaPackageSource)

assert.equal(packageLock.packages["node_modules/reka-ui"].version, expectedRekaVersion)
assert.equal(rekaPackage.version, expectedRekaVersion)

const integrationRequire = createRequire(resolve(integrationNodeModules, "widget-form-oracle.cjs"))
const {compileScript, compileTemplate, parse} = integrationRequire("@vue/compiler-sfc")

const parsed = parse(source, {filename: paths.component})
assert.deepEqual(parsed.errors, [], "WidgetForm.vue parses with the pinned Vue compiler")
assert.ok(parsed.descriptor.scriptSetup, "WidgetForm keeps its typed setup block")
assert.ok(parsed.descriptor.template, "WidgetForm keeps its template block")

const compiledScript = compileScript(parsed.descriptor, {id: "widget-form-toggle-oracle"})
const compiledTemplate = compileTemplate({
  id: "widget-form-toggle-oracle",
  filename: paths.component,
  source: parsed.descriptor.template.content,
  compilerOptions: {bindingMetadata: compiledScript.bindings},
})

assert.deepEqual(compiledTemplate.errors, [], "WidgetForm.vue compiles with the pinned Vue compiler")

const script = parsed.descriptor.scriptSetup.content
const template = parsed.descriptor.template.content

assert.match(script, /^import CadenceToggle from "\.\/ui\/reka\/CadenceToggle\.vue"$/m)
assert.match(
  script,
  /^import WidgetFormField from "\.\/ui\/components\/WidgetFormField\.vue"$/m,
)
assert.match(script, /from "\.\/ui\/components\/widget_form_field"$/m)
assert.doesNotMatch(script, /from "reka-ui"/)
assert.doesNotMatch(script, /const WidgetFormField = defineComponent/)
assert.equal(template.match(/<CadenceToggle\b/g)?.length, 2)
assert.equal(template.match(/<\/CadenceToggle>/g)?.length, 2)
assert.doesNotMatch(source, /ToggleGroup|ToggleRoot/)

const sourceSlice = (sourceText, start, end, label) => {
  const startIndex = sourceText.indexOf(start)
  const endIndex = sourceText.indexOf(end, startIndex + start.length)

  assert.ok(startIndex >= 0 && endIndex > startIndex, `${label} must remain source-auditable`)
  return sourceText.slice(startIndex, endIndex)
}

const inclusiveSourceSlice = (sourceText, start, end, label) =>
  `${sourceSlice(sourceText, start, end, label)}${end}`

const pointToggle = inclusiveSourceSlice(
  template,
  "            <CadenceToggle\n",
  "            </CadenceToggle>",
  "point-picker option CadenceToggle",
)
const observableToggle = inclusiveSourceSlice(
  template,
  "                <CadenceToggle\n",
  "                </CadenceToggle>",
  "operational-observable option CadenceToggle",
)

for (const [label, toggle] of [
  ["point-picker", pointToggle],
  ["operational-observable", observableToggle],
]) {
  assert.equal(toggle.match(/<button\b/g)?.length, 1, `${label} CadenceToggle owns one button`)
  assert.equal(toggle.match(/<\/button>/g)?.length, 1, `${label} CadenceToggle closes one button`)
  assert.match(toggle, /:pressed="option\.attrs\['aria-pressed'\] === 'true'"/)
  assert.match(toggle, /:type="option\.type"/)
  assert.match(toggle, /:class="option\.class"/)
  assert.match(toggle, /v-bind="option\.attrs"/)
  assert.doesNotMatch(toggle, /@click|@update:model-value|@request-change|v-model|\bname=/)
  assert.doesNotMatch(toggle, /<input\b/)
}

assert.doesNotMatch(pointToggle, /:disabled=/)
assert.match(observableToggle, /:disabled="option\.attrs\.disabled !== undefined"/)

const selectedPointRemovals = sourceSlice(
  template,
  '        <div\n          v-if="presentation.point_widget.point_picker.selected_points"',
  "        <WidgetFormField\n          v-if=\"presentation.point_widget.point_picker.search\"",
  "selected point removal buttons",
)
const selectedObservableRemovals = sourceSlice(
  template,
  '        <div\n          v-if="presentation.point_widget.operational_observable_picker.selected"',
  "        <p\n          v-if=\"presentation.point_widget.operational_observable_picker.scope_warning\"",
  "selected operational-observable removal buttons",
)

for (const removalButtons of [selectedPointRemovals, selectedObservableRemovals]) {
  assert.equal(removalButtons.match(/<button\b/g)?.length, 1)
  assert.doesNotMatch(removalButtons, /<Toggle\b/)
  assert.match(removalButtons, /v-bind="button\.attrs"/)
}

assert.doesNotMatch(source, /\bv-model(?::model-value)?=/)
assert.doesNotMatch(script, /\b(?:computed|reactive|ref|watch)\s*\(/)
assert.doesNotMatch(
  source,
  /@update:model-value|@request-change|\bname="[^"]*toggle|type="hidden"[^>]*toggle/,
)

const unwrapToggle = (toggle) => {
  const lines = toggle.split("\n")
  const openingEnd = lines.findIndex((line) => line.trim() === ">")

  assert.ok(openingEnd > 0, "Toggle opening tag stays multiline and auditable")
  assert.equal(lines.at(-1)?.trim(), "</CadenceToggle>")

  return lines
    .slice(openingEnd + 1, -1)
    .map((line) => line.replace(/^  /, ""))
    .join("\n")
}

const extractionImports = `import WidgetFormField from "./ui/components/WidgetFormField.vue"
import type {
  Attributes,
  FieldPresentation,
  TextPresentation
} from "./ui/components/widget_form_field"
`
const sharedTextTypes = `type Attributes = Record<string, string>

type TextPresentation = {
  class: string
  text: string
}`
const iconPresentationType = `type IconPresentation = {
  name: string
  class: string
}`
const fieldPresentationTypes = `type OptionPresentation = {
  key: string
  text: string
  attrs: Attributes
}

type FieldPresentation = {
  key: string
  type: "checkbox" | "search" | "select" | "text"
  wrapper_class: string
  label: TextPresentation | null
  control: {
    class: string
    attrs: Attributes
    options: OptionPresentation[]
  }
  hidden_control: {attrs: Attributes} | null
  description: TextPresentation | null
  errors: TextPresentation[]
}`
const fieldRenderer = sourceSlice(
  fieldSource,
  "const WidgetFormField = defineComponent({",
  "\n\nexport default WidgetFormField",
  "extracted WidgetFormField renderer",
)

assert.equal(
  fieldTypesSource.trim(),
  `${sharedTextTypes.replaceAll("type ", "export type ")}

${fieldPresentationTypes.replaceAll("type ", "export type ")}`,
  "shared WidgetForm field presentation types stay byte-equivalent to the local contract",
)

const reconstructedComponent = source
  .replace(
    extractionImports,
    `import {defineComponent, h, type PropType} from "vue"

${sharedTextTypes}
`,
  )
  .replace(iconPresentationType, `${iconPresentationType}\n\n${fieldPresentationTypes}`)
  .replace(
    "defineProps<{presentation: Presentation}>()",
    `${fieldRenderer}\n\ndefineProps<{presentation: Presentation}>()`,
  )

const normalizedComponent = reconstructedComponent
  .replace('import CadenceToggle from "./ui/reka/CadenceToggle.vue"\n', "")
  .replace(pointToggle, unwrapToggle(pointToggle))
  .replace(observableToggle, unwrapToggle(observableToggle))

assert.equal(
  createHash("sha256").update(normalizedComponent).digest("hex"),
  "4d0d8ffc024656b10c7179ed410c458125ab6a6119471a4922037b19875d8ee2",
  "every non-option-button WidgetForm byte stays unchanged",
)

assert.equal(
  createHash("sha256").update(serverSource).digest("hex"),
  "be8038bae73a05bda5a7b0e1b53c47fcf9ac0fbc6a7ce0af5307576e6a90bf52",
  "the server-authored WidgetForm DTO stays immutable",
)
assert.equal(
  createHash("sha256").update(serverTestSource).digest("hex"),
  "0a448033f663f2ad241ec69596d5660a16c852ba83d68a57df9ef09248a34b68",
  "the WidgetForm Phoenix contract oracle stays immutable",
)

const pointOptionDto = sourceSlice(
  serverSource,
  "  defp point_list_dto(form, points, selected_points, selected_point, false) do",
  "\n  defp operational_observable_picker_dto(_assigns, false)",
  "point option DTO",
)
const observableOptionDto = sourceSlice(
  serverSource,
  "  defp operational_observable_option_dto(observable, selected, scope_context, focus_ids) do",
  "\n  defp trailing_fields_dto(form, type) do",
  "operational-observable option DTO",
)

for (const dto of [pointOptionDto, observableOptionDto]) {
  assert.match(dto, /"phx-click" => "pick_point"/)
  assert.match(dto, /"phx-value-point-id" =>/)
  assert.match(dto, /"aria-pressed" => boolean_text\(selected\?\)/)
}

for (const contract of [
  '"disabled" => not selectable?',
  '"data-operational-observable-readiness-focus" => boolean_text(focused?)',
  '"data-operational-observable-scopes" =>',
  '"data-operational-observable-source-product" =>',
  '"data-operational-observable-product-family" =>',
  '"data-operational-observable-scope-supported" =>',
  '"data-operational-observable-selected" => boolean_text(selected?)',
]) {
  assert.ok(observableOptionDto.includes(contract), `missing server contract: ${contract}`)
}

assert.match(serverTestSource, /assert point_options\["HK\.counter"\]\["attrs"\]\["aria-pressed"\] == "true"/)
assert.match(serverTestSource, /assert point_options\["HK\.counter"\]\["attrs"\]\["phx-click"\] == "pick_point"/)
assert.match(serverTestSource, /assert selected\["contacts\.phase"\]\["attrs"\]\["phx-click"\] == "pick_point"/)
assert.match(serverTestSource, /assert vue\.handlers == %\{\}/)
assert.match(serverTestSource, /assert Map\.keys\(vue\.props\) == \["presentation"\]/)

const {JSDOM} = integrationRequire("jsdom")
const dom = new JSDOM('<div id="app"></div>', {url: "http://localhost/"})

for (const globalName of [
  "window",
  "document",
  "Node",
  "Element",
  "HTMLElement",
  "SVGElement",
  "Event",
  "MouseEvent",
]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const {createApp, defineComponent, h, nextTick} = integrationRequire("vue")
const {component: CadenceToggle} = await loadSfc(cadenceTogglePath)

const pointOption = Object.freeze({
  type: "button",
  class: "point-option-class",
  attrs: Object.freeze({
    "phx-click": "pick_point",
    "phx-value-point-id": "HK.counter",
    "aria-pressed": "true",
    "data-point-selected": "true",
  }),
})
const observableOption = Object.freeze({
  type: "button",
  class: "observable-option-class",
  attrs: Object.freeze({
    "phx-click": "pick_point",
    "phx-value-point-id": "contacts.phase",
    disabled: "",
    "aria-pressed": "false",
    "data-operational-observable": "contacts.phase",
    "data-operational-observable-readiness-focus": "true",
    "data-operational-observable-scopes": "contact mission spacecraft",
    "data-operational-observable-source-product": "contact_state_history",
    "data-operational-observable-product-family": "contact_state",
    "data-operational-observable-scope-supported": "false",
    "data-operational-observable-selected": "false",
  }),
})

const RuntimeOracle = defineComponent({
  name: "WidgetFormToggleRuntimeOracle",
  setup() {
    const button = (option) =>
      h("button", {type: option.type, class: option.class, ...option.attrs}, option.class)

    return () =>
      h("form", null, [
        h(
          CadenceToggle,
          {
            pressed: pointOption.attrs["aria-pressed"] === "true",
          },
          {default: () => button(pointOption)},
        ),
        h(
          CadenceToggle,
          {
            pressed: observableOption.attrs["aria-pressed"] === "true",
            disabled: observableOption.attrs.disabled !== undefined,
          },
          {default: () => button(observableOption)},
        ),
      ])
  },
})

const app = createApp(RuntimeOracle)
app.mount(dom.window.document.querySelector("#app"))

const form = dom.window.document.querySelector("form")
const buttons = [...form.querySelectorAll("button")]

assert.equal(buttons.length, 2, "two CadenceToggle instances render exactly two underlying buttons")
assert.equal(form.children.length, 2, "CadenceToggle adds no wrapper elements")
assert.equal(form.querySelectorAll("input").length, 0, "CadenceToggle adds no hidden inputs")

const attributes = (element) =>
  Object.fromEntries(element.getAttributeNames().sort().map((name) => [name, element.getAttribute(name)]))

assert.deepEqual(attributes(buttons[0]), {
  "aria-pressed": "true",
  class: "point-option-class",
  "data-point-selected": "true",
  "data-state": "on",
  "phx-click": "pick_point",
  "phx-value-point-id": "HK.counter",
  type: "button",
})
assert.deepEqual(attributes(buttons[1]), {
  "aria-pressed": "false",
  class: "observable-option-class",
  "data-disabled": "",
  "data-operational-observable": "contacts.phase",
  "data-operational-observable-product-family": "contact_state",
  "data-operational-observable-readiness-focus": "true",
  "data-operational-observable-scope-supported": "false",
  "data-operational-observable-scopes": "contact mission spacecraft",
  "data-operational-observable-selected": "false",
  "data-operational-observable-source-product": "contact_state_history",
  "data-state": "off",
  disabled: "",
  "phx-click": "pick_point",
  "phx-value-point-id": "contacts.phase",
  type: "button",
})

assert.equal(buttons[0].getAttribute("tabindex"), null)
assert.equal(buttons[0].tabIndex, 0, "enabled option keeps native Tab behavior")
assert.equal(buttons[1].getAttribute("tabindex"), null)
assert.equal(buttons[1].disabled, true, "server-disabled option stays natively disabled")

let nativeClickCount = 0
buttons[0].addEventListener("click", () => nativeClickCount++)
buttons[0].click()
await nextTick()

assert.equal(nativeClickCount, 1, "CadenceToggle leaves the native phx-click path observable once")
assert.equal(pointOption.attrs["aria-pressed"], "true")
assert.equal(buttons[0].getAttribute("aria-pressed"), "true")
assert.equal(buttons[0].getAttribute("data-state"), "on")
assert.equal(buttons[0].getAttribute("phx-click"), "pick_point")

app.unmount()
dom.window.close()
