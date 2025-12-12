/**
 * LiveView Hooks Index
 *
 * Exports all custom LiveView hooks for the Cadence application.
 */

import { OpsConsoleHook } from "./ops_console_hook"
import { OpsConsoleV2Hook } from "./ops_console_v2_hook"
import { DagEditorHook } from "./dag_editor"
import { DagViewerHook } from "./dag_viewer"
import { ExecutionChannelHook } from "./execution_channel_hook"

/**
 * AutoScroll hook for log containers
 * Automatically scrolls to bottom when new content is added
 * Respects a data-auto-scroll attribute to enable/disable
 */
const AutoScrollHook = {
  mounted() {
    this.scrollToBottom()
    this.observer = new MutationObserver(() => {
      if (this.el.dataset.autoScroll === "true") {
        this.scrollToBottom()
      }
    })
    this.observer.observe(this.el, { childList: true, subtree: true })
  },

  updated() {
    if (this.el.dataset.autoScroll === "true") {
      this.scrollToBottom()
    }
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect()
    }
  },

  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight
  }
}

/**
 * Sortable hook for drag-and-drop reordering
 * Uses native HTML5 drag and drop API
 * Handles reordering entirely on the frontend, updating the hidden JSON input
 */
const SortableHook = {
  mounted() {
    this.draggedEl = null

    // Set up drag events on the container
    this.el.addEventListener('dragstart', (e) => this.handleDragStart(e))
    this.el.addEventListener('dragend', (e) => this.handleDragEnd(e))
    this.el.addEventListener('dragover', (e) => this.handleDragOver(e))
    this.el.addEventListener('dragenter', (e) => this.handleDragEnter(e))
    this.el.addEventListener('dragleave', (e) => this.handleDragLeave(e))
    this.el.addEventListener('drop', (e) => this.handleDrop(e))
  },

  handleDragStart(e) {
    const item = e.target.closest('[data-sortable-id]')
    if (!item) return

    this.draggedEl = item

    // Set drag data
    e.dataTransfer.effectAllowed = 'move'
    e.dataTransfer.setData('text/plain', item.dataset.sortableId)

    // Add dragging style after a short delay (so drag image captures original style)
    setTimeout(() => {
      item.classList.add('opacity-50', 'border-dashed')
    }, 0)
  },

  handleDragEnd(e) {
    if (this.draggedEl) {
      this.draggedEl.classList.remove('opacity-50', 'border-dashed')
    }

    // Remove all drop indicators
    this.el.querySelectorAll('[data-sortable-id]').forEach(el => {
      el.classList.remove('border-t-primary', 'border-t-2', 'border-b-primary', 'border-b-2')
    })

    this.draggedEl = null
  },

  handleDragOver(e) {
    e.preventDefault()
    e.dataTransfer.dropEffect = 'move'
  },

  handleDragEnter(e) {
    e.preventDefault()
    const item = e.target.closest('[data-sortable-id]')
    if (!item || item === this.draggedEl) return

    // Clear previous indicators
    this.el.querySelectorAll('[data-sortable-id]').forEach(el => {
      el.classList.remove('border-t-primary', 'border-t-2', 'border-b-primary', 'border-b-2')
    })

    // Show indicator based on mouse position relative to item center
    const rect = item.getBoundingClientRect()
    const midY = rect.top + rect.height / 2

    if (e.clientY < midY) {
      item.classList.add('border-t-primary', 'border-t-2')
    } else {
      item.classList.add('border-b-primary', 'border-b-2')
    }
  },

  handleDragLeave(e) {
    const item = e.target.closest('[data-sortable-id]')
    if (!item) return

    // Only remove if actually leaving the item (not entering a child)
    const relatedTarget = e.relatedTarget
    if (relatedTarget && item.contains(relatedTarget)) return

    item.classList.remove('border-t-primary', 'border-t-2', 'border-b-primary', 'border-b-2')
  },

  handleDrop(e) {
    e.preventDefault()
    const targetItem = e.target.closest('[data-sortable-id]')
    if (!targetItem || !this.draggedEl) return
    if (targetItem === this.draggedEl) return

    // Determine position based on where we dropped
    const rect = targetItem.getBoundingClientRect()
    const midY = rect.top + rect.height / 2
    const insertBefore = e.clientY < midY

    // Reorder DOM elements
    if (insertBefore) {
      this.el.insertBefore(this.draggedEl, targetItem)
    } else {
      this.el.insertBefore(this.draggedEl, targetItem.nextSibling)
    }

    // Update step numbers in badges
    this.updateStepNumbers()

    // Update the hidden JSON input
    this.updateHiddenInput()
  },

  updateStepNumbers() {
    // Update the step number badges after reordering
    const items = this.el.querySelectorAll('[data-sortable-id]')
    items.forEach((item, index) => {
      const badge = item.querySelector('.badge-neutral')
      if (badge) {
        badge.textContent = index + 1
      }
    })
  },

  updateHiddenInput() {
    // Find the hidden source_json input and update it with reordered steps
    const form = this.el.closest('form')
    if (!form) return

    const hiddenInput = form.querySelector('input[name="source_json"]')
    if (!hiddenInput) return

    try {
      // Parse current JSON
      const steps = JSON.parse(hiddenInput.value)

      // Get new order from DOM
      const items = this.el.querySelectorAll('[data-sortable-id]')
      const newOrder = Array.from(items).map(item => item.dataset.sortableId)

      // Reorder steps array to match DOM order
      const stepsById = {}
      steps.forEach(step => {
        stepsById[step.id] = step
      })

      const reorderedSteps = newOrder.map(id => stepsById[id]).filter(Boolean)

      // Update hidden input
      hiddenInput.value = JSON.stringify(reorderedSteps)
    } catch (err) {
      console.error('Failed to update step order:', err)
    }
  }
}

