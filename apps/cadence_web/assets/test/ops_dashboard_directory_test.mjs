import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const scenarioLedger = [
  "the star control uses one wrapper-free CadenceToggle around the existing button",
  "the server row remains the only source of pressed and disabled state",
  "each update request emits the exact Phoenix event and row.star.payload once",
  "the button ID type disabled title classes icon aria label and focus node stay exact",
  "the directory row identity lifecycle metadata and dashboard navigation stay exact",
  "every non-star component contract remains byte-for-byte unchanged",
  "Phoenix retains user scope persistence reload behavior and the exact star DTO",
  "the LiveVue host retains the same stream prop and toggle_dashboard_star bridge",
  "the focused star and archived ExUnit scenarios stay byte-pinned",
  "the route remains in the authenticated current-scope Ops live session",
  "Reka UI remains locked to the reviewed Toggle export and implementation version",
]

assert.equal(
  process.versions.node,
  "24.16.0",
  "Ops Dashboard Directory contracts use pinned Node 24.16.0",
)
assert.equal(scenarioLedger.length, 11)

const __dirname = dirname(fileURLToPath(import.meta.url))
const paths = {
  component: resolve(__dirname, "../vue/OpsDashboardDirectory.vue"),
  liveView: resolve(__dirname, "../../lib/cadence_web/live/ops_dashboard_list_live.ex"),
  liveViewTest: resolve(
    __dirname,
    "../../test/cadence_web/live/ops_dashboard_directory_live_test.exs",
  ),
  router: resolve(__dirname, "../../lib/cadence_web/router.ex"),
  packageLock: resolve(__dirname, "../../package-lock.json"),
}

const [source, liveViewSource, liveViewTestSource, routerSource, packageLockSource] =
  await Promise.all(Object.values(paths).map((path) => readFile(path, "utf8")))

const sourceSlice = (sourceText, start, end, label) => {
  const startIndex = sourceText.indexOf(start)
  const endIndex = sourceText.indexOf(end, startIndex + start.length)

  assert.ok(startIndex >= 0 && endIndex > startIndex, `${label} must remain source-auditable`)
  return sourceText.slice(startIndex, endIndex)
}

const inclusiveSourceSlice = (sourceText, start, end, label) => {
  const slice = sourceSlice(sourceText, start, end, label)
  return `${slice}${end}`
}

const sha256 = (value) => createHash("sha256").update(value).digest("hex")

const script = source.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "OpsDashboardDirectory.vue keeps an auditable TypeScript setup block")
assert.ok(template, "OpsDashboardDirectory.vue keeps an auditable template block")
assert.match(script, /^import CadenceToggle from "\.\/ui\/reka\/CadenceToggle\.vue"$/m)
assert.doesNotMatch(script, /from "reka-ui"/)
assert.equal(template.match(/<CadenceToggle\b/g)?.length, 1)
assert.equal(template.match(/<\/CadenceToggle>/g)?.length, 1)
assert.doesNotMatch(source, /ToggleRoot|ToggleGroup/)

const directoryRow = sourceSlice(
  template,
  '        <article\n          v-for="row in dashboard_directory"',
  '        </article>',
  "dashboard directory row",
)
const toggleMarkup = inclusiveSourceSlice(
  source,
  "            <CadenceToggle\n",
  "            </CadenceToggle>",
  "dashboard star CadenceToggle",
)
const buttonMarkup = inclusiveSourceSlice(
  toggleMarkup,
  "              <button\n",
  "              </button>",
  "dashboard star button",
)

