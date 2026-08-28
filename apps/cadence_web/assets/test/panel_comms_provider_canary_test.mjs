import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {integrationRequire} from "./reka_adapter_test_support.mjs"

assert.equal(process.versions.node, "24.16.0", "panel canary uses pinned Node 24.16.0")

const base = "88137bfa2ea69aaedfa0c5d3882e763dae0d09db"
const baseByteLength = 13677
const baseSha256 = "84771fcb6fde91f9a0ee782b206d473c638aeb19ea14bab55b40e93ddd61fc34"
const pageHeaderImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const compactPageHeaderOpen = '    <CadencePageHeaderFrame variant="compact">'
const compactPageHeaderBaseOpen = '    <header class="border-b border-primary/20 pb-4">'
const compactPageHeaderClose = "    </CadencePageHeaderFrame>"
const compactPageHeaderBaseClose = "    </header>"
const panelImport = 'import CadencePanel from "./ui/components/CadencePanel.vue"\n'
const headerClass = "flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/CommsProviderShow.vue")
const currentSource = await readFile(componentPath, "utf8")
const {parse} = integrationRequire("@vue/compiler-sfc")
const parsed = parse(currentSource, {filename: componentPath})

assert.deepEqual(parsed.errors, [], "migrated CommsProviderShow parses with the pinned Vue compiler")
assert.ok(parsed.descriptor.scriptSetup, "CommsProviderShow retains its script setup boundary")
assert.ok(parsed.descriptor.template, "CommsProviderShow retains its template boundary")
assert.equal(currentSource.split(pageHeaderImport).length - 1, 1, "page header import reconstructs")
assert.equal(currentSource.split(compactPageHeaderOpen).length - 1, 1, "page header opening reconstructs")
assert.equal(currentSource.split(compactPageHeaderClose).length - 1, 1, "page header close reconstructs")
const source = currentSource
  .replace(pageHeaderImport, "")
  .replace(compactPageHeaderOpen, compactPageHeaderBaseOpen)
  .replace(compactPageHeaderClose, compactPageHeaderBaseClose)
assert.equal(source.split(panelImport).length - 1, 1, "CadencePanel is imported exactly once")
assert.equal(source.match(/<CadencePanel\b/g)?.length, 2, "exactly two panel boundaries open")
assert.equal(source.split("</CadencePanel>").length - 1, 2, "exactly two panel boundaries close")
assert.equal(
  source.split(`header-class="${headerClass}"`).length - 1,
  2,
  "both migrated headers retain the exact caller-provided class",
)
assert.equal(source.split("<template #header>").length - 1, 2, "both panels own one named header slot")
assert.equal(
  source.match(/<CadenceCard\b/g)?.length,
  3,
  "the three existing CadenceCard boundaries remain untouched",
)

const lines = (...sourceLines) => sourceLines.join("\n")
const occurrenceCount = (value, token) => value.split(token).length - 1
const replaceExactlyOnce = (value, current, replacement, label) => {
  assert.equal(occurrenceCount(value, current), 1, `${label} occurs exactly once`)
  return value.replace(current, replacement)
}
const boundaries = Object.freeze([
  Object.freeze({
    label: "service profile panel",
    migrated: lines(
      "        <CadencePanel",
      '          :id="profiles.service.id"',
      '          class="card bg-base-200 border border-base-300"',
      `          header-class="${headerClass}"`,
      "        >",
      "          <template #header>",
    ),
    base: lines(
      '        <section :id="profiles.service.id" class="card bg-base-200 border border-base-300">',
      `          <div class="${headerClass}">`,
    ),
  }),
  Object.freeze({
    label: "delivery profile panel",
    migrated: lines(
      "        <CadencePanel",
      '          :id="profiles.delivery.id"',
      '          class="card bg-base-200 border border-base-300"',
      `          header-class="${headerClass}"`,
      "        >",
      "          <template #header>",
    ),
    base: lines(
      '        <section :id="profiles.delivery.id" class="card bg-base-200 border border-base-300">',
      `          <div class="${headerClass}">`,
    ),
  }),
])

let reconstructed = replaceExactlyOnce(source, panelImport, "", "CadencePanel import")

for (const boundary of boundaries) {
  reconstructed = replaceExactlyOnce(
    reconstructed,
    boundary.migrated,
    boundary.base,
    boundary.label,
  )
}

assert.equal(
  occurrenceCount(
    reconstructed,
    '          </template>\n          <div class="card-body p-0">',
  ),
  2,
  "exactly two header slot closings reconstruct",
)
reconstructed = reconstructed.replaceAll(
  '          </template>\n          <div class="card-body p-0">',
  '          </div>\n          <div class="card-body p-0">',
)

assert.equal(
  occurrenceCount(reconstructed, "        </CadencePanel>"),
  2,
  "exactly two panel closings reconstruct",
)
reconstructed = reconstructed.replaceAll("        </CadencePanel>", "        </section>")

assert.doesNotMatch(reconstructed, /CadencePanel/)
assert.equal(
  Buffer.byteLength(reconstructed),
  baseByteLength,
  `the reconstructed source has the exact byte length from base ${base}`,
)
assert.equal(
  createHash("sha256").update(reconstructed).digest("hex"),
  baseSha256,
  `the reconstructed source is byte-for-byte identical to CommsProviderShow at base ${base}`,
)

console.log("panel_comms_provider_canary_test passed (2 boundaries, exact base reconstruction)")
