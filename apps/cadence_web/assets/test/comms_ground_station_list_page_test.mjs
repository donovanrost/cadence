import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {peelCadenceEmptyStateComponent} from "./empty_state_frame_test_support.mjs"
import {peelCadenceListToolbarFrame} from "./list_toolbar_frame_test_support.mjs"
import {peelCadencePaginationFrame} from "./pagination_frame_test_support.mjs"

const scenarioLedger = [
  "the complete Ground Station List page is one always-present non-SSR LiveVue parent",
  "the LiveVue host has exactly one JSON-safe presentation prop and class contents",
  "Phoenix owns authentication, organization and mission scope, store loading, counts, and routes",
  "Phoenix owns ListParams parsing, matching, sorting, page clamping, visible rows, and URL patches",
  "Phoenix owns the complete root, header, breadcrumb, action, empty, card, and child presentation",
  "CommsGroundStationListPage composes shared Cadence shell components and the immutable child once",
  "the child receives rows, search, sort, sort_dir, page, page_size, and total_count unchanged",
  "the page root and inner nonempty wrapper retain their existing IDs and branch structure",
  "breadcrumb, setup, and row links retain LiveView redirect and push navigation attributes",
  "raw attrs preserve HEEx nil, false, true, string, and number behavior",
  "provider and region fallbacks and mission-scoped row hrefs remain server decisions",
  "the eight pre-migration scenarios and all list-returning paths remain present one-for-one",
  "search, sort, pagination, no-match, show, form, archive, and not-found outcomes stay exact",
  "handle_params recomputes the complete presentation after every URL-driven list-state change",
  "the authenticated comms route, mounts, action, and mission-sidebar layout stay unchanged",
  "router, LiveView, tests, page, and shared Cadence components use semantic source contracts",
]

assert.equal(
  process.versions.node,
  "24.16.0",
  "ground-station-list contracts use pinned Node 24.16.0",
)
assert.equal(scenarioLedger.length, 16)

const __dirname = dirname(fileURLToPath(import.meta.url))
const pagePath = resolve(__dirname, "../vue/CommsGroundStationListPage.vue")
const childPath = resolve(__dirname, "../vue/CommsGroundStationList.vue")
const breadcrumbsPath = resolve(__dirname, "../vue/ui/components/CadenceBreadcrumbs.vue")
const pageHeaderPath = resolve(__dirname, "../vue/ui/components/CadencePageHeader.vue")
const emptyStatePath = resolve(__dirname, "../vue/ui/components/CadenceEmptyState.vue")
const pageShellTypesPath = resolve(__dirname, "../vue/ui/components/page_shell.ts")
const liveViewPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/comms_ground_station_list_live.ex",
)
const liveViewTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/comms_ground_station_live_test.exs",
)
const routerPath = resolve(__dirname, "../../lib/cadence_web/router.ex")

const [
  pageSource,
  childSource,
  breadcrumbsSource,
  pageHeaderSource,
  currentEmptyStateSource,
  pageShellTypesSource,
  liveViewSource,
  liveViewTestSource,
  routerSource,
] = await Promise.all([
  readFile(pagePath, "utf8"),
  readFile(childPath, "utf8"),
  readFile(breadcrumbsPath, "utf8"),
  readFile(pageHeaderPath, "utf8"),
  readFile(emptyStatePath, "utf8"),
  readFile(pageShellTypesPath, "utf8"),
  readFile(liveViewPath, "utf8"),
  readFile(liveViewTestPath, "utf8"),
  readFile(routerPath, "utf8"),
])
const emptyStateSource = peelCadenceEmptyStateComponent(currentEmptyStateSource)

const sourceSlice = (source, start, end, label) => {
  const startIndex = source.indexOf(start)
  const endIndex = source.indexOf(end, startIndex + start.length)

  assert.ok(startIndex >= 0 && endIndex > startIndex, `${label} must remain source-auditable`)
  return source.slice(startIndex, endIndex)
}

