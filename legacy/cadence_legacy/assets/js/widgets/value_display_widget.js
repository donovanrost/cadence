/**
 * Value Display Widget
 *
 * Displays the current value of a single telemetry item with limits coloring.
 * Shows value, unit, limits state, and optional trend indicator.
 */

import { BaseWidget, registerWidget } from "../dashboard/widget_factory"
import { getStore } from "../telemetry_store"
import { getLimitsColor, TokyoNightColors } from "../scichart/tokyo_night_theme"

/**
 * ValueDisplayWidget - Shows current value with limits coloring.
 */
export class ValueDisplayWidget extends BaseWidget {
  static displayName = "Value Display"
  static description = "Shows current telemetry value with limits status"
  static icon = "number"

  constructor(options) {
    super(options)
    this.type = "value_display"
    this.currentValue = null
    this.limitsState = "unknown"
    this.previousValue = null
    this.trend = null  // "up" | "down" | "stable"
    this.valueElement = null
    this.trendElement = null
    this.stateElement = null
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
      <div class="value-display flex flex-col items-center justify-center h-full">
        <div class="value-container flex items-baseline gap-2">
          <span class="value text-4xl font-mono font-bold" id="value-${this.id}">--</span>
          <span class="unit text-lg text-base-content/70">${unit}</span>
          <span class="trend text-2xl" id="trend-${this.id}"></span>
        </div>
        <div class="limits-state mt-2" id="state-${this.id}">
          <span class="badge badge-sm badge-neutral">Unknown</span>
        </div>
        <div class="item-label text-sm text-base-content/50 mt-2">
          ${item.target || ""}/${item.packet || ""}/${item.item || "Item"}
        </div>
      </div>
    `
  }

  render() {
    super.render()

    // Get references to dynamic elements
    this.valueElement = this.container.querySelector(`#value-${this.id}`)
    this.trendElement = this.container.querySelector(`#trend-${this.id}`)
    this.stateElement = this.container.querySelector(`#state-${this.id}`)
  }

  _subscribeToTelemetry() {
    const item = this.config.telemetry_item

    if (!item || !item.target || !item.packet || !item.item) {
      console.warn("[ValueDisplayWidget] No telemetry item configured")
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
      console.error("[ValueDisplayWidget] Failed to subscribe to telemetry:", err)
    }
  }

  _updateDisplay(value, limitsState) {
    // Calculate trend
    if (this.currentValue !== null && typeof value === "number") {
      if (value > this.currentValue) {
        this.trend = "up"
      } else if (value < this.currentValue) {
        this.trend = "down"
      } else {
        this.trend = "stable"
      }
    }

    this.previousValue = this.currentValue
    this.currentValue = value
    this.limitsState = limitsState

    // Update value display
    if (this.valueElement) {
      this.valueElement.textContent = this._formatValue(value)

      // Apply limits color
      const color = getLimitsColor(limitsState)
      this.valueElement.style.color = color
    }

    // Update trend indicator
    if (this.trendElement && this.config.show_trend !== false) {
      const trendIcons = {
        up: "&#x2191;",    // ↑
        down: "&#x2193;",  // ↓
        stable: "&#x2022;" // •
      }
      const trendColors = {
        up: TokyoNightColors.teal,
        down: TokyoNightColors.red,
        stable: TokyoNightColors.textMuted
      }

      this.trendElement.innerHTML = trendIcons[this.trend] || ""
      this.trendElement.style.color = trendColors[this.trend] || ""
    }

    // Update limits state badge
    if (this.stateElement) {
      const badgeClass = this._getLimitsBadgeClass(limitsState)
      this.stateElement.innerHTML = `
        <span class="badge badge-sm ${badgeClass}">${this._formatLimitsState(limitsState)}</span>
      `
    }
  }

  _formatValue(value) {
    if (value === null || value === undefined) return "--"

    const precision = this.config.precision ?? 2

    if (typeof value === "number") {
      if (Number.isInteger(value)) {
        return value.toString()
      }
      return value.toFixed(precision)
    }

    return String(value)
  }

  _formatLimitsState(state) {
    const labels = {
      green: "Normal",
      yellow: "Warning",
      yellow_low: "Low Warning",
      yellow_high: "High Warning",
      red: "Critical",
      red_low: "Low Critical",
      red_high: "High Critical",
      blue: "Stale",
      unknown: "Unknown"
    }
    return labels[state] || "Unknown"
  }

  _getLimitsBadgeClass(state) {
    const classes = {
      green: "badge-success",
      yellow: "badge-warning",
      yellow_low: "badge-warning",
      yellow_high: "badge-warning",
      red: "badge-error",
      red_low: "badge-error",
      red_high: "badge-error",
      blue: "badge-info",
      unknown: "badge-neutral"
    }
    return classes[state] || "badge-neutral"
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
}

// Register the widget
registerWidget("value_display", ValueDisplayWidget)

export default ValueDisplayWidget
