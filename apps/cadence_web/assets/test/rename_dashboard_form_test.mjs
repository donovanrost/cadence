import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const testDirectory = dirname(fileURLToPath(import.meta.url))
const vuePath = resolve(testDirectory, "../vue/RenameDashboardForm.vue")
const componentPath = resolve(
  testDirectory,
  "../../lib/cadence_web/live/ops_dashboard_show_live/form_components.ex",
)
const controllerPath = resolve(
  testDirectory,
  "../../lib/cadence_web/live/ops_dashboard_show_live.ex",
)
const routerPath = resolve(testDirectory, "../../lib/cadence_web/router.ex")
const loaderPath = resolve(testDirectory, "../vue/index.ts")
const componentTestPath = resolve(
  testDirectory,
  "../../test/cadence_web/live/ops_dashboard_show_live/rename_dashboard_form_components_test.exs",
)
const liveTestPath = resolve(
  testDirectory,
  "../../test/cadence_web/live/ops_dashboard_show_live/rename_dashboard_form_live_test.exs",
)

const [
  vueSource,
  componentSource,
  controllerSource,
  routerSource,
  loaderSource,
  componentTestSource,
  liveTestSource,
] = await Promise.all([
  readFile(vuePath, "utf8"),
  readFile(componentPath, "utf8"),
  readFile(controllerPath, "utf8"),
  readFile(routerPath, "utf8"),
  readFile(loaderPath, "utf8"),
  readFile(componentTestPath, "utf8"),
  readFile(liveTestPath, "utf8"),
])

const scenarioLedger = [
  {
    file: "../../test/cadence_web/live/ops_dashboard_activity_live_test.exs",
    name: "Viewer routes page-sized workflows instead of exposing inline mutation controls",
    assertionCount: 7,
    sha256: "3692bd8e0929a6556c532ba16c740f91e6c6c5256419b4d0631bca201473d2ac",
  },
  {
    file:
      "../../test/cadence_web/live/ops_dashboard_show_live/dashboard_lifecycle_version_actions_live_test.exs",
    name: "renames the dashboard from the toolbar menu without exposing hard delete",
    assertionCount: 6,
    sha256: "111ece5774ad24ea004c1d352ca360dc649ef2dd201823371df03d8c25e182b7",
  },
  {
    file: "../../test/cadence_web/live/ops_dashboard_show_live/panel_events_test.exs",
    name: "open_rename opens the rename panel",
    assertionCount: 4,
    sha256: "27b1a74bdc5106a410bd51425dd2c36ba67a7d54ca26aefdad003cc7aabbadd9",
  },
  {
    file: "../../test/cadence_web/live/ops_dashboard_show_live/rename_flow_test.exs",
    name: "renamed_document normalizes name and description",
    assertionCount: 2,
    sha256: "8a68183b6249bf1297aaae5d6fc2dfb35edd22890a808a3e9b8f56f14e671353",
  },
  {
    file: "../../test/cadence_web/live/ops_dashboard_show_live/rename_flow_test.exs",
    name: "renamed_document keeps the current name when submitted name is blank",
    assertionCount: 2,
    sha256: "aec267a2c03638f68168e3cddc3bfd2642a3f7b9cab22e23157756fb50b799f5",
  },
  {
    file: "../../test/cadence_web/live/ops_dashboard_show_live/rename_flow_test.exs",
    name: "rename persists the renamed document, refreshes summaries, and closes the panel",
    assertionCount: 6,
    sha256: "34c781d43724fe80bf103e200d3b2d88b6e7b40266b4e147c2580dc19fa5ea5b",
  },
  {
    file: "../../test/cadence_web/live/ops_dashboard_show_live/rename_flow_test.exs",
    name: "rename returns persistence errors without refreshing summaries or closing the panel",
    assertionCount: 3,
    sha256: "521b647c1264a38097d3d5649c36c603f34640df02ec61e664af6c25d55717bf",
  },
]

const scenarioBlock = (source, name) => {
  const marker = `test "${name}" do`
  assert.equal(
    source.split(marker).length - 1,
    1,
    `rename behavior scenario must remain named exactly once: ${name}`,
  )

  const start = source.indexOf(marker)
  const finishCandidates = ["\n  test \"", "\n  defp ", "\n  describe \"", "\nend\n"]
    .map((needle) => source.indexOf(needle, start + marker.length))
    .filter((index) => index >= 0)

  assert.ok(finishCandidates.length > 0, `scenario must have a source boundary: ${name}`)
  return source.slice(start, Math.min(...finishCandidates)).trimEnd()
}

