import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const vuePath = resolve(__dirname, "../vue/DataLinkInspectorPanel.vue")
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

assert.match(vueSource, /<form v-bind="presentation\.revision_decision\.form\.attrs">/)
assert.match(vueSource, /<form v-bind="presentation\.late_data_policy\.form\.attrs">/)
assert.match(vueSource, /v-bind="presentation\.revision_decision\.form\.confirmation\.input\.attrs"/)
assert.match(vueSource, /v-bind="presentation\.late_data_policy\.form\.confirmation\.input\.attrs"/)
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
const viewportCopyClickPath = viewportSmokeSource.match(
  /if \(profile\.copyClickSelector\) \{([\s\S]*?)\n  \}\n\n  const expression/,
)?.[1]
assert.ok(viewportCopyClickPath, "the viewport smoke must retain its physical clipboard click path")
assert.match(
  viewportCopyClickPath,
  /target\.scrollIntoView\(\{behavior: "instant", block: "center", inline: "center"\}\)[\s\S]*const rect = target\.getBoundingClientRect\(\)/,
  "the clipboard target must be scrolled deterministically before its click coordinates are measured",
)
assert.match(viewportCopyClickPath, /Input\.dispatchMouseEvent[\s\S]*type: "mousePressed"/)
assert.match(viewportCopyClickPath, /Input\.dispatchMouseEvent[\s\S]*type: "mouseReleased"/)
assert.match(viewportCopyClickPath, /window\.scrollTo\(\{left:/)
assert.match(
  viewportSmokeSource,
  /assert\.equal\(result\.copyClickSucceeded, true, `\$\{result\.name\} should run ClipboardButton on click`\)/,
  "the physical click must still prove ClipboardButton success",
)
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
