import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import vm from "node:vm"

const __dirname = dirname(fileURLToPath(import.meta.url))
const hookPath = resolve(__dirname, "../js/hooks/telemetry_chart.js")

const source = await readFile(hookPath, "utf8")
const testableSource = source
  .replace('import uPlot from "../../vendor/uplot/uPlot.esm"\n', "const uPlot = class {}\n")
  .replace("export default TelemetryChart", "globalThis.TelemetryChart = TelemetryChart")

const context = { console, setTimeout: (callback) => callback() }
vm.createContext(context)
vm.runInContext(testableSource, context, { filename: hookPath })

const TelemetryChart = context.TelemetryChart

function chartWithMarkers(limitMarkers = [], eventMarkers = []) {
  const chart = Object.create(TelemetryChart)
  chart.limitMarkers = limitMarkers
  chart.eventMarkers = eventMarkers
  chart.placementId = "placement-1"
  chart.el = {
    dataset: {
      dataRealm: "flight",
      dataSourceId: "runtime-source",
      sourceBindingId: "runtime-binding",
      timeMode: "live",
      timeAxis: "generation_time",
      replayRunId: "",
    },
  }
  return chart
}

function plain(value) {
  return JSON.parse(JSON.stringify(value))
}

function fakeElement(tagName) {
  return {
    tagName,
    type: "",
    title: "",
    dataset: {},
    style: {},
    attributes: {},
    children: [],
    listeners: {},
    setAttribute(name, value) {
      this.attributes[name] = value
    },
    appendChild(child) {
      this.children.push(child)
    },
    addEventListener(name, callback) {
      this.listeners[name] = callback
    },
  }
}

function chartWithPlot(limitMarkers = []) {
  const chart = chartWithMarkers(limitMarkers)
  chart.xs = [1781697600, 1781697660, 1781697720]
  chart.el.clientHeight = 180
  chart.el.clientWidth = 320
  chart.chart = {
    bbox: { left: 10, top: 20, width: 300, height: 120 },
    valToPos(value, scale) {
      if (scale === "x") return ((value - 1781697600) / 120) * 300
      return 120 - value
    },
  }
  chart.markerLayer = fakeElement("div")
  chart.eventLayer = fakeElement("div")
  chart.selectionLayer = fakeElement("div")
  chart.pushedEvents = []
  chart.pushEvent = (name, payload) => chart.pushedEvents.push({ name, payload })
  return chart
}

{
  const chart = chartWithMarkers()
  const markers = chart.collapseSourceWatermarkMarkers([
    {
      marker_type: "source_watermark_event",
      marker_id: "event-1",
      timestamp_ms: 1000,
      logical_source: "telemetry",
      data_source_id: "questdb",
      source_binding_id: "flight",
    },
    {
      marker_type: "source_watermark_event",
      marker_id: "event-2",
      timestamp_ms: 2000,
      logical_source: "telemetry",
      data_source_id: "questdb",
      source_binding_id: "flight",
    },
    {
      marker_type: "source_watermark_cursor",
      marker_id: "cursor-1",
      timestamp_ms: 3000,
      logical_source: "telemetry",
      data_source_id: "questdb",
      source_binding_id: "flight",
    },
    { marker_type: "mission_event", marker_id: "mission-event-1", timestamp_ms: 1500 },
  ])

  assert.deepEqual(
    plain(markers.map((marker) => [marker.marker_type, marker.marker_id])),
    [
      ["mission_event", "mission-event-1"],
      ["source_watermark_cursor", "cursor-1"],
    ]
  )
}

{
  const chart = chartWithMarkers()
  const markers = chart.collapseSourceWatermarkMarkers([
    {
      marker_type: "source_watermark_event",
      marker_id: "event-1",
      timestamp_ms: 1000,
      logical_source: "telemetry",
    },
    {
      marker_type: "source_watermark_event",
      marker_id: "event-2",
      timestamp_ms: 2000,
      logical_source: "telemetry",
    },
  ])

  assert.deepEqual(plain(markers.map((marker) => marker.marker_id)), ["event-2"])
}

