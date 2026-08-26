import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/WidgetInspectPanel.vue")
const csvButtonPath = resolve(testDirectory, "../vue/CsvDownloadButton.vue")
const cadenceButtonPath = resolve(testDirectory, "../vue/ui/components/CadenceButton.vue")
const serverPath = resolve(
  testDirectory,
  "../../lib/cadence_web/live/ops_dashboard_show_live/widget_inspect_panel_components.ex",
)
const callerPath = resolve(
  testDirectory,
  "../../lib/cadence_web/live/ops_dashboard_show_live/form_components.ex",
)
const panelTestPath = resolve(
  testDirectory,
  "../../test/cadence_web/live/ops_dashboard_show_live/widget_inspect_panel_components_test.exs",
)
const modelTestPath = resolve(
  testDirectory,
  "../../test/cadence_web/live/ops_dashboard_show_live/widget_inspect_model_test.exs",
)
const csvTestPath = resolve(
  testDirectory,
  "../../test/cadence_web/assets/csv_download_button_test.exs",
)
const liveTestPath = resolve(
  testDirectory,
  "../../test/cadence_web/live/ops_dashboard_show_live/live_widget_event_marker_navigation_live_test.exs",
)

const [
  source,
  csvButtonSource,
  cadenceButtonSource,
  serverSource,
  callerSource,
  panelTestSource,
  modelTestSource,
  csvTestSource,
  liveTestSource,
] = await Promise.all([
  readFile(componentPath, "utf8"),
  readFile(csvButtonPath, "utf8"),
  readFile(cadenceButtonPath, "utf8"),
  readFile(serverPath, "utf8"),
  readFile(callerPath, "utf8"),
  readFile(panelTestPath, "utf8"),
  readFile(modelTestPath, "utf8"),
  readFile(csvTestPath, "utf8"),
  readFile(liveTestPath, "utf8"),
])

const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
assert.ok(template, "WidgetInspectPanel.vue must have a template block")

const frozenScenarioLedger = Object.freeze([
  [modelTestSource, "merges misaligned series on the union of timestamps with blanks"],
  [modelTestSource, "skips non-numeric values and keeps point metadata out of the table"],
  [modelTestSource, "caps displayed rows but reports the total"],
  [modelTestSource, "computes stats per series"],
  [modelTestSource, "empty series produce an empty model, not a crash"],
  [modelTestSource, "renders the full dataset ascending with ISO times and unit-suffixed headers"],
  [modelTestSource, "quotes fields containing commas or quotes per RFC 4180"],
  [modelTestSource, "blank cells for missing values"],
  [modelTestSource, "returns nil for other panels or missing placements"],
  [panelTestSource, "renders header badges, stats, table rows, and the download payload"],
  [panelTestSource, "disables the download component when there are no rows"],
  [panelTestSource, "shows the cap notice when rows exceed the display limit"],
  [panelTestSource, "renders a fallback when the widget is gone"],
  [csvTestSource, "CSV button preserves download behavior, fallback, cleanup, and accessibility"],
  [liveTestSource, "widget inspect panel opens from the details popover with table and CSV"],
])

const scenarioLedger = Object.freeze([
  "frozen named behavioral ledger",
  "sole FormComponents caller boundary",
  "one parent LiveVue host",
  "single Vue root without nested LiveVue roots",
  "missing branch contract",
  "ready root and header contract",
  "server-owned time cap and display formatting",
  "direct CSV child contract",
  "stats strip and every stat value",
  "dynamic table ordering and display contract",
  "empty states and dynamic colspan",
  "stable selectors classes and accessibility",
])
const coveredScenarios = []
const cover = (name, callback) => {
  assert.equal(name, scenarioLedger[coveredScenarios.length])
  callback()
  coveredScenarios.push(name)
}

const assertionCount = (testSource) =>
  (testSource.match(/^\s*(?:assert|refute)\b/gm) || []).length

cover("frozen named behavioral ledger", () => {
  assert.equal(frozenScenarioLedger.length, 15)
  for (const [testSource, name] of frozenScenarioLedger) {
    assert.ok(testSource.includes(`test "${name}"`), `missing frozen scenario: ${name}`)
  }

  assert.equal(assertionCount(modelTestSource), 28)
  assert.equal(assertionCount(panelTestSource), 16)
  assert.equal(assertionCount(csvTestSource), 2)

  const liveScenarioSource = liveTestSource.slice(
    liveTestSource.indexOf(
      'test "widget inspect panel opens from the details popover with table and CSV"',
    ),
  )
  assert.equal(assertionCount(liveScenarioSource), 18)
})

cover("sole FormComponents caller boundary", () => {
  assert.equal(
    (callerSource.match(/WidgetInspectPanelComponents\.inspect_panel_presentation/g) || []).length,
    1,
  )
  assert.match(callerSource, /defp child_presentation\(%\{panel: \{:widget_inspect, _context\}\} = assigns\)/)
  assert.match(callerSource, /"widget_inspect_panel"/)
  assert.match(callerSource, /"dashboard-widget-inspector-component"/)
  assert.match(
    callerSource,
    /WidgetInspectPanelComponents\.inspect_panel_presentation\(assigns\.widget_inspect\)/,
  )
  assert.doesNotMatch(callerSource, /v-component="WidgetInspectPanel"/)
})

