import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const scenarioLedger = [
  "the full diagnostics page is one always-present non-SSR LiveVue parent",
  "the parent receives exactly one ordinary JSON-safe presentation prop plus diagnostic_rows",
  "the existing diagnostic_rows LiveStream remains native and preserves server order",
  "LiveVue supplies each row __dom_id and Vue consumes it without server enumeration",
  "Phoenix retains dashboard fetch plus organization and mission scoping",
  "Phoenix retains all seven diagnostic collections in exact tab order",
  "Phoenix retains runtime query normalization plus collection and selected-row decisions",
  "Phoenix retains counts, row identity, status, details, status classes, and selected styling",
  "Phoenix retains viewer, collection patch, row patch, explore, sources, catalog, and admin paths",
  "Phoenix retains platform-admin visibility while Vue only renders the supplied links",
  "the component directly composes the byte-for-byte immutable ClipboardButton once",
  "all existing ids, classes, text, aria labels, and data attributes remain server-authored",
  "raw attrs preserve HEEx nil, false, true, string false, empty-string, and number behavior",
  "both named domain scenarios and each prior oracle remain translated in place",
  "the authenticated ops route, ordered on_mount hooks, ops layout, and show action stay unchanged",
]

assert.equal(process.versions.node, "24.16.0")
assert.equal(scenarioLedger.length, 15)

const __dirname = dirname(fileURLToPath(import.meta.url))
const pagePath = resolve(__dirname, "../vue/OpsDashboardDiagnostics.vue")
const childPath = resolve(__dirname, "../vue/ClipboardButton.vue")
const liveViewPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_diagnostics_live.ex",
)
const liveViewTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/ops_dashboard_diagnostics_live_test.exs",
)
const routerPath = resolve(__dirname, "../../lib/cadence_web/router.ex")

const [pageSource, childSource, liveViewSource, liveViewTestSource, routerSource] =
  await Promise.all([
    readFile(pagePath, "utf8"),
    readFile(childPath, "utf8"),
    readFile(liveViewPath, "utf8"),
    readFile(liveViewTestPath, "utf8"),
    readFile(routerPath, "utf8"),
  ])

const sourceSlice = (source, start, end, label) => {
  const startIndex = source.indexOf(start)
  const endIndex = source.indexOf(end, startIndex + start.length)

  assert.ok(startIndex >= 0 && endIndex > startIndex, `${label} stays source-auditable`)
  return source.slice(startIndex, endIndex)
}

const assertBalancedTemplate = source => {
  const stack = []

  for (const match of source.matchAll(/<\/?([A-Za-z][\w.-]*)(?:\s[^<>]*?)?>/gs)) {
    const token = match[0]
    const name = match[1]

    if (token.startsWith("</")) {
      assert.equal(stack.pop(), name, `${name} closes the current SFC element`)
    } else if (!token.endsWith("/>")) {
      stack.push(name)
    }
  }

  assert.deepEqual(stack, [], "OpsDashboardDiagnostics.vue template tags are balanced")
}

assert.equal(
  createHash("sha256").update(childSource).digest("hex"),
  "67901b80e920b330ac6d1972ceb8bbee4f8ab54714a3e232bb46733dd121471e",
  "ClipboardButton.vue remains byte-for-byte immutable",
)

const script = pageSource.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = pageSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "the page has an auditable TypeScript setup block")
assert.ok(template, "the page has an auditable template block")
assertBalancedTemplate(template)

