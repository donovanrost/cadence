import assert from "node:assert/strict"
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
  "as-child composition preserves the one public focusable element and all child attributes",
  "activation emits the requested next state without optimistic local mutation",
  "disabled activation emits nothing and the adapter never introduces a hidden input",
])

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/ui/reka/CadenceToggle.vue")
const packageLockPath = resolve(testDirectory, "../../package-lock.json")

await assertPinnedAdapterRuntime(packageLockPath)
assert.equal(scenarios.length, 4)

const dom = installDom()
const {component: CadenceToggle, descriptor, source} = await loadSfc(componentPath)
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
assert.doesNotMatch(source, /\bv-model\b|defaultValue|default-value|<input\b|\bname=|\bref\(|\breactive\(/)

const {createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")
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

app.unmount()
dom.window.close()

console.log(`cadence_toggle_adapter_test passed (${scenarios.length} scenarios)`)
