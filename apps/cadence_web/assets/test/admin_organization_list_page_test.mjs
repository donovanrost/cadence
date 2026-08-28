import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const scenarioLedger = [
  "one non-SSR AdminOrganizationListPage host owns the complete page boundary",
  "Phoenix retains organization loading, slug ordering, empty/card selection, row projection, and routes",
  "AdminOrganizationListPage composes the shared Cadence page shell and byte-pinned AdminOrganizationList child",
  "the DTO binds the exact root, header, breadcrumb, action, empty-state, card, class, ID, and copy contracts",
  "all three anchors receive server-rendered LiveView redirect navigation attrs",
  "all existing AdminLiveTest scenarios and assertions remain in the same broad test file",
  "raw attrs retain HEEx nil, false, true, empty-string, string, and number semantics",
  "the authenticated admin scope, platform-admin mount, user-menu mount, and sidebar layout remain unchanged",
]

assert.equal(
  process.versions.node,
  "24.16.0",
  "Admin Organization List contracts use pinned Node 24.16.0",
)
assert.equal(scenarioLedger.length, 8)

const __dirname = dirname(fileURLToPath(import.meta.url))
const paths = {
  component: resolve(__dirname, "../vue/AdminOrganizationListPage.vue"),
  immutableChild: resolve(__dirname, "../vue/AdminOrganizationList.vue"),
  breadcrumbs: resolve(__dirname, "../vue/ui/components/CadenceBreadcrumbs.vue"),
  pageHeader: resolve(__dirname, "../vue/ui/components/CadencePageHeader.vue"),
  emptyState: resolve(__dirname, "../vue/ui/components/CadenceEmptyState.vue"),
  pageShellTypes: resolve(__dirname, "../vue/ui/components/page_shell.ts"),
  liveView: resolve(__dirname, "../../lib/cadence_web/live/admin_organization_list_live.ex"),
  presentation: resolve(
    __dirname,
    "../../lib/cadence_web/live/admin_organization_list_live/presentation.ex",
  ),
  organizations: resolve(__dirname, "../../../cadence/lib/cadence/organizations.ex"),
  router: resolve(__dirname, "../../lib/cadence_web/router.ex"),
  broadTest: resolve(__dirname, "../../test/cadence_web/live/admin_live_test.exs"),
}

const [
  component,
  immutableChild,
  breadcrumbs,
  pageHeader,
  emptyState,
  pageShellTypes,
  liveView,
  presentation,
  organizations,
  router,
  broadTest,
] = await Promise.all(Object.values(paths).map((path) => readFile(path, "utf8")))

const sha256 = (source) => createHash("sha256").update(source).digest("hex")

assert.equal(
  immutableChild.match(
    /^import CadenceTableFrame from "\.\/ui\/components\/CadenceTableFrame\.vue"$/gm,
  )?.length,
  1,
  "AdminOrganizationList.vue has one CadenceTableFrame import before compatibility peeling",
)
assert.equal(
  immutableChild.match(/<\/?CadenceTableFrame\b/g)?.length,
  2,
  "AdminOrganizationList.vue has one CadenceTableFrame boundary before compatibility peeling",
)

const predecessorImmutableChild = immutableChild
  .replace('import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"\n\n', "")
  .replace(
    '  <CadenceTableFrame id="admin-orgs-table">',
    '  <table id="admin-orgs-table" class="table">',
  )
  .replace("  </CadenceTableFrame>", "  </table>")

assert.doesNotMatch(
  predecessorImmutableChild,
  /CadenceTableFrame/,
  "AdminOrganizationList.vue predecessor has no residual CadenceTableFrame shell",
)

assert.equal(
  sha256(predecessorImmutableChild),
  "a40163d97f403117e58ccc4e2338c76d1e1c5c5d96cac636e4651d30cf3ebcaf",
  "AdminOrganizationList.vue remains byte-identical to the frozen source",
)

const script = component.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = component.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "AdminOrganizationListPage.vue keeps an auditable TypeScript setup block")
assert.ok(template, "AdminOrganizationListPage.vue keeps an auditable template block")

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

  assert.deepEqual(stack, [], "AdminOrganizationListPage.vue template tags are balanced")
}

assertBalancedTemplate(template)

const breadcrumbsTemplate = breadcrumbs.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const pageHeaderTemplate = pageHeader.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const emptyStateTemplate = emptyState.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(breadcrumbsTemplate, "CadenceBreadcrumbs.vue keeps an auditable template block")
assert.ok(pageHeaderTemplate, "CadencePageHeader.vue keeps an auditable template block")
assert.ok(emptyStateTemplate, "CadenceEmptyState.vue keeps an auditable template block")
assertBalancedTemplate(breadcrumbsTemplate)
assertBalancedTemplate(pageHeaderTemplate)
assertBalancedTemplate(emptyStateTemplate)

