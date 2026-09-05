import assert from "node:assert/strict"
import {readFile, readdir} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  elementAttributes,
  expectedNodeVersion,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"
import {peelCompactTableFrames} from "./compact_table_frame_test_support.mjs"
import {
  excludedHoverTableRowFiles,
  hoverTableRowCallerNames,
  hoverTableRowClass,
  hoverTableRowMigrations,
  peelCadenceHoverTableRows,
  reorderedHoverTableRowClass,
  sha256,
} from "./hover_table_row_test_support.mjs"
import {pageTitleCallerNames, peelCadencePageTitle} from "./page_title_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `hover-table-row contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueDirectory = resolve(testDirectory, "../vue")
const primitivePath = resolve(vueDirectory, "ui/components/CadenceHoverTableRow.vue")
const primitiveSource = await readFile(primitivePath, "utf8")
const dom = installDom(
  '<div id="primitive-contract"></div><div id="admin-contract"></div>',
)
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const parsedPrimitive = parse(primitiveSource, {filename: primitivePath})

assert.deepEqual(parsedPrimitive.errors, [], "CadenceHoverTableRow parses with the pinned compiler")
assert.ok(parsedPrimitive.descriptor.script, "the primitive uses a normal typed script")
assert.equal(parsedPrimitive.descriptor.script.lang, "ts")
assert.equal(parsedPrimitive.descriptor.scriptSetup, null)
assert.equal(parsedPrimitive.descriptor.template, null, "the primitive avoids template slot anchors")

