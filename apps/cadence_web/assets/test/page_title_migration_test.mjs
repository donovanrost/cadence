#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {readFile, readdir} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

import {
  peelCadenceCompactPageHeaderBodyFrameBeforeOlderLayers,
} from "./compact_page_header_body_frame_test_support.mjs"
import {
  elementAttributes,
  expectedNodeVersion,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"
import {peelCompactTableFrames} from "./compact_table_frame_test_support.mjs"
import {peelConditionalKeyedCadenceFields} from "./conditional_keyed_field_test_support.mjs"
import {
  opsViewportCallerNames,
  peelCadenceOpsViewport,
} from "./ops_viewport_test_support.mjs"
import {
  paddedOpsViewportCallerNames,
  peelPaddedOpsViewport,
} from "./padded_ops_viewport_test_support.mjs"
import {
  opsAuthorHeaderCallerNames,
  peelCadenceOpsAuthorHeader,
} from "./page_header_ops_author_test_support.mjs"
import {
  excludedPageTitles,
  pageTitleCallerNames,
  pageTitleClass,
  pageTitleMigrationFor,
  pageTitleMigrations,
  pageTitlePredecessorCommit,
  peelCadencePageTitle,
  sha256,
} from "./page_title_test_support.mjs"
import {peelResidualCadenceCardBeforeOlderLayers} from "./residual_cadence_cards_test_support.mjs"
import {
  peelCadenceFormSectionFrameBeforeOlderLayers,
} from "./form_section_frame_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `page-title contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const primitivePath = resolve(vueDirectory, "ui/components/CadencePageTitle.vue")
const primitiveSource = await readFile(primitivePath, "utf8")
const occurrences = (source, fragment) => source.split(fragment).length - 1

assert.equal(pageTitleMigrations.length, 26, "the exact cohort has 26 callers")
assert.equal(new Set(pageTitleCallerNames).size, 26, "every caller is unique")
assert.equal(excludedPageTitles.length, 29, "the surviving adjacent-title exclusion ledger is frozen")
assert.throws(
  () => pageTitleMigrationFor("UnknownPage.vue"),
  /audited CadencePageTitle caller/,
  "unknown callers fail closed",
)

for (const entry of pageTitleMigrations) {
  const current = await readFile(resolve(vueDirectory, entry.file), "utf8")
  const compactHeaderBodyCompatibleCurrent =
    peelCadenceCompactPageHeaderBodyFrameBeforeOlderLayers(current, entry.file)
  const residualCardCompatibleCurrent = peelResidualCadenceCardBeforeOlderLayers(
    compactHeaderBodyCompatibleCurrent,
    entry.file,
  )
  const contactSummaryCompatibleCurrent = residualCardCompatibleCurrent
  const predecessor = execFileSync(
    "git",
    ["-C", repositoryRoot, "show", `${pageTitlePredecessorCommit}:apps/cadence_web/assets/vue/${entry.file}`],
    {encoding: "utf8"},
  )

  assert.equal(entry.predecessorCommit, pageTitlePredecessorCommit)
  assert.equal(Buffer.byteLength(predecessor), entry.predecessorByteLength)
  assert.equal(sha256(predecessor), entry.predecessorSha256)
  assert.equal(
    sha256(peelCadencePageTitle(contactSummaryCompatibleCurrent, entry.file)),
    entry.predecessorSha256,
  )
  assert.equal(occurrences(current, `<h1 class="${pageTitleClass}">`), 0)

  const openingStart = current.indexOf(entry.opening)
  const closingStart = current.indexOf(entry.closing, openingStart + entry.opening.length)
  const callerOwnedSlot = current.slice(openingStart + entry.opening.length, closingStart)

  assert.notEqual(openingStart, -1, `${entry.file} keeps one exact opening`)
  assert.ok(closingStart > openingStart, `${entry.file} keeps a bounded caller-owned slot`)
  assert.ok(callerOwnedSlot.trim().length > 0, `${entry.file} keeps title content in the caller`)
  assert.doesNotMatch(entry.opening, /\s(?:title|text|label|content)=/)
}

const exclusionCounts = Object.create(null)
for (const entry of excludedPageTitles) {
  const current = await readFile(resolve(vueDirectory, entry.file), "utf8")
  const formSectionFrameCompatibleCurrent = peelCadenceFormSectionFrameBeforeOlderLayers(
    current,
    entry.file,
  )
  const opsListCompatibleCurrent = formSectionFrameCompatibleCurrent
  const compactHeaderBodyCompatibleCurrent = peelCadenceCompactPageHeaderBodyFrameBeforeOlderLayers(
    opsListCompatibleCurrent,
    entry.file,
  )
  const conditionalKeyedCompatibleCurrent = peelConditionalKeyedCadenceFields(
    compactHeaderBodyCompatibleCurrent,
    entry.file,
  )
  const fieldCompatibleCurrent = conditionalKeyedCompatibleCurrent
  const opsAuthorHeaderCompatibleSource = opsAuthorHeaderCallerNames.includes(entry.file)
    ? peelCadenceOpsAuthorHeader(fieldCompatibleCurrent, entry.file)
    : fieldCompatibleCurrent
  const paddedOpsViewportCompatibleSource = paddedOpsViewportCallerNames.includes(entry.file)
    ? peelPaddedOpsViewport(opsAuthorHeaderCompatibleSource, entry.file)
    : opsAuthorHeaderCompatibleSource
  const compactTableCompatibleSource = peelCompactTableFrames(
    paddedOpsViewportCompatibleSource,
    entry.file,
  )
  const source = opsViewportCallerNames.includes(entry.file)
    ? peelCadenceOpsViewport(compactTableCompatibleSource, entry.file)
    : compactTableCompatibleSource

  assert.equal(sha256(source), entry.sha256, `${entry.file} remains byte-frozen`)
  assert.equal(occurrences(source, entry.opening), entry.count, `${entry.file} exact excluded title`)
  assert.doesNotMatch(source, /CadencePageTitle/)
  exclusionCounts[entry.reason] = (exclusionCounts[entry.reason] ?? 0) + entry.count
}
assert.deepEqual({...exclusionCounts}, {
  dynamic: 15,
  "ops-mt-1": 5,
  "reduced-or-structural": 4,
  "reordered-token": 5,
})

const walkVueFiles = async (directory) => {
  const entries = await readdir(directory, {withFileTypes: true})
  const nested = await Promise.all(
    entries.map(async (entry) => {
      const entryPath = resolve(directory, entry.name)
      if (entry.isDirectory()) return walkVueFiles(entryPath)
      return entry.isFile() && entry.name.endsWith(".vue") ? [entryPath] : []
    }),
  )
  return nested.flat()
}

const allVueSources = await Promise.all(
  (await walkVueFiles(vueDirectory)).map(async (filePath) => ({
    file: filePath.slice(vueDirectory.length + 1),
    source: await readFile(filePath, "utf8"),
  })),
)
assert.deepEqual(
  allVueSources
    .filter(({source}) => /^import CadencePageTitle\b/m.test(source))
    .map(({file}) => file)
    .sort(),
  [...pageTitleCallerNames].sort(),
  "only the exact 26-file ledger imports CadencePageTitle",
)
assert.deepEqual(
  allVueSources
    .filter(({source}) => /<h1\b/.test(source))
    .map(({file}) => file)
    .sort(),
  excludedPageTitles.map(({file}) => file).sort(),
  "all remaining native h1 files are explicitly excluded",
)
assert.equal(
  allVueSources.reduce(
    (total, {source}) => total + (source.match(/<CadencePageTitle\b/g)?.length ?? 0),
    0,
  ),
  26,
)
assert.equal(
  allVueSources.reduce(
    (total, {source}) => total + (source.match(/<\/CadencePageTitle>/g)?.length ?? 0),
    0,
  ),
  26,
)
assert.equal(
  allVueSources.reduce((total, {source}) => total + (source.match(/<h1\b/g)?.length ?? 0), 0),
  29,
)

const dom = installDom('<div id="page-title-contract"></div>')
for (const globalName of ["Document", "ShadowRoot"]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const parsed = parse(primitiveSource, {filename: primitivePath})

assert.deepEqual(parsed.errors, [], "CadencePageTitle parses with the pinned compiler")
assert.ok(parsed.descriptor.script, "CadencePageTitle uses a normal typed script")
assert.equal(parsed.descriptor.script.lang, "ts")
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null, "the render script introduces no slot anchors")

const compiled = compileScript(parsed.descriptor, {id: "cadence-page-title-contract"})
const transformed = transformSync(compiled.content, {
  format: "cjs",
  loader: "ts",
  platform: "node",
  target: "node24",
})
const loadedModule = {exports: {}}
const evaluate = new Function("require", "module", "exports", transformed.code)
evaluate(integrationRequire, loadedModule, loadedModule.exports)
const CadencePageTitle = loadedModule.exports.default

assert.equal(CadencePageTitle.inheritAttrs, false)
assert.deepEqual(Object.keys(CadencePageTitle.props ?? {}), [])
assert.deepEqual(Object.keys(CadencePageTitle.emits ?? {}), [])
assert.match(primitiveSource, /h\(\s*"h1"/)
assert.equal(occurrences(primitiveSource, pageTitleClass), 1)
assert.doesNotMatch(
  primitiveSource,
  /<template|defineProps|defineEmits|\b(?:computed|reactive|ref|watch|onMounted)\s*\(/,
)
assert.doesNotMatch(primitiveSource, /\b(?:role|aria-|data-|tabindex)\b/)

const {Fragment, createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")
const titles = ref([
  {key: "alpha", label: "Alpha"},
  {key: "bravo", label: "Bravo"},
])
const titleClicks = []
const childClicks = []
const Contract = defineComponent({
  name: "CadencePageTitleMountedContract",
  setup() {
    return () =>
      h(
        "div",
        {id: "page-title-list"},
        titles.value.map((title) =>
          h(
            CadencePageTitle,
            {
              key: title.key,
              id: `page-title-${title.key}`,
              class: "caller-first caller-second",
              "data-title-owner": title.key,
              "aria-label": `${title.label} title`,
              onClick: () => titleClicks.push(title.key),
            },
            {
              default: () => [
                `${title.label} `,
                [
                  h(Fragment, null, [
                    h("span", {id: `page-title-value-${title.key}`}, "value"),
                    [
                      h(Fragment, null, [
                        " ",
                        h(
                          "button",
                          {
                            id: `page-title-action-${title.key}`,
                            type: "button",
                            onClick: () => childClicks.push(title.key),
                          },
                          "act",
                        ),
                      ]),
                    ],
                  ]),
                ],
              ],
            },
          ),
        ),
      )
  },
})

const host = dom.window.document.querySelector("#page-title-contract")
const app = createApp(Contract)
app.mount(host)
await nextTick()

const capture = (key) => ({
  title: dom.window.document.querySelector(`#page-title-${key}`),
  value: dom.window.document.querySelector(`#page-title-value-${key}`),
  action: dom.window.document.querySelector(`#page-title-action-${key}`),
})
const assertRetained = (key, retained) => {
  const current = capture(key)
  assert.strictEqual(current.title, retained.title)
  assert.strictEqual(current.value, retained.value)
  assert.strictEqual(current.action, retained.action)
}
const alpha = capture("alpha")
const bravo = capture("bravo")

for (const retained of [alpha, bravo]) {
  assert.equal(retained.title.tagName, "H1")
  assert.equal(retained.title.className, `${pageTitleClass} caller-first caller-second`)
  assert.equal(retained.title.hasAttribute("key"), false, "Vue key remains VNode metadata")
  assert.equal(retained.title.hasAttribute("role"), false)
  assert.deepEqual(
    [...retained.title.childNodes].map(({nodeName}) => nodeName),
    ["#text", "SPAN", "#text", "BUTTON"],
    "fragment and array slots flatten without DOM anchors",
  )
}
assert.deepEqual(elementAttributes(alpha.title), {
  "aria-label": "Alpha title",
  class: `${pageTitleClass} caller-first caller-second`,
  "data-title-owner": "alpha",
  id: "page-title-alpha",
})

alpha.action.click()
assert.deepEqual(childClicks, ["alpha"], "caller-owned native child listener fires")
assert.deepEqual(titleClicks, ["alpha"], "forwarded native h1 listener receives the bubbled event")

titles.value = [titles.value[1], titles.value[0]]
await nextTick()
assert.deepEqual(
  [...host.querySelectorAll("#page-title-list > h1")].map(({id}) => id),
  ["page-title-bravo", "page-title-alpha"],
)
assertRetained("alpha", alpha)
assertRetained("bravo", bravo)

titles.value = [
  titles.value[0],
  {key: "charlie", label: "Charlie"},
  titles.value[1],
]
await nextTick()
const charlie = capture("charlie")
assertRetained("alpha", alpha)
assertRetained("bravo", bravo)

titles.value = titles.value.filter(({key}) => key !== "bravo")
await nextTick()
assert.equal(dom.window.document.querySelector("#page-title-bravo"), null)
assertRetained("alpha", alpha)
assertRetained("charlie", charlie)

app.unmount()
assert.equal(host.children.length, 0)
dom.window.close()

console.log(
  "page_title_migration_test passed (26 exact callers, 52 frozen exclusions, native h1 identity)",
)
