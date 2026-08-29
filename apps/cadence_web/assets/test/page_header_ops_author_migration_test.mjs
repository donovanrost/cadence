#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {readFile, readdir, realpath} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  opsAuthorHeaderCallerNames,
  opsAuthorHeaderClass,
  opsAuthorHeaderMigrations,
  opsAuthorHeaderPredecessorCommit,
  opsAuthorHeaderPrimitivePredecessor,
  opsAuthorHeaderSha256,
  peelCadenceOpsAuthorHeader,
  peelOpsAuthorVariantFromPrimitive,
} from "./page_header_ops_author_test_support.mjs"
import {
  assertPinnedAdapterRuntime,
  elementAttributes,
  expectedNodeVersion,
  flushVue,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"

const scenarios = Object.freeze([
  "the exact predecessor cohort contains only two native dashboard-author header roots",
  "the primitive and both callers are frozen from the exact predecessor commit",
  "the primitive inverse and both caller inverses reconstruct exact predecessor bytes",
  "compact and ops source mappings remain unchanged while ops-author validates narrowly",
  "both actual caller SFCs compile through the real production primitive import",
  "both callers retain exact header DOM while Library forwards its caller-owned id",
  "attrs, listeners, directives, Fragment text, and native child identity remain transparent",
  "keyed native header and child identity survives reorder, insertion, and removal",
])

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `ops-author page-header contracts use pinned Node ${expectedNodeVersion}`,
)
assert.equal(
  await realpath(process.execPath),
  await realpath("/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"),
  "the migration ledger runs through the exact pinned Node binary",
)
assert.equal(scenarios.length, 8)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const packageLockPath = resolve(testDirectory, "../../package-lock.json")
const primitivePath = resolve(vueDirectory, "ui/components/CadencePageHeaderFrame.vue")
const git = (...args) =>
  execFileSync("git", ["-C", repositoryRoot, ...args], {encoding: "utf8"})
const occurrences = (source, fragment) => source.split(fragment).length - 1
const predecessorSource = (repositoryPath) =>
  git("show", `${opsAuthorHeaderPredecessorCommit}:${repositoryPath}`)

assert.equal(git("cat-file", "-t", opsAuthorHeaderPredecessorCommit).trim(), "commit")
assert.equal(opsAuthorHeaderMigrations.length, 2, "the exact cohort has two callers")
assert.deepEqual([...opsAuthorHeaderCallerNames].sort(), [
  "OpsDashboardLibrary.vue",
  "OpsDashboardPlaylists.vue",
])

const frozenEntries = [opsAuthorHeaderPrimitivePredecessor, ...opsAuthorHeaderMigrations]
for (const entry of frozenEntries) {
  const source = predecessorSource(entry.repositoryPath)

  assert.equal(entry.predecessorCommit, opsAuthorHeaderPredecessorCommit)
  assert.equal(Buffer.byteLength(source), entry.predecessorByteLength)
  assert.equal(opsAuthorHeaderSha256(source), entry.predecessorSha256)
  assert.equal(
    git("rev-parse", `${opsAuthorHeaderPredecessorCommit}:${entry.repositoryPath}`).trim(),
    entry.predecessorBlob,
    `${entry.repositoryPath} freezes the exact Git blob`,
  )
}

const predecessorCohort = git(
  "grep",
  "-n",
  "-F",
  opsAuthorHeaderClass,
  opsAuthorHeaderPredecessorCommit,
  "--",
  ":(glob)apps/cadence_web/assets/vue/**/*.vue",
)
  .trim()
  .split("\n")
  .map((line) => line.match(/assets\/vue\/([^:]+):\d+:/)?.[1])
  .filter(Boolean)
  .sort()

assert.deepEqual(
  predecessorCohort,
  [...opsAuthorHeaderCallerNames].sort(),
  "only the two frozen predecessor SFCs contain the exact native header class",
)

for (const entry of opsAuthorHeaderMigrations) {
  const source = predecessorSource(entry.repositoryPath)

  assert.equal(source.match(/<header\b/g)?.length, 1, `${entry.file} has one native HEADER root`)
  assert.equal(occurrences(source, "</header>"), 1, `${entry.file} closes one HEADER root`)
  assert.equal(occurrences(source, entry.predecessorOpening), 1)
  assert.doesNotMatch(source, /CadencePageHeaderFrame/)
}

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

const currentVueSources = await Promise.all(
  (await walkVueFiles(vueDirectory)).map(async (filePath) => ({
    file: filePath.slice(vueDirectory.length + 1),
    source: await readFile(filePath, "utf8"),
  })),
)
const exactNativeOpening = new RegExp(
  `<header\\b[^>]*class="${opsAuthorHeaderClass.replaceAll("/", "\\/")}"[^>]*>`,
  "g",
)

