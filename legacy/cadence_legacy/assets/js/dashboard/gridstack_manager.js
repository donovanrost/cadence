/**
 * GridStack Manager
 *
 * Manages the widget grid dashboard inside the center panel.
 * Handles widget creation, positioning, and persistence.
 */

import { GridStack } from "gridstack"
import "gridstack/dist/gridstack.min.css"
import "gridstack/dist/gridstack-extra.min.css"

import { WidgetFactory } from "./widget_factory"

/**
 * Default grid options.
 */
const DEFAULT_OPTIONS = {
  column: 12,
  cellHeight: 80,
  margin: 8,
  float: true,
  removable: true,
  acceptWidgets: true,
  animate: true,
  styleInHead: true,  // Ensure dynamic styles go in <head> to survive LiveView patches
  resizable: {
    handles: "e, se, s, sw, w"
  }
}

/**
 * GridStackManager - Manages the widget dashboard grid.
 */
export class GridStackManager {
  constructor(container, options = {}) {
    this.container = container
    this.options = { ...DEFAULT_OPTIONS, ...options }
    this.grid = null
    this.widgets = new Map()  // id -> widget instance
    this.locked = false
    this.eventHandlers = new Map()
    this.selectedWidgets = new Set()  // Track selected widget IDs
    this.selectionMode = false  // Whether multi-select mode is active
  }

  /**
   * Initialize the grid.
   *
   * @returns {GridStackManager}
   */
  init() {
    this.grid = GridStack.init(this.options, this.container)

    // Explicitly enable float mode after init (required in GridStack 10.x)
    // This allows widgets to be positioned anywhere on the grid without
    // automatically floating to the top
    if (this.options.float) {
      this.grid.float(true)
    }

    this._setupEventHandlers()

    return this
  }

  /**
   * Add a widget to the grid.
   *
   * @param {Object} config - Widget configuration
   * @returns {Object} The created widget
   */
  addWidget(config) {
    console.log("[GridStackManager] Adding widget:", config)

    const id = config.id || `widget-${Date.now()}`
    const type = config.type || "value_display"
    const position = config.position || { x: 0, y: 0, w: 4, h: 2 }

    try {
      // Add widget to grid using GridStack's API
      const gridItem = this.grid.addWidget({
        x: position.x,
        y: position.y,
        w: position.w,
        h: position.h,
        id,
        content: `<div class="cadence-widget" data-widget-id="${id}" data-widget-type="${type}"></div>`
      })

      if (!gridItem) {
        console.error("[GridStackManager] addWidget returned null/undefined!")
        return null
      }

      // Get the content container that GridStack created
      const element = gridItem
      element.dataset.widgetId = id
      element.dataset.widgetType = type
      const content = element.querySelector(".cadence-widget")

      // Create widget instance
      const widget = WidgetFactory.create(type, {
        id,
        container: content,
        config: config.config || {},
        manager: this
      })

      this.widgets.set(id, widget)

      // Initialize the widget (handle async init for chart widgets)
      const initResult = widget.init()
      if (initResult instanceof Promise) {
        initResult.catch(err => {
          console.error(`[GridStackManager] Widget ${id} async init failed:`, err)
        })
      }

      this.emit("widgetAdded", { id, type, widget })

      return widget

    } catch (err) {
      console.error("[GridStackManager] Failed to add widget:", err)
      throw err
    }
  }

  /**
   * Remove a widget from the grid.
   *
   * @param {string} id - Widget ID
   */
  removeWidget(id) {
    const widget = this.widgets.get(id)
    if (!widget) return

    // Destroy widget
    widget.destroy()

    // Remove from grid
    const element = this.container.querySelector(`[data-widget-id="${id}"]`)
    if (element) {
      this.grid.removeWidget(element, true)
    }

    this.widgets.delete(id)

    this.emit("widgetRemoved", { id })
  }

