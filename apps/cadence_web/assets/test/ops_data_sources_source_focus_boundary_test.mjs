import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

assert.equal(process.versions.node, "24.16.0", "contracts use pinned Node 24.16.0")

const scenarios = [
  "resource panel links resolved operational context to verified mission routes",
  "remediation panel preserves dashboard return defaults",
  "evidence panel renders selected evidence and explicit return activity",
]

const __dirname = dirname(fileURLToPath(import.meta.url))
const vuePath = resolve(__dirname, "../vue/OpsDataSources.vue")
const pagePath = resolve(__dirname, "../../lib/cadence_web/live/ops_data_sources_live/page.ex")
const liveViewPath = resolve(__dirname, "../../lib/cadence_web/live/ops_data_sources_live.ex")
const routerPath = resolve(__dirname, "../../lib/cadence_web/router.ex")
const testPath = resolve(
  __dirname,
  "../../test/cadence_web/live/ops_data_sources_live/source_focus_components_test.exs",
)
const [vueSource, pageSource, liveViewSource, routerSource, testSource] = await Promise.all([
  readFile(vuePath, "utf8"),
  readFile(pagePath, "utf8"),
  readFile(liveViewPath, "utf8"),
  readFile(routerPath, "utf8"),
  readFile(testPath, "utf8"),
])

const sourceSlice = (source, start, end, label) => {
  const startIndex = source.indexOf(start)
  const endIndex = source.indexOf(end, startIndex + start.length)

  assert.ok(startIndex >= 0 && endIndex > startIndex, `${label} remains source-auditable`)
  return source.slice(startIndex, endIndex)
}

for (const scenario of scenarios) {
  assert.equal(
    testSource.match(new RegExp(`test "${scenario}"`, "g"))?.length,
    1,
    `${scenario} remains exactly once`,
  )
}

