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
import {opsPageBodyFrameClass} from "./ops_page_body_frame_test_support.mjs"

const scenarios = Object.freeze([
  "the actual frame SFC owns exactly one native div and its canonical class",
  "all caller root attrs, classes, and listeners forward without a wrapper",
  "nested arrays and Fragments flatten to caller-owned native children",
  "caller-owned forms, controls, links, details, and events remain native",
  "keyed nested Fragments retain multiple unkeyed native child identities across reorder",
])

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
assert.equal(process.execPath, pinnedNode, "CadenceOpsPageBodyFrame uses the pinned Node executable")
assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `CadenceOpsPageBodyFrame uses pinned Node ${expectedNodeVersion}`,
)
assert.equal(scenarios.length, 5)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(
  testDirectory,
  "../vue/ui/components/CadenceOpsPageBodyFrame.vue",
)
const source = await readFile(componentPath, "utf8")
const dom = installDom('<div id="ops-page-body-frame-contract"></div>')

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

assert.deepEqual(parsed.errors, [], "CadenceOpsPageBodyFrame parses with the pinned compiler")
assert.ok(parsed.descriptor.script, "the frame keeps a typed render-function block")
assert.equal(parsed.descriptor.script.lang, "ts")
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null, "the frame avoids template slot anchors")
assert.equal(parsed.descriptor.styles.length, 0)

const compiled = compileScript(parsed.descriptor, {id: "cadence-ops-page-body-frame-contract"})
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

