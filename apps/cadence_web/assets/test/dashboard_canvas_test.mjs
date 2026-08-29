import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const scenarioLedger = [
  "Controller exposes one non-SSR DashboardCanvas host with one presentation prop",
  "DashboardCanvas composes the real collapsible adapters DashboardGrid and DashboardComparisonInspector",
  "outer flex content and optional inspector remain siblings",
  "reactive dashboard section disclosure state survives complete prop replacement by stable group key",
  "section and unsectioned groups use the same Vue-owned grid subtree",
  "GridStack items remain direct grid children with exact controller props",
  "every DashboardGrid layout event is re-emitted by DashboardCanvas",
  "Phoenix maps the parent layout event to layout_changed",
  "empty editor viewer and absent branches remain server-presented",
  "raw attrs preserve omission empty-string and stringification semantics",
  "authenticated viewer and author router sessions stay unchanged",
  "the global morphdom callback is retired while unrelated child sources remain unchanged",
]

assert.equal(scenarioLedger.length, 12)

const __dirname = dirname(fileURLToPath(import.meta.url))
const vueRoot = resolve(__dirname, "../vue")
const liveRoot = resolve(__dirname, "../../lib/cadence_web/live/ops_dashboard_show_live")
const routerPath = resolve(__dirname, "../../lib/cadence_web/router.ex")

