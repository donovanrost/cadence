import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {peelCadenceEmptyStateComponent} from "./empty_state_frame_test_support.mjs"
import {peelCadenceHoverTableRows} from "./hover_table_row_test_support.mjs"

const scenarioLedger = [
  "one always-present non-SSR CommsRoutingListPage host owns the complete list page",
  "the host exposes exactly one JSON-safe presentation prop and uses class contents",
  "Phoenix owns mission and organization scope, both stores, lookups, fallbacks, humanization, counts, rows, and routes",
  "CommsRoutingListPage composes the shared Cadence shell and byte-pinned CommsRoutingList child exactly once",
  "the Vue root, header, breadcrumbs, title suffix, actions, empty state, and card preserve exact DOM contracts",
  "routing-rules-list-component exists only inside the server-selected nonempty card",
  "all breadcrumb, creation, and row anchors retain LiveView redirect and push navigation semantics",
  "raw attrs preserve HEEx nil, false, true, empty-string, string, and number behavior",
  "all pre-migration scenarios and assertion oracles remain one-for-one in the broad routing test",
  "form, show, and spacecraft routing scenarios remain in place and list-return destinations stay exact",
  "the authenticated comms route, organization and mission mounts, user-menu mount, and mission-sidebar layout remain unchanged",
  "router, LiveView, and test contracts use semantic source slices; only the immutable child is hashed",
]

assert.equal(process.versions.node, "24.16.0", "routing-list contracts use pinned Node 24.16.0")
assert.equal(scenarioLedger.length, 12)

const __dirname = dirname(fileURLToPath(import.meta.url))
const pagePath = resolve(__dirname, "../vue/CommsRoutingListPage.vue")
const childPath = resolve(__dirname, "../vue/CommsRoutingList.vue")
const breadcrumbsPath = resolve(__dirname, "../vue/ui/components/CadenceBreadcrumbs.vue")
const pageHeaderPath = resolve(__dirname, "../vue/ui/components/CadencePageHeader.vue")
const emptyStatePath = resolve(__dirname, "../vue/ui/components/CadenceEmptyState.vue")
const pageShellTypesPath = resolve(__dirname, "../vue/ui/components/page_shell.ts")
const liveViewPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/comms_routing_list_live.ex",
)
const liveViewTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/comms_routing_live_test.exs",
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
const preHoverTableRowChildSource = peelCadenceHoverTableRows(
  childSource,
  "CommsRoutingList.vue",
)

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

assert.equal(
  preHoverTableRowChildSource.match(
    /^import CadenceTableFrame from "\.\/ui\/components\/CadenceTableFrame\.vue"$/gm,
  )?.length,
  1,
  "CommsRoutingList.vue has one CadenceTableFrame import before compatibility peeling",
)
assert.equal(
  preHoverTableRowChildSource.match(/<\/?CadenceTableFrame\b/g)?.length,
  2,
  "CommsRoutingList.vue has one CadenceTableFrame boundary before compatibility peeling",
)

const predecessorChildSource = preHoverTableRowChildSource
  .replace('import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"\n\n', "")
  .replace(
    '  <CadenceTableFrame id="routing-rules-table">',
    '  <table id="routing-rules-table" class="table">',
  )
  .replace("  </CadenceTableFrame>", "  </table>")

assert.doesNotMatch(
  predecessorChildSource,
  /CadenceTableFrame/,
  "CommsRoutingList.vue predecessor has no residual CadenceTableFrame shell",
)

assert.equal(
  createHash("sha256").update(predecessorChildSource).digest("hex"),
  "ad0e9cddc6ae751f00f92eac67cd81a6412d75c9d443a21054802ce57eb7bc09",
  "CommsRoutingList.vue remains byte-for-byte immutable",
)

const script = pageSource.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = pageSource.match(/<template>\n([\s\S]*)\n<\/template>/)?.[1]

assert.ok(script, "CommsRoutingListPage.vue has an auditable TypeScript setup block")
assert.ok(template, "CommsRoutingListPage.vue has an auditable template block")
assertBalancedTemplate(template, "CommsRoutingListPage.vue")

