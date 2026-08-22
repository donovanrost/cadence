/**
 * Alarm Summary Widget
 *
 * Filtered alarm view with inline actions.
 * Features:
 * - Configurable severity filter (critical/warning/info)
 * - Configurable source filter (by target, subsystem)
 * - Inline actions: Acknowledge, Shelve, Clear
 * - Visual severity indication with animated critical alarms
 * - Auto-scroll to new alarms
 */

import { BaseWidget, registerWidget } from "../dashboard/widget_factory"

/**
 * AlarmWidget - Alarm summary with inline actions.
 */
export class AlarmWidget extends BaseWidget {
  static displayName = "Alarm Summary"
  static description = "Filtered alarm list with inline actions"
  static icon = "bell"

  constructor(options) {
    super(options)
    this.type = "alarm"
    this.alarms = []
    this.acknowledgedIds = new Set()
  }

  init() {
    this.render()
    this.initialized = true
  }

  renderContent() {
    const {
      severity_filter = [], // empty = all, or ['critical', 'warning', 'info']
      target_filter = null,
      subsystem_filter = null,
      max_alarms = 20,
      show_cleared = false,
      auto_scroll = true
    } = this.config

    // Filter alarms based on configuration
    let filteredAlarms = [...this.alarms]

    if (severity_filter.length > 0) {
      filteredAlarms = filteredAlarms.filter(a => severity_filter.includes(a.severity))
    }

    if (target_filter) {
      filteredAlarms = filteredAlarms.filter(a => a.target_id === target_filter || a.target_name === target_filter)
    }

    if (subsystem_filter) {
      filteredAlarms = filteredAlarms.filter(a => a.subsystem === subsystem_filter)
    }

    if (!show_cleared) {
      filteredAlarms = filteredAlarms.filter(a => a.status !== 'cleared')
    }

    // Limit number of alarms shown
    filteredAlarms = filteredAlarms.slice(0, max_alarms)

    // Count by severity
    const counts = {
      critical: this.alarms.filter(a => a.severity === 'critical' && a.status !== 'cleared').length,
      warning: this.alarms.filter(a => a.severity === 'warning' && a.status !== 'cleared').length,
      info: this.alarms.filter(a => (a.severity === 'info' || !a.severity) && a.status !== 'cleared').length
    }

    return `
      <div class="alarm-widget flex flex-col h-full">
        <!-- Summary header -->
        <div class="alarm-summary flex items-center justify-between mb-2 pb-2 border-b border-base-300">
          <div class="flex items-center gap-3">
            ${counts.critical > 0 ? `
              <div class="flex items-center gap-1 ${counts.critical > 0 ? 'status-critical-pulse' : ''}">
                <span class="w-2 h-2 rounded-full bg-error"></span>
                <span class="text-xs font-bold text-error">${counts.critical}</span>
              </div>
            ` : ''}
            ${counts.warning > 0 ? `
              <div class="flex items-center gap-1">
                <span class="w-2 h-2 rounded-full bg-warning"></span>
                <span class="text-xs font-bold text-warning">${counts.warning}</span>
              </div>
            ` : ''}
            ${counts.info > 0 ? `
              <div class="flex items-center gap-1">
                <span class="w-2 h-2 rounded-full bg-info"></span>
                <span class="text-xs font-bold text-info">${counts.info}</span>
              </div>
            ` : ''}
            ${counts.critical === 0 && counts.warning === 0 && counts.info === 0 ? `
              <div class="flex items-center gap-1">
                <span class="w-2 h-2 rounded-full bg-success"></span>
                <span class="text-xs text-success">All clear</span>
              </div>
            ` : ''}
          </div>
          <div class="flex items-center gap-1">
            <button class="btn btn-ghost btn-xs" id="alarm-ack-all-${this.id}" title="Acknowledge All">
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
              </svg>
            </button>
          </div>
        </div>

        <!-- Alarm list -->
        <div class="alarm-list flex-1 overflow-y-auto space-y-1" id="alarm-list-${this.id}">
          ${filteredAlarms.length > 0 ? filteredAlarms.map(alarm => this._renderAlarmItem(alarm)).join('') : `
            <div class="text-center py-8 text-base-content/40">
              <svg class="w-8 h-8 mx-auto mb-2 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
              </svg>
              <p class="text-xs">No alarms</p>
            </div>
          `}
        </div>

        <!-- Filter indicator -->
        ${(severity_filter.length > 0 || target_filter || subsystem_filter) ? `
          <div class="alarm-filter-info mt-2 pt-2 border-t border-base-300">
            <div class="text-xs text-base-content/40 flex items-center gap-2">
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z"/>
              </svg>
              <span>Filtered view</span>
            </div>
          </div>
        ` : ''}
      </div>
    `
  }

