/**
 * Panel Registry V2
 *
 * Enhanced panel components for the Ops Console V2 layout.
 * Extends the base panels with new features and adds the Quick Access Bar.
 */

import { registerPanel, PANEL_SNAP_POINTS } from "./golden_layout_manager"

// Threshold width for collapsing panels
const NAV_COLLAPSE_THRESHOLD = (PANEL_SNAP_POINTS.navigation.compact + PANEL_SNAP_POINTS.navigation.full) / 2
const CONTEXT_COLLAPSE_THRESHOLD = (PANEL_SNAP_POINTS.context.compact + PANEL_SNAP_POINTS.context.full) / 2

/**
 * Navigation Panel V2 - Left sidebar
 * Enhanced with operational mode switching
 */
class NavigationPanelV2 {
  constructor(container, state, layoutManager) {
    this.container = container
    this.state = state
    this.layoutManager = layoutManager
    this.element = null
    this.collapsed = false
    this.resizeObserver = null
    this.dashboards = []
    this.currentDashboardId = null
    this.dashboardSectionExpanded = true
    this.currentMode = 'overview' // overview | focus | procedure

    this._render()
    this._bindEvents()
    this._setupResizeObserver()
  }

  _render() {
    this.element = document.createElement("div")
    this.element.className = "navigation-panel v2 h-full flex flex-col bg-base-200 overflow-hidden"
    this.element.innerHTML = `
      <div class="nav-header border-b border-base-300">
        <h2 class="nav-title text-lg font-bold text-primary">Mission</h2>
        <p class="nav-subtitle text-sm text-base-content/70" id="nav-mission-name">Loading...</p>
      </div>

      <!-- Operational Mode Selector -->
      <div class="nav-section mode-section">
        <span class="nav-section-title">Mode</span>
        <div class="mode-selector">
          <button class="mode-btn active" data-mode="overview" title="Constellation Overview">
            <svg class="mode-icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z"/>
            </svg>
            <span class="mode-label">Overview</span>
          </button>
          <button class="mode-btn" data-mode="focus" title="Vehicle Focus">
            <svg class="mode-icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z"/>
            </svg>
            <span class="mode-label">Focus</span>
          </button>
          <button class="mode-btn" data-mode="procedure" title="Procedure Execution">
            <svg class="mode-icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4"/>
            </svg>
            <span class="mode-label">Procedure</span>
          </button>
        </div>
      </div>

      <nav class="flex-1 overflow-y-auto">
        <div class="nav-section">
          <span class="nav-section-title">Quick Actions</span>
          <button class="nav-action" data-action="add-widget" title="Add Widget">
            <svg class="nav-icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
            </svg>
            <span class="nav-label">Add Widget</span>
          </button>
          <button class="nav-action" data-action="save-layout" title="Save Layout">
            <svg class="nav-icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4"/>
            </svg>
            <span class="nav-label">Save Layout</span>
          </button>
          <button class="nav-action" data-action="reset-layout" title="Reset Layout">
            <svg class="nav-icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
            </svg>
            <span class="nav-label">Reset Layout</span>
          </button>
        </div>

        <!-- Dashboards Section (collapsible) -->
        <div class="nav-section dashboards-section">
          <button class="nav-section-header" id="dashboards-toggle" title="Toggle Dashboards">
            <span class="nav-section-title">Dashboards</span>
            <svg class="nav-section-chevron w-3 h-3 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/>
            </svg>
          </button>
          <div class="dashboards-content" id="dashboards-content">
            <div class="dashboard-list" id="dashboard-list">
              <!-- Dashboard items rendered dynamically -->
            </div>
            <button class="nav-action create-dashboard-btn" data-action="create-dashboard" title="Create Dashboard">
              <svg class="nav-icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
              </svg>
              <span class="nav-label">New Dashboard</span>
            </button>
          </div>
        </div>
      </nav>

      <div class="nav-footer border-t border-base-300">
        <span id="nav-connection-status" class="nav-status">
          <span class="status-dot connected"></span>
          <span class="nav-label">Connected</span>
        </span>
      </div>
    `

    this.container.element.appendChild(this.element)
  }