const assertBalancedTemplate = (source, label) => {
  const stack = []
  const voidElements = new Set([
    "area",
    "base",
    "br",
    "col",
    "embed",
    "hr",
    "img",
    "input",
    "link",
    "meta",
  ])
  const tags = source.matchAll(/<\/?([A-Za-z][\w.-]*)(?:\s[^<>]*?)?>/gs)

  for (const match of tags) {
    const token = match[0]
    const name = match[1]

    if (token.startsWith("</")) {
      assert.equal(stack.pop(), name, `${name} closes the current ${label} element`)
    } else if (!token.endsWith("/>") && !voidElements.has(name)) {
      stack.push(name)
    }
  }

  assert.deepEqual(stack, [], `${label} template tags are balanced`)
}

const sfcParts = (source, label) => {
  const script = source.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
  const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

  assert.ok(script, `${label} must have a TypeScript script setup block`)
  assert.ok(template, `${label} must have a template block`)
  assertBalancedTemplate(template, label)

  return {script, template}
}

const assertInOrder = (source, contracts, label) => {
  let previousIndex = -1

  for (const contract of contracts) {
    const index = source.indexOf(contract, previousIndex + 1)
    assert.ok(index > previousIndex, `${label} preserves ${contract} in order`)
    previousIndex = index
  }
}

const preToolbarChildSource = peelCadenceListToolbarFrame(
  childSource,
  "CommsGroundStationList.vue",
)
const prePaginationChildSource = peelCadencePaginationFrame(
  preToolbarChildSource,
  "CommsGroundStationList.vue",
)

assert.equal(
  prePaginationChildSource.match(
    /^import CadenceTableFrame from "\.\/ui\/components\/CadenceTableFrame\.vue"$/gm,
  )?.length,
  1,
  "CommsGroundStationList.vue has one CadenceTableFrame import before compatibility peeling",
)
assert.equal(
  prePaginationChildSource.match(/<\/?CadenceTableFrame\b/g)?.length,
  2,
  "CommsGroundStationList.vue has one CadenceTableFrame boundary before compatibility peeling",
)

const predecessorChildSource = prePaginationChildSource
  .replace('import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"\n', "")
  .replace(
    '    <CadenceTableFrame id="ground-stations-table">',
    '    <table id="ground-stations-table" class="table">',
  )
  .replace("    </CadenceTableFrame>", "    </table>")

assert.doesNotMatch(
  predecessorChildSource,
  /CadenceTableFrame/,
  "CommsGroundStationList.vue predecessor has no residual CadenceTableFrame shell",
)

assert.equal(
  createHash("sha256").update(predecessorChildSource).digest("hex"),
  "a30c8122f8314e4e386708e1f2ba6a4bf163dc763a3879bd1f8034894d709a2e",
  "CommsGroundStationList.vue remains the explicitly immutable child",
)

const {script, template} = sfcParts(pageSource, "CommsGroundStationListPage.vue")
const {script: breadcrumbsScript, template: breadcrumbsTemplate} = sfcParts(
  breadcrumbsSource,
  "CadenceBreadcrumbs.vue",
)
const {script: pageHeaderScript, template: pageHeaderTemplate} = sfcParts(
  pageHeaderSource,
  "CadencePageHeader.vue",
)
const {script: emptyStateScript, template: emptyStateTemplate} = sfcParts(
  emptyStateSource,
  "CadenceEmptyState.vue",
)

assert.match(script, /import CommsGroundStationList from "\.\/CommsGroundStationList\.vue"/)
assert.match(script, /import CadenceEmptyState from "\.\/ui\/components\/CadenceEmptyState\.vue"/)
assert.match(script, /import CadencePageHeader from "\.\/ui\/components\/CadencePageHeader\.vue"/)
assert.match(
  script,
  /type GroundStationListProps = InstanceType<typeof CommsGroundStationList>\["\$props"\]/,
)
assert.match(script, /header: PageHeaderPresentation &/)
assert.match(script, /new_ground_station: PageHeaderAction/)
assert.match(script, /empty_state: EmptyStatePresentation \| null/)
assert.match(script, /defineProps<\{presentation: Presentation\}>\(\)/)
assert.equal(template.match(/<CommsGroundStationList\b/g)?.length, 1)
assert.equal(template.match(/<CadencePageHeader\b/g)?.length, 1)
assert.equal(template.match(/<CadenceEmptyState\b/g)?.length, 1)