assert.equal(scenarioLedger.length, 7, "every existing dashboard rename scenario must stay pinned")

for (const scenario of scenarioLedger) {
  const source = await readFile(resolve(testDirectory, scenario.file), "utf8")
  const block = scenarioBlock(source, scenario.name)
  const assertionCount = block.match(/^\s*(?:assert|refute)\b/gm)?.length ?? 0
  const sha256 = createHash("sha256").update(block).digest("hex")

  assert.equal(
    assertionCount,
    scenario.assertionCount,
    `rename behavior assertions must remain exact: ${scenario.name}`,
  )
  assert.equal(sha256, scenario.sha256, `rename behavior source must remain frozen: ${scenario.name}`)
}

assert.equal(
  componentSource.match(/<\.vue\b/g)?.length,
  1,
  "FormComponents must contain one LiveVue host for the complete panel region",
)
assert.doesNotMatch(componentSource, /<\.form\b/)
assert.match(componentSource, /id="dashboard-panel-component"/)
assert.match(componentSource, /v-component="DashboardPanel"/)
assert.match(componentSource, /v-ssr=\{false\}/)
assert.match(componentSource, /class="contents"/)
assert.doesNotMatch(componentSource, /v-component="RenameDashboardForm"/)
assert.match(componentSource, /defp child_presentation\(%\{panel: :rename\} = assigns\)/)
assert.match(componentSource, /"rename_dashboard_form"/)
assert.match(componentSource, /"rename-dashboard-form-component"/)
assert.match(componentSource, /"id" => "rename-dashboard-form"/)
assert.match(componentSource, /"phx-submit" => "rename"/)
assert.match(componentSource, /"class" => "space-y-4"/)
assert.match(componentSource, /"name" => assigns\.dashboard_document\.name/)
assert.match(componentSource, /"description" => assigns\.dashboard_document\.description/)
assert.match(componentSource, /as: :dashboard/)
assert.match(componentSource, /rename_text_field_presentation\(form, :name, "Name", required: true\)/)
assert.match(
  componentSource,
  /rename_text_field_presentation\(form, :description, "Description", required: false\)/,
)
assert.match(componentSource, /"class" => "fieldset mb-3"/)
assert.match(componentSource, /"class" => "hud-label block mb-1\.5"/)
assert.match(componentSource, /"class" => "w-full input"/)
assert.match(componentSource, /"type" => "submit"/)
assert.match(componentSource, /"class" => "btn btn-primary"/)
assert.match(componentSource, /text: "Save"/)

assert.doesNotMatch(componentSource, /<\.sheet\b|<\/\.sheet>/)
assert.match(componentSource, /"id" => "dashboard-panel-layer"/)
assert.match(componentSource, /"id" => "dashboard-panel"/)
assert.match(componentSource, /"phx-click" => "close_panel"/)
assert.match(componentSource, /"phx-window-keydown" => "close_panel"/)
assert.match(componentSource, /"phx-key" => "Escape"/)
assert.match(componentSource, /defp panel_title\(:rename\), do: "Rename Dashboard"/)
assert.match(componentSource, /defp panel_width\(_panel\), do: :md/)

assert.match(controllerSource, /def handle_event\("open_rename", _params, socket\)/)
assert.match(controllerSource, /\{:noreply, PanelEvents\.open_rename\(socket\)\}/)
assert.match(controllerSource, /def handle_event\("rename", %\{"dashboard" => params\}, socket\)/)
assert.match(controllerSource, /RenameFlow\.rename\(socket, params, rename_flow_opts\(socket\)\)/)

assert.match(routerSource, /pipe_through \[:browser, :require_authenticated_scope\]/)
const authorSessionStart = routerSource.indexOf("live_session :ops_dashboard_author")
const authorSessionEnd = routerSource.indexOf("live_session :ops,", authorSessionStart)
const authorSession = routerSource.slice(authorSessionStart, authorSessionEnd)
assert.ok(authorSessionStart >= 0 && authorSessionEnd > authorSessionStart)
assert.match(authorSession, /OrganizationAuth, :require_organization_scope/)
assert.match(authorSession, /MissionAuth, :load_mission/)
assert.match(authorSession, /DashboardAuthorAuth, :require_dashboard_author/)
assert.match(authorSession, /OpsDashboardEditorLive/)
assert.match(authorSession, /:edit/)
assert.match(loaderSource, /import\.meta\.glob\("\.\/\*\*\/\*\.vue", \{eager: true\}\)/)
assert.match(loaderSource, /findComponent\(components, name\)/)

