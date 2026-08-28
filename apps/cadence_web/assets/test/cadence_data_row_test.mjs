import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  elementAttributes,
  flushVue,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"

const scenarios = Object.freeze([
  "CadenceDataRow renders exactly one caller-classed div and one caller-classed label span",
  "the label and caller-owned default slot preserve escaping and child order without wrappers",
  "CatalogArtifactShow migrates exactly four byte-equivalent hud data rows",
  "the nested SHA-256 value span remains caller-owned with exact classes and text",
  "the caller-owned run link remains the same Phoenix redirect anchor with exact attributes",
])

assert.equal(process.versions.node, "24.16.0", "data-row contracts use pinned Node 24.16.0")
assert.equal(scenarios.length, 5)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPaths = {
  card: resolve(testDirectory, "../vue/ui/components/CadenceCard.vue"),
  dataRow: resolve(testDirectory, "../vue/ui/components/CadenceDataRow.vue"),
  tableFrame: resolve(testDirectory, "../vue/ui/components/CadenceTableFrame.vue"),
  artifactShow: resolve(testDirectory, "../vue/CatalogArtifactShow.vue"),
}
const dom = installDom('<div id="app"></div>')
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")

const loadSfc = async (componentPath, localModules = {}) => {
  const source = await readFile(componentPath, "utf8")
  const parsed = parse(source, {filename: componentPath})

  assert.deepEqual(parsed.errors, [], `${componentPath} parses with the pinned Vue compiler`)

  const script = parsed.descriptor.scriptSetup
    ? compileScript(parsed.descriptor, {
        id: `cadence-data-row-${componentPath.split("/").at(-1)}`,
        inlineTemplate: true,
      }).content
    : parsed.descriptor.script?.content

  assert.ok(script, `${componentPath} keeps an auditable compiled script`)

  const transformed = transformSync(script, {
    format: "cjs",
    loader: "ts",
    platform: "node",
    target: "node24",
  })
  const loadedModule = {exports: {}}
  const localRequire = (specifier) => localModules[specifier] ?? integrationRequire(specifier)

  new Function("require", "module", "exports", transformed.code)(
    localRequire,
    loadedModule,
    loadedModule.exports,
  )

  return {
    component: loadedModule.exports.default,
    descriptor: parsed.descriptor,
    module: loadedModule.exports,
    source,
  }
}

const cardSfc = await loadSfc(componentPaths.card)
const dataRowSfc = await loadSfc(componentPaths.dataRow)
const tableFrameSfc = await loadSfc(componentPaths.tableFrame)
const CadenceDataRow = dataRowSfc.component

assert.ok(dataRowSfc.descriptor.script, "CadenceDataRow keeps a native render-function script")
assert.equal(dataRowSfc.descriptor.scriptSetup, null)
assert.equal(dataRowSfc.descriptor.template, null)
assert.deepEqual(Object.keys(CadenceDataRow.props).sort(), [
  "label",
  "labelClass",
  "rowClass",
  "rowId",
])
assert.equal(CadenceDataRow.inheritAttrs, false)

for (const propName of ["label", "labelClass", "rowClass"]) {
  const prop = CadenceDataRow.props[propName]

  assert.equal(prop.required, true)
  assert.equal(prop.type, String)
}
assert.equal(CadenceDataRow.props.rowId.required, undefined)
assert.equal(CadenceDataRow.props.rowId.default, undefined)
assert.equal(CadenceDataRow.props.rowId.type, String)

