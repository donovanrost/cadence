import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  assertPinnedAdapterRuntime,
  flushVue,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"

const scenarioLedger = Object.freeze([
  "the actual CatalogDatabaseTable SFC compiles and mounts with two rows",
  "the integration runtime and repaired SFC bytes stay pinned",
  "the repair adds only the one-way content label without custom menu ownership",
  "closed menus expose neither content nor an unresolved aria-controls IDREF",
  "open triggers and generated content IDs resolve both IDREF directions",
  "generated content IDs stay unique across both rows",
  "menu content remains portaled with Reka menu and menuitem roles",
  "View database links retain their exact href and LiveView navigation attributes",
  "ArrowDown, Escape, and selection retain their native menu behavior",
  "default modal Tab behavior and trigger focus restoration remain intact",
])

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/CatalogDatabaseTable.vue")
const packageLockPath = resolve(testDirectory, "../../package-lock.json")
await assertPinnedAdapterRuntime(packageLockPath)
assert.equal(scenarioLedger.length, 10)

const source = await readFile(componentPath, "utf8")
const rootTag = source.match(/<DropdownMenuRoot\b[^>]*>/)?.[0]
const contentTag = source.match(/<DropdownMenuContent\b[\s\S]*?>/)?.[0]

assert.equal(
  createHash("sha256").update(source).digest("hex"),
  "14b28fc4ef6589daf99d5c2b32bdcff0b8845ee3dbce4823b2cf4cc2a98d72ed",
)
assert.equal(rootTag, "<DropdownMenuRoot>")
assert.ok(contentTag, "CatalogDatabaseTable keeps its direct Reka content")
assert.equal(source.match(/:aria-labelledby="row\.actions_id"/g)?.length, 1)
assert.doesNotMatch(contentTag, /(?:^|\s):?id=/)
assert.doesNotMatch(source, /aria-controls/)
assert.doesNotMatch(rootTag, /\bv-slot\b/)
assert.doesNotMatch(rootTag, /(?:^|\s):?modal(?:=|\s|>)/)
assert.doesNotMatch(source, /CadenceMenu/)

const dom = installDom('<div id="app"></div>')
Object.defineProperty(globalThis, "HTMLInputElement", {
  configurable: true,
  value: dom.window.HTMLInputElement,
})

const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const {createApp, defineComponent, h, nextTick} = integrationRequire("vue")

const parsed = parse(source, {filename: componentPath})
assert.deepEqual(parsed.errors, [], "CatalogDatabaseTable parses with the pinned Vue compiler")
assert.ok(parsed.descriptor.scriptSetup, "CatalogDatabaseTable keeps its setup script")
assert.ok(parsed.descriptor.template, "CatalogDatabaseTable keeps its template")

const compiled = compileScript(parsed.descriptor, {
  id: "catalog-database-table-idref-oracle",
  inlineTemplate: true,
})
const transformed = transformSync(compiled.content, {
  format: "cjs",
  loader: "ts",
  platform: "node",
  target: "node24",
})
const loadedModule = {exports: {}}
const StatusBadge = defineComponent({
  props: ["status", "label"],
  setup: (props) => () => h("span", props.label),
})
const localRequire = (specifier) =>
  specifier === "./StatusBadge.vue" ? StatusBadge : integrationRequire(specifier)

new Function("require", "module", "exports", transformed.code)(
  localRequire,
  loadedModule,
  loadedModule.exports,
)
const CatalogDatabaseTable = loadedModule.exports.default

const rows = ["alpha", "beta"].map((id) => ({
  id: `catalog-database-${id}`,
  actions_id: `catalog-database-${id}-actions`,
  name: `${id} database`,
  slug: id,
  href: `/missions/mission-1/catalog/databases/${id}`,
  latest_revision: null,
  latest_import: null,
}))

const Probe = defineComponent({
  setup: () => () => h("main", {id: "catalog-database-table-probe"}, [
    h(CatalogDatabaseTable, {rows}),
  ]),
})

document.addEventListener("click", (event) => {
  if (event.target.closest("a")) event.preventDefault()
})

const appElement = document.querySelector("#app")
const app = createApp(Probe)
app.mount(appElement)
await flushVue(nextTick)

assert.equal(document.querySelectorAll("#catalog-databases-table tbody tr").length, 2)
assert.equal(new Set(rows.map((row) => row.actions_id)).size, 2)

