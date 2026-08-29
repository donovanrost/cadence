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
import {
  statTileClass,
  statTileLabelClass,
  statTileValueClass,
} from "./stat_tile_test_support.mjs"

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
const scenarios = Object.freeze([
  "the actual typed render SFC owns exactly one native div and one native label p",
  "root attrs, caller classes, listeners, and nested named/default Fragments forward exactly",
  "rendered DOM and attributes match a caller-native control specimen byte-for-byte",
  "the complete caller-owned value p remains the same native node through reactive updates",
  "keyed reorder preserves every existing tile root, label, and value-node identity",
])

assert.equal(process.execPath, pinnedNode)
assert.equal(process.versions.node, expectedNodeVersion)
assert.equal(scenarios.length, 5)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/ui/components/CadenceStatTile.vue")
const source = await readFile(componentPath, "utf8")

// Install every DOM global before the first Vue import/evaluation.
const dom = installDom('<main><div id="stat-tile-contract"></div><div id="native-contract"></div></main>')
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const parsed = parse(source, {filename: componentPath})

assert.deepEqual(parsed.errors, [], "CadenceStatTile parses with the pinned Vue compiler")
assert.ok(parsed.descriptor.script, "CadenceStatTile keeps a typed render-function script")
assert.equal(parsed.descriptor.script.lang, "ts")
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null, "render slots create no template anchors")

const compiled = compileScript(parsed.descriptor, {id: "cadence-stat-tile-contract"})
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

const CadenceStatTile = loadedModule.exports.default
const {Fragment, createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")

assert.equal(CadenceStatTile.inheritAttrs, false)
assert.equal(CadenceStatTile.props, undefined)
assert.equal(CadenceStatTile.emits, undefined)
assert.equal(source.match(/h\(\s*"div"/g)?.length, 1, "the primitive owns one native div")
assert.equal(source.match(/h\(\s*"p"/g)?.length, 1, "the primitive owns one native p")
assert.match(source, /Array\.isArray\(child\)/)
assert.match(source, /child\.type === Fragment/)
assert.doesNotMatch(
  source,
  /<template|<input|<button|<select|<form|defineProps|defineEmits|\b(?:computed|reactive|ref|watch)\s*\(|\bemit\s*\(|\b(?:id|value|role|aria-[\w-]+)\s*:/,
  "the primitive owns no template, controls, IDs, values, state, events, or caller semantics",
)

const initialStats = Object.freeze([
  Object.freeze({id: "stat-alpha", label: "Alpha", value: "10"}),
  Object.freeze({id: "stat-beta", label: "Beta", value: "20"}),
  Object.freeze({id: "stat-gamma", label: "Gamma", value: "30"}),
])
const updatedStats = Object.freeze([
  Object.freeze({id: "stat-gamma", label: "Gamma updated", value: "31"}),
  Object.freeze({id: "stat-alpha", label: "Alpha updated", value: "11"}),
  Object.freeze({id: "stat-beta", label: "Beta updated", value: "21"}),
])
const stats = ref(initialStats)
const phase = ref("ready")
let tileClicks = 0

const statTile = (stat) =>
  h(
    CadenceStatTile,
    {
      key: stat.id,
      id: stat.id,
      class: "caller-text-right caller-canary",
      "aria-label": `Caller ${stat.label}`,
      "data-phase": phase.value,
      onClick: () => {
        tileClicks += 1
      },
    },
    {
      label: () => [[h(Fragment, null, [[stat.label]])]],
      default: () => [
        h(Fragment, null, [
          [h("p", {class: statTileValueClass, "data-value-id": stat.id}, stat.value)],
        ]),
      ],
    },
  )

const nativeTile = (stat) =>
  h(
    "div",
    {
      key: stat.id,
      id: stat.id,
      class: [statTileClass, "caller-text-right caller-canary"],
      "aria-label": `Caller ${stat.label}`,
      "data-phase": phase.value,
    },
    [
      h("p", {class: statTileLabelClass}, stat.label),
      h("p", {class: statTileValueClass, "data-value-id": stat.id}, stat.value),
    ],
  )

const PrimitiveCohort = defineComponent({
  name: "CadenceStatTileContract",
  setup: () => () => h(Fragment, null, stats.value.map(statTile)),
})
const NativeCohort = defineComponent({
  name: "NativeStatTileContract",
  setup: () => () => h(Fragment, null, stats.value.map(nativeTile)),
})

const contractHost = dom.window.document.querySelector("#stat-tile-contract")
const nativeHost = dom.window.document.querySelector("#native-contract")
const primitiveApp = createApp(PrimitiveCohort)
const nativeApp = createApp(NativeCohort)
primitiveApp.mount(contractHost)
nativeApp.mount(nativeHost)
await flushVue(nextTick)

const exactTiles = (host) => [...host.children]
const snapshot = (host) =>
  exactTiles(host).map((tile) => ({
    outerHTML: tile.outerHTML,
    attributes: elementAttributes(tile),
    childTags: [...tile.children].map((child) => child.tagName),
  }))

assert.deepEqual(snapshot(contractHost), snapshot(nativeHost))
assert.equal(contractHost.children.length, initialStats.length)

const originalNodes = new Map(
  exactTiles(contractHost).map((tile) => [
    tile.id,
    {root: tile, label: tile.children[0], value: tile.children[1]},
  ]),
)

for (const tile of exactTiles(contractHost)) {
  assert.equal(tile.tagName, "DIV")
  assert.equal(tile.className, `${statTileClass} caller-text-right caller-canary`)
  assert.equal(tile.childNodes.length, 2)
  assert.equal(tile.children[0].tagName, "P")
  assert.equal(tile.children[0].className, statTileLabelClass)
  assert.equal(tile.children[1].tagName, "P")
  assert.equal(tile.children[1].className, statTileValueClass)
}

originalNodes.get("stat-alpha").root.dispatchEvent(
  new dom.window.MouseEvent("click", {bubbles: true}),
)
assert.equal(tileClicks, 1, "the caller root listener falls through to the native div")

stats.value = updatedStats
phase.value = "updated"
await flushVue(nextTick)

assert.deepEqual(snapshot(contractHost), snapshot(nativeHost))
assert.deepEqual(exactTiles(contractHost).map((tile) => tile.id), [
  "stat-gamma",
  "stat-alpha",
  "stat-beta",
])

for (const stat of updatedStats) {
  const current = dom.window.document.querySelector(`#stat-tile-contract > #${stat.id}`)
  const original = originalNodes.get(stat.id)

  assert.strictEqual(current, original.root, `${stat.id} root identity survives keyed reorder`)
  assert.strictEqual(current.children[0], original.label, `${stat.id} label p identity survives`)
  assert.strictEqual(current.children[1], original.value, `${stat.id} caller value p identity survives`)
  assert.equal(current.children[0].textContent, stat.label)
  assert.equal(current.children[1].textContent, stat.value)
  assert.equal(current.getAttribute("data-phase"), "updated")
}

assert.doesNotThrow(() => primitiveApp.unmount())
assert.doesNotThrow(() => nativeApp.unmount())
dom.window.close()

console.log(`cadence_stat_tile_test passed (${scenarios.length} exact-DOM scenarios)`)
