/**
 * Fleet Honeycomb
 *
 * A hexagonal grid visualization showing spacecraft health at-a-glance.
 * Each hexagon represents one spacecraft/target with color indicating health status.
 */

import { TokyoNightColors, getLimitsColor } from "../scichart/tokyo_night_theme"
import { getStore } from "../telemetry_store"

// Hexagon layout constants
const HEX_SIZE = 30  // Radius of hexagon
const HEX_WIDTH = HEX_SIZE * 2
const HEX_HEIGHT = Math.sqrt(3) * HEX_SIZE
const HEX_SPACING = 4

/**
 * FleetHoneycomb - Renders a hexagonal grid of spacecraft health indicators.
 */
export class FleetHoneycomb {
  constructor(container, targets, options = {}) {
    this.container = container
    this.targets = targets
    this.options = options
    this.svg = null
    this.hexagons = new Map()  // targetId -> hex element
    this.subscriptions = []

    this._render()
    this._subscribeToHealth()
  }

  _render() {
    // Clear container
    this.container.innerHTML = ""

    if (this.targets.length === 0) {
      this.container.innerHTML = `
        <div class="flex items-center justify-center h-full text-base-content/50">
          No targets configured
        </div>
      `
      return
    }

    // Calculate grid dimensions
    const cols = Math.ceil(Math.sqrt(this.targets.length))
    const rows = Math.ceil(this.targets.length / cols)

    const width = cols * (HEX_WIDTH + HEX_SPACING) + HEX_SIZE
    const height = rows * (HEX_HEIGHT * 0.75 + HEX_SPACING) + HEX_HEIGHT * 0.5

    // Create SVG
    this.svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    this.svg.setAttribute("viewBox", `0 0 ${width} ${height}`)
    this.svg.setAttribute("class", "w-full h-auto max-h-[200px]")

    // Create hexagons
    this.targets.forEach((target, index) => {
      const col = index % cols
      const row = Math.floor(index / cols)

      // Offset every other row
      const offsetX = (row % 2) * (HEX_WIDTH * 0.5 + HEX_SPACING * 0.5)

      const x = col * (HEX_WIDTH + HEX_SPACING) + HEX_SIZE + offsetX
      const y = row * (HEX_HEIGHT * 0.75 + HEX_SPACING) + HEX_HEIGHT * 0.5

      const group = this._createHexagon(x, y, target)
      this.svg.appendChild(group)
      this.hexagons.set(target.identifier, group)
    })

    this.container.appendChild(this.svg)
  }

  _createHexagon(cx, cy, target) {
    const group = document.createElementNS("http://www.w3.org/2000/svg", "g")
    group.setAttribute("data-target", target.identifier)
    group.setAttribute("class", "cursor-pointer transition-transform hover:scale-110")

    // Hexagon path
    const points = this._hexPoints(cx, cy, HEX_SIZE)
    const polygon = document.createElementNS("http://www.w3.org/2000/svg", "polygon")
    polygon.setAttribute("points", points.map(p => `${p.x},${p.y}`).join(" "))
    polygon.setAttribute("fill", TokyoNightColors.surface)
    polygon.setAttribute("stroke", TokyoNightColors.border)
    polygon.setAttribute("stroke-width", "2")
    polygon.setAttribute("class", "hex-bg")

    // Status indicator (inner circle)
    const indicator = document.createElementNS("http://www.w3.org/2000/svg", "circle")
    indicator.setAttribute("cx", cx)
    indicator.setAttribute("cy", cy - 5)
    indicator.setAttribute("r", "8")
    indicator.setAttribute("fill", TokyoNightColors.textMuted)
    indicator.setAttribute("class", "hex-status")

    // Target label
    const label = document.createElementNS("http://www.w3.org/2000/svg", "text")
    label.setAttribute("x", cx)
    label.setAttribute("y", cy + 12)
    label.setAttribute("text-anchor", "middle")
    label.setAttribute("font-size", "8")
    label.setAttribute("fill", TokyoNightColors.textSecondary)
    label.setAttribute("class", "hex-label")
    label.textContent = this._shortenName(target.identifier)

    group.appendChild(polygon)
    group.appendChild(indicator)
    group.appendChild(label)

    // Click handler
    group.addEventListener("click", () => {
      this._onTargetClick(target)
    })

    return group
  }

