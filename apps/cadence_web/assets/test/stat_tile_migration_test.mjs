#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {createHash} from "node:crypto"
import {readFile, readdir} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

import {
  compactHeaderBodyFramePath,
  peelCadenceCompactPageHeaderBodyFrameBeforeOlderLayers,
} from "./compact_page_header_body_frame_test_support.mjs"
import {
  elementAttributes,
  expectedNodeVersion,
  flushVue,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"
import {
  peelCadenceStatTile,
  statTileCallerNames,
  statTileClass,
  statTileImport,
  statTileKnownExclusions,
  statTileLabelClass,
  statTileMigrations,
  statTilePredecessorCommit,
  statTileValueClass,
} from "./stat_tile_test_support.mjs"

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
const scenarios = Object.freeze([
  "the fixed 223-SFC predecessor and full 227-SFC current tree add only the audited primitives",
  "all predecessor SFCs classify into six exact shells and one frozen semantic exclusion",
  "all current SFCs parse and exactly six singular imports/openings replace the native cohort",
  "the fixed predecessor commit, Git blob, byte length, and SHA-256 are exact for every caller",
  "all six actual caller SFCs and their immediate predecessors parse and compile",
  "all six newest inverse peels reconstruct their predecessor source byte-for-byte",
  "a real current caller and compiled native predecessor render exact HTML and attributes",
  "the real caller preserves keyed tile-root and caller-owned value-p identity through reorder",
])

assert.equal(process.execPath, pinnedNode)
assert.equal(process.versions.node, expectedNodeVersion)
assert.equal(scenarios.length, 8)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const primitiveRepositoryPath =
  "apps/cadence_web/assets/vue/ui/components/CadenceStatTile.vue"
const definitionListPanelRepositoryPath =
  "apps/cadence_web/assets/vue/ui/components/CadenceDefinitionListPanel.vue"
const primitivePath = resolve(repositoryRoot, primitiveRepositoryPath)
const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const occurrences = (source, fragment) => source.split(fragment).length - 1
const git = (...args) =>
  execFileSync("git", ["-C", repositoryRoot, ...args], {encoding: "utf8"})
const gitShow = (repositoryPath) =>
  git("show", `${statTilePredecessorCommit}:${repositoryPath}`)

assert.equal(git("cat-file", "-t", statTilePredecessorCommit).trim(), "commit")
assert.equal(statTileMigrations.length, 6)
assert.equal(new Set(statTileCallerNames).size, 6)
assert.equal(statTileKnownExclusions.length, 1)

const walkVueFiles = async (directory) => {
  const entries = await readdir(directory, {withFileTypes: true})
  entries.sort((left, right) => left.name.localeCompare(right.name))
  const nested = await Promise.all(
    entries.map(async (entry) => {
      const entryPath = resolve(directory, entry.name)
      if (entry.isDirectory()) return walkVueFiles(entryPath)
      return entry.isFile() && entry.name.endsWith(".vue") ? [entryPath] : []
    }),
  )
  return nested.flat()
}

const predecessorVuePaths = git(
  "ls-tree",
  "-r",
  "--name-only",
  statTilePredecessorCommit,
  "apps/cadence_web/assets/vue",
)
  .trim()
  .split("\n")
  .filter((path) => path.endsWith(".vue"))
  .sort()
const currentVuePaths = (await walkVueFiles(vueDirectory))
  .map((path) => path.slice(repositoryRoot.length + 1))
  .sort()
const addedVuePaths = currentVuePaths.filter((path) => !predecessorVuePaths.includes(path))

assert.equal(predecessorVuePaths.length, 223, "the fixed predecessor retains 223 Vue SFCs")
assert.equal(currentVuePaths.length, 227, "the current-tree gate includes exactly 227 Vue SFCs")
assert.deepEqual(addedVuePaths, [
  compactHeaderBodyFramePath,
  definitionListPanelRepositoryPath,
  "apps/cadence_web/assets/vue/ui/components/CadenceOpsListFrame.vue",
  primitiveRepositoryPath,
])
assert.deepEqual(
  currentVuePaths,
  [
    ...predecessorVuePaths,
    compactHeaderBodyFramePath,
    definitionListPanelRepositoryPath,
    "apps/cadence_web/assets/vue/ui/components/CadenceOpsListFrame.vue",
    primitiveRepositoryPath,
  ].sort(),
  "the current inventory is every fixed predecessor SFC plus only the audited primitives",
)

// Install JSDOM before the first Vue runtime import or compiled-SFC evaluation.
const dom = installDom(
  '<main><div id="current-transport"></div><div id="native-transport"></div></main>',
)
for (const globalName of ["HTMLFormElement", "HTMLInputElement", "HTMLParagraphElement"]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const {parse: parseDom} = integrationRequire("@vue/compiler-dom")
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")

const elementChildren = (node) => node.children?.filter((child) => child.type === 1) ?? []
const staticAttribute = (node, name) =>
  node.props.find((property) => property.type === 6 && property.name === name)?.value?.content
const allElements = (root) => {
  const elements = []
  const visit = (node) => {
    if (node.type === 1) elements.push(node)
    for (const child of node.children ?? []) visit(child)
  }
  visit(root)
  return elements
}
const parseTemplate = (source, filename) => {
  const parsed = parse(source, {filename})
  assert.deepEqual(parsed.errors, [], `${filename} parses as an actual SFC`)
  return parsed.descriptor.template ? parseDom(parsed.descriptor.template.content) : null
}
const exactNativeTiles = (source, filename) => {
  const template = parseTemplate(source, filename)
  if (!template) return []
  return allElements(template).filter((node) => {
    const children = elementChildren(node)
    return (
      node.tag === "div" &&
      staticAttribute(node, "class") === statTileClass &&
      children.length === 2 &&
      children[0].tag === "p" &&
      staticAttribute(children[0], "class") === statTileLabelClass &&
      children[1].tag === "p" &&
      staticAttribute(children[1], "class") === statTileValueClass
    )
  })
}
const nativeClassNearVariants = (source, filename) => {
  const template = parseTemplate(source, filename)
  if (!template) return []
  return allElements(template).filter((node) => {
    const rootClass = staticAttribute(node, "class")
    return node.tag === "div" && rootClass?.startsWith(`${statTileClass} `)
  })
}
const componentTiles = (source, filename) => {
  const template = parseTemplate(source, filename)
  if (!template) return []
  return allElements(template).filter((node) => node.tag === "CadenceStatTile")
}

const predecessorSources = new Map()
const currentSources = new Map()
const predecessorCohort = []
const predecessorExclusions = []
const currentCohort = []
const currentNativeCohort = []
const currentExclusions = []

for (const repositoryPath of predecessorVuePaths) {
  const source = gitShow(repositoryPath)
  predecessorSources.set(repositoryPath, source)

  for (const _node of exactNativeTiles(source, repositoryPath)) {
    predecessorCohort.push(repositoryPath)
  }
  for (const node of nativeClassNearVariants(source, repositoryPath)) {
    predecessorExclusions.push({
      repositoryPath,
      class: staticAttribute(node, "class"),
    })
  }
}

for (const repositoryPath of currentVuePaths) {
  const source = await readFile(resolve(repositoryRoot, repositoryPath), "utf8")
  currentSources.set(repositoryPath, source)

  for (const _node of componentTiles(source, repositoryPath)) currentCohort.push(repositoryPath)
  for (const _node of exactNativeTiles(source, repositoryPath)) {
    currentNativeCohort.push(repositoryPath)
  }
  for (const node of nativeClassNearVariants(source, repositoryPath)) {
    currentExclusions.push({repositoryPath, class: staticAttribute(node, "class")})
  }
}

const expectedCallerPaths = statTileMigrations.map(({repositoryPath}) => repositoryPath).sort()
const expectedExclusions = [
  {
    repositoryPath: "apps/cadence_web/assets/vue/OpsDataSources.vue",
    class: `${statTileClass} text-right`,
  },
]

assert.deepEqual(predecessorCohort.sort(), expectedCallerPaths)
assert.deepEqual(predecessorExclusions, expectedExclusions)
assert.deepEqual(currentCohort.sort(), expectedCallerPaths)
assert.deepEqual(currentNativeCohort, [], "no seventh compatible native shell remains")
assert.deepEqual(currentExclusions, expectedExclusions, "the semantic near variant stays native")

assert.equal(
  [...currentSources.values()].reduce(
    (total, source) => total + (source.match(/^import CadenceStatTile\b/gm)?.length ?? 0),
    0,
  ),
  6,
)
assert.equal(
  [...currentSources.values()].reduce(
    (total, source) => total + (source.match(/<CadenceStatTile\b/g)?.length ?? 0),
    0,
  ),
  6,
)
assert.equal(
  [...currentSources.values()].reduce(
    (total, source) => total + (source.match(/<\/CadenceStatTile>/g)?.length ?? 0),
    0,
  ),
  6,
)

const compileOnly = (source, filename, id) => {
  const parsed = parse(source, {filename})
  assert.deepEqual(parsed.errors, [], `${filename} parses before compile`)
  const compiled = compileScript(parsed.descriptor, {id, inlineTemplate: true})
  if (parsed.descriptor.template) {
    assert.match(compiled.content, /render|_sfc_render/)
  } else {
    assert.ok(parsed.descriptor.script, `${filename} keeps its render-function script`)
    assert.match(compiled.content, /export default|defineComponent/)
  }
  return compiled.content
}

for (const entry of statTileMigrations) {
  const predecessor = predecessorSources.get(entry.repositoryPath)
  const current = currentSources.get(entry.repositoryPath)
  const compactHeaderBodyCompatibleCurrent =
    peelCadenceCompactPageHeaderBodyFrameBeforeOlderLayers(current, entry.file)
  const reconstructed = peelCadenceStatTile(compactHeaderBodyCompatibleCurrent, entry.file)

  assert.equal(entry.predecessorCommit, statTilePredecessorCommit)
  assert.equal(
    git("rev-parse", `${statTilePredecessorCommit}:${entry.repositoryPath}`).trim(),
    entry.predecessorBlobId,
  )
  assert.equal(Buffer.byteLength(predecessor), entry.predecessorByteLength)
  assert.equal(sha256(predecessor), entry.predecessorSha256)
  assert.equal(occurrences(current, statTileImport), 1)
  assert.equal(occurrences(current, entry.componentOpening), 1)
  assert.equal(occurrences(current, entry.componentLabel), 1)
  assert.equal(occurrences(current, entry.valueLine), 1)
  assert.equal(reconstructed, predecessor, `${entry.file} reconstructs byte-for-byte`)
  assert.equal(sha256(reconstructed), entry.predecessorSha256)

  compileOnly(current, entry.repositoryPath, `stat-tile-current-${entry.file}`)
  compileOnly(predecessor, entry.repositoryPath, `stat-tile-predecessor-${entry.file}`)
}

const exclusion = statTileKnownExclusions[0]
const predecessorExclusionSource = predecessorSources.get(exclusion.repositoryPath)
const currentExclusionSource = currentSources.get(exclusion.repositoryPath)
assert.equal(occurrences(predecessorExclusionSource, exclusion.opening), 1)
assert.equal(occurrences(currentExclusionSource, exclusion.opening), 1)
const extractExclusion = (source) => {
  const start = source.indexOf(exclusion.opening)
  const end = source.indexOf(exclusion.closing, start + exclusion.opening.length)
  assert.ok(end > start, "the frozen readiness-policy exclusion has its native closing")
  return source.slice(start, end + exclusion.closing.length)
}
assert.equal(
  extractExclusion(currentExclusionSource),
  extractExclusion(predecessorExclusionSource),
  "the known semantic exclusion remains byte-for-byte native",
)

const compileModule = (source, filename, id, moduleRequire) => {
  const compiledSource = compileOnly(source, filename, id)
  const transformed = transformSync(compiledSource, {
    format: "cjs",
    loader: "ts",
    platform: "node",
    target: "node24",
  })
  const loadedModule = {exports: {}}
  new Function("require", "module", "exports", transformed.code)(
    moduleRequire,
    loadedModule,
    loadedModule.exports,
  )
  return loadedModule.exports
}

const primitiveSource = currentSources.get(primitiveRepositoryPath)
const primitiveModule = compileModule(
  primitiveSource,
  primitivePath,
  "stat-tile-real-primitive",
  integrationRequire,
)
const {Fragment, createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")
const Passthrough = defineComponent({
  name: "StatTileCallerPassthrough",
  inheritAttrs: false,
  setup: (_props, {slots}) => () => h(Fragment, null, slots.default?.() ?? []),
})
const passthroughModule = {__esModule: true, default: Passthrough}
const callerRequire = (specifier) => {
  if (specifier === "vue") return integrationRequire("vue")
  if (specifier.endsWith("CadenceStatTile.vue")) return primitiveModule
  if (specifier.startsWith(".")) return passthroughModule
  return integrationRequire(specifier)
}

const realCallerEntry = statTileMigrations.find(({file}) => file === "CommsTransportShow.vue")
const currentCaller = compileModule(
  currentSources.get(realCallerEntry.repositoryPath),
  realCallerEntry.repositoryPath,
  "stat-tile-real-current-caller",
  callerRequire,
).default
const predecessorCaller = compileModule(
  predecessorSources.get(realCallerEntry.repositoryPath),
  realCallerEntry.repositoryPath,
  "stat-tile-real-native-caller",
  callerRequire,
).default

const summary = (id, label, value) => Object.freeze({id, label, value})
const initialSummaryTiles = Object.freeze([
  summary("transport-stat-alpha", "Alpha", "10"),
  summary("transport-stat-beta", "Beta", "20"),
  summary("transport-stat-gamma", "Gamma", "30"),
])
const updatedSummaryTiles = Object.freeze([
  summary("transport-stat-gamma", "Gamma updated", "31"),
  summary("transport-stat-alpha", "Alpha updated", "11"),
  summary("transport-stat-beta", "Beta updated", "21"),
])
const callerProps = (summaryTiles) => ({
  navigation: {breadcrumbs: []},
  transport: {
    display_name: "Transport",
    transport_id: "transport-one",
    origin_badge: {id: "transport-origin", label: "managed"},
    version: "v1",
    summary_tiles: summaryTiles,
    capability: {
      eyebrow: "Capability",
      endpoint: "Endpoint",
      description: "Description",
      kind: "managed",
      details: [],
      diagnostics: {
        id: "transport-diagnostics",
        json_id: "transport-diagnostics-json",
        label: "Diagnostics",
        json: "{}",
      },
    },
  },
  version_history: {id: "transport-versions", title: "Versions", rows: []},
})

const currentProps = ref(callerProps(initialSummaryTiles))
const nativeProps = ref(callerProps(initialSummaryTiles))
const CurrentHarness = defineComponent({
  name: "CurrentTransportStatTileHarness",
  setup: () => () => h(currentCaller, currentProps.value),
})
const NativeHarness = defineComponent({
  name: "NativeTransportStatTileHarness",
  setup: () => () => h(predecessorCaller, nativeProps.value),
})
const currentHost = dom.window.document.querySelector("#current-transport")
const nativeHost = dom.window.document.querySelector("#native-transport")
const currentApp = createApp(CurrentHarness)
const nativeApp = createApp(NativeHarness)
currentApp.mount(currentHost)
nativeApp.mount(nativeHost)
await flushVue(nextTick)

const exactRenderedTiles = (host) =>
  [...host.querySelectorAll("div")].filter((element) => element.className === statTileClass)
const renderedSnapshot = (host) =>
  exactRenderedTiles(host).map((element) => ({
    outerHTML: element.outerHTML,
    attributes: elementAttributes(element),
  }))

assert.deepEqual(renderedSnapshot(currentHost), renderedSnapshot(nativeHost))
assert.equal(exactRenderedTiles(currentHost).length, 3)

const originalCallerNodes = new Map(
  exactRenderedTiles(currentHost).map((tile) => [
    tile.id,
    {root: tile, label: tile.children[0], value: tile.children[1]},
  ]),
)

for (const tile of exactRenderedTiles(currentHost)) {
  assert.equal(tile.childNodes.length, 2)
  assert.equal(tile.children[0].className, statTileLabelClass)
  assert.equal(tile.children[1].className, statTileValueClass)
}

currentProps.value = callerProps(updatedSummaryTiles)
nativeProps.value = callerProps(updatedSummaryTiles)
await flushVue(nextTick)

assert.deepEqual(renderedSnapshot(currentHost), renderedSnapshot(nativeHost))
assert.deepEqual(exactRenderedTiles(currentHost).map((tile) => tile.id), [
  "transport-stat-gamma",
  "transport-stat-alpha",
  "transport-stat-beta",
])

for (const stat of updatedSummaryTiles) {
  const current = currentHost.querySelector(`#${stat.id}`)
  const original = originalCallerNodes.get(stat.id)
  assert.strictEqual(current, original.root, `${stat.id} real caller root identity survives`)
  assert.strictEqual(current.children[0], original.label, `${stat.id} real caller label identity survives`)
  assert.strictEqual(current.children[1], original.value, `${stat.id} real caller value identity survives`)
  assert.equal(current.children[0].textContent, stat.label)
  assert.equal(current.children[1].textContent, stat.value)
}

assert.doesNotThrow(() => currentApp.unmount())
assert.doesNotThrow(() => nativeApp.unmount())
dom.window.close()

console.log(
  `stat_tile_migration_test passed (${predecessorVuePaths.length} predecessor SFCs + ${currentVuePaths.length} current SFCs + 6 inverses + real caller identity)`,
)
