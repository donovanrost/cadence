import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readdir, readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  elementAttributes,
  expectedNodeVersion,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"
import {
  listToolbarFrameClass,
  listToolbarFrameMigrations,
  peelCadenceListToolbarFrame,
} from "./list_toolbar_frame_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `list toolbar migration contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueDirectory = resolve(testDirectory, "../vue")
const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const expectedCallers = listToolbarFrameMigrations.map(({file}) => file).sort()
const dom = installDom('<main id="list-toolbar-migration"></main>')

for (const globalName of ["HTMLFormElement", "HTMLInputElement"]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const {createApp, nextTick} = integrationRequire("vue")
const vueFiles = (await readdir(vueDirectory, {recursive: true}))
  .filter((path) => path.endsWith(".vue"))
  .sort()
const sources = await Promise.all(
  vueFiles.map(async (relativePath) => ({
    relativePath,
    source: await readFile(resolve(vueDirectory, relativePath), "utf8"),
  })),
)
const migratedSources = sources.filter(({source}) => /<CadenceListToolbarFrame\b/.test(source))

assert.deepEqual(
  migratedSources.map(({relativePath}) => relativePath).sort(),
  expectedCallers,
  "exactly the three audited callers use CadenceListToolbarFrame",
)
assert.equal(
  sources.reduce(
    (total, {source}) =>
      total + (source.match(/^import CadenceListToolbarFrame\b/gm)?.length ?? 0),
    0,
  ),
  3,
  "the Vue source tree has exactly three CadenceListToolbarFrame imports",
)
assert.equal(
  sources.reduce(
    (total, {source}) => total + (source.match(/<CadenceListToolbarFrame\b/g)?.length ?? 0),
    0,
  ),
  3,
  "the Vue source tree has exactly three CadenceListToolbarFrame openings",
)
assert.equal(
  sources.reduce(
    (total, {source}) => total + (source.match(/<\/CadenceListToolbarFrame>/g)?.length ?? 0),
    0,
  ),
  3,
  "the Vue source tree has exactly three CadenceListToolbarFrame closings",
)
assert.deepEqual(
  sources
    .filter(({source}) => source.includes(`class="${listToolbarFrameClass}"`))
    .map(({relativePath}) => relativePath),
  [],
  "the canonical class has transferred out of every caller native boundary",
)

const definitions = Object.freeze([
  Object.freeze({
    file: "CommsGroundStationList.vue",
    toolbarId: "ground-stations-toolbar",
    formId: "ground-stations-toolbar-search-form",
    inputId: "ground-stations-toolbar-search",
    formSha256: "c9ecd7bbb894d2c7c6783aa36ebe06eee7bba23d5e6056ba83fa9febcb38bc9c",
    inputClass: "w-full input input-sm",
    placeholder: "Search ground stations",
    value: "goldstone",
    props: Object.freeze({
      rows: Object.freeze([]),
      search: "goldstone",
      sort: "display_name",
      sort_dir: "asc",
      page: 1,
      page_size: 50,
      total_count: 0,
    }),
  }),
  Object.freeze({
    file: "CommsTransportList.vue",
    toolbarId: "transports-toolbar",
    formId: "transports-toolbar-search-form",
    inputId: "transports-toolbar-search",
    formSha256: "a2c1406b1aeee1d1dd46606eab3dccccbed264d94cb5a177a5cb6636d8137799",
    inputClass: "w-full input input-sm",
    placeholder: "Search transports",
    value: "tcp",
    props: Object.freeze({
      rows: Object.freeze([]),
      search: "tcp",
      sort: "display_name",
      sort_dir: "asc",
      page: 1,
      page_size: 50,
      total_count: 0,
    }),
  }),
  Object.freeze({
    file: "SpacecraftList.vue",
    toolbarId: "spacecraft-roster-toolbar",
    formId: "spacecraft-roster-toolbar-search-form",
    inputId: "spacecraft-roster-toolbar-search",
    formSha256: "457e643a89375b761824dae7e1c0f865c98a425f27aeeaa35c7c3e7750c0f8fa",
    inputClass: "input input-sm w-full",
    placeholder: "Search name or SCID",
    value: "scid",
    props: Object.freeze({
      summary_tiles: Object.freeze([]),
      roster: Object.freeze({
        fleet_empty: false,
        subtitle: "Fleet",
        new_spacecraft_href: "/missions/mission-1/spacecraft/new",
        search: "scid",
        sort_by: "display_name",
        sort_dir: "asc",
        filtered_empty: true,
        page: 1,
        page_size: 50,
        total_count: 0,
        pagination_visible: false,
        range_label: "0–0 of 0",
        previous_page: 0,
        next_page: 2,
        previous_disabled: true,
        next_disabled: true,
        rows: Object.freeze([]),
      }),
      profiles: Object.freeze({
        empty: true,
        truncated: false,
        subtitle: "Profiles",
        new_profile_href: "/missions/mission-1/spacecraft/profiles/new",
        all_profiles_href: "/missions/mission-1/spacecraft/profiles",
        rows: Object.freeze([]),
      }),
    }),
  }),
])

const exactFormSource = (source, formId) => {
  const opening = source.match(new RegExp(`^(\\s*)<form\\n\\s+id="${formId}"`, "m"))
  assert.ok(opening, `${formId} has one source-exact native form opening`)
  const closing = `${opening[1]}</form>`
  const closingIndex = source.indexOf(closing, opening.index)
  assert.ok(closingIndex > opening.index, `${formId} has a matching native form closing`)
  return source.slice(opening.index, closingIndex + closing.length)
}

const reconstructedHashes = {}

for (const definition of definitions) {
  const migration = listToolbarFrameMigrations.find(({file}) => file === definition.file)
  const callerPath = resolve(vueDirectory, definition.file)
  const callerSource = await readFile(callerPath, "utf8")
  const formSource = exactFormSource(callerSource, definition.formId)
  const predecessor = peelCadenceListToolbarFrame(callerSource, definition.file)

  assert.ok(migration, `${definition.file} has a frozen toolbar migration entry`)
  assert.equal(sha256(formSource), definition.formSha256, `${definition.file} keeps its native form bytes`)
  assert.equal(
    exactFormSource(predecessor, definition.formId),
    formSource,
    `${definition.file} inverse peel leaves the native form subtree byte-identical`,
  )
  assert.equal(
    sha256(predecessor),
    migration.currentSha256,
    `${definition.file} reconstructs its exact audited current source`,
  )
  reconstructedHashes[definition.file] = sha256(predecessor)

  const {component, descriptor} = await loadSfc(callerPath)

  assert.ok(descriptor.scriptSetup, `${definition.file} retains script setup`)
  assert.ok(descriptor.template, `${definition.file} retains its template`)

  const host = dom.window.document.createElement("div")
  host.id = `host-${definition.toolbarId}`
  dom.window.document.querySelector("#list-toolbar-migration").append(host)

  const app = createApp(component, definition.props)
  app.mount(host)
  await nextTick()

  const toolbar = dom.window.document.querySelector(`#${definition.toolbarId}`)
  const form = dom.window.document.querySelector(`#${definition.formId}`)
  const input = dom.window.document.querySelector(`#${definition.inputId}`)

  assert.equal(toolbar.tagName, "DIV", `${definition.file} keeps one native toolbar div`)
  assert.deepEqual(elementAttributes(toolbar), {
    class: listToolbarFrameClass,
    id: definition.toolbarId,
  })
  assert.equal(toolbar.childNodes.length, 1, `${definition.file} toolbar has one direct caller node`)
  assert.strictEqual(toolbar.firstElementChild, form)
  assert.deepEqual(elementAttributes(form), {
    class: "w-64 max-w-full",
    id: definition.formId,
    "phx-change": "search",
  })
  assert.deepEqual(elementAttributes(input), {
    class: definition.inputClass,
    id: definition.inputId,
    name: "q",
    "phx-debounce": "300",
    placeholder: definition.placeholder,
    type: "search",
    value: definition.value,
  })
  assert.equal(input.value, definition.value)

  const submitEvent = new dom.window.Event("submit", {bubbles: true, cancelable: true})
  assert.equal(form.dispatchEvent(submitEvent), false, `${definition.file} retains @submit.prevent`)
  assert.equal(submitEvent.defaultPrevented, true)

  app.unmount()
  host.remove()
}

assert.deepEqual(reconstructedHashes, {
  "CommsGroundStationList.vue":
    "72435e60587d54aa25c7c1e0fca0ebe38b5de8a38312720e886ef7a51d68718e",
  "CommsTransportList.vue":
    "16380da7163768eb6d09f12fe16dac75d5c3b97b0a6fa60bef7257a4f55727ae",
  "SpacecraftList.vue": "e8cacfac123f4f92547045131ba28a651095a7cbcf2bcc959853f6afb617d318",
})

dom.window.close()

console.log(
  "list_toolbar_frame_migration_test passed (3 actual SFCs + 3 exact audited-source reconstructions)",
)
