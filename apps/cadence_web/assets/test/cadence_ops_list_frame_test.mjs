import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  elementAttributes,
  expectedNodeVersion,
  flushVue,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"
import {opsListFrameClass} from "./ops_list_frame_test_support.mjs"

const scenarios = Object.freeze([
  "the actual frame SFC owns exactly one native section and its canonical class",
  "all caller root attrs, classes, and listeners forward without a wrapper",
  "nested arrays and Fragments flatten to caller-owned native children",
  "caller-owned forms, inputs, buttons, and events remain native",
  "keyed nested Fragments retain unkeyed native child identity across reorder",
])

assert.equal(
  process.execPath,
  "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node",
  "CadenceOpsListFrame contracts use the pinned Node executable",
)
assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `CadenceOpsListFrame contracts use pinned Node ${expectedNodeVersion}`,
)
assert.equal(scenarios.length, 5)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/ui/components/CadenceOpsListFrame.vue")
const source = await readFile(componentPath, "utf8")
const dom = installDom('<div id="ops-list-frame-contract"></div>')
for (const globalName of ["Document", "ShadowRoot", "HTMLFormElement", "HTMLInputElement"]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const parsed = parse(source, {filename: componentPath})

assert.deepEqual(parsed.errors, [], "CadenceOpsListFrame parses with the pinned compiler")
assert.ok(parsed.descriptor.script, "the frame keeps a typed render-function block")
assert.equal(parsed.descriptor.script.lang, "ts")
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null, "the frame avoids template slot anchors")
assert.equal(parsed.descriptor.styles.length, 0)

const compiled = compileScript(parsed.descriptor, {id: "cadence-ops-list-frame-contract"})
const transformed = transformSync(compiled.content, {
  format: "cjs",
  loader: "ts",
  platform: "node",
  target: "node24",
})
const loadedModule = {exports: {}}
new Function("require", "module", "exports", transformed.code)(
  integrationRequire,
  loadedModule,
  loadedModule.exports,
)

