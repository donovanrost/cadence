import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  assertPinnedAdapterRuntime,
  flushVue,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"

const scenarioLedger = Object.freeze([
  "the actual three direct-dropdown SFCs compile and mount with two rows each",
  "closed menus expose neither content nor an unresolved aria-controls IDREF",
  "open public trigger and content IDs are unique and resolve both IDREF directions",
  "menu content remains portaled outside the LiveVue host",
  "menus and native link items retain their Reka roles",
  "every existing link and LiveView navigation attribute stays exact",
  "ArrowDown opens each first-row menu and Escape closes it",
  "selection closes each second-row menu",
  "Escape and selection restore focus to the public trigger",
  "the unchanged default modal behavior suppresses Tab and hides background content",
])

const testDirectory = dirname(fileURLToPath(import.meta.url))
const packageLockPath = resolve(testDirectory, "../../package-lock.json")
await assertPinnedAdapterRuntime(packageLockPath)
assert.equal(scenarioLedger.length, 10)

const dom = installDom('<div id="app"></div>')
Object.defineProperty(globalThis, "HTMLInputElement", {
  configurable: true,
  value: dom.window.HTMLInputElement,
})

const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const {createApp, defineComponent, h, nextTick} = integrationRequire("vue")
const modalMenuPath = resolve(testDirectory, "../vue/ui/reka/CadenceModalMenu.vue")
const menuItemPath = resolve(testDirectory, "../vue/ui/reka/CadenceMenuItem.vue")

const [{component: CadenceModalMenu}, {component: CadenceMenuItem}] = await Promise.all([
  loadSfc(modalMenuPath),
  loadSfc(menuItemPath),
])

const StatusBadge = defineComponent({
  props: ["status", "label"],
  setup: (props) => () => h("span", props.label),
})

const definitions = [
  {
    name: "SpacecraftList",
    path: resolve(testDirectory, "../vue/SpacecraftList.vue"),
    subject: "row",
    menuItemCount: 2,
    wrapperClass: "",
    sha256: "b322bffd1e6082c1d7f18a942c3a5879e2751beceb2e3d0f41175d2a11e25669",
  },
  {
    name: "CatalogArtifactShow",
    path: resolve(testDirectory, "../vue/CatalogArtifactShow.vue"),
    subject: "run",
    menuItemCount: 1,
    wrapperClass: "cadence-overlay",
    sha256: "76dd24a2f09333ef871304a3d8de09530f099b6c683df822f1cf2040e227a6fa",
  },
  {
    name: "MissionOverview",
    path: resolve(testDirectory, "../vue/MissionOverview.vue"),
    subject: "row",
    menuItemCount: 2,
    wrapperClass: "cadence-overlay",
    sha256: "79c4f3777ad19171238631f3c8f546ec591891ed8f049164b8554c55ddeb1371",
  },
]

const reconstructCatalogArtifactShowPreDataRowSource = (source) => {
  const dataRowImport = 'import CadenceDataRow from "./ui/components/CadenceDataRow.vue"\n'
  const dataRowBoundary =
    /          <CadenceDataRow\n            row-class="hud-data-row"\n            label-class="hud-data-label"\n            label="([^"]+)"\n          >([\s\S]*?)          <\/CadenceDataRow>/g
  const dataRowBoundaries = [...source.matchAll(dataRowBoundary)]

  assert.equal(
    source.split(dataRowImport).length - 1,
    1,
    "CatalogArtifactShow has exactly one CadenceDataRow import to strip",
  )
  assert.equal(
    dataRowBoundaries.length,
    4,
    "CatalogArtifactShow has exactly four CadenceDataRow boundaries to strip",
  )

  const reconstructedSource = source
    .replace(dataRowImport, "")
    .replace(
      dataRowBoundary,
      (_, label, callerSlot) =>
        `          <div class="hud-data-row">\n            <span class="hud-data-label">${label}</span>${callerSlot}          </div>`,
    )

  assert.doesNotMatch(reconstructedSource, /CadenceDataRow/)
  return reconstructedSource
}

