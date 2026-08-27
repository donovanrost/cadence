import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const scenarioLedger = [
  "the full Spacecraft Applications inventory is one non-SSR parent with one presentation prop",
  "Phoenix owns organization, mission, spacecraft, profile, catalog, install-policy, and lifecycle decisions",
  "mount and every lifecycle refresh recompute the complete page presentation",
  "the exact four-level breadcrumbs, header, subtitle, Readiness action, page root, and child wrapper remain",
  "SpacecraftApplicationsPage directly composes the immutable SpacecraftApplications child once",
  "install, disable, and uninstall payloads are transparently re-emitted to the same JS.push handlers",
  "the immutable child retains status, actions, navigation attrs, raw lifecycle attrs, and confirmation behavior",
  "raw attrs preserve HEEx nil, false, true, empty string, string, and number behavior",
  "all nine pre-migration domain scenarios and every focused oracle remain one-for-one",
  "the authenticated spacecraft-show route, mounts, action, and mission-sidebar layout remain exact",
  "router and tests use semantic source slices; only immutable SpacecraftApplications.vue is hashed",
]

assert.equal(
  process.versions.node,
  "24.16.0",
  "Spacecraft Applications contracts use pinned Node 24.16.0",
)
assert.equal(scenarioLedger.length, 11)

const __dirname = dirname(fileURLToPath(import.meta.url))
const pagePath = resolve(__dirname, "../vue/SpacecraftApplicationsPage.vue")
const childPath = resolve(__dirname, "../vue/SpacecraftApplications.vue")
const liveViewPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/spacecraft_applications_live.ex",
)
const liveViewTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/spacecraft_applications_live_test.exs",
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

const occurrences = (source, fragment) => source.split(fragment).length - 1
const dataRowImport = 'import CadenceDataRow from "./ui/components/CadenceDataRow.vue"\n'
const migratedDataRowOpen = `            <CadenceDataRow
              v-for="fact in application.status.facts"
              :key="fact.id"
              row-class="hud-data-row"
              label-class="hud-data-label"
              :label="fact.label"
            >`
const predecessorDataRowOpen = `            <div v-for="fact in application.status.facts" :key="fact.id" class="hud-data-row">
              <span class="hud-data-label">{{ fact.label }}</span>`
const migratedDataRowClose = "\n            </CadenceDataRow>"
const predecessorDataRowClose = "\n            </div>"

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
  "3f4a33eb98893bc456f232cf64b00bab0db6bea5d2bc21fcf0f8f8a39392bb73",
  "SpacecraftApplications.vue remains the explicitly immutable child",
)

const script = pageSource.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = pageSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "SpacecraftApplicationsPage.vue has a TypeScript script setup block")
assert.ok(template, "SpacecraftApplicationsPage.vue has a template block")
assertBalancedTemplate(template)

assert.match(script, /import SpacecraftApplications from "\.\/SpacecraftApplications\.vue"/)
assert.match(
  script,
  /type SpacecraftApplicationsProps = InstanceType<typeof SpacecraftApplications>\["\$props"\]/,
)
assert.match(script, /profile: SpacecraftApplicationsProps\["profile"\]/)
assert.match(script, /applications: SpacecraftApplicationsProps\["applications"\]/)
assert.match(script, /defineProps<\{presentation: Presentation\}>\(\)/)
assert.match(script, /install: \[payload: ApplicationEvent\]/)
assert.match(script, /disable: \[payload: ApplicationEvent\]/)
assert.match(script, /uninstall: \[payload: ApplicationEvent\]/)

assert.equal(template.match(/<SpacecraftApplications\b/g)?.length, 1)
assert.match(template, /:profile="props\.presentation\.profile"/)
assert.match(template, /:applications="props\.presentation\.applications"/)
assert.match(template, /@install="emit\('install', \$event\)"/)
assert.match(template, /@disable="emit\('disable', \$event\)"/)
assert.match(template, /@uninstall="emit\('uninstall', \$event\)"/)