const CadenceOpsListFrame = loadedModule.exports.default
const {Fragment, createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")

assert.equal(CadenceOpsListFrame.inheritAttrs, false)
assert.equal(CadenceOpsListFrame.props, undefined)
assert.equal(CadenceOpsListFrame.emits, undefined)
assert.equal(source.match(/h\(\s*"section"/g)?.length, 1)
assert.equal(source.match(/<section\b/g)?.length ?? 0, 0)
assert.equal(source.match(/<slot\b/g)?.length ?? 0, 0)
assert.equal(source.match(new RegExp(opsListFrameClass, "g"))?.length, 1)
assert.match(source, /Array\.isArray\(child\)/)
assert.match(source, /child\.type === Fragment/)
assert.match(source, /cloneVNode\(child/)
assert.match(source, /String\(inheritedKey\)/)
assert.match(source, /keyPath/)
assert.doesNotMatch(
  source,
  /<template|<style|defineProps|defineEmits|\b(?:computed|reactive|ref|watch|onMounted)\s*\(|\b(?:id|value|role|aria-[\w-]+)\s*:/,
  "the frame owns no template, controls, IDs, values, state, events, or semantics",
)

const frameId = ref("ops-list-frame-initial")
const callerClass = ref("caller-first caller-second")
const phase = ref("ready")
const inputValue = ref("alpha")
const items = ref([
  {key: "alpha", label: "Alpha"},
  {key: "bravo", label: "Bravo"},
])
const formElement = ref()
const inputElement = ref()
let rootClicks = 0
let formSubmits = 0
let inputEvents = 0
let buttonClicks = 0

const Contract = defineComponent({
  name: "CadenceOpsListFrameMountedContract",
  setup() {
    return () =>
      h(
        CadenceOpsListFrame,
        {
          id: frameId.value,
          class: callerClass.value,
          "aria-label": "Caller operations list",
          "data-phase": phase.value,
          onClick: () => {
            rootClicks += 1
          },
        },
        {
          default: () => [
            h(Fragment, null, [
              [
                h(
                  "form",
                  {
                    ref: formElement,
                    id: "caller-ops-list-form",
                    "phx-change": "search",
                    onSubmit: event => {
                      event.preventDefault()
                      formSubmits += 1
                    },
                  },
                  [
                    h("input", {
                      ref: inputElement,
                      id: "caller-ops-list-query",
                      name: "q",
                      type: "search",
                      value: inputValue.value,
                      onInput: event => {
                        inputEvents += 1
                        inputValue.value = event.target.value
                      },
                    }),
                    h(
                      "button",
                      {
                        id: "caller-ops-list-action",
                        type: "button",
                        onClick: () => {
                          buttonClicks += 1
                        },
                      },
                      "Run",
                    ),
                  ],
                ),
                items.value.map(item =>
                  h(Fragment, {key: item.key}, [
                    h("article", {id: `caller-ops-list-${item.key}`, "data-item": item.key}, item.label),
                    h(
                      "span",
                      {
                        id: `caller-ops-list-${item.key}-meta`,
                        "data-item-meta": item.key,
                      },
                      `${item.label} metadata`,
                    ),
                  ]),
                ),
              ],
            ]),
          ],
        },
      )
  },
})

const host = dom.window.document.querySelector("#ops-list-frame-contract")
const app = createApp(Contract)
app.mount(host)
await flushVue(nextTick)

const root = host.firstElementChild
const form = dom.window.document.querySelector("#caller-ops-list-form")
const input = dom.window.document.querySelector("#caller-ops-list-query")
const button = dom.window.document.querySelector("#caller-ops-list-action")
const alpha = dom.window.document.querySelector("#caller-ops-list-alpha")
const bravo = dom.window.document.querySelector("#caller-ops-list-bravo")
const alphaMeta = dom.window.document.querySelector("#caller-ops-list-alpha-meta")
const bravoMeta = dom.window.document.querySelector("#caller-ops-list-bravo-meta")

assert.equal(host.childNodes.length, 1, "the frame adds no sibling or wrapper node")
assert.equal(root.tagName, "SECTION")
assert.equal(root.className, `${opsListFrameClass} ${callerClass.value}`)
assert.deepEqual(elementAttributes(root), {
  "aria-label": "Caller operations list",
  class: `${opsListFrameClass} ${callerClass.value}`,
  "data-phase": "ready",
  id: "ops-list-frame-initial",
})
assert.deepEqual(
  [...root.children].map(child => child.id),
  [
    "caller-ops-list-form",
    "caller-ops-list-alpha",
    "caller-ops-list-alpha-meta",
    "caller-ops-list-bravo",
    "caller-ops-list-bravo-meta",
  ],
)
assert.strictEqual(root.firstElementChild, form)
assert.strictEqual(formElement.value, form)
assert.strictEqual(inputElement.value, input)
assert.equal(input.value, "alpha")
assert.equal(form.getAttribute("phx-change"), "search")
assert.equal(input.getAttribute("name"), "q")
assert.equal(input.getAttribute("type"), "search")
assert.equal(button.getAttribute("type"), "button")
assert.equal(alpha.getAttribute("data-item"), "alpha")
assert.equal(bravo.getAttribute("data-item"), "bravo")
assert.equal(alphaMeta.getAttribute("data-item-meta"), "alpha")
assert.equal(bravoMeta.getAttribute("data-item-meta"), "bravo")

root.dispatchEvent(new dom.window.MouseEvent("click", {bubbles: true}))
button.dispatchEvent(new dom.window.MouseEvent("click", {bubbles: true}))
assert.equal(rootClicks, 2, "the caller root listener receives native bubbled clicks")
assert.equal(buttonClicks, 1, "the caller button listener remains native")

input.value = "beta"
input.dispatchEvent(new dom.window.Event("input", {bubbles: true}))
await flushVue(nextTick)
assert.equal(inputEvents, 1)
assert.equal(inputValue.value, "beta")

const submitEvent = new dom.window.Event("submit", {bubbles: true, cancelable: true})
assert.equal(form.dispatchEvent(submitEvent), false)
assert.equal(submitEvent.defaultPrevented, true)
assert.equal(formSubmits, 1)

const originalNodes = {root, form, input, alpha, bravo, alphaMeta, bravoMeta}
frameId.value = "ops-list-frame-updated"
callerClass.value = "caller-updated caller-extra"
phase.value = "running"
inputValue.value = "gamma"
items.value = [items.value[1], {key: "charlie", label: "Charlie"}, items.value[0]]
await flushVue(nextTick)

const updatedRoot = dom.window.document.querySelector("#ops-list-frame-updated")
assert.strictEqual(updatedRoot, originalNodes.root)
assert.equal(updatedRoot.className, `${opsListFrameClass} ${callerClass.value}`)
assert.deepEqual(elementAttributes(updatedRoot), {
  "aria-label": "Caller operations list",
  class: `${opsListFrameClass} ${callerClass.value}`,
  "data-phase": "running",
  id: "ops-list-frame-updated",
})
assert.deepEqual(
  [...updatedRoot.children].map(child => child.id),
  [
    "caller-ops-list-form",
    "caller-ops-list-bravo",
    "caller-ops-list-bravo-meta",
    "caller-ops-list-charlie",
    "caller-ops-list-charlie-meta",
    "caller-ops-list-alpha",
    "caller-ops-list-alpha-meta",
  ],
)
assert.strictEqual(updatedRoot.firstElementChild, originalNodes.form)
assert.strictEqual(formElement.value, originalNodes.form)
assert.strictEqual(inputElement.value, originalNodes.input)
assert.strictEqual(dom.window.document.querySelector("#caller-ops-list-alpha"), originalNodes.alpha)
assert.strictEqual(dom.window.document.querySelector("#caller-ops-list-bravo"), originalNodes.bravo)
assert.strictEqual(
  dom.window.document.querySelector("#caller-ops-list-alpha-meta"),
  originalNodes.alphaMeta,
)
assert.strictEqual(
  dom.window.document.querySelector("#caller-ops-list-bravo-meta"),
  originalNodes.bravoMeta,
)
assert.equal(input.value, "gamma")

assert.doesNotThrow(() => app.unmount())
dom.window.close()

console.log(`cadence_ops_list_frame_test passed (${scenarios.length} exact-DOM scenarios)`)