cover("one parent LiveVue host", () => {
  const hostSource = serverSource.match(
    /def inspect_panel\(assigns\) do[\s\S]*?@doc "Builds the JSON-safe presentation contract/,
  )?.[0]

  assert.ok(hostSource, "inspect_panel/1 must remain an auditable host boundary")
  assert.equal((hostSource.match(/<\.vue/g) || []).length, 1)
  assert.match(hostSource, /id="dashboard-widget-inspector-component"/)
  assert.match(hostSource, /v-component="WidgetInspectPanel"/)
  assert.match(hostSource, /presentation=\{@presentation\}/)
  assert.match(hostSource, /v-ssr=\{false\}/)
  assert.match(hostSource, /class="contents"/)
})

cover("single Vue root without nested LiveVue roots", () => {
  assert.match(template, /^  <section v-bind="props\.presentation\.root\.attrs">/)
  assert.match(template, /<\/section>$/)
  assert.doesNotMatch(source, /<\.vue|v-component=|createApp|phx-hook/)
  assert.equal((source.match(/import CsvDownloadButton/g) || []).length, 1)
})

cover("missing branch contract", () => {
  assert.match(serverSource, /state: "missing"/)
  assert.match(serverSource, /"id" => "dashboard-widget-inspector"/)
  assert.match(serverSource, /"data-widget-inspect-state" => "missing"/)
  assert.match(serverSource, /This widget is no longer on the dashboard\./)
  assert.match(template, /props\.presentation\.state === 'missing'/)
  assert.match(template, /props\.presentation\.missing\.text/)
})

cover("ready root and header contract", () => {
  assert.match(serverSource, /state: "ready"/)
  assert.match(serverSource, /"data-widget-inspect-placement" => inspect\.placement_id/)
  assert.match(serverSource, /"data-widget-inspect-state" => "ready"/)
  assert.match(serverSource, /"class" => "space-y-4"/)
  assert.match(serverSource, /text: "Time series"/)
  assert.match(serverSource, /"data-widget-inspect-series-count" => series_count/)
  assert.match(serverSource, /"data-widget-inspect-row-total" => inspect\.row_count_total/)
  assert.match(template, /props\.presentation\.header\.series_badge\.attrs/)
  assert.match(template, /props\.presentation\.header\.rows_badge\.attrs/)
})

