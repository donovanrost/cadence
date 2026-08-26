import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const scenarioLedger = [
  "one always-present non-SSR SpacecraftTypeListPage host owns the complete list page",
  "the host exposes exactly one JSON-safe presentation prop and uses class contents",
  "Phoenix owns organization and mission scope, SpacecraftTypeStore reads, count, empty, labels, ordering, and routes",
  "SpacecraftTypeListPage composes the shared Cadence shell and byte-pinned SpacecraftTypeList child exactly once",
  "the Vue root, header, breadcrumbs, title suffix, action, empty state, and card preserve exact DOM contracts",
  "spacecraft-profiles-list-component exists only inside the server-selected nonempty card",
  "breadcrumb, creation, and row anchors retain LiveView redirect and push navigation semantics",
  "raw attrs preserve HEEx nil, false, true, empty-string, string, and number behavior",
  "all pre-migration profile scenarios and assertion oracles remain one-for-one in the broad test",
  "the authenticated spacecraft route, organization and mission mounts, user-menu mount, and mission-sidebar layout remain unchanged",
  "router, LiveView, and tests use semantic source slices; only immutable SpacecraftTypeList.vue is hashed",
]

assert.equal(process.versions.node, "24.16.0", "spacecraft-type-list contracts use pinned Node 24.16.0")
assert.equal(scenarioLedger.length, 11)

const __dirname = dirname(fileURLToPath(import.meta.url))
const pagePath = resolve(__dirname, "../vue/SpacecraftTypeListPage.vue")
const childPath = resolve(__dirname, "../vue/SpacecraftTypeList.vue")
const breadcrumbsPath = resolve(__dirname, "../vue/ui/components/CadenceBreadcrumbs.vue")
const pageHeaderPath = resolve(__dirname, "../vue/ui/components/CadencePageHeader.vue")
const emptyStatePath = resolve(__dirname, "../vue/ui/components/CadenceEmptyState.vue")
const pageShellTypesPath = resolve(__dirname, "../vue/ui/components/page_shell.ts")
const liveViewPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/spacecraft_type_list_live.ex",
)
const liveViewTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/spacecraft_profile_live_test.exs",
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

assert.equal(
  createHash("sha256").update(childSource).digest("hex"),
  "2537026b313d3dff90a164531a2c100846c0a181658505178b2248f01e32088d",
  "SpacecraftTypeList.vue remains byte-for-byte immutable",
)

const script = pageSource.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = pageSource.match(/<template>\n([\s\S]*)\n<\/template>/)?.[1]

assert.ok(script, "SpacecraftTypeListPage.vue has an auditable TypeScript setup block")
assert.ok(template, "SpacecraftTypeListPage.vue has an auditable template block")
assertBalancedTemplate(template, "SpacecraftTypeListPage.vue")

const breadcrumbsTemplate = breadcrumbsSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const pageHeaderTemplate = pageHeaderSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const emptyStateTemplate = emptyStateSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(breadcrumbsTemplate, "CadenceBreadcrumbs.vue has an auditable template block")
assert.ok(pageHeaderTemplate, "CadencePageHeader.vue has an auditable template block")
assert.ok(emptyStateTemplate, "CadenceEmptyState.vue has an auditable template block")
assertBalancedTemplate(breadcrumbsTemplate, "CadenceBreadcrumbs.vue")
assertBalancedTemplate(pageHeaderTemplate, "CadencePageHeader.vue")
assertBalancedTemplate(emptyStateTemplate, "CadenceEmptyState.vue")

