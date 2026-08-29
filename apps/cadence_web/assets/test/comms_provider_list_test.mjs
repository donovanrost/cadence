import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {peelCadenceHoverTableRows} from "./hover_table_row_test_support.mjs"

const scenarioLedger = [
  "the complete provider-list page is one non-SSR LiveVue parent with one presentation prop",
  "Phoenix owns provider loading, counts, empty/card selection, status labels, bindings, timestamps, and routes",
  "the page root, breadcrumbs, header, actions, empty state, card, and child host visual contracts stay exact",
  "CommsProviderList directly composes the immutable CommsProviderTable child",
  "the existing child receives every prior row prop without renaming or deriving values in Vue",
  "all breadcrumb, setup, and provider-detail links retain Phoenix redirect navigation semantics",
  "raw attrs preserve HEEx nil, false, true, string, and number behavior",
  "the pre-migration provider-list scenario and its three oracles remain one-for-one",
  "provider fetching and the configured providers LiveView stream remain server-owned",
  "the authenticated comms route, mission mounts, and mission-sidebar layout remain unchanged",
  "router and caller contracts use semantic source slices; only the explicitly immutable child is hashed",
]

assert.equal(process.versions.node, "24.16.0", "provider-list contracts use pinned Node 24.16.0")
assert.equal(scenarioLedger.length, 11)

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/CommsProviderList.vue")
const childPath = resolve(__dirname, "../vue/CommsProviderTable.vue")
const liveViewPath = resolve(__dirname, "../../lib/cadence_web/live/comms_provider_list_live.ex")
const liveViewTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/comms_provider_live_test.exs",
)
const routerPath = resolve(__dirname, "../../lib/cadence_web/router.ex")

const [componentSource, childSource, liveViewSource, liveViewTestSource, routerSource] =
  await Promise.all([
    readFile(componentPath, "utf8"),
    readFile(childPath, "utf8"),
    readFile(liveViewPath, "utf8"),
    readFile(liveViewTestPath, "utf8"),
    readFile(routerPath, "utf8"),
  ])
const preHoverTableRowChildSource = peelCadenceHoverTableRows(
  childSource,
  "CommsProviderTable.vue",
)

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
  const tags = source.matchAll(/<\/?([a-z][\w-]*)(?:\s[^<>]*?)?>/gs)

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
  preHoverTableRowChildSource.match(
    /^import CadenceTableFrame from "\.\/ui\/components\/CadenceTableFrame\.vue"$/gm,
  )?.length,
  1,
  "CommsProviderTable.vue has one CadenceTableFrame import before compatibility peeling",
)
assert.equal(
  preHoverTableRowChildSource.match(/<\/?CadenceTableFrame\b/g)?.length,
  2,
  "CommsProviderTable.vue has one CadenceTableFrame boundary before compatibility peeling",
)

const predecessorChildSource = preHoverTableRowChildSource
  .replace('import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"\n', "")
  .replace(
    '  <CadenceTableFrame id="mission-providers-table">',
    '  <table id="mission-providers-table" class="table">',
  )
  .replace("  </CadenceTableFrame>", "  </table>")

assert.doesNotMatch(
  predecessorChildSource,
  /CadenceTableFrame/,
  "CommsProviderTable.vue predecessor has no residual CadenceTableFrame shell",
)

assert.equal(
  createHash("sha256").update(predecessorChildSource).digest("hex"),
  "16515b3198ae4f3ebafe6ddce55d0e035a393bd029958576d3a5cb921cfda581",
  "CommsProviderTable.vue remains byte-for-byte immutable",
)

const script = componentSource.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = componentSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "CommsProviderList.vue must have a TypeScript script setup block")
assert.ok(template, "CommsProviderList.vue must have a template block")
assertBalancedTemplate(template)

assert.match(script, /import CommsProviderTable from "\.\/CommsProviderTable\.vue"/)
assert.match(script, /defineProps<\{presentation: Presentation\}>\(\)/)
assert.match(template, /<CommsProviderTable :rows="props\.presentation\.card\.rows" \/>/)
assert.equal(template.match(/<CommsProviderTable/g)?.length, 1)

