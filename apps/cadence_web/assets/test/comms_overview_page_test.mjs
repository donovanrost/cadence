import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const scenarioLedger = [
  "the complete Comms Overview page is one non-SSR LiveVue parent with one presentation prop",
  "Phoenix owns the outer shell, exact page-header presentation, and existing child overview prop",
  "Phoenix retains mission scope, queries, limits, statuses, findings, grouping, and verified routes",
  "CommsOverviewPage directly composes the immutable CommsOverview child exactly once",
  "the page, header, child roots, text, and visual classes remain exact",
  "all child links retain LiveView redirect and push navigation attributes",
  "raw attrs preserve HEEx nil, false, true, string, and number behavior",
  "the ten pre-migration LiveView scenarios and their oracles remain one-for-one",
  "the authenticated route, Comms LiveSession, mounts, action, and mission-sidebar layout stay exact",
  "Layouts.app remains the LiveView host boundary with flash and current_scope",
]

assert.equal(process.versions.node, "24.16.0", "Comms Overview contracts use pinned Node 24.16.0")
assert.equal(scenarioLedger.length, 10)

const __dirname = dirname(fileURLToPath(import.meta.url))
const pagePath = resolve(__dirname, "../vue/CommsOverviewPage.vue")
const childPath = resolve(__dirname, "../vue/CommsOverview.vue")
const liveViewPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/comms_overview_live.ex",
)
const liveViewTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/comms_live_test.exs",
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
  "2c377d7c0f5904311de59a10dd517b21175ecef95eb1b5d8df5a6474932d9a96",
  "CommsOverview.vue remains the explicitly immutable child",
)

const script = pageSource.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = pageSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "CommsOverviewPage.vue must have a TypeScript script setup block")
assert.ok(template, "CommsOverviewPage.vue must have a template block")
assertBalancedTemplate(template)

assert.match(script, /import CommsOverview from "\.\/CommsOverview\.vue"/)
assert.match(script, /type CommsOverviewProps = InstanceType<typeof CommsOverview>\["\$props"\]/)
assert.match(script, /overview: CommsOverviewProps\["overview"\]/)
assert.match(script, /defineProps<\{presentation: Presentation\}>\(\)/)
assert.equal(template.match(/<CommsOverview\b/g)?.length, 1)
assert.match(template, /<CommsOverview :overview="props\.presentation\.overview" \/>/)

for (const binding of [
  "props.presentation.root.attrs",
  "props.presentation.header.attrs",
  "props.presentation.header.body.attrs",
  "props.presentation.header.content.attrs",
  "props.presentation.header.eyebrow.attrs",
  "props.presentation.header.title.attrs",
  "props.presentation.header.title_suffix.attrs",
]) {
  assert.ok(template.includes(`v-bind="${binding}"`), `${binding} stays DTO-owned`)
}

for (const textBinding of [
  "props.presentation.header.eyebrow.text",
  "props.presentation.header.title.text",
  "props.presentation.header.title_suffix.text",
]) {
  assert.ok(template.includes(`{{ ${textBinding} }}`), `${textBinding} stays DTO-owned`)
}

assert.doesNotMatch(
  pageSource,
  /Communications|Mission Comms|space-y-6|border-primary|hud-label|text-2xl|font-mono/,
)
assert.doesNotMatch(pageSource, /\/missions|data-phx-link|v-if=|v-for=|v-html|<\.vue|v-component=/)

assert.match(childSource, /import StatusBadge from "\.\/StatusBadge\.vue"/)
assert.match(childSource, /id="comms-overview-content" class="space-y-6"/)
assert.equal(childSource.match(/data-phx-link="redirect"/g)?.length, 5)
assert.equal(childSource.match(/data-phx-link-state="push"/g)?.length, 5)

for (const idBinding of [
  ':id="overview.transport.id"',
  ':id="transport.id"',
  ':id="overview.validation.id"',
  ':id="overview.validation.findings_id"',
  ':id="group.id"',
  ':id="finding.id ?? undefined"',
]) {
  assert.ok(childSource.includes(idBinding), `${idBinding} remains in the immutable child`)
}

const mountSource = sourceSlice(
  liveViewSource,
  "  def mount(_params, _session, socket) do",
  "  @impl true\n  def render(assigns) do",
  "CommsOverviewLive mount",
)

assert.match(mountSource, /summary = load_summary\(socket\.assigns\)/)
assert.match(
  mountSource,
  /presentation = page_presentation_dto\(socket\.assigns\.current_mission, summary\)/,
)
assert.match(mountSource, /assign\(:page_title, "Comms"\)/)
assert.match(mountSource, /assign\(:nav_item, :comms_overview\)/)
assert.match(mountSource, /assign\(:presentation, presentation\)/)

const renderSource = sourceSlice(
  liveViewSource,
  "  def render(assigns) do",
  "  @doc false",
  "CommsOverviewLive render",
)

