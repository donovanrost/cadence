import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const scenarioLedger = [
  "the complete organization-home page is one non-SSR LiveVue parent with one presentation prop",
  "Phoenix owns organization identity, counts, recent ordering and limit, status derivation, and routes",
  "the page root, header, stats, recent card, empty state, and row visual contracts stay exact",
  "OrganizationHome directly composes immutable OrganizationStats and RecentMissions children",
  "RecentMissions continues composing the StatusBadge compatibility boundary",
  "all missions, new mission, and mission-detail links retain Phoenix redirect navigation semantics",
  "raw attrs preserve HEEx nil, false, true, string, and number behavior",
  "the five pre-migration LiveView scenarios remain present one-for-one",
  "the authenticated organization route and sidebar LiveSession remain unchanged",
  "the newly migrated global sidebar remains outside the owned slice",
]

assert.equal(process.versions.node, "24.16.0", "organization-home contracts use pinned Node 24.16.0")
assert.equal(scenarioLedger.length, 10)

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/OrganizationHome.vue")
const statsPath = resolve(__dirname, "../vue/OrganizationStats.vue")
const recentMissionsPath = resolve(__dirname, "../vue/RecentMissions.vue")
const liveViewPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/organization_home_live.ex",
)
const liveViewTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/organization_home_live_test.exs",
)
const routerPath = resolve(__dirname, "../../lib/cadence_web/router.ex")

