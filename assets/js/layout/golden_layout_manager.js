/**
 * Golden Layout Manager
 *
 * Manages the docking panel layout for the Ops Console.
 * Provides a VS Code-style layout with collapsible side panels.
 */

import { GoldenLayout, LayoutConfig, ComponentContainer, ContentItem } from "golden-layout"

/**
 * Default layout configuration for the Ops Console.
 * Three-panel layout: navigation (left), dashboard (center), context (right).
 * Headers are hidden for a cleaner look - panels are not tabbed.
 */

// Panel size constants
// Full minimum widths (expanded state)
const NAV_PANEL_MIN_WIDTH = 180
const CONTEXT_PANEL_MIN_WIDTH = 180
const DASHBOARD_MIN_WIDTH = 400

// Compact widths (collapsed state - icon/badge only)
const NAV_PANEL_COMPACT_WIDTH = 48
const CONTEXT_PANEL_COMPACT_WIDTH = 64

// Threshold for triggering snap (dead zone boundaries)
// If panel is between compact and full, snap to one or the other
const SNAP_THRESHOLD_BUFFER = 20

/**
 * Snap point configuration for each panel.
 * Panels will snap between compact and full widths to avoid
 * awkward in-between states.
 */
export const PANEL_SNAP_POINTS = {
  navigation: {
    compact: NAV_PANEL_COMPACT_WIDTH,
    full: NAV_PANEL_MIN_WIDTH
  },
  context: {
    compact: CONTEXT_PANEL_COMPACT_WIDTH,
    full: CONTEXT_PANEL_MIN_WIDTH
  }
  // dashboard doesn't snap - it's the flexible center panel
}

export const DEFAULT_LAYOUT_CONFIG = {
  settings: {
    showPopoutIcon: false,
    showMaximiseIcon: false,
    showCloseIcon: false
  },
  dimensions: {
    defaultMinItemWidth: 100
  },
  header: {
    show: "top",
    popout: false,
    maximise: false,
    close: false,
    minimise: false
  },
  root: {
    type: "row",
    content: [
      {
        type: "component",
        componentType: "navigation",
        title: "Navigation",
        isClosable: false,
        header: { show: false },
        minWidth: NAV_PANEL_COMPACT_WIDTH,  // Allow collapse to compact
        componentState: {}
      },
      {
        type: "component",
        componentType: "dashboard",
        title: "Dashboard",
        isClosable: false,
        header: { show: false },
        minWidth: DASHBOARD_MIN_WIDTH,
        componentState: {}
      },
      {
        type: "component",
        componentType: "context",
        title: "Context",
        isClosable: false,
        header: { show: false },
        minWidth: CONTEXT_PANEL_COMPACT_WIDTH,  // Allow collapse to compact
        componentState: {}
      }
    ]
  }
}

/**
 * Panel component registry
 */
const panelRegistry = new Map()

/**
 * Register a panel component.
 *
 * @param {string} name - The component type name
 * @param {Function} factory - Factory function that creates the panel content
 */
export function registerPanel(name, factory) {
  panelRegistry.set(name, factory)
}

/**
 * Convert a ResolvedLayoutConfig (from saveLayout) back to a LayoutConfig (for loadLayout).
 * Golden Layout 2 saveLayout() returns a "resolved" config with extra fields that
 * loadLayout() cannot handle directly.
 */
function convertResolvedToLayoutConfig(config) {
  if (!config) return null

  // If it's not a resolved config, return as-is (but still sanitize)
  if (!config.resolved && !config.settings) {
    return config
  }

  // Build a clean LayoutConfig from the resolved config
  function convertItem(item) {
    if (!item) return null

    const converted = {
      type: item.type
    }

    // Copy relevant fields based on type
    if (item.type === 'component') {
      converted.componentType = item.componentType
      converted.componentState = item.componentState || {}
      if (item.title) converted.title = item.title
      if (item.id) converted.id = item.id
      if (typeof item.isClosable === 'boolean') converted.isClosable = item.isClosable
    }

    // Handle size - convert back to string format
    if (item.size !== undefined && item.sizeUnit) {
      converted.size = `${item.size}${item.sizeUnit}`
    } else if (typeof item.size === 'string') {
      converted.size = item.size
    }

    // Recursively convert content
    if (Array.isArray(item.content) && item.content.length > 0) {
      // For stacks, we want to get the inner components
      if (item.type === 'stack' && item.content.length === 1 && item.content[0].type === 'component') {
        // Unwrap single-component stacks back to components
        return convertItem(item.content[0])
      }
      converted.content = item.content.map(convertItem).filter(Boolean)
    }

    return converted
  }

  // Convert root
  const layoutConfig = {
    root: convertItem(config.root)
  }

  return layoutConfig
}

