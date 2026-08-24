import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const nodeScenarioLedger = [
  "one non-SSR parent host directly composes WidgetWarning children",
  "the established warning strip root label fallback and HUD classes stay presentation-driven",
  "warning order and stable child host ids pass through without client normalization",
  "WidgetWarning receives the original overlay evidence and data-link event attributes",
  "the global hook is absent while WidgetWarning retains its local overlay lifecycle and protocol",
]

assert.equal(process.versions.node, "24.16.0", "dashboard warning contracts use pinned Node 24.16.0")
assert.equal(nodeScenarioLedger.length, 5)

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/DashboardWarnings.vue")
const widgetWarningPath = resolve(__dirname, "../vue/WidgetWarning.vue")
const componentsPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/components.ex",
)
const appPath = resolve(__dirname, "../js/app.js")
const viewportSmokePath = resolve(__dirname, "dashboard_viewport_smoke.mjs")

const [
  source,
  widgetWarningSource,
  componentsSource,
  appSource,
  viewportSmokeSource,
] = await Promise.all([
  readFile(componentPath, "utf8"),
  readFile(widgetWarningPath, "utf8"),
  readFile(componentsPath, "utf8"),
  readFile(appPath, "utf8"),
  readFile(viewportSmokePath, "utf8"),
])

const script = source.match(/<script setup>\n([\s\S]*?)\n<\/script>/)?.[1]
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const hostStart = componentsSource.indexOf("  def dashboard_warnings(assigns) do")
const hostEnd = componentsSource.indexOf("  attr :health, :map, required: true", hostStart)
const hostSource = componentsSource.slice(hostStart, hostEnd)

assert.ok(script, "DashboardWarnings.vue must have a script setup block")
assert.ok(template, "DashboardWarnings.vue must have a template block")
assert.ok(hostStart >= 0 && hostEnd > hostStart, "dashboard_warnings/1 must remain auditable")