  _bindEvents() {
    // Quick action buttons
    this.element.querySelectorAll(".nav-action").forEach(btn => {
      btn.addEventListener("click", (e) => {
        const action = e.currentTarget.dataset.action
        this.layoutManager.emit("navigation:action", { action })
      })
    })

    // Mode selector
    this.element.querySelectorAll(".mode-btn").forEach(btn => {
      btn.addEventListener("click", (e) => {
        const mode = e.currentTarget.dataset.mode
        this._setMode(mode)
        this.layoutManager.emit("navigation:modeChange", { mode })
      })
    })

    // Dashboards section toggle
    const toggle = this.element.querySelector("#dashboards-toggle")
    toggle?.addEventListener("click", () => {
      this.dashboardSectionExpanded = !this.dashboardSectionExpanded
      this._updateDashboardSectionState()
    })
  }

  _setMode(mode) {
    this.currentMode = mode
    this.element.querySelectorAll(".mode-btn").forEach(btn => {
      btn.classList.toggle("active", btn.dataset.mode === mode)
    })
  }

  _setupResizeObserver() {
    this.resizeObserver = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const width = entry.contentRect.width
        const shouldCollapse = width < NAV_COLLAPSE_THRESHOLD

        if (shouldCollapse !== this.collapsed) {
          this.collapsed = shouldCollapse
          this.element.classList.toggle("collapsed", shouldCollapse)
        }
      }
    })

    this.resizeObserver.observe(this.element)
  }

  _updateDashboardSectionState() {
    const content = this.element.querySelector("#dashboards-content")
    const chevron = this.element.querySelector(".nav-section-chevron")

    if (this.dashboardSectionExpanded) {
      content?.classList.remove("collapsed")
      chevron?.classList.remove("rotate-[-90deg]")
    } else {
      content?.classList.add("collapsed")
      chevron?.classList.add("rotate-[-90deg]")
    }
  }

  setDashboards(dashboards, currentId) {
    this.dashboards = dashboards || []
    this.currentDashboardId = currentId
    this._renderDashboardList()
  }

  setCurrentDashboard(id) {
    this.currentDashboardId = id
    this._updateActiveIndicator()
  }

  _renderDashboardList() {
    const container = this.element.querySelector("#dashboard-list")
    if (!container) return

    if (this.dashboards.length === 0) {
      container.innerHTML = `
        <p class="text-xs text-base-content/50 px-2 py-1">No dashboards</p>
      `
      return
    }

    container.innerHTML = this.dashboards.map(d => `
      <div class="dashboard-item ${d.id === this.currentDashboardId ? 'active' : ''}"
           data-dashboard-id="${d.id}">
        <span class="dashboard-name">${this._escapeHtml(d.name)}</span>
        <div class="dashboard-actions">
          <button class="dashboard-action-btn" data-action="rename" title="Rename">
            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"/>
            </svg>
          </button>
          <button class="dashboard-action-btn" data-action="duplicate" title="Duplicate">
            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
            </svg>
          </button>
          <button class="dashboard-action-btn dashboard-action-delete" data-action="delete" title="Delete">
            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
            </svg>
          </button>
        </div>
      </div>
    `).join('')

    this._bindDashboardEvents()
  }

  _bindDashboardEvents() {
    const items = this.element.querySelectorAll(".dashboard-item")
    items.forEach(item => {
      item.addEventListener("click", (e) => {
        if (e.target.closest(".dashboard-actions")) return
        const id = item.dataset.dashboardId
        this.layoutManager.emit("navigation:action", {
          action: "switch-dashboard",
          dashboardId: id
        })
      })

      item.querySelector('[data-action="rename"]')?.addEventListener("click", (e) => {
        e.stopPropagation()
        const id = item.dataset.dashboardId
        const name = item.querySelector(".dashboard-name")?.textContent
        this.layoutManager.emit("navigation:action", {
          action: "rename-dashboard",
          dashboardId: id,
          currentName: name
        })
      })

      item.querySelector('[data-action="duplicate"]')?.addEventListener("click", (e) => {
        e.stopPropagation()
        const id = item.dataset.dashboardId
        this.layoutManager.emit("navigation:action", {
          action: "duplicate-dashboard",
          dashboardId: id
        })
      })

      item.querySelector('[data-action="delete"]')?.addEventListener("click", (e) => {
        e.stopPropagation()
        const id = item.dataset.dashboardId
        const name = item.querySelector(".dashboard-name")?.textContent
        this.layoutManager.emit("navigation:action", {
          action: "delete-dashboard",
          dashboardId: id,
          dashboardName: name
        })
      })
    })
  }

  _updateActiveIndicator() {
    const items = this.element.querySelectorAll(".dashboard-item")
    items.forEach(item => {
      const isActive = item.dataset.dashboardId === this.currentDashboardId
      item.classList.toggle("active", isActive)
    })
  }

  _escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }

  setMissionName(name) {
    const el = this.element.querySelector("#nav-mission-name")
    if (el) el.textContent = name
  }

  setConnectionStatus(connected) {
    const statusEl = this.element.querySelector("#nav-connection-status")
    const dotEl = statusEl?.querySelector(".status-dot")
    const labelEl = statusEl?.querySelector(".nav-label")

    if (dotEl) {
      dotEl.classList.toggle("connected", connected)
      dotEl.classList.toggle("disconnected", !connected)
    }
    if (labelEl) {
      labelEl.textContent = connected ? "Connected" : "Disconnected"
    }
  }

  destroy() {
    this.resizeObserver?.disconnect()
    this.element?.remove()
  }
}