/**
 * GoldenLayoutManager - Manages the layout lifecycle and state.
 */
export class GoldenLayoutManager {
  constructor(container, options = {}) {
    this.container = container
    this.options = options
    this.layout = null
    this.panels = new Map()
    this.eventHandlers = new Map()
    this._isSnapping = false  // Prevent recursive snapping
    this._snapDebounceTimer = null
  }

  /**
   * Initialize the layout with a configuration.
   *
   * @param {Object} config - Layout configuration (or null for default)
   * @returns {Promise}
   */
  async init(config = null) {
    const layoutConfig = convertResolvedToLayoutConfig(config) || DEFAULT_LAYOUT_CONFIG

    console.log("[GoldenLayout] Initializing with config:", JSON.stringify(layoutConfig, null, 2))

    // Wait for container to have valid dimensions
    await this._waitForContainerSize()

    // Create Golden Layout instance
    this.layout = new GoldenLayout(this.container)

    // Enable automatic resizing when container size changes
    this.layout.resizeWithContainerAutomatically = true
    this.layout.resizeDebounceInterval = 50

    // Register component factories
    for (const [name, factory] of panelRegistry) {
      this.layout.registerComponentFactoryFunction(name, (container, state) => {
        const panel = factory(container, state, this)
        this.panels.set(name, panel)
        return panel
      })
    }

    // Load the layout configuration
    this.layout.loadLayout(layoutConfig)

    // Set up event handlers
    this._setupEventHandlers()

    return this
  }

  /**
   * Get the current layout state for persistence.
   *
   * @returns {Object} The serialized layout configuration
   */
  saveLayout() {
    if (!this.layout) return null
    return this.layout.saveLayout()
  }

  /**
   * Restore a saved layout.
   *
   * @param {Object} config - The saved layout configuration
   */
  loadLayout(config) {
    if (!this.layout) return
    this.layout.loadLayout(config)
  }

  /**
   * Get a panel by name.
   *
   * @param {string} name - The panel component type
   * @returns {Object|undefined}
   */
  getPanel(name) {
    return this.panels.get(name)
  }

  /**
   * Add an event handler.
   *
   * @param {string} event - Event name
   * @param {Function} handler - Event handler
   */
  on(event, handler) {
    if (!this.eventHandlers.has(event)) {
      this.eventHandlers.set(event, new Set())
    }
    this.eventHandlers.get(event).add(handler)
  }

  /**
   * Remove an event handler.
   *
   * @param {string} event - Event name
   * @param {Function} handler - Event handler
   */
  off(event, handler) {
    this.eventHandlers.get(event)?.delete(handler)
  }

  /**
   * Emit an event.
   *
   * @param {string} event - Event name
   * @param {any} data - Event data
   */
  emit(event, data) {
    this.eventHandlers.get(event)?.forEach(handler => {
      try {
        handler(data)
      } catch (err) {
        console.error(`[GoldenLayoutManager] Error in ${event} handler:`, err)
      }
    })
  }

  /**
   * Destroy the layout and clean up.
   */
  destroy() {
    // Clean up panels
    for (const panel of this.panels.values()) {
      if (typeof panel.destroy === "function") {
        panel.destroy()
      }
    }
    this.panels.clear()

    // Destroy Golden Layout
    if (this.layout) {
      this.layout.destroy()
      this.layout = null
    }

    // Clear event handlers
    this.eventHandlers.clear()
  }

  /**
   * Resize the layout (call when container size changes).
   */
  resize() {
    if (!this.layout) return

    try {
      // Check if container has valid dimensions
      const rect = this.container.getBoundingClientRect()
      if (rect.width > 0 && rect.height > 0) {
        this.layout.setSize(rect.width, rect.height)
      }
    } catch (err) {
      console.warn("[GoldenLayoutManager] Resize failed:", err)
    }
  }

  // Private methods

