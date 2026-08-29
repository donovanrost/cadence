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
import {narrowFormPageFrameClass} from "./narrow_form_page_frame_test_support.mjs"

const scenarios = Object.freeze([
  "the actual frame SFC owns exactly one native div and its canonical class",
  "all caller root attrs, classes, and listeners forward without a wrapper",
  "caller-owned forms, controls, links, and events remain native",
  "nested arrays and keyed Fragments flatten while preserving child identity",
])

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
assert.equal(process.execPath, pinnedNode)
assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `CadenceNarrowFormPageFrame contracts use pinned Node ${expectedNodeVersion}`,
)
assert.equal(scenarios.length, 4)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(
  testDirectory,
  "../vue/ui/components/CadenceNarrowFormPageFrame.vue",
)
const source = await readFile(componentPath, "utf8")
const dom = installDom('<div id="narrow-form-page-frame-contract"></div>')

for (const globalName of [
  "Document",
  "ShadowRoot",
  "HTMLFormElement",
  "HTMLInputElement",
  "HTMLButtonElement",
]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const parsed = parse(source, {filename: componentPath})

assert.deepEqual(parsed.errors, [], "CadenceNarrowFormPageFrame parses with the pinned compiler")
assert.ok(parsed.descriptor.script, "the frame keeps a typed render-function block")
assert.equal(parsed.descriptor.script.lang, "ts")
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null, "the frame avoids template slot anchors")
assert.equal(parsed.descriptor.styles.length, 0)

const compiled = compileScript(parsed.descriptor, {id: "cadence-narrow-form-page-frame-contract"})
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