/**
 * Dashboard Panel V2 - Center workspace (same as V1 for now)
 */
class DashboardPanelV2 {
  constructor(container, state, layoutManager) {
    this.container = container
    this.state = state
    this.layoutManager = layoutManager
    this.element = null
    this.gridElement = null
    this.locked = false
    this.selectionMode = false
    this.selectedCount = 0

    this._render()
    this._bindEvents()
  }

  _render() {
    this.element = document.createElement("div")
    this.element.className = "dashboard-panel v2 h-full flex flex-col bg-base-100 overflow-hidden"
    this.element.innerHTML = `
      <div class="dashboard-toolbar p-2 border-b border-base-300 flex items-center justify-between">
        <div class="flex items-center gap-2">
          <span class="text-sm font-semibold">Dashboard</span>
          <span class="badge badge-sm badge-primary" id="dashboard-widget-count">0 widgets</span>
        </div>
        <div class="flex items-center gap-2" id="toolbar-actions">
          <div class="selection-toolbar hidden" id="selection-toolbar">
            <span class="selection-count" id="selection-count">0 selected</span>
            <button class="btn btn-xs" id="select-all-btn" title="Select All">All</button>
            <button class="btn btn-xs btn-error" id="delete-selected-btn" title="Delete Selected">
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
              </svg>
            </button>
            <button class="btn btn-xs" id="cancel-selection-btn" title="Cancel Selection">
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
              </svg>
            </button>
          </div>
          <div id="normal-toolbar">
            <button class="btn btn-ghost btn-xs" id="dashboard-select-toggle" title="Select multiple widgets">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4"/>
              </svg>
            </button>
            <button class="btn btn-ghost btn-xs" id="dashboard-lock-toggle" title="Lock/Unlock editing">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 11V7a4 4 0 118 0m-4 8v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2z"/>
              </svg>
            </button>
          </div>
        </div>
      </div>

      <div class="dashboard-grid flex-1 overflow-auto p-2" id="dashboard-grid-container">
        <div class="grid-stack"></div>
      </div>
    `

    this.container.element.appendChild(this.element)
    this.gridElement = this.element.querySelector(".grid-stack")
  }