  _hexPoints(cx, cy, size) {
    const points = []
    for (let i = 0; i < 6; i++) {
      const angle = (Math.PI / 3) * i - Math.PI / 6  // Start from flat top
      points.push({
        x: cx + size * Math.cos(angle),
        y: cy + size * Math.sin(angle)
      })
    }
    return points
  }

  _shortenName(name) {
    // Shorten long names to fit in hexagon
    if (name.length <= 6) return name
    return name.substring(0, 5) + "…"
  }

  _subscribeToHealth() {
    const store = getStore()

    for (const target of this.targets) {
      // Subscribe to health status telemetry
      // Assuming there's a STATUS item in HEALTH packet
      const key = `${target.identifier}:HEALTH:STATUS`

      const unsub = store.subscribe(key, (value, timestamp, limitsState) => {
        this._updateTargetHealth(target.identifier, limitsState)
      })

      this.subscriptions.push(unsub)

      // Also check for any red/yellow limits on key items
      const healthItems = [
        `${target.identifier}:HEALTH:CPU_TEMP`,
        `${target.identifier}:HEALTH:BATTERY_V`,
        `${target.identifier}:POWER:SOLAR_CURRENT`
      ]

      for (const itemKey of healthItems) {
        const itemUnsub = store.subscribe(itemKey, (value, timestamp, limitsState) => {
          // Update if any item is in warning/critical state
          if (limitsState && limitsState !== "green") {
            this._updateTargetHealth(target.identifier, limitsState)
          }
        })
        this.subscriptions.push(itemUnsub)
      }
    }
  }

  _updateTargetHealth(targetId, limitsState) {
    const group = this.hexagons.get(targetId)
    if (!group) return

    const indicator = group.querySelector(".hex-status")
    const polygon = group.querySelector(".hex-bg")

    if (!indicator || !polygon) return

    const color = getLimitsColor(limitsState)

    // Update indicator color
    indicator.setAttribute("fill", color)

    // Add glow effect for warnings/errors
    if (limitsState === "red" || limitsState === "red_high" || limitsState === "red_low") {
      polygon.setAttribute("stroke", color)
      polygon.setAttribute("stroke-width", "3")
      indicator.setAttribute("r", "10")
    } else if (limitsState === "yellow" || limitsState === "yellow_high" || limitsState === "yellow_low") {
      polygon.setAttribute("stroke", color)
      polygon.setAttribute("stroke-width", "2.5")
      indicator.setAttribute("r", "9")
    } else {
      polygon.setAttribute("stroke", TokyoNightColors.border)
      polygon.setAttribute("stroke-width", "2")
      indicator.setAttribute("r", "8")
    }
  }

  _onTargetClick(target) {
    // Dispatch custom event for parent to handle
    const event = new CustomEvent("honeycomb:target-selected", {
      detail: { target },
      bubbles: true
    })
    this.container.dispatchEvent(event)
  }

  /**
   * Manually set a target's health status (for testing).
   */
  setTargetHealth(targetId, limitsState) {
    this._updateTargetHealth(targetId, limitsState)
  }

  /**
   * Update the target list and re-render.
   */
  updateTargets(targets) {
    // Unsubscribe from old targets
    for (const unsub of this.subscriptions) {
      unsub()
    }
    this.subscriptions = []

    // Update and re-render
    this.targets = targets
    this._render()
    this._subscribeToHealth()
  }

  /**
   * Destroy the honeycomb and clean up.
   */
  destroy() {
    for (const unsub of this.subscriptions) {
      unsub()
    }
    this.subscriptions = []
    this.hexagons.clear()
    this.container.innerHTML = ""
  }
}

/**
 * Create a fleet honeycomb instance.
 *
 * @param {HTMLElement} container - The container element
 * @param {Array} targets - Array of target objects {id, identifier, name}
 * @param {Object} options - Options
 * @returns {FleetHoneycomb}
 */
export function createFleetHoneycomb(container, targets, options = {}) {
  return new FleetHoneycomb(container, targets, options)
}

export default {
  FleetHoneycomb,
  createFleetHoneycomb
}