assert.match(script, /import WidgetWarning from "\.\/WidgetWarning\.vue"/)
assert.match(script, /presentation: \{type: Object, required: true\}/)
assert.match(template, /:id="props\.presentation\.root\.id"/)
assert.match(template, /:class="props\.presentation\.root\.class"/)
assert.match(template, /v-bind="props\.presentation\.root\.attrs"/)
assert.match(template, /\{\{ props\.presentation\.label\.text \}\}/)
assert.match(template, /v-if="props\.presentation\.fallback\.visible"/)
assert.match(template, /\{\{ props\.presentation\.fallback\.text \}\}/)
assert.match(template, /v-for="warning in props\.presentation\.warnings"/)
assert.match(template, /:id="warning\.component_id"/)
assert.match(template, /:key="warning\.component_id"/)
assert.match(template, /:key="warning\.component_id"[\s\S]*?class="contents"/)
assert.match(template, /<WidgetWarning :presentation="warning" \/>/)
assert.equal(template.match(/<WidgetWarning/g)?.length, 1)
assert.doesNotMatch(source, /v-component|data-name=|phx-hook|<\.vue/)
assert.doesNotMatch(script, /\.sort\(|\.reverse\(|\.filter\(|severity|code_text/)

const labelIndex = template.indexOf("props.presentation.label.text")
const fallbackIndex = template.indexOf("props.presentation.fallback.text")
const warningsIndex = template.indexOf("v-for=\"warning in props.presentation.warnings\"")
assert.ok(labelIndex >= 0 && labelIndex < fallbackIndex && fallbackIndex < warningsIndex)

assert.match(hostSource, /id="dashboard-engine-warnings-component"/)
assert.match(hostSource, /v-component="DashboardWarnings"/)
assert.match(hostSource, /presentation=\{@presentation\}/)
assert.match(hostSource, /v-ssr=\{false\}/)
assert.match(hostSource, /class="contents"/)
assert.equal(hostSource.match(/<\.vue/g)?.length, 1)
assert.doesNotMatch(hostSource, /engine_warning_badge/)
assert.match(hostSource, /defp dashboard_warnings_presentation\(\[\], false\), do: nil/)
assert.match(hostSource, /id: "dashboard-engine-warnings"/)
assert.match(hostSource, /"data-engine-degraded" => if\(degraded\?, do: "true", else: "false"\)/)
assert.match(hostSource, /"data-warning-codes" => WidgetWarningComponents\.warning_codes\(warnings\)/)
assert.match(hostSource, /text: "Dashboard degraded"/)
assert.match(hostSource, /text: "One or more sources returned degraded data\."/)
assert.match(hostSource, /warnings == \[\]/)
assert.match(hostSource, /Enum\.with_index\(\)/)
assert.match(hostSource, /WidgetWarningComponents\.warning_presentation\(/)
assert.match(hostSource, /"dashboard-engine-warning-#\{index\}"/)

assert.match(widgetWarningSource, /v-bind="presentation\.overlay\.attrs"/)
assert.match(widgetWarningSource, /v-bind="presentation\.body\.evidence_button\.attrs"/)
assert.match(widgetWarningSource, /v-bind="row\.attrs"/)
assert.doesNotMatch(appSource, /hooks\/(?:overlay|resizable_panel)/)
assert.doesNotMatch(appSource, /\b(?:Overlay|ResizablePanel)\b/)
assert.match(widgetWarningSource, /onMounted\(/)
assert.match(widgetWarningSource, /onBeforeUpdate\(/)
assert.match(widgetWarningSource, /onUpdated\(/)
assert.match(widgetWarningSource, /onBeforeUnmount\(/)
assert.match(widgetWarningSource, /new windowObject\.CustomEvent\("cadence:overlay-opened"/)
assert.match(widgetWarningSource, /windowObject\.addEventListener\("cadence:overlay-opened"/)
assert.match(widgetWarningSource, /windowObject\.removeEventListener\("cadence:overlay-opened"/)
assert.doesNotMatch(appSource, /DashboardWarnings|WidgetWarning/)
assert.match(viewportSmokeSource, /document\.querySelectorAll\("\[data-engine-warning\]"\)/)
assert.match(
  viewportSmokeSource,
  /warning\.closest\("\[data-engine-warning-detail\]"\)/,
)
assert.match(
  viewportSmokeSource,
  /document\.querySelector\("\[data-engine-warning='unsupported_observable_scope'\]"\)/,
)

const evidenceAttrs = {
  "data-warning-evidence-open": "",
  "phx-click": "open_evidence",
  "phx-value-kind": "warning",
  "phx-value-warning-code": "first_warning",
}
const linkAttrs = {
  "phx-click": "open_data_link",
  "phx-value-link-id": "link-1",
  "phx-value-target": "source",
  "phx-value-target-id": "source-1",
}
const firstWarning = {
  component_id: "dashboard-engine-warning-0-component",
  overlay: {id: "dashboard-engine-warning-0"},
  body: {evidence_button: {attrs: evidenceAttrs}, links: {rows: [{attrs: linkAttrs}]}},
}
const secondWarning = {
  component_id: "dashboard-engine-warning-1-component",
  overlay: {id: "dashboard-engine-warning-1"},
  body: {evidence_button: {attrs: {}}, links: {rows: []}},
}
const presentation = {
  root: {
    id: "dashboard-engine-warnings",
    class:
      "shrink-0 flex items-center gap-2 px-2 py-1 border-b border-warning/30 bg-warning/10 text-xs",
    attrs: {"data-engine-degraded": "true", "data-warning-codes": "first_warning,second_warning"},
  },
  label: {class: "font-semibold text-warning", text: "Dashboard degraded"},
  fallback: {
    visible: false,
    class: "text-base-content/70",
    text: "One or more sources returned degraded data.",
  },
  warnings: [firstWarning, secondWarning],
}
const componentProps = {presentation}
const context = {
  WidgetWarning: {},
  defineProps(definition) {
    assert.equal(definition.presentation.type.name, "Object")
    assert.equal(definition.presentation.required, true)
    return componentProps
  },
}

const testableScript =
  script.replace(
    'import WidgetWarning from "./WidgetWarning.vue"',
    "const WidgetWarning = globalThis.WidgetWarning",
  ) + "\nglobalThis.dashboardWarningsProps = props"

vm.createContext(context)
vm.runInContext(testableScript, context, {filename: componentPath})

assert.equal(context.dashboardWarningsProps.presentation, presentation)
assert.deepEqual(
  Array.from(context.dashboardWarningsProps.presentation.warnings, (warning) => warning.component_id),
  ["dashboard-engine-warning-0-component", "dashboard-engine-warning-1-component"],
)
assert.equal(context.dashboardWarningsProps.presentation.fallback.visible, false)
assert.equal(
  context.dashboardWarningsProps.presentation.warnings[0].body.evidence_button.attrs,
  evidenceAttrs,
)
assert.equal(context.dashboardWarningsProps.presentation.warnings[0].body.links.rows[0].attrs, linkAttrs)

componentProps.presentation = {
  ...presentation,
  fallback: {...presentation.fallback, visible: true},
  warnings: [secondWarning, firstWarning],
}

assert.equal(context.dashboardWarningsProps.presentation.fallback.visible, true)
assert.deepEqual(
  Array.from(context.dashboardWarningsProps.presentation.warnings, (warning) => warning.component_id),
  ["dashboard-engine-warning-1-component", "dashboard-engine-warning-0-component"],
)

console.log("dashboard_warnings_test passed")