  _bindEvents() {
    const lockBtn = this.element.querySelector("#dashboard-lock-toggle")
    lockBtn?.addEventListener("click", () => {
      this.layoutManager.emit("dashboard:toggleLock", {})
    })

    const selectToggleBtn = this.element.querySelector("#dashboard-select-toggle")
    selectToggleBtn?.addEventListener("click", () => {
      this.layoutManager.emit("dashboard:toggleSelectionMode", {})
    })

    const selectAllBtn = this.element.querySelector("#select-all-btn")
    selectAllBtn?.addEventListener("click", () => {
      this.layoutManager.emit("dashboard:selectAll", {})
    })

    const deleteSelectedBtn = this.element.querySelector("#delete-selected-btn")
    deleteSelectedBtn?.addEventListener("click", () => {
      this.layoutManager.emit("dashboard:deleteSelected", {})
    })

    const cancelSelectionBtn = this.element.querySelector("#cancel-selection-btn")
    cancelSelectionBtn?.addEventListener("click", () => {
      this.layoutManager.emit("dashboard:cancelSelection", {})
    })
  }

  getGridContainer() {
    return this.gridElement
  }

  setWidgetCount(count) {
    const el = this.element.querySelector("#dashboard-widget-count")
    if (el) el.textContent = `${count} widget${count !== 1 ? 's' : ''}`
  }

  setLocked(locked) {
    this.locked = locked
    const lockBtn = this.element.querySelector("#dashboard-lock-toggle")
    if (lockBtn) {
      const iconSvg = locked
        ? `<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/>`
        : `<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 11V7a4 4 0 118 0m-4 8v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2z"/>`

      lockBtn.innerHTML = `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">${iconSvg}</svg>`
      lockBtn.title = locked ? "Unlock editing" : "Lock editing"
      lockBtn.classList.toggle("btn-active", locked)
    }

    const gridContainer = this.element.querySelector("#dashboard-grid-container")
    gridContainer?.classList.toggle("grid-locked", locked)
  }

  setSelectionMode(enabled) {
    this.selectionMode = enabled

    const selectionToolbar = this.element.querySelector("#selection-toolbar")
    const normalToolbar = this.element.querySelector("#normal-toolbar")
    const selectToggleBtn = this.element.querySelector("#dashboard-select-toggle")

    if (enabled) {
      selectionToolbar?.classList.remove("hidden")
      normalToolbar?.classList.add("hidden")
      selectToggleBtn?.classList.add("btn-active")
    } else {
      selectionToolbar?.classList.add("hidden")
      normalToolbar?.classList.remove("hidden")
      selectToggleBtn?.classList.remove("btn-active")
      this.selectedCount = 0
      this._updateSelectionCount()
    }
  }

  setSelectionCount(count) {
    this.selectedCount = count
    this._updateSelectionCount()
  }

  _updateSelectionCount() {
    const countEl = this.element.querySelector("#selection-count")
    if (countEl) {
      countEl.textContent = `${this.selectedCount} selected`
    }

    const deleteBtn = this.element.querySelector("#delete-selected-btn")
    if (deleteBtn) {
      deleteBtn.disabled = this.selectedCount === 0
      deleteBtn.classList.toggle("btn-disabled", this.selectedCount === 0)
    }
  }

  destroy() {
    this.element?.remove()
  }
}

/**
 * Context Panel V2 - Right sidebar with enhanced alarm display
 */
class ContextPanelV2 {
  constructor(container, state, layoutManager) {
    this.container = container
    this.state = state
    this.layoutManager = layoutManager
    this.element = null
    this.collapsed = false
    this.resizeObserver = null
    this.alarms = []
    this.liveViewHook = null

    this._render()
    this._setupResizeObserver()
  }