const [
  componentSource,
  statsSource,
  recentMissionsSource,
  liveViewSource,
  liveViewTestSource,
  routerSource,
] = await Promise.all([
  readFile(componentPath, "utf8"),
  readFile(statsPath, "utf8"),
  readFile(recentMissionsPath, "utf8"),
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
  const voidElements = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta"])
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

for (const [label, source, expectedHash] of [
  ["OrganizationStats.vue", statsSource, "99e4693d18ba7d2b32301bfbc7a09c5b52c83d12f26f9fa344ed5a7855b89771"],
  ["RecentMissions.vue", recentMissionsSource, "99872dcbdecee4489aedccd3996d5accb521935e9b9d10fd25bc33d2eda46584"],
]) {
  assert.equal(
    createHash("sha256").update(source).digest("hex"),
    expectedHash,
    `${label} remains byte-for-byte immutable`,
  )
}

const script = componentSource.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = componentSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "OrganizationHome.vue must have a TypeScript script setup block")
assert.ok(template, "OrganizationHome.vue must have a template block")
assertBalancedTemplate(template)

assert.match(script, /import OrganizationStats from "\.\/OrganizationStats\.vue"/)
assert.match(script, /import RecentMissions from "\.\/RecentMissions\.vue"/)
assert.match(script, /defineProps<\{presentation: Presentation\}>\(\)/)
assert.match(template, /<OrganizationStats v-bind="props\.presentation\.stats" \/>/)
assert.match(template, /<RecentMissions v-else :rows="props\.presentation\.recent_missions\.rows" \/>/)
assert.equal(template.match(/<OrganizationStats/g)?.length, 1)
assert.equal(template.match(/<RecentMissions/g)?.length, 1)

for (const binding of [
  "props.presentation.root.attrs",
  "props.presentation.header.attrs",
  "props.presentation.header.title.attrs",
  "props.presentation.header.subtitle.attrs",
  "props.presentation.recent_missions.card.attrs",
  "props.presentation.recent_missions.body.attrs",
  "props.presentation.recent_missions.header.attrs",
  "props.presentation.recent_missions.header.all_missions.attrs",
  "props.presentation.recent_missions.empty_state.container.attrs",
  "props.presentation.recent_missions.empty_state.root.attrs",
  "props.presentation.recent_missions.empty_state.action.attrs",
]) {
  assert.ok(template.includes(`v-bind="${binding}"`), `${binding} stays DTO-owned`)
}

assert.match(template, /v-if="props\.presentation\.recent_missions\.empty_state"/)
assert.doesNotMatch(
  componentSource,
  /\/missions|data-phx-link|All missions|New Mission|No missions yet|Recent Missions|Jump into a mission|space-y-6|card bg-base-200/,
)
assert.doesNotMatch(componentSource, /sort\(|\.sort|slice\(|\.slice|status_label\s*=|spacecraft_count\s*=/)
assert.doesNotMatch(componentSource, /v-html|<\.vue|v-component=/)

assert.match(recentMissionsSource, /import StatusBadge from "\.\/StatusBadge\.vue"/)
assert.match(recentMissionsSource, /<StatusBadge :status="row\.status" :label="row\.status_label" \/>/)
assert.match(recentMissionsSource, /id="organization-recent-missions-list"/)
assert.match(recentMissionsSource, /class="mt-5 divide-y divide-base-300"/)
assert.match(recentMissionsSource, /class="py-3"/)
assert.match(recentMissionsSource, /data-phx-link="redirect"/)
assert.match(recentMissionsSource, /data-phx-link-state="push"/)
assert.match(recentMissionsSource, /class="flex items-center justify-between gap-4 hover:text-primary"/)

for (const id of [
  "organization-stats",
  "organization-stat-missions",
  "organization-stat-spacecraft",
  "organization-stat-members",
]) {
  assert.ok(statsSource.includes(`id="${id}"`), `${id} remains in the immutable stats child`)
}

for (const label of ["Missions", "Spacecraft", "Members"]) {
  assert.ok(statsSource.includes(`>${label}</p>`), `${label} remains in the immutable stats child`)
}

const renderSource = sourceSlice(
  liveViewSource,
  "  def render(assigns) do",
  "  @doc false",
  "OrganizationHomeLive render boundary",
)

assert.equal(renderSource.match(/<\.vue/g)?.length, 1)
assert.match(renderSource, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(renderSource, /id="organization-home-component"/)
assert.match(renderSource, /v-component="OrganizationHome"/)
assert.match(renderSource, /presentation=\{@presentation\}/)
assert.match(renderSource, /v-ssr=\{false\}/)
assert.doesNotMatch(renderSource, /<\.page_header|<\.card|<\.section_header|<\.empty_state|<\.button/)
assert.doesNotMatch(renderSource, /OrganizationStats|RecentMissions/)

const presentationSource = sourceSlice(
  liveViewSource,
  "  defp presentation_dto(org, summary) do",
  "  defp load_summary(organization_id) do",
  "organization-home presentation DTO",
)

for (const text of [
  "Recent Missions",
  "Jump into a mission",
  "All missions",
  "No missions yet",
  "Create your first mission to get started.",
  "New Mission",
]) {
  assert.ok(presentationSource.includes(`"${text}"`), `${text} stays Phoenix-owned`)
}

for (const className of [
  "space-y-6",
  "border-b border-primary/20 pb-4",
  "mt-2 text-2xl font-bold text-base-content tracking-tight",
  "mt-1 max-w-3xl text-sm text-base-content/70",
  "card bg-base-200 border border-base-300",
  "card-body p-6",
  "flex items-start justify-between gap-4",
  "hud-label mb-2",
  "text-lg font-semibold",
  "flex flex-wrap items-center justify-end gap-2",
  "btn btn-ghost btn-sm",
  "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center",
  "hero-rocket-launch mx-auto h-10 w-10 text-base-content/30 block",
  "btn btn-primary btn-sm",
]) {
  assert.ok(liveViewSource.includes(`"${className}"`), `${className} stays Phoenix-owned`)
}

for (const route of [
  '~p"/missions"',
  '~p"/missions/new"',
  '~p"/missions/#{row.mission.mission_id}"',
]) {
  assert.ok(liveViewSource.includes(route), `${route} remains server-verified`)
}

assert.match(liveViewSource, /"data-phx-link" => "redirect"/)
assert.match(liveViewSource, /"data-phx-link-state" => "push"/)
assert.match(liveViewSource, /Cadence\.Missions\.list_missions\(organization_id\)/)
assert.match(liveViewSource, /Cadence\.Accounts\.list_organization_members\(organization_id\)/)
assert.match(liveViewSource, /Cadence\.SpacecraftStore\.list_spacecraft\(organization_id, mission\.mission_id\)/)
assert.match(liveViewSource, /Enum\.take\(mission_summaries, @recent_mission_limit\)/)
assert.match(liveViewSource, /@recent_mission_limit 3/)
assert.match(liveViewSource, /Enum\.all\?\(spacecraft, & &1\.scid\)/)

const rawAttrsSource = sourceSlice(
  liveViewSource,
  "  @doc false\n  def presentation_attrs(attrs) when is_map(attrs) do",
  "  defp presentation_dto(org, summary) do",
  "raw attribute semantics",
)

assert.match(rawAttrsSource, /value in \[nil, false\]/)
assert.match(rawAttrsSource, /\{name, true\}, rendered/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, ""\)/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, to_string\(value\)\)/)

for (const scenario of [
  'test "renders org display_name and slug"',
  'test "sidebar highlights the Home nav item"',
  'test "shows the current mission count and link to /missions"',
  'test "lists recent missions with status badges"',
  'test "active admin mode redirects to /admin even from /"',
]) {
  assert.ok(liveViewTestSource.includes(scenario), `${scenario} remains one-for-one`)
}

assert.match(liveViewTestSource, /LiveVue\.Test\.get_vue\(view, id: "organization-home-component"\)/)
assert.match(liveViewTestSource, /Map\.keys\(vue\.props\) == \["presentation"\]/)
assert.match(liveViewTestSource, /Jason\.decode!\(Jason\.encode!\(presentation\)\)/)
assert.match(liveViewTestSource, /values|"nil" => nil/)
assert.match(liveViewTestSource, /"false" => false/)
assert.match(liveViewTestSource, /"true" => true/)
assert.match(liveViewTestSource, /"number" => 7/)

assert.match(
  routerSource,
  /scope "\/", CadenceWeb do\n    pipe_through \[:browser, :require_authenticated_scope\]/,
)

const organizationSession = sourceSlice(
  routerSource,
  "    live_session :organization,",
  "    live_session :provider_accounts,",
  "organization LiveSession",
)

assert.match(organizationSession, /CadenceWeb\.OrganizationAuth, :require_organization_scope/)
assert.match(organizationSession, /CadenceWeb\.UserAuth, :attach_user_menu/)
assert.match(organizationSession, /layout: \{CadenceWeb\.Layouts, :sidebar\}/)
assert.match(organizationSession, /live "\/", OrganizationHomeLive, :show/)
assert.doesNotMatch(organizationSession, /require_organization_admin|require_platform_admin/)