/**
 * Download hook for triggering file downloads from LiveView
 * Listens for "download" events and creates blob downloads
 */
const DownloadHook = {
  mounted() {
    this.handleEvent("download", ({ filename, content, content_type }) => {
      const blob = new Blob([content], { type: content_type })
      const url = URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      a.download = filename
      a.click()
      URL.revokeObjectURL(url)
    })
  }
}

/**
 * LogFilter hook for client-side log filtering
 * Filters log entries by level without server round-trips
 * Uses MutationObserver to catch DOM changes from LiveView updates
 */
const LogFilterHook = {
  mounted() {
    this.filterSelect = this.el.querySelector('[data-log-filter-select]')

    if (this.filterSelect) {
      this.filterSelect.addEventListener('change', (e) => {
        this.applyFilter(e.target.value)
      })
    }

    // Watch for DOM changes (new logs being added)
    const logContainer = this.el.querySelector('[data-log-container]')
    if (logContainer) {
      this.observer = new MutationObserver(() => {
        this.applyFilter(this.filterSelect?.value || 'all')
      })
      this.observer.observe(logContainer, { childList: true, subtree: true })
    }

    // Apply initial filter
    this.applyFilter(this.filterSelect?.value || 'all')
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect()
    }
  },

  updated() {
    // Re-apply filter after LiveView updates (new logs added)
    this.applyFilter(this.filterSelect?.value || 'all')
  },

  applyFilter(level) {
    // Re-query elements each time in case DOM has changed
    const logContainer = this.el.querySelector('[data-log-container]')
    const countDisplay = this.el.querySelector('[data-log-count]')

    if (!logContainer) return

    const rows = logContainer.querySelectorAll('[data-log-level]')
    let visibleCount = 0
    const totalCount = rows.length

    rows.forEach(row => {
      if (level === 'all' || row.dataset.logLevel === level) {
        row.style.display = ''
        visibleCount++
      } else {
        row.style.display = 'none'
      }
    })

    // Update count display
    if (countDisplay) {
      if (level === 'all') {
        countDisplay.textContent = `${totalCount} log entries`
      } else {
        countDisplay.textContent = `${visibleCount} log entries (filtered from ${totalCount} total)`
      }
    }
  }
}

export const Hooks = {
  OpsConsole: OpsConsoleHook,
  OpsConsoleV2: OpsConsoleV2Hook,
  AutoScroll: AutoScrollHook,
  LogFilter: LogFilterHook,
  Sortable: SortableHook,
  DagEditor: DagEditorHook,
  DagViewer: DagViewerHook,
  ExecutionChannel: ExecutionChannelHook,
  Download: DownloadHook
}

export default Hooks
