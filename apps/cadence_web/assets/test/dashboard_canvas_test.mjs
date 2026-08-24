import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const scenarioLedger = [
  "Controller exposes one non-SSR DashboardCanvas host with one presentation prop",
  "DashboardCanvas directly composes DashboardWidget DashboardGrid and DashboardComparisonInspector",
  "outer flex content and optional inspector remain siblings",
  "section and unsectioned groups preserve grid-before-controller topology",
  "GridStack items remain direct grid children with exact controller props",
  "every DashboardGrid layout event is re-emitted by DashboardCanvas",
  "Phoenix maps the parent layout event to layout_changed",
  "empty editor viewer and absent branches remain server-presented",
  "raw attrs preserve omission empty-string and stringification semantics",
  "comparison presentation reuses the existing narrow Phoenix builder",
  "authenticated viewer and author router sessions stay unchanged",
  "existing child component sources stay byte-for-byte unchanged",
]

assert.equal(scenarioLedger.length, 12)

const __dirname = dirname(fileURLToPath(import.meta.url))
const vueRoot = resolve(__dirname, "../vue")
const liveRoot = resolve(__dirname, "../../lib/cadence_web/live/ops_dashboard_show_live")
const routerPath = resolve(__dirname, "../../lib/cadence_web/router.ex")

const paths = {
  canvas: resolve(vueRoot, "DashboardCanvas.vue"),
  widget: resolve(vueRoot, "DashboardWidget.vue"),
  grid: resolve(vueRoot, "DashboardGrid.vue"),
  inspector: resolve(vueRoot, "DashboardComparisonInspector.vue"),
  controller: `${liveRoot}.ex`,
  presentation: resolve(liveRoot, "dashboard_canvas_presentation.ex"),
  comparisonInspector: resolve(liveRoot, "comparison_inspector_components.ex"),
  comparisonRollup: resolve(liveRoot, "comparison_rollup_components.ex"),
  router: routerPath,
}

const entries = await Promise.all(
  Object.entries(paths).map(async ([key, path]) => [key, await readFile(path, "utf8")]),
)
const source = Object.fromEntries(entries)
const template = source.canvas.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const renderSource = source.controller.match(/def render\(assigns\) do[\s\S]*?\n  end\nend\s*$/)?.[0]

assert.ok(template, "DashboardCanvas.vue must expose an auditable template")
assert.ok(renderSource, "Controller.render/1 must expose an auditable host")
assert.equal(renderSource.match(/<\.vue/g)?.length, 2)
assert.equal(renderSource.match(/v-component="DashboardCanvas"/g)?.length, 1)
assert.match(renderSource, /v-component="DashboardEditorGuard"/)
assert.match(renderSource, /id="dashboard-canvas-component"/)
assert.match(renderSource, /v-component="DashboardCanvas"/)
assert.match(renderSource, /presentation=\{@canvas_presentation\}/)
assert.match(renderSource, /v-on:layout_changed=\{JS\.push\("layout_changed"\)\}/)
assert.match(renderSource, /v-ssr=\{false\}/)
assert.match(renderSource, /class="contents"/)
assert.doesNotMatch(renderSource, /v-component="Dashboard(Grid|Widget|ComparisonInspector)"/)

for (const component of ["DashboardWidget", "DashboardGrid", "DashboardComparisonInspector"]) {
  assert.match(source.canvas, new RegExp(`import ${component} from "\\./${component}\\.vue"`))
  assert.match(template, new RegExp(`<${component}\\b`))
}

assert.match(template, /^  <div v-bind="presentation\.root\.attrs">/)
assert.match(template, /<div v-bind="presentation\.content\.attrs">/)
assert.match(
  template,
  /<div\n      v-if="presentation\.comparison_inspector"\n      v-bind="presentation\.comparison_inspector\.host\.attrs"[\s\S]*?:presentation="presentation\.comparison_inspector\.presentation"/,
)
assert.match(template, /<details v-if="group\.section" v-bind="group\.section\.root\.attrs">/)
assert.match(template, /<summary v-bind="group\.section\.summary\.attrs">/)
assert.match(template, /<header v-if="group\.header" v-bind="group\.header\.attrs">/)