  _render() {
    this.element = document.createElement("div")
    this.element.className = "context-panel v2 h-full flex flex-col bg-base-200 overflow-hidden"
    this.element.innerHTML = `
      <!-- Expanded view -->
      <div class="context-expanded flex-1 flex flex-col overflow-hidden">
        <div class="flex-1 overflow-y-auto">
          <!-- Fleet Health Section - Enhanced -->
          <div class="context-section border-b border-base-300">
            <div class="context-section-header">
              <span class="context-section-title">Fleet Health</span>
            </div>
            <div class="context-section-content">
              <div id="fleet-health-v2" class="fleet-health-grid">
                <!-- Fleet health bars will be rendered here -->
                <div class="text-xs text-base-content/50 p-2">Loading fleet data...</div>
              </div>
            </div>
          </div>

          <!-- Active Alarms Section - Enhanced -->
          <div class="context-section border-b border-base-300 flex-1">
            <div class="context-section-header">
              <span class="context-section-title">Active Alarms</span>
              <span class="badge badge-xs badge-error" id="alarm-count">0</span>
            </div>
            <div class="context-section-content alarms-list" id="active-alarms">
              <p class="text-xs text-base-content/50 p-2">No active alarms</p>
            </div>
          </div>

          <!-- Running Procedures Section -->
          <div class="context-section border-b border-base-300">
            <div class="context-section-header">
              <span class="context-section-title">Procedures</span>
              <span class="badge badge-xs badge-info" id="procedure-count">0</span>
            </div>
            <div class="context-section-content" id="running-procedures">
              <p class="text-xs text-base-content/50 p-2">No running procedures</p>
            </div>
          </div>

          <!-- Command History Section -->
          <div class="context-section">
            <div class="context-section-header">
              <span class="context-section-title">Recent Commands</span>
            </div>
            <div class="context-section-content" id="command-history">
              <p class="text-xs text-base-content/50 p-2">No recent commands</p>
            </div>
          </div>
        </div>
      </div>

      <!-- Collapsed view - badges only -->
      <div class="context-collapsed flex-col items-center py-2 gap-3">
        <div class="context-badge-item" title="Fleet Health">
          <svg class="w-4 h-4 text-base-content/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"/>
          </svg>
          <span class="badge badge-xs badge-success" id="fleet-health-badge">OK</span>
        </div>
        <div class="context-badge-item" title="Active Alarms">
          <svg class="w-4 h-4 text-base-content/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
          </svg>
          <span class="badge badge-xs badge-error" id="alarm-badge">0</span>
        </div>
        <div class="context-badge-item" title="Procedures">
          <svg class="w-4 h-4 text-base-content/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
          </svg>
          <span class="badge badge-xs badge-info" id="procedure-badge">0</span>
        </div>
      </div>
    `

    this.container.element.appendChild(this.element)
  }