{
  context.document = { createElement: fakeElement }
  const chart = chartWithPlot()

  chart.renderSourceWatermarkCursor({
    marker_type: "source_watermark_cursor",
    marker_id: "cursor-fresh",
    timestamp_ms: 1781697719000,
    display_mode: "status",
    freshness_state: "fresh",
    target_id: "telemetry-request",
  })

  assert.equal(chart.eventLayer.children.length, 1)
  const status = chart.eventLayer.children[0]
  assert.equal(status.dataset.sourceWatermarkStatus, "complete")
  assert.equal(status.dataset.sourceWatermarkLagMs, "1000")
  assert.equal(status.textContent, "Complete · 1.0s behind")
  assert.equal(chart.el.dataset.watermarkBoundaryVisible, "false")
}

{
  context.document = { createElement: fakeElement }
  const chart = chartWithPlot()

  chart.renderSourceWatermarkCursor({
    marker_type: "source_watermark_cursor",
    marker_id: "cursor-stale",
    timestamp_ms: 1781697660000,
    display_mode: "boundary",
    freshness_state: "stale",
    target_id: "telemetry-request",
  })

  assert.equal(chart.eventLayer.children.length, 3)
  const [region, boundary, status] = chart.eventLayer.children
  assert.equal(region.dataset.sourceWatermarkIncompleteRegion, "stale")
  assert.equal(region.style.left, "160px")
  assert.equal(region.style.width, "150px")
  assert.equal(boundary.dataset.watermarkBoundary, "stale")
  assert.equal(status.dataset.sourceWatermarkStatus, "incomplete")
  assert.equal(status.textContent, "Incomplete · 1m behind")
  assert.equal(chart.el.dataset.watermarkBoundaryVisible, "true")
}

{
  const chart = chartWithMarkers(
    [{ marker_type: "limit_event", limit_event_id: "existing-limit", timestamp_ms: 1 }],
    [{ marker_type: "mission_event", mission_event_id: "existing-event", timestamp_ms: 2 }]
  )

  chart.appendMarkerPayload({
    limit_markers: [
      { marker_type: "limit_event", limit_event_id: "new-limit", timestamp_ms: 3 },
      { marker_type: "limit_event", limit_event_id: "new-limit", timestamp_ms: 3 },
    ],
    event_markers: [
      { marker_type: "mission_event", mission_event_id: "new-event", timestamp_ms: 4 },
      { marker_type: "mission_event", mission_event_id: "new-event", timestamp_ms: 4 },
    ],
  })

  assert.deepEqual(
    chart.limitMarkers.map((marker) => marker.limit_event_id),
    ["existing-limit", "new-limit"]
  )
  assert.deepEqual(
    chart.eventMarkers.map((marker) => marker.mission_event_id),
    ["existing-event", "new-event"]
  )
}

{
  const chart = chartWithMarkers()

  chart.appendMarkerPayload([
    { marker_type: "limit_event", limit_event_id: "legacy-limit", timestamp_ms: 5 },
  ])

  assert.deepEqual(
    chart.limitMarkers.map((marker) => marker.limit_event_id),
    ["legacy-limit"]
  )
  assert.deepEqual(chart.eventMarkers, [])
}

{
  const chart = chartWithMarkers(
    [{ marker_type: "limit_event", limit_event_id: "stable-limit", timestamp_ms: 6 }],
    [{ marker_type: "mission_event", mission_event_id: "stable-event", timestamp_ms: 7 }]
  )

  chart.appendMarkerPayload(null)

  assert.deepEqual(
    chart.limitMarkers.map((marker) => marker.limit_event_id),
    ["stable-limit"]
  )
  assert.deepEqual(
    chart.eventMarkers.map((marker) => marker.mission_event_id),
    ["stable-event"]
  )
}

