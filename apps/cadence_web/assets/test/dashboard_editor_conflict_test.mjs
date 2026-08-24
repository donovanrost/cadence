import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const vueRoot = resolve(__dirname, "../vue")
const liveRoot = resolve(__dirname, "../../lib/cadence_web/live")
const testRoot = resolve(__dirname, "../../test/cadence_web/live")

const paths = {
  component: resolve(vueRoot, "DashboardEditorConflict.vue"),
  host: resolve(
    liveRoot,
    "ops_dashboard_show_live/dashboard_editor_conflict_components.ex",
  ),
  controller: resolve(liveRoot, "ops_dashboard_show_live.ex"),
  editorTest: resolve(testRoot, "ops_dashboard_editor_live_test.exs"),
  widgetTest: resolve(
    testRoot,
    "ops_dashboard_show_live/widget_lifecycle_live_test.exs",
  ),
}

const entries = await Promise.all(
  Object.entries(paths).map(async ([key, path]) => [key, await readFile(path, "utf8")]),
)
const source = Object.fromEntries(entries)
const template = source.component.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const renderSource = source.controller.match(/def render\(assigns\) do[\s\S]*?\n  end\nend\s*$/)?.[0]

assert.ok(template, "DashboardEditorConflict.vue must expose an auditable template")
assert.ok(renderSource, "OpsDashboardShowLive render/1 must remain auditable")

const toolbarIndex = renderSource.indexOf("<.dashboard_toolbar")
const conflictIndex = renderSource.indexOf(
  "<DashboardEditorConflictComponents.dashboard_editor_conflict",
)
const canvasIndex = renderSource.indexOf('v-component="DashboardCanvas"')

assert.ok(toolbarIndex >= 0 && conflictIndex > toolbarIndex && canvasIndex > conflictIndex)
assert.equal(
  renderSource.match(/DashboardEditorConflictComponents\.dashboard_editor_conflict/g)?.length,
  1,
)
assert.match(renderSource, /conflict=\{@editor_conflict\}/)
assert.doesNotMatch(renderSource, /id="dashboard-editor-conflict"/)
assert.doesNotMatch(renderSource, /phx-click="reload_editor"/)

for (const contract of [
  ':if={@presentation}',
  'id="dashboard-editor-conflict-component"',
  'v-component="DashboardEditorConflict"',
  'presentation={@presentation}',
  'v-on:reload_editor={JS.push("reload_editor")}',
  'v-ssr={false}',
  'class="contents"',
  "def presentation(nil), do: nil",
  'id: "dashboard-editor-conflict"',
  '"data-editor-starting-version" => starting_version',
  '"data-editor-current-version" => current_version',
  'class: "hero-exclamation-triangle h-4 w-4 shrink-0 text-error"',
  'class: "min-w-0 flex-1"',
  'id: "dashboard-editor-reload"',
  'type: "button"',
  'class: "btn btn-ghost btn-xs"',
  'text: "Reload latest"',
]) {
  assert.ok(source.host.includes(contract), `server contract remains present: ${contract}`)
}

assert.ok(
  source.host.includes(
    "flex shrink-0 items-center gap-3 border-b border-error/40 bg-error/10 px-3 py-2 text-sm",
  ),
)
assert.ok(
  source.host.includes(
    "was saved elsewhere. Your staged candidate is intact; reload before continuing to avoid an accidental overwrite.",
  ),
)

assert.match(source.component, /defineProps<\{presentation: EditorConflictPresentation\}>\(\)/)
assert.match(source.component, /defineEmits\(\["reload_editor"\]\)/)
assert.match(template, /^  <div v-bind="props\.presentation\.root\.attrs">/)
assert.match(template, /<span v-bind="props\.presentation\.icon\.attrs"><\/span>/)
assert.match(template, /<p :class="props\.presentation\.message\.class">/)
assert.match(template, /v-bind="props\.presentation\.reload\.attrs"/)
assert.match(template, /@click="emit\('reload_editor'\)"/)
assert.doesNotMatch(template, /v-if=/)
assert.doesNotMatch(source.component, /phx-click|starting_version|current_version/)

for (const testSource of [source.editorTest, source.widgetTest]) {
  assert.match(testSource, /LiveVue\.Test\.get_vue\([^\n]+, id: "dashboard-editor-conflict-component"\)/)
  assert.match(testSource, /"data-editor-starting-version" => "1"/)
  assert.match(testSource, /"data-editor-current-version" => "2"/)
}

assert.match(source.editorTest, /"reload_editor" => JS\.push\("reload_editor"\)/)
assert.match(source.editorTest, /render_hook\(editor, "reload_editor", %\{\}\)/)
assert.match(
  source.editorTest,
  /refute has_element\?\(editor, "#dashboard-editor-conflict-component"\)/,
)

console.log("dashboard_editor_conflict_test passed")
