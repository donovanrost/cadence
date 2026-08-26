import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const scenarioLedger = [
  "Components.widget exposes one non-SSR DashboardWidget host with a JSON-safe presentation",
  "DashboardWidget directly composes the established header point row chart and related children",
  "all seven widget body variants retain their Phoenix-selected root and content contracts",
  "regular and lifecycle notices retain text structure classes state and actionable dispatches",
  "point row and chart component identities remain stable without nested Phoenix Vue hosts",
  "the parent composition selects exactly one point or row child and preserves empty bodies",
  "global hooks are absent while the child header delegates overlay lifecycle and protocol ownership",
]

assert.equal(scenarioLedger.length, 7)

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/DashboardWidget.vue")
const headerPath = resolve(__dirname, "../vue/DashboardWidgetHeader.vue")
const pointPath = resolve(__dirname, "../vue/WidgetPoint.vue")
const rowsPath = resolve(__dirname, "../vue/WidgetRows.vue")
const componentsPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/components.ex",
)
const pointComponentsPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/widget_point_components.ex",
)
const rowComponentsPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/widget_row_components.ex",
)
const appPath = resolve(__dirname, "../js/app.js")
const popoverPath = resolve(__dirname, "../vue/ui/reka/CadencePopover.vue")
const popoverCompatibilityPath = resolve(
  __dirname,
  "../vue/ui/reka/popover_compatibility.js",
)

const [
  source,
  headerSource,
  pointSource,
  rowsSource,
  componentsSource,
  pointPhoenix,
  rowPhoenix,
  appSource,
  popoverSource,
  popoverCompatibilitySource,
] = await Promise.all([
    readFile(componentPath, "utf8"),
    readFile(headerPath, "utf8"),
    readFile(pointPath, "utf8"),
    readFile(rowsPath, "utf8"),
    readFile(componentsPath, "utf8"),
    readFile(pointComponentsPath, "utf8"),
    readFile(rowComponentsPath, "utf8"),
    readFile(appPath, "utf8"),
    readFile(popoverPath, "utf8"),
    readFile(popoverCompatibilityPath, "utf8"),
  ])

const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const hostSource = componentsSource.match(
  /def widget\(assigns\) do[\s\S]*?def widget_presentation\(assigns\) do/,
)?.[0]

assert.ok(template, "DashboardWidget.vue must expose an auditable template")
assert.ok(hostSource, "Components.widget/1 must expose an auditable parent host")
assert.equal(hostSource.match(/<\.vue/g)?.length, 1)
assert.match(hostSource, /v-component="DashboardWidget"/)
assert.match(hostSource, /presentation=\{@presentation\}/)
assert.match(hostSource, /v-ssr=\{false\}/)
assert.match(hostSource, /class="contents"/)
assert.doesNotMatch(hostSource, /<\.widget_header|<\.widget_body|DashboardWidgetHeader|WidgetPoint|WidgetRows/)

assert.match(source, /import DashboardWidgetHeader from "\.\/DashboardWidgetHeader\.vue"/)
assert.match(source, /import WidgetPoint from "\.\/WidgetPoint\.vue"/)
assert.match(source, /import WidgetRows from "\.\/WidgetRows\.vue"/)
assert.match(template, /<DashboardWidgetHeader :presentation="composition\.header" \/>/)
assert.match(template, /<WidgetPoint :presentation="composition\.point" \/>/)
assert.match(template, /<WidgetRows :presentation="composition\.rows" \/>/)
assert.match(template, /:id="composition\.header\.component_id"/)
assert.match(template, /:id="composition\.point\.component_id"/)
assert.match(template, /:id="composition\.rows\.component_id"/)
assert.match(pointSource, /import TelemetryChart from "\.\/TelemetryChart\.vue"/)
assert.match(pointSource, /<TelemetryChart v-bind="presentation\.chart\.props" \/>/)
assert.match(rowsSource, /import WidgetDataLinks from "\.\/WidgetDataLinks\.vue"/)

for (const kind of [
  "value_tile",
  "time_series",
  "status_matrix",
  "data_table",
  "state_timeline",
  "event_timeline",
  "constellation_health",
]) {
  assert.match(
    componentsSource,
    new RegExp(`defp widget_body_presentation\\(%\\{widget: %\\{type: :${kind}\\}\\}`),
    `${kind} must remain a Phoenix-selected body variant`,
  )
}

assert.match(componentsSource, /"flex-1 min-h-0 p-2 flex flex-col justify-center overflow-hidden"/)
assert.match(componentsSource, /"cadence-time-series-panel-body"/)
assert.match(componentsSource, /Map\.put\(engine_backed_attrs\(assigns\.data\), "data-status-matrix", ""\)/)
assert.match(componentsSource, /Map\.put\(engine_backed_attrs\(assigns\.data\), "data-data-table", ""\)/)
assert.match(componentsSource, /Map\.put\(engine_backed_attrs\(assigns\.data\), "data-state-timeline", ""\)/)
assert.match(componentsSource, /Map\.put\(engine_backed_attrs\(assigns\.data\), "data-event-timeline", ""\)/)
assert.match(componentsSource, /"flex-1 min-h-0 p-2 overflow-y-auto"/)