cover("server-owned time cap and display formatting", () => {
  assert.match(serverSource, /WidgetInspectModel\.iso_timestamp\(from_ms\)/)
  assert.match(serverSource, /WidgetInspectModel\.iso_timestamp\(to_ms\)/)
  assert.match(serverSource, /WidgetInspectModel\.iso_timestamp\(row\.timestamp_ms\)/)
  assert.match(serverSource, /Showing latest #\{length\(inspect\.rows\)\} of #\{inspect\.row_count_total\} rows\./)
  assert.match(serverSource, /defp format_number\(nil\), do: "—"/)
  assert.match(serverSource, /defp format_number\(value\), do: to_string\(value\)/)
  assert.doesNotMatch(source, /Date\(|toLocale|toFixed|Intl\.NumberFormat|\.sort\(|\.reverse\(/)
})

cover("direct CSV child contract", () => {
  assert.match(source, /import CsvDownloadButton from "\.\/CsvDownloadButton\.vue"/)
  assert.match(template, /<CsvDownloadButton v-bind="props\.presentation\.download\.props" \/>/)
  assert.match(serverSource, /id: "dashboard-widget-inspect-download-component"/)
  assert.match(serverSource, /component: "CsvDownloadButton"/)
  assert.match(serverSource, /csv: inspect\.csv/)
  assert.match(serverSource, /filename: csv_filename\(inspect\)/)
  assert.match(serverSource, /disabled: inspect\.row_count_total == 0/)
  assert.match(serverSource, /\(inspect\.title \|\| "widget"\)/)
  assert.match(serverSource, /String\.downcase\(\)/)
  assert.match(serverSource, /String\.replace\(~r\/\[\^a-z0-9\]\+\/, "-"\)/)
  assert.match(serverSource, /String\.trim\("-"\)/)
  assert.match(serverSource, /"#\{slug\}-inspect\.csv"/)
  assert.equal((serverSource.match(/v-component="CsvDownloadButton"/g) || []).length, 0)
  assert.match(csvButtonSource, /id="dashboard-widget-inspect-download"/)
  assert.match(csvButtonSource, /import CadenceButton from "\.\/ui\/components\/CadenceButton\.vue"/)
  assert.equal((csvButtonSource.match(/<CadenceButton\b/g) || []).length, 1)
  assert.match(csvButtonSource, /type="button"/)
  assert.match(csvButtonSource, /:disabled="props\.disabled"/)
  assert.match(csvButtonSource, /@click="downloadCsv"/)
  assert.match(csvButtonSource, /Download CSV/)
  assert.match(cadenceButtonSource, /h\("button", null, slots\.default\?\.\(\)\)/)
  assert.doesNotMatch(cadenceButtonSource, /class=|<template>|h\("div"|h\("span"/)
})

cover("stats strip and every stat value", () => {
  assert.match(serverSource, /"data-widget-inspect-stats" => ""/)
  assert.match(serverSource, /"data-widget-inspect-stat" => stat\.label/)
  assert.match(
    serverSource,
    /\{"count", stat\.count\}[\s\S]*\{"min", stat\.min\}[\s\S]*\{"max", stat\.max\}[\s\S]*\{"mean", stat\.mean\}[\s\S]*\{"last", stat\.last\}/,
  )
  assert.match(template, /v-for="\(stat, statIndex\) in props\.presentation\.stats\.rows"/)
  assert.match(template, /v-for="value in stat\.values"/)
  assert.match(template, /value\.value\.text/)
})

cover("dynamic table ordering and display contract", () => {
  assert.match(serverSource, /series_headers: Enum\.map\(inspect\.series/)
  assert.match(serverSource, /rows: Enum\.map\(inspect\.rows/)
  assert.match(serverSource, /Enum\.map\(row\.values/)
  assert.match(serverSource, /text: "Time \(UTC\)"/)
  assert.match(template, /v-for="\(series, seriesIndex\) in props\.presentation\.table\.series_headers"/)
  assert.match(template, /v-for="\(row, rowIndex\) in props\.presentation\.table\.rows"/)
  assert.match(template, /v-for="\(value, valueIndex\) in row\.values"/)
  assert.match(template, /row\.timestamp\.text/)
})

cover("empty states and dynamic colspan", () => {
  assert.match(serverSource, /visible: stats == \[\]/)
  assert.match(serverSource, /text: "No series resolved\."/)
  assert.match(serverSource, /visible: inspect\.rows == \[\]/)
  assert.match(serverSource, /colspan: length\(inspect\.series\) \+ 1/)
  assert.match(serverSource, /text: "No samples in the current window\."/)
  assert.match(template, /props\.presentation\.stats\.empty\.visible/)
  assert.match(template, /props\.presentation\.table\.empty\.visible/)
  assert.match(template, /:colspan="props\.presentation\.table\.empty\.colspan"/)
})

cover("stable selectors classes and accessibility", () => {
  const stableTokens = [
    "dashboard-widget-inspector",
    "dashboard-widget-inspect-capped",
    "dashboard-widget-inspect-download-component",
    "dashboard-widget-inspect-download",
    "data-widget-inspect-state",
    "data-widget-inspect-placement",
    "data-widget-inspect-series-count",
    "data-widget-inspect-row-total",
    "data-widget-inspect-stats",
    "data-widget-inspect-stat",
    "data-widget-inspect-table",
    "space-y-4",
    "rounded border border-base-300/70 bg-base-100/40 px-2 py-2 text-xs text-base-content/60",
    "space-y-1",
    "flex flex-wrap items-center gap-2",
    "badge badge-xs badge-outline",
    "badge badge-xs",
    "font-mono text-[0.68rem] text-base-content/60",
    "text-[0.68rem] text-base-content/60",
    "space-y-2",
    "hud-label",
    "grid grid-cols-[minmax(0,1fr)_repeat(5,minmax(3rem,auto))] items-baseline gap-x-3 rounded border border-base-300/70 px-2 py-1 text-xs",
    "truncate font-mono text-base-content/80",
    "text-base-content/60",
    "text-right",
    "block text-[0.6rem] uppercase tracking-wide text-base-content/50",
    "block font-mono text-base-content/80",
    "max-h-[28rem] overflow-auto rounded border border-base-300/70",
    "table table-xs",
    "whitespace-nowrap",
    "whitespace-nowrap text-right",
    "text-base-content/50",
    "whitespace-nowrap font-mono text-[0.68rem] text-base-content/70",
    "text-right font-mono text-[0.68rem]",
    "btn btn-sm btn-outline justify-start",
    "hero-arrow-down-tray h-4 w-4",
    "This widget is no longer on the dashboard.",
    "No series resolved.",
    "No samples in the current window.",
    "The CSV download contains the full window.",
  ]
  const ownedSource = `${serverSource}\n${source}\n${csvButtonSource}\n${cadenceButtonSource}`

  for (const token of stableTokens) {
    assert.ok(ownedSource.includes(token), `missing stable contract token: ${token}`)
  }

  assert.match(template, /<section v-bind=/)
  assert.match(template, /<h3 :class=/)
  assert.match(template, /<table :class=/)
  assert.match(template, /<th :class=/)
  assert.match(csvButtonSource, /<CadenceButton[\s\S]*Download CSV[\s\S]*<\/CadenceButton>/)
  assert.match(cadenceButtonSource, /h\("button", null, slots\.default\?\.\(\)\)/)
})

assert.deepEqual(coveredScenarios, scenarioLedger)
console.log(
  `widget_inspect_panel_test passed (${scenarioLedger.length} source scenarios; ${frozenScenarioLedger.length} frozen scenarios)`,
)
