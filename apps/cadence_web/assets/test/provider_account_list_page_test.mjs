import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const scenarioLedger = [
  "the complete Provider Account List page is one always-present non-SSR LiveVue parent",
  "the parent receives exactly one regular JSON-safe presentation prop plus the native provider_accounts stream",
  "Phoenix owns organization and admin authorization, ProviderAccounts and ProviderCredentials reads, and navigation",
  "Phoenix owns count, empty-state, health, provider, credential-label, ingestion, endpoint, href, and card decisions",
  "the canonical stream_configure and stream calls preserve stream order and historical identity",
  "LiveVue stream extraction supplies provider_accounts separately and injects each historical __dom_id",
  "ProviderAccountListPage directly composes the byte-for-byte immutable ProviderAccountCards child once",
  "the root, header, count, new action, empty state, stream grid, marker, and card wrappers preserve exact DOM contracts",
  "the outer stream wrapper and inner component wrapper derive only from LiveVue's __dom_id",
  "all page and card links retain LiveView redirect and push navigation semantics",
  "credential labels expose status and registry version but never credential refs, backend keys, or secret material",
  "raw attrs preserve HEEx nil, false, true, empty-string, string, and number behavior",
  "new, show, grants, and cursors scenarios in the broad test file remain outside the list-only edit",
  "the authenticated provider_accounts session, mounts, routes, and sidebar layout remain unchanged",
  "router, LiveView, parent, and focused tests use semantic source slices; only immutable ProviderAccountCards.vue is hashed",
]

assert.equal(
  process.versions.node,
  "24.16.0",
  "provider-account-list contracts use pinned Node 24.16.0",
)
assert.equal(scenarioLedger.length, 15)

const __dirname = dirname(fileURLToPath(import.meta.url))
const pagePath = resolve(__dirname, "../vue/ProviderAccountListPage.vue")
const childPath = resolve(__dirname, "../vue/ProviderAccountCards.vue")
const liveViewPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/provider_account_list_live.ex",
)
const liveViewTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/provider_account_live_test.exs",
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

  assert.deepEqual(stack, [], "ProviderAccountListPage.vue template tags are balanced")
}

assert.equal(
  createHash("sha256").update(childSource).digest("hex"),
  "271bfe52301c62a0e00e68d631b0955d1d4e1fe56303ade58d03675dcad70d40",
  "ProviderAccountCards.vue remains byte-for-byte immutable",
)

const script = pageSource.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = pageSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "ProviderAccountListPage.vue has an auditable TypeScript setup block")
assert.ok(template, "ProviderAccountListPage.vue has an auditable template block")
assertBalancedTemplate(template)

