#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

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
import {formPageFrameClass} from "./form_page_frame_test_support.mjs"

const scenarios = Object.freeze([
  "the actual frame SFC owns exactly one native div and its canonical class",
  "root attributes, classes, and listeners forward without a wrapper",
  "caller-owned forms, hidden CSRF fields, controls, links, and events remain native",
  "nested arrays and keyed Fragments flatten while preserving child identity",
])

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
assert.equal(process.execPath, pinnedNode)
assert.equal(process.versions.node, expectedNodeVersion)
assert.equal(scenarios.length, 4)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/ui/components/CadenceFormPageFrame.vue")
const source = await readFile(componentPath, "utf8")
const dom = installDom('<main id="form-page-frame-contract"></main>')

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

assert.deepEqual(parsed.errors, [], "CadenceFormPageFrame parses with the pinned compiler")
assert.ok(parsed.descriptor.script, "CadenceFormPageFrame keeps a typed render-function block")
assert.equal(parsed.descriptor.script.lang, "ts")
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null)
assert.equal(parsed.descriptor.styles.length, 0)

const compiled = compileScript(parsed.descriptor, {id: "cadence-form-page-frame-contract"})
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

const CadenceFormPageFrame = loadedModule.exports.default
const {Fragment, createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")

assert.equal(CadenceFormPageFrame.name, "CadenceFormPageFrame")
assert.equal(CadenceFormPageFrame.inheritAttrs, false)
assert.equal(CadenceFormPageFrame.props, undefined)
assert.equal(CadenceFormPageFrame.emits, undefined)
assert.equal(source.match(/h\(\s*"div"/g)?.length, 1)
assert.equal(source.match(/<div\b/g)?.length ?? 0, 0)
assert.equal(source.match(/<slot\b/g)?.length ?? 0, 0)
assert.equal(source.split(formPageFrameClass).length - 1, 1)
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

const frameId = ref("form-page-frame-initial")
const callerClass = ref("caller-first caller-second")
const mode = ref("edit")
const inputValue = ref("alpha")
const rows = ref([
  {key: "alpha", label: "Alpha"},
  {key: "bravo", label: "Bravo"},
])
const formElement = ref()
const inputElement = ref()
const csrfElement = ref()
const checkboxElement = ref()
const buttonElement = ref()
const linkElement = ref()
let rootClicks = 0
let inputEvents = 0
let formSubmits = 0

const keyedRows = () =>
  rows.value.map(row =>
    h(Fragment, {key: row.key}, [
      [h("article", {id: `form-page-${row.key}`}, row.label)],
      [h("span", {id: `form-page-${row.key}-meta`}, `${row.label} metadata`)],
    ]),
  )

const Contract = defineComponent({
  name: "CadenceFormPageFrameMountedContract",
  setup() {
    return () =>
      h(
        CadenceFormPageFrame,
        {
          id: frameId.value,
          class: callerClass.value,
          "aria-label": "Caller form page",
          "data-mode": mode.value,
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
                id: "caller-form",
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
                  id: "caller-query",
                  name: "spacecraft_type[display_name]",
                  type: "text",
                  value: inputValue.value,
                  onInput: event => {
                    inputEvents += 1
                    inputValue.value = event.target.value
                  },
                }),
                h("input", {
                  ref: csrfElement,
                  id: "caller-csrf",
                  type: "hidden",
                  name: "_csrf_token",
                  value: "frozen-token",
                }),
                h("input", {
                  ref: checkboxElement,
                  id: "caller-enabled",
                  type: "checkbox",
                  name: "spacecraft_type[enabled]",
                  checked: true,
                }),
                h("button", {ref: buttonElement, id: "caller-submit", type: "submit"}, "Save"),
              ],
            ),
            h(
              "a",
              {
                ref: linkElement,
                id: "caller-cancel",
                href: "/spacecraft/types",
                "data-phx-link": "redirect",
                "data-phx-link-state": "push",
              },
              "Cancel",
            ),
            keyedRows(),
          ],
        },
      )
  },
})

const host = dom.window.document.querySelector("#form-page-frame-contract")
const app = createApp(Contract)
app.mount(host)
await flushVue(nextTick)

const root = host.firstElementChild
const form = dom.window.document.querySelector("#caller-form")
const input = dom.window.document.querySelector("#caller-query")
const csrf = dom.window.document.querySelector("#caller-csrf")
const checkbox = dom.window.document.querySelector("#caller-enabled")
const button = dom.window.document.querySelector("#caller-submit")
const link = dom.window.document.querySelector("#caller-cancel")
const alpha = dom.window.document.querySelector("#form-page-alpha")
const bravo = dom.window.document.querySelector("#form-page-bravo")
const alphaMeta = dom.window.document.querySelector("#form-page-alpha-meta")
const bravoMeta = dom.window.document.querySelector("#form-page-bravo-meta")

