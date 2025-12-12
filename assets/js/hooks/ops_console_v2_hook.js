/**
 * Ops Console V2 LiveView Hook
 *
 * Next generation mission control interface featuring:
 * - Custom CSS-based panel layout with snap-to-close
 * - Global status bar integration
 * - Enhanced mission-control visual design
 * - Fullscreen widget capability
 * - New widget types (Command, Procedure, Alarm Summary, Fleet Health)
 */

import { createPanelLayout } from "../layout/panel_layout"
import { createGridManager } from "../dashboard/gridstack_manager"
import { TelemetryStore, getStore } from "../telemetry_store"

// Import widgets to register them
import "../widgets/index"

/**
 * OpsConsoleV2 LiveView Hook
 */
export const OpsConsoleV2Hook = {
  mounted() {
    console.log("[OpsConsoleV2] Mounting...", this.el.id)

    // Get configuration from data attributes
    this.missionId = this.el.dataset.missionId
    this.frameLayout = JSON.parse(this.el.dataset.layout || "null")
    this.widgets = JSON.parse(this.el.dataset.widgets || "[]")
    this.targets = JSON.parse(this.el.dataset.targets || "[]")
    this.dashboards = JSON.parse(this.el.dataset.dashboards || "[]")
    this.alarms = JSON.parse(this.el.dataset.alarms || "[]")
    this.commands = JSON.parse(this.el.dataset.commands || "[]")
    this.currentDashboardId = this.el.dataset.currentDashboardId
    this.token = this.el.dataset.token

    // Track collapsed state for context panel sections
    this.collapsedSections = {
      alarms: false,
      commands: false
    }

    // Track managers
    this.panelLayout = null
    this.gridManager = null
    this.telemetryStore = null
    this._windowResizeHandler = null
    this._initialized = false
    this._fullscreenWidget = null
    this.currentMode = "overview"
    this.selectedTargetId = null

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
      console.log("[OpsConsoleV2] Already initialized, skipping")
      return
    }

    try {
      // 1. Initialize custom panel layout on the inner container
      const layoutContainer = this.el.querySelector("#ops-console-v2")
      this.panelLayout = createPanelLayout(layoutContainer, {})
      this.panelLayout.init()

      // 2. Load saved panel state from localStorage (client-side preference)
      const storageKey = `ops-console-v2-panels-${this.missionId}`
      try {
        const savedPanelState = localStorage.getItem(storageKey)
        if (savedPanelState) {
          this.panelLayout.loadState(JSON.parse(savedPanelState))
        }
      } catch (e) {
        console.warn("[OpsConsoleV2] Failed to load panel state:", e)
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
      console.log("[OpsConsoleV2] Initialization complete")

    } catch (err) {
      console.error("[OpsConsoleV2] Initialization failed:", err)
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
        const storageKey = `ops-console-v2-panels-${this.missionId}`
        try {
          localStorage.setItem(storageKey, JSON.stringify(state))
        } catch (e) {
          console.warn("[OpsConsoleV2] Failed to save panel state:", e)
        }
      }, 500)
    })

    // Handle panel open/close for analytics or logging
    this.panelLayout.on("panel:opened", ({ panel }) => {
      console.log("[OpsConsoleV2] Panel opened:", panel)
    })

    this.panelLayout.on("panel:closed", ({ panel }) => {
      console.log("[OpsConsoleV2] Panel closed:", panel)
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
        <div class="nav-expanded p-3">
          <!-- Mission header -->
          <div class="mb-4">
            <span class="mc-label-subsystem text-base-content/40 block mb-1">MISSION</span>
            <span class="font-semibold text-sm text-primary">${missionName}</span>
          </div>

          <!-- Mode selector -->
          <div class="mb-4">
            <span class="mc-label-subsystem text-base-content/40 block mb-2">MODE</span>
            <div class="flex flex-col gap-1">
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
            </div>
          </div>

          <!-- Dashboards list -->
          <div class="mb-4">
            <div class="flex items-center justify-between mb-2">
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
          <div class="mt-auto pt-4 border-t border-base-300">
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
        console.log("[OpsConsoleV2] Mode changed:", this.currentMode)
      })
    })

    // Rail mode buttons
    navContent.querySelectorAll(".nav-rail .rail-btn[data-mode]").forEach(btn => {
      btn.addEventListener("click", () => {
        navContent.querySelectorAll(".mode-btn, .rail-btn[data-mode]").forEach(b => b.classList.remove("active"))
        navContent.querySelectorAll(`[data-mode="${btn.dataset.mode}"]`).forEach(b => b.classList.add("active"))
        this.currentMode = btn.dataset.mode
        console.log("[OpsConsoleV2] Mode changed:", this.currentMode)
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
          <div class="context-section-content">
            ${this.commands.length > 0 ?
              this.commands.map(cmd => this._renderCommandQueueItem(cmd)).join("") :
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

    // Command cancel handlers
    contextContent.querySelectorAll(".command-btn-cancel").forEach(btn => {
      btn.addEventListener("click", (e) => {
        e.stopPropagation()
        const commandId = btn.closest(".command-queue-item").dataset.id
        this.pushEvent("cancel_command", { id: commandId })
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

  _renderCommandQueueItem(cmd) {
    const statusClass = cmd.status === "executing" ? "command-executing" : "command-pending"

    return `
      <div class="command-queue-item ${statusClass}" data-id="${cmd.id}">
        <div class="command-header">
          <span class="command-target">${cmd.target_name || "Unknown"}</span>
          <span class="command-status">${cmd.status.toUpperCase()}</span>
        </div>
        <div class="command-name">${cmd.command_name}</div>
        <div class="command-actions">
          ${cmd.status === "pending" ? '<button class="command-btn command-btn-cancel">CANCEL</button>' : ''}
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
      console.log("[OpsConsoleV2] Target selected:", this.selectedTargetId)
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

      // Escape - exit fullscreen or close modals
      if (e.key === "Escape") {
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
      console.warn("[OpsConsoleV2] Missing token or missionId, skipping telemetry connection")
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
      console.error("[OpsConsoleV2] Failed to connect telemetry:", err)
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
      console.log("[OpsConsoleV2] Widget removed:", id)
      this._updateToolbar()
    })

    this.gridManager.on("widgetAdded", ({ id, type }) => {
      console.log("[OpsConsoleV2] Widget added:", id, type)
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
            console.error("[OpsConsoleV2] Failed to add widget:", err)
          }
        } else {
          console.error("[OpsConsoleV2] GridManager not initialized!")
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
      // Re-render alarms in context panel
      this._populateContextPanel()
    })

    this.handleEvent("update_commands", (payload) => {
      this.commands = payload.commands || []
      // Re-render context panel with updated commands
      this._populateContextPanel()
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

  _debounce(key, fn, delay) {
    if (!this._debounceTimers) {
      this._debounceTimers = {}
    }

    if (this._debounceTimers[key]) {
      clearTimeout(this._debounceTimers[key])
    }

    this._debounceTimers[key] = setTimeout(fn, delay)
  },

  updated() {
    // Custom panel layout handles resize via CSS
  },

  destroyed() {
    console.log("[OpsConsoleV2] Destroying...")

    // Remove keyboard handler
    if (this._keydownHandler) {
      document.removeEventListener("keydown", this._keydownHandler)
    }

    // Exit fullscreen if active
    this._exitFullscreen()

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

export default OpsConsoleV2Hook
