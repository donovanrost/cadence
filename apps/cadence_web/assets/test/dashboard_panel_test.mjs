import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const testDirectory = dirname(fileURLToPath(import.meta.url))
const sourcePath = resolve(testDirectory, "../vue/DashboardPanel.vue")
const formComponentsPath = resolve(
  testDirectory,
  "../../lib/cadence_web/live/ops_dashboard_show_live/form_components.ex",
)
const sectionComponentsPath = resolve(
  testDirectory,
  "../../lib/cadence_web/live/ops_dashboard_show_live/dashboard_section_components.ex",
)
const requestComponentsPath = resolve(
  testDirectory,
  "../../lib/cadence_web/live/ops_dashboard_show_live/historical_workflow_request_form_components.ex",
)
const widgetFormComponentsPath = resolve(
  testDirectory,
  "../../lib/cadence_web/live/ops_dashboard_show_live/widget_form_components.ex",
)
const dataLinkPresentationPath = resolve(
  testDirectory,
  "../../lib/cadence_web/live/ops_dashboard_show_live/data_link_inspector_panel_presentation.ex",
)
const runtimeDiagnosticsComponentsPath = resolve(
  testDirectory,
  "../../lib/cadence_web/live/ops_dashboard_show_live/runtime_diagnostics_panel_components.ex",
)
const evidenceComponentsPath = resolve(
  testDirectory,
  "../../lib/cadence_web/live/ops_dashboard_show_live/evidence_inspector_panel_components.ex",
)
const dashboardToolbarPath = resolve(testDirectory, "../vue/DashboardToolbar.vue")
const dashboardToolbarMenuPath = resolve(testDirectory, "../vue/DashboardToolbarMenu.vue")
const cadencePopoverPath = resolve(testDirectory, "../vue/ui/reka/CadencePopover.vue")
const cadenceMenuPath = resolve(testDirectory, "../vue/ui/reka/CadenceMenu.vue")
const routerPath = resolve(testDirectory, "../../lib/cadence_web/router.ex")
const appJsPath = resolve(testDirectory, "../js/app.js")

const [
  source,
  formComponentsSource,
  sectionComponentsSource,
  requestComponentsSource,
  widgetFormComponentsSource,
  dataLinkPresentationSource,
  runtimeDiagnosticsComponentsSource,
  evidenceComponentsSource,
  dashboardToolbarSource,
  dashboardToolbarMenuSource,
  cadencePopoverSource,
  cadenceMenuSource,
  routerSource,
  appJsSource,
] = await Promise.all([
  readFile(sourcePath, "utf8"),
  readFile(formComponentsPath, "utf8"),
  readFile(sectionComponentsPath, "utf8"),
  readFile(requestComponentsPath, "utf8"),
  readFile(widgetFormComponentsPath, "utf8"),
  readFile(dataLinkPresentationPath, "utf8"),
  readFile(runtimeDiagnosticsComponentsPath, "utf8"),
  readFile(evidenceComponentsPath, "utf8"),
  readFile(dashboardToolbarPath, "utf8"),
  readFile(dashboardToolbarMenuPath, "utf8"),
  readFile(cadencePopoverPath, "utf8"),
  readFile(cadenceMenuPath, "utf8"),
  readFile(routerPath, "utf8"),
  readFile(appJsPath, "utf8"),
])

const script = source.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "DashboardPanel.vue must expose a typed script setup contract")
assert.ok(template, "DashboardPanel.vue must expose the complete panel template")

const children = [
  ["rename_dashboard_form", "RenameDashboardForm", "rename-dashboard-form-component", "contents"],
  [
    "dashboard_section_manager",
    "DashboardSectionManager",
    "dashboard-section-manager-component",
    "contents",
  ],
  [
    "historical_workflow_request_form",
    "HistoricalWorkflowRequestForm",
    "historical-workflow-request-form-component",
    "contents",
  ],
  [
    "data_link_inspector_panel",
    "DataLinkInspectorPanel",
    "dashboard-data-link-inspector-component",
    "space-y-4",
    "dashboard-data-link-inspector",
  ],
  [
    "evidence_inspector_panel",
    "EvidenceInspectorPanel",
    "dashboard-evidence-inspector-component",
    "contents",
  ],
  [
    "widget_inspect_panel",
    "WidgetInspectPanel",
    "dashboard-widget-inspector-component",
    "contents",
  ],
  [
    "runtime_diagnostics_panel",
    "RuntimeDiagnosticsPanel",
    "dashboard-diagnostics-panel-component",
    "space-y-5",
    "dashboard-diagnostics-panel",
  ],
  [
    "version_history_panel",
    "VersionHistoryPanel",
    "dashboard-version-history-panel-component",
    "contents",
  ],
  ["widget_form", "WidgetForm", "widget-form-component", "contents"],
]