assert.equal(testSource.match(/^  test "/gm)?.length, 3, "the three scenarios remain one-for-one")
assert.match(testSource, /render_component\(&Page\.render\/1,/)
assert.match(testSource, /LiveVue\.Test\.get_vue\(id: "ops-data-sources-component"\)/)
assert.match(
  testSource,
  /vue\.handlers\["open-register-source"\] == JS\.push\("open_register_source"\)/,
)
assert.doesNotMatch(testSource, /LazyHTML/)

const liveViewRender = sourceSlice(
  liveViewSource,
  "  @impl true\n  def render(assigns), do: Page.render(assigns)",
  "\n\n  defp assign_source_inventory",
  "OpsDataSourcesLive render delegation",
)

assert.match(liveViewRender, /Page\.render\(assigns\)/)

const pageRender = sourceSlice(
  pageSource,
  "  def render(assigns) do",
  "\n  defp page_dto",
  "OpsDataSources LiveVue parent",
)

assert.equal(pageRender.match(/<\.vue\b/g)?.length, 1)
assert.match(pageRender, /id="ops-data-sources-component"/)
assert.match(pageRender, /v-component="OpsDataSources"/)
assert.match(pageRender, /page=\{@ops_data_sources_page\}/)
assert.match(pageRender, /v-on:open-register-source=\{JS\.push\("open_register_source"\)\}/)
assert.match(pageRender, /v-ssr=\{false\}/)

const focusDto = sourceSlice(
  pageSource,
  "  defp remediation_dto",
  "\n  defp binding_group_dto",
  "server-authored source focus DTO",
)

for (const contract of [
  'id: "source-focus-remediation"',
  'id: "source-focus-register-source"',
  'event: "open_register_source"',
  "payload: %{}",
  'id: "source-focus-resource"',
  'heading: "Operational resource context"',
  'id: "source-focus-evidence"',
  '"source-focus-dashboard-return"',
  '"source-focus-evidence-dashboard-return"',
  'label: "Return to dashboard readiness"',
]) {
  assert.ok(focusDto.includes(contract), `Phoenix retains ${contract}`)
}

for (const route of [
  '~p"/missions/#{mission_id}/comms/transports/#{transport_id}"',
  '~p"/missions/#{mission_id}/comms?#{%{source_endpoint_id: source_endpoint_id}}"',
  '~p"/missions/#{mission_id}/comms/routing/#{routing_rule_id}"',
  '~p"/missions/#{mission_id}/comms/ground-stations/#{ground_station_id}"',
  '~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}?#{params}"',
]) {
  assert.ok(focusDto.includes(route), `${route} remains server-authored`)
}

assert.match(focusDto, /SourceFocusPresentation\.remediation\(focus, sources\)/)
assert.match(focusDto, /SourceFocusResources\.build\(resources/)
assert.match(focusDto, /SourceFocusPresentation\.evidence\(focus\)/)
assert.match(focusDto, /"panel" => SourceFocus\.return_panel\(focus\)/)
assert.match(focusDto, /"activity_filter" => SourceFocus\.return_activity_filter\(focus\)/)
assert.match(focusDto, /"activity_event" => SourceFocus\.return_activity_event\(focus\)/)
assert.match(focusDto, /"refresh_readiness" => SourceFocus\.return_refresh_readiness\(focus\)/)

const script = vueSource.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = vueSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "OpsDataSources.vue has an auditable TypeScript setup block")
assert.ok(template, "OpsDataSources.vue has an auditable template block")
assert.match(script, /event: "open_register_source"/)
assert.match(script, /"open-register-source": \[payload: EmptyPayload\]/)

for (const binding of [
  ':id="page.focus.remediation.id"',
  ':data-source-remediation-kind="page.focus.remediation.kind"',
  ':id="page.focus.remediation.action.id"',
  "@click=\"emit('open-register-source', {})\"",
  ':id="page.focus.remediation.dashboard_return.id"',
  ':href="page.focus.remediation.dashboard_return.href"',
  ':data-source-focus-dashboard-return-panel="page.focus.remediation.dashboard_return.panel"',
  ':data-source-focus-dashboard-return-activity-filter="page.focus.remediation.dashboard_return.activity_filter"',
  ':data-source-focus-dashboard-return-activity-event="page.focus.remediation.dashboard_return.activity_event"',
  ':id="page.focus.resource.id"',
  ':data-source-resource-selected-target="page.focus.resource.selected_target"',
  ':href="row.href"',
  ':data-source-resource-link="row.key"',
  ':id="page.focus.evidence.id"',
  ':data-source-evidence-state="page.focus.evidence.state"',
  ':id="page.focus.evidence.dashboard_return.id"',
  ':href="page.focus.evidence.dashboard_return.href"',
  ':data-source-focus-dashboard-return-panel="page.focus.evidence.dashboard_return.panel"',
  ':data-source-focus-dashboard-return-activity-filter="page.focus.evidence.dashboard_return.activity_filter"',
  ':data-source-focus-dashboard-return-activity-event="page.focus.evidence.dashboard_return.activity_event"',
]) {
  assert.ok(template.includes(binding), `${binding} remains connected to the page DTO`)
}

assert.doesNotMatch(vueSource, /\/missions\//)

const opsRoutes = sourceSlice(
  routerSource,
  "    live_session :ops,",
  "\n    live_session :ops_admin,",
  "reader Ops routes",
)
const adminRoutes = sourceSlice(
  routerSource,
  "    live_session :ops_admin,",
  "\n    # Legacy application URLs redirect",
  "administrator Ops routes",
)

assert.match(opsRoutes, /CadenceWeb\.OrganizationAuth, :require_organization_scope/)
assert.match(opsRoutes, /CadenceWeb\.MissionAuth, :load_mission/)
assert.match(opsRoutes, /live "\/missions\/:mission_id\/ops\/data-sources",\n           OpsDataSourcesLive,\n           :index/)
assert.match(opsRoutes, /live "\/missions\/:mission_id\/ops\/data-sources\/:data_source_id",\n           OpsDataSourcesLive,\n           :show/)
assert.match(adminRoutes, /CadenceWeb\.OrganizationAuth, :require_organization_admin/)
assert.match(adminRoutes, /live "\/missions\/:mission_id\/ops\/data-sources\/registration\/new",\n           OpsDataSourcesLive,\n           :new/)
assert.match(adminRoutes, /live "\/missions\/:mission_id\/ops\/data-sources\/:data_source_id\/settings",\n           OpsDataSourcesLive,\n           :settings/)
