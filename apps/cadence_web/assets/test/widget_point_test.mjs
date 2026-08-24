import assert from "node:assert/strict"
import {readFileSync} from "node:fs"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/WidgetPoint.vue")
const componentSource = readFileSync(componentPath, "utf8")
const phoenixPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/widget_point_components.ex",
)
const phoenixSource = readFileSync(phoenixPath, "utf8")

assert.match(
  componentSource,
  /import ChartDataManagementStrip from "\.\/ChartDataManagementStrip\.vue"/,
)
assert.match(componentSource, /import TelemetryChart from "\.\/TelemetryChart\.vue"/)
assert.match(componentSource, /defineProps<\{presentation: WidgetPointPresentation\}>\(\)/)
assert.match(componentSource, /presentation\.kind === 'value_tile'/)
assert.match(componentSource, /presentation\.kind === 'time_series'/)
assert.match(componentSource, /<ChartDataManagementStrip/)
assert.match(componentSource, /<TelemetryChart v-bind="presentation\.chart\.props" \/>/)
assert.match(componentSource, /:id="presentation\.chart\.component_id"/)
assert.match(componentSource, /v-bind="presentation\.value\.attrs"/)
assert.match(componentSource, /v-bind="presentation\.stage\.attrs"/)
assert.match(componentSource, /v-bind="presentation\.spacecraft\.attrs"/)
assert.doesNotMatch(componentSource, /data-name=/)

assert.equal((phoenixSource.match(/v-component="WidgetPoint"/g) || []).length, 3)
assert.equal((phoenixSource.match(/presentation=\{@presentation\}/g) || []).length, 3)
assert.equal((phoenixSource.match(/v-ssr=\{false\}/g) || []).length, 3)
assert.doesNotMatch(phoenixSource, /v-component="TelemetryChart"/)
assert.doesNotMatch(phoenixSource, /v-component="ChartDataManagementStrip"/)

console.log("widget_point_test passed")
