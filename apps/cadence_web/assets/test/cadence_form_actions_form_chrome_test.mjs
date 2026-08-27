import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  elementAttributes,
  expectedNodeVersion,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `CadenceFormActions contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/ui/components/CadenceFormActions.vue")
const source = await readFile(componentPath, "utf8")
const dom = installDom('<form id="parent-form"><div id="actions-contract"></div></form>')
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const parsed = parse(source, {filename: componentPath})

assert.deepEqual(parsed.errors, [], "CadenceFormActions.vue parses with the pinned Vue compiler")
assert.ok(parsed.descriptor.script, "CadenceFormActions keeps a typed render-function block")
assert.equal(parsed.descriptor.script.lang, "ts")
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null, "the action wrapper avoids slot fragment anchors")

const compiled = compileScript(parsed.descriptor, {id: "cadence-form-actions-contract"})
const transformed = transformSync(compiled.content, {
  format: "cjs",
  loader: "ts",
  platform: "node",
  target: "node24",
})
const loadedModule = {exports: {}}
const evaluate = new Function("require", "module", "exports", transformed.code)
evaluate(integrationRequire, loadedModule, loadedModule.exports)
const CadenceFormActions = loadedModule.exports.default
const {createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")

assert.match(
  parsed.descriptor.script.content,
  /return \(\) => h\("div", \{class: props\.wrapperClass\}, slots\.default\?\.\(\)\)/,
  "the render function owns only the caller-classed wrapper and default slot",
)
assert.doesNotMatch(
  source,
  /\b(?:computed|reactive|ref|watch)\s*\(|defineEmits|@(?:click|input|change|submit)|\bfetch\s*\(|<button|<a\b|href|data-phx-link/,
  "the action wrapper owns no controls, state, events, routing, or Phoenix behavior",
)

const disabled = ref(true)
let nativeButton = null
let nativeLink = null
const Contract = defineComponent({
  setup() {
    return () =>
      h(
        CadenceFormActions,
        {wrapperClass: "flex items-center gap-3 border-t border-base-300/60 pt-5"},
        {
          default: () => [
            h(
              "button",
              {
                ref: (element) => {
                  nativeButton = element
                },
                id: "ground-station-submit",
                type: "submit",
                class: "btn btn-primary",
                disabled: disabled.value,
              },
              "Save Ground Station",
            ),
            h(
              "a",
              {
                ref: (element) => {
                  nativeLink = element
                },
                id: "ground-station-cancel",
                href: "/missions/mission-1/comms/ground-stations",
                "data-phx-link": "redirect",
                "data-phx-link-state": "push",
                class: "btn btn-ghost",
              },
              "Cancel",
            ),
          ],
        },
      )
  },
})

const parentForm = dom.window.document.querySelector("#parent-form")
const host = dom.window.document.querySelector("#actions-contract")
const submissions = []
parentForm.addEventListener("submit", (event) => {
  event.preventDefault()
  submissions.push(event.submitter)
})

const app = createApp(Contract)
app.mount(host)

const wrapper = host.firstElementChild
const button = wrapper.children[0]
const link = wrapper.children[1]
assert.equal(host.children.length, 1, "the SFC adds only its required action-row div")
assert.deepEqual([...wrapper.childNodes].map((node) => node.nodeName), ["BUTTON", "A"])
assert.strictEqual(button, nativeButton, "the slotted native button keeps its DOM identity")
assert.strictEqual(link, nativeLink, "the slotted redirect anchor keeps its DOM identity")
assert.strictEqual(button.form, parentForm, "the slotted submit button retains its parent form")
assert.deepEqual(elementAttributes(wrapper), {
  class: "flex items-center gap-3 border-t border-base-300/60 pt-5",
})
assert.deepEqual(elementAttributes(button), {
  class: "btn btn-primary",
  disabled: "",
  id: "ground-station-submit",
  type: "submit",
})
assert.deepEqual(elementAttributes(link), {
  class: "btn btn-ghost",
  "data-phx-link": "redirect",
  "data-phx-link-state": "push",
  href: "/missions/mission-1/comms/ground-stations",
  id: "ground-station-cancel",
})
assert.equal(button.textContent, "Save Ground Station")
assert.equal(link.textContent, "Cancel")

button.click()
assert.deepEqual(submissions, [], "native disabled behavior still suppresses parent-form submit")

disabled.value = false
await nextTick()
assert.strictEqual(wrapper.children[0], nativeButton, "disabled updates preserve button identity")
assert.equal(button.hasAttribute("disabled"), false)
button.click()
assert.deepEqual(
  submissions,
  [nativeButton],
  "the enabled slotted native button submits its unchanged parent form",
)

app.unmount()
assert.equal(host.children.length, 0)
dom.window.close()

console.log("cadence_form_actions_form_chrome_test passed")