for (const binding of [
  "props.presentation.root.attrs",
  "props.presentation.header.attrs",
  "props.presentation.header.body.attrs",
  "props.presentation.header.content.attrs",
  "props.presentation.header.breadcrumbs.attrs",
  "item.separator.attrs",
  "item.link.attrs",
  "item.current.attrs",
  "props.presentation.header.title.attrs",
  "props.presentation.header.subtitle.attrs",
  "props.presentation.header.actions.attrs",
  "props.presentation.header.actions.readiness.attrs",
  "props.presentation.component.attrs",
]) {
  assert.ok(template.includes(`v-bind="${binding}"`), `${binding} stays DTO-owned`)
}

for (const textBinding of [
  "item.separator.text",
  "item.link.text",
  "item.current.text",
  "props.presentation.header.title.text",
  "props.presentation.header.subtitle.text",
  "props.presentation.header.actions.readiness.text",
]) {
  assert.ok(template.includes(`{{ ${textBinding} }}`), `${textBinding} stays DTO-owned`)
}

assert.doesNotMatch(
  pageSource,
  /Install profile-declared|Readiness|Pinned Profile|No profile selected|Profile drift|Not installed/,
)
assert.doesNotMatch(pageSource, /\/missions|data-phx-link|window\.confirm|JS\.push|v-html/)
assert.doesNotMatch(
  pageSource,
  /space-y-6|border-primary|text-2xl|text-base-content|btn-ghost|spacecraft-applications-page/,
)

for (const childContract of [
  'id="spacecraft-applications-inventory" class="space-y-6"',
  'id="spacecraft-applications-list"',
  'data-phx-link="redirect"',
  'data-phx-link-state="push"',
  ':data-application-lifecycle-action="application.disable_action.action_id"',
  ':data-confirm="application.disable_action.confirmation?.prompt"',
  ':data-application-lifecycle-action="application.uninstall_action.action_id"',
  ':data-confirm="application.uninstall_action.confirmation?.prompt"',
  "window.confirm(action.confirmation.prompt)",
  "emit(event, {key: application.application_key})",
]) {
  assert.ok(childSource.includes(childContract), `${childContract} remains in the immutable child`)
}

const mountSource = sourceSlice(
  liveViewSource,
  "  def mount(_params, _session, socket) do",
  '  @impl true\n  def handle_event("install_application"',
  "SpacecraftApplicationsLive mount",
)

assert.match(
  mountSource,
  /%\{current_scope: scope, current_mission: mission, current_spacecraft: spacecraft\}/,
)
assert.match(
  mountSource,
  /load_type_binding\(scope\.organization_id, mission\.mission_id, spacecraft\)/,
)
assert.match(mountSource, /HostContext\.spacecraft\(mission\.mission_id, spacecraft\.spacecraft_id\)/)
assert.match(mountSource, /applications = application_rows\(scope, type_binding, host_context\)/)
assert.match(
  mountSource,
  /page_presentation_dto\(mission, spacecraft, type_binding, applications, host_context\)/,
)
assert.match(mountSource, /assign\(:page_title, "#\{spacecraft\.display_name\} Applications"\)/)
assert.match(mountSource, /assign\(:nav_item, :spacecraft\)/)
assert.match(mountSource, /assign\(:type_binding, type_binding\)/)
assert.match(mountSource, /assign\(:application_host_context, host_context\)/)
assert.match(mountSource, /assign\(:presentation, presentation\)/)

const eventSource = sourceSlice(
  liveViewSource,
  '  def handle_event("install_application"',
  "  @impl true\n  def render(assigns) do",
  "Spacecraft Applications lifecycle events",
)

