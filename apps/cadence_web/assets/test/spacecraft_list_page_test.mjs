import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const scenarioLedger = [
  "the complete Spacecraft List page is one non-SSR LiveVue parent with one presentation prop",
  "Phoenix owns organization and mission scoping, ListParams, filtering, sorting, pagination, and patches",
  "Phoenix owns summary, roster, profile, drift, setup-status, label, and verified-route decisions",
  "the page root, exact header, breadcrumbs, and existing child visual contracts stay exact",
  "SpacecraftListPage directly composes the audited IDREF-repaired SpacecraftList child once",
  "the child receives its existing summary_tiles, roster, and profiles props without renaming",
  "breadcrumb and child navigation retain the existing LiveView redirect or patch semantics",
  "raw attrs preserve HEEx nil, false, true, string, and number behavior",
  "the ten existing Spacecraft List scenarios remain present one-for-one",
  "the Spacecraft Profile caller continues inspecting the same nested roster and profiles data",
  "handle_params recomputes the full presentation after every URL-driven list-state change",
  "the authenticated spacecraft route, mounts, action, and mission-sidebar layout stay unchanged",
  "router, caller, and tests use semantic source slices; only audited SpacecraftList.vue is hashed",
]

assert.equal(process.versions.node, "24.16.0", "spacecraft-list contracts use pinned Node 24.16.0")
assert.equal(scenarioLedger.length, 13)

const __dirname = dirname(fileURLToPath(import.meta.url))
const pagePath = resolve(__dirname, "../vue/SpacecraftListPage.vue")
const childPath = resolve(__dirname, "../vue/SpacecraftList.vue")
const liveViewPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/spacecraft_list_live.ex",
)
const liveViewTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/spacecraft_list_live_test.exs",
)
const profileCallerTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/spacecraft_profile_live_test.exs",
)
const routerPath = resolve(__dirname, "../../lib/cadence_web/router.ex")

const [
  pageSource,
  childSource,
  liveViewSource,
  liveViewTestSource,
  profileCallerTestSource,
  routerSource,
] = await Promise.all([
  readFile(pagePath, "utf8"),
  readFile(childPath, "utf8"),
  readFile(liveViewPath, "utf8"),
  readFile(liveViewTestPath, "utf8"),
  readFile(profileCallerTestPath, "utf8"),
  readFile(routerPath, "utf8"),
])

const sourceSlice = (source, start, end, label) => {
  const startIndex = source.indexOf(start)
  const endIndex = source.indexOf(end, startIndex + start.length)

  assert.ok(startIndex >= 0 && endIndex > startIndex, `${label} must remain source-auditable`)
  return source.slice(startIndex, endIndex)
}

const assertBalancedTemplate = (source) => {
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
      assert.equal(stack.pop(), name, `${name} closes the current SFC element`)
    } else if (!token.endsWith("/>") && !voidElements.has(name)) {
      stack.push(name)
    }
  }

  assert.deepEqual(stack, [], "SFC template tags are balanced")
}

assert.equal(
  createHash("sha256").update(childSource).digest("hex"),
  "b322bffd1e6082c1d7f18a942c3a5879e2751beceb2e3d0f41175d2a11e25669",
  "SpacecraftList.vue remains the explicitly audited child",
)

const script = pageSource.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = pageSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "SpacecraftListPage.vue must have a TypeScript script setup block")
assert.ok(template, "SpacecraftListPage.vue must have a template block")
assertBalancedTemplate(template)

assert.match(script, /import SpacecraftList from "\.\/SpacecraftList\.vue"/)
assert.match(script, /type SpacecraftListProps = InstanceType<typeof SpacecraftList>\["\$props"\]/)
assert.match(script, /summary_tiles: SpacecraftListProps\["summary_tiles"\]/)
assert.match(script, /roster: SpacecraftListProps\["roster"\]/)
assert.match(script, /profiles: SpacecraftListProps\["profiles"\]/)
assert.match(script, /defineProps<\{presentation: Presentation\}>\(\)/)
assert.equal(template.match(/<SpacecraftList\b/g)?.length, 1)
assert.match(
  template,
  /<SpacecraftList\s+:summary_tiles="props\.presentation\.summary_tiles"\s+:roster="props\.presentation\.roster"\s+:profiles="props\.presentation\.profiles"\s+\/>/,
)