const directImports = [...script.matchAll(/^import (\w+) from "\.\/(\w+)\.vue"$/gm)].map(
  ([, localName, fileName]) => [localName, fileName],
)

assert.deepEqual(
  directImports,
  children.map(([, component]) => [component, component]),
  "DashboardPanel must directly import exactly the nine existing child SFCs in branch order",
)

let previousBranch = -1
for (const [kind, component, id, className, outerId] of children) {
  assert.equal(
    template.match(new RegExp(`<${component}\\b`, "g"))?.length,
    1,
    `${component} must be directly composed exactly once`,
  )
  assert.match(template, new RegExp(`presentation\\.child\\.kind === '${kind}'`))
  assert.match(template, new RegExp(`<${component} :presentation="presentation\\.child\\.presentation" \\/>`))
  assert.match(formComponentsSource, new RegExp(`"${kind}"`))
  if (kind === "evidence_inspector_panel") {
    assert.match(formComponentsSource, /presentation\.component_id/)
    assert.match(evidenceComponentsSource, new RegExp(`"${id}"`))
  } else {
    assert.match(formComponentsSource, new RegExp(`"${id}"`))
  }
  assert.match(formComponentsSource, new RegExp(`"${className.replaceAll("-", "\\-")}"`))

  const branch = template.indexOf(`presentation.child.kind === '${kind}'`)
  assert.ok(branch > previousBranch, `${kind} must preserve the Phoenix branch order`)
  previousBranch = branch

  if (outerId) {
    const outerSource =
      kind === "data_link_inspector_panel"
        ? dataLinkPresentationSource
        : runtimeDiagnosticsComponentsSource
    assert.match(outerSource, new RegExp(outerId))
  }
}

assert.equal(
  formComponentsSource.match(/<\.vue\b/g)?.length,
  1,
  "widget_panel/1 must own exactly one Phoenix LiveVue host",
)
assert.equal(
  formComponentsSource.match(/v-component=/g)?.length,
  1,
  "the parent region must not nest additional Phoenix LiveVue hosts",
)
assert.match(formComponentsSource, /id="dashboard-panel-component"/)
assert.match(formComponentsSource, /v-component="DashboardPanel"/)
assert.match(formComponentsSource, /presentation=\{@presentation\}/)
assert.match(formComponentsSource, /v-ssr=\{false\}/)
assert.match(formComponentsSource, /class="contents"/)
assert.doesNotMatch(
  formComponentsSource,
  /v-component="(?:RenameDashboardForm|DashboardSectionManager|HistoricalWorkflowRequestForm|DataLinkInspectorPanel|EvidenceInspectorPanel|WidgetInspectPanel|RuntimeDiagnosticsPanel|VersionHistoryPanel|WidgetForm)"/,
)
assert.doesNotMatch(source, /v-component|<\.vue|defineAsyncComponent|<component\b|phx-hook|hooks\/overlay/)

assert.match(template, /^  <div v-bind="presentation\.sheet\.layer\.attrs">/)
assert.match(template, /<section v-bind="presentation\.sheet\.root\.attrs">/)
assert.match(template, /<header v-bind="presentation\.sheet\.header\.attrs">/)
assert.match(template, /<h2 v-bind="presentation\.sheet\.header\.title\.attrs">/)
assert.match(template, /<button v-bind="presentation\.sheet\.header\.close\.attrs">/)
assert.match(template, /<span v-bind="presentation\.sheet\.header\.close\.icon\.attrs"><\/span>/)
assert.match(template, /<div v-bind="presentation\.sheet\.body\.attrs">/)