const compiledPrimitive = compileScript(parsedPrimitive.descriptor, {
  id: "cadence-hover-table-row-contract",
})
const transformedPrimitive = transformSync(compiledPrimitive.content, {
  format: "cjs",
  loader: "ts",
  platform: "node",
  target: "node24",
})
const primitiveModule = {exports: {}}
const evaluatePrimitive = new Function(
  "require",
  "module",
  "exports",
  transformedPrimitive.code,
)
evaluatePrimitive(integrationRequire, primitiveModule, primitiveModule.exports)
const CadenceHoverTableRow = primitiveModule.exports.default
const {Fragment, createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")

assert.equal(CadenceHoverTableRow.inheritAttrs, false)
assert.deepEqual(Object.keys(CadenceHoverTableRow.props ?? {}), [])
assert.deepEqual(Object.keys(CadenceHoverTableRow.emits ?? {}), [])
assert.match(primitiveSource, /h\(\s*"tr"/)
assert.equal(primitiveSource.split(hoverTableRowClass).length - 1, 1)
assert.doesNotMatch(
  primitiveSource,
  /<template|<td|<th|<a\b|<button|<form|defineProps|defineEmits|\b(?:computed|reactive|ref|watch|onMounted)\s*\(/,
  "the primitive owns no wrapper, descendants, actions, forms, events, or state",
)
assert.doesNotMatch(primitiveSource, /\b(?:role|aria-|data-|tabindex)\b/)

const occurrences = (source, fragment) => source.split(fragment).length - 1
const callerOwnership = Object.freeze({
  "AdminOrganizationList.vue": Object.freeze([
    Object.freeze({tds: 2, anchors: 1, buttons: 0, required: ['data-phx-link="redirect"']}),
  ]),
  "AdminOrganizationShow.vue": Object.freeze([
    Object.freeze({tds: 4, anchors: 0, buttons: 0, required: [":data-service-identity-state"]}),
  ]),
  "CommsProviderTable.vue": Object.freeze([
    Object.freeze({tds: 7, anchors: 1, buttons: 0, required: ["<StatusBadge"]}),
  ]),
  "CommsRoutingList.vue": Object.freeze([
    Object.freeze({tds: 6, anchors: 1, buttons: 0, required: ['data-phx-link="redirect"']}),
  ]),
  "CommsTransportList.vue": Object.freeze([
    Object.freeze({tds: 6, anchors: 1, buttons: 0, required: [":id=\"row.readiness_id\""]}),
  ]),
  "SpacecraftList.vue": Object.freeze([
    Object.freeze({
      tds: 5,
      anchors: 3,
      buttons: 1,
      required: ["<CadenceModalMenu", ":aria-controls", 'data-phx-link="redirect"'],
    }),
    Object.freeze({
      tds: 5,
      anchors: 2,
      buttons: 0,
      required: ['v-for="(entry, index) in row.fleet_entries"', 'data-phx-link="patch"'],
    }),
  ]),
  "SpacecraftTypeList.vue": Object.freeze([
    Object.freeze({tds: 5, anchors: 1, buttons: 0, required: ['data-phx-link="redirect"']}),
  ]),
})

assert.equal(hoverTableRowMigrations.length, 7, "the frozen ledger has exactly seven callers")
assert.equal(new Set(hoverTableRowCallerNames).size, 7)
assert.equal(
  hoverTableRowMigrations.reduce((total, migration) => total + migration.openings.length, 0),
  8,
  "the frozen ledger has exactly eight row boundaries",
)

for (const migration of hoverTableRowMigrations) {
  const source = await readFile(resolve(vueDirectory, migration.file), "utf8")
  const ownership = callerOwnership[migration.file]

  assert.equal(ownership.length, migration.openings.length)
  assert.equal(source.match(/^import CadenceHoverTableRow\b/gm)?.length, 1)
  assert.equal(source.match(/<CadenceHoverTableRow\b/g)?.length, migration.openings.length)
  assert.equal(occurrences(source, migration.componentClosing), migration.openings.length)
  assert.equal(occurrences(source, hoverTableRowClass), 0)

  for (const [index, opening] of migration.openings.entries()) {
    const openingStart = source.indexOf(opening.component)
    const slotStart = openingStart + opening.component.length
    const slotEnd = source.indexOf(migration.componentClosing, slotStart)
    const slot = source.slice(slotStart, slotEnd)
    const contract = ownership[index]

    assert.notEqual(openingStart, -1, `${migration.file} opening ${index + 1} remains exact`)
    assert.ok(slotEnd > slotStart, `${migration.file} opening ${index + 1} has one bounded slot`)
    assert.equal(slot.match(/<td\b/g)?.length ?? 0, contract.tds)
    assert.equal(slot.match(/<a\b/g)?.length ?? 0, contract.anchors)
    assert.equal(slot.match(/<button\b/g)?.length ?? 0, contract.buttons)
    for (const fragment of contract.required) assert.ok(slot.includes(fragment), fragment)
  }

  peelCadenceHoverTableRows(source, migration.file)
}

const walkVueFiles = async (directory) => {
  const entries = await readdir(directory, {withFileTypes: true})
  const nested = await Promise.all(
    entries.map(async (entry) => {
      const path = resolve(directory, entry.name)
      if (entry.isDirectory()) return walkVueFiles(path)
      return entry.isFile() && entry.name.endsWith(".vue") ? [path] : []
    }),
  )
  return nested.flat()
}

const allVueSources = await Promise.all(
  (await walkVueFiles(vueDirectory)).map(async (path) => ({
    file: path.slice(vueDirectory.length + 1),
    source: await readFile(path, "utf8"),
  })),
)
assert.deepEqual(
  allVueSources
    .filter(({source}) => /^import CadenceHoverTableRow\b/m.test(source))
    .map(({file}) => file)
    .sort(),
  [...hoverTableRowCallerNames].sort(),
  "only the explicit seven-file ledger imports the primitive",
)
assert.equal(
  allVueSources.reduce(
    (total, {source}) => total + (source.match(/<CadenceHoverTableRow\b/g)?.length ?? 0),
    0,
  ),
  8,
)
assert.equal(
  allVueSources.reduce(
    (total, {source}) => total + (source.match(/<\/CadenceHoverTableRow>/g)?.length ?? 0),
    0,
  ),
  8,
)

let excludedReorderedRows = 0
let excludedDynamicRows = 0
for (const exclusion of excludedHoverTableRowFiles) {
  const source = await readFile(resolve(vueDirectory, exclusion.file), "utf8")
  const definitionListCompatibleSource = source
  const predecessorCompatibleSource = pageTitleCallerNames.includes(exclusion.file)
    ? peelCadencePageTitle(definitionListCompatibleSource, exclusion.file)
    : peelCompactTableFrames(definitionListCompatibleSource, exclusion.file)
  const uniqueFragments = new Set(exclusion.fragments)

  assert.equal(
    sha256(predecessorCompatibleSource),
    exclusion.sha256,
    `${exclusion.file} remains byte-frozen`,
  )
  assert.doesNotMatch(predecessorCompatibleSource, /CadenceHoverTableRow/)
  for (const fragment of uniqueFragments) {
    const expectedCount = exclusion.fragments.filter((value) => value === fragment).length
    assert.equal(
      occurrences(predecessorCompatibleSource, fragment),
      expectedCount,
      `${exclusion.file}: ${fragment}`,
    )
    if (fragment === reorderedHoverTableRowClass) excludedReorderedRows += expectedCount
    else excludedDynamicRows += expectedCount
  }
}
assert.equal(excludedReorderedRows, 5, "all five reordered-class rows remain excluded")
assert.equal(excludedDynamicRows, 1, "the surviving dynamic row remains excluded")

const primitiveRows = ref([
  {key: "alpha", label: "Alpha", href: "/alpha?from=row&mode=one"},
  {key: "bravo", label: "Bravo", href: "/bravo?from=row&mode=two"},
])
const rowClicks = []
const actionClicks = []
const PrimitiveContract = defineComponent({
  name: "CadenceHoverTableRowMountedContract",
  setup() {
    return () =>
      h("table", {id: "primitive-table"}, [
        h(
          "tbody",
          {id: "primitive-body"},
          primitiveRows.value.map((row) =>
            h(
              CadenceHoverTableRow,
              {
                key: row.key,
                id: `primitive-row-${row.key}`,
                class: "caller-first caller-second",
                "data-row-owner": row.key,
                "aria-label": `${row.label} row`,
                onClick: () => rowClicks.push(row.key),
              },
              {
                default: () => [
                  h(Fragment, null, [
                    [
                      h("td", {id: `primitive-cell-${row.key}`}, [
                        h(
                          "a",
                          {
                            id: `primitive-link-${row.key}`,
                            href: row.href,
                            "data-phx-link": "redirect",
                            "data-phx-link-state": "push",
                          },
                          row.label,
                        ),
                      ]),
                    ],
                    h(Fragment, null, [
                      [
                        h("td", {id: `primitive-actions-${row.key}`}, [
                          h(
                            "button",
                            {
                              id: `primitive-button-${row.key}`,
                              type: "button",
                              onClick: () => actionClicks.push(row.key),
                            },
                            `Act on ${row.label}`,
                          ),
                        ]),
                      ],
                    ]),
                  ]),
                ],
              },
            ),
          ),
        ),
      ])
  },
})
const primitiveApp = createApp(PrimitiveContract)
primitiveApp.mount(dom.window.document.querySelector("#primitive-contract"))
await nextTick()

const capturePrimitive = (key) => ({
  row: dom.window.document.querySelector(`#primitive-row-${key}`),
  cell: dom.window.document.querySelector(`#primitive-cell-${key}`),
  link: dom.window.document.querySelector(`#primitive-link-${key}`),
  button: dom.window.document.querySelector(`#primitive-button-${key}`),
})
const assertRetainedPrimitive = (key, retained) => {
  const current = capturePrimitive(key)
  assert.strictEqual(current.row, retained.row)
  assert.strictEqual(current.cell, retained.cell)
  assert.strictEqual(current.link, retained.link)
  assert.strictEqual(current.button, retained.button)
}
const alphaPrimitive = capturePrimitive("alpha")
const bravoPrimitive = capturePrimitive("bravo")

for (const retained of [alphaPrimitive, bravoPrimitive]) {
  assert.equal(retained.row.tagName, "TR")
  assert.deepEqual([...retained.row.children].map(({tagName}) => tagName), ["TD", "TD"])
  assert.equal(retained.row.className, `${hoverTableRowClass} caller-first caller-second`)
  assert.equal(retained.row.hasAttribute("key"), false, "Vue key remains component metadata")
  assert.equal(retained.row.hasAttribute("role"), false)
}
assert.deepEqual(elementAttributes(alphaPrimitive.row), {
  "aria-label": "Alpha row",
  class: `${hoverTableRowClass} caller-first caller-second`,
  "data-row-owner": "alpha",
  id: "primitive-row-alpha",
})
assert.deepEqual(elementAttributes(alphaPrimitive.link), {
  "data-phx-link": "redirect",
  "data-phx-link-state": "push",
  href: "/alpha?from=row&mode=one",
  id: "primitive-link-alpha",
})
alphaPrimitive.button.click()
assert.deepEqual(actionClicks, ["alpha"])
assert.deepEqual(rowClicks, ["alpha"], "the forwarded native row listener receives bubbling clicks")

primitiveRows.value = [primitiveRows.value[1], primitiveRows.value[0]]
await nextTick()
assert.deepEqual(
  [...dom.window.document.querySelectorAll("#primitive-body > tr")].map(({id}) => id),
  ["primitive-row-bravo", "primitive-row-alpha"],
)
assertRetainedPrimitive("alpha", alphaPrimitive)
assertRetainedPrimitive("bravo", bravoPrimitive)

primitiveRows.value = [
  primitiveRows.value[0],
  {key: "charlie", label: "Charlie", href: "/charlie?from=row&mode=three"},
  primitiveRows.value[1],
]
await nextTick()
const charliePrimitive = capturePrimitive("charlie")
assertRetainedPrimitive("alpha", alphaPrimitive)
assertRetainedPrimitive("bravo", bravoPrimitive)

primitiveRows.value = primitiveRows.value.filter(({key}) => key !== "bravo")
await nextTick()
assert.equal(dom.window.document.querySelector("#primitive-row-bravo"), null)
assertRetainedPrimitive("alpha", alphaPrimitive)
assertRetainedPrimitive("charlie", charliePrimitive)

const adminPath = resolve(vueDirectory, "AdminOrganizationList.vue")
const {component: AdminOrganizationList} = await loadSfc(adminPath)
const adminRows = ref([
  {id: "organization-alpha", display_name: "Alpha", slug: "alpha", href: "/admin/organizations/alpha"},
  {id: "organization-bravo", display_name: "Bravo", slug: "bravo", href: "/admin/organizations/bravo"},
])
const AdminContract = defineComponent({
  name: "AdminOrganizationListKeyedContract",
  setup: () => () => h(AdminOrganizationList, {rows: adminRows.value}),
})
const adminApp = createApp(AdminContract)
adminApp.mount(dom.window.document.querySelector("#admin-contract"))
await nextTick()

const captureAdmin = (id) => {
  const row = dom.window.document.querySelector(`#${id}`)
  return {row, cell: row.children[0], link: row.querySelector("a")}
}
const assertRetainedAdmin = (id, retained) => {
  const current = captureAdmin(id)
  assert.strictEqual(current.row, retained.row)
  assert.strictEqual(current.cell, retained.cell)
  assert.strictEqual(current.link, retained.link)
}
const alphaAdmin = captureAdmin("organization-alpha")
const bravoAdmin = captureAdmin("organization-bravo")
assert.equal(alphaAdmin.row.tagName, "TR")
assert.equal(alphaAdmin.row.className, hoverTableRowClass)
assert.deepEqual([...alphaAdmin.row.children].map(({tagName}) => tagName), ["TD", "TD"])
assert.deepEqual(elementAttributes(alphaAdmin.link), {
  class: "text-primary hover:underline",
  "data-phx-link": "redirect",
  "data-phx-link-state": "push",
  href: "/admin/organizations/alpha",
})

adminRows.value = [adminRows.value[1], adminRows.value[0]]
await nextTick()
assertRetainedAdmin("organization-alpha", alphaAdmin)
assertRetainedAdmin("organization-bravo", bravoAdmin)
adminRows.value = [
  adminRows.value[0],
  {id: "organization-charlie", display_name: "Charlie", slug: "charlie", href: "/admin/organizations/charlie"},
  adminRows.value[1],
]
await nextTick()
const charlieAdmin = captureAdmin("organization-charlie")
assertRetainedAdmin("organization-alpha", alphaAdmin)
assertRetainedAdmin("organization-bravo", bravoAdmin)
adminRows.value = adminRows.value.filter(({id}) => id !== "organization-bravo")
await nextTick()
assert.equal(dom.window.document.querySelector("#organization-bravo"), null)
assertRetainedAdmin("organization-alpha", alphaAdmin)
assertRetainedAdmin("organization-charlie", charlieAdmin)

primitiveApp.unmount()
adminApp.unmount()
dom.window.close()

console.log(
  "cadence_hover_table_row_migration_test passed (8 callers, 9 boundaries, exact native row + keyed identity)",
)