  /**
   * Wait for the container to have valid dimensions.
   * Returns immediately if already sized, otherwise waits up to 1 second.
   */
  async _waitForContainerSize() {
    const maxWait = 1000
    const checkInterval = 50
    let waited = 0

    while (waited < maxWait) {
      const rect = this.container.getBoundingClientRect()
      if (rect.width > 0 && rect.height > 0) {
        console.log(`[GoldenLayout] Container ready: ${rect.width}x${rect.height}`)
        return
      }
      await new Promise(resolve => setTimeout(resolve, checkInterval))
      waited += checkInterval
    }

    console.warn("[GoldenLayout] Container size timeout, proceeding anyway")
  }

  _setupEventHandlers() {
    // Layout state changed - check for snap after resize
    this.layout.on("stateChanged", () => {
      this._checkAndSnap()
      this.emit("stateChanged", this.saveLayout())
    })

    // Item created
    this.layout.on("itemCreated", (item) => {
      this.emit("itemCreated", item)
    })

    // Focus changed
    this.layout.on("focus", (item) => {
      this.emit("focus", item)
    })
  }

  /**
   * Check panel widths and snap if in the dead zone between compact and full.
   * Uses debouncing to avoid excessive calculations during drag.
   */
  _checkAndSnap() {
    // Don't snap if we're already snapping (prevents recursion)
    if (this._isSnapping) return

    // Debounce to wait for drag to finish
    if (this._snapDebounceTimer) {
      clearTimeout(this._snapDebounceTimer)
    }

    this._snapDebounceTimer = setTimeout(() => {
      this._performSnap()
    }, 150)  // Wait 150ms after last state change
  }

  /**
   * Actually perform the snap calculation and adjustment.
   */
  _performSnap() {
    if (!this.layout || this._isSnapping) return

    const rootItem = this.layout.rootItem
    if (!rootItem || rootItem.type !== "row") return

    // Get the content items (panels) in the row
    const contentItems = rootItem.contentItems
    if (!contentItems || contentItems.length < 3) return

    let needsSnap = false
    const snapAdjustments = []

    // Check each panel that has snap points
    for (const item of contentItems) {
      // Get the component type - handle both direct components and stacks
      let componentType = null
      if (item.type === "component") {
        componentType = item.componentType
      } else if (item.type === "stack" && item.contentItems.length > 0) {
        const innerItem = item.contentItems[0]
        if (innerItem.type === "component") {
          componentType = innerItem.componentType
        }
      }

      if (!componentType) continue

      const snapPoints = PANEL_SNAP_POINTS[componentType]
      if (!snapPoints) continue  // No snap points for this panel (e.g., dashboard)

      // Get current width
      const element = item.element
      if (!element) continue

      const currentWidth = element.offsetWidth
      const { compact, full } = snapPoints

      // Define the dead zone: between compact+buffer and full-buffer
      const deadZoneMin = compact + SNAP_THRESHOLD_BUFFER
      const deadZoneMax = full - SNAP_THRESHOLD_BUFFER

      // If we're in the dead zone, snap to nearest
      if (currentWidth > deadZoneMin && currentWidth < deadZoneMax) {
        needsSnap = true
        // Snap to whichever is closer
        const distToCompact = currentWidth - compact
        const distToFull = full - currentWidth
        const targetWidth = distToCompact < distToFull ? compact : full

        snapAdjustments.push({
          item,
          currentWidth,
          targetWidth,
          componentType
        })
      }
    }

    // Apply snap adjustments if needed
    if (needsSnap && snapAdjustments.length > 0) {
      this._isSnapping = true

      try {
        for (const { item, targetWidth, componentType } of snapAdjustments) {
          console.log(`[GoldenLayout] Snapping ${componentType} to ${targetWidth}px`)

          // Calculate the percentage/pixel size to set
          // Golden Layout uses setSize with pixel values
          const containerWidth = this.container.offsetWidth
          if (containerWidth > 0) {
            // Use Golden Layout's internal method to resize
            // We need to set the size property and trigger a layout update
            item.setSize(targetWidth)
          }
        }
      } finally {
        // Small delay before allowing snap checks again
        setTimeout(() => {
          this._isSnapping = false
        }, 200)
      }
    }
  }
}

/**
 * Create a Golden Layout manager instance.
 *
 * @param {HTMLElement} container - The container element
 * @param {Object} options - Options
 * @returns {GoldenLayoutManager}
 */
export function createLayoutManager(container, options = {}) {
  return new GoldenLayoutManager(container, options)
}

export default {
  GoldenLayoutManager,
  createLayoutManager,
  registerPanel,
  DEFAULT_LAYOUT_CONFIG,
  PANEL_SNAP_POINTS
}
