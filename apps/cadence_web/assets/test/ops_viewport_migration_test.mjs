#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {readFile, readdir} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

import {
  elementAttributes,
  expectedNodeVersion,
  flushVue,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"
import {peelContactSummaryBand} from "./contact_summary_band_test_support.mjs"
import {peelConditionalKeyedCadenceFields} from "./conditional_keyed_field_test_support.mjs"
import {
  excludedOpsViewportVariants,
  opsViewportCallerNames,
  opsViewportClass,
  opsViewportMigrationFor,
  opsViewportMigrations,
  opsViewportPredecessorCommit,
  opsViewportSha256,
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

const scenarios = Object.freeze([
  "the complete Vue tree contains only the frozen exact cohort and two excluded padded variants",
  "all 17 migrated callers reconstruct the exact immutable predecessor bytes",
  "the actual primitive compiles from a normal typed render script without semantic state",
  "the primitive renders one native section with fixed classes before caller classes",
  "ids, aria, data attributes, listeners, and directives remain caller-owned and forwarded",
  "nested array and Fragment slots flatten without wrapper or anchor nodes",
  "Vue keys remain metadata and never become DOM attributes",
  "keyed section, child, and action identity survives reorder, insert, and remove updates",
])

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `Ops viewport contracts use pinned Node ${expectedNodeVersion}`,
)
assert.equal(scenarios.length, 8)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const primitivePath = resolve(vueDirectory, "ui/components/CadenceOpsViewport.vue")
const primitiveSource = await readFile(primitivePath, "utf8")
const occurrences = (source, fragment) => source.split(fragment).length - 1

assert.equal(opsViewportMigrations.length, 17, "the exact cohort has 17 callers")
assert.equal(new Set(opsViewportCallerNames).size, 17, "every caller is unique")
assert.equal(excludedOpsViewportVariants.length, 2, "two padded near variants stay excluded")
assert.equal(
  opsViewportMigrations.filter(({opening}) => opening === '  <CadenceOpsViewport :id="page.id">')
    .length,
  15,
  "15 ordinary callers own page.id",
)
assert.equal(
  opsViewportMigrations.filter(({opening}) => opening.includes(':id="header.id"')).length,
  1,
  "OpsFleetPlanningNew alone owns header.id",
)
assert.equal(
  opsViewportMigrations.filter(({opening}) => opening.includes(':aria-busy="planning"')).length,
  1,
  "OpsFleetPlanningRun alone owns planning aria-busy",
)
assert.throws(
  () => opsViewportMigrationFor("UnknownOpsViewport.vue"),
  /audited CadenceOpsViewport caller/,
  "unknown callers fail closed",
)

const predecessorType = execFileSync(
  "git",
  ["-C", repositoryRoot, "cat-file", "-t", opsViewportPredecessorCommit],
  {encoding: "utf8"},
).trim()
assert.equal(predecessorType, "commit", "the frozen predecessor resolves as a commit")

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

const historicalVueFiles = new Set(
  execFileSync(
    "git",
    [
      "-C",
      repositoryRoot,
      "ls-tree",
      "-r",
      "--name-only",
      opsViewportPredecessorCommit,
      "apps/cadence_web/assets/vue",
    ],
    {encoding: "utf8"},
  )
    .trim()
    .split("\n")
    .filter((filePath) => filePath.endsWith(".vue"))
    .map((filePath) => filePath.slice("apps/cadence_web/assets/vue/".length)),
)
historicalVueFiles.add("ui/components/CadenceOpsViewport.vue")

const allVueSources = await Promise.all(
  (await walkVueFiles(vueDirectory))
    .map((filePath) => ({filePath, file: filePath.slice(vueDirectory.length + 1)}))
    .filter(({file}) => historicalVueFiles.has(file))
    .map(async ({filePath, file}) => {
      const current = await readFile(filePath, "utf8")
      return {
        file,
        source: paddedOpsViewportCallerNames.includes(file)
          ? peelPaddedOpsViewport(current, file)
          : current,
      }
    }),
)

assert.equal(allVueSources.length, 221, "the audited Vue tree includes every current SFC")
assert.deepEqual(
  allVueSources
    .filter(({source}) => /^import CadenceOpsViewport\b/m.test(source))
    .map(({file}) => file)
    .sort(),
  [...opsViewportCallerNames].sort(),
  "only the exact 17-file ledger imports CadenceOpsViewport",
)
assert.equal(
  allVueSources.reduce(
    (total, {source}) => total + (source.match(/<CadenceOpsViewport\b/g)?.length ?? 0),
    0,
  ),
  17,
)
assert.equal(
  allVueSources.reduce(
    (total, {source}) => total + (source.match(/<\/CadenceOpsViewport>/g)?.length ?? 0),
    0,
  ),
  17,
)

const nativeExactOpening = new RegExp(
  `<section\\b[^>]*class="${opsViewportClass}"[^>]*>`,
  "g",
)
assert.deepEqual(
  allVueSources
    .filter(({source}) => (source.match(nativeExactOpening) ?? []).length > 0)
    .map(({file}) => file),
  [],
  "no exact native Ops viewport remains after migration",
)

const paddedNearOpening = new RegExp(
  `<section\\b[^>]*class="${opsViewportClass} [^"]+"[^>]*>`,
  "g",
)
assert.deepEqual(
  allVueSources
    .filter(({source}) => (source.match(paddedNearOpening) ?? []).length > 0)
    .map(({file}) => file)
    .sort(),
  excludedOpsViewportVariants.map(({file}) => file).sort(),
  "every native class-prefix lookalike is frozen in the exclusion ledger",
)

const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
for (const entry of opsViewportMigrations) {
  const current = await readFile(resolve(vueDirectory, entry.file), "utf8")
  const conditionalKeyedCompatibleCurrent = peelConditionalKeyedCadenceFields(
    current,
    entry.file,
  )
  const contactSummaryCompatibleCurrent = peelContactSummaryBand(
    conditionalKeyedCompatibleCurrent,
    entry.file,
  )
  const predecessorCompatibleCurrent = opsAuthorHeaderCallerNames.includes(entry.file)
    ? peelCadenceOpsAuthorHeader(contactSummaryCompatibleCurrent, entry.file)
    : contactSummaryCompatibleCurrent
  const predecessor = execFileSync(
    "git",
    [
      "-C",
      repositoryRoot,
      "show",
      `${opsViewportPredecessorCommit}:apps/cadence_web/assets/vue/${entry.file}`,
    ],
    {encoding: "utf8"},
  )

  assert.equal(entry.predecessorCommit, opsViewportPredecessorCommit)
  assert.equal(Buffer.byteLength(predecessor), entry.predecessorByteLength)
  assert.equal(opsViewportSha256(predecessor), entry.predecessorSha256)
  assert.equal(peelCadenceOpsViewport(predecessorCompatibleCurrent, entry.file), predecessor)
  assert.equal(occurrences(current, `class="${opsViewportClass}"`), 0)
  assert.match(entry.opening, /:id="(?:page|header)\.id"/, `${entry.file} keeps caller id`)

  if (entry.file === "OpsFleetPlanningRun.vue") {
    assert.match(entry.opening, /:aria-busy="planning"/, "planning busy state stays caller-owned")
  } else {
    assert.doesNotMatch(entry.opening, /aria-busy/)
  }

  const openingStart = current.indexOf(entry.opening)
  const closingStart = current.indexOf(entry.closing, openingStart + entry.opening.length)
  const callerOwnedSlot = current.slice(openingStart + entry.opening.length, closingStart)

  assert.notEqual(openingStart, -1, `${entry.file} keeps one exact component opening`)
  assert.ok(closingStart > openingStart, `${entry.file} keeps one bounded caller slot`)
  assert.ok(callerOwnedSlot.trim().length > 0, `${entry.file} keeps all viewport content in its slot`)

  const parsedCaller = parse(current, {filename: entry.file})
  assert.deepEqual(parsedCaller.errors, [], `${entry.file} parses with the pinned Vue compiler`)
  assert.ok(parsedCaller.descriptor.scriptSetup, `${entry.file} keeps its setup script`)
  assert.ok(parsedCaller.descriptor.template, `${entry.file} keeps its template`)
  assert.doesNotThrow(() =>
    compileScript(parsedCaller.descriptor, {
      id: `cadence-ops-viewport-${entry.file}`,
      inlineTemplate: true,
    }),
  )
}

for (const exclusion of excludedOpsViewportVariants) {
  const current = await readFile(resolve(vueDirectory, exclusion.file), "utf8")
  const predecessorCompatibleCurrent = paddedOpsViewportCallerNames.includes(exclusion.file)
    ? peelPaddedOpsViewport(current, exclusion.file)
    : current
  const predecessor = execFileSync(
    "git",
    [
      "-C",
      repositoryRoot,
      "show",
      `${opsViewportPredecessorCommit}:apps/cadence_web/assets/vue/${exclusion.file}`,
    ],
    {encoding: "utf8"},
  )

  assert.equal(
    predecessorCompatibleCurrent,
    predecessor,
    `${exclusion.file} stays byte-identical to the predecessor`,
  )
  assert.equal(Buffer.byteLength(predecessorCompatibleCurrent), exclusion.byteLength)
  assert.equal(opsViewportSha256(predecessorCompatibleCurrent), exclusion.sha256)
  assert.equal(occurrences(predecessorCompatibleCurrent, exclusion.opening), exclusion.count)
  assert.match(exclusion.reason, /^p-6 padded/)
  assert.doesNotMatch(predecessorCompatibleCurrent, /CadenceOpsViewport/)
}

const dom = installDom('<div id="ops-viewport-contract"></div>')
for (const globalName of ["Document", "ShadowRoot"]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const parsedPrimitive = parse(primitiveSource, {filename: primitivePath})
assert.deepEqual(parsedPrimitive.errors, [], "CadenceOpsViewport parses with the pinned compiler")
assert.ok(parsedPrimitive.descriptor.script, "CadenceOpsViewport uses a normal typed script")
assert.equal(parsedPrimitive.descriptor.script.lang, "ts")
assert.equal(parsedPrimitive.descriptor.scriptSetup, null)
assert.equal(parsedPrimitive.descriptor.template, null)
assert.equal(parsedPrimitive.descriptor.styles.length, 0)

const compiledPrimitive = compileScript(parsedPrimitive.descriptor, {
  id: "cadence-ops-viewport-contract",
}).content
const {transformSync} = integrationRequire("esbuild")
const transformedPrimitive = transformSync(compiledPrimitive, {
  format: "cjs",
  loader: "ts",
  platform: "node",
  target: "node24",
})
const loadedModule = {exports: {}}
new Function("require", "module", "exports", transformedPrimitive.code)(
  integrationRequire,
  loadedModule,
  loadedModule.exports,
)
const CadenceOpsViewport = loadedModule.exports.default

assert.equal(CadenceOpsViewport.inheritAttrs, false)
assert.deepEqual(Object.keys(CadenceOpsViewport.props ?? {}), [])
assert.deepEqual(Object.keys(CadenceOpsViewport.emits ?? {}), [])
assert.equal(primitiveSource.match(/h\(\s*"section"/g)?.length, 1)
assert.equal(occurrences(primitiveSource, opsViewportClass), 1)
assert.match(primitiveSource, /child\.type === Fragment/)
assert.doesNotMatch(
  primitiveSource,
  /<template|<style|defineProps|defineEmits|\b(?:computed|reactive|ref|watch|onMounted)\s*\(/,
)
assert.doesNotMatch(primitiveSource, /\b(?:role|aria-|data-|tabindex|key)\b/)

const {Fragment, createApp, defineComponent, h, nextTick, ref, withDirectives} =
  integrationRequire("vue")
const items = ref([
  {key: "alpha", label: "Alpha", phase: "ready", busy: false},
  {key: "bravo", label: "Bravo", phase: "planning", busy: true},
])
const viewportClicks = []
const actionClicks = []
const directiveElements = new Map()
const directiveUpdates = new Map()
const callerDirective = {
  mounted(element, binding) {
    directiveElements.set(binding.value, element)
  },
  updated(element, binding) {
    directiveElements.set(binding.value, element)
    directiveUpdates.set(binding.value, (directiveUpdates.get(binding.value) ?? 0) + 1)
  },
}

const Contract = defineComponent({
  name: "CadenceOpsViewportMountedContract",
  setup() {
    return () =>
      h(
        "div",
        {id: "ops-viewport-list"},
        items.value.map((item) =>
          withDirectives(
            h(
              CadenceOpsViewport,
              {
                key: item.key,
                id: `ops-viewport-${item.key}`,
                class: "caller-first caller-second",
                "aria-busy": String(item.busy),
                "data-owner": item.key,
                "data-phase": item.phase,
                onClick: () => viewportClicks.push(item.key),
              },
              {
                default: () => [
                  `${item.label} `,
                  [
                    h(Fragment, null, [
                      h("span", {id: `ops-viewport-child-${item.key}`}, "child"),
                      [
                        h(Fragment, null, [
                          h(
                            "button",
                            {
                              id: `ops-viewport-action-${item.key}`,
                              type: "button",
                              onClick: () => actionClicks.push(item.key),
                            },
                            "act",
                          ),
                          ` ${item.phase}`,
                        ]),
                      ],
                    ]),
                  ],
                ],
              },
            ),
            [[callerDirective, item.key]],
          ),
        ),
      )
  },
})

const host = dom.window.document.querySelector("#ops-viewport-contract")
const app = createApp(Contract)
app.mount(host)
await flushVue(nextTick)

const capture = (key) => ({
  viewport: dom.window.document.querySelector(`#ops-viewport-${key}`),
  child: dom.window.document.querySelector(`#ops-viewport-child-${key}`),
  action: dom.window.document.querySelector(`#ops-viewport-action-${key}`),
})
const assertRetained = (key, retained) => {
  const current = capture(key)
  assert.strictEqual(current.viewport, retained.viewport)
  assert.strictEqual(current.child, retained.child)
  assert.strictEqual(current.action, retained.action)
}
const alpha = capture("alpha")
const bravo = capture("bravo")

for (const [key, retained] of [
  ["alpha", alpha],
  ["bravo", bravo],
]) {
  assert.equal(retained.viewport.tagName, "SECTION")
  assert.equal(retained.viewport.className, `${opsViewportClass} caller-first caller-second`)
  assert.equal(retained.viewport.hasAttribute("key"), false)
  assert.equal(retained.viewport.hasAttribute("role"), false)
  assert.strictEqual(directiveElements.get(key), retained.viewport)
  assert.strictEqual(retained.viewport.children[0], retained.child)
  assert.strictEqual(retained.viewport.children[1], retained.action)
  assert.deepEqual(
    [...retained.viewport.childNodes].map((node) => [node.nodeType, node.nodeName]),
    [
      [dom.window.Node.TEXT_NODE, "#text"],
      [dom.window.Node.ELEMENT_NODE, "SPAN"],
      [dom.window.Node.ELEMENT_NODE, "BUTTON"],
      [dom.window.Node.TEXT_NODE, "#text"],
    ],
  )
}

assert.deepEqual(elementAttributes(alpha.viewport), {
  "aria-busy": "false",
  class: `${opsViewportClass} caller-first caller-second`,
  "data-owner": "alpha",
  "data-phase": "ready",
  id: "ops-viewport-alpha",
})
assert.deepEqual(elementAttributes(bravo.viewport), {
  "aria-busy": "true",
  class: `${opsViewportClass} caller-first caller-second`,
  "data-owner": "bravo",
  "data-phase": "planning",
  id: "ops-viewport-bravo",
})

alpha.action.click()
assert.deepEqual(actionClicks, ["alpha"])
assert.deepEqual(viewportClicks, ["alpha"])
alpha.viewport.dispatchEvent(new dom.window.MouseEvent("click", {bubbles: true}))
assert.deepEqual(viewportClicks, ["alpha", "alpha"])

items.value = [
  {key: "bravo", label: "Bravo", phase: "complete", busy: false},
  {key: "charlie", label: "Charlie", phase: "planning", busy: true},
  {key: "alpha", label: "Alpha", phase: "ready", busy: false},
]
await flushVue(nextTick)

assert.deepEqual(
  [...dom.window.document.querySelector("#ops-viewport-list").children].map(({id}) => id),
  ["ops-viewport-bravo", "ops-viewport-charlie", "ops-viewport-alpha"],
)
assertRetained("alpha", alpha)
assertRetained("bravo", bravo)
assert.ok((directiveUpdates.get("bravo") ?? 0) > 0)
const charlie = capture("charlie")
assert.strictEqual(directiveElements.get("charlie"), charlie.viewport)

items.value = [
  {key: "charlie", label: "Charlie", phase: "complete", busy: false},
  {key: "alpha", label: "Alpha", phase: "ready", busy: false},
]
await flushVue(nextTick)

assert.deepEqual(
  [...dom.window.document.querySelector("#ops-viewport-list").children].map(({id}) => id),
  ["ops-viewport-charlie", "ops-viewport-alpha"],
)
assertRetained("alpha", alpha)
assertRetained("charlie", charlie)
assert.equal(bravo.viewport.isConnected, false)
assert.equal(bravo.child.isConnected, false)
assert.equal(bravo.action.isConnected, false)

assert.doesNotThrow(() => app.unmount())
console.log(`ops_viewport_migration_test passed (${scenarios.length} exact-DOM scenarios)`)