{
  context.document = { createElement: fakeElement }
  const chart = chartWithPlot()

  chart.renderLimitAnalysisBucket({
    marker_type: "limit_analysis_bucket",
    marker_id: "limit-analysis-bucket:compare:1781697600000:1781697660000",
    link_id: "sample-link-worst",
    timestamp_ms: 1781697600000,
    starts_at_ms: 1781697600000,
    ends_at_ms: 1781697660000,
    normalized_state: "red",
    limit_event_id: "synthetic-limit-event",
    sample_id: "sample-worst",
    limit_definition_id: "limit-def-2",
    limit_definition_version: 2,
    limit_set_name: "ops-red",
    event_count: 2,
    limit_divergence_count: 1,
    selected_limit_clock: {
      observed: "limit_event_receipt_time",
      requested_time_axis: "receipt_time",
    },
    selected_limit_definition_intervals: [
      {
        definition_id: "limit-def-2",
        active_from: "2026-06-17T12:00:00Z",
      },
    ],
    synthetic_limit_analysis: true,
  })

  assert.equal(chart.markerLayer.children.length, 1)
  const bucket = chart.markerLayer.children[0]
  assert.equal(bucket.dataset.limitMarkerTarget, "limit analysis bucket")
  assert.equal(bucket.dataset.limitBucketState, "red")
  assert.equal(bucket.dataset.limitBucketEventCount, 2)
  assert.equal(bucket.dataset.limitBucketDivergenceCount, 1)
  assert.equal(bucket.dataset.limitDefinitionId, "limit-def-2")
  assert.equal(bucket.dataset.limitDefinitionVersion, 2)
  assert.equal(bucket.dataset.limitSetName, "ops-red")
  assert.equal(
    bucket.dataset.limitSelectedClock,
    JSON.stringify({
      observed: "limit_event_receipt_time",
      requested_time_axis: "receipt_time",
    })
  )
  assert.equal(
    bucket.dataset.limitSelectedDefinitionIntervals,
    JSON.stringify([
      {
        definition_id: "limit-def-2",
        active_from: "2026-06-17T12:00:00Z",
      },
    ])
  )
  assert.equal(bucket.dataset.limitBucketDiverged, "true")
  assert.equal(bucket.style.left, "10px")
  assert.equal(bucket.style.width, "150px")
  assert.equal(bucket.style.background, "rgba(248, 113, 113, 0.14)")

  bucket.listeners.click({
    preventDefault() {},
    stopPropagation() {},
  })

  assert.deepEqual(plain(chart.pushedEvents), [
    {
      name: "open_data_link",
      payload: {
        "link-id": "sample-link-worst",
        "placement-id": "placement-1",
        target: "telemetry_sample",
        "target-id": "sample-worst",
        "timestamp-ms": 1781697600000,
      },
    },
  ])
}

{
  context.document = { createElement: fakeElement }
  const chart = chartWithPlot()
  chart.selectedRef = { link_id: "bucket-link" }

  chart.renderSelectedLimit({
    marker_type: "limit_analysis_bucket",
    starts_at_ms: 1781697600000,
    ends_at_ms: 1781697660000,
    normalized_state: "yellow",
  })

  assert.equal(chart.selectionLayer.children.length, 1)
  const selection = chart.selectionLayer.children[0]
  assert.equal(selection.dataset.chartSelectionTarget, "limit analysis bucket")
  assert.equal(selection.style.left, "10px")
  assert.equal(selection.style.width, "150px")
  assert.equal(selection.style.background, "rgba(250, 204, 21, 0.18)")
}

{
  context.document = { createElement: fakeElement }
  const chart = chartWithPlot()

  chart.renderLimitDefinitionInterval({
    marker_type: "limit_definition_interval",
    starts_at_ms: 1781697600000,
    ends_at_ms: 1781697660000,
    link_id: "limit-definition-link",
    limit_definition_id: "counter-limits",
    limit_set_name: "Ops",
    red_low: 10,
    yellow_low: 25,
    yellow_high: 75,
    red_high: 90,
  })

  assert.equal(chart.markerLayer.children.length, 1)
  const interval = chart.markerLayer.children[0]
  const bands = interval.children.filter((child) => child.dataset.limitThresholdBand)
  assert.deepEqual(
    bands.map((band) => band.dataset.limitThresholdBand),
    ["red_high", "yellow_high", "yellow_low", "red_low"]
  )
  assert.deepEqual(
    bands.map((band) => [band.style.top, band.style.height, band.style.background]),
    [
      ["0px", "30px", "rgba(248, 113, 113, 0.08)"],
      ["30px", "15px", "rgba(250, 204, 21, 0.07)"],
      ["95px", "15px", "rgba(250, 204, 21, 0.07)"],
      ["110px", "10px", "rgba(248, 113, 113, 0.08)"],
    ]
  )
}

