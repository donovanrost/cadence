import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const scenarioLedger = [
  "one always-present non-SSR CatalogArtifactShowPage host owns the complete page",
  "the host exposes exactly one JSON-safe presentation prop and forwards reimport to Phoenix",
  "Phoenix retains authenticated organization and mission scope plus artifact and run queries",
  "Phoenix retains subscription filtering upsert order status formatting routes and uploader identity",
  "every mount and matching PubSub refresh recomputes the complete presentation",
  "CatalogArtifactShowPage directly composes the audited IDREF-repaired CatalogArtifactShow child exactly once",
  "the Vue root header breadcrumbs child wrapper text classes and navigation attrs stay exact",
  "CatalogArtifactShowPage transparently re-emits the unchanged child reimport event",
  "raw attrs preserve HEEx nil false true empty-string string and number behavior",
  "the six existing scenarios and 25 assertion sites remain one-for-one and in order",
  "only the focused parent-host JSON and raw-attribute scenarios are added",
  "the authenticated catalog route LiveSession mounts and mission-sidebar layout stay exact",
  "semantic source slices cover mutable files and only CatalogArtifactShow.vue is hashed",
]

assert.equal(process.versions.node, "24.16.0", "artifact-show contracts use pinned Node 24.16.0")
assert.equal(scenarioLedger.length, 13)

const __dirname = dirname(fileURLToPath(import.meta.url))
const paths = {
  page: resolve(__dirname, "../vue/CatalogArtifactShowPage.vue"),
  child: resolve(__dirname, "../vue/CatalogArtifactShow.vue"),
  liveView: resolve(
    __dirname,
    "../../lib/cadence_web/live/catalog/catalog_artifact_show_live.ex",
  ),
  liveViewTest: resolve(
    __dirname,
    "../../test/cadence_web/live/catalog/catalog_artifact_show_live_test.exs",
  ),
  router: resolve(__dirname, "../../lib/cadence_web/router.ex"),
}

const [page, child, liveView, liveViewTest, router] = await Promise.all(
  Object.values(paths).map((path) => readFile(path, "utf8")),
)

const sourceSlice = (source, start, end, label) => {
  const startIndex = source.indexOf(start)
  const endIndex = source.indexOf(end, startIndex + start.length)

  assert.ok(startIndex >= 0 && endIndex > startIndex, `${label} must remain source-auditable`)
  return source.slice(startIndex, endIndex)
}

const assertionSiteCount = (source) => source.match(/^\s+(?:assert|refute)\b/gm)?.length ?? 0

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

  assert.deepEqual(stack, [], "CatalogArtifactShowPage.vue template tags are balanced")
}

assert.equal(
  createHash("sha256").update(child).digest("hex"),
  "76dd24a2f09333ef871304a3d8de09530f099b6c683df822f1cf2040e227a6fa",
  "CatalogArtifactShow.vue remains the explicitly audited child",
)

const script = page.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = page.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "CatalogArtifactShowPage.vue keeps an auditable TypeScript setup block")
assert.ok(template, "CatalogArtifactShowPage.vue keeps an auditable template block")
assertBalancedTemplate(template)