const sheetTokens = [
  '"id" => "dashboard-panel-layer"',
  '"class" => "cadence-sheet-layer"',
  '"id" => "dashboard-panel"',
  '"role" => "dialog"',
  '"aria-modal" => "false"',
  '"aria-label" => title',
  '"data-sheet-width" => panel_width(assigns.panel)',
  '"class" => "cadence-sheet"',
  '"phx-window-keydown" => "close_panel"',
  '"phx-key" => "Escape"',
  '"class" => "cadence-sheet-header"',
  '"class" => "hud-label"',
  '"type" => "button"',
  '"class" => "cadence-icon-button"',
  '"phx-click" => "close_panel"',
  '"aria-label" => "Close panel"',
  '"class" => "hero-x-mark h-4 w-4"',
  '"class" => "cadence-sheet-body"',
]

for (const token of sheetTokens) {
  assert.ok(formComponentsSource.includes(token), `missing exact sheet contract: ${token}`)
}

assert.match(
  formComponentsSource,
  /@doc "Builds the server-authoritative, JSON-safe dashboard panel presentation\."/,
)
assert.match(formComponentsSource, /def dashboard_panel_presentation\(assigns\) do/)
assert.match(formComponentsSource, /title = panel_title\(assigns\.panel\)/)
assert.match(formComponentsSource, /child: child_presentation\(assigns\)/)
assert.match(formComponentsSource, /defp raw_attributes\(attributes\) do/)
assert.match(formComponentsSource, /defp rendered_body\(value\), do: to_string\(value\)/)
assert.doesNotMatch(formComponentsSource, /<\.sheet\b|CadenceWeb\.Components\.Overlay/)
assert.doesNotMatch(
  source,
  /dashboard-panel-layer|cadence-sheet|phx-window-keydown|close_panel/,
  "DashboardPanel must render the server-authored sheet DTO without recreating its values",
)