const paths = {
  app: resolve(__dirname, "../js/app.js"),
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
const canvasScript = source.canvas.match(/<script setup>\n([\s\S]*?)\n<\/script>/)?.[1]
const template = source.canvas.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const gridTemplate = source.grid.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const renderSource = source.controller.match(/def render\(assigns\) do[\s\S]*?\n  end\nend\s*$/)?.[0]

assert.ok(canvasScript, "DashboardCanvas.vue must expose auditable section state")
assert.ok(template, "DashboardCanvas.vue must expose an auditable template")
assert.ok(gridTemplate, "DashboardGrid.vue must expose an auditable owned grid subtree")
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

for (const component of ["DashboardGrid", "DashboardComparisonInspector"]) {
  assert.match(source.canvas, new RegExp(`import ${component} from "\\./${component}\\.vue"`))
  assert.match(template, new RegExp(`<${component}\\b`))
}
for (const component of [
  "CadenceCollapsible",
  "CadenceCollapsibleContent",
  "CadenceCollapsibleTrigger",
]) {
  assert.match(
    source.canvas,
    new RegExp(`import ${component} from "\\./ui/reka/${component}\\.vue"`),
  )
  assert.match(template, new RegExp(`<${component}\\b`))
}
assert.doesNotMatch(source.canvas, /import DashboardWidget/)
assert.match(source.grid, /import DashboardWidget from "\.\/DashboardWidget\.vue"/)
assert.match(gridTemplate, /<DashboardWidget :presentation="widget\.presentation" \/>/)

assert.match(template, /^  <div v-bind="presentation\.root\.attrs">/)
assert.match(template, /<div v-bind="presentation\.content\.attrs">/)
assert.match(
  template,
  /<div\n      v-if="presentation\.comparison_inspector"\n      v-bind="presentation\.comparison_inspector\.host\.attrs"[\s\S]*?:presentation="presentation\.comparison_inspector\.presentation"/,
)
assert.match(
  template,
  /<CadenceCollapsible\n          v-if="group\.section"\n          :content-id="sectionContentId\(group\)"\n          :open="sectionOpen\(group\)"\n          :unmount-on-hide="false"\n          @request-change="rememberSectionOpen\(group, \$event\)"/,
)
assert.match(template, /<div v-bind="sectionRootAttrs\(group\)">/)
assert.match(
  template,
  /<CadenceCollapsibleTrigger>\n              <button type="button" v-bind="group\.section\.summary\.attrs">/,
)
assert.match(
  template,
  /<CadenceCollapsibleContent>\n              <div class="contents">[\s\S]*?:section-open="sectionOpen\(group\)"/,
)
assert.doesNotMatch(template, /<details(?:\s|>)|<summary(?:\s|>)/)
assert.match(template, /<header v-if="group\.header" v-bind="group\.header\.attrs">/)

const gridControllers = [...template.matchAll(/<DashboardGrid\b/g)]
assert.equal(gridControllers.length, 2, "section and unsectioned branches each compose one controller")
assert.equal(template.match(/:presentation="group\.grid"/g)?.length, 2)
assert.equal(template.match(/@layout_changed="forwardLayoutChanged"/g)?.length, 2)
assert.equal(template.match(/:section-open="sectionOpen\(group\)"/g)?.length, 1)
assert.match(source.canvas, /const emit = defineEmits\(\["layout_changed"\]\)/)
assert.match(source.canvas, /emit\("layout_changed", payload\)/)
assert.match(source.canvas, /const sectionOpenByKey = reactive\(new Map\(\)\)/)
assert.doesNotMatch(source.canvas, /@toggle|currentTarget\.open/)

assert.match(gridTemplate, /^  <div ref="gridElement" v-bind="props\.presentation\.root\.attrs">/)
assert.match(gridTemplate, /v-for="widget in props\.presentation\.widgets"/)
assert.match(gridTemplate, /:key="widget\.key"/)
assert.match(gridTemplate, /v-bind="widget\.shell\.attrs"/)
assert.match(gridTemplate, /v-bind="widget\.content\.attrs"/)
assert.match(gridTemplate, /v-bind="widget\.host\.attrs"/)
assert.match(gridTemplate, /<div v-bind="props\.presentation\.controller\.host\.attrs">/)
assert.match(
  gridTemplate,
  /:data-dashboard-grid-target="props\.presentation\.controller\.props\.target_id"/,
)
assert.match(
  gridTemplate,
  /:data-edit-mode="String\(props\.presentation\.controller\.props\.edit_mode\)"/,
)
assert.match(
  gridTemplate,
  /:data-dashboard-grid-item-count="String\(props\.presentation\.controller\.props\.item_ids\.length\)"/,
)
assert.ok(
  gridTemplate.indexOf('ref="gridElement"') <
    gridTemplate.indexOf('v-bind="props.presentation.controller.host.attrs"'),
  "target grid must precede its controller marker",
)

const canvasContext = {
  reactive: (value) => value,
  defineProps() {},
  defineEmits() {
    return () => {}
  },
}
vm.createContext(canvasContext)
vm.runInContext(
  canvasScript.replace(/^import .*$/gm, "") +
    "\nglobalThis.DashboardCanvasTest = {sectionOpen, rememberSectionOpen, sectionContentId, sectionRootAttrs}",
  canvasContext,
)
const defaultOpenGroup = {key: "power", section: {root: {attrs: {open: ""}}}}
const defaultClosedGroup = {key: "comms", section: {root: {attrs: {}}}}
assert.equal(canvasContext.DashboardCanvasTest.sectionOpen(defaultOpenGroup), true)
assert.equal(canvasContext.DashboardCanvasTest.sectionOpen(defaultClosedGroup), false)
canvasContext.DashboardCanvasTest.rememberSectionOpen(defaultOpenGroup, false)
assert.equal(canvasContext.DashboardCanvasTest.sectionOpen(defaultOpenGroup), false)
assert.equal(
  canvasContext.DashboardCanvasTest.sectionOpen({
    key: "power",
    section: {root: {attrs: {open: ""}}},
  }),
  false,
)
const replacementPower = {
  key: "power-replacement",
  section: {
    root: {
      attrs: {
        id: "dashboard-section-group-power-replacement",
        class: "group/dashboard-section",
        "data-dashboard-section": "power-replacement",
        open: "",
      },
    },
  },
}
assert.equal(canvasContext.DashboardCanvasTest.sectionOpen(replacementPower), true)
assert.equal(
  canvasContext.DashboardCanvasTest.sectionContentId(replacementPower),
  "dashboard-section-group-power-replacement-content",
)
assert.deepEqual(
  JSON.parse(JSON.stringify(canvasContext.DashboardCanvasTest.sectionRootAttrs(replacementPower))),
  {
    id: "dashboard-section-group-power-replacement",
    class: "group/dashboard-section",
    "data-dashboard-section": "power-replacement",
  },
)

assert.match(source.app, /hooks: \{\.\.\.Hooks, \.\.\.getHooks\(liveVueApp\)\}/)
assert.doesNotMatch(source.app, /\bdom:\s*\{|onBeforeElUpdated|grid-stack|ui-resizable-handle/)

assert.match(source.presentation, /"class" => "flex flex-1 min-h-0"/)
assert.match(source.presentation, /"id" => "dashboard-widget-group-#\{group_id\}"/)
assert.match(source.presentation, /"id" => "dashboard-section-group-#\{group_id\}"/)
assert.match(source.presentation, /"data-dashboard-widget-group" => group_id/)
assert.match(source.presentation, /"data-dashboard-section" => group_id/)
assert.match(
  source.presentation,
  /group-data-\[state=open\]\/dashboard-section:rotate-90/,
)
assert.doesNotMatch(source.presentation, /group-open\/dashboard-section:rotate-90/)
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
assert.equal(sha256(source.inspector), "81f389567edd64256254aab2d8f18d2f4eff7d9251dd61777f7b15ad931112cd")

assert.doesNotMatch(source.canvas, /phx-hook|localStorage|<script(?! setup)/)

console.log("dashboard_canvas_test passed")