assert.deepEqual(
  currentVueSources
    .filter(({source}) => /<CadencePageHeaderFrame\b[^>]*variant="ops-author"/s.test(source))
    .map(({file}) => file)
    .sort(),
  [...opsAuthorHeaderCallerNames].sort(),
  "only the two exact callers adopt ops-author",
)
assert.equal(
  currentVueSources.reduce(
    (total, {source}) => total + (source.match(/<CadencePageHeaderFrame\b[^>]*variant="ops-author"/gs)?.length ?? 0),
    0,
  ),
  2,
)
assert.equal(
  currentVueSources.reduce(
    (total, {source}) => total + (source.match(exactNativeOpening)?.length ?? 0),
    0,
  ),
  0,
  "no exact native dashboard-author header remains",
)

for (const entry of opsAuthorHeaderMigrations) {
  const current = await readFile(resolve(repositoryRoot, entry.repositoryPath), "utf8")
  const predecessor = predecessorSource(entry.repositoryPath)

  assert.equal(peelCadenceOpsAuthorHeader(current, entry.file), predecessor)
  assert.equal(occurrences(current, '<div class="mx-auto max-w-6xl">'), 1)
  assert.equal(occurrences(current, entry.importLine), 1)
}

const primitiveSource = await readFile(primitivePath, "utf8")
const primitivePredecessor = predecessorSource(
  opsAuthorHeaderPrimitivePredecessor.repositoryPath,
)
assert.equal(peelOpsAuthorVariantFromPrimitive(primitiveSource), primitivePredecessor)
assert.equal(occurrences(primitiveSource, 'compact: "border-b border-primary/20 pb-4"'), 1)
assert.equal(
  occurrences(
    primitiveSource,
    'ops: "border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7"',
  ),
  1,
)

