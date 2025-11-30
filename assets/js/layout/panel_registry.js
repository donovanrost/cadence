/**
 * Panel Registry
 *
 * Defines the panel components used in the Ops Console layout.
 * Each panel is a factory function that receives a Golden Layout container.
 */

import { registerPanel, PANEL_SNAP_POINTS } from "./golden_layout_manager"

// Threshold width for collapsing panels
// Use the midpoint between compact and full as the collapse threshold
const NAV_COLLAPSE_THRESHOLD = (PANEL_SNAP_POINTS.navigation.compact + PANEL_SNAP_POINTS.navigation.full) / 2
const CONTEXT_COLLAPSE_THRESHOLD = (PANEL_SNAP_POINTS.context.compact + PANEL_SNAP_POINTS.context.full) / 2

/**
 * Navigation Panel - Left sidebar
 *
 * Contains:
 * - Mission selector
 * - Quick actions
 * - Dashboards (collapsible section with full CRUD)
 *
 * Collapses to icon-only mode when narrow.
 */
class NavigationPanel {
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

    this._render()
    this._bindEvents()
    this._setupResizeObserver()
  }

  _render() {
    this.element = document.createElement("div")
    this.element.className = "navigation-panel h-full flex flex-col bg-base-200 overflow-hidden"
    this.element.innerHTML = `
      <div class="nav-header border-b border-base-300">
        <h2 class="nav-title text-lg font-bold text-primary">Mission</h2>
        <p class="nav-subtitle text-sm text-base-content/70" id="nav-mission-name">Loading...</p>
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

    // Dashboards section toggle
    const toggle = this.element.querySelector("#dashboards-toggle")
    toggle?.addEventListener("click", () => {
      this.dashboardSectionExpanded = !this.dashboardSectionExpanded
      this._updateDashboardSectionState()
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

  /**
   * Set the list of dashboards and current selection.
   * @param {Array} dashboards - Array of {id, name, is_default}
   * @param {string} currentId - Currently active dashboard ID
   */
  setDashboards(dashboards, currentId) {
    this.dashboards = dashboards || []
    this.currentDashboardId = currentId
    this._renderDashboardList()
  }

  /**
   * Update the currently active dashboard.
   * @param {string} id - Dashboard ID
   */
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
      // Click to switch dashboard
      item.addEventListener("click", (e) => {
        // Don't switch if clicking action buttons
        if (e.target.closest(".dashboard-actions")) return

        const id = item.dataset.dashboardId
        this.layoutManager.emit("navigation:action", {
          action: "switch-dashboard",
          dashboardId: id
        })
      })

      // Action buttons
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
 * Dashboard Panel - Center workspace
 *
 * Contains the gridstack widget dashboard.
 */
class DashboardPanel {
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
    this.element.className = "dashboard-panel h-full flex flex-col bg-base-100 overflow-hidden"
    this.element.innerHTML = `
      <div class="dashboard-toolbar p-2 border-b border-base-300 flex items-center justify-between">
        <div class="flex items-center gap-2">
          <span class="text-sm font-semibold">Dashboard</span>
          <span class="badge badge-sm badge-primary" id="dashboard-widget-count">0 widgets</span>
        </div>
        <div class="flex items-center gap-2" id="toolbar-actions">
          <!-- Selection toolbar (hidden by default) -->
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
          <!-- Normal toolbar buttons -->
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
      // Update icon - locked uses a filled lock, unlocked uses open lock
      const iconSvg = locked
        ? `<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/>`
        : `<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 11V7a4 4 0 118 0m-4 8v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2z"/>`

      lockBtn.innerHTML = `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">${iconSvg}</svg>`
      lockBtn.title = locked ? "Unlock editing" : "Lock editing"
      lockBtn.classList.toggle("btn-active", locked)
    }

    // Add/remove locked class to grid container
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

    // Disable delete button if nothing selected
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
 * Context Panel - Right sidebar
 *
 * Contains:
 * - Fleet health honeycomb
 * - Command queue
 * - Active alarms
 * - Procedure status
 *
 * Collapses to badges-only mode when narrow.
 */
