/**
 * Procedure Status Widget
 *
 * Shows running procedure with real-time progress.
 * Features:
 * - Step list with completion states (pending/running/completed/failed/skipped)
 * - Current step highlight with elapsed time
 * - Pause/Resume/Abort controls
 * - Progress bar
 * - Real-time log tail (last few lines)
 */

import { BaseWidget, registerWidget } from "../dashboard/widget_factory"

/**
 * ProcedureWidget - Procedure execution status and control.
 */
export class ProcedureWidget extends BaseWidget {
  static displayName = "Procedure Status"
  static description = "Monitor and control running procedure execution"
  static icon = "clipboard-check"

  constructor(options) {
    super(options)
    this.type = "procedure"
    this.execution = null
    this.steps = []
    this.logs = []
    this.elapsedTimer = null
  }

  init() {
    this.render()
    this._startElapsedTimer()
    this.initialized = true
  }

  renderContent() {
    const {
      procedure_name,
      execution_id,
      show_logs = true,
      max_visible_steps = 5
    } = this.config

    // Mock execution data for display (in real implementation, this comes from LiveView)
    const execution = this.execution || {
      status: 'idle',
      current_step: null,
      started_at: null,
      completed_steps: 0,
      total_steps: 0
    }

    const steps = this.steps || []
    const logs = this.logs || []

    if (!procedure_name && !execution_id) {
      return `
        <div class="procedure-widget flex items-center justify-center h-full">
          <div class="text-center text-base-content/50">
            <svg class="w-8 h-8 mx-auto mb-2 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
            </svg>
            <p class="text-sm">No procedure configured</p>
          </div>
        </div>
      `
    }

    const progressPercent = execution.total_steps > 0
      ? Math.round((execution.completed_steps / execution.total_steps) * 100)
      : 0

    return `
      <div class="procedure-widget flex flex-col h-full">
        <!-- Header with procedure name and controls -->
        <div class="procedure-header flex items-center justify-between mb-2">
          <div class="flex-1 min-w-0">
            <div class="font-semibold text-sm truncate">${procedure_name || 'Procedure'}</div>
            <div class="text-xs text-base-content/50">${this._getStatusLabel(execution.status)}</div>
          </div>
          <div class="procedure-controls flex items-center gap-1">
            ${this._renderControls(execution.status)}
          </div>
        </div>

        <!-- Progress bar -->
        <div class="procedure-progress mb-3">
          <div class="flex items-center justify-between text-xs text-base-content/50 mb-1">
            <span>Step ${execution.completed_steps}/${execution.total_steps}</span>
            <span>${progressPercent}%</span>
          </div>
          <div class="w-full h-2 bg-base-300 rounded-full overflow-hidden">
            <div
              class="h-full ${this._getProgressBarClass(execution.status)} transition-all duration-300"
              style="width: ${progressPercent}%"
            ></div>
          </div>
        </div>

        <!-- Steps list -->
        <div class="procedure-steps flex-1 overflow-y-auto mb-2">
          ${this._renderSteps(steps, execution.current_step, max_visible_steps)}
        </div>

        <!-- Log tail -->
        ${show_logs ? `
          <div class="procedure-logs mt-auto pt-2 border-t border-base-300">
            <div class="mc-label-subsystem text-base-content/40 mb-1">LOG</div>
            <div class="log-content bg-base-300/50 rounded p-2 h-16 overflow-y-auto font-mono text-xs">
              ${logs.length > 0 ? logs.slice(-5).map(log => `
                <div class="log-line ${this._getLogClass(log.level)}">
                  <span class="text-base-content/40">${this._formatLogTime(log.timestamp)}</span>
                  <span>${log.message}</span>
                </div>
              `).join('') : '<span class="text-base-content/40">No log entries</span>'}
            </div>
          </div>
        ` : ''}

        <!-- Elapsed time -->
        ${execution.started_at ? `
          <div class="procedure-elapsed text-center mt-2">
            <span class="text-xs text-base-content/40">Elapsed: </span>
            <span class="text-xs font-mono" id="elapsed-${this.id}">${this._formatElapsed(execution.started_at)}</span>
          </div>
        ` : ''}
      </div>
    `
  }

  _renderControls(status) {
    switch (status) {
      case 'running':
        return `
          <button class="btn btn-ghost btn-xs" id="proc-pause-${this.id}" title="Pause">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
            </svg>
          </button>
          <button class="btn btn-ghost btn-xs text-error" id="proc-abort-${this.id}" title="Abort">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
            </svg>
          </button>
        `
      case 'paused':
        return `
          <button class="btn btn-ghost btn-xs text-success" id="proc-resume-${this.id}" title="Resume">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"/>
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
            </svg>
          </button>
          <button class="btn btn-ghost btn-xs text-error" id="proc-abort-${this.id}" title="Abort">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
            </svg>
          </button>
        `
      case 'idle':
        return `
          <button class="btn btn-ghost btn-xs text-success" id="proc-start-${this.id}" title="Start">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"/>
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
            </svg>
          </button>
        `
      default:
        return ''
    }
  }

