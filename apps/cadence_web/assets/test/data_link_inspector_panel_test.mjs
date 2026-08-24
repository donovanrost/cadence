import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const vuePath = resolve(__dirname, "../vue/DataLinkInspectorPanel.vue")
const componentPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/data_link_inspector_panel_components.ex"
)
const presentationPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/data_link_inspector_panel_presentation.ex"
)
const clipboardTestSupportPath = resolve(__dirname, "../../test/support/live_vue_clipboard_test_support.ex")
const viewportSmokePath = resolve(__dirname, "./dashboard_viewport_smoke.mjs")

const [vueSource, componentSource, presentationSource, clipboardTestSupportSource, viewportSmokeSource] = await Promise.all([
  readFile(vuePath, "utf8"),
  readFile(componentPath, "utf8"),
  readFile(presentationPath, "utf8"),
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

assert.equal(
  componentSource.match(/<\.vue\b/g)?.length,
  1,
  "the complete parent region must have one LiveVue host"
)
assert.match(componentSource, /id="dashboard-data-link-inspector"/)
assert.match(componentSource, /v-component="DataLinkInspectorPanel"/)
assert.match(componentSource, /presentation=\{@presentation\}/)
assert.doesNotMatch(componentSource, /v-component="ClipboardButton"/)

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
assert.match(presentationSource, /"phx-submit": "apply_revision_decision"/)
assert.match(presentationSource, /"phx-submit": "record_late_data_policy_decision"/)
assert.match(presentationSource, /value: "confirmed"/)
assert.doesNotMatch(presentationSource, /\{:confirmed, "dashboard-(?:late-data-policy|revision-decision)-/)
assert.match(clipboardTestSupportSource, /LiveVue\.Test\.get_vue\(renderable, id: "dashboard-data-link-inspector"\)/)

assert.match(vueSource, /v-bind="action\.attrs"/)
assert.match(vueSource, /v-bind="presentation\.historical_workflow_navigation\.attrs"/)
assert.match(vueSource, /v-bind="entry\.attrs"/)
assert.match(vueSource, /v-bind="link\.attrs"/)
assert.match(presentationSource, /"data-phx-link": "redirect"/)
assert.match(presentationSource, /"data-phx-link-state": "push"/)
assert.match(presentationSource, /"phx-click": "open_data_link"/)
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
