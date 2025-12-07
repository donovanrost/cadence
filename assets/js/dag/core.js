/**
 * Core DAG rendering module
 *
 * Shared between DagEditor and DagViewer hooks.
 * Provides layout calculation, node/edge rendering, and zoom/pan functionality.
 */

import dagre from 'dagre'
import {
  NODE_WIDTH,
  NODE_HEIGHT,
  NODE_MARGIN,
  NODE_RADIUS,
  ICON_RADIUS,
  ICON_OFFSET_X,
  TYPE_ICONS,
  MIN_ZOOM,
  MAX_ZOOM,
  STATUS_COLORS,
  EDITOR_COLORS,
  EDGE_COLORS
} from './constants.js'
import {
  escapeHtml,
  truncate,
  getStepSummary,
  calculateEdgePath,
  clamp
} from './utils.js'

/**
 * Calculate DAG layout using dagre
 * @param {Object} steps - Map of step name to step definition
 * @param {Object} customPositions - Optional custom positions to preserve
 * @returns {Object} Map of step name to { x, y } position
 */
export function calculateLayout(steps, customPositions = {}) {
  const stepNames = Object.keys(steps)
  if (stepNames.length === 0) return {}

  const g = new dagre.graphlib.Graph()
  g.setGraph({
    rankdir: 'TB',
    nodesep: NODE_MARGIN,
    ranksep: NODE_MARGIN * 1.5,
    marginx: NODE_MARGIN,
    marginy: NODE_MARGIN
  })
  g.setDefaultEdgeLabel(() => ({}))

  // Add nodes
  stepNames.forEach(name => {
    g.setNode(name, { width: NODE_WIDTH, height: NODE_HEIGHT })
  })

  // Add edges (dependencies)
  Object.entries(steps).forEach(([name, step]) => {
    const deps = step.depends_on || []
    deps.forEach(dep => {
      if (steps[dep]) {
        g.setEdge(dep, name)
      }
    })
  })

  // Run layout
  dagre.layout(g)

  // Extract positions, merging with custom positions
  const positions = {}
  stepNames.forEach(name => {
    if (customPositions[name]) {
      positions[name] = { ...customPositions[name] }
    } else {
      const node = g.node(name)
      positions[name] = { x: node.x, y: node.y }
    }
  })

  return positions
}

/**
 * Render SVG markers (arrowheads) and filters definition
 */
export function renderMarkers() {
  return `
    <marker id="arrowhead" markerWidth="10" markerHeight="7" refX="9" refY="3.5" orient="auto">
      <polygon points="0 0, 10 3.5, 0 7" fill="currentColor" opacity="0.5"/>
    </marker>
    <marker id="arrowhead-success" markerWidth="10" markerHeight="7" refX="9" refY="3.5" orient="auto">
      <polygon points="0 0, 10 3.5, 0 7" class="fill-success"/>
    </marker>
    <marker id="arrowhead-error" markerWidth="10" markerHeight="7" refX="9" refY="3.5" orient="auto">
      <polygon points="0 0, 10 3.5, 0 7" class="fill-error"/>
    </marker>

    <!-- Vaporwave glow filter for running steps -->
    <filter id="glow-cyan" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur in="SourceGraphic" stdDeviation="4" result="blur1"/>
      <feGaussianBlur in="SourceGraphic" stdDeviation="8" result="blur2"/>
      <feGaussianBlur in="SourceGraphic" stdDeviation="12" result="blur3"/>
      <feMerge>
        <feMergeNode in="blur3"/>
        <feMergeNode in="blur2"/>
        <feMergeNode in="blur1"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>

    <!-- Warning glow filter for pausing steps -->
    <filter id="glow-warning" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur in="SourceGraphic" stdDeviation="4" result="blur1"/>
      <feGaussianBlur in="SourceGraphic" stdDeviation="8" result="blur2"/>
      <feMerge>
        <feMergeNode in="blur2"/>
        <feMergeNode in="blur1"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  `
}

/**
 * Render grid pattern definition
 */
