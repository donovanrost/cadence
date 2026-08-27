import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const scenarioLedger = [
  "the inventory shell is one non-SSR LiveVue parent with one presentation prop and disabled diffing",
  "Phoenix owns authenticated mission scope, catalog order and availability, lifecycle decisions, persistence, flashes, and host paths",
  "mount and every successful lifecycle refresh recompute the complete page presentation",
  "MissionApplicationsPage directly composes the immutable MissionApplications child exactly once",
  "the page root, header, breadcrumbs, application wrapper, copy, classes, and navigation attributes stay exact",
  "the parent transparently re-emits install, disable, and uninstall payloads",
  "the immutable child retains its confirmation behavior and exact application event payload",
  "all six pre-migration application-host and lifecycle scenarios remain one-for-one in place",
  "focused host, one-prop, JSON-totality, raw-attribute, and use-diff coverage is present",
  "the authenticated mission route, mounts, and mission-sidebar layout remain unchanged",
  "only the explicitly immutable MissionApplications.vue child is hashed",
  "router, LiveView, parent SFC, and tests are checked through semantic source slices",
]

assert.equal(
  process.versions.node,
  "24.16.0",
  "mission-applications contracts use pinned Node 24.16.0",
)
assert.equal(scenarioLedger.length, 12)

const __dirname = dirname(fileURLToPath(import.meta.url))
const pagePath = resolve(__dirname, "../vue/MissionApplicationsPage.vue")
const childPath = resolve(__dirname, "../vue/MissionApplications.vue")
const liveViewPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/mission_applications_live.ex",
)
const liveViewTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/mission_applications_live_test.exs",
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

  for (const match of source.matchAll(/<\/?([A-Za-z][\w.-]*)(?:\s[^<>]*?)?>/gs)) {
    const token = match[0]
    const name = match[1]

    if (token.startsWith("</")) {
      assert.equal(stack.pop(), name, `${name} closes the current SFC element`)
    } else if (!token.endsWith("/>") && !voidElements.has(name)) {
      stack.push(name)
    }
  }

  assert.deepEqual(stack, [], "MissionApplicationsPage.vue template tags are balanced")
}

const occurrences = (source, fragment) => source.split(fragment).length - 1
const dataRowImport = 'import CadenceDataRow from "./ui/components/CadenceDataRow.vue"\n'
const migratedDataRowOpen = `          <CadenceDataRow
            v-for="fact in application.status.facts"
            :key="fact.id"
            row-class="hud-data-row"
            label-class="hud-data-label"
            :label="fact.label"
          >`
const predecessorDataRowOpen = `          <div v-for="fact in application.status.facts" :key="fact.id" class="hud-data-row">
            <span class="hud-data-label">{{ fact.label }}</span>`
const migratedDataRowClose = "\n          </CadenceDataRow>"
const predecessorDataRowClose = "\n          </div>"

assert.equal(occurrences(childSource, dataRowImport), 1)
assert.equal(occurrences(childSource, "<CadenceDataRow"), 1)
assert.equal(occurrences(childSource, migratedDataRowOpen), 1)
assert.equal(occurrences(childSource, migratedDataRowClose), 1)

const reconstructedChildSource = childSource
  .replace(dataRowImport, "")
  .replace(migratedDataRowOpen, predecessorDataRowOpen)
  .replace(migratedDataRowClose, predecessorDataRowClose)

assert.doesNotMatch(reconstructedChildSource, /CadenceDataRow/)

assert.equal(
  createHash("sha256").update(reconstructedChildSource).digest("hex"),
  "5bcfc94dbb88b0ed01fe9b67ea77b6e58d0ca226a93d3255c3416ba3a6a0e49f",
  "MissionApplications.vue remains byte-for-byte immutable",
)

const script = pageSource.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = pageSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "MissionApplicationsPage.vue must have a TypeScript script setup block")
assert.ok(template, "MissionApplicationsPage.vue must have a template block")
assertBalancedTemplate(template)