const CadenceOpsPageBodyFrame = loadedModule.exports.default
const {Fragment, createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")

assert.equal(CadenceOpsPageBodyFrame.inheritAttrs, false)
assert.equal(CadenceOpsPageBodyFrame.props, undefined)
assert.equal(CadenceOpsPageBodyFrame.emits, undefined)
assert.equal(source.match(/h\(\s*"div"/g)?.length, 1)
assert.equal(source.match(/<div\b/g)?.length ?? 0, 0)
assert.equal(source.match(/<slot\b/g)?.length ?? 0, 0)
assert.equal(source.split(opsPageBodyFrameClass).length - 1, 1)
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

const frameId = ref("ops-page-body-frame-initial")
const callerClass = ref("caller-first caller-second")
const phase = ref("ready")
const inputValue = ref("alpha")
const groups = ref([
  {key: "alpha", label: "Alpha"},
  {key: "bravo", label: "Bravo"},
])
const formElement = ref()
const inputElement = ref()
const linkElement = ref()
const detailsElement = ref()
let rootClicks = 0
let formSubmits = 0
let inputEvents = 0
let buttonClicks = 0

const Contract = defineComponent({
  name: "CadenceOpsPageBodyFrameMountedContract",
  setup() {
    return () =>
      h(
        CadenceOpsPageBodyFrame,
        {
          id: frameId.value,
          class: callerClass.value,
          "aria-label": "Caller operations page body",
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
                id: "caller-ops-page-body-form",
                "phx-change": "search",
                onSubmit: event => {
                  event.preventDefault()
                  formSubmits += 1
                },
              },
              [
                h("input", {
                  ref: inputElement,
                  id: "caller-ops-page-body-query",
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
                    id: "caller-ops-page-body-action",
                    type: "button",
                    onClick: () => {
                      buttonClicks += 1
                    },
                  },
                  "Run",
                ),
              ],
            ),
            h(
              Fragment,
              null,
              [
                [
                  h("a", {ref: linkElement, id: "caller-ops-page-body-link", href: "/ops/body"}, "Body link"),
                ],
                [
                  h(
                    "details",
                    {ref: detailsElement, id: "caller-ops-page-body-details"},
                    [h("summary", "Evidence"), h("p", "Details")],
                  ),
                ],
              ],
            ),
            groups.value.map(group =>
              h(Fragment, {key: group.key}, [
                [h("article", {id: `caller-ops-page-body-${group.key}`}, group.label)],
                [
                  h(
                    "span",
                    {id: `caller-ops-page-body-${group.key}-meta`},
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

const host = dom.window.document.querySelector("#ops-page-body-frame-contract")
const app = createApp(Contract)
app.mount(host)
await flushVue(nextTick)

const root = host.firstElementChild
const form = dom.window.document.querySelector("#caller-ops-page-body-form")
const input = dom.window.document.querySelector("#caller-ops-page-body-query")
const button = dom.window.document.querySelector("#caller-ops-page-body-action")
const link = dom.window.document.querySelector("#caller-ops-page-body-link")
const details = dom.window.document.querySelector("#caller-ops-page-body-details")
const alpha = dom.window.document.querySelector("#caller-ops-page-body-alpha")
const bravo = dom.window.document.querySelector("#caller-ops-page-body-bravo")
const alphaMeta = dom.window.document.querySelector("#caller-ops-page-body-alpha-meta")
const bravoMeta = dom.window.document.querySelector("#caller-ops-page-body-bravo-meta")

assert.equal(host.childNodes.length, 1, "the frame adds no sibling or wrapper node")
assert.equal(root.tagName, "DIV")
assert.equal(root.className, `${opsPageBodyFrameClass} ${callerClass.value}`)
assert.deepEqual(elementAttributes(root), {
  "aria-label": "Caller operations page body",
  class: `${opsPageBodyFrameClass} ${callerClass.value}`,
  "data-phase": "ready",
  id: "ops-page-body-frame-initial",
})
assert.deepEqual(
  [...root.children].map(child => child.id),
  [
    "caller-ops-page-body-form",
    "caller-ops-page-body-link",
    "caller-ops-page-body-details",
    "caller-ops-page-body-alpha",
    "caller-ops-page-body-alpha-meta",
    "caller-ops-page-body-bravo",
    "caller-ops-page-body-bravo-meta",
  ],
)
assert.strictEqual(root.firstElementChild, form)
assert.strictEqual(formElement.value, form)
assert.strictEqual(inputElement.value, input)
assert.strictEqual(linkElement.value, link)
assert.strictEqual(detailsElement.value, details)
assert.equal(input.value, "alpha")
assert.equal(form.getAttribute("phx-change"), "search")
assert.equal(input.getAttribute("name"), "q")
assert.equal(input.getAttribute("type"), "search")
assert.equal(button.getAttribute("type"), "button")
assert.equal(link.getAttribute("href"), "/ops/body")
assert.equal(details.querySelector("summary").textContent, "Evidence")

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

const originalNodes = {root, form, input, button, link, details, alpha, bravo, alphaMeta, bravoMeta}
frameId.value = "ops-page-body-frame-updated"
callerClass.value = "caller-updated caller-extra"
phase.value = "running"
inputValue.value = "gamma"
groups.value = [groups.value[1], {key: "charlie", label: "Charlie"}, groups.value[0]]
await flushVue(nextTick)

const updatedRoot = dom.window.document.querySelector("#ops-page-body-frame-updated")
assert.strictEqual(updatedRoot, originalNodes.root)
assert.equal(updatedRoot.className, `${opsPageBodyFrameClass} ${callerClass.value}`)
assert.deepEqual(elementAttributes(updatedRoot), {
  "aria-label": "Caller operations page body",
  class: `${opsPageBodyFrameClass} ${callerClass.value}`,
  "data-phase": "running",
  id: "ops-page-body-frame-updated",
})
assert.deepEqual(
  [...updatedRoot.children].map(child => child.id),
  [
    "caller-ops-page-body-form",
    "caller-ops-page-body-link",
    "caller-ops-page-body-details",
    "caller-ops-page-body-bravo",
    "caller-ops-page-body-bravo-meta",
    "caller-ops-page-body-charlie",
    "caller-ops-page-body-charlie-meta",
    "caller-ops-page-body-alpha",
    "caller-ops-page-body-alpha-meta",
  ],
)
assert.strictEqual(updatedRoot.firstElementChild, originalNodes.form)
assert.strictEqual(formElement.value, originalNodes.form)
assert.strictEqual(inputElement.value, originalNodes.input)
assert.strictEqual(linkElement.value, originalNodes.link)
assert.strictEqual(detailsElement.value, originalNodes.details)
assert.strictEqual(dom.window.document.querySelector("#caller-ops-page-body-alpha"), originalNodes.alpha)
assert.strictEqual(dom.window.document.querySelector("#caller-ops-page-body-bravo"), originalNodes.bravo)
assert.strictEqual(
  dom.window.document.querySelector("#caller-ops-page-body-alpha-meta"),
  originalNodes.alphaMeta,
)
assert.strictEqual(
  dom.window.document.querySelector("#caller-ops-page-body-bravo-meta"),
  originalNodes.bravoMeta,
)
assert.equal(input.value, "gamma")

assert.doesNotThrow(() => app.unmount())
dom.window.close()

console.log(`cadence_ops_page_body_frame_test passed (${scenarios.length} exact-DOM scenarios)`)
