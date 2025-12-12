/**
 * Fleet Health Widget
 *
 * Aggregated constellation health view.
 * Features:
 * - Group aggregation (by plane, shell, cluster, or custom groups)
 * - Health bars with percentage
 * - Expandable to show individual vehicles
 * - Click-to-select vehicle integration
 */

import { BaseWidget, registerWidget } from "../dashboard/widget_factory"

/**
 * FleetHealthWidget - Constellation health overview.
 */
export class FleetHealthWidget extends BaseWidget {
  static displayName = "Fleet Health"
  static description = "Aggregated constellation health overview"
  static icon = "server"

  constructor(options) {
    super(options)
    this.type = "fleet_health"
    this.groups = []
    this.expandedGroups = new Set()
    this.selectedTargetId = null
  }

  init() {
    this.render()
    this.initialized = true
  }

  renderContent() {
    const {
      group_by = 'none', // none | plane | shell | cluster | custom
      show_individual = true,
      show_critical_only = false
    } = this.config

    const groups = this.groups || []

    if (groups.length === 0) {
      return `
        <div class="fleet-health-widget flex items-center justify-center h-full">
          <div class="text-center text-base-content/50">
            <svg class="w-8 h-8 mx-auto mb-2 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2"/>
            </svg>
            <p class="text-sm">No fleet data</p>
          </div>
        </div>
      `
    }

    // Calculate overall health
    const totalHealthy = groups.reduce((sum, g) => sum + g.healthy, 0)
    const totalCount = groups.reduce((sum, g) => sum + g.total, 0)
    const overallPercent = totalCount > 0 ? Math.round((totalHealthy / totalCount) * 100) : 0

    return `
      <div class="fleet-health-widget flex flex-col h-full">
        <!-- Overall summary -->
        <div class="fleet-summary flex items-center justify-between mb-3 pb-2 border-b border-base-300">
          <div>
            <span class="mc-label-subsystem text-base-content/40">FLEET HEALTH</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-2xl font-mono font-bold ${this._getHealthColor(overallPercent)}">${overallPercent}%</span>
            <span class="text-xs text-base-content/50">(${totalHealthy}/${totalCount})</span>
          </div>
        </div>

        <!-- Groups list -->
        <div class="fleet-groups flex-1 overflow-y-auto space-y-2">
          ${groups.map((group, idx) => this._renderGroup(group, idx, show_individual)).join('')}
        </div>

        <!-- Legend -->
        <div class="fleet-legend mt-2 pt-2 border-t border-base-300">
          <div class="flex items-center justify-center gap-4 text-xs">
            <div class="flex items-center gap-1">
              <span class="w-2 h-2 rounded-full bg-success"></span>
              <span class="text-base-content/50">Healthy</span>
            </div>
            <div class="flex items-center gap-1">
              <span class="w-2 h-2 rounded-full bg-warning"></span>
              <span class="text-base-content/50">Degraded</span>
            </div>
            <div class="flex items-center gap-1">
              <span class="w-2 h-2 rounded-full bg-error"></span>
              <span class="text-base-content/50">Critical</span>
            </div>
          </div>
        </div>
      </div>
    `
  }