assert.match(script, /^import AdminOrganizationList from "\.\/AdminOrganizationList\.vue"$/m)
assert.equal(script.match(/import .*AdminOrganizationList\.vue/g)?.length, 1)
assert.match(script, /import CadenceEmptyState from "\.\/ui\/components\/CadenceEmptyState\.vue"/)
assert.match(script, /import CadencePageHeader from "\.\/ui\/components\/CadencePageHeader\.vue"/)
assert.match(script, /defineProps<\{presentation: AdminOrganizationListPresentation\}>\(\)/)
assert.doesNotMatch(script, /computed|ref\(|watch\(|fetch\(|defineEmits|useRoute|router/)

const headerAdapterSource = script.slice(
  script.indexOf("const headerPresentation"),
  script.indexOf("const emptyStatePresentation"),
)

assert.doesNotMatch(
  headerAdapterSource,
  /\bsuffix\b|\bsubtitle\b/,
  "the Admin adapter does not invent the omitted title suffix or subtitle",
)

const pageBindings = [
  'v-bind="props.presentation.root.attrs"',
  '<CadencePageHeader',
  ':header="headerPresentation(props.presentation.header)"',
  ':action="props.presentation.header.create_action"',
  '<CadenceEmptyState',
  'v-if="props.presentation.empty_state"',
  ':empty-state="emptyStatePresentation(props.presentation.empty_state)"',
  'v-if="props.presentation.card"',
  'v-bind="props.presentation.card.root.attrs"',
  'v-bind="props.presentation.card.body.attrs"',
  'v-bind="props.presentation.card.child.attrs"',
  '<AdminOrganizationList :rows="props.presentation.card.rows" />',
]

let previousPageBindingIndex = -1

for (const binding of pageBindings) {
  const bindingIndex = template.indexOf(binding, previousPageBindingIndex + 1)

  assert.ok(
    bindingIndex > previousPageBindingIndex,
    `AdminOrganizationListPage.vue preserves ${binding} in sibling order`,
  )
  previousPageBindingIndex = bindingIndex
}

for (const adapterBinding of [
  "attrs: header.root.attrs",
  "body: header.layout",
  "content: header.content",
  "attrs: header.breadcrumbs.root.attrs",
  "header.breadcrumbs.items.map((breadcrumb)",
  "key: breadcrumb.content.text",
  "separator: breadcrumb.separator",
  'link: breadcrumb.kind === "link" ? breadcrumb.content : null',
  'current: breadcrumb.kind === "current" ? breadcrumb.content : null',
  "title: header.title",
  "actions: header.actions",
  "attrs: emptyState.root.attrs",
  "title: emptyState.title",
  "description: emptyState.description",
  "action_container: emptyState.action_container",
  "...emptyState.action",
  "icon: emptyState.action_icon",
]) {
  assert.ok(script.includes(adapterBinding), `the Admin DTO adapter preserves ${adapterBinding}`)
}

for (const binding of [
  '<nav v-bind="props.breadcrumbs.attrs">',
  'v-for="item in props.breadcrumbs.items"',
  ':key="item.key"',
  'v-if="item.separator"',
  'v-bind="item.separator.attrs"',
  "{{ item.separator.text }}",
  'v-if="item.link"',
  'v-bind="item.link.attrs"',
  "{{ item.link.text }}",
  'v-if="item.current"',
  'v-bind="item.current.attrs"',
  "{{ item.current.text }}",
]) {
  assert.ok(breadcrumbsTemplate.includes(binding), `CadenceBreadcrumbs.vue preserves ${binding}`)
}

for (const binding of [
  '<header v-bind="props.header.attrs">',
  'v-bind="props.header.body.attrs"',
  'v-bind="props.header.content.attrs"',
  ':breadcrumbs="props.header.breadcrumbs"',
  'v-bind="props.header.title.attrs"',
  "{{ props.header.title.text }}",
  'v-if="props.header.title.suffix"',
  'v-bind="props.header.title.suffix.attrs"',
  "{{ props.header.title.suffix.text }}",
  'v-if="props.header.subtitle"',
  'v-bind="props.header.subtitle.attrs"',
  "{{ props.header.subtitle.text }}",
  'v-bind="props.header.actions.attrs"',
  'v-bind="props.action.attrs"',
  'v-if="props.action.icon"',
  'v-bind="props.action.icon.attrs"',
  "{{ props.action.text }}",
]) {
  assert.ok(pageHeaderTemplate.includes(binding), `CadencePageHeader.vue preserves ${binding}`)
}

for (const binding of [
  '<div v-bind="props.emptyState.attrs">',
  'v-bind="props.emptyState.title.attrs"',
  "{{ props.emptyState.title.text }}",
  'v-bind="props.emptyState.description.attrs"',
  "{{ props.emptyState.description.text }}",
  'v-bind="props.emptyState.action_container.attrs"',
  'v-bind="props.emptyState.action.attrs"',
  'v-bind="props.emptyState.action.icon.attrs"',
  "{{ props.emptyState.action.text }}",
]) {
  assert.ok(emptyStateTemplate.includes(binding), `CadenceEmptyState.vue preserves ${binding}`)
}

assert.match(pageShellTypes, /suffix: TextPresentation/)
assert.match(pageShellTypes, /export type CompactPageHeaderPresentation = Omit</)
assert.match(pageShellTypes, /suffix\?: null/)
assert.match(pageShellTypes, /subtitle\?: null/)
assert.equal(template.match(/<AdminOrganizationList\b/g)?.length, 1)
assert.equal(template.match(/<CadencePageHeader\b/g)?.length, 1)
assert.equal(template.match(/<CadenceEmptyState\b/g)?.length, 1)
assert.equal(
  [breadcrumbsTemplate, pageHeaderTemplate, emptyStateTemplate].join("\n").match(/<a\b/g)?.length,
  3,
)
assert.doesNotMatch(component, /\/admin|data-phx-link|data-phx-link-state|Create organization/)

assert.equal(liveView.match(/<\.vue\b/g)?.length, 1)
assert.match(liveView, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(liveView, /id="admin-organization-list-page-component"/)
assert.match(liveView, /v-component="AdminOrganizationListPage"/)
assert.match(liveView, /presentation=\{@presentation\}/)
assert.match(liveView, /v-ssr=\{false\}/)
assert.doesNotMatch(liveView, /v-component="AdminOrganizationList"|rows=\{@organization_rows\}/)

for (const authority of [
  "Cadence.Organizations.list_organizations()",
  "Presentation.build(organizations)",
]) {
  assert.ok(liveView.includes(authority), `Phoenix retains ${authority}`)
}

assert.match(presentation, /rows = Enum\.map\(organizations, &organization_row\/1\)/)
assert.match(presentation, /navigate_attrs\(~p"\/admin\/organizations\/new"/)
assert.match(presentation, /navigate_attrs\(~p"\/admin"/)
assert.match(presentation, /href: ~p"\/admin\/organizations\/#\{organization\.organization_id\}"/)
assert.match(presentation, /defp empty_state_presentation\(\[\], create_organization_attrs\)/)
assert.match(
  presentation,
  /defp empty_state_presentation\(_rows, _create_organization_attrs\), do: nil/,
)
assert.match(presentation, /defp card_presentation\(\[\]\), do: nil/)
assert.match(presentation, /attrs: raw_attrs\(%\{"id" => "admin-organization-list-component"\}\)/)
assert.match(presentation, /\{_name, value\}, rendered when value in \[nil, false\]/)
assert.match(presentation, /\{name, true\}, rendered/)
assert.match(presentation, /Map\.put\(rendered, name, ""\)/)
assert.match(presentation, /Map\.put\(rendered, name, to_string\(value\)\)/)

const sourceSlice = (source, startMarker, endMarker, label) => {
  const start = source.indexOf(startMarker)
  const end = source.indexOf(endMarker, start + startMarker.length)

  assert.ok(start >= 0, `${label} start remains present`)
  assert.ok(end > start, `${label} end remains present`)

  return source.slice(start, end)
}

const createActionPresentation = sourceSlice(
  presentation,
  "        create_action: %{",
  "\n      },\n      empty_state:",
  "Admin create action presentation",
)

assert.doesNotMatch(
  createActionPresentation,
  /icon/,
  "the Admin header action remains the icon-free optional-action case",
)

const organizationListQuery = sourceSlice(
  organizations,
  "  def list_organizations do",
  "\n  @spec count_organizations()",
  "organization list ordering query",
)

assert.match(organizationListQuery, /order_by\(\[organization_row\], asc: organization_row\.slug\)/)
assert.match(organizationListQuery, /Enum\.map\(&OrganizationRow\.to_domain\/1\)/)

const authenticatedAdminScope = sourceSlice(
  router,
  '  scope "/", CadenceWeb do\n    pipe_through [:browser, :require_authenticated_scope]',
  '\n  scope "/api", CadenceWeb do',
  "authenticated admin router scope",
)

const adminLiveSession = sourceSlice(
  authenticatedAdminScope,
  "    live_session :admin,",
  "\n    end\n  end",
  "admin LiveSession",
)

assert.match(adminLiveSession, /\{CadenceWeb\.AdminAuth, :require_platform_admin\}/)
assert.match(adminLiveSession, /\{CadenceWeb\.UserAuth, :attach_user_menu\}/)
assert.match(adminLiveSession, /layout: \{CadenceWeb\.Layouts, :sidebar\} do/)
assert.match(
  adminLiveSession,
  /^      live "\/admin\/organizations", AdminOrganizationListLive, :index$/m,
)
assert.equal(
  router.match(/live "\/admin\/organizations", AdminOrganizationListLive, :index/g)?.length,
  1,
)

const existingScenarios = [
  "non-admin user is redirected to /",
  "admin-eligible durable user without admin mode is redirected to reauthenticate",
  "platform admin can access the dashboard",
  "admin dashboard shows organization and user counts",
  "organization list shows empty state when no orgs exist",
  "admin can create an organization",
  "organization validation preserves the Vue-owned form values",
  "organization creation rejects required whitespace and preserves submitted values",
  "organization creation formats persistence changeset errors",
  "admin can view organization detail with no members",
  "admin can issue the first product API service credential",
  "admin can invite a new user and invitation email is delivered",
  "admin can grant an existing durable user directly",
  "invite validation preserves all Vue-owned form values",
  "invite errors preserve submitted values and exact messages",
  "unknown invitation roles preserve the existing member fallback",
  "missing organization flashes and redirects to the organization list",
  "admin can inspect dashboard runtime invalidation decisions",
  "admin can filter durable runtime invalidation decisions by impact metadata",
  "admin deep links render selected decision detail outside filtered results",
  "admin runtime diagnostics show an empty decision state",
  "runtime filter events normalize string values and keep the URL canonical",
  "missing selected decisions remain an explicit server-owned state",
]

const declaredScenarios = [...broadTest.matchAll(/^    test "([^"]+)"/gm)].map(
  ([, scenario]) => scenario,
)

assert.deepEqual(declaredScenarios, existingScenarios)

for (const scenario of existingScenarios) {
  assert.equal(
    broadTest.match(new RegExp(`test "${scenario.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}"`, "g"))
      ?.length,
    1,
    `${scenario} remains one-for-one in admin_live_test.exs`,
  )
}

assert.ok(
  (broadTest.match(/^\s+(?:assert|refute)(?:\s|\()/gm)?.length ?? 0) >= 146,
  "the broad test retains every pre-migration assert/refute site",
)

const organizationManagement = sourceSlice(
  broadTest,
  '  describe "organization management" do',
  '\n  describe "invitation" do',
  "organization management test section",
)

assert.equal(organizationManagement.match(/^    test "/gm)?.length, 8)

const emptyScenario = sourceSlice(
  broadTest,
  '    test "organization list shows empty state when no orgs exist"',
  '\n    test "admin can create an organization"',
  "empty organization list scenario",
)

assert.match(emptyScenario, /id: "admin-organization-list-page-component"/)
assert.match(emptyScenario, /refute has_element\?\(view, "#admin-organization-list-component"\)/)
assert.match(emptyScenario, /vue\.component == "AdminOrganizationListPage"/)
assert.match(emptyScenario, /vue\.ssr == false/)
assert.match(emptyScenario, /vue\.props == Jason\.decode!\(Jason\.encode!\(vue\.props\)\)/)
assert.match(emptyScenario, /"No organizations yet"/)
assert.match(emptyScenario, /vue\.props\["presentation"\]\["card"\] == nil/)
assert.match(
  emptyScenario,
  /refute Jason\.encode!\(vue\.props\["presentation"\]\) =~ "admin-organization-list-component"/,
)

const creationScenario = sourceSlice(
  broadTest,
  '    test "admin can create an organization"',
  '\n    test "organization validation preserves the Vue-owned form values"',
  "organization creation scenario",
)

assert.match(creationScenario, /assert redirect_path == ~p"\/admin\/organizations"/)
assert.match(creationScenario, /"Organization created successfully\."/)
assert.match(creationScenario, /vue\.component == "AdminOrganizationListPage"/)
assert.match(
  creationScenario,
  /vue\.props\["presentation"\]\["card"\]\["child"\]\["attrs"\]\["id"\]/,
)
assert.match(creationScenario, /vue\.props\["presentation"\]\["card"\]\["rows"\] == \[/)
assert.match(creationScenario, /"display_name" => "Test Org"/)
assert.match(creationScenario, /"slug" => "test-org"/)

console.log("admin_organization_list_page_test passed")