  /**
   * Update a widget's configuration.
   *
   * @param {string} id - Widget ID
   * @param {Object} config - New configuration
   */
  updateWidget(id, config) {
    const widget = this.widgets.get(id)
    if (!widget) return

    widget.updateConfig(config)

    this.emit("widgetUpdated", { id, config })
  }

  /**
   * Load widgets from a saved configuration.
   *
   * @param {Array} widgetConfigs - Array of widget configurations
   */
  loadWidgets(widgetConfigs) {
    // Clear existing widgets
    this.clear()

    // Use batchUpdate to prevent auto-compacting while adding widgets
    // This preserves the saved Y positions when float mode is enabled
    this.grid.batchUpdate()

    // Add saved widgets
    for (const config of widgetConfigs) {
      this.addWidget(config)
    }

    this.grid.batchUpdate(false)

    // Force style update after batch load (GridStack 10.x requires this
    // to apply inline top/left positioning based on gs-x/gs-y attributes)
    this.grid._updateStyles()
  }

  /**
   * Get the current widget configurations for saving.
   *
   * @returns {Array} Array of widget configurations
   */
  saveWidgets() {
    const configs = []

    for (const [id, widget] of this.widgets) {
      const element = this.container.querySelector(`[data-widget-id="${id}"]`)
      const node = element?.gridstackNode

      configs.push({
        id,
        type: widget.type,
        position: node ? {
          x: node.x,
          y: node.y,
          w: node.w,
          h: node.h
        } : { x: 0, y: 0, w: 4, h: 2 },
        config: widget.getConfig()
      })
    }

    return configs
  }

  /**
   * Clear all widgets.
   */
  clear() {
    for (const [id, widget] of this.widgets) {
      widget.destroy()
    }
    this.widgets.clear()
    this.grid.removeAll(true)
  }

  /**
   * Lock or unlock the grid for editing.
   *
   * @param {boolean} locked - Whether to lock
   */
  setLocked(locked) {
    this.locked = locked

    if (locked) {
      this.grid.disable()
    } else {
      this.grid.enable()
    }

    this.emit("lockChanged", { locked })
  }

  /**
   * Toggle grid lock state.
   *
   * @returns {boolean} New lock state
   */
  toggleLocked() {
    this.setLocked(!this.locked)
    return this.locked
  }

  // Selection methods for bulk operations

  /**
   * Toggle selection mode.
   *
   * @param {boolean} enabled - Whether to enable selection mode
   */
  setSelectionMode(enabled) {
    this.selectionMode = enabled

    if (!enabled) {
      this.clearSelection()
    }

    // Add/remove visual class on container
    this.container.classList.toggle("selection-mode", enabled)

    this.emit("selectionModeChanged", { enabled })
  }

  /**
   * Toggle selection mode.
   *
   * @returns {boolean} New selection mode state
   */
  toggleSelectionMode() {
    this.setSelectionMode(!this.selectionMode)
    return this.selectionMode
  }

  /**
   * Toggle widget selection.
   *
   * @param {string} id - Widget ID
   * @returns {boolean} Whether widget is now selected
   */
  toggleWidgetSelection(id) {
    if (!this.widgets.has(id)) return false

    const isSelected = this.selectedWidgets.has(id)

    if (isSelected) {
      this.selectedWidgets.delete(id)
    } else {
      this.selectedWidgets.add(id)
    }

    // Update visual state
    this._updateWidgetSelectionVisual(id, !isSelected)

    this.emit("selectionChanged", {
      selected: Array.from(this.selectedWidgets),
      count: this.selectedWidgets.size
    })

    return !isSelected
  }

  /**
   * Select a widget.
   *
   * @param {string} id - Widget ID
   */
  selectWidget(id) {
    if (!this.widgets.has(id)) return

    this.selectedWidgets.add(id)
    this._updateWidgetSelectionVisual(id, true)

    this.emit("selectionChanged", {
      selected: Array.from(this.selectedWidgets),
      count: this.selectedWidgets.size
    })
  }