export function renderGridPattern() {
  return `
    <pattern id="grid" width="20" height="20" patternUnits="userSpaceOnUse">
      <path d="M 20 0 L 0 0 0 20" fill="none" stroke="currentColor" stroke-width="0.5" opacity="0.1"/>
    </pattern>
  `
}

/**
 * Render a single edge between two nodes
 * @param {string} from - Source node name
 * @param {string} to - Target node name
 * @param {Object} fromPos - Source position { x, y }
 * @param {Object} toPos - Target position { x, y }
 * @param {Object} options - Rendering options
 * @param {string} options.colorClass - Tailwind stroke class
 * @param {string} options.markerEnd - Arrow marker ID
 */
export function renderEdge(from, to, fromPos, toPos, options = {}) {
  const {
    colorClass = EDGE_COLORS.default,
    markerEnd = 'url(#arrowhead)',
    opacity = '0.4'
  } = options

  // Calculate start/end points (from bottom of source to top of target)
  const start = { x: fromPos.x, y: fromPos.y + NODE_HEIGHT / 2 }
  const end = { x: toPos.x, y: toPos.y - NODE_HEIGHT / 2 }

  const path = calculateEdgePath(start, end)

  return `<path
    d="${path}"
    fill="none"
    class="${colorClass}"
    stroke-width="2"
    opacity="${opacity}"
    marker-end="${markerEnd}"
    data-edge-from="${from}"
    data-edge-to="${to}"
  />`
}

/**
 * Render a node for the VIEWER (execution display)
 * Includes status-based coloring and animations
 */
export function renderViewerNode(name, position, step, status = 'pending', options = {}) {
  const { selected = false, onClick = null, progress = null } = options

  const type = step.type || 'unknown'
  const icon = TYPE_ICONS[type] || TYPE_ICONS.unknown

  const x = position.x - NODE_WIDTH / 2
  const y = position.y - NODE_HEIGHT / 2

  const statusConfig = STATUS_COLORS[status] || STATUS_COLORS.pending

  // Selection highlight
  const selectionRing = selected ? `
    <rect
      x="${x - 4}" y="${y - 4}"
      width="${NODE_WIDTH + 8}" height="${NODE_HEIGHT + 8}"
      rx="${NODE_RADIUS + 2}"
      class="fill-none stroke-primary stroke-2"
      stroke-dasharray="4 2"
    />
  ` : ''

  // Running/pausing: apply glow filter and animate stroke color
  const isRunning = status === 'running' || status === 'pausing'
  const glowColors = status === 'pausing'
    ? ['#f90', '#ff0', '#fa0', '#f90']  // warning: orange -> yellow -> orange
    : ['#0ff', '#f0f', '#0af', '#0ff']   // running: cyan -> magenta -> blue -> cyan
  const filterId = status === 'pausing' ? 'glow-warning' : 'glow-cyan'

  const cursorClass = onClick ? 'cursor-pointer' : ''
  const hoverClass = onClick ? 'hover:scale-[1.02]' : ''

  // Build stroke animation for running states
  const strokeAnimation = isRunning ? `
    <animate
      attributeName="stroke"
      values="${glowColors.join(';')}"
      dur="2s"
      repeatCount="indefinite"
    />
  ` : ''

  // Determine summary text - use progress info when running, static summary otherwise
  const summaryText = (isRunning && progress)
    ? getProgressSummary(step, progress)
    : getStepSummary(step)

  // Add a pulsing dot indicator when we have live progress
  const progressIndicator = (isRunning && progress) ? `
    <circle
      cx="${x + 46}"
      cy="${position.y + 7}"
      r="3"
      class="fill-info"
    >
      <animate attributeName="opacity" values="1;0.4;1" dur="1.5s" repeatCount="indefinite"/>
    </circle>
  ` : ''

  return `
    <g
      data-node="${escapeHtml(name)}"
      class="${cursorClass} transition-transform ${hoverClass}"
    >
      ${selectionRing}

      <!-- Main node rectangle -->
      <rect
        x="${x}" y="${y}"
        width="${NODE_WIDTH}" height="${NODE_HEIGHT}"
        rx="${NODE_RADIUS}"
        class="${statusConfig.fill} ${isRunning ? '' : statusConfig.stroke} stroke-2"
        ${isRunning ? `filter="url(#${filterId})" stroke="${glowColors[0]}"` : ''}
      >${strokeAnimation}</rect>

      <!-- Icon circle background -->
      <circle
        cx="${x + ICON_OFFSET_X}"
        cy="${position.y}"
        r="${ICON_RADIUS}"
        class="fill-base-100/50"
      />

      <!-- Icon -->
      <text
        x="${x + ICON_OFFSET_X}"
        y="${position.y + 5}"
        text-anchor="middle"
        class="${statusConfig.text} text-lg pointer-events-none select-none"
      >${icon}</text>

      <!-- Step name -->
      <text
        x="${x + 50}"
        y="${position.y - 8}"
        class="${statusConfig.text} text-sm font-medium pointer-events-none select-none"
      >${escapeHtml(truncate(name, 16))}</text>

      <!-- Step summary (contextual - shows progress when running) -->
      ${progressIndicator}
      <text
        x="${x + (isRunning && progress ? 54 : 50)}"
        y="${position.y + 10}"
        class="${statusConfig.text} ${isRunning && progress ? '' : 'opacity-60'} text-xs pointer-events-none select-none"
        id="step-summary-${escapeHtml(name)}"
      >${escapeHtml(summaryText)}</text>
    </g>
  `
}

