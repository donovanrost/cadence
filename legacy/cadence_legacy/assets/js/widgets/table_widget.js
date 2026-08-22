/**
 * Table Widget
 *
 * A data table widget using TanStack Table for sorting, filtering,
 * and column resizing with TanStack Virtual for efficient rendering
 * of large datasets.
 */

import { BaseWidget, registerWidget } from "../dashboard/widget_factory"
import {
  createTable,
  getCoreRowModel,
  getSortedRowModel,
  getFilteredRowModel
} from "@tanstack/table-core"
import { Virtualizer } from "@tanstack/virtual-core"
import { getStore } from "../telemetry_store"
import { getLimitsColor, TokyoNightColors } from "../scichart/tokyo_night_theme"

/**
 * TableWidget - Data table for packet telemetry with sorting and filtering.
 */
export class TableWidget extends BaseWidget {
  static displayName = "Data Table"
  static description = "Tabular view of packet telemetry with sorting and filtering"
  static icon = "table-cells"

  constructor(options) {
    super(options)
    this.type = "table"
    this.table = null
    this.virtualizer = null
    this.data = []
    this._tableState = {
      sorting: [],
      globalFilter: "",
      columnSizing: {},
      columnSizingInfo: {
        startOffset: null,
        startSize: null,
        deltaOffset: null,
        deltaPercentage: null,
        isResizingColumn: false,
        columnSizingStart: []
      },
      columnPinning: {
        left: [],
        right: []
      },
      columnVisibility: {},
      columnOrder: [],
      rowSelection: {},
      expanded: {}
    }
    this._resizing = null
    this._rafId = null
    this._pendingUpdate = false
  }

  async init() {
    this.render()
    this._initTable()
    this._subscribeToTelemetry()
    this.initialized = true
  }

  renderContent() {
    return `
      <div class="table-widget h-full flex flex-col">
        <div class="table-toolbar flex items-center gap-2 p-2 border-b border-base-300">
          <input type="text"
                 class="input input-xs input-bordered flex-1"
                 placeholder="Filter items..."
                 id="table-filter-${this.id}" />
          <span class="text-xs text-base-content/50" id="table-count-${this.id}">0 items</span>
        </div>
        <div class="table-scroll-container flex-1 overflow-auto relative" id="table-container-${this.id}">
          <table class="table table-xs w-full">
            <thead class="sticky top-0 z-10" id="table-header-${this.id}"></thead>
            <tbody id="table-body-${this.id}"></tbody>
          </table>
        </div>
      </div>
    `
  }

  _initTable() {
    // Restore column sizing from config if available
    this._tableState.columnSizing = this.config.columnSizing || {
      item: 150,
      value: 100,
      units: 60,
      timestamp: 80
    }

    // Define columns
    const columns = [
      {
        id: "item",
        header: "Item",
        accessorKey: "item",
        size: this._tableState.columnSizing.item || 150
      },
      {
        id: "value",
        header: "Value",
        accessorKey: "value",
        size: this._tableState.columnSizing.value || 100
      },
      {
        id: "units",
        header: "Units",
        accessorKey: "units",
        size: this._tableState.columnSizing.units || 60
      },
      {
        id: "timestamp",
        header: "Time",
        accessorKey: "timestamp",
        size: this._tableState.columnSizing.timestamp || 80
      }
    ]

    // Store reference for data getter
    const self = this

    // Create TanStack Table instance with proper vanilla JS setup
    this.table = createTable({
      // Use getter function so table always sees current data
      get data() {
        return self.data
      },
      columns,
      state: this._tableState,
      onStateChange: (updater) => {
        // Handle state updates from TanStack Table
        if (typeof updater === "function") {
          this._tableState = updater(this._tableState)
        } else {
          this._tableState = updater
        }
        this._scheduleRender()
      },
      getCoreRowModel: getCoreRowModel(),
      getSortedRowModel: getSortedRowModel(),
      getFilteredRowModel: getFilteredRowModel(),
      enableColumnResizing: true,
      columnResizeMode: "onChange",
      globalFilterFn: (row, columnId, filterValue) => {
        const value = row.getValue(columnId)
        if (value == null) return false
        return String(value).toLowerCase().includes(filterValue.toLowerCase())
      },
      // Provide the rerender function
      renderFallbackValue: "--"
    })

    // Set up virtual scrolling
    const container = this.container.querySelector(`#table-container-${this.id}`)
    if (container) {
      this.virtualizer = new Virtualizer({
        count: this.data.length,
        getScrollElement: () => container,
        estimateSize: () => 28,
        overscan: 10
      })
    }

    // Bind filter input
    const filterInput = this.container.querySelector(`#table-filter-${this.id}`)
    filterInput?.addEventListener("input", (e) => {
      this._tableState.globalFilter = e.target.value
      this.table.setOptions(prev => ({
        ...prev,
        state: this._tableState
      }))
      this._scheduleRender()
    })

    // Initial render
    this._renderHeader()
    this._renderTable()
  }