assert.match(script, /^import SpacecraftTypeList from "\.\/SpacecraftTypeList\.vue"$/m)
assert.equal(script.match(/import .*SpacecraftTypeList\.vue/g)?.length, 1)
assert.match(script, /import CadenceEmptyState from "\.\/ui\/components\/CadenceEmptyState\.vue"/)
assert.match(script, /import CadencePageHeader from "\.\/ui\/components\/CadencePageHeader\.vue"/)
assert.match(
  script,
  /type SpacecraftTypeListProps = InstanceType<typeof SpacecraftTypeList>\["\$props"\]/,
)
assert.match(script, /rows: SpacecraftTypeListProps\["rows"\]/)
assert.match(script, /header: PageHeaderPresentation &/)
assert.match(script, /new_profile: PageHeaderAction/)
assert.match(script, /empty_state: EmptyStatePresentation \| null/)
assert.match(script, /defineProps<\{presentation: Presentation\}>\(\)/)
assert.doesNotMatch(script, /computed|ref\(|watch\(|fetch\(|defineEmits|useRoute|router/)

assert.equal(template.match(/<SpacecraftTypeList\b/g)?.length, 1)
assert.match(template, /<SpacecraftTypeList :rows="props\.presentation\.card\.rows" \/>/)
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
  ':action="props.presentation.header.actions.new_profile"',
  "<CadenceEmptyState",
  'v-if="props.presentation.empty_state"',
  ':empty-state="props.presentation.empty_state"',
  'v-if="props.presentation.card"',
  'v-bind="props.presentation.card.attrs"',
  'v-bind="props.presentation.card.body.attrs"',
  'v-bind="props.presentation.card.list_component.attrs"',
  '<SpacecraftTypeList :rows="props.presentation.card.rows" />',
]
let previousCompositionIndex = -1

for (const composition of pageComposition) {
  const compositionIndex = template.indexOf(composition, previousCompositionIndex + 1)

  assert.ok(
    compositionIndex > previousCompositionIndex,
    `SpacecraftTypeListPage.vue preserves ${composition} in sibling order`,
  )
  previousCompositionIndex = compositionIndex
}

for (const textBinding of [
  "item.separator.text",
  "item.link.text",
  "item.current.text",
]) {
  assert.ok(breadcrumbsTemplate.includes(`{{ ${textBinding} }}`), `${textBinding} stays DTO-owned`)
}

for (const textBinding of [
  "props.header.title.text",
  "props.header.title.suffix.text",
  "props.header.subtitle.text",
  "props.action.text",
]) {
  assert.ok(pageHeaderTemplate.includes(`{{ ${textBinding} }}`), `${textBinding} stays DTO-owned`)
}

for (const textBinding of [
  "props.emptyState.title.text",
  "props.emptyState.description.text",
  "props.emptyState.action.text",
]) {
  assert.ok(emptyStateTemplate.includes(`{{ ${textBinding} }}`), `${textBinding} stays DTO-owned`)
}

assert.match(template, /v-if="props\.presentation\.empty_state"/)
assert.match(template, /v-if="props\.presentation\.card"/)
assert.match(pageShellTypesSource, /suffix: TextPresentation/)
assert.match(pageShellTypesSource, /subtitle: TextPresentation/)
assert.doesNotMatch(
  pageSource,
  /\/missions|Reusable byte-interpretation|New Profile|No profiles yet|Create the first profile|space-y-6|btn btn-primary|data-phx-link/,
)
assert.doesNotMatch(pageSource, /sort\(|\.sort|filter\(|\.filter|Map\.keys|String\.upcase|v-html/)
assert.doesNotMatch(pageSource, /<\.vue|v-component=|phx-click|phx-change|phx-submit/)

const mountSource = sourceSlice(
  liveViewSource,
  "  def mount(_params, _session, socket) do",
  "  @impl true\n  def render(assigns) do",
  "SpacecraftTypeListLive mount",
)

for (const authority of [
  "socket.assigns.current_mission",
  "socket.assigns.current_scope.organization_id",
  "Cadence.SpacecraftTypeStore.list_spacecraft_types(organization_id, mission.mission_id)",
  "Enum.map(profiles, &spacecraft_profile_row_dto(&1, mission.mission_id))",
  "spacecraft_profile_count = length(profiles)",
  "spacecraft_profiles_empty? = profiles == []",
  "assign(:spacecraft_profile_count, spacecraft_profile_count)",
  "assign(:spacecraft_profiles_empty?, spacecraft_profiles_empty?)",
  "assign(:spacecraft_profile_rows, spacecraft_profile_rows)",
  "spacecraft_type_list_presentation(",
]) {
  assert.ok(mountSource.includes(authority), `Phoenix retains ${authority}`)
}

const renderSource = sourceSlice(
  liveViewSource,
  "  def render(assigns) do",
  "  @doc false",
  "SpacecraftTypeListLive render boundary",
)

assert.equal(renderSource.match(/<\.vue\b/g)?.length, 1)
assert.match(renderSource, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(renderSource, /id="spacecraft-type-list-page-component"/)
assert.match(renderSource, /v-component="SpacecraftTypeListPage"/)
assert.match(renderSource, /presentation=\{@presentation\}/)
assert.match(renderSource, /v-ssr=\{false\}/)
assert.match(renderSource, /class="contents"/)
assert.doesNotMatch(renderSource, /<\.page_header|<\.card|<\.empty_state|<\.button/)
assert.doesNotMatch(renderSource, /SpacecraftTypeList"|spacecraft_profile_rows|spacecraft_profiles_empty\?/)

const presentationSource = sourceSlice(
  liveViewSource,
  "  @doc false\n  def presentation_attrs(attrs) when is_map(attrs) do",
  "  defp spacecraft_profile_row_dto(profile, mission_id) do",
  "spacecraft-type-list presentation DTO",
)

for (const text of [
  "Spacecraft Profiles",
  "Reusable byte-interpretation contracts for spacecraft that share bus protocols, frame parameters, and platform applications.",
  "New Profile",
  "No profiles yet",
  "Define a profile to capture the protocol stack and applications shared by a set of spacecraft.",
  "Create the first profile",
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
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60",
  "hover:text-primary transition-colors",
  "text-base-content/20",
  "text-primary/90",
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
  "spacecraft-profiles-page",
  "new-spacecraft-profile-link",
  "spacecraft-profiles-list-component",
]) {
  assert.ok(presentationSource.includes(`"${id}"`), `${id} remains server-authored`)
}

for (const route of [
  '~p"/missions/#{mission.mission_id}"',
  '~p"/missions/#{mission.mission_id}/spacecraft"',
  '~p"/missions/#{mission.mission_id}/spacecraft/profiles/new"',
]) {
  assert.ok(presentationSource.includes(route), `${route} remains server-verified`)
}

assert.match(presentationSource, /"data-phx-link" => "redirect"/)
assert.match(presentationSource, /"data-phx-link-state" => "push"/)
assert.match(
  presentationSource,
  /empty_state_presentation\(spacecraft_profiles_empty\?, new_profile_path\)/,
)
assert.match(presentationSource, /card_presentation\(spacecraft_profiles_empty\?, rows\)/)
assert.match(presentationSource, /defp empty_state_presentation\(false, _new_profile_path\), do: nil/)
assert.match(presentationSource, /defp card_presentation\(true, _rows\), do: nil/)
assert.match(presentationSource, /"rows" => rows/)
assert.match(presentationSource, /value in \[nil, false\]/)
assert.match(presentationSource, /\{name, true\}, rendered/)
assert.match(presentationSource, /Map\.put\(rendered, name, ""\)/)
assert.match(presentationSource, /Map\.put\(rendered, name, to_string\(value\)\)/)

for (const serverDecision of [
  'id: "spacecraft-profile-#{profile.spacecraft_type_id}"',
  'version: "v#{profile.version}"',
  "downlink_protocol: protocol_label(profile.downlink_protocol)",
  "uplink_protocol: protocol_label(profile.uplink_protocol)",
  "applications: applications_summary(profile.applications)",
  'href: ~p"/missions/#{mission_id}/spacecraft/profiles/#{profile.spacecraft_type_id}"',
  "Atom.to_string()",
  "String.upcase()",
  "Map.keys()",
  "Enum.sort()",
  'Enum.map_join(", ", &humanize_application_key/1)',
  'defp applications_summary(_), do: "None"',
  'String.split("_")',
  'Enum.map_join(" ", &String.capitalize/1)',
]) {
  assert.ok(liveViewSource.includes(serverDecision), `${serverDecision} remains in Phoenix`)
}

const authenticatedSpacecraftScope = sourceSlice(
  routerSource,
  '  scope "/", CadenceWeb do\n    pipe_through [:browser, :require_authenticated_scope]',
  '\n  scope "/api", CadenceWeb do',
  "authenticated browser router scope",
)

const spacecraftSession = sourceSlice(
  authenticatedSpacecraftScope,
  "    live_session :spacecraft,",
  "    live_session :spacecraft_show,",
  "spacecraft LiveSession",
)

assert.match(spacecraftSession, /\{CadenceWeb\.OrganizationAuth, :require_organization_scope\}/)
assert.match(spacecraftSession, /\{CadenceWeb\.MissionAuth, :load_mission\}/)
assert.match(spacecraftSession, /\{CadenceWeb\.UserAuth, :attach_user_menu\}/)
assert.match(spacecraftSession, /layout: \{CadenceWeb\.Layouts, :mission_sidebar\} do/)
assert.match(
  spacecraftSession,
  /live "\/missions\/:mission_id\/spacecraft\/profiles", SpacecraftTypeListLive, :index/,
)
assert.equal(
  routerSource.match(
    /live "\/missions\/:mission_id\/spacecraft\/profiles", SpacecraftTypeListLive, :index/g,
  )?.length,
  1,
)
assert.doesNotMatch(
  spacecraftSession,
  /require_organization_admin|require_platform_admin|load_spacecraft/,
)

const helperSource = sourceSlice(
  liveViewTestSource,
  "  defp spacecraft_profile_list_vue(view) do",
  "  defp spacecraft_profile_show_vue(view) do",
  "Spacecraft Profile list test helper",
)

assert.match(liveViewTestSource, /^  alias LiveVue\.Test$/m)

for (const contract of [
  'Test.get_vue(view, id: "spacecraft-type-list-page-component")',
  'vue.component == "SpacecraftTypeListPage"',
  'vue.class == "contents"',
  "vue.ssr == false",
  'Map.keys(vue.props) == ["presentation"]',
  "is_binary(Jason.encode!(vue.props))",
  "vue.props == Jason.decode!(Jason.encode!(vue.props))",
]) {
  assert.ok(helperSource.includes(contract), `list helper retains ${contract}`)
}

const expectedScenarios = [
  "spacecraft management page exposes vehicle and profile cards with scoped actions",
  "mission sidebar keeps profiles under the spacecraft area",
  "renders the server-owned empty state when no profiles are defined",
  "lists spacecraft profiles using profile vocabulary and JSON-safe row props",
  "spacecraft profile list raw attrs preserve HEEx omission boolean string and number semantics",
  "lists only profiles belonging to the current mission and organization",
  "creates a spacecraft profile and redirects to the profile show page",
  "resyncs every conditional frame value and application selection from validate hooks",
  "persists active AOS and USLP frame branches and filters unsupported applications",
  "preserves exact create errors and submitted form values without persistence",
  "shows a spacecraft profile",
  "provides exact JSON-safe profile detail and version history props",
  "preserves empty frame-parameter and application presentation behavior",
  "missing profile redirects to the scoped profile list with the existing error",
  "does not expose profile details outside the current mission or organization scope",
  "unauthenticated profile detail requests redirect to sign in",
]

const declaredScenarios = [...liveViewTestSource.matchAll(/^    test "([^"]+)"/gm)].map(
  ([, scenario]) => scenario,
)

assert.deepEqual(declaredScenarios, expectedScenarios)
assert.ok(
  (liveViewTestSource.match(/^\s+(?:assert|refute)(?:\s|\()/gm)?.length ?? 0) >= 85,
  "the broad profile test retains every pre-migration assert/refute site",
)

const emptyScenario = sourceSlice(
  liveViewTestSource,
  '    test "renders the server-owned empty state when no profiles are defined"',
  '\n    test "lists spacecraft profiles using profile vocabulary and JSON-safe row props"',
  "empty spacecraft-profile-list scenario",
)

for (const contract of [
  '"#spacecraft-type-list-page-component"',
  '"id" => "spacecraft-profiles-page"',
  'presentation["empty_state"]["title"]["text"] == "No profiles yet"',
  '"id" => "new-spacecraft-profile-link"',
  'presentation["card"] == nil',
  'refute Jason.encode!(presentation) =~ "spacecraft-profiles-list-component"',
]) {
  assert.ok(emptyScenario.includes(contract), `empty scenario retains ${contract}`)
}

const rowsScenario = sourceSlice(
  liveViewTestSource,
  '    test "lists spacecraft profiles using profile vocabulary and JSON-safe row props"',
  '\n    test "spacecraft profile list raw attrs preserve HEEx omission boolean string and number semantics"',
  "nonempty spacecraft-profile-list scenario",
)

for (const contract of [
  '"#spacecraft-type-list-page-component"',
  '"attrs" => %{"id" => "spacecraft-profiles-list-component"}',
  'presentation["card"]["rows"] == [',
  '"downlink_protocol" => "AOS"',
  '"uplink_protocol" => "USLP"',
  '"applications" => "Command Dispatch, Telemetry Decom"',
  'presentation["header"]["title"]["text"] == "Spacecraft Profiles"',
  'refute Jason.encode!(presentation) =~ "Spacecraft Types"',
]) {
  assert.ok(rowsScenario.includes(contract), `nonempty scenario retains ${contract}`)
}

const rawAttrsScenario = sourceSlice(
  liveViewTestSource,
  '    test "spacecraft profile list raw attrs preserve HEEx omission boolean string and number semantics"',
  '\n    test "lists only profiles belonging to the current mission and organization"',
  "spacecraft-profile-list raw attribute scenario",
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

const scopeScenario = sourceSlice(
  liveViewTestSource,
  '    test "lists only profiles belonging to the current mission and organization"',
  '\n    test "creates a spacecraft profile and redirects to the profile show page"',
  "spacecraft-profile-list scope scenario",
)

assert.match(
  scopeScenario,
  /spacecraft_profile_list_vue\(view\)\.props\["presentation"\]\["card"\]\["rows"\]/,
)
assert.match(scopeScenario, /same_org_foreign/)
assert.match(scopeScenario, /other_org_foreign/)

console.log("spacecraft_type_list_page_test passed")