assert.match(directoryRow, /:id="row\.__dom_id"/)
assert.match(directoryRow, /:key="row\.id"/)
assert.match(directoryRow, /:data-dashboard-directory-id="row\.dashboard_id"/)
assert.match(directoryRow, /:data-dashboard-directory-lifecycle="row\.lifecycle\.state"/)
assert.match(directoryRow, /:data-dashboard-directory-starred="row\.star\.aria_pressed"/)
assert.match(
  directoryRow,
  /v-if="row\.open"[\s\S]*:id="row\.open\.id"[\s\S]*:href="row\.open\.href"[\s\S]*data-phx-link="redirect"[\s\S]*data-phx-link-state="push"/,
)
assert.equal(toggleMarkup.match(/<button\b/g)?.length, 1)
assert.match(
  toggleMarkup,
  /<CadenceToggle\n\s+:pressed="row\.star\.aria_pressed === 'true'"\n\s+:disabled="row\.star\.disabled"\n\s+@request-change="toggleDashboardStar\(row\)"/,
)
assert.equal(toggleMarkup.match(/@request-change=/g)?.length, 1)
const pressedBinding = toggleMarkup.match(/:pressed="([^"]+)"/)?.[1]
assert.ok(pressedBinding, "the server aria-pressed conversion remains executable")