  /**
   * Deselect a widget.
   *
   * @param {string} id - Widget ID
   */
  deselectWidget(id) {
    this.selectedWidgets.delete(id)
    this._updateWidgetSelectionVisual(id, false)

    this.emit("selectionChanged", {
      selected: Array.from(this.selectedWidgets),
      count: this.selectedWidgets.size
    })
  }

  /**
   * Select all widgets.
   */
  selectAll() {
    for (const id of this.widgets.keys()) {
      this.selectedWidgets.add(id)
      this._updateWidgetSelectionVisual(id, true)
    }

    this.emit("selectionChanged", {
      selected: Array.from(this.selectedWidgets),
      count: this.selectedWidgets.size
    })
  }

  /**
   * Clear all selections.
   */
  clearSelection() {
    for (const id of this.selectedWidgets) {
      this._updateWidgetSelectionVisual(id, false)
    }
    this.selectedWidgets.clear()

    this.emit("selectionChanged", {
      selected: [],
      count: 0
    })
  }

  /**
   * Get selected widget IDs.
   *
   * @returns {string[]}
   */
  getSelectedWidgets() {
    return Array.from(this.selectedWidgets)
  }

  /**
   * Delete all selected widgets.
   */
  deleteSelected() {
    const toDelete = Array.from(this.selectedWidgets)

    for (const id of toDelete) {
      this.removeWidget(id)
    }

    this.selectedWidgets.clear()

    this.emit("selectionChanged", {
      selected: [],
      count: 0
    })

    return toDelete
  }

  /**
   * Update visual selection state for a widget.
   *
   * @param {string} id - Widget ID
   * @param {boolean} selected - Whether selected
   */
  _updateWidgetSelectionVisual(id, selected) {
    const element = this.container.querySelector(`[data-widget-id="${id}"]`)
    if (element) {
      element.classList.toggle("widget-selected", selected)
    }
  }

  /**
   * Get widget count.
   *
   * @returns {number}
   */
  getWidgetCount() {
    return this.widgets.size
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
        console.error(`[GridStackManager] Error in ${event} handler:`, err)
      }
    })
  }

  /**
   * Destroy the grid and clean up.
   */
  destroy() {
    this.clear()

    if (this.grid) {
      this.grid.destroy(false)
      this.grid = null
    }

    this.eventHandlers.clear()
  }

  // Private methods

  _setupEventHandlers() {
    // Widget moved or resized
    this.grid.on("change", (event, items) => {
      this.emit("change", { items: this.saveWidgets() })
    })

    // Widget dropped from outside
    this.grid.on("dropped", (event, previousNode, newNode) => {
      this.emit("dropped", { previousNode, newNode })
    })

    // Widget removed via drag
    this.grid.on("removed", (event, items) => {
      for (const item of items) {
        const id = item.el?.dataset?.widgetId
        if (id && this.widgets.has(id)) {
          const widget = this.widgets.get(id)
          widget.destroy()
          this.widgets.delete(id)
          this.emit("widgetRemoved", { id })
        }
      }
    })

    // Handle clicks on widgets for selection mode
    this.container.addEventListener("click", (e) => {
      if (!this.selectionMode) return

      // Find the widget element that was clicked
      const widgetEl = e.target.closest("[data-widget-id]")
      if (!widgetEl) return

      const id = widgetEl.dataset.widgetId
      if (id) {
        e.preventDefault()
        e.stopPropagation()
        this.toggleWidgetSelection(id)
      }
    })
  }
}

/**
 * Create a GridStack manager instance.
 *
 * @param {HTMLElement} container - The container element
 * @param {Object} options - Options
 * @returns {GridStackManager}
 */
export function createGridManager(container, options = {}) {
  return new GridStackManager(container, options)
}

export default {
  GridStackManager,
  createGridManager
}
