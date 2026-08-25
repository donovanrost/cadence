import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  announceCadencePopoverOpened,
  subscribeToLegacyOverlayOpen,
} from "../vue/ui/reka/popover_compatibility.js"

const scenarioLedger = Object.freeze([
  "one parent LiveVue host",
  "direct runtime context child",
  "direct runtime controls child",
  "direct canonical time picker child",
  "direct comparison toggle child",
  "direct editor actions child",
  "direct warning badge children",
  "direct action menu child",
  "no nested LiveVue roots",
  "time picker payload forwarding",
  "operational scope uses the shared bottom-start Reka popover",
  "data health uses the shared bottom-end Reka popover",
  "health panel retains nested WidgetWarning composition",
  "server-owned overlay ids data aria labels and menu roles remain exact",
  "health and menu navigation plus warning event payloads remain server authoritative",
  "toolbar overlays participate in one-open coordination",
  "handwritten toolbar controllers and global hooks are absent",
])
const coveredScenarios = []
const cover = (name, callback) => {
  assert.equal(name, scenarioLedger[coveredScenarios.length])
  callback()
  coveredScenarios.push(name)
}

assert.equal(process.versions.node, "24.16.0", "dashboard toolbar contracts use pinned Node 24.16.0")

const testDirectory = dirname(fileURLToPath(import.meta.url))
const toolbarPath = resolve(testDirectory, "../vue/DashboardToolbar.vue")
const menuPath = resolve(testDirectory, "../vue/DashboardToolbarMenu.vue")
const popoverPath = resolve(testDirectory, "../vue/ui/reka/CadencePopover.vue")
const serverPath = resolve(
  testDirectory,
  "../../lib/cadence_web/live/ops_dashboard_show_live/dashboard_toolbar_components.ex",
)
const warningPresenterPath = resolve(
  testDirectory,
  "../../lib/cadence_web/live/ops_dashboard_show_live/dashboard_toolbar_warning_presentation.ex",
)
const appPath = resolve(testDirectory, "../js/app.js")

const [source, menuSource, popoverSource, serverSource, warningPresenterSource, appSource] =
  await Promise.all([
    readFile(toolbarPath, "utf8"),
    readFile(menuPath, "utf8"),
    readFile(popoverPath, "utf8"),
    readFile(serverPath, "utf8"),
    readFile(warningPresenterPath, "utf8"),
    readFile(appPath, "utf8"),
  ])
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(template, "DashboardToolbar.vue must have a template block")

cover("one parent LiveVue host", () => {
  assert.equal((serverSource.match(/<\.vue/g) || []).length, 1)
  assert.equal((serverSource.match(/v-component="DashboardToolbar"/g) || []).length, 1)
})

cover("direct runtime context child", () => {
  assert.match(source, /import DashboardRuntimeContextSelector from "\.\/DashboardRuntimeContextSelector\.vue"/)
  assert.match(template, /<DashboardRuntimeContextSelector/)
})

cover("direct runtime controls child", () => {
  assert.match(source, /import DashboardRuntimeControls from "\.\/DashboardRuntimeControls\.vue"/)
  assert.match(template, /<DashboardRuntimeControls/)
})

cover("direct canonical time picker child", () => {
  assert.match(source, /import DashboardTimePicker from "\.\/DashboardTimePicker\.vue"/)
  assert.match(template, /<DashboardTimePicker/)
  assert.match(serverSource, /Map\.put\(:quick_query, assigns\.time_quick_query\)/)
  assert.match(serverSource, /Map\.put\(:recent_ranges, assigns\.time_recent_ranges\)/)
  assert.match(
    serverSource,
    /DashboardTimePickerComponents\.time_toolbar_presentation\(time_picker_assigns\)/,
  )
})

cover("direct comparison toggle child", () => {
  assert.match(source, /import DashboardComparisonToggle from "\.\/DashboardComparisonToggle\.vue"/)
  assert.match(template, /<DashboardComparisonToggle/)
})

cover("direct editor actions child", () => {
  assert.match(source, /import DashboardEditorActions from "\.\/DashboardEditorActions\.vue"/)
  assert.match(template, /<DashboardEditorActions/)
})