{
  const chart = chartWithMarkers()

  assert.equal(
    chart.appendMarkerPayload({
      event_markers: [{ marker_type: "mission_event", mission_event_id: "marker-only", timestamp_ms: 8 }],
    }),
    true
  )

  assert.deepEqual(
    chart.eventMarkers.map((marker) => marker.mission_event_id),
    ["marker-only"]
  )
}

{
  const chart = chartWithMarkers()

  assert.deepEqual(
    plain(chart.markerDataLinkPayload(
      {
        link_id: "limit-link-1",
        requested_realm: "replay",
        realm: "flight",
        requested_data_view: "all_revisions",
        data_view: "canonical",
        requested_data_source_id: "requested-source",
        data_source_id: "actual-source",
        requested_source_binding_id: "requested-binding",
        source_binding_id: "actual-binding",
        time_mode: "replay_run",
        time_axis: "generation_time",
        replay_run_id: "replay-run-1",
      },
      "limit_event",
      "limit-event-1",
      9
    )),
    {
      "link-id": "limit-link-1",
      "placement-id": "placement-1",
      target: "limit_event",
      "target-id": "limit-event-1",
      "timestamp-ms": 9,
      realm: "replay",
      "data-view": "all_revisions",
      "data-source-id": "requested-source",
      "source-binding-id": "requested-binding",
      "time-mode": "replay_run",
      "time-axis": "generation_time",
      "replay-run-id": "replay-run-1",
    }
  )
}

{
  const chart = chartWithMarkers()
  chart.el.dataset.timeMode = "replay_run"
  chart.el.dataset.replayRunId = "replay-run-1"

  assert.deepEqual(
    plain(chart.pointDataLinkPayload(
      {
        link_id: "sample-link-1",
        sample_id: "sample-1",
        series_role: "compare",
        compare_of: "HK.counter",
        data_view: "all_revisions",
        data_source_id: "series-source",
        source_binding_id: "series-binding",
        time_axis: "receipt_time",
      },
      10
    )),
    {
      "link-id": "sample-link-1",
      "placement-id": "placement-1",
      target: "telemetry_sample",
      "target-id": "sample-1",
      "timestamp-ms": 10,
      "series-role": "compare",
      "compare-of": "HK.counter",
      realm: "flight",
      "data-view": "all_revisions",
      "data-source-id": "series-source",
      "source-binding-id": "series-binding",
      "time-mode": "replay_run",
      "time-axis": "receipt_time",
      "replay-run-id": "replay-run-1",
    }
  )
}

{
  const chart = chartWithMarkers()
  chart.widgetId = "widget-1"
  chart.el.dataset.dataView = "all_revisions"
  chart.el.dataset.compareDataView = "canonical"
  chart.el.dataset.timeMode = "replay_run"
  chart.el.dataset.replayRunId = "replay-run-1"

  const primarySeries = chart.normalizeSeriesPayload({
    series: [
      {
        id: "HK.counter",
        label: "Counter",
        data_source_id: "primary-source",
        source_binding_id: "primary-binding",
        time_axis: "generation_time",
        points: [[10, 42, { link_id: "primary-link", sample_id: "primary-sample" }]],
      },
    ],
  })

  const compareSeries = chart.normalizeCompareSeriesPayload({
    series: [
      {
        id: "HK.counter",
        label: "Counter",
        data_source_id: "compare-source",
        source_binding_id: "compare-binding",
        time_axis: "receipt_time",
        points: [[10, 40, { link_id: "compare-link", sample_id: "compare-sample" }]],
      },
    ],
  })

  chart.seriesList = primarySeries.concat(compareSeries)
  chart.rebuildPlotData()

  assert.equal(chart.el.dataset.chartPointCount, "2")
  assert.equal(chart.el.dataset.chartLatestTimestampMs, "10")

  assert.deepEqual(
    plain(chart.pointDataLinkPayload(chart.seriesPointMeta[1][0], 10)),
    {
      "link-id": "compare-link",
      "placement-id": "placement-1",
      target: "telemetry_sample",
      "target-id": "compare-sample",
      "timestamp-ms": 10,
      "series-role": "compare",
      "compare-of": "HK.counter",
      realm: "flight",
      "data-view": "canonical",
      "data-source-id": "compare-source",
      "source-binding-id": "compare-binding",
      "time-mode": "replay_run",
      "time-axis": "receipt_time",
      "replay-run-id": "replay-run-1",
    }
  )
}

