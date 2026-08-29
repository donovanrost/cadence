#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {createHash} from "node:crypto"
import {readFileSync} from "node:fs"
import {readFile, readdir} from "node:fs/promises"
import {dirname, extname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

import {
  definitionListPanelBoundaries,
  definitionListPanelCaller,
  definitionListPanelClass,
  definitionListPanelHeadingClass,
  definitionListPanelImport,
  definitionListPanelListClass,
  definitionListPanelPredecessorBlob,
  definitionListPanelPredecessorBytes,
  definitionListPanelPredecessorCommit,
  definitionListPanelPredecessorSha256,
  definitionListPanelPrimitiveRepositoryPath,
  definitionListPanelRepositoryPath,
  definitionListPanelSha256,
  peelCadenceDefinitionListPanel,
} from "./definition_list_panel_test_support.mjs"
import {
  elementAttributes,
  expectedNodeVersion,
  flushVue,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
const scenarios = Object.freeze([
  "the fixed 224-SFC predecessor and recursive 225-SFC current tree differ only by the primitive",
  "all current SFCs parse and compile with the actual pinned Vue compiler",
  "the predecessor tree classifies exactly two native shells and the current tree has no third",
  "the fixed predecessor commit, blob, byte length, and SHA-256 remain exact",
  "the primitive owns only section, h2, and dl with fixed classes and transparent attributes",
  "the caller keeps both ids, headings, keyed loops, native dt/dd nodes, data attributes, and values",
  "the Point, Selected Sample, and Source Context panels remain byte-identical nearby exclusions",
  "three divergent diagnostic articles, two WidgetForm fieldsets, four disclosures, four dashed empty states, and three Reka menu panels remain excluded",
  "the actual primitive and actual current OpsTelemetryExplore SFC mount after JSDOM globals",
  "the reconstructed immediate predecessor compiles and mounts through its actual local SFC graph",
  "current and native panels render exact HTML and attributes before and after reactive updates",
  "root, heading, dl, and keyed caller dt/dd identities survive value updates and reorder",
])

assert.equal(process.execPath, pinnedNode)
assert.equal(process.versions.node, expectedNodeVersion)
assert.equal(scenarios.length, 12)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const primitivePath = resolve(repositoryRoot, definitionListPanelPrimitiveRepositoryPath)
const callerPath = resolve(repositoryRoot, definitionListPanelRepositoryPath)
const occurrences = (source, fragment) => source.split(fragment).length - 1
const git = (...args) =>
  execFileSync("git", ["-C", repositoryRoot, ...args], {encoding: "utf8"})
const gitShow = (repositoryPath) =>
  git("show", `${definitionListPanelPredecessorCommit}:${repositoryPath}`)

assert.equal(git("cat-file", "-t", definitionListPanelPredecessorCommit).trim(), "commit")

const predecessorSource = gitShow(definitionListPanelRepositoryPath)
assert.equal(
  git("rev-parse", `${definitionListPanelPredecessorCommit}:${definitionListPanelRepositoryPath}`).trim(),
  definitionListPanelPredecessorBlob,
)
assert.equal(Buffer.byteLength(predecessorSource), definitionListPanelPredecessorBytes)
assert.equal(definitionListPanelSha256(predecessorSource), definitionListPanelPredecessorSha256)

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
  definitionListPanelPredecessorCommit,
  "apps/cadence_web/assets/vue",
)
  .trim()
  .split("\n")
  .filter((repositoryPath) => repositoryPath.endsWith(".vue"))
  .sort()
const currentVuePaths = (await walkVueFiles(vueDirectory))
  .map((filePath) => filePath.slice(repositoryRoot.length + 1))
  .sort()
const addedVuePaths = currentVuePaths.filter((path) => !predecessorVuePaths.includes(path))

assert.equal(predecessorVuePaths.length, 224, "the immediate predecessor freezes 224 SFCs")
assert.equal(currentVuePaths.length, 225, "the recursive current inventory includes 225 SFCs")
assert.deepEqual(addedVuePaths, [definitionListPanelPrimitiveRepositoryPath])
assert.deepEqual(
  currentVuePaths,
  [...predecessorVuePaths, definitionListPanelPrimitiveRepositoryPath].sort(),
  "the new primitive is the only current-tree addition",
)

const currentSources = new Map(
  await Promise.all(
    currentVuePaths.map(async (repositoryPath) => [
      repositoryPath,
      await readFile(resolve(repositoryRoot, repositoryPath), "utf8"),
    ]),
  ),
)
const currentCallerSource = currentSources.get(definitionListPanelRepositoryPath)
const primitiveSource = currentSources.get(definitionListPanelPrimitiveRepositoryPath)

assert.equal(occurrences(currentCallerSource, definitionListPanelImport), 1)
assert.equal(currentCallerSource.match(/^import CadenceDefinitionListPanel\b/gm)?.length, 1)
assert.equal(currentCallerSource.match(/<CadenceDefinitionListPanel\b/g)?.length, 2)
assert.equal(currentCallerSource.match(/<\/CadenceDefinitionListPanel>/g)?.length, 2)
assert.equal(peelCadenceDefinitionListPanel(currentCallerSource, definitionListPanelCaller), predecessorSource)

// Install JSDOM before the first Vue runtime import or compiled-SFC evaluation.
const dom = installDom(
  '<main><div id="primitive-panel"></div><div id="current-explore"></div><div id="native-explore"></div></main>',
)
for (const globalName of [
  "Document",
  "ShadowRoot",
  "HTMLFormElement",
  "HTMLInputElement",
  "HTMLSelectElement",
  "HTMLTextAreaElement",
  "HTMLOptionElement",
]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const {parse: parseDom} = integrationRequire("@vue/compiler-dom")
const {compileScript, compileTemplate, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")

const currentDescriptors = new Map()
for (const [repositoryPath, source] of currentSources) {
  const parsed = parse(source, {filename: repositoryPath})
  assert.deepEqual(parsed.errors, [], `${repositoryPath} parses as an actual current SFC`)
  currentDescriptors.set(repositoryPath, parsed.descriptor)

  if (parsed.descriptor.script || parsed.descriptor.scriptSetup) {
    const compiled = compileScript(parsed.descriptor, {
      id: `definition-list-current-${createHash("sha1").update(repositoryPath).digest("hex")}`,
      inlineTemplate: parsed.descriptor.template !== null,
    })
    assert.ok(compiled.content.length > 0, `${repositoryPath} compiles as an actual SFC`)
  } else {
    assert.ok(parsed.descriptor.template, `${repositoryPath} has executable SFC content`)
    const compiled = compileTemplate({
      id: `definition-list-template-${createHash("sha1").update(repositoryPath).digest("hex")}`,
      filename: repositoryPath,
      source: parsed.descriptor.template.content,
    })
    assert.deepEqual(compiled.errors, [], `${repositoryPath} template compiles`)
  }
}

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
const templateAst = (source, filename) => {
  const parsed = parse(source, {filename})
  assert.deepEqual(parsed.errors, [], `${filename} parses for structural inventory`)
  return parsed.descriptor.template ? parseDom(parsed.descriptor.template.content) : null
}
const exactNativePanels = (source, filename) => {
  const template = templateAst(source, filename)
  if (!template) return []
  return allElements(template).filter((node) => {
    const children = elementChildren(node)
    return (
      node.tag === "section" &&
      staticAttribute(node, "class") === definitionListPanelClass &&
      children.length === 2 &&
      children[0].tag === "h2" &&
      staticAttribute(children[0], "class") === definitionListPanelHeadingClass &&
      children[1].tag === "dl" &&
      staticAttribute(children[1], "class") === definitionListPanelListClass
    )
  })
}
const componentPanels = (source, filename) => {
  const template = templateAst(source, filename)
  if (!template) return []
  return allElements(template).filter((node) => node.tag === "CadenceDefinitionListPanel")
}

const predecessorCohort = []
for (const repositoryPath of predecessorVuePaths) {
  const source = gitShow(repositoryPath)
  for (const _panel of exactNativePanels(source, repositoryPath)) {
    predecessorCohort.push(repositoryPath)
  }
}
const currentNativeCohort = []
const currentComponentCohort = []
for (const [repositoryPath, source] of currentSources) {
  for (const _panel of exactNativePanels(source, repositoryPath)) {
    currentNativeCohort.push(repositoryPath)
  }
  for (const _panel of componentPanels(source, repositoryPath)) {
    currentComponentCohort.push(repositoryPath)
  }
}

assert.deepEqual(predecessorCohort, [
  definitionListPanelRepositoryPath,
  definitionListPanelRepositoryPath,
])
assert.deepEqual(currentNativeCohort, [], "no third compatible native shell remains")
assert.deepEqual(currentComponentCohort, [
  definitionListPanelRepositoryPath,
  definitionListPanelRepositoryPath,
])
assert.equal(
  [...currentSources.values()].reduce(
    (total, source) => total + (source.match(/^import CadenceDefinitionListPanel\b/gm)?.length ?? 0),
    0,
  ),
  1,
  "the full current tree has one singular primitive import",
)

const parsedPrimitive = parse(primitiveSource, {filename: primitivePath})
assert.deepEqual(parsedPrimitive.errors, [])
assert.ok(parsedPrimitive.descriptor.script)
assert.equal(parsedPrimitive.descriptor.script.lang, "ts")
assert.equal(parsedPrimitive.descriptor.scriptSetup, null)
assert.equal(parsedPrimitive.descriptor.template, null, "the primitive has no template anchors")
assert.equal(occurrences(primitiveSource, `h("section"`), 1)
assert.equal(occurrences(primitiveSource, `h("h2"`), 1)
assert.equal(occurrences(primitiveSource, `h("dl"`), 1)
assert.equal(occurrences(primitiveSource, definitionListPanelClass), 1)
assert.equal(occurrences(primitiveSource, definitionListPanelHeadingClass), 1)
assert.equal(occurrences(primitiveSource, definitionListPanelListClass), 1)
assert.match(primitiveSource, /inheritAttrs: false/)
assert.match(primitiveSource, /\.\.\.attrs, class: \[panelClass, attrs\.class\]/)
assert.match(primitiveSource, /slots\.heading\?\.\(\)/)
assert.match(primitiveSource, /slots\.default\?\.\(\)/)
assert.match(primitiveSource, /child\.type === Fragment/)
assert.match(primitiveSource, /cloneVNode\(child, \{key:/)
assert.doesNotMatch(
  primitiveSource,
  /<template|<section|<h2|<dl|<dt|<dd|<button|<a\b|<form|defineProps|defineEmits|\b(?:computed|reactive|ref|watch|onMounted)\s*\(/,
  "the primitive owns no extra DOM, caller rows, actions, events, props, or state",
)
assert.doesNotMatch(primitiveSource, /\b(?:id|aria-|data-|phx-|v-model|@click|@submit)\b/)

for (const entry of definitionListPanelBoundaries) {
  assert.equal(occurrences(currentCallerSource, entry.componentOpening), 1)
  assert.equal(occurrences(currentCallerSource, entry.nativeOpening), 0)
}
for (const fragment of [
  'id="telemetry-explore-context-card"',
  ':id="diagnostics.id"',
  '<template #heading>Context</template>',
  '<template #heading>Read Diagnostics</template>',
  '<template v-for="row in context_rows" :key="row.label">',
  '<template v-for="row in diagnostics.rows" :key="row.label">',
  '<dt class="text-base-content/60">{{ row.label }}</dt>',
  ':data-explore-context="row.label"',
  ':data-explore-diagnostics="row.label"',
  "{{ row.value }}",
]) {
  assert.ok(currentCallerSource.includes(fragment), `caller retains ${fragment}`)
}
assert.equal(
  currentCallerSource.match(/<dt class="text-base-content\/60">\{\{ row\.label \}\}<\/dt>/g)?.length,
  5,
  "all five caller-owned metadata label nodes remain native",
)
assert.equal(
  currentCallerSource.match(/<dd class="font-mono text-base-content break-all"/g)?.length,
  4,
  "the four literal-class metadata values remain native while Point keeps its dynamic class",
)

const predecessorLines = predecessorSource.match(/.*(?:\n|$)/g)
for (const [label, start, end] of [
  ["Point", 806, 881],
  ["Selected Sample", 883, 922],
  ["Source Context", 924, 961],
]) {
  const frozenSlice = predecessorLines.slice(start - 1, end).join("")
  assert.equal(occurrences(predecessorSource, frozenSlice), 1, `${label} predecessor slice is singular`)
  assert.equal(occurrences(currentCallerSource, frozenSlice), 1, `${label} remains byte-identical`)
}
for (const fragment of [
  '<form\n                v-if="authoring"',
  '@submit.prevent="addToDashboard"',
  'v-model="addToDashboardValues.dashboard_id"',
  'v-if="selected_sample"',
  '@click="clearSelectedSample"',
  ':data-explore-selected-sample-card="selected_sample.sample_id"',
  ':data-explore-source-state="source_context.state"',
  'v-for="action in source_context.actions"',
  'data-phx-link="redirect"',
]) {
  assert.ok(currentCallerSource.includes(fragment), `nearby exclusion retains ${fragment}`)
}

const divergentDiagnosticArticles = Object.freeze([
  Object.freeze({
    repositoryPath: "apps/cadence_web/assets/vue/OpsDashboardDiagnostics.vue",
    fragments: Object.freeze([
      '<article v-bind="props.presentation.detail.attrs">',
      '<dl v-bind="props.presentation.detail.selected.details.attrs">',
      'v-for="item in props.presentation.detail.selected.details.items"',
    ]),
  }),
  Object.freeze({
    repositoryPath: "apps/cadence_web/assets/vue/OpsCommands.vue",
    fragments: Object.freeze([
      'v-for="command in commands"',
      '<CadenceDetailsFrame class="xl:col-span-6 border-t border-base-300/50 pt-2">',
      '<dl class="mt-2 grid gap-2 text-xs sm:grid-cols-2 lg:grid-cols-4">',
    ]),
  }),
  Object.freeze({
    repositoryPath: "apps/cadence_web/assets/vue/OpsContactSchedule.vue",
    fragments: Object.freeze([
      'v-for="reservation in provider_reservations"',
      'v-if="reservation.diagnostics"',
      '<dl class="mt-3 grid gap-2 font-mono text-[0.65rem] text-base-content/55">',
    ]),
  }),
])
for (const exclusion of divergentDiagnosticArticles) {
  const source = currentSources.get(exclusion.repositoryPath)
  assert.equal(source, gitShow(exclusion.repositoryPath), `${exclusion.repositoryPath} stays native`)
  for (const fragment of exclusion.fragments) assert.equal(occurrences(source, fragment), 1)
}

const widgetFormPath = "apps/cadence_web/assets/vue/WidgetForm.vue"
const widgetFormSource = currentSources.get(widgetFormPath)
assert.equal(widgetFormSource, gitShow(widgetFormPath))
assert.equal(widgetFormSource.match(/<fieldset\b/g)?.length, 2)
assert.equal(occurrences(widgetFormSource, 'v-if="presentation.point_widget.point_picker"'), 1)
assert.equal(
  occurrences(widgetFormSource, 'v-if="presentation.point_widget.operational_observable_picker"'),
  1,
)

const nativeDisclosureInventory = [...currentSources]
  .flatMap(([repositoryPath, source]) =>
    Array.from({length: source.match(/<details\b/g)?.length ?? 0}, () => repositoryPath),
  )
  .sort()
assert.deepEqual(nativeDisclosureInventory, [
  "apps/cadence_web/assets/vue/ApplicationHost.vue",
  "apps/cadence_web/assets/vue/DashboardToolbar.vue",
  "apps/cadence_web/assets/vue/OpsApplicationDock.vue",
  "apps/cadence_web/assets/vue/UserMenu.vue",
])

const rawDashedClass =
  "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
const rawDashedInventory = [...currentSources]
  .flatMap(([repositoryPath, source]) =>
    Array.from({length: occurrences(source, `class="${rawDashedClass}"`)}, () => repositoryPath),
  )
  .sort()
assert.deepEqual(rawDashedInventory, [
  "apps/cadence_web/assets/vue/CommsOverview.vue",
  "apps/cadence_web/assets/vue/CommsValidation.vue",
  "apps/cadence_web/assets/vue/MissionOverview.vue",
  "apps/cadence_web/assets/vue/SpacecraftRouting.vue",
])

const rekaMenuPanels = Object.freeze([
  Object.freeze({
    repositoryPath: "apps/cadence_web/assets/vue/CatalogDatabaseTable.vue",
    opening: '<template #content="{open}">',
    panelClass: "z-50 min-w-40 rounded-box border border-base-300 bg-base-100 p-2 shadow-lg",
  }),
  Object.freeze({
    repositoryPath: "apps/cadence_web/assets/vue/MissionOverview.vue",
    opening: '<template #content="{open}">',
    panelClass: "z-50 w-52 rounded-box border border-base-300 bg-base-100 p-2 shadow-lg",
  }),
  Object.freeze({
    repositoryPath: "apps/cadence_web/assets/vue/SpacecraftList.vue",
    opening: '<template #content="{open}">',
    panelClass: "z-50 min-w-40 rounded-box border border-base-300 bg-base-100 p-2 shadow-lg",
  }),
])
for (const exclusion of rekaMenuPanels) {
  const source = currentSources.get(exclusion.repositoryPath)
  assert.equal(source, gitShow(exclusion.repositoryPath))
  assert.equal(occurrences(source, exclusion.opening), 1)
  assert.equal(occurrences(source, `class="${exclusion.panelClass}"`), 1)
  assert.equal(occurrences(source, "<CadenceModalMenu"), 1)
}

const compileVueModule = (source, filename, id) => {
  const parsed = parse(source, {filename})
  assert.deepEqual(parsed.errors, [], `${filename} parses before runtime evaluation`)
  const compiled = compileScript(parsed.descriptor, {
    id,
    inlineTemplate: parsed.descriptor.template !== null,
  })
  return transformSync(compiled.content, {
    format: "cjs",
    loader: "ts",
    platform: "node",
    target: "node24",
  }).code
}

const createLocalSfcLoader = (sourceOverrides, idPrefix) => {
  const cache = new Map()

  const load = (modulePath) => {
    if (cache.has(modulePath)) return cache.get(modulePath).exports

    const loadedModule = {exports: {}}
    cache.set(modulePath, loadedModule)
    const extension = extname(modulePath)
    const source = sourceOverrides.get(modulePath) ?? readFileSync(modulePath, "utf8")
    const transformed =
      extension === ".vue"
        ? compileVueModule(source, modulePath, `${idPrefix}-${modulePath.split("/").at(-1)}`)
        : transformSync(source, {
            format: "cjs",
            loader: extension === ".ts" ? "ts" : "js",
            platform: "node",
            target: "node24",
          }).code
    const moduleRequire = (specifier) =>
      specifier.startsWith(".")
        ? load(resolve(dirname(modulePath), specifier))
        : integrationRequire(specifier)

    new Function("require", "module", "exports", transformed)(
      moduleRequire,
      loadedModule,
      loadedModule.exports,
    )
    return loadedModule.exports
  }

  return load
}

const currentLoader = createLocalSfcLoader(new Map(), "definition-list-current")
const predecessorLoader = createLocalSfcLoader(
  new Map([[callerPath, predecessorSource]]),
  "definition-list-predecessor",
)
const CadenceDefinitionListPanel = currentLoader(primitivePath).default
const CurrentOpsTelemetryExplore = currentLoader(callerPath).default
const NativeOpsTelemetryExplore = predecessorLoader(callerPath).default

assert.equal(CadenceDefinitionListPanel.name, "CadenceDefinitionListPanel")
assert.equal(CadenceDefinitionListPanel.inheritAttrs, false)
assert.deepEqual(Object.keys(CadenceDefinitionListPanel.props ?? {}), [])
assert.deepEqual(Object.keys(CadenceDefinitionListPanel.emits ?? {}), [])
assert.equal(typeof CurrentOpsTelemetryExplore.setup, "function")
assert.equal(typeof NativeOpsTelemetryExplore.setup, "function")

const {Fragment, createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")

const primitiveRows = ref([
  {id: "alpha", label: "Alpha", value: "10"},
  {id: "beta", label: "Beta", value: "20"},
])
const PrimitiveHarness = defineComponent({
  name: "DefinitionListPrimitiveHarness",
  setup: () => () =>
    h(
      CadenceDefinitionListPanel,
      {id: "primitive-definition-list", class: "caller-panel", "data-caller": "retained"},
      {
        heading: () => [[h(Fragment, null, ["Primitive heading"])]],
        default: () =>
          primitiveRows.value.map((row) =>
            h(Fragment, {key: row.id}, [
              h("dt", {"data-row-label": row.id}, row.label),
              [h(Fragment, null, [h("dd", {"data-row-value": row.id}, row.value)])],
            ]),
          ),
      },
    ),
})
const primitiveHost = dom.window.document.querySelector("#primitive-panel")
const primitiveApp = createApp(PrimitiveHarness)
primitiveApp.mount(primitiveHost)
await flushVue(nextTick)

const primitivePanel = primitiveHost.querySelector("#primitive-definition-list")
assert.deepEqual(elementAttributes(primitivePanel), {
  class: `${definitionListPanelClass} caller-panel`,
  "data-caller": "retained",
  id: "primitive-definition-list",
})
assert.equal(primitivePanel.children.length, 2)
assert.equal(primitivePanel.children[0].tagName, "H2")
assert.equal(primitivePanel.children[0].className, definitionListPanelHeadingClass)
assert.equal(primitivePanel.children[0].textContent, "Primitive heading")
assert.equal(primitivePanel.children[1].tagName, "DL")
assert.equal(primitivePanel.children[1].className, definitionListPanelListClass)
assert.deepEqual(
  [...primitivePanel.children[1].children].map((element) => element.tagName),
  ["DT", "DD", "DT", "DD"],
)
const primitiveOriginal = new Map(
  primitiveRows.value.map(({id}) => [
    id,
    {
      dt: primitivePanel.querySelector(`[data-row-label="${id}"]`),
      dd: primitivePanel.querySelector(`[data-row-value="${id}"]`),
    },
  ]),
)
const primitiveRoot = primitivePanel
const primitiveHeading = primitivePanel.children[0]
const primitiveList = primitivePanel.children[1]
primitiveRows.value = [
  {id: "beta", label: "Beta updated", value: "21"},
  {id: "alpha", label: "Alpha updated", value: "11"},
]
await flushVue(nextTick)
assert.strictEqual(primitiveHost.querySelector("#primitive-definition-list"), primitiveRoot)
assert.strictEqual(primitiveRoot.children[0], primitiveHeading)
assert.strictEqual(primitiveRoot.children[1], primitiveList)
for (const row of primitiveRows.value) {
  assert.strictEqual(primitiveRoot.querySelector(`[data-row-label="${row.id}"]`), primitiveOriginal.get(row.id).dt)
  assert.strictEqual(primitiveRoot.querySelector(`[data-row-value="${row.id}"]`), primitiveOriginal.get(row.id).dd)
}
assert.deepEqual(
  [...primitiveList.querySelectorAll("dt")].map((element) => element.textContent),
  ["Beta updated", "Alpha updated"],
)

const selectField = (key) => ({
  id: `explore-${key}`,
  name: `explore[${key}]`,
  type: "select",
  label: key,
  options: [{label: "Any", value: ""}],
})
const textField = (key) => ({
  id: `explore-${key}`,
  name: `explore[${key}]`,
  type: "text",
  label: key,
})
const filterValues = () => ({
  point_id: "",
  spacecraft_id: "",
  scope_kind: "mission",
  scope_id: "mission-one",
  time_mode: "latest",
  time_axis: "receipt",
  from: "",
  to: "",
  replay_run_id: "",
  order: "desc",
  limit: "25",
  selection_view: "all",
  validity_state: "all",
  realm: "",
  logical_source: "",
  data_source_id: "",
  source_binding_id: "",
  source_dashboard_id: "",
  sample_id: "",
  selected_time: "",
  question: "",
  limit_mode: "bounded",
})
const exploreProps = (contextRows, diagnosticRows) => ({
  page: {
    id: "telemetry-explore",
    heading: "Telemetry Explore",
    point_label: "Point",
    realm: null,
    time_mode: "latest",
    source_state: "none",
    data_source_id: "",
    source_binding_id: "",
    logical_source: "",
    source_realm: "",
    selected_sample_state: "none",
    selected_sample_id: "",
    selected_sample_status: null,
    samples_summary: "No samples",
    empty_samples_message: "No samples",
  },
  clipboard: {
    button_id: "copy-investigation",
    text: "/missions/mission-one/ops/explore",
    class: "btn btn-xs",
    icon: "hero-link",
    icon_class: "h-4 w-4",
    label: "Copy",
    copied_message: "Copied",
    failed_message: "Failed",
  },
  investigation: {
    id: "investigation",
    label: "Investigation",
    path: "/missions/mission-one/ops/explore",
    fingerprint: "fingerprint",
  },
  navigation: {back_to_dashboard: null},
  questions: [],
  question_briefing: null,
  filter_form: {
    id: "telemetry-explore-filter",
    values: filterValues(),
    fields: {
      point_id: selectField("point_id"),
      spacecraft_id: selectField("spacecraft_id"),
      time_mode: selectField("time_mode"),
      from: textField("from"),
      to: textField("to"),
      order: selectField("order"),
      limit: {
        id: "explore-limit",
        name: "explore[limit]",
        type: "number",
        label: "limit",
        min: "1",
        max: "100",
      },
      realm: selectField("realm"),
      logical_source: selectField("logical_source"),
      data_source_id: selectField("data_source_id"),
      source_binding_id: selectField("source_binding_id"),
      selection_view: selectField("selection_view"),
      validity_state: selectField("validity_state"),
    },
    submit: {id: "apply-filters", label: "Apply", icon: "hero-funnel"},
  },
  point: {
    id: "telemetry-explore-point",
    requested_point_id: "point-one",
    rows: [{label: "Point", value: "point-one"}],
    missing: false,
  },
  selected_sample: null,
  source_context: {
    id: "telemetry-explore-source-context",
    state: "none",
    data_source_id: "",
    source_binding_id: "",
    logical_source: "",
    realm: "",
    matched_data_source_id: "",
    matched_source_binding_id: "",
    rows: [{label: "Source", value: "none"}],
    actions: [],
  },
  context_rows: contextRows,
  diagnostics: {id: "telemetry-explore-diagnostics", rows: diagnosticRows},
  samples: [],
})

const initialContextRows = [
  {label: "Time mode", value: "latest"},
  {label: "Realm", value: "all"},
  {label: "Limit", value: "25"},
]
const updatedContextRows = [
  {label: "Limit", value: "50"},
  {label: "Time mode", value: "window"},
  {label: "Realm", value: "flight"},
]
const initialDiagnosticRows = [
  {label: "History", value: "ready"},
  {label: "Read path", value: "archive"},
  {label: "Count", value: "3"},
]
const updatedDiagnosticRows = [
  {label: "Count", value: "4"},
  {label: "History", value: "updated"},
  {label: "Read path", value: "cache"},
]
const currentProps = ref(exploreProps(initialContextRows, initialDiagnosticRows))
const nativeProps = ref(exploreProps(initialContextRows, initialDiagnosticRows))
const CurrentHarness = defineComponent({
  name: "CurrentOpsTelemetryExploreHarness",
  setup: () => () => h(CurrentOpsTelemetryExplore, currentProps.value),
})
const NativeHarness = defineComponent({
  name: "NativeOpsTelemetryExploreHarness",
  setup: () => () => h(NativeOpsTelemetryExplore, nativeProps.value),
})
const currentHost = dom.window.document.querySelector("#current-explore")
const nativeHost = dom.window.document.querySelector("#native-explore")
const currentApp = createApp(CurrentHarness)
const nativeApp = createApp(NativeHarness)
currentApp.mount(currentHost)
nativeApp.mount(nativeHost)
await flushVue(nextTick)

const panelContract = (host, id, dataAttribute) => {
  const root = host.querySelector(`#${id}`)
  assert.ok(root, `${id} renders`)
  assert.equal(root.tagName, "SECTION")
  assert.equal(root.className, definitionListPanelClass)
  assert.equal(root.children.length, 2)
  const heading = root.children[0]
  const list = root.children[1]
  assert.equal(heading.tagName, "H2")
  assert.equal(heading.className, definitionListPanelHeadingClass)
  assert.equal(list.tagName, "DL")
  assert.equal(list.className, definitionListPanelListClass)
  assert.deepEqual(
    [...list.children].map((element) => element.tagName),
    ["DT", "DD", "DT", "DD", "DT", "DD"],
  )
  const rows = new Map(
    [...list.querySelectorAll(`dd[${dataAttribute}]`)].map((dd) => [
      dd.getAttribute(dataAttribute),
      {dt: dd.previousElementSibling, dd},
    ]),
  )
  return {root, heading, list, rows}
}
const renderedSnapshot = (host, id, dataAttribute) => {
  const contract = panelContract(host, id, dataAttribute)
  return {
    outerHTML: contract.root.outerHTML,
    rootAttrs: elementAttributes(contract.root),
    headingAttrs: elementAttributes(contract.heading),
    listAttrs: elementAttributes(contract.list),
  }
}
const panelDefinitions = [
  ["telemetry-explore-context-card", "data-explore-context"],
  ["telemetry-explore-diagnostics", "data-explore-diagnostics"],
]
for (const [id, dataAttribute] of panelDefinitions) {
  assert.deepEqual(
    renderedSnapshot(currentHost, id, dataAttribute),
    renderedSnapshot(nativeHost, id, dataAttribute),
    `${id} current and native HTML/attrs are exact`,
  )
}

const retainedCurrentPanels = new Map(
  panelDefinitions.map(([id, dataAttribute]) => [id, panelContract(currentHost, id, dataAttribute)]),
)
currentProps.value = exploreProps(updatedContextRows, updatedDiagnosticRows)
nativeProps.value = exploreProps(updatedContextRows, updatedDiagnosticRows)
await flushVue(nextTick)

for (const [id, dataAttribute] of panelDefinitions) {
  assert.deepEqual(
    renderedSnapshot(currentHost, id, dataAttribute),
    renderedSnapshot(nativeHost, id, dataAttribute),
    `${id} stays exact after update and reorder`,
  )
  const retained = retainedCurrentPanels.get(id)
  const current = panelContract(currentHost, id, dataAttribute)
  assert.strictEqual(current.root, retained.root, `${id} section identity survives`)
  assert.strictEqual(current.heading, retained.heading, `${id} heading identity survives`)
  assert.strictEqual(current.list, retained.list, `${id} dl identity survives`)
  for (const [label, nodes] of current.rows) {
    assert.strictEqual(nodes.dt, retained.rows.get(label).dt, `${id} ${label} dt identity survives`)
    assert.strictEqual(nodes.dd, retained.rows.get(label).dd, `${id} ${label} dd identity survives`)
  }
}
assert.deepEqual(
  [...currentHost.querySelectorAll("#telemetry-explore-context-card dd")].map((dd) => dd.textContent),
  ["50", "window", "flight"],
)
assert.deepEqual(
  [...currentHost.querySelectorAll("#telemetry-explore-diagnostics dd")].map((dd) => dd.textContent),
  ["4", "updated", "cache"],
)

assert.doesNotThrow(() => primitiveApp.unmount())
assert.doesNotThrow(() => currentApp.unmount())
assert.doesNotThrow(() => nativeApp.unmount())
dom.window.close()

console.log(
  `definition_list_panel_migration_test passed (${predecessorVuePaths.length}->${currentVuePaths.length} SFCs, ${scenarios.length} scenarios, exact ${definitionListPanelPredecessorSha256})`,
)