const assertClosed = (row, contentId) => {
  const trigger = document.getElementById(row.actions_id)

  assert.ok(trigger, `${row.slug} retains its public trigger ID`)
  assert.equal(trigger.getAttribute("aria-expanded"), "false")
  assert.equal(trigger.hasAttribute("aria-controls"), false)
  assert.equal(document.querySelector(`[role="menu"][aria-labelledby="${row.actions_id}"]`), null)
  if (contentId) assert.equal(document.getElementById(contentId), null)
}

const settleClose = async () => {
  await flushVue(nextTick)
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 10))
  await flushVue(nextTick)
}

const generatedContentIds = []

for (const [rowIndex, row] of rows.entries()) {
  const trigger = document.getElementById(row.actions_id)
  assertClosed(row)
  assert.equal(document.querySelectorAll(`[id="${row.actions_id}"]`).length, 1)
  trigger.focus()

  if (rowIndex === 0) {
    const arrowDown = new KeyboardEvent("keydown", {
      bubbles: true,
      cancelable: true,
      key: "ArrowDown",
    })
    trigger.dispatchEvent(arrowDown)
    assert.equal(arrowDown.defaultPrevented, true, "ArrowDown remains owned by Reka")
  } else {
    trigger.dispatchEvent(
      new MouseEvent("click", {bubbles: true, cancelable: true, button: 0}),
    )
  }

  await flushVue(nextTick)

  const contentId = trigger.getAttribute("aria-controls")
  const content = document.getElementById(contentId)
  generatedContentIds.push(contentId)

  assert.equal(trigger.getAttribute("aria-expanded"), "true")
  assert.ok(contentId, `${row.slug} receives a generated content IDREF`)
  assert.match(contentId, /^reka-dropdown-menu-content-v-\d+$/)
  assert.equal(contentId.includes(row.actions_id), false)
  assert.ok(content, `${row.slug} generated content ID resolves`)
  assert.equal(document.getElementById(trigger.getAttribute("aria-controls")), content)
  assert.equal(content.getAttribute("aria-labelledby"), row.actions_id)
  assert.equal(document.getElementById(content.getAttribute("aria-labelledby")), trigger)
  assert.equal(document.querySelectorAll(`[id="${contentId}"]`).length, 1)
  assert.equal(appElement.contains(content), false, `${row.slug} content stays portaled`)
  assert.equal(content.getAttribute("role"), "menu")
  assert.equal(appElement.getAttribute("aria-hidden"), "true", `${row.slug} remains modal`)
  assert.equal(content.contains(document.activeElement), true)
  assert.equal(document.activeElement.getAttribute("role"), "menuitem")

  const links = [...content.querySelectorAll("a")]
  assert.equal(links.length, 1)
  assert.equal(links[0].textContent.trim(), "View database")
  assert.equal(links[0].getAttribute("href"), row.href)
  assert.equal(links[0].getAttribute("role"), "menuitem")
  assert.equal(links[0].getAttribute("data-phx-link"), "redirect")
  assert.equal(links[0].getAttribute("data-phx-link-state"), "push")

  const tab = new KeyboardEvent("keydown", {
    bubbles: true,
    cancelable: true,
    key: "Tab",
  })
  content.dispatchEvent(tab)
  assert.equal(tab.defaultPrevented, true, `${row.slug} keeps default modal Tab suppression`)
  assert.equal(trigger.getAttribute("aria-expanded"), "true")

  if (rowIndex === 0) {
    const escape = new KeyboardEvent("keydown", {
      bubbles: true,
      cancelable: true,
      key: "Escape",
    })
    content.dispatchEvent(escape)
  } else {
    links[0].dispatchEvent(
      new MouseEvent("click", {bubbles: true, cancelable: true, button: 0}),
    )
  }

  await settleClose()
  assertClosed(row, contentId)
  assert.equal(document.activeElement, trigger, `${row.slug} restores trigger focus`)
  assert.equal(appElement.hasAttribute("aria-hidden"), false, `${row.slug} releases modal hiding`)
}

assert.equal(new Set(generatedContentIds).size, 2, "both generated content IDs stay unique")
assert.equal(document.querySelectorAll('[role="menu"]').length, 0)

app.unmount()
dom.window.close()

console.log(`catalog_database_table_idref_test passed (${scenarioLedger.length} scenarios)`)