await assertPinnedAdapterRuntime(packageLockPath)
const dom = installDom(
  '<div id="playlists-contract"></div><div id="library-contract"></div><div id="keyed-contract"></div>',
)
for (const globalName of ["Document", "ShadowRoot"]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const parsedPrimitive = parse(primitiveSource, {filename: primitivePath})
assert.deepEqual(parsedPrimitive.errors, [])
const compiledPrimitive = compileScript(parsedPrimitive.descriptor, {
  id: "cadence-page-header-ops-author-contract",
}).content
const transformedPrimitive = transformSync(compiledPrimitive, {
  format: "cjs",
  loader: "ts",
  platform: "node",
  target: "node24",
})
const loadedPrimitive = {exports: {}}
new Function("require", "module", "exports", transformedPrimitive.code)(
  integrationRequire,
  loadedPrimitive,
  loadedPrimitive.exports,
)
const CadencePageHeaderFrame = loadedPrimitive.exports.default

assert.equal(CadencePageHeaderFrame.props.variant.validator("compact"), true)
assert.equal(CadencePageHeaderFrame.props.variant.validator("ops"), true)
assert.equal(CadencePageHeaderFrame.props.variant.validator("ops-author"), true)
assert.equal(CadencePageHeaderFrame.props.variant.validator("other"), false)
assert.match(primitiveSource, /child\.type === Fragment/)
assert.doesNotMatch(
  primitiveSource,
  /<template|<header|<nav|<a\b|<button|defineEmits|\b(?:computed|reactive|ref|watch)\s*\(/,
)

const callerPaths = opsAuthorHeaderMigrations.map(({repositoryPath}) =>
  resolve(repositoryRoot, repositoryPath),
)
for (const callerPath of callerPaths) {
  const source = await readFile(callerPath, "utf8")
  const parsed = parse(source, {filename: callerPath})

  assert.deepEqual(parsed.errors, [], `${callerPath} parses with the pinned compiler`)
  assert.ok(parsed.descriptor.scriptSetup)
  assert.ok(parsed.descriptor.template)
  assert.doesNotThrow(() =>
    compileScript(parsed.descriptor, {
      id: `ops-author-${callerPath.split("/").at(-1)}`,
      inlineTemplate: true,
    }),
  )
}

const textField = ({id, name, label, type = "text", value = ""}) => ({
  id,
  name,
  type,
  label,
  value,
  required: true,
})
const selectField = ({id, name, label, value = ""}) => ({
  id,
  name,
  type: "select",
  label,
  value,
  required: true,
  placeholder: `Select ${label}`,
})
const playlistsProps = {
  page: {
    id: "dashboard-playlists-page",
    eyebrow: "Dashboard author",
    heading: "Playlists",
    copy: "Playlist copy",
    list: {id: "dashboard-playlists-list", empty: {id: "playlists-empty", copy: "Empty"}},
    form_eyebrow: "Create playlist",
    present_action: {label: "Present", icon: "hero-play"},
  },
  form: {
    id: "playlist-form",
    reset_revision: 0,
    name: textField({id: "playlist-name", name: "playlist[name]", label: "Name"}),
    description: textField({
      id: "playlist-description",
      name: "playlist[description]",
      label: "Description",
      type: "textarea",
    }),
    dashboard_ids: {
      ...selectField({
        id: "playlist-dashboard-ids",
        name: "playlist[dashboard_ids][]",
        label: "Dashboards",
        value: [],
      }),
      value: [],
      multiple: true,
    },
    dwell_seconds: {
      ...textField({
        id: "playlist-dwell",
        name: "playlist[dwell_seconds]",
        label: "Dwell",
        type: "number",
        value: "30",
      }),
      min: 1,
      max: 3600,
    },
    wallboard_mode: {
      id: "playlist-wallboard",
      name: "playlist[wallboard_mode]",
      type: "checkbox",
      label: "Wallboard",
      value: false,
      required: false,
    },
    submit: {id: "playlist-submit", label: "Create"},
  },
  options: [],
  dashboard_playlists: [],
}
const libraryProps = {
  page: {
    id: "dashboard-library-page",
    header: {
      id: "dashboard-library-header",
      eyebrow: "Dashboard author",
      heading: "Library",
      copy: "Library copy",
    },
    list: {id: "dashboard-library-list", empty: {id: "library-empty", copy: "Empty"}},
    paths: {dashboards: "/ops/dashboards", library: "/ops/dashboard-library"},
  },
  dashboard_options: [],
  library_options: [],
  stage_form: {
    id: "stage-form",
    eyebrow: "Stage",
    fields: {
      dashboard_id: selectField({id: "stage-dashboard", name: "stage[dashboard]", label: "Dashboard"}),
      item_id: selectField({id: "stage-item", name: "stage[item]", label: "Item"}),
      version: {...textField({id: "stage-version", name: "stage[version]", label: "Version", type: "number", value: "1"}), min: 1},
    },
    action: {id: "stage-submit", label: "Stage"},
  },
  create_form: {
    id: "create-form",
    reset_revision: 0,
    details: {id: "create-details", summary_id: "create-summary", summary: "Create", open: false},
    fields: {
      name: textField({id: "create-name", name: "create[name]", label: "Name"}),
      description: textField({id: "create-description", name: "create[description]", label: "Description", type: "textarea"}),
      change_summary: textField({id: "create-summary-field", name: "create[summary]", label: "Summary"}),
      widget_json: textField({id: "create-json", name: "create[json]", label: "JSON", type: "textarea"}),
    },
    action: {id: "create-submit", label: "Create"},
  },
  version_form: {
    id: "version-form",
    details: {id: "version-details", summary_id: "version-summary", summary: "Version", open: false},
    fields: {
      item_id: selectField({id: "version-item", name: "version[item]", label: "Item"}),
      change_summary: textField({id: "version-summary-field", name: "version[summary]", label: "Summary"}),
      widget_json: textField({id: "version-json", name: "version[json]", label: "JSON", type: "textarea"}),
    },
    action: {id: "version-submit", label: "Version"},
  },
  library_items: [],
}

const [librarySfc, playlistsSfc] = await Promise.all(callerPaths.map(loadSfc))
const {Fragment, createApp, defineComponent, h, nextTick, reactive, ref, withDirectives} =
  integrationRequire("vue")
const reactivePlaylistsProps = reactive(playlistsProps)
const reactiveLibraryProps = reactive(libraryProps)
const playlistsApp = createApp(
  defineComponent({setup: () => () => h(playlistsSfc.component, {...reactivePlaylistsProps})}),
)
const libraryApp = createApp(
  defineComponent({setup: () => () => h(librarySfc.component, {...reactiveLibraryProps})}),
)
playlistsApp.mount(dom.window.document.querySelector("#playlists-contract"))
libraryApp.mount(dom.window.document.querySelector("#library-contract"))
await flushVue(nextTick)

const playlistsHeader = dom.window.document.querySelector("#dashboard-playlists-page > header")
const libraryHeader = dom.window.document.querySelector("#dashboard-library-header")
assert.equal(
  playlistsHeader.outerHTML,
  `<header class="${opsAuthorHeaderClass}"><div class="mx-auto max-w-6xl"><p class="hud-label">Dashboard author</p><h1 class="mt-1 text-2xl font-semibold">Playlists</h1><p class="mt-2 text-sm text-base-content/60">Playlist copy</p></div></header>`,
)
assert.equal(
  libraryHeader.outerHTML,
  `<header id="dashboard-library-header" class="${opsAuthorHeaderClass}"><div class="mx-auto max-w-6xl"><p class="hud-label">Dashboard author</p><h1 class="mt-1 text-2xl font-semibold">Library</h1><p class="mt-2 max-w-3xl text-sm text-base-content/60">Library copy</p></div></header>`,
)
assert.deepEqual(elementAttributes(libraryHeader), {
  class: opsAuthorHeaderClass,
  id: "dashboard-library-header",
})
const playlistsInner = playlistsHeader.firstElementChild
const libraryInner = libraryHeader.firstElementChild
const playlistsHeading = playlistsHeader.querySelector("h1")
const libraryHeading = libraryHeader.querySelector("h1")
reactivePlaylistsProps.page.heading = "Updated playlists"
reactiveLibraryProps.page.header.heading = "Updated library"
await flushVue(nextTick)
assert.strictEqual(dom.window.document.querySelector("#dashboard-playlists-page > header"), playlistsHeader)
assert.strictEqual(dom.window.document.querySelector("#dashboard-library-header"), libraryHeader)
assert.strictEqual(playlistsHeader.firstElementChild, playlistsInner)
assert.strictEqual(libraryHeader.firstElementChild, libraryInner)
assert.strictEqual(playlistsHeader.querySelector("h1"), playlistsHeading)
assert.strictEqual(libraryHeader.querySelector("h1"), libraryHeading)

const keyedAuthors = ref([
  {key: "alpha", label: "Alpha"},
  {key: "bravo", label: "Bravo"},
])
const rootClicks = []
const directiveRoots = new Map()
const authorDirective = {
  mounted(element, binding) {
    directiveRoots.set(binding.value, element)
  },
}
const KeyedContract = defineComponent({
  setup() {
    return () =>
      h(
        "div",
        {id: "keyed-author-list"},
        keyedAuthors.value.map((author) =>
          withDirectives(
            h(
              CadencePageHeaderFrame,
              {
                key: author.key,
                variant: "ops-author",
                id: `author-header-${author.key}`,
                class: "caller-class-is-not-merged",
                "data-author": author.key,
                "aria-label": `${author.label} author header`,
                onClick: () => rootClicks.push(author.key),
              },
              {
                default: () => [
                  h("div", {id: `author-child-${author.key}`}, author.label),
                  h(Fragment, null, [" direct text ", [h("button", {id: `author-action-${author.key}`, type: "button"}, "Act")]]),
                ],
              },
            ),
            [[authorDirective, author.key]],
          ),
        ),
      )
  },
})
const keyedApp = createApp(KeyedContract)
keyedApp.mount(dom.window.document.querySelector("#keyed-contract"))
await flushVue(nextTick)

const alphaHeader = dom.window.document.querySelector("#author-header-alpha")
const bravoHeader = dom.window.document.querySelector("#author-header-bravo")
const alphaChild = dom.window.document.querySelector("#author-child-alpha")
const bravoChild = dom.window.document.querySelector("#author-child-bravo")
assert.deepEqual(elementAttributes(alphaHeader), {
  "aria-label": "Alpha author header",
  class: opsAuthorHeaderClass,
  "data-author": "alpha",
  id: "author-header-alpha",
})
assert.deepEqual([...alphaHeader.childNodes].map((node) => node.nodeName), [
  "DIV",
  "#text",
  "BUTTON",
])
assert.strictEqual(directiveRoots.get("alpha"), alphaHeader)
assert.strictEqual(directiveRoots.get("bravo"), bravoHeader)
assert.equal(alphaHeader.hasAttribute("key"), false)
dom.window.document.querySelector("#author-action-alpha").click()
assert.deepEqual(rootClicks, ["alpha"])

keyedAuthors.value = [
  {key: "bravo", label: "Bravo updated"},
  {key: "charlie", label: "Charlie"},
  {key: "alpha", label: "Alpha updated"},
]
await flushVue(nextTick)
assert.deepEqual(
  [...dom.window.document.querySelector("#keyed-author-list").children].map(({id}) => id),
  ["author-header-bravo", "author-header-charlie", "author-header-alpha"],
)
assert.strictEqual(dom.window.document.querySelector("#author-header-alpha"), alphaHeader)
assert.strictEqual(dom.window.document.querySelector("#author-header-bravo"), bravoHeader)
assert.strictEqual(dom.window.document.querySelector("#author-child-alpha"), alphaChild)
assert.strictEqual(dom.window.document.querySelector("#author-child-bravo"), bravoChild)
keyedAuthors.value = keyedAuthors.value.filter(({key}) => key !== "bravo")
await flushVue(nextTick)
assert.equal(dom.window.document.querySelector("#author-header-bravo"), null)
assert.strictEqual(dom.window.document.querySelector("#author-header-alpha"), alphaHeader)

keyedApp.unmount()
libraryApp.unmount()
playlistsApp.unmount()
dom.window.close()

console.log("page_header_ops_author_migration_test passed (2/2 exact-DOM callers)")
