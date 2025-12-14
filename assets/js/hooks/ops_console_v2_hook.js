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
    this.commandDefinitions = JSON.parse(this.el.dataset.commandDefinitions || "[]")
    this.targetGroups = JSON.parse(this.el.dataset.targetGroups || "[]")
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

    // Commands mode state
    this.cmdSelectedTargets = new Set()
    this.cmdSelectedCommand = null
    this.cmdTargetFilter = ""
    this.cmdCommandFilter = ""
    this.cmdQueuePaused = false
    this.cmdPriority = 3 // Normal priority by default
    this.cmdTargetViewMode = "compact" // "compact" or "detailed"

    // Per-target parameterized command state
    this.cmdStagedParams = new Map()      // targetId -> { params: {...} }
    this.cmdActiveTargetIndex = 0         // Index of currently active target in selection
    this.cmdPerTargetMode = false         // Whether we're in per-target configuration mode
    this.cmdReviewMode = false            // Whether showing review screen before queue

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

  // ============================================================================
  // Mode Switching
  // ============================================================================

  _onModeChange() {
    console.log("[OpsConsoleV2] Mode changed to:", this.currentMode)

    const dashboard = this.panelLayout?.elements?.dashboard
    if (!dashboard) return

    if (this.currentMode === "commands") {
      // Hide GridStack dashboard, show Commands mode
      dashboard.classList.add("commands-mode-active")
      this._renderCommandsMode()
    } else {
      // Show GridStack dashboard, hide Commands mode
      dashboard.classList.remove("commands-mode-active")
      this._hideCommandsMode()
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
        <!-- Left: Target Selection -->
        <div class="cmd-target-panel">
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

  _bindCommandsModeEvents(container) {
    // Bind target cell events
    this._bindTargetCellEvents(container)

    // Bind command item events
    this._bindCommandItemEvents(container)

    // Initialize tooltip
    this._initTargetTooltip(container)

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
      // Review mode: Queue button
      return `
        <div class="cmd-dispatch-actions review-mode">
          <button class="cmd-dispatch-btn queue ${hazClass}"
                  id="slideout-queue-btn"
                  ${disabled}>
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"/>
            </svg>
            Queue ${stagedCount} Command${stagedCount !== 1 ? 's' : ''}
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
      console.warn("[OpsConsoleV2] No staged params to dispatch")
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

export default OpsConsoleV2Hook
