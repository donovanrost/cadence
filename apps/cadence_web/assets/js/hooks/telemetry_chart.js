import uPlot from "../../vendor/uplot/uPlot.esm"

// Live telemetry strip chart. The LiveView owns the data: it embeds a
// `data-backfill` series on mount and pushes one consolidated "tlm:append"
// event per tick; every chart hook filters that event by its widget id.
// The container uses phx-update="ignore", so a context switch remounts the
// hook through a new DOM id rather than mutating it in place.
const TelemetryChart = {
  mounted() {
    this.widgetId = this.el.dataset.widgetId
    this.placementId = this.el.dataset.placementId
    this.windowSeconds = parseInt(this.el.dataset.windowSeconds, 10) || 300
    this.liveWindowEnd = null
    this.liveHeartbeatObserved = false
    this.liveHeartbeatCurrent = false
    this.liveReceivingSamples = false
    this.liveArrivalSequence = 0
    this.liveHeartbeatTimer = null
    this.liveArrivalTimer = null
    if (this.liveMode()) this.advanceLiveWindow(Date.now())

    const backfill = JSON.parse(this.el.dataset.backfill || "[]")
    const compareBackfill = JSON.parse(this.el.dataset.compareBackfill || "[]")
    const primarySeries = this.normalizeSeriesPayload(backfill)
    const compareSeries = this.normalizeCompareSeriesPayload(compareBackfill)
    this.seriesList = primarySeries.concat(compareSeries)
    this.el.dataset.compareSeriesCount = `${compareSeries.length}`
    this.hiddenSeriesIds = new Set()
    this.axisMode = this.el.dataset.axisMode === "shared" ? "shared" : "unit"
    this.legendMode = this.el.dataset.legendMode || "auto"
    this.lineWidth = this.el.dataset.lineWidth || "normal"
    this.fillOpacity = Math.max(0, Math.min(30, parseInt(this.el.dataset.fillOpacity, 10) || 0))
    this.spanGaps = this.el.dataset.spanGaps === "true"
    this.showPoints = this.el.dataset.showPoints === "true"
    this.showMinMaxBand = this.el.dataset.showMinMaxBand !== "false"
    this.sharedTooltip = this.el.dataset.sharedTooltip !== "false"
    this.rebuildPlotData()
    this.limitMarkers = JSON.parse(this.el.dataset.limitMarkers || "[]")
    this.eventMarkers = this.collapseSourceWatermarkMarkers(
      JSON.parse(this.el.dataset.eventMarkers || "[]")
    )
    this.selectedRef = JSON.parse(this.el.dataset.selectedRef || "null")

    this.el.style.position = "relative"
    this.chart = new uPlot(this.chartOptions(), this.plotData(), this.el)
    this.installRangeSelection()
    this.watermarkOverlayLayer = this.buildWatermarkOverlayLayer()
    this.attachWatermarkOverlayLayer()
    this.eventLayer = this.buildEventLayer()
    this.el.appendChild(this.eventLayer)
    this.markerLayer = this.buildMarkerLayer()
    this.el.appendChild(this.markerLayer)
    this.selectionLayer = this.buildSelectionLayer()
    this.el.appendChild(this.selectionLayer)
    this.liveEdge = this.buildLiveEdge()
    this.el.appendChild(this.liveEdge)
    this.legendLayer = this.buildLegendLayer()
    this.el.appendChild(this.legendLayer)
    this.renderEventMarkers()
    this.renderLimitMarkers()
    this.renderLegend()
    this.renderLiveEdge()
    this.tooltipLayer = this.buildTooltipLayer()
    this.el.appendChild(this.tooltipLayer)
    this.renderSelection()
    this.handleClick = (event) => this.openPointInspector(event)
    this.el.addEventListener("click", this.handleClick)

    this.handleEvent("tlm:append", ({
      series,
      markers,
      window_end_ms: windowEndMs,
      refresh_interval_ms: refreshIntervalMs,
    }) => {
      const points = series && (series[this.widgetId] || series[this.placementId])
      const appendedPointCount = this.seriesPayloadPointCount(points)
      const previousPlotSeriesLength = (this.plotSeries || []).length
      const appendedSeries = this.appendSeriesPayload(points)

      const markerAppends = markers && (markers[this.widgetId] || markers[this.placementId])
      const appendedMarkers = this.appendMarkerPayload(markerAppends)
      const advancedLiveWindow = this.advanceLiveWindow(windowEndMs)
      this.recordLiveActivity({
        appendedPointCount,
        advancedLiveWindow,
        refreshIntervalMs,
        seriesPayload: points,
        windowEndMs,
      })
      if (!appendedSeries && !appendedMarkers && !advancedLiveWindow) return

      this.trimToWindow()

      if ((this.plotSeries || []).length !== previousPlotSeriesLength) {
        this.rebuildChart()
      } else {
        this.chart.setData(this.plotData())
        this.renderEventMarkers()
        this.renderLimitMarkers()
        this.renderLegend()
        this.renderSelection()
        this.renderLiveEdge()
      }
    })

    this.handleEvent("tlm:select", ({ selection }) => {
      this.selectedRef = selection || null
      this.renderSelection()
    })

    this.resizeObserver = new ResizeObserver(() => {
      this.renderLegend()
      this.chart.setSize(this.chartSize())
      this.renderEventMarkers()
      this.renderLimitMarkers()
      this.renderSelection()
      this.renderLiveEdge()
    })
    this.resizeObserver.observe(this.el)
  },

  destroyed() {
    if (this.handleClick) this.el.removeEventListener("click", this.handleClick)
    if (this.resizeObserver) this.resizeObserver.disconnect()
    if (this.liveHeartbeatTimer) clearTimeout(this.liveHeartbeatTimer)
    if (this.liveArrivalTimer) clearTimeout(this.liveArrivalTimer)
    if (this.rangeSelectionOverlay && this.handleRangeSelection) {
      this.rangeSelectionOverlay.removeEventListener("mouseup", this.handleRangeSelection)
    }
    if (this.chart) this.chart.destroy()
  },

  appendMarkerPayload(markerAppends) {
    if (Array.isArray(markerAppends) && markerAppends.length > 0) {
      this.limitMarkers = this.dedupeMarkers(this.limitMarkers.concat(markerAppends))
      return true
    }

    if (!markerAppends) return false

    const limitMarkerAppends = markerAppends.limit_markers || []
    const eventMarkerAppends = markerAppends.event_markers || []
    let appended = false

    if (limitMarkerAppends.length > 0) {
      this.limitMarkers = this.dedupeMarkers(this.limitMarkers.concat(limitMarkerAppends))
      appended = true
    }

    if (eventMarkerAppends.length > 0) {
      this.eventMarkers = this.collapseSourceWatermarkMarkers(
        this.dedupeMarkers(this.eventMarkers.concat(eventMarkerAppends))
      )
      appended = true
    }

    return appended
  },

  rebuildChart() {
    if (this.chart) this.chart.destroy()

    this.chart = new uPlot(this.chartOptions(), this.plotData(), this.el)
    this.installRangeSelection()
    this.attachWatermarkOverlayLayer()
    this.el.appendChild(this.eventLayer)
    this.el.appendChild(this.markerLayer)
    this.el.appendChild(this.selectionLayer)
    this.el.appendChild(this.liveEdge)
    this.el.appendChild(this.legendLayer)
    if (this.tooltipLayer) this.el.appendChild(this.tooltipLayer)
    this.renderEventMarkers()
    this.renderLimitMarkers()
    this.renderLegend()
    this.renderSelection()
    this.renderLiveEdge()
  },

  normalizeSeriesPayload(payload) {
    if (Array.isArray(payload)) {
      return [this.normalizeSeries({ points: payload })].filter((series) => series.points.length > 0)
    }

    if (payload && Array.isArray(payload.series)) {
      return payload.series
        .map((series) => this.normalizeSeries(series))
        .filter((series) => series.points.length > 0)
    }

    if (payload && Array.isArray(payload.points)) {
      return [this.normalizeSeries(payload)].filter((series) => series.points.length > 0)
    }

    return []
  },

  normalizeCompareSeriesPayload(payload) {
    return this.normalizeSeriesPayload(payload).map((series) => {
      const primaryId = series.compare_of || series.id || this.widgetId
      const compareId = `${primaryId}`.startsWith("compare:") ? `${primaryId}` : `compare:${primaryId}`

      return {
        ...series,
        id: compareId,
        label: `${series.label || primaryId} compare`,
        role: "compare",
        compare_of: primaryId,
      }
    })
  },

  normalizeSeries(series) {
    const fallback = this.seriesList && this.seriesList[0]
    const id = series.id || series.observable_id || (fallback && fallback.id) || this.widgetId
    const label = series.label || series.observable_id || (fallback && fallback.label) || this.el.dataset.label || id

    return {
      id,
      label,
      observable_id: series.observable_id || (fallback && fallback.observable_id) || null,
      unit: series.unit || (fallback && fallback.unit) || this.el.dataset.unit || null,
      source: series.source || (fallback && fallback.source) || null,
      frame_id: series.frame_id || (fallback && fallback.frame_id) || null,
      field: series.field || (fallback && fallback.field) || null,
      time_axis: series.time_axis || (fallback && fallback.time_axis) || null,
      sampling: series.sampling || (fallback && fallback.sampling) || null,
      decimation: series.decimation || (fallback && fallback.decimation) || null,
      data_source_id: series.data_source_id || (fallback && fallback.data_source_id) || null,
      source_binding_id: series.source_binding_id || (fallback && fallback.source_binding_id) || null,
      role: series.role || (fallback && fallback.role) || "primary",
      compare_of: series.compare_of || (fallback && fallback.compare_of) || null,
      envelope: this.normalizeEnvelope(series.envelope || (fallback && fallback.envelope) || null),
      points: this.normalizePoints(series.points || []),
    }
  },

  normalizePoints(points) {
    return points
      .map((point) => {
        if (!Array.isArray(point) || point.length < 2) return null

        const timestampMs = Number(point[0])
        const value = Number(point[1])
        if (!Number.isFinite(timestampMs) || !Number.isFinite(value)) return null

        return [timestampMs, value, point[2] || {}]
      })
      .filter((point) => point !== null)
  },

  normalizeEnvelope(envelope) {
    if (!envelope || !Array.isArray(envelope.points)) return null

    const points = envelope.points
      .map((point) => {
        if (!Array.isArray(point) || point.length < 3) return null

        const timestampMs = Number(point[0])
        const min = Number(point[1])
        const max = Number(point[2])
        if (!Number.isFinite(timestampMs) || !Number.isFinite(min) || !Number.isFinite(max)) return null

        return [timestampMs, min, max, point[3] || {}]
      })
      .filter((point) => point !== null)

    if (points.length === 0) return null

    return {
      kind: envelope.kind || "min_max",
      lower_field: envelope.lower_field || null,
      upper_field: envelope.upper_field || null,
      sample_count_field: envelope.sample_count_field || null,
      points,
    }
  },

  appendSeriesPayload(payload) {
    const incoming = this.normalizeSeriesPayload(payload)
    if (incoming.length === 0) return false

    incoming.forEach((series) => {
      const index = this.seriesList.findIndex((existing) => existing.id === series.id)

      if (index >= 0) {
        const previous = this.seriesList[index]

        this.seriesList[index] = {
          ...previous,
          ...series,
          points: previous.points.concat(series.points),
          envelope: this.mergeEnvelope(previous.envelope, series.envelope),
        }
      } else {
        this.seriesList.push(series)
      }
    })

    this.rebuildPlotData()
    return true
  },

  seriesPayloadPointCount(payload) {
    return this.normalizeSeriesPayload(payload).reduce(
      (count, series) => count + series.points.length,
      0
    )
  },

  seriesPayloadLatestTimestampMs(payload) {
    const timestamps = this.normalizeSeriesPayload(payload).flatMap((series) =>
      series.points.map(([timestampMs]) => Number(timestampMs))
    )
    const valid = timestamps.filter((timestampMs) => Number.isFinite(timestampMs))

    return valid.length > 0 ? Math.max(...valid) : null
  },

  mergeEnvelope(previous, incoming) {
    if (!previous) return incoming
    if (!incoming) return previous

    return {
      ...previous,
      ...incoming,
      points: previous.points.concat(incoming.points),
    }
  },

  rebuildPlotData() {
    const xs = Array.from(
      new Set(
        this.seriesList.flatMap((series) => {
          const pointTimes = series.points.map(([timestampMs]) => timestampMs / 1000)
          const envelopeTimes = series.envelope
            ? series.envelope.points.map(([timestampMs]) => timestampMs / 1000)
            : []

          return pointTimes.concat(envelopeTimes)
        })
      )
    ).sort((a, b) => a - b)

    this.xs = xs
    this.seriesYs = []
    this.seriesPointMeta = []
    this.plotSeries = []

    this.seriesList.forEach((series, seriesIndex) => {
      const pointsByTime = new Map(
        series.points.map(([timestampMs, value, metadata = {}]) => [
          timestampMs / 1000,
          {
            value,
            metadata: {
              ...metadata,
              series_id: series.id,
              series_label: series.label,
              observable_id: series.observable_id,
              series_index: seriesIndex,
              series_role: series.role || "primary",
              compare_of: series.compare_of || null,
              data_source_id: series.data_source_id || this.el.dataset.dataSourceId || null,
              source_binding_id: series.source_binding_id || this.el.dataset.sourceBindingId || null,
              time_axis: series.time_axis || this.el.dataset.timeAxis || null,
              data_view:
                series.role === "compare"
                  ? this.el.dataset.compareDataView || null
                  : this.el.dataset.dataView || null,
            },
          },
        ])
      )

      this.seriesYs.push(xs.map((x) => (pointsByTime.has(x) ? pointsByTime.get(x).value : null)))
      this.seriesPointMeta.push(xs.map((x) => (pointsByTime.has(x) ? pointsByTime.get(x).metadata : {})))
      this.plotSeries.push({ kind: "line", seriesIndex })

      if (series.envelope && this.showMinMaxBand) {
        const envelopeByTime = new Map(
          series.envelope.points.map(([timestampMs, min, max]) => [
            timestampMs / 1000,
            { min, max },
          ])
        )

        this.plotSeries.push({
          kind: "envelope_low",
          seriesIndex,
          values: xs.map((x) => (envelopeByTime.has(x) ? envelopeByTime.get(x).min : null)),
        })
        this.plotSeries.push({
          kind: "envelope_high",
          seriesIndex,
          values: xs.map((x) => (envelopeByTime.has(x) ? envelopeByTime.get(x).max : null)),
        })
      }
    })

    const pointTimestamps = this.seriesList.flatMap((series) =>
      series.points.map(([timestampMs]) => timestampMs)
    )

    this.el.dataset.chartPointCount = `${pointTimestamps.length}`
    this.el.dataset.chartLatestTimestampMs =
      pointTimestamps.length > 0
        ? `${pointTimestamps.reduce((latest, timestampMs) => Math.max(latest, timestampMs), 0)}`
        : ""
  },

  plotData() {
    const series = (this.plotSeries || []).map((entry) => {
      if (entry.kind === "line") return this.seriesYs[entry.seriesIndex]
      return entry.values
    })

    return [this.xs].concat(series)
  },

  seriesGaps(plot, uPlotSeriesIndex, idx0, idx1, nullGaps = []) {
    const entry = (this.plotSeries || [])[uPlotSeriesIndex - 1]
    if (!entry) return nullGaps

    const xs = (plot.data && plot.data[0]) || this.xs || []
    const ys =
      (plot.data && plot.data[uPlotSeriesIndex]) ||
      (entry.kind === "line" ? this.seriesYs[entry.seriesIndex] : entry.values) ||
      []
    const observed = []
    const fromIndex = Math.max(0, idx0)
    const toIndex = Math.min(idx1, xs.length - 1, ys.length - 1)

    for (let index = fromIndex; index <= toIndex; index += 1) {
      const x = Number(xs[index])
      const y = ys[index]
      if (Number.isFinite(x) && y !== null && y !== undefined && Number.isFinite(Number(y))) {
        observed.push(x)
      }
    }

    const threshold = this.inferredGapThreshold(observed)
    if (!Number.isFinite(threshold)) return nullGaps

    const inferredGaps = []

    for (let index = 1; index < observed.length; index += 1) {
      const previous = observed[index - 1]
      const current = observed[index]
      if (current - previous <= threshold) continue

      const from = plot.valToPos(previous, "x", true)
      const to = plot.valToPos(current, "x", true)
      if (Number.isFinite(from) && Number.isFinite(to)) inferredGaps.push([from, to])
    }

    return this.mergePixelGaps(nullGaps.concat(inferredGaps))
  },

  inferredGapThreshold(observed) {
    const intervals = observed
      .slice(1)
      .map((value, index) => value - observed[index])
      .filter((value) => Number.isFinite(value) && value > 0)

    if (intervals.length < 3) return null

    const sorted = intervals.slice().sort((left, right) => left - right)
    const middle = Math.floor(sorted.length / 2)
    const median =
      sorted.length % 2 === 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]

    return Math.max(median * 3, 5)
  },

  mergePixelGaps(gaps) {
    return gaps
      .map(([from, to]) => [Math.min(from, to), Math.max(from, to)])
      .filter(([from, to]) => Number.isFinite(from) && Number.isFinite(to) && to > from)
      .sort((left, right) => left[0] - right[0])
      .reduce((merged, gap) => {
        const previous = merged[merged.length - 1]
        if (previous && gap[0] <= previous[1]) previous[1] = Math.max(previous[1], gap[1])
        else merged.push(gap)
        return merged
      }, [])
  },

  trimToWindow() {
    const windowEnd = this.chartWindowEnd()
    if (!Number.isFinite(windowEnd)) return

    const cutoff = windowEnd - this.windowSeconds
    this.seriesList = this.seriesList.map((series) => ({
      ...series,
      points: series.points.filter(([timestampMs]) => timestampMs / 1000 >= cutoff),
      envelope: series.envelope
        ? {
            ...series.envelope,
            points: series.envelope.points.filter(([timestampMs]) => timestampMs / 1000 >= cutoff),
          }
        : null,
    }))
    this.rebuildPlotData()
    this.limitMarkers = this.limitMarkers.filter((marker) => this.limitMarkerOverlapsWindow(marker, cutoff))
    this.eventMarkers = this.eventMarkers.filter((marker) => this.eventMarkerOverlapsWindow(marker, cutoff))
  },

  openPointInspector(event) {
    if (this.rangeSelectionInFlight) return
    const index = this.pointIndexFromEvent(event)
    if (index === null || index === undefined) return

    const metadata = this.pointMetadataAt(index, event)
    if (!metadata.link_id) return

    this.pushEvent("open_data_link", this.pointDataLinkPayload(metadata, Math.round(this.xs[index] * 1000)))
  },

  pointDataLinkPayload(metadata, timestampMs) {
    const target = metadata.target || metadata.link_target || (metadata.sample_id ? "telemetry_sample" : null)
    const targetId = metadata.target_id || metadata.link_target_id || metadata.sample_id

    return this.compactPayload({
      "link-id": metadata.link_id,
      "placement-id": this.placementId,
      target,
      "target-id": targetId,
      "timestamp-ms": timestampMs,
      "series-role": metadata.series_role,
      "compare-of": metadata.compare_of,
      realm: this.el.dataset.dataRealm,
      "data-view": metadata.data_view,
      "data-source-id": metadata.data_source_id || this.el.dataset.dataSourceId,
      "source-binding-id": metadata.source_binding_id || this.el.dataset.sourceBindingId,
      "time-mode": this.el.dataset.timeMode,
      "time-axis": metadata.time_axis || this.el.dataset.timeAxis,
      "replay-run-id": this.el.dataset.replayRunId,
    })
  },

  markerDataLinkPayload(marker, target, targetId, timestampMs) {
    return this.compactPayload({
      "link-id": marker.link_id,
      "placement-id": this.placementId,
      target,
      "target-id": targetId,
      "timestamp-ms": timestampMs,
      realm: marker.requested_realm || marker.realm,
      "data-view": marker.requested_data_view || marker.data_view,
      "data-source-id": marker.requested_data_source_id || marker.data_source_id,
      "source-binding-id": marker.requested_source_binding_id || marker.source_binding_id,
      "time-mode": marker.time_mode,
      "time-axis": marker.time_axis,
      "replay-run-id": marker.replay_run_id,
    })
  },

  compactPayload(payload) {
    return Object.fromEntries(
      Object.entries(payload).filter(([, value]) => value !== null && value !== undefined && value !== "")
    )
  },

  pointMetadataAt(index, event) {
    const seriesMeta = this.seriesPointMeta || []
    const pointerTop = this.pointerTop(event)
    const candidates = []

    for (let seriesIndex = 0; seriesIndex < seriesMeta.length; seriesIndex += 1) {
      const series = this.seriesList[seriesIndex]
      if (!this.seriesVisible(series)) continue

      const metadataByTime = seriesMeta[seriesIndex]
      const metadata = metadataByTime[index] || {}
      if (!metadata.link_id) continue

      const value = this.seriesYs[seriesIndex] && this.seriesYs[seriesIndex][index]
      if (value === null || value === undefined) continue

      const top =
        (this.chart.bbox.top || 0) + this.chart.valToPos(value, this.unitScaleKey(series.unit), false)

      candidates.push({
        metadata,
        distance: pointerTop === null || Number.isNaN(top) ? 0 : Math.abs(top - pointerTop),
      })
    }

    candidates.sort((left, right) => left.distance - right.distance)
    return (candidates[0] && candidates[0].metadata) || {}
  },

  pointerTop(event) {
    const overlay = this.el.querySelector(".u-over")
    if (!overlay || !event) return null

    const rect = overlay.getBoundingClientRect()
    const top = event.clientY - rect.top
    if (top < 0 || top > rect.height) return null

    return top
  },

  pointIndexFromEvent(event) {
    if (!this.chart || this.xs.length === 0) return null

    const overlay = this.el.querySelector(".u-over")
    if (!overlay) return this.chart.cursor && this.chart.cursor.idx

    const rect = overlay.getBoundingClientRect()
    const left = event.clientX - rect.left
    if (left < 0 || left > rect.width) return null

    return this.chart.posToIdx(left)
  },

  buildMarkerLayer() {
    const layer = document.createElement("div")
    layer.className = "telemetry-chart-limit-markers"
    layer.setAttribute("aria-hidden", "false")
    Object.assign(layer.style, {
      position: "absolute",
      inset: "0",
      bottom: `${this.legendHeight()}px`,
      pointerEvents: "none",
      zIndex: "3",
    })
    return layer
  },

  buildEventLayer() {
    const layer = document.createElement("div")
    layer.className = "telemetry-chart-event-overlays"
    layer.setAttribute("aria-hidden", "false")
    Object.assign(layer.style, {
      position: "absolute",
      inset: "0",
      bottom: `${this.legendHeight()}px`,
      pointerEvents: "none",
      zIndex: "2",
    })
    return layer
  },

  buildWatermarkOverlayLayer() {
    const layer = document.createElement("div")
    layer.className = "telemetry-chart-watermark-overlays"
    layer.dataset.chartWatermarkOverlayLayer = "true"
    Object.assign(layer.style, {
      position: "absolute",
      inset: "0",
      pointerEvents: "none",
    })
    return layer
  },

  attachWatermarkOverlayLayer() {
    const plotOverlay = (this.chart && this.chart.over) || this.el.querySelector(".u-over")
    if (!plotOverlay || !this.watermarkOverlayLayer) return

    // uPlot appends its native cursor after this layer. Keeping the watermark
    // wash inside `.u-over` but before the cursor lets it tint the plot without
    // covering the synchronized crosshair.
    plotOverlay.insertBefore(this.watermarkOverlayLayer, plotOverlay.firstChild)
  },

  buildSelectionLayer() {
    const layer = document.createElement("div")
    layer.className = "telemetry-chart-selection"
    Object.assign(layer.style, {
      position: "absolute",
      inset: "0",
      bottom: `${this.legendHeight()}px`,
      pointerEvents: "none",
      zIndex: "4",
    })
    return layer
  },

  buildLiveEdge() {
    const edge = document.createElement("div")
    edge.className = "telemetry-chart-live-edge"
    edge.dataset.liveStreamEdge = ""
    edge.setAttribute("role", "status")

    const wash = document.createElement("span")
    wash.className = "telemetry-chart-live-edge-wash"
    edge.appendChild(wash)

    const line = document.createElement("span")
    line.className = "telemetry-chart-live-edge-line"
    edge.appendChild(line)

    const beacon = document.createElement("span")
    beacon.className = "telemetry-chart-live-edge-beacon"
    edge.appendChild(beacon)

    const label = document.createElement("span")
    label.className = "telemetry-chart-live-edge-label"
    edge.appendChild(label)

    this.liveEdgeLabel = label
    return edge
  },

  buildLegendLayer() {
    const layer = document.createElement("div")
    layer.className = "telemetry-chart-legend"
    layer.dataset.chartLegend = "series"
    Object.assign(layer.style, {
      position: "absolute",
      left: "0",
      right: "0",
      bottom: "0",
      minHeight: `${this.legendHeight()}px`,
      display: "flex",
      flexWrap: "wrap",
      alignItems: "center",
      justifyContent: "flex-start",
      gap: "10px",
      overflow: "hidden",
      padding: "4px 8px",
      pointerEvents: "none",
      zIndex: "5",
    })
    return layer
  },

  buildTooltipLayer() {
    const layer = document.createElement("div")
    layer.dataset.chartSharedTooltip = "true"
    Object.assign(layer.style, {
      position: "absolute",
      left: "6px",
      top: "4px",
      display: "none",
      maxWidth: "55%",
      border: "1px solid rgba(204, 204, 220, 0.2)",
      borderRadius: "2px",
      background: "rgba(17, 18, 23, 0.96)",
      boxShadow: "0 4px 12px rgba(0, 0, 0, 0.35)",
      color: "rgba(230, 230, 235, 0.94)",
      font: "11px ui-sans-serif, system-ui, sans-serif",
      lineHeight: "1.45",
      padding: "6px 8px",
      pointerEvents: "none",
      zIndex: "6",
    })
    return layer
  },

  renderSharedTooltip(u) {
    if (!this.tooltipLayer || !this.sharedTooltip) return

    const index = u && u.cursor && u.cursor.idx
    if (!Number.isInteger(index) || !Number.isFinite(this.xs[index])) {
      this.tooltipLayer.style.display = "none"
      return
    }

    const rows = this.seriesList.flatMap((series, seriesIndex) => {
      if (!this.seriesVisible(series)) return []
      const value = this.seriesYs[seriesIndex] && this.seriesYs[seriesIndex][index]
      if (!Number.isFinite(value)) return []
      return [`${series.label || series.id}: ${value}${series.unit ? ` ${series.unit}` : ""}`]
    })

    if (rows.length === 0) {
      this.tooltipLayer.style.display = "none"
      return
    }

    const timestamp = new Date(this.xs[index] * 1000).toISOString()
    this.tooltipLayer.textContent = `${timestamp}\n${rows.join("  ·  ")}`
    this.tooltipLayer.style.whiteSpace = "pre-wrap"
    this.tooltipLayer.style.display = "block"
  },

  renderLegend() {
    if (!this.legendLayer) return

    this.legendLayer.replaceChildren()
    const visible = this.legendVisible()
    this.legendLayer.dataset.chartLegendVisible = visible ? "true" : "false"
    this.legendLayer.style.display = visible ? "flex" : "none"
    if (!visible) return

    const sourceUnitGroups = this.sourceUnitGroups()

    const palette = this.chartPalette()

    if (sourceUnitGroups.length > 1) {
      this.legendLayer.appendChild(this.axisModeButton())
    }

    this.seriesList.forEach((series, index) => {
      const item = document.createElement("button")
      const visible = this.seriesVisible(series)

      item.type = "button"
      item.dataset.chartLegendItem = series.id || `${index}`
      item.dataset.chartLegendUnit = series.unit || ""
      item.dataset.chartLegendScale = this.unitScaleKey(series.unit)
      item.dataset.chartSeriesRole = series.role || "primary"
      item.dataset.chartSeriesHidden = visible ? "false" : "true"
      item.setAttribute("aria-pressed", visible ? "true" : "false")
      item.title = `${series.label || series.id}${series.unit ? ` (${series.unit})` : ""}`
      item.setAttribute("aria-label", `${visible ? "Hide" : "Show"} ${item.title}`)

      const swatch = document.createElement("span")
      Object.assign(swatch.style, {
        width: "14px",
        height: "2px",
        borderRadius: "1px",
        background: this.seriesLegendColor(series, index, palette),
        flex: "0 0 auto",
      })

      if (series.role === "compare") {
        swatch.style.borderRadius = "0"
        swatch.style.height = "2px"
        swatch.style.borderTop = `1px dashed ${this.seriesLegendColor(series, index, palette)}`
        swatch.style.background = "transparent"
      }

      const label = document.createElement("span")
      label.textContent = this.legendLabel(series)
      Object.assign(label.style, {
        overflow: "hidden",
        textOverflow: "ellipsis",
        whiteSpace: "nowrap",
      })

      Object.assign(item.style, {
        display: "inline-flex",
        alignItems: "center",
        gap: "4px",
        maxWidth: "220px",
        border: "0",
        borderRadius: "2px",
        background: "transparent",
        color: visible ? "rgba(204, 204, 220, 0.9)" : "rgba(153, 153, 170, 0.62)",
        cursor: "pointer",
        font: "500 11px ui-sans-serif, system-ui, sans-serif",
        lineHeight: "1",
        padding: "2px 0",
        opacity: visible ? "1" : "0.58",
        pointerEvents: "auto",
      })

      if (!visible) {
        label.style.textDecoration = "line-through"
      }

      item.addEventListener("click", (event) => {
        event.preventDefault()
        event.stopPropagation()
        this.toggleSeries(series.id)
      })

      item.appendChild(swatch)
      item.appendChild(label)
      this.legendLayer.appendChild(item)
    })
  },

  axisModeButton() {
    const button = document.createElement("button")
    const nextMode = this.axisMode === "unit" ? "shared" : "unit"

    button.type = "button"
    button.dataset.chartAxisMode = this.axisMode
    button.title =
      this.axisMode === "unit"
        ? "Switch chart to one shared value axis"
        : "Group chart axes by engineering unit"
    button.setAttribute("aria-label", button.title)
    button.textContent = this.axisMode === "unit" ? "Axis: unit" : "Axis: shared"
    Object.assign(button.style, {
      border: "0",
      borderRadius: "2px",
      background: "transparent",
      color: "rgba(204, 204, 220, 0.72)",
      cursor: "pointer",
      font: "500 11px ui-sans-serif, system-ui, sans-serif",
      lineHeight: "1",
      padding: "2px 0",
      pointerEvents: "auto",
    })

    button.addEventListener("click", (event) => {
      event.preventDefault()
      event.stopPropagation()
      this.axisMode = nextMode
      this.rebuildChart()
    })

    return button
  },

  toggleSeries(seriesId) {
    if (!seriesId) return

    if (this.hiddenSeriesIds.has(seriesId)) {
      this.hiddenSeriesIds.delete(seriesId)
      this.rebuildChart()
      return
    }

    if (this.visibleSeriesCount() <= 1) return

    this.hiddenSeriesIds.add(seriesId)
    this.rebuildChart()
  },

  visibleSeriesCount() {
    return this.seriesList.filter((series) => this.seriesVisible(series)).length
  },

  legendVisible() {
    if (this.legendMode === "hidden") return false
    if (this.legendMode === "always") return this.seriesList.length > 0

    return this.seriesList.length > 1 || this.sourceUnitGroups().length > 1
  },

  legendHeight() {
    return this.legendVisible() ? 28 : 0
  },

  seriesVisible(series) {
    return !series || !series.id || !this.hiddenSeriesIds.has(series.id)
  },

  legendLabel(series) {
    const label = series.label || series.id || this.widgetId
    return series.unit ? `${label} [${series.unit}]` : label
  },

  renderEventMarkers() {
    if (!this.eventLayer || !this.chart) return

    this.eventLayer.replaceChildren()
    if (this.watermarkOverlayLayer) this.watermarkOverlayLayer.replaceChildren()
    delete this.el.dataset.watermarkState
    delete this.el.dataset.watermarkLagMs
    delete this.el.dataset.watermarkBoundaryVisible

    this.eventMarkers.forEach((marker) => {
      if (marker.marker_type === "source_binding_interval") {
        this.renderSourceBindingInterval(marker)
        return
      }

      if (marker.marker_type === "retention_gap") {
        this.renderRetentionGap(marker)
        return
      }

      if (marker.marker_type === "source_watermark_cursor" || marker.marker_type === "source_watermark_event") {
        this.renderSourceWatermarkCursor(marker)
        return
      }

      if (marker.marker_type === "source_health_transition") {
        this.renderSourceHealthTransition(marker)
        return
      }

      if (marker.marker_type === "telemetry_revision_range") {
        this.renderTelemetryRevisionRange(marker)
        return
      }

      if (marker.marker_type === "telemetry_backfill_lifecycle") {
        this.renderTelemetryBackfillLifecycle(marker)
        return
      }

      if (marker.marker_type === "telemetry_revision_decision") {
        this.renderTelemetryRevisionDecision(marker)
        return
      }

      if (marker.marker_type === "mission_event") {
        this.renderMissionEvent(marker)
      }
    })
  },

  renderSourceBindingInterval(marker) {
    if (!marker.marker_id || !marker.starts_at_ms) return

    const interval = this.intervalBounds(marker)
    if (!interval) return

    const button = document.createElement("button")
    button.type = "button"
    button.title = `Inspect ${marker.label || "source binding interval"}`
    button.setAttribute("aria-label", button.title)
    button.dataset.eventMarkerTarget = "source binding"
    button.dataset.eventMarkerId = marker.source_binding_id || marker.target_id || ""
    button.dataset.eventMarkerRef = marker.marker_id || ""
    Object.assign(button.style, {
      position: "absolute",
      left: `${interval.left}px`,
      top: `${this.chart.bbox.top || 0}px`,
      width: `${interval.width}px`,
      height: `${this.chart.bbox.height || this.el.clientHeight}px`,
      border: "0",
      borderLeft: `1px solid ${this.sourceBindingIntervalColor(marker)}`,
      borderRight: `1px solid ${this.sourceBindingIntervalColor(marker)}`,
      padding: "0",
      background: "rgba(129, 140, 248, 0.07)",
      cursor: "pointer",
      pointerEvents: "auto",
    })

    button.addEventListener("click", (event) => {
      event.preventDefault()
      event.stopPropagation()
      const dataLinkPayload = this.sourceWatermarkDataLinkPayload(marker)
      if (dataLinkPayload) {
        this.pushEvent("open_data_link", dataLinkPayload)
        return
      }

      this.pushEvent("open_evidence", {
        kind: "source",
        "source-evidence-mode": "health",
        "source-evidence-state": marker.freshness_state,
        "source-request-id": marker.source_request_id,
        "logical-source": marker.logical_source,
        realm: marker.realm,
        "replay-run-id": marker.replay_run_id,
        "time-mode": marker.time_mode,
        "time-axis": marker.time_axis,
        "requested-realm": marker.requested_realm,
        "requested-data-view": marker.requested_data_view,
        "requested-data-source-id": marker.requested_data_source_id,
        "requested-source-binding-id": marker.requested_source_binding_id,
        "data-source-id": marker.data_source_id,
        "source-binding-id": marker.source_binding_id || marker.target_id,
        "placement-id": this.placementId,
      })
    })

    this.eventLayer.appendChild(button)
  },

  renderRetentionGap(marker) {
    if (!marker.marker_id || !marker.starts_at_ms || !marker.ends_at_ms) return

    const interval = this.intervalBounds(marker)
    if (!interval) return

    const button = document.createElement("button")
    button.type = "button"
    button.title = `Inspect ${marker.label || "retention gap"}`
    button.setAttribute("aria-label", button.title)
    button.dataset.eventMarkerTarget = "retention gap"
    button.dataset.eventMarkerId = marker.target_id || marker.data_source_id || ""
    button.dataset.eventMarkerRef = marker.marker_id || ""
    Object.assign(button.style, {
      position: "absolute",
      left: `${interval.left}px`,
      top: `${this.chart.bbox.top || 0}px`,
      width: `${interval.width}px`,
      height: `${this.chart.bbox.height || this.el.clientHeight}px`,
      border: "0",
      borderRight: `1px solid ${this.retentionGapColor(marker)}`,
      padding: "0",
      background: "rgba(248, 113, 113, 0.09)",
      cursor: "pointer",
      pointerEvents: "auto",
    })

    button.addEventListener("click", (event) => {
      event.preventDefault()
      event.stopPropagation()
      this.pushEvent("open_evidence", {
        kind: "source",
        "source-evidence-mode": "health",
        "source-evidence-state": marker.freshness_state,
        "source-request-id": marker.source_request_id,
        "logical-source": marker.logical_source,
        realm: marker.realm,
        "replay-run-id": marker.replay_run_id,
        "time-mode": marker.time_mode,
        "time-axis": marker.time_axis,
        "requested-realm": marker.requested_realm,
        "requested-data-view": marker.requested_data_view,
        "requested-data-source-id": marker.requested_data_source_id,
        "requested-source-binding-id": marker.requested_source_binding_id,
        "data-source-id": marker.data_source_id,
        "source-binding-id": marker.source_binding_id,
        "placement-id": this.placementId,
      })
    })

    this.eventLayer.appendChild(button)
  },

  renderSourceWatermarkCursor(marker) {
    if (!marker.marker_id || !marker.timestamp_ms) return

    const left = this.markerLeft(marker)
    const boundaryVisible = marker.display_mode !== "status"

    if (boundaryVisible && left !== null && left !== undefined && !Number.isNaN(left)) {
      this.renderSourceWatermarkIncompleteRegion(marker, left)
      this.renderSourceWatermarkBoundary(marker, left)
    }

    this.renderSourceWatermarkStatus(marker, boundaryVisible)
  },

  renderSourceWatermarkBoundary(marker, left) {
    const button = document.createElement("button")
    button.type = "button"
    button.title = `Inspect ${marker.label || "source watermark cursor"}`
    button.setAttribute("aria-label", button.title)
    button.dataset.eventMarkerTarget = "source watermark"
    button.dataset.eventMarkerId = marker.source_watermark_event_id || marker.target_id || marker.data_source_id || ""
    button.dataset.eventMarkerRef = marker.marker_id || ""
    button.dataset.watermarkBoundary = marker.freshness_state || "unknown"
    Object.assign(button.style, {
      position: "absolute",
      left: `${left - (this.chart.bbox.left || 0)}px`,
      top: "0",
      height: `${this.chart.bbox.height || this.el.clientHeight}px`,
      width: "14px",
      transform: "translateX(-7px)",
      border: "0",
      padding: "0",
      background: "transparent",
      cursor: "pointer",
      pointerEvents: "auto",
    })

    const line = document.createElement("span")
    Object.assign(line.style, {
      display: "block",
      width: "1px",
      height: "100%",
      margin: "0 auto",
      background: this.sourceWatermarkCursorColor(marker),
      boxShadow: `0 0 6px ${this.sourceWatermarkCursorColor(marker)}`,
    })
    button.appendChild(line)

    this.installSourceWatermarkAction(button, marker)
    this.watermarkOverlayLayer.appendChild(button)
  },

  renderSourceWatermarkIncompleteRegion(marker, left) {
    const plotLeft = this.chart.bbox.left || 0
    const plotRight = plotLeft + (this.chart.bbox.width || this.el.clientWidth)
    const regionLeft = Math.max(plotLeft, Math.min(plotRight, left))
    const width = Math.max(0, plotRight - regionLeft)
    if (width <= 0) return

    const region = document.createElement("div")
    region.dataset.sourceWatermarkIncompleteRegion = marker.freshness_state || "unknown"
    Object.assign(region.style, {
      position: "absolute",
      left: `${regionLeft - plotLeft}px`,
      top: "0",
      width: `${width}px`,
      height: `${this.chart.bbox.height || this.el.clientHeight}px`,
      borderLeft: `1px dashed ${this.sourceWatermarkCursorColor(marker)}`,
      backgroundColor: this.sourceWatermarkRegionColor(marker),
      backgroundImage:
        "repeating-linear-gradient(135deg, transparent 0, transparent 8px, rgba(148, 163, 184, 0.07) 8px, rgba(148, 163, 184, 0.07) 9px)",
      pointerEvents: "none",
    })
    this.watermarkOverlayLayer.appendChild(region)
  },

  renderSourceWatermarkStatus(marker, boundaryVisible) {
    const lagMs = this.sourceWatermarkLagMs(marker)
    const state = boundaryVisible ? "incomplete" : "complete"
    const status = document.createElement("button")
    const statusText = this.sourceWatermarkStatusText(marker, lagMs, boundaryVisible)

    status.type = "button"
    status.title = this.sourceWatermarkStatusTitle(marker, lagMs, boundaryVisible)
    status.setAttribute("aria-label", status.title)
    status.dataset.eventMarkerTarget = "source watermark status"
    status.dataset.eventMarkerId = marker.source_watermark_event_id || marker.target_id || marker.data_source_id || ""
    status.dataset.eventMarkerRef = marker.marker_id || ""
    status.dataset.sourceWatermarkStatus = state
    status.dataset.sourceWatermarkLagMs = `${lagMs}`
    status.textContent = statusText

    Object.assign(status.style, {
      position: "absolute",
      left: "10px",
      top: "8px",
      border: `1px solid ${this.sourceWatermarkStatusBorder(marker, boundaryVisible)}`,
      borderRadius: "3px",
      background: boundaryVisible ? "rgba(30, 23, 10, 0.90)" : "rgba(6, 31, 31, 0.86)",
      color: boundaryVisible ? "rgba(253, 230, 138, 0.96)" : "rgba(153, 246, 228, 0.94)",
      cursor: "pointer",
      font: "600 10px ui-monospace, SFMono-Regular, Menlo, monospace",
      letterSpacing: "0.06em",
      lineHeight: "1",
      padding: "4px 6px",
      pointerEvents: "auto",
      textTransform: "uppercase",
      whiteSpace: "nowrap",
    })

    this.el.dataset.watermarkState = state
    this.el.dataset.watermarkLagMs = `${lagMs}`
    this.el.dataset.watermarkBoundaryVisible = `${boundaryVisible}`

    this.installSourceWatermarkAction(status, marker)
    this.watermarkOverlayLayer.appendChild(status)
  },

  installSourceWatermarkAction(control, marker) {
    this.installSharedCursorPassthrough(control)

    control.addEventListener("click", (event) => {
      event.preventDefault()
      event.stopPropagation()
      const dataLinkPayload = this.sourceWatermarkDataLinkPayload(marker)
      if (dataLinkPayload) {
        this.pushEvent("open_data_link", dataLinkPayload)
        return
      }

      this.pushEvent("open_evidence", {
        kind: "source",
        "source-evidence-mode": "health",
        "source-evidence-state": marker.freshness_state,
        "source-request-id": marker.source_request_id,
        "logical-source": marker.logical_source,
        realm: marker.realm,
        "replay-run-id": marker.replay_run_id,
        "time-mode": marker.time_mode,
        "time-axis": marker.time_axis,
        "requested-realm": marker.requested_realm,
        "requested-data-view": marker.requested_data_view,
        "requested-data-source-id": marker.requested_data_source_id,
        "requested-source-binding-id": marker.requested_source_binding_id,
        "requested-dataset": marker.requested_dataset,
        "requested-validity-state": marker.requested_validity_state,
        "data-source-id": marker.data_source_id,
        "source-binding-id": marker.source_binding_id,
        "placement-id": this.placementId,
      })
    })
  },

  installSharedCursorPassthrough(control) {
    control.dataset.chartCursorPassthrough = "true"

    const updateCursor = (event) => {
      const overlay = this.el.querySelector && this.el.querySelector(".u-over")
      if (!overlay || !this.chart || typeof this.chart.setCursor !== "function") return

      const rect = overlay.getBoundingClientRect()
      this.chart.setCursor(
        {
          left: event.clientX - rect.left,
          top: event.clientY - rect.top,
        },
        true,
        true
      )
    }

    control.addEventListener("mouseenter", updateCursor)
    control.addEventListener("mousemove", updateCursor)
    control.addEventListener("mouseleave", () => {
      if (!this.chart || typeof this.chart.setCursor !== "function") return
      this.chart.setCursor({ left: -10, top: -10 }, true, true)
    })
  },

  sourceWatermarkLagMs(marker) {
    const windowEnd = this.chartWindowEnd()
    if (!Number.isFinite(windowEnd)) return 0
    return Math.max(0, Math.round(windowEnd * 1000 - Number(marker.timestamp_ms)))
  },

  sourceWatermarkStatusText(marker, lagMs, boundaryVisible) {
    const prefix = marker.freshness_state === "retention_gap"
      ? "Retention gap"
      : boundaryVisible
        ? "Incomplete"
        : "Complete"
    return `${prefix} · ${this.formatSourceWatermarkLag(lagMs)}`
  },

  sourceWatermarkStatusTitle(marker, lagMs, boundaryVisible) {
    const timestamp = new Date(Number(marker.timestamp_ms)).toLocaleString()
    const prefix = boundaryVisible ? "Data is complete through" : "Data complete through"
    return `${prefix} ${timestamp} · ${this.formatSourceWatermarkLag(lagMs)}`
  },

  formatSourceWatermarkLag(lagMs) {
    if (lagMs < 1_000) return "current"
    if (lagMs < 10_000) return `${(lagMs / 1_000).toFixed(1)}s behind`
    if (lagMs < 60_000) return `${Math.round(lagMs / 1_000)}s behind`
    if (lagMs < 3_600_000) return `${Math.round(lagMs / 60_000)}m behind`
    return `${Math.round(lagMs / 3_600_000)}h behind`
  },

  sourceWatermarkStatusBorder(marker, boundaryVisible) {
    if (!boundaryVisible) return "rgba(45, 212, 191, 0.36)"
    return this.sourceWatermarkCursorColor(marker)
  },

  sourceWatermarkRegionColor(marker) {
    if (marker.freshness_state === "retention_gap") return "rgba(127, 29, 29, 0.10)"
    if (marker.freshness_state === "stale") return "rgba(120, 53, 15, 0.10)"
    return "rgba(51, 65, 85, 0.10)"
  },

  collapseSourceWatermarkMarkers(markers) {
    if (!Array.isArray(markers)) return []

    const latestCursors = this.latestSourceWatermarkMarkers(
      markers.filter((marker) => marker.marker_type === "source_watermark_cursor")
    )
    const cursorIdentities = new Set(
      latestCursors.map((marker) => this.sourceWatermarkIdentity(marker))
    )
    const fallbackEvents = this.latestSourceWatermarkMarkers(
      markers.filter((marker) => marker.marker_type === "source_watermark_event")
    ).filter((marker) => !cursorIdentities.has(this.sourceWatermarkIdentity(marker)))

    return markers
      .filter(
        (marker) =>
          marker.marker_type !== "source_watermark_cursor" &&
          marker.marker_type !== "source_watermark_event"
      )
      .concat(latestCursors, fallbackEvents)
  },

  latestSourceWatermarkMarkers(markers) {
    const latest = new Map()

    markers.forEach((marker) => {
      const identity = this.sourceWatermarkIdentity(marker)
      const current = latest.get(identity)
      if (!current || this.sourceWatermarkTimestamp(marker) >= this.sourceWatermarkTimestamp(current)) {
        latest.set(identity, marker)
      }
    })

    return Array.from(latest.values())
  },

  sourceWatermarkIdentity(marker) {
    return [
      marker.logical_source || "",
      marker.data_source_id || "",
      marker.source_binding_id || "",
      marker.dataset || "",
      marker.realm || "",
      marker.replay_run_id || "",
    ].join(":")
  },

  sourceWatermarkTimestamp(marker) {
    return Number(marker.timestamp_ms || marker.complete_through_ms || marker.observed_at_ms || 0)
  },

  renderSourceHealthTransition(marker) {
    if (!marker.link_id || !marker.timestamp_ms) return

    const left = this.markerLeft(marker)
    if (left === null || left === undefined || Number.isNaN(left)) return

    const button = document.createElement("button")
    button.type = "button"
    button.title = `Inspect ${marker.title || marker.label || "source health transition"}`
    button.setAttribute("aria-label", button.title)
    button.dataset.eventMarkerTarget = "source health"
    button.dataset.eventMarkerId = marker.source_health_event_id || marker.target_id || ""
    button.dataset.eventMarkerRef = marker.link_id || ""
    button.dataset.eventMarkerSummary = marker.reason || marker.source_health || ""
    Object.assign(button.style, {
      position: "absolute",
      left: `${left}px`,
      top: `${this.chart.bbox.top || 0}px`,
      height: `${this.chart.bbox.height || this.el.clientHeight}px`,
      width: "14px",
      transform: "translateX(-7px)",
      border: "0",
      padding: "0",
      background: "transparent",
      cursor: "pointer",
      pointerEvents: "auto",
    })

    const line = document.createElement("span")
    Object.assign(line.style, {
      display: "block",
      width: "1px",
      height: "100%",
      margin: "0 auto",
      background: this.eventColor(marker),
      boxShadow: `0 0 6px ${this.eventColor(marker)}`,
    })
    button.appendChild(line)

    button.addEventListener("click", (event) => {
      event.preventDefault()
      event.stopPropagation()
      this.pushEvent(
        "open_data_link",
        this.markerDataLinkPayload(
          marker,
          "source_health_event",
          marker.source_health_event_id || marker.target_id,
          marker.timestamp_ms
        )
      )
    })

    this.eventLayer.appendChild(button)
  },

  sourceWatermarkDataLinkPayload(marker) {
    if (marker.marker_type !== "source_watermark_event" || !marker.link_id) return null

    return this.markerDataLinkPayload(
      marker,
      marker.data_link_target || "source_watermark_event",
      marker.data_link_target_id || marker.source_watermark_event_id || marker.target_id,
      marker.timestamp_ms
    )
  },

  renderTelemetryRevisionRange(marker) {
    if (!marker.marker_id || !marker.starts_at_ms || !marker.ends_at_ms || !marker.observable_id) return

    const interval = this.intervalBounds(marker)
    if (!interval) return

    const button = document.createElement("button")
    button.type = "button"
    button.title = this.markerInspectionTitle(marker, "telemetry revision range")
    button.setAttribute("aria-label", button.title)
    button.dataset.eventMarkerTarget = "telemetry revision"
    button.dataset.eventMarkerId = marker.target_id || marker.observable_id || ""
    button.dataset.eventMarkerRef = marker.marker_id || ""
    button.dataset.eventMarkerSummary = marker.summary || ""
    Object.assign(button.style, {
      position: "absolute",
      left: `${interval.left}px`,
      top: `${this.chart.bbox.top || 0}px`,
      width: `${interval.width}px`,
      height: `${this.chart.bbox.height || this.el.clientHeight}px`,
      border: "0",
      borderLeft: `1px solid ${this.telemetryRevisionColor(marker)}`,
      borderRight: `1px solid ${this.telemetryRevisionColor(marker)}`,
      padding: "0",
      background: marker.revision_state === "backfill" ? "rgba(14, 165, 233, 0.08)" : "rgba(251, 191, 36, 0.10)",
      cursor: "pointer",
      pointerEvents: "auto",
    })

    button.addEventListener("click", (event) => {
      event.preventDefault()
      event.stopPropagation()
      if (marker.link_id) {
        this.pushEvent(
          "open_data_link",
          this.markerDataLinkPayload(
            marker,
            marker.data_link_target || marker.target,
            marker.data_link_target_id ||
              marker.target_id ||
              marker.telemetry_backfill_lifecycle_event_id ||
              marker.observable_id,
            marker.timestamp_ms || marker.starts_at_ms
          )
        )
        return
      }

      this.pushEvent("open_evidence", {
        kind: "frame",
        "placement-id": this.placementId,
        "observable-id": marker.observable_id,
        "warning-code": marker.warning_code,
        "revision-state": marker.revision_state,
        "dependency-fingerprint": marker.dependency_fingerprint,
        "source-request-id": marker.source_request_id,
        "logical-source": marker.logical_source,
        realm: marker.realm,
        "data-source-id": marker.data_source_id,
        "source-binding-id": marker.source_binding_id,
        "time-mode": marker.time_mode,
        "time-axis": marker.time_axis,
        "replay-run-id": marker.replay_run_id,
        "requested-realm": marker.requested_realm,
        "requested-data-view": marker.requested_data_view,
        "requested-data-source-id": marker.requested_data_source_id,
        "requested-source-binding-id": marker.requested_source_binding_id,
        "requested-dataset": marker.requested_dataset,
        "requested-validity-state": marker.requested_validity_state,
      })
    })

    this.eventLayer.appendChild(button)
  },

  renderTelemetryBackfillLifecycle(marker) {
    if (marker.starts_at_ms && marker.ends_at_ms) {
      this.renderTelemetryRevisionRange(marker)
      return
    }

    this.renderTelemetryRevisionDecision(marker)
  },

  renderTelemetryRevisionDecision(marker) {
    if (!marker.marker_id || !marker.timestamp_ms || !marker.observable_id) return

    const left = this.markerLeft(marker)
    if (left === null || left === undefined || Number.isNaN(left)) return

    const markerLabel =
      marker.marker_type === "telemetry_backfill_lifecycle"
        ? "telemetry backfill lifecycle"
        : "telemetry revision decision"

    const button = document.createElement("button")
    button.type = "button"
    button.title = this.markerInspectionTitle(marker, markerLabel)
    button.setAttribute("aria-label", button.title)
    button.dataset.eventMarkerTarget = markerLabel
    button.dataset.eventMarkerId =
      marker.telemetry_revision_decision_event_id ||
      marker.telemetry_backfill_lifecycle_event_id ||
      marker.target_id ||
      ""
    button.dataset.eventMarkerRef = marker.marker_id || ""
    button.dataset.eventMarkerSummary = marker.summary || ""
    Object.assign(button.style, {
      position: "absolute",
      left: `${left}px`,
      top: `${this.chart.bbox.top || 0}px`,
      height: `${this.chart.bbox.height || this.el.clientHeight}px`,
      width: "14px",
      transform: "translateX(-7px)",
      border: "0",
      padding: "0",
      background: "transparent",
      cursor: "pointer",
      pointerEvents: "auto",
    })

    const line = document.createElement("span")
    Object.assign(line.style, {
      display: "block",
      width: "2px",
      height: "100%",
      margin: "0 auto",
      borderRadius: "999px",
      background: this.telemetryRevisionColor(marker),
      boxShadow: `0 0 7px ${this.telemetryRevisionColor(marker)}`,
    })
    button.appendChild(line)

    button.addEventListener("click", (event) => {
      event.preventDefault()
      event.stopPropagation()
      if (marker.link_id) {
        this.pushEvent(
          "open_data_link",
          this.markerDataLinkPayload(
            marker,
            marker.data_link_target || marker.target,
            marker.data_link_target_id ||
              marker.target_id ||
              marker.telemetry_revision_decision_event_id ||
              marker.telemetry_backfill_lifecycle_event_id ||
              marker.observable_id,
            marker.timestamp_ms
          )
        )
        return
      }

      this.pushEvent("open_evidence", {
        kind: "frame",
        "placement-id": this.placementId,
        "observable-id": marker.observable_id,
        "warning-code": marker.warning_code,
        "revision-state": marker.revision_state,
        "dependency-fingerprint": marker.dependency_fingerprint,
        "source-request-id": marker.source_request_id,
        "logical-source": marker.logical_source,
        realm: marker.realm,
        "data-source-id": marker.data_source_id,
        "source-binding-id": marker.source_binding_id,
        "time-mode": marker.time_mode,
        "time-axis": marker.time_axis,
        "replay-run-id": marker.replay_run_id,
        "requested-realm": marker.requested_realm,
        "requested-data-view": marker.requested_data_view,
        "requested-data-source-id": marker.requested_data_source_id,
        "requested-source-binding-id": marker.requested_source_binding_id,
        "requested-dataset": marker.requested_dataset,
        "requested-validity-state": marker.requested_validity_state,
      })
    })

    this.eventLayer.appendChild(button)
  },

  markerInspectionTitle(marker, fallbackLabel) {
    const label = marker.label || fallbackLabel
    return marker.summary ? `Inspect ${label} - ${marker.summary}` : `Inspect ${label}`
  },

  renderMissionEvent(marker) {
    if (!marker.link_id || !marker.timestamp_ms) return

    const left = this.markerLeft(marker)
    if (left === null || left === undefined || Number.isNaN(left)) return

    const button = document.createElement("button")
    button.type = "button"
    button.title = `Inspect ${marker.title || "mission event"}`
    button.setAttribute("aria-label", button.title)
    button.dataset.eventMarkerTarget = "mission event"
    button.dataset.eventMarkerId = marker.mission_event_id || marker.target_id || ""
    button.dataset.eventMarkerRef = marker.link_id || ""
    Object.assign(button.style, {
      position: "absolute",
      left: `${left}px`,
      top: `${this.chart.bbox.top || 0}px`,
      height: `${this.chart.bbox.height || this.el.clientHeight}px`,
      width: "12px",
      transform: "translateX(-6px)",
      border: "0",
      padding: "0",
      background: "transparent",
      cursor: "pointer",
      pointerEvents: "auto",
    })

    const line = document.createElement("span")
    Object.assign(line.style, {
      display: "block",
      width: "1px",
      height: "100%",
      margin: "0 auto",
      background: this.eventColor(marker),
      boxShadow: `0 0 6px ${this.eventColor(marker)}`,
    })
    button.appendChild(line)

    button.addEventListener("click", (event) => {
      event.preventDefault()
      event.stopPropagation()
      this.pushEvent(
        "open_data_link",
        this.markerDataLinkPayload(
          marker,
          "mission_event",
          marker.target_id || marker.mission_event_id,
          marker.timestamp_ms
        )
      )
    })

    this.eventLayer.appendChild(button)
  },

  renderLimitMarkers() {
    if (!this.markerLayer || !this.chart) return

    this.markerLayer.replaceChildren()

    this.limitMarkers.forEach((marker) => {
      if (marker.marker_type === "limit_definition_interval") {
        this.renderLimitDefinitionInterval(marker)
        return
      }

      if (marker.marker_type === "limit_analysis_bucket") {
        this.renderLimitAnalysisBucket(marker)
        return
      }

      this.renderLimitEvent(marker)
    })
  },

  renderLimitAnalysisBucket(marker) {
    if (!marker.starts_at_ms || !marker.ends_at_ms) return

    const interval = this.intervalBounds(marker)
    if (!interval) return

    const button = document.createElement("button")
    button.type = "button"
    button.title = this.limitAnalysisBucketTitle(marker)
    button.setAttribute("aria-label", button.title)
    button.dataset.limitMarkerTarget = "limit analysis bucket"
    button.dataset.limitMarkerId = marker.limit_event_id || marker.sample_id || marker.marker_id || ""
    button.dataset.limitMarkerRef = marker.link_id || marker.marker_id || ""
    button.dataset.limitBucketState = marker.normalized_state || ""
    button.dataset.limitBucketEventCount = marker.event_count || ""
    button.dataset.limitBucketDivergenceCount = marker.limit_divergence_count || ""
    button.dataset.limitDefinitionId = marker.limit_definition_id || ""
    button.dataset.limitDefinitionVersion = marker.limit_definition_version || ""
    button.dataset.limitSetName = marker.limit_set_name || ""
    button.dataset.limitSelectedClock = this.limitMarkerMetadata(marker.selected_limit_clock)
    button.dataset.limitSelectedDefinitionIntervals = this.limitMarkerMetadata(
      marker.selected_limit_definition_intervals
    )
    Object.assign(button.style, {
      position: "absolute",
      left: `${interval.left}px`,
      top: `${this.chart.bbox.top || 0}px`,
      width: `${interval.width}px`,
      height: `${this.chart.bbox.height || this.el.clientHeight}px`,
      border: "0",
      borderLeft: `1px solid ${this.markerColor(marker)}`,
      borderRight: `1px solid ${this.markerColor(marker)}`,
      padding: "0",
      background: this.limitAnalysisBucketFill(marker),
      boxShadow: `inset 0 0 0 1px ${this.limitAnalysisBucketEdge(marker)}`,
      cursor: marker.link_id ? "pointer" : "default",
      pointerEvents: marker.link_id ? "auto" : "none",
    })

    if (marker.limit_divergence_count) {
      button.dataset.limitBucketDiverged = "true"
    }

    button.addEventListener("click", (event) => {
      if (!marker.link_id) return

      event.preventDefault()
      event.stopPropagation()
      const target = marker.synthetic_limit_analysis ? "telemetry_sample" : "limit_event"
      const targetId =
        target === "telemetry_sample" ? marker.sample_id : marker.limit_event_id || marker.sample_id
      this.pushEvent(
        "open_data_link",
        this.markerDataLinkPayload(marker, target, targetId, marker.timestamp_ms)
      )
    })

    this.markerLayer.appendChild(button)
  },

  renderLimitEvent(marker) {
    if (!marker.link_id || !marker.timestamp_ms) return

    const left = this.markerLeft(marker)
    if (left === null || left === undefined || Number.isNaN(left)) return

    const button = document.createElement("button")
    button.type = "button"
    button.title = `Inspect ${marker.normalized_state || "limit"} limit event`
    button.setAttribute("aria-label", button.title)
    button.dataset.limitMarkerTarget = "limit event"
    button.dataset.limitMarkerId = marker.limit_event_id || ""
    button.dataset.limitMarkerRef = marker.link_id || ""
    Object.assign(button.style, {
      position: "absolute",
      left: `${left}px`,
      top: `${this.chart.bbox.top || 0}px`,
      height: `${this.chart.bbox.height || this.el.clientHeight}px`,
      width: "14px",
      transform: "translateX(-7px)",
      border: "0",
      padding: "0",
      background: "transparent",
      cursor: "pointer",
      pointerEvents: "auto",
    })

    const line = document.createElement("span")
    Object.assign(line.style, {
      display: "block",
      width: "2px",
      height: "100%",
      margin: "0 auto",
      borderRadius: "999px",
      background: this.markerColor(marker),
      boxShadow: `0 0 0 1px rgba(0, 0, 0, 0.35), 0 0 8px ${this.markerColor(marker)}`,
    })
    button.appendChild(line)

    button.addEventListener("click", (event) => {
      event.preventDefault()
      event.stopPropagation()
      this.pushEvent(
        "open_data_link",
        this.markerDataLinkPayload(marker, "limit_event", marker.limit_event_id, marker.timestamp_ms)
      )
    })

    this.markerLayer.appendChild(button)
  },

  renderLimitDefinitionInterval(marker) {
    if (!marker.link_id || !marker.starts_at_ms) return

    const interval = this.intervalBounds(marker)
    if (!interval) return

    const button = document.createElement("button")
    button.type = "button"
    button.title = `Inspect ${marker.limit_set_name || "active"} limit definition`
    button.setAttribute("aria-label", button.title)
    button.dataset.limitMarkerTarget = "limit definition"
    button.dataset.limitMarkerId = marker.limit_definition_id || marker.target_id || ""
    button.dataset.limitMarkerRef = marker.link_id || ""
    Object.assign(button.style, {
      position: "absolute",
      left: `${interval.left}px`,
      top: `${this.chart.bbox.top || 0}px`,
      width: `${interval.width}px`,
      height: `${this.chart.bbox.height || this.el.clientHeight}px`,
      border: "0",
      borderLeft: `1px solid ${this.limitIntervalColor(marker)}`,
      borderRight: `1px solid ${this.limitIntervalColor(marker)}`,
      padding: "0",
      background: "rgba(250, 204, 21, 0.055)",
      cursor: "pointer",
      pointerEvents: "auto",
    })

    this.renderThresholdBands(button, marker)
    this.renderThresholdLines(button, marker)

    button.addEventListener("click", (event) => {
      event.preventDefault()
      event.stopPropagation()
      this.pushEvent(
        "open_data_link",
        this.markerDataLinkPayload(
          marker,
          "limit_definition",
          marker.target_id || marker.limit_definition_id,
          marker.starts_at_ms
        )
      )
    })

    this.markerLayer.appendChild(button)
  },

  renderThresholdLines(parent, marker) {
    const thresholdNames = ["red_high", "yellow_high", "yellow_low", "red_low"]

    thresholdNames.forEach((name) => {
      const value = Number(marker[name])
      if (!Number.isFinite(value)) return

      const top = this.chart.valToPos(value, "y", false)
      const height = this.chart.bbox.height || this.el.clientHeight
      if (top < 0 || top > height) return

      const line = document.createElement("span")
      Object.assign(line.style, {
        position: "absolute",
        left: "0",
        right: "0",
        top: `${top}px`,
        borderTop: `${name.startsWith("red") ? "1px solid" : "1px dashed"} ${this.limitThresholdColor(
          name
        )}`,
      })
      parent.appendChild(line)
    })
  },

  renderThresholdBands(parent, marker) {
    this.thresholdBandSpecs(marker).forEach((band) => {
      const bounds = this.thresholdBandBounds(band)
      if (!bounds) return

      const fill = document.createElement("span")
      fill.dataset.limitThresholdBand = band.name
      Object.assign(fill.style, {
        position: "absolute",
        left: "0",
        right: "0",
        top: `${bounds.top}px`,
        height: `${bounds.height}px`,
        background: this.limitThresholdBandColor(band.name),
        pointerEvents: "none",
      })
      parent.appendChild(fill)
    })
  },

  thresholdBandSpecs(marker) {
    return [
      { name: "red_high", from: this.numberOrNull(marker.red_high), to: null },
      { name: "yellow_high", from: this.numberOrNull(marker.yellow_high), to: this.numberOrNull(marker.red_high) },
      { name: "yellow_low", from: this.numberOrNull(marker.red_low), to: this.numberOrNull(marker.yellow_low) },
      { name: "red_low", from: null, to: this.numberOrNull(marker.red_low) },
    ].filter((band) => band.from !== null || band.to !== null)
  },

  thresholdBandBounds(band) {
    const plotTop = this.chart.bbox.top || 0
    const plotHeight = this.chart.bbox.height || this.el.clientHeight
    const plotBottom = plotTop + plotHeight
    const top = band.to === null ? plotTop : plotTop + this.chart.valToPos(band.to, "y", false)
    const bottom = band.from === null ? plotBottom : plotTop + this.chart.valToPos(band.from, "y", false)
    const clippedTop = Math.max(plotTop, Math.min(plotBottom, top))
    const clippedBottom = Math.max(plotTop, Math.min(plotBottom, bottom))
    const height = clippedBottom - clippedTop

    if (!Number.isFinite(height) || height <= 1) return null
    return { top: clippedTop - plotTop, height }
  },

  numberOrNull(value) {
    const number = Number(value)
    return Number.isFinite(number) ? number : null
  },

  renderSelection() {
    if (!this.selectionLayer || !this.chart) return

    this.selectionLayer.replaceChildren()
    if (!this.selectedRef) return
    if (this.selectedRef.placement_id && this.selectedRef.placement_id !== this.placementId) return

    this.renderSelectedTimeCursor()

    if (this.selectedRef.target === "limit_event") {
      const marker = this.selectedLimitMarker()
      if (marker) this.renderSelectedLimit(marker)
    }

    if (this.selectedRef.target === "limit_definition") {
      const marker = this.selectedLimitDefinitionMarker()
      if (marker) this.renderSelectedLimitDefinition(marker)
    }

    if (this.selectedRef.target === "mission_event") {
      const marker = this.selectedEventMarker("mission_event")
      if (marker) this.renderSelectedEvent(marker)
    }

    if (this.selectedRef.target === "telemetry_sample") {
      const selection = this.selectedPointIndex()
      if (selection) this.renderSelectedPoint(selection)
    }
  },

  selectedPointIndex() {
    for (let seriesIndex = 0; seriesIndex < this.seriesPointMeta.length; seriesIndex += 1) {
      if (!this.seriesVisible(this.seriesList[seriesIndex])) continue

      const pointIndex = this.seriesPointMeta[seriesIndex].findIndex((metadata) => {
        return (
          this.selectedPointMetadataMatchesSeries(metadata) &&
          (metadata.link_id === this.selectedRef.link_id ||
            metadata.sample_id === this.selectedRef.target_id)
        )
      })

      if (pointIndex >= 0) return { seriesIndex, pointIndex }
    }

    return null
  },

  selectedPointMetadataMatchesSeries(metadata) {
    if (!metadata) return false

    if (this.selectedRef.series_role && metadata.series_role !== this.selectedRef.series_role) {
      return false
    }

    if (this.selectedRef.compare_of && metadata.compare_of !== this.selectedRef.compare_of) {
      return false
    }

    if (this.selectedRef.data_view && metadata.data_view && metadata.data_view !== this.selectedRef.data_view) {
      return false
    }

    return true
  },

  selectedLimitMarker() {
    return this.limitMarkers.find((marker) => {
      if (marker.marker_type === "limit_definition_interval") return false

      return (
        marker.link_id === this.selectedRef.link_id ||
        marker.limit_event_id === this.selectedRef.target_id
      )
    })
  },

  selectedLimitDefinitionMarker() {
    return this.limitMarkers.find((marker) => {
      if (marker.marker_type !== "limit_definition_interval") return false

      return (
        marker.link_id === this.selectedRef.link_id ||
        marker.target_id === this.selectedRef.target_id ||
        marker.limit_definition_id === this.selectedRef.target_id
      )
    })
  },

  selectedEventMarker(target) {
    return this.eventMarkers.find((marker) => {
      if (marker.target !== target) return false

      return (
        marker.link_id === this.selectedRef.link_id ||
        marker.target_id === this.selectedRef.target_id ||
        marker.mission_event_id === this.selectedRef.target_id ||
        marker.contact_id === this.selectedRef.target_id
      )
    })
  },

  renderSelectedPoint(selection) {
    const series = this.seriesList[selection.seriesIndex] || {}
    const x = this.xs[selection.pointIndex]
    const y = this.seriesYs[selection.seriesIndex] && this.seriesYs[selection.seriesIndex][selection.pointIndex]
    if (x === undefined || y === undefined) return

    const left = (this.chart.bbox.left || 0) + this.chart.valToPos(x, "x", false)
    const top = (this.chart.bbox.top || 0) + this.chart.valToPos(y, this.unitScaleKey(series.unit), false)
    if (Number.isNaN(left) || Number.isNaN(top)) return

    const marker = document.createElement("div")
    marker.dataset.chartSelectionTarget = "telemetry sample"
    marker.dataset.chartSelectionRef = this.selectedRef.link_id || ""
    marker.dataset.chartSelectionSeriesRole = this.selectedRef.series_role || "primary"
    Object.assign(marker.style, {
      position: "absolute",
      left: `${left}px`,
      top: `${top}px`,
      width: "12px",
      height: "12px",
      transform: "translate(-6px, -6px)",
      border:
        this.selectedRef.series_role === "compare"
          ? "2px dashed rgba(203, 213, 225, 0.95)"
          : "2px solid rgba(125, 211, 252, 0.95)",
      borderRadius: "999px",
      background: "rgba(14, 165, 233, 0.18)",
      boxShadow: "0 0 0 1px rgba(0, 0, 0, 0.35), 0 0 10px rgba(125, 211, 252, 0.75)",
    })
    this.selectionLayer.appendChild(marker)
  },

  renderSelectedTimeCursor() {
    const left = this.selectedTimeCursorLeft()
    if (left === null || left === undefined || Number.isNaN(left)) return

    const cursor = document.createElement("div")
    cursor.dataset.chartSelectionTarget = "selected time"
    cursor.dataset.chartSelectionRef = this.selectedRef.link_id || ""
    cursor.dataset.chartSelectionTimestampMs = `${this.selectedTimestampMs()}`
    Object.assign(cursor.style, {
      position: "absolute",
      left: `${left}px`,
      top: `${this.chart.bbox.top || 0}px`,
      height: `${this.chart.bbox.height || this.el.clientHeight}px`,
      width: "0",
      borderLeft: "1px dashed rgba(125, 211, 252, 0.68)",
      boxShadow: "0 0 8px rgba(125, 211, 252, 0.42)",
    })
    this.selectionLayer.appendChild(cursor)
  },

  selectedTimeCursorLeft() {
    const timestampMs = this.selectedTimestampMs()
    if (timestampMs === null || this.xs.length === 0) return null

    const x = timestampMs / 1000
    if (x < this.xs[0] || x > this.xs[this.xs.length - 1]) return null

    return (this.chart.bbox.left || 0) + this.chart.valToPos(x, "x", false)
  },

  selectedTimestampMs() {
    const value = this.selectedRef && this.selectedRef.timestamp_ms
    if (value === null || value === undefined || value === "") return null

    const timestampMs = Number(value)
    if (!Number.isFinite(timestampMs)) return null
    return timestampMs
  },

  renderSelectedLimit(marker) {
    if (marker.marker_type === "limit_analysis_bucket") {
      this.renderSelectedLimitBucket(marker)
      return
    }

    const left = this.markerLeft(marker)
    if (left === null || left === undefined || Number.isNaN(left)) return

    const selection = document.createElement("div")
    selection.dataset.chartSelectionTarget = "limit event"
    selection.dataset.chartSelectionRef = this.selectedRef.link_id || ""
    Object.assign(selection.style, {
      position: "absolute",
      left: `${left}px`,
      top: `${this.chart.bbox.top || 0}px`,
      height: `${this.chart.bbox.height || this.el.clientHeight}px`,
      width: "18px",
      transform: "translateX(-9px)",
      borderLeft: `3px solid ${this.markerColor(marker)}`,
      borderRight: `3px solid ${this.markerColor(marker)}`,
      background: "rgba(250, 250, 250, 0.08)",
      boxShadow: `0 0 12px ${this.markerColor(marker)}`,
    })
    this.selectionLayer.appendChild(selection)
  },

  renderSelectedLimitBucket(marker) {
    const interval = this.intervalBounds(marker)
    if (!interval) return

    const selection = document.createElement("div")
    selection.dataset.chartSelectionTarget = "limit analysis bucket"
    selection.dataset.chartSelectionRef = this.selectedRef.link_id || ""
    Object.assign(selection.style, {
      position: "absolute",
      left: `${interval.left}px`,
      top: `${this.chart.bbox.top || 0}px`,
      width: `${interval.width}px`,
      height: `${this.chart.bbox.height || this.el.clientHeight}px`,
      border: `2px solid ${this.markerColor(marker)}`,
      background: this.limitAnalysisBucketSelectionFill(marker),
      boxShadow: `0 0 12px ${this.markerColor(marker)}`,
    })
    this.selectionLayer.appendChild(selection)
  },

  renderSelectedLimitDefinition(marker) {
    const interval = this.intervalBounds(marker)
    if (!interval) return

    const selection = document.createElement("div")
    selection.dataset.chartSelectionTarget = "limit definition"
    selection.dataset.chartSelectionRef = this.selectedRef.link_id || ""
    Object.assign(selection.style, {
      position: "absolute",
      left: `${interval.left}px`,
      top: `${this.chart.bbox.top || 0}px`,
      width: `${interval.width}px`,
      height: `${this.chart.bbox.height || this.el.clientHeight}px`,
      border: `1px solid ${this.limitIntervalColor(marker)}`,
      background: "rgba(250, 204, 21, 0.13)",
      boxShadow: `0 0 10px ${this.limitIntervalColor(marker)}`,
    })
    this.selectionLayer.appendChild(selection)
  },

  renderSelectedEvent(marker) {
    const left = this.markerLeft(marker)
    if (left === null || left === undefined || Number.isNaN(left)) return

    const selection = document.createElement("div")
    selection.dataset.chartSelectionTarget = "mission event"
    selection.dataset.chartSelectionRef = this.selectedRef.link_id || ""
    Object.assign(selection.style, {
      position: "absolute",
      left: `${left}px`,
      top: `${this.chart.bbox.top || 0}px`,
      height: `${this.chart.bbox.height || this.el.clientHeight}px`,
      width: "16px",
      transform: "translateX(-8px)",
      borderLeft: `2px solid ${this.eventColor(marker)}`,
      borderRight: `2px solid ${this.eventColor(marker)}`,
      background: "rgba(250, 250, 250, 0.06)",
      boxShadow: `0 0 10px ${this.eventColor(marker)}`,
    })
    this.selectionLayer.appendChild(selection)
  },

  markerLeft(marker) {
    const plotLeft = this.chart.bbox.left || 0
    const x = marker.timestamp_ms / 1000
    return plotLeft + this.chart.valToPos(x, "x", false)
  },

  intervalBounds(marker) {
    if (!marker.starts_at_ms || this.xs.length === 0) return null

    const plotLeft = this.chart.bbox.left || 0
    const plotRight = plotLeft + (this.chart.bbox.width || this.el.clientWidth)
    const startSeconds = marker.starts_at_ms / 1000
    const endSeconds = marker.ends_at_ms ? marker.ends_at_ms / 1000 : this.xs[this.xs.length - 1]
    const xDomain = this.chartXDomain()

    if (endSeconds < xDomain.min || startSeconds > xDomain.max) return null

    const left = Math.max(plotLeft, plotLeft + this.chart.valToPos(startSeconds, "x", false))
    const right = Math.min(plotRight, plotLeft + this.chart.valToPos(endSeconds, "x", false))
    const width = Math.max(2, right - left)

    return { left, width }
  },

  markerColor(marker) {
    if (marker.normalized_state === "red") return "rgba(248, 113, 113, 0.95)"
    return "rgba(250, 204, 21, 0.95)"
  },

  limitAnalysisBucketTitle(marker) {
    const state = marker.normalized_state || "limit"
    const count = marker.event_count ? ` / ${marker.event_count} event${marker.event_count === 1 ? "" : "s"}` : ""
    const divergence = marker.limit_divergence_count ? ` / ${marker.limit_divergence_count} divergent` : ""
    return `Inspect ${state} limit analysis bucket${count}${divergence}`
  },

  limitMarkerMetadata(value) {
    if (value === null || value === undefined || value === "") return ""
    if (typeof value === "string") return value

    try {
      return JSON.stringify(value)
    } catch (_error) {
      return ""
    }
  },

  limitAnalysisBucketFill(marker) {
    if (marker.normalized_state === "red") return "rgba(248, 113, 113, 0.14)"
    return "rgba(250, 204, 21, 0.12)"
  },

  limitAnalysisBucketSelectionFill(marker) {
    if (marker.normalized_state === "red") return "rgba(248, 113, 113, 0.20)"
    return "rgba(250, 204, 21, 0.18)"
  },

  limitAnalysisBucketEdge(marker) {
    if (marker.normalized_state === "red") return "rgba(248, 113, 113, 0.28)"
    return "rgba(250, 204, 21, 0.24)"
  },

  limitIntervalColor(_marker) {
    return "rgba(250, 204, 21, 0.58)"
  },

  limitThresholdColor(name) {
    if (name.startsWith("red")) return "rgba(248, 113, 113, 0.82)"
    return "rgba(250, 204, 21, 0.82)"
  },

  limitThresholdBandColor(name) {
    if (name.startsWith("red")) return "rgba(248, 113, 113, 0.08)"
    return "rgba(250, 204, 21, 0.07)"
  },

  eventColor(marker) {
    if (marker.severity === "critical" || marker.severity === "error") return "rgba(248, 113, 113, 0.90)"
    if (marker.severity === "warning" || marker.status === "canceled") return "rgba(251, 191, 36, 0.90)"
    if (marker.marker_type === "retention_gap") return this.retentionGapColor(marker)
    if (marker.marker_type === "source_binding_interval") return this.sourceBindingIntervalColor(marker)
    if (marker.marker_type === "source_health_transition") return this.sourceHealthTransitionColor(marker)
    if (marker.marker_type === "source_watermark_cursor" || marker.marker_type === "source_watermark_event") return this.sourceWatermarkCursorColor(marker)
    if (
      marker.marker_type === "telemetry_revision_range" ||
      marker.marker_type === "telemetry_revision_decision" ||
      marker.marker_type === "telemetry_backfill_lifecycle"
    ) return this.telemetryRevisionColor(marker)
    return "rgba(129, 140, 248, 0.86)"
  },

  retentionGapColor(_marker) {
    return "rgba(248, 113, 113, 0.76)"
  },

  sourceBindingIntervalColor(_marker) {
    return "rgba(129, 140, 248, 0.68)"
  },

  sourceWatermarkCursorColor(marker) {
    if (marker.freshness_state === "stale") return "rgba(251, 191, 36, 0.82)"
    if (marker.freshness_state === "retention_gap") return "rgba(248, 113, 113, 0.78)"
    return "rgba(45, 212, 191, 0.76)"
  },

  sourceHealthTransitionColor(marker) {
    if (marker.source_health === "unavailable") return "rgba(248, 113, 113, 0.88)"
    if (marker.source_health === "degraded" || marker.source_health === "unknown") return "rgba(251, 191, 36, 0.86)"
    return "rgba(34, 197, 94, 0.76)"
  },

  telemetryRevisionColor(marker) {
    if (marker.revision_state === "backfill") return "rgba(14, 165, 233, 0.72)"
    return "rgba(251, 191, 36, 0.78)"
  },

  eventMarkerOverlapsWindow(marker, cutoff) {
    if (
      marker.marker_type === "source_binding_interval" ||
      marker.marker_type === "retention_gap" ||
      marker.marker_type === "telemetry_revision_range" ||
      (marker.marker_type === "telemetry_backfill_lifecycle" && marker.starts_at_ms)
    ) {
      return this.intervalMarkerOverlapsWindow(marker, cutoff)
    }

    if (!marker.timestamp_ms) return false
    return marker.timestamp_ms / 1000 >= cutoff
  },

  limitMarkerOverlapsWindow(marker, cutoff) {
    if (
      marker.marker_type === "limit_definition_interval" ||
      marker.marker_type === "limit_analysis_bucket"
    ) {
      return this.intervalMarkerOverlapsWindow(marker, cutoff)
    }

    if (!marker.timestamp_ms) return false
    return marker.timestamp_ms / 1000 >= cutoff
  },

  intervalMarkerOverlapsWindow(marker, cutoff) {
    const start = marker.starts_at_ms && marker.starts_at_ms / 1000
    const end = marker.ends_at_ms ? marker.ends_at_ms / 1000 : this.chartWindowEnd()
    if (!start) return false
    return end >= cutoff
  },

  liveMode() {
    return this.el.dataset.timeMode === "live"
  },

  recordLiveActivity({
    appendedPointCount,
    advancedLiveWindow,
    refreshIntervalMs,
    seriesPayload,
    windowEndMs,
  }) {
    if (!this.liveMode()) return

    const intervalMs = Number(refreshIntervalMs)

    if (advancedLiveWindow) {
      this.liveHeartbeatObserved = true
      this.liveHeartbeatCurrent = true
      this.el.dataset.liveHeartbeatAtMs = `${Math.round(Number(windowEndMs))}`

      if (Number.isFinite(intervalMs) && intervalMs > 0) {
        this.el.dataset.liveRefreshIntervalMs = `${Math.round(intervalMs)}`
      }

      if (this.liveHeartbeatTimer) clearTimeout(this.liveHeartbeatTimer)
      const heartbeatTimeoutMs = Math.max(
        (Number.isFinite(intervalMs) && intervalMs > 0 ? intervalMs : 1_000) * 3,
        5_000
      )

      this.liveHeartbeatTimer = setTimeout(() => {
        this.liveHeartbeatCurrent = false
        this.renderLiveEdge()
      }, heartbeatTimeoutMs)
    }

    if (appendedPointCount > 0) {
      this.liveReceivingSamples = true
      this.liveArrivalSequence += 1
      this.el.dataset.liveArrivalCount = `${appendedPointCount}`
      this.el.dataset.liveArrivalSequence = `${this.liveArrivalSequence}`

      const latestTimestampMs = this.seriesPayloadLatestTimestampMs(seriesPayload)
      if (Number.isFinite(latestTimestampMs)) {
        this.el.dataset.liveLastSampleAtMs = `${Math.round(latestTimestampMs)}`
      }

      this.restartLiveArrivalAnimation()
      if (this.liveArrivalTimer) clearTimeout(this.liveArrivalTimer)
      this.liveArrivalTimer = setTimeout(() => {
        this.liveReceivingSamples = false
        if (this.liveEdge) this.liveEdge.classList.remove("is-receiving")
        this.renderLiveEdge()
      }, 720)
    }

    this.renderLiveEdge()
  },

  restartLiveArrivalAnimation() {
    if (!this.liveEdge) return

    this.liveEdge.classList.remove("is-receiving")
    void this.liveEdge.offsetWidth
    this.liveEdge.classList.add("is-receiving")
  },

  liveStreamState() {
    const page = this.el.closest && this.el.closest("#ops-dashboard-show-page")
    const degradedSources = Number(page && page.dataset.runtimeSourceExecutionDegraded)
    const refreshDegraded = page && page.dataset.runtimeRefreshStatus === "degraded"

    if (refreshDegraded || (Number.isFinite(degradedSources) && degradedSources > 0)) {
      return "degraded"
    }

    const delayedWatermark = (this.eventMarkers || []).some((marker) =>
      (marker.marker_type === "source_watermark_cursor" ||
        marker.marker_type === "source_watermark_event") &&
      (marker.display_mode !== "status" ||
        marker.freshness_state === "stale" ||
        marker.freshness_state === "retention_gap")
    )

    if (this.el.dataset.watermarkBoundaryVisible === "true" || delayedWatermark) {
      return "delayed"
    }

    if (!this.liveHeartbeatObserved) return "connecting"
    if (!this.liveHeartbeatCurrent) return "paused"
    if (this.liveReceivingSamples) return "receiving"
    return "following"
  },

  renderLiveEdge() {
    if (!this.liveEdge) return

    if (!this.liveMode()) {
      this.liveEdge.hidden = true
      delete this.el.dataset.liveStreamState
      this.publishDashboardLiveState()
      return
    }

    const bbox = this.chart && this.chart.bbox
    if (!bbox) return

    const state = this.liveStreamState()
    const plotRight = (bbox.left || 0) + (bbox.width || this.el.clientWidth)
    const edgeWidth = 64

    this.liveEdge.hidden = false
    this.liveEdge.dataset.liveStreamState = state
    this.el.dataset.liveStreamState = state
    Object.assign(this.liveEdge.style, {
      left: `${Math.max(0, plotRight - edgeWidth)}px`,
      top: `${bbox.top || 0}px`,
      width: `${edgeWidth}px`,
      height: `${bbox.height || this.el.clientHeight}px`,
    })

    const label = this.liveStreamLabel(state)
    const description = this.liveStreamDescription(state)
    if (this.liveEdgeLabel) this.liveEdgeLabel.textContent = label
    this.liveEdge.title = description
    this.liveEdge.setAttribute("aria-label", description)
    this.publishDashboardLiveState()
  },

  liveStreamLabel(state) {
    if (state === "connecting") return "SYNC"
    if (state === "paused") return "PAUSED"
    if (state === "delayed") return "DELAYED"
    if (state === "degraded") return "DEGRADED"
    return "LIVE"
  },

  liveStreamDescription(state) {
    if (state === "connecting") return "Connecting the live telemetry window"
    if (state === "paused") return "Live telemetry heartbeat has paused"
    if (state === "delayed") return "Live telemetry is following a delayed source watermark"
    if (state === "degraded") return "Live telemetry source execution is degraded"

    if (state === "receiving") {
      const count = Number(this.el.dataset.liveArrivalCount) || 0
      return `Live telemetry received ${count} new ${count === 1 ? "sample" : "samples"}`
    }

    return "Live telemetry window is current"
  },

  publishDashboardLiveState() {
    const page = this.el.closest && this.el.closest("#ops-dashboard-show-page")
    if (!page || !page.querySelectorAll) return

    const charts = Array.from(
      page.querySelectorAll("[phx-hook='TelemetryChart'][data-time-mode='live']")
    )

    if (charts.length === 0) {
      delete page.dataset.dashboardLiveStreamState
      delete page.dataset.dashboardLiveStreamChartCount
      return
    }

    const states = charts.map((chart) => chart.dataset.liveStreamState || "connecting")
    const priority = ["degraded", "paused", "delayed", "connecting", "receiving", "following"]
    const state = priority.find((candidate) => states.includes(candidate)) || "connecting"

    page.dataset.dashboardLiveStreamState = state
    page.dataset.dashboardLiveStreamChartCount = `${charts.length}`

    const timeRange = page.querySelector("#dashboard-active-time-range")
    if (timeRange) timeRange.dataset.liveStreamState = state
  },

  advanceLiveWindow(windowEndMs) {
    if (!this.liveMode()) return false

    const windowEnd = Number(windowEndMs) / 1000
    if (!Number.isFinite(windowEnd) || windowEnd <= 0) return false

    this.liveWindowEnd = windowEnd
    this.el.dataset.liveWindowStartMs = `${Math.round((windowEnd - this.windowSeconds) * 1000)}`
    this.el.dataset.liveWindowEndMs = `${Math.round(windowEnd * 1000)}`
    return true
  },

  chartWindowEnd() {
    if (this.liveMode() && Number.isFinite(this.liveWindowEnd)) return this.liveWindowEnd
    if (this.xs.length === 0) return null
    return this.xs[this.xs.length - 1]
  },

  dedupeMarkers(markers) {
    const seen = new Set()
    return markers.filter((marker) => {
      const key =
        marker.link_id ||
        marker.marker_id ||
        `${marker.marker_type || "limit_event"}:${marker.limit_event_id || marker.limit_definition_id}:${marker.timestamp_ms || marker.starts_at_ms}`
      if (seen.has(key)) return false
      seen.add(key)
      return true
    })
  },

  chartSize() {
    // Keep Grafana-style legends in a fixed footer rather than layering them
    // over the plot or making the panel itself scroll.
    const containerHeight = this.el.clientHeight || 180
    return {
      width: this.el.clientWidth,
      height: Math.max(containerHeight - this.legendHeight(), 80),
    }
  },

  chartPalette() {
    const accent = getComputedStyle(this.el).color || "#c0caf5"
    return [
      accent,
      "rgba(45, 212, 191, 0.92)",
      "rgba(251, 191, 36, 0.90)",
      "rgba(248, 113, 113, 0.88)",
      "rgba(167, 139, 250, 0.90)",
    ]
  },

  chartOptions() {
    // Derive the series color from the surrounding theme instead of
    // hardcoding palette values.
    const palette = this.chartPalette()
    const axis = {
      stroke: "rgba(204, 204, 220, 0.62)",
      grid: { stroke: "rgba(204, 204, 220, 0.08)" },
      ticks: { stroke: "rgba(204, 204, 220, 0.12)" },
      font: "11px ui-sans-serif, system-ui, sans-serif",
    }

    return {
      ...this.chartSize(),
      legend: { show: false },
      cursor: {
        drag: { x: this.el.dataset.editMode !== "true", y: false },
        sync: { key: this.el.dataset.correlationGroup || "cadence-dashboard-time" },
      },
      hooks: {
        setCursor: [(u) => this.renderSharedTooltip(u)],
      },
      scales: this.chartScales(),
      series: [{}].concat(this.chartSeriesOptions(palette)),
      bands: this.chartBands(palette),
      axes: this.chartAxes(axis),
    }
  },

  chartScales() {
    return this.unitGroups().reduce(
      (scales, unit) => ({
        ...scales,
        [this.unitScaleKey(unit)]: {},
      }),
      { x: { time: true, range: (_u, dataMin, dataMax) => this.chartXRange(dataMin, dataMax) } }
    )
  },

  chartXRange(dataMin, dataMax) {
    const liveWindowEnd = this.liveMode() ? this.chartWindowEnd() : null

    if (Number.isFinite(liveWindowEnd)) {
      return [liveWindowEnd - this.windowSeconds, liveWindowEnd]
    }

    const requestedRange = this.requestedTimeRange()
    if (requestedRange) return requestedRange

    const values = [dataMin, dataMax]
      .concat(this.markerXValues(this.limitMarkers))
      .concat(this.markerXValues(this.eventMarkers))
      .filter((value) => Number.isFinite(value))

    if (values.length === 0) return [dataMin, dataMax]

    const min = Math.min(...values)
    const max = Math.max(...values)

    if (min === max) return [min - 30, max + 30]

    return [min, max]
  },

  requestedTimeRange() {
    const fromMs = Date.parse(this.el.dataset.timeFrom || "")
    const toMs = Date.parse(this.el.dataset.timeTo || "")

    if (!Number.isFinite(fromMs) || !Number.isFinite(toMs) || fromMs >= toMs) return null
    return [fromMs / 1000, toMs / 1000]
  },

  chartXDomain() {
    const scale = this.chart && this.chart.scales && this.chart.scales.x

    return {
      min: Number.isFinite(scale && scale.min) ? scale.min : this.xs[0],
      max: Number.isFinite(scale && scale.max) ? scale.max : this.xs[this.xs.length - 1],
    }
  },

  markerXValues(markers) {
    if (!Array.isArray(markers)) return []

    return markers.flatMap((marker) =>
      ["timestamp_ms", "starts_at_ms", "ends_at_ms"]
        .map((key) => {
          const value = Number(marker[key])
          return Number.isFinite(value) ? value / 1000 : null
        })
        .filter((value) => value !== null)
    )
  },

  chartAxes(axis) {
    const unitGroups = this.unitGroups()

    return [
      axis,
      ...unitGroups.map((unit, index) => ({
        ...axis,
        scale: this.unitScaleKey(unit),
        label: unit || this.el.dataset.unit || undefined,
        side: index % 2 === 0 ? 3 : 1,
      })),
    ]
  },

  unitGroups() {
    if (this.axisMode === "shared") return [""]

    const units = this.seriesList
      .filter((series) => this.seriesVisible(series))
      .map((series) => series.unit || "")
      .filter((unit) => unit !== "")

    if (units.length === 0) return [""]
    return Array.from(new Set(units))
  },

  sourceUnitGroups() {
    const units = this.seriesList.map((series) => series.unit || "").filter((unit) => unit !== "")

    if (units.length === 0) return [""]
    return Array.from(new Set(units))
  },

  unitScaleKey(unit) {
    if (this.axisMode === "shared") return "y"

    const units = this.unitGroups()
    const index = Math.max(units.indexOf(unit || ""), 0)
    return index === 0 ? "y" : `y${index}`
  },

  chartSeriesOptions(palette) {
    return (this.plotSeries || []).map((entry) => {
      const series = this.seriesList[entry.seriesIndex] || {}
      const color = palette[entry.seriesIndex % palette.length]

      if (entry.kind === "line") {
        const compare = series.role === "compare"

        return {
          label: series.label || series.id || this.widgetId,
          show: this.seriesVisible(series),
          scale: this.unitScaleKey(series.unit),
          stroke: compare ? this.compareSeriesColor(color) : color,
          width: compare ? Math.max(this.lineWidthValue() - 0.4, 0.8) : this.lineWidthValue(),
          dash: compare ? [6, 4] : undefined,
          spanGaps: this.spanGaps,
          gaps: (plot, seriesIndex, idx0, idx1, nullGaps) =>
            this.seriesGaps(plot, seriesIndex, idx0, idx1, nullGaps),
          fill: this.fillOpacity > 0 ? this.seriesFillColor(color) : undefined,
          points: { show: this.showPoints, size: 4 },
        }
      }

      return {
        label: `${series.label || series.id || this.widgetId} ${entry.kind === "envelope_low" ? "min" : "max"}`,
        show: this.seriesVisible(series),
        scale: this.unitScaleKey(series.unit),
        stroke: "rgba(0, 0, 0, 0)",
        width: 0,
        points: { show: false },
        spanGaps: false,
        gaps: (plot, seriesIndex, idx0, idx1, nullGaps) =>
          this.seriesGaps(plot, seriesIndex, idx0, idx1, nullGaps),
      }
    })
  },

  seriesLegendColor(series, index, palette) {
    const color = palette[index % palette.length]
    return series && series.role === "compare" ? this.compareSeriesColor(color) : color
  },

  compareSeriesColor(_color) {
    return "rgba(203, 213, 225, 0.76)"
  },

  lineWidthValue() {
    if (this.lineWidth === "thin") return 1
    if (this.lineWidth === "bold") return 3
    return 2
  },

  seriesFillColor(color) {
    const alpha = this.fillOpacity / 100
    if (color.startsWith("rgba(")) {
      const parts = color.slice(5, -1).split(",")
      if (parts.length >= 3) return `rgba(${parts.slice(0, 3).join(",")}, ${alpha})`
    }
    return `rgba(125, 211, 252, ${alpha})`
  },

  installRangeSelection() {
    if (!this.chart || this.el.dataset.editMode === "true") return

    const overlay = this.el.querySelector(".u-over")
    if (!overlay) return

    if (this.rangeSelectionOverlay && this.handleRangeSelection) {
      this.rangeSelectionOverlay.removeEventListener("mouseup", this.handleRangeSelection)
    }

    this.rangeSelectionOverlay = overlay
    this.handleRangeSelection = () => {
      const selection = this.chart && this.chart.select
      if (!selection || selection.width < 8) return

      const fromSeconds = this.chart.posToVal(selection.left, "x")
      const toSeconds = this.chart.posToVal(selection.left + selection.width, "x")
      if (!Number.isFinite(fromSeconds) || !Number.isFinite(toSeconds)) return

      const from = new Date(Math.min(fromSeconds, toSeconds) * 1000).toISOString()
      const to = new Date(Math.max(fromSeconds, toSeconds) * 1000).toISOString()
      this.rangeSelectionInFlight = true
      this.pushEvent("set_chart_time_range", { from, to })
      this.chart.setSelect({ left: 0, width: 0, top: 0, height: 0 }, false)
      setTimeout(() => {
        this.rangeSelectionInFlight = false
      }, 0)
    }
    overlay.addEventListener("mouseup", this.handleRangeSelection)
  },

  chartBands(palette) {
    const bands = []
    const plotSeries = this.plotSeries || []

    plotSeries.forEach((entry, index) => {
      if (entry.kind !== "envelope_high") return
      if (!this.seriesVisible(this.seriesList[entry.seriesIndex])) return

      const lowIndex = plotSeries.findIndex(
        (candidate) =>
          candidate.kind === "envelope_low" &&
          candidate.seriesIndex === entry.seriesIndex
      )
      if (lowIndex < 0) return

      const color = palette[entry.seriesIndex % palette.length]
      bands.push({
        series: [index + 1, lowIndex + 1],
        fill: () => this.envelopeBandColor(color),
      })
    })

    return bands
  },

  envelopeBandColor(color) {
    if (color.startsWith("rgba(")) {
      const parts = color.slice(5, -1).split(",")
      if (parts.length >= 3) return `rgba(${parts.slice(0, 3).join(",")}, 0.16)`
    }

    return "rgba(125, 211, 252, 0.14)"
  },
}

export default TelemetryChart