  _setupResizeObserver() {
    this.resizeObserver = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const width = entry.contentRect.width
        const shouldCollapse = width < CONTEXT_COLLAPSE_THRESHOLD

        if (shouldCollapse !== this.collapsed) {
          this.collapsed = shouldCollapse
          this.element.classList.toggle("collapsed", shouldCollapse)
        }
      }
    })

    this.resizeObserver.observe(this.element)
  }

  setAlarmCount(count) {
    const expandedEl = this.element.querySelector("#alarm-count")
    const collapsedEl = this.element.querySelector("#alarm-badge")

    ;[expandedEl, collapsedEl].forEach(el => {
      if (el) {
        el.textContent = count
        el.classList.toggle("badge-error", count > 0)
        el.classList.toggle("badge-neutral", count === 0)
      }
    })
  }

  setProcedureCount(count) {
    const expandedEl = this.element.querySelector("#procedure-count")
    const collapsedEl = this.element.querySelector("#procedure-badge")

    ;[expandedEl, collapsedEl].forEach(el => {
      if (el) el.textContent = count
    })
  }

  setAlarms(alarms, liveViewHook) {
    this.alarms = alarms || []
    this.liveViewHook = liveViewHook
    this._renderAlarms()
    this.setAlarmCount(this.alarms.length)
  }

  _renderAlarms() {
    const container = this.element.querySelector("#active-alarms")
    if (!container) return

    if (this.alarms.length === 0) {
      container.innerHTML = `<p class="text-xs text-base-content/50 p-2">No active alarms</p>`
      return
    }

    // Group by severity
    const critical = this.alarms.filter(a => a.severity === 'critical')
    const warning = this.alarms.filter(a => a.severity === 'warning')
    const info = this.alarms.filter(a => a.severity !== 'critical' && a.severity !== 'warning')

    let html = ''

    if (critical.length > 0) {
      html += `<div class="alarm-group severity-critical">
        <div class="alarm-group-header">Critical (${critical.length})</div>
        ${critical.map(a => this._renderAlarmItem(a)).join('')}
      </div>`
    }

    if (warning.length > 0) {
      html += `<div class="alarm-group severity-warning">
        <div class="alarm-group-header">Warning (${warning.length})</div>
        ${warning.map(a => this._renderAlarmItem(a)).join('')}
      </div>`
    }

    if (info.length > 0) {
      html += `<div class="alarm-group severity-info">
        <div class="alarm-group-header">Info (${info.length})</div>
        ${info.map(a => this._renderAlarmItem(a)).join('')}
      </div>`
    }

    container.innerHTML = html
    this._bindAlarmEvents()
  }

  _renderAlarmItem(alarm) {
    const timeAgo = this._formatTimeAgo(alarm.triggered_at)
    const statusClass = alarm.status === 'acknowledged' ? 'acknowledged' : (alarm.shelved_at ? 'shelved' : 'active')

    return `
      <div class="alarm-item-v2 ${statusClass}" data-alarm-id="${alarm.id}">
        <div class="alarm-item-header">
          <span class="alarm-source">${this._escapeHtml(alarm.source_id)}</span>
          <span class="alarm-time">${timeAgo}</span>
        </div>
        <div class="alarm-message">${this._escapeHtml(alarm.message || 'No message')}</div>
        <div class="alarm-actions">
          ${alarm.status === 'active' ? `<button class="alarm-btn" data-action="acknowledge">Ack</button>` : ''}
          ${alarm.shelved_at ? `<button class="alarm-btn" data-action="unshelve">Unshelve</button>` : `<button class="alarm-btn" data-action="shelve">Shelve</button>`}
          <button class="alarm-btn alarm-btn-clear" data-action="clear">Clear</button>
        </div>
      </div>
    `
  }

  _bindAlarmEvents() {
    const container = this.element.querySelector("#active-alarms")
    if (!container || !this.liveViewHook) return

    container.querySelectorAll('.alarm-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation()
        const alarmItem = btn.closest('.alarm-item-v2')
        const alarmId = alarmItem?.dataset.alarmId
        const action = btn.dataset.action

        if (!alarmId) return

        switch (action) {
          case 'acknowledge':
            this.liveViewHook.pushEvent('acknowledge_alarm', { id: alarmId })
            break
          case 'shelve':
            this.liveViewHook.pushEvent('open_shelve_modal', { id: alarmId })
            break
          case 'unshelve':
            this.liveViewHook.pushEvent('unshelve_alarm', { id: alarmId })
            break
          case 'clear':
            this.liveViewHook.pushEvent('clear_alarm', { id: alarmId })
            break
        }
      })
    })
  }

  _formatTimeAgo(isoString) {
    if (!isoString) return ''
    const date = new Date(isoString)
    const now = new Date()
    const seconds = Math.floor((now - date) / 1000)

    if (seconds < 60) return `${seconds}s`
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m`
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h`
    return `${Math.floor(seconds / 86400)}d`
  }

  _escapeHtml(str) {
    if (!str) return ''
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }

  destroy() {
    this.resizeObserver?.disconnect()
    this.element?.remove()
  }
}

/**
 * Quick Access Bar - Bottom panel (NEW)
 *
 * Provides quick access to:
 * - Vehicle/target selector
 * - Quick command buttons
 * - Timeline scrubber (future)
 */
class QuickAccessBar {
  constructor(container, state, layoutManager) {
    this.container = container
    this.state = state
    this.layoutManager = layoutManager
    this.element = null
    this.collapsed = false
    this.targets = []
    this.selectedTargetId = null

    this._render()
    this._bindEvents()
  }