for (const binding of [
  "props.presentation.root.attrs",
  "props.presentation.header.attrs",
  "props.presentation.header.body.attrs",
  "props.presentation.header.content.attrs",
  "props.presentation.header.breadcrumbs.attrs",
  "props.presentation.header.title.attrs",
  "props.presentation.header.title.suffix.attrs",
  "props.presentation.header.subtitle.attrs",
  "props.presentation.header.actions.attrs",
  "props.presentation.header.actions.new_provider.attrs",
  "props.presentation.empty_state.attrs",
  "props.presentation.empty_state.action.attrs",
  "props.presentation.card.attrs",
  "props.presentation.card.body.attrs",
  "props.presentation.card.table_component.attrs",
]) {
  assert.ok(template.includes(`v-bind="${binding}"`), `${binding} stays DTO-owned`)
}

assert.match(template, /v-if="props\.presentation\.empty_state"/)
assert.match(template, /v-else-if="props\.presentation\.card"/)
assert.doesNotMatch(
  componentSource,
  /\/missions|Ground Network Providers|No ground network providers|New Provider|Configure the first provider|space-y-6|btn btn-primary|data-phx-link/,
)
assert.doesNotMatch(componentSource, /sort\(|\.sort|filter\(|\.filter|Calendar|DateTime|v-html/)
assert.doesNotMatch(componentSource, /<\.vue|v-component=|phx-click|phx-change|phx-submit/)

const renderSource = sourceSlice(
  liveViewSource,
  "  def render(assigns) do",
  "  @doc false",
  "CommsProviderListLive render boundary",
)

assert.equal(renderSource.match(/<\.vue/g)?.length, 1)
assert.match(renderSource, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(renderSource, /id="comms-provider-list-component"/)
assert.match(renderSource, /v-component="CommsProviderList"/)
assert.match(renderSource, /presentation=\{@presentation\}/)
assert.match(renderSource, /v-ssr=\{false\}/)
assert.match(renderSource, /class="contents"/)
assert.doesNotMatch(renderSource, /<\.page_header|<\.card|<\.empty_state|<\.button/)
assert.doesNotMatch(renderSource, /CommsProviderTable|provider_table_rows|@streams/)

const mountSource = sourceSlice(
  liveViewSource,
  "  def mount(_params, _session, socket) do",
  "  @impl true\n  def render(assigns) do",
  "provider-list mount boundary",
)

assert.match(
  mountSource,
  /Providers\.list_providers\(scope\.organization_id, mission\.mission_id\)/,
)
assert.match(mountSource, /Enum\.map\(providers, &provider_table_row\(&1, mission\.mission_id\)\)/)
assert.match(mountSource, /assign\(:provider_count, provider_count\)/)
assert.match(mountSource, /assign\(:providers_empty\?, providers_empty\?\)/)
assert.match(mountSource, /assign\(:provider_table_rows, provider_table_rows\)/)
assert.match(mountSource, /assign\(\s*:presentation,/)
assert.ok(
  mountSource.includes(
    'stream_configure(:providers, dom_id: &"mission-provider-#{&1.provider_id}")',
  ),
  "the configured provider stream DOM IDs stay exact",
)
assert.match(mountSource, /stream\(:providers, providers\)/)

const presentationSource = sourceSlice(
  liveViewSource,
  "  defp presentation_dto(mission, provider_count, providers_empty?, rows) do",
  "  defp control_plane_status(provider) do",
  "provider-list presentation DTO",
)

for (const text of [
  "Ground Network Providers",
  "Provider control planes for scheduling, inventory discovery, and delivery profile negotiation.",
  "New Provider",
  "No ground network providers",
  "Connect this mission to a simulator or commercial ground network control plane.",
  "Configure the first provider",
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
  "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center",
  "hud-label",
  "mt-2 max-w-md mx-auto text-sm text-base-content/70",
  "btn btn-primary btn-sm",
  "card bg-base-200 border border-base-300",
  "card-body p-0",
]) {
  assert.ok(presentationSource.includes(`"${className}"`), `${className} stays Phoenix-owned`)
}

for (const route of [
  '~p"/missions/#{mission.mission_id}"',
  '~p"/missions/#{mission.mission_id}/comms"',
  '~p"/missions/#{mission.mission_id}/comms/providers/new"',
]) {
  assert.ok(presentationSource.includes(route), `${route} remains server-verified`)
}

assert.match(presentationSource, /"data-phx-link" => "redirect"/)
assert.match(presentationSource, /"data-phx-link-state" => "push"/)
assert.match(presentationSource, /empty_state_presentation\(providers_empty\?, new_provider_path\)/)
assert.match(presentationSource, /card_presentation\(providers_empty\?, rows\)/)
assert.match(presentationSource, /"rows" => rows/)
assert.match(presentationSource, /"id" => "mission-providers-table-component"/)

for (const serverDecision of [
  "defp control_plane_status(provider)",
  "defp control_plane_label(provider)",
  'defp timestamp_label(nil), do: "Never"',
  "defp account_binding_label(provider)",
  "defp grant_binding_label(provider)",
  "defp provider_table_row(provider, mission_id)",
  "defp provider_type_label(%{provider_type: :simulator})",
]) {
  assert.ok(liveViewSource.includes(serverDecision), `${serverDecision} remains in Phoenix`)
}

const rawAttrsSource = sourceSlice(
  liveViewSource,
  "  @doc false\n  def presentation_attrs(attrs) when is_map(attrs) do",
  "  defp presentation_dto(mission, provider_count, providers_empty?, rows) do",
  "raw attribute semantics",
)

assert.match(rawAttrsSource, /value in \[nil, false\]/)
assert.match(rawAttrsSource, /\{name, true\}, rendered/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, ""\)/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, to_string\(value\)\)/)

assert.ok(
  liveViewTestSource.includes(
    'test "lists mission providers and exposes the mission-scoped setup path"',
  ),
  "the existing provider-list scenario remains one-for-one",
)
assert.match(
  liveViewTestSource,
  /presentation\["root"\]\["attrs"\]\["id"\] == "comms-providers-page"/,
)
assert.match(
  liveViewTestSource,
  /presentation\["header"\]\["actions"\]\["new_provider"\]\["attrs"\]\["id"\]/,
)
assert.match(
  liveViewTestSource,
  /presentation\["empty_state"\]\["title"\]\["text"\] == "No ground network providers"/,
)
assert.match(
  liveViewTestSource,
  /LiveVue\.Test\.get_vue\(view, id: "comms-provider-list-component"\)/,
)
assert.match(liveViewTestSource, /Map\.keys\(vue\.props\) == \["presentation"\]/)
assert.match(liveViewTestSource, /Jason\.decode!\(Jason\.encode!\(presentation\)\)/)
assert.match(liveViewTestSource, /"nil" => nil/)
assert.match(liveViewTestSource, /"false" => false/)
assert.match(liveViewTestSource, /"true" => true/)
assert.match(liveViewTestSource, /"number" => 7/)

assert.match(
  routerSource,
  /scope "\/", CadenceWeb do\n    pipe_through \[:browser, :require_authenticated_scope\]/,
)

const commsSession = sourceSlice(
  routerSource,
  "    live_session :comms,",
  "    live_session :ops_dashboard_author,",
  "comms LiveSession",
)

assert.match(commsSession, /CadenceWeb\.OrganizationAuth, :require_organization_scope/)
assert.match(commsSession, /CadenceWeb\.MissionAuth, :load_mission/)
assert.match(commsSession, /CadenceWeb\.UserAuth, :attach_user_menu/)
assert.match(commsSession, /layout: \{CadenceWeb\.Layouts, :mission_sidebar\}/)
assert.match(
  commsSession,
  /live "\/missions\/:mission_id\/comms\/providers",\s+CommsProviderListLive,\s+:index/,
)
assert.doesNotMatch(commsSession, /require_organization_admin|require_platform_admin/)
