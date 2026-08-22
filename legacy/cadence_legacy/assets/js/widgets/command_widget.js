/**
 * Command Widget
 *
 * Quick-send single command with one click.
 * Features:
 * - Configurable command + default parameters
 * - Hazardous command confirmation
 * - Status indicator (idle/pending/sent/verified/failed)
 * - Last execution timestamp
 */

import { BaseWidget, registerWidget } from "../dashboard/widget_factory"

/**
 * CommandWidget - Quick command execution button.
 */
export class CommandWidget extends BaseWidget {
  static displayName = "Command Button"
  static description = "Quick-send a single command with one click"
  static icon = "play"

  constructor(options) {
    super(options)
    this.type = "command"
    this.status = "idle" // idle | pending | sent | verified | failed
    this.lastExecution = null
    this.lastError = null
    this._confirmTimeout = null
  }

  init() {
    this.render()
    this.initialized = true
  }

  renderContent() {
    const {
      target_id,
      target_name,
      command_name,
      label,
      hazardous = false,
      description = "",
      parameters = {}
    } = this.config

    const buttonClass = hazardous
      ? "btn-error"
      : "btn-primary"

    const statusInfo = this._getStatusDisplay()

    return `
      <div class="command-widget flex flex-col h-full">
        <!-- Command info -->
        <div class="command-info mb-3">
          <div class="flex items-center gap-2 mb-1">
            ${hazardous ? `
              <svg class="w-4 h-4 text-error" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
              </svg>
            ` : ''}
            <span class="mc-label-subsystem text-base-content/40">${target_name || 'TARGET'}</span>
          </div>
          <div class="text-sm text-base-content/70 truncate" title="${command_name || 'Command'}">
            ${command_name || 'No command configured'}
          </div>
          ${description ? `<div class="text-xs text-base-content/50 mt-1">${description}</div>` : ''}
        </div>

        <!-- Execute button -->
        <div class="command-action flex-1 flex flex-col items-center justify-center">
          <button
            class="command-btn btn ${buttonClass} btn-lg w-full max-w-48 ${!command_name ? 'btn-disabled' : ''}"
            id="cmd-btn-${this.id}"
            ${!command_name ? 'disabled' : ''}
          >
            ${this._getButtonContent()}
          </button>

          ${hazardous && this.status === 'confirming' ? `
            <div class="confirm-prompt mt-2 text-center">
              <span class="text-warning text-xs">Click again to confirm</span>
            </div>
          ` : ''}
        </div>

        <!-- Status footer -->
        <div class="command-status mt-3 pt-2 border-t border-base-300">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="w-2 h-2 rounded-full ${statusInfo.dotClass}"></span>
              <span class="text-xs ${statusInfo.textClass}">${statusInfo.label}</span>
            </div>
            ${this.lastExecution ? `
              <span class="text-xs text-base-content/40">${this._formatTime(this.lastExecution)}</span>
            ` : ''}
          </div>
          ${this.lastError ? `
            <div class="text-xs text-error mt-1 truncate" title="${this.lastError}">${this.lastError}</div>
          ` : ''}
        </div>
      </div>
    `
  }

  render() {
    super.render()
    this._bindButton()
  }

  _getButtonContent() {
    const label = this.config.label || this.config.command_name || 'EXECUTE'

    switch (this.status) {
      case 'pending':
        return `<span class="loading loading-spinner loading-sm"></span>`
      case 'confirming':
        return `<span class="text-warning">CONFIRM?</span>`
      default:
        return label
    }
  }

  _getStatusDisplay() {
    const statusMap = {
      idle: {
        label: 'Ready',
        dotClass: 'bg-base-content/30',
        textClass: 'text-base-content/50'
      },
      confirming: {
        label: 'Awaiting confirmation',
        dotClass: 'bg-warning animate-pulse',
        textClass: 'text-warning'
      },
      pending: {
        label: 'Sending...',
        dotClass: 'bg-info animate-pulse',
        textClass: 'text-info'
      },
      sent: {
        label: 'Sent',
        dotClass: 'bg-success',
        textClass: 'text-success'
      },
      verified: {
        label: 'Verified',
        dotClass: 'bg-success',
        textClass: 'text-success'
      },
      failed: {
        label: 'Failed',
        dotClass: 'bg-error',
        textClass: 'text-error'
      }
    }
    return statusMap[this.status] || statusMap.idle
  }

  _bindButton() {
    const btn = this.container.querySelector(`#cmd-btn-${this.id}`)
    if (!btn) return

    btn.addEventListener("click", (e) => {
      e.stopPropagation()
      this._handleClick()
    })
  }

  _handleClick() {
    const { hazardous = false, command_name } = this.config

    if (!command_name) return

    if (hazardous && this.status !== 'confirming') {
      // First click on hazardous command - show confirmation
      this._setStatus('confirming')

      // Auto-cancel after 5 seconds
      this._confirmTimeout = setTimeout(() => {
        if (this.status === 'confirming') {
          this._setStatus('idle')
        }
      }, 5000)
    } else {
      // Execute the command
      if (this._confirmTimeout) {
        clearTimeout(this._confirmTimeout)
        this._confirmTimeout = null
      }
      this._executeCommand()
    }
  }

  _executeCommand() {
    this._setStatus('pending')
    this.lastError = null

    const { target_id, command_name, parameters = {} } = this.config

    // Dispatch event to LiveView
    const event = new CustomEvent("widget:command", {
      detail: {
        widgetId: this.id,
        targetId: target_id,
        commandName: command_name,
        parameters: parameters
      },
      bubbles: true
    })
    this.container.dispatchEvent(event)

    // Simulate response (in real implementation, LiveView would call back)
    // For now, we'll set to 'sent' after a short delay
    setTimeout(() => {
      if (this.status === 'pending') {
        this._setStatus('sent')
        this.lastExecution = new Date()

        // Reset to idle after a few seconds
        setTimeout(() => {
          if (this.status === 'sent' || this.status === 'verified') {
            this._setStatus('idle')
          }
        }, 3000)
      }
    }, 500)
  }

  _setStatus(status) {
    this.status = status
    this.render()
  }

  // Called by external code to update status
  setCommandResult(success, error = null) {
    if (success) {
      this._setStatus('verified')
      this.lastExecution = new Date()
    } else {
      this._setStatus('failed')
      this.lastError = error || 'Command failed'
    }

    // Reset to idle after a few seconds
    setTimeout(() => {
      this._setStatus('idle')
    }, 5000)
  }

  _formatTime(date) {
    if (!date) return ''
    return date.toLocaleTimeString('en-US', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false
    })
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
    if (this._confirmTimeout) {
      clearTimeout(this._confirmTimeout)
    }
    super.destroy()
  }
}

// Register the widget
registerWidget("command", CommandWidget)

export default CommandWidget
