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

const scenarios = Object.freeze([
  "the actual SFC renders one native details root with no wrapper",
  "caller slot fragments flatten into exact native child order and identity",
  "caller root and child attributes remain on their native elements",
  "the caller owns open state and reactive root attributes",
  "caller content events and the forwarded native toggle listener retain their payloads",
])

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `CadenceDetailsFrame contracts use pinned Node ${expectedNodeVersion}`,
)
assert.equal(scenarios.length, 5)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/ui/components/CadenceDetailsFrame.vue")
const source = await readFile(componentPath, "utf8")
const dom = installDom('<div id="details-contract"></div>')
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const parsed = parse(source, {filename: componentPath})

assert.deepEqual(parsed.errors, [], "CadenceDetailsFrame parses with the pinned Vue compiler")
assert.ok(parsed.descriptor.script, "the frame keeps a TypeScript render-function script")
assert.equal(parsed.descriptor.script.lang, "ts")
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null, "the frame avoids template slot anchors")
assert.equal(parsed.descriptor.styles.length, 0, "the frame owns no disclosure styling")

const compiled = compileScript(parsed.descriptor, {id: "cadence-details-frame-contract"}).content
const transformed = transformSync(compiled, {
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

const CadenceDetailsFrame = loadedModule.exports.default

assert.equal(CadenceDetailsFrame.inheritAttrs, false)
assert.equal(source.match(/h\("details"/g)?.length, 1)
assert.match(source, /child\.type === Fragment/)
assert.doesNotMatch(
  source,
  /<template|<style|<summary|h\("summary"|defineEmits|emit\(|\b(?:computed|reactive|ref|watch)\s*\(/,
  "the frame owns no wrapper, summary, styling, events, or state",
)

const {Fragment, Text, createApp, defineComponent, h, nextTick, ref} =
  integrationRequire("vue")
const disclosureId = ref("caller-disclosure-initial")
const disclosureOpen = ref(true)
let callerSummary = null
let callerContent = null
let callerAction = null
let actionPayload = null
const toggleCalls = []

const DetailsContract = defineComponent({
  name: "CadenceDetailsFrameContract",
  setup() {
    return () =>
      h(
        CadenceDetailsFrame,
        {
          id: disclosureId.value,
          class: "caller-disclosure caller-spacing",
          open: disclosureOpen.value,
          "aria-labelledby": "caller-summary",
          "data-disclosure-owner": "caller",
          onToggle: (event) => {
            toggleCalls.push({
              currentTarget: event.currentTarget,
              event,
              target: event.target,
            })
          },
        },
        {
          default: () => [
            h(Fragment, null, [
              [
                h(
                  "summary",
                  {
                    ref: (element) => {
                      callerSummary = element
                    },
                    id: "caller-summary",
                    class: "caller-summary-class",
                    "data-summary-owner": "caller",
                  },
                  "Caller <summary>",
                ),
              ],
              h(Text, null, "caller-owned text"),
              h(Fragment, null, [
                h(
                  "div",
                  {
                    ref: (element) => {
                      callerContent = element
                    },
                    id: "caller-details-content",
                    class: "caller-content-class",
                    "data-content-owner": "caller",
                  },
                  [
                    h(
                      "button",
                      {
                        ref: (element) => {
                          callerAction = element
                        },
                        id: "caller-details-action",
                        class: "caller-action-class",
                        type: "button",
                        name: "intent",
                        value: "inspect-disclosure",
                        onClick: (event) => {
                          actionPayload = {
                            target: event.currentTarget,
                            value: event.currentTarget.value,
                          }
                        },
                      },
                      "Inspect disclosure",
                    ),
                  ],
                ),
              ]),
            ]),
          ],
        },
      )
  },
})

const host = dom.window.document.querySelector("#details-contract")
const app = createApp(DetailsContract)
app.mount(host)
await flushVue(nextTick)

const details = host.firstElementChild
const initialDetails = dom.window.document.querySelector("#caller-disclosure-initial")

assert.equal(host.childNodes.length, 1, "the frame adds no wrapper or sibling anchors")
assert.strictEqual(initialDetails, details)
assert.equal(details.tagName, "DETAILS")
assert.equal(
  details.outerHTML,
  '<details id="caller-disclosure-initial" class="caller-disclosure caller-spacing" open="" aria-labelledby="caller-summary" data-disclosure-owner="caller"><summary id="caller-summary" class="caller-summary-class" data-summary-owner="caller">Caller &lt;summary&gt;</summary>caller-owned text<div id="caller-details-content" class="caller-content-class" data-content-owner="caller"><button id="caller-details-action" class="caller-action-class" type="button" name="intent" value="inspect-disclosure">Inspect disclosure</button></div></details>',
)
assert.deepEqual(elementAttributes(details), {
  "aria-labelledby": "caller-summary",
  class: "caller-disclosure caller-spacing",
  "data-disclosure-owner": "caller",
  id: "caller-disclosure-initial",
  open: "",
})
assert.equal(details.open, true)
assert.deepEqual(
  [...details.childNodes].map((node) => [node.nodeType, node.nodeName]),
  [
    [dom.window.Node.ELEMENT_NODE, "SUMMARY"],
    [dom.window.Node.TEXT_NODE, "#text"],
    [dom.window.Node.ELEMENT_NODE, "DIV"],
  ],
)
assert.strictEqual(details.children[0], callerSummary)
assert.strictEqual(details.children[1], callerContent)
assert.strictEqual(callerContent.children[0], callerAction)
assert.deepEqual(elementAttributes(callerSummary), {
  class: "caller-summary-class",
  "data-summary-owner": "caller",
  id: "caller-summary",
})
assert.deepEqual(elementAttributes(callerContent), {
  class: "caller-content-class",
  "data-content-owner": "caller",
  id: "caller-details-content",
})
assert.deepEqual(elementAttributes(callerAction), {
  class: "caller-action-class",
  id: "caller-details-action",
  name: "intent",
  type: "button",
  value: "inspect-disclosure",
})

callerAction.click()
assert.deepEqual(actionPayload, {
  target: callerAction,
  value: "inspect-disclosure",
})

const toggleEvent = new dom.window.Event("toggle")
const toggleCountBeforeDispatch = toggleCalls.length
assert.equal(details.dispatchEvent(toggleEvent), true)
assert.equal(toggleCalls.length, toggleCountBeforeDispatch + 1)
assert.deepEqual(toggleCalls.at(-1), {
  currentTarget: details,
  event: toggleEvent,
  target: details,
})

disclosureId.value = "caller-disclosure-updated"
disclosureOpen.value = false
await flushVue(nextTick)

const updatedDetails = dom.window.document.querySelector("#caller-disclosure-updated")

assert.strictEqual(updatedDetails, details, "caller attr updates preserve the native details root")
assert.strictEqual(updatedDetails.children[0], callerSummary)
assert.strictEqual(updatedDetails.children[1], callerContent)
assert.strictEqual(callerContent.children[0], callerAction)
assert.equal(updatedDetails.open, false)
assert.equal(updatedDetails.hasAttribute("open"), false)
assert.deepEqual(elementAttributes(updatedDetails), {
  "aria-labelledby": "caller-summary",
  class: "caller-disclosure caller-spacing",
  "data-disclosure-owner": "caller",
  id: "caller-disclosure-updated",
})

assert.doesNotThrow(() => app.unmount())
console.log(`cadence_details_frame_test passed (${scenarios.length} semantic scenarios)`)