const compileSfc = async (definition) => {
  const currentSource = await readFile(definition.path, "utf8")
  const source =
    definition.name === "CatalogArtifactShow"
      ? reconstructCatalogArtifactShowPreDataRowSource(currentSource)
      : currentSource
  const parsed = parse(source, {filename: definition.path})

  assert.deepEqual(parsed.errors, [], `${definition.name} parses with the pinned Vue compiler`)
  assert.ok(parsed.descriptor.scriptSetup, `${definition.name} keeps its setup script`)
  assert.ok(parsed.descriptor.template, `${definition.name} keeps its template`)
  assert.equal(createHash("sha256").update(source).digest("hex"), definition.sha256)
  assert.match(source, /import CadenceModalMenu from "\.\/ui\/reka\/CadenceModalMenu\.vue"/)
  assert.match(source, /import CadenceMenuItem from "\.\/ui\/reka\/CadenceMenuItem\.vue"/)
  assert.equal(source.match(/<CadenceModalMenu\b/g)?.length, 1)
  assert.equal(source.match(/<CadenceMenuItem\b/g)?.length, definition.menuItemCount)
  assert.doesNotMatch(source, /from "reka-ui"|<DropdownMenu/)
  assert.doesNotMatch(source, /\bmodal(?:=|\s)|\bref\(|\bwatch\(|@update:open/)
  assert.ok(
    source.includes(
      definition.wrapperClass === ""
        ? `<div :id="${definition.subject}.actions_id">`
        : `<div :id="${definition.subject}.actions_id" class="${definition.wrapperClass}">`,
    ),
  )
  assert.ok(
    source.includes(
      `:aria-controls="open ? \`\${${definition.subject}.actions_id}-menu\` : undefined"`,
    ),
  )
  assert.ok(
    source.includes(`:aria-labelledby="\`\${${definition.subject}.actions_id}-trigger\`"`),
  )

  const compiled = compileScript(parsed.descriptor, {
    id: `direct-dropdown-${definition.name}`,
    inlineTemplate: true,
  })
  const transformed = transformSync(compiled.content, {
    format: "cjs",
    loader: "ts",
    platform: "node",
    target: "node24",
  })
  const loadedModule = {exports: {}}
  const localRequire = (specifier) => {
    if (specifier === "./StatusBadge.vue") return StatusBadge
    if (specifier === "./ui/reka/CadenceModalMenu.vue") return CadenceModalMenu
    if (specifier === "./ui/reka/CadenceMenuItem.vue") return CadenceMenuItem
    return integrationRequire(specifier)
  }

  new Function("require", "module", "exports", transformed.code)(
    localRequire,
    loadedModule,
    loadedModule.exports,
  )

  return loadedModule.exports.default
}

const [SpacecraftList, CatalogArtifactShow, MissionOverview] = await Promise.all(
  definitions.map(compileSfc),
)

const spacecraftRows = ["alpha", "beta"].map((id) => ({
  id: `spacecraft-${id}`,
  actions_id: `spacecraft-${id}-actions`,
  display_name: id,
  scid_label: "1",
  scid_missing: false,
  profile_label: "Profile",
  status: "ready",
  status_label: "Ready",
  href: `/missions/mission-1/spacecraft/${id}`,
  identity_href: `/missions/mission-1/spacecraft/${id}/identity`,
}))

const spacecraftProps = {
  summary_tiles: [],
  roster: {
    fleet_empty: false,
    subtitle: "Fleet",
    new_spacecraft_href: "/missions/mission-1/spacecraft/new",
    search: "",
    sort_by: "display_name",
    sort_dir: "asc",
    filtered_empty: false,
    page: 1,
    page_size: 50,
    total_count: 2,
    pagination_visible: false,
    range_label: "1-2",
    previous_page: 0,
    next_page: 2,
    previous_disabled: true,
    next_disabled: true,
    rows: spacecraftRows,
  },
  profiles: {
    empty: true,
    truncated: false,
    subtitle: "",
    new_profile_href: "/missions/mission-1/spacecraft-profiles/new",
    all_profiles_href: "/missions/mission-1/spacecraft-profiles",
    rows: [],
  },
}

const artifactRuns = ["alpha", "beta"].map((id) => ({
  id: `artifact-run-${id}`,
  actions_id: `artifact-run-${id}-actions`,
  status: "ready",
  status_label: "Ready",
  started_at: "now",
  completed_at: "now",
  href: `/missions/mission-1/catalog/imports/${id}`,
}))

const artifactProps = {
  artifact: {
    format_key: "yaml",
    media_type: "text/yaml",
    content_sha256: "abc",
    uploaded_at: "now",
    download_href: "/missions/mission-1/catalog/artifacts/artifact-1/download",
  },
  runs: artifactRuns,
}

const missionRows = ["alpha", "beta"].map((id) => ({
  id: `mission-${id}`,
  __dom_id: `mission-${id}-row`,
  actions_id: `mission-${id}-readiness-actions`,
  spacecraft_display_name: id,
  spacecraft_id: id,
  scid_label: "1",
  endpoint_label: "Endpoint",
  endpoint_ref_label: "endpoint-ref",
  path_label: "Path",
  path_detail: "Path detail",
  status: "ready",
  status_label: "Ready",
  issue: "None",
  primary_action: "Review readiness",
  primary_action_href: `/missions/mission-1/spacecraft/${id}/readiness`,
  view_spacecraft_href: `/missions/mission-1/spacecraft/${id}`,
}))

const missionProps = {
  overview: {
    mission: {eyebrow: "Mission", display_name: "Alpha", slug: "alpha"},
    readiness_cards: [],
    setup: {
      eyebrow: "Readiness",
      title: "Setup",
      description: "Description",
      issue_count: 0,
      status: {tone: "ready", label: "Ready"},
      empty: false,
      empty_state: {title: "Empty", action_label: "Add", action_href: "/add"},
    },
  },
  spacecraft_readiness: missionRows,
}

const cases = [
  {
    name: "spacecraft",
    component: SpacecraftList,
    props: spacecraftProps,
    wrapperClass: "",
    rows: spacecraftRows.map((row) => ({
      actionsId: row.actions_id,
      links: [
        ["View", row.href],
        ["Identity", row.identity_href],
      ],
    })),
  },
  {
    name: "artifact run",
    component: CatalogArtifactShow,
    props: artifactProps,
    wrapperClass: "cadence-overlay",
    rows: artifactRuns.map((run) => ({
      actionsId: run.actions_id,
      links: [["View run", run.href]],
    })),
  },
  {
    name: "mission readiness",
    component: MissionOverview,
    props: missionProps,
    wrapperClass: "cadence-overlay",
    rows: missionRows.map((row) => ({
      actionsId: row.actions_id,
      links: [
        [row.primary_action, row.primary_action_href],
        ["View spacecraft", row.view_spacecraft_href],
      ],
    })),
  },
]

const Probe = defineComponent({
  setup: () => () =>
    h(
      "main",
      {id: "direct-dropdown-probe"},
      cases.map(({component, props}) => h(component, props)),
    ),
})

document.addEventListener("click", (event) => {
  if (event.target.closest("a")) event.preventDefault()
})

const appElement = document.querySelector("#app")
const app = createApp(Probe)
app.mount(appElement)
await flushVue(nextTick)

const allTriggerIds = cases.flatMap(({rows}) =>
  rows.map(({actionsId}) => `${actionsId}-trigger`),
)
const allContentIds = cases.flatMap(({rows}) =>
  rows.map(({actionsId}) => `${actionsId}-menu`),
)

assert.equal(new Set(allTriggerIds).size, 6, "all six public trigger IDs are unique")
assert.equal(new Set(allContentIds).size, 6, "all six public content IDs are unique")

const assertClosed = (actionsId, label) => {
  const wrapper = document.getElementById(actionsId)
  const trigger = document.getElementById(`${actionsId}-trigger`)

  assert.ok(wrapper, `${label} retains its public wrapper`)
  assert.ok(trigger, `${label} retains its public trigger`)
  assert.equal(trigger.tagName, "BUTTON")
  assert.equal(trigger.getAttribute("type"), "button")
  assert.equal(wrapper.children.length, 1, `${label} has one native trigger root`)
  assert.equal(trigger.parentElement, wrapper)
  assert.equal(trigger.getAttribute("aria-expanded"), "false")
  assert.equal(trigger.hasAttribute("aria-controls"), false)
  assert.equal(document.getElementById(`${actionsId}-menu`), null)
  assert.equal(document.querySelectorAll(`[id="${actionsId}-trigger"]`).length, 1)
}

const settleClose = async () => {
  await flushVue(nextTick)
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 10))
  await flushVue(nextTick)
}