cover("direct warning badge children", () => {
  assert.match(source, /import WidgetWarning from "\.\/WidgetWarning\.vue"/)
  assert.match(template, /<WidgetWarning :presentation="warning"/)
  assert.match(serverSource, /DashboardToolbarWarningPresentation\.build\(/)
  assert.doesNotMatch(serverSource, /WidgetWarningComponents/)
})

cover("direct action menu child", () => {
  assert.match(source, /import DashboardToolbarMenu from "\.\/DashboardToolbarMenu\.vue"/)
  assert.match(template, /<DashboardToolbarMenu :presentation="props\.presentation\.menu"/)
})

cover("no nested LiveVue roots", () => {
  assert.doesNotMatch(source, /v-component|data-name|phx-hook|hooks\/overlay/)
  assert.doesNotMatch(menuSource, /v-component|data-name|phx-hook|hooks\/overlay/)
})

cover("time picker payload forwarding", () => {
  assert.match(template, /@recents-loaded="forwardRecentsLoaded"/)
  assert.match(template, /@select-range="forwardSelectRange"/)
  assert.match(serverSource, /v-on:recents-loaded=\{JS\.push\("time_recents_loaded"\)\}/)
  assert.match(serverSource, /v-on:select-range=\{JS\.push\("set_chart_time_range"\)\}/)
})

cover("operational scope uses the shared bottom-start Reka popover", () => {
  assert.match(source, /import CadencePopover from "\.\/ui\/reka\/CadencePopover\.vue"/)
  assert.equal(template.match(/<CadencePopover/g)?.length, 2)
  assert.match(
    source,
    /const identity = props\.presentation\.viewer\?\.operational_scope\.root\.attrs\.id/,
  )
  assert.match(
    source,
    /props\.presentation\.viewer\?\.operational_scope\.panel\.attrs \|\| \{\}/,
  )
  assert.match(
    template,
    /<CadencePopover[\s\S]*:identity="operationalScopeIdentity"[\s\S]*side="bottom"[\s\S]*align="start"[\s\S]*:collision-padding="16"[\s\S]*v-bind="props\.presentation\.viewer\.operational_scope\.root\.attrs"/,
  )
  assert.match(
    template,
    /v-bind="props\.presentation\.viewer\.operational_scope\.trigger\.attrs"[\s\S]*:aria-expanded="String\(open\)"/,
  )
  assert.match(template, /v-bind="operationalScopePanelAttrs"[\s\S]*:hidden="!open"/)
})

cover("data health uses the shared bottom-end Reka popover", () => {
  assert.match(source, /const identity = props\.presentation\.data_health\?\.root\.attrs\.id/)
  assert.match(source, /props\.presentation\.data_health\?\.panel\.attrs \|\| \{\}/)
  assert.match(
    template,
    /<CadencePopover[\s\S]*:identity="dataHealthIdentity"[\s\S]*side="bottom"[\s\S]*align="end"[\s\S]*:collision-padding="16"[\s\S]*v-bind="props\.presentation\.data_health\.root\.attrs"/,
  )
  assert.match(
    template,
    /v-bind="props\.presentation\.data_health\.trigger\.attrs"[\s\S]*:aria-expanded="String\(open\)"/,
  )
  assert.match(template, /v-bind="dataHealthPanelAttrs"[\s\S]*:hidden="!open"/)
})

cover("health panel retains nested WidgetWarning composition", () => {
  assert.match(
    template,
    /v-for="warning in props\.presentation\.data_health\.panel\.body\.warnings"[\s\S]*:key="warning\.component_id"[\s\S]*:id="warning\.component_id"[\s\S]*class="contents"[\s\S]*<WidgetWarning :presentation="warning"/,
  )
  assert.match(warningPresenterSource, /def build\(id, warning\)/)
  assert.match(warningPresenterSource, /EvidenceAttrs\.warning\(nil\)/)
})

cover("server-owned overlay ids data aria labels and menu roles remain exact", () => {
  const contracts = [
    'id: "dashboard-data-controls"',
    '"data-overlay-kind": "popover"',
    '"data-overlay-placement": "bottom-start"',
    '"data-dashboard-primary-control": "scope"',
    'id: "dashboard-data-controls-toggle"',
    '"aria-haspopup": "dialog"',
    '"aria-controls": "dashboard-data-controls-panel"',
    '"aria-label": "Dashboard operational scope"',
    'id: "dashboard-data-controls-panel"',
    'id: "dashboard-data-issues"',
    '"data-overlay-placement": "bottom-end"',
    '"data-dashboard-data-issue-count": Integer.to_string(assigns.data_issue_count)',
    '"data-dashboard-data-issue-status": to_string(assigns.data_issue_status)',
    '"data-dashboard-data-issue-codes": data_issue_codes(assigns.dashboard_warnings)',
    'id: "dashboard-data-issues-trigger"',
    '"aria-controls": "dashboard-data-issues-panel"',
    '"aria-label": "Dashboard data health"',
    'id: "dashboard-data-issues-panel"',
    'id: "dashboard-menu"',
    '"data-overlay-kind": "menu"',
    'id: "dashboard-menu-trigger"',
    '"aria-haspopup": "menu"',
    'id: "dashboard-menu-menu"',
    'role: "menu"',
  ]

  for (const contract of contracts) {
    assert.ok(serverSource.includes(contract), `missing server-owned toolbar contract: ${contract}`)
  }
})

cover("health and menu navigation plus warning event payloads remain server authoritative", () => {
  assert.match(template, /v-bind="props\.presentation\.data_health\.panel\.body\.action\.attrs"/)
  assert.match(
    template,
    /v-bind="props\.presentation\.data_health\.panel\.body\.diagnostics_action\.attrs"/,
  )
  assert.match(menuSource, /v-bind="item\.link\.attrs"/)
  assert.match(serverSource, /href: path/)
  assert.match(serverSource, /"data-phx-link": "redirect"/)
  assert.match(serverSource, /"data-phx-link-state": "push"/)
  assert.match(serverSource, /"data-dashboard-data-issue-action": action\.kind/)
  assert.match(warningPresenterSource, /"phx-click" => "open_evidence"/)
  assert.match(warningPresenterSource, /"phx-click" => "open_data_link"/)
  assert.match(warningPresenterSource, /"data-warning-link-target"/)
  assert.match(warningPresenterSource, /"data-warning-link-id"/)
  assert.match(warningPresenterSource, /"data-warning-link-ref"/)
})

cover("toolbar overlays participate in one-open coordination", () => {
  class FakeWindow extends EventTarget {
    CustomEvent = class extends Event {
      constructor(type, options) {
        super(type)
        this.detail = options.detail
      }
    }
  }

  const windowObject = new FakeWindow()
  const scopeRoot = {id: "dashboard-data-controls"}
  const healthRoot = {id: "dashboard-data-issues"}
  const menuRoot = {id: "dashboard-menu"}
  const open = {scope: true, health: true, menu: true}
  const removers = [
    subscribeToLegacyOverlayOpen(windowObject, scopeRoot, () => (open.scope = false)),
    subscribeToLegacyOverlayOpen(windowObject, healthRoot, () => (open.health = false)),
    subscribeToLegacyOverlayOpen(windowObject, menuRoot, () => (open.menu = false)),
  ]

  announceCadencePopoverOpened(windowObject, healthRoot)
  assert.deepEqual(open, {scope: false, health: true, menu: false})
  removers.forEach((remove) => remove())
})

cover("handwritten toolbar controllers and global hooks are absent", () => {
  assert.doesNotMatch(appSource, /hooks\/(?:overlay|resizable_panel)/)
  assert.doesNotMatch(appSource, /\b(?:Overlay|ResizablePanel)\b/)
  assert.doesNotMatch(
    source,
    /createDashboardToolbarPopoverController|addEventListener|removeEventListener|onBeforeUpdate|onUpdated/,
  )
  assert.doesNotMatch(
    menuSource,
    /createDashboardToolbarMenuController|addEventListener|removeEventListener|onBeforeUpdate|onUpdated/,
  )
  assert.match(popoverSource, /PopoverContent, PopoverRoot, PopoverTrigger/)
  assert.match(popoverSource, /subscribeToLegacyOverlayOpen/)
  assert.match(popoverSource, /announceCadencePopoverOpened/)
})

assert.deepEqual(coveredScenarios, scenarioLedger)
console.log(`dashboard_toolbar_test passed (${scenarioLedger.length} scenarios)`)