{
  const chart = chartWithMarkers()

  assert.deepEqual(
    plain(chart.pointDataLinkPayload(
      {
        link_id: "transport:transport-alpha:request-ops",
        target: "transport",
        target_id: "transport-alpha",
        series_role: "primary",
        data_source_id: "managed-operational",
        source_binding_id: "ops-binding",
        time_axis: "occurred_at",
      },
      11
    )),
    {
      "link-id": "transport:transport-alpha:request-ops",
      "placement-id": "placement-1",
      target: "transport",
      "target-id": "transport-alpha",
      "timestamp-ms": 11,
      "series-role": "primary",
      realm: "flight",
      "data-source-id": "managed-operational",
      "source-binding-id": "ops-binding",
      "time-mode": "live",
      "time-axis": "occurred_at",
    }
  )
}

{
  const chart = chartWithMarkers()

  assert.deepEqual(
    plain(chart.sourceWatermarkDataLinkPayload(
      {
        marker_type: "source_watermark_event",
        link_id: "source_watermark_event:watermark-event-1:events-request-1",
        data_link_target: "source_watermark_event",
        data_link_target_id: "watermark-event-1",
        target: "source_watermark",
        target_id: "watermark-event-1",
        source_watermark_event_id: "watermark-event-1",
        timestamp_ms: 12,
        requested_realm: "flight",
        requested_data_view: "canonical",
        requested_data_source_id: "events-projection",
        requested_source_binding_id: "events-binding",
        time_mode: "archive",
        time_axis: "occurred_at",
      }
    )),
    {
      "link-id": "source_watermark_event:watermark-event-1:events-request-1",
      "placement-id": "placement-1",
      target: "source_watermark_event",
      "target-id": "watermark-event-1",
      "timestamp-ms": 12,
      realm: "flight",
      "data-view": "canonical",
      "data-source-id": "events-projection",
      "source-binding-id": "events-binding",
      "time-mode": "archive",
      "time-axis": "occurred_at",
    }
  )

  assert.equal(
    chart.sourceWatermarkDataLinkPayload({
      marker_type: "source_watermark_cursor",
      link_id: "source_watermark_event:watermark-event-1:events-request-1",
      timestamp_ms: 13,
    }),
    null
  )
}

{
  const chart = chartWithMarkers()

  assert.deepEqual(
    plain(chart.pointDataLinkPayload(
      {
        link_id: "sample-link-2",
        sample_id: "sample-2",
        data_view: "canonical",
      },
      11
    )),
    {
      "link-id": "sample-link-2",
      "placement-id": "placement-1",
      target: "telemetry_sample",
      "target-id": "sample-2",
      "timestamp-ms": 11,
      realm: "flight",
      "data-view": "canonical",
      "data-source-id": "runtime-source",
      "source-binding-id": "runtime-binding",
      "time-mode": "live",
      "time-axis": "generation_time",
    }
  )
}