for (const [ariaPressed, expectedPressed] of [["false", false], ["true", true]]) {
  assert.equal(
    vm.runInNewContext(pressedBinding, {
      row: {star: {aria_pressed: ariaPressed}, starred: !expectedPressed},
    }),
    expectedPressed,
    "CadenceToggle pressed state follows the server string rather than a parallel row boolean",
  )
}
assert.equal(
  buttonMarkup,
  `              <button
                :id="row.star.id"
                type="button"
                :aria-label="row.star.aria_label"
                :aria-pressed="row.star.aria_pressed"
                :disabled="row.star.disabled"
                :title="row.star.title"
                :class="['btn btn-ghost btn-xs shrink-0', row.starred && 'text-warning']"
              >
                <span :class="[row.star.icon, 'h-4 w-4']" aria-hidden="true"></span>
              </button>`,
  "CadenceToggle preserves the exact public button and focus node",
)
assert.doesNotMatch(
  toggleMarkup,
  /@click|@update:model-value|v-model|\bname=|<input|<ToggleGroup|\bas-child\b/,
)
assert.doesNotMatch(source, /\bv-model(?::model-value)?=/)
assert.doesNotMatch(script, /row\.starred\s*=|row\.star\s*=|starred\.value\s*=/)
assert.doesNotMatch(
  script,
  /const\s+\w*(?:star|toggle)\w*\s*=\s*(?:ref|reactive|computed)\s*\(/i,
)

const originalButtonMarkup = `            <button
              :id="row.star.id"
              type="button"
              :aria-label="row.star.aria_label"
              :aria-pressed="row.star.aria_pressed"
              :disabled="row.star.disabled"
              :title="row.star.title"
              :class="['btn btn-ghost btn-xs shrink-0', row.starred && 'text-warning']"
              @click="toggleStar(row)"
            >
              <span :class="[row.star.icon, 'h-4 w-4']" aria-hidden="true"></span>
            </button>`
const normalizedComponent = source
  .replace('import CadenceToggle from "./ui/reka/CadenceToggle.vue"\n', "")
  .replace("const toggleDashboardStar = (row: DirectoryRow) => {", "const toggleStar = (row: DirectoryRow) => {")
  .replace(toggleMarkup, originalButtonMarkup)

assert.equal(
  sha256(normalizedComponent),
  "cbe249460034770ae9960d859566a015ffc061c47d4cb3164bec17b3b411e099",
  "only the reviewed import handler name and star-button wrapper differ from the parent",
)

const toggleHandler = sourceSlice(
  script,
  "const toggleDashboardStar = (row: DirectoryRow) => {",
  "\n\nconst restoreDashboard",
  "dashboard star emitter",
)

assert.equal(toggleHandler.match(/\bemit\(/g)?.length, 1)
assert.match(toggleHandler, /emit\("toggle_dashboard_star", row\.star\.payload\)/)
assert.doesNotMatch(toggleHandler, /if\s*\(|return|row\.starred\s*=|row\.star\s*=/)

const emissions = []
const behaviorContext = vm.createContext({
  emit: (...args) => emissions.push(args),
})
const executableToggleHandler = toggleHandler.replace("(row: DirectoryRow)", "(row)")

vm.runInContext(
  `${executableToggleHandler}\nglobalThis.toggleDashboardStar = toggleDashboardStar`,
  behaviorContext,
  {filename: paths.component},
)

for (const starred of [false, true]) {
  const payload = Object.freeze({"dashboard-id": "dashboard-server-1", starred: String(!starred)})
  const row = Object.freeze({
    starred,
    star: Object.freeze({payload}),
  })
  const emissionCount = emissions.length

  behaviorContext.toggleDashboardStar(row)

  assert.equal(emissions.length, emissionCount + 1, "one update emits exactly once")
  assert.equal(row.starred, starred, "the client never mutates server star state")
  assert.equal(emissions.at(-1)[0], "toggle_dashboard_star")
  assert.strictEqual(
    emissions.at(-1)[1],
    payload,
    "the exact server-authored row.star.payload is forwarded",
  )
}

const liveViewToggle = sourceSlice(
  liveViewSource,
  '  def handle_event("toggle_dashboard_star", params, socket) do',
  '\n  def handle_event("restore_dashboard"',
  "Phoenix star handler",
)
const liveViewHost = sourceSlice(
  liveViewSource,
  "  @impl true\n  def render(assigns) do",
  "\n  defp reload_directory",
  "LiveVue directory host",
)
const liveViewDirectoryEntry = sourceSlice(
  liveViewSource,
  "  defp directory_entry(summary, preference_by_dashboard, mission_id, dashboard_author?) do",
  "\n  defp directory_page_dto",
  "Phoenix directory row DTO",
)
const liveViewStarDto = sourceSlice(
  liveViewSource,
  "  defp dashboard_star_dto(summary, starred?) do",
  "\n  defp dashboard_restore_dto",
  "Phoenix star DTO",
)
const liveViewStarContract = [
  liveViewToggle,
  liveViewHost,
  liveViewDirectoryEntry,
  liveViewStarDto,
].join("\n-- pinned server star slice --\n")

assert.equal(
  sha256(liveViewStarContract),
  "aa3d4fc4b0a5c34ad092191ce944e39ea891b1fb1c8db6d137f694c5862cf66d",
  "the read-only Phoenix star contract remains byte-pinned",
)
assert.match(liveViewToggle, /dashboard_id = params\["dashboard-id"\]/)
assert.match(liveViewToggle, /starred = params\["starred"\] == "true"/)
assert.match(liveViewToggle, /%\{current_scope: scope, current_mission: mission\} = socket\.assigns/)
assert.match(liveViewToggle, /current_user_id\(scope\)/)
assert.match(liveViewToggle, /Cadence\.Dashboards\.set_dashboard_starred\(/)
assert.match(
  liveViewToggle,
  /scope\.organization_id,[\s\S]*mission\.mission_id,[\s\S]*user_id,[\s\S]*dashboard_id,[\s\S]*starred/,
)
assert.match(liveViewToggle, /\{:noreply, reload_directory\(socket\)\}/)
assert.match(liveViewHost, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(liveViewHost, /v-component="OpsDashboardDirectory"/)
assert.match(liveViewHost, /dashboard_directory=\{@streams\.dashboard_directory\}/)
assert.match(
  liveViewHost,
  /v-on:toggle_dashboard_star=\{JS\.push\("toggle_dashboard_star"\)\}/,
)
assert.match(liveViewHost, /v-ssr=\{false\}/)
assert.match(liveViewDirectoryEntry, /starred: starred\?/)
assert.match(liveViewDirectoryEntry, /star: dashboard_star_dto\(summary, starred\?\)/)
assert.match(liveViewStarDto, /"dashboard-id" => summary\.dashboard_id/)
assert.match(liveViewStarDto, /"starred" => to_string\(not starred\?\)/)
assert.match(liveViewStarDto, /aria_label: if\(starred\?, do: "Unstar #\{summary\.name\}", else: "Star #\{summary\.name\}"\)/)
assert.match(liveViewStarDto, /aria_pressed: to_string\(starred\?\)/)
assert.match(liveViewStarDto, /disabled: archived\?/)
assert.match(liveViewStarDto, /title: if\(archived\?, do: "Restore this dashboard before starring it", else: nil\)/)
assert.match(liveViewStarDto, /icon: if\(starred\?, do: "hero-star-solid", else: "hero-star"\)/)

const starExUnit = sourceSlice(
  liveViewTestSource,
  '  test "stars are personal while opening a dashboard promotes it into recent navigation" do',
  '\n  test "archived dashboards have a dedicated filtered view and restore outcome" do',
  "personal star ExUnit scenario",
)
const archivedExUnit = sourceSlice(
  liveViewTestSource,
  '  test "archived dashboards have a dedicated filtered view and restore outcome" do',
  "\n  defp dashboard_directory_vue",
  "archived star ExUnit scenario",
)
const starPropsOracle = sourceSlice(
  liveViewTestSource,
  "  defp star_props(dashboard, starred?, archived?) do",
  "\n  defp default_filters",
  "star DTO ExUnit oracle",
)
const liveViewTestStarContract = [starExUnit, archivedExUnit, starPropsOracle].join(
  "\n-- pinned ExUnit star slice --\n",
)

assert.equal(
  sha256(liveViewTestStarContract),
  "d18d0bbf89ff0c6d82ff7cd8b90c3a080186531a88be1c72f237f82c4237cca7",
  "the read-only focused ExUnit star contracts remain byte-pinned",
)
assert.match(starExUnit, /"payload" => %\{[\s\S]*"dashboard-id" => dashboard\.dashboard_id,[\s\S]*"starred" => "true"/)
assert.match(starExUnit, /"aria_label" => "Star Mission Power"/)
assert.match(starExUnit, /"aria_pressed" => "false"/)
assert.match(
  starExUnit,
  /render_hook\(directory, "toggle_dashboard_star", initial_row\["star"\]\["payload"\]\)/,
)
assert.match(starExUnit, /assert starred_row == active_row\(dashboard, mission, true\)/)
assert.match(starExUnit, /"starred" => "false"/)
assert.match(starExUnit, /"aria_label" => "Unstar Mission Power"/)
assert.match(starExUnit, /"aria_pressed" => "true"/)
assert.match(starExUnit, /second_user_row\["starred"\] == false/)
assert.match(archivedExUnit, /"disabled" => true/)
assert.match(archivedExUnit, /"title" => "Restore this dashboard before starring it"/)
assert.match(starPropsOracle, /"starred" => to_string\(not starred\?\)/)

const authenticatedScope = sourceSlice(
  routerSource,
  '  scope "/", CadenceWeb do\n    pipe_through [:browser, :require_authenticated_scope]',
  '\n  scope "/api", CadenceWeb do',
  "authenticated browser scope",
)
const opsLiveSession = sourceSlice(
  authenticatedScope,
  "    live_session :ops,",
  "\n    live_session :ops_admin,",
  "Ops live session",
)

assert.match(authenticatedScope, /pipe_through \[:browser, :require_authenticated_scope\]/)
assert.match(opsLiveSession, /\{CadenceWeb\.OrganizationAuth, :require_organization_scope\}/)
assert.match(opsLiveSession, /\{CadenceWeb\.MissionAuth, :load_mission\}/)
assert.match(opsLiveSession, /\{CadenceWeb\.UserAuth, :attach_user_menu\}/)
assert.match(opsLiveSession, /\{CadenceWeb\.OpsShellHook, :default\}/)
assert.match(opsLiveSession, /layout: \{CadenceWeb\.Layouts, :ops\}/)
assert.match(
  opsLiveSession,
  /live "\/missions\/:mission_id\/ops\/dashboards",\n\s+OpsDashboardListLive,\n\s+:index/,
)

const packageLock = JSON.parse(packageLockSource)
assert.equal(packageLock.packages["node_modules/reka-ui"].version, "2.10.3")

console.log("ops_dashboard_directory_test passed")
