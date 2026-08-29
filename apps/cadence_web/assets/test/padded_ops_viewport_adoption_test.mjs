#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

import {opsViewportCallerNames} from "./ops_viewport_test_support.mjs"
import {
  paddedOpsViewportCallerNames,
  paddedOpsViewportMigrations,
  paddedOpsViewportMigrationFor,
  paddedOpsViewportNativeClass,
  paddedOpsViewportPredecessorCommit,
  paddedOpsViewportSha256,
  peelPaddedOpsViewport,
} from "./padded_ops_viewport_test_support.mjs"
import {
  elementAttributes,
  expectedNodeVersion,
  flushVue,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"

const scenarios = Object.freeze([
  "all 222 predecessor SFCs classify into exactly the two padded native root boundaries",
  "git show preserves both predecessor byte lengths and full SHA-256 values",
  "both adopted callers reconstruct the exact current predecessor bytes",
  "only the two-file adoption extends the frozen 17-caller Ops viewport cohort",
  "the existing primitive remains byte-identical to the current predecessor",
  "both production-compiled callers preserve exact native p-6 DOM against compiled predecessors",
  "caller root, action, and keyed list identities survive reorder, insert, and remove updates",
])

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `padded Ops viewport contracts use pinned Node ${expectedNodeVersion}`,
)
assert.equal(scenarios.length, 7)
assert.equal(paddedOpsViewportMigrations.length, 2)
assert.deepEqual(paddedOpsViewportCallerNames, [
  "OpsDashboardShare.vue",
  "OpsDashboardSnapshot.vue",
])
assert.throws(
  () => paddedOpsViewportMigrationFor("UnknownPaddedViewport.vue"),
  /audited padded Ops viewport caller/,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const primitiveRepositoryPath =
  "apps/cadence_web/assets/vue/ui/components/CadenceOpsViewport.vue"
const occurrences = (source, fragment) => source.split(fragment).length - 1
const git = (...args) =>
  execFileSync("git", ["-C", repositoryRoot, ...args], {encoding: "utf8"})
const predecessorSource = (repositoryPath) =>
  git("show", `${paddedOpsViewportPredecessorCommit}:${repositoryPath}`)

assert.equal(git("cat-file", "-t", paddedOpsViewportPredecessorCommit).trim(), "commit")

const predecessorVuePaths = git(
  "ls-tree",
  "-r",
  "--name-only",
  paddedOpsViewportPredecessorCommit,
  "apps/cadence_web/assets/vue",
)
  .trim()
  .split("\n")
  .filter((sourcePath) => sourcePath.endsWith(".vue"))
  .sort()
const auditedVuePaths = predecessorVuePaths.filter(
  (sourcePath) => sourcePath !== primitiveRepositoryPath,
)

assert.equal(predecessorVuePaths.length, 223, "the predecessor contains 223 total Vue SFCs")
assert.equal(
  auditedVuePaths.length,
  222,
  "the exhaustive adoption inventory audits every non-primitive Vue SFC",
)

const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const exactCohort = []
let renderOnlyCount = 0
let templateCount = 0
let nativeSectionRootCount = 0

const rootElement = (template) => {
  const significant = template.ast.children.filter(
    (node) => node.type !== 3 && !(node.type === 2 && node.content.trim() === ""),
  )
  return significant.length === 1 && significant[0].type === 1 ? significant[0] : null
}

for (const repositoryPath of auditedVuePaths) {
  const source = predecessorSource(repositoryPath)
  const parsed = parse(source, {filename: repositoryPath})

  assert.deepEqual(parsed.errors, [], `${repositoryPath} parses in the frozen inventory`)
  if (!parsed.descriptor.template) {
    renderOnlyCount += 1
    continue
  }

  templateCount += 1
  const root = rootElement(parsed.descriptor.template)
  if (!root || root.tag !== "section") continue

  nativeSectionRootCount += 1
  const staticClass = root.props.find((prop) => prop.type === 6 && prop.name === "class")
  const id = root.props.find(
    (prop) =>
      (prop.type === 6 && prop.name === "id") ||
      (prop.type === 7 &&
        prop.name === "bind" &&
        prop.arg?.type === 4 &&
        prop.arg.content === "id"),
  )

  if (id && staticClass?.value?.content === paddedOpsViewportNativeClass) {
    exactCohort.push(repositoryPath)
  }
}

assert.equal(renderOnlyCount, 20)
assert.equal(templateCount, 202)
assert.equal(nativeSectionRootCount, 24)
assert.equal(renderOnlyCount + templateCount, auditedVuePaths.length)
assert.deepEqual(
  exactCohort,
  paddedOpsViewportMigrations.map(({repositoryPath}) => repositoryPath),
  "only the exact two native SECTION roots own an id and the ordered padded class",
)

for (const migration of paddedOpsViewportMigrations) {
  const predecessor = predecessorSource(migration.repositoryPath)
  const current = await readFile(resolve(repositoryRoot, migration.repositoryPath), "utf8")
  const reconstructed = peelPaddedOpsViewport(current, migration.file)

  assert.equal(migration.predecessorCommit, paddedOpsViewportPredecessorCommit)
  assert.equal(Buffer.byteLength(predecessor), migration.predecessorByteLength)
  assert.equal(paddedOpsViewportSha256(predecessor), migration.predecessorSha256)
  assert.equal(reconstructed, predecessor, `${migration.file} reconstructs byte-for-byte`)
  assert.equal(paddedOpsViewportSha256(reconstructed), migration.predecessorSha256)
  assert.equal(occurrences(current, migration.opening), 1)
  assert.equal(occurrences(current, migration.closing), 1)
  assert.equal(occurrences(current, paddedOpsViewportNativeClass), 0)
}

const currentVueSources = await Promise.all(
  predecessorVuePaths.map(async (repositoryPath) => ({
    file: repositoryPath.slice("apps/cadence_web/assets/vue/".length),
    source: await readFile(resolve(repositoryRoot, repositoryPath), "utf8"),
  })),
)
const expectedCurrentCallers = [...opsViewportCallerNames, ...paddedOpsViewportCallerNames].sort()

assert.deepEqual(
  currentVueSources
    .filter(({source}) => /^import CadenceOpsViewport\b/m.test(source))
    .map(({file}) => file)
    .sort(),
  expectedCurrentCallers,
)
assert.equal(
  currentVueSources.reduce(
    (total, {source}) => total + (source.match(/<CadenceOpsViewport\b/g)?.length ?? 0),
    0,
  ),
  19,
)
assert.equal(
  currentVueSources.reduce(
    (total, {source}) => total + (source.match(/<\/CadenceOpsViewport>/g)?.length ?? 0),
    0,
  ),
  19,
)

const primitiveSource = await readFile(resolve(repositoryRoot, primitiveRepositoryPath), "utf8")
assert.equal(primitiveSource, predecessorSource(primitiveRepositoryPath))

const dom = installDom(
  '<div id="share-current"></div><div id="share-predecessor"></div>' +
    '<div id="snapshot-current"></div><div id="snapshot-predecessor"></div>',
)
for (const globalName of ["Document", "ShadowRoot"]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const compileModule = (source, filename, localModules = new Map()) => {
  const parsed = parse(source, {filename})
  assert.deepEqual(parsed.errors, [], `${filename} parses for production compilation`)

  const compiled = compileScript(parsed.descriptor, {
    id: `padded-ops-viewport-${filename.split("/").at(-1)}`,
    inlineTemplate: parsed.descriptor.template !== null,
  }).content
  const transformed = transformSync(compiled, {
    format: "cjs",
    loader: "ts",
    platform: "node",
    target: "node24",
  })
  const loadedModule = {exports: {}}
  const localRequire = (specifier) => localModules.get(specifier) ?? integrationRequire(specifier)

  new Function("require", "module", "exports", transformed.code)(
    localRequire,
    loadedModule,
    loadedModule.exports,
  )
  return loadedModule.exports
}

const primitiveModule = compileModule(primitiveSource, primitiveRepositoryPath)
const localModules = new Map([
  ["./ui/components/CadenceOpsViewport.vue", primitiveModule],
])
const {createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")

const mountedParity = async ({
  migration,
  propName,
  initial,
  updated,
  currentHost,
  predecessorHost,
  listSelector,
  labelSelector,
  retainedLabel,
  removedLabel,
  expectedLabels,
  actionSelector,
}) => {
  const currentSource = await readFile(resolve(repositoryRoot, migration.repositoryPath), "utf8")
  const predecessor = predecessorSource(migration.repositoryPath)
  const currentComponent = compileModule(currentSource, migration.repositoryPath, localModules).default
  const predecessorComponent = compileModule(predecessor, migration.repositoryPath).default
  const currentModel = ref(initial)
  const predecessorModel = ref(structuredClone(initial))
  const harness = (name, component, model) =>
    defineComponent({
      name,
      setup() {
        return () => h(component, {[propName]: model.value})
      },
    })
  const currentApp = createApp(harness("CurrentPaddedViewport", currentComponent, currentModel))
  const predecessorApp = createApp(
    harness("PredecessorPaddedViewport", predecessorComponent, predecessorModel),
  )

  currentApp.mount(dom.window.document.querySelector(currentHost))
  predecessorApp.mount(dom.window.document.querySelector(predecessorHost))
  await flushVue(nextTick)

  const currentRoot = dom.window.document.querySelector(`${currentHost} > section`)
  const predecessorRoot = dom.window.document.querySelector(`${predecessorHost} > section`)
  const currentAction = currentRoot.querySelector(actionSelector)
  const currentList = currentRoot.querySelector(listSelector)
  const initialItems = new Map(
    [...currentList.children].map((element) => [
      element.querySelector(labelSelector).textContent.trim(),
      element,
    ]),
  )

  assert.equal(currentRoot.tagName, "SECTION")
  assert.deepEqual(elementAttributes(currentRoot), {
    class: paddedOpsViewportNativeClass,
    id: initial.id,
  })
  assert.equal(currentRoot.outerHTML, predecessorRoot.outerHTML)
  assert.equal(currentRoot.children.length, 1)
  assert.ok(currentAction instanceof dom.window.HTMLAnchorElement)
  assert.equal(currentAction.hasAttribute("key"), false)
  assert.ok([...currentList.children].every((element) => !element.hasAttribute("key")))

  currentModel.value = updated
  predecessorModel.value = structuredClone(updated)
  await flushVue(nextTick)

  const updatedCurrentRoot = dom.window.document.querySelector(`${currentHost} > section`)
  const updatedPredecessorRoot = dom.window.document.querySelector(`${predecessorHost} > section`)
  const updatedItems = new Map(
    [...updatedCurrentRoot.querySelector(listSelector).children].map((element) => [
      element.querySelector(labelSelector).textContent.trim(),
      element,
    ]),
  )

  assert.strictEqual(updatedCurrentRoot, currentRoot)
  assert.strictEqual(updatedCurrentRoot.querySelector(actionSelector), currentAction)
  assert.strictEqual(updatedItems.get(retainedLabel), initialItems.get(retainedLabel))
  assert.equal(initialItems.get(removedLabel).isConnected, false)
  assert.deepEqual([...updatedItems.keys()], expectedLabels)
  assert.equal(updatedCurrentRoot.outerHTML, updatedPredecessorRoot.outerHTML)

  currentApp.unmount()
  predecessorApp.unmount()
}

const share = {
  id: "dashboard-share-page",
  eyebrow: "Authenticated mission share",
  title: "Dashboard context is ready",
  restriction: {
    prefix: "Restricted to members. It declares",
    visibility_id: "dashboard-share-visibility",
    visibility: "mission",
    suffix: "and preserves selectors.",
  },
  context: {
    id: "dashboard-share-context",
    entries: [
      {key: "spacecraft", value: "Odyssey"},
      {key: "range", value: "last-15-minutes"},
    ],
  },
  action: {
    id: "dashboard-share-open-dashboard",
    label: "Open live dashboard",
    href: "/missions/mission-1/ops/dashboards/dashboard-1",
  },
}
const updatedShare = {
  ...share,
  context: {
    ...share.context,
    entries: [
      {key: "range", value: "last-30-minutes"},
      {key: "source", value: "telemetry"},
    ],
  },
}

await mountedParity({
  migration: paddedOpsViewportMigrations[0],
  propName: "share",
  initial: share,
  updated: updatedShare,
  currentHost: "#share-current",
  predecessorHost: "#share-predecessor",
  listSelector: "#dashboard-share-context",
  labelSelector: "dt",
  retainedLabel: "range",
  removedLabel: "spacecraft",
  expectedLabels: ["range", "source"],
  actionSelector: "#dashboard-share-open-dashboard",
})

const snapshot = {
  id: "dashboard-snapshot-page",
  eyebrow: "Read-only snapshot",
  name: "Mission health",
  policy: {id: "dashboard-snapshot-policy", text: "Definition version 4"},
  warning: "Definition and selectors are immutable.",
  definition: {
    id: "dashboard-snapshot-definition",
    items: [
      {label: "Widgets", value: 4},
      {label: "Captured selectors", value: 2},
      {label: "Schema", value: "v1"},
    ],
  },
  action: {
    id: "dashboard-snapshot-open-current",
    label: "Open current dashboard",
    href: "/missions/mission-1/ops/dashboards/dashboard-1",
  },
}
const updatedSnapshot = {
  ...snapshot,
  definition: {
    ...snapshot.definition,
    items: [
      {label: "Schema", value: "v1"},
      {label: "Signals", value: 12},
    ],
  },
}

await mountedParity({
  migration: paddedOpsViewportMigrations[1],
  propName: "snapshot",
  initial: snapshot,
  updated: updatedSnapshot,
  currentHost: "#snapshot-current",
  predecessorHost: "#snapshot-predecessor",
  listSelector: "#dashboard-snapshot-definition",
  labelSelector: ".hud-label",
  retainedLabel: "Schema",
  removedLabel: "Widgets",
  expectedLabels: ["Schema", "Signals"],
  actionSelector: "#dashboard-snapshot-open-current",
})

console.log(`padded_ops_viewport_adoption_test passed (${scenarios.length} scenarios)`)