assert.match(script, /^import CatalogArtifactShow from "\.\/CatalogArtifactShow\.vue"$/m)
assert.equal(script.match(/import .*CatalogArtifactShow\.vue/g)?.length, 1)
assert.match(
  script,
  /type CatalogArtifactShowProps = InstanceType<typeof CatalogArtifactShow>\["\$props"\]/,
)
assert.match(script, /artifact: CatalogArtifactShowProps\["artifact"\]/)
assert.match(script, /runs: CatalogArtifactShowProps\["runs"\]/)
assert.match(script, /defineProps<\{presentation: Presentation\}>\(\)/)
assert.equal(script.match(/defineProps</g)?.length, 1)
assert.match(script, /defineEmits<\{\s*reimport: \[\]\s*\}>\(\)/s)
assert.equal(script.match(/defineEmits</g)?.length, 1)
assert.doesNotMatch(script, /computed|ref\(|watch\(|fetch\(|useRoute|router|sort\(|filter\(/)

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
  "props.presentation.child_wrapper.attrs",
]) {
  assert.ok(template.includes(`v-bind="${binding}"`), `${binding} stays Phoenix-authored`)
}

for (const textBinding of [
  "item.separator.text",
  "item.link.text",
  "item.current.text",
  "props.presentation.header.title.text",
]) {
  assert.ok(template.includes(`{{ ${textBinding} }}`), `${textBinding} stays Phoenix-authored`)
}

assert.equal(template.match(/<CatalogArtifactShow\b/g)?.length, 1)
assert.match(template, /:artifact="props\.presentation\.artifact_show\.artifact"/)
assert.match(template, /:runs="props\.presentation\.artifact_show\.runs"/)
assert.match(template, /@reimport="emit\('reimport'\)"/)
assert.doesNotMatch(
  page,
  /\/missions|catalog-artifact-show-page|catalog-artifact-show-component|data-phx-link/,
)
assert.doesNotMatch(
  page,
  /mission\.yaml|"Catalog"|"space-y-6"|border-primary|text-primary|transition-colors/,
)
assert.doesNotMatch(page, /v-html|<\.vue|v-component=|JS\.push|phx-click/)

assert.match(child, /import CadenceModalMenu from "\.\/ui\/reka\/CadenceModalMenu\.vue"/)
assert.match(child, /import CadenceMenuItem from "\.\/ui\/reka\/CadenceMenuItem\.vue"/)
assert.match(child, /<CadenceModalMenu/)
assert.match(child, /<CadenceMenuItem/)
assert.doesNotMatch(child, /from "reka-ui"|<DropdownMenu/)
assert.match(child, /defineEmits<\{\s*reimport: \[\]\s*\}>\(\)/s)
assert.match(child, /@click="emit\('reimport'\)"/)
assert.match(child, /id="catalog-artifact-show-content" class="space-y-6"/)
assert.match(child, /data-phx-link="redirect"/)
assert.match(child, /data-phx-link-state="push"/)

const mountSource = sourceSlice(
  liveView,
  '  def mount(%{"artifact_id" => artifact_id}, _session, socket) do',
  "  @impl true\n  def handle_info",
  "CatalogArtifactShowLive mount",
)

for (const authority of [
  "socket.assigns.current_mission",
  "socket.assigns.current_scope.organization_id",
  "Catalog.fetch_artifact(organization_id, mission.mission_id, artifact_id)",
  "Events.subscribe_import_runs(mission.mission_id)",
  "Catalog.list_import_runs(organization_id, mission.mission_id, artifact_id: artifact_id)",
  "assign(:page_title, artifact.artifact_name)",
  "assign(:nav_item, :catalog)",
  "assign(:artifact, artifact)",
  "assign_runs(runs)",
  'put_flash(:error, "Artifact not found.")',
  'redirect(to: ~p"/missions/#{mission.mission_id}/catalog")',
]) {
  assert.ok(mountSource.includes(authority), `mount retains ${authority}`)
}

const pubSubSource = sourceSlice(
  liveView,
  "  def handle_info({event, run}, socket)",
  "  defp upsert_run(runs, run) do",
  "Catalog Artifact Show PubSub refresh",
)

for (const event of [
  ":import_run_started",
  ":import_run_updated",
  ":import_run_completed",
  ":import_run_failed",
]) {
  assert.ok(pubSubSource.includes(event), `${event} remains subscribed behavior`)
}

assert.equal(pubSubSource.match(/:import_run_(?:started|updated|completed|failed)/g)?.length, 4)
assert.match(pubSubSource, /run\.artifact_id == socket\.assigns\.artifact\.artifact_id/)
assert.match(
  pubSubSource,
  /assign_runs\(socket, upsert_run\(socket\.assigns\.runs, run\)\)/,
)
assert.match(pubSubSource, /\{:noreply, socket\}/)

const upsertSource = sourceSlice(
  liveView,
  "  defp upsert_run(runs, run) do",
  "  @impl true\n  def handle_event",
  "Catalog Artifact Show run upsert",
)

assert.match(upsertSource, /Enum\.find_index\(runs, &\(&1\.import_run_id == run\.import_run_id\)\)/)
assert.match(upsertSource, /nil -> \[run \| runs\]/)
assert.match(upsertSource, /index -> List\.replace_at\(runs, index, run\)/)

const reimportSource = sourceSlice(
  liveView,
  '  def handle_event("reimport", _params, socket) do',
  "  @impl true\n  def render(assigns) do",
  "Catalog Artifact Show reimport and uploader identity",
)

for (const authority of [
  "socket.assigns.artifact",
  "socket.assigns.current_mission",
  "socket.assigns.current_scope.organization_id",
  "Catalog.start_import_run(",
  "artifact.artifact_id",
  "artifact.format_key",
  "requested_by: uploader_identity(socket)",
  'push_navigate(socket,\n           to: ~p"/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}"',
  'put_flash(socket, :error, "Failed to start import: #{inspect(reason)}")',
  "%{user: %{id: id, email: email}} -> %{user_id: id, email: email}",
  "_ -> %{}",
]) {
  assert.ok(reimportSource.includes(authority), `reimport retains ${authority}`)
}

const renderSource = sourceSlice(
  liveView,
  "  def render(assigns) do",
  "  @doc false\n  def presentation_attrs",
  "CatalogArtifactShowLive render boundary",
)

assert.equal(renderSource.match(/<\.vue\b/g)?.length, 1)
assert.match(renderSource, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(renderSource, /id="catalog-artifact-show-page-component"/)
assert.match(renderSource, /v-component="CatalogArtifactShowPage"/)
assert.match(renderSource, /presentation=\{@catalog_artifact_show_presentation\}/)
assert.match(renderSource, /v-on:reimport=\{JS\.push\("reimport"\)\}/)
assert.match(renderSource, /v-ssr=\{false\}/)
assert.match(renderSource, /class="contents"/)
assert.doesNotMatch(renderSource, /<\.page_header|v-component="CatalogArtifactShow"/)
assert.doesNotMatch(renderSource, /artifact=\{|runs=\{|catalog-artifact-show-component/)

const rawAttrsSource = sourceSlice(
  liveView,
  "  @doc false\n  def presentation_attrs(attrs) when is_map(attrs) do",
  "  defp assign_runs(socket, runs) do",
  "Catalog Artifact Show raw attribute projection",
)

assert.match(rawAttrsSource, /value in \[nil, false\]/)
assert.match(rawAttrsSource, /\{name, true\}, rendered/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, ""\)/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, to_string\(value\)\)/)

const assignRunsSource = sourceSlice(
  liveView,
  "  defp assign_runs(socket, runs) do",
  "  defp page_presentation_dto(mission, artifact, runs) do",
  "Catalog Artifact Show complete presentation refresh",
)

assert.match(assignRunsSource, /mission = socket\.assigns\.current_mission/)
assert.match(assignRunsSource, /artifact = socket\.assigns\.artifact/)
assert.match(assignRunsSource, /assign\(:runs, runs\)/)
assert.match(assignRunsSource, /:catalog_artifact_show_presentation/)
assert.match(assignRunsSource, /page_presentation_dto\(mission, artifact, runs\)/)

const presentationSource = sourceSlice(
  liveView,
  "  defp page_presentation_dto(mission, artifact, runs) do",
  "  defp run_dto(run, mission_id) do",
  "Catalog Artifact Show page and child presentation",
)

for (const id of [
  "catalog-artifact-show-page",
  "catalog-artifact-show-component",
]) {
  assert.ok(presentationSource.includes(`"${id}"`), `${id} remains Phoenix-authored`)
}

for (const text of ["Catalog", "Breadcrumb", "—", "/"]) {
  assert.ok(presentationSource.includes(`"${text}"`), `${text} remains Phoenix-authored`)
}

for (const className of [
  "space-y-6",
  "border-b border-primary/20 pb-4",
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60",
  "hover:text-primary transition-colors",
  "text-base-content/20",
  "text-primary/90",
  "mt-2 text-2xl font-bold text-base-content tracking-tight",
]) {
  assert.ok(presentationSource.includes(`"${className}"`), `${className} stays exact`)
}

assert.match(presentationSource, /presentation_attrs\(%\{"class" => false\}\)/)
assert.match(presentationSource, /"data-phx-link" => "redirect"/)
assert.match(presentationSource, /"data-phx-link-state" => "push"/)
assert.match(presentationSource, /~p"\/missions\/#\{mission\.mission_id\}"/)
assert.match(presentationSource, /~p"\/missions\/#\{mission\.mission_id\}\/catalog"/)
assert.match(presentationSource, /"text" => artifact\.artifact_name/)
assert.equal(presentationSource.match(/"text" => artifact\.artifact_name/g)?.length, 2)
assert.match(presentationSource, /"media_type" => artifact\.media_type \|\| "—"/)
assert.match(
  presentationSource,
  /Calendar\.strftime\(artifact\.uploaded_at, "%Y-%m-%d %H:%M:%S UTC"\)/,
)
assert.match(
  presentationSource,
  /~p"\/missions\/#\{mission_id\}\/catalog\/artifacts\/#\{artifact\.artifact_id\}\/download"/,
)
assert.match(presentationSource, /"runs" => Enum\.map\(runs, &run_dto\(&1, mission_id\)\)/)

const runProjectionSource = liveView.slice(liveView.indexOf("  defp run_dto(run, mission_id) do"))

for (const contract of [
  '"id" => "catalog-artifact-run-#{run.import_run_id}"',
  '"actions_id" => "#{run.import_run_id}-actions"',
  '"status" => status_tone(run.status)',
  '"status_label" => status_label(run.status)',
  'Calendar.strftime(run.started_at, "%Y-%m-%d %H:%M:%S")',
  '"completed_at" => completed_at(run.completed_at)',
  '~p"/missions/#{mission_id}/catalog/imports/#{run.import_run_id}"',
  'defp completed_at(nil), do: "—"',
  'defp status_tone(:running), do: "info"',
  'defp status_tone(:completed), do: "ready"',
  'defp status_tone(:failed), do: "blocked"',
  'defp status_label(:running), do: "Running"',
  'defp status_label(:completed), do: "Completed"',
  'defp status_label(:failed), do: "Failed"',
]) {
  assert.ok(runProjectionSource.includes(contract), `run projection retains ${contract}`)
}

const authenticatedScope = sourceSlice(
  router,
  '  scope "/", CadenceWeb do\n    pipe_through [:browser, :require_authenticated_scope]',
  "    live_session :organization,",
  "authenticated browser scope",
)

assert.match(authenticatedScope, /pipe_through \[:browser, :require_authenticated_scope\]/)

const catalogSession = sourceSlice(
  router,
  "    live_session :catalog,",
  "    live_session :comms,",
  "Catalog LiveSession",
)

assert.match(catalogSession, /\{CadenceWeb\.OrganizationAuth, :require_organization_scope\}/)
assert.match(catalogSession, /\{CadenceWeb\.MissionAuth, :load_mission\}/)
assert.match(catalogSession, /\{CadenceWeb\.UserAuth, :attach_user_menu\}/)
assert.match(catalogSession, /layout: \{CadenceWeb\.Layouts, :mission_sidebar\} do/)
assert.match(
  catalogSession,
  /live "\/missions\/:mission_id\/catalog\/artifacts\/:artifact_id",\s+CatalogArtifactShowLive,\s+:show/,
)
assert.equal(
  catalogSession.match(
    /live "\/missions\/:mission_id\/catalog\/artifacts\/:artifact_id",\s+CatalogArtifactShowLive,\s+:show/g,
  )?.length,
  1,
)
assert.doesNotMatch(catalogSession, /require_organization_admin|require_platform_admin/)

const expectedScenarios = [
  "renders artifact metadata and its import runs",
  "represents the no-runs state without leaking domain structs",
  "re-import action starts a new run and navigates to it",
  "updates matching runs from PubSub and ignores events for another artifact",
  "missing artifact redirects to the catalog index",
  "does not load an artifact outside the current mission scope",
  "projects the complete page through one JSON-safe non-SSR parent host",
  "raw attrs preserve HEEx nil false true empty string string and number semantics",
]

const declaredScenarios = [...liveViewTest.matchAll(/^  test "([^"]+)"/gm)].map(
  ([, scenario]) => scenario,
)

assert.deepEqual(declaredScenarios, expectedScenarios)

const helperSource = sourceSlice(
  liveViewTest,
  "  defp artifact_show_vue(view) do",
  '  test "renders artifact metadata and its import runs"',
  "Catalog Artifact Show Vue helper",
)

assert.equal(assertionSiteCount(helperSource), 5)
assert.match(helperSource, /#catalog-artifact-show-page-component/)
assert.match(helperSource, /#catalog-artifact-show-page-component\.contents/)
assert.match(helperSource, /id: "catalog-artifact-show-page-component"/)
assert.match(helperSource, /vue\.component == "CatalogArtifactShowPage"/)
assert.match(helperSource, /vue\.ssr == false/)

const existingScenarioStarts = expectedScenarios.slice(0, 6).map((scenario) => `  test "${scenario}"`)
const existingScenarioEnds = [
  ...existingScenarioStarts.slice(1),
  `  test "${expectedScenarios[6]}"`,
]
const expectedAssertionSites = [2, 2, 4, 6, 3, 3]

for (const [index, scenario] of expectedScenarios.slice(0, 6).entries()) {
  const scenarioSource = sourceSlice(
    liveViewTest,
    existingScenarioStarts[index],
    existingScenarioEnds[index],
    `existing scenario ${scenario}`,
  )

  assert.equal(
    assertionSiteCount(scenarioSource),
    expectedAssertionSites[index],
    `${scenario} retains every assertion site`,
  )
}

assert.equal(5 + expectedAssertionSites.reduce((sum, count) => sum + count, 0), 25)

const metadataScenario = sourceSlice(
  liveViewTest,
  existingScenarioStarts[0],
  existingScenarioEnds[0],
  "artifact metadata and runs scenario",
)
assert.match(metadataScenario, /artifact_show_presentation\(view\)\["header"\]\["title"\]\["text"\]/)
assert.match(metadataScenario, /vue\.props\["presentation"\]\["artifact_show"\]/)

const noRunsScenario = sourceSlice(
  liveViewTest,
  existingScenarioStarts[1],
  existingScenarioEnds[1],
  "artifact no-runs scenario",
)
assert.match(noRunsScenario, /artifact_show_presentation\(view\)\["artifact_show"\]/)
assert.match(noRunsScenario, /props\["runs"\] == \[\]/)

const reimportScenario = sourceSlice(
  liveViewTest,
  existingScenarioStarts[2],
  existingScenarioEnds[2],
  "artifact reimport scenario",
)
assert.match(reimportScenario, /vue\.handlers == %\{"reimport" => JS\.push\("reimport"\)\}/)
assert.match(reimportScenario, /element\("#catalog-artifact-show-page-component"\)/)
assert.match(reimportScenario, /render_hook\("reimport", %\{\}\)/)
assert.match(reimportScenario, /\{:error, \{:live_redirect, %\{to: to\}\}\}/)

const pubSubScenario = sourceSlice(
  liveViewTest,
  existingScenarioStarts[3],
  existingScenarioEnds[3],
  "artifact PubSub scenario",
)
assert.match(pubSubScenario, /artifact_show_presentation\(view\)\["artifact_show"\]\["runs"\]/)
assert.match(pubSubScenario, /send\(view\.pid, \{:import_run_started, other_run\}\)/)

const redirectScenarios = sourceSlice(
  liveViewTest,
  existingScenarioStarts[4],
  existingScenarioEnds[5],
  "artifact not-found and scope scenarios",
)
assert.equal(redirectScenarios.match(/flash\["error"\] == "Artifact not found\."/g)?.length, 2)
assert.equal(
  redirectScenarios.match(/to == ~p"\/missions\/#\{mission\.mission_id\}\/catalog"/g)?.length,
  2,
)

const hostScenario = sourceSlice(
  liveViewTest,
  `  test "${expectedScenarios[6]}"`,
  `  test "${expectedScenarios[7]}"`,
  "focused parent host and JSON scenario",
)

for (const contract of [
  'vue.class == "contents"',
  'Map.keys(vue.props) == ["presentation"]',
  'vue.handlers == %{"reimport" => JS.push("reimport")}',
  "Jason.decode!(Jason.encode!(presentation))",
  '"id" => "catalog-artifact-show-page"',
  '"id" => "catalog-artifact-show-component"',
  '"data-phx-link" => "redirect"',
  '"data-phx-link-state" => "push"',
]) {
  assert.ok(hostScenario.includes(contract), `host scenario retains ${contract}`)
}

const rawAttrsScenario = sourceSlice(
  liveViewTest,
  `  test "${expectedScenarios[7]}"`,
  "  defp artifact_show_presentation(view)",
  "focused raw attribute scenario",
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

console.log("catalog_artifact_show_page_test passed")
