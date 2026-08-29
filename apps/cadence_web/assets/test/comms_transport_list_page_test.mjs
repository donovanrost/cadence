import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {peelCadencePaginationFrame} from "./pagination_frame_test_support.mjs"

const scenarioLedger = [
  "the complete transport-list page is one non-SSR LiveVue parent with one presentation prop",
  "Phoenix owns mission-scoped TransportStore loading, counts, empty/card selection, and row decisions",
  "Phoenix retains in-memory filtering, whitelisted sorting, pagination slicing and clamping, and patch URLs",
  "handle_params recomputes the complete presentation and every existing child prop",
  "CommsTransportListPage composes shared Cadence shell components and the immutable child once",
  "the shared breadcrumbs, header, optional action icon, empty state, and page-owned card stay exact",
  "breadcrumb, create, and transport-detail links retain LiveView redirect navigation semantics",
  "the immutable child retains search, sort, pagination, and link event attributes",
  "all eleven pre-migration transport scenarios and their oracles remain one-for-one in the broad test file",
  "focused JSON-totality and raw HEEx attribute semantics are covered",
  "the authenticated comms route, mission mounts, and mission-sidebar layout remain unchanged",
  "only the immutable child is hashed; page and shared Cadence components use semantic contracts",
]

assert.equal(
  process.versions.node,
  "24.16.0",
  "transport-list contracts use pinned Node 24.16.0",
)
assert.equal(scenarioLedger.length, 12)

const __dirname = dirname(fileURLToPath(import.meta.url))
const pagePath = resolve(__dirname, "../vue/CommsTransportListPage.vue")
const childPath = resolve(__dirname, "../vue/CommsTransportList.vue")
const breadcrumbsPath = resolve(__dirname, "../vue/ui/components/CadenceBreadcrumbs.vue")
const pageHeaderPath = resolve(__dirname, "../vue/ui/components/CadencePageHeader.vue")
const emptyStatePath = resolve(__dirname, "../vue/ui/components/CadenceEmptyState.vue")
const pageShellTypesPath = resolve(__dirname, "../vue/ui/components/page_shell.ts")
const liveViewPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/comms_transport_list_live.ex",
)
const liveViewTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/comms_transport_live_test.exs",
)
const routerPath = resolve(__dirname, "../../lib/cadence_web/router.ex")