for (const binding of [
  "props.presentation.root.attrs",
  "props.presentation.header.attrs",
  "props.presentation.header.body.attrs",
  "props.presentation.header.content.attrs",
  "props.presentation.breadcrumbs.attrs",
  "item.separator.attrs",
  "item.link.attrs",
  "item.current.attrs",
  "props.presentation.header.title.attrs",
  "props.presentation.header.subtitle.attrs",
]) {
  assert.ok(template.includes(`v-bind="${binding}"`), `${binding} stays DTO-owned`)
}

for (const textBinding of [
  "item.separator.text",
  "item.link.text",
  "item.current.text",
  "props.presentation.header.title.text",
  "props.presentation.header.subtitle.text",
]) {
  assert.ok(template.includes(`{{ ${textBinding} }}`), `${textBinding} stays DTO-owned`)
}

assert.doesNotMatch(
  pageSource,
  /Manage mission spacecraft|space-y-6|border-primary|text-2xl|\/missions|data-phx-link/,
)
assert.doesNotMatch(
  pageSource,
  /sort\(|\.sort\(|filter\(|\.filter\(|slice\(|\.slice\(|pushPatch|pushEvent|v-html/,
)
assert.doesNotMatch(pageSource, /<\.vue|v-component=|phx-click|phx-change|phx-submit/)

for (const childContract of [
  "defineProps<{",
  "summary_tiles: SummaryTile[]",
  "roster: Roster",
  "profiles: Profiles",
  'id="spacecraft-list-content" class="space-y-6"',
  'phx-change="search"',
  'phx-click="sort"',
  'phx-click="paginate"',
]) {
  assert.ok(childSource.includes(childContract), `${childContract} remains in the audited child`)
}

const mountSource = sourceSlice(
  liveViewSource,
  "  def mount(_params, _session, socket) do",
  "  @impl true\n  def handle_params(params, _uri, socket) do",
  "SpacecraftListLive mount",
)

assert.match(mountSource, /socket\.assigns\.current_mission/)
assert.match(mountSource, /socket\.assigns\.current_scope\.organization_id/)
assert.match(mountSource, /Cadence\.SpacecraftTypeStore\.list_spacecraft_types/)
assert.match(mountSource, /Cadence\.SpacecraftStore\.fleet_summary/)
assert.match(mountSource, /assign\(:profiles, profiles\)/)
assert.match(mountSource, /assign\(:profiles_by_id,/)
assert.match(mountSource, /assign\(:latest_versions, latest_versions\)/)
assert.match(mountSource, /assign\(:summary, summary\)/)
assert.match(mountSource, /assign\(:drift_count,/)
assert.match(mountSource, /assign\(:version_counts_by_profile,/)
assert.match(mountSource, /assign\(:presentation, nil\)/)

const handleParamsSource = sourceSlice(
  liveViewSource,
  "  def handle_params(params, _uri, socket) do",
  '  @impl true\n  def handle_event("search", %{"q" => q}, socket) do',
  "SpacecraftListLive handle_params",
)

assert.match(
  handleParamsSource,
  /ListParams\.parse\(params, sortable: @sortable, default_sort: "display_name"\)/,
)
assert.match(handleParamsSource, /filter = parse_filter\(params\["filter"\]\)/)
assert.match(handleParamsSource, /fetch_roster\(organization_id, mission\.mission_id, list, filter, socket\)/)
assert.match(
  handleParamsSource,
  /presentation = page_presentation_dto\(mission, list, filter, page, socket\)/,
)
assert.match(handleParamsSource, /assign\(:list, list\)/)
assert.match(handleParamsSource, /assign\(:filter, filter\)/)
assert.match(handleParamsSource, /assign\(:presentation, presentation\)/)

const eventSource = sourceSlice(
  liveViewSource,
  '  def handle_event("search", %{"q" => q}, socket) do',
  "  @impl true\n  def render(assigns) do",
  "SpacecraftListLive URL-driven events",
)

for (const event of ["search", "sort", "paginate"]) {
  assert.ok(eventSource.includes(`handle_event("${event}"`), `${event} remains server-owned`)
}

assert.match(eventSource, /ListParams\.toggle_sort/)
assert.match(eventSource, /ListParams\.parse\(%\{"page" => page\}, sortable: \[\]\)\.page/)
assert.equal(eventSource.match(/patch_roster\(/g)?.length, 3)

const renderSource = sourceSlice(
  liveViewSource,
  "  def render(assigns) do",
  "  @doc false",
  "SpacecraftListLive render boundary",
)

assert.equal(renderSource.match(/<\.vue/g)?.length, 1)
assert.match(renderSource, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(renderSource, /id="spacecraft-list-component"/)
assert.match(renderSource, /v-component="SpacecraftListPage"/)
assert.match(renderSource, /presentation=\{@presentation\}/)
assert.match(renderSource, /v-ssr=\{false\}/)
assert.match(renderSource, /class="contents"/)
assert.doesNotMatch(renderSource, /<\.page_header|summary_tiles=|roster=|profiles=/)
assert.doesNotMatch(renderSource, /spacecraft-management-page|SpacecraftList"/)

const rawAttrsSource = sourceSlice(
  liveViewSource,
  "  @doc false\n  def presentation_attrs(attrs) when is_map(attrs) do",
  "  defp page_presentation_dto(mission, list, filter, page, socket) do",
  "Spacecraft List raw attribute projection",
)

assert.match(rawAttrsSource, /value in \[nil, false\]/)
assert.match(rawAttrsSource, /\{name, true\}, rendered/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, ""\)/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, to_string\(value\)\)/)

const presentationSource = sourceSlice(
  liveViewSource,
  "  defp page_presentation_dto(mission, list, filter, page, socket) do",
  "  defp fetch_roster(organization_id, mission_id, list, filter, socket) do",
  "Spacecraft List page presentation DTO",
)

for (const topLevelKey of [
  "root",
  "header",
  "breadcrumbs",
  "summary_tiles",
  "roster",
  "profiles",
]) {
  assert.ok(presentationSource.includes(`"${topLevelKey}" =>`), `${topLevelKey} stays in presentation`)
}

for (const text of [
  "Spacecraft",
  "Manage mission spacecraft identities and reusable spacecraft profiles.",
]) {
  assert.ok(presentationSource.includes(`"${text}"`), `${text} stays Phoenix-owned`)
}

for (const className of [
  "space-y-6",
  "border-b border-primary/20 pb-4",
  "mt-2 text-2xl font-bold text-base-content tracking-tight",
  "mt-1 max-w-3xl text-sm text-base-content/70",
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60",
  "hover:text-primary transition-colors",
  "text-base-content/20",
  "text-primary/90",
]) {
  assert.ok(presentationSource.includes(`"${className}"`), `${className} stays Phoenix-owned`)
}

assert.match(presentationSource, /"id" => "spacecraft-management-page"/)
assert.match(presentationSource, /~p"\/missions\/#\{mission\.mission_id\}"/)
assert.match(presentationSource, /"data-phx-link" => "redirect"/)
assert.match(presentationSource, /"data-phx-link-state" => "push"/)
assert.match(presentationSource, /summary_tiles_dto\(/)
assert.match(presentationSource, /roster_dto\(/)
assert.match(presentationSource, /profiles_dto\(/)

for (const serverDecision of [
  "defp fetch_roster",
  "defp patch_roster",
  "defp parse_filter",
  "defp serialize_filter",
  "defp store_filter",
  "defp sort_tuple",
  "defp summary_tiles_dto",
  "defp roster_dto",
  "defp spacecraft_row_dto",
  "defp profiles_dto",
  "defp profile_row_dto",
  "defp profile_fleet_entries",
  "defp filter_path",
  "defp setup_status",
  "defp setup_status_label",
  "defp profile_drift?",
  "defp profile_status",
  "defp profile_status_label",
  "defp applications_summary",
  "defp drift_count",
  "defp version_counts_by_profile",
]) {
  assert.ok(liveViewSource.includes(serverDecision), `${serverDecision} remains in Phoenix`)
}

assert.match(liveViewSource, /Cadence\.SpacecraftStore\.list_spacecraft_page\(/)
assert.match(liveViewSource, /ListParams\.to_query\(list, filter:/)
assert.match(liveViewSource, /push_patch\(socket, to: ~p"\/missions\/#\{mission_id\}\/spacecraft\?#\{query\}"\)/)
assert.match(liveViewSource, /@page_size 50/)
assert.match(liveViewSource, /@profile_preview_limit 5/)
assert.match(liveViewSource, /@sortable ~w\(display_name scid\)/)

const helperSource = sourceSlice(
  liveViewTestSource,
  "  defp spacecraft_list_props(view) do",
  '  describe "mount" do',
  "Spacecraft List shared test helper",
)

assert.match(helperSource, /LiveVue\.Test\.get_vue\(view, id: "spacecraft-list-component"\)/)
assert.match(helperSource, /vue\.component == "SpacecraftListPage"/)
assert.match(helperSource, /Map\.keys\(vue\.props\) == \["presentation"\]/)
assert.match(helperSource, /vue\.props\["presentation"\]/)

for (const scenario of [
  'test "renders empty state when there are no spacecraft"',
  'test "renders spacecraft through JSON-safe roster props"',
  'test "shows only spacecraft belonging to this mission"',
  'test "shows only spacecraft belonging to the current organization"',
  'test "name cell links to the spacecraft show page"',
  'test "search narrows the roster"',
  'test "filter tiles patch to a filtered roster"',
  'test "sorts by SCID descending via the header button"',
  'test "paginates past fifty spacecraft"',
  'test "filtered-empty roster keeps the table copy, not the empty-mission state"',
]) {
  assert.equal(
    liveViewTestSource.split(scenario).length - 1,
    1,
    `${scenario} remains present one-for-one`,
  )
}

for (const existingChildPath of [
  '["roster"]["fleet_empty"]',
  '["roster"]["rows"]',
  '["summary_tiles"]',
  '["profiles"]["empty"]',
]) {
  assert.ok(liveViewTestSource.includes(existingChildPath), `${existingChildPath} remains asserted`)
}

assert.match(liveViewTestSource, /Jason\.decode!\(Jason\.encode!\(presentation\)\)/)
assert.match(liveViewTestSource, /SpacecraftListLive\.presentation_attrs/)
assert.match(liveViewTestSource, /"nil" => nil/)
assert.match(liveViewTestSource, /"false" => false/)
assert.match(liveViewTestSource, /"true" => true/)
assert.match(liveViewTestSource, /"number" => 7/)

const profileCallerSource = sourceSlice(
  profileCallerTestSource,
  '    test "spacecraft management page exposes vehicle and profile cards with scoped actions"',
  '    test "mission sidebar keeps profiles under the spacecraft area"',
  "Spacecraft Profile management-page caller",
)

assert.match(profileCallerSource, /vue\.component == "SpacecraftListPage"/)
assert.match(profileCallerSource, /presentation = vue\.props\["presentation"\]/)
assert.match(profileCallerSource, /presentation\["root"\]\["attrs"\]\["id"\]/)
assert.match(profileCallerSource, /presentation\["roster"\]\["new_spacecraft_href"\]/)
assert.match(profileCallerSource, /presentation\["profiles"\]\["new_profile_href"\]/)
assert.match(profileCallerSource, /presentation\["roster"\]\["rows"\]/)
assert.match(profileCallerSource, /presentation\["profiles"\]\["rows"\]/)

assert.match(
  routerSource,
  /scope "\/", CadenceWeb do\n    pipe_through \[:browser, :require_authenticated_scope\]/,
)

const spacecraftSession = sourceSlice(
  routerSource,
  "    live_session :spacecraft,",
  "    live_session :spacecraft_show,",
  "spacecraft LiveSession",
)

assert.match(spacecraftSession, /CadenceWeb\.OrganizationAuth, :require_organization_scope/)
assert.match(spacecraftSession, /CadenceWeb\.MissionAuth, :load_mission/)
assert.match(spacecraftSession, /CadenceWeb\.UserAuth, :attach_user_menu/)
assert.match(spacecraftSession, /layout: \{CadenceWeb\.Layouts, :mission_sidebar\}/)
assert.match(
  spacecraftSession,
  /live "\/missions\/:mission_id\/spacecraft", SpacecraftListLive, :index/,
)
assert.doesNotMatch(
  spacecraftSession,
  /require_organization_admin|require_platform_admin|load_spacecraft/,
)
