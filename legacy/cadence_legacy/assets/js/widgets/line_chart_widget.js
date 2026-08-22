/**
 * Line Chart Widget
 *
 * A real-time line chart widget using SciChart for GPU-accelerated rendering.
 * Supports multiple telemetry series with configurable colors and axes.
 */

import { BaseWidget, registerWidget } from "../dashboard/widget_factory"
import { createRealtimeChart, addLineSeries } from "../scichart/scichart_config"
import { TokyoNightColors } from "../scichart/tokyo_night_theme"
import { getStore } from "../telemetry_store"

/**
 * LineChartWidget - Real-time line chart for telemetry data.
 */
export class LineChartWidget extends BaseWidget {
  static displayName = "Line Chart"
  static description = "Real-time line chart for telemetry values"
  static icon = "chart-line"

  constructor(options) {
    super(options)
    this.type = "line_chart"
    this.surface = null
    this.wasmContext = null
    this.dataSeries = new Map()  // key -> XyDataSeries
    this.chartContainer = null
  }

  async init() {
    this.render()
    await this._initChart()
    this._subscribeToTelemetry()
    this.initialized = true
  }

  renderContent() {
    return `<div class="chart-container w-full h-full" id="chart-${this.id}"></div>`
  }

  async _initChart() {
    this.chartContainer = this.container.querySelector(`#chart-${this.id}`)

    if (!this.chartContainer) {
      console.error("[LineChartWidget] Chart container not found")
      return
    }

    try {
      const { sciChartSurface, wasmContext, theme } = await createRealtimeChart(this.chartContainer, {
        title: this.config.title || "",
        yAxisTitle: this.config.y_axis?.label || "",
        yAxisUnit: this.config.y_axis?.unit || "",
        yMin: this.config.y_axis?.min,
        yMax: this.config.y_axis?.max,
        timeWindowSeconds: this.config.time_window || 60,
        showLegend: this.config.telemetry_items?.length > 1,
        showRollover: true,
        enableZoom: true
      })

      this.surface = sciChartSurface
      this.wasmContext = wasmContext
      this.theme = theme

      // Add series for each telemetry item
      const items = this.config.telemetry_items || []
      for (let i = 0; i < items.length; i++) {
        const item = items[i]
        const key = `${item.target}:${item.packet}:${item.item}`

        const { dataSeries, renderableSeries } = addLineSeries(this.surface, this.wasmContext, {
          name: item.label || item.item,
          color: item.color || this.theme.getSeriesColor(i),
          strokeThickness: 2.5,
          fifoCapacity: 10000,
          antiAliased: true
        })

        this.dataSeries.set(key, dataSeries)
      }

    } catch (err) {
      console.error("[LineChartWidget] Failed to initialize chart:", err)
      this.chartContainer.innerHTML = `
        <div class="flex items-center justify-center h-full">
          <p class="text-error text-sm">Failed to load chart</p>
        </div>
      `
    }
  }

  _subscribeToTelemetry() {
    const store = getStore()
    const items = this.config.telemetry_items || []

    for (const item of items) {
      const key = `${item.target}:${item.packet}:${item.item}`
      const dataSeries = this.dataSeries.get(key)

      if (!dataSeries) continue

      // Load historical data
      const history = store.getHistory(key, 1000)
      for (const entry of history) {
        dataSeries.append(entry.timestamp, entry.value)
      }

      // Subscribe to updates
      const unsub = store.subscribe(key, (value, timestamp, limitsState) => {
        if (typeof value === "number") {
          dataSeries.append(timestamp, value)
        }
      })

      this.subscriptions.push(unsub)
    }
  }

  updateConfig(config) {
    const oldConfig = this.config
    this.config = { ...this.config, ...config }

    // If telemetry items changed, reinitialize
    const itemsChanged = JSON.stringify(oldConfig.telemetry_items) !==
                         JSON.stringify(this.config.telemetry_items)

    if (itemsChanged) {
      this._cleanup()
      this.init()
    } else {
      // Just update title
      const titleEl = this.container.querySelector(".widget-title")
      if (titleEl) titleEl.textContent = this.config.title || "Line Chart"
    }
  }

  _cleanup() {
    // Unsubscribe from telemetry
    for (const unsub of this.subscriptions) {
      unsub()
    }
    this.subscriptions = []

    // Destroy SciChart
    if (this.surface) {
      this.surface.delete()
      this.surface = null
    }

    this.dataSeries.clear()
  }

  destroy() {
    this._cleanup()
    super.destroy()
  }

  openConfig() {
    // Emit event for config modal (handled by LiveView)
    const event = new CustomEvent("widget:configure", {
      detail: {
        widgetId: this.id,
        widgetType: this.type,
        config: this.getConfig()
      },
      bubbles: true
    })
    this.container.dispatchEvent(event)
  }
}

// Register the widget
registerWidget("line_chart", LineChartWidget)

export default LineChartWidget
