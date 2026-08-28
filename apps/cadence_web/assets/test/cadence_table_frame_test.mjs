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
  `CadenceTableFrame contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/ui/components/CadenceTableFrame.vue")
const source = await readFile(componentPath, "utf8")
const dom = installDom(
  '<div id="table-contract"></div><div id="native-contract"></div><div id="default-contract"></div>',
)
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const parsed = parse(source, {filename: componentPath})

assert.deepEqual(parsed.errors, [], "CadenceTableFrame.vue parses with the pinned compiler")
assert.ok(parsed.descriptor.script, "the frame keeps a typed render-function block")
assert.equal(parsed.descriptor.script.lang, "ts")
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null, "the frame avoids template slot anchors")

const compiled = compileScript(parsed.descriptor, {id: "cadence-table-frame-contract"})
const transformed = transformSync(compiled.content, {
  format: "cjs",
  loader: "ts",
  platform: "node",
  target: "node24",
})
const loadedModule = {exports: {}}
const evaluate = new Function("require", "module", "exports", transformed.code)
evaluate(integrationRequire, loadedModule, loadedModule.exports)
const CadenceTableFrame = loadedModule.exports.default
const {Fragment, createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")

assert.equal(CadenceTableFrame.inheritAttrs, false)
assert.doesNotMatch(
  source,
  /<template|<thead|<tbody|<tr|<th|<td|<input|<button|<a\b|defineEmits|\b(?:computed|reactive|ref|watch)\s*\(/,
  "the frame owns no template wrapper, table content, controls, links, events, or state",
)
assert.match(source, /h\(\s*"table"/, "the frame renders one native table root")

let callerHead = null
let callerBody = null
let callerHeaderRow = null
let callerDataRow = null
let callerNameCell = null
let callerActionsCell = null
let callerFilter = null
let callerAction = null
let callerLink = null
let filterModel = null
let actionClicks = 0
let bubbledClicks = 0

const callerTableChildren = () => [
  h(Fragment, null, [
    [
      h(
        "thead",
        {
          ref: (element) => {
            callerHead = element
          },
          id: "missions-table-head",
        },
        [
          h(
            "tr",
            {
              ref: (element) => {
                callerHeaderRow = element
              },
              id: "missions-header-row",
            },
            [
              h("th", {id: "missions-name-heading", scope: "col"}, "Mission"),
              h("th", {id: "missions-actions-heading", scope: "col"}, "Actions"),
            ],
          ),
        ],
      ),
    ],
    h(Fragment, null, [
      [
        h(
          "tbody",
          {
            ref: (element) => {
              callerBody = element
            },
            id: "missions-table-body",
          },
          [
            h(
              "tr",
              {
                ref: (element) => {
                  callerDataRow = element
                },
                id: "mission-row-7",
              },
              [
                h(
                  "td",
                  {
                    ref: (element) => {
                      callerNameCell = element
                    },
                    id: "mission-name-7",
                  },
                  [
                    h("input", {
                      ref: (element) => {
                        callerFilter = element
                      },
                      id: "mission-filter-7",
                      name: "mission[filter]",
                      type: "text",
                      value: filterModel.value,
                      onInput: (event) => {
                        filterModel.value = event.currentTarget.value
                      },
                    }),
                  ],
                ),
                h(
                  "td",
                  {
                    ref: (element) => {
                      callerActionsCell = element
                    },
                    id: "mission-actions-7",
                  },
                  [
                    h(
                      "button",
                      {
                        ref: (element) => {
                          callerAction = element
                        },
                        id: "mission-select-7",
                        type: "button",
                        onClick: () => {
                          actionClicks += 1
                        },
                      },
                      "Select & verify",
                    ),
                    h(
                      "a",
                      {
                        ref: (element) => {
                          callerLink = element
                        },
                        id: "mission-link-7",
                        href: "/missions/7?from=table&mode=ops",
                        "data-phx-link": "redirect",
                        "data-phx-link-state": "push",
                      },
                      "Open <mission>",
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    ]),
  ]),
]

const TableContract = defineComponent({
  name: "CadenceTableFrameContract",
  setup() {
    filterModel = ref("alpha")

    return () =>
      h(
        CadenceTableFrame,
        {
          id: "missions-table",
          class: ["caller-grid", {"table-striped": true}],
          "aria-label": "Missions <table> & controls",
          "data-table-owner": "caller",
          onClick: () => {
            bubbledClicks += 1
          },
        },
        {default: callerTableChildren},
      )
  },
})

const nativeTableChildren = () => [
  h("thead", {id: "missions-table-head"}, [
    h("tr", {id: "missions-header-row"}, [
      h("th", {id: "missions-name-heading", scope: "col"}, "Mission"),
      h("th", {id: "missions-actions-heading", scope: "col"}, "Actions"),
    ]),
  ]),
  h("tbody", {id: "missions-table-body"}, [
    h("tr", {id: "mission-row-7"}, [
      h("td", {id: "mission-name-7"}, [
        h("input", {
          id: "mission-filter-7",
          name: "mission[filter]",
          type: "text",
          value: "alpha",
        }),
      ]),
      h("td", {id: "mission-actions-7"}, [
        h("button", {id: "mission-select-7", type: "button"}, "Select & verify"),
        h(
          "a",
          {
            id: "mission-link-7",
            href: "/missions/7?from=table&mode=ops",
            "data-phx-link": "redirect",
            "data-phx-link-state": "push",
          },
          "Open <mission>",
        ),
      ]),
    ]),
  ]),
]

const NativeTableContract = defineComponent({
  name: "NativeTableContract",
  setup() {
    return () =>
      h(
        "table",
        {
          id: "missions-table",
          class: "table caller-grid table-striped",
          "aria-label": "Missions <table> & controls",
          "data-table-owner": "caller",
        },
        nativeTableChildren(),
      )
  },
})

const tableHost = dom.window.document.querySelector("#table-contract")
const nativeHost = dom.window.document.querySelector("#native-contract")
const tableApp = createApp(TableContract)
const nativeApp = createApp(NativeTableContract)
tableApp.mount(tableHost)
nativeApp.mount(nativeHost)

const table = tableHost.firstElementChild
const nativeTable = nativeHost.firstElementChild
assert.equal(tableHost.children.length, 1, "the frame adds no wrapper")
assert.equal(table.tagName, "TABLE")
assert.deepEqual(elementAttributes(table), {
  "aria-label": "Missions <table> & controls",
  class: "table caller-grid table-striped",
  "data-table-owner": "caller",
  id: "missions-table",
})
assert.deepEqual([...table.childNodes].map((node) => node.nodeName), ["THEAD", "TBODY"])
assert.deepEqual([...callerHead.childNodes].map((node) => node.nodeName), ["TR"])
assert.deepEqual([...callerHeaderRow.childNodes].map((node) => node.nodeName), ["TH", "TH"])
assert.deepEqual([...callerBody.childNodes].map((node) => node.nodeName), ["TR"])
assert.deepEqual([...callerDataRow.childNodes].map((node) => node.nodeName), ["TD", "TD"])
assert.strictEqual(table.children[0], callerHead)
assert.strictEqual(table.children[1], callerBody)
assert.strictEqual(callerHead.children[0], callerHeaderRow)
assert.strictEqual(callerBody.children[0], callerDataRow)
assert.strictEqual(callerDataRow.children[0], callerNameCell)
assert.strictEqual(callerDataRow.children[1], callerActionsCell)
assert.strictEqual(callerNameCell.children[0], callerFilter)
assert.strictEqual(callerActionsCell.children[0], callerAction)
assert.strictEqual(callerActionsCell.children[1], callerLink)
assert.deepEqual(elementAttributes(callerLink), {
  "data-phx-link": "redirect",
  "data-phx-link-state": "push",
  href: "/missions/7?from=table&mode=ops",
  id: "mission-link-7",
})
assert.equal(
  table.outerHTML,
  nativeTable.outerHTML,
  "the frame is byte-identical to an equivalent native table",
)

callerAction.click()
assert.equal(actionClicks, 1, "the caller-owned native button keeps its event handler")
assert.equal(bubbledClicks, 1, "the forwarded table listener keeps native bubbling behavior")

callerFilter.value = "beta"
callerFilter.dispatchEvent(new dom.window.Event("input", {bubbles: true}))
await nextTick()
assert.equal(filterModel.value, "beta", "the caller-owned input updates its Vue model")
filterModel.value = "gamma"
await nextTick()
assert.equal(callerFilter.value, "gamma", "the Vue model updates the same native input")

const DefaultClassContract = defineComponent({
  name: "CadenceTableFrameDefaultClassContract",
  setup() {
    return () =>
      h(CadenceTableFrame, {id: "default-table"}, {default: () => [h("tbody")]})
  },
})
const defaultHost = dom.window.document.querySelector("#default-contract")
const defaultApp = createApp(DefaultClassContract)
defaultApp.mount(defaultHost)
assert.equal(defaultHost.firstElementChild.outerHTML, '<table id="default-table" class="table"><tbody></tbody></table>')

tableApp.unmount()
nativeApp.unmount()
defaultApp.unmount()
assert.equal(tableHost.children.length, 0)
assert.equal(nativeHost.children.length, 0)
assert.equal(defaultHost.children.length, 0)
dom.window.close()

console.log("cadence_table_frame_test passed (compiled SFC + exact native table contract)")
