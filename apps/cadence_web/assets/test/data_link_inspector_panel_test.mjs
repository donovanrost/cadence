import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const vuePath = resolve(__dirname, "../vue/DataLinkInspectorPanel.vue")
const rowSectionPath = resolve(__dirname, "../vue/data_link_inspector/RowSection.vue")
const formPresentationPath = resolve(__dirname, "../vue/data_link_inspector/FormPresentation.vue")
const effectsListPath = resolve(__dirname, "../vue/data_link_inspector/EffectsList.vue")
const presentationTypesPath = resolve(
  __dirname,
  "../vue/data_link_inspector/presentation_types.ts"
)
const dashboardPanelPath = resolve(__dirname, "../vue/DashboardPanel.vue")
const formComponentsPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/form_components.ex"
)
const presentationPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/data_link_inspector_panel_presentation.ex"
)
const controllerPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live.ex"
)
const viewerPath = resolve(__dirname, "../../lib/cadence_web/live/ops_dashboard_viewer_live.ex")
const routerPath = resolve(__dirname, "../../lib/cadence_web/router.ex")
const clipboardTestSupportPath = resolve(__dirname, "../../test/support/live_vue_clipboard_test_support.ex")
const viewportSmokePath = resolve(__dirname, "./dashboard_viewport_smoke.mjs")

const [
  vueSource,
  rowSectionSource,
  formPresentationSource,
  effectsListSource,
  presentationTypesSource,
  dashboardPanelSource,
  formComponentsSource,
  presentationSource,
  controllerSource,
  viewerSource,
  routerSource,
  clipboardTestSupportSource,
  viewportSmokeSource
] = await Promise.all([
  readFile(vuePath, "utf8"),
  readFile(rowSectionPath, "utf8"),
  readFile(formPresentationPath, "utf8"),
  readFile(effectsListPath, "utf8"),
  readFile(presentationTypesPath, "utf8"),
  readFile(dashboardPanelPath, "utf8"),
  readFile(formComponentsPath, "utf8"),
  readFile(presentationPath, "utf8"),
  readFile(controllerPath, "utf8"),
  readFile(viewerPath, "utf8"),
  readFile(routerPath, "utf8"),
  readFile(clipboardTestSupportPath, "utf8"),
  readFile(viewportSmokePath, "utf8")
])

const scenarioLedger = [
  [
    "data_link_inspector_panel_components_test.exs",
    "data_link_panel renders inspector identity, rows, related links, and actions"
  ],
  [
    "data_link_inspector_panel_lifecycle_recovery_test.exs",
    "data_link_panel explains failed lifecycle events that require correction"
  ],
  [
    "data_link_inspector_panel_lifecycle_recovery_test.exs",
    "data_link_panel groups lifecycle recovery related links"
  ],
  [
    "data_link_inspector_panel_workflow_dispatch_test.exs",
    "data_link_panel presents degraded workflow dispatch with retry controls"
  ],
  [
    "data_link_inspector_panel_revision_decision_test.exs",
    "data_link_panel renders revision decision controls for revision decision events"
  ],
  [
    "data_link_inspector_panel_revision_decision_test.exs",
    "data_link_panel renders revision decision controls for comparison findings with identity context"
  ],
  [
    "data_link_inspector_panel_late_data_policy_test.exs",
    "data_link_panel renders late-data policy controls for lifecycle events"
  ],
  [
    "data_link_inspector_panel_late_data_policy_events_test.exs",
    "data_link_panel marks late-data policy decisions event-only without source sample identity"
  ],
  [
    "data_link_inspector_panel_late_data_policy_events_test.exs",
    "data_link_panel does not render late-data policy controls for policy events"
  ],
  [
    "data_link_inspector_panel_source_watermark_test.exs",
    "data_link_panel renders source watermark event inspector rows"
  ]
]

assert.equal(scenarioLedger.length, 10, "the frozen migration ledger must remain one-for-one")

for (const [file, scenario] of scenarioLedger) {
  const source = await readFile(resolve(__dirname, `../../test/cadence_web/live/ops_dashboard_show_live/${file}`), "utf8")
  assert.equal(
    source.split(`test "${scenario}"`).length - 1,
    1,
    `ledger scenario must remain named exactly once: ${scenario}`
  )
}

