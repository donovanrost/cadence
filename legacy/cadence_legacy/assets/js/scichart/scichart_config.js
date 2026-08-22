/**
 * SciChart Configuration and Initialization
 *
 * This module handles SciChart licensing, WASM loading, and provides
 * factory functions for creating common chart types.
 */

import {
  SciChartSurface,
  SciChartDefaults,
  NumericAxis,
  DateTimeNumericAxis,
  FastLineRenderableSeries,
  XyDataSeries,
  EAutoRange,
  EAxisAlignment,
  ENumericFormat,
  NumberRange,
  RolloverModifier,
  ZoomPanModifier,
  ZoomExtentsModifier,
  MouseWheelZoomModifier,
  RubberBandXyZoomModifier,
  XAxisDragModifier,
  YAxisDragModifier,
  LegendModifier
} from "scichart"

import TokyoNightTheme, { TokyoNightColors } from "./tokyo_night_theme"

// Track initialization state
let initialized = false
let initPromise = null

/**
 * Initialize SciChart with Community Edition license.
 * Must be called before creating any charts.
 *
 * @returns {Promise} Resolves when SciChart is ready
 */
export async function initSciChart() {
  if (initialized) return
  if (initPromise) return initPromise

  initPromise = (async () => {
    // Set runtime license key (Community Edition)
    // SciChart.js Community Edition is free for non-commercial use
    SciChartSurface.setRuntimeLicenseKey("")

    // Configure WASM loading from local static files
    SciChartSurface.configure({
      wasmUrl: "/wasm/scichart2d.wasm",
      dataUrl: "/wasm/scichart2d.data"
    })

    // Set global defaults
    SciChartDefaults.enableResampling = true
    SciChartDefaults.useSharedCache = true

    initialized = true
  })()

  return initPromise
}

/**
 * Create a real-time line chart optimized for telemetry data.
 *
 * @param {HTMLElement|string} rootElement - The container element or ID
 * @param {Object} options - Chart configuration options
 * @returns {Promise<{surface: SciChartSurface, wasmContext: any}>}
 */
export async function createRealtimeChart(rootElement, options = {}) {
  await initSciChart()

  const {
    title = "",
    yAxisTitle = "",
    yAxisUnit = "",
    yMin = undefined,
    yMax = undefined,
    timeWindowSeconds = 60,
    showLegend = true,
    showRollover = true,
    enableZoom = true
  } = options

  const theme = new TokyoNightTheme()

  const { sciChartSurface, wasmContext } = await SciChartSurface.create(rootElement, {
    theme,
    padding: { left: 0, top: 0, right: 0, bottom: 0 }
  })

  // X-Axis: Time (as unix milliseconds)
  const xAxis = new NumericAxis(wasmContext, {
    axisTitle: "",  // Hide axis title for cleaner look
    axisAlignment: EAxisAlignment.Bottom,
    autoRange: EAutoRange.Always,
    labelFormat: ENumericFormat.NoFormat,
    labelPostfix: "",
    labelPrecision: 0,
    labelStyle: {
      fontSize: 10,
      color: TokyoNightColors.textMuted
    },
    drawMajorGridLines: true,
    drawMinorGridLines: false,
    drawMajorBands: false,
    majorGridLineStyle: {
      color: TokyoNightColors.border + "30",
      strokeThickness: 1
    }
  })

  // Custom label formatting for time
  xAxis.labelProvider.formatLabel = (value) => {
    if (!value || !isFinite(value)) return ""
    const date = new Date(value)
    if (isNaN(date.getTime())) return ""
    const h = date.getHours().toString().padStart(2, '0')
    const m = date.getMinutes().toString().padStart(2, '0')
    const s = date.getSeconds().toString().padStart(2, '0')
    return `${h}:${m}:${s}`
  }

  sciChartSurface.xAxes.add(xAxis)

  // Y-Axis: Values
  const yAxisLabel = yAxisUnit ? `(${yAxisUnit})` : ""
  const yAxis = new NumericAxis(wasmContext, {
    axisTitle: yAxisLabel,
    axisTitleStyle: {
      fontSize: 11,
      color: TokyoNightColors.textMuted
    },
    axisAlignment: EAxisAlignment.Left,
    autoRange: (yMin === undefined && yMax === undefined) ? EAutoRange.Always : EAutoRange.Never,
    visibleRange: (yMin !== undefined && yMax !== undefined) ? new NumberRange(yMin, yMax) : undefined,
    labelStyle: {
      fontSize: 10,
      color: TokyoNightColors.textMuted
    },
    drawMajorGridLines: true,
    drawMinorGridLines: false,
    drawMajorBands: false,
    majorGridLineStyle: {
      color: TokyoNightColors.border + "30",
      strokeThickness: 1
    }
  })
  sciChartSurface.yAxes.add(yAxis)

  // Add modifiers
  const modifiers = []

  if (showRollover) {
    modifiers.push(new RolloverModifier({
      rolloverLineStroke: TokyoNightColors.cyan + "80",
      showRolloverLine: true
    }))
  }

  if (enableZoom) {
    modifiers.push(
      new ZoomPanModifier({ enablePan: true }),
      new MouseWheelZoomModifier(),
      new ZoomExtentsModifier()
    )
  }

  if (showLegend) {
    modifiers.push(new LegendModifier({
      showCheckboxes: true,
      showSeriesMarkers: true,
      placementDivId: null  // Inline legend
    }))
  }

  if (modifiers.length > 0) {
    sciChartSurface.chartModifiers.add(...modifiers)
  }

  return { sciChartSurface, wasmContext, theme }
}