assert.match(
  formComponentsSource,
  /DataLinkInspectorPanelPresentation\.for_vue\([\s\S]*?presentation\.root\.attrs/,
)
assert.match(
  formComponentsSource,
  /RuntimeDiagnosticsPanelComponents\.presentation\([\s\S]*?presentation\.root\.attrs/,
)
assert.equal(
  template.match(/v-bind="presentation\.child\.outer_wrapper\?\.attrs"/g)?.length,
  2,
  "only DataLink and runtime diagnostics may recreate thin outer wrappers",
)
assert.equal(
  template.match(/v-bind="presentation\.child\.wrapper\.attrs"/g)?.length,
  9,
  "every direct child must retain its component-id wrapper",
)

assert.match(sectionComponentsSource, /def section_manager_presentation\(assigns\)/)
assert.match(requestComponentsSource, /def request_form_dto\(form\)/)
assert.match(widgetFormComponentsSource, /def widget_form_dto\(assigns\)/)
assert.match(
  formComponentsSource,
  /EvidenceInspectorPanelComponents\.presentation\(%\{[\s\S]*dashboard_lifecycle_events:/,
)
assert.match(formComponentsSource, /WidgetInspectPanelComponents\.inspect_panel_presentation\(/)
assert.match(formComponentsSource, /VersionHistoryPanelComponents\.presentation\(assigns\)/)
assert.match(formComponentsSource, /child_presentation\(%\{panel: :add_widget\} = assigns\)/)
assert.match(
  formComponentsSource,
  /child_presentation\(%\{panel: \{:edit_placement, _id\}\} = assigns\)/,
)

const fixedPanelTitles = [
  [":add_widget", "Add Widget"],
  [":rename", "Rename Dashboard"],
  [":versions", "Version History"],
  [":diagnostics", "Diagnostics"],
  [":dashboard_sections", "Dashboard Sections"],
  [":historical_workflow_request", "Historical Data Request"],
]

for (const [panel, title] of fixedPanelTitles) {
  assert.ok(
    formComponentsSource.includes(`defp panel_title(${panel}), do: "${title}"`),
    `${panel} must retain its exact sheet title`,
  )
}

assert.match(
  formComponentsSource,
  /defp panel_title\(\{:edit_placement, _id\}\), do: "Configure Widget"/,
)
assert.match(formComponentsSource, /defp panel_title\(\{:data_link, inspector\}\), do: inspector\.title/)
assert.match(formComponentsSource, /defp panel_title\(\{:evidence, inspector\}\), do: inspector\.title/)
assert.match(
  formComponentsSource,
  /defp panel_title\(\{:widget_inspect, %\{title: title\}\}\), do: "Inspect: #\{title\}"/,
)
assert.match(formComponentsSource, /defp panel_width\(\{:widget_inspect, _context\}\), do: :lg/)
assert.match(formComponentsSource, /defp panel_width\(_panel\), do: :md/)

const representativeSheet = {
  root: {
    attrs: {
      "phx-window-keydown": "close_panel",
      "phx-key": "Escape",
    },
  },
  header: {close: {attrs: {"phx-click": "close_panel"}}},
}

const dispatchCloseClick = (sheet) => ({event: sheet.header.close.attrs["phx-click"], payload: {}})
const dispatchWindowKey = (sheet, key) =>
  key === sheet.root.attrs["phx-key"]
    ? {event: sheet.root.attrs["phx-window-keydown"], payload: {key}}
    : null

assert.deepEqual(dispatchCloseClick(representativeSheet), {event: "close_panel", payload: {}})
assert.deepEqual(dispatchWindowKey(representativeSheet, "Escape"), {
  event: "close_panel",
  payload: {key: "Escape"},
})
assert.equal(dispatchWindowKey(representativeSheet, "Enter"), null)

assert.doesNotMatch(appJsSource, /hooks\/(?:overlay|resizable_panel)/)
assert.doesNotMatch(appJsSource, /\b(?:Overlay|ResizablePanel)\b/)

assert.match(dashboardToolbarSource, /import CadencePopover from "\.\/ui\/reka\/CadencePopover\.vue"/)
assert.equal(dashboardToolbarSource.match(/<CadencePopover/g)?.length, 2)
assert.match(dashboardToolbarMenuSource, /import CadenceMenu from "\.\/ui\/reka\/CadenceMenu\.vue"/)
assert.match(dashboardToolbarMenuSource, /import \{DropdownMenuItem\} from "reka-ui"/)
assert.match(cadencePopoverSource, /PopoverContent, PopoverRoot, PopoverTrigger/)
assert.match(
  cadenceMenuSource,
  /DropdownMenuContent,[\s\S]*DropdownMenuRoot,[\s\S]*DropdownMenuTrigger/,
)
assert.match(cadenceMenuSource, /:modal="false"/)
assert.match(cadenceMenuSource, /:loop="true"/)
assert.match(cadenceMenuSource, /subscribeToLegacyOverlayOpen/)
assert.doesNotMatch(
  dashboardToolbarSource,
  /createDashboardToolbarPopoverController|addEventListener|removeEventListener/,
)
assert.doesNotMatch(
  dashboardToolbarMenuSource,
  /createDashboardToolbarMenuController|addEventListener|removeEventListener/,
)

const authorSessionStart = routerSource.indexOf("live_session :ops_dashboard_author")
const viewerSessionStart = routerSource.indexOf("live_session :ops,", authorSessionStart)
const nextSessionStart = routerSource.indexOf("live_session :ops_admin", viewerSessionStart)
const authorSession = routerSource.slice(authorSessionStart, viewerSessionStart)
const viewerSession = routerSource.slice(viewerSessionStart, nextSessionStart)

assert.ok(authorSessionStart > routerSource.indexOf("pipe_through [:browser, :require_authenticated_scope]"))
assert.match(authorSession, /DashboardAuthorAuth, :require_dashboard_author/)
assert.match(authorSession, /OpsDashboardEditorLive/)
assert.match(authorSession, /:edit/)
assert.doesNotMatch(viewerSession, /DashboardAuthorAuth, :require_dashboard_author/)
assert.match(viewerSession, /OpsDashboardViewerLive/)
assert.match(viewerSession, /:show/)

const sha256 = (value) => createHash("sha256").update(value).digest("hex")
assert.equal(
  sha256(routerSource),
  "83cedada0ed49d4c06d4e2b81133fbc84db147b5608a281fa0fe1bb4f08edc03",
  "the authenticated viewer/author router contract must remain byte-unchanged",
)
assert.match(appJsSource, /hooks: \{\.\.\.Hooks, \.\.\.getHooks\(liveVueApp\)\}/)
assert.doesNotMatch(
  appJsSource,
  /\bdom:\s*\{|onBeforeElUpdated|grid-stack|ui-resizable-handle/,
  "app.js must retain the LiveVue registry without global dashboard DOM repair",
)

console.log("dashboard_panel_test passed")