assert.match(
  routerSource,
  /live "\/missions\/:mission_id\/ops\/dashboards\/:dashboard_id",\s+OpsDashboardViewerLive,\s+:show/
)
assert.match(viewerSource, /alias CadenceWeb\.OpsDashboardShowLive\.Controller/)
assert.match(viewerSource, /defdelegate render\(assigns\), to: Controller/)
assert.match(controllerSource, /<FormComponents\.widget_panel/)
assert.match(formComponentsSource, /def dashboard_panel_presentation\(assigns\)/)
assert.match(formComponentsSource, /defp child_presentation\(%\{panel: \{:data_link, inspector\}\} = assigns\)/)
assert.match(formComponentsSource, /DataLinkInspectorPanelPresentation\.for_vue\(/)
assert.match(formComponentsSource, /"data_link_inspector_panel"/)
assert.match(formComponentsSource, /"dashboard-data-link-inspector-component"/)
assert.match(formComponentsSource, /presentation\.root\.attrs/)
assert.equal(
  formComponentsSource.match(/<\.vue\b/g)?.length,
  1,
  "the routed panel region must have one LiveVue host"
)
assert.match(formComponentsSource, /id="dashboard-panel-component"/)
assert.match(formComponentsSource, /v-component="DashboardPanel"/)
assert.match(formComponentsSource, /presentation=\{@presentation\}/)
assert.doesNotMatch(formComponentsSource, /v-component="DataLinkInspectorPanel"/)
assert.match(dashboardPanelSource, /import DataLinkInspectorPanel from "\.\/DataLinkInspectorPanel\.vue"/)
assert.match(dashboardPanelSource, /presentation\.child\.kind === 'data_link_inspector_panel'/)
assert.match(dashboardPanelSource, /v-bind="presentation\.child\.outer_wrapper\?\.attrs"/)
assert.match(dashboardPanelSource, /v-bind="presentation\.child\.wrapper\.attrs"/)
assert.match(
  dashboardPanelSource,
  /<DataLinkInspectorPanel :presentation="presentation\.child\.presentation" \/>/
)
assert.match(presentationSource, /:id => "dashboard-data-link-inspector"/)

assert.match(vueSource, /import ClipboardButton from "\.\/ClipboardButton\.vue"/)
assert.equal(
  vueSource.match(/<ClipboardButton\b/g)?.length,
  1,
  "the panel must directly compose the existing clipboard control"
)
assert.doesNotMatch(vueSource, /v-component|<\.vue/)
assert.doesNotMatch(vueSource, /data-name/)

assert.match(
  vueSource,
  /import DataLinkRowSection from "\.\/data_link_inspector\/RowSection\.vue"/
)
assert.match(
  vueSource,
  /import DataLinkFormPresentation from "\.\/data_link_inspector\/FormPresentation\.vue"/
)
assert.equal(
  vueSource.match(/<DataLinkRowSection\b/g)?.length,
  3,
  "selection, record, and runtime context must share the row renderer one-for-one"
)
assert.equal(
  vueSource.match(/<DataLinkFormPresentation\b/g)?.length,
  2,
  "revision decision and late-data policy must share the native form renderer one-for-one"
)
assert.match(vueSource, /v-if="presentation\.selection" :presentation="presentation\.selection"/)
assert.match(vueSource, /v-if="presentation\.record" :presentation="presentation\.record"/)
assert.match(vueSource, /v-if="presentation\.runtime_context"/)
assert.match(vueSource, /:presentation="presentation\.runtime_context"/)
assert.match(vueSource, /:presentation="presentation\.revision_decision\.form"/)
assert.match(vueSource, /:effects="presentation\.revision_decision\.effects"/)
assert.match(vueSource, /effects_id="dashboard-revision-decision-effect-preview"/)
assert.match(vueSource, /effect_key_attribute="data-revision-decision-effect"/)
assert.match(vueSource, /:presentation="presentation\.late_data_policy\.form"/)
assert.match(vueSource, /:effects="presentation\.late_data_policy\.effects"/)
assert.match(vueSource, /effects_id="dashboard-late-data-policy-effect-preview"/)
assert.match(vueSource, /effect_key_attribute="data-late-data-policy-effect"/)
assert.doesNotMatch(vueSource, /<form\b/)

assert.match(rowSectionSource, /<section v-bind="presentation\.attrs">/)
assert.match(rowSectionSource, /<template v-for="row in presentation\.rows" :key="row\.key">/)
assert.match(rowSectionSource, /<dt :class="row\.label\.class">/)
assert.match(rowSectionSource, /<dd :class="row\.value\.class" v-bind="row\.value\.attrs">/)

assert.match(formPresentationSource, /<form v-bind="presentation\.attrs">/)
assert.match(formPresentationSource, /v-for="field in presentation\.hidden_fields"/)
assert.match(formPresentationSource, /:key="String\(field\.id\)"/)
assert.match(formPresentationSource, /<EffectsList/)
assert.match(formPresentationSource, /v-for="field in presentation\.fields"/)
assert.match(formPresentationSource, /<select v-if="field\.options" v-bind="field\.attrs">/)
assert.match(formPresentationSource, /:selected="option\.selected"/)
assert.match(formPresentationSource, /:disabled="option\.disabled"/)
assert.match(formPresentationSource, /:title="option\.title"/)
assert.match(formPresentationSource, /<input v-else v-bind="field\.attrs">/)
assert.match(formPresentationSource, /v-bind="presentation\.confirmation\.input\.attrs"/)
assert.match(formPresentationSource, /<button v-bind="presentation\.submit\.attrs">/)

assert.match(effectsListSource, /<div :id="id" class="grid grid-cols-1 gap-1 text-\[0\.68rem\] sm:grid-cols-2">/)
assert.match(effectsListSource, /v-for="effect in effects"/)
assert.match(effectsListSource, /:key="String\(effect\.attrs\[key_attribute\]\)"/)
assert.match(effectsListSource, /v-bind="effect\.attrs"/)
assert.match(effectsListSource, /v-bind="effect\.summary\.attrs"/)

assert.match(presentationTypesSource, /export type RowSectionPresentation =/)
assert.match(presentationTypesSource, /export type FormPresentation =/)
assert.match(presentationTypesSource, /export type EffectPresentation =/)
assert.doesNotMatch(
  [vueSource, rowSectionSource, formPresentationSource, effectsListSource].join("\n"),
  /from "reka-ui"|ui\/reka/
)
assert.match(presentationSource, /as: :revision_decision/)
assert.match(presentationSource, /as: :late_data_policy/)
assert.match(presentationSource, /"phx-submit" => "apply_revision_decision"/)
assert.match(presentationSource, /"phx-submit" => "record_late_data_policy_decision"/)
assert.match(presentationSource, /value: "confirmed"/)
assert.doesNotMatch(presentationSource, /\{:confirmed, "dashboard-(?:late-data-policy|revision-decision)-/)
assert.match(clipboardTestSupportSource, /LiveVue\.Test\.get_vue\(renderable, id: "dashboard-data-link-inspector-component"\)/)

assert.match(vueSource, /v-bind="action\.attrs"/)
assert.match(vueSource, /v-bind="presentation\.historical_workflow_navigation\.attrs"/)
assert.match(vueSource, /v-bind="entry\.attrs"/)
assert.match(vueSource, /v-bind="link\.attrs"/)
assert.match(presentationSource, /"data-phx-link" => "redirect"/)
assert.match(presentationSource, /"data-phx-link-state" => "push"/)
assert.match(presentationSource, /"phx-click" => "open_data_link"/)
assert.match(presentationSource, /DataLinkAttrs\.open/)
let clipboardSelector
let dataLinkClipboardOracles = 0
for (const line of viewportSmokeSource.split("\n")) {
  if (line.includes('const copy = document.querySelector("#dashboard-data-link-copy-link")')) {
    clipboardSelector = "data-link"
  } else if (line.includes('const copy = document.querySelector("#dashboard-evidence-copy-link")')) {
    clipboardSelector = "evidence"
  } else if (line.includes("copyComponent:") && clipboardSelector === "data-link") {
    assert.match(line, /copy\?\.matches\("\[data-clipboard-button\]"\) \? "ClipboardButton" : ""/)
    assert.doesNotMatch(line, /data-name/)
    dataLinkClipboardOracles += 1
  }
}
assert.equal(dataLinkClipboardOracles, 52, "every DataLink browser clipboard oracle must use a stable attribute")