class ContextPanel {
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
    this.element.className = "context-panel h-full flex flex-col bg-base-200 overflow-hidden"
    this.element.innerHTML = `
      <!-- Expanded view -->
      <div class="context-expanded flex-1 flex flex-col overflow-hidden">
        <div class="flex-1 overflow-y-auto">
          <!-- Fleet Health Section -->
          <div class="context-section border-b border-base-300">
            <div class="context-section-header">
              <span class="context-section-title">Fleet Health</span>
            </div>
            <div class="context-section-content">
              <div id="fleet-honeycomb" class="min-h-[100px] flex items-center justify-center">
                <span class="text-base-content/50 text-xs">Loading...</span>
              </div>
            </div>
          </div>

          <!-- Command Queue Section -->
          <div class="context-section border-b border-base-300">
            <div class="context-section-header">
              <span class="context-section-title">Commands</span>
              <span class="badge badge-xs badge-neutral" id="command-queue-count">0</span>
            </div>
            <div class="context-section-content">
              <div id="command-queue">
                <p class="text-xs text-base-content/50">No pending</p>
              </div>
            </div>
          </div>

          <!-- Active Alarms Section -->
          <div class="context-section border-b border-base-300">
            <div class="context-section-header">
              <span class="context-section-title">Alarms</span>
              <span class="badge badge-xs badge-error" id="alarm-count">0</span>
            </div>
            <div class="context-section-content">
              <div id="active-alarms">
                <p class="text-xs text-base-content/50">No alarms</p>
              </div>
            </div>
          </div>

          <!-- Procedure Status Section -->
          <div class="context-section border-b border-base-300">
            <div class="context-section-header">
              <span class="context-section-title">Procedures</span>
              <span class="badge badge-xs badge-info" id="procedure-count">0</span>
            </div>
            <div class="context-section-content">
              <div id="procedure-status">
                <p class="text-xs text-base-content/50">None active</p>
              </div>
            </div>
          </div>
        </div>

        <!-- Quick Stats Footer -->
        <div class="context-footer border-t border-base-300 bg-base-300/50">
          <div class="context-stats">
            <div class="context-stat">
              <span class="context-stat-label">UL</span>
              <span class="context-stat-value" id="uplink-rate">--</span>
            </div>
            <div class="context-stat">
              <span class="context-stat-label">DL</span>
              <span class="context-stat-value" id="downlink-rate">--</span>
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
        <div class="context-badge-item" title="Command Queue">
          <svg class="w-4 h-4 text-base-content/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
          </svg>
          <span class="badge badge-xs badge-neutral" id="command-queue-badge">0</span>
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

  getHoneycombContainer() {
    return this.element.querySelector("#fleet-honeycomb")
  }

  getCommandQueueContainer() {
    return this.element.querySelector("#command-queue")
  }

  getAlarmsContainer() {
    return this.element.querySelector("#active-alarms")
  }

  setAlarmCount(count) {
    // Update both expanded and collapsed views
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

  setCommandQueueCount(count) {
    const expandedEl = this.element.querySelector("#command-queue-count")
    const collapsedEl = this.element.querySelector("#command-queue-badge")

    ;[expandedEl, collapsedEl].forEach(el => {
      if (el) el.textContent = count
    })
  }

  setProcedureCount(count) {
    const expandedEl = this.element.querySelector("#procedure-count")
    const collapsedEl = this.element.querySelector("#procedure-badge")

    ;[expandedEl, collapsedEl].forEach(el => {
      if (el) el.textContent = count
    })
  }

  /**
   * Set the list of active alarms and render them.
   * @param {Array} alarms - Array of alarm objects
   * @param {Object} liveViewHook - Reference to LiveView hook for pushing events
   */
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
      container.innerHTML = `<p class="text-xs text-base-content/50">No alarms</p>`
      return
    }

    container.innerHTML = this.alarms.map(alarm => {
      const severityClass = this._getSeverityClass(alarm.severity)
      const statusIcon = this._getStatusIcon(alarm.status)
      const timeAgo = this._formatTimeAgo(alarm.triggered_at)

      return `
        <div class="alarm-item ${severityClass}" data-alarm-id="${alarm.id}">
          <div class="alarm-header">
            ${statusIcon}
            <span class="alarm-severity ${severityClass}">${alarm.severity}</span>
            <span class="alarm-time">${timeAgo}</span>
          </div>
          <div class="alarm-message">${this._escapeHtml(alarm.message || alarm.source_id)}</div>
          <div class="alarm-source">${this._escapeHtml(alarm.source_id)}</div>
          <div class="alarm-actions">
            ${this._renderAlarmActions(alarm)}
          </div>
        </div>
      `
    }).join('')

    this._bindAlarmEvents()
  }

  _getSeverityClass(severity) {
    switch (severity) {
      case 'critical': return 'severity-critical'
      case 'warning': return 'severity-warning'
      case 'info': return 'severity-info'
      default: return ''
    }
  }

  _getStatusIcon(status) {
    switch (status) {
      case 'active':
        return `<svg class="alarm-status-icon status-active" fill="currentColor" viewBox="0 0 24 24">
          <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
        </svg>`
      case 'acknowledged':
        return `<svg class="alarm-status-icon status-acknowledged" fill="currentColor" viewBox="0 0 24 24">
          <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/>
        </svg>`
      case 'shelved':
        return `<svg class="alarm-status-icon status-shelved" fill="currentColor" viewBox="0 0 24 24">
          <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.42 0-8-3.58-8-8s3.58-8 8-8 8 3.58 8 8-3.58 8-8 8zm.5-13H11v6l5.25 3.15.75-1.23-4.5-2.67z"/>
        </svg>`
      default:
        return ''
    }
  }

  _renderAlarmActions(alarm) {
    const actions = []

    if (alarm.status === 'active') {
      actions.push(`<button class="alarm-action-btn" data-action="acknowledge" title="Acknowledge">Ack</button>`)
    }

    if (alarm.status === 'shelved') {
      actions.push(`<button class="alarm-action-btn" data-action="unshelve" title="Unshelve">Unshelve</button>`)
    } else {
      actions.push(`<button class="alarm-action-btn" data-action="shelve" title="Shelve">Shelve</button>`)
    }

    actions.push(`<button class="alarm-action-btn alarm-action-clear" data-action="clear" title="Clear">Clear</button>`)

    return actions.join('')
  }

  _bindAlarmEvents() {
    const container = this.element.querySelector("#active-alarms")
    if (!container || !this.liveViewHook) return

    container.querySelectorAll('.alarm-action-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation()
        const alarmItem = btn.closest('.alarm-item')
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

    if (seconds < 60) return `${seconds}s ago`
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`
    return `${Math.floor(seconds / 86400)}d ago`
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
 * Register all panel components.
 */
export function registerPanels() {
  registerPanel("navigation", (container, state, manager) => {
    return new NavigationPanel(container, state, manager)
  })

  registerPanel("dashboard", (container, state, manager) => {
    return new DashboardPanel(container, state, manager)
  })

  registerPanel("context", (container, state, manager) => {
    return new ContextPanel(container, state, manager)
  })
}

export {
  NavigationPanel,
  DashboardPanel,
  ContextPanel
}

export default {
  registerPanels
}