  _subscribeToTelemetry() {
    const store = getStore()
    const target = this.config.target
    const packet = this.config.packet

    if (!target || !packet) {
      console.warn("[TableWidget] No target or packet configured")
      return
    }

    // Get items from config (populated from telemetry catalog)
    const items = this.config.items || []

    for (const item of items) {
      const key = `${target}:${packet}:${item.name}`

      // Initialize row data
      this.data.push({
        item: item.name,
        value: "--",
        units: item.units || "",
        timestamp: "--",
        limitsState: "unknown",
        key
      })

      // Get current value if available
      const current = store.getCurrent(key)
      if (current) {
        const row = this.data.find(r => r.key === key)
        if (row) {
          row.value = this._formatValue(current.value)
          row.timestamp = this._formatTime(current.timestamp)
          row.limitsState = current.limitsState
        }
      }

      // Subscribe to updates
      const unsub = store.subscribe(key, (value, timestamp, limitsState) => {
        this._updateRow(key, value, timestamp, limitsState)
      })
      this.subscriptions.push(unsub)
    }

    // Update table with initial data
    this._updateTableData()
    this._scheduleRender()
  }

  _updateRow(key, value, timestamp, limitsState) {
    const row = this.data.find(r => r.key === key)
    if (row) {
      row.value = this._formatValue(value)
      row.timestamp = this._formatTime(timestamp)
      row.limitsState = limitsState
      this._scheduleRender()
    }
  }

  _updateTableData() {
    // Update table options with new data - pass data directly to force recalculation
    this.table.setOptions(prev => ({
      ...prev,
      data: [...this.data], // Create new array reference to invalidate cache
      state: this._tableState
    }))

    // Force row model recalculation by getting core row model
    this.table.getCoreRowModel()

    // Update virtualizer count
    if (this.virtualizer) {
      const rowCount = this.table.getFilteredRowModel().rows.length
      this.virtualizer.setOptions({
        count: rowCount
      })
    }
  }

  _scheduleRender() {
    if (this._pendingUpdate) return

    this._pendingUpdate = true
    this._rafId = requestAnimationFrame(() => {
      this._pendingUpdate = false
      this._updateTableData()
      this._renderTable()
    })
  }