for (const childProp of [
  "rows",
  "search",
  "sort",
  "sort_dir",
  "page",
  "page_size",
  "total_count",
]) {
  assert.ok(
    template.includes(
      `:${childProp}="props.presentation.card.list_component.props.${childProp}"`,
    ),
    `${childProp} passes directly into the immutable child`,
  )
}

for (const binding of [
  "props.presentation.root.attrs",
  "props.presentation.card.attrs",
  "props.presentation.card.body.attrs",
  "props.presentation.card.list_component.attrs",
]) {
  assert.ok(template.includes(`v-bind="${binding}"`), `${binding} stays DTO-owned`)
}

assertInOrder(
  template,
  [
    'v-bind="props.presentation.root.attrs"',
    "<CadencePageHeader",
    ':header="props.presentation.header"',
    ':action="props.presentation.header.actions.new_ground_station"',
    "<CadenceEmptyState",
    'v-if="props.presentation.empty_state"',
    ':empty-state="props.presentation.empty_state"',
    'v-else-if="props.presentation.card"',
    'v-bind="props.presentation.card.attrs"',
    'v-bind="props.presentation.card.body.attrs"',
    'v-bind="props.presentation.card.list_component.attrs"',
    "<CommsGroundStationList",
  ],
  "Ground Station page composition",
)

assert.match(breadcrumbsScript, /defineProps<\{breadcrumbs\?: BreadcrumbsPresentation\}>\(\)/)
assertInOrder(
  breadcrumbsTemplate,
  [
    '<nav v-bind="props.breadcrumbs.attrs">',
    'v-for="item in props.breadcrumbs.items"',
    'v-if="item.separator"',
    'v-bind="item.separator.attrs"',
    "{{ item.separator.text }}",
    'v-if="item.link"',
    'v-bind="item.link.attrs"',
    "{{ item.link.text }}",
    'v-if="item.current"',
    'v-bind="item.current.attrs"',
    "{{ item.current.text }}",
  ],
  "breadcrumb elements",
)

assert.match(pageHeaderScript, /import CadenceBreadcrumbs from "\.\/CadenceBreadcrumbs\.vue"/)
assert.match(pageHeaderScript, /header: PageHeaderPresentation/)
assert.match(pageHeaderScript, /action: PageHeaderAction/)
assert.equal(pageHeaderTemplate.match(/<CadenceBreadcrumbs\b/g)?.length, 1)
assertInOrder(
  pageHeaderTemplate,
  [
    '<header v-bind="props.header.attrs">',
    'v-bind="props.header.body.attrs"',
    'v-bind="props.header.content.attrs"',
    ':breadcrumbs="props.header.breadcrumbs"',
    'v-bind="props.header.title.attrs"',
    "{{ props.header.title.text }}",
    'v-bind="props.header.title.suffix.attrs"',
    "{{ props.header.title.suffix.text }}",
    'v-bind="props.header.subtitle.attrs"',
    "{{ props.header.subtitle.text }}",
    'v-bind="props.header.actions.attrs"',
    'v-bind="props.action.attrs"',
    'v-if="props.action.icon"',
    'v-bind="props.action.icon.attrs"',
    "{{ props.action.text }}",
  ],
  "page-header elements",
)