assert.match(componentsSource, /kind: "notice"/)
assert.match(componentsSource, /kind: "lifecycle"/)
assert.match(template, /props\.presentation\.body\.notice\.kind === 'lifecycle'/)
assert.match(template, /v-for="action in props\.presentation\.body\.notice\.actions"/)
assert.match(componentsSource, /dispatch_click\("#dashboard-data-controls-toggle"\)/)
assert.match(componentsSource, /dispatch_click\("#dashboard-menu-trigger"\)/)
assert.match(componentsSource, /JS\.dispatch\(to: target\)/)
assert.match(componentsSource, /Jason\.encode!\(\)/)

assert.match(pointPhoenix, /def value_tile_presentation\(assigns\)/)
assert.match(pointPhoenix, /def time_series_presentation\(assigns\)/)
assert.match(pointPhoenix, /def constellation_health_presentation\(assigns\)/)
assert.match(rowPhoenix, /def status_matrix_presentation\(data, widget, placement_id\)/)
assert.match(rowPhoenix, /def data_table_presentation\(data, widget, placement_id\)/)
assert.match(rowPhoenix, /def state_timeline_presentation\(data, placement_id\)/)
assert.match(rowPhoenix, /def event_timeline_presentation\(data, placement_id\)/)

const compositionStart = "// DASHBOARD_WIDGET_COMPOSITION_START"
const compositionEnd = "// DASHBOARD_WIDGET_COMPOSITION_END"
const start = source.indexOf(compositionStart)
const end = source.indexOf(compositionEnd)
assert.ok(start >= 0 && end > start, "DashboardWidget must expose its composition behavior")

const compositionSource = source
  .slice(start + compositionStart.length, end)
  .replace(": DashboardWidgetPresentation", "")
const context = {}
vm.createContext(context)
vm.runInContext(
  `${compositionSource}\nglobalThis.dashboardWidgetComposition = dashboardWidgetComposition`,
  context,
  {filename: componentPath},
)

const compose = context.dashboardWidgetComposition
assert.equal(typeof compose, "function")

const header = {component_id: "dashboard-widget-header-placement-1-component"}
const point = {component_id: "widget-point-placement-1-component", kind: "value_tile"}
const rows = {component_id: "widget-rows-data-table-placement-1-component", kind: "data_table"}
const presentation = (content) => ({
  component_id: "dashboard-widget-placement-1-component",
  header,
  body: {kind: "data_table", root: {class: "body", attrs: {}}, notice: null, content},
})

const pointComposition = compose(presentation({component: "WidgetPoint", presentation: point}))
assert.deepEqual(JSON.parse(JSON.stringify(pointComposition)), {header, point, rows: null})

const rowComposition = compose(presentation({component: "WidgetRows", presentation: rows}))
assert.deepEqual(JSON.parse(JSON.stringify(rowComposition)), {header, point: null, rows})

const emptyComposition = compose(presentation(null))
assert.deepEqual(JSON.parse(JSON.stringify(emptyComposition)), {header, point: null, rows: null})

assert.doesNotMatch(appSource, /hooks\/(?:overlay|resizable_panel)/)
assert.doesNotMatch(appSource, /\b(?:Overlay|ResizablePanel)\b/)
assert.doesNotMatch(appSource, /DashboardWidget/)
assert.match(headerSource, /import CadencePopover from "\.\/ui\/reka\/CadencePopover\.vue"/)
assert.equal(headerSource.match(/<CadencePopover\b/g)?.length, 1)
assert.doesNotMatch(
  headerSource,
  /DASHBOARD_WIDGET_HEADER_CONTROLLER|onMounted|onBeforeUpdate|onUpdated|onBeforeUnmount/,
)
assert.doesNotMatch(
  headerSource,
  /cadence:overlay-opened|announceCadencePopoverOpened|subscribeToLegacyOverlayOpen/,
)
assert.match(popoverSource, /onMounted\(\(\) => \{[\s\S]*subscribeToLegacyOverlayOpen/)
assert.match(
  popoverSource,
  /onBeforeUnmount\(\(\) => \{[\s\S]*removeLegacyOverlayListener\?\.\(\)/,
)
assert.match(
  popoverSource,
  /preservesPopoverOpenState\(open\.value, previousIdentity, nextIdentity\)/,
)
assert.match(
  popoverCompatibilitySource,
  /export const CADENCE_OVERLAY_OPENED_EVENT = "cadence:overlay-opened"/,
)
assert.match(
  popoverCompatibilitySource,
  /new windowObject\.CustomEvent\(CADENCE_OVERLAY_OPENED_EVENT/,
)
assert.match(
  popoverCompatibilitySource,
  /windowObject\.addEventListener\(CADENCE_OVERLAY_OPENED_EVENT, onOverlayOpened\)/,
)
assert.match(
  popoverCompatibilitySource,
  /windowObject\.removeEventListener\(CADENCE_OVERLAY_OPENED_EVENT, onOverlayOpened\)/,
)

console.log("dashboard_widget_test passed")
