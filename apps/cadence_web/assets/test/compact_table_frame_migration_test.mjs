#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {createHash} from "node:crypto"
import {readFile, readdir} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

import {
  compactHeaderBodyFramePath,
} from "./compact_page_header_body_frame_test_support.mjs"
import {
  compactTableFrameImport,
  compactTableFrameMigrations,
  compactTableFramePredecessor,
  compactTableNativeExclusions,
  peelCompactTableFrames,
  predecessorCadenceTableFrameCallers,
} from "./compact_table_frame_test_support.mjs"
import {opsListBodyFramePath} from "./ops_list_body_frame_test_support.mjs"
import {narrowFormPageFramePath} from "./narrow_form_page_frame_test_support.mjs"
import {
  peelCadenceDefinitionListPanelBeforeOlderLayers,
} from "./definition_list_panel_test_support.mjs"
import {
  elementAttributes,
  expectedNodeVersion,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `compact-table contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const primitivePath = resolve(vueDirectory, "ui/components/CadenceTableFrame.vue")
const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const occurrences = (source, fragment) => source.split(fragment).length - 1
const lineOccurrences = (source, line) =>
  source.split("\n").filter((candidate) => candidate === line).length
const git = (...args) =>
  execFileSync("git", ["-C", repositoryRoot, ...args], {encoding: "utf8"})

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

assert.equal(git("cat-file", "-t", compactTableFramePredecessor).trim(), "commit")
assert.equal(compactTableFrameMigrations.length, 3, "three callers own the compact cohort")
assert.equal(
  compactTableFrameMigrations.reduce((total, entry) => total + entry.boundaries.length, 0),
  4,
  "the frozen migration ledger has exactly four native-table boundaries",
)
assert.equal(compactTableNativeExclusions.length, 3, "all three native-table exclusions are frozen")

const currentVuePaths = (await walkVueFiles(vueDirectory))
  .map((path) => path.slice(repositoryRoot.length + 1))
  .sort()
const predecessorVuePaths = git(
  "ls-tree",
  "-r",
  "--name-only",
  compactTableFramePredecessor,
  "apps/cadence_web/assets/vue",
)
  .trim()
  .split("\n")
  .filter((path) => path.endsWith(".vue"))
  .sort()
const allowedPostPredecessorVuePaths = Object.freeze([
  compactHeaderBodyFramePath,
  "apps/cadence_web/assets/vue/ui/components/CadenceDefinitionListPanel.vue",
  "apps/cadence_web/assets/vue/ui/components/CadenceDiagnosticsSectionFrame.vue",
  narrowFormPageFramePath,
  opsListBodyFramePath,
  "apps/cadence_web/assets/vue/ui/components/CadenceOpsListFrame.vue",
  "apps/cadence_web/assets/vue/ui/components/CadenceStatTile.vue",
])
const postPredecessorVuePaths = currentVuePaths.filter(
  (path) => !predecessorVuePaths.includes(path),
)

assert.deepEqual(
  postPredecessorVuePaths,
  allowedPostPredecessorVuePaths,
  "exactly seven explicitly allowed SFCs were added after the frozen predecessor",
)
assert.deepEqual(
  currentVuePaths,
  [...predecessorVuePaths, ...allowedPostPredecessorVuePaths].sort(),
  "the audit covers the full current tree: every frozen predecessor SFC plus seven allowed additions",
)
assert.equal(predecessorVuePaths.length, 222, "the frozen audit covers exactly 222 Vue SFCs")

const predecessorSources = new Map(
  predecessorVuePaths.map((path) => [
    path,
    git("show", `${compactTableFramePredecessor}:${path}`),
  ]),
)
const currentSources = new Map(
  await Promise.all(
    currentVuePaths.map(async (path) => [path, await readFile(resolve(repositoryRoot, path), "utf8")]),
  ),
)

const frozenNativeLedger = [
  ...compactTableFrameMigrations.flatMap((migration) =>
    migration.boundaries.map((entry) => ({
      path: migration.repositoryPath,
      opening: entry.nativeOpening.trimStart(),
      closing: entry.nativeClosing.trimStart(),
      classification: "migrate-literal-compact",
    })),
  ),
  ...compactTableNativeExclusions.map((entry) => ({
    path: entry.repositoryPath,
    opening: entry.opening.trimStart(),
    closing: entry.closing.trimStart(),
    classification: entry.classification,
  })),
].sort((left, right) =>
  `${left.path}\0${left.opening}`.localeCompare(`${right.path}\0${right.opening}`),
)

const nativeInventory = (sources) =>
  [...sources]
    .flatMap(([path, source]) =>
      (source.match(/<table\b[^>]*>/gs) ?? []).map((opening) => ({
        path,
        opening: opening.trimStart(),
      })),
    )
    .sort((left, right) =>
      `${left.path}\0${left.opening}`.localeCompare(`${right.path}\0${right.opening}`),
    )

assert.deepEqual(
  nativeInventory(predecessorSources),
  frozenNativeLedger.map(({path, opening}) => ({path, opening})),
  "all predecessor native-table openings are either migrated or explicitly excluded",
)
assert.equal(
  [...predecessorSources.values()].reduce(
    (total, source) => total + (source.match(/<\/table>/g)?.length ?? 0),
    0,
  ),
  7,
  "every predecessor native-table opening has one closing",
)

for (const entry of [...compactTableFrameMigrations, ...compactTableNativeExclusions]) {
  const predecessor = predecessorSources.get(entry.repositoryPath)
  assert.equal(Buffer.byteLength(predecessor), entry.predecessorByteLength)
  assert.equal(sha256(predecessor), entry.predecessorSha256)
}

for (const migration of compactTableFrameMigrations) {
  const predecessor = predecessorSources.get(migration.repositoryPath)
  const current = currentSources.get(migration.repositoryPath)

  for (const [index, entry] of migration.boundaries.entries()) {
    assert.equal(
      occurrences(predecessor, entry.nativeOpening),
      1,
      `${migration.file} frozen native opening ${index + 1}`,
    )
    assert.equal(
      lineOccurrences(predecessor, entry.nativeClosing),
      1,
      `${migration.file} frozen native closing ${index + 1}`,
    )
  }
  assert.equal(occurrences(current, compactTableFrameImport), 1)
  assert.equal(current.match(/^import CadenceTableFrame\b/gm)?.length, 1)
  assert.equal(current.match(/<CadenceTableFrame\b/g)?.length, migration.boundaries.length)
  assert.equal(current.match(/<\/CadenceTableFrame>/g)?.length, migration.boundaries.length)
  assert.equal(
    peelCompactTableFrames(
      peelCadenceDefinitionListPanelBeforeOlderLayers(current, migration.file),
      migration.file,
    ),
    predecessor,
    `${migration.file} inversely reconstructs ${compactTableFramePredecessor} byte-for-byte`,
  )
}

for (const exclusion of compactTableNativeExclusions) {
  const predecessor = predecessorSources.get(exclusion.repositoryPath)
  const current = currentSources.get(exclusion.repositoryPath)
  assert.equal(current, predecessor, `${exclusion.file} exclusion bytes remain untouched`)
  assert.equal(occurrences(predecessor, exclusion.opening), 1)
  assert.equal(occurrences(predecessor, exclusion.closing), 1)
  if (exclusion.producerPath) {
    const producer = await readFile(resolve(repositoryRoot, exclusion.producerPath), "utf8")
    assert.ok(
      occurrences(producer, exclusion.producerFragment) >= 1,
      `${exclusion.file} keeps its audited dynamic compact producer`,
    )
  }
}

assert.deepEqual(
  nativeInventory(currentSources),
  compactTableNativeExclusions
    .map(({repositoryPath: path, opening}) => ({path, opening: opening.trimStart()}))
    .sort((left, right) =>
      `${left.path}\0${left.opening}`.localeCompare(`${right.path}\0${right.opening}`),
    ),
  "only the three explicitly excluded native tables remain",
)

const currentFrameCallers = [...currentSources]
  .filter(([, source]) => /<CadenceTableFrame\b/.test(source))
  .map(([path]) => path.split("/").at(-1))
  .sort()
const expectedFrameCallers = [
  ...predecessorCadenceTableFrameCallers,
  ...compactTableFrameMigrations.map(({file}) => file),
].sort()

assert.deepEqual(currentFrameCallers, expectedFrameCallers)
assert.equal(
  [...currentSources.values()].reduce(
    (total, source) => total + (source.match(/^import CadenceTableFrame\b/gm)?.length ?? 0),
    0,
  ),
  18,
  "the source tree has exactly 18 audited TableFrame importers",
)
assert.equal(
  [...currentSources.values()].reduce(
    (total, source) => total + (source.match(/<CadenceTableFrame\b/g)?.length ?? 0),
    0,
  ),
  23,
  "the source tree has 19 predecessor frames plus the four compact boundaries",
)
assert.equal(
  [...currentSources.values()].reduce(
    (total, source) => total + (source.match(/<\/CadenceTableFrame>/g)?.length ?? 0),
    0,
  ),
  23,
)

const literalCompactVariants = [...currentSources]
  .flatMap(([path, source]) =>
    [...source.matchAll(/<CadenceTableFrame\b[^>]*\bclass="(table-(?:sm|xs))"[^>]*>/g)].map(
      ([opening, variant]) => ({path, opening: opening.trimStart(), variant}),
    ),
  )
  .sort((left, right) =>
    `${left.path}\0${left.opening}`.localeCompare(`${right.path}\0${right.opening}`),
  )

assert.deepEqual(
  literalCompactVariants.map(({path, variant}) => ({path, variant})),
  compactTableFrameMigrations
    .flatMap((migration) =>
      migration.boundaries.map(({componentOpening}) => ({
        path: migration.repositoryPath,
        variant: componentOpening.match(/class="(table-(?:sm|xs))"/)[1],
      })),
    )
    .sort((left, right) =>
      `${left.path}\0${left.variant}`.localeCompare(`${right.path}\0${right.variant}`),
    ),
  "table-sm and table-xs are caller-owned variants on the same primitive",
)

const primitiveSource = await readFile(primitivePath, "utf8")
assert.match(primitiveSource, /h\(\s*"table"/)
assert.equal(occurrences(primitiveSource, '"table"'), 2)
assert.doesNotMatch(primitiveSource, /table-(?:sm|xs)/)

const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
for (const migration of compactTableFrameMigrations) {
  const componentPath = resolve(repositoryRoot, migration.repositoryPath)
  const parsed = parse(currentSources.get(migration.repositoryPath), {filename: componentPath})
  assert.deepEqual(parsed.errors, [], `${migration.file} parses as an actual SFC`)
  assert.ok(parsed.descriptor.scriptSetup)
  assert.ok(parsed.descriptor.template)
  assert.doesNotThrow(() =>
    compileScript(parsed.descriptor, {
      id: `compact-table-${migration.file}`,
      inlineTemplate: true,
    }),
  )
}

const dom = installDom(
  '<div id="compact-frame-contract"></div><div id="compact-native-contract"></div>',
)
const parsedPrimitive = parse(primitiveSource, {filename: primitivePath})
assert.deepEqual(parsedPrimitive.errors, [])
const compiledPrimitive = compileScript(parsedPrimitive.descriptor, {
  id: "compact-table-frame-mounted-contract",
})
const {transformSync} = integrationRequire("esbuild")
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
const CadenceTableFrame = primitiveModule.exports.default
const {
  Fragment,
  createApp,
  defineComponent,
  h,
  nextTick,
  reactive,
  ref,
  withDirectives,
} = integrationRequire("vue")

const rootDirective = {
  mounted(element, binding) {
    assert.equal(element.tagName, "TABLE")
    element.dataset.compactDirective = binding.value
  },
  updated(element, binding) {
    assert.equal(element.tagName, "TABLE")
    element.dataset.compactDirective = binding.value
  },
}

const contractState = () => ({
  directiveValue: ref("mounted"),
  reverseTables: ref(false),
  rows: ref([
    {key: "alpha", label: "Alpha"},
    {key: "bravo", label: "Bravo"},
  ]),
  values: reactive({alpha: "A", bravo: "B"}),
  buttonClicks: [],
  tableClicks: 0,
})

const renderContractTables = (root, state) => {
  const table = (attrs, children) =>
    root === "native"
      ? h("table", {...attrs, class: ["table", attrs.class]}, children())
      : h(CadenceTableFrame, attrs, {default: children})

  const small = table(
    {
      key: "small",
      id: "admin-runtime-decisions-table",
      class: "table-sm",
      "aria-label": "Runtime decisions",
      "data-owner": "caller",
      onClick: () => {
        state.tableClicks += 1
      },
    },
    () => [
      h(Fragment, null, [
        [h("thead", {id: "compact-head"}, [h("tr", {key: "heading"}, [h("th", "Name"), h("th", "Control")])])],
        [
          h(
            "tbody",
            {id: "compact-stream", "phx-update": "stream"},
            state.rows.value.map((row) =>
              h("tr", {id: `compact-row-${row.key}`, key: row.key}, [
                h("td", {id: `compact-label-${row.key}`}, row.label),
                h("td", [
                  h("input", {
                    id: `compact-control-${row.key}`,
                    key: `input-${row.key}`,
                    name: `compact[${row.key}]`,
                    value: state.values[row.key],
                    onInput: (event) => {
                      state.values[row.key] = event.currentTarget.value
                    },
                  }),
                  h(
                    "button",
                    {
                      id: `compact-action-${row.key}`,
                      key: `button-${row.key}`,
                      type: "button",
                      onClick: () => state.buttonClicks.push(row.key),
                    },
                    `Select ${row.label}`,
                  ),
                ]),
              ]),
            ),
          ),
        ],
        h("tfoot", {id: "compact-foot"}, [h("tr", [h("td", {colspan: "2"}, "Caller footer")])]),
      ]),
    ],
  )

  const extraSmall = withDirectives(
    table(
      {
        key: "extra-small",
        id: "telemetry-explore-samples",
        class: "table-xs",
        "data-sample-table": "true",
      },
      () => [
        h(Fragment, null, [
          [h("thead", [h("tr", [h("th", "Sample")])])],
          h("tbody", {id: "telemetry-samples-body"}, [
            h("tr", {id: "telemetry-empty-row", key: "empty"}, [
              h("td", [
                h(
                  "a",
                  {
                    id: "telemetry-empty-link",
                    href: "/missions/one/ops/explore?sample=none",
                    "data-phx-link": "redirect",
                    "data-phx-link-state": "push",
                  },
                  "No samples",
                ),
              ]),
            ]),
          ]),
        ]),
      ],
    ),
    [[rootDirective, state.directiveValue.value]],
  )

  return state.reverseTables.value ? [extraSmall, small] : [small, extraSmall]
}

const mountedContract = (root, state) =>
  defineComponent({
    name: root === "native" ? "NativeCompactTableContract" : "FrameCompactTableContract",
    setup() {
      return () => h("section", {id: `${root}-compact-tables`}, renderContractTables(root, state))
    },
  })

const frameState = contractState()
const nativeState = contractState()
const frameHost = dom.window.document.querySelector("#compact-frame-contract")
const nativeHost = dom.window.document.querySelector("#compact-native-contract")
const frameApp = createApp(mountedContract("frame", frameState))
const nativeApp = createApp(mountedContract("native", nativeState))
frameApp.mount(frameHost)
nativeApp.mount(nativeHost)

const frameSection = frameHost.firstElementChild
const nativeSection = nativeHost.firstElementChild
const smallTable = frameSection.querySelector("#admin-runtime-decisions-table")
const extraSmallTable = frameSection.querySelector("#telemetry-explore-samples")
assert.equal(smallTable.tagName, "TABLE")
assert.equal(extraSmallTable.tagName, "TABLE")
assert.equal(smallTable.className, "table table-sm")
assert.equal(extraSmallTable.className, "table table-xs")
assert.deepEqual(elementAttributes(smallTable), {
  "aria-label": "Runtime decisions",
  class: "table table-sm",
  "data-owner": "caller",
  id: "admin-runtime-decisions-table",
})
assert.deepEqual(elementAttributes(extraSmallTable), {
  class: "table table-xs",
  "data-compact-directive": "mounted",
  "data-sample-table": "true",
  id: "telemetry-explore-samples",
})
assert.deepEqual([...smallTable.childNodes].map((node) => node.nodeName), [
  "THEAD",
  "TBODY",
  "TFOOT",
])
assert.deepEqual([...extraSmallTable.childNodes].map((node) => node.nodeName), [
  "THEAD",
  "TBODY",
])
assert.equal(smallTable.querySelector("tbody").getAttribute("phx-update"), "stream")
assert.equal(
  frameSection.innerHTML.replace('id="frame-compact-tables"', 'id="native-compact-tables"'),
  nativeSection.innerHTML,
  "both production-frame variants match equivalent native tables exactly",
)

const alphaRow = frameSection.querySelector("#compact-row-alpha")
const bravoRow = frameSection.querySelector("#compact-row-bravo")
const alphaControl = frameSection.querySelector("#compact-control-alpha")
const bravoControl = frameSection.querySelector("#compact-control-bravo")
const alphaAction = frameSection.querySelector("#compact-action-alpha")
alphaAction.click()
assert.deepEqual(frameState.buttonClicks, ["alpha"])
assert.equal(frameState.tableClicks, 1)
alphaControl.value = "A2"
alphaControl.dispatchEvent(new dom.window.Event("input", {bubbles: true}))
await nextTick()
assert.equal(frameState.values.alpha, "A2")

frameState.rows.value = [
  {key: "bravo", label: "Bravo updated"},
  {key: "alpha", label: "Alpha updated"},
]
nativeState.rows.value = [
  {key: "bravo", label: "Bravo updated"},
  {key: "alpha", label: "Alpha updated"},
]
frameState.values.alpha = "A2"
nativeState.values.alpha = "A2"
frameState.reverseTables.value = true
nativeState.reverseTables.value = true
frameState.directiveValue.value = "updated"
nativeState.directiveValue.value = "updated"
await nextTick()

assert.strictEqual(frameSection.children[0], extraSmallTable)
assert.strictEqual(frameSection.children[1], smallTable)
assert.strictEqual(frameSection.querySelector("#compact-row-alpha"), alphaRow)
assert.strictEqual(frameSection.querySelector("#compact-row-bravo"), bravoRow)
assert.strictEqual(frameSection.querySelector("#compact-control-alpha"), alphaControl)
assert.strictEqual(frameSection.querySelector("#compact-control-bravo"), bravoControl)
assert.strictEqual(frameSection.querySelector("#compact-action-alpha"), alphaAction)
assert.deepEqual(
  [...smallTable.querySelectorAll("tbody > tr")].map((row) => row.id),
  ["compact-row-bravo", "compact-row-alpha"],
)
assert.equal(alphaControl.value, "A2")
assert.equal(extraSmallTable.dataset.compactDirective, "updated")
assert.equal(smallTable.className, "table table-sm")
assert.equal(extraSmallTable.className, "table table-xs")
assert.equal(
  frameSection.innerHTML.replace('id="frame-compact-tables"', 'id="native-compact-tables"'),
  nativeSection.innerHTML,
  "reorder and updates preserve exact native output",
)

frameApp.unmount()
nativeApp.unmount()
assert.equal(frameHost.children.length, 0)
assert.equal(nativeHost.children.length, 0)
dom.window.close()

console.log(
  "compact_table_frame_migration_test passed (222 SFC audit + 4 inverses + mounted sm/xs identity)",
)