/**
 * Add a data series to an existing chart.
 *
 * @param {SciChartSurface} surface - The chart surface
 * @param {any} wasmContext - The WASM context
 * @param {Object} options - Series configuration
 * @returns {{dataSeries: XyDataSeries, renderableSeries: FastLineRenderableSeries}}
 */
export function addLineSeries(surface, wasmContext, options = {}) {
  const theme = new TokyoNightTheme()

  const {
    name = "",
    color = theme.getSeriesColor(surface.renderableSeries.size()),
    strokeThickness = 2,
    fifoCapacity = 10000,
    antiAliased = true
  } = options

  const dataSeries = new XyDataSeries(wasmContext, {
    dataSeriesName: name,
    fifoCapacity
  })

  const renderableSeries = new FastLineRenderableSeries(wasmContext, {
    dataSeries,
    stroke: color,
    strokeThickness,
    isDigitalLine: false
  })

  surface.renderableSeries.add(renderableSeries)

  return { dataSeries, renderableSeries }
}

/**
 * Create a sparkline chart (minimal, no axes visible).
 *
 * @param {HTMLElement|string} rootElement - The container element or ID
 * @param {Object} options - Chart configuration options
 * @returns {Promise<{surface: SciChartSurface, dataSeries: XyDataSeries, wasmContext: any}>}
 */
export async function createSparkline(rootElement, options = {}) {
  await initSciChart()

  const {
    color = TokyoNightColors.cyan,
    fifoCapacity = 100,
    fillOpacity = 0.2
  } = options

  const theme = new TokyoNightTheme()

  const { sciChartSurface, wasmContext } = await SciChartSurface.create(rootElement, {
    theme,
    padding: { left: 0, top: 0, right: 0, bottom: 0 }
  })

  // Hidden X-Axis
  const xAxis = new NumericAxis(wasmContext, {
    isVisible: false,
    autoRange: EAutoRange.Always
  })
  sciChartSurface.xAxes.add(xAxis)

  // Hidden Y-Axis
  const yAxis = new NumericAxis(wasmContext, {
    isVisible: false,
    autoRange: EAutoRange.Always
  })
  sciChartSurface.yAxes.add(yAxis)

  // Create data series
  const dataSeries = new XyDataSeries(wasmContext, { fifoCapacity })

  // Add line series with optional fill
  const lineSeries = new FastLineRenderableSeries(wasmContext, {
    dataSeries,
    stroke: color,
    strokeThickness: 1.5
  })

  sciChartSurface.renderableSeries.add(lineSeries)

  return { sciChartSurface, dataSeries, wasmContext }
}

export default {
  initSciChart,
  createRealtimeChart,
  addLineSeries,
  createSparkline,
  TokyoNightColors
}