for (const testCase of cases) {
  for (const [rowIndex, row] of testCase.rows.entries()) {
    const label = `${testCase.name} row ${rowIndex + 1}`
    const triggerId = `${row.actionsId}-trigger`
    const contentId = `${row.actionsId}-menu`
    const trigger = document.getElementById(triggerId)
    const wrapper = document.getElementById(row.actionsId)

    assertClosed(row.actionsId, label)
    assert.equal(wrapper.className, testCase.wrapperClass, `${label} preserves its wrapper class`)
    trigger.focus()

    if (rowIndex === 0) {
      const arrowDown = new KeyboardEvent("keydown", {
        bubbles: true,
        cancelable: true,
        key: "ArrowDown",
      })
      trigger.dispatchEvent(arrowDown)
      assert.equal(arrowDown.defaultPrevented, true, `${label} ArrowDown is owned by Reka`)
    } else {
      trigger.dispatchEvent(
        new MouseEvent("click", {bubbles: true, cancelable: true, button: 0}),
      )
    }

    await flushVue(nextTick)

    const content = document.getElementById(contentId)
    assert.ok(content, `${label} mounts its public content while open`)
    assert.equal(trigger.getAttribute("aria-expanded"), "true")
    assert.equal(trigger.getAttribute("aria-controls"), contentId)
    assert.equal(document.getElementById(trigger.getAttribute("aria-controls")), content)
    assert.equal(content.getAttribute("aria-labelledby"), triggerId)
    assert.equal(document.getElementById(content.getAttribute("aria-labelledby")), trigger)
    assert.equal(document.querySelectorAll(`[id="${contentId}"]`).length, 1)
    assert.equal(appElement.contains(content), false, `${label} content stays portaled`)
    assert.equal(content.tagName, "DIV")
    assert.equal(content.parentElement.children.length, 1, `${label} has one native content root`)
    assert.equal(content.getAttribute("role"), "menu")
    assert.equal(appElement.getAttribute("aria-hidden"), "true", `${label} remains modal`)
    assert.equal(content.contains(document.activeElement), true, `${label} focuses a menu item`)
    assert.equal(document.activeElement.getAttribute("role"), "menuitem")

    const links = [...content.querySelectorAll("a")]
    assert.deepEqual(
      links.map((link) => [link.textContent.trim(), link.getAttribute("href")]),
      row.links,
    )

    for (const link of links) {
      assert.equal(link.parentElement, content)
      assert.equal(link.getAttribute("role"), "menuitem")
      assert.equal(link.getAttribute("data-phx-link"), "redirect")
      assert.equal(link.getAttribute("data-phx-link-state"), "push")
    }

    const tab = new KeyboardEvent("keydown", {
      bubbles: true,
      cancelable: true,
      key: "Tab",
    })
    content.dispatchEvent(tab)
    assert.equal(tab.defaultPrevented, true, `${label} keeps default modal Tab suppression`)
    assert.equal(trigger.getAttribute("aria-expanded"), "true")

    if (rowIndex === 0) {
      const escape = new KeyboardEvent("keydown", {
        bubbles: true,
        cancelable: true,
        key: "Escape",
      })
      content.dispatchEvent(escape)
    } else {
      links[0].dispatchEvent(
        new MouseEvent("click", {bubbles: true, cancelable: true, button: 0}),
      )
    }

    await settleClose()
    assertClosed(row.actionsId, label)
    assert.equal(document.activeElement, trigger, `${label} restores public trigger focus`)
    assert.equal(appElement.hasAttribute("aria-hidden"), false, `${label} releases modal hiding`)
  }
}

app.unmount()
dom.window.close()

console.log(`direct_dropdown_menu_idref_test passed (${scenarioLedger.length} scenarios)`)