assert.match(script, /^import MissionApplications from "\.\/MissionApplications\.vue"$/m)
assert.equal(script.match(/import .*MissionApplications\.vue/g)?.length, 1)
assert.match(
  script,
  /type MissionApplicationsProps = InstanceType<typeof MissionApplications>\["\$props"\]/,
)
assert.match(script, /defineProps<\{presentation: Presentation\}>\(\)/)
assert.match(script, /install: \[payload: ApplicationEvent\]/)
assert.match(script, /disable: \[payload: ApplicationEvent\]/)
assert.match(script, /uninstall: \[payload: ApplicationEvent\]/)
assert.doesNotMatch(script, /computed|ref\(|watch\(|fetch\(|useRoute|router|window\.confirm/)

const exactBindings = [
  'v-bind="props.presentation.root.attrs"',
  'v-bind="props.presentation.header.attrs"',
  'v-bind="props.presentation.header.body.attrs"',
  'v-bind="props.presentation.header.content.attrs"',
  'v-bind="props.presentation.header.breadcrumbs.attrs"',
  'v-for="item in props.presentation.header.breadcrumbs.items"',
  'v-if="item.separator"',
  'v-bind="item.separator.attrs"',
  "{{ item.separator.text }}",
  'v-if="item.link"',
  'v-bind="item.link.attrs"',
  "{{ item.link.text }}",
  'v-if="item.current"',
  'v-bind="item.current.attrs"',
  "{{ item.current.text }}",
  'v-bind="props.presentation.header.title.attrs"',
  "{{ props.presentation.header.title.text }}",
  'v-bind="props.presentation.header.subtitle.attrs"',
  "{{ props.presentation.header.subtitle.text }}",
  'v-bind="props.presentation.applications_component.attrs"',
  ':applications="props.presentation.applications_component.props.applications"',
  '@install="emit(\'install\', $event)"',
  '@disable="emit(\'disable\', $event)"',
  '@uninstall="emit(\'uninstall\', $event)"',
]

for (const binding of exactBindings) {
  assert.ok(template.includes(binding), `MissionApplicationsPage.vue preserves ${binding}`)
}

assert.equal(template.match(/<MissionApplications\b/g)?.length, 1)
assert.equal(template.match(/<a\b/g)?.length, 1)
assert.doesNotMatch(
  pageSource,
  /\/missions|Install mission-scoped|space-y-6|border-b border-primary|data-phx-link|phx-click|phx-value-key/,
)
assert.doesNotMatch(
  pageSource,
  /application_key|lifecycle_state|installable|manageable|uninstallable|manage_path|unavailable_message|\.sort|\.filter|\.slice|Math\.|v-html|<\.vue|v-component=/,
)

const mountSource = sourceSlice(
  liveViewSource,
  "  def mount(_params, _session, socket) do",
  '  @impl true\n  def handle_event("install_application", %{"key" => application_key}, socket) do',
  "mission-applications mount boundary",
)

assert.match(
  mountSource,
  /HostContext\.mission\(socket\.assigns\.current_mission\.mission_id\)/,
)
assert.match(
  mountSource,
  /assign\(:page_title, "#\{socket\.assigns\.current_mission\.display_name\} Applications"\)/,
)
assert.match(mountSource, /assign\(:nav_item, :mission_applications\)/)
assert.match(mountSource, /assign\(:application_host_context, host_context\)/)
assert.match(mountSource, /assign_applications_presentation\(\)/)

const lifecycleSource = sourceSlice(
  liveViewSource,
  '  def handle_event("install_application", %{"key" => application_key}, socket) do',
  "  @impl true\n  def render(assigns) do",
  "mission-applications lifecycle boundary",
)

assert.match(
  lifecycleSource,
  /ApplicationInventoryLifecycle\.install\(\s+socket,\s+application_key,\s+:allowed,\s+&refresh_applications\/1\s+\)/,
)
assert.match(
  lifecycleSource,
  /ApplicationInventoryLifecycle\.disable\(socket, application_key, &refresh_applications\/1\)/,
)
assert.match(
  lifecycleSource,
  /ApplicationInventoryLifecycle\.uninstall\(socket, application_key, &refresh_applications\/1\)/,
)

const renderSource = sourceSlice(
  liveViewSource,
  "  def render(assigns) do",
  "  @doc false",
  "MissionApplicationsLive render boundary",
)

assert.equal(renderSource.match(/<\.vue/g)?.length, 1)
assert.match(renderSource, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(renderSource, /id="mission-applications-page-component"/)
assert.match(renderSource, /v-component="MissionApplicationsPage"/)
assert.match(renderSource, /presentation=\{@presentation\}/)
assert.match(renderSource, /v-on:install=\{JS\.push\("install_application"\)\}/)
assert.match(renderSource, /v-on:disable=\{JS\.push\("disable_application"\)\}/)
assert.match(renderSource, /v-on:uninstall=\{JS\.push\("uninstall_application"\)\}/)
assert.match(renderSource, /v-diff=\{false\}/)
assert.match(renderSource, /v-ssr=\{false\}/)
assert.match(renderSource, /class="contents"/)
assert.doesNotMatch(renderSource, /<\.page_header|applications=\{|id="mission-applications-component"/)

const rawAttrsSource = sourceSlice(
  liveViewSource,
  "  @doc false\n  def presentation_attrs(attrs) when is_map(attrs) do",
  "  defp assign_applications_presentation(socket) do",
  "mission-applications raw attribute projection",
)

assert.match(rawAttrsSource, /value in \[nil, false\]/)
assert.match(rawAttrsSource, /\{name, true\}, rendered/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, ""\)/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, to_string\(value\)\)/)

const assignPresentationSource = sourceSlice(
  liveViewSource,
  "  defp assign_applications_presentation(socket) do",
  "  defp page_presentation_dto(mission, applications, host_context) do",
  "mission-applications complete presentation assignment",
)

assert.match(
  assignPresentationSource,
  /application_rows\(\s+socket\.assigns\.current_scope,\s+socket\.assigns\.application_host_context\s+\)/,
)
assert.match(assignPresentationSource, /assign\(\s+socket,\s+:presentation,/)
assert.match(
  assignPresentationSource,
  /page_presentation_dto\(\s+socket\.assigns\.current_mission,\s+applications,\s+socket\.assigns\.application_host_context\s+\)/,
)

const presentationSource = sourceSlice(
  liveViewSource,
  "  defp page_presentation_dto(mission, applications, host_context) do",
  "  defp application_rows(scope, host_context) do",
  "mission-applications page presentation DTO",
)

for (const text of [
  "Applications",
  "Install mission-scoped product capabilities and open their host-rendered workspaces.",
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

assert.match(presentationSource, /"id" => "mission-applications-page"/)
assert.match(presentationSource, /"id" => "mission-applications-component"/)
assert.match(
  presentationSource,
  /application_rows_dto\(applications, host_context, mission\.mission_id\)/,
)
assert.match(presentationSource, /~p"\/missions\/#\{mission\.mission_id\}"/)
assert.match(presentationSource, /"data-phx-link" => "redirect"/)
assert.match(presentationSource, /"data-phx-link-state" => "push"/)
assert.match(presentationSource, /"aria-hidden" => "true"/)

const inventoryDecisionSource = sourceSlice(
  liveViewSource,
  "  defp application_rows(scope, host_context) do",
  "  defp atom_string(nil), do: nil",
  "mission-applications Phoenix inventory and DTO boundary",
)

for (const decision of [
  "ApplicationInventory.catalog(scope, host_context)",
  "assign_applications_presentation(socket)",
  "Enum.map(applications, &application_row_dto(&1, host_context, mission_id))",
  "ApplicationInventory.dom_id(host_context, application.application_key)",
  'manage_path: ~p"/missions/#{mission_id}/applications/#{application.application_key}"',
  "status: status_dto(application.status)",
  'install_action: install_action_dto(application, card_id)',
  'if(application.manageable?, do: lifecycle_action_dto("disable", card_id))',
  'if(application.uninstallable?, do: lifecycle_action_dto("uninstall", card_id))',
  "LifecycleActions.fetch(action_id)",
  "ActionConfirmation.prompt(confirmation)",
]) {
  assert.ok(inventoryDecisionSource.includes(decision), `${decision} remains Phoenix-owned`)
}

assert.match(
  inventoryDecisionSource,
  /defp refresh_applications\(socket\) do\n    assign_applications_presentation\(socket\)\n  end/,
)

for (const childContract of [
  "defineProps<{applications: ApplicationCard[]}>()",
  "install: [payload: ApplicationEvent]",
  "disable: [payload: ApplicationEvent]",
  "uninstall: [payload: ApplicationEvent]",
  "if (action.confirmation && !window.confirm(action.confirmation.prompt)) return",
  "emit(event, {key: application.application_key})",
  'id="mission-applications-list"',
  ':data-application-lifecycle-action="application.disable_action.action_id"',
  ':data-confirm="application.disable_action.confirmation?.prompt"',
  ':data-confirm="application.uninstall_action.confirmation?.prompt"',
]) {
  assert.ok(childSource.includes(childContract), `${childContract} stays in the immutable child`)
}

const broadTestSource = sourceSlice(
  liveViewTestSource,
  '  test "installs a registered mission application from the host inventory", context do',
  '  test "projects the complete inventory shell through one JSON-safe non-SSR parent", context do',
  "mission-applications original scenario ledger",
)

for (const scenario of [
  'test "installs a registered mission application from the host inventory"',
  'test "renders and submits a generated form through the declarative host"',
  'test "paginates declarative application tables through shareable host state"',
  'test "disables, uninstalls, and reinstalls a mission application"',
  'test "installs limits and versions a governed threshold definition through the host"',
  'test "known but uninstalled mission application redirects to the inventory"',
]) {
  assert.ok(broadTestSource.includes(scenario), `${scenario} remains one-for-one in place`)
}

assert.equal(broadTestSource.match(/^  test /gm)?.length, 6)
assert.match(
  liveViewTestSource,
  /LiveVue\.Test\.get_vue\(view, id: "mission-applications-page-component"\)/,
)
assert.doesNotMatch(
  liveViewTestSource,
  /LiveVue\.Test\.get_vue\(view, id: "mission-applications-component"\)/,
)
assert.match(
  liveViewTestSource,
  /get_in\(\["applications_component", "props", "applications"\]\)/,
)
assert.match(liveViewTestSource, /vue\.use_diff == false/)
assert.match(liveViewTestSource, /Map\.keys\(vue\.props\) == \["presentation"\]/)
assert.match(liveViewTestSource, /Jason\.decode!\(Jason\.encode!\(presentation\)\)/)
assert.match(liveViewTestSource, /MissionApplicationsLive\.presentation_attrs/)
assert.match(liveViewTestSource, /"nil" => nil/)
assert.match(liveViewTestSource, /"false" => false/)
assert.match(liveViewTestSource, /"true" => true/)
assert.match(liveViewTestSource, /"number" => 7/)

assert.match(
  routerSource,
  /scope "\/", CadenceWeb do\n    pipe_through \[:browser, :require_authenticated_scope\]/,
)

const missionSession = sourceSlice(
  routerSource,
  "    live_session :mission,",
  "    live_session :spacecraft,",
  "mission LiveSession",
)

assert.match(missionSession, /CadenceWeb\.OrganizationAuth, :require_organization_scope/)
assert.match(missionSession, /CadenceWeb\.MissionAuth, :load_mission/)
assert.match(missionSession, /CadenceWeb\.UserAuth, :attach_user_menu/)
assert.match(missionSession, /layout: \{CadenceWeb\.Layouts, :mission_sidebar\}/)
assert.match(
  missionSession,
  /live "\/missions\/:mission_id\/applications", MissionApplicationsLive, :index/,
)
assert.match(
  missionSession,
  /live "\/missions\/:mission_id\/applications\/:application_key",\s+ApplicationHostLive,\s+:show/,
)
assert.match(
  missionSession,
  /live "\/missions\/:mission_id\/applications\/:application_key\/:surface_id",\s+ApplicationHostLive,\s+:show/,
)
assert.doesNotMatch(missionSession, /require_organization_admin|require_platform_admin/)

console.log("mission applications page semantic contract passed")
