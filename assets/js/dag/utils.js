/**
 * Shared utilities for DAG rendering
 */

/**
 * Escape HTML special characters
 */
export function escapeHtml(str) {
  if (!str) return ''
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;')
}

/**
 * Truncate string to max length with ellipsis
 */
export function truncate(str, maxLen) {
  if (!str) return ''
  if (str.length <= maxLen) return str
  return str.slice(0, maxLen - 2) + '..'
}

/**
 * Get a human-readable summary of a step's configuration
 */
export function getStepSummary(step) {
  if (!step || !step.type) return ''

  switch (step.type) {
    case 'command':
      return step.name ? truncate(step.name, 20) : 'no command'
    case 'wait':
      if (step.duration) {
        const ms = step.duration
        if (ms >= 1000) return `${(ms / 1000).toFixed(1)}s`
        return `${ms}ms`
      }
      return 'wait'
    case 'wait_for':
      if (step.item) return truncate(step.item, 18)
      return 'wait_for'
    case 'check':
    case 'assert':
      if (step.condition) return truncate(step.condition, 18)
      return step.type
    case 'log':
      return step.level || 'info'
    case 'set':
      if (step.name) return truncate(step.name, 18)
      return 'set'
    case 'branch':
      if (step.goto) return `→ ${truncate(step.goto, 14)}`
      return 'branch'
    case 'label':
      return step.name || 'label'
    default:
      return step.type
  }
}

/**
 * Generate unique ID
 */
export function generateId() {
  return `dag-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`
}

/**
 * Clamp a value between min and max
 */
export function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

/**
 * Get mouse position relative to SVG
 */
export function getSvgPoint(svg, event) {
  const pt = svg.createSVGPoint()
  pt.x = event.clientX
  pt.y = event.clientY
  const svgP = pt.matrixTransform(svg.getScreenCTM().inverse())
  return { x: svgP.x, y: svgP.y }
}

/**
 * Calculate bezier curve control points for an edge
 */
export function calculateEdgePath(start, end) {
  const deltaY = end.y - start.y
  const deltaX = end.x - start.x

  // Control point offset - curves more for longer vertical distances
  const curveStrength = Math.min(Math.abs(deltaY) * 0.5, 80)

  // For mostly vertical connections, use vertical bezier
  // For diagonal connections, add some horizontal curve
  const cp1x = start.x + (deltaX * 0.1)
  const cp1y = start.y + curveStrength
  const cp2x = end.x - (deltaX * 0.1)
  const cp2y = end.y - curveStrength

  return `M ${start.x} ${start.y} C ${cp1x} ${cp1y}, ${cp2x} ${cp2y}, ${end.x} ${end.y}`
}

/**
 * Calculate bounding box for a set of nodes
 */
export function calculateBoundingBox(positions) {
  const nodeNames = Object.keys(positions)
  if (nodeNames.length === 0) {
    return { minX: 0, minY: 0, maxX: 400, maxY: 200, width: 400, height: 200 }
  }

  let minX = Infinity, minY = Infinity
  let maxX = -Infinity, maxY = -Infinity

  nodeNames.forEach(name => {
    const pos = positions[name]
    minX = Math.min(minX, pos.x)
    minY = Math.min(minY, pos.y)
    maxX = Math.max(maxX, pos.x)
    maxY = Math.max(maxY, pos.y)
  })

  return {
    minX,
    minY,
    maxX,
    maxY,
    width: maxX - minX,
    height: maxY - minY
  }
}
