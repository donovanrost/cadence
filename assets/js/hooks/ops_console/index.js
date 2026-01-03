/**
 * Ops Console V2 LiveView Hook
 *
 * Next generation mission control interface featuring:
 * - Custom CSS-based panel layout with snap-to-close
 * - Global status bar integration
 * - Enhanced mission-control visual design
 * - Fullscreen widget capability
 * - New widget types (Command, Procedure, Alarm Summary, Fleet Health)
 *
 * Module structure:
 * - state.js: State initialization and management
 * - utils.js: Utility methods (debounce, etc.)
 * - index.js: Main hook with all methods (this file)
 */

import { createPanelLayout } from "../../layout/panel_layout"
import { createGridManager } from "../../dashboard/gridstack_manager"
import { TelemetryStore, getStore } from "../../telemetry_store"

// Import widgets to register them
import "../../widgets/index"

// Import state initialization
import { initializeState } from "./state"

/**
 * OpsConsole LiveView Hook
 */
export const OpsConsoleHook = {
  mounted() {
    console.log("[OpsConsole] Mounting...", this.el.id)

    // Initialize all state from data attributes
    initializeState(this)

    // Register LiveView event handlers immediately
    this._setupEventHandlers()

    // Wait for next frame to ensure container has proper dimensions
    requestAnimationFrame(() => {
      this._init()
    })

    // Start timeline live update timer (updates relative times every second)
    this._timelineUpdateInterval = setInterval(() => {
      this._updateTimelineLiveElements()
    }, 1000)
  },

  async _init() {
    // Prevent re-initialization
    if (this._initialized) {
      console.log("[OpsConsole] Already initialized, skipping")
      return
    }

    try {
      // 1. Initialize custom panel layout on the inner container
      const layoutContainer = this.el.querySelector("#ops-console")
      this.panelLayout = createPanelLayout(layoutContainer, {})
      this.panelLayout.init()

      // 2. Load saved panel state from localStorage (client-side preference)
      const storageKey = `ops-console-panels-${this.missionId}`
      try {
        const savedPanelState = localStorage.getItem(storageKey)
        if (savedPanelState) {
          this.panelLayout.loadState(JSON.parse(savedPanelState))
        }
      } catch (e) {
        console.warn("[OpsConsole] Failed to load panel state:", e)
      }

      // 3. Set up panel layout event handlers
      this._setupPanelLayoutEvents()

      // 4. Initialize GridStack in the dashboard panel
      const gridContainer = this.panelLayout.getGridContainer()
      if (gridContainer) {
        this.gridManager = createGridManager(gridContainer)
        this.gridManager.init()

        // Load saved widgets
        if (this.widgets.length > 0) {
          this.gridManager.loadWidgets(this.widgets)
        }

        // Set up grid event handlers
        this._setupGridEvents()

        // Update toolbar with widget count
        this._updateToolbar()
      }

      // 5. Populate navigation panel content
      this._populateNavPanel()

      // 6. Populate context panel with alarms
      this._populateContextPanel()

      // 7. Populate quick access bar
      this._populateQuickAccessBar()

      // 8. Connect to telemetry channel
      await this._connectTelemetry()

      // 9. Set up resize handling
      this._setupResizeHandling()

      // 10. Set up keyboard shortcuts
      this._setupKeyboardShortcuts()

      this._initialized = true
      console.log("[OpsConsole] Initialization complete")

    } catch (err) {
      console.error("[OpsConsole] Initialization failed:", err)
    }
  },

  _setupResizeHandling() {
    this._windowResizeHandler = () => {
      this._debounce("windowResize", () => {
        // GridStack handles its own resize - just trigger a refresh
        if (this.gridManager) {
          // GridStack auto-resizes, but we can force a layout update if needed
        }
      }, 100)
    }
    window.addEventListener("resize", this._windowResizeHandler)
  },

  _setupPanelLayoutEvents() {
    // Handle layout state changes - persist to localStorage (client-side only)
    this.panelLayout.on("layout:changed", (state) => {
      this._debounce("saveLayout", () => {
        const storageKey = `ops-console-panels-${this.missionId}`
        try {
          localStorage.setItem(storageKey, JSON.stringify(state))
        } catch (e) {
          console.warn("[OpsConsole] Failed to save panel state:", e)
        }
      }, 500)
    })

    // Handle panel open/close for analytics or logging
    this.panelLayout.on("panel:opened", ({ panel }) => {
      console.log("[OpsConsole] Panel opened:", panel)
    })

    this.panelLayout.on("panel:closed", ({ panel }) => {
      console.log("[OpsConsole] Panel closed:", panel)
    })
  },

  _updateToolbar() {
    const toolbar = this.panelLayout.getToolbarContainer()
    if (!toolbar) return

    const widgetCount = this.gridManager?.getWidgetCount() || 0

    toolbar.innerHTML = `
      <div class="flex items-center gap-3">
        <span class="mc-label-subsystem text-base-content/40">DASHBOARD</span>
        <span class="text-xs text-base-content/60">${widgetCount} widgets</span>
      </div>
      <div class="flex items-center gap-2">
        <button class="btn btn-ghost btn-xs" id="toolbar-add-widget" title="Add Widget">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
          </svg>
        </button>
        <button class="btn btn-ghost btn-xs" id="toolbar-toggle-lock" title="Toggle Lock">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 11V7a4 4 0 118 0m-4 8v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2z"/>
          </svg>
        </button>
        <button class="btn btn-ghost btn-xs" id="toolbar-save" title="Save Layout">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4"/>
          </svg>
        </button>
      </div>
    `

    // Bind toolbar actions
    toolbar.querySelector("#toolbar-add-widget")?.addEventListener("click", () => {
      this.pushEvent("open_widget_palette", {})
    })

    toolbar.querySelector("#toolbar-toggle-lock")?.addEventListener("click", () => {
      if (this.gridManager) {
        this.gridManager.toggleLocked()
        this._updateToolbar()
      }
    })

    toolbar.querySelector("#toolbar-save")?.addEventListener("click", () => {
      const layout = {
        panels: this.panelLayout.saveState(),
        widgets: this.gridManager?.saveWidgets() || []
      }
      this.pushEvent("save_layout", layout)
    })
  },

  _populateNavPanel() {
    const navContent = this.panelLayout.getPanelContent("navigation")
    if (!navContent) return

    const missionName = this.el.dataset.missionName || "Mission"

    navContent.innerHTML = `
      <div class="nav-panel-v2">
        <!-- Expanded content -->
        <div class="nav-expanded py-3">
          <!-- Mission header -->
          <div class="mb-4 px-3">
            <span class="mc-label-subsystem text-base-content/40 block mb-1">MISSION</span>
            <span class="font-semibold text-sm text-primary">${missionName}</span>
          </div>

          <!-- Mode selector -->
          <div class="mb-4">
            <span class="mc-label-subsystem text-base-content/40 block mb-2 px-3">MODE</span>
            <div class="flex flex-col">
              <button class="mode-btn active" data-mode="overview">
                <svg class="w-4 h-4 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zm10 0a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zm10 0a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z"/>
                </svg>
                <span class="nav-label">Overview</span>
              </button>
              <button class="mode-btn" data-mode="focus">
                <svg class="w-4 h-4 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2z"/>
                </svg>
                <span class="nav-label">Focus</span>
              </button>
              <button class="mode-btn" data-mode="procedure">
                <svg class="w-4 h-4 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4"/>
                </svg>
                <span class="nav-label">Procedure</span>
              </button>
              <button class="mode-btn" data-mode="commands">
                <svg class="w-4 h-4 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                </svg>
                <span class="nav-label">Commands</span>
              </button>
              <button class="mode-btn" data-mode="timeline">
                <svg class="w-4 h-4 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
                </svg>
                <span class="nav-label">Timeline</span>
              </button>
              <button class="mode-btn" data-mode="queue">
                <svg class="w-4 h-4 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"/>
                </svg>
                <span class="nav-label">Queue</span>
              </button>
              <button class="mode-btn" data-mode="alarms">
                <svg class="w-4 h-4 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"/>
                </svg>
                <span class="nav-label">Alarms</span>
              </button>
            </div>
          </div>

          <!-- Dashboards list -->
          <div class="mb-4">
            <div class="flex items-center justify-between mb-2 px-3">
              <span class="mc-label-subsystem text-base-content/40">DASHBOARDS</span>
              <button class="btn btn-ghost btn-xs" id="nav-create-dashboard" title="Create Dashboard">
                <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
                </svg>
              </button>
            </div>
            <div id="nav-dashboard-list" class="flex flex-col gap-1">
              ${this._renderDashboardList()}
            </div>
          </div>

          <!-- Actions -->
          <div class="mt-auto pt-4 border-t border-base-300 px-3">
            <button class="btn btn-ghost btn-xs w-full justify-start gap-2" id="nav-add-widget">
              <svg class="w-4 h-4 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
              </svg>
              <span class="nav-label">Add Widget</span>
            </button>
          </div>
        </div>

        <!-- Rail content (visible when collapsed) -->
        <div class="nav-rail">
          <!-- Mode icons -->
          <div class="rail-section">
            <button class="rail-btn active" data-mode="overview" title="Overview">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zm10 0a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zm10 0a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z"/>
              </svg>
            </button>
            <button class="rail-btn" data-mode="focus" title="Focus Mode">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2z"/>
              </svg>
            </button>
            <button class="rail-btn" data-mode="procedure" title="Procedure Mode">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4"/>
              </svg>
            </button>
            <button class="rail-btn" data-mode="commands" title="Commands Mode">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
              </svg>
            </button>
            <button class="rail-btn" data-mode="timeline" title="Timeline Mode">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
              </svg>
            </button>
            <button class="rail-btn" data-mode="queue" title="Queue Mode">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"/>
              </svg>
            </button>
            <button class="rail-btn" data-mode="alarms" title="Alarms Mode">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"/>
              </svg>
            </button>
          </div>

          <div class="rail-divider"></div>

          <!-- Quick actions -->
          <div class="rail-section">
            <button class="rail-btn" id="rail-add-widget" title="Add Widget">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
              </svg>
            </button>
            <button class="rail-btn" id="rail-dashboards" title="Dashboards">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V5zm0 8a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H5a1 1 0 01-1-1v-6zm12 0a1 1 0 011-1h2a1 1 0 011 1v6a1 1 0 01-1 1h-2a1 1 0 01-1-1v-6z"/>
              </svg>
            </button>
            <button class="rail-btn" id="rail-save" title="Save Layout">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4"/>
              </svg>
            </button>
          </div>
        </div>
      </div>
    `

    // Bind navigation actions (expanded view)
    navContent.querySelector("#nav-create-dashboard")?.addEventListener("click", () => {
      this.pushEvent("open_create_dashboard", {})
    })

    navContent.querySelector("#nav-add-widget")?.addEventListener("click", () => {
      this.pushEvent("open_widget_palette", {})
    })

    // Mode selector (expanded view)
    navContent.querySelectorAll(".nav-expanded .mode-btn").forEach(btn => {
      btn.addEventListener("click", () => {
        // Update both expanded and rail buttons
        navContent.querySelectorAll(".mode-btn, .rail-btn[data-mode]").forEach(b => b.classList.remove("active"))
        navContent.querySelectorAll(`[data-mode="${btn.dataset.mode}"]`).forEach(b => b.classList.add("active"))
        this.currentMode = btn.dataset.mode
        this._onModeChange()
      })
    })

    // Rail mode buttons
    navContent.querySelectorAll(".nav-rail .rail-btn[data-mode]").forEach(btn => {
      btn.addEventListener("click", () => {
        navContent.querySelectorAll(".mode-btn, .rail-btn[data-mode]").forEach(b => b.classList.remove("active"))
        navContent.querySelectorAll(`[data-mode="${btn.dataset.mode}"]`).forEach(b => b.classList.add("active"))
        this.currentMode = btn.dataset.mode
        this._onModeChange()
      })
    })

    // Rail quick actions
    navContent.querySelector("#rail-add-widget")?.addEventListener("click", () => {
      this.pushEvent("open_widget_palette", {})
    })

    navContent.querySelector("#rail-dashboards")?.addEventListener("click", () => {
      // Open the nav panel to show dashboards
      this.panelLayout._openPanel("navigation")
    })

    navContent.querySelector("#rail-save")?.addEventListener("click", () => {
      const layout = {
        panels: this.panelLayout.saveState(),
        widgets: this.gridManager?.saveWidgets() || []
      }
      this.pushEvent("save_layout", layout)
    })

    // Dashboard list click handlers
    this._bindDashboardListEvents(navContent)
  },

  _renderDashboardList() {
    if (!this.dashboards || this.dashboards.length === 0) {
      return '<div class="text-xs text-base-content/40 px-2 py-1">No dashboards</div>'
    }

    return this.dashboards.map(d => `
      <button class="dashboard-item ${d.id === this.currentDashboardId ? 'active' : ''}" data-id="${d.id}">
        <span class="truncate">${d.name}</span>
        ${d.id === this.currentDashboardId ? '<span class="w-1.5 h-1.5 rounded-full bg-primary"></span>' : ''}
      </button>
    `).join("")
  },

  _bindDashboardListEvents(container) {
    container.querySelectorAll(".dashboard-item").forEach(item => {
      item.addEventListener("click", () => {
        const dashboardId = item.dataset.id
        if (dashboardId !== this.currentDashboardId) {
          this.pushEvent("switch_dashboard", { id: dashboardId })
        }
      })
    })
  },

  _populateContextPanel() {
    const contextContent = this.panelLayout.getPanelContent("context")
    if (!contextContent) return

    // Group alarms by severity
    const critical = this.alarms.filter(a => a.severity === "critical")
    const warning = this.alarms.filter(a => a.severity === "warning")
    const info = this.alarms.filter(a => a.severity === "info" || !a.severity)

    const alarmsCollapsed = this.collapsedSections.alarms
    const commandsCollapsed = this.collapsedSections.commands

    contextContent.innerHTML = `
      <!-- Expanded content -->
      <div class="context-panel-v2 p-3">
        <!-- Alarms Section -->
        <div class="context-section ${alarmsCollapsed ? 'collapsed' : ''}">
          <button class="context-section-header" data-section="alarms">
            <div class="flex items-center gap-2">
              <svg class="section-chevron w-3 h-3 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/>
              </svg>
              <span class="mc-label-subsystem text-base-content/40">ACTIVE ALARMS</span>
              <span class="text-xs text-base-content/60">(${this.alarms.length})</span>
            </div>
            ${this.alarms.length > 0 ? `
              <div class="flex items-center gap-1.5">
                ${critical.length > 0 ? `<span class="w-2 h-2 rounded-full bg-error"></span>` : ''}
                ${warning.length > 0 ? `<span class="w-2 h-2 rounded-full bg-warning"></span>` : ''}
                ${info.length > 0 ? `<span class="w-2 h-2 rounded-full bg-info"></span>` : ''}
              </div>
            ` : ''}
          </button>
          <div class="context-section-content">
            ${critical.length > 0 ? `
              <div class="alarm-group mb-3">
                <div class="alarm-group-header alarm-group-critical mb-2">
                  <span class="w-2 h-2 rounded-full bg-error"></span>
                  <span>CRITICAL (${critical.length})</span>
                </div>
                <div class="flex flex-col gap-1">
                  ${critical.map(a => this._renderAlarmItem(a)).join("")}
                </div>
              </div>
            ` : ''}

            ${warning.length > 0 ? `
              <div class="alarm-group mb-3">
                <div class="alarm-group-header alarm-group-warning mb-2">
                  <span class="w-2 h-2 rounded-full bg-warning"></span>
                  <span>WARNING (${warning.length})</span>
                </div>
                <div class="flex flex-col gap-1">
                  ${warning.map(a => this._renderAlarmItem(a)).join("")}
                </div>
              </div>
            ` : ''}

            ${info.length > 0 ? `
              <div class="alarm-group mb-3">
                <div class="alarm-group-header alarm-group-info mb-2">
                  <span class="w-2 h-2 rounded-full bg-info"></span>
                  <span>INFO (${info.length})</span>
                </div>
                <div class="flex flex-col gap-1">
                  ${info.map(a => this._renderAlarmItem(a)).join("")}
                </div>
              </div>
            ` : ''}

            ${this.alarms.length === 0 ? `
              <div class="text-center py-4 text-base-content/40">
                <p class="text-xs">No active alarms</p>
              </div>
            ` : ''}
          </div>
        </div>

        <!-- Command Queue Section -->
        <div class="context-section ${commandsCollapsed ? 'collapsed' : ''} mt-3 pt-3 border-t border-base-300">
          <button class="context-section-header" data-section="commands">
            <div class="flex items-center gap-2">
              <svg class="section-chevron w-3 h-3 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/>
              </svg>
              <span class="mc-label-subsystem text-base-content/40">COMMAND QUEUE</span>
              <span class="text-xs text-base-content/60">(${this.commands.length})</span>
            </div>
            ${this.commands.some(c => c.status === 'executing') ? `
              <span class="w-2 h-2 rounded-full bg-warning animate-pulse"></span>
            ` : ''}
          </button>
          <div class="context-section-content cmd-queue-list">
            ${this.commands.length > 0 ?
              this.commands.map(cmd => this._renderQueueItem(cmd)).join("") :
              '<p class="text-xs text-base-content/40 text-center py-4">No pending commands</p>'
            }
          </div>
        </div>
      </div>

      <!-- Rail content (visible when collapsed) -->
      <div class="context-rail">
        <!-- Alarm counts -->
        <div class="rail-alarm-badge critical ${critical.length > 0 ? 'has-alarms' : ''}" id="rail-alarm-critical" title="Critical Alarms">
          <span class="rail-alarm-count">${critical.length}</span>
          <span class="rail-alarm-label">CRIT</span>
        </div>

        <div class="rail-alarm-badge warning" id="rail-alarm-warning" title="Warning Alarms">
          <span class="rail-alarm-count">${warning.length}</span>
          <span class="rail-alarm-label">WARN</span>
        </div>

        <div class="rail-alarm-badge info" id="rail-alarm-info" title="Info Alarms">
          <span class="rail-alarm-count">${info.length}</span>
          <span class="rail-alarm-label">INFO</span>
        </div>

        <div class="rail-divider"></div>

        <!-- Command queue badge -->
        <div class="rail-command-badge ${this.commands.length > 0 ? 'has-commands' : ''}" id="rail-command-queue" title="Pending Commands">
          <span class="rail-command-count">${this.commands.length}</span>
          <span class="rail-command-label">CMD</span>
        </div>

        <div class="rail-divider"></div>

        <!-- Quick actions -->
        <button class="rail-btn" id="rail-expand-context" title="Expand Panel">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4"/>
          </svg>
        </button>
      </div>
    `

    // Bind alarm action handlers
    contextContent.querySelectorAll(".alarm-btn-ack").forEach(btn => {
      btn.addEventListener("click", (e) => {
        e.stopPropagation()
        const alarmId = btn.closest(".alarm-item").dataset.id
        this.pushEvent("acknowledge_alarm", { id: alarmId })
      })
    })

    contextContent.querySelectorAll(".alarm-btn-clear").forEach(btn => {
      btn.addEventListener("click", (e) => {
        e.stopPropagation()
        const alarmId = btn.closest(".alarm-item").dataset.id
        this.pushEvent("clear_alarm", { id: alarmId })
      })
    })

    // Queue entry click handlers - click to open detail slideout
    contextContent.querySelectorAll(".qe").forEach(entry => {
      entry.addEventListener("click", () => {
        const entryId = entry.dataset.id
        this._openQueueEntrySlideout(entryId)
      })
    })

    // Rail click handlers - clicking any alarm badge opens the panel
    contextContent.querySelectorAll(".rail-alarm-badge").forEach(badge => {
      badge.addEventListener("click", () => {
        this.panelLayout._openPanel("context")
      })
    })

    // Command queue badge click handler
    contextContent.querySelector("#rail-command-queue")?.addEventListener("click", () => {
      this.panelLayout._openPanel("context")
    })

    contextContent.querySelector("#rail-expand-context")?.addEventListener("click", () => {
      this.panelLayout._openPanel("context")
    })

    // Section collapse/expand handlers
    contextContent.querySelectorAll(".context-section-header").forEach(header => {
      header.addEventListener("click", () => {
        const section = header.dataset.section
        if (section) {
          this.collapsedSections[section] = !this.collapsedSections[section]
          this._populateContextPanel()
        }
      })
    })
  },

  _renderAlarmItem(alarm) {
    const severityClass = alarm.severity === "critical" ? "alarm-item-critical" :
                          alarm.severity === "warning" ? "alarm-item-warning" : "alarm-item-info"

    return `
      <div class="alarm-item ${severityClass}" data-id="${alarm.id}">
        <div class="alarm-header">
          <span class="alarm-source">${alarm.target_name || "Unknown"}</span>
          <span class="alarm-time">${this._formatTime(alarm.triggered_at)}</span>
        </div>
        <div class="alarm-message">${alarm.message || alarm.name || "Alarm"}</div>
        <div class="alarm-actions">
          <button class="alarm-btn alarm-btn-ack">ACK</button>
          <button class="alarm-btn alarm-btn-clear">CLEAR</button>
        </div>
      </div>
    `
  },

  _formatTime(timestamp) {
    if (!timestamp) return "--:--"
    const date = new Date(timestamp)
    return date.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false })
  },

  _populateQuickAccessBar() {
    const quickAccessContent = this.panelLayout.getPanelContent("quickAccess")
    if (!quickAccessContent) return

    // Build target selector options
    const targetOptions = this.targets.map(t =>
      `<option value="${t.id}">${t.name}</option>`
    ).join("")

    quickAccessContent.innerHTML = `
      <div class="flex items-center gap-4">
        <!-- Target selector -->
        <div class="flex items-center gap-2">
          <span class="mc-label-subsystem text-base-content/40">TARGET</span>
          <select id="quick-target-select" class="select select-xs select-bordered w-40">
            <option value="">All Targets</option>
            ${targetOptions}
          </select>
        </div>

        <!-- Quick command buttons -->
        <div class="flex items-center gap-2">
          <span class="mc-label-subsystem text-base-content/40">QUICK CMD</span>
          <button class="btn btn-xs btn-outline btn-warning" id="quick-cmd-safe" title="Safe Mode">
            SAFE
          </button>
          <button class="btn btn-xs btn-outline" id="quick-cmd-ping" title="Ping Target">
            PING
          </button>
          <button class="btn btn-xs btn-outline" id="quick-cmd-status" title="Request Status">
            STATUS
          </button>
        </div>

        <!-- Connection indicator -->
        <div class="flex items-center gap-2 ml-auto">
          <span id="quick-connection-status" class="flex items-center gap-1.5">
            <span class="w-2 h-2 rounded-full bg-success animate-pulse"></span>
            <span class="mc-label-subsystem text-success">CONNECTED</span>
          </span>
        </div>
      </div>
    `

    // Bind quick command handlers
    quickAccessContent.querySelector("#quick-target-select")?.addEventListener("change", (e) => {
      this.selectedTargetId = e.target.value || null
      console.log("[OpsConsole] Target selected:", this.selectedTargetId)
    })

    quickAccessContent.querySelector("#quick-cmd-safe")?.addEventListener("click", () => {
      if (this.selectedTargetId) {
        this.pushEvent("quick_command", { target_id: this.selectedTargetId, command: "SAFE_MODE" })
      }
    })

    quickAccessContent.querySelector("#quick-cmd-ping")?.addEventListener("click", () => {
      if (this.selectedTargetId) {
        this.pushEvent("quick_command", { target_id: this.selectedTargetId, command: "PING" })
      }
    })

    quickAccessContent.querySelector("#quick-cmd-status")?.addEventListener("click", () => {
      if (this.selectedTargetId) {
        this.pushEvent("quick_command", { target_id: this.selectedTargetId, command: "STATUS" })
      }
    })
  },

  _setupKeyboardShortcuts() {
    this._keydownHandler = (e) => {
      // Ignore if typing in an input
      if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA") {
        return
      }

      // Escape - close slideout, exit fullscreen, or close modals
      if (e.key === "Escape") {
        if (this._slideoutOpen) {
          if (this._slideoutType === 'queue-entry') {
            this._closeQueueEntrySlideout()
          } else {
            this._closeCommandSlideout()
          }
          e.preventDefault()
          return
        }
        if (this._fullscreenWidget) {
          this._exitFullscreen()
          e.preventDefault()
        }
        return
      }

      // F - Toggle fullscreen for focused widget
      if (e.key === "f" || e.key === "F") {
        const focusedWidget = document.activeElement?.closest(".grid-stack-item")
        if (focusedWidget) {
          const widgetId = focusedWidget.getAttribute("gs-id")
          if (widgetId) {
            this._toggleFullscreen(widgetId)
            e.preventDefault()
          }
        }
        return
      }

      // L - Toggle lock
      if (e.key === "l" || e.key === "L") {
        if (this.gridManager) {
          this.gridManager.toggleLocked()
          this._updateToolbar()
          e.preventDefault()
        }
        return
      }
    }

    document.addEventListener("keydown", this._keydownHandler)
  },

  _toggleFullscreen(widgetId) {
    if (this._fullscreenWidget === widgetId) {
      this._exitFullscreen()
    } else {
      this._enterFullscreen(widgetId)
    }
  },

  _enterFullscreen(widgetId) {
    const widget = this.gridManager?.getWidget(widgetId)
    if (!widget) return

    // Create fullscreen overlay
    const overlay = document.createElement("div")
    overlay.id = "fullscreen-overlay"
    overlay.className = "fixed inset-0 z-50 bg-base-100 flex flex-col"

    // Create header
    const header = document.createElement("div")
    header.className = "flex items-center justify-between px-4 py-2 bg-base-200 border-b border-base-300"
    header.innerHTML = `
      <div class="flex items-center gap-2">
        <span class="mc-label-subsystem text-base-content/40">FULLSCREEN</span>
        <span class="font-semibold text-sm">${widget.config?.title || "Widget"}</span>
      </div>
      <button class="btn btn-ghost btn-sm" id="exit-fullscreen-btn" title="Exit fullscreen (Esc)">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
        </svg>
      </button>
    `
    overlay.appendChild(header)

    // Create content container
    const content = document.createElement("div")
    content.className = "flex-1 p-4 overflow-auto"
    content.id = "fullscreen-content"
    overlay.appendChild(content)

    // Clone the widget content into fullscreen
    const widgetElement = document.querySelector(`[gs-id="${widgetId}"]`)
    if (widgetElement) {
      const widgetContent = widgetElement.querySelector(".widget-body, .cadence-widget")
      if (widgetContent) {
        const clone = widgetContent.cloneNode(true)
        clone.style.height = "100%"
        content.appendChild(clone)
      }
    }

    document.body.appendChild(overlay)
    this._fullscreenWidget = widgetId

    // Bind exit button
    document.getElementById("exit-fullscreen-btn")?.addEventListener("click", () => {
      this._exitFullscreen()
    })
  },

  _exitFullscreen() {
    const overlay = document.getElementById("fullscreen-overlay")
    if (overlay) {
      overlay.remove()
    }
    this._fullscreenWidget = null
  },

  async _connectTelemetry() {
    if (!this.token || !this.missionId) {
      console.warn("[OpsConsole] Missing token or missionId, skipping telemetry connection")
      return
    }

    this.telemetryStore = getStore({ maxSamples: 5000 })

    this._connectionUnsubscribe = this.telemetryStore.onConnectionChange((connected) => {
      // Update connection status in quick access bar
      const statusEl = document.getElementById("quick-connection-status")
      if (statusEl) {
        if (connected) {
          statusEl.innerHTML = `
            <span class="w-2 h-2 rounded-full bg-success animate-pulse"></span>
            <span class="mc-label-subsystem text-success">CONNECTED</span>
          `
        } else {
          statusEl.innerHTML = `
            <span class="w-2 h-2 rounded-full bg-error"></span>
            <span class="mc-label-subsystem text-error">DISCONNECTED</span>
          `
        }
      }
    })

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
      if (widgetConfig.config?.telemetry_items) {
        for (const item of widgetConfig.config.telemetry_items) {
          subscriptions.push({
            target: item.target,
            packet: item.packet,
            item: item.item
          })
        }
      }

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

  _setupGridEvents() {
    this.gridManager.on("change", ({ items }) => {
      this._debounce("saveWidgets", () => {
        this.pushEvent("widgets_changed", { widgets: items })
      }, 1000)

      // Update toolbar widget count
      this._updateToolbar()
    })

    this.gridManager.on("widgetRemoved", ({ id }) => {
      console.log("[OpsConsole] Widget removed:", id)
      this._updateToolbar()
    })

    this.gridManager.on("widgetAdded", ({ id, type }) => {
      console.log("[OpsConsole] Widget added:", id, type)
      this._updateToolbar()
    })
  },

  _setupEventHandlers() {
    this.handleEvent("add_widget", (payload) => {
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
      if (payload.widgets && this.gridManager) {
        this.gridManager.loadWidgets(payload.widgets)
      }
    })

    this.handleEvent("update_dashboards", (payload) => {
      this.dashboards = payload.dashboards
      this.currentDashboardId = payload.currentId
      // Re-render dashboard list in nav panel
      this._populateNavPanel()
    })

    this.handleEvent("alarm_update", (payload) => {
      if (payload.type === "created" || payload.type === "triggered") {
        this.alarms = [payload.alarm, ...this.alarms]
      } else if (payload.type === "updated") {
        const idx = this.alarms.findIndex(a => a.id === payload.alarm.id)
        if (idx >= 0) {
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
      // Re-render alarms in context panel and alarms mode
      this._populateContextPanel()
      if (this.currentMode === 'alarms') {
        this._renderAlarmsMode()
      }
    })

    this.handleEvent("historical_alarms_loaded", (payload) => {
      this.historicalAlarms = payload.alarms || []
      if (this.currentMode === 'alarms' && this.alarmsViewMode === 'historical') {
        this._renderAlarmsMode()
      }
    })

    this.handleEvent("alarm_rules_loaded", (payload) => {
      this.alarmRules = payload.rules || []
      if (this.currentMode === 'alarms' && this.alarmsViewMode === 'panel') {
        this._renderAlarmsMode()
      }
    })

    this.handleEvent("update_commands", (payload) => {
      this.commands = payload.commands || []
      // Re-render context panel with updated commands
      this._populateContextPanel()
    })

    // Handle queue entries update (for Queue mode)
    this.handleEvent("update_queue_entries", (payload) => {
      this.queueEntries = payload.entries || []
      // Re-render queue mode if active
      if (this.currentMode === "queue") {
        this._renderQueueMode()
      }
    })

    // Handle server-side queue metrics (accurate counts from database)
    this.handleEvent("queue_metrics", ({ metrics }) => {
      this.queueServerMetrics = metrics
      // Re-render queue mode if active (metrics will be used in overview)
      if (this.currentMode === "queue") {
        this._renderQueueMode()
      }
    })

    // Handle target queue paused
    this.handleEvent("queue_target_paused", (payload) => {
      const targetId = payload.target_id
      if (targetId) {
        const status = this.queueTargetStatuses.get(targetId) || { paused: false, pending: 0, executing: 0 }
        status.paused = true
        this.queueTargetStatuses.set(targetId, status)
        // Re-render if in queue mode and manage view
        if (this.currentMode === "queue" && this.queueViewMode === "manage") {
          this._renderQueueMode()
        }
      }
    })

    // Handle target queue resumed
    this.handleEvent("queue_target_resumed", (payload) => {
      const targetId = payload.target_id
      if (targetId) {
        const status = this.queueTargetStatuses.get(targetId) || { paused: false, pending: 0, executing: 0 }
        status.paused = false
        this.queueTargetStatuses.set(targetId, status)
        // Re-render if in queue mode and manage view
        if (this.currentMode === "queue" && this.queueViewMode === "manage") {
          this._renderQueueMode()
        }
      }
    })

    // Handle staged commands loaded from server
    this.handleEvent("load_staged_commands", (payload) => {
      this.cmdStagedCommands = payload.staged || []
      this._updateStagingPanel()
    })

    // Handle staging updates (for multi-tab/multi-operator sync)
    this.handleEvent("staging_updated", (payload) => {
      console.log("[OpsConsole] Staging updated:", payload.action)
      // The server will send load_staged_commands right after this
      // This event is just a notification that staging changed
    })

    // Handle timeline events (real-time updates)
    this.handleEvent("timeline_event", (payload) => {
      this._handleTimelineEvent(payload.event)
    })

    // Handle more timeline events from infinite scroll
    this.handleEvent("more_timeline_events", (payload) => {
      this._handleMoreTimelineEvents(payload.events, payload.has_more)
    })

    this.el.addEventListener("widget:configure", (e) => {
      const { widgetId, widgetType, config } = e.detail
      this.pushEvent("open_widget_config", {
        widget_id: widgetId,
        widget_type: widgetType,
        config: config
      })
    })
  },

  // ============================================================================
  // Mode Switching
  // ============================================================================

  _onModeChange() {
    console.log("[OpsConsole] Mode changed to:", this.currentMode)

    const dashboard = this.panelLayout?.elements?.dashboard
    if (!dashboard) return

    // Clear all mode classes first
    dashboard.classList.remove("commands-mode-active", "timeline-mode-active", "queue-mode-active", "alarms-mode-active")

    if (this.currentMode === "commands") {
      // Hide GridStack dashboard, show Commands mode
      dashboard.classList.add("commands-mode-active")
      this._hideTimelineMode()
      this._hideQueueMode()
      this._hideAlarmsMode()
      this._renderCommandsMode()
    } else if (this.currentMode === "timeline") {
      // Hide GridStack dashboard, show Timeline mode
      dashboard.classList.add("timeline-mode-active")
      this._hideCommandsMode()
      this._hideQueueMode()
      this._hideAlarmsMode()
      this._renderTimelineMode()
    } else if (this.currentMode === "queue") {
      // Hide GridStack dashboard, show Queue mode
      dashboard.classList.add("queue-mode-active")
      this._hideCommandsMode()
      this._hideTimelineMode()
      this._hideAlarmsMode()
      this._renderQueueMode()
    } else if (this.currentMode === "alarms") {
      // Hide GridStack dashboard, show Alarms mode
      dashboard.classList.add("alarms-mode-active")
      this._hideCommandsMode()
      this._hideTimelineMode()
      this._hideQueueMode()
      this._renderAlarmsMode()
    } else {
      // Show GridStack dashboard, hide mode-specific content
      this._hideCommandsMode()
      this._hideTimelineMode()
      this._hideQueueMode()
      this._hideAlarmsMode()
    }

    // Update context panel based on mode
    this._populateContextPanel()
  },

  _renderCommandsMode() {
    const dashboard = this.panelLayout?.elements?.dashboard
    if (!dashboard) return

    // Check if commands container already exists
    let commandsContainer = dashboard.querySelector(".commands-mode-container")
    if (!commandsContainer) {
      commandsContainer = document.createElement("div")
      commandsContainer.className = "commands-mode-container"
      dashboard.appendChild(commandsContainer)
    }

    commandsContainer.innerHTML = `
      <div class="commands-mode-layout">
        <!-- Top: Target Selection and Command Browser -->
        <div class="cmd-panels-row">
          <!-- Left: Target Selection -->
          <div class="cmd-target-panel" style="flex: 0 0 ${this.cmdTargetPanelWidth || 40}%">
            <div class="cmd-panel-header">
              <div class="cmd-panel-title">
                <span class="mc-label-subsystem">TARGET SELECTION</span>
                <span class="cmd-selection-count">${this.cmdSelectedTargets.size} of ${this.targets.length}</span>
              </div>
              <div class="cmd-view-toggle">
                <button class="cmd-view-btn ${this.cmdTargetViewMode === 'compact' ? 'active' : ''}"
                        data-view="compact" title="Compact view">
                  <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 10h16M4 14h16M4 18h16"/>
                  </svg>
                </button>
                <button class="cmd-view-btn ${this.cmdTargetViewMode === 'detailed' ? 'active' : ''}"
                        data-view="detailed" title="Detailed view">
                  <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16m-7 6h7"/>
                  </svg>
                </button>
              </div>
            </div>
            <div class="cmd-target-filters">
              <input type="text"
                     class="cmd-target-search"
                     placeholder="Filter targets..."
                     value="${this.cmdTargetFilter}">
              <select class="cmd-group-filter">
                <option value="">All Groups</option>
                ${this.targetGroups.map(g => `<option value="${g.id}">${g.name}</option>`).join("")}
              </select>
            </div>
            <div class="cmd-target-grid ${this.cmdTargetViewMode === 'detailed' ? 'detailed-view' : ''}">
              ${this._renderTargetGrid()}
            </div>
            <div class="cmd-selection-actions">
              <button class="btn btn-ghost btn-xs" id="cmd-select-all">Select All</button>
              <button class="btn btn-ghost btn-xs" id="cmd-clear-selection">Clear</button>
            </div>
          </div>

          <!-- Resize Handle -->
          <div class="cmd-resize-handle" id="cmd-resize-handle"></div>

          <!-- Right: Command Browser -->
          <div class="cmd-command-panel">
            <div class="cmd-panel-header">
              <span class="mc-label-subsystem">COMMANDS</span>
              <span class="cmd-command-count">${this.commandDefinitions.length} available</span>
            </div>
            <div class="cmd-command-filters">
              <input type="text"
                     class="cmd-command-search"
                     placeholder="Search commands..."
                     value="${this.cmdCommandFilter}">
            </div>
            <div class="cmd-command-list">
              ${this._renderCommandList()}
            </div>
          </div>
        </div>

        <!-- Bottom: Staging Panel -->
        ${this._renderStagingPanel()}
      </div>
    `

    // Bind event handlers
    this._bindCommandsModeEvents(commandsContainer)
  },

  _hideCommandsMode() {
    const dashboard = this.panelLayout?.elements?.dashboard
    if (!dashboard) return

    const commandsContainer = dashboard.querySelector(".commands-mode-container")
    if (commandsContainer) {
      commandsContainer.innerHTML = ""
    }
  },

  // ============================================================================
  // Timeline Mode
  // ============================================================================

  _renderTimelineMode() {
    const dashboard = this.panelLayout?.elements?.dashboard
    if (!dashboard) return

    // Check if timeline container already exists
    let timelineContainer = dashboard.querySelector(".timeline-mode-container")
    if (!timelineContainer) {
      timelineContainer = document.createElement("div")
      timelineContainer.className = "timeline-mode-container"
      dashboard.appendChild(timelineContainer)
    }

    // Render the appropriate view
    let viewContent = ''
    switch (this.timelineView) {
      case 'matrix':
        viewContent = this._renderMatrixViewContent()
        break
      case 'lanes':
        viewContent = this._renderLanesViewContent()
        break
      case 'stream':
      default:
        viewContent = this._renderStreamViewContent()
        break
    }

    timelineContainer.innerHTML = `
      <div class="timeline-mode-layout">
        ${viewContent}

        <!-- Controls Bar -->
        <div class="timeline-controls">
          <div class="timeline-view-tabs">
            <button class="timeline-view-tab ${this.timelineView === 'stream' ? 'active' : ''}" data-view="stream">STREAM</button>
            <button class="timeline-view-tab ${this.timelineView === 'matrix' ? 'active' : ''}" data-view="matrix">MATRIX</button>
            <button class="timeline-view-tab ${this.timelineView === 'lanes' ? 'active' : ''}" data-view="lanes">LANES</button>
          </div>
          ${this._renderTimelineViewControls()}
        </div>
      </div>
    `

    // Bind event handlers
    this._bindTimelineModeEvents(timelineContainer)
  },

  _renderTimelineViewControls() {
    // Common type filters
    const typeFilters = `
      <div class="timeline-filters">
        <label class="timeline-filter-toggle ${this.timelineTypeFilter.has('command') ? 'active' : ''}" data-type="command">
          <span class="filter-badge filter-badge-command">CMD</span>
        </label>
        <label class="timeline-filter-toggle ${this.timelineTypeFilter.has('alarm') ? 'active' : ''}" data-type="alarm">
          <span class="filter-badge filter-badge-alarm">ALM</span>
        </label>
        <label class="timeline-filter-toggle ${this.timelineTypeFilter.has('procedure') ? 'active' : ''}" data-type="procedure">
          <span class="filter-badge filter-badge-procedure">PROC</span>
        </label>
        <label class="timeline-filter-toggle ${this.timelineTypeFilter.has('automation') ? 'active' : ''}" data-type="automation">
          <span class="filter-badge filter-badge-automation">AUTO</span>
        </label>
      </div>
    `

    // View-specific controls
    switch (this.timelineView) {
      case 'matrix':
        return `
          ${typeFilters}
          <div class="timeline-matrix-controls">
            <select class="timeline-select" id="matrix-bucket">
              <option value="5" ${this.matrixTimeBucket === 5 ? 'selected' : ''}>5 min</option>
              <option value="15" ${this.matrixTimeBucket === 15 ? 'selected' : ''}>15 min</option>
              <option value="60" ${this.matrixTimeBucket === 60 ? 'selected' : ''}>1 hour</option>
              <option value="240" ${this.matrixTimeBucket === 240 ? 'selected' : ''}>4 hours</option>
            </select>
          </div>
        `
      case 'lanes':
        return `
          ${typeFilters}
          <div class="timeline-lanes-controls">
            <select class="timeline-select" id="lanes-range">
              <option value="2" ${this.lanesTimeRange === 2 ? 'selected' : ''}>±2 hours</option>
              <option value="6" ${this.lanesTimeRange === 6 ? 'selected' : ''}>±6 hours</option>
              <option value="12" ${this.lanesTimeRange === 12 ? 'selected' : ''}>±12 hours</option>
              <option value="24" ${this.lanesTimeRange === 24 ? 'selected' : ''}>±24 hours</option>
            </select>
          </div>
        `
      case 'stream':
      default:
        return `
          ${typeFilters}
          <div class="timeline-actions">
            <button class="timeline-action-btn ${this.timelinePaused ? 'active' : ''}" id="timeline-pause">
              ${this.timelinePaused ? '▶ RESUME' : '⏸ PAUSE'}
            </button>
            <button class="timeline-action-btn" id="timeline-jump-now">↑ NOW</button>
          </div>
        `
    }
  },

  _renderStreamViewContent() {
    const now = new Date()

    // Filter by event type first
    let filteredEvents = this.timelineEvents.filter(e => this.timelineTypeFilter.has(e.type))

    // Apply target filter - show events for selected targets only
    filteredEvents = filteredEvents.filter(e => {
      // System events (no target_id)
      if (!e.target_id) {
        return this.streamShowSystem
      }
      // Only show events for selected targets
      return this.streamTargetFilter.has(e.target_id)
    })

    // All past events - no client-side limit, server handles pagination
    const pastEvents = filteredEvents
      .filter(e => !e.is_future && new Date(e.timestamp) <= now)
      .sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp))
    const futureEvents = filteredEvents
      .filter(e => e.is_future || new Date(e.timestamp) > now)
      .sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp))

    // Cluster related events
    const pastClusters = this._clusterEvents(pastEvents, 'past')
    const futureClusters = this._clusterEvents(futureEvents, 'future')

    // Calculate activity metrics
    const activityRate = this._calculateActivityRate(pastEvents)

    // Determine activity level class
    const activityLevel = activityRate > 20 ? 'high' : activityRate > 5 ? 'medium' : 'low'

    // Status indicator
    const statusDotClass = this.timelinePaused ? 'paused' : 'active'
    const statusText = this.timelinePaused ? 'PAUSED' : 'LIVE'

    // Render loading state or load more button
    const loadMoreContent = this.streamLoadingMore
      ? `<div class="stream-loading-more">
           <div class="stream-loading-spinner"></div>
           <span>Loading older events...</span>
         </div>`
      : this.streamHasMoreEvents
        ? `<div class="stream-load-more">
             <button class="stream-load-more-btn" id="stream-load-more">
               Load more events
             </button>
           </div>`
        : pastEvents.length > 0
          ? `<div class="stream-end-marker">
               <span class="end-marker-text">End of timeline</span>
             </div>`
          : ''

    // Get saved panel width or default to 30%
    const filterPanelWidth = this.streamFilterPanelWidth || 30

    return `
      <div class="timeline-stream-enhanced">
        <div class="stream-split-layout">
          <!-- Left Panel: Target Filter -->
          ${this._renderStreamTargetFilterPanel(filterPanelWidth)}

          <!-- Resize Handle -->
          <div class="stream-resize-handle" id="stream-resize-handle"></div>

          <!-- Right Panel: Events Stream -->
          <div class="stream-events-panel">
            <!-- HUD Panel Header -->
            <div class="stream-panel-header">
              <div class="stream-panel-title">
                <span class="stream-panel-label">EVENT STREAM</span>
                <div class="stream-panel-status">
                  <span class="stream-status-dot ${statusDotClass}"></span>
                  <span class="stream-status-text">${statusText}</span>
                </div>
              </div>
              <div class="stream-panel-metrics">
                <div class="stream-metric ${activityLevel}">
                  <div class="stream-metric-bar">
                    <div class="stream-metric-fill" style="width: ${Math.min(100, activityRate * 5)}%"></div>
                  </div>
                  <span class="stream-metric-value">${activityRate.toFixed(1)} evt/min</span>
                </div>
                <span class="stream-metric-count">${pastEvents.length}</span>
                ${this.timelinePaused ? '<span class="stream-paused-badge">PAUSED</span>' : ''}
              </div>
            </div>

            <!-- HUD Body with Grid Background -->
            <div class="stream-body">
              <div class="stream-events-container" id="stream-events-container">
                <!-- Future Events Section -->
                ${futureClusters.length > 0 ? `
                  <div class="stream-section stream-future-section">
                    <div class="stream-section-header">
                      <span class="stream-section-icon">◇</span>
                      <span class="stream-section-label">SCHEDULED</span>
                      <span class="stream-section-count">${futureEvents.length}</span>
                    </div>
                    <div class="stream-events-list">
                      ${futureClusters.map(item =>
                        item.isCluster
                          ? this._renderEventCluster(item)
                          : this._renderStreamEvent(item.events[0])
                      ).join('')}
                    </div>
                  </div>
                ` : ''}

                <!-- NOW Marker -->
                <div class="stream-now-marker" id="stream-now-marker">
                  <div class="stream-now-line"></div>
                  <div class="stream-now-badge">
                    <span class="stream-now-text">NOW</span>
                    <span class="stream-now-time">${this._formatTimeUTC(now)}</span>
                  </div>
                  <div class="stream-now-line"></div>
                </div>

                <!-- Past Events Section with Time Context -->
                <div class="stream-section stream-past-section">
                  ${pastClusters.length > 0 ? `
                    <div class="stream-events-list">
                      ${this._renderPastEventsWithTimeContext(pastClusters)}
                    </div>
                  ` : `
                    <div class="stream-empty-state">
                      <span class="empty-icon">○</span>
                      <span class="empty-text">No events in the selected time range</span>
                    </div>
                  `}

                  <!-- Load More / Loading / End of timeline -->
                  ${loadMoreContent}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    `
  },

  /**
   * Cluster related events that occur within a short time window.
   * Groups same command to multiple targets, alarm storms, etc.
   */
  _clusterEvents(events, direction) {
    if (events.length === 0) return []

    const clusters = []
    const clusterWindowMs = 30000 // 30 second window for clustering
    let currentCluster = null

    events.forEach((event, idx) => {
      const eventTime = new Date(event.timestamp).getTime()

      if (!currentCluster) {
        currentCluster = {
          events: [event],
          type: event.type,
          title: event.title,
          startTime: eventTime,
          endTime: eventTime
        }
        return
      }

      const timeDiff = direction === 'past'
        ? currentCluster.startTime - eventTime
        : eventTime - currentCluster.endTime

      // Check if this event should be added to current cluster
      const sameType = event.type === currentCluster.type
      const sameTitle = event.title === currentCluster.title
      const withinWindow = timeDiff <= clusterWindowMs

      if (sameType && sameTitle && withinWindow) {
        currentCluster.events.push(event)
        if (direction === 'past') {
          currentCluster.startTime = eventTime
        } else {
          currentCluster.endTime = eventTime
        }
      } else {
        // Finalize current cluster and start new one
        clusters.push(this._finalizeCluster(currentCluster))
        currentCluster = {
          events: [event],
          type: event.type,
          title: event.title,
          startTime: eventTime,
          endTime: eventTime
        }
      }
    })

    // Don't forget the last cluster
    if (currentCluster) {
      clusters.push(this._finalizeCluster(currentCluster))
    }

    return clusters
  },

  /**
   * Finalize a cluster - determine if it should be shown as cluster or individual events
   */
  _finalizeCluster(cluster) {
    const isCluster = cluster.events.length >= 3
    return {
      isCluster,
      events: cluster.events,
      type: cluster.type,
      title: cluster.title,
      count: cluster.events.length,
      startTime: cluster.startTime,
      endTime: cluster.endTime,
      id: `cluster-${cluster.startTime}-${cluster.type}`
    }
  },

  /**
   * Render the target filter panel for the Stream view.
   * Side panel with SYSTEM pseudo-target and all constellation targets.
   */
  _renderStreamTargetFilterPanel(widthPercent = 30) {
    // Gather all unique targets from events and from available targets
    const targetMap = new Map()

    // Get targets from events
    this.timelineEvents.forEach(e => {
      if (e.target_id && e.target_name) {
        targetMap.set(e.target_id, {
          id: e.target_id,
          name: e.target_name,
          status: e.target_status || 'online'
        })
      }
    })

    // Also use the available targets list if available
    const availableTargets = JSON.parse(this.el.dataset.targets || '[]')
    availableTargets.forEach(t => {
      if (!targetMap.has(t.id)) {
        targetMap.set(t.id, {
          id: t.id,
          name: t.name,
          status: t.status || 'online'
        })
      }
    })

    const targets = Array.from(targetMap.values()).sort((a, b) =>
      a.name.localeCompare(b.name)
    )

    // Initialize filter with all targets selected on first render
    if (!this.streamTargetFilterInitialized && targets.length > 0) {
      this.streamTargetFilter = new Set(targets.map(t => t.id))
      this.streamTargetFilterInitialized = true
    }

    // Count system events (events without target_id)
    const systemEventCount = this.timelineEvents.filter(e => !e.target_id).length

    // Filter targets by search
    const filteredTargets = this.streamTargetSearch
      ? targets.filter(t =>
          t.name.toLowerCase().includes(this.streamTargetSearch.toLowerCase())
        )
      : targets

    // Calculate selected count
    const totalCount = targets.length + 1 // +1 for SYSTEM
    const selectedCount = this.streamTargetFilter.size + (this.streamShowSystem ? 1 : 0)
    const countText = `${selectedCount} of ${totalCount}`

    return `
      <div class="stream-target-filter-panel" style="flex: 0 0 ${widthPercent}%;">
        <!-- Filter Panel Header -->
        <div class="stream-target-filter-header">
          <div class="stream-filter-title">
            <span class="stream-filter-title-text">FILTER BY TARGET</span>
            <span class="stream-filter-count">${countText}</span>
          </div>
        </div>

        <!-- Search Input -->
        <div class="stream-target-search-wrapper">
          <input
            type="text"
            class="stream-target-search"
            id="stream-target-search"
            placeholder="Filter targets..."
            value="${this.streamTargetSearch}"
          />
        </div>

        <!-- Target Grid -->
        <div class="stream-target-grid" id="stream-target-grid">
          ${this._renderStreamTargetGrid(filteredTargets, systemEventCount)}
        </div>

        <!-- Selection Actions Footer -->
        <div class="stream-filter-actions-footer">
          <button class="stream-filter-action" id="stream-select-all-targets">
            Select All
          </button>
          <button class="stream-filter-action" id="stream-clear-target-filter">
            Clear
          </button>
        </div>
      </div>
    `
  },

  /**
   * Render the target grid cells including SYSTEM pseudo-target.
   */
  _renderStreamTargetGrid(targets, systemEventCount) {
    // SYSTEM pseudo-target (always first)
    const systemSelected = this.streamShowSystem
    const systemCell = `
      <div
        class="stream-target-cell system-target ${systemSelected ? 'selected' : ''}"
        data-target-id="__SYSTEM__"
        title="System events (${systemEventCount} events)"
      >
        <span class="stream-target-name">◆ SYSTEM</span>
      </div>
    `

    // Regular target cells
    const targetCells = targets.map(target => {
      const isSelected = this.streamTargetFilter.has(target.id)
      const statusClass = `status-${target.status || 'online'}`

      return `
        <div
          class="stream-target-cell ${statusClass} ${isSelected ? 'selected' : ''}"
          data-target-id="${target.id}"
          title="${target.name}"
        >
          <span class="stream-target-name">${target.name}</span>
        </div>
      `
    }).join('')

    return systemCell + targetCells
  },

  /**
   * Toggle a target in the stream filter.
   */
  _toggleStreamTargetFilter(targetId) {
    if (targetId === '__SYSTEM__') {
      this.streamShowSystem = !this.streamShowSystem
    } else {
      if (this.streamTargetFilter.has(targetId)) {
        this.streamTargetFilter.delete(targetId)
      } else {
        this.streamTargetFilter.add(targetId)
      }
    }
    this._renderTimelineMode()
  },

  /**
   * Select all targets in the stream filter.
   */
  _selectAllStreamTargets() {
    // Gather all target IDs
    const targetMap = new Map()
    this.timelineEvents.forEach(e => {
      if (e.target_id && e.target_name) {
        targetMap.set(e.target_id, true)
      }
    })

    const availableTargets = JSON.parse(this.el.dataset.targets || '[]')
    availableTargets.forEach(t => {
      targetMap.set(t.id, true)
    })

    // Add all targets to the filter
    this.streamTargetFilter = new Set(targetMap.keys())
    this.streamShowSystem = true
    this._renderTimelineMode()
  },

  /**
   * Clear all target selections.
   */
  _clearStreamTargetFilter() {
    this.streamShowSystem = false
    this.streamTargetFilter.clear()
    this._renderTimelineMode()
  },

  /**
   * Handle stream target search input.
   * Only updates the target grid, not full re-render, to preserve focus.
   */
  _handleStreamTargetSearch(searchText) {
    this.streamTargetSearch = searchText
    this._updateStreamTargetGrid()
  },

  /**
   * Start resizing the stream filter panel.
   */
  _startStreamPanelResize(e) {
    e.preventDefault()

    const dashboard = this.panelLayout?.elements?.dashboard
    const splitLayout = dashboard?.querySelector('.stream-split-layout')
    const filterPanel = dashboard?.querySelector('.stream-target-filter-panel')
    const resizeHandle = dashboard?.querySelector('#stream-resize-handle')

    if (!splitLayout || !filterPanel) return

    resizeHandle?.classList.add('dragging')

    const startX = e.clientX
    const layoutRect = splitLayout.getBoundingClientRect()
    const startWidth = filterPanel.getBoundingClientRect().width
    const layoutWidth = layoutRect.width

    const onMouseMove = (moveEvent) => {
      const deltaX = moveEvent.clientX - startX
      const newWidth = startWidth + deltaX
      const newPercent = (newWidth / layoutWidth) * 100

      // Clamp between 15% and 50%
      const clampedPercent = Math.max(15, Math.min(50, newPercent))

      filterPanel.style.flex = `0 0 ${clampedPercent}%`
      this.streamFilterPanelWidth = clampedPercent
    }

    const onMouseUp = () => {
      resizeHandle?.classList.remove('dragging')
      document.removeEventListener('mousemove', onMouseMove)
      document.removeEventListener('mouseup', onMouseUp)
    }

    document.addEventListener('mousemove', onMouseMove)
    document.addEventListener('mouseup', onMouseUp)
  },

  /**
   * Start resizing the commands target panel.
   */
  _startCmdPanelResize(e) {
    e.preventDefault()

    const dashboard = this.panelLayout?.elements?.dashboard
    const panelsRow = dashboard?.querySelector('.cmd-panels-row')
    const targetPanel = dashboard?.querySelector('.cmd-target-panel')
    const resizeHandle = dashboard?.querySelector('#cmd-resize-handle')

    if (!panelsRow || !targetPanel) return

    resizeHandle?.classList.add('dragging')

    const startX = e.clientX
    const layoutRect = panelsRow.getBoundingClientRect()
    const startWidth = targetPanel.getBoundingClientRect().width
    const layoutWidth = layoutRect.width

    const onMouseMove = (moveEvent) => {
      const deltaX = moveEvent.clientX - startX
      const newWidth = startWidth + deltaX
      const newPercent = (newWidth / layoutWidth) * 100

      // Clamp between 15% and 60%
      const clampedPercent = Math.max(15, Math.min(60, newPercent))

      targetPanel.style.flex = `0 0 ${clampedPercent}%`
      this.cmdTargetPanelWidth = clampedPercent
    }

    const onMouseUp = () => {
      resizeHandle?.classList.remove('dragging')
      document.removeEventListener('mousemove', onMouseMove)
      document.removeEventListener('mouseup', onMouseUp)
    }

    document.addEventListener('mousemove', onMouseMove)
    document.addEventListener('mouseup', onMouseUp)
  },

  /**
   * Update only the stream target grid without full re-render.
   * Preserves search input focus.
   */
  _updateStreamTargetGrid() {
    const dashboard = this.panelLayout?.elements?.dashboard
    const gridContainer = dashboard?.querySelector('#stream-target-grid')
    if (!gridContainer) return

    // Gather targets same as in _renderStreamTargetFilterPanel
    const targetMap = new Map()
    this.timelineEvents.forEach(e => {
      if (e.target_id && e.target_name) {
        targetMap.set(e.target_id, {
          id: e.target_id,
          name: e.target_name,
          status: e.target_status || 'online'
        })
      }
    })

    const availableTargets = JSON.parse(this.el.dataset.targets || '[]')
    availableTargets.forEach(t => {
      if (!targetMap.has(t.id)) {
        targetMap.set(t.id, { id: t.id, name: t.name, status: t.status || 'online' })
      }
    })

    const targets = Array.from(targetMap.values()).sort((a, b) =>
      a.name.localeCompare(b.name)
    )

    const filteredTargets = this.streamTargetSearch
      ? targets.filter(t =>
          t.name.toLowerCase().includes(this.streamTargetSearch.toLowerCase())
        )
      : targets

    const systemEventCount = this.timelineEvents.filter(e => !e.target_id).length

    // Update only the grid content
    gridContainer.innerHTML = this._renderStreamTargetGrid(filteredTargets, systemEventCount)

    // Re-bind click handlers for the new cells
    gridContainer.querySelectorAll('.stream-target-cell').forEach(cell => {
      cell.addEventListener('click', () => {
        const targetId = cell.dataset.targetId
        this._toggleStreamTargetFilter(targetId)
      })
    })
  },

  /**
   * Calculate activity density for the timeline spine visualization.
   * Returns array of density segments with intensity levels.
   */
  _calculateDensity(events) {
    const now = new Date()
    const timeRangeMs = 2 * 60 * 60 * 1000 // 2 hours
    const startTime = new Date(now.getTime() - timeRangeMs)
    const endTime = new Date(now.getTime() + (timeRangeMs / 2)) // 1 hour future
    const totalMs = endTime - startTime
    const bucketCount = 30 // Number of density segments
    const bucketMs = totalMs / bucketCount

    // Initialize buckets
    const buckets = Array(bucketCount).fill(0).map((_, i) => ({
      time: new Date(startTime.getTime() + i * bucketMs),
      count: 0
    }))

    // Count events per bucket
    events.forEach(event => {
      const eventTime = new Date(event.timestamp).getTime()
      const bucketIndex = Math.floor((eventTime - startTime.getTime()) / bucketMs)
      if (bucketIndex >= 0 && bucketIndex < bucketCount) {
        buckets[bucketIndex].count++
      }
    })

    // Find max for normalization
    const maxCount = Math.max(1, ...buckets.map(b => b.count))

    // Calculate NOW position
    const nowPosition = ((now - startTime) / totalMs) * 100

    // Map to density segments with intensity
    return buckets.map(bucket => {
      const ratio = bucket.count / maxCount
      let intensity = 'none'
      if (bucket.count > 0) {
        if (ratio > 0.7) intensity = 'high'
        else if (ratio > 0.3) intensity = 'medium'
        else intensity = 'low'
      }
      return {
        ...bucket,
        height: 100 / bucketCount,
        intensity,
        nowPosition
      }
    }).map((d, _, arr) => ({ ...d, nowPosition }))
  },

  /**
   * Calculate events per minute for the activity rate indicator.
   */
  _calculateActivityRate(pastEvents) {
    if (pastEvents.length === 0) return 0

    const now = new Date()
    const fiveMinAgo = new Date(now.getTime() - 5 * 60 * 1000)

    const recentEvents = pastEvents.filter(e => new Date(e.timestamp) > fiveMinAgo)
    return recentEvents.length / 5 // events per minute over last 5 minutes
  },

  /**
   * Get the time bucket label for a given timestamp.
   * Returns bucket info with label and key for grouping.
   */
  _getTimeBucket(timestamp, now) {
    const eventTime = new Date(timestamp)
    const diffMs = now - eventTime
    const diffMin = diffMs / (1000 * 60)
    const diffHours = diffMs / (1000 * 60 * 60)

    // Define buckets
    if (diffMin < 1) {
      return { key: 'now', label: 'JUST NOW', order: 0 }
    } else if (diffMin < 5) {
      return { key: '5min', label: 'LAST 5 MINUTES', order: 1 }
    } else if (diffMin < 15) {
      return { key: '15min', label: '5-15 MINUTES AGO', order: 2 }
    } else if (diffMin < 30) {
      return { key: '30min', label: '15-30 MINUTES AGO', order: 3 }
    } else if (diffHours < 1) {
      return { key: '1hour', label: '30-60 MINUTES AGO', order: 4 }
    } else if (diffHours < 2) {
      return { key: '2hours', label: '1-2 HOURS AGO', order: 5 }
    } else if (diffHours < 6) {
      return { key: '6hours', label: '2-6 HOURS AGO', order: 6 }
    } else if (diffHours < 24) {
      return { key: 'today', label: 'EARLIER TODAY', order: 7 }
    } else if (diffHours < 48) {
      return { key: 'yesterday', label: 'YESTERDAY', order: 8 }
    } else {
      // Format as date
      const dateStr = eventTime.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
      return { key: `date-${dateStr}`, label: dateStr.toUpperCase(), order: 9 + diffHours }
    }
  },

  /**
   * Organize events into time buckets with gap indicators.
   * Returns array of items: { type: 'bucket-header' | 'event' | 'gap', ... }
   */
  _organizeEventsWithTimeContext(events) {
    if (events.length === 0) return []

    const now = new Date()
    const result = []
    let currentBucketKey = null
    let prevEventTime = null
    const GAP_THRESHOLD_MS = 5 * 60 * 1000 // 5 minutes

    events.forEach((event, idx) => {
      const eventTime = new Date(event.timestamp)
      const bucket = this._getTimeBucket(event.timestamp, now)

      // Check if we need a new bucket header
      if (bucket.key !== currentBucketKey) {
        result.push({
          type: 'bucket-header',
          key: bucket.key,
          label: bucket.label,
          order: bucket.order
        })
        currentBucketKey = bucket.key
      }

      // Check for significant time gap (only within same bucket or adjacent events)
      if (prevEventTime && idx > 0) {
        const gapMs = prevEventTime - eventTime // prev is more recent
        if (gapMs > GAP_THRESHOLD_MS) {
          const gapMinutes = Math.floor(gapMs / (1000 * 60))
          const gapText = this._formatGapDuration(gapMs)
          result.push({
            type: 'gap',
            duration: gapMs,
            durationText: gapText,
            minutes: gapMinutes
          })
        }
      }

      // Add the event
      result.push({
        type: 'event',
        event: event
      })

      prevEventTime = eventTime
    })

    return result
  },

  /**
   * Format a duration gap into human-readable text.
   */
  _formatGapDuration(ms) {
    const minutes = Math.floor(ms / (1000 * 60))
    const hours = Math.floor(ms / (1000 * 60 * 60))

    if (minutes < 60) {
      return `${minutes} min`
    } else if (hours < 24) {
      const remainingMin = minutes % 60
      return remainingMin > 0 ? `${hours}h ${remainingMin}m` : `${hours} hour${hours > 1 ? 's' : ''}`
    } else {
      const days = Math.floor(hours / 24)
      return `${days} day${days > 1 ? 's' : ''}`
    }
  },

  /**
   * Render a time bucket header.
   */
  _renderTimeBucketHeader(bucket) {
    return `
      <div class="stream-time-bucket" data-bucket="${bucket.key}">
        <div class="time-bucket-line"></div>
        <span class="time-bucket-label">${bucket.label}</span>
        <div class="time-bucket-line"></div>
      </div>
    `
  },

  /**
   * Render a time gap indicator.
   */
  _renderTimeGap(gap) {
    // Visual intensity based on gap duration
    const intensityClass = gap.minutes > 60 ? 'gap-large' : gap.minutes > 15 ? 'gap-medium' : 'gap-small'

    return `
      <div class="stream-time-gap ${intensityClass}">
        <div class="time-gap-connector">
          <div class="gap-line gap-line-top"></div>
          <div class="gap-indicator">
            <span class="gap-icon">⋮</span>
          </div>
          <div class="gap-line gap-line-bottom"></div>
        </div>
        <div class="time-gap-label">
          <span class="gap-duration">${gap.durationText}</span>
          <span class="gap-text">of quiet</span>
        </div>
      </div>
    `
  },

  /**
   * Render past events with time bucket headers and gap indicators.
   * Takes clustered items and adds temporal context.
   */
  _renderPastEventsWithTimeContext(clusteredItems) {
    if (clusteredItems.length === 0) return ''

    const now = new Date()
    const result = []
    let currentBucketKey = null
    let prevItemTime = null
    const GAP_THRESHOLD_MS = 5 * 60 * 1000 // 5 minutes

    clusteredItems.forEach((item, idx) => {
      // Get the representative timestamp for this item
      const itemTime = item.isCluster
        ? new Date(item.events[0].timestamp)
        : new Date(item.events[0].timestamp)
      const bucket = this._getTimeBucket(itemTime, now)

      // Check if we need a new bucket header
      if (bucket.key !== currentBucketKey) {
        result.push(this._renderTimeBucketHeader(bucket))
        currentBucketKey = bucket.key
      }

      // Check for significant time gap between items
      if (prevItemTime && idx > 0) {
        const gapMs = prevItemTime - itemTime // prev is more recent
        if (gapMs > GAP_THRESHOLD_MS) {
          const gapMinutes = Math.floor(gapMs / (1000 * 60))
          const gapText = this._formatGapDuration(gapMs)
          result.push(this._renderTimeGap({
            duration: gapMs,
            durationText: gapText,
            minutes: gapMinutes
          }))
        }
      }

      // Render the item (cluster or single event)
      if (item.isCluster) {
        result.push(this._renderEventCluster(item))
      } else {
        result.push(this._renderStreamEvent(item.events[0]))
      }

      prevItemTime = itemTime
    })

    return result.join('')
  },

  /**
   * Render a single enhanced stream event card.
   */
  _renderStreamEvent(event) {
    const timestamp = new Date(event.timestamp)
    const relativeTime = this._formatRelativeTime(timestamp)
    const statusClass = this._getStatusClass(event.status)
    const typeClass = `stream-event-${event.type}`
    const futureClass = event.is_future ? 'stream-event-future' : ''
    const statusIcon = this._getStatusIcon(event.status)

    // Determine priority/severity styling
    const isCritical = event.type === 'alarm' && (event.status === 'active' || event.status === 'error')
    const priorityClass = isCritical ? 'stream-event-critical' : ''
    const isCompleted = ['success', 'completed', 'cleared'].includes(event.status)
    const completedClass = isCompleted ? 'stream-event-completed' : ''

    // Check if this event is expanded
    const isExpanded = this.streamExpandedEvent === event.id

    return `
      <div class="stream-event ${typeClass} ${futureClass} ${priorityClass} ${completedClass} ${isExpanded ? 'expanded' : ''}"
           data-event-id="${event.id}">
        <!-- Timeline connector -->
        <div class="stream-event-connector">
          <div class="connector-line connector-line-top"></div>
          <div class="connector-node ${event.type}">
            ${event.is_future ? '◇' : '●'}
          </div>
          <div class="connector-line connector-line-bottom"></div>
        </div>

        <!-- Event Card -->
        <div class="stream-event-card">
          <!-- Card Header -->
          <div class="stream-event-header">
            <div class="stream-event-time-group">
              <span class="stream-event-time">${this._formatTimeUTC(timestamp)}</span>
              <span class="stream-event-relative" data-timestamp="${event.timestamp}">${relativeTime}</span>
            </div>
            <div class="stream-event-status ${statusClass}">
              <span class="status-icon">${statusIcon}</span>
              <span class="status-text">${event.status_label || event.status || ''}</span>
            </div>
          </div>

          <!-- Card Body -->
          <div class="stream-event-body">
            <span class="stream-event-type-badge ${event.type}">${event.type.toUpperCase().slice(0, 3)}</span>
            <span class="stream-event-title">${event.title}</span>
            ${event.target_name ? `
              <span class="stream-event-target">
                <span class="target-arrow">→</span>
                <span class="target-name">${event.target_name}</span>
              </span>
            ` : ''}
          </div>

          ${event.description ? `
            <div class="stream-event-description">${event.description}</div>
          ` : ''}

          <!-- Expandable Detail Section -->
          ${isExpanded ? `
            <div class="stream-event-detail">
              <div class="event-detail-section">
                <div class="detail-label">Event ID</div>
                <div class="detail-value mono">${event.id}</div>
              </div>
              ${event.target_id ? `
                <div class="event-detail-section">
                  <div class="detail-label">Target ID</div>
                  <div class="detail-value mono">${event.target_id}</div>
                </div>
              ` : ''}
              ${event.user_name ? `
                <div class="event-detail-section">
                  <div class="detail-label">Initiated By</div>
                  <div class="detail-value">${event.user_name}</div>
                </div>
              ` : ''}
              ${event.metadata && Object.keys(event.metadata).length > 0 ? `
                <div class="event-detail-section">
                  <div class="detail-label">Parameters</div>
                  <div class="detail-value mono">
                    <pre>${JSON.stringify(event.metadata, null, 2)}</pre>
                  </div>
                </div>
              ` : ''}
              <div class="event-detail-actions">
                ${event.type === 'command' ? `
                  <button class="detail-action-btn" data-action="rerun" data-event-id="${event.id}">
                    ↻ Re-run
                  </button>
                ` : ''}
                ${event.type === 'alarm' && event.status === 'active' ? `
                  <button class="detail-action-btn" data-action="acknowledge" data-event-id="${event.id}">
                    ✓ Acknowledge
                  </button>
                ` : ''}
                <button class="detail-action-btn secondary" data-action="copy" data-event-id="${event.id}">
                  ⎘ Copy
                </button>
              </div>
            </div>
          ` : ''}

          <!-- Expand indicator -->
          <div class="stream-event-expand-hint">
            <span class="expand-icon">${isExpanded ? '▲' : '▼'}</span>
          </div>
        </div>
      </div>
    `
  },

  /**
   * Render a cluster of related events.
   */
  _renderEventCluster(cluster) {
    const firstEvent = cluster.events[0]
    const timestamp = new Date(firstEvent.timestamp)
    const relativeTime = this._formatRelativeTime(timestamp)
    const typeClass = `stream-event-${cluster.type}`

    // Summarize statuses
    const statusCounts = {}
    cluster.events.forEach(e => {
      statusCounts[e.status] = (statusCounts[e.status] || 0) + 1
    })

    // Get unique targets
    const targets = [...new Set(cluster.events.map(e => e.target_name).filter(Boolean))]
    const targetSummary = targets.length > 3
      ? `${targets.slice(0, 3).join(', ')} +${targets.length - 3} more`
      : targets.join(', ')

    // Check if cluster is expanded
    const isExpanded = this.streamExpandedCluster === cluster.id

    return `
      <div class="stream-cluster ${typeClass} ${isExpanded ? 'expanded' : ''}"
           data-cluster-id="${cluster.id}">
        <!-- Timeline connector -->
        <div class="stream-event-connector">
          <div class="connector-line connector-line-top"></div>
          <div class="connector-node cluster ${cluster.type}">
            <span class="cluster-count">${cluster.count}</span>
          </div>
          <div class="connector-line connector-line-bottom"></div>
        </div>

        <!-- Cluster Card -->
        <div class="stream-cluster-card">
          <!-- Cluster Header -->
          <div class="stream-cluster-header">
            <div class="stream-event-time-group">
              <span class="stream-event-time">${this._formatTimeUTC(timestamp)}</span>
              <span class="stream-event-relative" data-timestamp="${firstEvent.timestamp}">${relativeTime}</span>
              <span class="cluster-duration">over ${this._formatDuration(cluster.endTime - cluster.startTime)}</span>
            </div>
            <div class="cluster-status-summary">
              ${Object.entries(statusCounts).map(([status, count]) => `
                <span class="cluster-status-badge ${this._getStatusClass(status)}">
                  ${count} ${status}
                </span>
              `).join('')}
            </div>
          </div>

          <!-- Cluster Summary -->
          <div class="stream-cluster-body">
            <span class="stream-event-type-badge ${cluster.type}">${cluster.type.toUpperCase().slice(0, 3)}</span>
            <span class="cluster-title">
              <strong>${cluster.count}</strong> × ${cluster.title}
            </span>
          </div>

          <div class="cluster-targets">
            <span class="targets-label">Targets:</span>
            <span class="targets-list">${targetSummary || 'Multiple targets'}</span>
          </div>

          <!-- Expanded Events List -->
          ${isExpanded ? `
            <div class="cluster-events-expanded">
              ${cluster.events.map(e => `
                <div class="cluster-event-item" data-event-id="${e.id}">
                  <span class="cluster-event-time">${this._formatTimeUTC(new Date(e.timestamp))}</span>
                  <span class="cluster-event-target">${e.target_name || '-'}</span>
                  <span class="cluster-event-status ${this._getStatusClass(e.status)}">
                    ${this._getStatusIcon(e.status)} ${e.status}
                  </span>
                </div>
              `).join('')}
            </div>
          ` : ''}

          <!-- Expand indicator -->
          <div class="stream-cluster-expand">
            <span class="expand-text">${isExpanded ? 'Collapse' : `Expand ${cluster.count} events`}</span>
            <span class="expand-icon">${isExpanded ? '▲' : '▼'}</span>
          </div>
        </div>
      </div>
    `
  },

  /**
   * Format a duration in milliseconds to a human-readable string.
   */
  _formatDuration(ms) {
    const seconds = Math.floor(ms / 1000)
    if (seconds < 60) return `${seconds}s`
    const minutes = Math.floor(seconds / 60)
    if (minutes < 60) return `${minutes}m ${seconds % 60}s`
    const hours = Math.floor(minutes / 60)
    return `${hours}h ${minutes % 60}m`
  },

  _renderMatrixViewContent() {
    const now = new Date()
    const filteredEvents = this.timelineEvents.filter(e => this.timelineTypeFilter.has(e.type))
    const bucketMs = this.matrixTimeBucket * 60 * 1000

    // Calculate time range: 2 hours past to 1 hour future
    const startTime = new Date(now.getTime() - 2 * 60 * 60 * 1000)
    const endTime = new Date(now.getTime() + 1 * 60 * 60 * 1000)

    // Generate time buckets
    const buckets = []
    let bucketTime = new Date(Math.floor(startTime.getTime() / bucketMs) * bucketMs)
    while (bucketTime <= endTime) {
      buckets.push(new Date(bucketTime))
      bucketTime = new Date(bucketTime.getTime() + bucketMs)
    }

    // Group events by target
    const targetGroups = new Map()
    filteredEvents.forEach(event => {
      const targetId = event.target_id || 'unknown'
      const targetName = event.target_name || targetId
      if (!targetGroups.has(targetId)) {
        targetGroups.set(targetId, { name: targetName, events: [] })
      }
      targetGroups.get(targetId).events.push(event)
    })

    // Also include targets from the targets list that might not have events
    this.targets.forEach(target => {
      if (!targetGroups.has(target.id)) {
        targetGroups.set(target.id, { name: target.name || target.identifier, events: [] })
      }
    })

    // Sort targets by name
    const sortedTargets = Array.from(targetGroups.entries())
      .sort((a, b) => (a[1].name || '').localeCompare(b[1].name || ''))
      .slice(0, 20) // Limit to 20 targets for performance

    // Find NOW bucket index
    const nowBucketIndex = buckets.findIndex(b =>
      now >= b && now < new Date(b.getTime() + bucketMs)
    )

    return `
      <div class="timeline-matrix">
        <div class="timeline-matrix-header">
          <div class="timeline-matrix-corner">TARGET</div>
          ${buckets.map((bucket, idx) => `
            <div class="timeline-matrix-time ${idx === nowBucketIndex ? 'now-bucket' : ''}"
                 title="${bucket.toISOString()}">
              ${this._formatTimeUTC(bucket).slice(0, 5)}
            </div>
          `).join('')}
        </div>
        <div class="timeline-matrix-body">
          ${sortedTargets.length > 0 ? sortedTargets.map(([targetId, group]) => {
            // Bucket events for this target
            const eventBuckets = buckets.map(bucketStart => {
              const bucketEnd = new Date(bucketStart.getTime() + bucketMs)
              return group.events.filter(e => {
                const eventTime = new Date(e.timestamp)
                return eventTime >= bucketStart && eventTime < bucketEnd
              })
            })

            return `
              <div class="timeline-matrix-row" data-target-id="${targetId}">
                <div class="timeline-matrix-label" title="${group.name}">${group.name}</div>
                ${eventBuckets.map((cellEvents, idx) => {
                  const hasCmd = cellEvents.some(e => e.type === 'command')
                  const hasAlm = cellEvents.some(e => e.type === 'alarm')
                  const hasProc = cellEvents.some(e => e.type === 'procedure')
                  const hasAuto = cellEvents.some(e => e.type === 'automation')
                  const hasError = cellEvents.some(e => e.status === 'error' || e.status === 'failed')
                  const isFuture = cellEvents.some(e => e.is_future)

                  return `
                    <div class="timeline-matrix-cell ${idx === nowBucketIndex ? 'now-bucket' : ''} ${cellEvents.length > 0 ? 'has-events' : ''}"
                         data-target-id="${targetId}"
                         data-bucket-index="${idx}"
                         title="${cellEvents.length} events">
                      ${hasCmd ? `<span class="matrix-dot matrix-dot-cmd ${hasError ? 'has-error' : ''} ${isFuture ? 'is-future' : ''}">·</span>` : ''}
                      ${hasAlm ? `<span class="matrix-dot matrix-dot-alm ${hasError ? 'has-error' : ''}">●</span>` : ''}
                      ${hasProc ? `<span class="matrix-dot matrix-dot-proc ${hasError ? 'has-error' : ''} ${isFuture ? 'is-future' : ''}">▲</span>` : ''}
                      ${hasAuto ? `<span class="matrix-dot matrix-dot-auto ${hasError ? 'has-error' : ''}">◆</span>` : ''}
                    </div>
                  `
                }).join('')}
              </div>
            `
          }).join('') : `
            <div class="timeline-empty-state">No targets available</div>
          `}
        </div>

        <!-- Selected Cell Detail -->
        ${this.matrixSelectedCell ? this._renderMatrixCellDetail() : `
          <div class="timeline-matrix-detail">
            <div class="timeline-matrix-detail-empty">Click a cell to see events</div>
          </div>
        `}

        <!-- Legend -->
        <div class="timeline-matrix-legend">
          <span class="legend-item"><span class="matrix-dot matrix-dot-cmd">·</span> CMD</span>
          <span class="legend-item"><span class="matrix-dot matrix-dot-alm">●</span> ALM</span>
          <span class="legend-item"><span class="matrix-dot matrix-dot-proc">▲</span> PROC</span>
          <span class="legend-item"><span class="matrix-dot matrix-dot-auto">◆</span> AUTO</span>
          <span class="legend-item"><span class="matrix-dot has-error">!</span> ERROR</span>
        </div>
      </div>
    `
  },

  _renderMatrixCellDetail() {
    if (!this.matrixSelectedCell) return ''

    const { targetId, bucketIndex } = this.matrixSelectedCell
    const bucketMs = this.matrixTimeBucket * 60 * 1000
    const startTime = new Date(Date.now() - 2 * 60 * 60 * 1000)
    const bucketStart = new Date(Math.floor(startTime.getTime() / bucketMs) * bucketMs + bucketIndex * bucketMs)
    const bucketEnd = new Date(bucketStart.getTime() + bucketMs)

    const cellEvents = this.timelineEvents.filter(e => {
      const eventTime = new Date(e.timestamp)
      return (e.target_id === targetId || (!e.target_id && targetId === 'unknown')) &&
             eventTime >= bucketStart && eventTime < bucketEnd &&
             this.timelineTypeFilter.has(e.type)
    }).sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp))

    const target = this.targets.find(t => t.id === targetId)
    const targetName = target?.name || target?.identifier || targetId

    return `
      <div class="timeline-matrix-detail">
        <div class="timeline-matrix-detail-header">
          <span class="detail-target">${targetName}</span>
          <span class="detail-time">${this._formatTimeUTC(bucketStart)} - ${this._formatTimeUTC(bucketEnd)}</span>
        </div>
        <div class="timeline-matrix-detail-events">
          ${cellEvents.length > 0 ? cellEvents.map(e => this._renderTimelineEvent(e)).join('') :
            '<div class="timeline-empty-state">No events in this cell</div>'
          }
        </div>
      </div>
    `
  },

  _renderLanesViewContent() {
    const now = new Date()
    const rangeMs = this.lanesTimeRange * 60 * 60 * 1000

    // Calculate view window based on offset (for horizontal panning)
    // Show 80% past and 20% future (viewCenter is at 80% position)
    const viewCenter = new Date(now.getTime() + this.lanesViewOffset)
    const pastMs = rangeMs * 1.6    // 80% of total range
    const futureMs = rangeMs * 0.4  // 20% of total range
    const startTime = new Date(viewCenter.getTime() - pastMs)
    const endTime = new Date(viewCenter.getTime() + futureMs)
    const totalMs = endTime - startTime

    const filteredEvents = this.timelineEvents.filter(e => this.timelineTypeFilter.has(e.type))

    // Use only explicitly selected targets (no auto-pin to avoid state mismatch)
    const pinnedTargets = this.lanesPinnedTargets

    // The scrubber position is draggable within the timeline
    // viewTime is calculated based on where the scrubber sits within the visible window
    const scrubberPosition = this.lanesScrubberPosition
    const viewTime = new Date(startTime.getTime() + (totalMs * scrubberPosition / 100))
    const isViewingNow = Math.abs(viewTime - now) < 60000  // Scrubber within 1 minute of NOW
    const scrubberLabel = isViewingNow ? 'NOW' : this._formatTimeUTC(viewTime)

    // Calculate where real NOW is (for showing an indicator when scrolled away)
    const realNowPosition = ((now - startTime) / totalMs) * 100
    const realNowInView = realNowPosition >= 0 && realNowPosition <= 100

    // Check if there are events near the current view time (for handle pulse indicator)
    const eventWindowMs = 60000 // ±1 minute
    const hasNearbyEvents = filteredEvents.some(event => {
      const eventTime = new Date(event.timestamp)
      return Math.abs(eventTime - viewTime) <= eventWindowMs
    })

    // Generate time markers
    const timeMarkers = []
    const markerInterval = this.lanesTimeRange <= 2 ? 30 : this.lanesTimeRange <= 6 ? 60 : 120 // minutes
    let markerTime = new Date(Math.ceil(startTime.getTime() / (markerInterval * 60000)) * (markerInterval * 60000))
    while (markerTime <= endTime) {
      const position = ((markerTime - startTime) / totalMs) * 100
      timeMarkers.push({ time: markerTime, position })
      markerTime = new Date(markerTime.getTime() + markerInterval * 60000)
    }

    return `
      <div class="timeline-lanes">
        <div class="lanes-split-layout">
          <!-- Left Panel: Target Selector -->
          ${this._renderLanesTargetPickerPanel()}

          <!-- Resize Handle -->
          <div class="lanes-resize-handle" id="lanes-resize-handle"></div>

          <!-- Right Panel: Lanes Content -->
          <div class="lanes-main-panel">
            <!-- HUD Lanes Panel -->
            <div class="lanes-hud-panel">
              <!-- Panel Header -->
              <div class="lanes-panel-header">
                <div class="lanes-panel-title">
                  <span class="lanes-panel-label">TARGET LANES</span>
                  <span class="lanes-panel-count">${pinnedTargets.length} TARGETS</span>
                </div>
                <div class="lanes-panel-controls">
                  <select id="lanes-range" class="lanes-range-select">
                    <option value="2" ${this.lanesTimeRange === 2 ? 'selected' : ''}>±2h</option>
                    <option value="6" ${this.lanesTimeRange === 6 ? 'selected' : ''}>±6h</option>
                    <option value="12" ${this.lanesTimeRange === 12 ? 'selected' : ''}>±12h</option>
                    <option value="24" ${this.lanesTimeRange === 24 ? 'selected' : ''}>±24h</option>
                  </select>
                </div>
              </div>

              <!-- Time axis -->
          <div class="timeline-lanes-axis">
            <div class="lanes-axis-label">TIME</div>
            <div class="lanes-axis-track">
              ${timeMarkers.map(m => `
                <div class="lanes-time-marker" style="left: ${m.position}%">
                  <span class="lanes-time-label">${this._formatTimeUTC(m.time).slice(0, 5)}</span>
                </div>
              `).join('')}
              <!-- View marker at 80% position (80% past, 20% future) -->
              <div class="lanes-view-marker ${isViewingNow ? '' : 'is-historical'}" style="left: ${scrubberPosition}%">
                <div class="lanes-now-line"></div>
                <span class="lanes-now-label">${scrubberLabel}</span>
              </div>
              <!-- Real NOW indicator when scrolled away -->
              ${!isViewingNow && realNowInView ? `
                <div class="lanes-real-now-marker" style="left: ${realNowPosition}%">
                  <div class="lanes-real-now-line"></div>
                </div>
              ` : ''}
              ${!isViewingNow && !realNowInView ? `
                <div class="lanes-now-indicator ${realNowPosition > 100 ? 'right' : 'left'}">
                  <button class="lanes-jump-now-btn" title="Jump to NOW">
                    ${realNowPosition > 100 ? '▶' : '◀'} NOW
                  </button>
                </div>
              ` : ''}
            </div>
          </div>

          <!-- Lanes Body -->
          <div class="timeline-lanes-body">
          <!-- Single vertical scrub line spanning all lanes at 80% position -->
          <div class="lanes-scrub-line ${!isViewingNow ? 'is-historical' : ''}" style="left: calc(120px + (100% - 120px) * ${scrubberPosition} / 100)"></div>
          <!-- Real NOW line in body when scrolled away -->
          ${!isViewingNow && realNowInView ? `
            <div class="lanes-real-now-line-body" style="left: calc(120px + (100% - 120px) * ${realNowPosition} / 100)"></div>
          ` : ''}

          <div class="timeline-lanes-container">
            ${pinnedTargets.length > 0 ? pinnedTargets.map(targetId => {
              // Handle type conversion for target matching (dataset returns strings)
              const target = this.targets.find(t => String(t.id) === String(targetId))
              const targetName = targetId === '__SYSTEM__' ? '◆ SYSTEM' : (target?.name || target?.identifier || targetId)
              const targetEvents = filteredEvents
                .filter(e => {
                  // SYSTEM lane shows events without target_id
                  if (targetId === '__SYSTEM__') {
                    return !e.target_id
                  }
                  // Compare as strings to handle type mismatches
                  return String(e.target_id) === String(targetId)
                })
                .filter(e => {
                  const eventTime = new Date(e.timestamp)
                  return eventTime >= startTime && eventTime <= endTime
                })

              return `
                <div class="timeline-lane" data-target-id="${targetId}">
                  <div class="lane-header">
                    <span class="lane-target-name">${targetName}</span>
                    <button class="lane-unpin" data-target-id="${targetId}" title="Remove lane">×</button>
                  </div>
                  <div class="lane-track">
                    ${targetEvents.map(event => {
                      const eventTime = new Date(event.timestamp)
                      const position = ((eventTime - startTime) / totalMs) * 100
                      const typeClass = `lane-event-${event.type}`
                      const statusClass = event.status === 'error' || event.status === 'failed' ? 'has-error' : ''
                      const futureClass = event.is_future ? 'is-future' : ''

                      return `
                        <div class="lane-event ${typeClass} ${statusClass} ${futureClass}"
                             style="left: ${position}%"
                             data-event-id="${event.id}"
                             title="${event.title} - ${this._formatTimeUTC(eventTime)}">
                          ${this._getLaneEventSymbol(event)}
                        </div>
                      `
                    }).join('')}
                  </div>
                </div>
              `
            }).join('') : `
              <div class="timeline-empty-state">
                Select targets from the panel on the left to show lanes.
              </div>
            `}
          </div>

          <!-- Fleet Summary Sparkline -->
          <div class="timeline-lanes-summary">
            <div class="lane-header">
              <span class="lane-target-name">FLEET</span>
            </div>
            <div class="lane-track lane-summary-track">
              ${this._renderFleetActivitySparkline(filteredEvents, startTime, endTime, totalMs)}
            </div>
          </div>
        </div>

          <!-- HUD Corner Accents for Lanes Panel -->
          <div class="lanes-hud-corners"></div>
        </div>

        <!-- Fleet Activity Panel (Stage Panel style) -->
        <div class="lanes-activity-panel ${this.lanesActivityExpanded ? 'expanded' : 'minimized'}${!this.lanesActivityExpanded && hasNearbyEvents ? ' has-events' : ''}"
             style="${this.lanesActivityHeight ? `--activity-height: ${this.lanesActivityHeight}px;` : ''}">
          <div class="lanes-activity-resize-handle" id="activity-resize-handle"></div>
          <div class="lanes-activity-header" id="activity-panel-toggle">
            <div class="lanes-activity-title">
              <span class="lanes-activity-label">FLEET ACTIVITY</span>
              ${this.lanesSelectedEvent ? `
                <span class="lanes-activity-badge">EVENT DETAIL</span>
              ` : `
                <span class="lanes-activity-hint">${this.lanesActivityExpanded ? 'Click header to collapse' : 'Click to expand'}</span>
              `}
            </div>
            <div class="lanes-activity-actions">
              ${!isViewingNow ? `
                <button class="lanes-return-now-btn" title="Return to NOW">
                  <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
                  </svg>
                  <span>NOW</span>
                </button>
              ` : ''}
            </div>
          </div>
          ${this.lanesActivityExpanded ? `
            <div class="lanes-activity-body">
              ${this._renderLanesActivityContent(filteredEvents, startTime, endTime)}
            </div>
          ` : ''}
          <!-- HUD Corner Accents -->
          <div class="lanes-activity-corners"></div>
        </div>
          </div>
        </div>
      </div>
    `
  },

  _getLaneEventSymbol(event) {
    const symbols = {
      command: '·',
      alarm: '●',
      procedure: '▲',
      automation: '◆'
    }
    return symbols[event.type] || '·'
  },

  _renderFleetActivitySparkline(events, startTime, endTime, totalMs) {
    // Create activity buckets
    const bucketCount = 50
    const bucketMs = totalMs / bucketCount
    const buckets = new Array(bucketCount).fill(0)

    events.forEach(event => {
      const eventTime = new Date(event.timestamp)
      if (eventTime >= startTime && eventTime <= endTime) {
        const bucketIndex = Math.floor((eventTime - startTime) / bucketMs)
        if (bucketIndex >= 0 && bucketIndex < bucketCount) {
          buckets[bucketIndex]++
        }
      }
    })

    const maxCount = Math.max(...buckets, 1)

    return buckets.map((count, idx) => {
      const height = (count / maxCount) * 100
      const left = (idx / bucketCount) * 100
      const width = 100 / bucketCount
      return `
        <div class="sparkline-bar"
             style="left: ${left}%; width: ${width}%; height: ${height}%"
             title="${count} events">
        </div>
      `
    }).join('')
  },

  /**
   * Render the Lanes target selector panel (side panel like Stream View).
   */
  _renderLanesTargetPickerPanel() {
    // Convert to strings for consistent comparison (dataset attributes return strings)
    const pinnedSet = new Set(this.lanesPinnedTargets.map(String))

    // Gather ALL targets from events and available targets list (use string IDs for consistency)
    const targetMap = new Map()
    this.timelineEvents.forEach(e => {
      if (e.target_id && e.target_name) {
        const strId = String(e.target_id)
        targetMap.set(strId, {
          id: strId,
          name: e.target_name,
          status: e.target_status || 'online'
        })
      }
    })

    const availableTargets = JSON.parse(this.el.dataset.targets || '[]')
    availableTargets.forEach(t => {
      const strId = String(t.id)
      if (!targetMap.has(strId)) {
        targetMap.set(strId, {
          id: strId,
          name: t.name,
          status: t.status || 'online'
        })
      }
    })

    const targets = Array.from(targetMap.values()).sort((a, b) =>
      a.name.localeCompare(b.name)
    )

    // Apply search filter
    const filteredTargets = this.lanesTargetSearch
      ? targets.filter(t =>
          t.name.toLowerCase().includes(this.lanesTargetSearch.toLowerCase())
        )
      : targets

    // Count system events
    const systemEventCount = this.timelineEvents.filter(e => !e.target_id).length
    const systemSelected = pinnedSet.has('__SYSTEM__')

    // Calculate selected count
    const totalCount = targets.length + 1 // +1 for SYSTEM
    const selectedCount = pinnedSet.size
    const countText = `${selectedCount} of ${totalCount}`

    return `
      <div class="lanes-target-picker-panel" style="flex: 0 0 ${this.lanesTargetPanelWidth}px;">
        <div class="lanes-target-picker-header">
          <div class="lanes-picker-title-row">
            <span class="lanes-picker-title">FILTER BY TARGET</span>
            <span class="lanes-picker-count">${countText}</span>
          </div>
        </div>

        <div class="lanes-target-search-wrapper">
          <input type="text"
                 class="lanes-target-search"
                 id="lanes-target-search"
                 placeholder="Filter targets..."
                 value="${this.lanesTargetSearch}" />
        </div>

        <div class="lanes-target-grid" id="lanes-target-grid">
          ${this._renderLanesTargetGrid(filteredTargets, systemEventCount, systemSelected, pinnedSet)}
        </div>

        <div class="lanes-picker-actions">
          <button class="lanes-picker-action" id="lanes-select-all">Select All</button>
          <button class="lanes-picker-action" id="lanes-clear-all">Clear</button>
        </div>
      </div>
    `
  },

  /**
   * Render the target grid cells for the lanes picker.
   */
  _renderLanesTargetGrid(targets, systemEventCount, systemSelected, pinnedSet) {
    // SYSTEM pseudo-target (for events without target_id)
    const systemCell = `
      <div class="lanes-target-cell system-target ${systemSelected ? 'selected' : ''}"
           data-target-id="__SYSTEM__"
           title="System events (${systemEventCount} events)">
        <span class="lanes-target-name">◆ SYSTEM</span>
      </div>
    `

    // Regular target cells
    const targetCells = targets.map(target => {
      const statusClass = `status-${target.status || 'online'}`
      const isSelected = pinnedSet.has(String(target.id))
      return `
        <div class="lanes-target-cell ${statusClass} ${isSelected ? 'selected' : ''}"
             data-target-id="${target.id}"
             title="${target.name}">
          <span class="lanes-target-name">${target.name}</span>
        </div>
      `
    }).join('')

    if (targets.length === 0 && systemEventCount === 0) {
      return `<div class="lanes-picker-empty">No targets available</div>`
    }

    return systemCell + targetCells
  },

  /**
   * Render the Fleet Activity panel content based on current state.
   */
  _renderLanesActivityContent(filteredEvents, startTime, endTime) {
    const isViewingNow = Math.abs(this.lanesViewOffset) < 60000

    // If viewing historical time (scrolled away from NOW), show events near view center
    if (!isViewingNow) {
      const now = new Date()
      const viewCenterTime = new Date(now.getTime() + this.lanesViewOffset)
      const windowMs = 60000 // ±1 minute window
      const nearbyEvents = filteredEvents.filter(event => {
        const eventTime = new Date(event.timestamp)
        return Math.abs(eventTime - viewCenterTime) <= windowMs
      })

      if (nearbyEvents.length === 0) {
        return `
          <div class="lanes-activity-empty">
            <span class="empty-icon">○</span>
            <span class="empty-text">No events at this time</span>
          </div>
        `
      }

      return `
        <div class="lanes-activity-grid">
          ${nearbyEvents.map(event => this._renderActivityCard(event)).join('')}
        </div>
      `
    }

    // If an event is selected, show its detail
    if (this.lanesSelectedEvent) {
      const event = this.timelineEvents.find(e => e.id === this.lanesSelectedEvent)
      if (event) {
        return this._renderActivityEventDetail(event)
      }
    }

    // Default empty state
    return `
      <div class="lanes-activity-empty">
        <span class="empty-icon">⊙</span>
        <span class="empty-text">Scroll the timeline or click an event to see activity</span>
      </div>
    `
  },

  /**
   * Render a single activity card (for scrubbed events grid).
   */
  _renderActivityCard(event) {
    const target = this.targets.find(t => t.id === event.target_id)
    const targetName = target?.name || target?.identifier || 'Unknown'
    const relativeTime = this._formatRelativeTime(new Date(event.timestamp))

    return `
      <div class="activity-card type-${event.type}" data-event-id="${event.id}">
        <div class="activity-card-header">
          <span class="activity-card-type">${event.type.toUpperCase().slice(0, 3)}</span>
          <span class="activity-card-time">${relativeTime}</span>
        </div>
        <div class="activity-card-title">${event.title}</div>
        <div class="activity-card-meta">
          <span class="activity-card-target">${targetName}</span>
          <span class="activity-card-status ${this._getStatusClass(event.status)}">${event.status_label || event.status}</span>
        </div>
      </div>
    `
  },

  /**
   * Render detailed view of a selected event.
   */
  _renderActivityEventDetail(event) {
    const target = this.targets.find(t => t.id === event.target_id)
    const targetName = target?.name || target?.identifier || event.target_id || 'Unknown'

    return `
      <div class="activity-detail">
        <div class="activity-detail-header">
          <span class="activity-detail-type type-${event.type}">${event.type.toUpperCase()}</span>
          <span class="activity-detail-title">${event.title}</span>
        </div>
        <div class="activity-detail-grid">
          <div class="activity-detail-row">
            <span class="detail-label">TIME</span>
            <span class="detail-value">${this._formatTimeUTC(new Date(event.timestamp))}</span>
          </div>
          <div class="activity-detail-row">
            <span class="detail-label">TARGET</span>
            <span class="detail-value">${targetName}</span>
          </div>
          <div class="activity-detail-row">
            <span class="detail-label">STATUS</span>
            <span class="detail-value ${this._getStatusClass(event.status)}">${event.status_label || event.status}</span>
          </div>
          ${event.description ? `
            <div class="activity-detail-row full-width">
              <span class="detail-label">DETAILS</span>
              <span class="detail-value">${event.description}</span>
            </div>
          ` : ''}
        </div>
      </div>
    `
  },

  _renderLanesEventDetail() {
    const event = this.timelineEvents.find(e => e.id === this.lanesSelectedEvent)
    if (!event) return ''

    const target = this.targets.find(t => t.id === event.target_id)
    const targetName = target?.name || target?.identifier || event.target_id || 'Unknown'

    return `
      <div class="timeline-lanes-detail">
        <div class="lanes-detail-header">
          <span class="detail-type type-${event.type}">${event.type.toUpperCase()}</span>
          <span class="detail-title">${event.title}</span>
          <span class="detail-time">${this._formatTimeUTC(new Date(event.timestamp))}</span>
        </div>
        <div class="lanes-detail-body">
          <div class="detail-row">
            <span class="detail-label">Target:</span>
            <span class="detail-value">${targetName}</span>
          </div>
          <div class="detail-row">
            <span class="detail-label">Status:</span>
            <span class="detail-value ${this._getStatusClass(event.status)}">${event.status_label || event.status}</span>
          </div>
          ${event.description ? `
            <div class="detail-row">
              <span class="detail-label">Details:</span>
              <span class="detail-value">${event.description}</span>
            </div>
          ` : ''}
        </div>
      </div>
    `
  },

  _hideTimelineMode() {
    const dashboard = this.panelLayout?.elements?.dashboard
    if (!dashboard) return

    const timelineContainer = dashboard.querySelector(".timeline-mode-container")
    if (timelineContainer) {
      timelineContainer.innerHTML = ""
    }
  },

  _renderTimelineEvent(event) {
    const timestamp = new Date(event.timestamp)
    const relativeTime = this._formatRelativeTime(timestamp)
    const statusClass = this._getStatusClass(event.status)
    const typeClass = `timeline-event-${event.type}`
    const futureClass = event.is_future ? 'timeline-event-future' : ''
    const statusIcon = this._getStatusIcon(event.status)

    return `
      <div class="timeline-event ${typeClass} ${futureClass} ${statusClass}" data-event-id="${event.id}">
        <div class="timeline-event-marker">
          ${event.is_future ? '◇' : '●'}
        </div>
        <div class="timeline-event-content">
          <div class="timeline-event-header">
            <span class="timeline-event-time">${this._formatTimeUTC(timestamp)}</span>
            <span class="timeline-event-relative" data-timestamp="${event.timestamp}">${relativeTime}</span>
          </div>
          <div class="timeline-event-body">
            <span class="timeline-event-type-badge timeline-badge-${event.type}">${event.type.toUpperCase().slice(0, 3)}</span>
            <span class="timeline-event-title">${event.title}</span>
            ${event.target_name ? `<span class="timeline-event-target">→ ${event.target_name}</span>` : ''}
          </div>
          ${event.description ? `<div class="timeline-event-description">${event.description}</div>` : ''}
        </div>
        <div class="timeline-event-status ${statusClass}">
          ${statusIcon} ${event.status_label || ''}
        </div>
      </div>
    `
  },

  _bindTimelineModeEvents(container) {
    // View tab switching
    container.querySelectorAll('.timeline-view-tab').forEach(tab => {
      tab.addEventListener('click', () => {
        const view = tab.dataset.view
        if (view && view !== this.timelineView) {
          this.timelineView = view
          this._renderTimelineMode()
        }
      })
    })

    // Event type filter toggles
    container.querySelectorAll('.timeline-filter-toggle').forEach(toggle => {
      toggle.addEventListener('click', () => {
        const type = toggle.dataset.type
        if (this.timelineTypeFilter.has(type)) {
          this.timelineTypeFilter.delete(type)
          toggle.classList.remove('active')
        } else {
          this.timelineTypeFilter.add(type)
          toggle.classList.add('active')
        }
        this._renderTimelineMode()
      })
    })

    // Stream view controls
    container.querySelector('#timeline-pause')?.addEventListener('click', () => {
      this.timelinePaused = !this.timelinePaused
      this._renderTimelineMode()
    })

    container.querySelector('#timeline-jump-now')?.addEventListener('click', () => {
      const nowMarker = container.querySelector('.timeline-now-marker')
      if (nowMarker) {
        nowMarker.scrollIntoView({ behavior: 'smooth', block: 'center' })
      }
    })

    // Matrix view controls
    container.querySelector('#matrix-bucket')?.addEventListener('change', (e) => {
      this.matrixTimeBucket = parseInt(e.target.value, 10)
      this.matrixSelectedCell = null
      this._renderTimelineMode()
    })

    // Matrix cell clicks
    container.querySelectorAll('.timeline-matrix-cell').forEach(cell => {
      cell.addEventListener('click', () => {
        const targetId = cell.dataset.targetId
        const bucketIndex = parseInt(cell.dataset.bucketIndex, 10)
        this.matrixSelectedCell = { targetId, bucketIndex }
        this._renderTimelineMode()
      })
    })

    // Lanes view controls
    container.querySelector('#lanes-range')?.addEventListener('change', (e) => {
      this.lanesTimeRange = parseInt(e.target.value, 10)
      this._renderTimelineMode()
    })

    // Target picker search input
    container.querySelector('#lanes-target-search')?.addEventListener('input', (e) => {
      this.lanesTargetSearch = e.target.value
      this._renderTimelineMode()
    })

    // Target picker cell clicks - toggle selection (like Stream View)
    container.querySelectorAll('.lanes-target-cell').forEach(cell => {
      cell.addEventListener('click', () => {
        const targetId = cell.dataset.targetId
        const index = this.lanesPinnedTargets.indexOf(targetId)
        if (index >= 0) {
          // Already selected - remove it
          this.lanesPinnedTargets.splice(index, 1)
        } else {
          // Not selected - add it
          this.lanesPinnedTargets.push(targetId)
        }
        this._renderTimelineMode()
      })
    })

    // Select All button
    container.querySelector('#lanes-select-all')?.addEventListener('click', () => {
      // Gather all target IDs (convert to strings for consistency)
      const targetMap = new Map()
      this.timelineEvents.forEach(e => {
        if (e.target_id) targetMap.set(String(e.target_id), true)
      })
      const availableTargets = JSON.parse(this.el.dataset.targets || '[]')
      availableTargets.forEach(t => targetMap.set(String(t.id), true))

      this.lanesPinnedTargets = ['__SYSTEM__', ...Array.from(targetMap.keys())]
      this._renderTimelineMode()
    })

    // Clear button
    container.querySelector('#lanes-clear-all')?.addEventListener('click', () => {
      this.lanesPinnedTargets = []
      this._renderTimelineMode()
    })

    // Lanes panel resize handle
    this._bindLanesPanelResize(container)

    // Lane unpin buttons
    container.querySelectorAll('.lane-unpin').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation()
        const targetId = btn.dataset.targetId
        this.lanesPinnedTargets = this.lanesPinnedTargets.filter(id => id !== targetId)
        this._renderTimelineMode()
      })
    })

    // Lane event clicks
    container.querySelectorAll('.lane-event').forEach(eventEl => {
      eventEl.addEventListener('click', () => {
        const eventId = eventEl.dataset.eventId
        this.lanesSelectedEvent = eventId
        this.lanesActivityExpanded = true  // Auto-expand to show detail
        this._renderTimelineMode()
      })
    })

    // View marker drag handling for time scrubbing
    const viewMarker = container.querySelector('.lanes-view-marker')
    if (viewMarker) {
      viewMarker.addEventListener('mousedown', (e) => this._startLanesScrubbing(e))
      viewMarker.addEventListener('dblclick', () => this._returnToNow())
    }

    // Return to NOW button (in scrubbing detail panel)
    container.querySelector('.lanes-return-now')?.addEventListener('click', (e) => {
      e.stopPropagation()
      this._returnToNow()
    })

    container.querySelector('.lanes-return-now-btn')?.addEventListener('click', (e) => {
      e.stopPropagation()
      this._returnToNow()
    })

    // Activity panel toggle expand/collapse
    container.querySelector('#activity-panel-toggle')?.addEventListener('click', (e) => {
      // Don't toggle if clicking on a button
      if (e.target.closest('button')) return
      this.lanesActivityExpanded = !this.lanesActivityExpanded
      this._renderTimelineMode()
    })

    // Activity panel resize handle
    this._bindActivityPanelResize(container)

    // Lanes horizontal panning via wheel scroll
    const lanesBody = container.querySelector('.timeline-lanes-body')
    if (lanesBody) {
      lanesBody.addEventListener('wheel', (e) => {
        // Don't scroll while dragging
        if (this.lanesIsDragging || this.lanesIsPanning) return

        // Horizontal scroll with shift+wheel or horizontal trackpad gesture
        if (e.shiftKey || Math.abs(e.deltaX) > Math.abs(e.deltaY)) {
          e.preventDefault()

          // Convert scroll delta to time offset
          // Sensitivity: ~500px of scroll = full range width
          const scrollSensitivity = (this.lanesTimeRange * 60 * 60 * 1000 * 2) / 500
          const delta = (e.deltaX || e.deltaY) * scrollSensitivity

          this.lanesViewOffset += delta
          this._checkLanesNeedMoreEvents()
          this._renderTimelineMode()
        }
      }, { passive: false })

      // Drag panning on lanes body
      lanesBody.addEventListener('mousedown', (e) => {
        // Only initiate pan on left click and not on interactive elements
        if (e.button !== 0) return
        if (this.lanesIsDragging || this.lanesIsPanning) return
        if (e.target.closest('.lane-event, .lane-unpin, .lanes-view-marker, button')) return

        this._startLanesPanning(e, lanesBody)
      })
    }

    // Jump to NOW button (when panned away)
    container.querySelector('.lanes-jump-now-btn')?.addEventListener('click', () => {
      this.lanesViewOffset = 0
      this._renderTimelineMode()
    })

    // Enhanced Stream view event handlers
    // Event card expand/collapse
    container.querySelectorAll('.stream-event').forEach(eventEl => {
      eventEl.addEventListener('click', (e) => {
        // Don't toggle if clicking action buttons
        if (e.target.closest('.detail-action-btn')) return

        // Preserve scroll position before re-render
        const scrollContainer = document.getElementById('stream-events-container')
        const scrollTop = scrollContainer ? scrollContainer.scrollTop : 0

        const eventId = eventEl.dataset.eventId
        if (this.streamExpandedEvent === eventId) {
          this.streamExpandedEvent = null
        } else {
          this.streamExpandedEvent = eventId
          this.streamExpandedCluster = null // Close any expanded cluster
        }
        this._renderTimelineMode()

        // Restore scroll position after re-render
        requestAnimationFrame(() => {
          const newScrollContainer = document.getElementById('stream-events-container')
          if (newScrollContainer) {
            newScrollContainer.scrollTop = scrollTop
          }
        })
      })
    })

    // Cluster expand/collapse
    container.querySelectorAll('.stream-cluster').forEach(clusterEl => {
      clusterEl.addEventListener('click', (e) => {
        // Don't toggle if clicking on individual cluster events
        if (e.target.closest('.cluster-event-item')) return

        // Preserve scroll position before re-render
        const scrollContainer = document.getElementById('stream-events-container')
        const scrollTop = scrollContainer ? scrollContainer.scrollTop : 0

        const clusterId = clusterEl.dataset.clusterId
        if (this.streamExpandedCluster === clusterId) {
          this.streamExpandedCluster = null
        } else {
          this.streamExpandedCluster = clusterId
          this.streamExpandedEvent = null // Close any expanded event
        }
        this._renderTimelineMode()

        // Restore scroll position after re-render
        requestAnimationFrame(() => {
          const newScrollContainer = document.getElementById('stream-events-container')
          if (newScrollContainer) {
            newScrollContainer.scrollTop = scrollTop
          }
        })
      })
    })

    // Individual cluster event clicks
    container.querySelectorAll('.cluster-event-item').forEach(eventEl => {
      eventEl.addEventListener('click', (e) => {
        e.stopPropagation()

        // Preserve scroll position before re-render
        const scrollContainer = document.getElementById('stream-events-container')
        const scrollTop = scrollContainer ? scrollContainer.scrollTop : 0

        const eventId = eventEl.dataset.eventId
        this.streamExpandedEvent = eventId
        this.streamExpandedCluster = null
        this._renderTimelineMode()

        // Restore scroll position after re-render
        requestAnimationFrame(() => {
          const newScrollContainer = document.getElementById('stream-events-container')
          if (newScrollContainer) {
            newScrollContainer.scrollTop = scrollTop
          }
        })
      })
    })

    // Action button handlers
    container.querySelectorAll('.detail-action-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation()
        const action = btn.dataset.action
        const eventId = btn.dataset.eventId
        this._handleStreamEventAction(action, eventId)
      })
    })

    // Load More button handler - fetch more from server
    const loadMoreBtn = container.querySelector('#stream-load-more')
    if (loadMoreBtn) {
      loadMoreBtn.addEventListener('click', () => {
        this._loadMoreTimelineEvents()
      })
    }

    // Infinite scroll - load more when near bottom (debounced)
    const eventsContainer = container.querySelector('#stream-events-container')
    if (eventsContainer) {
      eventsContainer.addEventListener('scroll', () => {
        this._debounce('streamScroll', () => {
          const { scrollTop, scrollHeight, clientHeight } = eventsContainer
          if (scrollTop + clientHeight >= scrollHeight - 100) {
            // Near bottom, load more from server
            this._loadMoreTimelineEvents()
          }
        }, 200)
      })
    }

    // Stream target filter - target cell clicks
    container.querySelectorAll('.stream-target-cell').forEach(cell => {
      cell.addEventListener('click', () => {
        const targetId = cell.dataset.targetId
        this._toggleStreamTargetFilter(targetId)
      })
    })

    // Stream target filter - Select All button
    container.querySelector('#stream-select-all-targets')?.addEventListener('click', () => {
      this._selectAllStreamTargets()
    })

    // Stream target filter - Clear button
    container.querySelector('#stream-clear-target-filter')?.addEventListener('click', () => {
      this._clearStreamTargetFilter()
    })

    // Stream target filter - Search input (debounced)
    const targetSearchInput = container.querySelector('#stream-target-search')
    if (targetSearchInput) {
      targetSearchInput.addEventListener('input', (e) => {
        this._debounce('streamTargetSearch', () => {
          this._handleStreamTargetSearch(e.target.value)
        }, 150)
      })
    }

    // Stream panel resize handle
    const resizeHandle = container.querySelector('#stream-resize-handle')
    if (resizeHandle) {
      resizeHandle.addEventListener('mousedown', (e) => {
        this._startStreamPanelResize(e)
      })
    }

    // Legacy timeline-event support (for Matrix/Lanes views)
    container.querySelectorAll('.timeline-event').forEach(eventEl => {
      eventEl.addEventListener('click', () => {
        const eventId = eventEl.dataset.eventId
        console.log('[Timeline] Event clicked:', eventId)
      })
    })
  },

  /**
   * Handle action button clicks in stream event detail panel.
   */
  _handleStreamEventAction(action, eventId) {
    const event = this.timelineEvents.find(e => e.id === eventId)
    if (!event) return

    switch (action) {
      case 'rerun':
        // Push event to server to re-run command
        this.pushEvent('rerun_command', { command_log_id: event.source_id })
        break
      case 'acknowledge':
        // Push event to server to acknowledge alarm
        this.pushEvent('acknowledge_alarm', { alarm_event_id: event.source_id })
        break
      case 'copy':
        // Copy event details to clipboard
        const details = JSON.stringify(event, null, 2)
        navigator.clipboard.writeText(details).then(() => {
          console.log('[Stream] Event details copied to clipboard')
        })
        break
    }
  },

  _formatTimeUTC(date) {
    if (!(date instanceof Date)) date = new Date(date)
    return date.toISOString().slice(11, 19) + ' UTC'
  },

  _formatRelativeTime(date) {
    if (!(date instanceof Date)) date = new Date(date)
    const now = new Date()
    const diffMs = now - date
    const diffSec = Math.abs(Math.floor(diffMs / 1000))
    const diffMin = Math.floor(diffSec / 60)
    const diffHour = Math.floor(diffMin / 60)
    const diffDay = Math.floor(diffHour / 24)

    const isFuture = diffMs < 0

    if (diffSec < 60) return isFuture ? `in ${diffSec}s` : `${diffSec}s ago`
    if (diffMin < 60) return isFuture ? `in ${diffMin}m` : `${diffMin}m ago`
    if (diffHour < 24) return isFuture ? `in ${diffHour}h` : `${diffHour}h ago`
    return isFuture ? `in ${diffDay}d` : `${diffDay}d ago`
  },

  /**
   * Start scrubbing from the view marker in Lanes view.
   * Dragging the marker moves the scrubber position within the timeline.
   */
  _startLanesScrubbing(e) {
    e.preventDefault()
    e.stopPropagation()

    const axisTrack = this.panelLayout?.elements?.dashboard?.querySelector('.lanes-axis-track')
    if (!axisTrack) return

    this.lanesIsDragging = true
    this.lanesSelectedEvent = null  // Clear selected event when starting to scrub

    const trackRect = axisTrack.getBoundingClientRect()
    const startX = e.clientX
    const startPosition = this.lanesScrubberPosition

    const onMouseMove = (moveEvent) => {
      if (!this.lanesIsDragging) return

      const deltaX = moveEvent.clientX - startX
      const trackWidth = trackRect.width

      // Convert pixel movement to percentage
      const deltaPercent = (deltaX / trackWidth) * 100

      // Constrain to 0-100%
      let newPosition = startPosition + deltaPercent
      newPosition = Math.max(0, Math.min(100, newPosition))

      this.lanesScrubberPosition = newPosition
      this._renderTimelineMode()
    }

    const onMouseUp = () => {
      this.lanesIsDragging = false
      document.removeEventListener('mousemove', onMouseMove)
      document.removeEventListener('mouseup', onMouseUp)
      this._renderTimelineMode()
    }

    document.addEventListener('mousemove', onMouseMove)
    document.addEventListener('mouseup', onMouseUp)
  },

  /**
   * Update the view marker label during drag without full re-render.
   */
  _updateViewMarkerLabel() {
    const dashboard = this.panelLayout?.elements?.dashboard
    const marker = dashboard?.querySelector('.lanes-view-marker')
    if (!marker) return

    const now = new Date()
    const rangeMs = this.lanesTimeRange * 60 * 60 * 1000
    const viewCenter = new Date(now.getTime() + this.lanesViewOffset)
    const pastMs = rangeMs * 1.6
    const startTime = new Date(viewCenter.getTime() - pastMs)
    const totalMs = rangeMs * 2
    const viewTime = new Date(startTime.getTime() + (totalMs * this.lanesScrubberPosition / 100))
    const isViewingNow = Math.abs(viewTime - now) < 60000

    // Update label
    const label = marker.querySelector('.lanes-now-label')
    if (label) {
      label.textContent = isViewingNow ? 'NOW' : this._formatTimeUTC(viewTime)
    }

    // Toggle historical class
    if (isViewingNow) {
      marker.classList.remove('is-historical')
    } else {
      marker.classList.add('is-historical')
    }

    // Update activity panel handle indicator (pulse when events nearby)
    const activityPanel = dashboard?.querySelector('.lanes-activity-panel')
    if (activityPanel && !this.lanesActivityExpanded) {
      const filteredEvents = this.timelineEvents.filter(e => this.timelineTypeFilter.has(e.type))
      const eventWindowMs = 60000 // ±1 minute
      const hasNearbyEvents = filteredEvents.some(event => {
        const eventTime = new Date(event.timestamp)
        return Math.abs(eventTime - viewTime) <= eventWindowMs
      })
      activityPanel.classList.toggle('has-events', hasNearbyEvents)
    }
  },

  /**
   * Return to live NOW mode from scrubbing.
   */
  _returnToNow() {
    this.lanesScrubbingTime = null
    this.lanesViewOffset = 0  // Reset panning when returning to NOW
    this.lanesScrubberPosition = 80  // Reset scrubber to default position
    this._renderTimelineMode()
  },

  /**
   * Check if we need to load more events for the current lanes view window.
   * Called after panning to ensure we have events for the visible time range.
   */
  _checkLanesNeedMoreEvents() {
    if (this.streamLoadingMore || !this.streamHasMoreEvents) {
      return
    }

    // Calculate the current view window (80% past, 20% future)
    const now = new Date()
    const rangeMs = this.lanesTimeRange * 60 * 60 * 1000
    const pastMs = rangeMs * 1.6  // 80% of total range
    const viewCenter = new Date(now.getTime() + this.lanesViewOffset)
    const viewStart = new Date(viewCenter.getTime() - pastMs)

    // Find the oldest event we have loaded
    const pastEvents = this.timelineEvents.filter(e =>
      !e.is_future && new Date(e.timestamp) <= now
    )

    if (pastEvents.length === 0) {
      return
    }

    const oldestEvent = pastEvents.reduce((oldest, e) => {
      const eDate = new Date(e.timestamp)
      const oldestDate = new Date(oldest.timestamp)
      return eDate < oldestDate ? e : oldest
    }, pastEvents[0])

    const oldestEventTime = new Date(oldestEvent.timestamp)

    // If the view extends before the oldest loaded event, load more
    // Add a small buffer (5 minutes) to trigger loading before we hit the edge
    const bufferMs = 5 * 60 * 1000
    if (viewStart.getTime() < oldestEventTime.getTime() + bufferMs) {
      this._loadMoreTimelineEvents()
    }
  },

  /**
   * Start horizontal panning of the lanes view.
   * Called on mousedown on the lanes body (not on interactive elements).
   */
  _startLanesPanning(e, lanesBody) {
    e.preventDefault()
    this.lanesIsPanning = true
    this.lanesPanStartX = e.clientX
    this.lanesPanStartOffset = this.lanesViewOffset

    lanesBody.style.cursor = 'grabbing'
    lanesBody.classList.add('is-panning')

    const onMouseMove = (moveEvent) => {
      if (!this.lanesIsPanning) return

      const deltaX = moveEvent.clientX - this.lanesPanStartX
      const containerWidth = lanesBody.getBoundingClientRect().width

      // Convert pixel delta to time offset
      // Moving mouse right = scrolling left (going back in time)
      const rangeMs = this.lanesTimeRange * 60 * 60 * 1000 * 2
      const msPerPixel = rangeMs / containerWidth

      this.lanesViewOffset = this.lanesPanStartOffset - (deltaX * msPerPixel)
      this._renderTimelineMode()
    }

    const onMouseUp = () => {
      this.lanesIsPanning = false
      lanesBody.style.cursor = ''
      lanesBody.classList.remove('is-panning')
      document.removeEventListener('mousemove', onMouseMove)
      document.removeEventListener('mouseup', onMouseUp)

      // Check if we need to load more events after panning
      this._checkLanesNeedMoreEvents()
    }

    document.addEventListener('mousemove', onMouseMove)
    document.addEventListener('mouseup', onMouseUp)
  },

  /**
   * Bind resize drag behavior to the Lanes target panel.
   */
  _bindLanesPanelResize(container) {
    const handle = container.querySelector('#lanes-resize-handle')
    if (!handle) return

    const panel = container.querySelector('.lanes-target-picker-panel')
    if (!panel) return

    const minWidth = 150
    const maxWidth = 400

    const onMouseMove = (e) => {
      const splitLayout = container.querySelector('.lanes-split-layout')
      if (!splitLayout) return

      const rect = splitLayout.getBoundingClientRect()
      const newWidth = e.clientX - rect.left

      const clampedWidth = Math.max(minWidth, Math.min(maxWidth, newWidth))
      this.lanesTargetPanelWidth = clampedWidth
      panel.style.flex = `0 0 ${clampedWidth}px`

      handle.classList.add('dragging')
    }

    const onMouseUp = () => {
      handle.classList.remove('dragging')
      document.removeEventListener('mousemove', onMouseMove)
      document.removeEventListener('mouseup', onMouseUp)
    }

    handle.addEventListener('mousedown', (e) => {
      e.preventDefault()
      document.addEventListener('mousemove', onMouseMove)
      document.addEventListener('mouseup', onMouseUp)
    })
  },

  /**
   * Bind resize drag behavior to the Fleet Activity panel.
   * Similar to the staging panel resize in Commands mode.
   */
  _bindActivityPanelResize(container) {
    const handle = container.querySelector('#activity-resize-handle')
    if (!handle) return

    let panel = null
    let isMinimized = false
    let startY = 0
    let startHeight = 0

    const minHeight = 100
    const maxHeight = () => window.innerHeight * 0.5
    const expandThreshold = 30
    const collapseThreshold = 60

    const onMouseMove = (e) => {
      if (!panel) return

      const deltaY = startY - e.clientY  // Negative because we drag up to expand
      const newHeight = startHeight + deltaY

      panel.classList.add('resizing')

      if (isMinimized) {
        // When minimized, show preview of expansion
        if (deltaY > 10) {
          panel.style.height = `${Math.min(minHeight + deltaY, maxHeight())}px`
          panel.style.opacity = Math.min(1, 0.5 + deltaY / 100)
        }
      } else {
        // When expanded, resize normally
        const clampedHeight = Math.max(minHeight, Math.min(newHeight, maxHeight()))
        panel.style.height = `${clampedHeight}px`
      }
    }

    const onMouseUp = (e) => {
      document.removeEventListener('mousemove', onMouseMove)
      document.removeEventListener('mouseup', onMouseUp)

      if (!panel) return

      const deltaY = startY - e.clientY
      const finalHeight = startHeight + deltaY

      panel.classList.remove('resizing')
      panel.style.opacity = ''

      if (isMinimized) {
        panel.style.height = ''
        if (deltaY > expandThreshold) {
          this.lanesActivityExpanded = true
          this.lanesActivityHeight = Math.min(minHeight + deltaY, maxHeight())
          this._renderTimelineMode()
        }
      } else {
        if (finalHeight < collapseThreshold) {
          this.lanesActivityExpanded = false
          this.lanesActivityHeight = null
          this._renderTimelineMode()
        } else {
          // Keep the new height
          this.lanesActivityHeight = Math.max(minHeight, Math.min(finalHeight, maxHeight()))
          panel.style.setProperty('--activity-height', `${this.lanesActivityHeight}px`)
        }
      }

      panel = null
    }

    handle.addEventListener('mousedown', (e) => {
      e.preventDefault()

      panel = container.querySelector('.lanes-activity-panel.expanded') ||
              container.querySelector('.lanes-activity-panel.minimized')
      if (!panel) return

      isMinimized = panel.classList.contains('minimized')
      startY = e.clientY
      startHeight = panel.offsetHeight

      document.addEventListener('mousemove', onMouseMove)
      document.addEventListener('mouseup', onMouseUp)
    })
  },

  /**
   * Update the fleet activity panel for a specific scrubbed time.
   * Re-renders just the activity panel content for smooth updates during drag.
   */
  _updateFleetActivityForTime(time) {
    const dashboard = this.panelLayout?.elements?.dashboard
    if (!dashboard) return

    // Auto-expand if not already expanded
    if (!this.lanesActivityExpanded) {
      this.lanesActivityExpanded = true
      this._renderTimelineMode()
      return
    }

    // Update the activity panel content (only when already expanded)
    const activityBody = dashboard.querySelector('.lanes-activity-body')
    const activityTime = dashboard.querySelector('.lanes-activity-time')

    if (activityTime) {
      activityTime.textContent = this._formatTimeUTC(time)
    }

    if (activityBody) {
      const filteredEvents = this.timelineEvents.filter(e => this.timelineTypeFilter.has(e.type))
      const windowMs = 60000 // ±1 minute window
      const nearbyEvents = filteredEvents.filter(event => {
        const eventTime = new Date(event.timestamp)
        return Math.abs(eventTime - time) <= windowMs
      })

      if (nearbyEvents.length === 0) {
        activityBody.innerHTML = `
          <div class="lanes-activity-empty">
            <span class="empty-icon">○</span>
            <span class="empty-text">No events at this time</span>
          </div>
        `
      } else {
        activityBody.innerHTML = `
          <div class="lanes-activity-grid">
            ${nearbyEvents.map(event => this._renderActivityCard(event)).join('')}
          </div>
        `
      }
    }
  },

  /**
   * Update live time-dependent elements in the timeline without full re-render.
   * Called every second by the interval timer.
   */
  _updateTimelineLiveElements() {
    // Only update if in timeline mode and not paused
    if (this.currentMode !== 'timeline' || this.timelinePaused) return

    const dashboard = this.panelLayout?.elements?.dashboard
    if (!dashboard) return

    const now = new Date()

    // Update NOW marker label in Stream view (legacy)
    const nowLabel = dashboard.querySelector('.timeline-now-label')
    if (nowLabel) {
      nowLabel.textContent = `NOW ${this._formatTimeUTC(now)}`
    }

    // Update enhanced Stream view NOW marker
    const streamNowTime = dashboard.querySelector('.stream-now-time')
    if (streamNowTime) {
      streamNowTime.textContent = this._formatTimeUTC(now)
    }

    // Update relative times on all events (both legacy and enhanced)
    dashboard.querySelectorAll('.timeline-event-relative[data-timestamp], .stream-event-relative[data-timestamp]').forEach(timeEl => {
      const timestamp = timeEl.dataset.timestamp
      if (timestamp) {
        timeEl.textContent = this._formatRelativeTime(new Date(timestamp))
      }
    })

    // Update Lanes view - marker is centered, so just update label if viewing NOW
    if (this.timelineView === 'lanes') {
      const lanesContainer = dashboard.querySelector('.timeline-lanes')
      if (lanesContainer) {
        const isViewingNow = Math.abs(this.lanesViewOffset) < 60000
        const viewMarker = lanesContainer.querySelector('.lanes-view-marker')
        if (viewMarker && isViewingNow) {
          // When viewing NOW, keep the label showing "NOW" with current time
          const label = viewMarker.querySelector('.lanes-now-label')
          if (label) {
            label.textContent = 'NOW'
          }
        }

        // Update real NOW indicator position if scrolled away (80% past, 20% future)
        const realNowLine = lanesContainer.querySelector('.lanes-real-now-line-body')
        if (realNowLine && !isViewingNow) {
          const rangeMs = this.lanesTimeRange * 60 * 60 * 1000
          const pastMs = rangeMs * 1.6
          const futureMs = rangeMs * 0.4
          const viewCenter = new Date(now.getTime() + this.lanesViewOffset)
          const startTime = new Date(viewCenter.getTime() - pastMs)
          const totalMs = pastMs + futureMs
          const realNowPosition = ((now - startTime) / totalMs) * 100

          if (realNowPosition >= 0 && realNowPosition <= 100) {
            realNowLine.style.left = `calc(120px + (100% - 120px) * ${realNowPosition} / 100)`
          }
        }
      }
    }
  },

  _getStatusClass(status) {
    const statusMap = {
      success: 'status-success',
      verified: 'status-success',
      completed: 'status-success',
      cleared: 'status-success',
      pending: 'status-pending',
      running: 'status-running',
      active: 'status-active',
      error: 'status-error',
      failed: 'status-error'
    }
    return statusMap[status] || 'status-default'
  },

  _getStatusIcon(status) {
    const iconMap = {
      success: '✓',
      verified: '✓',
      completed: '✓',
      cleared: '✓',
      pending: '◷',
      running: '▶',
      active: '⚠',
      error: '✖',
      failed: '✖'
    }
    return iconMap[status] || ''
  },

  _handleTimelineEvent(event) {
    // Find existing event with same ID
    const existingIndex = this.timelineEvents.findIndex(e => e.id === event.id)

    if (existingIndex >= 0) {
      // Update existing event
      this.timelineEvents[existingIndex] = event
    } else {
      // Add new event and sort by timestamp
      this.timelineEvents.push(event)
      this.timelineEvents.sort((a, b) => {
        const dateA = new Date(a.timestamp)
        const dateB = new Date(b.timestamp)
        return dateB - dateA // Descending (newest first in memory)
      })

      // Trim to reasonable size (keep last 500 events)
      if (this.timelineEvents.length > 500) {
        this.timelineEvents = this.timelineEvents.slice(0, 500)
      }
    }

    // Re-render if in timeline mode and not paused
    if (this.currentMode === 'timeline' && !this.timelinePaused) {
      // _renderTimelineMode modifies DOM directly, just call it
      this._renderTimelineMode()

      // Auto-scroll to show new event if it's recent
      const eventDate = new Date(event.timestamp)
      const now = new Date()
      const diffMs = Math.abs(now - eventDate)

      // If event is within 1 minute of now, scroll to make it visible
      if (diffMs < 60000) {
        const dashboard = this.panelLayout?.elements?.dashboard
        const nowMarker = dashboard?.querySelector('.timeline-now-marker')
        if (nowMarker) {
          nowMarker.scrollIntoView({ behavior: 'smooth', block: 'center' })
        }
      }
    }
  },

  /**
   * Handle response from server with more timeline events (infinite scroll).
   */
  _handleMoreTimelineEvents(newEvents, hasMore) {
    this.streamLoadingMore = false
    this.streamHasMoreEvents = hasMore

    // Capture scroll position before re-render
    const dashboard = this.panelLayout?.elements?.dashboard
    const scrollContainer = dashboard?.querySelector('#stream-events-container')
    const savedScrollTop = scrollContainer?.scrollTop || 0

    if (!newEvents || newEvents.length === 0) {
      // No more events, just re-render to update UI state
      if (this.currentMode === 'timeline') {
        this._renderTimelineMode()
        // Restore scroll position
        this._restoreStreamScrollPosition(savedScrollTop)
      }
      return
    }

    // Add new events to our collection (avoiding duplicates)
    const existingIds = new Set(this.timelineEvents.map(e => e.id))
    const uniqueNewEvents = newEvents.filter(e => !existingIds.has(e.id))

    this.timelineEvents = [...this.timelineEvents, ...uniqueNewEvents]

    // Sort by timestamp descending
    this.timelineEvents.sort((a, b) => {
      const dateA = new Date(a.timestamp)
      const dateB = new Date(b.timestamp)
      return dateB - dateA
    })

    // Re-render to show new events
    if (this.currentMode === 'timeline') {
      this._renderTimelineMode()
      // Restore scroll position after render
      this._restoreStreamScrollPosition(savedScrollTop)
    }
  },

  /**
   * Restore scroll position after re-render (for infinite scroll).
   */
  _restoreStreamScrollPosition(scrollTop) {
    // Use requestAnimationFrame to ensure DOM has updated
    requestAnimationFrame(() => {
      const dashboard = this.panelLayout?.elements?.dashboard
      const scrollContainer = dashboard?.querySelector('#stream-events-container')
      if (scrollContainer) {
        scrollContainer.scrollTop = scrollTop
      }
    })
  },

  /**
   * Load more timeline events from the server using cursor-based pagination.
   */
  _loadMoreTimelineEvents() {
    if (this.streamLoadingMore || !this.streamHasMoreEvents) {
      return
    }

    // Find the oldest event timestamp as our cursor
    const now = new Date()
    const pastEvents = this.timelineEvents.filter(e =>
      !e.is_future && new Date(e.timestamp) <= now
    )

    if (pastEvents.length === 0) {
      return
    }

    // Get oldest event's timestamp
    const oldestEvent = pastEvents.reduce((oldest, e) => {
      const eDate = new Date(e.timestamp)
      const oldestDate = new Date(oldest.timestamp)
      return eDate < oldestDate ? e : oldest
    }, pastEvents[0])

    // Capture scroll position before showing loading state
    const dashboard = this.panelLayout?.elements?.dashboard
    const scrollContainer = dashboard?.querySelector('#stream-events-container')
    const savedScrollTop = scrollContainer?.scrollTop || 0

    this.streamLoadingMore = true

    // Re-render to show loading state, preserving scroll
    if (this.currentMode === 'timeline') {
      this._renderTimelineMode()
      this._restoreStreamScrollPosition(savedScrollTop)
    }

    // Request more events from server, including filter state
    this.pushEvent("load_more_timeline_events", {
      cursor: oldestEvent.timestamp,
      target_ids: Array.from(this.streamTargetFilter),
      include_system: this.streamShowSystem
    })
  },

  _renderTargetGrid() {
    const filteredTargets = this.targets.filter(t => {
      if (!this.cmdTargetFilter) return true
      const search = this.cmdTargetFilter.toLowerCase()
      return t.name?.toLowerCase().includes(search) ||
             t.identifier?.toLowerCase().includes(search)
    })

    if (filteredTargets.length === 0) {
      return '<div class="cmd-empty-state">No targets match filter</div>'
    }

    const isDetailed = this.cmdTargetViewMode === "detailed"

    return filteredTargets.map(target => {
      const isSelected = this.cmdSelectedTargets.has(target.id)
      const statusClass = target.status || "offline"

      // Get additional target data for detailed view and tooltip
      const mode = target.mode || "NOMINAL"
      const lastContact = this._formatLastContact(target.last_contact_at)
      const pendingCmds = target.pending_commands || 0
      const hasAlarms = target.alarm_count > 0
      const alarmCount = target.alarm_count || 0

      // Build tooltip content
      const tooltipLines = [
        `${target.name || target.identifier}`,
        `Status: ${statusClass.toUpperCase()}`,
        `Mode: ${mode}`,
        `Last Contact: ${lastContact}`,
        pendingCmds > 0 ? `Pending Commands: ${pendingCmds}` : null,
        alarmCount > 0 ? `Active Alarms: ${alarmCount}` : null
      ].filter(Boolean).join("\\n")

      if (isDetailed) {
        return `
          <div class="cmd-target-cell ${isSelected ? "selected" : ""} status-${statusClass} ${hasAlarms ? "has-alarms" : ""}"
               data-target-id="${target.id}"
               data-tooltip="${tooltipLines}">
            <div class="cmd-target-main">
              <span class="cmd-target-name">${target.name || target.identifier}</span>
              <span class="cmd-target-mode">${mode}</span>
            </div>
            <div class="cmd-target-meta">
              <span class="cmd-target-contact">${lastContact}</span>
              ${pendingCmds > 0 ? `<span class="cmd-target-pending">${pendingCmds}</span>` : ''}
              ${hasAlarms ? `<span class="cmd-target-alarm-badge">${alarmCount}</span>` : ''}
            </div>
          </div>
        `
      } else {
        // Compact view
        return `
          <div class="cmd-target-cell ${isSelected ? "selected" : ""} status-${statusClass} ${hasAlarms ? "has-alarms" : ""}"
               data-target-id="${target.id}"
               data-tooltip="${tooltipLines}">
            <span class="cmd-target-name">${target.name || target.identifier}</span>
            ${hasAlarms ? `<span class="cmd-target-alarm-dot"></span>` : ''}
          </div>
        `
      }
    }).join("")
  },

  _formatLastContact(timestamp) {
    if (!timestamp) return "Unknown"

    const now = new Date()
    const contact = new Date(timestamp)
    const diffMs = now - contact
    const diffSecs = Math.floor(diffMs / 1000)
    const diffMins = Math.floor(diffSecs / 60)
    const diffHours = Math.floor(diffMins / 60)
    const diffDays = Math.floor(diffHours / 24)

    if (diffSecs < 60) return `${diffSecs}s ago`
    if (diffMins < 60) return `${diffMins}m ago`
    if (diffHours < 24) return `${diffHours}h ago`
    return `${diffDays}d ago`
  },

  _initTargetTooltip(container) {
    // Create tooltip element if it doesn't exist
    let tooltip = document.getElementById("cmd-target-tooltip")
    if (!tooltip) {
      tooltip = document.createElement("div")
      tooltip.id = "cmd-target-tooltip"
      tooltip.className = "cmd-tooltip"
      document.body.appendChild(tooltip)
    }

    const grid = container.querySelector(".cmd-target-grid")
    if (!grid) return

    // Show tooltip on hover
    grid.addEventListener("mouseenter", (e) => {
      const cell = e.target.closest(".cmd-target-cell")
      if (cell && cell.dataset.tooltip) {
        const content = cell.dataset.tooltip.replace(/\\n/g, "<br>")
        tooltip.innerHTML = content
        tooltip.classList.add("visible")
        this._positionTooltip(tooltip, cell)
      }
    }, true)

    grid.addEventListener("mousemove", (e) => {
      const cell = e.target.closest(".cmd-target-cell")
      if (cell && tooltip.classList.contains("visible")) {
        this._positionTooltip(tooltip, cell)
      }
    }, true)

    grid.addEventListener("mouseleave", (e) => {
      const cell = e.target.closest(".cmd-target-cell")
      if (cell) {
        tooltip.classList.remove("visible")
      }
    }, true)
  },

  _positionTooltip(tooltip, cell) {
    const rect = cell.getBoundingClientRect()
    const tooltipRect = tooltip.getBoundingClientRect()

    // Position above the cell by default
    let top = rect.top - tooltipRect.height - 8
    let left = rect.left + (rect.width / 2) - (tooltipRect.width / 2)

    // If tooltip would go off top of screen, show below
    if (top < 8) {
      top = rect.bottom + 8
      tooltip.classList.add("below")
    } else {
      tooltip.classList.remove("below")
    }

    // Keep tooltip within horizontal bounds
    if (left < 8) left = 8
    if (left + tooltipRect.width > window.innerWidth - 8) {
      left = window.innerWidth - tooltipRect.width - 8
    }

    tooltip.style.top = `${top}px`
    tooltip.style.left = `${left}px`
  },

  _getFilteredCommands() {
    return this.commandDefinitions.filter(cmd => {
      if (!this.cmdCommandFilter) return true
      const search = this.cmdCommandFilter.toLowerCase()
      return cmd.name?.toLowerCase().includes(search) ||
             cmd.description?.toLowerCase().includes(search)
    })
  },

  _getFilteredCommandCount() {
    return this._getFilteredCommands().length
  },

  _renderCommandList() {
    const filteredCommands = this._getFilteredCommands()

    if (filteredCommands.length === 0) {
      return '<div class="cmd-empty-state">No commands match filter</div>'
    }

    return filteredCommands.map(cmd => {
      const isSelected = this.cmdSelectedCommand?.id === cmd.id
      const opcodeHex = cmd.opcode ? `0x${cmd.opcode.toString(16).toUpperCase().padStart(4, "0")}` : ""
      return `
        <div class="cmd-command-item ${isSelected ? "selected" : ""} ${cmd.is_hazardous ? "hazardous" : ""}"
             data-command-id="${cmd.id}">
          <div class="cmd-command-header">
            <span class="cmd-command-name">${cmd.name}</span>
            ${cmd.is_hazardous ? '<span class="cmd-hazard-badge">HAZARD</span>' : ""}
          </div>
          <div class="cmd-command-meta">
            ${opcodeHex ? `<span class="cmd-opcode">${opcodeHex}</span>` : ""}
            ${cmd.description ? `<span class="cmd-description">${cmd.description}</span>` : ""}
          </div>
        </div>
      `
    }).join("")
  },

  _renderStagingPanel() {
    const count = this.cmdStagedCommands.length
    const isEmpty = count === 0

    // Calculate total target count across all staged commands
    const totalTargets = isEmpty ? 0 : this.cmdStagedCommands.reduce((acc, cmd) => acc + cmd.targets.length, 0)

    // Height style for expanded panel via CSS variable
    const heightStyle = this.cmdStagePanelHeight ? `--staging-height: ${this.cmdStagePanelHeight}px;` : ''

    if (isEmpty) {
      // Empty state: show collapsed bar with disabled buttons
      return `
        <div class="cmd-staging-panel empty">
          <div class="cmd-staging-header">
            <div class="cmd-staging-title">
              <span class="mc-label-subsystem">STAGED</span>
              <span class="cmd-staging-count">empty</span>
            </div>
            <div class="cmd-staging-actions">
              <button class="cmd-staging-btn queue-all" disabled>Queue All</button>
              <button class="cmd-staging-btn clear" disabled>Clear</button>
            </div>
          </div>
          <div class="cmd-staging-panel-corners"></div>
        </div>
      `
    }

    if (!this.cmdStagePanelExpanded) {
      // Minimized bar state
      return `
        <div class="cmd-staging-panel minimized">
          <div class="cmd-staging-resize-handle" id="staging-resize-handle"></div>
          <div class="cmd-staging-header" id="staging-panel-toggle">
            <div class="cmd-staging-title">
              <span class="mc-label-subsystem">STAGED</span>
              <span class="cmd-staging-count">${count} cmd${count !== 1 ? 's' : ''} / ${totalTargets} target${totalTargets !== 1 ? 's' : ''}</span>
            </div>
            <div class="cmd-staging-actions">
              <button class="cmd-staging-btn queue-all" id="staging-queue-all">Queue All (${totalTargets})</button>
              <button class="cmd-staging-btn clear" id="staging-clear">Clear</button>
            </div>
          </div>
          <div class="cmd-staging-panel-corners"></div>
        </div>
      `
    }

    // Expanded state
    const { rows: filteredRows, filteredCount } = this._getFilteredStagedRows()
    const isCardView = this.cmdStageViewMode === 'cards'

    // View toggle buttons
    const viewToggle = `
      <div class="cmd-staging-view-toggle">
        <button class="cmd-view-btn ${!isCardView ? 'active' : ''}" data-view="table" title="Table view">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M3 6h18M3 12h18M3 18h18"/>
          </svg>
        </button>
        <button class="cmd-view-btn ${isCardView ? 'active' : ''}" data-view="cards" title="Card view">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <rect x="3" y="3" width="7" height="7" rx="1"/>
            <rect x="14" y="3" width="7" height="7" rx="1"/>
            <rect x="3" y="14" width="7" height="7" rx="1"/>
            <rect x="14" y="14" width="7" height="7" rx="1"/>
          </svg>
        </button>
      </div>
    `

    // Render content based on view mode
    const bodyContent = isCardView
      ? this._renderStagedCards(filteredCount)
      : `
        <table class="cmd-staging-table">
          <thead>
            <tr>
              <th>Target</th>
              <th>Command</th>
              <th>Parameters</th>
              <th>Pri</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            ${filteredRows.length > 0 ? filteredRows : '<tr><td colspan="5" class="cmd-staging-empty">No matches</td></tr>'}
          </tbody>
        </table>
      `

    return `
      <div class="cmd-staging-panel expanded ${isCardView ? 'card-view' : 'table-view'}" style="${heightStyle}">
        <div class="cmd-staging-resize-handle" id="staging-resize-handle"></div>
        <div class="cmd-staging-header" id="staging-panel-toggle">
          <div class="cmd-staging-title">
            <span class="mc-label-subsystem">STAGED</span>
            <span class="cmd-staging-count">${this.cmdStageFilter ? `${filteredCount} of ` : ''}${totalTargets} item${totalTargets !== 1 ? 's' : ''}</span>
          </div>
          <div class="cmd-staging-actions">
            ${viewToggle}
            <button class="cmd-staging-btn queue-all" id="staging-queue-all">${this.cmdStageFilter ? `Queue (${filteredCount})` : `Queue All (${totalTargets})`}</button>
            <button class="cmd-staging-btn clear" id="staging-clear">Clear</button>
          </div>
        </div>
        <div class="cmd-staging-filters">
          <input type="text"
                 class="cmd-staging-search"
                 id="staging-filter-input"
                 placeholder="Filter by target or command..."
                 value="${this.cmdStageFilter}">
          ${this.cmdStageFilter ? `<button class="cmd-staging-filter-clear" id="staging-filter-clear" title="Clear filter">&times;</button>` : ''}
        </div>
        <div class="cmd-staging-body">
          ${bodyContent}
        </div>
        <div class="cmd-staging-panel-corners"></div>
      </div>
    `
  },

  _getFilteredStagedRows() {
    const rows = []
    const filter = this.cmdStageFilter.toLowerCase()

    this.cmdStagedCommands.forEach((staged, cmdIndex) => {
      // Look up command definition for hazardous flag
      const cmdDef = this.commandDefinitions?.find(c => c.id === staged.command_id)
      const isHazardous = cmdDef?.is_hazardous || false

      staged.targets.forEach((targetEntry, targetIndex) => {
        const target = this.targets.find(t => t.id === targetEntry.target_id)
        const targetName = target?.name || targetEntry.target_name || targetEntry.target_id
        const commandName = staged.command_name

        // Apply filter
        if (filter) {
          const matchesTarget = targetName.toLowerCase().includes(filter)
          const matchesCommand = commandName.toLowerCase().includes(filter)
          if (!matchesTarget && !matchesCommand) return
        }

        // Format params preview
        const paramsPreview = Object.entries(targetEntry.params || {})
          .slice(0, 3)
          .map(([k, v]) => `${k}=${v}`)
          .join(', ')
        const hasMoreParams = Object.keys(targetEntry.params || {}).length > 3

        rows.push(`
          <tr class="cmd-staged-row ${isHazardous ? 'hazardous' : ''}"
              data-staged-idx="${cmdIndex}" data-target-idx="${targetIndex}">
            <td class="cmd-staged-target">${targetName}</td>
            <td class="cmd-staged-command">
              ${commandName}
              ${isHazardous ? '<span class="cmd-hazard-badge-sm">HAZ</span>' : ''}
            </td>
            <td class="cmd-staged-params">${paramsPreview}${hasMoreParams ? '...' : ''}</td>
            <td class="cmd-staged-priority">P${staged.priority}</td>
            <td class="cmd-staged-actions">
              <div class="cmd-staged-actions-inner">
                <button class="cmd-staged-queue" data-staged-idx="${cmdIndex}" data-target-idx="${targetIndex}">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M5 12h14M12 5l7 7-7 7"/>
                  </svg>
                  <span class="cmd-action-label">Queue</span>
                </button>
                <button class="cmd-staged-remove" data-staged-idx="${cmdIndex}" data-target-idx="${targetIndex}">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M18 6L6 18M6 6l12 12"/>
                  </svg>
                  <span class="cmd-action-label">Remove</span>
                </button>
              </div>
            </td>
          </tr>
        `)
      })
    })

    return { rows: rows.join(''), filteredCount: rows.length }
  },

  _renderStagedCards(filteredCount) {
    const filter = this.cmdStageFilter.toLowerCase()
    const cards = []

    this.cmdStagedCommands.forEach((staged, cmdIndex) => {
      // Look up command definition for hazardous flag
      const cmdDef = this.commandDefinitions?.find(c => c.id === staged.command_id)
      const isHazardous = cmdDef?.is_hazardous || false
      const commandName = staged.command_name

      staged.targets.forEach((targetEntry, targetIndex) => {
        // Look up target name (with fallback to stored name or ID)
        const target = this.targets?.find(t => t.id === targetEntry.target_id)
        const targetName = target?.name || targetEntry.target_name || targetEntry.target_id

        // Apply filter
        if (filter) {
          const matchesTarget = targetName.toLowerCase().includes(filter)
          const matchesCommand = commandName.toLowerCase().includes(filter)
          if (!matchesTarget && !matchesCommand) return
        }

        // Build params display
        const params = Object.entries(targetEntry.params || {})
        const paramsHtml = params.length > 0
          ? params.slice(0, 4).map(([k, v]) => `
              <div class="cmd-card-param">
                <span class="cmd-card-param-key">${k}</span>
                <span class="cmd-card-param-val">${v}</span>
              </div>
            `).join('') + (params.length > 4 ? `<div class="cmd-card-param-more">+${params.length - 4} more</div>` : '')
          : '<div class="cmd-card-no-params">No parameters</div>'

        cards.push(`
          <div class="cmd-staged-card ${isHazardous ? 'hazardous' : ''}"
               data-staged-idx="${cmdIndex}" data-target-idx="${targetIndex}">
            <div class="cmd-card-header">
              <div class="cmd-card-target">
                <span class="cmd-card-target-dot"></span>
                ${targetName}
              </div>
              <div class="cmd-card-priority">P${staged.priority}</div>
            </div>
            <div class="cmd-card-command">
              ${commandName}
              ${isHazardous ? '<span class="cmd-card-hazard">HAZ</span>' : ''}
            </div>
            <div class="cmd-card-params">
              ${paramsHtml}
            </div>
            <div class="cmd-card-actions">
              <button class="cmd-staged-queue" data-staged-idx="${cmdIndex}" data-target-idx="${targetIndex}">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M5 12h14M12 5l7 7-7 7"/>
                </svg>
                <span class="cmd-action-label">Queue</span>
              </button>
              <button class="cmd-staged-remove" data-staged-idx="${cmdIndex}" data-target-idx="${targetIndex}">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M18 6L6 18M6 6l12 12"/>
                </svg>
                <span class="cmd-action-label">Remove</span>
              </button>
            </div>
          </div>
        `)
      })
    })

    if (cards.length === 0) {
      return '<div class="cmd-staging-empty-cards">No matches</div>'
    }

    return `<div class="cmd-staged-cards-grid">${cards.join('')}</div>`
  },

  _bindCommandsModeEvents(container) {
    // Bind target cell events
    this._bindTargetCellEvents(container)

    // Bind command item events
    this._bindCommandItemEvents(container)

    // Initialize tooltip
    this._initTargetTooltip(container)

    // Commands panel resize handle
    const resizeHandle = container.querySelector('#cmd-resize-handle')
    if (resizeHandle) {
      resizeHandle.addEventListener('mousedown', (e) => {
        this._startCmdPanelResize(e)
      })
    }

    // View toggle buttons
    container.querySelectorAll(".cmd-view-btn").forEach(btn => {
      btn.addEventListener("click", (e) => {
        const newView = btn.dataset.view
        if (newView !== this.cmdTargetViewMode) {
          this.cmdTargetViewMode = newView

          // Update button states
          container.querySelectorAll(".cmd-view-btn").forEach(b => {
            b.classList.toggle("active", b.dataset.view === newView)
          })

          // Update grid class and re-render
          const grid = container.querySelector(".cmd-target-grid")
          if (grid) {
            grid.classList.toggle("detailed-view", newView === "detailed")
            grid.innerHTML = this._renderTargetGrid()
            this._bindTargetCellEvents(container)
          }
        }
      })
    })

    // Target search filter
    container.querySelector(".cmd-target-search")?.addEventListener("input", (e) => {
      this.cmdTargetFilter = e.target.value
      this._debounce("targetFilter", () => {
        // Only update the grid, not the whole container
        const grid = container.querySelector(".cmd-target-grid")
        if (grid) {
          grid.innerHTML = this._renderTargetGrid()
          this._bindTargetCellEvents(container)
        }
        // Update count
        const count = container.querySelector(".cmd-selection-count")
        if (count) count.textContent = `${this.cmdSelectedTargets.size} of ${this.targets.length}`
      }, 150)
    })

    // Group filter
    container.querySelector(".cmd-group-filter")?.addEventListener("change", (e) => {
      // TODO: Filter by group
      this._renderCommandsMode()
    })

    // Select all / Clear
    container.querySelector("#cmd-select-all")?.addEventListener("click", () => {
      this.targets.forEach(t => this.cmdSelectedTargets.add(t.id))
      // Update all visible cells
      container.querySelectorAll(".cmd-target-cell").forEach(cell => cell.classList.add("selected"))
      // Update count
      const count = container.querySelector(".cmd-selection-count")
      if (count) count.textContent = `${this.cmdSelectedTargets.size} of ${this.targets.length}`
      this._populateContextPanel()
    })

    container.querySelector("#cmd-clear-selection")?.addEventListener("click", () => {
      this.cmdSelectedTargets.clear()
      // Update all visible cells
      container.querySelectorAll(".cmd-target-cell").forEach(cell => cell.classList.remove("selected"))
      // Update count
      const count = container.querySelector(".cmd-selection-count")
      if (count) count.textContent = `0 of ${this.targets.length}`
      this._populateContextPanel()
    })

    // Command search filter
    container.querySelector(".cmd-command-search")?.addEventListener("input", (e) => {
      this.cmdCommandFilter = e.target.value
      this._debounce("commandFilter", () => {
        // Only update the list, not the whole container
        const list = container.querySelector(".cmd-command-list")
        if (list) {
          list.innerHTML = this._renderCommandList()
          this._bindCommandItemEvents(container)
        }
        // Update count with filtered results
        const filteredCount = this._getFilteredCommandCount()
        const count = container.querySelector(".cmd-command-count")
        if (count) count.textContent = `${filteredCount} of ${this.commandDefinitions.length} available`
      }, 150)
    })

    // Bind staging panel events
    this._bindStagingPanelEvents(container)
  },

  _bindStagingPanelEvents(container) {
    // Toggle expand/collapse
    container.querySelector("#staging-panel-toggle")?.addEventListener("click", (e) => {
      // Don't toggle if clicking on a button
      if (e.target.closest('button')) return
      this.cmdStagePanelExpanded = !this.cmdStagePanelExpanded
      this._updateStagingPanel()
    })

    // Queue all staged commands
    container.querySelector("#staging-queue-all")?.addEventListener("click", (e) => {
      e.stopPropagation()
      this._queueAllStaged()
    })

    // Clear all staged commands
    container.querySelector("#staging-clear")?.addEventListener("click", (e) => {
      e.stopPropagation()
      this.cmdStagedCommands = []
      this._updateStagingPanel()
    })

    // View toggle (table/cards)
    container.querySelectorAll(".cmd-staging-view-toggle .cmd-view-btn")?.forEach(btn => {
      btn.addEventListener("click", (e) => {
        e.stopPropagation()
        const newView = btn.dataset.view
        if (newView !== this.cmdStageViewMode) {
          this.cmdStageViewMode = newView
          this._updateStagingPanel()
        }
      })
    })

    // Click on staging table row to edit
    container.querySelectorAll(".cmd-staged-row")?.forEach(row => {
      row.addEventListener("click", (e) => {
        // Don't trigger edit if clicking action buttons
        if (e.target.closest('.cmd-staged-remove') || e.target.closest('.cmd-staged-queue')) return

        const cmdIdx = parseInt(row.dataset.stagedIdx, 10)
        const targetIdx = parseInt(row.dataset.targetIdx, 10)

        this._editStagedEntry(cmdIdx, targetIdx)
      })
    })

    // Click on staging card to edit
    container.querySelectorAll(".cmd-staged-card")?.forEach(card => {
      card.addEventListener("click", (e) => {
        // Don't trigger edit if clicking action buttons
        if (e.target.closest('.cmd-staged-remove') || e.target.closest('.cmd-staged-queue')) return

        const cmdIdx = parseInt(card.dataset.stagedIdx, 10)
        const targetIdx = parseInt(card.dataset.targetIdx, 10)

        this._editStagedEntry(cmdIdx, targetIdx)
      })
    })

    // Queue individual staged row
    container.querySelectorAll(".cmd-staged-queue")?.forEach(btn => {
      btn.addEventListener("click", (e) => {
        e.stopPropagation()
        const cmdIdx = parseInt(btn.dataset.stagedIdx, 10)
        const targetIdx = parseInt(btn.dataset.targetIdx, 10)
        this._queueStagedEntry(cmdIdx, targetIdx)
      })
    })

    // Remove individual staged row (target from a command)
    container.querySelectorAll(".cmd-staged-remove")?.forEach(btn => {
      btn.addEventListener("click", (e) => {
        e.stopPropagation()
        const cmdIdx = parseInt(btn.dataset.stagedIdx, 10)
        const targetIdx = parseInt(btn.dataset.targetIdx, 10)

        const staged = this.cmdStagedCommands[cmdIdx]
        if (!staged) return

        const target = staged.targets[targetIdx]
        if (!target?.id) return

        this.pushEvent("remove_staged_target", {
          target_entry_id: target.id
        })
      })
    })

    // Filter input
    const filterInput = container.querySelector("#staging-filter-input")
    if (filterInput) {
      filterInput.addEventListener("input", (e) => {
        this.cmdStageFilter = e.target.value
        this._updateStagingContent()
      })
      // Focus retention - keep focus after re-render
      filterInput.addEventListener("keydown", (e) => {
        if (e.key === "Escape") {
          this.cmdStageFilter = ''
          this._updateStagingPanel()
        }
      })
    }

    // Filter clear button
    container.querySelector("#staging-filter-clear")?.addEventListener("click", (e) => {
      e.stopPropagation()
      this.cmdStageFilter = ''
      this._updateStagingPanel()
    })

    // Resize handle for expanded panel
    const resizeHandle = container.querySelector("#staging-resize-handle")
    if (resizeHandle) {
      this._bindStagingResizeHandle(resizeHandle, container)
    }
  },

  _bindStagingResizeHandle(handle, container) {
    let startY = 0
    let startHeight = 0
    let panel = null
    let isMinimized = false
    const collapseThreshold = 80
    const expandThreshold = 40
    const minHeight = 120
    const maxHeight = () => window.innerHeight * 0.7

    const onMouseMove = (e) => {
      if (!panel) return
      const deltaY = startY - e.clientY // positive = dragging up

      if (isMinimized) {
        // Dragging from minimized - preview expansion
        if (deltaY > expandThreshold) {
          const previewHeight = Math.min(minHeight + deltaY, maxHeight())
          panel.style.setProperty('--staging-height', `${previewHeight}px`)
          panel.style.height = 'var(--staging-height)'
        }
      } else {
        // Dragging from expanded - resize via CSS variable
        const newHeight = Math.max(minHeight, Math.min(startHeight + deltaY, maxHeight()))

        if (newHeight < collapseThreshold) {
          panel.style.opacity = '0.5'
        } else {
          panel.style.setProperty('--staging-height', `${newHeight}px`)
          panel.style.opacity = ''
        }
      }
    }

    const onMouseUp = (e) => {
      if (!panel) return
      const deltaY = startY - e.clientY
      const finalHeight = isMinimized ? minHeight + deltaY : startHeight + deltaY

      panel.classList.remove('resizing')
      panel.style.opacity = ''

      if (isMinimized) {
        panel.style.height = ''
        if (deltaY > expandThreshold) {
          this.cmdStagePanelExpanded = true
          this.cmdStagePanelHeight = Math.min(minHeight + deltaY, maxHeight())
          this._updateStagingPanel()
        }
      } else {
        if (finalHeight < collapseThreshold) {
          this.cmdStagePanelExpanded = false
          this.cmdStagePanelHeight = null
          this._updateStagingPanel()
        } else {
          // Keep the new height
          this.cmdStagePanelHeight = Math.max(minHeight, Math.min(finalHeight, maxHeight()))
        }
      }

      document.removeEventListener('mousemove', onMouseMove)
      document.removeEventListener('mouseup', onMouseUp)
      document.body.style.cursor = ''
      document.body.style.userSelect = ''
    }

    handle.addEventListener('mousedown', (e) => {
      e.preventDefault()

      panel = container.querySelector('.cmd-staging-panel.expanded') ||
              container.querySelector('.cmd-staging-panel.minimized')
      if (!panel) return

      isMinimized = panel.classList.contains('minimized')
      startY = e.clientY
      startHeight = panel.offsetHeight

      panel.classList.add('resizing')
      document.body.style.cursor = 'ns-resize'
      document.body.style.userSelect = 'none'

      document.addEventListener('mousemove', onMouseMove)
      document.addEventListener('mouseup', onMouseUp)
    })
  },

  _updateStagingPanel() {
    const container = document.querySelector(".commands-mode-container")
    if (!container) return

    // Find or create staging panel container
    const layout = container.querySelector(".commands-mode-layout")
    if (!layout) return

    // Remove existing staging panel
    const existingPanel = layout.querySelector(".cmd-staging-panel")
    if (existingPanel) {
      existingPanel.remove()
    }

    // Add new staging panel
    const panelHtml = this._renderStagingPanel()
    if (panelHtml) {
      layout.insertAdjacentHTML('beforeend', panelHtml)
      this._bindStagingPanelEvents(container)
    }
  },

  _updateStagingContent() {
    // Update just the content (table body or cards) without re-rendering the whole panel
    // This keeps the filter input focused
    const container = document.querySelector(".commands-mode-container")
    if (!container) return

    const countSpan = container.querySelector(".cmd-staging-count")
    const queueAllBtn = container.querySelector("#staging-queue-all")
    const totalTargets = this.cmdStagedCommands.reduce((acc, cmd) => acc + cmd.targets.length, 0)

    if (this.cmdStageViewMode === 'cards') {
      // Update cards view
      const cardsGrid = container.querySelector(".cmd-staged-cards-grid")
      const stagingBody = container.querySelector(".cmd-staging-body")
      if (!stagingBody) return

      const cardsHtml = this._renderStagedCards()
      stagingBody.innerHTML = cardsHtml

      // Count filtered cards
      const filteredCount = container.querySelectorAll(".cmd-staged-card").length

      // Update count
      if (countSpan) {
        countSpan.textContent = this.cmdStageFilter
          ? `${filteredCount} of ${totalTargets} item${totalTargets !== 1 ? 's' : ''}`
          : `${totalTargets} item${totalTargets !== 1 ? 's' : ''}`
      }

      // Update queue button label
      if (queueAllBtn) {
        queueAllBtn.textContent = this.cmdStageFilter
          ? `Queue (${filteredCount})`
          : `Queue All (${totalTargets})`
      }

      // Re-bind card click to edit
      container.querySelectorAll(".cmd-staged-card")?.forEach(card => {
        card.addEventListener("click", (e) => {
          if (e.target.closest('.cmd-staged-remove') || e.target.closest('.cmd-staged-queue')) return
          const cmdIdx = parseInt(card.dataset.stagedIdx, 10)
          const targetIdx = parseInt(card.dataset.targetIdx, 10)
          this._editStagedEntry(cmdIdx, targetIdx)
        })
      })
    } else {
      // Update table view
      const tbody = container.querySelector(".cmd-staging-table tbody")
      if (!tbody) return

      const { rows, filteredCount } = this._getFilteredStagedRows()

      // Update table body
      tbody.innerHTML = rows.length > 0 ? rows : '<tr><td colspan="5" class="cmd-staging-empty">No matches</td></tr>'

      // Update count
      if (countSpan) {
        countSpan.textContent = this.cmdStageFilter
          ? `${filteredCount} of ${totalTargets} item${totalTargets !== 1 ? 's' : ''}`
          : `${totalTargets} item${totalTargets !== 1 ? 's' : ''}`
      }

      // Update queue button label
      if (queueAllBtn) {
        queueAllBtn.textContent = this.cmdStageFilter
          ? `Queue (${filteredCount})`
          : `Queue All (${totalTargets})`
      }

      // Re-bind row click to edit
      container.querySelectorAll(".cmd-staged-row")?.forEach(row => {
        row.addEventListener("click", (e) => {
          if (e.target.closest('.cmd-staged-remove') || e.target.closest('.cmd-staged-queue')) return
          const cmdIdx = parseInt(row.dataset.stagedIdx, 10)
          const targetIdx = parseInt(row.dataset.targetIdx, 10)
          this._editStagedEntry(cmdIdx, targetIdx)
        })
      })
    }

    // Re-bind queue buttons (works for both views)
    container.querySelectorAll(".cmd-staged-queue")?.forEach(btn => {
      btn.addEventListener("click", (e) => {
        e.stopPropagation()
        const cmdIdx = parseInt(btn.dataset.stagedIdx, 10)
        const targetIdx = parseInt(btn.dataset.targetIdx, 10)
        this._queueStagedEntry(cmdIdx, targetIdx)
      })
    })

    // Re-bind remove buttons (works for both views)
    container.querySelectorAll(".cmd-staged-remove")?.forEach(btn => {
      btn.addEventListener("click", (e) => {
        e.stopPropagation()
        const cmdIdx = parseInt(btn.dataset.stagedIdx, 10)
        const targetIdx = parseInt(btn.dataset.targetIdx, 10)

        const staged = this.cmdStagedCommands[cmdIdx]
        if (!staged) return

        const target = staged.targets[targetIdx]
        if (!target?.id) return

        this.pushEvent("remove_staged_target", {
          target_entry_id: target.id
        })
      })
    })
  },

  _queueAllStaged() {
    const filter = this.cmdStageFilter.toLowerCase()

    // If no filter, use the simple server-side queue_all
    if (!filter) {
      this.pushEvent("queue_all_staged", {})
      this.cmdStageFilter = ''
      return
    }

    // With filter: queue each matching target individually
    this.cmdStagedCommands.forEach((staged) => {
      const commandName = staged.command_name

      staged.targets.forEach((targetEntry) => {
        if (!targetEntry.id) return

        // Apply filter
        const target = this.targets?.find(t => t.id === targetEntry.target_id)
        const targetName = target?.name || targetEntry.target_name || targetEntry.target_id
        const matchesTarget = targetName.toLowerCase().includes(filter)
        const matchesCommand = commandName?.toLowerCase().includes(filter)

        if (!matchesTarget && !matchesCommand) return

        this.pushEvent("queue_staged_target", {
          target_entry_id: targetEntry.id
        })
      })
    })

    // Clear filter after queueing
    this.cmdStageFilter = ''
  },

  _queueStagedEntry(cmdIdx, targetIdx) {
    const staged = this.cmdStagedCommands[cmdIdx]
    if (!staged) return

    const target = staged.targets[targetIdx]
    if (!target?.id) return

    // Queue via server - server handles queue creation and staging cleanup
    this.pushEvent("queue_staged_target", {
      target_entry_id: target.id
    })
  },

  _addToStagingArea() {
    const cmd = this.cmdSelectedCommand
    if (!cmd) return

    // Build targets array from staged params
    const targets = []
    this.cmdStagedParams.forEach((entry, targetId) => {
      // Look up target name
      const target = this.targets?.find(t => t.id === targetId)
      targets.push({
        target_id: targetId,
        target_name: target?.name || `Target ${targetId}`,
        params: entry.params
      })
    })

    if (targets.length === 0) {
      console.warn("[OpsConsole] No staged params to add to staging area")
      return
    }

    // Generate client-side ID for optimistic UI (optional)
    const clientId = `staged-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`

    // Push to server - server will persist and broadcast to all clients
    this.pushEvent("stage_command", {
      command_id: cmd.id,
      targets: targets,
      priority: this.cmdPriority,
      client_id: clientId
    })

    // Close the slideout
    this._closeCommandSlideout()
  },

  _bindTargetCellEvents(container) {
    container.querySelectorAll(".cmd-target-cell").forEach(cell => {
      cell.addEventListener("click", (e) => {
        const targetId = cell.dataset.targetId
        if (this.cmdSelectedTargets.has(targetId)) {
          this.cmdSelectedTargets.delete(targetId)
        } else {
          this.cmdSelectedTargets.add(targetId)
        }
        // Update just the cell and count, not the whole UI
        cell.classList.toggle("selected")
        const count = container.querySelector(".cmd-selection-count")
        if (count) count.textContent = `${this.cmdSelectedTargets.size} of ${this.targets.length} selected`
        // Update context panel to reflect selection
        this._populateContextPanel()
      })
    })
  },

  _bindCommandItemEvents(container) {
    container.querySelectorAll(".cmd-command-item").forEach(item => {
      item.addEventListener("click", () => {
        // Remove selected from all items
        container.querySelectorAll(".cmd-command-item").forEach(i => i.classList.remove("selected"))
        // Add selected to clicked item
        item.classList.add("selected")
        // Update state
        const commandId = item.dataset.commandId
        this.cmdSelectedCommand = this.commandDefinitions.find(c => c.id === commandId)
        // Open slideout panel with the selected command
        this._openCommandSlideout()
      })
    })
  },

  _renderQueueItem(cmd) {
    const statusClass = cmd.status === 'executing' ? 'executing' :
                        cmd.status === 'held' ? 'held' :
                        cmd.status === 'failed' ? 'failed' : 'pending'
    const isExecuting = cmd.status === 'executing'
    const isFailed = cmd.status === 'failed'

    // Priority indicator (0=highest, 5=lowest)
    const priority = cmd.priority ?? 3
    const priorityClass = priority <= 1 ? 'priority-high' : priority >= 4 ? 'priority-low' : ''

    // Compact status label
    const statusLabel = {
      'pending': 'PEND',
      'held': 'HOLD',
      'executing': 'EXEC',
      'completed': 'DONE',
      'failed': 'FAIL'
    }[cmd.status] || cmd.status.toUpperCase().slice(0, 4)

    // Format parameters as compact string
    const params = cmd.parameters || {}
    const paramEntries = Object.entries(params)
    const paramsPreview = paramEntries
      .map(([k, v]) => `<span class="qe-param-item"><span class="qe-param-key">${k}</span><span class="qe-param-val">${this._formatParamValue(v)}</span></span>`)
      .join('')

    return `
      <div class="qe ${statusClass}" data-id="${cmd.id}">
        <div class="qe-meta-row">
          <span class="qe-target">${cmd.target_name || '?'}</span>
          <div class="qe-badges">
            <span class="qe-priority ${priorityClass}">P${priority}</span>
            <span class="qe-status">${statusLabel}</span>
          </div>
        </div>
        <div class="qe-command-row">
          ${isExecuting ? '<span class="qe-pulse-inline"></span>' : ''}
          ${isFailed ? `
            <svg class="qe-error-inline" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
            </svg>
          ` : ''}
          <span class="qe-command">${cmd.command_name}</span>
        </div>
        ${paramEntries.length > 0 ? `
          <div class="qe-params-row">${paramsPreview}</div>
        ` : ''}
      </div>
    `
  },

  _getStatusLabel(status) {
    const labels = {
      'pending': 'PENDING',
      'held': 'HELD',
      'executing': 'EXECUTING',
      'completed': 'COMPLETED',
      'failed': 'FAILED'
    }
    return labels[status] || status.toUpperCase()
  },

  _formatQueueAge(timestamp) {
    if (!timestamp) return '--'
    const now = new Date()
    const created = new Date(timestamp)
    const diffMs = now - created
    const diffSecs = Math.floor(diffMs / 1000)
    const diffMins = Math.floor(diffSecs / 60)
    const diffHours = Math.floor(diffMins / 60)

    if (diffSecs < 60) return `${diffSecs}s`
    if (diffMins < 60) return `${diffMins}m`
    if (diffHours < 24) return `${diffHours}h ${diffMins % 60}m`
    return `${Math.floor(diffHours / 24)}d`
  },

  _formatScheduledTime(timestamp) {
    if (!timestamp) return '--'
    const date = new Date(timestamp)
    return date.toLocaleTimeString('en-US', {
      hour: '2-digit',
      minute: '2-digit',
      hour12: false
    })
  },

  _formatParamValue(value) {
    if (typeof value === 'boolean') return value ? 'true' : 'false'
    if (typeof value === 'object') return JSON.stringify(value)
    return String(value)
  },

  _renderParameterForm(cmd) {
    const params = cmd.parameters || []
    if (params.length === 0) {
      return '<div class="text-xs text-base-content/60">No parameters required</div>'
    }

    return params.map(param => {
      const required = param.required ? '<span class="text-error">*</span>' : ''
      const defaultVal = param.default_value ?? ''
      const hasValidValues = param.valid_values && param.valid_values.length > 0
      const hasRange = param.min_value != null || param.max_value != null
      const isNumeric = ['int', 'uint', 'float', 'double', 'integer', 'number'].includes(param.data_type?.toLowerCase())
      const isBool = ['boolean', 'bool'].includes(param.data_type?.toLowerCase())

      // Description tooltip
      const descTooltip = param.description
        ? `title="${param.description.replace(/"/g, '&quot;')}"`
        : ''

      // Build range hint text
      let rangeHint = ''
      if (hasRange) {
        if (param.min_value != null && param.max_value != null) {
          rangeHint = `Range: ${param.min_value} - ${param.max_value}`
        } else if (param.min_value != null) {
          rangeHint = `Min: ${param.min_value}`
        } else if (param.max_value != null) {
          rangeHint = `Max: ${param.max_value}`
        }
      }

      // Boolean type - toggle switch
      if (isBool) {
        return `
          <div class="form-control cmd-param-group">
            <label class="label cursor-pointer py-1" ${descTooltip}>
              <span class="label-text text-xs">${param.name}${required}</span>
              <input type="checkbox" class="toggle toggle-xs toggle-primary cmd-param" data-param="${param.name}"
                     ${defaultVal === 'true' || defaultVal === true ? 'checked' : ''}>
            </label>
            ${param.description ? `<span class="cmd-param-desc">${param.description}</span>` : ''}
          </div>
        `
      }

      // Has valid values - parse labels from description and render appropriately
      if (hasValidValues) {
        // Parse value->label mappings from description (e.g., "Mode (0=BOOT, 1=SAFE, ...)")
        const valueLabels = this._parseValueLabels(param.description, param.valid_values)
        const optionCount = param.valid_values.length

        // For small number of options (2-4), use button group
        if (optionCount <= 4) {
          return `
            <div class="form-control cmd-param-group">
              <label class="label py-1">
                <span class="label-text text-xs">${param.name}${required}</span>
              </label>
              <div class="cmd-value-buttons" data-param="${param.name}">
                ${param.valid_values.map(v => {
                  const label = valueLabels[v] || v
                  const isSelected = String(v) === String(defaultVal)
                  return `
                    <button type="button"
                            class="cmd-value-btn ${isSelected ? 'selected' : ''}"
                            data-value="${v}"
                            title="${param.description || ''}">
                      <span class="cmd-value-label">${label}</span>
                      <span class="cmd-value-raw">${v}</span>
                    </button>
                  `
                }).join('')}
              </div>
              <input type="hidden" class="cmd-param" data-param="${param.name}" value="${defaultVal}">
            </div>
          `
        }

        // For more options, use enhanced dropdown with labels
        return `
          <div class="form-control cmd-param-group">
            <label class="label py-1">
              <span class="label-text text-xs">${param.name}${required}</span>
              ${param.units ? `<span class="label-text-alt text-xs text-base-content/50">${param.units}</span>` : ''}
            </label>
            <select class="select select-bordered select-xs w-full cmd-param cmd-param-labeled" data-param="${param.name}">
              ${!param.required ? '<option value="">-- Select --</option>' : ''}
              ${param.valid_values.map(v => {
                const label = valueLabels[v]
                const displayText = label ? `${label} (${v})` : v
                return `<option value="${v}" ${String(v) === String(defaultVal) ? 'selected' : ''}>${displayText}</option>`
              }).join('')}
            </select>
            <div class="cmd-value-preview" data-for="${param.name}">
              ${defaultVal && valueLabels[defaultVal] ? `<span class="cmd-value-preview-label">${valueLabels[defaultVal]}</span>` : ''}
            </div>
          </div>
        `
      }

      // Numeric type with range
      if (isNumeric) {
        const step = ['float', 'double'].includes(param.data_type?.toLowerCase()) ? 'any' : '1'
        return `
          <div class="form-control cmd-param-group">
            <label class="label py-1" ${descTooltip}>
              <span class="label-text text-xs">${param.name}${required}</span>
              ${param.units ? `<span class="label-text-alt text-xs text-base-content/50">${param.units}</span>` : ''}
            </label>
            <input type="number"
                   class="input input-bordered input-xs w-full cmd-param"
                   data-param="${param.name}"
                   value="${defaultVal}"
                   step="${step}"
                   ${param.min_value != null ? `min="${param.min_value}"` : ''}
                   ${param.max_value != null ? `max="${param.max_value}"` : ''}
                   placeholder="${rangeHint || ''}">
            ${rangeHint ? `<span class="cmd-param-hint">${rangeHint}</span>` : ''}
            ${param.description ? `<span class="cmd-param-desc">${param.description}</span>` : ''}
          </div>
        `
      }

      // Default: text input
      return `
        <div class="form-control cmd-param-group">
          <label class="label py-1" ${descTooltip}>
            <span class="label-text text-xs">${param.name}${required}</span>
            ${param.units ? `<span class="label-text-alt text-xs text-base-content/50">${param.units}</span>` : ''}
          </label>
          <input type="text"
                 class="input input-bordered input-xs w-full cmd-param"
                 data-param="${param.name}"
                 value="${defaultVal}"
                 placeholder="${param.description || ''}">
          ${param.description ? `<span class="cmd-param-desc">${param.description}</span>` : ''}
        </div>
      `
    }).join('')
  },

  // Parse value->label mappings from description string
  // Handles patterns like: "Mode (0=BOOT, 1=SAFE, 2=IDLE)" or "State: 0=OFF, 1=ON"
  _parseValueLabels(description, validValues) {
    const labels = {}
    if (!description) return labels

    // Try to extract mappings with various patterns
    // Pattern 1: "0=BOOT" or "0: BOOT"
    const patterns = [
      /(\d+)\s*[=:]\s*([A-Z_][A-Z0-9_]*)/gi,  // 0=BOOT, 1=SAFE
      /([A-Z_][A-Z0-9_]*)\s*[=:]\s*(\d+)/gi,  // BOOT=0, SAFE=1
    ]

    for (const pattern of patterns) {
      let match
      while ((match = pattern.exec(description)) !== null) {
        // Check if first group is numeric
        if (/^\d+$/.test(match[1])) {
          labels[match[1]] = match[2]
        } else if (/^\d+$/.test(match[2])) {
          labels[match[2]] = match[1]
        }
      }
    }

    return labels
  },

  _dispatchCommand(mode) {
    if (!this.cmdSelectedCommand || this.cmdSelectedTargets.size === 0) return

    // Collect parameter values from slideout
    const params = {}
    const slideout = document.getElementById("cmd-slideout")
    if (slideout) {
      slideout.querySelectorAll(".cmd-param").forEach(input => {
        const paramName = input.dataset.param
        if (input.type === "checkbox") {
          params[paramName] = input.checked
        } else {
          params[paramName] = input.value
        }
      })
    }

    // Send dispatch event to LiveView
    this.pushEvent("cmd_dispatch", {
      command_id: this.cmdSelectedCommand.id,
      target_ids: Array.from(this.cmdSelectedTargets),
      params: params,
      mode: mode,
      priority: this.cmdPriority
    })

    // Close the slideout after dispatching
    this._closeCommandSlideout()

    // Clear command selection
    this.cmdSelectedCommand = null
    const dashboard = this.panelLayout?.elements?.dashboard
    if (dashboard) {
      dashboard.querySelectorAll(".cmd-command-item").forEach(i => i.classList.remove("selected"))
    }
  },

  // ============================================================================
  // Queue Mode
  // ============================================================================

  _renderQueueMode() {
    const dashboard = this.panelLayout?.elements?.dashboard
    if (!dashboard) return

    // Check if queue container already exists
    let queueContainer = dashboard.querySelector(".queue-mode-container")
    if (!queueContainer) {
      queueContainer = document.createElement("div")
      queueContainer.className = "queue-mode-container"
      dashboard.appendChild(queueContainer)
    }

    // Render view-specific content
    let viewContent
    if (this.queueViewMode === 'overview') {
      viewContent = this._renderQueueOverviewContent()
    } else if (this.queueViewMode === 'manage') {
      viewContent = this._renderQueueManageContent()
    } else {
      viewContent = this._renderQueueTableContent()
    }

    queueContainer.innerHTML = `
      <div class="queue-mode-layout">
        ${viewContent}

        <!-- Controls Bar (Bottom) -->
        <div class="queue-controls">
          <div class="queue-view-tabs">
            <button class="queue-view-tab ${this.queueViewMode === 'overview' ? 'active' : ''}"
                    data-view="overview">OVERVIEW</button>
            <button class="queue-view-tab ${this.queueViewMode === 'table' ? 'active' : ''}"
                    data-view="table">TABLE</button>
            <button class="queue-view-tab ${this.queueViewMode === 'manage' ? 'active' : ''}"
                    data-view="manage">MANAGE</button>
          </div>
          <div class="queue-global-actions">
            <button class="btn btn-warning btn-sm" id="queue-pause-all">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
              </svg>
              PAUSE ALL
            </button>
            <button class="btn btn-success btn-sm" id="queue-resume-all">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"/>
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
              </svg>
              RESUME ALL
            </button>
            <button class="btn btn-ghost btn-sm" id="queue-refresh" title="Refresh">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
              </svg>
            </button>
          </div>
        </div>
      </div>
    `

    this._bindQueueModeEvents(queueContainer)
    if (this.queueViewMode === 'table') {
      this._initQueuePanelResize(queueContainer)
    }
  },

  _renderQueueOverviewContent() {
    const metrics = this._calculateQueueMetrics()
    const targetActivity = this._calculateTargetActivity()

    return `
      <div class="queue-overview">
        <!-- Large Metric Cards -->
        <div class="queue-overview-metrics">
          <div class="queue-metric-card-lg queue-metric-queued">
            <span class="queue-metric-card-value">${metrics.counts.pending + metrics.counts.executing}</span>
            <span class="queue-metric-card-label">QUEUED</span>
          </div>
          <div class="queue-metric-card-lg queue-metric-pending">
            <span class="queue-metric-card-value">${metrics.counts.pending}</span>
            <span class="queue-metric-card-label">PENDING</span>
          </div>
          <div class="queue-metric-card-lg queue-metric-executing">
            <span class="queue-metric-card-value">${metrics.counts.executing}</span>
            <span class="queue-metric-card-label">EXECUTING</span>
          </div>
          <div class="queue-metric-card-lg queue-metric-failed">
            <span class="queue-metric-card-value">${metrics.counts.failed}</span>
            <span class="queue-metric-card-label">FAILED</span>
          </div>
          <div class="queue-metric-card-lg queue-metric-success">
            <span class="queue-metric-card-value">${metrics.successRate}%</span>
            <span class="queue-metric-card-label">SUCCESS RATE</span>
          </div>
        </div>

        <!-- Charts Row -->
        <div class="queue-overview-charts">
          <!-- Status Breakdown -->
          <div class="queue-chart-panel">
            <div class="queue-chart-header">
              <span class="mc-label-subsystem">STATUS BREAKDOWN</span>
            </div>
            <div class="queue-status-chart">
              ${this._renderStatusBreakdownChart(metrics)}
            </div>
          </div>

          <!-- Target Activity -->
          <div class="queue-chart-panel">
            <div class="queue-chart-header">
              <span class="mc-label-subsystem">TARGET ACTIVITY</span>
            </div>
            <div class="queue-target-activity">
              ${this._renderTargetActivityChart(targetActivity)}
            </div>
          </div>
        </div>

        <!-- Quick Actions -->
        <div class="queue-overview-actions">
          <span class="mc-label-subsystem">QUICK ACTIONS</span>
          <div class="queue-quick-actions">
            <button class="btn btn-error btn-sm" id="queue-retry-failed" ${metrics.counts.failed === 0 ? 'disabled' : ''}>
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
              </svg>
              RETRY ALL FAILED (${metrics.counts.failed})
            </button>
            <button class="btn btn-ghost btn-sm" id="queue-clear-completed" ${metrics.counts.completed === 0 ? 'disabled' : ''}>
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
              </svg>
              CLEAR COMPLETED (${metrics.counts.completed})
            </button>
          </div>
        </div>
      </div>
    `
  },

  _renderQueueManageContent() {
    const selectedTarget = this.queueManageSelectedTarget
    const selectedTargetData = selectedTarget
      ? this.targets.find(t => t.id === selectedTarget)
      : null

    // Calculate queue stats per target
    const targetStats = this._calculateTargetQueueStats()

    return `
      <div class="queue-manage-view">
        <!-- Left Panel: Target List -->
        <div class="queue-manage-target-panel">
          <div class="queue-panel-header">
            <span class="mc-label-subsystem">TARGET QUEUES</span>
          </div>
          <div class="queue-manage-target-list">
            ${this.targets.map(target => {
              const stats = targetStats.get(target.id) || { pending: 0, executing: 0, paused: false }
              const isSelected = selectedTarget === target.id
              const isPaused = this.queueTargetStatuses.get(target.id)?.paused || false

              return `
                <div class="queue-manage-target-item ${isSelected ? 'selected' : ''} ${isPaused ? 'paused' : ''}"
                     data-target-id="${target.id}">
                  <div class="queue-manage-target-info">
                    <span class="queue-manage-target-name">${target.name}</span>
                    <span class="queue-manage-target-stats">
                      ${stats.pending + stats.executing + (stats.failed || 0)} queued${stats.failed > 0 ? ` (${stats.failed} failed)` : ''}
                    </span>
                  </div>
                  <button class="queue-manage-pause-btn ${isPaused ? 'paused' : ''}"
                          data-target-id="${target.id}"
                          title="${isPaused ? 'Resume queue' : 'Pause queue'}">
                    ${isPaused
                      ? `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                           <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"/>
                           <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
                         </svg>`
                      : `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                           <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
                         </svg>`
                    }
                  </button>
                </div>
              `
            }).join('')}
          </div>
        </div>

        <!-- Right Panel: Queue Detail -->
        <div class="queue-manage-detail-panel">
          ${selectedTargetData
            ? this._renderQueueDetailPanel(selectedTargetData, targetStats.get(selectedTarget) || { pending: 0, executing: 0, paused: false })
            : `<div class="queue-manage-empty-state">
                 <svg class="w-12 h-12 text-neutral-text" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                   <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"/>
                 </svg>
                 <span>Select a target to manage its queue</span>
               </div>`
          }
        </div>
      </div>
    `
  },

  _renderQueueDetailPanel(target, stats) {
    const isPaused = this.queueTargetStatuses.get(target.id)?.paused || false
    const entries = this.queueEntries.filter(e =>
      e.target_id === target.id &&
      ['pending', 'executing', 'failed'].includes(e.status)
    ).sort((a, b) => {
      // Sort by status (executing first, then pending, then failed), then priority, then sequence
      const statusOrder = { executing: 0, pending: 1, failed: 2 }
      const statusDiff = (statusOrder[a.status] || 99) - (statusOrder[b.status] || 99)
      if (statusDiff !== 0) return statusDiff
      if (a.priority !== b.priority) return a.priority - b.priority
      return (a.sequence_number || 0) - (b.sequence_number || 0)
    })

    return `
      <div class="queue-detail-header">
        <div class="queue-detail-title">
          <span class="queue-detail-target-name">${target.name}</span>
          <span class="queue-detail-status ${isPaused ? 'paused' : 'active'}">
            ${isPaused ? 'PAUSED' : 'ACTIVE'}
          </span>
        </div>
        <div class="queue-detail-stats">
          <span>Pending: <strong>${stats.pending}</strong></span>
          <span>Executing: <strong>${stats.executing}</strong></span>
          ${stats.failed > 0 ? `<span class="text-error">Failed: <strong>${stats.failed}</strong></span>` : ''}
        </div>
      </div>

      <div class="queue-detail-actions">
        <button class="btn ${isPaused ? 'btn-success' : 'btn-warning'} btn-sm"
                id="queue-detail-toggle-pause"
                data-target-id="${target.id}">
          ${isPaused ? 'RESUME QUEUE' : 'PAUSE QUEUE'}
        </button>
        <button class="btn btn-error btn-sm"
                id="queue-detail-cancel-all"
                data-target-id="${target.id}"
                ${entries.length === 0 ? 'disabled' : ''}>
          CANCEL ALL (${entries.length})
        </button>
      </div>

      <div class="queue-detail-table-wrapper">
        ${entries.length === 0
          ? `<div class="queue-detail-empty">
               <span>No commands queued for this target</span>
             </div>`
          : `<table class="queue-detail-table">
               <thead>
                 <tr>
                   <th class="queue-detail-th-pos">#</th>
                   <th class="queue-detail-th-pri">PRI</th>
                   <th class="queue-detail-th-cmd">COMMAND</th>
                   <th class="queue-detail-th-status">STATUS</th>
                   <th class="queue-detail-th-actions"></th>
                 </tr>
               </thead>
               <tbody>
                 ${entries.map((entry, index) => `
                   <tr class="queue-detail-row queue-status-${entry.status}">
                     <td class="queue-detail-td-pos">${index + 1}</td>
                     <td class="queue-detail-td-pri">
                       <span class="queue-priority-badge priority-${entry.priority}">P${entry.priority}</span>
                     </td>
                     <td class="queue-detail-td-cmd">${entry.command_name}</td>
                     <td class="queue-detail-td-status">
                       <span class="queue-status-badge status-${entry.status}">${entry.status.toUpperCase()}</span>
                     </td>
                     <td class="queue-detail-td-actions">
                       ${entry.status === 'pending'
                         ? `<button class="queue-cancel-entry-btn"
                                    data-entry-id="${entry.id}"
                                    data-target-id="${target.id}"
                                    title="Cancel command">
                              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                              </svg>
                            </button>`
                         : ''
                       }
                     </td>
                   </tr>
                 `).join('')}
               </tbody>
             </table>`
        }
      </div>
    `
  },

  _calculateTargetQueueStats() {
    const stats = new Map()

    // Initialize all targets with zero counts
    this.targets.forEach(target => {
      stats.set(target.id, { pending: 0, executing: 0, failed: 0, paused: false })
    })

    // Count entries per target
    this.queueEntries.forEach(entry => {
      if (!entry.target_id) return
      let targetStats = stats.get(entry.target_id)

      // If target not in our list, create a stats entry for it anyway
      if (!targetStats) {
        targetStats = { pending: 0, executing: 0, failed: 0, paused: false }
        stats.set(entry.target_id, targetStats)
      }

      if (entry.status === 'pending') {
        targetStats.pending++
      } else if (entry.status === 'executing') {
        targetStats.executing++
      } else if (entry.status === 'failed') {
        targetStats.failed++
      }
    })

    return stats
  },

  _renderQueueTableContent() {
    const selectedCount = this.queueSelectedTargets.size
    const totalTargets = this.targets.length

    return `
      <div class="queue-table-view">
        <!-- Main Panels Row -->
        <div class="queue-panels-row">
          <!-- Left: Target Selection Panel -->
          <div class="queue-target-panel" style="flex: 0 0 ${this.queueTargetPanelWidth}%">
            <div class="queue-panel-header">
              <div class="queue-panel-title">
                <span class="mc-label-subsystem">TARGET FILTER</span>
                <span class="queue-selection-count">${selectedCount === 0 ? 'All' : selectedCount} of ${totalTargets}</span>
              </div>
              <div class="queue-panel-actions">
                <button class="queue-view-toggle ${this.queueTargetViewMode === 'compact' ? 'active' : ''}"
                        data-view="compact" title="Compact view">
                  <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 10h16M4 14h16M4 18h16"/>
                  </svg>
                </button>
                <button class="queue-view-toggle ${this.queueTargetViewMode === 'detailed' ? 'active' : ''}"
                        data-view="detailed" title="Detailed view">
                  <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z"/>
                  </svg>
                </button>
              </div>
            </div>

            <div class="queue-target-filters">
              <input type="text"
                     class="queue-target-search"
                     id="queue-target-search"
                     placeholder="Search targets..."
                     value="${this.queueTargetSearch}">
            </div>

            <div class="queue-target-grid ${this.queueTargetViewMode}">
              ${this._renderQueueTargetGrid()}
            </div>

            <div class="queue-selection-actions">
              <button class="btn btn-ghost btn-xs" id="queue-select-all-targets">Select All</button>
              <button class="btn btn-ghost btn-xs" id="queue-clear-targets">Clear</button>
            </div>
          </div>

          <!-- Resize Handle -->
          <div class="queue-resize-handle" id="queue-resize-handle">
            <div class="queue-resize-grip"></div>
          </div>

          <!-- Right: Queue Panel -->
          <div class="queue-main-panel">
            <!-- Filter Bar -->
            <div class="queue-filter-bar">
              ${this._renderQueueFilterBar()}
            </div>

            <!-- Queue Table -->
            <div class="queue-table-container">
              ${this._renderQueueTable()}
            </div>

            <!-- Bulk Actions Bar -->
            <div class="queue-bulk-bar">
              <span class="queue-selected-count">${this.queueSelectedEntries.size} selected</span>
              <button class="btn btn-ghost btn-xs" id="queue-bulk-cancel"
                      ${this.queueSelectedEntries.size === 0 ? 'disabled' : ''}>
                CANCEL SELECTED
              </button>
            </div>
          </div>
        </div>
      </div>
    `
  },

  _calculateTargetActivity() {
    const entries = this.queueEntries || []
    const activity = new Map()

    // Count entries per target
    entries.forEach(entry => {
      const targetId = entry.target_id
      const targetName = entry.target_name || 'Unknown'
      if (!activity.has(targetId)) {
        activity.set(targetId, { id: targetId, name: targetName, count: 0 })
      }
      activity.get(targetId).count++
    })

    // Sort by count descending, take top 10
    return Array.from(activity.values())
      .sort((a, b) => b.count - a.count)
      .slice(0, 10)
  },

  _renderStatusBreakdownChart(metrics) {
    const statuses = [
      { key: 'pending', label: 'Pending', count: metrics.counts.pending, color: 'var(--badge-pending)' },
      { key: 'executing', label: 'Executing', count: metrics.counts.executing, color: 'var(--glow-cyan)' },
      { key: 'failed', label: 'Failed', count: metrics.counts.failed, color: 'var(--status-critical)' },
      { key: 'completed', label: 'Completed', count: metrics.counts.completed, color: 'var(--status-success)' },
      { key: 'cancelled', label: 'Cancelled', count: metrics.counts.cancelled, color: 'var(--neutral-text)' }
    ].filter(s => s.count > 0)

    const maxCount = Math.max(...statuses.map(s => s.count), 1)

    return statuses.map(status => `
      <div class="queue-status-bar-item">
        <div class="queue-status-bar-label">
          <span class="queue-status-bar-name">${status.label}</span>
          <span class="queue-status-bar-count">${status.count}</span>
        </div>
        <div class="queue-status-bar-track">
          <div class="queue-status-bar-fill" style="width: ${(status.count / maxCount) * 100}%; background: ${status.color}"></div>
        </div>
      </div>
    `).join('')
  },

  _renderTargetActivityChart(targetActivity) {
    if (targetActivity.length === 0) {
      return `<div class="queue-chart-empty">No target activity</div>`
    }

    const maxCount = Math.max(...targetActivity.map(t => t.count), 1)

    return targetActivity.map(target => `
      <div class="queue-target-bar-item" data-target-id="${target.id}">
        <div class="queue-target-bar-label">
          <span class="queue-target-bar-name">${target.name}</span>
          <span class="queue-target-bar-count">${target.count}</span>
        </div>
        <div class="queue-target-bar-track">
          <div class="queue-target-bar-fill" style="width: ${(target.count / maxCount) * 100}%"></div>
        </div>
      </div>
    `).join('')
  },

  _hideQueueMode() {
    const dashboard = this.panelLayout?.elements?.dashboard
    if (!dashboard) return

    const queueContainer = dashboard.querySelector(".queue-mode-container")
    if (queueContainer) {
      queueContainer.innerHTML = ""
    }
  },

  _hideAlarmsMode() {
    const dashboard = this.panelLayout?.elements?.dashboard
    if (!dashboard) return

    const alarmsContainer = dashboard.querySelector(".alarms-mode-container")
    if (alarmsContainer) {
      alarmsContainer.innerHTML = ""
    }
  },

  _calculateQueueMetrics() {
    // Use server-side metrics if available (accurate counts from database)
    if (this.queueServerMetrics) {
      const m = this.queueServerMetrics
      return {
        counts: {
          pending: m.pending || 0,
          executing: m.executing || 0,
          completed: m.completed || 0,
          failed: m.failed || 0,
          cancelled: m.cancelled || 0,
          expired: m.expired || 0
        },
        total: m.total || 0,
        successRate: Math.round(m.success_rate || 100)
      }
    }

    // Fallback to client-side calculation from fetched entries
    const entries = this.queueEntries || []

    const counts = {
      pending: entries.filter(e => e.status === 'pending').length,
      executing: entries.filter(e => e.status === 'executing').length,
      completed: entries.filter(e => e.status === 'completed').length,
      failed: entries.filter(e => e.status === 'failed').length,
      cancelled: entries.filter(e => e.status === 'cancelled').length,
      expired: entries.filter(e => e.status === 'expired').length
    }

    const total = Object.values(counts).reduce((a, b) => a + b, 0)
    const successful = counts.completed
    const attempted = counts.completed + counts.failed
    const successRate = attempted > 0 ? Math.round((successful / attempted) * 100) : 100

    return { counts, total, successRate }
  },

  _renderQueueMetricsSummary(metrics) {
    return `
      <div class="queue-metric queue-metric-total">
        <span class="queue-metric-value">${metrics.counts.pending + metrics.counts.executing}</span>
        <span class="queue-metric-label">QUEUED</span>
      </div>
      <div class="queue-metric queue-metric-pending">
        <span class="queue-metric-value">${metrics.counts.pending}</span>
        <span class="queue-metric-label">PENDING</span>
      </div>
      <div class="queue-metric queue-metric-executing">
        <span class="queue-metric-value">${metrics.counts.executing}</span>
        <span class="queue-metric-label">EXECUTING</span>
      </div>
      <div class="queue-metric queue-metric-failed">
        <span class="queue-metric-value">${metrics.counts.failed}</span>
        <span class="queue-metric-label">FAILED</span>
      </div>
      <div class="queue-metric queue-metric-success">
        <span class="queue-metric-value">${metrics.successRate}%</span>
        <span class="queue-metric-label">SUCCESS</span>
      </div>
    `
  },

  _renderQueueMetricsDetail(metrics) {
    return `
      <div class="queue-metrics-grid">
        <div class="queue-metric-card">
          <span class="queue-metric-card-value">${metrics.counts.completed}</span>
          <span class="queue-metric-card-label">COMPLETED</span>
        </div>
        <div class="queue-metric-card">
          <span class="queue-metric-card-value">${metrics.counts.cancelled}</span>
          <span class="queue-metric-card-label">CANCELLED</span>
        </div>
        <div class="queue-metric-card">
          <span class="queue-metric-card-value">${metrics.counts.expired}</span>
          <span class="queue-metric-card-label">EXPIRED</span>
        </div>
        <div class="queue-metric-card">
          <span class="queue-metric-card-value">${metrics.total}</span>
          <span class="queue-metric-card-label">TOTAL</span>
        </div>
      </div>
    `
  },

  _renderQueueTargetGrid() {
    // Filter targets by search
    const filteredTargets = this.targets.filter(t => {
      if (!this.queueTargetSearch) return true
      const search = this.queueTargetSearch.toLowerCase()
      return t.name?.toLowerCase().includes(search) ||
             t.identifier?.toLowerCase().includes(search)
    })

    if (filteredTargets.length === 0) {
      return `
        <div class="queue-target-empty">
          <p>No targets match filter</p>
        </div>
      `
    }

    return filteredTargets.map(target => {
      const isSelected = this.queueSelectedTargets.has(target.id)

      // Get target status and queue info
      const statusClass = target.connection_status || 'unknown'
      const queuedCount = (this.queueEntries || []).filter(e =>
        e.target_id === target.id && ['pending', 'executing'].includes(e.status)
      ).length

      // Get alarm count for this target
      const alarmCount = (this.alarms || []).filter(a =>
        a.target_id === target.id && a.active
      ).length

      if (this.queueTargetViewMode === 'detailed') {
        return `
          <div class="queue-target-cell ${isSelected ? 'selected' : ''} status-${statusClass}"
               data-target-id="${target.id}">
            <div class="queue-target-main">
              <span class="queue-target-name">${target.name}</span>
              <span class="queue-target-status-dot status-${statusClass}"></span>
            </div>
            <div class="queue-target-meta">
              ${queuedCount > 0 ? `<span class="queue-target-queued">${queuedCount} queued</span>` : ''}
              ${alarmCount > 0 ? `<span class="queue-target-alarms">${alarmCount} alarms</span>` : ''}
            </div>
          </div>
        `
      }

      // Compact view
      return `
        <div class="queue-target-cell ${isSelected ? 'selected' : ''} status-${statusClass} ${alarmCount > 0 ? 'has-alarms' : ''}"
             data-target-id="${target.id}">
          <span class="queue-target-name">${target.name}</span>
          ${queuedCount > 0 ? `<span class="queue-target-badge">${queuedCount}</span>` : ''}
        </div>
      `
    }).join('')
  },

  _renderQueueFilterBar() {
    const statusButtons = ['pending', 'executing', 'failed', 'completed'].map(status => `
      <button class="queue-status-btn ${this.queueStatusFilter.has(status) ? 'active' : ''}"
              data-status="${status}">${status.toUpperCase()}</button>
    `).join('')

    // Priority range display
    const priorityDisplay = this._getPriorityRangeDisplay()

    return `
      <!-- Row 1: Search & Status -->
      <div class="queue-filter-row">
        <input type="text"
               class="queue-search"
               id="queue-search"
               placeholder="Search commands..."
               value="${this.queueSearchQuery}">

        <div class="queue-status-filters">
          ${statusButtons}
        </div>
      </div>

      <!-- Row 2: Priority Range & Actions -->
      <div class="queue-filter-row">
        <div class="queue-priority-range">
          <span class="queue-priority-label">PRIORITY</span>
          <div class="queue-range-slider">
            <input type="range"
                   id="queue-range-min"
                   class="queue-range-input queue-range-min"
                   min="0" max="5" step="1"
                   value="${this.queuePriorityMin}">
            <input type="range"
                   id="queue-range-max"
                   class="queue-range-input queue-range-max"
                   min="0" max="5" step="1"
                   value="${this.queuePriorityMax}">
            <div class="queue-range-track">
              <div class="queue-range-fill" id="queue-range-fill"></div>
            </div>
          </div>
          <span class="queue-priority-value" id="queue-priority-display">${priorityDisplay}</span>
        </div>

        <div class="queue-filter-actions">
          <button class="btn btn-ghost btn-xs" id="queue-clear-filters">CLEAR</button>
          <span class="queue-entry-count">${this._getFilteredQueueEntries().length} entries</span>
        </div>
      </div>
    `
  },

  _getPriorityRangeDisplay() {
    if (this.queuePriorityMin === 0 && this.queuePriorityMax === 5) {
      return 'ALL'
    } else if (this.queuePriorityMin === this.queuePriorityMax) {
      return `P${this.queuePriorityMin}`
    } else {
      return `P${this.queuePriorityMin} – P${this.queuePriorityMax}`
    }
  },

  _updatePriorityRangeDisplay(container) {
    // Update text display
    const displayEl = container.querySelector('#queue-priority-display')
    if (displayEl) {
      displayEl.textContent = this._getPriorityRangeDisplay()
    }

    // Update range fill visual
    const fillEl = container.querySelector('#queue-range-fill')
    if (fillEl) {
      const minPercent = (this.queuePriorityMin / 5) * 100
      const maxPercent = (this.queuePriorityMax / 5) * 100
      fillEl.style.left = `${minPercent}%`
      fillEl.style.width = `${maxPercent - minPercent}%`
    }

    // Sync slider positions (in case they were swapped)
    const minSlider = container.querySelector('#queue-range-min')
    const maxSlider = container.querySelector('#queue-range-max')
    if (minSlider) minSlider.value = this.queuePriorityMin
    if (maxSlider) maxSlider.value = this.queuePriorityMax
  },

  _renderQueueTable() {
    const entries = this._getFilteredQueueEntries()

    if (entries.length === 0) {
      return `
        <div class="queue-table-empty">
          <svg class="w-12 h-12 text-base-content/20" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                  d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"/>
          </svg>
          <p class="text-base-content/40">No queue entries match your filters</p>
        </div>
      `
    }

    const sortIndicator = (col) => {
      if (this.queueSortColumn !== col) return ''
      return this.queueSortDirection === 'asc' ? ' ↑' : ' ↓'
    }

    return `
      <table class="queue-table">
        <thead>
          <tr>
            <th class="queue-th queue-th-checkbox">
              <input type="checkbox" class="checkbox checkbox-xs" id="queue-select-all">
            </th>
            <th class="queue-th queue-th-target sortable" data-sort="target_name">
              TARGET${sortIndicator('target_name')}
            </th>
            <th class="queue-th queue-th-command sortable" data-sort="command_name">
              COMMAND${sortIndicator('command_name')}
            </th>
            <th class="queue-th queue-th-status sortable" data-sort="status">
              STATUS${sortIndicator('status')}
            </th>
            <th class="queue-th queue-th-priority sortable" data-sort="priority">
              PRI${sortIndicator('priority')}
            </th>
            <th class="queue-th queue-th-scheduled sortable" data-sort="scheduled_at">
              SCHEDULED${sortIndicator('scheduled_at')}
            </th>
            <th class="queue-th queue-th-attempts">
              ATT
            </th>
            <th class="queue-th queue-th-actions">
              ACTIONS
            </th>
          </tr>
        </thead>
        <tbody>
          ${entries.map(entry => this._renderQueueTableRow(entry)).join('')}
        </tbody>
      </table>
    `
  },

  _renderQueueTableRow(entry) {
    const statusClass = `queue-status-${entry.status}`
    const priorityClass = `queue-priority-${entry.priority}`
    const isSelected = this.queueSelectedEntries.has(entry.id)

    const scheduledTime = entry.scheduled_at
      ? new Date(entry.scheduled_at).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false })
      : '—'

    return `
      <tr class="queue-row ${statusClass} ${isSelected ? 'selected' : ''}" data-entry-id="${entry.id}">
        <td class="queue-td queue-td-checkbox">
          <input type="checkbox" class="checkbox checkbox-xs queue-entry-checkbox"
                 data-id="${entry.id}" ${isSelected ? 'checked' : ''}>
        </td>
        <td class="queue-td queue-td-target">
          <span class="queue-target-name">${entry.target_name || 'Unknown'}</span>
        </td>
        <td class="queue-td queue-td-command">
          <span class="queue-command-name">${entry.command_name}</span>
        </td>
        <td class="queue-td queue-td-status">
          <span class="queue-status-badge ${statusClass}">${entry.status.toUpperCase()}</span>
        </td>
        <td class="queue-td queue-td-priority">
          <span class="queue-priority-badge ${priorityClass}">${entry.priority}</span>
        </td>
        <td class="queue-td queue-td-scheduled">
          ${scheduledTime}
        </td>
        <td class="queue-td queue-td-attempts">
          ${entry.attempts || 0}/${entry.max_attempts || 3}
        </td>
        <td class="queue-td queue-td-actions">
          <div class="queue-row-actions">
            ${entry.status === 'pending' ? `
              <button class="btn btn-ghost btn-xs queue-action-priority" data-id="${entry.id}"
                      data-target-id="${entry.target_id}" title="Change Priority">
                <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16V4m0 0L3 8m4-4l4 4m6 0v12m0 0l4-4m-4 4l-4-4"/>
                </svg>
              </button>
              <button class="btn btn-ghost btn-xs queue-action-cancel" data-id="${entry.id}"
                      data-target-id="${entry.target_id}" title="Cancel">
                <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                </svg>
              </button>
            ` : ''}
            ${entry.status === 'failed' && entry.last_error ? `
              <button class="btn btn-ghost btn-xs queue-action-error" data-id="${entry.id}"
                      data-error="${encodeURIComponent(entry.last_error)}" title="View Error">
                <svg class="w-3 h-3 text-error" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
                </svg>
              </button>
            ` : ''}
          </div>
        </td>
      </tr>
    `
  },

  _renderQueueActionsBar() {
    const selectedCount = this.queueSelectedEntries.size

    return `
      <div class="queue-bulk-actions">
        <span class="queue-selected-count">${selectedCount} selected</span>
        <button class="btn btn-ghost btn-xs" id="queue-bulk-cancel" ${selectedCount === 0 ? 'disabled' : ''}>
          Cancel Selected
        </button>
      </div>

      <div class="queue-global-actions">
        <button class="btn btn-outline btn-xs btn-warning" id="queue-pause-all">
          <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
          </svg>
          PAUSE ALL
        </button>
        <button class="btn btn-outline btn-xs btn-success" id="queue-resume-all">
          <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"/>
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
          </svg>
          RESUME ALL
        </button>
        <button class="btn btn-ghost btn-xs" id="queue-refresh" title="Refresh">
          <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
          </svg>
        </button>
      </div>
    `
  },

  _getFilteredQueueEntries() {
    let entries = this.queueEntries || []

    // Filter by selected targets (if any selected, show only those; if none, show all)
    if (this.queueSelectedTargets.size > 0) {
      entries = entries.filter(e => this.queueSelectedTargets.has(e.target_id))
    }

    // Filter by status
    if (this.queueStatusFilter.size > 0) {
      entries = entries.filter(e => this.queueStatusFilter.has(e.status))
    }

    // Filter by priority range
    entries = entries.filter(e =>
      e.priority >= this.queuePriorityMin &&
      e.priority <= this.queuePriorityMax
    )

    // Search filter
    if (this.queueSearchQuery) {
      const query = this.queueSearchQuery.toLowerCase()
      entries = entries.filter(e =>
        e.command_name?.toLowerCase().includes(query) ||
        e.target_name?.toLowerCase().includes(query)
      )
    }

    // Sort
    entries = [...entries].sort((a, b) => {
      let aVal = a[this.queueSortColumn]
      let bVal = b[this.queueSortColumn]

      // Handle null/undefined
      if (aVal == null) aVal = ''
      if (bVal == null) bVal = ''

      if (typeof aVal === 'string') aVal = aVal.toLowerCase()
      if (typeof bVal === 'string') bVal = bVal.toLowerCase()

      if (aVal < bVal) return this.queueSortDirection === 'asc' ? -1 : 1
      if (aVal > bVal) return this.queueSortDirection === 'asc' ? 1 : -1
      return 0
    })

    return entries
  },

  _getPriorityLabel(priority) {
    const labels = ['EMERGENCY', 'CRITICAL', 'HIGH', 'NORMAL', 'LOW', 'BACKGROUND']
    return labels[priority] || 'UNKNOWN'
  },

  _bindQueueModeEvents(container) {
    // View tab switching
    container.querySelectorAll('.queue-view-tab').forEach(tab => {
      tab.addEventListener('click', () => {
        const view = tab.dataset.view
        if (view && view !== this.queueViewMode) {
          this.queueViewMode = view
          this._renderQueueMode()
        }
      })
    })

    // Global actions (available in both views)
    container.querySelector('#queue-pause-all')?.addEventListener('click', () => {
      this.pushEvent('queue_pause_all', {})
    })

    container.querySelector('#queue-resume-all')?.addEventListener('click', () => {
      this.pushEvent('queue_resume_all', {})
    })

    container.querySelector('#queue-refresh')?.addEventListener('click', () => {
      this.pushEvent('queue_refresh', {})
    })

    // Overview-specific events
    if (this.queueViewMode === 'overview') {
      // Retry all failed
      container.querySelector('#queue-retry-failed')?.addEventListener('click', () => {
        this.pushEvent('queue_retry_all_failed', {})
      })

      // Clear completed
      container.querySelector('#queue-clear-completed')?.addEventListener('click', () => {
        this.pushEvent('queue_clear_completed', {})
      })

      // Target bar click - switch to table view filtered to that target
      container.querySelectorAll('.queue-target-bar-item').forEach(item => {
        item.addEventListener('click', () => {
          const targetId = item.dataset.targetId
          if (targetId) {
            this.queueSelectedTargets.clear()
            this.queueSelectedTargets.add(targetId)
            this.queueViewMode = 'table'
            this._renderQueueMode()
          }
        })
      })

      return // Skip other view-specific event bindings
    }

    // Manage view-specific events
    if (this.queueViewMode === 'manage') {
      // Target item click - select target
      container.querySelectorAll('.queue-manage-target-item').forEach(item => {
        item.addEventListener('click', (e) => {
          // Don't select if clicking the pause button
          if (e.target.closest('.queue-manage-pause-btn')) return

          const targetId = item.dataset.targetId
          if (targetId && targetId !== this.queueManageSelectedTarget) {
            this.queueManageSelectedTarget = targetId
            this._renderQueueMode()
          }
        })
      })

      // Pause/resume buttons in target list
      container.querySelectorAll('.queue-manage-pause-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
          e.stopPropagation()
          const targetId = btn.dataset.targetId
          const isPaused = this.queueTargetStatuses.get(targetId)?.paused || false

          if (isPaused) {
            this.pushEvent('queue_resume_target', { target_id: targetId })
          } else {
            this.pushEvent('queue_pause_target', { target_id: targetId })
          }
        })
      })

      // Detail panel: toggle pause
      container.querySelector('#queue-detail-toggle-pause')?.addEventListener('click', () => {
        const targetId = this.queueManageSelectedTarget
        if (!targetId) return

        const isPaused = this.queueTargetStatuses.get(targetId)?.paused || false
        if (isPaused) {
          this.pushEvent('queue_resume_target', { target_id: targetId })
        } else {
          this.pushEvent('queue_pause_target', { target_id: targetId })
        }
      })

      // Detail panel: cancel all
      container.querySelector('#queue-detail-cancel-all')?.addEventListener('click', () => {
        const targetId = this.queueManageSelectedTarget
        if (!targetId) return

        if (confirm('Cancel all queued commands for this target?')) {
          this.pushEvent('queue_cancel_all_target', { target_id: targetId })
        }
      })

      // Cancel individual entry buttons
      container.querySelectorAll('.queue-cancel-entry-btn').forEach(btn => {
        btn.addEventListener('click', () => {
          const entryId = btn.dataset.entryId
          const targetId = btn.dataset.targetId
          if (entryId && targetId) {
            this.pushEvent('queue_cancel_entry', { entry_id: entryId, target_id: targetId })
          }
        })
      })

      return // Skip table-specific event bindings
    }

    // Table view-specific events below

    // Search with debounce
    container.querySelector('#queue-search')?.addEventListener('input', (e) => {
      this.queueSearchQuery = e.target.value
      if (this._queueSearchDebounce) clearTimeout(this._queueSearchDebounce)
      this._queueSearchDebounce = setTimeout(() => {
        this._updateQueueTable(container)
      }, 150)
    })

    // Target panel: target cell clicks (multi-select)
    container.querySelectorAll('.queue-target-cell').forEach(cell => {
      cell.addEventListener('click', () => {
        const targetId = cell.dataset.targetId
        if (this.queueSelectedTargets.has(targetId)) {
          this.queueSelectedTargets.delete(targetId)
          cell.classList.remove('selected')
        } else {
          this.queueSelectedTargets.add(targetId)
          cell.classList.add('selected')
        }
        this._updateQueueTargetCount(container)
        this._updateQueueTable(container)
      })
    })

    // Target panel: search filter
    container.querySelector('#queue-target-search')?.addEventListener('input', (e) => {
      this.queueTargetSearch = e.target.value
      if (this._queueTargetSearchDebounce) clearTimeout(this._queueTargetSearchDebounce)
      this._queueTargetSearchDebounce = setTimeout(() => {
        this._updateQueueTargetGrid(container)
      }, 150)
    })

    // Target panel: view mode toggle (compact/detailed)
    container.querySelectorAll('.queue-view-toggle').forEach(btn => {
      btn.addEventListener('click', () => {
        this.queueTargetViewMode = btn.dataset.view
        container.querySelectorAll('.queue-view-toggle').forEach(b => b.classList.remove('active'))
        btn.classList.add('active')
        const grid = container.querySelector('.queue-target-grid')
        if (grid) {
          grid.classList.remove('compact', 'detailed')
          grid.classList.add(this.queueTargetViewMode)
          grid.innerHTML = this._renderQueueTargetGrid()
        }
        // Re-bind target cell events
        this._bindQueueTargetCellEvents(container)
      })
    })

    // Target panel: select all targets
    container.querySelector('#queue-select-all-targets')?.addEventListener('click', () => {
      // Select all visible (filtered) targets
      const visibleCells = container.querySelectorAll('.queue-target-cell')
      visibleCells.forEach(cell => {
        this.queueSelectedTargets.add(cell.dataset.targetId)
        cell.classList.add('selected')
      })
      this._updateQueueTargetCount(container)
      this._updateQueueTable(container)
    })

    // Target panel: clear selection
    container.querySelector('#queue-clear-targets')?.addEventListener('click', () => {
      this.queueSelectedTargets.clear()
      container.querySelectorAll('.queue-target-cell').forEach(cell => {
        cell.classList.remove('selected')
      })
      this._updateQueueTargetCount(container)
      this._updateQueueTable(container)
    })

    // Status filters
    container.querySelectorAll('.queue-status-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        const status = btn.dataset.status
        if (this.queueStatusFilter.has(status)) {
          this.queueStatusFilter.delete(status)
        } else {
          this.queueStatusFilter.add(status)
        }
        btn.classList.toggle('active')
        this._updateQueueTable(container)
      })
    })

    // Priority range slider handlers
    const minSlider = container.querySelector('#queue-range-min')
    const maxSlider = container.querySelector('#queue-range-max')

    const updatePriorityRange = () => {
      let min = parseInt(minSlider?.value || 0)
      let max = parseInt(maxSlider?.value || 5)

      // Ensure min <= max by swapping if needed
      if (min > max) {
        [min, max] = [max, min]
      }

      this.queuePriorityMin = min
      this.queuePriorityMax = max

      // Update the display
      this._updatePriorityRangeDisplay(container)
      this._updateQueueTable(container)
    }

    minSlider?.addEventListener('input', updatePriorityRange)
    maxSlider?.addEventListener('input', updatePriorityRange)

    // Clear filters
    container.querySelector('#queue-clear-filters')?.addEventListener('click', () => {
      // Note: We don't clear target selection from this button - that's done via the target panel
      this.queueStatusFilter = new Set(['pending', 'executing', 'failed'])
      this.queuePriorityMin = 0
      this.queuePriorityMax = 5
      this.queueSearchQuery = ''
      this._renderQueueMode()
    })

    // Sort columns
    container.querySelectorAll('.queue-th.sortable').forEach(th => {
      th.addEventListener('click', () => {
        const col = th.dataset.sort
        if (this.queueSortColumn === col) {
          this.queueSortDirection = this.queueSortDirection === 'asc' ? 'desc' : 'asc'
        } else {
          this.queueSortColumn = col
          this.queueSortDirection = 'asc'
        }
        this._updateQueueTable(container)
      })
    })

    // Bind table row events
    this._bindQueueTableEvents(container)

    // Bulk selection
    container.querySelector('#queue-select-all')?.addEventListener('change', (e) => {
      const checked = e.target.checked
      const entries = this._getFilteredQueueEntries()
      this.queueSelectedEntries.clear()
      if (checked) {
        entries.forEach(entry => this.queueSelectedEntries.add(entry.id))
      }
      container.querySelectorAll('.queue-entry-checkbox').forEach(cb => {
        cb.checked = checked
      })
      this._updateBulkActions(container)
    })

    // Bulk cancel
    container.querySelector('#queue-bulk-cancel')?.addEventListener('click', () => {
      if (this.queueSelectedEntries.size === 0) return

      // Get target_id for each selected entry
      this.queueSelectedEntries.forEach(entryId => {
        const entry = this.queueEntries.find(e => e.id === entryId)
        if (entry && entry.status === 'pending') {
          this.pushEvent('queue_cancel_command', {
            entry_id: entryId,
            target_id: entry.target_id
          })
        }
      })
      this.queueSelectedEntries.clear()
      this._updateBulkActions(container)
    })
  },

  _bindQueueTableEvents(container) {
    // Individual row checkboxes
    container.querySelectorAll('.queue-entry-checkbox').forEach(cb => {
      cb.addEventListener('change', () => {
        const id = cb.dataset.id
        if (cb.checked) {
          this.queueSelectedEntries.add(id)
        } else {
          this.queueSelectedEntries.delete(id)
        }
        this._updateBulkActions(container)
      })
    })

    // Cancel buttons
    container.querySelectorAll('.queue-action-cancel').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation()
        const entryId = btn.dataset.id
        const targetId = btn.dataset.targetId
        this.pushEvent('queue_cancel_command', { entry_id: entryId, target_id: targetId })
      })
    })

    // Priority change buttons
    container.querySelectorAll('.queue-action-priority').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation()
        const entryId = btn.dataset.id
        const targetId = btn.dataset.targetId
        this._showPriorityModal(entryId, targetId)
      })
    })

    // Error view buttons
    container.querySelectorAll('.queue-action-error').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation()
        const error = decodeURIComponent(btn.dataset.error)
        alert(`Command Error:\n\n${error}`)
      })
    })
  },

  _updateQueueTable(container) {
    const tableContainer = container.querySelector('.queue-table-container')
    if (tableContainer) {
      tableContainer.innerHTML = this._renderQueueTable()
      this._bindQueueTableEvents(container)
    }

    // Update count
    const countEl = container.querySelector('.queue-entry-count')
    if (countEl) {
      countEl.textContent = `${this._getFilteredQueueEntries().length} entries`
    }

    // Update select-all checkbox state
    const selectAll = container.querySelector('#queue-select-all')
    if (selectAll) {
      const entries = this._getFilteredQueueEntries()
      const allSelected = entries.length > 0 && entries.every(e => this.queueSelectedEntries.has(e.id))
      selectAll.checked = allSelected
    }
  },

  _updateQueueTargetCount(container) {
    const countEl = container.querySelector('.queue-selection-count')
    if (countEl) {
      const selectedCount = this.queueSelectedTargets.size
      const totalTargets = this.targets.length
      countEl.textContent = `${selectedCount === 0 ? 'All' : selectedCount} of ${totalTargets}`
    }
  },

  _updateQueueTargetGrid(container) {
    const grid = container.querySelector('.queue-target-grid')
    if (grid) {
      grid.innerHTML = this._renderQueueTargetGrid()
      this._bindQueueTargetCellEvents(container)
    }
  },

  _bindQueueTargetCellEvents(container) {
    container.querySelectorAll('.queue-target-cell').forEach(cell => {
      cell.addEventListener('click', () => {
        const targetId = cell.dataset.targetId
        if (this.queueSelectedTargets.has(targetId)) {
          this.queueSelectedTargets.delete(targetId)
          cell.classList.remove('selected')
        } else {
          this.queueSelectedTargets.add(targetId)
          cell.classList.add('selected')
        }
        this._updateQueueTargetCount(container)
        this._updateQueueTable(container)
      })
    })
  },

  _initQueuePanelResize(container) {
    const resizeHandle = container.querySelector('#queue-resize-handle')
    if (!resizeHandle) return

    resizeHandle.addEventListener('mousedown', (e) => {
      e.preventDefault()

      const panelsRow = container.querySelector('.queue-panels-row')
      const targetPanel = container.querySelector('.queue-target-panel')

      if (!panelsRow || !targetPanel) return

      resizeHandle.classList.add('dragging')

      const startX = e.clientX
      const layoutRect = panelsRow.getBoundingClientRect()
      const startWidth = targetPanel.getBoundingClientRect().width
      const layoutWidth = layoutRect.width

      const onMouseMove = (moveEvent) => {
        const deltaX = moveEvent.clientX - startX
        const newWidth = startWidth + deltaX
        const newPercent = (newWidth / layoutWidth) * 100

        // Clamp between 15% and 50%
        const clampedPercent = Math.max(15, Math.min(50, newPercent))

        targetPanel.style.flex = `0 0 ${clampedPercent}%`
        this.queueTargetPanelWidth = clampedPercent
      }

      const onMouseUp = () => {
        resizeHandle.classList.remove('dragging')
        document.removeEventListener('mousemove', onMouseMove)
        document.removeEventListener('mouseup', onMouseUp)
      }

      document.addEventListener('mousemove', onMouseMove)
      document.addEventListener('mouseup', onMouseUp)
    })
  },

  _updateBulkActions(container) {
    const selected = this.queueSelectedEntries.size
    const countEl = container.querySelector('.queue-selected-count')
    const cancelBtn = container.querySelector('#queue-bulk-cancel')

    if (countEl) countEl.textContent = `${selected} selected`
    if (cancelBtn) cancelBtn.disabled = selected === 0
  },

  _showPriorityModal(entryId, targetId) {
    const entry = this.queueEntries.find(e => e.id === entryId)
    if (!entry) return

    const currentPriority = entry.priority
    const newPriority = prompt(
      `Change priority for ${entry.command_name}\n\nCurrent: P${currentPriority} (${this._getPriorityLabel(currentPriority)})\n\nEnter new priority (0-5):\n0 = EMERGENCY\n1 = CRITICAL\n2 = HIGH\n3 = NORMAL\n4 = LOW\n5 = BACKGROUND`,
      currentPriority.toString()
    )

    if (newPriority !== null) {
      const priority = parseInt(newPriority)
      if (priority >= 0 && priority <= 5 && priority !== currentPriority) {
        this.pushEvent('queue_change_priority', {
          entry_id: entryId,
          target_id: targetId,
          priority: priority
        })
      }
    }
  },

  // ============================================================================
  // Command Config Slideout Panel
  // ============================================================================

  _openCommandSlideout() {
    if (!this.cmdSelectedCommand) return

    // Initialize per-target staging state
    // Default to per-target mode when multiple targets selected (safer)
    const hasMultipleTargets = this.cmdSelectedTargets.size > 1
    this.cmdStagedParams = new Map()
    this.cmdActiveTargetIndex = 0
    this.cmdPerTargetMode = hasMultipleTargets
    this.cmdReviewMode = false

    // Create slideout elements if they don't exist
    let backdrop = document.getElementById("cmd-slideout-backdrop")
    let slideout = document.getElementById("cmd-slideout")

    if (!backdrop) {
      backdrop = document.createElement("div")
      backdrop.id = "cmd-slideout-backdrop"
      backdrop.className = "cmd-slideout-backdrop"
      document.body.appendChild(backdrop)

      // Close on backdrop click
      backdrop.addEventListener("click", () => this._closeCommandSlideout())
    }

    if (!slideout) {
      slideout = document.createElement("div")
      slideout.id = "cmd-slideout"
      slideout.className = "cmd-slideout"
      document.body.appendChild(slideout)
    }

    // Render slideout content
    this._renderSlideoutContent(slideout)

    // Show with animation
    requestAnimationFrame(() => {
      backdrop.classList.add("visible")
      slideout.classList.add("visible")
    })

    // Track that slideout is open
    this._slideoutOpen = true
  },

  _closeCommandSlideout() {
    const backdrop = document.getElementById("cmd-slideout-backdrop")
    const slideout = document.getElementById("cmd-slideout")

    if (backdrop) backdrop.classList.remove("visible")
    if (slideout) slideout.classList.remove("visible")

    this._slideoutOpen = false

    // Clear per-target staging state
    this.cmdStagedParams = new Map()
    this.cmdActiveTargetIndex = 0
    this.cmdPerTargetMode = false
    this.cmdReviewMode = false

    // Clear edit mode
    this.cmdEditingStaged = null
  },

  _editStagedEntry(cmdIndex, targetIndex) {
    const staged = this.cmdStagedCommands[cmdIndex]
    if (!staged) return

    const targetEntry = staged.targets[targetIndex]
    if (!targetEntry) return

    // Set editing state
    this.cmdEditingStaged = { cmdIndex, targetIndex }

    // Look up the command from command definitions by ID
    const command = this.commandDefinitions.find(c => c.id === staged.command_id)
    if (!command) {
      console.warn('Command not found for staged entry:', staged.command_id)
      return
    }
    this.cmdSelectedCommand = command

    // Set priority
    this.cmdPriority = staged.priority

    // Store the current params for pre-filling the form
    this._editingParams = targetEntry.params || {}

    // Get the target
    const target = this.targets.find(t => t.id === targetEntry.target_id)
    this._editingTarget = target || { id: targetEntry.target_id, name: targetEntry.target_name }

    // Open slideout in edit mode
    this._openEditSlideout()
  },

  _openEditSlideout() {
    // Create slideout elements if they don't exist
    let backdrop = document.getElementById("cmd-slideout-backdrop")
    let slideout = document.getElementById("cmd-slideout")

    if (!backdrop) {
      backdrop = document.createElement("div")
      backdrop.id = "cmd-slideout-backdrop"
      backdrop.className = "cmd-slideout-backdrop"
      document.body.appendChild(backdrop)
      backdrop.addEventListener("click", () => this._closeCommandSlideout())
    }

    if (!slideout) {
      slideout = document.createElement("div")
      slideout.id = "cmd-slideout"
      slideout.className = "cmd-slideout"
      document.body.appendChild(slideout)
    }

    // Render edit mode content
    this._renderEditSlideoutContent(slideout)

    // Show with animation
    requestAnimationFrame(() => {
      backdrop.classList.add("visible")
      slideout.classList.add("visible")
    })

    this._slideoutOpen = true
  },

  _renderEditSlideoutContent(slideout) {
    const cmd = this.cmdSelectedCommand
    if (!cmd) return

    const target = this._editingTarget
    const params = this._editingParams || {}

    slideout.innerHTML = `
      <div class="cmd-slideout-header">
        <div class="cmd-slideout-title">
          <div class="command-name">Edit Staged Command</div>
          <div class="target-count">${cmd.name}</div>
        </div>
        <button class="cmd-slideout-close" id="slideout-close-btn" title="Close (Esc)">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
          </svg>
        </button>
      </div>

      <div class="cmd-slideout-breadcrumb-bar">
        <span class="cmd-mode-label">Target: <strong>${target.name || target.id}</strong></span>
      </div>

      <div class="cmd-slideout-body">
        ${cmd.is_hazardous ? `
          <div class="cmd-slideout-hazard-warning">
            <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
            </svg>
            <div class="warning-text">
              <strong>Hazardous Command</strong>
              ${cmd.hazard_description || 'This command may cause irreversible changes.'}
            </div>
          </div>
        ` : ''}

        <div class="cmd-slideout-section">
          <div class="cmd-slideout-section-title">Parameters</div>
          <div class="cmd-param-form">
            ${this._renderParameterFormWithValues(cmd, params)}
          </div>
        </div>
      </div>

      <div class="cmd-slideout-footer">
        <div class="cmd-slideout-priority">
          <label>Priority</label>
          <select id="slideout-priority">
            <option value="0" ${this.cmdPriority === 0 ? 'selected' : ''}>0 - Emergency</option>
            <option value="1" ${this.cmdPriority === 1 ? 'selected' : ''}>1 - Critical</option>
            <option value="2" ${this.cmdPriority === 2 ? 'selected' : ''}>2 - High</option>
            <option value="3" ${this.cmdPriority === 3 ? 'selected' : ''}>3 - Normal</option>
            <option value="4" ${this.cmdPriority === 4 ? 'selected' : ''}>4 - Low</option>
            <option value="5" ${this.cmdPriority === 5 ? 'selected' : ''}>5 - Background</option>
          </select>
        </div>

        <div class="cmd-dispatch-actions edit-mode">
          <button class="cmd-dispatch-btn cancel" id="slideout-cancel-btn">
            Cancel
          </button>
          <button class="cmd-dispatch-btn update" id="slideout-update-btn">
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
            </svg>
            Update
          </button>
        </div>
      </div>
    `

    this._bindEditSlideoutEvents(slideout)
  },

  _renderParameterFormWithValues(cmd, values) {
    const params = cmd.parameters || []
    if (params.length === 0) {
      return '<div class="text-xs text-base-content/60">No parameters required</div>'
    }

    return params.map(param => {
      const required = param.required ? '<span class="text-error">*</span>' : ''
      // Use provided value, fall back to default
      const currentVal = values[param.name] !== undefined ? values[param.name] : (param.default_value ?? '')
      const hasValidValues = param.valid_values && param.valid_values.length > 0
      const hasRange = param.min_value != null || param.max_value != null
      const isNumeric = ['int', 'uint', 'float', 'double', 'integer', 'number'].includes(param.data_type?.toLowerCase())
      const isBool = ['boolean', 'bool'].includes(param.data_type?.toLowerCase())

      const descTooltip = param.description
        ? `title="${param.description.replace(/"/g, '&quot;')}"`
        : ''

      let rangeHint = ''
      if (hasRange) {
        if (param.min_value != null && param.max_value != null) {
          rangeHint = `Range: ${param.min_value} - ${param.max_value}`
        } else if (param.min_value != null) {
          rangeHint = `Min: ${param.min_value}`
        } else if (param.max_value != null) {
          rangeHint = `Max: ${param.max_value}`
        }
      }

      if (isBool) {
        return `
          <div class="form-control cmd-param-group">
            <label class="label cursor-pointer py-1" ${descTooltip}>
              <span class="label-text text-xs">${param.name}${required}</span>
              <input type="checkbox" class="toggle toggle-xs toggle-primary cmd-param" data-param="${param.name}"
                     ${currentVal === 'true' || currentVal === true ? 'checked' : ''}>
            </label>
            ${param.description ? `<span class="cmd-param-desc">${param.description}</span>` : ''}
          </div>
        `
      }

      if (hasValidValues) {
        const valueLabels = this._parseValueLabels(param.description, param.valid_values)
        const optionCount = param.valid_values.length

        if (optionCount <= 4) {
          return `
            <div class="form-control cmd-param-group">
              <label class="label py-1">
                <span class="label-text text-xs">${param.name}${required}</span>
              </label>
              <div class="cmd-value-buttons" data-param="${param.name}">
                ${param.valid_values.map(v => {
                  const label = valueLabels[v] || v
                  const isSelected = String(v) === String(currentVal)
                  return `
                    <button type="button"
                            class="cmd-value-btn ${isSelected ? 'selected' : ''}"
                            data-value="${v}"
                            title="${param.description || ''}">
                      <span class="cmd-value-label">${label}</span>
                      <span class="cmd-value-raw">${v}</span>
                    </button>
                  `
                }).join('')}
              </div>
              <input type="hidden" class="cmd-param" data-param="${param.name}" value="${currentVal}">
            </div>
          `
        }

        return `
          <div class="form-control cmd-param-group">
            <label class="label py-1" ${descTooltip}>
              <span class="label-text text-xs">${param.name}${required}</span>
            </label>
            <select class="select select-xs select-bordered cmd-param w-full" data-param="${param.name}">
              ${param.valid_values.map(v => {
                const label = valueLabels[v] || v
                return `<option value="${v}" ${String(v) === String(currentVal) ? 'selected' : ''}>${label} (${v})</option>`
              }).join('')}
            </select>
          </div>
        `
      }

      return `
        <div class="form-control cmd-param-group">
          <label class="label py-1" ${descTooltip}>
            <span class="label-text text-xs">${param.name}${required}</span>
            ${rangeHint ? `<span class="label-text-alt text-xs opacity-60">${rangeHint}</span>` : ''}
          </label>
          <input type="${isNumeric ? 'number' : 'text'}"
                 class="input input-xs input-bordered cmd-param w-full"
                 data-param="${param.name}"
                 value="${currentVal}"
                 ${param.min_value != null ? `min="${param.min_value}"` : ''}
                 ${param.max_value != null ? `max="${param.max_value}"` : ''}
                 ${param.units ? `placeholder="${param.units}"` : ''}>
          ${param.description ? `<span class="cmd-param-desc">${param.description}</span>` : ''}
        </div>
      `
    }).join('')
  },

  _bindEditSlideoutEvents(slideout) {
    // Close button
    slideout.querySelector("#slideout-close-btn")?.addEventListener("click", () => {
      this._closeCommandSlideout()
    })

    // Cancel button
    slideout.querySelector("#slideout-cancel-btn")?.addEventListener("click", () => {
      this._closeCommandSlideout()
    })

    // Priority selector
    slideout.querySelector("#slideout-priority")?.addEventListener("change", (e) => {
      this.cmdPriority = parseInt(e.target.value, 10)
    })

    // Update button
    slideout.querySelector("#slideout-update-btn")?.addEventListener("click", () => {
      this._updateStagedEntry(slideout)
    })

    // Value button groups
    slideout.querySelectorAll('.cmd-value-buttons').forEach(group => {
      const hiddenInput = group.querySelector('input[type="hidden"]')
      group.querySelectorAll('.cmd-value-btn').forEach(btn => {
        btn.addEventListener('click', () => {
          group.querySelectorAll('.cmd-value-btn').forEach(b => b.classList.remove('selected'))
          btn.classList.add('selected')
          if (hiddenInput) {
            hiddenInput.value = btn.dataset.value
          }
        })
      })
    })

    // Escape key to close
    const escHandler = (e) => {
      if (e.key === 'Escape' && this._slideoutOpen) {
        this._closeCommandSlideout()
        document.removeEventListener('keydown', escHandler)
      }
    }
    document.addEventListener('keydown', escHandler)
  },

  _updateStagedEntry(slideout) {
    if (!this.cmdEditingStaged) return

    const { cmdIndex, targetIndex } = this.cmdEditingStaged
    const staged = this.cmdStagedCommands[cmdIndex]
    if (!staged) return

    // Collect params from form
    const params = this._collectFormParams(slideout)

    // Update the staged entry
    staged.targets[targetIndex].params = params
    staged.priority = this.cmdPriority

    // Close slideout and refresh staging panel
    this._closeCommandSlideout()
    this._updateStagingPanel()
  },

  _renderSlideoutContent(slideout) {
    const cmd = this.cmdSelectedCommand
    if (!cmd) return

    const selectedTargetCount = this.cmdSelectedTargets.size
    const selectedTargets = this.targets.filter(t => this.cmdSelectedTargets.has(t.id))
    const stagedCount = this.cmdStagedParams.size
    const activeTarget = selectedTargets[this.cmdActiveTargetIndex]
    const hasMultipleTargets = selectedTargetCount > 1
    const hasParameters = cmd.parameters && cmd.parameters.length > 0

    // Header subtitle shows command description if available
    const headerSubtitle = cmd.description
      ? `<span class="command-description">${cmd.description}</span>`
      : ''

    // Mode bar - always present to avoid layout shift
    // Navigation action always on the right for consistency
    let modeBarContent
    if (this.cmdReviewMode) {
      // Review mode: show count on left, back link on right
      modeBarContent = `
        <span class="cmd-mode-label">Review <strong>${stagedCount}</strong> command${stagedCount !== 1 ? 's' : ''}</span>
        <span class="cmd-mode-switch" id="slideout-back-to-config">← Edit</span>
      `
    } else if (this.cmdPerTargetMode && activeTarget) {
      // Per-target mode: current target on left, back link on right
      modeBarContent = `
        <span class="cmd-mode-label">Configuring <strong>${activeTarget.name || activeTarget.identifier}</strong></span>
        <span class="cmd-mode-switch" id="slideout-back-to-uniform">← Uniform</span>
      `
    } else if (hasMultipleTargets && hasParameters) {
      // Uniform mode with multiple targets: mode label on left, configure each on right
      modeBarContent = `
        <span class="cmd-mode-label">Uniform parameters</span>
        <span class="cmd-mode-switch" id="slideout-configure-each-link">Configure each →</span>
      `
    } else {
      // Single target or no parameters: just show mode label
      modeBarContent = `
        <span class="cmd-mode-label">${selectedTargetCount === 1 ? 'Single target' : 'Uniform parameters'}</span>
      `
    }

    const modeBar = `<div class="cmd-slideout-breadcrumb-bar">${modeBarContent}</div>`

    slideout.innerHTML = `
      <div class="cmd-slideout-header">
        <div class="cmd-slideout-title">
          <div class="command-name">${cmd.name}</div>
          <div class="target-count">${headerSubtitle}</div>
        </div>
        <button class="cmd-slideout-close" id="slideout-close-btn" title="Close (Esc)">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
          </svg>
        </button>
      </div>

      ${modeBar}

      <div class="cmd-slideout-body">
        ${cmd.is_hazardous ? `
          <div class="cmd-slideout-hazard-warning">
            <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
            </svg>
            <div class="warning-text">
              <strong>Hazardous Command</strong>
              ${cmd.hazard_description || 'This command may cause irreversible changes.'}
            </div>
          </div>
        ` : ''}

        ${this.cmdReviewMode
          ? this._renderReviewTable()
          : this._renderConfigBody(cmd, selectedTargets, hasMultipleTargets, stagedCount, selectedTargetCount, activeTarget)
        }
      </div>

      <div class="cmd-slideout-footer">
        <div class="cmd-slideout-priority">
          <label>Priority</label>
          <select id="slideout-priority">
            <option value="0" ${this.cmdPriority === 0 ? 'selected' : ''}>0 - Emergency</option>
            <option value="1" ${this.cmdPriority === 1 ? 'selected' : ''}>1 - Critical</option>
            <option value="2" ${this.cmdPriority === 2 ? 'selected' : ''}>2 - High</option>
            <option value="3" ${this.cmdPriority === 3 ? 'selected' : ''}>3 - Normal</option>
            <option value="4" ${this.cmdPriority === 4 ? 'selected' : ''}>4 - Low</option>
            <option value="5" ${this.cmdPriority === 5 ? 'selected' : ''}>5 - Background</option>
          </select>
        </div>

        ${this._renderSlideoutActions(cmd, selectedTargetCount, stagedCount)}
      </div>
    `

    // Bind slideout events
    this._bindSlideoutEvents(slideout)
  },

  _renderSlideoutActions(cmd, selectedTargetCount, stagedCount) {
    const isHazardous = cmd.is_hazardous
    const hazClass = isHazardous ? 'hazardous' : ''
    const disabled = selectedTargetCount === 0 ? 'disabled' : ''
    const hasMultipleTargets = selectedTargetCount > 1

    if (this.cmdReviewMode) {
      // Review mode: Add to Stage + Queue buttons
      return `
        <div class="cmd-dispatch-actions review-mode">
          <button class="cmd-dispatch-btn add-to-stage"
                  id="slideout-add-to-stage-btn"
                  ${disabled}>
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"/>
            </svg>
            Add to Stage
          </button>
          <button class="cmd-dispatch-btn queue ${hazClass}"
                  id="slideout-queue-btn"
                  ${disabled}>
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"/>
            </svg>
            Queue ${stagedCount}
          </button>
        </div>
      `
    } else if (this.cmdPerTargetMode) {
      // Per-target mode: Stage current + Review Staged
      const allStaged = stagedCount === selectedTargetCount
      const canReview = stagedCount > 0

      return `
        <div class="cmd-dispatch-actions per-target-mode">
          <button class="cmd-dispatch-btn stage ${hazClass}"
                  id="slideout-stage-btn"
                  ${disabled}>
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
            </svg>
            Stage${!allStaged ? ` (${this.cmdActiveTargetIndex + 1}/${selectedTargetCount})` : ''}
          </button>
          <button class="cmd-dispatch-btn review ${canReview ? '' : 'disabled'}"
                  id="slideout-review-btn"
                  ${!canReview ? 'disabled' : ''}>
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
            </svg>
            Review ${stagedCount} Staged
          </button>
        </div>
      `
    } else {
      // Uniform mode: Stage All
      return `
        <div class="cmd-dispatch-actions">
          <button class="cmd-dispatch-btn stage-all ${hazClass}"
                  id="slideout-stage-all-btn"
                  ${disabled}>
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
            </svg>
            Stage${hasMultipleTargets ? ' All' : ''} →
          </button>
        </div>
      `
    }
  },

  _bindSlideoutEvents(slideout) {
    // Close button
    slideout.querySelector("#slideout-close-btn")?.addEventListener("click", () => {
      this._closeCommandSlideout()
    })

    // Priority selector
    slideout.querySelector("#slideout-priority")?.addEventListener("change", (e) => {
      this.cmdPriority = parseInt(e.target.value, 10)
    })

    // Queue button (in review mode, dispatches parameterized)
    slideout.querySelector("#slideout-queue-btn")?.addEventListener("click", () => {
      if (this.cmdReviewMode) {
        this._dispatchParameterized("queue")
      } else {
        this._dispatchCommand("queue")
      }
    })

    // Add to Stage button (in review mode, adds to persistent staging area)
    slideout.querySelector("#slideout-add-to-stage-btn")?.addEventListener("click", () => {
      this._addToStagingArea()
    })

    // Stage All button (uniform mode -> review)
    slideout.querySelector("#slideout-stage-all-btn")?.addEventListener("click", () => {
      this._stageAllTargets()
    })

    // Configure Each link in mode bar (enters per-target mode)
    slideout.querySelector("#slideout-configure-each-link")?.addEventListener("click", () => {
      this._enterPerTargetMode()
    })

    // Back to Uniform link (exits per-target mode)
    slideout.querySelector("#slideout-back-to-uniform")?.addEventListener("click", () => {
      this._exitPerTargetMode()
    })

    // Back to Config link (exits review mode)
    slideout.querySelector("#slideout-back-to-config")?.addEventListener("click", () => {
      this._exitReviewMode()
    })

    // Stage button (per-target mode)
    slideout.querySelector("#slideout-stage-btn")?.addEventListener("click", () => {
      this._stageCurrentTarget(slideout)
    })

    // Review button (per-target mode -> review)
    slideout.querySelector("#slideout-review-btn")?.addEventListener("click", () => {
      this._enterReviewMode()
    })

    // Target chip clicks (jump to target in per-target mode, or enter per-target mode)
    slideout.querySelectorAll(".cmd-slideout-target-chip[data-target-idx]").forEach(chip => {
      chip.addEventListener("click", () => {
        const idx = parseInt(chip.dataset.targetIdx, 10)
        if (this.cmdPerTargetMode) {
          // Already in per-target mode, just navigate
          this._goToTarget(idx, slideout)
        } else if (this.cmdSelectedTargets.size > 1) {
          // Enter per-target mode and go to clicked target
          this.cmdActiveTargetIndex = idx
          this._enterPerTargetMode()
        }
      })
    })

    // Value button groups (for params with valid_values)
    slideout.querySelectorAll(".cmd-value-buttons").forEach(group => {
      const paramName = group.dataset.param
      const hiddenInput = group.parentElement.querySelector(`input[data-param="${paramName}"]`)

      group.querySelectorAll(".cmd-value-btn").forEach(btn => {
        btn.addEventListener("click", () => {
          group.querySelectorAll(".cmd-value-btn").forEach(b => b.classList.remove("selected"))
          btn.classList.add("selected")
          if (hiddenInput) {
            hiddenInput.value = btn.dataset.value
          }
        })
      })
    })

    // Keyboard shortcut: Enter to stage in per-target mode
    if (this.cmdPerTargetMode) {
      this._slideoutKeyHandler = (e) => {
        if (e.key === 'Enter' && !e.target.matches('input, select, button')) {
          e.preventDefault()
          this._stageCurrentTarget(slideout)
        }
      }
      document.addEventListener('keydown', this._slideoutKeyHandler)
    }
  },

  // Per-target mode navigation helpers

  _enterPerTargetMode() {
    this.cmdPerTargetMode = true
    const slideout = document.getElementById("cmd-slideout")
    if (slideout) {
      this._renderSlideoutContent(slideout)
    }
  },

  _exitPerTargetMode() {
    this.cmdPerTargetMode = false
    this.cmdStagedParams = new Map()
    this.cmdActiveTargetIndex = 0
    const slideout = document.getElementById("cmd-slideout")
    if (slideout) {
      this._renderSlideoutContent(slideout)
    }
  },

  // Review mode helpers

  _enterReviewMode() {
    this.cmdReviewMode = true
    const slideout = document.getElementById("cmd-slideout")
    if (slideout) {
      this._renderSlideoutContent(slideout)
    }
  },

  _exitReviewMode() {
    this.cmdReviewMode = false
    const slideout = document.getElementById("cmd-slideout")
    if (slideout) {
      this._renderSlideoutContent(slideout)
    }
  },

  _stageAllTargets() {
    const slideout = document.getElementById("cmd-slideout")
    if (!slideout) return

    const params = this._collectFormParams(slideout)
    const selectedTargets = this.targets.filter(t => this.cmdSelectedTargets.has(t.id))

    // Stage all targets with the same params
    selectedTargets.forEach(target => {
      this.cmdStagedParams.set(target.id, { params: {...params} })
    })

    // Enter review mode
    this._enterReviewMode()
  },

  _renderReviewTable() {
    const cmd = this.cmdSelectedCommand
    if (!cmd) return ''

    const selectedTargets = this.targets.filter(t => this.cmdSelectedTargets.has(t.id))
    const params = cmd.parameters || []

    // Build table header with param names
    const headerCells = params.slice(0, 4).map(p =>
      `<th class="cmd-review-th">${p.name}</th>`
    ).join('')

    // Build table rows
    const rows = selectedTargets.map(target => {
      const staged = this.cmdStagedParams.get(target.id)
      const targetParams = staged?.params || {}

      const cells = params.slice(0, 4).map(p => {
        const value = targetParams[p.name]
        const displayValue = value !== undefined ? value : '—'
        return `<td class="cmd-review-td">${displayValue}</td>`
      }).join('')

      return `
        <tr class="cmd-review-row" data-target-id="${target.id}">
          <td class="cmd-review-td cmd-review-target">${target.name || target.identifier}</td>
          ${cells}
        </tr>
      `
    }).join('')

    return `
      <div class="cmd-review-section">
        <div class="cmd-slideout-section-title">Staged Commands</div>
        <div class="cmd-review-table-wrapper">
          <table class="cmd-review-table">
            <thead>
              <tr>
                <th class="cmd-review-th">Target</th>
                ${headerCells}
              </tr>
            </thead>
            <tbody>
              ${rows}
            </tbody>
          </table>
        </div>
      </div>
    `
  },

  _renderConfigBody(cmd, selectedTargets, hasMultipleTargets, stagedCount, selectedTargetCount, activeTarget) {
    const targetChips = selectedTargets.length > 0
      ? selectedTargets.map((t, idx) => {
          // In per-target mode: highlight only active target
          // In Queue All mode: highlight all targets
          const isActive = this.cmdPerTargetMode
            ? idx === this.cmdActiveTargetIndex
            : true
          const isStaged = this.cmdStagedParams.has(t.id)
          const chipClasses = [
            'cmd-slideout-target-chip',
            isActive ? 'active' : '',
            isStaged ? 'staged' : ''
          ].filter(Boolean).join(' ')

          const statusIcon = isStaged
            ? `<svg class="staged-check w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
              </svg>`
            : `<span class="status-dot ${t.status || 'online'}"></span>`

          return `
            <span class="${chipClasses}" data-target-idx="${idx}" data-target-id="${t.id}">
              ${statusIcon}
              ${t.name || t.identifier}
            </span>
          `
        }).join('')
      : '<span class="text-xs text-base-content/50">No targets selected</span>'

    const progressIndicator = hasMultipleTargets && this.cmdPerTargetMode
      ? `<div class="cmd-slideout-progress">${stagedCount} of ${selectedTargetCount} staged</div>`
      : ''

    const paramLabel = this.cmdPerTargetMode && activeTarget
      ? `<span class="param-target-label">for ${activeTarget.name || activeTarget.identifier}</span>`
      : ''

    return `
      <div class="cmd-slideout-section">
        <div class="cmd-slideout-section-header">
          <div class="cmd-slideout-section-title">Targets</div>
          ${progressIndicator}
        </div>
        <div class="cmd-slideout-targets">
          ${targetChips}
        </div>
      </div>

      <div class="cmd-slideout-section">
        <div class="cmd-slideout-section-title">
          Parameters
          ${paramLabel}
        </div>
        <div class="cmd-param-form">
          ${this._renderParameterForm(cmd, activeTarget?.id)}
        </div>
      </div>
    `
  },

  _goToTarget(index, slideout) {
    const selectedTargets = this.targets.filter(t => this.cmdSelectedTargets.has(t.id))
    const maxIndex = selectedTargets.length - 1

    // Clamp index to valid range
    if (index < 0) index = 0
    if (index > maxIndex) index = maxIndex

    if (index !== this.cmdActiveTargetIndex) {
      this.cmdActiveTargetIndex = index
      this._renderSlideoutContent(slideout)
    }
  },

  _stageCurrentTarget(slideout) {
    const selectedTargets = this.targets.filter(t => this.cmdSelectedTargets.has(t.id))
    const activeTarget = selectedTargets[this.cmdActiveTargetIndex]
    if (!activeTarget) return

    // Collect current form parameters
    const params = this._collectFormParams(slideout)

    // Stage the params for this target
    this.cmdStagedParams.set(activeTarget.id, {
      params: params,
      staged: true
    })

    // Find next unstaged target, or stay on current if all staged
    const nextUnstagedIdx = selectedTargets.findIndex((t, idx) =>
      idx > this.cmdActiveTargetIndex && !this.cmdStagedParams.has(t.id)
    )

    if (nextUnstagedIdx !== -1) {
      this.cmdActiveTargetIndex = nextUnstagedIdx
    } else {
      // Check for any unstaged before current position
      const prevUnstagedIdx = selectedTargets.findIndex(t => !this.cmdStagedParams.has(t.id))
      if (prevUnstagedIdx !== -1 && prevUnstagedIdx !== this.cmdActiveTargetIndex) {
        this.cmdActiveTargetIndex = prevUnstagedIdx
      }
      // Otherwise stay on current (all staged)
    }

    // Re-render to show updated state
    this._renderSlideoutContent(slideout)
  },

  _collectFormParams(slideout) {
    const params = {}
    const form = slideout.querySelector(".cmd-param-form")
    if (!form) return params

    // Collect from input fields
    form.querySelectorAll("input[data-param], select[data-param]").forEach(input => {
      const name = input.dataset.param
      let value = input.value

      // Convert to appropriate type based on input type
      if (input.type === 'number') {
        value = input.value === '' ? null : parseFloat(input.value)
      } else if (input.type === 'checkbox') {
        value = input.checked
      }

      if (value !== null && value !== '') {
        params[name] = value
      }
    })

    return params
  },

  _dispatchParameterized(mode) {
    const cmd = this.cmdSelectedCommand
    if (!cmd) return

    // Build target_params array from staged params
    const targetParams = []
    this.cmdStagedParams.forEach((entry, targetId) => {
      targetParams.push({
        target_id: targetId,
        params: entry.params
      })
    })

    if (targetParams.length === 0) {
      console.warn("[OpsConsole] No staged params to dispatch")
      return
    }

    // Push event to LiveView
    this.pushEvent("cmd_dispatch_parameterized", {
      command_id: cmd.id,
      target_params: targetParams,
      mode: mode,
      priority: this.cmdPriority
    })

    // Close slideout after dispatch
    this._closeCommandSlideout()
  },

  // ============================================================================
  // Queue Entry Detail Slideout
  // ============================================================================

  _openQueueEntrySlideout(entryId) {
    const entry = this.commands.find(c => c.id === entryId)
    if (!entry) return

    // Store the selected entry
    this._selectedQueueEntry = entry

    // Reuse the same slideout infrastructure
    let backdrop = document.getElementById("cmd-slideout-backdrop")
    let slideout = document.getElementById("cmd-slideout")

    if (!backdrop) {
      backdrop = document.createElement("div")
      backdrop.id = "cmd-slideout-backdrop"
      backdrop.className = "cmd-slideout-backdrop"
      document.body.appendChild(backdrop)
      backdrop.addEventListener("click", () => this._closeQueueEntrySlideout())
    }

    if (!slideout) {
      slideout = document.createElement("div")
      slideout.id = "cmd-slideout"
      slideout.className = "cmd-slideout"
      document.body.appendChild(slideout)
    }

    // Render queue entry detail content
    this._renderQueueEntrySlideout(slideout, entry)

    // Show with animation
    requestAnimationFrame(() => {
      backdrop.classList.add("visible")
      slideout.classList.add("visible")
    })

    this._slideoutOpen = true
    this._slideoutType = 'queue-entry'
  },

  _closeQueueEntrySlideout() {
    const backdrop = document.getElementById("cmd-slideout-backdrop")
    const slideout = document.getElementById("cmd-slideout")

    if (backdrop) backdrop.classList.remove("visible")
    if (slideout) slideout.classList.remove("visible")

    this._slideoutOpen = false
    this._slideoutType = null
    this._selectedQueueEntry = null
  },

  _renderQueueEntrySlideout(slideout, entry) {
    const isHeld = entry.status === 'held'
    const isPending = entry.status === 'pending'
    const isExecuting = entry.status === 'executing'
    const isFailed = entry.status === 'failed'
    const canModify = isPending || isHeld

    const params = entry.parameters || {}
    const paramEntries = Object.entries(params)
    const hasParams = paramEntries.length > 0

    const priority = entry.priority ?? 3
    const priorityLabels = ['Emergency', 'Critical', 'High', 'Normal', 'Low', 'Background']
    const priorityLabel = priorityLabels[priority] || 'Normal'

    const queueAge = this._formatQueueAge(entry.created_at)
    const isScheduled = entry.scheduled_at && new Date(entry.scheduled_at) > new Date()
    const scheduledTime = isScheduled ? this._formatScheduledTime(entry.scheduled_at) : null

    const statusClass = isExecuting ? 'executing' : isHeld ? 'held' : isFailed ? 'failed' : 'pending'

    slideout.innerHTML = `
      <div class="cmd-slideout-header">
        <div class="cmd-slideout-title">
          <div class="command-name">${entry.command_name}</div>
          <div class="target-count">
            Target: <strong>${entry.target_name || 'Unknown'}</strong>
          </div>
        </div>
        <button class="cmd-slideout-close" id="qe-slideout-close" title="Close (Esc)">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
          </svg>
        </button>
      </div>

      <div class="cmd-slideout-body">
        <!-- Status Section -->
        <div class="qe-detail-status ${statusClass}">
          <div class="qe-detail-status-badge">${this._getStatusLabel(entry.status)}</div>
          ${isExecuting ? '<div class="qe-detail-status-text">Command is currently being executed</div>' : ''}
          ${isHeld ? '<div class="qe-detail-status-text">Command is on hold</div>' : ''}
          ${isPending ? '<div class="qe-detail-status-text">Waiting in queue for execution</div>' : ''}
          ${isFailed ? '<div class="qe-detail-status-text">Command execution failed</div>' : ''}
        </div>

        ${isFailed && entry.last_error ? `
          <div class="qe-detail-error">
            <div class="qe-detail-error-label">Error Details</div>
            <div class="qe-detail-error-message">${entry.last_error}</div>
          </div>
        ` : ''}

        <!-- Info Grid -->
        <div class="qe-detail-grid">
          <div class="qe-detail-item">
            <span class="qe-detail-label">Priority</span>
            <span class="qe-detail-value">${priority} - ${priorityLabel}</span>
          </div>
          <div class="qe-detail-item">
            <span class="qe-detail-label">Queued</span>
            <span class="qe-detail-value">${queueAge} ago</span>
          </div>
          ${entry.attempts > 0 ? `
            <div class="qe-detail-item">
              <span class="qe-detail-label">Attempts</span>
              <span class="qe-detail-value">${entry.attempts}</span>
            </div>
          ` : ''}
          ${isScheduled ? `
            <div class="qe-detail-item">
              <span class="qe-detail-label">Scheduled</span>
              <span class="qe-detail-value">${scheduledTime}</span>
            </div>
          ` : ''}
        </div>

        <!-- Parameters -->
        ${hasParams ? `
          <div class="cmd-slideout-section">
            <div class="cmd-slideout-section-title">Parameters</div>
            <div class="qe-detail-params">
              ${paramEntries.map(([key, value]) => `
                <div class="qe-detail-param">
                  <span class="qe-detail-param-key">${key}</span>
                  <span class="qe-detail-param-value">${this._formatParamValue(value)}</span>
                </div>
              `).join('')}
            </div>
          </div>
        ` : `
          <div class="cmd-slideout-section">
            <div class="cmd-slideout-section-title">Parameters</div>
            <div class="qe-detail-no-params">No parameters</div>
          </div>
        `}
      </div>

      <div class="cmd-slideout-footer">
        <div class="qe-detail-actions">
          ${isExecuting ? `
            <div class="qe-detail-executing">
              <span class="qe-pulse"></span>
              Executing...
            </div>
          ` : ''}

          ${canModify ? `
            ${isHeld ? `
              <button class="qe-detail-btn qe-detail-btn-release" data-id="${entry.id}">
                <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"/>
                </svg>
                Release
              </button>
            ` : `
              <button class="qe-detail-btn qe-detail-btn-hold" data-id="${entry.id}">
                <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 9v6m4-6v6"/>
                </svg>
                Hold
              </button>
            `}

            ${priority > 0 ? `
              <button class="qe-detail-btn qe-detail-btn-promote" data-id="${entry.id}" data-priority="${priority - 1}">
                <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 15l7-7 7 7"/>
                </svg>
                Promote
              </button>
            ` : ''}

            <button class="qe-detail-btn qe-detail-btn-cancel" data-id="${entry.id}">
              <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
              </svg>
              Cancel
            </button>
          ` : ''}

          ${isFailed ? `
            <button class="qe-detail-btn qe-detail-btn-retry" data-id="${entry.id}">
              <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
              </svg>
              Retry
            </button>
            <button class="qe-detail-btn qe-detail-btn-dismiss" data-id="${entry.id}">
              <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
              </svg>
              Dismiss
            </button>
          ` : ''}
        </div>
      </div>
    `

    this._bindQueueEntrySlideoutEvents(slideout)
  },

  _bindQueueEntrySlideoutEvents(slideout) {
    // Close button
    slideout.querySelector("#qe-slideout-close")?.addEventListener("click", () => {
      this._closeQueueEntrySlideout()
    })

    // Action buttons
    slideout.querySelectorAll(".qe-detail-btn").forEach(btn => {
      btn.addEventListener("click", () => {
        const entryId = btn.dataset.id

        if (btn.classList.contains("qe-detail-btn-cancel") || btn.classList.contains("qe-detail-btn-dismiss")) {
          this.pushEvent("cancel_command", { id: entryId })
          this._closeQueueEntrySlideout()
        } else if (btn.classList.contains("qe-detail-btn-hold")) {
          this.pushEvent("hold_command", { id: entryId })
        } else if (btn.classList.contains("qe-detail-btn-release")) {
          this.pushEvent("release_command", { id: entryId })
        } else if (btn.classList.contains("qe-detail-btn-promote")) {
          const newPriority = parseInt(btn.dataset.priority, 10)
          this.pushEvent("promote_command", { id: entryId, priority: newPriority })
        } else if (btn.classList.contains("qe-detail-btn-retry")) {
          this.pushEvent("retry_command", { id: entryId })
        }
      })
    })
  },

  _debounce(key, fn, delay) {
    if (!this._debounceTimers) {
      this._debounceTimers = {}
    }

    if (this._debounceTimers[key]) {
      clearTimeout(this._debounceTimers[key])
    }

    this._debounceTimers[key] = setTimeout(fn, delay)
  },

  // ============================================================================
  // Alarms Mode
  // ============================================================================

  _renderAlarmsMode() {
    const dashboard = this.panelLayout?.elements?.dashboard
    if (!dashboard) return

    // Check if alarms container already exists
    let alarmsContainer = dashboard.querySelector(".alarms-mode-container")
    if (!alarmsContainer) {
      alarmsContainer = document.createElement("div")
      alarmsContainer.className = "alarms-mode-container"
      dashboard.appendChild(alarmsContainer)
    }

    // Get filtered alarms
    const filteredAlarms = this._getFilteredAlarms()
    const groupedAlarms = this._groupAlarmsBySeverity(filteredAlarms)
    const selectedAlarm = this.alarmsSelectedAlarm
      ? this.alarms.find(a => a.id === this.alarmsSelectedAlarm)
      : null

    // Render view-specific content
    let viewContent
    if (this.alarmsViewMode === 'panel') {
      viewContent = this._renderAlarmsPanelView()
    } else if (this.alarmsViewMode === 'historical') {
      viewContent = this._renderAlarmsHistoricalView()
    } else if (this.alarmsViewMode === 'rules') {
      viewContent = this._renderAlarmsRulesView()
    } else if (this.alarmsViewMode === 'analytics') {
      viewContent = this._renderAlarmsAnalyticsView()
    } else {
      viewContent = this._renderAlarmsActiveView(filteredAlarms, groupedAlarms, selectedAlarm)
    }

    alarmsContainer.innerHTML = `
      <div class="alarms-mode-layout">
        <!-- View Tabs -->
        <div class="alarms-view-tabs">
          <button class="alarms-view-tab ${this.alarmsViewMode === 'active' ? 'active' : ''}"
                  data-view="active">ACTIVE</button>
          <button class="alarms-view-tab ${this.alarmsViewMode === 'panel' ? 'active' : ''}"
                  data-view="panel">PANEL</button>
          <button class="alarms-view-tab ${this.alarmsViewMode === 'historical' ? 'active' : ''}"
                  data-view="historical">HISTORICAL</button>
          <button class="alarms-view-tab ${this.alarmsViewMode === 'rules' ? 'active' : ''}"
                  data-view="rules">RULES</button>
          <button class="alarms-view-tab ${this.alarmsViewMode === 'analytics' ? 'active' : ''}"
                  data-view="analytics">ANALYTICS</button>
        </div>

        ${viewContent}
      </div>
    `

    this._bindAlarmsModeEvents(alarmsContainer)
  },

  _renderAlarmsActiveView(filteredAlarms, groupedAlarms, selectedAlarm) {
    const selectedCount = this.alarmsSelectedTargets.size
    const totalTargets = this.targets.length

    return `
      <!-- Main Content Area -->
      <div class="alarms-panels-row" id="alarms-panels-row">
        <!-- Left Panel: Target Selection -->
        <div class="alarms-target-panel" id="alarms-target-panel" style="flex: 0 0 ${this.alarmsTargetPanelWidth}%">
          <div class="alarms-panel-header">
            <div class="alarms-panel-title">
              <span class="mc-label-subsystem">TARGETS</span>
              <span class="alarms-selection-count">${selectedCount === 0 ? 'All' : selectedCount} of ${totalTargets}</span>
            </div>
            <div class="alarms-view-toggle">
              <button class="alarms-view-btn ${this.alarmsTargetViewMode === 'compact' ? 'active' : ''}"
                      data-target-view="compact" title="Compact view">
                <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 10h16M4 14h16M4 18h16"/>
                </svg>
              </button>
              <button class="alarms-view-btn ${this.alarmsTargetViewMode === 'detailed' ? 'active' : ''}"
                      data-target-view="detailed" title="Detailed view">
                <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16m-7 6h7"/>
                </svg>
              </button>
            </div>
          </div>
          <div class="alarms-target-filters">
            <input type="text"
                   class="alarms-target-search"
                   id="alarms-target-search"
                   placeholder="Filter targets..."
                   value="${this.alarmsTargetSearch}">
          </div>
          <div class="alarms-target-grid ${this.alarmsTargetViewMode === 'detailed' ? 'detailed-view' : ''}">
            ${this._renderAlarmsTargetGrid()}
          </div>
          <div class="alarms-selection-actions">
            <button class="btn btn-ghost btn-xs" id="alarms-select-all-targets">Select All</button>
            <button class="btn btn-ghost btn-xs" id="alarms-clear-targets">Clear</button>
          </div>
        </div>

        <!-- Resize Handle (Target/List) -->
        <div class="alarms-resize-handle" id="alarms-target-resize-handle">
          <div class="alarms-resize-grip"></div>
        </div>

        <!-- Middle Panel: Alarm List -->
        <div class="alarms-list-panel" id="alarms-list-panel" style="flex: 0 0 ${this.alarmsListPanelWidth}%">
          <div class="alarms-panel-header">
            <div class="alarms-panel-title">
              <span class="mc-label-subsystem">ALARMS</span>
              <span class="alarms-count">${filteredAlarms.length} total</span>
            </div>
          </div>

          <!-- Filter Controls -->
          <div class="alarms-filters">
            <div class="alarms-filter-row">
              <div class="alarms-status-filters">
                <button class="alarms-filter-btn ${this.alarmsFilterStatus.has('active') ? 'active' : ''}"
                        data-status="active">ACTIVE</button>
                <button class="alarms-filter-btn ${this.alarmsFilterStatus.has('acknowledged') ? 'active' : ''}"
                        data-status="acknowledged">ACK</button>
                <button class="alarms-filter-btn ${this.alarmsFilterStatus.has('shelved') ? 'active' : ''}"
                        data-status="shelved">SHELVED</button>
              </div>
              <div class="alarms-severity-filters">
                <button class="alarms-severity-btn severity-critical ${this.alarmsFilterSeverity.has('critical') ? 'active' : ''}"
                        data-severity="critical" title="Critical">C</button>
                <button class="alarms-severity-btn severity-warning ${this.alarmsFilterSeverity.has('warning') ? 'active' : ''}"
                        data-severity="warning" title="Warning">W</button>
                <button class="alarms-severity-btn severity-info ${this.alarmsFilterSeverity.has('info') ? 'active' : ''}"
                        data-severity="info" title="Info">I</button>
              </div>
            </div>
          </div>

          <!-- Alarm Groups -->
          <div class="alarms-list">
            ${this._renderAlarmGroups(groupedAlarms)}
          </div>

          <!-- Bulk Actions -->
          <div class="alarms-bulk-actions">
            <button class="btn btn-primary btn-sm" id="alarms-ack-all"
                    ${filteredAlarms.filter(a => a.status === 'active').length === 0 ? 'disabled' : ''}>
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
              </svg>
              ACK ALL VISIBLE (${filteredAlarms.filter(a => a.status === 'active').length})
            </button>
          </div>
        </div>

        <!-- Resize Handle (List/Detail) -->
        <div class="alarms-resize-handle" id="alarms-resize-handle">
          <div class="alarms-resize-grip"></div>
        </div>

        <!-- Right Panel: Alarm Detail -->
        <div class="alarms-detail-panel" id="alarms-detail-panel">
          ${selectedAlarm
            ? this._renderAlarmDetailPanel(selectedAlarm)
            : `<div class="alarms-detail-empty">
                 <svg class="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                   <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"
                         d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"/>
                 </svg>
                 <span>Select an alarm to view details</span>
               </div>`
          }
        </div>
      </div>
    `
  },

  _renderAlarmsTargetGrid() {
    const searchLower = this.alarmsTargetSearch.toLowerCase()
    const filteredTargets = this.targets.filter(t =>
      t.name.toLowerCase().includes(searchLower)
    )

    // Count alarms per target
    const alarmCounts = new Map()
    const activeAlarms = this.alarms || []
    activeAlarms.forEach(alarm => {
      if (alarm.target_id) {
        const count = alarmCounts.get(alarm.target_id) || { active: 0, ack: 0, total: 0 }
        count.total++
        if (alarm.status === 'active') count.active++
        if (alarm.status === 'acknowledged') count.ack++
        alarmCounts.set(alarm.target_id, count)
      }
    })

    if (filteredTargets.length === 0) {
      return `<div class="alarms-target-empty">No targets match filter</div>`
    }

    const isDetailed = this.alarmsTargetViewMode === 'detailed'

    return filteredTargets.map(target => {
      const isSelected = this.alarmsSelectedTargets.has(target.id)
      const counts = alarmCounts.get(target.id) || { active: 0, ack: 0, total: 0 }
      const hasActiveAlarms = counts.active > 0
      const hasAckAlarms = counts.ack > 0
      const statusClass = target.status || 'online'
      const mode = target.mode || 'NOMINAL'

      if (isDetailed) {
        return `
          <div class="alarms-target-cell ${isSelected ? 'selected' : ''} status-${statusClass} ${hasActiveAlarms ? 'has-alarms' : ''}"
               data-target-id="${target.id}">
            <div class="alarms-target-main">
              <span class="alarms-target-name">${target.name}</span>
              <span class="alarms-target-mode">${mode}</span>
            </div>
            <div class="alarms-target-meta">
              <span class="alarms-target-type">${target.target_type || 'Unknown'}</span>
              ${counts.total > 0 ? `
                <span class="alarms-target-alarm-count">
                  ${hasActiveAlarms ? `<span class="active">${counts.active}</span>` : ''}
                  ${hasAckAlarms ? `<span class="ack">${counts.ack}</span>` : ''}
                </span>
              ` : ''}
            </div>
          </div>
        `
      } else {
        // Compact view
        return `
          <div class="alarms-target-cell ${isSelected ? 'selected' : ''} status-${statusClass} ${hasActiveAlarms ? 'has-alarms' : ''}"
               data-target-id="${target.id}">
            <span class="alarms-target-name">${target.name}</span>
            ${counts.total > 0 ? `<span class="alarms-target-count">${counts.total}</span>` : ''}
          </div>
        `
      }
    }).join('')
  },

  _renderAlarmsHistoricalView() {
    const alarms = this.historicalAlarms || []
    const selectedAlarm = this.alarmsSelectedAlarm
      ? alarms.find(a => a.id === this.alarmsSelectedAlarm)
      : null

    return `
      <div class="alarms-panels-row" id="alarms-panels-row">
        <!-- Left Panel: Historical Alarm List -->
        <div class="alarms-list-panel" id="alarms-list-panel" style="flex: 0 0 ${this.alarmsListPanelWidth}%">
          <div class="alarms-panel-header">
            <div class="alarms-panel-title">
              <span class="mc-label-subsystem">HISTORICAL ALARMS</span>
              <span class="alarms-count">${alarms.length} total</span>
            </div>
          </div>

          <!-- Time Range Filter -->
          <div class="alarms-filters">
            <div class="alarms-filter-row">
              <div class="alarms-time-filters">
                <button class="alarms-filter-btn ${this.alarmsFilterTimeRange === '1h' ? 'active' : ''}"
                        data-time-range="1h">1H</button>
                <button class="alarms-filter-btn ${this.alarmsFilterTimeRange === '6h' ? 'active' : ''}"
                        data-time-range="6h">6H</button>
                <button class="alarms-filter-btn ${this.alarmsFilterTimeRange === '24h' ? 'active' : ''}"
                        data-time-range="24h">24H</button>
                <button class="alarms-filter-btn ${this.alarmsFilterTimeRange === '7d' ? 'active' : ''}"
                        data-time-range="7d">7D</button>
                <button class="alarms-filter-btn ${this.alarmsFilterTimeRange === 'all' ? 'active' : ''}"
                        data-time-range="all">ALL</button>
              </div>
            </div>
          </div>

          <!-- Historical Alarm Table -->
          <div class="alarms-historical-table-container">
            ${alarms.length > 0 ? `
              <table class="alarms-historical-table">
                <thead>
                  <tr>
                    <th class="alarms-th-severity">SEV</th>
                    <th class="alarms-th-source">SOURCE</th>
                    <th class="alarms-th-message">MESSAGE</th>
                    <th class="alarms-th-target">TARGET</th>
                    <th class="alarms-th-triggered">TRIGGERED</th>
                    <th class="alarms-th-cleared">CLEARED</th>
                  </tr>
                </thead>
                <tbody>
                  ${alarms.map(alarm => this._renderHistoricalAlarmRow(alarm)).join('')}
                </tbody>
              </table>
            ` : `
              <div class="alarms-table-empty">
                <svg class="w-10 h-10" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"
                        d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
                </svg>
                <span>No historical alarms found</span>
              </div>
            `}
          </div>
        </div>

        <!-- Resize Handle -->
        <div class="alarms-resize-handle" id="alarms-resize-handle">
          <div class="alarms-resize-grip"></div>
        </div>

        <!-- Right Panel: Alarm Detail -->
        <div class="alarms-detail-panel" id="alarms-detail-panel">
          ${selectedAlarm
            ? this._renderAlarmDetailPanel(selectedAlarm)
            : `<div class="alarms-detail-empty">
                 <svg class="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                   <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"
                         d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"/>
                 </svg>
                 <span>Select an alarm to view details</span>
               </div>`
          }
        </div>
      </div>
    `
  },

  _renderHistoricalAlarmRow(alarm) {
    const isSelected = this.alarmsSelectedAlarm === alarm.id
    const targetName = alarm.target_id
      ? (this.targets.find(t => t.id === alarm.target_id)?.name || 'Unknown')
      : 'System'

    return `
      <tr class="alarms-historical-row ${isSelected ? 'selected' : ''}"
          data-alarm-id="${alarm.id}">
        <td class="alarms-td-severity">
          <span class="alarms-severity-dot severity-${alarm.severity}"></span>
        </td>
        <td class="alarms-td-source">${alarm.source_id || 'Unknown'}</td>
        <td class="alarms-td-message">${alarm.message || '-'}</td>
        <td class="alarms-td-target">${targetName}</td>
        <td class="alarms-td-time">${this._formatAlarmDateTime(alarm.triggered_at)}</td>
        <td class="alarms-td-time">${this._formatAlarmDateTime(alarm.cleared_at)}</td>
      </tr>
    `
  },

  _renderAlarmsRulesView() {
    return `
      <div class="alarms-placeholder-view">
        <svg class="w-16 h-16" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"
                d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"
                d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/>
        </svg>
        <span class="alarms-placeholder-title">ALARM RULES</span>
        <span class="alarms-placeholder-text">Alarm rules management coming soon</span>
      </div>
    `
  },

  _renderAlarmsAnalyticsView() {
    return `
      <div class="alarms-placeholder-view">
        <svg class="w-16 h-16" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"
                d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"/>
        </svg>
        <span class="alarms-placeholder-title">ANALYTICS</span>
        <span class="alarms-placeholder-text">Alarm analytics coming soon</span>
      </div>
    `
  },

  // =====================================================
  // Alarm Panel View (Annunciator Panel)
  // =====================================================

  _renderAlarmsPanelView() {
    const panelCells = this._computePanelCells()
    const selectedCell = this.alarmPanelSelectedCell
      ? panelCells.find(c => c.rule.id === this.alarmPanelSelectedCell)
      : null

    // Count active alarms by state
    const activeCells = panelCells.filter(c => c.state !== 'ok')
    const criticalCount = activeCells.filter(c => c.rule.severity === 'critical' && c.state === 'active').length
    const warningCount = activeCells.filter(c => c.rule.severity === 'warning' && c.state === 'active').length
    const ackCount = activeCells.filter(c => c.state === 'acknowledged').length

    return `
      <div class="alarms-panel-fullwidth">
        <!-- Header Bar -->
        <div class="alarms-panel-header-bar">
          <div class="alarms-panel-title">
            <span class="mc-label-subsystem">ANNUNCIATOR PANEL</span>
            <span class="alarms-count">${panelCells.length} rules</span>
            ${criticalCount > 0 ? `<span class="alarms-panel-badge critical">${criticalCount} CRIT</span>` : ''}
            ${warningCount > 0 ? `<span class="alarms-panel-badge warning">${warningCount} WARN</span>` : ''}
            ${ackCount > 0 ? `<span class="alarms-panel-badge ack">${ackCount} ACK</span>` : ''}
          </div>
          <div class="alarms-panel-controls">
            <select class="alarms-panel-size-select" id="panel-size-select">
              <option value="auto" ${this.alarmPanelGridSize === 'auto' ? 'selected' : ''}>Auto</option>
              <option value="small" ${this.alarmPanelGridSize === 'small' ? 'selected' : ''}>Small</option>
              <option value="medium" ${this.alarmPanelGridSize === 'medium' ? 'selected' : ''}>Medium</option>
              <option value="large" ${this.alarmPanelGridSize === 'large' ? 'selected' : ''}>Large</option>
            </select>
          </div>
        </div>

        <!-- Full-width Grid -->
        <div class="alarms-panel-grid alarms-panel-grid-${this.alarmPanelGridSize}">
          ${panelCells.length > 0 ? panelCells.map(cell => this._renderPanelCell(cell)).join('') : `
            <div class="alarms-panel-empty">
              <svg class="w-10 h-10" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"
                      d="M9 17V7m0 10a2 2 0 01-2 2H5a2 2 0 01-2-2V7a2 2 0 012-2h2a2 2 0 012 2m0 10a2 2 0 002 2h2a2 2 0 002-2M9 7a2 2 0 012-2h2a2 2 0 012 2m0 10V7m0 10a2 2 0 002 2h2a2 2 0 002-2V7a2 2 0 00-2-2h-2a2 2 0 00-2 2"/>
              </svg>
              <span>No alarm rules configured</span>
            </div>
          `}
        </div>

        <!-- Slide-up Detail Overlay -->
        ${selectedCell ? `
          <div class="alarms-panel-overlay">
            <div class="alarms-panel-overlay-content">
              <button class="alarms-panel-overlay-close" data-action="close-panel-overlay">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                </svg>
              </button>
              ${this._renderPanelOverlayContent(selectedCell)}
            </div>
          </div>
        ` : ''}
      </div>
    `
  },

  _renderPanelOverlayContent(selectedCell) {
    const rule = selectedCell.rule
    const alarm = selectedCell.alarm
    const targetName = rule.target_id
      ? (this.targets.find(t => t.id === rule.target_id)?.name || 'Unknown')
      : 'All Targets'

    if (alarm) {
      // Active alarm - show alarm details with actions
      const timeSince = this._formatTimeSince(alarm.triggered_at)
      return `
        <div class="alarms-panel-overlay-grid">
          <div class="alarms-panel-overlay-main">
            <div class="alarms-panel-overlay-header">
              <span class="alarms-detail-severity severity-${alarm.severity}">${alarm.severity.toUpperCase()}</span>
              <span class="alarms-detail-source">${rule.name}</span>
              <span class="alarms-panel-overlay-status state-${alarm.status}">${alarm.status.toUpperCase()}</span>
            </div>
            <p class="alarms-panel-overlay-message">${alarm.message || 'No message'}</p>
          </div>
          <div class="alarms-panel-overlay-meta">
            <div class="alarms-panel-overlay-item">
              <span class="label">TARGET</span>
              <span class="value">${targetName}</span>
            </div>
            <div class="alarms-panel-overlay-item">
              <span class="label">TRIGGERED</span>
              <span class="value">${timeSince} ago</span>
            </div>
            <div class="alarms-panel-overlay-item">
              <span class="label">SOURCE</span>
              <span class="value">${alarm.source_id || 'N/A'}</span>
            </div>
            ${alarm.current_value !== null ? `
              <div class="alarms-panel-overlay-item">
                <span class="label">VALUE</span>
                <span class="value">${typeof alarm.current_value === 'number' ? alarm.current_value.toFixed(2) : alarm.current_value}</span>
              </div>
            ` : ''}
          </div>
          <div class="alarms-panel-overlay-actions">
            ${alarm.status === 'active' ? `
              <button class="alarm-action-btn acknowledge" data-alarm-id="${alarm.id}">ACKNOWLEDGE</button>
              <button class="alarm-action-btn shelve" data-alarm-id="${alarm.id}">SHELVE</button>
            ` : ''}
            ${alarm.status === 'acknowledged' ? `
              <button class="alarm-action-btn shelve" data-alarm-id="${alarm.id}">SHELVE</button>
            ` : ''}
            ${alarm.status === 'shelved' ? `
              <button class="alarm-action-btn unshelve" data-alarm-id="${alarm.id}">UNSHELVE</button>
            ` : ''}
            <button class="alarm-action-btn clear" data-alarm-id="${alarm.id}">CLEAR</button>
          </div>
        </div>
      `
    } else {
      // Rule is OK - show rule info
      return `
        <div class="alarms-panel-overlay-grid">
          <div class="alarms-panel-overlay-main">
            <div class="alarms-panel-overlay-header">
              <span class="alarms-detail-severity severity-${rule.severity}">${rule.severity.toUpperCase()}</span>
              <span class="alarms-detail-source">${rule.name}</span>
              <span class="alarms-panel-overlay-status state-ok">OK</span>
            </div>
            <p class="alarms-panel-overlay-message">This alarm rule is not currently triggered.</p>
          </div>
          <div class="alarms-panel-overlay-meta">
            <div class="alarms-panel-overlay-item">
              <span class="label">TARGET</span>
              <span class="value">${targetName}</span>
            </div>
            <div class="alarms-panel-overlay-item">
              <span class="label">EVENT TYPE</span>
              <span class="value">${rule.event_type || 'telemetry_limit'}</span>
            </div>
            ${rule.message_template ? `
              <div class="alarms-panel-overlay-item wide">
                <span class="label">MESSAGE TEMPLATE</span>
                <span class="value">${rule.message_template}</span>
              </div>
            ` : ''}
          </div>
        </div>
      `
    }
  },

  _computePanelCells() {
    const cells = (this.alarmRules || []).map(rule => {
      // Find matching active alarm via alarm_rule_id
      const activeAlarm = (this.alarms || []).find(a => a.alarm_rule_id === rule.id)

      return {
        rule,
        alarm: activeAlarm || null,
        state: this._getPanelCellState(activeAlarm),
        value: activeAlarm?.current_value,
        triggeredAt: activeAlarm?.triggered_at
      }
    })

    // Sort by severity (critical first), then by state (active first)
    const severityOrder = { critical: 0, warning: 1, info: 2 }
    const stateOrder = { active: 0, acknowledged: 1, shelved: 2, ok: 3 }

    return cells.sort((a, b) => {
      const sevDiff = (severityOrder[a.rule.severity] || 2) - (severityOrder[b.rule.severity] || 2)
      if (sevDiff !== 0) return sevDiff
      return (stateOrder[a.state] || 3) - (stateOrder[b.state] || 3)
    })
  },

  _getPanelCellState(alarm) {
    if (!alarm) return 'ok'
    return alarm.status  // 'active', 'acknowledged', 'shelved'
  },

  _renderPanelCell(cell) {
    const isSelected = this.alarmPanelSelectedCell === cell.rule.id
    const targetName = cell.rule.target_id
      ? (this.targets.find(t => t.id === cell.rule.target_id)?.name || 'Unknown')
      : 'All'

    // Format time since triggered
    const timeSince = cell.triggeredAt ? this._formatTimeSince(cell.triggeredAt) : null

    // Format value (show only for active alarms with numeric value)
    const valueStr = (cell.value !== null && cell.value !== undefined)
      ? (typeof cell.value === 'number' ? cell.value.toFixed(2) : String(cell.value))
      : null

    return `
      <div class="alarm-panel-cell state-${cell.state} severity-${cell.rule.severity} ${isSelected ? 'selected' : ''}"
           data-rule-id="${cell.rule.id}"
           data-alarm-id="${cell.alarm?.id || ''}">
        <div class="alarm-panel-cell-header">
          <span class="alarm-panel-cell-name" title="${cell.rule.name}">${cell.rule.name}</span>
          <span class="alarm-panel-cell-indicator"></span>
        </div>
        <div class="alarm-panel-cell-body">
          ${valueStr ? `<span class="alarm-panel-cell-value">${valueStr}</span>` : ''}
          ${timeSince ? `<span class="alarm-panel-cell-time">${timeSince}</span>` : ''}
          ${!valueStr && !timeSince ? `<span class="alarm-panel-cell-status">OK</span>` : ''}
        </div>
        <div class="alarm-panel-cell-footer">
          <span class="alarm-panel-cell-target">${targetName}</span>
        </div>
      </div>
    `
  },

  _formatTimeSince(isoString) {
    if (!isoString) return null
    const triggered = new Date(isoString)
    const now = new Date()
    const diffMs = now - triggered
    const diffSecs = Math.floor(diffMs / 1000)

    if (diffSecs < 60) return `${diffSecs}s`
    if (diffSecs < 3600) return `${Math.floor(diffSecs / 60)}m`
    if (diffSecs < 86400) return `${Math.floor(diffSecs / 3600)}h`
    return `${Math.floor(diffSecs / 86400)}d`
  },

  _getFilteredAlarms() {
    let alarms = this.alarms || []

    // Filter by status
    alarms = alarms.filter(a => this.alarmsFilterStatus.has(a.status))

    // Filter by severity
    alarms = alarms.filter(a => this.alarmsFilterSeverity.has(a.severity))

    // Filter by selected targets (empty set = all targets)
    if (this.alarmsSelectedTargets.size > 0) {
      alarms = alarms.filter(a => this.alarmsSelectedTargets.has(a.target_id))
    }

    // Filter by search query
    if (this.alarmsSearchQuery) {
      const query = this.alarmsSearchQuery.toLowerCase()
      alarms = alarms.filter(a =>
        a.source_id?.toLowerCase().includes(query) ||
        a.message?.toLowerCase().includes(query)
      )
    }

    return alarms
  },

  _groupAlarmsBySeverity(alarms) {
    const groups = {
      critical: [],
      warning: [],
      info: []
    }

    for (const alarm of alarms) {
      if (groups[alarm.severity]) {
        groups[alarm.severity].push(alarm)
      }
    }

    // Sort each group by triggered_at (newest first)
    for (const severity of Object.keys(groups)) {
      groups[severity].sort((a, b) => new Date(b.triggered_at) - new Date(a.triggered_at))
    }

    return groups
  },

  _renderAlarmGroups(groupedAlarms) {
    const severities = ['critical', 'warning', 'info']
    const severityLabels = {
      critical: 'CRITICAL',
      warning: 'WARNING',
      info: 'INFO'
    }

    return severities.map(severity => {
      const alarms = groupedAlarms[severity]
      const isCollapsed = this.alarmsCollapsedGroups.has(severity)
      const count = alarms.length

      if (count === 0) return ''

      return `
        <div class="alarms-group severity-${severity}">
          <div class="alarms-group-header" data-severity="${severity}">
            <svg class="alarms-group-chevron ${isCollapsed ? 'collapsed' : ''}"
                 fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/>
            </svg>
            <span class="alarms-group-dot severity-${severity}"></span>
            <span class="alarms-group-label">${severityLabels[severity]}</span>
            <span class="alarms-group-count">${count}</span>
          </div>
          <div class="alarms-group-items ${isCollapsed ? 'collapsed' : ''}">
            ${alarms.map(alarm => this._renderAlarmRow(alarm)).join('')}
          </div>
        </div>
      `
    }).join('')
  },

  _renderAlarmRow(alarm) {
    const isSelected = this.alarmsSelectedAlarm === alarm.id
    const triggeredTime = this._formatAlarmTime(alarm.triggered_at)
    const targetName = alarm.target_id
      ? (this.targets.find(t => t.id === alarm.target_id)?.name || 'Unknown')
      : 'System'

    return `
      <div class="alarms-row ${isSelected ? 'selected' : ''} status-${alarm.status}"
           data-alarm-id="${alarm.id}">
        <div class="alarms-row-main">
          <span class="alarms-row-status status-${alarm.status}"></span>
          <div class="alarms-row-content">
            <div class="alarms-row-source">${alarm.source_id || 'Unknown'}</div>
            <div class="alarms-row-message">${alarm.message || 'No message'}</div>
          </div>
          <div class="alarms-row-meta">
            <span class="alarms-row-target">${targetName}</span>
            <span class="alarms-row-time">${triggeredTime}</span>
          </div>
        </div>
        <div class="alarms-row-actions">
          ${alarm.status === 'active' ? `
            <button class="alarms-action-btn" data-action="acknowledge" data-alarm-id="${alarm.id}" title="Acknowledge">
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
              </svg>
            </button>
          ` : ''}
          ${alarm.status !== 'shelved' ? `
            <button class="alarms-action-btn" data-action="shelve" data-alarm-id="${alarm.id}" title="Shelve">
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
              </svg>
            </button>
          ` : `
            <button class="alarms-action-btn" data-action="unshelve" data-alarm-id="${alarm.id}" title="Unshelve">
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
              </svg>
            </button>
          `}
        </div>
      </div>
    `
  },

  _renderAlarmDetailPanel(alarm) {
    const targetName = alarm.target_id
      ? (this.targets.find(t => t.id === alarm.target_id)?.name || 'Unknown')
      : 'System'
    const triggeredTime = this._formatAlarmDateTime(alarm.triggered_at)

    return `
      <div class="alarms-detail-content">
        <!-- Header -->
        <div class="alarms-detail-header">
          <div class="alarms-detail-title">
            <span class="alarms-detail-severity severity-${alarm.severity}">${alarm.severity.toUpperCase()}</span>
            <span class="alarms-detail-source">${alarm.source_id || 'Unknown'}</span>
          </div>
          <span class="alarms-detail-status status-${alarm.status}">${alarm.status.toUpperCase()}</span>
        </div>

        <!-- Message -->
        <div class="alarms-detail-section">
          <span class="alarms-detail-label">MESSAGE</span>
          <p class="alarms-detail-message">${alarm.message || 'No message provided'}</p>
        </div>

        <!-- Details Grid -->
        <div class="alarms-detail-grid">
          <div class="alarms-detail-item">
            <span class="alarms-detail-label">TARGET</span>
            <span class="alarms-detail-value">${targetName}</span>
          </div>
          <div class="alarms-detail-item">
            <span class="alarms-detail-label">TRIGGERED</span>
            <span class="alarms-detail-value">${triggeredTime}</span>
          </div>
          ${alarm.current_value !== null && alarm.current_value !== undefined ? `
            <div class="alarms-detail-item">
              <span class="alarms-detail-label">VALUE</span>
              <span class="alarms-detail-value">${alarm.current_value}</span>
            </div>
          ` : ''}
          ${alarm.limit_state ? `
            <div class="alarms-detail-item">
              <span class="alarms-detail-label">LIMIT STATE</span>
              <span class="alarms-detail-value limit-${alarm.limit_state}">${alarm.limit_state.toUpperCase()}</span>
            </div>
          ` : ''}
          ${alarm.acknowledged_at ? `
            <div class="alarms-detail-item">
              <span class="alarms-detail-label">ACKNOWLEDGED</span>
              <span class="alarms-detail-value">${this._formatAlarmDateTime(alarm.acknowledged_at)}</span>
            </div>
          ` : ''}
          ${alarm.shelved_until ? `
            <div class="alarms-detail-item">
              <span class="alarms-detail-label">SHELVED UNTIL</span>
              <span class="alarms-detail-value">${this._formatAlarmDateTime(alarm.shelved_until)}</span>
            </div>
          ` : ''}
        </div>

        <!-- Actions -->
        <div class="alarms-detail-actions">
          ${alarm.status === 'active' ? `
            <button class="btn btn-primary btn-sm" data-action="acknowledge" data-alarm-id="${alarm.id}">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
              </svg>
              ACKNOWLEDGE
            </button>
          ` : ''}
          ${alarm.status !== 'shelved' ? `
            <button class="btn btn-warning btn-sm" data-action="shelve" data-alarm-id="${alarm.id}">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
              </svg>
              SHELVE
            </button>
          ` : `
            <button class="btn btn-success btn-sm" data-action="unshelve" data-alarm-id="${alarm.id}">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
              </svg>
              UNSHELVE
            </button>
          `}
          <button class="btn btn-error btn-sm" data-action="clear" data-alarm-id="${alarm.id}">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
            </svg>
            CLEAR
          </button>
        </div>
      </div>
    `
  },

  _formatAlarmTime(isoString) {
    if (!isoString) return '--:--'
    const date = new Date(isoString)
    return date.toLocaleTimeString('en-US', {
      hour: '2-digit',
      minute: '2-digit',
      hour12: false
    })
  },

  _formatAlarmDateTime(isoString) {
    if (!isoString) return '--'
    const date = new Date(isoString)
    return date.toLocaleString('en-US', {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false
    })
  },

  _bindAlarmsModeEvents(container) {
    // View tab switching
    container.querySelectorAll('.alarms-view-tab').forEach(tab => {
      tab.addEventListener('click', () => {
        const view = tab.dataset.view
        this.alarmsViewMode = view

        // Load data on-demand when switching views
        if (view === 'panel') {
          this.pushEvent('load_alarm_rules', {})
        } else if (view === 'historical') {
          this.pushEvent('load_historical_alarms', { time_range: this.alarmsFilterTimeRange })
        }

        this._renderAlarmsMode()
      })
    })

    // Status filter buttons (only for active view)
    container.querySelectorAll('.alarms-filter-btn[data-status]').forEach(btn => {
      btn.addEventListener('click', () => {
        const status = btn.dataset.status
        if (this.alarmsFilterStatus.has(status)) {
          this.alarmsFilterStatus.delete(status)
        } else {
          this.alarmsFilterStatus.add(status)
        }
        this._renderAlarmsMode()
      })
    })

    // Time range filter buttons (for historical view)
    container.querySelectorAll('.alarms-filter-btn[data-time-range]').forEach(btn => {
      btn.addEventListener('click', () => {
        const timeRange = btn.dataset.timeRange
        this.alarmsFilterTimeRange = timeRange
        this.pushEvent('load_historical_alarms', { time_range: timeRange })
        this._renderAlarmsMode()
      })
    })

    // Severity filter buttons
    container.querySelectorAll('.alarms-severity-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        const severity = btn.dataset.severity
        if (this.alarmsFilterSeverity.has(severity)) {
          this.alarmsFilterSeverity.delete(severity)
        } else {
          this.alarmsFilterSeverity.add(severity)
        }
        this._renderAlarmsMode()
      })
    })

    // Target panel events
    this._bindAlarmsTargetPanelEvents(container)

    // Group header collapse/expand
    container.querySelectorAll('.alarms-group-header').forEach(header => {
      header.addEventListener('click', () => {
        const severity = header.dataset.severity
        if (this.alarmsCollapsedGroups.has(severity)) {
          this.alarmsCollapsedGroups.delete(severity)
        } else {
          this.alarmsCollapsedGroups.add(severity)
        }
        this._renderAlarmsMode()
      })
    })

    // Alarm row selection (active view)
    container.querySelectorAll('.alarms-row').forEach(row => {
      row.addEventListener('click', (e) => {
        // Don't select if clicking on action buttons
        if (e.target.closest('.alarms-action-btn')) return

        const alarmId = row.dataset.alarmId
        this.alarmsSelectedAlarm = alarmId
        this._renderAlarmsMode()
      })
    })

    // Historical alarm row selection
    container.querySelectorAll('.alarms-historical-row').forEach(row => {
      row.addEventListener('click', () => {
        const alarmId = row.dataset.alarmId
        this.alarmsSelectedAlarm = alarmId
        this._renderAlarmsMode()
      })
    })

    // Panel cell selection
    container.querySelectorAll('.alarm-panel-cell').forEach(cell => {
      cell.addEventListener('click', () => {
        const ruleId = cell.dataset.ruleId
        const alarmId = cell.dataset.alarmId

        this.alarmPanelSelectedCell = ruleId
        // If cell has an active alarm, also set alarmsSelectedAlarm for reuse
        if (alarmId) {
          this.alarmsSelectedAlarm = alarmId
        }
        this._renderAlarmsMode()
      })
    })

    // Panel grid size selector
    const sizeSelect = container.querySelector('#panel-size-select')
    if (sizeSelect) {
      sizeSelect.addEventListener('change', (e) => {
        this.alarmPanelGridSize = e.target.value
        this._renderAlarmsMode()
      })
    }

    // Panel overlay close button
    const closeOverlayBtn = container.querySelector('[data-action="close-panel-overlay"]')
    if (closeOverlayBtn) {
      closeOverlayBtn.addEventListener('click', () => {
        this.alarmPanelSelectedCell = null
        this.alarmsSelectedAlarm = null
        this._renderAlarmsMode()
      })
    }

    // Panel overlay action buttons
    container.querySelectorAll('.alarms-panel-overlay-actions .alarm-action-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        const alarmId = btn.dataset.alarmId
        if (btn.classList.contains('acknowledge')) {
          this.pushEvent('acknowledge_alarm', { id: alarmId })
        } else if (btn.classList.contains('shelve')) {
          this.pushEvent('open_shelve_modal', { id: alarmId })
        } else if (btn.classList.contains('unshelve')) {
          this.pushEvent('unshelve_alarm', { id: alarmId })
        } else if (btn.classList.contains('clear')) {
          this.pushEvent('clear_alarm', { id: alarmId })
        }
      })
    })

    // Inline action buttons
    container.querySelectorAll('.alarms-action-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation()
        const action = btn.dataset.action
        const alarmId = btn.dataset.alarmId
        this._handleAlarmAction(action, alarmId)
      })
    })

    // Detail panel action buttons
    container.querySelectorAll('.alarms-detail-actions button').forEach(btn => {
      btn.addEventListener('click', () => {
        const action = btn.dataset.action
        const alarmId = btn.dataset.alarmId
        this._handleAlarmAction(action, alarmId)
      })
    })

    // Acknowledge All Visible button
    const ackAllBtn = container.querySelector('#alarms-ack-all')
    if (ackAllBtn) {
      ackAllBtn.addEventListener('click', () => {
        const activeAlarms = this._getFilteredAlarms().filter(a => a.status === 'active')
        const alarmIds = activeAlarms.map(a => a.id)
        if (alarmIds.length > 0) {
          this.pushEvent('acknowledge_alarms', { alarm_ids: alarmIds })
        }
      })
    }

    // Resize handle for split view
    this._bindAlarmsResizeHandle(container)
  },

  _bindAlarmsTargetPanelEvents(container) {
    // Target cell selection
    container.querySelectorAll('.alarms-target-cell').forEach(cell => {
      cell.addEventListener('click', () => {
        const targetId = cell.dataset.targetId
        if (this.alarmsSelectedTargets.has(targetId)) {
          this.alarmsSelectedTargets.delete(targetId)
        } else {
          this.alarmsSelectedTargets.add(targetId)
        }
        this._renderAlarmsMode()
      })
    })

    // Target search input
    const targetSearch = container.querySelector('#alarms-target-search')
    if (targetSearch) {
      targetSearch.addEventListener('input', (e) => {
        this.alarmsTargetSearch = e.target.value
        this._renderAlarmsMode()
      })
    }

    // Target view mode toggle
    container.querySelectorAll('.alarms-view-btn[data-target-view]').forEach(btn => {
      btn.addEventListener('click', () => {
        this.alarmsTargetViewMode = btn.dataset.targetView
        this._renderAlarmsMode()
      })
    })

    // Select All button
    const selectAllBtn = container.querySelector('#alarms-select-all-targets')
    if (selectAllBtn) {
      selectAllBtn.addEventListener('click', () => {
        this.targets.forEach(t => this.alarmsSelectedTargets.add(t.id))
        this._renderAlarmsMode()
      })
    }

    // Clear button
    const clearBtn = container.querySelector('#alarms-clear-targets')
    if (clearBtn) {
      clearBtn.addEventListener('click', () => {
        this.alarmsSelectedTargets.clear()
        this._renderAlarmsMode()
      })
    }
  },

  _bindAlarmsResizeHandle(container) {
    const panelsRow = container.querySelector('#alarms-panels-row')
    if (!panelsRow) return

    // Target panel resize handle
    const targetResizeHandle = container.querySelector('#alarms-target-resize-handle')
    if (targetResizeHandle) {
      this._setupResizeHandle(targetResizeHandle, panelsRow, '#alarms-target-panel', 'alarmsTargetPanelWidth', 15, 40)
    }

    // List panel resize handle
    const listResizeHandle = container.querySelector('#alarms-resize-handle')
    if (listResizeHandle) {
      this._setupResizeHandle(listResizeHandle, panelsRow, '#alarms-list-panel', 'alarmsListPanelWidth', 25, 60)
    }
  },

  _setupResizeHandle(handle, panelsRow, panelSelector, stateKey, minPercent, maxPercent) {
    handle.addEventListener('mousedown', (e) => {
      e.preventDefault()

      const panel = panelsRow.querySelector(panelSelector)
      if (!panel) return

      handle.classList.add('dragging')

      const startX = e.clientX
      const layoutRect = panelsRow.getBoundingClientRect()
      const startWidth = panel.getBoundingClientRect().width
      const layoutWidth = layoutRect.width

      const onMouseMove = (moveEvent) => {
        const deltaX = moveEvent.clientX - startX
        const newWidth = startWidth + deltaX
        const newPercent = (newWidth / layoutWidth) * 100

        const clampedPercent = Math.max(minPercent, Math.min(maxPercent, newPercent))

        panel.style.flex = `0 0 ${clampedPercent}%`
        this[stateKey] = clampedPercent
      }

      const onMouseUp = () => {
        handle.classList.remove('dragging')
        document.removeEventListener('mousemove', onMouseMove)
        document.removeEventListener('mouseup', onMouseUp)
      }

      document.addEventListener('mousemove', onMouseMove)
      document.addEventListener('mouseup', onMouseUp)
    })
  },

  _handleAlarmAction(action, alarmId) {
    switch (action) {
      case 'acknowledge':
        this.pushEvent('acknowledge_alarm', { id: alarmId })
        break
      case 'shelve':
        // Open the shelve modal (existing handler)
        this.pushEvent('open_shelve_modal', { id: alarmId })
        break
      case 'unshelve':
        this.pushEvent('unshelve_alarm', { id: alarmId })
        break
      case 'clear':
        this.pushEvent('clear_alarm', { id: alarmId })
        break
    }
  },

  updated() {
    // Custom panel layout handles resize via CSS
  },

  destroyed() {
    console.log("[OpsConsole] Destroying...")

    // Clean up timeline update interval
    if (this._timelineUpdateInterval) {
      clearInterval(this._timelineUpdateInterval)
      this._timelineUpdateInterval = null
    }

    // Remove keyboard handler
    if (this._keydownHandler) {
      document.removeEventListener("keydown", this._keydownHandler)
    }

    // Exit fullscreen if active
    this._exitFullscreen()

    // Close and remove slideout elements
    const backdrop = document.getElementById("cmd-slideout-backdrop")
    const slideout = document.getElementById("cmd-slideout")
    if (backdrop) backdrop.remove()
    if (slideout) slideout.remove()

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
    this.panelLayout?.destroy()
  }
}

export default OpsConsoleHook