  _renderGroup(group, index, showIndividual) {
    const percent = group.total > 0 ? Math.round((group.healthy / group.total) * 100) : 0
    const isExpanded = this.expandedGroups.has(group.id || index)
    const hasIssues = group.critical > 0 || group.warning > 0

    return `
      <div class="fleet-group ${hasIssues ? 'has-issues' : ''}">
        <!-- Group header -->
        <div
          class="group-header flex items-center gap-2 p-2 rounded cursor-pointer hover:bg-base-300/50 transition-colors"
          data-group-id="${group.id || index}"
        >
          ${showIndividual && group.targets?.length > 0 ? `
            <svg class="w-4 h-4 text-base-content/40 transition-transform ${isExpanded ? 'rotate-90' : ''}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
            </svg>
          ` : '<span class="w-4"></span>'}

          <div class="flex-1 min-w-0">
            <div class="flex items-center justify-between">
              <span class="text-sm font-medium truncate">${group.name}</span>
              <span class="text-xs text-base-content/50">${group.healthy}/${group.total}</span>
            </div>
            <!-- Health bar -->
            <div class="h-1.5 bg-base-300 rounded-full mt-1 overflow-hidden flex">
              ${group.healthy > 0 ? `<div class="bg-success" style="width: ${(group.healthy / group.total) * 100}%"></div>` : ''}
              ${group.warning > 0 ? `<div class="bg-warning" style="width: ${(group.warning / group.total) * 100}%"></div>` : ''}
              ${group.critical > 0 ? `<div class="bg-error" style="width: ${(group.critical / group.total) * 100}%"></div>` : ''}
            </div>
          </div>

          <span class="text-sm font-mono font-bold ${this._getHealthColor(percent)}">${percent}%</span>
        </div>

        <!-- Expanded targets list -->
        ${isExpanded && showIndividual && group.targets?.length > 0 ? `
          <div class="group-targets pl-6 pr-2 pb-2">
            <div class="grid grid-cols-4 gap-1">
              ${group.targets.map(target => this._renderTargetDot(target)).join('')}
            </div>
          </div>
        ` : ''}
      </div>
    `
  }

  _renderTargetDot(target) {
    const statusClass = this._getTargetStatusClass(target.status)
    const isSelected = this.selectedTargetId === target.id

    return `
      <div
        class="target-dot flex items-center justify-center w-6 h-6 rounded cursor-pointer transition-all
               ${statusClass} ${isSelected ? 'ring-2 ring-primary ring-offset-1 ring-offset-base-100' : ''}
               hover:scale-110"
        data-target-id="${target.id}"
        title="${target.name}: ${target.status}"
      >
        <span class="text-[0.6rem] font-mono font-bold">${this._getTargetInitials(target.name)}</span>
      </div>
    `
  }

  _getTargetInitials(name) {
    if (!name) return '?'
    // Get first 2 characters or initials
    const parts = name.split(/[-_\s]/)
    if (parts.length > 1) {
      return (parts[0][0] + parts[1][0]).toUpperCase()
    }
    return name.slice(0, 2).toUpperCase()
  }

  _getTargetStatusClass(status) {
    switch (status) {
      case 'healthy':
      case 'nominal':
        return 'bg-success/20 text-success'
      case 'warning':
      case 'degraded':
        return 'bg-warning/20 text-warning'
      case 'critical':
      case 'failed':
        return 'bg-error/20 text-error'
      case 'offline':
      case 'stale':
        return 'bg-base-content/10 text-base-content/30'
      default:
        return 'bg-base-content/10 text-base-content/50'
    }
  }

  _getHealthColor(percent) {
    if (percent >= 95) return 'text-success'
    if (percent >= 80) return 'text-warning'
    return 'text-error'
  }

  render() {
    super.render()
    this._bindInteractions()
  }

  _bindInteractions() {
    // Group expand/collapse
    this.container.querySelectorAll('.group-header').forEach(header => {
      header.addEventListener('click', (e) => {
        const groupId = header.dataset.groupId
        if (this.expandedGroups.has(groupId)) {
          this.expandedGroups.delete(groupId)
        } else {
          this.expandedGroups.add(groupId)
        }
        this.render()
      })
    })

    // Target selection
    this.container.querySelectorAll('.target-dot').forEach(dot => {
      dot.addEventListener('click', (e) => {
        e.stopPropagation()
        const targetId = dot.dataset.targetId
        this.selectedTargetId = targetId

        // Dispatch selection event
        const event = new CustomEvent("widget:target_selected", {
          detail: {
            widgetId: this.id,
            targetId: targetId
          },
          bubbles: true
        })
        this.container.dispatchEvent(event)

        this.render()
      })
    })
  }

  // Called by external code to update fleet data
  updateFleetData(groups) {
    this.groups = groups
    this.render()
  }

  // Set selected target (from external selection)
  setSelectedTarget(targetId) {
    this.selectedTargetId = targetId
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
registerWidget("fleet_health", FleetHealthWidget)

export default FleetHealthWidget