const [
  pageSource,
  childSource,
  breadcrumbsSource,
  pageHeaderSource,
  emptyStateSource,
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

  for (const match of source.matchAll(/<\/?([A-Za-z][\w.-]*)(?:\s[^<>]*?)?>/gs)) {
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

const prePaginationChildSource = peelCadencePaginationFrame(
  childSource,
  "CommsTransportList.vue",
)

assert.equal(
  prePaginationChildSource.match(
    /^import CadenceTableFrame from "\.\/ui\/components\/CadenceTableFrame\.vue";$/gm,
  )?.length,
  1,
  "CommsTransportList.vue has one CadenceTableFrame import before compatibility peeling",
)
assert.equal(
  prePaginationChildSource.match(/<\/?CadenceTableFrame\b/g)?.length,
  2,
  "CommsTransportList.vue has one CadenceTableFrame boundary before compatibility peeling",
)

const predecessorChildSource = prePaginationChildSource
  .replace('import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue";\n', "")
  .replace(
    '    <CadenceTableFrame id="transports-table">',
    '    <table id="transports-table" class="table">',
  )
  .replace("    </CadenceTableFrame>", "    </table>")

assert.doesNotMatch(
  predecessorChildSource,
  /CadenceTableFrame/,
  "CommsTransportList.vue predecessor has no residual CadenceTableFrame shell",
)

assert.equal(
  createHash("sha256").update(predecessorChildSource).digest("hex"),
  "7a9ad282915fd8aa8e9d3ed1f2663a9b7170ce4e89cc2c96ff29acf260c019c3",
  "CommsTransportList.vue remains byte-for-byte immutable",
)

const {script, template} = sfcParts(pageSource, "CommsTransportListPage.vue")
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

assert.match(script, /^import CommsTransportList from "\.\/CommsTransportList\.vue"$/m)
assert.equal(script.match(/import .*CommsTransportList\.vue/g)?.length, 1)
assert.match(script, /import CadenceEmptyState from "\.\/ui\/components\/CadenceEmptyState\.vue"/)
assert.match(script, /import CadencePageHeader from "\.\/ui\/components\/CadencePageHeader\.vue"/)
assert.match(
  script,
  /type CommsTransportListProps = InstanceType<typeof CommsTransportList>\["\$props"\]/,
)
assert.match(script, /header: PageHeaderPresentation &/)
assert.match(script, /new_transport: PageHeaderAction/)
assert.match(script, /empty_state: EmptyStatePresentation \| null/)
assert.match(script, /defineProps<\{presentation: Presentation\}>\(\)/)
assert.doesNotMatch(script, /computed|ref\(|watch\(|fetch\(|defineEmits|useRoute|router/)

assert.equal(template.match(/<CommsTransportList\b/g)?.length, 1)
assert.equal(template.match(/<CadencePageHeader\b/g)?.length, 1)
assert.equal(template.match(/<CadenceEmptyState\b/g)?.length, 1)
assertInOrder(
  template,
  [
    'v-bind="props.presentation.root.attrs"',
    "<CadencePageHeader",
    ':header="props.presentation.header"',
    ':action="props.presentation.header.actions.new_transport"',
    "<CadenceEmptyState",
    'v-if="props.presentation.empty_state"',
    ':empty-state="props.presentation.empty_state"',
    'v-else-if="props.presentation.card"',
    'v-bind="props.presentation.card.attrs"',
    'v-bind="props.presentation.card.body.attrs"',
    'v-bind="props.presentation.card.list_component.attrs"',
    '<CommsTransportList v-bind="props.presentation.card.list_component.props" />',
  ],
  "transport page composition",
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
    /\/missions|Transports|No transports|New Transport|data-phx-link|phx-change|phx-click/,
  )
  assert.doesNotMatch(
    componentSource,
    /computed|ref\(|watch\(|fetch\(|defineEmits|useRoute|router|\.sort|\.filter|\.slice|Math\./,
  )
}

assert.doesNotMatch(
  pageSource,
  /\/missions|Transports|No transports|New Transport|Create the first transport|space-y-6|btn btn-primary|data-phx-link|phx-change|phx-click/,
)
assert.doesNotMatch(pageSource, /\.sort|\.filter|\.slice|Math\.|v-html|<\.vue|v-component=/)

const mountSource = sourceSlice(
  liveViewSource,
  "  def mount(_params, _session, socket) do",
  "  @impl true\n  def handle_params(params, _uri, socket) do",
  "transport-list mount boundary",
)

assert.match(
  mountSource,
  /TransportStore\.list_transports\(scope\.organization_id, mission\.mission_id\)/,
)
assert.match(mountSource, /assign\(:page_title, "Comms Transports"\)/)
assert.match(mountSource, /assign\(:nav_item, :comms_transports\)/)
assert.match(mountSource, /assign\(:transports, transports\)/)
assert.match(mountSource, /assign\(:transport_count, length\(transports\)\)/)
assert.match(mountSource, /assign\(:transports_empty\?, transports == \[\]\)/)

const handleParamsSource = sourceSlice(
  liveViewSource,
  "  def handle_params(params, _uri, socket) do",
  '  @impl true\n  def handle_event("search", %{"q" => q}, socket) do',
  "transport-list handle_params boundary",
)

assert.match(
  handleParamsSource,
  /ListParams\.parse\(params, sortable: @sortable, default_sort: "display_name"\)/,
)
assert.match(handleParamsSource, /filter_transports\(socket\.assigns\.transports, list\)/)
assert.match(handleParamsSource, /Enum\.map\(visible, &transport_table_row\(&1, mission\.mission_id\)\)/)
assert.match(handleParamsSource, /presentation =\s+page_presentation_dto\(/)
assert.match(handleParamsSource, /assign\(:list, list\)/)
assert.match(handleParamsSource, /assign\(:presentation, presentation\)/)

const eventSource = sourceSlice(
  liveViewSource,
  '  def handle_event("search", %{"q" => q}, socket) do',
  "  defp filter_transports(transports, %ListParams{} = list) do",
  "transport-list event and patch boundary",
)

assert.match(eventSource, /%\{socket\.assigns\.list \| q: q, page: 1\}/)
assert.match(eventSource, /ListParams\.toggle_sort\(socket\.assigns\.list, key\)/)
assert.match(eventSource, /ListParams\.parse\(%\{"page" => page\}, sortable: \[\]\)\.page/)
assert.match(eventSource, /ListParams\.to_query\(list\)/)
assert.match(
  eventSource,
  /push_patch\(socket, to: ~p"\/missions\/#\{mission_id\}\/comms\/transports\?#\{query\}"\)/,
)

const filterSource = sourceSlice(
  liveViewSource,
  "  defp filter_transports(transports, %ListParams{} = list) do",
  "  defp matches_query?(_transport, nil), do: true",
  "transport-list in-memory filtering boundary",
)

assert.match(filterSource, /Enum\.filter\(&matches_query\?\(&1, list\.q\)\)/)
assert.match(filterSource, /Enum\.sort_by\(&String\.downcase\(&1\.display_name\), list\.dir\)/)
assert.match(filterSource, /last_page = max\(ceil\(length\(matching\) \/ @page_size\), 1\)/)
assert.match(filterSource, /page = min\(list\.page, last_page\)/)
assert.match(filterSource, /Enum\.slice\(matching, \(page - 1\) \* @page_size, @page_size\)/)

const renderSource = sourceSlice(
  liveViewSource,
  "  def render(assigns) do",
  "  @doc false",
  "CommsTransportListLive render boundary",
)

assert.equal(renderSource.match(/<\.vue/g)?.length, 1)
assert.match(renderSource, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(renderSource, /id="comms-transport-list-page-component"/)
assert.match(renderSource, /v-component="CommsTransportListPage"/)
assert.match(renderSource, /presentation=\{@presentation\}/)
assert.match(renderSource, /v-ssr=\{false\}/)
assert.match(renderSource, /class="contents"/)
assert.doesNotMatch(renderSource, /<\.page_header|<\.card|<\.empty_state|<\.button/)
assert.doesNotMatch(renderSource, /rows=|search=|sort=|sort_dir=|page=|page_size=|total_count=/)

const rawAttrsSource = sourceSlice(
  liveViewSource,
  "  @doc false\n  def presentation_attrs(attrs) when is_map(attrs) do",
  "  defp page_presentation_dto(mission, transport_count, transports_empty?, rows, list, total) do",
  "transport-list raw attribute projection",
)

assert.match(rawAttrsSource, /value in \[nil, false\]/)
assert.match(rawAttrsSource, /\{name, true\}, rendered/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, ""\)/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, to_string\(value\)\)/)

const presentationSource = sourceSlice(
  liveViewSource,
  "  defp page_presentation_dto(mission, transport_count, transports_empty?, rows, list, total) do",
  "  defp transport_summary(transport) do",
  "transport-list page presentation DTO",
)
const headerPresentationSource = sourceSlice(
  liveViewSource,
  "  defp header_presentation(mission, transport_count, new_transport_path) do",
  "  defp breadcrumbs_presentation(mission) do",
  "transport-list header presentation DTO",
)

for (const text of [
  "Transports",
  "Durable byte-moving capabilities Cadence can use for inbound, outbound, or bidirectional spacecraft traffic.",
  "New Transport",
  "No transports",
  "Create a transport to describe an external capability for moving bytes.",
  "Create the first transport",
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
  "btn btn-primary btn-sm gap-1",
  "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center",
  "hud-label",
  "mt-2 max-w-md mx-auto text-sm text-base-content/70",
  "btn btn-primary btn-sm",
  "card bg-base-200 border border-base-300",
  "card-body p-0",
]) {
  assert.ok(presentationSource.includes(`"${className}"`), `${className} stays Phoenix-owned`)
}

for (const route of [
  '~p"/missions/#{mission.mission_id}"',
  '~p"/missions/#{mission.mission_id}/comms"',
  '~p"/missions/#{mission.mission_id}/comms/transports/new"',
]) {
  assert.ok(presentationSource.includes(route), `${route} remains server-verified`)
}

for (const prop of [
  "rows",
  "search",
  "sort",
  "sort_dir",
  "page",
  "page_size",
  "total_count",
]) {
  assert.match(presentationSource, new RegExp(`"${prop}" =>`))
}

assert.match(presentationSource, /"data-phx-link" => "redirect"/)
assert.match(presentationSource, /"data-phx-link-state" => "push"/)
assert.match(presentationSource, /"aria-hidden" => "true"/)
assert.match(presentationSource, /empty_state_presentation\(transports_empty\?, new_transport_path\)/)
assert.match(presentationSource, /card_presentation\(transports_empty\?, rows, list, total\)/)
assert.match(presentationSource, /"id" => "comms-transports-page"/)
assert.match(presentationSource, /"id" => "new-transport-link"/)
assert.match(presentationSource, /"id" => "transports-list-component"/)
assert.match(headerPresentationSource, /"new_transport" => %\{/)
assert.match(headerPresentationSource, /"icon" => %\{/)
assert.match(headerPresentationSource, /"class" => "hero-plus h-4 w-4"/)

for (const decision of [
  "defp transport_table_row(transport, mission_id)",
  "defp origin_label(:provider_managed)",
  "defp provider_label(%{origin: :provider_managed} = transport)",
  "defp operator_summary(%{origin: :provider_managed} = transport)",
  "defp readiness_status(%{origin: :provider_managed} = transport)",
  "defp readiness_label(%{origin: :provider_managed} = transport)",
]) {
  assert.ok(liveViewSource.includes(decision), `${decision} remains Phoenix-owned`)
}

for (const childContract of [
  'phx-change="search"',
  'phx-click="sort"',
  'phx-click="paginate"',
  ':phx-value-page="page - 1"',
  ':phx-value-page="page + 1"',
  'data-phx-link="redirect"',
  'data-phx-link-state="push"',
  'id="transports-toolbar-search-form"',
  'id="transports-table"',
  'id="transports-pagination"',
]) {
  assert.ok(childSource.includes(childContract), `${childContract} stays in the immutable child`)
}

const broadTestSource = sourceSlice(
  liveViewTestSource,
  '  describe "transport routes" do',
  "  defp transport_list_props(view) do",
  "transport LiveView scenario ledger",
)

for (const scenario of [
  'test "renders the empty state when the mission has no transports"',
  'test "lists transports with origin, operator summary, and readiness"',
  'test "search narrows the transport list"',
  'test "sorts through the LiveView-owned list event"',
  'test "paginates through the LiveView event and keeps visible rows in props"',
  'test "progressively configures and shows a direct TCP transport"',
  'test "derives a provider-managed Transport from compatible synchronized profiles"',
  'test "missing transport redirects to the current mission transport list"',
  'test "does not expose transports outside the current organization or mission scope"',
  'test "keeps unvalidated providers out of the selectable provider flow"',
  'test "renders a stable validation outcome for invalid direct TCP setup"',
]) {
  assert.ok(broadTestSource.includes(scenario), `${scenario} remains one-for-one`)
}

assert.match(
  liveViewTestSource,
  /LiveVue\.Test\.get_vue\(view, id: "comms-transport-list-page-component"\)/,
)
assert.doesNotMatch(
  liveViewTestSource,
  /LiveVue\.Test\.get_vue\(view, id: "transports-list-component"\)/,
)
assert.match(liveViewTestSource, /Map\.keys\(vue\.props\) == \["presentation"\]/)
assert.match(broadTestSource, /Jason\.decode!\(Jason\.encode!\(presentation\)\)/)
assert.match(broadTestSource, /CommsTransportListLive\.presentation_attrs/)
assert.match(broadTestSource, /"nil" => nil/)
assert.match(broadTestSource, /"false" => false/)
assert.match(broadTestSource, /"true" => true/)
assert.match(broadTestSource, /"number" => 7/)

assert.match(
  routerSource,
  /scope "\/", CadenceWeb do\n    pipe_through \[:browser, :require_authenticated_scope\]/,
)

const commsSession = sourceSlice(
  routerSource,
  "    live_session :comms,",
  "    live_session :ops_dashboard_author,",
  "comms LiveSession",
)

assert.match(commsSession, /CadenceWeb\.OrganizationAuth, :require_organization_scope/)
assert.match(commsSession, /CadenceWeb\.MissionAuth, :load_mission/)
assert.match(commsSession, /CadenceWeb\.UserAuth, :attach_user_menu/)
assert.match(commsSession, /layout: \{CadenceWeb\.Layouts, :mission_sidebar\}/)
assert.match(
  commsSession,
  /live "\/missions\/:mission_id\/comms\/transports",\s+CommsTransportListLive,\s+:index/,
)
assert.doesNotMatch(commsSession, /require_organization_admin|require_platform_admin/)