const CadenceNarrowFormPageFrame = loadedModule.exports.default
const {Fragment, createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")

assert.equal(CadenceNarrowFormPageFrame.inheritAttrs, false)
assert.equal(CadenceNarrowFormPageFrame.props, undefined)
assert.equal(CadenceNarrowFormPageFrame.emits, undefined)
assert.equal(source.match(/h\(\s*"div"/g)?.length, 1)
assert.equal(source.match(/<div\b/g)?.length ?? 0, 0)
assert.equal(source.match(/<slot\b/g)?.length ?? 0, 0)
assert.equal(source.split(narrowFormPageFrameClass).length - 1, 1)
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

const frameId = ref("narrow-form-page-frame-initial")
const callerClass = ref("caller-first caller-second")
const phase = ref("ready")
const inputValue = ref("alpha")
const groups = ref([
  {key: "alpha", label: "Alpha"},
  {key: "bravo", label: "Bravo"},
])
const formElement = ref()
const inputElement = ref()
const buttonElement = ref()
const linkElement = ref()
let rootClicks = 0
let formSubmits = 0
let inputEvents = 0
let buttonClicks = 0

const Contract = defineComponent({
  name: "CadenceNarrowFormPageFrameMountedContract",
  setup() {
    return () =>
      h(
        CadenceNarrowFormPageFrame,
        {
          id: frameId.value,
          class: callerClass.value,
          "aria-label": "Caller narrow form page",
          "data-phase": phase.value,
          onClick: () => {
            rootClicks += 1
          },
        },
        {
          default: () => [
            h(
              "form",
              {
                ref: formElement,
                id: "caller-narrow-form",
                "phx-change": "validate",
                "phx-submit": "save",
                onSubmit: event => {
                  event.preventDefault()
                  formSubmits += 1
                },
              },
              [
                h("input", {
                  ref: inputElement,
                  id: "caller-narrow-query",
                  name: "mission[display_name]",
                  type: "text",
                  value: inputValue.value,
                  onInput: event => {
                    inputEvents += 1
                    inputValue.value = event.target.value
                  },
                }),
                h(
                  "button",
                  {
                    ref: buttonElement,
                    id: "caller-narrow-submit",
                    type: "submit",
                    onClick: () => {
                      buttonClicks += 1
                    },
                  },
                  "Save",
                ),
              ],
            ),
            h(
              "a",
              {
                ref: linkElement,
                id: "caller-narrow-cancel",
                href: "/missions",
                "data-phx-link": "redirect",
                "data-phx-link-state": "push",
              },
              "Cancel",
            ),
            groups.value.map(group =>
              h(Fragment, {key: group.key}, [
                [h("article", {id: `caller-narrow-${group.key}`}, group.label)],
                [
                  h(
                    "span",
                    {id: `caller-narrow-${group.key}-meta`},
                    `${group.label} metadata`,
                  ),
                ],
              ]),
            ),
          ],
        },
      )
  },
})

const host = dom.window.document.querySelector("#narrow-form-page-frame-contract")
const app = createApp(Contract)
app.mount(host)
await flushVue(nextTick)

const root = host.firstElementChild
const form = dom.window.document.querySelector("#caller-narrow-form")
const input = dom.window.document.querySelector("#caller-narrow-query")
const button = dom.window.document.querySelector("#caller-narrow-submit")
const link = dom.window.document.querySelector("#caller-narrow-cancel")
const alpha = dom.window.document.querySelector("#caller-narrow-alpha")
const bravo = dom.window.document.querySelector("#caller-narrow-bravo")
const alphaMeta = dom.window.document.querySelector("#caller-narrow-alpha-meta")
const bravoMeta = dom.window.document.querySelector("#caller-narrow-bravo-meta")

assert.equal(host.childNodes.length, 1, "the frame adds no sibling or wrapper node")
assert.equal(root.tagName, "DIV")
assert.equal(root.className, `${narrowFormPageFrameClass} ${callerClass.value}`)
assert.deepEqual(elementAttributes(root), {
  "aria-label": "Caller narrow form page",
  class: `${narrowFormPageFrameClass} ${callerClass.value}`,
  "data-phase": "ready",
  id: "narrow-form-page-frame-initial",
})
assert.deepEqual([...root.children].map(child => child.id), [
  "caller-narrow-form",
  "caller-narrow-cancel",
  "caller-narrow-alpha",
  "caller-narrow-alpha-meta",
  "caller-narrow-bravo",
  "caller-narrow-bravo-meta",
])
assert.strictEqual(formElement.value, form)
assert.strictEqual(inputElement.value, input)
assert.strictEqual(buttonElement.value, button)
assert.strictEqual(linkElement.value, link)
assert.equal(form.getAttribute("phx-change"), "validate")
assert.equal(form.getAttribute("phx-submit"), "save")
assert.equal(input.getAttribute("name"), "mission[display_name]")
assert.equal(input.getAttribute("type"), "text")
assert.equal(input.value, "alpha")
assert.equal(button.getAttribute("type"), "submit")
assert.equal(link.getAttribute("href"), "/missions")
assert.equal(link.getAttribute("data-phx-link"), "redirect")

root.dispatchEvent(new dom.window.MouseEvent("click", {bubbles: true}))
button.dispatchEvent(new dom.window.Event("click", {bubbles: true}))
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

const originalNodes = {root, form, input, button, link, alpha, bravo, alphaMeta, bravoMeta}
frameId.value = "narrow-form-page-frame-updated"
callerClass.value = "caller-updated caller-extra"
phase.value = "running"
inputValue.value = "gamma"
groups.value = [groups.value[1], {key: "charlie", label: "Charlie"}, groups.value[0]]
await flushVue(nextTick)

const updatedRoot = dom.window.document.querySelector("#narrow-form-page-frame-updated")
assert.strictEqual(updatedRoot, originalNodes.root)
assert.equal(updatedRoot.className, `${narrowFormPageFrameClass} ${callerClass.value}`)
assert.deepEqual(elementAttributes(updatedRoot), {
  "aria-label": "Caller narrow form page",
  class: `${narrowFormPageFrameClass} ${callerClass.value}`,
  "data-phase": "running",
  id: "narrow-form-page-frame-updated",
})
assert.deepEqual([...updatedRoot.children].map(child => child.id), [
  "caller-narrow-form",
  "caller-narrow-cancel",
  "caller-narrow-bravo",
  "caller-narrow-bravo-meta",
  "caller-narrow-charlie",
  "caller-narrow-charlie-meta",
  "caller-narrow-alpha",
  "caller-narrow-alpha-meta",
])
assert.strictEqual(formElement.value, originalNodes.form)
assert.strictEqual(inputElement.value, originalNodes.input)
assert.strictEqual(buttonElement.value, originalNodes.button)
assert.strictEqual(linkElement.value, originalNodes.link)
assert.strictEqual(dom.window.document.querySelector("#caller-narrow-alpha"), originalNodes.alpha)
assert.strictEqual(dom.window.document.querySelector("#caller-narrow-bravo"), originalNodes.bravo)
assert.strictEqual(
  dom.window.document.querySelector("#caller-narrow-alpha-meta"),
  originalNodes.alphaMeta,
)
assert.strictEqual(
  dom.window.document.querySelector("#caller-narrow-bravo-meta"),
  originalNodes.bravoMeta,
)
assert.equal(input.value, "gamma")

assert.doesNotThrow(() => app.unmount())
dom.window.close()

console.log(`cadence_narrow_form_page_frame_test passed (${scenarios.length} exact-DOM scenarios)`)