assert.equal(host.childNodes.length, 1)
assert.equal(root.tagName, "DIV")
assert.equal(root.className, `${formPageFrameClass} ${callerClass.value}`)
assert.deepEqual(elementAttributes(root), {
  "aria-label": "Caller form page",
  class: `${formPageFrameClass} ${callerClass.value}`,
  "data-mode": "edit",
  id: "form-page-frame-initial",
})
assert.deepEqual([...root.children].map(child => child.id), [
  "caller-form",
  "caller-cancel",
  "form-page-alpha",
  "form-page-alpha-meta",
  "form-page-bravo",
  "form-page-bravo-meta",
])
assert.strictEqual(formElement.value, form)
assert.strictEqual(inputElement.value, input)
assert.strictEqual(csrfElement.value, csrf)
assert.strictEqual(checkboxElement.value, checkbox)
assert.strictEqual(buttonElement.value, button)
assert.strictEqual(linkElement.value, link)
assert.equal(form.getAttribute("phx-change"), "validate")
assert.equal(form.getAttribute("phx-submit"), "save")
assert.equal(input.getAttribute("name"), "spacecraft_type[display_name]")
assert.equal(input.value, "alpha")
assert.equal(csrf.getAttribute("type"), "hidden")
assert.equal(csrf.value, "frozen-token")
assert.equal(checkbox.getAttribute("type"), "checkbox")
assert.equal(checkbox.checked, true)
assert.equal(button.getAttribute("type"), "submit")
assert.equal(link.getAttribute("href"), "/spacecraft/types")
assert.equal(link.getAttribute("data-phx-link"), "redirect")

root.dispatchEvent(new dom.window.MouseEvent("click", {bubbles: true}))
button.dispatchEvent(new dom.window.Event("click", {bubbles: true}))
assert.equal(rootClicks, 2)

input.value = "beta"
input.dispatchEvent(new dom.window.Event("input", {bubbles: true}))
await flushVue(nextTick)
assert.equal(inputEvents, 1)
assert.equal(inputValue.value, "beta")

const submitEvent = new dom.window.Event("submit", {bubbles: true, cancelable: true})
assert.equal(form.dispatchEvent(submitEvent), false)
assert.equal(submitEvent.defaultPrevented, true)
assert.equal(formSubmits, 1)

const originalNodes = {
  root,
  form,
  input,
  csrf,
  checkbox,
  button,
  link,
  alpha,
  bravo,
  alphaMeta,
  bravoMeta,
}
frameId.value = "form-page-frame-updated"
callerClass.value = "caller-updated caller-extra"
mode.value = "new"
inputValue.value = "gamma"
rows.value = [rows.value[1], {key: "charlie", label: "Charlie"}, rows.value[0]]
await flushVue(nextTick)

const updatedRoot = dom.window.document.querySelector("#form-page-frame-updated")
assert.strictEqual(updatedRoot, originalNodes.root)
assert.equal(updatedRoot.className, `${formPageFrameClass} ${callerClass.value}`)
assert.deepEqual(elementAttributes(updatedRoot), {
  "aria-label": "Caller form page",
  class: `${formPageFrameClass} ${callerClass.value}`,
  "data-mode": "new",
  id: "form-page-frame-updated",
})
assert.deepEqual([...updatedRoot.children].map(child => child.id), [
  "caller-form",
  "caller-cancel",
  "form-page-bravo",
  "form-page-bravo-meta",
  "form-page-charlie",
  "form-page-charlie-meta",
  "form-page-alpha",
  "form-page-alpha-meta",
])
assert.strictEqual(formElement.value, originalNodes.form)
assert.strictEqual(inputElement.value, originalNodes.input)
assert.strictEqual(csrfElement.value, originalNodes.csrf)
assert.strictEqual(checkboxElement.value, originalNodes.checkbox)
assert.strictEqual(buttonElement.value, originalNodes.button)
assert.strictEqual(linkElement.value, originalNodes.link)
assert.strictEqual(dom.window.document.querySelector("#form-page-alpha"), originalNodes.alpha)
assert.strictEqual(dom.window.document.querySelector("#form-page-bravo"), originalNodes.bravo)
assert.strictEqual(
  dom.window.document.querySelector("#form-page-alpha-meta"),
  originalNodes.alphaMeta,
)
assert.strictEqual(
  dom.window.document.querySelector("#form-page-bravo-meta"),
  originalNodes.bravoMeta,
)
assert.equal(input.value, "gamma")

app.unmount()
dom.window.close()

console.log(`cadence_form_page_frame_test passed (${scenarios.length} exact-DOM scenarios)`)
