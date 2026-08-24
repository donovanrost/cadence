import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const scenarioLedger = [
  "the complete Ops Timeline body is one always-present non-SSR LiveVue parent",
  "the parent receives exactly one ordinary JSON-safe presentation prop plus timeline_events",
  "Phoenix retains authenticated scope, mission context, MissionTimeline reads, and query normalization",
  "Phoenix retains selected-event, return, owner, explore, formatting, and projection decisions",
  "handle_params recomputes the complete presentation and resets the projected stream in read order",
  "LiveVue stream extraction injects each historical __dom_id without server-side enumeration",
  "the parent directly composes the byte-for-byte immutable ClipboardButton child once",
  "the filter owns only six ephemeral values initialized and refreshed from Phoenix presentation",
  "filter submit emits exactly timeline category, kind, severity, spacecraft_id, from, and to",
  "selection clear emits only to the existing clear_timeline_selection JS.push handler",
  "all historical ids, data attrs, classes, text, empty state, detail rows, and selected styling remain server-authored",
  "event links remain patch links while return, owner, and explore links remain navigate links",
  "raw attrs preserve HEEx nil, false, true, empty-string, string-false, string, and number behavior",
  "the single canonical mission-events test scenario and every original behavior oracle remain in place",
  "the authenticated ops route scope, ordered mounts, route, and ops layout remain unchanged",
]

assert.equal(process.versions.node, "24.16.0", "Ops Timeline contracts use pinned Node 24.16.0")
assert.equal(scenarioLedger.length, 15)

const __dirname = dirname(fileURLToPath(import.meta.url))
const pagePath = resolve(__dirname, "../vue/OpsTimeline.vue")
const childPath = resolve(__dirname, "../vue/ClipboardButton.vue")
const liveViewPath = resolve(__dirname, "../../lib/cadence_web/live/ops_timeline_live.ex")
const liveViewTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/ops_timeline_live_test.exs",
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

  assert.ok(startIndex >= 0 && endIndex > startIndex, `${label} must remain source-auditable`)
  return source.slice(startIndex, endIndex)
}

const assertBalancedTemplate = source => {
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
      assert.equal(stack.pop(), name, `${name} closes the current SFC element`)
    } else if (!token.endsWith("/>") && !voidElements.has(name)) {
      stack.push(name)
    }
  }

  assert.deepEqual(stack, [], "OpsTimeline.vue template tags are balanced")
}

assert.equal(
  createHash("sha256").update(childSource).digest("hex"),
  "67901b80e920b330ac6d1972ceb8bbee4f8ab54714a3e232bb46733dd121471e",
  "ClipboardButton.vue remains byte-for-byte immutable",
)

const script = pageSource.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = pageSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "OpsTimeline.vue has an auditable TypeScript setup block")
assert.ok(template, "OpsTimeline.vue has an auditable template block")
assertBalancedTemplate(template)