/**
 * Format progress data into a human-readable summary for display on node
 */
export function getProgressSummary(step, progress) {
  if (!progress || !progress.type) {
    return getStepSummary(step)
  }

  switch (progress.type) {
    case 'wait': {
      const remaining = Math.ceil(progress.remaining_ms / 1000)
      const total = Math.ceil(progress.total_ms / 1000)
      if (remaining <= 0) return 'completing...'
      if (total < 60) {
        return `${remaining}s remaining`
      } else {
        // For longer waits, show mm:ss format
        const mins = Math.floor(remaining / 60)
        const secs = remaining % 60
        return `${mins}:${secs.toString().padStart(2, '0')} remaining`
      }
    }

    case 'wait_for': {
      const actual = progress.actual !== null && progress.actual !== undefined
        ? progress.actual
        : '?'
      const expected = progress.expected
      const op = progress.operator || '=='
      const remaining = Math.ceil(progress.remaining_ms / 1000)

      // Format: "current → target (timeout)"
      // Truncate values if too long
      const actualStr = String(actual).substring(0, 8)
      const expectedStr = String(expected).substring(0, 8)

      return `${actualStr} ${op} ${expectedStr} (${remaining}s)`
    }

    default:
      return getStepSummary(step)
  }
}

/**
 * Render a node for the EDITOR
 * Includes selection state, error indicators, and connection handle
 */
