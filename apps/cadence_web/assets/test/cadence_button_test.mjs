import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  elementAttributes,
  flushVue,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"

const scenarios = Object.freeze([
  "CadenceButton owns only one transparent native button root",
  "all attributes and listeners fall through without changing class order",
  "the default slot preserves child and text order without a wrapper",
  "native disabled behavior suppresses the fallen-through click listener",
])

assert.equal(process.versions.node, "24.16.0", "button contracts use pinned Node 24.16.0")
assert.equal(scenarios.length, 4)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/ui/components/CadenceButton.vue")
const dom = installDom('<div id="app"></div>')
const source = await readFile(componentPath, "utf8")
const {parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const parsed = parse(source, {filename: componentPath})

assert.deepEqual(parsed.errors, [], "CadenceButton.vue parses with the pinned Vue compiler")
assert.ok(parsed.descriptor.script, "CadenceButton.vue keeps an auditable native render function")
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null)

const transformed = transformSync(parsed.descriptor.script.content, {
  format: "cjs",
  loader: "js",
  platform: "node",
  target: "node24",
})
const cadenceButtonModule = {exports: {}}
new Function("require", "module", "exports", transformed.code)(
  integrationRequire,
  cadenceButtonModule,
  cadenceButtonModule.exports,
)
const CadenceButton = cadenceButtonModule.exports.default

assert.deepEqual(Object.keys(CadenceButton.props ?? {}), [])
assert.equal(CadenceButton.inheritAttrs, true)
assert.match(
  parsed.descriptor.script.content,
  /return \(\) => h\("button", null, slots\.default\?\.\(\)\)/,
)
assert.doesNotMatch(source, /class=|<template>|h\("div"|h\("span"/)

const {createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")
const disabled = ref(false)
let clickCount = 0

const RuntimeOracle = defineComponent({
  name: "CadenceButtonRuntimeOracle",
  setup() {
    return () =>
      h(
        CadenceButton,
        {
          id: "cadence-button-oracle",
          type: "button",
          disabled: disabled.value,
          class: "first second third",
          title: "Transparent button",
          "aria-label": "Transparent button contract",
          "data-contract": "native-fallthrough",
          onClick: () => {
            clickCount += 1
          },
        },
        {
          default: () => [
            h("span", {id: "first-slot-child"}, "Icon"),
            " Exact label ",
            h("em", {id: "last-slot-child"}, "tail"),
          ],
        },
      )
  },
})

const app = createApp(RuntimeOracle)
app.mount(dom.window.document.querySelector("#app"))
await flushVue(nextTick)

const container = dom.window.document.querySelector("#app")
const button = dom.window.document.querySelector("#cadence-button-oracle")

assert.equal(container.children.length, 1)
assert.equal(container.firstElementChild, button)
assert.equal(button.tagName, "BUTTON")
assert.deepEqual(elementAttributes(button), {
  "aria-label": "Transparent button contract",
  class: "first second third",
  "data-contract": "native-fallthrough",
  id: "cadence-button-oracle",
  title: "Transparent button",
  type: "button",
})
assert.equal(button.className, "first second third")
assert.equal(button.childNodes.length, 3)
assert.equal(button.childNodes[0].id, "first-slot-child")
assert.equal(button.childNodes[1].nodeType, dom.window.Node.TEXT_NODE)
assert.equal(button.childNodes[1].textContent, " Exact label ")
assert.equal(button.childNodes[2].id, "last-slot-child")
assert.equal(button.textContent, "Icon Exact label tail")

button.click()
assert.equal(clickCount, 1)

disabled.value = true
await flushVue(nextTick)

assert.equal(button.disabled, true)
assert.equal(button.getAttribute("disabled"), "")
button.click()
assert.equal(clickCount, 1)

assert.doesNotThrow(() => app.unmount())
console.log(`cadence_button_test passed (${scenarios.length} semantic scenarios)`)
