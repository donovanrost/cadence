import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  assertPinnedAdapterRuntime,
  elementAttributes,
  flushVue,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"

const scenarios = Object.freeze([
  "the adapter maps server-authored pressed and disabled state into a controlled Reka Toggle",
  "raw Fragment text number and comment siblings survive around the one native button root",
  "zero and multiple root candidates fail with a clear contract error",
  "component roots are rejected before their render shape or default attributes can escape",
  "anchor roots fail the native-button contract before interaction",
  "activation emits the requested next state without optimistic local mutation",
  "disabled activation emits nothing and the adapter never introduces a hidden input",
  "normalized event handlers run exactly once and unmount remains safe",
  "a parent template ref retains its owner through the adapter clone",
])

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/ui/reka/CadenceToggle.vue")
const primitiveChildPath = resolve(testDirectory, "../vue/ui/reka/cadence_primitive_child.js")
const packageLockPath = resolve(testDirectory, "../../package-lock.json")

await assertPinnedAdapterRuntime(packageLockPath)
assert.equal(scenarios.length, 9)

const dom = installDom('<div id="app"></div>')
const {component: CadenceToggle, descriptor, source} = await loadSfc(componentPath)
const primitiveChildSource = await readFile(primitiveChildPath, "utf8")
const script = descriptor.scriptSetup.content
const template = descriptor.template.content