assert.equal(renderSource.match(/<\.vue/g)?.length, 1)
assert.match(renderSource, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(renderSource, /id="comms-overview-component"/)
assert.match(renderSource, /v-component="CommsOverviewPage"/)
assert.match(renderSource, /presentation=\{@presentation\}/)
assert.match(renderSource, /v-ssr=\{false\}/)
assert.doesNotMatch(renderSource, /<\.page_header|overview=\{@overview\}|id="comms-overview-page"/)

const rawAttrsSource = sourceSlice(
  liveViewSource,
  "  @doc false\n  def presentation_attrs(attrs) when is_map(attrs) do",
  "  defp page_presentation_dto(mission, summary) do",
  "Comms Overview raw attribute projection",
)

assert.match(rawAttrsSource, /value in \[nil, false\]/)
assert.match(rawAttrsSource, /\{name, true\}, rendered/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, ""\)/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, to_string\(value\)\)/)

const presentationSource = sourceSlice(
  liveViewSource,
  "  defp page_presentation_dto(mission, summary) do",
  "  defp load_summary(%{current_scope: scope, current_mission: mission}) do",
  "Comms Overview page presentation DTO",
)

for (const text of ["Communications", "· Mission Comms"]) {
  assert.ok(presentationSource.includes(`"${text}"`), `${text} stays Phoenix-owned`)
}

for (const className of [
  "space-y-6",
  "border-b border-primary/20 pb-4",
  "hud-label",
  "mt-2 text-2xl font-bold text-base-content tracking-tight",
  "ml-3 font-mono text-base text-base-content/60",
]) {
  assert.ok(presentationSource.includes(`"${className}"`), `${className} stays Phoenix-owned`)
}

assert.match(presentationSource, /"id" => "comms-overview-page"/)
assert.match(presentationSource, /"text" => mission\.display_name/)
assert.match(presentationSource, /"overview" => overview_dto\(mission\.mission_id, summary\)/)

const summarySource = sourceSlice(
  liveViewSource,
  "  defp load_summary(%{current_scope: scope, current_mission: mission}) do",
  "  defp overview_dto(mission_id, summary) do",
  "Comms Overview server summary",
)

for (const call of [
  "Cadence.SpacecraftStore.list_spacecraft",
  "Cadence.SourceEndpoints.list_source_endpoints",
  "TransportStore.list_transports",
  "Cadence.Contacts.list_provider_profiles",
  "Cadence.Contacts.list_transport_profiles",
  "Cadence.Contacts.list_path_templates",
  "RoutingRuleStore.list_routing_rules",
  "CommsValidation.findings_for_resources",
  "CommsValidation.finding_groups",
]) {
  assert.ok(summarySource.includes(call), `${call} remains server-owned`)
}

assert.match(summarySource, /transports: Enum\.take\(transports, 6\)/)
assert.match(summarySource, /transport_count: length\(transports\)/)

const existingScenarioSource = sourceSlice(
  liveViewTestSource,
  '  describe "overview" do',
  '  describe "overview presentation" do',
  "pre-migration Comms LiveView scenarios",
)

for (const scenario of [
  'test "renders the comms setup overview and section navigation"',
  'test "inlined validation surface includes spacecraft setup findings"',
  'test "inlined validation surface includes routing setup findings"',
  'test "expands the Comms section and marks Overview active on /comms"',
  'test "renders dedicated validation page grouped by setup owner"',
  'test "keeps dedicated validation groups in setup-owner order"',
  'test "projects the no-findings card through exact JSON-safe props"',
  'test "projects required application installation status into Comms Validation"',
  'test "projects installed application status without application-specific Comms code"',
  'test "leaves the Comms section collapsed when not on a /comms route"',
]) {
  assert.ok(existingScenarioSource.includes(scenario), `${scenario} remains one-for-one`)
}

const presentationTestSource = sourceSlice(
  liveViewTestSource,
  '  describe "overview presentation" do',
  "  defp comms_overview_props(view) do",
  "focused Comms Overview presentation tests",
)

assert.match(presentationTestSource, /Jason\.decode!\(Jason\.encode!\(presentation\)\)/)
assert.match(presentationTestSource, /CommsOverviewLive\.presentation_attrs/)
assert.match(presentationTestSource, /"nil" => nil/)
assert.match(presentationTestSource, /"false" => false/)
assert.match(presentationTestSource, /"true" => true/)
assert.match(presentationTestSource, /"number" => 7/)

const authenticatedScopeSource = sourceSlice(
  routerSource,
  '  scope "/", CadenceWeb do\n    pipe_through [:browser, :require_authenticated_scope]',
  "    live_session :organization,",
  "authenticated browser scope",
)

assert.match(authenticatedScopeSource, /pipe_through \[:browser, :require_authenticated_scope\]/)

const commsSessionSource = sourceSlice(
  routerSource,
  "    live_session :comms,",
  "    live_session :ops_dashboard_author,",
  "Comms LiveSession",
)

assert.match(commsSessionSource, /CadenceWeb\.OrganizationAuth, :require_organization_scope/)
assert.match(commsSessionSource, /CadenceWeb\.MissionAuth, :load_mission/)
assert.match(commsSessionSource, /CadenceWeb\.UserAuth, :attach_user_menu/)
assert.match(commsSessionSource, /layout: \{CadenceWeb\.Layouts, :mission_sidebar\}/)
assert.match(
  commsSessionSource,
  /live "\/missions\/:mission_id\/comms", CommsOverviewLive, :index/,
)
assert.doesNotMatch(commsSessionSource, /require_organization_admin|require_platform_admin/)