const gridRoots = [...template.matchAll(/<div v-bind="group\.grid\.root\.attrs">/g)]
const gridControllers = [...template.matchAll(/<DashboardGrid\b/g)]
assert.equal(gridRoots.length, 2, "section and unsectioned branches each render one target grid")
assert.equal(gridControllers.length, 2, "section and unsectioned branches each compose one controller")
for (let index = 0; index < 2; index += 1) {
  assert.ok(gridRoots[index].index < gridControllers[index].index, "target grid must precede its controller")
}

assert.equal(template.match(/v-for="widget in group\.grid\.widgets"/g)?.length, 2)
assert.equal(template.match(/v-bind="widget\.shell\.attrs"/g)?.length, 2)
assert.equal(template.match(/<DashboardWidget :presentation="widget\.presentation" \/>/g)?.length, 2)
assert.equal(template.match(/:target_id="group\.grid\.controller\.props\.target_id"/g)?.length, 2)
assert.equal(template.match(/:edit_mode="group\.grid\.controller\.props\.edit_mode"/g)?.length, 2)
assert.equal(template.match(/:item_ids="group\.grid\.controller\.props\.item_ids"/g)?.length, 2)
assert.equal(template.match(/@layout_changed="forwardLayoutChanged"/g)?.length, 2)
assert.match(source.canvas, /const emit = defineEmits\(\["layout_changed"\]\)/)
assert.match(source.canvas, /emit\("layout_changed", payload\)/)

assert.match(source.presentation, /"class" => "flex flex-1 min-h-0"/)
assert.match(source.presentation, /"id" => "dashboard-widget-group-#\{group_id\}"/)
assert.match(source.presentation, /"id" => "dashboard-section-group-#\{group_id\}"/)
assert.match(source.presentation, /"data-dashboard-widget-group" => group_id/)
assert.match(source.presentation, /"data-dashboard-section" => group_id/)
assert.match(source.presentation, /defp widget_count_text\(1\), do: "1 widget"/)
assert.match(source.presentation, /defp widget_count_text\(count\), do: "#\{count\} widgets"/)
assert.match(source.presentation, /"dashboard-editor-empty-add-widget"/)
assert.match(source.presentation, /"dashboard-viewer-empty-edit"/)
assert.match(source.presentation, /"Open Dashboard Editor"/)
assert.match(source.presentation, /"id" => "dashboard-comparison-inspector-component"/)
assert.match(source.presentation, /rendered when value in \[nil, false\]/)
assert.match(source.presentation, /Map\.put\(rendered, to_string\(key\), ""\)/)
assert.match(source.presentation, /Map\.put\(rendered, to_string\(key\), rendered_string\(value\)\)/)

assert.match(source.presentation, /&ComparisonInspectorComponents\.presentation\/5/)
assert.match(source.comparisonInspector, /def presentation\(true, rollup, preset, open_review_summary, saved_presets\)/)
assert.match(source.comparisonInspector, /ComparisonRollupComponents\.presentation\(%\{/)
assert.match(source.comparisonRollup, /def presentation\(assigns\) when is_map\(assigns\)/)

assert.match(source.router, /scope "\/", CadenceWeb do\n    pipe_through \[:browser, :require_authenticated_scope\]/)
const authorStart = source.router.indexOf("live_session :ops_dashboard_author")
const viewerStart = source.router.indexOf("live_session :ops,", authorStart)
assert.ok(authorStart >= 0 && viewerStart > authorStart)
assert.match(
  source.router.slice(authorStart, viewerStart),
  /live "\/missions\/:mission_id\/ops\/dashboards\/:dashboard_id\/edit",\n           OpsDashboardEditorLive,\n           :edit/,
)
assert.match(
  source.router.slice(viewerStart),
  /live "\/missions\/:mission_id\/ops\/dashboards\/:dashboard_id",\n           OpsDashboardViewerLive,\n           :show/,
)

const sha256 = (value) => createHash("sha256").update(value).digest("hex")
assert.equal(sha256(source.widget), "a643f2e4a4348b821f2d0c54e2fea18b22383097b624f4c9ad5f718aad0625de")
assert.equal(sha256(source.grid), "b0c49435a148f81d5e569a6513187a4846c82d7c9af16b48e442f7791dae43b3")
assert.equal(sha256(source.inspector), "81f389567edd64256254aab2d8f18d2f4eff7d9251dd61777f7b15ad931112cd")

assert.doesNotMatch(source.canvas, /phx-hook|localStorage|<script(?! setup)/)

console.log("dashboard_canvas_test passed")
