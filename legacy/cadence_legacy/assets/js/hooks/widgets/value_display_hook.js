/**
 * ValueDisplayWidget Hook
 *
 * Connects a Phoenix-rendered ValueDisplayWidget to the TelemetryStore
 * for real-time updates. This allows high-frequency telemetry updates
 * without LiveView round-trips.
 *
 * Expected data attributes:
 * - data-telemetry-key: The telemetry key to subscribe to (e.g., "SAT-1:HEALTH:CPU_TEMP")
 * - data-unit: The unit to display
 * - data-precision: Number of decimal places for formatting
 * - data-show-trend: Whether to show trend indicator
 *
 * Expected DOM structure (rendered by Phoenix):
 * - [data-value]: Element to update with current value
 * - [data-trend]: Element to update with trend arrow
 * - [data-limits-state]: Element to update with limits badge
 */

import { getStore } from "../../telemetry_store"
import { getLimitsColor, TokyoNightColors } from "../../scichart/tokyo_night_theme"

// Trend icons and colors
const TREND_ICONS = {
  up: "↑",
  down: "↓",
  stable: "•"
}

const TREND_COLORS = {
  up: TokyoNightColors.teal,
  down: TokyoNightColors.red,
  stable: TokyoNightColors.textMuted
}

// Limits state to badge class mapping
const LIMITS_BADGE_CLASSES = {
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

const LIMITS_LABELS = {
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

/**
 * ValueDisplayWidget LiveView Hook
 */
export const ValueDisplayWidgetHook = {
  mounted() {
    this.telemetryKey = this.el.dataset.telemetryKey
    this.unit = this.el.dataset.unit || ""
    this.precision = parseInt(this.el.dataset.precision || "2", 10)
    this.showTrend = this.el.dataset.showTrend === "true"

    // Get DOM element references
    this.valueEl = this.el.querySelector("[data-value]")
    this.trendEl = this.el.querySelector("[data-trend]")
    this.limitsStateEl = this.el.querySelector("[data-limits-state]")

    // State
    this.currentValue = null
    this.previousValue = null
    this.trend = null

    // Subscribe to telemetry if we have a key
    if (this.telemetryKey) {
      this._subscribe()
    }
  },

  updated() {
    // Check if telemetry key changed
    const newKey = this.el.dataset.telemetryKey
    if (newKey !== this.telemetryKey) {
      this._unsubscribe()
      this.telemetryKey = newKey
      if (this.telemetryKey) {
        this._subscribe()
      }
    }

    // Update other config
    this.unit = this.el.dataset.unit || ""
    this.precision = parseInt(this.el.dataset.precision || "2", 10)
    this.showTrend = this.el.dataset.showTrend === "true"
  },

  destroyed() {
    this._unsubscribe()
  },

  _subscribe() {
    try {
      const store = getStore()
      if (!store) {
        console.warn("[ValueDisplayWidgetHook] TelemetryStore not available")
        return
      }

      // Get current value if available
      const current = store.getCurrent(this.telemetryKey)
      if (current) {
        this._updateDisplay(current.value, current.limitsState)
      }

      // Subscribe to updates
      this._unsubscribeFn = store.subscribe(
        this.telemetryKey,
        (value, timestamp, limitsState) => {
          this._updateDisplay(value, limitsState)
        }
      )
    } catch (err) {
      console.error("[ValueDisplayWidgetHook] Failed to subscribe:", err)
    }
  },

  _unsubscribe() {
    if (this._unsubscribeFn) {
      this._unsubscribeFn()
      this._unsubscribeFn = null
    }
  },

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

    // Update value display
    if (this.valueEl) {
      this.valueEl.textContent = this._formatValue(value)
      const color = getLimitsColor(limitsState)
      this.valueEl.style.color = color
    }

    // Update trend indicator
    if (this.trendEl && this.showTrend) {
      this.trendEl.textContent = TREND_ICONS[this.trend] || ""
      this.trendEl.style.color = TREND_COLORS[this.trend] || ""
    }

    // Update limits state badge
    if (this.limitsStateEl) {
      const badgeClass = LIMITS_BADGE_CLASSES[limitsState] || LIMITS_BADGE_CLASSES.unknown
      const label = LIMITS_LABELS[limitsState] || LIMITS_LABELS.unknown
      this.limitsStateEl.innerHTML = `<span class="badge badge-sm ${badgeClass}">${label}</span>`
    }
  },

  _formatValue(value) {
    if (value === null || value === undefined) return "--"

    if (typeof value === "number") {
      if (Number.isInteger(value)) {
        return value.toString()
      }
      return value.toFixed(this.precision)
    }

    return String(value)
  }
}

export default ValueDisplayWidgetHook
