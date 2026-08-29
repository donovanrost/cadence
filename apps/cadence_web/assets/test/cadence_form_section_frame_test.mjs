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
import {formSectionFrameClass} from "./form_section_frame_test_support.mjs"

const scenarios = Object.freeze([
  "the actual frame SFC owns exactly one native section and its canonical class",
  "root attributes, classes, and listeners forward without a wrapper",
  "caller-owned forms, hidden CSRF fields, controls, links, and events remain native",
  "nested arrays and keyed Fragments flatten while preserving child identity",
])

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
assert.equal(process.execPath, pinnedNode)
assert.equal(process.versions.node, expectedNodeVersion)
assert.equal(scenarios.length, 4)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/ui/components/CadenceFormSectionFrame.vue")
const source = await readFile(componentPath, "utf8")
const dom = installDom('<main id="form-section-frame-contract"></main>')

for (const globalName of [
  "Document",
  "ShadowRoot",
  "HTMLFormElement",
  "HTMLInputElement",
  "HTMLButtonElement",
  "HTMLAnchorElement",
]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const parsed = parse(source, {filename: componentPath})

assert.deepEqual(parsed.errors, [], "CadenceFormSectionFrame parses with the pinned compiler")
assert.ok(parsed.descriptor.script, "CadenceFormSectionFrame keeps a typed render-function block")
assert.equal(parsed.descriptor.script.lang, "ts")
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null)
assert.equal(parsed.descriptor.styles.length, 0)

const compiled = compileScript(parsed.descriptor, {id: "cadence-form-section-frame-contract"})
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

const CadenceFormSectionFrame = loadedModule.exports.default
const {Fragment, createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")

assert.equal(CadenceFormSectionFrame.name, "CadenceFormSectionFrame")
assert.equal(CadenceFormSectionFrame.inheritAttrs, false)
assert.equal(CadenceFormSectionFrame.props, undefined)
assert.equal(CadenceFormSectionFrame.emits, undefined)
assert.equal(source.match(/h\(\s*"section"/g)?.length, 1)
assert.equal(source.match(/<section\b/g)?.length ?? 0, 0)
assert.equal(source.match(/<slot\b/g)?.length ?? 0, 0)
assert.equal(source.split(formSectionFrameClass).length - 1, 1)
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

const frameId = ref("form-section-frame-initial")
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
      [h("article", {id: `form-section-${row.key}`}, row.label)],
      [h("span", {id: `form-section-${row.key}-meta`}, `${row.label} metadata`)],
    ]),
  )

const Contract = defineComponent({
  name: "CadenceFormSectionFrameMountedContract",
  setup() {
    return () =>
      h(
        CadenceFormSectionFrame,
        {
          id: frameId.value,
          class: callerClass.value,
          "aria-label": "Caller form section",
          "data-mode": mode.value,
          onClick: () => {
            rootClicks += 1
          },
        },
        {
          default: () => [
            h("div", {id: "caller-header"}, "Section header"),
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

const host = dom.window.document.querySelector("#form-section-frame-contract")
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
const alpha = dom.window.document.querySelector("#form-section-alpha")
const bravo = dom.window.document.querySelector("#form-section-bravo")
const alphaMeta = dom.window.document.querySelector("#form-section-alpha-meta")
const bravoMeta = dom.window.document.querySelector("#form-section-bravo-meta")

assert.equal(host.childNodes.length, 1)
assert.equal(host.querySelectorAll("section").length, 1)
assert.equal(root.tagName, "SECTION")
assert.equal(root.className, `${formSectionFrameClass} ${callerClass.value}`)
assert.deepEqual(elementAttributes(root), {
  "aria-label": "Caller form section",
  class: `${formSectionFrameClass} ${callerClass.value}`,
  "data-mode": "edit",
  id: "form-section-frame-initial",
})
assert.deepEqual([...root.children].map(child => child.id), [
  "caller-header",
  "caller-form",
  "caller-cancel",
  "form-section-alpha",
  "form-section-alpha-meta",
  "form-section-bravo",
  "form-section-bravo-meta",
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
frameId.value = "form-section-frame-updated"
callerClass.value = "caller-updated caller-extra"
mode.value = "new"
inputValue.value = "gamma"
rows.value = [rows.value[1], {key: "charlie", label: "Charlie"}, rows.value[0]]
await flushVue(nextTick)

const updatedRoot = dom.window.document.querySelector("#form-section-frame-updated")
assert.strictEqual(updatedRoot, originalNodes.root)
assert.equal(updatedRoot.className, `${formSectionFrameClass} ${callerClass.value}`)
assert.deepEqual(elementAttributes(updatedRoot), {
  "aria-label": "Caller form section",
  class: `${formSectionFrameClass} ${callerClass.value}`,
  "data-mode": "new",
  id: "form-section-frame-updated",
})
assert.deepEqual([...updatedRoot.children].map(child => child.id), [
  "caller-header",
  "caller-form",
  "caller-cancel",
  "form-section-bravo",
  "form-section-bravo-meta",
  "form-section-charlie",
  "form-section-charlie-meta",
  "form-section-alpha",
  "form-section-alpha-meta",
])
assert.strictEqual(formElement.value, originalNodes.form)
assert.strictEqual(inputElement.value, originalNodes.input)
assert.strictEqual(csrfElement.value, originalNodes.csrf)
assert.strictEqual(checkboxElement.value, originalNodes.checkbox)
assert.strictEqual(buttonElement.value, originalNodes.button)
assert.strictEqual(linkElement.value, originalNodes.link)
assert.strictEqual(dom.window.document.querySelector("#form-section-alpha"), originalNodes.alpha)
assert.strictEqual(dom.window.document.querySelector("#form-section-bravo"), originalNodes.bravo)
assert.strictEqual(
  dom.window.document.querySelector("#form-section-alpha-meta"),
  originalNodes.alphaMeta,
)
assert.strictEqual(
  dom.window.document.querySelector("#form-section-bravo-meta"),
  originalNodes.bravoMeta,
)
assert.equal(input.value, "gamma")

app.unmount()
dom.window.close()
console.log("cadence_form_section_frame_test passed")