  _renderSteps(steps, currentStepId, maxVisible) {
    if (steps.length === 0) {
      return '<div class="text-xs text-base-content/40 text-center py-2">No steps loaded</div>'
    }

    // Find current step index to show context around it
    const currentIndex = steps.findIndex(s => s.id === currentStepId)
    let visibleSteps = steps

    if (steps.length > maxVisible && currentIndex >= 0) {
      // Show steps around the current one
      const start = Math.max(0, currentIndex - Math.floor(maxVisible / 2))
      const end = Math.min(steps.length, start + maxVisible)
      visibleSteps = steps.slice(start, end)
    } else if (steps.length > maxVisible) {
      visibleSteps = steps.slice(0, maxVisible)
    }

    return visibleSteps.map((step, idx) => `
      <div class="step-item flex items-start gap-2 py-1 ${step.id === currentStepId ? 'bg-primary/10 -mx-2 px-2 rounded' : ''}">
        <div class="step-indicator flex-shrink-0 mt-0.5">
          ${this._getStepIcon(step.status, step.id === currentStepId)}
        </div>
        <div class="step-content flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <span class="text-xs font-mono text-base-content/40">${step.number || idx + 1}.</span>
            <span class="text-sm truncate ${step.status === 'failed' ? 'text-error' : ''}">${step.name}</span>
          </div>
          ${step.duration ? `
            <span class="text-xs text-base-content/40">${this._formatDuration(step.duration)}</span>
          ` : ''}
        </div>
      </div>
    `).join('')
  }

  _getStepIcon(status, isCurrent) {
    const iconClass = "w-4 h-4"

    switch (status) {
      case 'completed':
        return `<svg class="${iconClass} text-success" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
        </svg>`
      case 'running':
        return `<span class="${iconClass} flex items-center justify-center">
          <span class="loading loading-spinner loading-xs text-primary"></span>
        </span>`
      case 'failed':
        return `<svg class="${iconClass} text-error" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
        </svg>`
      case 'skipped':
        return `<svg class="${iconClass} text-base-content/30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 5l7 7-7 7M5 5l7 7-7 7"/>
        </svg>`
      default: // pending
        return `<span class="w-3 h-3 rounded-full border-2 border-base-content/20 ${isCurrent ? 'border-primary' : ''}"></span>`
    }
  }

  _getStatusLabel(status) {
    const labels = {
      idle: 'Ready to run',
      running: 'Running',
      paused: 'Paused',
      completed: 'Completed',
      failed: 'Failed',
      aborted: 'Aborted'
    }
    return labels[status] || 'Unknown'
  }

  _getProgressBarClass(status) {
    switch (status) {
      case 'running':
        return 'bg-primary'
      case 'paused':
        return 'bg-warning'
      case 'completed':
        return 'bg-success'
      case 'failed':
      case 'aborted':
        return 'bg-error'
      default:
        return 'bg-base-content/20'
    }
  }

  _getLogClass(level) {
    switch (level) {
      case 'error':
        return 'text-error'
      case 'warning':
        return 'text-warning'
      case 'success':
        return 'text-success'
      default:
        return 'text-base-content/70'
    }
  }

  _formatLogTime(timestamp) {
    if (!timestamp) return ''
    const date = new Date(timestamp)
    return date.toLocaleTimeString('en-US', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false
    })
  }

  _formatElapsed(startedAt) {
    if (!startedAt) return '00:00:00'

    const start = new Date(startedAt)
    const now = new Date()
    const diff = Math.floor((now - start) / 1000)

    const hours = Math.floor(diff / 3600)
    const minutes = Math.floor((diff % 3600) / 60)
    const seconds = diff % 60

    return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`
  }

  _formatDuration(ms) {
    if (!ms) return ''
    const seconds = Math.round(ms / 1000)
    if (seconds < 60) return `${seconds}s`
    const minutes = Math.floor(seconds / 60)
    const remainingSeconds = seconds % 60
    return `${minutes}m ${remainingSeconds}s`
  }

  _startElapsedTimer() {
    // Update elapsed time every second
    this.elapsedTimer = setInterval(() => {
      const elapsedEl = this.container.querySelector(`#elapsed-${this.id}`)
      if (elapsedEl && this.execution?.started_at) {
        elapsedEl.textContent = this._formatElapsed(this.execution.started_at)
      }
    }, 1000)
  }

  render() {
    super.render()
    this._bindControls()
  }

  _bindControls() {
    const pauseBtn = this.container.querySelector(`#proc-pause-${this.id}`)
    const resumeBtn = this.container.querySelector(`#proc-resume-${this.id}`)
    const abortBtn = this.container.querySelector(`#proc-abort-${this.id}`)
    const startBtn = this.container.querySelector(`#proc-start-${this.id}`)

    pauseBtn?.addEventListener('click', (e) => {
      e.stopPropagation()
      this._dispatchAction('pause')
    })

    resumeBtn?.addEventListener('click', (e) => {
      e.stopPropagation()
      this._dispatchAction('resume')
    })

    abortBtn?.addEventListener('click', (e) => {
      e.stopPropagation()
      this._dispatchAction('abort')
    })

    startBtn?.addEventListener('click', (e) => {
      e.stopPropagation()
      this._dispatchAction('start')
    })
  }

  _dispatchAction(action) {
    const event = new CustomEvent("widget:procedure_action", {
      detail: {
        widgetId: this.id,
        executionId: this.config.execution_id,
        action: action
      },
      bubbles: true
    })
    this.container.dispatchEvent(event)
  }

  // Called by external code to update execution state
  updateExecution(execution, steps, logs) {
    this.execution = execution
    this.steps = steps || this.steps
    this.logs = logs || this.logs
    this.render()
  }

  // Add a log entry
  addLog(log) {
    this.logs.push(log)
    // Keep only last 50 logs
    if (this.logs.length > 50) {
      this.logs = this.logs.slice(-50)
    }
    this.render()
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
    if (this.elapsedTimer) {
      clearInterval(this.elapsedTimer)
    }
    super.destroy()
  }
}

// Register the widget
registerWidget("procedure", ProcedureWidget)

export default ProcedureWidget