  _renderHeader() {
    const thead = this.container.querySelector(`#table-header-${this.id}`)
    if (!thead) return

    const headerGroups = this.table.getHeaderGroups()
    let html = ""

    for (const headerGroup of headerGroups) {
      html += "<tr>"
      for (const header of headerGroup.headers) {
        const sortDir = header.column.getIsSorted()
        const width = this._tableState.columnSizing[header.id] || header.column.getSize()

        html += `
          <th class="relative select-none ${sortDir ? 'sorted' : ''}"
              style="width: ${width}px; min-width: ${width}px;"
              data-column-id="${header.id}">
            <div class="flex items-center justify-between">
              <span class="header-label">${header.column.columnDef.header}</span>
              <span class="sort-indicator text-xs">
                ${sortDir === "asc" ? "▲" : sortDir === "desc" ? "▼" : ""}
              </span>
            </div>
            <div class="resize-handle" data-column-id="${header.id}"></div>
          </th>
        `
      }
      html += "</tr>"
    }

    thead.innerHTML = html

    // Bind header click events for sorting
    thead.querySelectorAll("th").forEach(th => {
      th.addEventListener("click", (e) => {
        if (e.target.classList.contains("resize-handle")) return

        const columnId = th.dataset.columnId
        this._toggleSort(columnId)
      })
    })

    // Bind resize handle events
    thead.querySelectorAll(".resize-handle").forEach(handle => {
      handle.addEventListener("mousedown", (e) => {
        e.preventDefault()
        e.stopPropagation()
        this._startResize(e, handle.dataset.columnId)
      })
    })
  }

  _toggleSort(columnId) {
    const column = this.table.getColumn(columnId)
    if (!column) return

    const currentSort = column.getIsSorted()

    if (!currentSort) {
      // Add ascending sort
      this._tableState.sorting = [{ id: columnId, desc: false }]
    } else if (currentSort === "asc") {
      // Change to descending
      this._tableState.sorting = [{ id: columnId, desc: true }]
    } else {
      // Remove sort
      this._tableState.sorting = []
    }

    this.table.setOptions(prev => ({
      ...prev,
      state: this._tableState
    }))

    this._renderHeader()
    this._scheduleRender()
  }

  _startResize(e, columnId) {
    const startX = e.clientX
    const startWidth = this._tableState.columnSizing[columnId] || 100

    this._resizing = { columnId, startX, startWidth }

    const handle = e.target
    handle.classList.add("resizing")

    const onMouseMove = (e) => {
      const diff = e.clientX - startX
      const newWidth = Math.max(40, startWidth + diff)
      this._tableState.columnSizing[columnId] = newWidth

      // Update header cell width
      const th = this.container.querySelector(`th[data-column-id="${columnId}"]`)
      if (th) {
        th.style.width = `${newWidth}px`
        th.style.minWidth = `${newWidth}px`
      }

      // Update body cells
      this.container.querySelectorAll(`td[data-column-id="${columnId}"]`).forEach(td => {
        td.style.width = `${newWidth}px`
        td.style.minWidth = `${newWidth}px`
      })
    }

    const onMouseUp = () => {
      handle.classList.remove("resizing")
      this._resizing = null
      document.removeEventListener("mousemove", onMouseMove)
      document.removeEventListener("mouseup", onMouseUp)
    }

    document.addEventListener("mousemove", onMouseMove)
    document.addEventListener("mouseup", onMouseUp)
  }

  _renderTable() {
    const tbody = this.container.querySelector(`#table-body-${this.id}`)
    const countEl = this.container.querySelector(`#table-count-${this.id}`)
    if (!tbody) return

    const rows = this.table.getRowModel().rows
    const filteredCount = this.table.getFilteredRowModel().rows.length

    // Update count display
    if (countEl) {
      countEl.textContent = `${filteredCount} item${filteredCount !== 1 ? "s" : ""}`
    }

    // For small datasets, render all rows directly
    // For large datasets, use virtualization
    if (rows.length <= 100) {
      this._renderAllRows(tbody, rows)
    } else {
      this._renderVirtualRows(tbody, rows)
    }
  }

  _renderAllRows(tbody, rows) {
    let html = ""

    for (const row of rows) {
      const limitsState = row.original.limitsState || "unknown"
      html += `<tr data-limits="${limitsState}">`

      for (const cell of row.getVisibleCells()) {
        const width = this._tableState.columnSizing[cell.column.id] || cell.column.getSize()
        const isValueCell = cell.column.id === "value"

        html += `
          <td class="${isValueCell ? "value-cell font-mono" : ""}"
              data-column-id="${cell.column.id}"
              style="width: ${width}px; min-width: ${width}px;">
            ${cell.getValue() ?? "--"}
          </td>
        `
      }

      html += "</tr>"
    }

    tbody.innerHTML = html
  }