assert.match(script, /^import ClipboardButton from "\.\/ClipboardButton\.vue"$/m)
assert.equal(script.match(/import .*ClipboardButton\.vue/g)?.length, 1)
assert.match(script, /presentation: Presentation/)
assert.match(script, /diagnostic_rows: DiagnosticRow\[\]/)
assert.match(script, /__dom_id: string/)
assert.doesNotMatch(script, /computed|ref\(|reactive|watch\(|fetch\(|defineEmits|useRoute|router/)

assert.equal(template.match(/<ClipboardButton\b/g)?.length, 1)
assert.match(
  template,
  /<ClipboardButton\s+v-bind="props\.presentation\.detail\.selected\.header\.copy\.props"/,
)
assert.match(template, /v-for="row in props\.diagnostic_rows"/)
assert.match(template, /:id="row\.__dom_id"/)
assert.match(template, /:key="row\.__dom_id"/)
assert.doesNotMatch(pageSource, /\.sort|\.filter|\.slice|diagnostic_path|platform_admin|status_class/)
assert.doesNotMatch(
  pageSource,
  /Dashboard \/ Diagnostics|Back to Viewer|No records exist|Select a diagnostic|btn btn|text-primary|\/missions\//,
)

for (const binding of [
  "props.presentation.root.attrs",
  "props.presentation.header.attrs",
  "props.presentation.header.inner.attrs",
  "props.presentation.header.content.attrs",
  "props.presentation.header.eyebrow.attrs",
  "props.presentation.header.heading.attrs",
  "props.presentation.header.copy.attrs",
  "props.presentation.header.viewer.attrs",
  "props.presentation.content.attrs",
  "props.presentation.collections.attrs",
  "collection.attrs",
  "collection.count.attrs",
  "props.presentation.workspace.attrs",
  "props.presentation.master.attrs",
  "props.presentation.master.header.attrs",
  "props.presentation.master.header.label.attrs",
  "props.presentation.master.header.count.attrs",
  "props.presentation.master.stream.attrs",
  "props.presentation.master.stream.empty.attrs",
  "row.attrs",
  "row.header.attrs",
  "row.title.attrs",
  "row.status.attrs",
  "row.identity.attrs",
  "props.presentation.detail.attrs",
  "props.presentation.detail.selected.header.attrs",
  "props.presentation.detail.selected.header.content.attrs",
  "props.presentation.detail.selected.header.label.attrs",
  "props.presentation.detail.selected.header.title.attrs",
  "props.presentation.detail.selected.header.identity.attrs",
  "props.presentation.detail.selected.header.copy.host.attrs",
  "props.presentation.detail.selected.details.attrs",
  "item.attrs",
  "item.label.attrs",
  "item.value.attrs",
  "props.presentation.detail.selected.drilldowns.attrs",
  "link.attrs",
  "props.presentation.detail.empty.attrs",
]) {
  assert.ok(template.includes(`v-bind="${binding}"`), `${binding} stays Phoenix-authored`)
}

const handleParamsSource = sourceSlice(
  liveViewSource,
  "  def handle_params(params, _uri, socket) do",
  "  @impl true\n  def render(assigns) do",
  "diagnostics handle_params",
)

for (const authority of [
  'normalize_collection(params["collection"])',
  "Map.get(socket.assigns.diagnostic_collections, collection, [])",
  'select_row(rows, params["selected"])',
  "runtime_query(params)",
  "assign(:diagnostic_collection, collection)",
  "assign(:runtime_query, runtime_query)",
  "assign(:diagnostic_rows_list, rows)",
  "assign(:selected_diagnostic, selected)",
  "assign(:diagnostic_count, length(rows))",
  "assign_diagnostics_presentation()",
  "diagnostic_row_presentation(",
  "stream(socket, :diagnostic_rows, stream_rows, reset: true)",
]) {
  assert.ok(handleParamsSource.includes(authority), `Phoenix retains ${authority}`)
}

const renderSource = sourceSlice(
  liveViewSource,
  "  def render(assigns) do",
  "  defp load_diagnostics(socket) do",
  "diagnostics render boundary",
)

assert.equal(renderSource.match(/<\.vue\b/g)?.length, 1)
assert.match(renderSource, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(renderSource, /id="ops-dashboard-diagnostics-page-component"/)
assert.match(renderSource, /v-component="OpsDashboardDiagnostics"/)
assert.match(renderSource, /presentation=\{@presentation\}/)
assert.match(renderSource, /diagnostic_rows=\{@streams\.diagnostic_rows\}/)
assert.match(renderSource, /v-diff=\{false\}/)
assert.match(renderSource, /v-ssr=\{false\}/)
assert.match(renderSource, /class="contents"/)
assert.doesNotMatch(renderSource, /id="dashboard-diagnostics-page"|ClipboardButton|:for=|<section/)

const loadSource = sourceSlice(
  liveViewSource,
  "  defp load_diagnostics(socket) do",
  "  @doc false\n  def presentation_attrs",
  "dashboard load authority",
)

for (const authority of [
  "Cadence.Dashboards.fetch_document(",
  "scope.organization_id",
  "mission.mission_id",
  "diagnostic_collections(scope, mission, document)",
  'Map.get(collections, "plan", [])',
  "select_row(rows, nil)",
  "assign(:diagnostic_collections, collections)",
  "assign_diagnostics_presentation()",
  'put_flash(:error, "Dashboard diagnostics are unavailable.")',
  'push_navigate(to: ~p"/missions/#{mission.mission_id}/ops/dashboards")',
]) {
  assert.ok(loadSource.includes(authority), `dashboard loading retains ${authority}`)
}

const presentationSource = sourceSlice(
  liveViewSource,
  "  @doc false\n  def presentation_attrs",
  "  defp diagnostic_collections(scope, mission, document) do",
  "diagnostics presentation boundary",
)

assert.doesNotMatch(
  presentationSource,
  /"phx-update"/,
  "the Vue-owned keyed stream subtree has no legacy LiveView morphdom ownership",
)

for (const id of [
  "dashboard-diagnostics-page",
  "dashboard-diagnostics-viewer",
  "dashboard-diagnostic-collections",
  "dashboard-diagnostic-count",
  "dashboard-diagnostic-rows",
  "dashboard-diagnostic-rows-empty",
  "dashboard-diagnostic-detail",
  "dashboard-diagnostic-copy-identity-component",
  "dashboard-diagnostic-copy-identity",
  "diagnostics-open-explore",
  "diagnostics-open-sources",
  "diagnostics-open-catalog",
  "diagnostics-open-admin-runtime",
]) {
  assert.ok(presentationSource.includes(`"${id}"`), `${id} remains server-authored`)
}

for (const authority of [
  "diagnostic_path(",
  "collection_class(collection, selected_collection)",
  "diagnostic_row_class(row, selected)",
  "Enum.join(status_class(row.status), \" \")",
  "detail_label(key)",
  "detail_value(value)",
  "platform_admin?(scope)",
  '"data-phx-link" => "redirect"',
  '"data-phx-link" => "patch"',
  '"data-name" => "ClipboardButton"',
]) {
  assert.ok(presentationSource.includes(authority), `Phoenix presentation retains ${authority}`)
}

for (const rawAttrContract of [
  "value in [nil, false]",
  "{name, true}, rendered",
  'Map.put(rendered, to_string(name), "")',
  "Map.put(rendered, to_string(name), to_string(value))",
]) {
  assert.ok(presentationSource.includes(rawAttrContract), `${rawAttrContract} stays explicit`)
}

const rawAttrs = attrs =>
  Object.fromEntries(
    Object.entries(attrs)
      .filter(([, value]) => value !== null && value !== false)
      .map(([name, value]) => [name, value === true ? "" : String(value)]),
  )

assert.deepEqual(
  rawAttrs({nil: null, false: false, true: true, stringFalse: "false", empty: "", number: 7}),
  {true: "", stringFalse: "false", empty: "", number: "7"},
)

const collectionsSource = sourceSlice(
  liveViewSource,
  "  defp diagnostic_collections(scope, mission, document) do",
  "  defp plan_rows(document) do",
  "seven diagnostic collections",
)

for (const collection of [
  '"plan" => plan_rows(document)',
  '"requests" => request_rows(document)',
  '"frames" => frame_rows(document)',
  '"cache" => cache_rows(document)',
  '"source" => source_rows(source_events)',
  '"refresh" => decision_rows(invalidations, "refresh")',
  '"invalidations" => decision_rows(invalidations, "invalidation")',
]) {
  assert.ok(collectionsSource.includes(collection), `${collection} remains present and ordered`)
}

assert.match(
  liveViewSource,
  /@collections ~w\(plan requests frames cache source refresh invalidations\)/,
)
assert.match(liveViewSource, /stream_configure\(:diagnostic_rows,/)
assert.match(liveViewSource, /dom_id: &"dashboard-diagnostic-row-#\{&1\.id\}"/)
assert.match(liveViewSource, /@runtime_query_keys ~w\([^\n]+selected_id\)/)
assert.match(liveViewSource, /defp normalize_collection\(collection\) when collection in @collections/)
assert.match(liveViewSource, /defp select_row\(rows, id\), do: Enum\.find/)

for (const scenario of [
  'test "diagnostic collections and master detail selection have stable URLs"',
  'test "durable invalidation decisions expose context, impact, and refresh evidence"',
]) {
  assert.equal(liveViewTestSource.match(new RegExp(scenario, "g"))?.length, 1)
}

for (const translatedOracle of [
  'cache_tab["attrs"]["class"] =~ "text-primary"',
  'cache_row["__dom_id"] == "dashboard-diagnostic-row-cache-contract"',
  'copy["component"] == "ClipboardButton"',
  'copy["props"]["button_id"] == "dashboard-diagnostic-copy-identity"',
  'copy["props"]["clipboard_text"] == "#{dashboard.dashboard_id}:cache"',
  'copy["props"]["button_class"] == "btn btn-outline btn-xs"',
  'copy["props"]["icon"] == "hero-clipboard"',
  'copy["props"]["icon_class"] == "h-3.5 w-3.5"',
  'copy["props"]["label"] == "Copy identity"',
  'copy["host"]["attrs"]["class"] == "contents"',
  "refute vue.ssr",
  '"diagnostics-open-explore"',
  '"diagnostics-open-sources"',
  '"diagnostics-open-catalog"',
  "assert_patch(",
  '["count"]["text"] == "0"',
  "assert {:ok, decision} =",
  '["count"]["text"] == "1"',
  "assert row",
  'row["status"]["text"] == "filtered"',
  'row["title"]["text"] =~ "historical_data_changed"',
  'String.contains?(&1["value"]["text"], "replay_run_mismatch")',
  'String.contains?(&1["value"]["text"], "stale_for_context")',
  'copy["props"]["clipboard_text"] =~ decision.invalidation_event_id',
]) {
  assert.ok(liveViewTestSource.includes(translatedOracle), `${translatedOracle} remains covered`)
}

assert.match(liveViewTestSource, /Map\.keys\(vue\.props\) == \["presentation"\]/)
assert.match(liveViewTestSource, /vue\.use_diff == false/)
assert.match(liveViewTestSource, /"streams_diff" => vue\.streams_diff/)
assert.match(liveViewTestSource, /Jason\.decode!\(Jason\.encode!\(contract\)\)/)
assert.match(liveViewTestSource, /presentation_attrs\(%\{/)

const routeBoundary = sourceSlice(
  routerSource,
  '  scope "/", CadenceWeb do\n    pipe_through [:browser, :require_authenticated_scope]',
  "    live_session :ops_admin,",
  "authenticated ops route boundary",
)

for (const routeContract of [
  "live_session :ops,",
  "{CadenceWeb.OrganizationAuth, :require_organization_scope}",
  "{CadenceWeb.MissionAuth, :load_mission}",
  "{CadenceWeb.UserAuth, :attach_user_menu}",
  "{CadenceWeb.OpsShellHook, :default}",
  "layout: {CadenceWeb.Layouts, :ops}",
  'live "/missions/:mission_id/ops/dashboards/:dashboard_id/diagnostics",',
  "OpsDashboardDiagnosticsLive,",
  ":show",
]) {
  assert.ok(routeBoundary.includes(routeContract), `${routeContract} remains unchanged`)
}

console.log("ops dashboard diagnostics page contracts passed")
