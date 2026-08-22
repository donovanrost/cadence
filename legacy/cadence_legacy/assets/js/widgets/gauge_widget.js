/**
 * Gauge Widget
 *
 * Displays a telemetry value as a radial gauge with configurable
 * min/max values and limits-based coloring.
 */

import { BaseWidget, registerWidget } from "../dashboard/widget_factory"
import { getStore } from "../telemetry_store"
import { getLimitsColor, TokyoNightColors } from "../scichart/tokyo_night_theme"

/**
 * GaugeWidget - Radial gauge for bounded telemetry values.
 */
export class GaugeWidget extends BaseWidget {
  static displayName = "Gauge"
  static description = "Radial gauge for bounded values like temperature or pressure"
  static icon = "chart-pie"

  constructor(options) {
    super(options)
    this.type = "gauge"
    this.currentValue = null
    this.limitsState = "unknown"
    this.canvasElement = null
    this.valueElement = null
    this.labelElement = null
  }

  init() {
    this.render()
    this._subscribeToTelemetry()
    this.initialized = true
  }

  renderContent() {
    const item = this.config.telemetry_item || {}
    const unit = this.config.unit || ""

    return `
      <div class="gauge-widget flex flex-col items-center justify-center h-full p-2">
        <div class="gauge-container relative" style="width: 100%; max-width: 200px; aspect-ratio: 1;">
          <canvas id="gauge-canvas-${this.id}" class="w-full h-full"></canvas>
          <div class="gauge-value-overlay absolute inset-0 flex flex-col items-center justify-center">
            <span class="gauge-value text-2xl font-mono font-bold" id="gauge-value-${this.id}">--</span>
            <span class="gauge-unit text-xs text-base-content/70">${unit}</span>
          </div>
        </div>
        <div class="gauge-label text-xs text-base-content/50 mt-1 text-center truncate w-full">
          ${item.target || ""}/${item.packet || ""}/${item.item || "Item"}
        </div>
      </div>
    `
  }

  render() {
    super.render()

    this.canvasElement = this.container.querySelector(`#gauge-canvas-${this.id}`)
    this.valueElement = this.container.querySelector(`#gauge-value-${this.id}`)

    // Initial draw
    this._drawGauge(0)

    // Handle resize
    this._resizeObserver = new ResizeObserver(() => {
      this._drawGauge(this._normalizeValue(this.currentValue))
    })

    if (this.canvasElement) {
      this._resizeObserver.observe(this.canvasElement.parentElement)
    }
  }

  _subscribeToTelemetry() {
    const item = this.config.telemetry_item

    if (!item || !item.target || !item.packet || !item.item) {
      console.warn("[GaugeWidget] No telemetry item configured")
      return
    }

    try {
      const store = getStore()
      const key = `${item.target}:${item.packet}:${item.item}`

      // Get current value if available
      const current = store.getCurrent(key)
      if (current) {
        this._updateDisplay(current.value, current.limitsState)
      }

      // Subscribe to updates
      const unsub = store.subscribe(key, (value, timestamp, limitsState) => {
        this._updateDisplay(value, limitsState)
      })

      this.subscriptions.push(unsub)
    } catch (err) {
      console.error("[GaugeWidget] Failed to subscribe to telemetry:", err)
    }
  }

  _updateDisplay(value, limitsState) {
    this.currentValue = value
    this.limitsState = limitsState

    // Update value text
    if (this.valueElement) {
      this.valueElement.textContent = this._formatValue(value)
      this.valueElement.style.color = getLimitsColor(limitsState)
    }

    // Redraw gauge
    this._drawGauge(this._normalizeValue(value))
  }

  _normalizeValue(value) {
    if (value === null || value === undefined) return 0

    const min = this.config.min_value ?? 0
    const max = this.config.max_value ?? 100
    const range = max - min

    if (range === 0) return 0

    return Math.max(0, Math.min(1, (value - min) / range))
  }

  _formatValue(value) {
    if (value === null || value === undefined) return "--"

    if (typeof value === "number") {
      if (Number.isInteger(value)) {
        return value.toString()
      }
      return value.toFixed(1)
    }

    return String(value)
  }

  _drawGauge(normalizedValue) {
    const canvas = this.canvasElement
    if (!canvas) return

    const ctx = canvas.getContext("2d")
    const container = canvas.parentElement
    const size = Math.min(container.clientWidth, container.clientHeight)

    // Set canvas size for proper resolution
    const dpr = window.devicePixelRatio || 1
    canvas.width = size * dpr
    canvas.height = size * dpr
    canvas.style.width = `${size}px`
    canvas.style.height = `${size}px`
    ctx.scale(dpr, dpr)

    const centerX = size / 2
    const centerY = size / 2
    const radius = (size / 2) - 10
    const lineWidth = Math.max(8, size / 12)

    // Clear canvas
    ctx.clearRect(0, 0, size, size)

    // Draw background arc (270 degrees, leaving 90 degrees at bottom)
    const startAngle = (3 * Math.PI) / 4  // 135 degrees
    const endAngle = (9 * Math.PI) / 4    // 405 degrees (wraps around)
    const totalArc = endAngle - startAngle

    ctx.beginPath()
    ctx.arc(centerX, centerY, radius, startAngle, endAngle)
    ctx.strokeStyle = TokyoNightColors.bg
    ctx.lineWidth = lineWidth
    ctx.lineCap = "round"
    ctx.stroke()

    // Draw value arc
    if (normalizedValue > 0) {
      const valueAngle = startAngle + (totalArc * normalizedValue)

      // Create gradient for value arc
      const gradient = this._createArcGradient(ctx, centerX, centerY, radius, startAngle, valueAngle)

      ctx.beginPath()
      ctx.arc(centerX, centerY, radius, startAngle, valueAngle)
      ctx.strokeStyle = gradient
      ctx.lineWidth = lineWidth
      ctx.lineCap = "round"
      ctx.stroke()
    }

    // Draw min/max labels
    ctx.font = `${Math.max(10, size / 16)}px sans-serif`
    ctx.fillStyle = TokyoNightColors.textMuted
    ctx.textAlign = "center"

    const min = this.config.min_value ?? 0
    const max = this.config.max_value ?? 100

    // Min label (bottom left)
    const minLabelX = centerX - radius * 0.7
    const minLabelY = centerY + radius * 0.7
    ctx.fillText(min.toString(), minLabelX, minLabelY)

    // Max label (bottom right)
    const maxLabelX = centerX + radius * 0.7
    const maxLabelY = centerY + radius * 0.7
    ctx.fillText(max.toString(), maxLabelX, maxLabelY)
  }

  _createArcGradient(ctx, cx, cy, radius, startAngle, endAngle) {
    // Use limits color based on current state
    const color = getLimitsColor(this.limitsState)

    // Create a simple solid color for now
    // Could be enhanced with gradient based on value position
    return color
  }

  openConfig() {
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

  destroy() {
    if (this._resizeObserver) {
      this._resizeObserver.disconnect()
    }
    super.destroy()
  }
}

// Register the widget
registerWidget("gauge", GaugeWidget)

export default GaugeWidget