assert.match(script, /^import ProviderAccountCards from "\.\/ProviderAccountCards\.vue"$/m)
assert.equal(script.match(/import .*ProviderAccountCards\.vue/g)?.length, 1)
assert.match(
  script,
  /type ProviderAccountCard = InstanceType<typeof ProviderAccountCards>\["\$props"\]\["card"\] & \{/,
)
assert.match(script, /__dom_id: string/)
assert.match(script, /presentation: Presentation/)
assert.match(script, /provider_accounts: ProviderAccountCard\[\]/)
assert.doesNotMatch(script, /computed|ref\(|watch\(|fetch\(|defineEmits|useRoute|router/)

assert.equal(template.match(/<ProviderAccountCards\b/g)?.length, 1)
assert.match(template, /<ProviderAccountCards :card="card" \/>/)
assert.match(template, /v-for="card in props\.provider_accounts"/)
assert.match(template, /:id="card\.__dom_id"/)
assert.match(template, /:key="card\.__dom_id"/)
assert.match(template, /:id="`\$\{card\.__dom_id\}-component`"/)

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
  "props.presentation.header.title.suffix.attrs",
  "props.presentation.header.subtitle.attrs",
  "props.presentation.header.actions.attrs",
  "props.presentation.header.actions.new_account.attrs",
  "props.presentation.header.actions.new_account.icon.attrs",
  "props.presentation.empty_state.attrs",
  "props.presentation.empty_state.icon.attrs",
  "props.presentation.empty_state.title.attrs",
  "props.presentation.empty_state.description.attrs",
  "props.presentation.empty_state.action_container.attrs",
  "props.presentation.empty_state.action.attrs",
  "props.presentation.empty_state.action.icon.attrs",
  "props.presentation.stream.attrs",
  "props.presentation.stream.empty_marker.attrs",
]) {
  assert.ok(template.includes(`v-bind="${binding}"`), `${binding} stays DTO-owned`)
}

assert.match(template, /v-if="props\.presentation\.empty_state"/)
assert.equal(template.match(/<a\b/g)?.length, 3)
assert.doesNotMatch(
  pageSource,
  /\/provider-accounts|Provider Accounts|New Account|No provider accounts|registered|space-y-6|btn btn-primary|data-phx-link/,
)
assert.doesNotMatch(pageSource, /\.sort|\.filter|v-html|<\.vue|v-component=|phx-click/)

for (const childContract of [
  'data-phx-link="redirect"',
  'data-phx-link-state="push"',
  ':href="props.card.href"',
  "{{ props.card.display_name }}",
  "{{ props.card.provider_account_id }}",
  '<StatusBadge :status="props.card.status" :label="props.card.status_label" />',
  "{{ props.card.endpoint }}",
]) {
  assert.ok(childSource.includes(childContract), `${childContract} remains in the immutable child`)
}

const mountSource = sourceSlice(
  liveViewSource,
  "  def mount(_params, _session, socket) do",
  "  @impl true\n  def render(assigns) do",
  "ProviderAccountListLive mount",
)

for (const authority of [
  "scope = socket.assigns.current_scope",
  "ProviderAccounts.list(scope)",
  "version.credential_ref",
  "ProviderCredentials.fetch(",
  "scope.organization_id",
  "provider_account_card(",
  "account_count = length(accounts)",
  "accounts_empty? = accounts == []",
  "assign(:account_versions, versions)",
  "assign(:account_credentials, credentials)",
  "assign(:presentation, page_presentation(account_count, accounts_empty?))",
  "stream_configure(:provider_accounts,",
  'dom_id: &"provider-account-#{&1.id}"',
  "stream(:provider_accounts, card_rows)",
]) {
  assert.ok(mountSource.includes(authority), `Phoenix retains ${authority}`)
}

const renderSource = sourceSlice(
  liveViewSource,
  "  def render(assigns) do",
  "  @doc false",
  "ProviderAccountListLive render boundary",
)

assert.equal(renderSource.match(/<\.vue\b/g)?.length, 1)
assert.match(renderSource, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(renderSource, /id="provider-account-list-page-component"/)
assert.match(renderSource, /v-component="ProviderAccountListPage"/)
assert.match(renderSource, /presentation=\{@presentation\}/)
assert.match(renderSource, /provider_accounts=\{@streams\.provider_accounts\}/)
assert.match(renderSource, /v-ssr=\{false\}/)
assert.match(renderSource, /class="contents"/)
assert.doesNotMatch(renderSource, /<\.page_header|<\.empty_state|ProviderAccountCards|:for=/)

const presentationSource = sourceSlice(
  liveViewSource,
  "  @doc false\n  def presentation_attrs(attrs) when is_map(attrs) do",
  "  defp provider_account_card(account, version, credential) do",
  "Provider Account List presentation DTO",
)

for (const text of [
  "Provider Accounts",
  "Organization-owned ground network control planes. Grant access to missions without copying credentials.",
  "New Account",
  "No provider accounts",
  "Register the simulator or a commercial ground network once, then grant it to the missions that need it.",
  "Register provider account",
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
  "hero-globe-alt mx-auto h-10 w-10 text-base-content/30 block",
  "hud-label mt-3",
  "mt-2 max-w-md mx-auto text-sm text-base-content/70",
  "btn btn-primary btn-sm",
  "hero-plus -ml-0.5 mr-1 h-4 w-4",
  "grid gap-4 xl:grid-cols-2",
  "hidden only:block",
]) {
  assert.ok(presentationSource.includes(`"${className}"`), `${className} stays Phoenix-owned`)
}

for (const id of [
  "provider-accounts-page",
  "new-provider-account-link",
  "provider-accounts",
  "provider-accounts-empty",
]) {
  assert.ok(presentationSource.includes(`"${id}"`), `${id} remains server-authored`)
}

assert.match(presentationSource, /~p"\/provider-accounts\/new"/)
assert.match(presentationSource, /"data-phx-link" => "redirect"/)
assert.match(presentationSource, /"data-phx-link-state" => "push"/)
assert.match(presentationSource, /"phx-update" => "stream"/)
assert.match(presentationSource, /empty_state_presentation\(accounts_empty\?, new_account_path\)/)
assert.match(presentationSource, /defp empty_state_presentation\(false, _new_account_path\), do: nil/)
assert.match(presentationSource, /value in \[nil, false\]/)
assert.match(presentationSource, /\{name, true\}, rendered/)
assert.match(presentationSource, /Map\.put\(rendered, name, ""\)/)
assert.match(presentationSource, /Map\.put\(rendered, name, to_string\(value\)\)/)
assert.doesNotMatch(presentationSource, /provider_credential_ref|backend_key|secret_material/)

const cardSource = sourceSlice(
  liveViewSource,
  "  defp provider_account_card(account, version, credential) do",
  "  defp account_health_status",
  "Provider Account card DTO",
)

for (const decision of [
  "account_health_status(account)",
  "account_health_label(account)",
  "provider_label(version)",
  '"v#{account.active_version}"',
  "credential_label(credential)",
  "ingestion_label(version)",
  "endpoint_summary(version)",
  '~p"/provider-accounts/#{account.provider_account_id}"',
]) {
  assert.ok(cardSource.includes(decision), `${decision} remains server-authored`)
}
assert.doesNotMatch(cardSource, /credential_ref|provider_credential_ref|backend_key|material/)

const credentialLabelSource = sourceSlice(
  liveViewSource,
  '  defp credential_label(nil), do: "Unavailable"',
  "  defp ingestion_label(version)",
  "safe credential label",
)

assert.match(credentialLabelSource, /credential\.status/)
assert.match(credentialLabelSource, /credential\.registry_version/)
assert.doesNotMatch(credentialLabelSource, /credential_ref|provider_credential_ref|backend_key|material/)

const listTestsSource = sourceSlice(
  liveViewTestSource,
  '  test "organization administrators can navigate to the account registry" do',
  '  test "ordinary members are redirected away from Provider Account administration" do',
  "Provider Account List focused tests",
)

for (const assertion of [
  '#provider-account-list-page-component.contents',
  'vue.component == "ProviderAccountListPage"',
  "vue.ssr == false",
  'vue.class == "contents"',
  'Map.keys(vue.props) == ["presentation"]',
  '%{"props" => vue.props, "streams_diff" => vue.streams_diff}',
  '["replace", "/provider_accounts", []]',
  '["upsert", "/provider_accounts/-", card]',
  '"provider-account-provider-account-#{account.provider_account_id}"',
  "credential.provider_credential_ref",
  "credential.backend_key",
  "assert_provider_account_value_has_no_secret_fields(contract)",
  "presentation_attrs",
]) {
  assert.ok(listTestsSource.includes(assertion), `${assertion} stays covered by focused tests`)
}

for (const preservedScenario of [
  'test "ordinary members are redirected away from Provider Account administration"',
  'test "registers an account without rendering secret material fields"',
  'test "validates, rotates, and revokes a stable credential reference"',
  'test "grants and revokes mission access from the account page"',
  'test "shows durable cursor health, inbox backlog, and quarantine counts"',
]) {
  assert.ok(liveViewTestSource.includes(preservedScenario), `${preservedScenario} remains present`)
}

const routerBoundary = sourceSlice(
  routerSource,
  '  scope "/", CadenceWeb do\n    pipe_through [:browser, :require_authenticated_scope]',
  "    live_session :mission,",
  "authenticated Provider Account route boundary",
)

for (const routeContract of [
  "live_session :provider_accounts,",
  "{CadenceWeb.OrganizationAuth, :require_organization_scope}",
  "{CadenceWeb.OrganizationAuth, :require_organization_admin}",
  "{CadenceWeb.UserAuth, :attach_user_menu}",
  "layout: {CadenceWeb.Layouts, :sidebar}",
  'live "/provider-accounts", ProviderAccountListLive, :index',
  'live "/provider-accounts/new", ProviderAccountNewLive, :new',
  'live "/provider-accounts/:provider_account_id", ProviderAccountShowLive, :show',
]) {
  assert.ok(routerBoundary.includes(routeContract), `${routeContract} remains unchanged`)
}

console.log("provider account list page contracts passed")