const breadcrumbsTemplate = breadcrumbsSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const pageHeaderTemplate = pageHeaderSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const emptyStateTemplate = emptyStateSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(breadcrumbsTemplate, "CadenceBreadcrumbs.vue has an auditable template block")
assert.ok(pageHeaderTemplate, "CadencePageHeader.vue has an auditable template block")
assert.ok(emptyStateTemplate, "CadenceEmptyState.vue has an auditable template block")
assertBalancedTemplate(breadcrumbsTemplate, "CadenceBreadcrumbs.vue")
assertBalancedTemplate(pageHeaderTemplate, "CadencePageHeader.vue")
assertBalancedTemplate(emptyStateTemplate, "CadenceEmptyState.vue")

assert.match(script, /^import CommsRoutingList from "\.\/CommsRoutingList\.vue"$/m)
assert.equal(script.match(/import .*CommsRoutingList\.vue/g)?.length, 1)
assert.match(script, /import CadenceEmptyState from "\.\/ui\/components\/CadenceEmptyState\.vue"/)
assert.match(script, /import CadencePageHeader from "\.\/ui\/components\/CadencePageHeader\.vue"/)
assert.match(script, /type CommsRoutingListProps = InstanceType<typeof CommsRoutingList>\["\$props"\]/)
assert.match(script, /rows: CommsRoutingListProps\["rows"\]/)
assert.match(script, /header: PageHeaderPresentation &/)
assert.match(script, /new_rule: PageHeaderAction/)
assert.match(script, /empty_state: EmptyStatePresentation \| null/)
assert.match(script, /defineProps<\{presentation: Presentation\}>\(\)/)
assert.doesNotMatch(script, /computed|ref\(|watch\(|fetch\(|defineEmits|useRoute|router/)

assert.equal(template.match(/<CommsRoutingList\b/g)?.length, 1)
assert.match(template, /<CommsRoutingList :rows="props\.presentation\.card\.rows" \/>/)
assert.equal(template.match(/<CadencePageHeader\b/g)?.length, 1)
assert.equal(template.match(/<CadenceEmptyState\b/g)?.length, 1)
assert.equal(
  [breadcrumbsTemplate, pageHeaderTemplate, emptyStateTemplate].join("\n").match(/<a\b/g)?.length,
  3,
  "the shared shell retains all three existing anchor positions",
)

for (const binding of [
  "props.presentation.root.attrs",
  "props.presentation.card.attrs",
  "props.presentation.card.body.attrs",
  "props.presentation.card.list_component.attrs",
]) {
  assert.ok(template.includes(`v-bind="${binding}"`), `${binding} stays DTO-owned`)
}

for (const binding of [
  "props.header.attrs",
  "props.header.body.attrs",
  "props.header.content.attrs",
  "props.header.title.attrs",
  "props.header.title.suffix.attrs",
  "props.header.subtitle.attrs",
  "props.header.actions.attrs",
  "props.action.attrs",
  "props.action.icon.attrs",
]) {
  assert.ok(pageHeaderTemplate.includes(`v-bind="${binding}"`), `${binding} stays DTO-owned`)
}

assert.ok(
  pageHeaderTemplate.includes(':breadcrumbs="props.header.breadcrumbs"'),
  "the complete DTO-owned breadcrumb presentation reaches CadenceBreadcrumbs.vue",
)

for (const binding of [
  '<nav v-bind="props.breadcrumbs.attrs">',
  'v-for="item in props.breadcrumbs.items"',
  ':key="item.key"',
]) {
  assert.ok(breadcrumbsTemplate.includes(binding), `${binding} preserves breadcrumb order and identity`)
}

for (const binding of [
  "item.separator.attrs",
  "item.link.attrs",
  "item.current.attrs",
]) {
  assert.ok(breadcrumbsTemplate.includes(`v-bind="${binding}"`), `${binding} stays DTO-owned`)
}

for (const binding of [
  "props.emptyState.attrs",
  "props.emptyState.title.attrs",
  "props.emptyState.description.attrs",
  "props.emptyState.action_container.attrs",
  "props.emptyState.action.attrs",
  "props.emptyState.action.icon.attrs",
]) {
  assert.ok(emptyStateTemplate.includes(`v-bind="${binding}"`), `${binding} stays DTO-owned`)
}

const pageComposition = [
  'v-bind="props.presentation.root.attrs"',
  "<CadencePageHeader",
  ':header="props.presentation.header"',
  ':action="props.presentation.header.actions.new_rule"',
  "<CadenceEmptyState",
  'v-if="props.presentation.empty_state"',
  ':empty-state="props.presentation.empty_state"',
  'v-if="props.presentation.card"',
  'v-bind="props.presentation.card.attrs"',
  'v-bind="props.presentation.card.body.attrs"',
  'v-bind="props.presentation.card.list_component.attrs"',
  '<CommsRoutingList :rows="props.presentation.card.rows" />',
]
let previousCompositionIndex = -1

for (const composition of pageComposition) {
  const compositionIndex = template.indexOf(composition, previousCompositionIndex + 1)

  assert.ok(
    compositionIndex > previousCompositionIndex,
    `CommsRoutingListPage.vue preserves ${composition} in sibling order`,
  )
  previousCompositionIndex = compositionIndex
}

assert.match(template, /v-if="props\.presentation\.empty_state"/)
assert.match(template, /v-if="props\.presentation\.card"/)
assert.match(pageShellTypesSource, /suffix: TextPresentation/)
assert.match(pageShellTypesSource, /subtitle: TextPresentation/)
assert.doesNotMatch(
  pageSource,
  /\/missions|Durable rules|New Routing Rule|No routing rules|Create the first routing rule|space-y-6|btn btn-primary|data-phx-link/,
)
assert.doesNotMatch(pageSource, /sort\(|\.sort|filter\(|\.filter|Map\.fetch|String\.upcase|v-html/)
assert.doesNotMatch(pageSource, /<\.vue|v-component=|phx-click|phx-change|phx-submit/)

const mountSource = sourceSlice(
  liveViewSource,
  "  def mount(_params, _session, socket) do",
  "  @impl true\n  def render(assigns) do",
  "CommsRoutingListLive mount",
)

for (const authority of [
  "RoutingRuleStore.list_routing_rules(scope.organization_id, mission.mission_id)",
  "spacecraft_lookup(scope.organization_id, mission.mission_id)",
  "transport_lookup(scope.organization_id, mission.mission_id)",
  "&routing_rule_row(&1, mission.mission_id, spacecraft_by_id, transport_by_id)",
  "routing_rule_count = length(routing_rules)",
  "routing_rules_empty? = routing_rules == []",
  "assign(:routing_rule_count, routing_rule_count)",
  "assign(:routing_rules_empty?, routing_rules_empty?)",
  "assign(:routing_rule_rows, routing_rule_rows)",
  "routing_list_presentation(",
]) {
  assert.ok(mountSource.includes(authority), `Phoenix retains ${authority}`)
}

const renderSource = sourceSlice(
  liveViewSource,
  "  def render(assigns) do",
  "  @doc false",
  "CommsRoutingListLive render boundary",
)

assert.equal(renderSource.match(/<\.vue\b/g)?.length, 1)
assert.match(renderSource, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(renderSource, /id="comms-routing-list-page-component"/)
assert.match(renderSource, /v-component="CommsRoutingListPage"/)
assert.match(renderSource, /presentation=\{@presentation\}/)
assert.match(renderSource, /v-ssr=\{false\}/)
assert.match(renderSource, /class="contents"/)
assert.doesNotMatch(renderSource, /<\.page_header|<\.card|<\.empty_state|<\.button/)
assert.doesNotMatch(renderSource, /CommsRoutingList"|routing_rule_rows|routing_rules_empty\?/)

const presentationSource = sourceSlice(
  liveViewSource,
  "  @doc false\n  def presentation_attrs(attrs) when is_map(attrs) do",
  "  defp spacecraft_lookup(organization_id, mission_id) do",
  "routing-list presentation DTO",
)

for (const text of [
  "Routing",
  "Durable rules describing how spacecraft use transports for a purpose and direction.",
  "New Routing Rule",
  "No routing rules",
  "Create a routing rule to declare how a spacecraft should use an available transport.",
  "Create the first routing rule",
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
  "hero-plus h-4 w-4",
  "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center",
  "hud-label",
  "mt-2 max-w-md mx-auto text-sm text-base-content/70",
  "btn btn-primary btn-sm",
  "hero-plus -ml-0.5 mr-1 h-4 w-4",
  "card bg-base-200 border border-base-300",
  "card-body p-0",
]) {
  assert.ok(presentationSource.includes(`"${className}"`), `${className} stays Phoenix-owned`)
}

for (const id of [
  "comms-routing-page",
  "new-routing-rule-link",
  "routing-rules-list-component",
]) {
  assert.ok(presentationSource.includes(`"${id}"`), `${id} remains server-authored`)
}

for (const route of [
  '~p"/missions/#{mission.mission_id}"',
  '~p"/missions/#{mission.mission_id}/comms"',
  '~p"/missions/#{mission.mission_id}/comms/routing/new"',
]) {
  assert.ok(presentationSource.includes(route), `${route} remains server-verified`)
}

assert.match(presentationSource, /"data-phx-link" => "redirect"/)
assert.match(presentationSource, /"data-phx-link-state" => "push"/)
assert.match(presentationSource, /empty_state_presentation\(routing_rules_empty\?, new_rule_path\)/)
assert.match(presentationSource, /card_presentation\(routing_rules_empty\?, rows\)/)
assert.match(presentationSource, /defp empty_state_presentation\(false, _new_rule_path\), do: nil/)
assert.match(presentationSource, /defp card_presentation\(true, _rows\), do: nil/)
assert.match(presentationSource, /"rows" => rows/)
assert.match(presentationSource, /value in \[nil, false\]/)
assert.match(presentationSource, /\{name, true\}, rendered/)
assert.match(presentationSource, /Map\.put\(rendered, name, ""\)/)
assert.match(presentationSource, /Map\.put\(rendered, name, to_string\(value\)\)/)

for (const serverDecision of [
  "Cadence.SpacecraftStore.list_spacecraft(mission_id)",
  "TransportStore.list_transports(mission_id)",
  "Map.new(&{&1.spacecraft_id, &1})",
  "Map.new(&{&1.transport_id, &1})",
  "spacecraft_name(spacecraft_by_id, rule.spacecraft_id)",
  "transport_name(transport_by_id, rule.transport_id)",
  "human_atom(rule.direction)",
  "human_atom(rule.role)",
  'href: ~p"/missions/#{mission_id}/comms/routing/#{rule.routing_rule_id}"',
  ":error -> spacecraft_id",
  ":error -> transport_id",
  'String.replace("_", " ")',
  "String.upcase()",
]) {
  assert.ok(liveViewSource.includes(serverDecision), `${serverDecision} remains in Phoenix`)
}

const authenticatedCommsScope = sourceSlice(
  routerSource,
  '  scope "/", CadenceWeb do\n    pipe_through [:browser, :require_authenticated_scope]',
  '\n  scope "/api", CadenceWeb do',
  "authenticated browser router scope",
)

const commsSession = sourceSlice(
  authenticatedCommsScope,
  "    live_session :comms,",
  "    live_session :ops_dashboard_author,",
  "comms LiveSession",
)

assert.match(commsSession, /\{CadenceWeb\.OrganizationAuth, :require_organization_scope\}/)
assert.match(commsSession, /\{CadenceWeb\.MissionAuth, :load_mission\}/)
assert.match(commsSession, /\{CadenceWeb\.UserAuth, :attach_user_menu\}/)
assert.match(commsSession, /layout: \{CadenceWeb\.Layouts, :mission_sidebar\} do/)
assert.match(
  commsSession,
  /live "\/missions\/:mission_id\/comms\/routing",\s+CommsRoutingListLive,\s+:index/,
)
assert.equal(
  routerSource.match(/live "\/missions\/:mission_id\/comms\/routing",\s+CommsRoutingListLive,\s+:index/g)
    ?.length,
  1,
)

const expectedScenarios = [
  "renders the empty state when the mission has no routing rules",
  "lists routing rules with routing vocabulary and JSON-safe row props",
  "routing list raw attrs preserve HEEx omission boolean string and number semantics",
  "creates and shows a routing rule",
  "preserves nested validate values in the Vue form DTO",
  "preserves exact required and invalid save errors",
  "trims text and preserves the parsed transport version when saving",
  "preselects local spacecraft, preserves option order, and excludes foreign scope",
  "preserves humanized changeset error formatting",
  "shows disabled routing rule state without changing its details",
  "missing routing rule redirects to the current mission routing list",
  "does not expose routing rules outside the current organization or mission scope",
  "spacecraft routing page exposes the client-only empty state DTO",
  "spacecraft routing page lists rules for current spacecraft",
  "spacecraft routing page preserves rule ordering, vocabulary, ids, and state",
  "spacecraft routing page preserves scope and falls back to the transport id",
]

const declaredScenarios = [...liveViewTestSource.matchAll(/^    test "([^"]+)"/gm)].map(
  ([, scenario]) => scenario,
)

assert.deepEqual(declaredScenarios, expectedScenarios)
assert.ok(
  (liveViewTestSource.match(/^\s+(?:assert|refute)(?:\s|\()/gm)?.length ?? 0) >= 85,
  "the broad test retains every pre-migration assert/refute site",
)

const emptyScenario = sourceSlice(
  liveViewTestSource,
  '    test "renders the empty state when the mission has no routing rules"',
  '\n    test "lists routing rules with routing vocabulary and JSON-safe row props"',
  "empty routing-list scenario",
)

for (const contract of [
  'id: "comms-routing-list-page-component"',
  'vue.component == "CommsRoutingListPage"',
  'vue.class == "contents"',
  "vue.ssr == false",
  'Map.keys(vue.props) == ["presentation"]',
  "Jason.decode!(Jason.encode!(presentation))",
  '"id" => "comms-routing-page"',
  '"id" => "new-routing-rule-link"',
  'presentation["empty_state"]["title"]["text"] == "No routing rules"',
  'presentation["card"] == nil',
  'refute Jason.encode!(presentation) =~ "routing-rules-list-component"',
]) {
  assert.ok(emptyScenario.includes(contract), `empty scenario retains ${contract}`)
}

const rowsScenario = sourceSlice(
  liveViewTestSource,
  '    test "lists routing rules with routing vocabulary and JSON-safe row props"',
  '\n    test "routing list raw attrs preserve HEEx omission boolean string and number semantics"',
  "nonempty routing-list scenario",
)

for (const contract of [
  'id: "comms-routing-list-page-component"',
  'presentation["root"]["attrs"]["id"] == "comms-routing-page"',
  '"attrs" => %{"id" => "routing-rules-list-component"}',
  'presentation["card"]["rows"] == [',
  '"spacecraft_name" => spacecraft.display_name',
  '"direction" => "INBOUND"',
  '"transport_name" => transport.display_name',
  '"role" => "PRIMARY"',
  'refute encoded_presentation =~ "Link Assignment"',
  'refute encoded_presentation =~ "Link Template"',
]) {
  assert.ok(rowsScenario.includes(contract), `nonempty scenario retains ${contract}`)
}

const rawAttrsScenario = sourceSlice(
  liveViewTestSource,
  '    test "routing list raw attrs preserve HEEx omission boolean string and number semantics"',
  '\n    test "creates and shows a routing rule"',
  "raw attribute scenario",
)

for (const input of [
  '"nil" => nil',
  '"false" => false',
  '"true" => true',
  '"empty" => ""',
  '"string" => "retained"',
  '"number" => 7',
]) {
  assert.ok(rawAttrsScenario.includes(input), `raw attribute scenario covers ${input}`)
}

const creationScenario = sourceSlice(
  liveViewTestSource,
  '    test "creates and shows a routing rule"',
  '\n    test "preserves nested validate values in the Vue form DTO"',
  "existing form/show/list caller scenario",
)

assert.ok(
  creationScenario.includes('"href" => "/missions/#{mission.mission_id}/comms/routing"'),
  "the unchanged new-form cancel caller still returns to the list",
)

const redirectsSource = sourceSlice(
  liveViewTestSource,
  '    test "missing routing rule redirects to the current mission routing list"',
  '\n    test "spacecraft routing page exposes the client-only empty state DTO"',
  "existing list-return redirect scenarios",
)

assert.equal(
  redirectsSource.split('assert to == ~p"/missions/#{mission.mission_id}/comms/routing"').length -
    1,
  2,
  "both unchanged show failures still return to the current mission list",
)

console.log("comms_routing_list_page_test passed")
