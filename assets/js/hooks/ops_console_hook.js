/**
 * Ops Console LiveView Hook
 *
 * Manages the Ops Console UI including:
 * - Golden Layout initialization
 * - GridStack dashboard
 * - Telemetry channel connection
 * - Layout persistence
 */

import { createLayoutManager, DEFAULT_LAYOUT_CONFIG } from "../layout/golden_layout_manager"
import { registerPanels } from "../layout/panel_registry"
import { createGridManager } from "../dashboard/gridstack_manager"
import { TelemetryStore, getStore } from "../telemetry_store"

// Import widgets to register them
import "../widgets/index"

/**
 * OpsConsole LiveView Hook
 */
export const OpsConsoleHook = {
  mounted() {
    console.log("[OpsConsole] Mounting...", this.el.id)

    // Get configuration from data attributes
    this.missionId = this.el.dataset.missionId
    this.frameLayout = JSON.parse(this.el.dataset.layout || "null")
    this.widgets = JSON.parse(this.el.dataset.widgets || "[]")
    this.targets = JSON.parse(this.el.dataset.targets || "[]")
    this.dashboards = JSON.parse(this.el.dataset.dashboards || "[]")
    this.alarms = JSON.parse(this.el.dataset.alarms || "[]")
    this.currentDashboardId = this.el.dataset.currentDashboardId
    this.token = this.el.dataset.token

    // Track managers
    this.layoutManager = null
    this.gridManager = null
    this.telemetryStore = null
    this._windowResizeHandler = null
    this._initialized = false

    // Register LiveView event handlers immediately
    this._setupEventHandlers()

    // Wait for next frame to ensure container has proper dimensions
    requestAnimationFrame(() => {
      this._init()
    })
  },

  async _init() {
    // Prevent re-initialization
    if (this._initialized) {
      console.log("[OpsConsole] Already initialized, skipping")
      return
    }

    try {
      // 1. Register panel components
      registerPanels()

      // 2. Determine layout config to use
      // If frameLayout is null/undefined/empty, use default
      let layoutConfig = DEFAULT_LAYOUT_CONFIG
      if (this.frameLayout && this.frameLayout.root) {
        layoutConfig = this.frameLayout
      }
      console.log("[OpsConsole] Using layout config:", layoutConfig)

      // 3. Initialize Golden Layout on the inner container (which has phx-update="ignore")
      const layoutContainer = this.el.querySelector("#ops-console")
      this.layoutManager = createLayoutManager(layoutContainer, {})
      await this.layoutManager.init(layoutConfig)

      // 3. Set up layout event handlers
      this._setupLayoutEvents()

      // 4. Initialize GridStack in the dashboard panel
      const dashboardPanel = this.layoutManager.getPanel("dashboard")
      if (dashboardPanel) {
        const gridContainer = dashboardPanel.getGridContainer()
        this.gridManager = createGridManager(gridContainer)
        this.gridManager.init()

        // Load saved widgets
        if (this.widgets.length > 0) {
          this.gridManager.loadWidgets(this.widgets)
        }

        // Set up grid event handlers
        this._setupGridEvents()

        // Update widget count display
        dashboardPanel.setWidgetCount(this.gridManager.getWidgetCount())
      }

      // 5. Initialize navigation panel
      const navPanel = this.layoutManager.getPanel("navigation")
      if (navPanel) {
        // Set mission name from LiveView assign
        const missionName = this.el.dataset.missionName || "Mission"
        navPanel.setMissionName(missionName)

        // Set dashboards list
        navPanel.setDashboards(this.dashboards, this.currentDashboardId)
      }

      // 5b. Initialize context panel with alarms
      const contextPanel = this.layoutManager.getPanel("context")
      if (contextPanel) {
        contextPanel.setAlarms(this.alarms, this)
      }

      // 6. Connect to telemetry channel
      await this._connectTelemetry()

      // 7. Set up resize handling
      this._setupResizeHandling()

      this._initialized = true
      console.log("[OpsConsole] Initialization complete")

    } catch (err) {
      console.error("[OpsConsole] Initialization failed:", err)
    }
  },

  _setupResizeHandling() {
    // Golden Layout handles its own resize via ResizeObserver
    // We just need to handle window resize for edge cases
    this._windowResizeHandler = () => {
      this._debounce("windowResize", () => {
        if (this.layoutManager) {
          this.layoutManager.resize()
        }
      }, 100)
    }
    window.addEventListener("resize", this._windowResizeHandler)
  },

  async _connectTelemetry() {
    if (!this.token || !this.missionId) {
      console.warn("[OpsConsole] Missing token or missionId, skipping telemetry connection")
      return
    }

    this.telemetryStore = getStore({ maxSamples: 5000 })

    // Subscribe to connection state changes
    this._connectionUnsubscribe = this.telemetryStore.onConnectionChange((connected) => {
      const navPanel = this.layoutManager?.getPanel("navigation")
      navPanel?.setConnectionStatus(connected)
    })

    // Collect all telemetry items from widgets
    const subscriptions = this._collectTelemetrySubscriptions()

    try {
      await this.telemetryStore.connect(this.token, this.missionId, subscriptions)
    } catch (err) {
      console.error("[OpsConsole] Failed to connect telemetry:", err)
    }
  },

  _collectTelemetrySubscriptions() {
    const subscriptions = []

    for (const widgetConfig of this.widgets) {
      // Line charts have multiple items
      if (widgetConfig.config?.telemetry_items) {
        for (const item of widgetConfig.config.telemetry_items) {
          subscriptions.push({
            target: item.target,
            packet: item.packet,
            item: item.item
          })
        }
      }

      // Value displays have single item
      if (widgetConfig.config?.telemetry_item) {
        const item = widgetConfig.config.telemetry_item
        subscriptions.push({
          target: item.target,
          packet: item.packet,
          item: item.item
        })
      }
    }

    return subscriptions
  },

  _setupLayoutEvents() {
    // Don't auto-save layout on every state change - it causes re-render issues
    // The layout will be saved when the user explicitly clicks "Save Layout"
    // this.layoutManager.on("stateChanged", (layout) => {
    //   this._debounce("saveLayout", () => {
    //     this.pushEvent("layout_changed", { frame_layout: layout })
    //   }, 1000)
    // })

    // Handle navigation actions
    this.layoutManager.on("navigation:action", (data) => {
      this._handleNavAction(data)
    })

    // Handle dashboard lock toggle
    this.layoutManager.on("dashboard:toggleLock", () => {
      if (this.gridManager) {
        const locked = this.gridManager.toggleLocked()
        const dashboardPanel = this.layoutManager.getPanel("dashboard")
        dashboardPanel?.setLocked(locked)
      }
    })

    // Handle selection mode events
    this.layoutManager.on("dashboard:toggleSelectionMode", () => {
      if (this.gridManager) {
        const enabled = this.gridManager.toggleSelectionMode()
        const dashboardPanel = this.layoutManager.getPanel("dashboard")
        dashboardPanel?.setSelectionMode(enabled)
      }
    })

    this.layoutManager.on("dashboard:selectAll", () => {
      if (this.gridManager) {
        this.gridManager.selectAll()
      }
    })

    this.layoutManager.on("dashboard:deleteSelected", () => {
      if (this.gridManager) {
        const deleted = this.gridManager.deleteSelected()
        if (deleted.length > 0) {
          // Emit change event to save
          this._debounce("saveWidgets", () => {
            this.pushEvent("widgets_changed", { widgets: this.gridManager.saveWidgets() })
          }, 500)
        }
      }
    })

    this.layoutManager.on("dashboard:cancelSelection", () => {
      if (this.gridManager) {
        this.gridManager.setSelectionMode(false)
        const dashboardPanel = this.layoutManager.getPanel("dashboard")
        dashboardPanel?.setSelectionMode(false)
      }
    })
  },

  _setupGridEvents() {
    // Handle widget changes
    this.gridManager.on("change", ({ items }) => {
      this._debounce("saveWidgets", () => {
        this.pushEvent("widgets_changed", { widgets: items })
      }, 1000)

      // Update count
      const dashboardPanel = this.layoutManager?.getPanel("dashboard")
      dashboardPanel?.setWidgetCount(this.gridManager.getWidgetCount())
    })

    // Handle selection changes
    this.gridManager.on("selectionChanged", ({ count }) => {
      const dashboardPanel = this.layoutManager?.getPanel("dashboard")
      dashboardPanel?.setSelectionCount(count)
    })

    // Handle widget removed
    this.gridManager.on("widgetRemoved", ({ id }) => {
      console.log("[OpsConsole] Widget removed:", id)
    })

    // Handle widget added
    this.gridManager.on("widgetAdded", ({ id, type }) => {
      console.log("[OpsConsole] Widget added:", id, type)

      // Subscribe to telemetry for new widget
      // (handled inside widget init)
    })
  },

  _handleNavAction(actionData) {
    // Handle both string actions and object actions with data
    const action = typeof actionData === "string" ? actionData : actionData.action

    switch (action) {
      case "add-widget":
        this.pushEvent("open_widget_palette", {})
        break

      case "save-layout":
        const layout = {
          frame_layout: this.layoutManager.saveLayout(),
          widgets: this.gridManager.saveWidgets()
        }
        this.pushEvent("save_layout", layout)
        break

      case "reset-layout":
        this.pushEvent("reset_layout", {})
        break

      // Dashboard actions
      case "create-dashboard":
        this.pushEvent("open_create_dashboard", {})
        break

      case "switch-dashboard":
        this.pushEvent("switch_dashboard", { id: actionData.dashboardId })
        break

      case "rename-dashboard":
        this.pushEvent("open_rename_dashboard", {
          id: actionData.dashboardId,
          name: actionData.currentName
        })
        break

      case "duplicate-dashboard":
        this.pushEvent("duplicate_dashboard", { id: actionData.dashboardId })
        break

      case "delete-dashboard":
        this.pushEvent("open_delete_confirm", {
          id: actionData.dashboardId,
          name: actionData.dashboardName
        })
        break

      default:
        console.log("[OpsConsole] Unknown nav action:", action, actionData)
    }
  },

  _setupEventHandlers() {
    // Register event handlers using LiveView's handleEvent method
    this.handleEvent("add_widget", (payload) => {
      // Defer widget addition to next frame to ensure DOM is stable after modal close
      requestAnimationFrame(() => {
        if (this.gridManager) {
          try {
            this.gridManager.addWidget(payload)
          } catch (err) {
            console.error("[OpsConsole] Failed to add widget:", err)
          }
        } else {
          console.error("[OpsConsole] GridManager not initialized!")
        }
      })
    })

    this.handleEvent("remove_widget", (payload) => {
      if (this.gridManager) {
        this.gridManager.removeWidget(payload.id)
      }
    })

    this.handleEvent("update_widget", (payload) => {
      if (this.gridManager) {
        this.gridManager.updateWidget(payload.id, payload.config)
      }
    })

    this.handleEvent("load_layout", (payload) => {
      // NOTE: We intentionally do NOT reload the Golden Layout frame_layout here
      // because doing so destroys and recreates all panels, which would invalidate
      // our gridManager reference. The frame layout (panel sizes/positions) is
      // typically the same across dashboards anyway.
      //
      // We only reload the widgets, which is the dashboard-specific content.
      if (payload.widgets && this.gridManager) {
        this.gridManager.loadWidgets(payload.widgets)
      }
    })

    // Dashboard management events
    this.handleEvent("update_dashboards", (payload) => {
      const navPanel = this.layoutManager?.getPanel("navigation")
      if (navPanel) {
        navPanel.setDashboards(payload.dashboards, payload.currentId)
      }
      // Update local state
      this.dashboards = payload.dashboards
      this.currentDashboardId = payload.currentId
    })

    // Alarm update events
    this.handleEvent("alarm_update", (payload) => {
      const contextPanel = this.layoutManager?.getPanel("context")
      if (contextPanel) {
        if (payload.type === "created") {
          this.alarms = [payload.alarm, ...this.alarms]
        } else if (payload.type === "updated") {
          const idx = this.alarms.findIndex(a => a.id === payload.alarm.id)
          if (idx >= 0) {
            // If alarm is no longer active, remove it
            if (payload.alarm.status === "cleared") {
              this.alarms.splice(idx, 1)
            } else {
              this.alarms[idx] = payload.alarm
            }
          } else if (payload.alarm.status !== "cleared") {
            this.alarms.unshift(payload.alarm)
          }
        } else if (payload.type === "cleared") {
          this.alarms = this.alarms.filter(a => a.id !== payload.alarm.id)
        }
        contextPanel.setAlarms(this.alarms, this)
      }
    })

    // Listen for widget configuration requests from widgets
    this.el.addEventListener("widget:configure", (e) => {
      const { widgetId, widgetType, config } = e.detail
      this.pushEvent("open_widget_config", {
        widget_id: widgetId,
        widget_type: widgetType,
        config: config
      })
    })
  },

  // Debounce helper
  _debounce(key, fn, delay) {
    if (!this._debounceTimers) {
      this._debounceTimers = {}
    }

    if (this._debounceTimers[key]) {
      clearTimeout(this._debounceTimers[key])
    }

    this._debounceTimers[key] = setTimeout(fn, delay)
  },

  // Handle LiveView updates
  updated() {
    // Golden Layout handles resize automatically
  },

  destroyed() {
    console.log("[OpsConsole] Destroying...")

    // Clean up window resize handler
    if (this._windowResizeHandler) {
      window.removeEventListener("resize", this._windowResizeHandler)
      this._windowResizeHandler = null
    }

    // Clean up debounce timers
    if (this._debounceTimers) {
      for (const timer of Object.values(this._debounceTimers)) {
        clearTimeout(timer)
      }
    }

    // Unsubscribe from connection state changes
    if (this._connectionUnsubscribe) {
      this._connectionUnsubscribe()
    }

    // Disconnect telemetry
    if (this.telemetryStore) {
      this.telemetryStore.disconnect()
    }

    // Destroy managers
    this.gridManager?.destroy()
    this.layoutManager?.destroy()
  }
}

export default OpsConsoleHook