assert.doesNotMatch(dataRowSfc.source, /<template>|ref\(|reactive\(|computed\(|watch\(|emit/)
assert.equal(dataRowSfc.source.match(/h\("div"/g)?.length, 1)
assert.equal(dataRowSfc.source.match(/h\("span"/g)?.length, 1)

const {Fragment, createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")
const rowId = ref("cadence-data-row-present")
const PrimitiveOracle = defineComponent({
  name: "CadenceDataRowPrimitiveOracle",
  setup() {
    return () =>
      h(
        CadenceDataRow,
        {
          rowId: rowId.value,
          rowClass: "row-first row-second",
          labelClass: "label-first label-second",
          label: "<Label & safe>",
        },
        {
          default: () => [
            h("span", {class: "caller-value"}, "<Caller & safe>"),
            h(
              "a",
              {
                href: "/runs/one?left=1&right=2",
                "data-phx-link": "redirect",
                "data-phx-link-state": "push",
              },
              "View <run>",
            ),
          ],
        },
      )
  },
})

const primitiveApp = createApp(PrimitiveOracle)
primitiveApp.mount(dom.window.document.querySelector("#app"))
await flushVue(nextTick)

const primitiveRow = dom.window.document.querySelector("#app > div")
const primitiveOuterHtml = (idAttribute = "") =>
  `<div${idAttribute} class="row-first row-second"><span class="label-first label-second">&lt;Label &amp; safe&gt;</span><span class="caller-value">&lt;Caller &amp; safe&gt;</span><a href="/runs/one?left=1&amp;right=2" data-phx-link="redirect" data-phx-link-state="push">View &lt;run&gt;</a></div>`

assert.equal(
  primitiveRow.outerHTML,
  primitiveOuterHtml(' id="cadence-data-row-present"'),
)
assert.equal(primitiveRow.id, "cadence-data-row-present")
assert.equal(primitiveRow.childNodes.length, 3)
assert.deepEqual(
  [...primitiveRow.children].map((element) => [element.tagName, element.className]),
  [
    ["SPAN", "label-first label-second"],
    ["SPAN", "caller-value"],
    ["A", ""],
  ],
)

rowId.value = "cadence-data-row-updated"
await flushVue(nextTick)

assert.equal(primitiveRow.id, "cadence-data-row-updated")
assert.equal(primitiveRow.outerHTML, primitiveOuterHtml(' id="cadence-data-row-updated"'))

rowId.value = undefined
await flushVue(nextTick)

assert.equal(primitiveRow.hasAttribute("id"), false)
assert.equal(primitiveRow.outerHTML, primitiveOuterHtml())
assert.doesNotThrow(() => primitiveApp.unmount())

const passthrough = (name) =>
  defineComponent({
    name,
    inheritAttrs: false,
    setup(_props, {slots}) {
      return () => slots.default?.()
    },
  })
const ModalMenuOracle = defineComponent({
  name: "ModalMenuOracle",
  inheritAttrs: false,
  setup(_props, {slots}) {
    return () =>
      h(Fragment, null, [slots.trigger?.({open: true}), slots.content?.({open: true})])
  },
})
const StatusBadgeOracle = defineComponent({
  name: "StatusBadgeOracle",
  props: {label: {type: String, required: true}},
  setup(props) {
    return () => h("span", {class: "status-badge-oracle"}, props.label)
  },
})
const componentModule = (component) => ({__esModule: true, default: component})
const artifactShowSfc = await loadSfc(componentPaths.artifactShow, {
  "./StatusBadge.vue": componentModule(StatusBadgeOracle),
  "./ui/components/CadenceCard.vue": cardSfc.module,
  "./ui/components/CadenceDataRow.vue": dataRowSfc.module,
  "./ui/components/CadenceTableFrame.vue": tableFrameSfc.module,
  "./ui/reka/CadenceMenuItem.vue": componentModule(passthrough("CadenceMenuItemOracle")),
  "./ui/reka/CadenceModalMenu.vue": componentModule(ModalMenuOracle),
})
const CatalogArtifactShow = artifactShowSfc.component
const artifact = {
  format_key: "<OPM & safe>",
  media_type: "application/<orbit>&json",
  content_sha256: "sha<&>256",
  uploaded_at: "2026-08-26 <12:00> & UTC",
  download_href: "/artifacts/one?download=1&original=true",
}
const run = {
  id: "catalog-artifact-run-one",
  actions_id: "catalog-artifact-run-one-actions",
  status: "ready",
  status_label: "Completed",
  started_at: "2026-08-26 12:00:00",
  completed_at: "2026-08-26 12:01:00",
  href: "/missions/mission-one/catalog/imports/run-one?from=artifact&mode=view",
}
const artifactApp = createApp(CatalogArtifactShow, {artifact, runs: [run]})
artifactApp.mount(dom.window.document.querySelector("#app"))
await flushVue(nextTick)

const rows = [...dom.window.document.querySelectorAll(".hud-data-row")]

assert.equal(rows.length, 4)
assert.deepEqual(
  rows.map((row) => row.outerHTML),
  [
    '<div class="hud-data-row"><span class="hud-data-label">Format</span><span class="hud-data-value font-mono text-sm">&lt;OPM &amp; safe&gt;</span></div>',
    '<div class="hud-data-row"><span class="hud-data-label">Media type</span><span class="hud-data-value font-mono text-sm">application/&lt;orbit&gt;&amp;json</span></div>',
    '<div class="hud-data-row"><span class="hud-data-label">Content SHA-256</span><span class="hud-data-value"><span class="break-all font-mono text-xs">sha&lt;&amp;&gt;256</span></span></div>',
    '<div class="hud-data-row"><span class="hud-data-label">Uploaded at</span><span class="hud-data-value">2026-08-26 &lt;12:00&gt; &amp; UTC</span></div>',
  ],
)

for (const row of rows) {
  assert.equal(row.childNodes.length, 2)
  assert.equal(row.children[0].tagName, "SPAN")
  assert.equal(row.children[0].className, "hud-data-label")
  assert.equal(row.children[1].tagName, "SPAN")
}

const shaValue = rows[2].children[1]

assert.equal(shaValue.className, "hud-data-value")
assert.equal(shaValue.children.length, 1)
assert.equal(shaValue.firstElementChild.tagName, "SPAN")
assert.equal(shaValue.firstElementChild.className, "break-all font-mono text-xs")
assert.equal(shaValue.firstElementChild.textContent, artifact.content_sha256)

const redirectAnchor = dom.window.document.querySelector(
  "#catalog-artifact-run-one-actions-menu a",
)

assert.equal(redirectAnchor.tagName, "A")
assert.equal(redirectAnchor.textContent, "View run")
assert.deepEqual(elementAttributes(redirectAnchor), {
  class: "block cursor-pointer rounded px-3 py-2 text-sm outline-none hover:bg-base-200",
  "data-phx-link": "redirect",
  "data-phx-link-state": "push",
  href: run.href,
})
assert.equal(dom.window.document.querySelectorAll(`[href="${run.href}"]`).length, 1)

assert.doesNotThrow(() => artifactApp.unmount())
console.log(`cadence_data_row_test passed (${scenarios.length} semantic scenarios)`)
