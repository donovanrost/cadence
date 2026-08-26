import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  elementAttributes,
  expectedNodeVersion,
  installDom,
  integrationRequire,
  loadSfc
} from "./reka_adapter_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `WidgetFormCallout contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const paths = {
  component: resolve(testDirectory, "../vue/WidgetFormCallout.vue"),
  presentationTypes: resolve(testDirectory, "../vue/widget_form_callout.ts"),
  widgetForm: resolve(testDirectory, "../vue/WidgetForm.vue"),
}

const [source, presentationTypesSource, widgetFormSource] = await Promise.all(
  Object.values(paths).map((path) => readFile(path, "utf8")),
)

const {compileScript, compileTemplate, parse} = integrationRequire("@vue/compiler-sfc")
const parsed = parse(source, {filename: paths.component})

assert.deepEqual(parsed.errors, [], "WidgetFormCallout.vue parses with the pinned Vue compiler")
assert.ok(parsed.descriptor.scriptSetup, "WidgetFormCallout keeps its typed setup block")
assert.ok(parsed.descriptor.template, "WidgetFormCallout keeps its literal template block")

const script = parsed.descriptor.scriptSetup.content
const template = parsed.descriptor.template.content

assert.match(script, /^import type \{CalloutPresentation\} from "\.\/widget_form_callout"$/m)
assert.match(script, /defineProps<\{callout: CalloutPresentation\}>\(\)/)
assert.doesNotMatch(script, /\b(?:computed|reactive|ref|watch)\s*\(|\bfetch\s*\(/)
assert.doesNotMatch(source, /CadenceToggle|from "reka-ui"|\bv-model(?::model-value)?=|@submit\.prevent/)
assert.equal(
  template.trim(),
  `<p :class="callout.class" v-bind="callout.attrs">
    <span :class="[callout.icon.name, callout.icon.class]"></span>
    <span>{{ callout.text }}</span>
  </p>`,
  "the extracted renderer keeps the exact native tag, bindings, icon class order, and span shape",
)

assert.match(
  presentationTypesSource,
  /^import type \{Attributes\} from "\.\/ui\/components\/widget_form_field"$/m,
)
assert.match(presentationTypesSource, /export type IconPresentation = \{/)
assert.match(presentationTypesSource, /export type CalloutPresentation = \{/)
assert.match(presentationTypesSource, /attrs: Attributes/)
assert.match(presentationTypesSource, /icon: IconPresentation/)

assert.match(widgetFormSource, /^import WidgetFormCallout from "\.\/WidgetFormCallout\.vue"$/m)
assert.match(widgetFormSource, /from "\.\/widget_form_callout"$/m)
assert.equal(
  widgetFormSource.match(/<WidgetFormCallout\b/g)?.length,
  3,
  "scope override and both operational warnings use the extracted renderer one-for-one",
)
assert.equal(
  widgetFormSource.match(/<WidgetFormField\b/g)?.length,
  9,
  "all nine WidgetFormField call sites remain present one-for-one",
)
assert.doesNotMatch(widgetFormSource, /type CalloutPresentation =/)

const calloutReferences = [
  "presentation.point_widget.scope_override",
  "presentation.point_widget.operational_observable_picker.capability_warning",
  "presentation.point_widget.operational_observable_picker.scope_warning",
]
let previousCallout = -1

for (const reference of calloutReferences) {
  const condition = widgetFormSource.indexOf(`v-if="${reference}"`)
  const binding = widgetFormSource.indexOf(`:callout="${reference}"`, condition)

  assert.ok(condition > previousCallout, `${reference} keeps its sibling order`)
  assert.ok(binding > condition, `${reference} keeps its matching presentation binding`)
  previousCallout = condition
}

const widgetFormParsed = parse(widgetFormSource, {filename: paths.widgetForm})
assert.deepEqual(widgetFormParsed.errors, [], "WidgetForm.vue still parses with the pinned Vue compiler")
const widgetFormScript = compileScript(widgetFormParsed.descriptor, {id: "widget-form-callout-parent"})
const widgetFormTemplate = compileTemplate({
  id: "widget-form-callout-parent",
  filename: paths.widgetForm,
  source: widgetFormParsed.descriptor.template.content,
  compilerOptions: {bindingMetadata: widgetFormScript.bindings},
})
assert.deepEqual(
  widgetFormTemplate.errors,
  [],
  "WidgetForm.vue still compiles with the extracted callout component",
)

const compiledCallout = compileScript(parsed.descriptor, {id: "widget-form-callout-contract"})
const compiledCalloutTemplate = compileTemplate({
  id: "widget-form-callout-contract",
  filename: paths.component,
  source: template,
  compilerOptions: {bindingMetadata: compiledCallout.bindings},
})
assert.deepEqual(
  compiledCalloutTemplate.errors,
  [],
  "WidgetFormCallout.vue compiles with the pinned Vue compiler",
)

const dom = installDom('<div id="callout-contracts"></div>')
const {component: WidgetFormCallout} = await loadSfc(paths.component)
const {createApp} = integrationRequire("vue")

const deepFreeze = (value) => {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value)
    Object.values(value).forEach(deepFreeze)
  }

  return value
}

const fixtures = [
  {
    label: "scope override",
    callout: {
      class: "flex items-start gap-1.5 rounded border px-2 py-1 text-xs",
      attrs: {
        "data-widget-scope-override": "",
        "data-widget-scope-override-state": "ready",
      },
      icon: {name: "hero-map-pin", class: "mt-0.5 h-3.5 w-3.5 shrink-0"},
      text: "Pins this widget to ground station ground-dss-14.",
    },
  },
  {
    label: "capability warning",
    callout: {
      class: "flex items-start gap-1.5 rounded border border-warning/40",
      attrs: {
        "data-operational-observable-capability-warning": "",
        "data-operational-observable-capability-warning-products": "link_rf_metric_history",
      },
      icon: {name: "hero-exclamation-triangle", class: "mt-0.5 h-3.5 w-3.5 shrink-0"},
      text: "Selected source cannot satisfy raw_series for link_rf_metric_history.",
    },
  },
  {
    label: "scope warning",
    callout: {
      class: "flex items-start gap-1.5 text-xs text-warning",
      attrs: {
        "data-operational-observable-scope-warning": "",
        "data-operational-observable-scope-warning-ids": "ground.station.connection_state",
      },
      icon: {name: "hero-exclamation-triangle", class: "mt-0.5 h-3.5 w-3.5 shrink-0"},
      text: "Current context does not support ground.station.connection_state.",
    },
  },
]

for (const fixture of fixtures) {
  const callout = deepFreeze(fixture.callout)
  const before = JSON.stringify(callout)
  const host = dom.window.document.createElement("div")
  dom.window.document.querySelector("#callout-contracts").append(host)
  const app = createApp(WidgetFormCallout, {callout})
  app.mount(host)

  assert.equal(JSON.stringify(callout), before, `${fixture.label} presentation stays immutable`)
  assert.equal(host.children.length, 1, `${fixture.label} adds no wrapper element`)

  const root = host.firstElementChild
  assert.equal(root.tagName, "P")
  assert.deepEqual(elementAttributes(root), {class: callout.class, ...callout.attrs})
  assert.deepEqual(
    [...root.children].map((element) => element.tagName),
    ["SPAN", "SPAN"],
  )
  assert.equal(root.children[0].getAttribute("class"), `${callout.icon.name} ${callout.icon.class}`)
  assert.equal(root.children[0].textContent, "")
  assert.equal(root.children[1].textContent, callout.text)

  app.unmount()
  host.remove()
}

assert.equal(dom.window.document.querySelector("#callout-contracts").children.length, 0)
dom.window.close()

console.log("widget_form_callout_test passed")
