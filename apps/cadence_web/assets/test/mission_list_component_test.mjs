import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const scenarioLedger = [
  "one non-SSR MissionList host owns the complete page boundary",
  "Phoenix retains mission loading, ordering, counts, status derivation, branch choice, and routes",
  "MissionList directly composes the byte-pinned MissionTable child",
  "the DTO binds the exact header, empty-state, card, row, class, ID, and copy contracts",
  "both New Mission anchors receive server-rendered redirect navigation attrs",
  "the three existing LiveView scenarios remain one-for-one at the root DTO boundary",
  "raw attrs retain HEEx nil, false, true, string, and number semantics",
  "the authenticated organization scope, LiveSession mounts, and sidebar layout remain unchanged",
]

assert.equal(process.versions.node, "24.16.0", "Mission List contracts use pinned Node 24.16.0")
assert.equal(scenarioLedger.length, 8)

const __dirname = dirname(fileURLToPath(import.meta.url))
const paths = {
  component: resolve(__dirname, "../vue/MissionList.vue"),
  missionTable: resolve(__dirname, "../vue/MissionTable.vue"),
  statusBadge: resolve(__dirname, "../vue/StatusBadge.vue"),
  liveView: resolve(__dirname, "../../lib/cadence_web/live/mission_list_live.ex"),
  presentation: resolve(
    __dirname,
    "../../lib/cadence_web/live/mission_list_live/presentation.ex",
  ),
  router: resolve(__dirname, "../../lib/cadence_web/router.ex"),
  liveViewTest: resolve(
    __dirname,
    "../../test/cadence_web/live/mission_list_live_test.exs",
  ),
}

const [component, missionTable, statusBadge, liveView, presentation, router, liveViewTest] =
  await Promise.all(Object.values(paths).map((path) => readFile(path, "utf8")))

const sha256 = (source) => createHash("sha256").update(source).digest("hex")

assert.equal(
  sha256(missionTable),
  "6589381280b0a77895a3a8beaaa6bbad01b247ce91f136624af7fefab64d7a6f",
  "MissionTable.vue remains byte-identical to the frozen source",
)
assert.equal(
  sha256(statusBadge),
  "44d9a452683390afdf9cc8d11db414d45f826a7ec5ba737c01b68f2c418c3888",
  "StatusBadge.vue remains byte-identical to the frozen source",
)

const script = component.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = component.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "MissionList.vue keeps an auditable TypeScript setup block")
assert.ok(template, "MissionList.vue keeps an auditable template block")

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

  for (const match of source.matchAll(/<\/?([a-z][\w-]*)(?:\s[^<>]*?)?>/gs)) {
    const token = match[0]
    const name = match[1]

    if (token.startsWith("</")) {
      assert.equal(stack.pop(), name, `${name} closes the current SFC element`)
    } else if (!token.endsWith("/>") && !voidElements.has(name)) {
      stack.push(name)
    }
  }

  assert.deepEqual(stack, [], "MissionList.vue template tags are balanced")
}

assertBalancedTemplate(template)

