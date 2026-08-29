import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {peelCadenceEmptyStateFrames} from "./empty_state_frame_test_support.mjs"
import {pageTitleCallerNames, peelCadencePageTitle} from "./page_title_test_support.mjs"
import {
  assertPinnedAdapterRuntime,
  flushVue,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"
import {hoverTableRowClass, peelCadenceHoverTableRows} from "./hover_table_row_test_support.mjs"
import {peelCadenceListToolbarFrame} from "./list_toolbar_frame_test_support.mjs"
import {peelCadencePaginationFrame} from "./pagination_frame_test_support.mjs"
import {peelResidualCadenceCardBeforeOlderLayers} from "./residual_cadence_cards_test_support.mjs"

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
const pageHeaderFramePath = resolve(
  testDirectory,
  "../vue/ui/components/CadencePageHeaderFrame.vue",
)
const tableFramePath = resolve(
  testDirectory,
  "../vue/ui/components/CadenceTableFrame.vue",
)
const hoverTableRowPath = resolve(
  testDirectory,
  "../vue/ui/components/CadenceHoverTableRow.vue",
)
const cardImport = 'import CadenceCard from "./ui/components/CadenceCard.vue"\n'
const pageHeaderImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const panelImport = 'import CadencePanel from "./ui/components/CadencePanel.vue"\n'
const tableImport =
  'import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"\n'

const loadPageHeaderFrame = async () => {
  const source = await readFile(pageHeaderFramePath, "utf8")
  const parsed = parse(source, {filename: pageHeaderFramePath})
  if (parsed.errors.length > 0) throw parsed.errors[0]

  const compiled = compileScript(parsed.descriptor, {
    id: "direct-dropdown-page-header-frame",
  })
  const transformed = transformSync(compiled.content, {
    format: "cjs",
    loader: "ts",
    platform: "node",
    target: "node24",
  })
  const loadedModule = {exports: {}}

  new Function("require", "module", "exports", transformed.code)(
    integrationRequire,
    loadedModule,
    loadedModule.exports,
  )

  return loadedModule.exports.default
}

const loadTableFrame = async () => {
  const source = await readFile(tableFramePath, "utf8")
  const parsed = parse(source, {filename: tableFramePath})
  if (parsed.errors.length > 0) throw parsed.errors[0]

  const compiled = compileScript(parsed.descriptor, {
    id: "direct-dropdown-table-frame",
  })
  const transformed = transformSync(compiled.content, {
    format: "cjs",
    loader: "ts",
    platform: "node",
    target: "node24",
  })
  const loadedModule = {exports: {}}

  new Function("require", "module", "exports", transformed.code)(
    integrationRequire,
    loadedModule,
    loadedModule.exports,
  )

  return loadedModule.exports.default
}

const loadHoverTableRow = async () => {
  const source = await readFile(hoverTableRowPath, "utf8")
  const parsed = parse(source, {filename: hoverTableRowPath})
  assert.deepEqual(parsed.errors, [], "CadenceHoverTableRow parses for direct-dropdown mounting")
  assert.ok(parsed.descriptor.script, "CadenceHoverTableRow keeps its normal render script")
  assert.equal(parsed.descriptor.scriptSetup, null)
  assert.equal(parsed.descriptor.template, null)

  const compiled = compileScript(parsed.descriptor, {
    id: "direct-dropdown-hover-table-row",
  })
  const transformed = transformSync(compiled.content, {
    format: "cjs",
    loader: "ts",
    platform: "node",
    target: "node24",
  })
  const loadedModule = {exports: {}}

  new Function("require", "module", "exports", transformed.code)(
    integrationRequire,
    loadedModule,
    loadedModule.exports,
  )

  return loadedModule.exports.default
}

const spacecraftPanelMigrations = [
  {
    componentOpen: `    <CadencePanel
      id="spacecraft-vehicles-card"
      class="card border border-base-300 bg-base-200"
      header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
    >`,
    sectionOpen:
      '    <section id="spacecraft-vehicles-card" class="card border border-base-300 bg-base-200">',
    slotOpen: "      <template #header>",
    headerOpen:
      '      <div class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3">',
    slotClose: "      </template>",
    headerClose: "      </div>",
    componentClose: "    </CadencePanel>",
    sectionClose: "    </section>",
  },
  {
    componentOpen: `    <CadencePanel
      id="spacecraft-profiles-card"
      class="card border border-base-300 bg-base-200"
      header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
    >`,
    sectionOpen:
      '    <section id="spacecraft-profiles-card" class="card border border-base-300 bg-base-200">',
    slotOpen: "      <template #header>",
    headerOpen:
      '      <div class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3">',
    slotClose: "      </template>",
    headerClose: "      </div>",
    componentClose: "    </CadencePanel>",
    sectionClose: "    </section>",
  },
]

const [
  {component: CadenceModalMenu},
  {component: CadenceMenuItem},
  CadencePageHeaderFrame,
  CadenceTableFrame,
  CadenceHoverTableRow,
] = await Promise.all([
  loadSfc(modalMenuPath),
  loadSfc(menuItemPath),
  loadPageHeaderFrame(),
  loadTableFrame(),
  loadHoverTableRow(),
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
    cardBoundaryCount: 0,
    tableOpeningRewrites: [
      {
        current: '          <CadenceTableFrame id="spacecraft-vehicles-table">',
        predecessor: '          <table id="spacecraft-vehicles-table" class="table">',
      },
      {
        current:
          '          <CadenceTableFrame id="spacecraft-profiles-preview-table">',
        predecessor:
          '          <table id="spacecraft-profiles-preview-table" class="table">',
      },
    ],
    tableClosing: "          </CadenceTableFrame>",
    nativeTableClosing: "          </table>",
    wrapperClass: "",
    sha256: "b322bffd1e6082c1d7f18a942c3a5879e2751beceb2e3d0f41175d2a11e25669",
  },
  {
    name: "CatalogArtifactShow",
    path: resolve(testDirectory, "../vue/CatalogArtifactShow.vue"),
    subject: "run",
    menuItemCount: 1,
    cardBoundaryCount: 2,
    tableOpeningRewrites: [
      {
        current: '          <CadenceTableFrame id="catalog-artifact-runs-table">',
        predecessor:
          '          <table id="catalog-artifact-runs-table" class="table">',
      },
    ],
    tableClosing: "          </CadenceTableFrame>",
    nativeTableClosing: "          </table>",
    wrapperClass: "cadence-overlay",
    sha256: "76dd24a2f09333ef871304a3d8de09530f099b6c683df822f1cf2040e227a6fa",
  },
  {
    name: "MissionOverview",
    path: resolve(testDirectory, "../vue/MissionOverview.vue"),
    subject: "row",
    menuItemCount: 2,
    cardBoundaryCount: 2,
    tableOpeningRewrites: [
      {
        current:
          '        <CadenceTableFrame v-else id="mission-spacecraft-readiness">',
        predecessor:
          '        <table v-else id="mission-spacecraft-readiness" class="table">',
      },
    ],
    tableClosing: "        </CadenceTableFrame>",
    nativeTableClosing: "        </table>",
    cardOpeningRewrites: [
      {
        current: `    <CadenceCard
      v-for="card in overview.readiness_cards"
      :key="card.title"
      class="card bg-base-200 border border-base-300"
      body-class="card-body p-6"
    >`,
        predecessor: `    <section
      v-for="card in overview.readiness_cards"
      :key="card.title"
      class="card bg-base-200 border border-base-300"
    >
      <div class="card-body p-6">`,
      },
      {
        current: `  <CadenceCard
    class="card bg-base-200 border border-base-300"
    body-class="card-body p-6"
  >`,
        predecessor: `  <section class="card bg-base-200 border border-base-300">
    <div class="card-body p-6">`,
      },
    ],
    wrapperClass: "cadence-overlay",
    sha256: "79c4f3777ad19171238631f3c8f546ec591891ed8f049164b8554c55ddeb1371",
  },
]

const reconstructPreCardSource = (source, definition) => {
  const expectedImportCount = definition.cardBoundaryCount === 0 ? 0 : 1

  assert.equal(
    source.split(cardImport).length - 1,
    expectedImportCount,
    `${definition.name} has the exact CadenceCard import count`,
  )
  assert.equal(
    source.match(/^import CadenceCard\b/gm)?.length ?? 0,
    expectedImportCount,
    `${definition.name} has the exact CadenceCard import declaration count`,
  )

  let openingCount = 0
  let reconstructedSource = source.replace(cardImport, "")

  if (definition.cardOpeningRewrites) {
    for (const {current, predecessor} of definition.cardOpeningRewrites) {
      assert.equal(
        reconstructedSource.split(current).length - 1,
        1,
        `${definition.name} CadenceCard boundary ${openingCount + 1} is exact and unique`,
      )
      openingCount += 1
      reconstructedSource = reconstructedSource.replace(current, predecessor)
    }
  } else {
    reconstructedSource = reconstructedSource.replace(
      /^([ \t]*)<CadenceCard\b([\s\S]*?)>$/gm,
      (_opening, indentation, attributes) => {
        const bodyClass = /(?:\n[ \t]*| )body-class="card-body p-6"/

        assert.match(
          attributes,
          bodyClass,
          `${definition.name} CadenceCard boundary ${openingCount + 1} keeps its body class`,
        )
        assert.equal(
          attributes.match(/body-class=/g)?.length,
          1,
          `${definition.name} CadenceCard boundary ${openingCount + 1} has one body class`,
        )
        openingCount += 1

        return `${indentation}<section${attributes.replace(bodyClass, "")}>\n${indentation}  <div class="card-body p-6">`
      },
    )
  }

  let closingCount = 0
  reconstructedSource = reconstructedSource.replace(
    /^([ \t]*)<\/CadenceCard>$/gm,
    (_closing, indentation) => {
      closingCount += 1
      return `${indentation}  </div>\n${indentation}</section>`
    },
  )

  assert.equal(
    openingCount,
    definition.cardBoundaryCount,
    `${definition.name} has the exact CadenceCard opening count`,
  )
  assert.equal(
    closingCount,
    definition.cardBoundaryCount,
    `${definition.name} has the exact CadenceCard closing count`,
  )
  assert.doesNotMatch(reconstructedSource, /CadenceCard/)

  return reconstructedSource
}

const replacePanelBoundaryAfter = (source, before, after, start, label) => {
  const index = source.indexOf(before, start)
  assert.notEqual(index, -1, `${label} exists after its panel opening`)

  return {
    source: source.slice(0, index) + after + source.slice(index + before.length),
    next: index + after.length,
  }
}

const reconstructSpacecraftListPrePanelSource = (source) => {
  assert.equal(
    source.split(panelImport).length - 1,
    1,
    "SpacecraftList has exactly one CadencePanel import to strip",
  )
  assert.equal(source.match(/<CadencePanel\b/g)?.length, 2)
  assert.equal(source.match(/<\/CadencePanel>/g)?.length, 2)

  let reconstructedSource = source.replace(panelImport, "")

  for (const [index, migration] of spacecraftPanelMigrations.entries()) {
    const label = `SpacecraftList CadencePanel boundary ${index + 1}`
    let replacement = replacePanelBoundaryAfter(
      reconstructedSource,
      migration.componentOpen,
      migration.sectionOpen,
      0,
      `${label} opening`,
    )
    reconstructedSource = replacement.source
    replacement = replacePanelBoundaryAfter(
      reconstructedSource,
      migration.slotOpen,
      migration.headerOpen,
      replacement.next,
      `${label} header opening`,
    )
    reconstructedSource = replacement.source
    replacement = replacePanelBoundaryAfter(
      reconstructedSource,
      migration.slotClose,
      migration.headerClose,
      replacement.next,
      `${label} header closing`,
    )
    reconstructedSource = replacement.source
    replacement = replacePanelBoundaryAfter(
      reconstructedSource,
      migration.componentClose,
      migration.sectionClose,
      replacement.next,
      `${label} closing`,
    )
    reconstructedSource = replacement.source
  }

  assert.doesNotMatch(reconstructedSource, /CadencePanel/)
  return reconstructedSource
}

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

const reconstructPreTableSource = (source, definition) => {
  const expectedFrameCount = definition.tableOpeningRewrites.length

  assert.equal(
    source.split(tableImport).length - 1,
    1,
    `${definition.name} has exactly one CadenceTableFrame import to strip`,
  )
  assert.equal(
    source.match(/^import CadenceTableFrame\b/gm)?.length,
    1,
    `${definition.name} has exactly one CadenceTableFrame import declaration`,
  )
  assert.equal(
    source.match(/<CadenceTableFrame\b/g)?.length,
    expectedFrameCount,
    `${definition.name} has the exact CadenceTableFrame opening count`,
  )
  assert.equal(
    source.split(definition.tableClosing).length - 1,
    expectedFrameCount,
    `${definition.name} has the exact CadenceTableFrame closing count`,
  )

  let reconstructedSource = source.replace(tableImport, "")

  for (const [index, rewrite] of definition.tableOpeningRewrites.entries()) {
    assert.equal(
      reconstructedSource.split(rewrite.current).length - 1,
      1,
      `${definition.name} CadenceTableFrame boundary ${index + 1} is exact and unique`,
    )
    reconstructedSource = reconstructedSource.replace(rewrite.current, rewrite.predecessor)
  }

  reconstructedSource = reconstructedSource
    .split(definition.tableClosing)
    .join(definition.nativeTableClosing)

  assert.doesNotMatch(reconstructedSource, /CadenceTableFrame/)
  return reconstructedSource
}

const reconstructMissionOverviewPrePageHeaderSource = source =>
  source
    .replace(pageHeaderImport, "")
    .replace(
      '<CadencePageHeaderFrame variant="compact">',
      '<header class="border-b border-primary/20 pb-4">',
    )
    .replace("</CadencePageHeaderFrame>", "</header>")

const compileSfc = async (definition) => {
  const currentSource = await readFile(definition.path, "utf8")
  const residualCardCompatibleSource = peelResidualCadenceCardBeforeOlderLayers(
    currentSource,
    `${definition.name}.vue`,
  )
  const reconstructNewerPresentationFrames = (inputSource) => {
    const filename = `${definition.name}.vue`
    const prePageTitleSource = pageTitleCallerNames.includes(filename)
      ? peelCadencePageTitle(inputSource, filename)
      : inputSource
    const prePaginationSource =
      definition.name === "SpacecraftList"
        ? peelCadencePaginationFrame(
            peelCadenceListToolbarFrame(prePageTitleSource, "SpacecraftList.vue"),
            "SpacecraftList.vue",
          )
        : prePageTitleSource
    const preCardSource = reconstructPreCardSource(prePaginationSource, definition)
    const prePanelSource =
      definition.name === "SpacecraftList"
        ? reconstructSpacecraftListPrePanelSource(preCardSource)
        : preCardSource

    return definition.name === "CatalogArtifactShow"
      ? reconstructCatalogArtifactShowPreDataRowSource(prePanelSource)
      : prePanelSource
  }
  const preEmptyStateSource =
    definition.name === "SpacecraftList"
      ? peelCadenceEmptyStateFrames(residualCardCompatibleSource, "SpacecraftList.vue")
      : residualCardCompatibleSource
  const source = reconstructNewerPresentationFrames(preEmptyStateSource)
  const predecessorCompatibleSource =
    definition.name === "SpacecraftList"
      ? reconstructNewerPresentationFrames(
          peelCadenceHoverTableRows(currentSource, "SpacecraftList.vue"),
        )
      : source
  const parsed = parse(source, {filename: definition.path})

  assert.deepEqual(parsed.errors, [], `${definition.name} parses with the pinned Vue compiler`)
  assert.ok(parsed.descriptor.scriptSetup, `${definition.name} keeps its setup script`)
  assert.ok(parsed.descriptor.template, `${definition.name} keeps its template`)
  const preTableSource = reconstructPreTableSource(predecessorCompatibleSource, definition)
  const predecessorSource =
    definition.name === "MissionOverview"
      ? reconstructMissionOverviewPrePageHeaderSource(preTableSource)
      : preTableSource
  assert.equal(createHash("sha256").update(predecessorSource).digest("hex"), definition.sha256)
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
    if (specifier === "./ui/components/CadencePageHeaderFrame.vue") {
      return CadencePageHeaderFrame
    }
    if (specifier === "./ui/components/CadenceTableFrame.vue") return CadenceTableFrame
    if (specifier === "./ui/components/CadenceHoverTableRow.vue") return CadenceHoverTableRow
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
    empty: false,
    truncated: false,
    subtitle: "Profiles",
    new_profile_href: "/missions/mission-1/spacecraft-profiles/new",
    all_profiles_href: "/missions/mission-1/spacecraft-profiles",
    rows: [
      {
        id: "spacecraft-profile-alpha",
        display_name: "Alpha profile",
        href: "/missions/mission-1/spacecraft/profiles/alpha",
        fleet_entries: [
          {
            label: "Alpha",
            href: "/missions/mission-1/spacecraft?profile=alpha",
          },
        ],
        protocols: "ccsds",
        applications: "Telemetry",
        status: "ready",
        status_label: "Ready",
      },
    ],
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

const spacecraftNativeNodes = new Map(
  spacecraftRows.map((row) => {
    const nativeRow = document.getElementById(row.id)
    const primaryLink = nativeRow.querySelector('a[data-phx-link="redirect"]')
    const trigger = document.getElementById(`${row.actions_id}-trigger`)

    assert.equal(nativeRow.tagName, "TR")
    assert.equal(nativeRow.className, hoverTableRowClass)
    assert.equal(nativeRow.hasAttribute("key"), false)
    assert.deepEqual([...nativeRow.children].map(({tagName}) => tagName), ["TD", "TD", "TD", "TD", "TD"])
    assert.equal(primaryLink.getAttribute("href"), row.href)
    assert.equal(primaryLink.getAttribute("data-phx-link"), "redirect")
    assert.equal(primaryLink.getAttribute("data-phx-link-state"), "push")
    assert.equal(trigger.closest("tr"), nativeRow)

    return [row.id, {nativeRow, primaryLink, trigger}]
  }),
)
const profileRow = document.getElementById("spacecraft-profile-alpha")
const profileRedirect = profileRow.querySelector('a[data-phx-link="redirect"]')
const profilePatch = profileRow.querySelector('a[data-phx-link="patch"]')
assert.equal(profileRow.tagName, "TR")
assert.equal(profileRow.className, hoverTableRowClass)
assert.equal(profileRow.hasAttribute("key"), false)
assert.deepEqual([...profileRow.children].map(({tagName}) => tagName), ["TD", "TD", "TD", "TD", "TD"])
assert.equal(profileRedirect.getAttribute("href"), spacecraftProps.profiles.rows[0].href)
assert.equal(profileRedirect.getAttribute("data-phx-link-state"), "push")
assert.equal(profilePatch.getAttribute("href"), spacecraftProps.profiles.rows[0].fleet_entries[0].href)
assert.equal(profilePatch.getAttribute("data-phx-link-state"), "push")

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

for (const row of spacecraftRows) {
  const retained = spacecraftNativeNodes.get(row.id)
  assert.strictEqual(document.getElementById(row.id), retained.nativeRow)
  assert.strictEqual(
    retained.nativeRow.querySelector('a[data-phx-link="redirect"]'),
    retained.primaryLink,
  )
  assert.strictEqual(document.getElementById(`${row.actions_id}-trigger`), retained.trigger)
}
assert.strictEqual(document.getElementById("spacecraft-profile-alpha"), profileRow)
assert.strictEqual(profileRow.querySelector('a[data-phx-link="redirect"]'), profileRedirect)
assert.strictEqual(profileRow.querySelector('a[data-phx-link="patch"]'), profilePatch)

app.unmount()
dom.window.close()

console.log(`direct_dropdown_menu_idref_test passed (${scenarioLedger.length} scenarios)`)