assert.match(eventSource, /decision = install_decision\(scope, type_binding, host_context, application_key\)/)
assert.match(eventSource, /ApplicationInventoryLifecycle\.install\(/)
assert.match(eventSource, /ApplicationInventoryLifecycle\.disable\(/)
assert.match(eventSource, /ApplicationInventoryLifecycle\.uninstall\(/)
assert.equal(eventSource.match(/&refresh_applications\/1/g)?.length, 3)

const renderSource = sourceSlice(
  liveViewSource,
  "  def render(assigns) do",
  "  @doc false",
  "Spacecraft Applications LiveVue boundary",
)

assert.equal(renderSource.match(/<\.vue/g)?.length, 1)
assert.match(renderSource, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(renderSource, /id="spacecraft-applications-page-component"/)
assert.match(renderSource, /v-component="SpacecraftApplicationsPage"/)
assert.match(renderSource, /presentation=\{@presentation\}/)
assert.match(renderSource, /v-on:install=\{JS\.push\("install_application"\)\}/)
assert.match(renderSource, /v-on:disable=\{JS\.push\("disable_application"\)\}/)
assert.match(renderSource, /v-on:uninstall=\{JS\.push\("uninstall_application"\)\}/)
assert.match(renderSource, /v-diff=\{false\}/)
assert.match(renderSource, /v-ssr=\{false\}/)
assert.match(renderSource, /class="contents"/)
assert.doesNotMatch(renderSource, /<\.page_header|<\.button|profile=|applications=/)
assert.doesNotMatch(renderSource, /phx-hook|spacecraft-applications-page"/)

const rawAttrsSource = sourceSlice(
  liveViewSource,
  "  @doc false\n  def presentation_attrs(attrs) when is_map(attrs) do",
  "  defp page_presentation_dto(",
  "Spacecraft Applications raw attribute projection",
)

assert.match(rawAttrsSource, /value in \[nil, false\]/)
assert.match(rawAttrsSource, /\{name, true\}, rendered/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, ""\)/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, to_string\(value\)\)/)

const presentationSource = sourceSlice(
  liveViewSource,
  "  defp page_presentation_dto(",
  "  defp application_rows(scope, nil, host_context) do",
  "Spacecraft Applications page presentation",
)

for (const topLevelKey of ["root", "header", "component", "profile", "applications"]) {
  assert.ok(presentationSource.includes(`"${topLevelKey}" =>`), `${topLevelKey} stays in presentation`)
}

for (const text of [
  "Applications",
  "Install profile-declared product applications and open their host-rendered workspaces.",
  "Spacecraft",
  "Readiness",
]) {
  assert.ok(presentationSource.includes(`"${text}"`), `${text} stays Phoenix-owned`)
}

for (const className of [
  "space-y-6",
  "border-b border-primary/20 pb-4",
  "flex items-end justify-between gap-4",
  "mt-2 text-2xl font-bold text-base-content tracking-tight",
  "mt-1 max-w-3xl text-sm text-base-content/70",
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60",
  "hover:text-primary transition-colors",
  "text-base-content/20",
  "text-primary/90",
  "flex items-center gap-2",
  "btn btn-ghost btn-sm",
]) {
  assert.ok(presentationSource.includes(`"${className}"`), `${className} stays Phoenix-owned`)
}

assert.match(presentationSource, /"id" => "spacecraft-applications-page"/)
assert.match(presentationSource, /"id" => "spacecraft-applications-component"/)
assert.equal(presentationSource.match(/breadcrumb_separator\(\)/g)?.length, 3)
assert.match(presentationSource, /"data-phx-link" => "redirect"/)
assert.match(presentationSource, /"data-phx-link-state" => "push"/)
assert.match(presentationSource, /profile_card_dto\(type_binding, mission_id, spacecraft_id\)/)
assert.match(
  presentationSource,
  /application_rows_dto\(applications, host_context, mission_id, spacecraft_id\)/,
)

const inventorySource = sourceSlice(
  liveViewSource,
  "  defp application_rows(scope, nil, host_context) do",
  "  defp load_type_binding(_organization_id, _mission_id, %{spacecraft_type_id: nil}), do: nil",
  "Spacecraft Applications inventory and install policy",
)

assert.match(inventorySource, /load_application_rows\(scope, host_context, %\{\}\)/)
assert.match(inventorySource, /%\{pinned: %\{applications: applications\}\}/)
assert.match(inventorySource, /ApplicationInventory\.declared\(scope, host_context, applications\)/)
assert.match(inventorySource, /\{:error, _reason\} -> \[\]/)
assert.match(inventorySource, /Map\.has_key\?\(applications, application_key\)/)
assert.match(inventorySource, /desired_application\?\(type_binding, application_key\) or/)
assert.match(inventorySource, /retained_application\?\(scope, host_context, application_key\)/)
assert.match(
  inventorySource,
  /Application is neither declared by this profile nor retained at this scope\./,
)
assert.match(inventorySource, /ApplicationInstallations\.fetch\(scope, host_context, application_key\)/)

const typeBindingSource = sourceSlice(
  liveViewSource,
  "  defp load_type_binding(_organization_id, _mission_id, %{spacecraft_type_id: nil}), do: nil",
  "  defp refresh_applications(socket) do",
  "Spacecraft Applications pinned profile binding",
)

assert.match(typeBindingSource, /fetch_spacecraft_type_version\(/)
assert.match(typeBindingSource, /organization_id,\s+mission_id,\s+spacecraft\.spacecraft_type_id,/s)
assert.match(typeBindingSource, /spacecraft\.spacecraft_type_version/)
assert.match(typeBindingSource, /fetch_spacecraft_type\(/)
assert.match(typeBindingSource, /latest_version: latest_type\.version/)
assert.match(typeBindingSource, /drift\?: latest_type\.version > pinned_type\.version/)
assert.match(typeBindingSource, /drift\?: false/)

const refreshSource = sourceSlice(
  liveViewSource,
  "  defp refresh_applications(socket) do",
  "  defp profile_card_dto(nil, mission_id, spacecraft_id) do",
  "Spacecraft Applications lifecycle refresh",
)

assert.match(refreshSource, /socket\.assigns\.current_scope/)
assert.match(refreshSource, /socket\.assigns\.type_binding/)
assert.match(refreshSource, /socket\.assigns\.application_host_context/)
assert.match(refreshSource, /page_presentation_dto\(/)
assert.match(refreshSource, /socket\.assigns\.current_mission/)
assert.match(refreshSource, /socket\.assigns\.current_spacecraft/)
assert.match(refreshSource, /assign\(socket, :presentation, presentation\)/)

for (const serverDecision of [
  "defp profile_card_dto(nil",
  "defp profile_card_dto(%{pinned:",
  "defp application_rows_dto",
  "defp application_row_dto",
  "defp status_dto",
  "defp install_action_dto",
  "defp lifecycle_action_dto",
  "defp confirmation_dto(nil)",
  "defp confirmation_dto(%ActionConfirmation{}",
  "defp install_label(:disabled)",
  "defp install_label(:uninstalled)",
  "defp install_label(:installed)",
  "defp atom_string",
]) {
  assert.ok(liveViewSource.includes(serverDecision), `${serverDecision} remains Phoenix-owned`)
}

for (const decisionContract of [
  'kind: "missing"',
  'id: "spacecraft-applications-no-profile"',
  'title: "No profile selected"',
  'label: "Select profile"',
  'kind: "pinned"',
  'id: "spacecraft-applications-profile"',
  'tone: if(drift?, do: "attention", else: "ready")',
  'label: if(drift?, do: "Profile drift", else: "Current")',
  "ApplicationInventory.dom_id",
  "application.installable?",
  "application.manageable?",
  "application.uninstallable?",
  'scope_label: "Application"',
  "status_dto(application.status)",
  'lifecycle_action_dto("disable", card_id)',
  'lifecycle_action_dto("uninstall", card_id)',
  "ActionConfirmation.prompt(confirmation)",
]) {
  assert.ok(liveViewSource.includes(decisionContract), `${decisionContract} stays server-authored`)
}

const existingScenarioNames = [
  "projects the page, pinned profile, and application card through exact LiveVue props",
  "preserves pinned profile drift plus deterministic custom application order and safe IDs",
  "refreshes manage, disable, uninstall, and reinstall lifecycle DTOs after each hook",
  "keeps a retained application visible and reinstallable without a pinned profile",
  "preserves missing-profile and empty pinned-profile presentation conditions",
  "denies installation outside the declared-or-retained spacecraft policy",
  "unknown application detail redirects back to the applications list",
  "known but uninstalled application detail redirects to the inventory",
  "missing spacecraft and unauthenticated inventory requests preserve router redirects",
]

assert.equal(existingScenarioNames.length, 9)
for (const scenario of existingScenarioNames) {
  assert.equal(
    liveViewTestSource.split(`test "${scenario}"`).length - 1,
    1,
    `${scenario} remains one-for-one`,
  )
}
assert.equal(liveViewTestSource.match(/^  test "/gm)?.length, 10)
assert.match(liveViewTestSource, /Map\.keys\(vue\.props\) == \["presentation"\]/)
assert.match(liveViewTestSource, /Jason\.decode!\(Jason\.encode!\(vue\.props\)\)/)
assert.match(
  liveViewTestSource,
  /LiveVue\.Test\.get_vue\(view, id: "spacecraft-applications-page-component"\)/,
)
assert.match(liveViewTestSource, /Map\.fetch!\("presentation"\)/)
assert.match(liveViewTestSource, /element\("#spacecraft-applications-page-component"\)/)
assert.match(
  liveViewTestSource,
  /SpacecraftApplicationsLive\.presentation_attrs\(%\{[\s\S]*"nil" => nil,[\s\S]*"false" => false,[\s\S]*"true" => true,[\s\S]*"empty" => "",[\s\S]*"string_false" => "false",[\s\S]*"number" => 7/,
)

const authenticatedScopeSource = sourceSlice(
  routerSource,
  '  scope "/", CadenceWeb do\n    pipe_through [:browser, :require_authenticated_scope]',
  "    live_session :organization,",
  "authenticated browser scope",
)

assert.match(authenticatedScopeSource, /pipe_through \[:browser, :require_authenticated_scope\]/)

const spacecraftShowSessionSource = sourceSlice(
  routerSource,
  "    live_session :spacecraft_show,",
  "    live_session :catalog,",
  "spacecraft-show LiveSession",
)

const mountContracts = [
  "{CadenceWeb.OrganizationAuth, :require_organization_scope}",
  "{CadenceWeb.MissionAuth, :load_mission}",
  "{CadenceWeb.SpacecraftAuth, :load_spacecraft}",
  "{CadenceWeb.UserAuth, :attach_user_menu}",
]

for (const mount of mountContracts) {
  assert.ok(spacecraftShowSessionSource.includes(mount), `${mount} remains on the route`)
}

assert.ok(
  mountContracts.every(
    (mount, index) =>
      index === 0 ||
      spacecraftShowSessionSource.indexOf(mountContracts[index - 1]) <
        spacecraftShowSessionSource.indexOf(mount),
  ),
  "spacecraft-show mounts stay in their exact order",
)
assert.match(
  spacecraftShowSessionSource,
  /layout: \{CadenceWeb\.Layouts, :mission_sidebar\}/,
)
assert.match(
  spacecraftShowSessionSource,
  /live "\/missions\/:mission_id\/spacecraft\/:spacecraft_id\/applications",\s+SpacecraftApplicationsLive,\s+:index/,
)
assert.doesNotMatch(spacecraftShowSessionSource, /SpacecraftApplicationsLive,\s+:show/)

console.log("spacecraft_applications_page_test passed")