assert.match(script, /^import MissionTable from "\.\/MissionTable\.vue"$/m)
assert.equal(script.match(/import .*MissionTable\.vue/g)?.length, 1)
assert.match(script, /defineProps<\{presentation: MissionListPresentation\}>\(\)/)
assert.doesNotMatch(script, /StatusBadge|computed|ref\(|watch\(|fetch\(|useRoute|router/)

const exactBindings = [
  ':class="presentation.root_class"',
  ':class="presentation.header.class"',
  ':class="presentation.header.content_class"',
  ':class="presentation.header.eyebrow.class"',
  "{{ presentation.header.eyebrow.text }}",
  ':class="presentation.header.title.class"',
  "{{ presentation.header.title.text }}",
  ':class="presentation.header.title.suffix.class"',
  "{{ presentation.header.title.suffix.text }}",
  ':class="presentation.header.actions_class"',
  'v-bind="presentation.header.action.attrs"',
  ':class="presentation.header.action.class"',
  ':class="presentation.header.action.icon_class"',
  "{{ presentation.header.action.label }}",
  'v-if="presentation.empty_state.visible"',
  ':id="presentation.empty_state.id"',
  ':class="presentation.empty_state.class"',
  ':class="presentation.empty_state.icon_class"',
  ':class="presentation.empty_state.title.class"',
  "{{ presentation.empty_state.title.text }}",
  ':class="presentation.empty_state.description.class"',
  "{{ presentation.empty_state.description.text }}",
  ':class="presentation.empty_state.action_container_class"',
  'v-bind="presentation.empty_state.action.attrs"',
  ':class="presentation.empty_state.action.class"',
  ':class="presentation.empty_state.action.icon_class"',
  "{{ presentation.empty_state.action.label }}",
  'v-else-if="presentation.card.visible"',
  ':class="presentation.card.class"',
  ':class="presentation.card.body_class"',
  '<MissionTable :rows="presentation.card.rows" />',
]

for (const binding of exactBindings) {
  assert.ok(template.includes(binding), `MissionList.vue preserves ${binding}`)
}

assert.equal(template.match(/<MissionTable\b/g)?.length, 1)
assert.equal(template.match(/<a\b/g)?.length, 2)
assert.equal(template.match(/v-bind="presentation\..*\.action\.attrs"/g)?.length, 2)
assert.doesNotMatch(component, /\/missions(?:\/new)?|data-phx-link|data-phx-link-state/)

assert.equal(liveView.match(/<\.vue\b/g)?.length, 1)
assert.match(liveView, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(liveView, /id="mission-list-component"/)
assert.match(liveView, /v-component="MissionList"/)
assert.match(liveView, /presentation=\{@mission_list_presentation\}/)
assert.match(liveView, /v-ssr=\{false\}/)
assert.doesNotMatch(liveView, /mission-list-table-component|v-component="MissionTable"/)

for (const authority of [
  "Cadence.Missions.list_missions()",
  "Cadence.SpacecraftStore.list_spacecraft(organization_id, mission.mission_id)",
  "Map.put(mission_status(spacecraft), :mission, mission)",
  "Enum.all?(spacecraft, & &1.scid)",
  "Presentation.build(mission_rows)",
]) {
  assert.ok(liveView.includes(authority), `Phoenix retains ${authority}`)
}

assert.match(presentation, /new_mission_attrs = navigate_attrs\(~p"\/missions\/new"\)/)
assert.match(presentation, /href: ~p"\/missions\/#\{row\.mission\.mission_id\}"/)
assert.match(presentation, /visible: rows == \[\]/)
assert.match(presentation, /visible: rows != \[\]/)
assert.match(presentation, /text: "#\{length\(rows\)\} configured"/)
assert.match(presentation, /\{_name, value\}, rendered when value in \[nil, false\]/)
assert.match(presentation, /\{name, true\}, rendered/)
assert.match(presentation, /Map\.put\(rendered, name, ""\)/)
assert.match(presentation, /Map\.put\(rendered, name, to_string\(value\)\)/)

const authenticatedScopeStart = router.indexOf(
  '  scope "/", CadenceWeb do\n    pipe_through [:browser, :require_authenticated_scope]',
)
const providerAccountsStart = router.indexOf("\n    live_session :provider_accounts,", authenticatedScopeStart)

assert.ok(authenticatedScopeStart >= 0, "authenticated organization router scope remains present")
assert.ok(providerAccountsStart > authenticatedScopeStart, "organization LiveSession remains auditable")

const organizationRouterLedger = router.slice(authenticatedScopeStart, providerAccountsStart)

assert.match(organizationRouterLedger, /live_session :organization,/)
assert.match(
  organizationRouterLedger,
  /\{CadenceWeb\.OrganizationAuth, :require_organization_scope\}/,
)
assert.match(organizationRouterLedger, /\{CadenceWeb\.UserAuth, :attach_user_menu\}/)
assert.match(organizationRouterLedger, /layout: \{CadenceWeb\.Layouts, :sidebar\} do/)
assert.match(organizationRouterLedger, /^      live "\/missions", MissionListLive, :index$/m)
assert.equal(router.match(/live "\/missions", MissionListLive, :index/g)?.length, 1)

const existingScenarios = [
  "renders empty state when there are no missions",
  "renders missions through the Vue table host and JSON-safe row props",
  "shows only missions belonging to the current organization",
]

assert.equal(liveViewTest.match(/^    test "/gm)?.length, existingScenarios.length)

for (const scenario of existingScenarios) {
  assert.ok(liveViewTest.includes(`test "${scenario}"`), `${scenario} remains one-for-one`)
}

assert.equal(liveViewTest.match(/id: "mission-list-component"/g)?.length, 3)
assert.match(liveViewTest, /assert vue\.ssr == false/)
assert.match(liveViewTest, /assert Map\.keys\(vue\.props\) == \["presentation"\]/)
assert.match(liveViewTest, /assert vue\.props == Jason\.decode!\(Jason\.encode!\(vue\.props\)\)/)
assert.match(liveViewTest, /vue\.props\["presentation"\]\["empty_state"\]\["id"\]/)
assert.match(liveViewTest, /vue\.props\["presentation"\]\["card"\]\["rows"\]/)

console.log("mission_list_component_test passed")