export function renderEditorNode(name, position, step, options = {}) {
  const {
    selected = false,
    hasErrors = false,
    showHandle = true
  } = options

  const type = step.type || 'unknown'
  const icon = TYPE_ICONS[type] || TYPE_ICONS.unknown

  const x = position.x - NODE_WIDTH / 2
  const y = position.y - NODE_HEIGHT / 2

  // Determine colors based on state
  let colorConfig = EDITOR_COLORS.default
  let glowStyle = ''

  if (hasErrors) {
    colorConfig = EDITOR_COLORS.error
    glowStyle = `filter: drop-shadow(0 0 6px ${EDITOR_COLORS.error.glow});`
  } else if (selected) {
    colorConfig = EDITOR_COLORS.selected
    glowStyle = `filter: drop-shadow(0 0 6px ${EDITOR_COLORS.selected.glow});`
  }

  // Error indicator
  const errorIndicator = hasErrors ? `
    <circle cx="${x + NODE_WIDTH - 12}" cy="${y + 12}" r="6" class="fill-error"/>
    <text x="${x + NODE_WIDTH - 12}" y="${y + 16}" text-anchor="middle" class="fill-error-content text-xs pointer-events-none">!</text>
  ` : ''

  // Connection handle (for drawing edges)
  const handle = showHandle ? `
    <circle
      cx="${position.x}"
      cy="${y + NODE_HEIGHT}"
      r="6"
      class="fill-base-100 stroke-base-content/30 stroke-2 cursor-crosshair hover:fill-primary hover:stroke-primary transition-colors"
      data-handle="${escapeHtml(name)}"
    />
  ` : ''

  return `
    <g data-node="${escapeHtml(name)}" class="cursor-grab" style="${glowStyle}">
      <!-- Main node rectangle -->
      <rect
        x="${x}" y="${y}"
        width="${NODE_WIDTH}" height="${NODE_HEIGHT}"
        rx="${NODE_RADIUS}"
        class="${colorConfig.fill} ${colorConfig.stroke}"
        stroke-width="2"
      />

      <!-- Icon -->
      <text
        x="${x + ICON_OFFSET_X}"
        y="${position.y + 5}"
        text-anchor="middle"
        class="fill-current text-lg pointer-events-none select-none"
      >${icon}</text>

      <!-- Step name -->
      <text
        x="${x + 50}"
        y="${position.y - 8}"
        class="fill-current text-sm font-medium pointer-events-none select-none"
      >${escapeHtml(truncate(name, 16))}</text>

      <!-- Step summary -->
      <text
        x="${x + 50}"
        y="${position.y + 10}"
        class="fill-current/60 text-xs pointer-events-none select-none"
      >${escapeHtml(getStepSummary(step))}</text>

      ${errorIndicator}
      ${handle}
    </g>
  `
}

/**
 * Render empty state when no steps exist
 */
export function renderEmptyState(message = 'No steps defined', subMessage = '') {
  return `
    <foreignObject x="0" y="0" width="400" height="200">
      <div xmlns="http://www.w3.org/1999/xhtml" class="flex items-center justify-center h-full text-base-content/50">
        <div class="text-center">
          <svg class="w-16 h-16 mx-auto mb-4 opacity-30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"
                  d="M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM4 13a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H5a1 1 0 01-1-1v-6zM16 13a1 1 0 011-1h2a1 1 0 011 1v6a1 1 0 01-1 1h-2a1 1 0 01-1-1v-6z"/>
          </svg>
          <p class="text-lg">${escapeHtml(message)}</p>
          ${subMessage ? `<p class="text-sm mt-1">${escapeHtml(subMessage)}</p>` : ''}
        </div>
      </div>
    </foreignObject>
  `
}

/**
 * ZoomPanController - handles zoom and pan interactions
 */
export class ZoomPanController {
  constructor(options = {}) {
    this.zoom = options.initialZoom || 1.0
    this.panX = options.initialPanX || 50
    this.panY = options.initialPanY || 50
    this.minZoom = options.minZoom || MIN_ZOOM
    this.maxZoom = options.maxZoom || MAX_ZOOM
    this.onChange = options.onChange || (() => {})

    // Interaction state
    this.isPanning = false
    this.lastMouseX = 0
    this.lastMouseY = 0
  }

  /**
   * Get current transform string for SVG
   */
  getTransform() {
    return `translate(${this.panX}, ${this.panY}) scale(${this.zoom})`
  }

  /**
   * Set zoom level with bounds checking
   */
  setZoom(newZoom, centerX = null, centerY = null) {
    const oldZoom = this.zoom
    this.zoom = clamp(newZoom, this.minZoom, this.maxZoom)

    // If center point provided, adjust pan to zoom toward that point
    if (centerX !== null && centerY !== null) {
      const zoomRatio = this.zoom / oldZoom
      this.panX = centerX - (centerX - this.panX) * zoomRatio
      this.panY = centerY - (centerY - this.panY) * zoomRatio
    }

    this.onChange()
    return this.zoom
  }

  /**
   * Adjust zoom by delta
   */
  adjustZoom(delta, centerX = null, centerY = null) {
    return this.setZoom(this.zoom + delta, centerX, centerY)
  }