  _renderAlarmItem(alarm) {
    const severityClass = this._getSeverityClass(alarm.severity)
    const isAcknowledged = this.acknowledgedIds.has(alarm.id) || alarm.acknowledged
    const isNew = alarm.isNew // Set by updateAlarms when a new alarm comes in

    return `
      <div
        class="alarm-item ${severityClass} ${isNew ? 'alarm-new' : ''} ${isAcknowledged ? 'opacity-60' : ''}"
        data-alarm-id="${alarm.id}"
      >
        <div class="alarm-item-header flex items-start justify-between gap-2">
          <div class="flex items-center gap-2 min-w-0 flex-1">
            <span class="alarm-severity-dot w-2 h-2 rounded-full flex-shrink-0 ${this._getSeverityDotClass(alarm.severity)}"></span>
            <span class="alarm-source text-xs font-medium truncate">${alarm.target_name || 'Unknown'}</span>
          </div>
          <span class="alarm-time text-xs text-base-content/40 flex-shrink-0">${this._formatTime(alarm.triggered_at)}</span>
        </div>

        <div class="alarm-message text-sm mt-1 ${alarm.severity === 'critical' ? 'font-medium' : ''}">
          ${alarm.message || alarm.name || 'Alarm'}
        </div>

        <div class="alarm-actions flex items-center gap-1 mt-2">
          ${!isAcknowledged ? `
            <button class="alarm-btn alarm-btn-ack" data-action="acknowledge" title="Acknowledge">
              ACK
            </button>
          ` : `
            <span class="text-xs text-base-content/40">Acknowledged</span>
          `}
          <button class="alarm-btn" data-action="shelve" title="Shelve">
            SHELVE
          </button>
          <button class="alarm-btn alarm-btn-clear" data-action="clear" title="Clear">
            CLEAR
          </button>
          <button class="alarm-btn ml-auto" data-action="details" title="View Details">
            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
            </svg>
          </button>
        </div>
      </div>
    `
  }

  _getSeverityClass(severity) {
    switch (severity) {
      case 'critical':
        return 'alarm-item-critical'
      case 'warning':
        return 'alarm-item-warning'
      case 'info':
      default:
        return 'alarm-item-info'
    }
  }

  _getSeverityDotClass(severity) {
    switch (severity) {
      case 'critical':
        return 'bg-error'
      case 'warning':
        return 'bg-warning'
      case 'info':
      default:
        return 'bg-info'
    }
  }

  _formatTime(timestamp) {
    if (!timestamp) return '--:--'
    const date = new Date(timestamp)
    return date.toLocaleTimeString('en-US', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false
    })
  }

  render() {
    super.render()
    this._bindActions()
  }

  _bindActions() {
    // Acknowledge all button
    this.container.querySelector(`#alarm-ack-all-${this.id}`)?.addEventListener('click', (e) => {
      e.stopPropagation()
      this._dispatchAction('acknowledge_all', null)
    })

    // Individual alarm actions
    this.container.querySelectorAll('.alarm-item').forEach(item => {
      const alarmId = item.dataset.alarmId

      item.querySelectorAll('.alarm-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
          e.stopPropagation()
          const action = btn.dataset.action
          this._dispatchAction(action, alarmId)

          // Optimistic UI update for acknowledge
          if (action === 'acknowledge') {
            this.acknowledgedIds.add(alarmId)
            this.render()
          }
        })
      })
    })
  }

  _dispatchAction(action, alarmId) {
    const event = new CustomEvent("widget:alarm_action", {
      detail: {
        widgetId: this.id,
        alarmId: alarmId,
        action: action
      },
      bubbles: true
    })
    this.container.dispatchEvent(event)
  }

  // Called by external code to update alarms
  updateAlarms(alarms, options = {}) {
    const { markNewAlarms = true } = options

    if (markNewAlarms) {
      // Mark new alarms that weren't in the previous list
      const previousIds = new Set(this.alarms.map(a => a.id))
      alarms = alarms.map(a => ({
        ...a,
        isNew: !previousIds.has(a.id)
      }))
    }

    this.alarms = alarms
    this.render()

    // Auto-scroll to top if configured and there are new alarms
    if (this.config.auto_scroll && alarms.some(a => a.isNew)) {
      const list = this.container.querySelector(`#alarm-list-${this.id}`)
      if (list) {
        list.scrollTop = 0
      }
    }

    // Clear "new" markers after a delay
    setTimeout(() => {
      this.alarms = this.alarms.map(a => ({ ...a, isNew: false }))
      // Don't re-render, just clear the flag for next update
    }, 3000)
  }

  // Add a single alarm
  addAlarm(alarm) {
    this.alarms = [{ ...alarm, isNew: true }, ...this.alarms]
    this.render()

    if (this.config.auto_scroll) {
      const list = this.container.querySelector(`#alarm-list-${this.id}`)
      if (list) {
        list.scrollTop = 0
      }
    }
  }

  // Remove an alarm
  removeAlarm(alarmId) {
    this.alarms = this.alarms.filter(a => a.id !== alarmId)
    this.acknowledgedIds.delete(alarmId)
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
}

// Register the widget
registerWidget("alarm", AlarmWidget)

export default AlarmWidget