assert.match(emptyStateScript, /defineProps<\{emptyState: EmptyStatePresentation\}>\(\)/)
assertInOrder(
  emptyStateTemplate,
  [
    '<div v-bind="props.emptyState.attrs">',
    'v-bind="props.emptyState.title.attrs"',
    "{{ props.emptyState.title.text }}",
    'v-bind="props.emptyState.description.attrs"',
    "{{ props.emptyState.description.text }}",
    'v-bind="props.emptyState.action_container.attrs"',
    'v-bind="props.emptyState.action.attrs"',
    'v-bind="props.emptyState.action.icon.attrs"',
    "{{ props.emptyState.action.text }}",
  ],
  "empty-state elements",
)

assert.match(pageShellTypesSource, /icon\?: ElementPresentation \| null/)
assert.equal(
  [breadcrumbsTemplate, pageHeaderTemplate, emptyStateTemplate].join("\n").match(/<a\b/g)
    ?.length,
  3,
  "the extracted shell retains the three existing anchor positions",
)

for (const componentSource of [
  breadcrumbsSource,
  pageHeaderSource,
  emptyStateSource,
  pageShellTypesSource,
]) {
  assert.doesNotMatch(componentSource, /reka-ui|ui\/reka/)
  assert.doesNotMatch(
    componentSource,
    /\/missions|Ground Stations|No ground stations|New Ground Station|data-phx-link|phx-change|phx-click/,
  )
  assert.doesNotMatch(
    componentSource,
    /computed|ref\(|watch\(|fetch\(|defineEmits|useRoute|router|\.sort|\.filter|\.slice|Math\./,
  )
}

assert.match(template, /v-else-if="props\.presentation\.card"/)
assert.match(
  template,
  /<div v-bind="props\.presentation\.card\.list_component\.attrs">\s+<CommsGroundStationList/,
)
assert.doesNotMatch(
  pageSource,
  /Ground Stations|No ground stations|New Ground Station|Mission-owned antenna|space-y-6|btn btn-primary|data-phx-link|\/missions/,
)
assert.doesNotMatch(
  pageSource,
  /computed|sort\(|\.sort\(|filter\(|\.filter\(|slice\(|\.slice\(|pushPatch|pushEvent|v-html/,
)
assert.doesNotMatch(pageSource, /<\.vue|v-component=|phx-click|phx-change|phx-submit/)

for (const childContract of [
  "type Props = {",
  "rows: GroundStationRow[]",
  "search: string | null",
  'id="ground-stations-toolbar"',
  'id="ground-stations-toolbar-search-form"',
  'phx-change="search"',
  'id="ground-stations-table"',
  'phx-click="sort"',
  'id="ground-stations"',
  'data-phx-link="redirect"',
  'data-phx-link-state="push"',
  'id="ground-stations-pagination"',
  'phx-click="paginate"',
]) {
  assert.ok(childSource.includes(childContract), `${childContract} remains in the immutable child`)
}

const mountSource = sourceSlice(
  liveViewSource,
  "  def mount(_params, _session, socket) do",
  "  @impl true\n  def handle_params(params, _uri, socket) do",
  "CommsGroundStationListLive mount",
)

assert.match(mountSource, /%\{current_scope: scope, current_mission: mission\} = socket\.assigns/)
assert.match(
  mountSource,
  /GroundStationStore\.list_ground_stations\(\s*scope\.organization_id,\s*mission\.mission_id\s*\)/,
)
assert.match(mountSource, /assign\(:page_title, "Ground Stations"\)/)
assert.match(mountSource, /assign\(:nav_item, :comms_ground_stations\)/)
assert.match(mountSource, /assign\(:ground_stations, ground_stations\)/)
assert.match(mountSource, /assign\(:ground_station_count, length\(ground_stations\)\)/)
assert.match(mountSource, /assign\(:ground_stations_empty\?, ground_stations == \[\]\)/)
assert.match(mountSource, /assign\(:presentation, nil\)/)

const handleParamsSource = sourceSlice(
  liveViewSource,
  "  def handle_params(params, _uri, socket) do",
  '  @impl true\n  def handle_event("search", %{"q" => q}, socket) do',
  "CommsGroundStationListLive handle_params",
)

assert.match(
  handleParamsSource,
  /ListParams\.parse\(params, sortable: @sortable, default_sort: "display_name"\)/,
)
assert.match(
  handleParamsSource,
  /\{visible, total\} = filter_ground_stations\(socket\.assigns\.ground_stations, list\)/,
)
assert.match(handleParamsSource, /sort_dir = Atom\.to_string\(list\.dir\)/)
assert.match(
  handleParamsSource,
  /rows = Enum\.map\(visible, &ground_station_table_row\(&1, mission_id\)\)/,
)
assert.match(handleParamsSource, /presentation =\s+page_presentation_dto\(/)
assert.match(handleParamsSource, /assign\(:list, list\)/)
assert.match(handleParamsSource, /assign\(:ground_station_sort_dir, sort_dir\)/)
assert.match(handleParamsSource, /assign\(:filtered_count, total\)/)
assert.match(handleParamsSource, /assign\(:ground_station_table_rows, rows\)/)
assert.match(handleParamsSource, /assign\(:presentation, presentation\)/)

const eventSource = sourceSlice(
  liveViewSource,
  '  def handle_event("search", %{"q" => q}, socket) do',
  "  @impl true\n  def render(assigns) do",
  "Ground Station List URL and collection decisions",
)

for (const event of ["search", "sort", "paginate"]) {
  assert.ok(eventSource.includes(`handle_event("${event}"`), `${event} remains server-owned`)
}

assert.match(eventSource, /ListParams\.toggle_sort/)
assert.match(eventSource, /ListParams\.parse\(%\{"page" => page\}, sortable: \[\]\)\.page/)
assert.equal(eventSource.match(/patch_list\(/g)?.length, 4)
assert.match(eventSource, /ListParams\.to_query\(list\)/)
assert.match(
  eventSource,
  /push_patch\(socket, to: ~p"\/missions\/#\{mission_id\}\/comms\/ground-stations\?#\{query\}"\)/,
)
assert.match(eventSource, /Enum\.filter\(&matches_query\?\(&1, list\.q\)\)/)
assert.match(eventSource, /Enum\.sort_by\(&String\.downcase\(&1\.display_name\), list\.dir\)/)
assert.match(eventSource, /last_page = max\(ceil\(length\(matching\) \/ @page_size\), 1\)/)
assert.match(eventSource, /page = min\(list\.page, last_page\)/)
assert.match(eventSource, /Enum\.slice\(matching, \(page - 1\) \* @page_size, @page_size\)/)
assert.match(eventSource, /ground_station\.provider/)
assert.match(eventSource, /ground_station\.region/)

const renderSource = sourceSlice(
  liveViewSource,
  "  def render(assigns) do",
  "  @doc false",
  "CommsGroundStationListLive render boundary",
)

assert.equal(renderSource.match(/<\.vue/g)?.length, 1)
assert.match(renderSource, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(renderSource, /id="comms-ground-station-list-page-component"/)
assert.match(renderSource, /v-component="CommsGroundStationListPage"/)
assert.match(renderSource, /presentation=\{@presentation\}/)
assert.match(renderSource, /v-ssr=\{false\}/)
assert.match(renderSource, /class="contents"/)
assert.doesNotMatch(renderSource, /<\.page_header|<\.empty_state|<\.card|<\.button/)
assert.doesNotMatch(renderSource, /ground-stations-list-component|CommsGroundStationList"/)

const rawAttrsSource = sourceSlice(
  liveViewSource,
  "  @doc false\n  def presentation_attrs(attrs) when is_map(attrs) do",
  "  defp page_presentation_dto(",
  "Ground Station List raw attribute projection",
)

assert.match(rawAttrsSource, /value in \[nil, false\]/)
assert.match(rawAttrsSource, /\{name, true\}, rendered/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, ""\)/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, to_string\(value\)\)/)

const presentationSource = sourceSlice(
  liveViewSource,
  "  defp page_presentation_dto(",
  "  defp ground_station_table_row(ground_station, mission_id) do",
  "Ground Station List page presentation DTO",
)
const headerPresentationSource = sourceSlice(
  liveViewSource,
  "  defp header_presentation(mission, ground_station_count, new_ground_station_path) do",
  "  defp breadcrumbs_presentation(mission) do",
  "Ground Station List header presentation DTO",
)

for (const topLevelKey of ["root", "header", "empty_state", "card"]) {
  assert.ok(presentationSource.includes(`"${topLevelKey}" =>`), `${topLevelKey} stays in presentation`)
}

for (const text of [
  "Ground Stations",
  "Mission-owned antenna and site identities used by dashboard scope, source diagnostics, and comms setup.",
  "New Ground Station",
  "No ground stations",
  "Create a setup record before linking telemetry diagnostics to a stable station identity.",
]) {
  assert.ok(presentationSource.includes(`"${text}"`), `${text} stays Phoenix-owned`)
}

for (const className of [
  "space-y-6",
  "border-b border-primary/20 pb-4",
  "flex items-end justify-between gap-4",
  "mt-2 text-2xl font-bold text-base-content tracking-tight",
  "ml-3 font-mono text-base text-base-content/60",
  "mt-1 max-w-3xl text-sm text-base-content/70",
  "flex items-center gap-2",
  "btn btn-primary btn-sm",
  "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center",
  "hud-label",
  "mt-2 max-w-md mx-auto text-sm text-base-content/70",
  "hero-plus -ml-0.5 mr-1 h-4 w-4",
  "card bg-base-200 border border-base-300",
  "card-body p-0",
]) {
  assert.ok(presentationSource.includes(`"${className}"`), `${className} stays Phoenix-owned`)
}

for (const route of [
  '~p"/missions/#{mission.mission_id}"',
  '~p"/missions/#{mission.mission_id}/comms"',
  '~p"/missions/#{mission.mission_id}/comms/ground-stations/new"',
]) {
  assert.ok(presentationSource.includes(route), `${route} remains server-verified`)
}

assert.match(presentationSource, /"id" => "comms-ground-stations-page"/)
assert.match(presentationSource, /"id" => "new-ground-station-link"/)
assert.match(presentationSource, /"id" => "ground-stations-list-component"/)
assert.match(presentationSource, /"data-phx-link" => "redirect"/)
assert.match(presentationSource, /"data-phx-link-state" => "push"/)
assert.match(presentationSource, /empty_state_presentation\(ground_stations_empty\?,/)
assert.match(presentationSource, /card_presentation\(\s*ground_stations_empty\?,/)
assert.match(headerPresentationSource, /"new_ground_station" => %\{/)
assert.doesNotMatch(
  headerPresentationSource,
  /"icon" =>/,
  "the Ground Station header action remains the icon-free optional-action case",
)

for (const childProp of [
  '"rows" => rows',
  '"search" => list.q',
  '"sort" => list.sort',
  '"sort_dir" => sort_dir',
  '"page" => list.page',
  '"page_size" => @page_size',
  '"total_count" => filtered_count',
]) {
  assert.ok(presentationSource.includes(childProp), `${childProp} remains Phoenix-authored`)
}

for (const fallback of [
  'provider: ground_station.provider || "UNSPECIFIED"',
  'region: ground_station.region || "none"',
  '~p"/missions/#{mission_id}/comms/ground-stations/#{ground_station.ground_station_id}"',
]) {
  assert.ok(liveViewSource.includes(fallback), `${fallback} remains a server-owned row decision`)
}

assert.match(liveViewSource, /@page_size 50/)
assert.match(liveViewSource, /@sortable ~w\(display_name\)/)

for (const scenario of [
  'test "renders the empty state when the mission has no ground stations"',
  'test "lists and shows configured ground stations"',
  'test "searches and sorts through LiveView-owned list events"',
  'test "paginates through the LiveView event and keeps visible rows in props"',
  'test "creates, edits, and archives ground stations"',
  'test "keeps Vue-owned values synchronized through validation"',
  'test "redirects edit mode when the ground station is not found"',
  'test "rejects invalid metadata JSON"',
]) {
  assert.equal(
    liveViewTestSource.split(scenario).length - 1,
    1,
    `${scenario} remains present one-for-one`,
  )
}

for (const focusedScenario of [
  'test "projects the complete list page through one JSON-safe LiveVue prop"',
  'test "preserves HEEx raw attribute coercion in the page presentation"',
]) {
  assert.equal(
    liveViewTestSource.split(focusedScenario).length - 1,
    1,
    `${focusedScenario} remains focused and unique`,
  )
}

for (const listContract of [
  'LiveVue.Test.get_vue(view, id: "comms-ground-station-list-page-component")',
  'page_vue.props["presentation"]',
  '["card"]["list_component"]["props"]',
  'Map.keys(vue.props) == ["presentation"]',
  'Jason.decode!(Jason.encode!(vue.props))',
  'CadenceWeb.CommsGroundStationListLive.presentation_attrs',
  '"nil" => nil',
  '"false" => false',
  '"true" => true',
  '"number" => 7',
]) {
  assert.ok(liveViewTestSource.includes(listContract), `${listContract} remains asserted`)
}

assert.doesNotMatch(
  liveViewTestSource,
  /LiveVue\.Test\.get_vue\(view, id: "ground-stations-list-component"\)/,
)

const listAndShowScenario = sourceSlice(
  liveViewTestSource,
  '    test "lists and shows configured ground stations" do',
  '    test "searches and sorts through LiveView-owned list events" do',
  "Ground Station list and show caller scenario",
)

assert.match(listAndShowScenario, /show_vue\.component == "CommsGroundStationShow"/)
assert.match(listAndShowScenario, /show_vue\.props == %\{/)
assert.match(
  listAndShowScenario,
  /"href" => "\/missions\/#\{mission\.mission_id\}\/comms\/ground-stations"/,
)

const createEditArchiveScenario = sourceSlice(
  liveViewTestSource,
  '    test "creates, edits, and archives ground stations" do',
  '    test "keeps Vue-owned values synchronized through validation" do',
  "Ground Station form and archive list-return scenario",
)

assert.match(createEditArchiveScenario, /assert list_path ==/)
assert.match(
  createEditArchiveScenario,
  /"\/missions\/#\{mission\.mission_id\}\/comms\/ground-stations"/,
)

assert.match(
  routerSource,
  /scope "\/", CadenceWeb do\n    pipe_through \[:browser, :require_authenticated_scope\]/,
)

const commsSession = sourceSlice(
  routerSource,
  "    live_session :comms,",
  "    live_session :ops_dashboard_author,",
  "authenticated comms LiveSession",
)

assert.match(commsSession, /CadenceWeb\.OrganizationAuth, :require_organization_scope/)
assert.match(commsSession, /CadenceWeb\.MissionAuth, :load_mission/)
assert.match(commsSession, /CadenceWeb\.UserAuth, :attach_user_menu/)
assert.match(commsSession, /layout: \{CadenceWeb\.Layouts, :mission_sidebar\}/)
assert.match(
  commsSession,
  /live "\/missions\/:mission_id\/comms\/ground-stations",\s+CommsGroundStationListLive,\s+:index/,
)
assert.match(
  commsSession,
  /live "\/missions\/:mission_id\/comms\/ground-stations\/new",\s+CommsGroundStationFormLive,\s+:new/,
)
assert.match(
  commsSession,
  /live "\/missions\/:mission_id\/comms\/ground-stations\/:ground_station_id\/edit",\s+CommsGroundStationFormLive,\s+:edit/,
)
assert.match(
  commsSession,
  /live "\/missions\/:mission_id\/comms\/ground-stations\/:ground_station_id",\s+CommsGroundStationShowLive,\s+:show/,
)
assert.doesNotMatch(
  commsSession,
  /require_organization_admin|require_platform_admin|load_spacecraft/,
)