assert.match(script, /^import \{reactive, watch\} from "vue"$/m)
assert.match(script, /^import ClipboardButton from "\.\/ClipboardButton\.vue"$/m)
assert.equal(script.match(/import ClipboardButton/g)?.length, 1)
assert.match(script, /presentation: Presentation/)
assert.match(script, /timeline_events: TimelineEvent\[\]/)
assert.match(script, /__dom_id: string/)
assert.match(script, /const filterValues = reactive<FilterValues>\(\{\.\.\.props\.presentation\.filters\.values\}\)/)
assert.match(script, /watch\([\s\S]*props\.presentation\.filters\.values[\s\S]*Object\.assign\(filterValues, values\)/)
assert.match(script, /apply_timeline_filters: \[payload: \{timeline: FilterValues\}\]/)
assert.match(script, /clear_timeline_selection: \[payload: Record<string, never>\]/)
assert.match(script, /emit\("clear_timeline_selection", \{\}\)/)

const filterEmission = sourceSlice(
  script,
  "const applyFilters = () => {",
  "\n}\n\nconst clearSelection",
  "exact filter emission",
)

assert.match(filterEmission, /emit\("apply_timeline_filters", \{/)
assert.match(filterEmission, /timeline: \{/)

for (const key of ["category", "kind", "severity", "spacecraft_id", "from", "to"]) {
  assert.match(filterEmission, new RegExp(`${key}: filterValues\\.${key}`))
}

assert.equal(filterEmission.match(/filterValues\./g)?.length, 6)
assert.doesNotMatch(script, /fetch\(|useRoute|useRouter|window\.|location\.|new URL|\.sort\(|\.filter\(/)

assert.equal(template.match(/<ClipboardButton\b/g)?.length, 1)
assert.match(template, /<ClipboardButton[\s\S]*:button_id="props\.presentation\.body\.detail\.selected\.copy\.button_id"/)
assert.match(template, /:clipboard_text="props\.presentation\.body\.detail\.selected\.copy\.clipboard_text"/)
assert.match(template, /v-for="timelineEvent in props\.timeline_events"/)
assert.match(template, /:id="timelineEvent\.__dom_id"/)
assert.match(template, /:key="timelineEvent\.__dom_id"/)
assert.match(template, /v-bind="timelineEvent\.attrs"/)
assert.match(template, /@submit\.prevent="applyFilters"/)
assert.match(template, /@click="clearSelection"/)

for (const binding of [
  "props.presentation.root.attrs",
  "props.presentation.container.attrs",
  "props.presentation.header.attrs",
  "props.presentation.header.return_link.attrs",
  "props.presentation.filters.attrs",
  "field.wrapper.attrs",
  "field.label.attrs",
  "field.label_text.attrs",
  "field.control.attrs",
  "props.presentation.filters.submit.attrs",
  "props.presentation.body.attrs",
  "props.presentation.body.timeline.section.attrs",
  "props.presentation.body.timeline.header.attrs",
  "props.presentation.body.timeline.stream.attrs",
  "props.presentation.body.timeline.stream.empty.attrs",
  "props.presentation.body.detail.attrs",
  "props.presentation.body.detail.selected.copy.host_attrs",
  "row.value.attrs",
]) {
  assert.ok(template.includes(`v-bind="${binding}"`), `${binding} remains DTO-owned`)
}

for (const serverOwnedText of [
  "Mission Timeline",
  "Observe / Canonical event projection",
  "No canonical mission events match this context.",
  "Copy canonical event link",
  "Continue investigation",
  "Open owning workflow",
  "Explore telemetry context",
  "telemetry_backfill_failed",
]) {
  assert.doesNotMatch(pageSource, new RegExp(serverOwnedText.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")))
  assert.ok(liveViewSource.includes(`"${serverOwnedText}"`), `${serverOwnedText} stays server-authored`)
}

const renderSource = sourceSlice(
  liveViewSource,
  "  def render(assigns) do",
  "  @doc false",
  "OpsTimelineLive render boundary",
)

assert.equal(renderSource.match(/<\.vue\b/g)?.length, 1)
assert.match(renderSource, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(renderSource, /id="ops-timeline-page-component"/)
assert.match(renderSource, /v-component="OpsTimeline"/)
assert.match(renderSource, /presentation=\{@timeline_presentation\}/)
assert.match(renderSource, /timeline_events=\{@streams\.timeline_events\}/)
assert.match(renderSource, /v-on:apply_timeline_filters=\{JS\.push\("apply_timeline_filters"\)\}/)
assert.match(renderSource, /v-on:clear_timeline_selection=\{JS\.push\("clear_timeline_selection"\)\}/)
assert.match(renderSource, /v-diff=\{false\}/)
assert.match(renderSource, /v-ssr=\{false\}/)
assert.match(renderSource, /class="contents"/)
assert.doesNotMatch(renderSource, /<main|<\.form|@streams\.timeline_events.*:for|ClipboardButton/)

const handleParamsSource = sourceSlice(
  liveViewSource,
  "  def handle_params(params, _uri, socket) do",
  "  @impl true\n  def handle_event(\"apply_timeline_filters\"",
  "OpsTimelineLive handle_params authority",
)

for (const authority of [
  "%{current_scope: scope, current_mission: mission} = socket.assigns",
  "context = timeline_context(params)",
  "MissionTimeline.list_for_mission(",
  "scope.organization_id",
  "mission.mission_id",
  "event_read_opts(context)",
  "selected_event(scope.organization_id, mission.mission_id, context.event_id)",
  "Enum.map(events, &timeline_event_presentation(&1, mission.mission_id, context))",
  "timeline_presentation(mission.mission_id, context, selected_event)",
  "stream(:timeline_events, timeline_events, reset: true)",
]) {
  assert.ok(handleParamsSource.includes(authority), `Phoenix retains ${authority}`)
}

assert.doesNotMatch(handleParamsSource, /Enum\.(sort|filter|reverse)/)

const handlerSource = sourceSlice(
  liveViewSource,
  '  def handle_event("apply_timeline_filters", %{"timeline" => params}, socket) do',
  "  @impl true\n  def render(assigns) do",
  "OpsTimelineLive event handlers",
)

for (const contract of [
  "Map.take(params, ~w(category kind severity spacecraft_id from to))",
  'Map.delete("event_id")',
  "compact_query()",
  'push_patch(socket, to: ~p"/missions/#{mission_id}/ops/timeline?#{query}")',
  'def handle_event("clear_timeline_selection", _params, socket) do',
]) {
  assert.ok(handlerSource.includes(contract), `${contract} remains authoritative`)
}

const presentationSource = sourceSlice(
  liveViewSource,
  "  @doc false\n  def presentation_attrs(attrs) when is_map(attrs) do",
  "  defp timeline_context(params) do",
  "Ops Timeline presentation DTO",
)

for (const contract of [
  "value in [nil, false]",
  "{name, true}, rendered",
  'Map.put(rendered, name, "")',
  "Map.put(rendered, name, to_string(value))",
  '"data-phx-link" => "patch"',
  '"data-phx-link" => "redirect"',
  '"data-phx-link-state" => "push"',
  '"data-mission-event-kind" => event.kind',
  '"data-mission-event-category" => event.category',
  '"data-mission-event-severity" => event.severity || "none"',
  'row_class <> " border-l-2 border-primary bg-primary/10"',
  "event_rows(event)",
  "format_time(event.occurred_at)",
  "category_options()",
  "severity_options()",
  "return_path(mission_id, context)",
  "event_owner_path(mission_id, event)",
  "event_explore_path(mission_id, event, context)",
]) {
  assert.ok(presentationSource.includes(contract), `${contract} remains server-owned`)
}

assert.doesNotMatch(presentationSource, /"phx-update"/, "Vue owns the extracted stream DOM")

const renderAttrs = attrs =>
  Object.fromEntries(
    Object.entries(attrs).flatMap(([name, value]) => {
      if (value === null || value === false) return []
      if (value === true) return [[name, ""]]
      return [[name, String(value)]]
    }),
  )

assert.deepEqual(
  renderAttrs({
    nil: null,
    false: false,
    true: true,
    empty: "",
    string_false: "false",
    string: "value",
    number: 7,
  }),
  {true: "", empty: "", string_false: "false", string: "value", number: "7"},
)

assert.equal(liveViewTestSource.match(/^\s*test "/gm)?.length, 1)

for (const oracle of [
  'test "renders canonical mission events and round-trips originating dashboard context"',
  '"#ops-timeline-page-component.contents"',
  '"#ops-context-rail-component"',
  'Map.keys(vue.props) == ["presentation"]',
  '%{"props" => vue.props, "streams_diff" => vue.streams_diff}',
  '"mission-event-mission_event-operational-event-source-health-1"',
  '"mission-event-mission_event-operational-event-backfill-1"',
  '"timeline-selected-event-title"',
  '"timeline-copy-event-link"',
  '"timeline-open-event-owner"',
  '"timeline-explore-event"',
  '"timeline-return-to-origin"',
  'render_hook(view, "apply_timeline_filters"',
  '"scheduled_contact_interval"',
  "render_patch(view, contact_event[\"attrs\"][\"href\"])",
  "presentation_attrs",
]) {
  assert.ok(liveViewTestSource.includes(oracle), `${oracle} remains covered in the single scenario`)
}

const opsRouteSource = sourceSlice(
  routerSource,
  "    live_session :ops,",
  "    live_session :ops_admin,",
  "authenticated Ops route boundary",
)

const routeContracts = [
  "{CadenceWeb.OrganizationAuth, :require_organization_scope}",
  "{CadenceWeb.MissionAuth, :load_mission}",
  "{CadenceWeb.UserAuth, :attach_user_menu}",
  "{CadenceWeb.OpsShellHook, :default}",
  "layout: {CadenceWeb.Layouts, :ops}",
]

for (const contract of routeContracts) {
  assert.ok(opsRouteSource.includes(contract), `${contract} remains in the ops route boundary`)
}

for (let index = 1; index < routeContracts.length; index += 1) {
  assert.ok(
    opsRouteSource.indexOf(routeContracts[index - 1]) < opsRouteSource.indexOf(routeContracts[index]),
    `${routeContracts[index - 1]} remains ordered before ${routeContracts[index]}`,
  )
}

assert.match(
  opsRouteSource,
  /live "\/missions\/:mission_id\/ops\/timeline",\n\s+OpsTimelineLive,\n\s+:index/,
)

const authenticatedScope = sourceSlice(
  routerSource,
  '  scope "/", CadenceWeb do\n    pipe_through [:browser, :require_authenticated_scope]',
  "    live_session :organization,",
  "authenticated browser scope",
)

assert.match(authenticatedScope, /pipe_through \[:browser, :require_authenticated_scope\]/)

console.log("ops timeline page contracts passed")
