/**
 * Shared constants for DAG rendering
 */

// Node dimensions
export const NODE_WIDTH = 180
export const NODE_HEIGHT = 70
export const NODE_MARGIN = 40
export const NODE_RADIUS = 8

// Icon circle
export const ICON_RADIUS = 14
export const ICON_OFFSET_X = 24

// Step type icons (emoji)
export const TYPE_ICONS = {
  command: '⚡',
  wait: '⏱',
  wait_for: '👁',
  check: '✓',
  assert: '⚠',
  log: '📝',
  set: '📌',
  branch: '⑂',
  label: '🏷',
  unknown: '?'
}

// Step types for UI
export const STEP_TYPES = [
  { type: 'command', icon: '⚡', label: 'command' },
  { type: 'wait', icon: '⏱', label: 'wait' },
  { type: 'wait_for', icon: '👁', label: 'wait_for' },
  { type: 'check', icon: '✓', label: 'check' },
  { type: 'assert', icon: '⚠', label: 'assert' },
  { type: 'log', icon: '📝', label: 'log' },
  { type: 'set', icon: '📌', label: 'set' },
  { type: 'branch', icon: '⑂', label: 'branch' },
  { type: 'label', icon: '🏷', label: 'label' }
]

// Input types for procedure inputs
export const INPUT_TYPES = [
  { type: 'string', label: 'String' },
  { type: 'number', label: 'Number' },
  { type: 'integer', label: 'Integer' },
  { type: 'boolean', label: 'Boolean' },
  { type: 'duration', label: 'Duration (ms)' },
  { type: 'telemetry_item', label: 'Telemetry Item' },
  { type: 'command', label: 'Command' }
]

// Zoom constraints
export const MIN_ZOOM = 0.25
export const MAX_ZOOM = 2.0
export const ZOOM_STEP = 0.25

// Status colors for execution viewer
// Pattern: colored border, subtle background tint, readable base-content text
// Running/pausing states get vaporwave glow animation via CSS
export const STATUS_COLORS = {
  pending: {
    fill: 'fill-base-100',
    stroke: 'stroke-base-content/30',
    text: 'fill-base-content'
  },
  running: {
    fill: 'fill-info/10',
    stroke: 'stroke-info',
    text: 'fill-base-content'
  },
  pausing: {
    fill: 'fill-warning/10',
    stroke: 'stroke-warning',
    text: 'fill-base-content'
  },
  completed: {
    fill: 'fill-success/10',
    stroke: 'stroke-success',
    text: 'fill-base-content'
  },
  failed: {
    fill: 'fill-error/10',
    stroke: 'stroke-error',
    text: 'fill-base-content'
  },
  timed_out: {
    fill: 'fill-warning/10',
    stroke: 'stroke-warning',
    text: 'fill-base-content'
  },
  cancelled: {
    fill: 'fill-base-200',
    stroke: 'stroke-base-content/50',
    text: 'fill-base-content/70'
  },
  blocked: {
    fill: 'fill-base-200',
    stroke: 'stroke-base-content/30',
    text: 'fill-base-content/50'
  },
  skipped: {
    fill: 'fill-warning/10',
    stroke: 'stroke-warning',
    text: 'fill-base-content'
  }
}

// Editor-specific colors
export const EDITOR_COLORS = {
  default: {
    fill: 'fill-base-100',
    stroke: 'stroke-base-content/30'
  },
  selected: {
    fill: 'fill-primary/5',
    stroke: 'stroke-primary',
    glow: 'rgba(99, 102, 241, 0.5)'
  },
  error: {
    fill: 'fill-error/5',
    stroke: 'stroke-error',
    glow: 'rgba(239, 68, 68, 0.5)'
  }
}

// Edge colors based on status
export const EDGE_COLORS = {
  default: 'stroke-base-content/30',
  success: 'stroke-success',
  successFaded: 'stroke-success/50',
  error: 'stroke-error/50'
}
