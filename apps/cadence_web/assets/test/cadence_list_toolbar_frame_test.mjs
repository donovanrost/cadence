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
import {listToolbarFrameClass} from "./list_toolbar_frame_test_support.mjs"

const scenarios = Object.freeze([
  "the actual frame SFC owns exactly one native div and its canonical class",
  "all caller root attrs, classes, and listeners forward without a wrapper",
  "nested arrays and Fragments flatten to the exact caller-owned form",
  "the caller-owned form and input retain native attributes and listeners",
  "reactive attrs and input values update without replacing caller-owned nodes",
])

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `CadenceListToolbarFrame contracts use pinned Node ${expectedNodeVersion}`,
)
assert.equal(scenarios.length, 5)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/ui/components/CadenceListToolbarFrame.vue")
const source = await readFile(componentPath, "utf8")
const dom = installDom('<div id="list-toolbar-contract"></div>')
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const parsed = parse(source, {filename: componentPath})

assert.deepEqual(parsed.errors, [], "CadenceListToolbarFrame parses with the pinned compiler")
assert.ok(parsed.descriptor.script, "the frame keeps a typed render-function block")
assert.equal(parsed.descriptor.script.lang, "ts")
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null, "the frame avoids template slot anchors")

const compiled = compileScript(parsed.descriptor, {id: "cadence-list-toolbar-frame-contract"})
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

const CadenceListToolbarFrame = loadedModule.exports.default
const {Fragment, createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")

assert.equal(CadenceListToolbarFrame.inheritAttrs, false)
assert.equal(CadenceListToolbarFrame.props, undefined)
assert.equal(CadenceListToolbarFrame.emits, undefined)
assert.equal(source.match(/h\(\s*"div"/g)?.length, 1, "the frame owns one native div")
assert.match(source, new RegExp(JSON.stringify(listToolbarFrameClass).slice(1, -1)))
assert.match(source, /Array\.isArray\(child\)/)
assert.match(source, /child\.type === Fragment/)
assert.doesNotMatch(
  source,
  /<template|<form|<input|<button|<select|defineProps|defineEmits|\b(?:computed|reactive|ref|watch)\s*\(|\bemit\s*\(|\b(?:id|value|role|aria-[\w-]+)\s*:/,
  "the frame owns no template, controls, IDs, values, state, events, or semantics",
)

const toolbarId = ref("caller-toolbar-initial")
const callerClass = ref("caller-toolbar-first caller-toolbar-second")
const phase = ref("ready")
const searchValue = ref("alpha")
const formElement = ref()
const inputElement = ref()
let rootClicks = 0
let formSubmits = 0
let inputEvents = 0

const ToolbarContract = defineComponent({
  name: "CadenceListToolbarFrameContract",
  setup() {
    return () =>
      h(
        CadenceListToolbarFrame,
        {
          id: toolbarId.value,
          class: callerClass.value,
          "aria-label": "Caller list controls",
          "data-phase": phase.value,
          onClick: () => {
            rootClicks += 1
          },
        },
        {
          default: () => [
            h(Fragment, null, [
              [
                h(Fragment, null, [
                  [
                    h(
                      "form",
                      {
                        ref: formElement,
                        id: "caller-toolbar-search-form",
                        "phx-change": "search",
                        class: "w-64 max-w-full",
                        onSubmit: (event) => {
                          event.preventDefault()
                          formSubmits += 1
                        },
                      },
                      [
                        h("div", {class: "fieldset"}, [
                          h("label", null, [
                            h("input", {
                              ref: inputElement,
                              id: "caller-toolbar-search",
                              name: "q",
                              type: "search",
                              value: searchValue.value,
                              placeholder: "Search caller rows",
                              class: "w-full input input-sm",
                              "phx-debounce": "300",
                              onInput: (event) => {
                                inputEvents += 1
                                searchValue.value = event.target.value
                              },
                            }),
                          ]),
                        ]),
                      ],
                    ),
                  ],
                ]),
              ],
            ]),
          ],
        },
      )
  },
})

const expectedOuterHtml = (id, classes, currentPhase, value) =>
  `<div id="${id}" class="${listToolbarFrameClass} ${classes}" aria-label="Caller list controls" data-phase="${currentPhase}"><form id="caller-toolbar-search-form" phx-change="search" class="w-64 max-w-full"><div class="fieldset"><label><input id="caller-toolbar-search" name="q" type="search" placeholder="Search caller rows" class="w-full input input-sm" phx-debounce="300" value="${value}"></label></div></form></div>`

const host = dom.window.document.querySelector("#list-toolbar-contract")
const app = createApp(ToolbarContract)
app.mount(host)
await flushVue(nextTick)

const root = host.firstElementChild
const form = dom.window.document.querySelector("#caller-toolbar-search-form")
const input = dom.window.document.querySelector("#caller-toolbar-search")

assert.equal(host.childNodes.length, 1, "the component adds no sibling or wrapper node")
assert.equal(root.tagName, "DIV")
assert.equal(root.outerHTML, expectedOuterHtml(toolbarId.value, callerClass.value, phase.value, "alpha"))
assert.deepEqual(elementAttributes(root), {
  "aria-label": "Caller list controls",
  class: `${listToolbarFrameClass} ${callerClass.value}`,
  "data-phase": "ready",
  id: "caller-toolbar-initial",
})
assert.equal(root.childNodes.length, 1)
assert.strictEqual(root.firstElementChild, form)
assert.strictEqual(formElement.value, form)
assert.strictEqual(inputElement.value, input)
assert.deepEqual(elementAttributes(form), {
  class: "w-64 max-w-full",
  id: "caller-toolbar-search-form",
  "phx-change": "search",
})
assert.deepEqual(elementAttributes(input), {
  class: "w-full input input-sm",
  id: "caller-toolbar-search",
  name: "q",
  "phx-debounce": "300",
  placeholder: "Search caller rows",
  type: "search",
  value: "alpha",
})

const originalNodes = {root, form, input}

root.dispatchEvent(new dom.window.MouseEvent("click", {bubbles: true}))
assert.equal(rootClicks, 1, "the caller root listener falls through to the native div")

input.value = "beta"
input.dispatchEvent(new dom.window.Event("input", {bubbles: true}))
await flushVue(nextTick)
assert.equal(inputEvents, 1)
assert.equal(searchValue.value, "beta")

const submitEvent = new dom.window.Event("submit", {bubbles: true, cancelable: true})
assert.equal(form.dispatchEvent(submitEvent), false)
assert.equal(submitEvent.defaultPrevented, true)
assert.equal(formSubmits, 1)

toolbarId.value = "caller-toolbar-updated"
callerClass.value = "caller-toolbar-updated caller-toolbar-extra"
phase.value = "running"
searchValue.value = "gamma"
await flushVue(nextTick)

const updatedRoot = dom.window.document.querySelector("#caller-toolbar-updated")

assert.strictEqual(updatedRoot, originalNodes.root)
assert.strictEqual(updatedRoot.firstElementChild, originalNodes.form)
assert.strictEqual(formElement.value, originalNodes.form)
assert.strictEqual(inputElement.value, originalNodes.input)
assert.equal(input.value, "gamma")
assert.equal(
  updatedRoot.outerHTML,
  expectedOuterHtml(toolbarId.value, callerClass.value, phase.value, "gamma"),
)

assert.doesNotThrow(() => app.unmount())
dom.window.close()

console.log(
  `cadence_list_toolbar_frame_test passed (${scenarios.length} exact-DOM scenarios)`,
)