{
  const chart = chartWithMarkers()

  assert.deepEqual(
    plain(chart.markerDataLinkPayload(
      {
        link_id: "mission-event-link",
        realm: "",
        data_view: null,
        data_source_id: undefined,
        source_binding_id: "binding-1",
      },
      "mission_event",
      "mission-event-1",
      null
    )),
    {
      "link-id": "mission-event-link",
      "placement-id": "placement-1",
      target: "mission_event",
      "target-id": "mission-event-1",
      "source-binding-id": "binding-1",
    }
  )
}

{
  const chart = chartWithMarkers()
  chart.windowSeconds = 300
  chart.liveWindowEnd = 1781697900
  chart.xs = [1781694000, 1781694060]

  assert.deepEqual(plain(chart.chartXRange(1781694000, 1781694060)), [1781697600, 1781697900])
}

{
  const chart = chartWithMarkers()
  chart.windowSeconds = 300
  chart.liveWindowEnd = 1781697900
  chart.seriesList = [
    {
      id: "HK.counter",
      label: "Counter",
      role: "primary",
      envelope: null,
      points: [
        [1781697540000, 1, {}],
        [1781697840000, 2, {}],
      ],
    },
  ]
  chart.rebuildPlotData()
  chart.trimToWindow()

  assert.deepEqual(plain(chart.seriesList[0].points), [[1781697840000, 2, {}]])
  assert.equal(chart.advanceLiveWindow(1781697960000), true)
  assert.equal(chart.liveWindowEnd, 1781697960)
  assert.equal(chart.el.dataset.liveWindowStartMs, "1781697660000")
  assert.equal(chart.el.dataset.liveWindowEndMs, "1781697960000")
}

{
  const chart = chartWithMarkers()
  chart.el.dataset.timeMode = "archive"
  chart.windowSeconds = 300
  chart.liveWindowEnd = 1781697900
  chart.xs = [1781694000, 1781694060]

  assert.deepEqual(plain(chart.chartXRange(1781694000, 1781694060)), [1781694000, 1781694060])
  assert.equal(chart.advanceLiveWindow(1781697960000), false)
}

{
  const chart = chartWithMarkers()
  chart.lineWidth = "thin"
  assert.equal(chart.lineWidthValue(), 1)
  chart.lineWidth = "normal"
  assert.equal(chart.lineWidthValue(), 2)
  chart.lineWidth = "bold"
  assert.equal(chart.lineWidthValue(), 3)
  chart.fillOpacity = 16
  assert.equal(chart.seriesFillColor("rgba(45, 212, 191, 0.92)"), "rgba(45, 212, 191, 0.16)")
}

{
  context.document = { createElement: fakeElement }
  const chart = chartWithPlot()
  chart.legendMode = "always"
  chart.hiddenSeriesIds = new Set()
  chart.seriesList = [{ id: "battery_voltage", label: "Battery voltage", unit: "V" }]

  const legend = chart.buildLegendLayer()

  assert.equal(legend.style.top, undefined)
  assert.equal(legend.style.bottom, "0")
  assert.equal(legend.style.left, "0")
  assert.equal(legend.style.right, "0")
  assert.equal(chart.legendHeight(), 28)
  assert.deepEqual(plain(chart.chartSize()), { width: 320, height: 152 })

  chart.legendMode = "hidden"
  assert.equal(chart.legendHeight(), 0)
  assert.deepEqual(plain(chart.chartSize()), { width: 320, height: 180 })
}

{
  const chart = chartWithPlot()
  const overlay = fakeElement("div")
  chart.el.dataset.editMode = "false"
  chart.el.querySelector = (selector) => (selector === ".u-over" ? overlay : null)
  chart.chart.select = { left: 10, width: 20 }
  chart.chart.posToVal = (position) => 1781697600 + position
  chart.chart.setSelect = (selection) => {
    chart.clearedSelection = selection
  }

  chart.installRangeSelection()
  overlay.listeners.mouseup()

  assert.deepEqual(plain(chart.pushedEvents), [
    {
      name: "set_chart_time_range",
      payload: {
        from: "2026-06-17T12:00:10.000Z",
        to: "2026-06-17T12:00:30.000Z",
      },
    },
  ])
  assert.equal(chart.clearedSelection.width, 0)
}

console.log("telemetry_chart_append_test passed")