  /**
   * Set pan position
   */
  setPan(x, y) {
    this.panX = x
    this.panY = y
    this.onChange()
  }

  /**
   * Adjust pan by delta
   */
  adjustPan(dx, dy) {
    this.panX += dx
    this.panY += dy
    this.onChange()
  }

  /**
   * Start panning
   */
  startPan(mouseX, mouseY) {
    this.isPanning = true
    this.lastMouseX = mouseX
    this.lastMouseY = mouseY
  }

  /**
   * Update pan during drag
   */
  updatePan(mouseX, mouseY) {
    if (!this.isPanning) return false

    const dx = mouseX - this.lastMouseX
    const dy = mouseY - this.lastMouseY
    this.lastMouseX = mouseX
    this.lastMouseY = mouseY

    this.adjustPan(dx, dy)
    return true
  }

  /**
   * End panning
   */
  endPan() {
    this.isPanning = false
  }

  /**
   * Fit view to show all content
   */
  fitToView(boundingBox, containerWidth, containerHeight, padding = 50) {
    const { minX, minY, width, height } = boundingBox

    // Calculate zoom to fit
    const scaleX = (containerWidth - padding * 2) / (width + NODE_WIDTH)
    const scaleY = (containerHeight - padding * 2) / (height + NODE_HEIGHT)
    this.zoom = clamp(Math.min(scaleX, scaleY), this.minZoom, this.maxZoom)

    // Center the content
    const contentCenterX = minX + width / 2
    const contentCenterY = minY + height / 2
    this.panX = containerWidth / 2 - contentCenterX * this.zoom
    this.panY = containerHeight / 2 - contentCenterY * this.zoom

    this.onChange()
  }

  /**
   * Reset to default view
   */
  reset() {
    this.zoom = 1.0
    this.panX = 50
    this.panY = 50
    this.onChange()
  }

  /**
   * Handle wheel event for zooming
   */
  handleWheel(event, containerRect) {
    event.preventDefault()

    const delta = event.deltaY > 0 ? -0.1 : 0.1
    const mouseX = event.clientX - containerRect.left
    const mouseY = event.clientY - containerRect.top

    this.adjustZoom(delta, mouseX, mouseY)
  }
}

/**
 * Get edge color based on step statuses
 */
export function getEdgeColor(fromStatus, toStatus) {
  if (fromStatus === 'completed' && (toStatus === 'running' || toStatus === 'completed')) {
    return { colorClass: EDGE_COLORS.success, markerEnd: 'url(#arrowhead-success)', opacity: '0.7' }
  }
  if (fromStatus === 'failed' || fromStatus === 'timed_out') {
    return { colorClass: EDGE_COLORS.error, markerEnd: 'url(#arrowhead-error)', opacity: '0.5' }
  }
  if (fromStatus === 'completed') {
    return { colorClass: EDGE_COLORS.successFaded, markerEnd: 'url(#arrowhead-success)', opacity: '0.5' }
  }
  return { colorClass: EDGE_COLORS.default, markerEnd: 'url(#arrowhead)', opacity: '0.4' }
}

/**
 * Render the status legend for viewer
 */
export function renderLegend() {
  const items = [
    { status: 'pending', label: 'Pending' },
    { status: 'running', label: 'Running' },
    { status: 'completed', label: 'Completed' },
    { status: 'failed', label: 'Failed' },
    { status: 'timed_out', label: 'Timed Out' },
    { status: 'blocked', label: 'Blocked' },
    { status: 'skipped', label: 'Skipped' }
  ]

  return `
    <div class="flex flex-wrap items-center gap-4 text-sm">
      ${items.map(({ status, label }) => {
        const config = STATUS_COLORS[status]
        const isRunning = status === 'running'
        return `
          <div class="flex items-center gap-2">
            <div class="w-4 h-4 rounded ${config.fill} border-2 ${config.stroke}" ${isRunning ? 'style="animation: vapor-glow-legend 2s ease-in-out infinite;"' : ''}></div>
            <span>${label}</span>
          </div>
        `
      }).join('')}
    </div>
  `
}