  _renderVirtualRows(tbody, rows) {
    const container = this.container.querySelector(`#table-container-${this.id}`)
    if (!container || !this.virtualizer) {
      return this._renderAllRows(tbody, rows)
    }

    // Update virtualizer
    this.virtualizer.setOptions({
      count: rows.length
    })

    const virtualRows = this.virtualizer.getVirtualItems()
    const totalHeight = this.virtualizer.getTotalSize()

    // Create spacer elements for virtual scrolling
    let html = ""

    // Top spacer
    const topPad = virtualRows.length > 0 ? virtualRows[0].start : 0
    if (topPad > 0) {
      html += `<tr class="virtual-spacer"><td colspan="4" style="height: ${topPad}px; padding: 0;"></td></tr>`
    }

    // Visible rows
    for (const virtualRow of virtualRows) {
      const row = rows[virtualRow.index]
      if (!row) continue

      const limitsState = row.original.limitsState || "unknown"
      html += `<tr data-limits="${limitsState}" style="height: ${virtualRow.size}px;">`

      for (const cell of row.getVisibleCells()) {
        const width = this._tableState.columnSizing[cell.column.id] || cell.column.getSize()
        const isValueCell = cell.column.id === "value"

        html += `
          <td class="${isValueCell ? "value-cell font-mono" : ""}"
              data-column-id="${cell.column.id}"
              style="width: ${width}px; min-width: ${width}px;">
            ${cell.getValue() ?? "--"}
          </td>
        `
      }

      html += "</tr>"
    }

    // Bottom spacer
    const bottomPad = virtualRows.length > 0
      ? totalHeight - virtualRows[virtualRows.length - 1].end
      : 0
    if (bottomPad > 0) {
      html += `<tr class="virtual-spacer"><td colspan="4" style="height: ${bottomPad}px; padding: 0;"></td></tr>`
    }

    tbody.innerHTML = html
  }

  _formatValue(value) {
    if (value === null || value === undefined) return "--"
    if (typeof value === "number") {
      return Number.isInteger(value) ? value.toString() : value.toFixed(3)
    }
    return String(value)
  }

  _formatTime(timestamp) {
    if (!timestamp) return "--"
    const date = new Date(timestamp)
    if (isNaN(date.getTime())) return "--"

    const h = date.getHours().toString().padStart(2, "0")
    const m = date.getMinutes().toString().padStart(2, "0")
    const s = date.getSeconds().toString().padStart(2, "0")
    return `${h}:${m}:${s}`
  }

  getConfig() {
    return {
      ...this.config,
      columnSizing: this._tableState.columnSizing
    }
  }

  updateConfig(config) {
    const oldConfig = this.config
    this.config = { ...this.config, ...config }

    // Check if target/packet changed
    const packetChanged = oldConfig.target !== this.config.target ||
                          oldConfig.packet !== this.config.packet

    if (packetChanged) {
      // Unsubscribe from old telemetry
      for (const unsub of this.subscriptions) {
        unsub()
      }
      this.subscriptions = []

      // Clear data and reinitialize
      this.data = []
      this._subscribeToTelemetry()
      this._renderHeader()
      this._scheduleRender()
    } else {
      // Just update title
      const titleEl = this.container.querySelector(".widget-title")
      if (titleEl) titleEl.textContent = this.config.title || "Data Table"
    }
  }

  openConfig() {
    const event = new CustomEvent("widget:configure", {
      detail: {
        widgetId: this.id,
        widgetType: this.type,
        config: this.getConfig()
      },
      bubbles: true
    })
    this.container.dispatchEvent(event)
  }

  destroy() {
    if (this._rafId) {
      cancelAnimationFrame(this._rafId)
    }
    this.virtualizer = null
    this.table = null
    this.data = []
    super.destroy()
  }
}

// Register the widget
registerWidget("table", TableWidget)

export default TableWidget
