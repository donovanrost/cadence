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

function chartWithMarkers(limitMarkers = [], eventMarkers = [], annotations = []) {
  const chart = Object.create(TelemetryChart)
  chart.limitMarkers = limitMarkers
  chart.eventMarkers = eventMarkers
  chart.annotations = annotations
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
    get firstChild() {
      return this.children[0] || null
    },
    setAttribute(name, value) {
      this.attributes[name] = value
    },
    appendChild(child) {
      if (child.parentNode && child.parentNode !== this) {
        child.parentNode.children = child.parentNode.children.filter((candidate) => candidate !== child)
      }
      this.children.push(child)
      child.parentNode = this
    },
    insertBefore(child, reference) {
      if (child.parentNode && child.parentNode !== this) {
        child.parentNode.children = child.parentNode.children.filter((candidate) => candidate !== child)
      }
      const index = reference ? this.children.indexOf(reference) : -1
      if (index >= 0) this.children.splice(index, 0, child)
      else this.children.push(child)
      child.parentNode = this
    },
    replaceChildren(...children) {
      this.children = children
    },
    contains(candidate) {
      if (candidate === this) return true
      return this.children.some((child) => child.contains?.(candidate))
    },
    querySelector(selector) {
      const dataAttribute = selector.match(/^\[data-([a-z0-9-]+)='([^']+)'\]$/)
      const datasetKey = dataAttribute?.[1].replace(/-([a-z])/g, (_match, letter) => letter.toUpperCase())
      const matches =
        datasetKey && String(this.dataset[datasetKey] || "") === String(dataAttribute[2])

      if (matches) return this

      for (const child of this.children) {
        const match = child.querySelector?.(selector)
        if (match) return match
      }

      return null
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
  chart.annotationLayer = fakeElement("div")
  chart.watermarkOverlayLayer = fakeElement("div")
  chart.selectionLayer = fakeElement("div")
  chart.pushedEvents = []
  chart.pushEvent = (name, payload) => chart.pushedEvents.push({ name, payload })
  return chart
}

{
  const chart = chartWithPlot()
  chart.sharedTooltip = true
  chart.tooltipLayer = fakeElement("div")
  chart.tooltipLayer.offsetWidth = 100
  chart.tooltipLayer.offsetHeight = 40
  chart.seriesList = [{ id: "battery-voltage", label: "Battery Voltage", unit: "V" }]
  chart.seriesYs = [[27.4, 27.8, 28.1]]
  chart.hiddenSeriesIds = new Set()

  chart.renderSharedTooltip({ cursor: { idx: 1, left: 275, top: 115 } })

  assert.equal(chart.tooltipLayer.style.display, "block")
  assert.equal(chart.tooltipLayer.style.left, "173px")
  assert.equal(chart.tooltipLayer.style.top, "83px")
  assert.equal(chart.tooltipLayer.dataset.chartTooltipPlacementX, "left")
  assert.equal(chart.tooltipLayer.dataset.chartTooltipPlacementY, "above")
  assert.match(chart.tooltipLayer.textContent, /Battery Voltage: 27.8 V/)

  chart.renderSharedTooltip({ cursor: { idx: 0, left: 5, top: 4 } })

  assert.equal(chart.tooltipLayer.style.left, "27px")
  assert.equal(chart.tooltipLayer.style.top, "36px")
  assert.equal(chart.tooltipLayer.dataset.chartTooltipPlacementX, "right")
  assert.equal(chart.tooltipLayer.dataset.chartTooltipPlacementY, "below")
}

{
  context.document = { createElement: fakeElement }
  const chart = chartWithPlot()
  chart.eventMarkers = [
    {
      marker_type: "source_health_transition",
      timestamp_ms: 1781697600000,
      source_health_event_id: "legacy-source-health-event",
      link_id: "source_health_event:legacy-source-health-event",
    },
  ]

  chart.renderEventMarkers()

  assert.equal(chart.eventLayer.children.length, 0)
}

{
  context.document = { createElement: fakeElement }
  const chart = chartWithPlot()
  chart.annotations = [
    {
      annotation_id: "cadence.source-health:outage:source-health-event-1",
      provider_id: "cadence.source-health",
      layer_id: "source-status",
      geometry: "interval",
      starts_at_ms: 1781697600000,
      ends_at_ms: 1781697660000,
      title: "Limits source unavailable",
      text: "The managed limits projection stopped responding.",
      tags: ["limits", "unavailable"],
      color: "red",
      glyph: "SOURCE",
      link_id: "source_health_event:source-health-event-1",
      target: "source_health_event",
      target_id: "source-health-event-1",
      requested_realm: "replay",
      requested_data_source_id: "managed-events-projection",
      requested_source_binding_id: "replay-events",
      time_mode: "replay_run",
      time_axis: "occurred_at",
      replay_run_id: "replay-run-1",
      metadata: {
        realm: "replay",
        data_source_id: "managed-operational-observables",
        source_binding_id: "replay-operational-observables",
      },
    },
  ]

  chart.renderAnnotations()

  assert.equal(chart.annotationLayer.children.length, 2)
  const [region, anchor] = chart.annotationLayer.children
  const [control, tooltip] = anchor.children
  const evidenceControl = tooltip.querySelector("[data-chart-annotation-open-evidence='true']")
  assert.equal(region.dataset.chartAnnotationLayer, "source-status")
  assert.equal(region.style.pointerEvents, "none")
  assert.equal(region.style.height, "120px")
  assert.match(region.style.borderLeft, /^2px dashed rgba\(/)
  assert.match(region.style.borderRight, /^2px dashed rgba\(/)
  assert.match(region.style.background, /10%/)
  assert.equal(anchor.style.pointerEvents, "none")
  assert.equal(anchor.style.height, "5px")
  assert.equal(control.dataset.chartAnnotationControl, "true")
  assert.equal(control.dataset.chartAnnotationGeometry, "interval")
  assert.equal(control.style.pointerEvents, "auto")
  assert.equal(control.style.height, "5px")
  assert.equal(control.attributes["aria-expanded"], "false")
  assert.equal(tooltip.hidden, true)
  assert.equal(tooltip.attributes.role, "tooltip")
  assert.equal(tooltip.dataset.chartAnnotationId, chart.annotations[0].annotation_id)
  assert.equal(tooltip.querySelector("[data-chart-annotation-tags='true']").children.length, 2)
  assert.equal(
    tooltip.querySelector("[data-chart-annotation-provenance='true']").textContent,
    "cadence.source-health / source-status"
  )

  anchor.listeners.mouseenter()
  assert.equal(tooltip.hidden, false)
  assert.equal(control.attributes["aria-expanded"], "true")
  anchor.listeners.mouseleave()
  assert.equal(tooltip.hidden, true)

  control.listeners.click({
    preventDefault() {},
    stopPropagation() {},
  })
  assert.equal(tooltip.hidden, false)
  assert.deepEqual(plain(chart.pushedEvents), [])

  evidenceControl.listeners.click({
    preventDefault() {},
    stopPropagation() {},
  })

  assert.deepEqual(plain(chart.pushedEvents), [
    {
      name: "open_data_link",
      payload: {
        "link-id": "source_health_event:source-health-event-1",
        "placement-id": "placement-1",
        target: "source_health_event",
        "target-id": "source-health-event-1",
        "timestamp-ms": 1781697600000,
        realm: "replay",
        "data-source-id": "managed-operational-observables",
        "source-binding-id": "replay-operational-observables",
        "time-mode": "replay_run",
        "time-axis": "occurred_at",
        "replay-run-id": "replay-run-1",
      },
    },
  ])
}

{
  context.document = { createElement: fakeElement }
  const chart = chartWithPlot()
  chart.annotations = [
    {
      annotation_id: "cadence.deployments:deployment:deploy-1",
      provider_id: "cadence.deployments",
      layer_id: "deployments",
      geometry: "point",
      starts_at_ms: 1781697660000,
      title: "Flight software deployed",
      color: "green",
    },
  ]

  chart.renderAnnotations()

  assert.equal(chart.annotationLayer.children.length, 2)
  const [line, anchor] = chart.annotationLayer.children
  const [control, tooltip] = anchor.children
  const [triangle] = control.children
  assert.equal(line.dataset.chartAnnotation, "point")
  assert.equal(line.style.width, "0")
  assert.match(line.style.borderLeft, /^2px dashed rgba\(/)
  assert.equal(line.style.pointerEvents, "none")
  assert.equal(anchor.dataset.chartAnnotationAnchor, "point")
  assert.equal(anchor.style.pointerEvents, "none")
  assert.equal(control.dataset.chartAnnotationGeometry, "point")
  assert.equal(control.style.pointerEvents, "auto")
  assert.equal(triangle.dataset.chartAnnotationPointGlyph, "true")
  assert.match(triangle.style.borderBottom, /^5px solid rgba\(/)
  assert.equal(tooltip.hidden, true)
  assert.equal(
    tooltip.querySelector("[data-chart-annotation-open-evidence='true']"),
    null
  )
}

{
  context.document = { createElement: fakeElement }
  context.devicePixelRatio = 2
  const chart = chartWithPlot()
  chart.chart.bbox = { left: 20, top: 40, width: 600, height: 240 }
  chart.annotations = [
    {
      annotation_id: "cadence.deployments:deployment:retina",
      provider_id: "cadence.deployments",
      layer_id: "deployments",
      geometry: "point",
      starts_at_ms: 1781697660000,
      title: "Retina-safe annotation",
      color: "violet",
    },
  ]

  chart.renderAnnotations()

  const [line, anchor] = chart.annotationLayer.children
  assert.equal(line.style.left, "160px")
  assert.equal(line.style.top, "20px")
  assert.equal(line.style.height, "120px")
  assert.equal(anchor.style.top, "140px")
  context.devicePixelRatio = 1
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

  assert.equal(chart.eventLayer.children.length, 0)
  assert.equal(chart.watermarkOverlayLayer.children.length, 1)
  const status = chart.watermarkOverlayLayer.children[0]
  assert.equal(status.dataset.sourceWatermarkStatus, "complete")
  assert.equal(status.dataset.sourceWatermarkLagMs, "1000")
  assert.equal(status.dataset.chartCursorPassthrough, "true")
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

  assert.equal(chart.watermarkOverlayLayer.children.length, 3)
  const [region, boundary, status] = chart.watermarkOverlayLayer.children
  assert.equal(chart.eventLayer.children.length, 0)
  assert.equal(region.dataset.sourceWatermarkIncompleteRegion, "stale")
  assert.equal(region.style.left, "150px")
  assert.equal(region.style.top, "0")
  assert.equal(region.style.width, "150px")
  assert.equal(boundary.dataset.watermarkBoundary, "stale")
  assert.equal(boundary.style.left, "150px")
  assert.equal(boundary.style.top, "0")
  assert.equal(boundary.dataset.chartCursorPassthrough, "true")
  assert.equal(status.dataset.sourceWatermarkStatus, "incomplete")
  assert.equal(status.dataset.chartCursorPassthrough, "true")
  assert.equal(status.style.left, "10px")
  assert.equal(status.style.top, "8px")
  assert.equal(status.textContent, "Incomplete · 1m behind")
  assert.equal(chart.el.dataset.watermarkBoundaryVisible, "true")
}

{
  context.document = { createElement: fakeElement }
  const chart = chartWithPlot()
  const plotOverlay = fakeElement("div")
  const nativeCursor = fakeElement("span")
  plotOverlay.appendChild(nativeCursor)
  chart.chart.over = plotOverlay
  chart.watermarkOverlayLayer = chart.buildWatermarkOverlayLayer()

  chart.attachWatermarkOverlayLayer()

  assert.equal(chart.watermarkOverlayLayer.dataset.chartWatermarkOverlayLayer, "true")
  assert.equal(chart.watermarkOverlayLayer.parentNode, plotOverlay)
  assert.equal(plotOverlay.children[0], chart.watermarkOverlayLayer)
  assert.equal(plotOverlay.children[1], nativeCursor)
}

{
  const chart = chartWithPlot()
  const control = fakeElement("button")
  const cursorUpdates = []
  const overlay = {
    getBoundingClientRect() {
      return { left: 100, top: 50 }
    },
  }

  chart.el.querySelector = (selector) => (selector === ".u-over" ? overlay : null)
  chart.chart.setCursor = (position, fire, publish) => {
    cursorUpdates.push({ position, fire, publish })
  }
  chart.installSharedCursorPassthrough(control)

  control.listeners.mousemove({ clientX: 132, clientY: 94 })
  control.listeners.mouseleave()

  assert.equal(control.dataset.chartCursorPassthrough, "true")
  assert.deepEqual(plain(cursorUpdates), [
    { position: { left: 32, top: 44 }, fire: true, publish: true },
    { position: { left: -10, top: -10 }, fire: true, publish: true },
  ])
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
  const chart = chartWithMarkers([], [], [
    { annotation_id: "annotation-existing", starts_at_ms: 1 },
  ])

  chart.appendMarkerPayload({
    annotations: [
      { annotation_id: "annotation-new", starts_at_ms: 2 },
      { annotation_id: "annotation-new", starts_at_ms: 2 },
    ],
  })

  assert.deepEqual(
    chart.annotations.map((annotation) => annotation.annotation_id),
    ["annotation-existing", "annotation-new"]
  )
}

{
  context.document = { createElement: fakeElement }
  const chart = chartWithPlot()
  chart.annotations = [
    {
      annotation_id: "cadence.contacts:scheduled_contact:contact-1",
      provider_id: "cadence.contacts",
      layer_id: "mission-contacts",
      geometry: "interval",
      starts_at_ms: 1781697600000,
      ends_at_ms: 1781697660000,
      title: "DSS-14 pass",
      color: "cyan",
      glyph: "CONTACT",
      link_id: "contact:contact-1",
      target: "contact",
      target_id: "contact-1",
      requested_realm: "flight",
      requested_data_view: "canonical",
      requested_data_source_id: "managed-events",
      requested_source_binding_id: "events-flight",
      time_mode: "archive",
      time_axis: "occurred_at",
    },
  ]

  chart.renderAnnotations()

  assert.equal(chart.annotationLayer.children.length, 2)
  const [region, anchor] = chart.annotationLayer.children
  const [control, tooltip] = anchor.children
  const evidenceControl = tooltip.querySelector("[data-chart-annotation-open-evidence='true']")
  assert.equal(region.dataset.chartAnnotation, "interval")
  assert.equal(region.dataset.chartAnnotationProvider, "cadence.contacts")
  assert.equal(region.style.pointerEvents, "none")
  assert.equal(anchor.dataset.chartAnnotationAnchor, "interval")
  assert.equal(anchor.style.pointerEvents, "none")
  assert.equal(control.dataset.chartAnnotationControl, "true")
  assert.equal(control.style.pointerEvents, "auto")
  assert.equal(control.style.height, "5px")

  control.listeners.click({
    preventDefault() {},
    stopPropagation() {},
  })
  assert.equal(tooltip.hidden, false)

  evidenceControl.listeners.click({
    preventDefault() {},
    stopPropagation() {},
  })

  assert.deepEqual(plain(chart.pushedEvents), [
    {
      name: "open_data_link",
      payload: {
        "link-id": "contact:contact-1",
        "placement-id": "placement-1",
        target: "contact",
        "target-id": "contact-1",
        "timestamp-ms": 1781697600000,
        realm: "flight",
        "data-view": "canonical",
        "data-source-id": "managed-events",
        "source-binding-id": "events-flight",
        "time-mode": "archive",
        "time-axis": "occurred_at",
      },
    },
  ])
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
  const payload = {
    series: [
      { id: "HK.counter", points: [[1000, 1, {}], [2000, 2, {}]] },
      { id: "HK.voltage", points: [[1500, 28.4, {}]] },
    ],
  }

  assert.equal(chart.seriesPayloadPointCount(payload), 3)
  assert.equal(chart.seriesPayloadLatestTimestampMs(payload), 2000)
}

{
  const chart = chartWithMarkers()
  chart.eventMarkers = []

  assert.equal(chart.liveStreamState(), "connecting")

  chart.liveHeartbeatObserved = true
  assert.equal(chart.liveStreamState(), "paused")

  chart.liveHeartbeatCurrent = true
  assert.equal(chart.liveStreamState(), "following")

  chart.liveReceivingSamples = true
  assert.equal(chart.liveStreamState(), "receiving")

  chart.eventMarkers = [
    {
      marker_type: "source_watermark_cursor",
      display_mode: "boundary",
      freshness_state: "stale",
    },
  ]
  assert.equal(chart.liveStreamState(), "delayed")

  chart.el.closest = () => ({
    dataset: { runtimeRefreshStatus: "degraded", runtimeSourceExecutionDegraded: "1" },
  })
  assert.equal(chart.liveStreamState(), "degraded")
}

{
  context.document = { createElement: fakeElement }
  const chart = chartWithPlot()
  chart.eventMarkers = []
  chart.liveHeartbeatObserved = true
  chart.liveHeartbeatCurrent = true
  chart.liveReceivingSamples = false
  chart.liveEdge = chart.buildLiveEdge()
  chart.renderLiveEdge()

  assert.equal(chart.liveEdge.hidden, false)
  assert.equal(chart.liveEdge.dataset.liveStreamState, "following")
  assert.equal(chart.liveEdgeLabel.textContent, "LIVE")
  assert.equal(chart.liveEdge.style.left, "246px")
  assert.equal(chart.el.dataset.liveStreamState, "following")
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
  const chart = chartWithMarkers([], [], [
    {
      annotation_id: "outside-visible-range",
      geometry: "interval",
      starts_at_ms: 1781680000000,
      ends_at_ms: 1781680060000,
    },
  ])
  chart.el.dataset.timeMode = "archive"

  assert.deepEqual(plain(chart.chartXRange(1781694000, 1781694060)), [1781694000, 1781694060])
}

{
  const chart = chartWithMarkers([], [
    {
      marker_type: "source_watermark_cursor",
      timestamp_ms: 1781694300000,
    },
  ])
  chart.el.dataset.timeMode = "archive"
  chart.el.dataset.timeFrom = new Date(1781694000000).toISOString()
  chart.el.dataset.timeTo = new Date(1781694060000).toISOString()

  assert.deepEqual(plain(chart.chartXRange(1781694000, 1781694060)), [1781694000, 1781694060])
}

{
  const chart = chartWithMarkers()
  chart.spanGaps = false
  chart.hiddenSeriesIds = new Set()
  chart.axisMode = "unit"
  chart.lineWidth = "normal"
  chart.fillOpacity = 0
  chart.showPoints = false
  chart.seriesList = [
    {
      id: "battery_voltage",
      label: "Battery voltage",
      role: "primary",
      points: [
        [1000, 1],
        [2000, 2],
        [3000, 3],
        [101000, 4],
        [102000, 5],
      ],
    },
  ]
  chart.rebuildPlotData()

  const series = chart.chartSeriesOptions(["cyan"])[0]
  const plot = {
    data: chart.plotData(),
    valToPos(value) {
      return value
    },
  }

  assert.deepEqual(plain(series.gaps(plot, 1, 0, 4, [])), [[3, 101]])
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