assert.match(script, /^import \{Toggle\} from "reka-ui"$/m)
assert.match(script, /import \{CadencePrimitiveChild\} from "\.\/cadence_primitive_child\.js"/)
assert.match(script, /pressed: boolean/)
assert.match(script, /disabled\?: boolean/)
assert.match(script, /"request-change": \[pressed: boolean\]/)
assert.match(template, /<Toggle/)
assert.match(template, /:model-value="props\.pressed"/)
assert.match(template, /:disabled="props\.disabled"/)
assert.match(template, /\bas-child\b/)
assert.match(template, /@update:model-value="emit\('request-change', \$event\)"/)
assert.match(template, /contract-name="CadenceToggle"/)
assert.match(template, /required-tag="button"/)
assert.doesNotMatch(
  source,
  /\bv-model\b|defaultValue|default-value|<input\b|(?:^|\s)name=|\bref\(|\breactive\(/m,
)
assert.match(primitiveChildSource, /createVNode\(Text, null, String\(child\)\)/)
assert.match(primitiveChildSource, /requires exactly one native element child/)
assert.match(primitiveChildSource, /component children are not supported/)
assert.match(primitiveChildSource, /delete childProps\.ref/)
assert.doesNotMatch(primitiveChildSource, /cloneVNode\([^\n]+,\s*child\.props/)
assert.match(primitiveChildSource, /requires a native <\$\{props\.requiredTag\}> child/)

const {
  createApp,
  createCommentVNode,
  defineComponent,
  Fragment,
  h,
  nextTick,
  ref,
} = integrationRequire("vue")
const pressed = ref(false)
const disabled = ref(false)
const requestedStates = []
let nativeClickCount = 0

const RuntimeOracle = defineComponent({
  name: "CadenceToggleRuntimeOracle",
  setup() {
    return () =>
      h("form", {id: "toggle-form"}, [
        h(
          CadenceToggle,
          {
            pressed: pressed.value,
            disabled: disabled.value,
            name: "must-not-create-a-form-field",
            required: true,
            onRequestChange: (nextPressed) => requestedStates.push(nextPressed),
          },
          {
            default: ({pressed: slotPressed}) =>
              h(Fragment, null, [
                "raw text before toggle",
                createCommentVNode("retained-toggle-comment"),
                h(
                  "button",
                  {
                    id: "server-toggle",
                    type: "button",
                    class: "server-authored-class",
                    "aria-label": "Server toggle",
                    "aria-pressed": String(!slotPressed),
                    "data-state": "child-stale",
                    "data-disabled": "child-stale",
                    disabled: !disabled.value,
                    "data-server-contract": "preserved",
                    "phx-click": "request_toggle",
                    onClick: () => nativeClickCount++,
                  },
                  "Toggle",
                ),
                24,
              ]),
          },
        ),
      ])
  },
})

const app = createApp(RuntimeOracle)
app.mount(dom.window.document.querySelector("#app"))

const form = dom.window.document.querySelector("#toggle-form")
const button = dom.window.document.querySelector("#server-toggle")
assert.equal(form.children.length, 1, "as-child adds no public wrapper")
assert.equal(form.querySelectorAll("button").length, 1)
assert.equal(form.querySelectorAll("input").length, 0)
assert.match(form.textContent, /raw text before toggle/)
assert.match(form.textContent, /24/)
assert.ok(
  [...form.childNodes].some(
    (child) => child.nodeType === dom.window.Node.COMMENT_NODE && child.nodeValue === "retained-toggle-comment",
  ),
  "the normalized Fragment preserves its comment sibling",
)
assert.deepEqual(elementAttributes(button), {
  "aria-label": "Server toggle",
  "aria-pressed": "false",
  class: "server-authored-class",
  "data-server-contract": "preserved",
  "data-state": "off",
  id: "server-toggle",
  "phx-click": "request_toggle",
  type: "button",
})
assert.equal(button.tabIndex, 0, "the slotted native button remains focusable")
assert.equal(button.disabled, false, "adapter state overrides a stale disabled child prop")

button.click()
await flushVue(nextTick)
assert.deepEqual(requestedStates, [true])
assert.equal(nativeClickCount, 1)
assert.equal(button.getAttribute("aria-pressed"), "false")
assert.equal(button.getAttribute("data-state"), "off")

button.click()
await flushVue(nextTick)
assert.deepEqual(requestedStates, [true, true], "each request derives from server state")
assert.equal(button.getAttribute("data-state"), "off")

pressed.value = true
await flushVue(nextTick)
assert.equal(button.getAttribute("aria-pressed"), "true")
assert.equal(button.getAttribute("data-state"), "on")

disabled.value = true
await flushVue(nextTick)
assert.equal(button.disabled, true)
assert.equal(button.getAttribute("data-disabled"), "")
button.click()
await flushVue(nextTick)
assert.deepEqual(requestedStates, [true, true])
assert.equal(nativeClickCount, 2, "native disabled buttons do not dispatch a third click")
assert.equal(form.querySelectorAll("input").length, 0)

const mountInvalidToggle = (slot, expectedError) => {
  const container = dom.window.document.createElement("div")
  dom.window.document.body.append(container)
  const InvalidToggleOracle = defineComponent({
    setup: () => () =>
      h(CadenceToggle, {pressed: false}, {default: slot}),
  })
  const invalidApp = createApp(InvalidToggleOracle)
  invalidApp.config.warnHandler = () => {}
  invalidApp.config.errorHandler = (error) => {
    throw error
  }

  assert.throws(() => invalidApp.mount(container), expectedError)
}

mountInvalidToggle(
  () => h(Fragment, null, ["text only", createCommentVNode("no-root")]),
  /CadenceToggle requires exactly one native element child; received 0/,
)
mountInvalidToggle(
  () => h(Fragment, null, [h("button", "First"), h("button", "Second")]),
  /CadenceToggle requires exactly one native element child; received 2/,
)
mountInvalidToggle(
  () => h("a", {href: "#unsupported"}, "Anchor"),
  /CadenceToggle requires a native <button> child; received <a>/,
)

const MultipleRootComponent = defineComponent({
  name: "MultipleRootComponent",
  render: () => [
    h("button", "First component root"),
    h("button", "Second component root"),
  ],
})
mountInvalidToggle(
  () => h(MultipleRootComponent),
  /CadenceToggle requires a native element child; component children are not supported/,
)

const DisabledDefaultComponent = defineComponent({
  name: "DisabledDefaultComponent",
  inheritAttrs: false,
  props: {
    dataDisabled: {
      type: String,
      default: "component-default",
    },
  },
  render() {
    return h("button", {"data-disabled": this.dataDisabled}, "Component button")
  },
})
mountInvalidToggle(
  () => h(DisabledDefaultComponent),
  /CadenceToggle requires a native element child; component children are not supported/,
)

const templateRefContainer = dom.window.document.createElement("div")
dom.window.document.body.append(templateRefContainer)
const TemplateRefOracle = defineComponent({
  name: "CadenceToggleTemplateRefOracle",
  components: {CadenceToggle},
  data: () => ({serverPressed: false}),
  template: `
    <CadenceToggle :pressed="serverPressed">
      <button id="template-ref-toggle" ref="templateToggle" type="button">
        Template ref toggle
      </button>
    </CadenceToggle>
  `,
})
const templateRefApp = createApp(TemplateRefOracle)
const templateRefOwner = templateRefApp.mount(templateRefContainer)
await flushVue(nextTick)
const templateRefButton = dom.window.document.querySelector("#template-ref-toggle")
assert.equal(templateRefOwner.$refs.templateToggle, templateRefButton)
assert.equal(Array.isArray(templateRefOwner.$refs.templateToggle), false)
templateRefOwner.serverPressed = true
await flushVue(nextTick)
assert.equal(templateRefOwner.$refs.templateToggle, templateRefButton)
assert.equal(templateRefButton.getAttribute("data-state"), "on")
assert.doesNotThrow(() => templateRefApp.unmount())

assert.doesNotThrow(() => app.unmount())
dom.window.close()

console.log(`cadence_toggle_adapter_test passed (${scenarios.length} scenarios)`)
