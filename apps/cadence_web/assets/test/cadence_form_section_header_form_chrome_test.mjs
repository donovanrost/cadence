import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  expectedNodeVersion,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `CadenceFormSectionHeader contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(
  testDirectory,
  "../vue/ui/components/CadenceFormSectionHeader.vue",
)
const source = await readFile(componentPath, "utf8")
const dom = installDom('<div id="section-header-contract"></div>')
const {component: CadenceFormSectionHeader, descriptor} = await loadSfc(componentPath)
const {createApp} = integrationRequire("vue")

assert.ok(descriptor.scriptSetup, "CadenceFormSectionHeader keeps a typed setup block")
assert.equal(descriptor.scriptSetup.lang, "ts")
assert.ok(descriptor.template, "CadenceFormSectionHeader keeps a literal template")
assert.equal(
  descriptor.template.content.trim(),
  `<div :class="wrapperClass">
    <span :class="numberClass">{{ number }}</span>
    <h2 :class="titleClass">{{ title }}</h2>
    <div :class="dividerClass"></div>
  </div>`,
)
assert.doesNotMatch(
  source,
  /\b(?:computed|reactive|ref|watch)\s*\(|defineEmits|@(?:click|input|change|submit)|\bfetch\s*\(|href|data-phx-link/,
  "the section header owns no state, events, routing, or Phoenix behavior",
)
assert.doesNotMatch(source, /<slot|<button|<a\b|<input|<form/)

const rawProps = Object.freeze({
  wrapperClass: "flex items-center gap-3 exact-order",
  number: " 07 / β ",
  numberClass: "hud-label text-primary/70 raw-number-order",
  title: "RF & Link <Ops>",
  titleClass: "hud-label raw-title-order",
  dividerClass: "flex-1 h-px bg-base-300/60 raw-divider-order",
})
const before = JSON.stringify(rawProps)
const host = dom.window.document.querySelector("#section-header-contract")
const app = createApp(CadenceFormSectionHeader, rawProps)
app.mount(host)

assert.equal(JSON.stringify(rawProps), before, "raw content and classes remain immutable")
assert.equal(host.children.length, 1, "the component adds only its required root div")
assert.equal(
  host.firstElementChild.outerHTML,
  '<div class="flex items-center gap-3 exact-order"><span class="hud-label text-primary/70 raw-number-order"> 07 / β </span><h2 class="hud-label raw-title-order">RF &amp; Link &lt;Ops&gt;</h2><div class="flex-1 h-px bg-base-300/60 raw-divider-order"></div></div>',
  "the mounted SFC preserves exact tags, raw content, class order, and sibling order",
)
assert.deepEqual(
  [...host.firstElementChild.childNodes].map((node) => node.nodeName),
  ["SPAN", "H2", "DIV"],
  "no whitespace or wrapper nodes drift into the header",
)

app.unmount()
assert.equal(host.children.length, 0)
dom.window.close()

console.log("cadence_form_section_header_form_chrome_test passed")
