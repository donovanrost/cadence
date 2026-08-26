import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  elementAttributes,
  expectedNodeVersion,
  installDom,
  integrationRequire
} from "./reka_adapter_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `WidgetFormField contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const paths = {
  component: resolve(testDirectory, "../vue/ui/components/WidgetFormField.vue"),
  presentationTypes: resolve(testDirectory, "../vue/ui/components/widget_form_field.ts"),
  widgetForm: resolve(testDirectory, "../vue/WidgetForm.vue"),
}

const [source, presentationTypesSource, widgetFormSource] = await Promise.all(
  Object.values(paths).map((path) => readFile(path, "utf8")),
)

const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const parsed = parse(source, {filename: paths.component})

assert.deepEqual(parsed.errors, [], "WidgetFormField.vue parses with the pinned Vue compiler")
assert.ok(parsed.descriptor.script, "WidgetFormField keeps its typed render-function block")
assert.equal(parsed.descriptor.script.lang, "ts")
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null, "WidgetFormField adds no template wrapper boundary")

const script = parsed.descriptor.script.content

assert.match(script, /^import \{defineComponent, h, type PropType\} from "vue"$/m)
assert.match(script, /^import type \{FieldPresentation\} from "\.\/widget_form_field"$/m)
assert.match(script, /name: "WidgetFormField"/)
assert.match(script, /if \(field\.type === "checkbox"\)/)
assert.match(script, /h\("input", field\.hidden_control\?\.attrs \?\? \{\}\)/)
assert.match(script, /h\("input", \{\.\.\.field\.control\.attrs, class: field\.control\.class\}\)/)
assert.match(script, /field\.control\.options\.map\(\(option\) =>/)
assert.match(script, /h\("option", \{\.\.\.option\.attrs, key: option\.key\}, option\.text\)/)
assert.match(script, /field\.errors\.map\(\(error, index\) =>/)
assert.match(script, /key: `\$\{field\.key\}-error-\$\{index\}`/)
assert.doesNotMatch(source, /CadenceToggle|from "reka-ui"|<input|<select|<option/)
assert.doesNotMatch(source, /\bv-model(?::model-value)?=|@submit\.prevent/)
assert.doesNotMatch(script, /\b(?:computed|reactive|ref|watch)\s*\(|\bfetch\s*\(/)

assert.match(
  presentationTypesSource,
  /type: "checkbox" \| "search" \| "select" \| "text"/,
)
assert.match(presentationTypesSource, /hidden_control: \{attrs: Attributes\} \| null/)
assert.match(presentationTypesSource, /options: OptionPresentation\[\]/)
assert.match(presentationTypesSource, /errors: TextPresentation\[\]/)

assert.match(
  widgetFormSource,
  /^import WidgetFormField from "\.\/ui\/components\/WidgetFormField\.vue"$/m,
)
assert.match(widgetFormSource, /from "\.\/ui\/components\/widget_form_field"$/m)
assert.equal(
  widgetFormSource.match(/<WidgetFormField\b/g)?.length,
  9,
  "all nine WidgetFormField call sites remain present one-for-one",
)
assert.doesNotMatch(widgetFormSource, /const WidgetFormField = defineComponent/)

const dom = installDom('<div id="field-contracts"></div>')
const compiled = compileScript(parsed.descriptor, {id: "widget-form-field-contract"})
const {transformSync} = integrationRequire("esbuild")
const transformed = transformSync(compiled.content, {
  format: "cjs",
  loader: "ts",
  platform: "node",
  target: "node24",
})
const loadedModule = {exports: {}}
const evaluate = new Function("require", "module", "exports", transformed.code)
evaluate(integrationRequire, loadedModule, loadedModule.exports)
const WidgetFormField = loadedModule.exports.default
const {createApp} = integrationRequire("vue")

const deepFreeze = (value) => {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value)
    Object.values(value).forEach(deepFreeze)
  }

  return value
}

const mountField = (field) => {
  const frozenField = deepFreeze(field)
  const before = JSON.stringify(frozenField)
  const host = dom.window.document.createElement("div")
  dom.window.document.querySelector("#field-contracts").append(host)
  const app = createApp(WidgetFormField, {field: frozenField})
  app.mount(host)

  assert.equal(JSON.stringify(frozenField), before, `${field.type} presentation stays immutable`)
  assert.equal(host.children.length, 1, `${field.type} renders one root element`)

  return {
    root: host.firstElementChild,
    unmount() {
      app.unmount()
      host.remove()
    },
  }
}

const checkboxField = {
  key: "show_unit",
  type: "checkbox",
  wrapper_class: "fieldset mb-3",
  label: {class: "block text-sm font-medium", text: "Show engineering unit"},
  control: {
    class: "checkbox checkbox-sm mt-0.5",
    attrs: {
      type: "checkbox",
      id: "widget_show_unit",
      name: "widget[show_unit]",
      value: "true",
      checked: "",
    },
    options: [],
  },
  hidden_control: {
    attrs: {type: "hidden", name: "widget[show_unit]", value: "false"},
  },
  description: {class: "text-xs text-base-content/60", text: "Display the engineering unit."},
  errors: [],
}
const checkbox = mountField(checkboxField)

assert.equal(checkbox.root.tagName, "DIV")
assert.deepEqual(elementAttributes(checkbox.root), {class: "fieldset mb-3"})
assert.equal(checkbox.root.children.length, 1)
const checkboxLabel = checkbox.root.firstElementChild
assert.equal(checkboxLabel.tagName, "LABEL")
assert.deepEqual(elementAttributes(checkboxLabel), {
  class: "flex cursor-pointer items-start gap-3",
})
assert.deepEqual(
  [...checkboxLabel.children].map((element) => element.tagName),
  ["INPUT", "INPUT", "SPAN"],
)
assert.deepEqual(elementAttributes(checkboxLabel.children[0]), {
  name: "widget[show_unit]",
  type: "hidden",
  value: "false",
})
assert.deepEqual(elementAttributes(checkboxLabel.children[1]), {
  checked: "",
  class: "checkbox checkbox-sm mt-0.5",
  id: "widget_show_unit",
  name: "widget[show_unit]",
  type: "checkbox",
  value: "true",
})
assert.deepEqual(
  [...checkboxLabel.children[2].children].map((element) => ({
    attrs: elementAttributes(element),
    text: element.textContent,
  })),
  [
    {attrs: {class: "block text-sm font-medium"}, text: "Show engineering unit"},
    {
      attrs: {class: "text-xs text-base-content/60"},
      text: "Display the engineering unit.",
    },
  ],
)
assert.equal(checkbox.root.querySelectorAll("p").length, 0)
checkbox.unmount()

const searchField = {
  key: "point_q",
  type: "search",
  wrapper_class: "fieldset mb-3",
  label: null,
  control: {
    class: "w-full input",
    attrs: {
      id: "widget_point_q",
      name: "widget[point_q]",
      type: "search",
      value: "temp",
      placeholder: "Filter points by name or description",
      "phx-debounce": "150",
    },
    options: [],
  },
  hidden_control: null,
  description: null,
  errors: [],
}
const search = mountField(searchField)

assert.equal(search.root.children.length, 1)
assert.equal(search.root.firstElementChild.tagName, "LABEL")
assert.equal(search.root.firstElementChild.children.length, 1)
assert.deepEqual(elementAttributes(search.root.querySelector("input")), {
  class: "w-full input",
  id: "widget_point_q",
  name: "widget[point_q]",
  "phx-debounce": "150",
  placeholder: "Filter points by name or description",
  type: "search",
  value: "temp",
})
search.unmount()

const textField = {
  key: "title",
  type: "text",
  wrapper_class: "fieldset mb-3",
  label: {class: "hud-label block mb-1.5", text: "Title"},
  control: {
    class: "w-full input input-error",
    attrs: {
      id: "widget_title",
      name: "widget[title]",
      type: "text",
      value: "",
      required: "",
    },
    options: [],
  },
  hidden_control: null,
  description: null,
  errors: [
    {class: "mt-1.5 text-sm text-error", text: "can't be blank"},
    {class: "mt-1.5 text-sm text-error", text: "is too short"},
  ],
}
const textVNode = WidgetFormField.setup({field: textField})()
assert.deepEqual(
  textVNode.children.slice(1).map((error) => error.key),
  ["title-error-0", "title-error-1"],
)
const text = mountField(textField)

assert.deepEqual(
  [...text.root.children].map((element) => element.tagName),
  ["LABEL", "P", "P"],
)
assert.deepEqual(
  [...text.root.querySelector("label").children].map((element) => element.tagName),
  ["SPAN", "INPUT"],
)
assert.deepEqual(elementAttributes(text.root.querySelector("label > span")), {
  class: "hud-label block mb-1.5",
})
assert.equal(text.root.querySelector("label > span").textContent, "Title")
assert.deepEqual(elementAttributes(text.root.querySelector("input")), {
  class: "w-full input input-error",
  id: "widget_title",
  name: "widget[title]",
  required: "",
  type: "text",
  value: "",
})
assert.deepEqual(
  [...text.root.querySelectorAll("p")].map((error) => ({
    attrs: elementAttributes(error),
    text: error.textContent,
  })),
  [
    {attrs: {class: "mt-1.5 text-sm text-error"}, text: "can't be blank"},
    {attrs: {class: "mt-1.5 text-sm text-error"}, text: "is too short"},
  ],
)
text.unmount()

const selectField = {
  key: "type",
  type: "select",
  wrapper_class: "fieldset mb-3",
  label: {class: "hud-label block mb-1.5", text: "Widget Type"},
  control: {
    class: "w-full select",
    attrs: {id: "widget_type", name: "widget[type]", required: ""},
    options: [
      {key: "", text: "Choose a widget", attrs: {value: ""}},
      {
        key: "time_series",
        text: "Time series chart",
        attrs: {value: "time_series", selected: ""},
      },
      {
        key: "retired",
        text: "Retired widget",
        attrs: {value: "retired", disabled: "", title: "Unavailable"},
      },
    ],
  },
  hidden_control: null,
  description: null,
  errors: [],
}
const selectVNode = WidgetFormField.setup({field: selectField})()
assert.deepEqual(
  selectVNode.children[0].children[1].children.map((option) => option.key),
  ["", "time_series", "retired"],
)
const select = mountField(selectField)

assert.deepEqual(elementAttributes(select.root.querySelector("select")), {
  class: "w-full select",
  id: "widget_type",
  name: "widget[type]",
  required: "",
})
assert.deepEqual(
  [...select.root.querySelectorAll("option")].map((option) => ({
    attrs: elementAttributes(option),
    text: option.textContent,
  })),
  [
    {attrs: {value: ""}, text: "Choose a widget"},
    {attrs: {selected: "", value: "time_series"}, text: "Time series chart"},
    {
      attrs: {disabled: "", title: "Unavailable", value: "retired"},
      text: "Retired widget",
    },
  ],
)
assert.equal(select.root.querySelector("select").value, "time_series")
select.unmount()

assert.equal(dom.window.document.querySelector("#field-contracts").children.length, 0)
dom.window.close()

console.log("widget_form_field_test passed")