  _render() {
    this.element = document.createElement("div")
    this.element.className = "quick-access-bar h-full flex items-center bg-base-200 border-t border-base-300 px-4 gap-4"
    this.element.innerHTML = `
      <!-- Target Selector -->
      <div class="qa-section target-selector">
        <label class="mc-label-subsystem text-base-content/40 mr-2">TARGET</label>
        <select id="qa-target-select" class="select select-xs select-bordered bg-base-300 min-w-[150px]">
          <option value="">All Targets</option>
        </select>
      </div>

      <!-- Quick Command Buttons -->
      <div class="qa-section quick-commands flex items-center gap-2">
        <label class="mc-label-subsystem text-base-content/40 mr-2">QUICK CMD</label>
        <button class="btn btn-xs btn-outline" data-command="ping" title="Send Ping">
          <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.111 16.404a5.5 5.5 0 017.778 0M12 20h.01m-7.08-7.071c3.904-3.905 10.236-3.905 14.141 0M1.394 9.393c5.857-5.857 15.355-5.857 21.213 0"/>
          </svg>
          Ping
        </button>
        <button class="btn btn-xs btn-outline" data-command="status" title="Request Status">
          <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"/>
          </svg>
          Status
        </button>
        <button class="btn btn-xs btn-outline btn-warning" data-command="safe_mode" title="Safe Mode">
          <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
          </svg>
          Safe Mode
        </button>
      </div>

      <!-- Spacer -->
      <div class="flex-1"></div>

      <!-- Timeline placeholder -->
      <div class="qa-section timeline-hint">
        <span class="text-xs text-base-content/30 italic">Timeline coming soon...</span>
      </div>

      <!-- Toggle collapse -->
      <button class="btn btn-ghost btn-xs" id="qa-toggle-collapse" title="Toggle Quick Access Bar">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/>
        </svg>
      </button>
    `

    this.container.element.appendChild(this.element)
  }

  _bindEvents() {
    // Target selector
    const targetSelect = this.element.querySelector("#qa-target-select")
    targetSelect?.addEventListener("change", (e) => {
      this.selectedTargetId = e.target.value || null
      this.layoutManager.emit("quickAccess:targetSelected", { targetId: this.selectedTargetId })
    })

    // Quick command buttons
    this.element.querySelectorAll("[data-command]").forEach(btn => {
      btn.addEventListener("click", (e) => {
        const command = e.currentTarget.dataset.command
        this.layoutManager.emit("quickAccess:command", {
          command,
          targetId: this.selectedTargetId
        })
      })
    })

    // Collapse toggle
    const toggleBtn = this.element.querySelector("#qa-toggle-collapse")
    toggleBtn?.addEventListener("click", () => {
      this.collapsed = !this.collapsed
      this.element.classList.toggle("collapsed", this.collapsed)
      toggleBtn.querySelector("svg")?.classList.toggle("rotate-180", this.collapsed)
    })
  }

  setTargets(targets) {
    this.targets = targets || []
    const select = this.element.querySelector("#qa-target-select")
    if (!select) return

    const currentValue = select.value
    select.innerHTML = `<option value="">All Targets</option>` +
      this.targets.map(t => `<option value="${t.id}">${this._escapeHtml(t.name || t.identifier)}</option>`).join('')

    // Restore selection if still valid
    if (currentValue && this.targets.find(t => t.id === currentValue)) {
      select.value = currentValue
    }
  }

  _escapeHtml(str) {
    if (!str) return ''
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }

  destroy() {
    this.element?.remove()
  }
}

/**
 * Register all V2 panel components.
 */
export function registerPanelsV2() {
  registerPanel("navigation", (container, state, manager) => {
    return new NavigationPanelV2(container, state, manager)
  })

  registerPanel("dashboard", (container, state, manager) => {
    return new DashboardPanelV2(container, state, manager)
  })

  registerPanel("context", (container, state, manager) => {
    return new ContextPanelV2(container, state, manager)
  })

  registerPanel("quickAccess", (container, state, manager) => {
    return new QuickAccessBar(container, state, manager)
  })
}

export {
  NavigationPanelV2,
  DashboardPanelV2,
  ContextPanelV2,
  QuickAccessBar
}

export default {
  registerPanelsV2
}