const script = vueSource.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = vueSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
assert.ok(script, "RenameDashboardForm.vue must expose its typed presentation contract")
assert.ok(template, "RenameDashboardForm.vue must expose its form template")
assert.match(script, /defineProps<\{presentation: Presentation\}>\(\)/)
assert.match(script, /value: string \| null/)
assert.match(template, /<form v-bind="presentation\.root\.attrs">/)
assert.match(template, /v-for="field in presentation\.fields"/)
assert.match(template, /v-bind="field\.wrapper\.attrs"/)
assert.match(template, /v-bind="field\.label\.attrs"/)
assert.match(template, /v-bind="field\.control\.attrs" :value="field\.control\.value"/)
assert.match(template, /<button v-bind="presentation\.submit\.attrs">/)
assert.doesNotMatch(vueSource, /defineEmits|\bemit\(|\breactive\(|\bwatch\(|@submit|@click/)

const orderedTemplateTokens = [
  '<form v-bind="presentation.root.attrs">',
  'v-for="field in presentation.fields"',
  'v-bind="field.control.attrs"',
  '<button v-bind="presentation.submit.attrs">',
]
let previousTemplateIndex = -1
for (const token of orderedTemplateTokens) {
  const index = template.indexOf(token, previousTemplateIndex + 1)
  assert.ok(index > previousTemplateIndex, `${token} must preserve form ordering`)
  previousTemplateIndex = index
}

const browserFormSubmission = (presentation, currentValues = {}) => {
  const params = Object.fromEntries(
    presentation.fields.map((field) => {
      const match = field.control.attrs.name.match(/^([^[]+)\[([^\]]+)\]$/)
      assert.ok(match, `field must retain a nested browser name: ${field.key}`)
      assert.equal(match[1], presentation.root.param)
      return [match[2], currentValues[field.key] ?? field.control.value ?? ""]
    }),
  )

  return {[presentation.root.param]: params}
}

const representativePresentation = {
  root: {
    attrs: {id: "rename-dashboard-form", "phx-submit": "rename", class: "space-y-4"},
    param: "dashboard",
    params: {name: "Power", description: ""},
  },
  fields: [
    {
      key: "name",
      control: {attrs: {name: "dashboard[name]", required: ""}, value: "Power"},
    },
    {
      key: "description",
      control: {attrs: {name: "dashboard[description]"}, value: null},
    },
  ],
}

assert.deepEqual(browserFormSubmission(representativePresentation), {
  dashboard: {name: "Power", description: ""},
})
assert.deepEqual(
  browserFormSubmission(representativePresentation, {
    name: "Power North",
    description: "Primary EPS",
  }),
  {dashboard: {name: "Power North", description: "Primary EPS"}},
)

assert.match(componentTestSource, /exact populated RenameDashboardForm contract/)
assert.match(componentTestSource, /nil description presentation and browser form semantics/)
assert.match(componentTestSource, /vue\.component == "DashboardPanel"/)
assert.match(componentTestSource, /panel\["child"\]\["kind"\] == "rename_dashboard_form"/)
assert.match(componentTestSource, /vue\.props == Jason\.decode!\(Jason\.encode!\(vue\.props\)\)/)
assert.match(liveTestSource, /submits every browser form value through the authoritative rename event/)
assert.match(liveTestSource, /submits an empty browser description so Phoenix restores nil semantics/)
assert.match(liveTestSource, /vue\.component == "DashboardPanel"/)
assert.match(liveTestSource, /panel\["child"\]\["kind"\] == "rename_dashboard_form"/)
assert.match(liveTestSource, /assert browser_params == root\["params"\]/)
assert.match(liveTestSource, /Map\.keys\(params\) \|> Enum\.sort\(\) == \["description", "name"\]/)
assert.match(
  liveTestSource,
  /render_submit\(view, root\["attrs"\]\["phx-submit"\], %\{root\["param"\] => params\}\)/,
)
