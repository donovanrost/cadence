import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/VersionHistoryPanel.vue")
const serverPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/version_history_panel_components.ex",
)

const componentSource = await readFile(componentPath, "utf8")
const serverSource = await readFile(serverPath, "utf8")

assert.match(componentSource, /import ActivityTimeline from "\.\/ActivityTimeline\.vue"/)
assert.match(
  componentSource,
  /import VersionHistorySummary from "\.\/VersionHistorySummary\.vue"/,
)
assert.match(componentSource, /v-bind="presentation\.root\.attrs"/)
assert.match(componentSource, /v-bind="presentation\.version_history_summary\.root\.attrs"/)
assert.match(componentSource, /v-bind="presentation\.activity_timeline\.root\.attrs"/)
assert.match(
  componentSource,
  /<VersionHistorySummary :presentation="presentation\.version_history_summary\.presentation" \/>/,
)
assert.match(
  componentSource,
  /<ActivityTimeline :presentation="presentation\.activity_timeline\.presentation" \/>/,
)
assert.ok(
  componentSource.indexOf("<VersionHistorySummary") <
    componentSource.indexOf("<ActivityTimeline"),
  "version summary must remain before the activity timeline",
)

assert.equal(
  serverSource.match(/<\.vue/g)?.length,
  1,
  "versions_panel must emit exactly one LiveVue host",
)
assert.match(serverSource, /v-component="VersionHistoryPanel"/)
assert.match(serverSource, /"id" => "dashboard-versions-panel"/)
assert.match(serverSource, /"id" => "dashboard-version-history-summary-component"/)
assert.match(serverSource, /"id" => "dashboard-activity-timeline-component"/)
