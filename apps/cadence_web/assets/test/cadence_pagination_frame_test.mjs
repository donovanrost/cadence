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
import {paginationFrameClass} from "./pagination_frame_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `CadencePaginationFrame contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/ui/components/CadencePaginationFrame.vue")
const source = await readFile(componentPath, "utf8")
const dom = installDom('<div id="pagination-contract"></div>')
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const parsed = parse(source, {filename: componentPath})

assert.deepEqual(parsed.errors, [], "CadencePaginationFrame.vue parses with the pinned compiler")
assert.ok(parsed.descriptor.script, "the frame keeps a typed render-function block")
assert.equal(parsed.descriptor.script.lang, "ts")
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null, "the frame avoids template slot anchors")

const compiled = compileScript(parsed.descriptor, {id: "cadence-pagination-frame-contract"})
const transformed = transformSync(compiled.content, {
  format: "cjs",
  loader: "ts",
  platform: "node",
  target: "node24",
})
const loadedModule = {exports: {}}
const evaluate = new Function("require", "module", "exports", transformed.code)
evaluate(integrationRequire, loadedModule, loadedModule.exports)
const CadencePaginationFrame = loadedModule.exports.default
const {Fragment, createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")

assert.equal(CadencePaginationFrame.inheritAttrs, false)
assert.equal(source.match(/h\(\s*"div"/g)?.length, 1, "the frame owns one native div")
assert.match(source, new RegExp(JSON.stringify(paginationFrameClass).slice(1, -1)))
assert.doesNotMatch(
  source,
  /<template|<span|<button|defineProps|defineEmits|\b(?:computed|reactive|ref|watch)\s*\(|\b(?:id|role|aria-[\w-]+)\s*:/,
  "the frame owns no template wrapper, values, controls, state, events, IDs, or semantics",
)

let page = null
let rangeSpan = null
let actionCluster = null
let previousButton = null
let nextButton = null
let previousClicks = 0
let nextClicks = 0

const callerChildren = () => [
  h(Fragment, null, [
    [
      h(
        "span",
        {
          ref: (element) => {
            rangeSpan = element
          },
          id: "pagination-range",
          class: "font-mono text-xs text-base-content/70",
        },
        `${(page.value - 1) * 25 + 1}–${page.value * 25} of 50`,
      ),
    ],
    h(Fragment, null, [
      [
        h(
          "div",
          {
            ref: (element) => {
              actionCluster = element
            },
            id: "pagination-actions",
            class: "flex items-center gap-1",
          },
          [
            h(
              "button",
              {
                ref: (element) => {
                  previousButton = element
                },
                id: "pagination-previous",
                type: "button",
                class: "btn btn-ghost btn-xs",
                "phx-click": "paginate",
                "phx-value-page": page.value - 1,
                disabled: page.value <= 1,
                onClick: () => {
                  previousClicks += 1
                  page.value -= 1
                },
              },
              "Prev",
            ),
            h(
              "button",
              {
                ref: (element) => {
                  nextButton = element
                },
                id: "pagination-next",
                type: "button",
                class: "btn btn-ghost btn-xs",
                "phx-click": "paginate",
                "phx-value-page": page.value + 1,
                disabled: page.value >= 2,
                onClick: () => {
                  nextClicks += 1
                  page.value += 1
                },
              },
              "Next",
            ),
          ],
        ),
      ],
    ]),
  ]),
]

const PaginationContract = defineComponent({
  name: "CadencePaginationFrameContract",
  setup() {
    page = ref(1)

    return () =>
      h(
        CadencePaginationFrame,
        {
          id: "spacecraft-roster-pagination",
          class: "caller-pagination-class",
          title: "Caller pagination",
          "data-pagination-owner": "caller",
        },
        {default: callerChildren},
      )
  },
})

const host = dom.window.document.querySelector("#pagination-contract")
const app = createApp(PaginationContract)
app.mount(host)
await nextTick()

const root = host.firstElementChild

assert.equal(host.childElementCount, 1, "the component adds no sibling or wrapper element")
assert.equal(root.tagName, "DIV")
assert.equal(root.id, "spacecraft-roster-pagination")
assert.deepEqual(elementAttributes(root), {
  class: `${paginationFrameClass} caller-pagination-class`,
  "data-pagination-owner": "caller",
  id: "spacecraft-roster-pagination",
  title: "Caller pagination",
})
assert.deepEqual(
  [...root.children].map((element) => element.id),
  ["pagination-range", "pagination-actions"],
  "nested arrays and Fragments flatten into exact caller order",
)
assert.equal(root.children[0], rangeSpan)
assert.equal(root.children[1], actionCluster)
assert.deepEqual(
  [...actionCluster.children].map((element) => element.id),
  ["pagination-previous", "pagination-next"],
)
assert.equal(actionCluster.children[0], previousButton)
assert.equal(actionCluster.children[1], nextButton)
assert.ok(previousButton instanceof dom.window.HTMLButtonElement)
assert.ok(nextButton instanceof dom.window.HTMLButtonElement)
assert.equal(previousButton.type, "button")
assert.equal(nextButton.type, "button")
assert.equal(previousButton.getAttribute("phx-click"), "paginate")
assert.equal(nextButton.getAttribute("phx-click"), "paginate")
assert.equal(previousButton.disabled, true)
assert.equal(nextButton.disabled, false)

const originalNodes = {rangeSpan, actionCluster, previousButton, nextButton}

previousButton.click()
await nextTick()
assert.equal(previousClicks, 0, "a disabled native button does not dispatch its click handler")

nextButton.click()
await nextTick()

assert.equal(nextClicks, 1)
assert.equal(page.value, 2)
assert.equal(rangeSpan, originalNodes.rangeSpan)
assert.equal(actionCluster, originalNodes.actionCluster)
assert.equal(previousButton, originalNodes.previousButton)
assert.equal(nextButton, originalNodes.nextButton)
assert.equal(rangeSpan.textContent, "26–50 of 50")
assert.equal(previousButton.disabled, false)
assert.equal(nextButton.disabled, true)
assert.equal(previousButton.getAttribute("phx-value-page"), "1")
assert.equal(nextButton.getAttribute("phx-value-page"), "3")

nextButton.click()
await nextTick()
assert.equal(nextClicks, 1, "the newly disabled native button retains disabled behavior")

previousButton.click()
await nextTick()
assert.equal(previousClicks, 1)
assert.equal(page.value, 1)
assert.equal(previousButton, originalNodes.previousButton)
assert.equal(nextButton, originalNodes.nextButton)
assert.equal(previousButton.disabled, true)
assert.equal(nextButton.disabled, false)

app.unmount()
dom.window.close()

console.log(
  "cadence_pagination_frame_test passed (compiled SFC + exact native pagination contract)",
)
