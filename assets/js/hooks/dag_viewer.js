/**
 * DAG Viewer Hook
 *
 * Read-only DAG visualization for procedure execution display.
 * Uses the shared dag/core module for rendering.
 *
 * Features:
 * - Real-time status updates via LiveView assigns
 * - Zoom and pan controls
 * - Click-to-select step details
 * - Status-based coloring and animations
 */

import {
  calculateLayout,
  renderMarkers,
  renderGridPattern,
  renderEdge,
  renderViewerNode,
  renderEmptyState,
  renderLegend,
  getEdgeColor,
  ZoomPanController
} from '../dag/core.js'
import { NODE_WIDTH, NODE_HEIGHT, ZOOM_STEP } from '../dag/constants.js'
import { calculateBoundingBox, escapeHtml } from '../dag/utils.js'

export const DagViewerHook = {
  mounted() {
    // Parse initial data from data attributes
    this.parseDataAttributes()

    // Get the content container (inner div with phx-update="ignore")
    this.contentEl = this.el.querySelector('#dag-viewer-content') || this.el

    // UI state
    this.selectedStep = null
    this.positions = {}
    this.isLocked = true  // Canvas locked by default

    // Initialize zoom/pan controller
    this.zoomPan = new ZoomPanController({
      initialZoom: 1.0,
      initialPanX: 50,
      initialPanY: 50,
      onChange: () => this.updateTransform()
    })

    // Render initial UI
    this.render()

    // Set up event listeners
    this.setupEventListeners()
  },

  parseDataAttributes() {
    this.steps = JSON.parse(this.el.dataset.steps || '{}')
    this.completedSteps = JSON.parse(this.el.dataset.completedSteps || '[]')
    this.failedSteps = JSON.parse(this.el.dataset.failedSteps || '[]')
    this.blockedSteps = JSON.parse(this.el.dataset.blockedSteps || '[]')
    this.skippedSteps = JSON.parse(this.el.dataset.skippedSteps || '[]')
    this.timedOutSteps = JSON.parse(this.el.dataset.timedOutSteps || '[]')
    this.runningSteps = JSON.parse(this.el.dataset.runningSteps || '[]')
    this.stepResults = JSON.parse(this.el.dataset.stepResults || '{}')
    this.stepProgress = JSON.parse(this.el.dataset.stepProgress || '{}')
    this.executionStatus = this.el.dataset.executionStatus || 'pending'
  },

  handleDataUpdate() {
    const oldSteps = JSON.stringify(this.steps)

    // Re-parse data attributes
    this.parseDataAttributes()

    // Check if steps changed (need to recalculate layout)
    const stepsChanged = JSON.stringify(this.steps) !== oldSteps

    if (stepsChanged) {
      // Recalculate layout for new steps
      this.positions = calculateLayout(this.steps)
    }

    // Re-render canvas content (nodes and edges with new statuses)
    this.renderCanvasContent()

    // Update step details if selected
    if (this.selectedStep) {
      this.updateStepDetails()
    }
  },

  updated() {
    // With phx-update="ignore", this shouldn't be called often,
    // but handle it just in case
    this.handleDataUpdate()
  },

  // Handle server push events - note: LiveView calls this directly
  handleEvent(event, payload) {
    if (event === 'step_progress') {
      const { step_name, progress } = payload
      this.stepProgress[step_name] = progress
      this.updateStepProgressDisplay(step_name, progress)
    }
  },

  // Update the progress display for a specific step
  updateStepProgressDisplay(stepName, progress) {
    // Re-render the canvas to update the node's contextual summary
    // This is efficient because we're just updating the SVG text
    this.renderCanvasContent()

    // Update step details panel if this step is selected
    if (this.selectedStep === stepName) {
      this.updateStepDetails()
    }
  },

  destroyed() {
    // Cleanup
    this.removeEventListeners()
  },

  // ==========================================================================
  // Rendering
  // ==========================================================================

  render() {
    const stepCount = Object.keys(this.steps).length

    this.contentEl.innerHTML = `
      <style>
        @keyframes vapor-glow {
          0%, 100% {
            filter:
              drop-shadow(0 0 3px #0ff)
              drop-shadow(0 0 6px #0ff)
              drop-shadow(0 0 12px #0ff)
              drop-shadow(0 0 24px #0af);
            opacity: 0.9;
          }
          33% {
            filter:
              drop-shadow(0 0 4px #f0f)
              drop-shadow(0 0 8px #f0f)
              drop-shadow(0 0 16px #f0f)
              drop-shadow(0 0 32px #f0f)
              drop-shadow(0 0 48px #a0f);
            opacity: 1;
          }
          66% {
            filter:
              drop-shadow(0 0 3px #0ff)
              drop-shadow(0 0 8px #0af)
              drop-shadow(0 0 20px #0af)
              drop-shadow(0 0 40px #05f);
            opacity: 0.95;
          }
        }
        @keyframes vapor-glow-warning {
          0%, 100% {
            filter:
              drop-shadow(0 0 3px #f90)
              drop-shadow(0 0 6px #f90)
              drop-shadow(0 0 12px #f60)
              drop-shadow(0 0 24px #f30);
            opacity: 0.9;
          }
          50% {
            filter:
              drop-shadow(0 0 4px #ff0)
              drop-shadow(0 0 10px #fa0)
              drop-shadow(0 0 20px #f80)
              drop-shadow(0 0 35px #f50);
            opacity: 1;
          }
        }
        @keyframes vapor-glow-legend {
          0%, 100% {
            box-shadow: 0 0 4px #0ff, 0 0 8px #0ff, 0 0 12px #0af;
          }
          33% {
            box-shadow: 0 0 6px #f0f, 0 0 12px #f0f, 0 0 20px #a0f;
          }
          66% {
            box-shadow: 0 0 4px #0ff, 0 0 10px #0af, 0 0 16px #05f;
          }
        }
      </style>
      <div class="dag-viewer-container flex flex-col h-full">
        <!-- Toolbar -->
        <div class="flex items-center justify-between px-3 py-2 border-b border-base-300 bg-base-200">
          <div class="flex items-center gap-2">
            <span class="text-sm font-medium text-base-content/70">Step Progress</span>
            <span class="badge badge-sm">${stepCount} steps</span>
          </div>
          <div class="flex items-center gap-1">
            <!-- Zoom controls (hidden when locked) -->
            <div id="zoom-controls" class="${this.isLocked ? 'hidden' : 'flex'} items-center gap-1">
              <button type="button" id="zoom-out-btn" class="btn btn-ghost btn-xs btn-square" title="Zoom out">
                <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 12H4"/>
                </svg>
              </button>
              <span id="zoom-level" class="text-xs w-12 text-center tabular-nums">${Math.round(this.zoomPan.zoom * 100)}%</span>
              <button type="button" id="zoom-in-btn" class="btn btn-ghost btn-xs btn-square" title="Zoom in">
                <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
                </svg>
              </button>
              <div class="w-px h-4 bg-base-300 mx-1"></div>
              <button type="button" id="fit-view-btn" class="btn btn-ghost btn-xs btn-square" title="Fit to view">
                <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4"/>
                </svg>
              </button>
              <button type="button" id="reset-view-btn" class="btn btn-ghost btn-xs btn-square" title="Reset view">
                <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
                </svg>
              </button>
              <div class="w-px h-4 bg-base-300 mx-1"></div>
            </div>
            <!-- Lock toggle -->
            <button type="button" id="lock-toggle-btn" class="btn btn-ghost btn-xs btn-square" title="${this.isLocked ? 'Unlock canvas' : 'Lock canvas'}">
              <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                ${this.isLocked
                  ? '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/>'
                  : '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 11V7a4 4 0 118 0m-4 8v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2z"/>'
                }
              </svg>
            </button>
          </div>
        </div>

        <!-- Canvas -->
        <div class="flex-1 relative overflow-hidden">
          <div id="canvas-container" class="absolute inset-0 bg-base-100">
            <svg id="dag-svg" class="w-full h-full">
              <defs>
                ${renderGridPattern()}
                ${renderMarkers()}
              </defs>
              <g id="canvas-transform">
                <rect x="-10000" y="-10000" width="20000" height="20000" fill="url(#grid)" class="pointer-events-none"/>
                <g id="edges-group"></g>
                <g id="nodes-group"></g>
              </g>
            </svg>
          </div>

          <!-- Step Details Panel (slides in from right) -->
          <div id="step-details-panel" class="absolute top-0 right-0 bottom-0 w-80 bg-base-100 border-l border-base-300 transform translate-x-full transition-transform duration-200 ease-out z-10">
            <div id="step-details-content"></div>
          </div>
        </div>

        <!-- Legend -->
        <div class="px-4 py-3 border-t border-base-300 bg-base-50">
          ${renderLegend()}
        </div>
      </div>
    `

    // Calculate initial layout
    this.positions = calculateLayout(this.steps)

    // Render canvas content
    this.renderCanvasContent()

    // Update transform
    this.updateTransform()

    // Auto-fit view when locked (after a small delay to ensure DOM is ready)
    if (this.isLocked && Object.keys(this.steps).length > 0) {
      setTimeout(() => this.fitToView(), 50)
    }
  },

  renderCanvasContent() {
    const nodesGroup = document.getElementById('nodes-group')
    const edgesGroup = document.getElementById('edges-group')
    if (!nodesGroup || !edgesGroup) return

    const stepCount = Object.keys(this.steps).length

    if (stepCount === 0) {
      nodesGroup.innerHTML = renderEmptyState('No steps defined')
      edgesGroup.innerHTML = ''
      return
    }

    // Render edges
    edgesGroup.innerHTML = ''
    Object.entries(this.steps).forEach(([name, step]) => {
      const deps = step.depends_on || []
      deps.forEach(dep => {
        if (this.positions[dep] && this.positions[name]) {
          const fromPos = this.positions[dep]
          const toPos = this.positions[name]
          const fromStatus = this.getStepStatus(dep)
          const toStatus = this.getStepStatus(name)
          const edgeOptions = getEdgeColor(fromStatus, toStatus)
          edgesGroup.innerHTML += renderEdge(dep, name, fromPos, toPos, edgeOptions)
        }
      })
    })

    // Render nodes
    nodesGroup.innerHTML = ''
    Object.entries(this.steps).forEach(([name, step]) => {
      const pos = this.positions[name]
      if (!pos) return

      const status = this.getStepStatus(name)
      const isSelected = name === this.selectedStep
      const progress = this.stepProgress[name] || null

      nodesGroup.innerHTML += renderViewerNode(name, pos, step, status, {
        selected: isSelected,
        onClick: true,
        progress: progress
      })
    })

    // Attach click handlers to nodes
    this.attachNodeClickHandlers()
  },

  getStepStatus(stepName) {
    // Check execution status for special cases
    if (this.runningSteps.includes(stepName)) {
      if (this.executionStatus === 'pausing') return 'pausing'
      if (this.executionStatus === 'cancelled') return 'cancelled'
      return 'running'
    }
    if (this.completedSteps.includes(stepName)) return 'completed'
    if (this.failedSteps.includes(stepName)) return 'failed'
    if (this.timedOutSteps.includes(stepName)) return 'timed_out'
    if (this.blockedSteps.includes(stepName)) return 'blocked'
    if (this.skippedSteps.includes(stepName)) return 'skipped'
    return 'pending'
  },

  updateTransform() {
    const transformGroup = document.getElementById('canvas-transform')
    if (transformGroup) {
      transformGroup.setAttribute('transform', this.zoomPan.getTransform())
    }

    const zoomLabel = document.getElementById('zoom-level')
    if (zoomLabel) {
      zoomLabel.textContent = `${Math.round(this.zoomPan.zoom * 100)}%`
    }
  },

  // ==========================================================================
  // Step Details Panel
  // ==========================================================================

  showStepDetails(stepName) {
    this.selectedStep = stepName
    this.updateStepDetails()
    this.renderCanvasContent() // Re-render to show selection

    const panel = document.getElementById('step-details-panel')
    if (panel) {
      panel.classList.remove('translate-x-full')
      panel.classList.add('translate-x-0')
    }
  },

  hideStepDetails() {
    this.selectedStep = null
    this.renderCanvasContent() // Re-render to hide selection

    const panel = document.getElementById('step-details-panel')
    if (panel) {
      panel.classList.remove('translate-x-0')
      panel.classList.add('translate-x-full')
    }
  },

  updateStepDetails() {
    const content = document.getElementById('step-details-content')
    if (!content || !this.selectedStep) return

    const step = this.steps[this.selectedStep] || {}
    const status = this.getStepStatus(this.selectedStep)
    const result = this.stepResults[this.selectedStep]
    const progress = this.stepProgress[this.selectedStep]

    // Build progress display for running steps
    let progressHtml = ''
    if (status === 'running' && progress) {
      progressHtml = this.renderProgressSection(progress)
    }

    content.innerHTML = `
      <div class="flex flex-col h-full">
        <!-- Header -->
        <div class="flex items-center justify-between px-4 py-3 border-b border-base-300 bg-base-200">
          <div class="flex items-center gap-2 min-w-0">
            <span class="text-lg">${this.getTypeIcon(step.type)}</span>
            <span class="font-medium truncate">${escapeHtml(this.selectedStep)}</span>
          </div>
          <button type="button" id="close-details-btn" class="btn btn-ghost btn-sm btn-square flex-shrink-0">
            <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
            </svg>
          </button>
        </div>

        <!-- Content -->
        <div class="flex-1 overflow-y-auto p-4 space-y-4">
          <!-- Status & Type -->
          <div class="grid grid-cols-2 gap-4">
            <div>
              <div class="text-xs font-medium uppercase tracking-wide text-base-content/60 mb-1">Type</div>
              <div class="font-mono text-sm">${escapeHtml(step.type || 'unknown')}</div>
            </div>
            <div>
              <div class="text-xs font-medium uppercase tracking-wide text-base-content/60 mb-1">Status</div>
              <span class="${this.getStatusBadgeClass(status)}">${this.formatStatus(status)}</span>
            </div>
          </div>

          <!-- Progress (for running wait/wait_for steps) -->
          ${progressHtml}

          <!-- Dependencies -->
          ${step.depends_on && step.depends_on.length > 0 ? `
            <div>
              <div class="text-xs font-medium uppercase tracking-wide text-base-content/60 mb-1">Depends On</div>
              <div class="flex flex-wrap gap-1">
                ${step.depends_on.map(dep => `
                  <span class="badge badge-sm badge-ghost">${escapeHtml(dep)}</span>
                `).join('')}
              </div>
            </div>
          ` : ''}

          <!-- Step-specific details -->
          ${this.renderStepSpecificDetails(step)}

          <!-- Result (if available) -->
          ${result ? `
            <div>
              <div class="text-xs font-medium uppercase tracking-wide text-base-content/60 mb-1">Result</div>
              <pre class="p-2 bg-base-200 rounded text-xs overflow-auto max-h-40 font-mono">${escapeHtml(JSON.stringify(result, null, 2))}</pre>
            </div>
          ` : ''}
        </div>
      </div>
    `

    // Attach close handler
    const closeBtn = document.getElementById('close-details-btn')
    if (closeBtn) {
      closeBtn.addEventListener('click', () => this.hideStepDetails())
    }
  },

  renderProgressSection(progress) {
    if (progress.type === 'wait') {
      const remaining = Math.ceil(progress.remaining_ms / 1000)
      const total = Math.ceil(progress.total_ms / 1000)
      const pct = Math.round((progress.elapsed_ms / progress.total_ms) * 100)

      return `
        <div class="p-3 bg-info/10 border border-info/30 rounded-lg">
          <div class="text-xs font-medium uppercase tracking-wide text-info mb-2">Wait Progress</div>
          <div class="flex items-center gap-3">
            <div class="flex-1">
              <div class="w-full bg-base-300 rounded-full h-2">
                <div class="bg-info h-2 rounded-full transition-all duration-300" style="width: ${pct}%"></div>
              </div>
            </div>
            <div class="text-sm font-mono tabular-nums text-info">${remaining}s</div>
          </div>
          <div class="text-xs text-base-content/60 mt-1">${pct}% complete (${total - remaining}s / ${total}s)</div>
        </div>
      `
    }

    if (progress.type === 'wait_for') {
      const remaining = Math.ceil(progress.remaining_ms / 1000)
      const actualDisplay = progress.actual !== null ? progress.actual : '—'

      return `
        <div class="p-3 bg-info/10 border border-info/30 rounded-lg">
          <div class="text-xs font-medium uppercase tracking-wide text-info mb-2">Waiting For Condition</div>
          <div class="space-y-2">
            <div class="flex items-center justify-between">
              <span class="text-sm text-base-content/70">Current Value:</span>
              <code class="px-2 py-0.5 bg-base-200 rounded font-mono text-sm">${escapeHtml(String(actualDisplay))}</code>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-sm text-base-content/70">Expected:</span>
              <code class="px-2 py-0.5 bg-base-200 rounded font-mono text-sm">${progress.operator} ${escapeHtml(String(progress.expected))}</code>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-sm text-base-content/70">Timeout in:</span>
              <span class="font-mono text-sm tabular-nums">${remaining}s</span>
            </div>
          </div>
        </div>
      `
    }

    return ''
  },

  renderStepSpecificDetails(step) {
    if (!step.type) return ''

    const details = []

    switch (step.type) {
      case 'command':
        if (step.name) details.push({ label: 'Command', value: step.name, mono: true })
        if (step.args && Object.keys(step.args).length > 0) {
          details.push({ label: 'Arguments', value: JSON.stringify(step.args, null, 2), pre: true })
        }
        break
      case 'wait':
        if (step.duration) details.push({ label: 'Duration', value: `${step.duration}ms` })
        break
      case 'wait_for':
        if (step.item) details.push({ label: 'Item', value: step.item, mono: true })
        if (step.operator) details.push({ label: 'Operator', value: step.operator })
        if (step.value !== undefined) details.push({ label: 'Value', value: String(step.value) })
        if (step.timeout) details.push({ label: 'Timeout', value: `${step.timeout}ms` })
        break
      case 'check':
      case 'assert':
        if (step.condition) details.push({ label: 'Condition', value: step.condition, mono: true })
        if (step.message) details.push({ label: 'Message', value: step.message })
        break
      case 'log':
        if (step.level) details.push({ label: 'Level', value: step.level })
        if (step.message) details.push({ label: 'Message', value: step.message })
        break
      case 'set':
        if (step.name) details.push({ label: 'Variable', value: step.name, mono: true })
        if (step.value !== undefined) details.push({ label: 'Value', value: String(step.value) })
        break
      case 'branch':
        if (step.condition) details.push({ label: 'Condition', value: step.condition, mono: true })
        if (step.goto) details.push({ label: 'Go To', value: step.goto })
        if (step.else_goto) details.push({ label: 'Else Go To', value: step.else_goto })
        break
      case 'label':
        if (step.name) details.push({ label: 'Label Name', value: step.name })
        break
    }

    if (details.length === 0) return ''

    return `
      <div class="space-y-3">
        ${details.map(d => `
          <div>
            <div class="text-xs font-medium uppercase tracking-wide text-base-content/60 mb-1">${d.label}</div>
            ${d.pre ? `<pre class="p-2 bg-base-200 rounded text-xs overflow-auto max-h-32 font-mono">${escapeHtml(d.value)}</pre>` :
              d.mono ? `<code class="px-1 bg-base-200 rounded text-sm font-mono">${escapeHtml(d.value)}</code>` :
              `<div class="text-sm">${escapeHtml(d.value)}</div>`}
          </div>
        `).join('')}
      </div>
    `
  },

  getTypeIcon(type) {
    const icons = {
      command: '⚡',
      wait: '⏱',
      wait_for: '👁',
      check: '✓',
      assert: '⚠',
      log: '📝',
      set: '📌',
      branch: '⑂',
      label: '🏷'
    }
    return icons[type] || '?'
  },

  getStatusBadgeClass(status) {
    const classes = {
      pending: 'badge badge-sm',
      running: 'badge badge-sm badge-info',
      pausing: 'badge badge-sm badge-warning animate-pulse',
      completed: 'badge badge-sm badge-success',
      failed: 'badge badge-sm badge-error',
      timed_out: 'badge badge-sm badge-warning',
      cancelled: 'badge badge-sm badge-ghost',
      blocked: 'badge badge-sm badge-ghost',
      skipped: 'badge badge-sm badge-warning'
    }
    return classes[status] || 'badge badge-sm'
  },

  formatStatus(status) {
    if (status === 'timed_out') return 'Timed Out'
    return status.charAt(0).toUpperCase() + status.slice(1)
  },

  // ==========================================================================
  // Event Handling
  // ==========================================================================

  setupEventListeners() {
    const container = document.getElementById('canvas-container')
    if (container) {
      // Pan handling
      container.addEventListener('mousedown', (e) => this.handleMouseDown(e))
      container.addEventListener('mousemove', (e) => this.handleMouseMove(e))
      container.addEventListener('mouseup', () => this.handleMouseUp())
      container.addEventListener('mouseleave', () => this.handleMouseUp())

      // Zoom handling
      container.addEventListener('wheel', (e) => this.handleWheel(e), { passive: false })
    }

    // Toolbar buttons
    this.on('#zoom-out-btn', 'click', () => this.zoomPan.adjustZoom(-ZOOM_STEP))
    this.on('#zoom-in-btn', 'click', () => this.zoomPan.adjustZoom(ZOOM_STEP))
    this.on('#fit-view-btn', 'click', () => this.fitToView())
    this.on('#reset-view-btn', 'click', () => this.zoomPan.reset())
    this.on('#lock-toggle-btn', 'click', () => this.toggleLock())
  },

  toggleLock() {
    this.isLocked = !this.isLocked

    // Update zoom controls visibility
    const zoomControls = document.getElementById('zoom-controls')
    if (zoomControls) {
      zoomControls.classList.toggle('hidden', this.isLocked)
      zoomControls.classList.toggle('flex', !this.isLocked)
    }

    // Update lock button icon and title
    const lockBtn = document.getElementById('lock-toggle-btn')
    if (lockBtn) {
      lockBtn.title = this.isLocked ? 'Unlock canvas' : 'Lock canvas'
      lockBtn.innerHTML = `
        <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          ${this.isLocked
            ? '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/>'
            : '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 11V7a4 4 0 118 0m-4 8v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2z"/>'
          }
        </svg>
      `
    }
  },

  removeEventListeners() {
    // Event listeners are automatically cleaned up when element is removed
  },

  attachNodeClickHandlers() {
    const nodesGroup = document.getElementById('nodes-group')
    if (!nodesGroup) return

    nodesGroup.querySelectorAll('[data-node]').forEach(node => {
      node.addEventListener('click', (e) => {
        e.stopPropagation()
        const stepName = node.getAttribute('data-node')
        if (stepName === this.selectedStep) {
          this.hideStepDetails()
        } else {
          this.showStepDetails(stepName)
        }
      })
    })
  },

  handleMouseDown(e) {
    // Only pan on left click on empty space, and only if unlocked
    if (this.isLocked) return
    if (e.button !== 0) return
    if (e.target.closest('[data-node]')) return

    this.zoomPan.startPan(e.clientX, e.clientY)
    e.currentTarget.style.cursor = 'grabbing'
  },

  handleMouseMove(e) {
    if (this.isLocked) return
    if (this.zoomPan.updatePan(e.clientX, e.clientY)) {
      // Panning
    }
  },

  handleMouseUp() {
    if (this.isLocked) return
    this.zoomPan.endPan()
    const container = document.getElementById('canvas-container')
    if (container) {
      container.style.cursor = ''
    }
  },

  handleWheel(e) {
    // Don't zoom when locked
    if (this.isLocked) return
    const container = document.getElementById('canvas-container')
    if (!container) return
    this.zoomPan.handleWheel(e, container.getBoundingClientRect())
  },

  fitToView() {
    const container = document.getElementById('canvas-container')
    if (!container) return

    const bbox = calculateBoundingBox(this.positions)
    const rect = container.getBoundingClientRect()
    this.zoomPan.fitToView(bbox, rect.width, rect.height)
  },

  // Helper to attach event listener
  on(selector, event, handler) {
    const el = document.querySelector(selector)
    if (el) {
      el.addEventListener(event, handler)
    }
  }
}

export default DagViewerHook
