/**
 * DAG Editor Hook
 *
 * A fully client-side DAG procedure editor. LiveView only handles:
 * - Initial data load (via data attributes)
 * - Save to database (via pushEvent)
 *
 * All UI state is managed here: zoom, pan, selection, modals, text editor visibility.
 */

import dagre from 'dagre'

// Import shared constants and utilities
import {
  NODE_WIDTH,
  NODE_HEIGHT,
  NODE_MARGIN,
  TYPE_ICONS,
  STEP_TYPES,
  INPUT_TYPES
} from '../dag/constants.js'
import { escapeHtml, truncate, getStepSummary } from '../dag/utils.js'

export const DagEditorHook = {
  mounted() {
    // Load initial data from LiveView
    this.steps = JSON.parse(this.el.dataset.steps || '{}')
    this.inputs = JSON.parse(this.el.dataset.inputs || '{}')
    this.onStepFailure = this.el.dataset.onStepFailure || 'abort'
    this.procedureName = this.el.dataset.procedureName || ''
    this.procedureId = this.el.dataset.procedureId || null
    this.missionUrl = this.el.dataset.missionUrl || '/'
    this.saving = this.el.dataset.saving === 'true'

    // UI State (all client-side)
    this.zoom = 1.0
    this.panX = 50
    this.panY = 50
    this.selectedStep = null
    this.selectedInput = null
    this.showTextEditor = false
    this.showInputsPanel = false
    this.showAddModal = false
    this.showAddInputModal = false
    this.dirty = false

    // Custom node positions (overrides dagre layout)
    // Format: { stepName: { x, y } }
    this.nodePositions = {}

    // Interaction state
    this.isPanning = false
    this.isDrawingEdge = false
    this.isDraggingNode = false
    this.draggedNode = null
    this.dragStartX = 0
    this.dragStartY = 0
    this.edgeStartNode = null
    this.lastMouseX = 0
    this.lastMouseY = 0
    this.lastFocusedInput = null  // For input reference insertion

    // Render the full UI
    this.render()
  },

  updated() {
    // LiveView may update saving state
    const newSaving = this.el.dataset.saving === 'true'
    if (newSaving !== this.saving) {
      this.saving = newSaving
      this.updateHeader()
    }
  },

  destroyed() {
    // Cleanup
  },

  // ==========================================================================
  // Rendering
  // ==========================================================================

  render() {
    this.el.innerHTML = `
      <div class="dag-editor-container h-full flex flex-col overflow-hidden">
        ${this.renderHeader()}
        <div class="flex-1 relative overflow-hidden">
          ${this.renderCanvas()}
          ${this.renderTextEditor()}
          ${this.renderInputsPanel()}
          ${this.renderSidePanel()}
          ${this.renderToolbar()}
          ${this.renderAddModal()}
          ${this.renderAddInputModal()}
        </div>
      </div>
    `

    this.setupGlobalListeners()
    this.attachEventListeners()
    this.renderCanvasContent()
  },

  renderHeader() {
    return `
      <header class="flex items-center justify-between px-4 py-3 border-b border-base-300 bg-base-200">
        <div class="flex items-center gap-4">
          <a href="${this.missionUrl}" class="btn btn-ghost btn-sm">
            <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/>
            </svg>
          </a>
          <div>
            <h1 class="text-lg font-semibold">
              ${this.procedureId ? `Edit Procedure` : 'New Procedure'}
            </h1>
            <p class="text-xs ${this.dirty ? 'text-warning' : 'text-base-content/50'}">
              ${this.dirty ? 'Unsaved changes' : 'All changes saved'}
            </p>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <input
            type="text"
            id="procedure-name"
            value="${escapeHtml(this.procedureName)}"
            placeholder="Procedure name"
            class="input input-bordered input-sm w-64"
          />
          <div class="divider divider-horizontal mx-1"></div>
          <div class="dropdown dropdown-end">
            <label tabindex="0" class="btn btn-ghost btn-sm gap-1" title="On step failure behavior">
              <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/>
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/>
              </svg>
              Settings
            </label>
            <div tabindex="0" class="dropdown-content z-50 menu p-4 shadow-lg bg-base-100 rounded-box w-72 border border-base-300">
              <div class="space-y-3">
                <div>
                  <label class="label py-1"><span class="label-text text-xs font-medium uppercase tracking-wide">On Step Failure</span></label>
                  <select id="on-step-failure" class="select select-bordered select-sm w-full">
                    <option value="abort" ${this.onStepFailure === 'abort' ? 'selected' : ''}>Abort - Stop entire procedure</option>
                    <option value="continue" ${this.onStepFailure === 'continue' ? 'selected' : ''}>Continue - Run independent branches</option>
                    <option value="pause" ${this.onStepFailure === 'pause' ? 'selected' : ''}>Pause - Wait for operator</option>
                  </select>
                  <p class="text-xs text-base-content/50 mt-1">What happens when a step fails</p>
                </div>
              </div>
            </div>
          </div>
          <button type="button" id="cancel-btn" class="btn btn-ghost btn-sm">Cancel</button>
          <button type="button" id="save-btn" class="btn btn-primary btn-sm" ${this.saving ? 'disabled' : ''}>
            ${this.saving ? 'Saving...' : 'Save'}
          </button>
        </div>
      </header>
    `
  },

  renderCanvas() {
    return `
      <div id="canvas-container" class="absolute inset-0 overflow-hidden bg-base-100">
        <svg id="dag-svg" class="w-full h-full">
          <defs>
            <pattern id="grid" width="20" height="20" patternUnits="userSpaceOnUse">
              <path d="M 20 0 L 0 0 0 20" fill="none" stroke="currentColor" stroke-width="0.5" opacity="0.1"/>
            </pattern>
            <marker id="arrowhead" markerWidth="10" markerHeight="7" refX="9" refY="3.5" orient="auto">
              <polygon points="0 0, 10 3.5, 0 7" fill="currentColor" opacity="0.5"/>
            </marker>
          </defs>
          <g id="canvas-transform">
            <rect x="-10000" y="-10000" width="20000" height="20000" fill="url(#grid)" class="pointer-events-none"/>
            <g id="edges-group"></g>
            <g id="nodes-group"></g>
            <g id="temp-edge-group"></g>
          </g>
        </svg>
      </div>
    `
  },

  renderTextEditor() {
    // Drawer slides in from the right
    const translateClass = this.showTextEditor ? 'translate-x-0' : 'translate-x-full'
    const yaml = this.stepsToYaml()

    return `
      <div id="text-editor-panel" class="absolute top-0 right-0 bottom-0 w-[30%] min-w-80 max-w-md bg-base-100 border-l border-base-300 flex flex-col z-20 transform transition-transform duration-200 ease-out ${translateClass}">
        <div class="flex-none flex items-center justify-between px-3 py-2 border-b border-base-300 bg-base-200">
          <span class="text-sm font-medium">YAML Editor</span>
          <button type="button" id="close-text-editor" class="btn btn-ghost btn-sm btn-square">
            <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
            </svg>
          </button>
        </div>
        <textarea
          id="yaml-editor"
          class="flex-1 min-h-0 w-full p-3 font-mono text-sm bg-base-100 resize-none focus:outline-none border-none overflow-y-auto"
          spellcheck="false"
        >${escapeHtml(yaml)}</textarea>
        <div class="flex-none px-3 py-2 border-t border-base-300 bg-base-200 flex items-center justify-between">
          <span class="text-xs text-base-content/50">Ctrl+Enter to apply</span>
          <button type="button" id="apply-yaml" class="btn btn-xs btn-primary">Apply</button>
        </div>
      </div>
    `
  },

  renderSidePanel() {
    const step = this.selectedStep ? (this.steps[this.selectedStep] || {}) : {}
    const availableDeps = this.selectedStep
      ? Object.keys(this.steps).filter(n => n !== this.selectedStep).sort()
      : []
    const currentDeps = step.depends_on || []

    // Drawer slides in from the right, always rendered but translated off-screen when closed
    const isOpen = this.selectedStep !== null
    const translateClass = isOpen ? 'translate-x-0' : 'translate-x-full'

    return `
      <div id="side-panel" class="absolute top-0 right-0 bottom-0 w-80 bg-base-100 border-l border-base-300 flex flex-col z-20 transform transition-transform duration-200 ease-out ${translateClass}">
        <div class="flex-none flex items-center justify-between px-4 py-3 border-b border-base-300 bg-base-200">
          <div class="flex items-center gap-2">
            <span class="text-lg">${this.selectedStep ? (TYPE_ICONS[step.type] || '?') : ''}</span>
            <span class="font-medium">${escapeHtml(this.selectedStep || '')}</span>
          </div>
          <button type="button" id="close-side-panel" class="btn btn-ghost btn-sm btn-square">
            <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
            </svg>
          </button>
        </div>

        ${this.selectedStep ? `
        <div class="flex-1 min-h-0 overflow-y-auto p-4">
          <div class="space-y-4">
            <!-- Step Name -->
            <div>
              <label class="label py-1"><span class="label-text text-xs font-medium uppercase tracking-wide text-base-content/60">Name</span></label>
              <input
                type="text"
                id="step-name"
                value="${escapeHtml(this.selectedStep)}"
                class="input input-bordered input-sm w-full"
              />
            </div>

            <!-- Step Type -->
            <div>
              <label class="label py-1"><span class="label-text text-xs font-medium uppercase tracking-wide text-base-content/60">Type</span></label>
              <select id="step-type" class="select select-bordered select-sm w-full">
                ${STEP_TYPES.map(t => `
                  <option value="${t.type}" ${step.type === t.type ? 'selected' : ''}>${t.icon} ${t.type}</option>
                `).join('')}
              </select>
            </div>

            <!-- Type-specific fields -->
            <div id="step-config" class="space-y-3 pt-3 border-t border-base-300">
              <div class="text-xs font-medium uppercase tracking-wide text-base-content/60 mb-2">Configuration</div>
              ${this.renderStepConfigFields(step)}
            </div>

            <!-- Dependencies -->
            <div class="pt-3 border-t border-base-300">
              <label class="label py-1"><span class="label-text text-xs font-medium uppercase tracking-wide text-base-content/60">Depends On</span></label>
              ${availableDeps.length === 0 ? `
                <p class="text-xs text-base-content/50 italic">No other steps available</p>
              ` : `
                <div class="flex flex-wrap gap-2 mt-1">
                  ${availableDeps.map(dep => `
                    <label class="flex items-center gap-1.5 cursor-pointer px-2 py-1 rounded-md hover:bg-base-200 transition-colors">
                      <input
                        type="checkbox"
                        class="step-dep-checkbox checkbox checkbox-xs checkbox-primary"
                        data-dep="${dep}"
                        ${currentDeps.includes(dep) ? 'checked' : ''}
                      />
                      <span class="text-xs">${escapeHtml(dep)}</span>
                    </label>
                  `).join('')}
                </div>
              `}
            </div>

            <!-- Available Inputs -->
            ${this.renderAvailableInputsHint()}
          </div>
        </div>

        <div class="flex-none p-4 border-t border-base-300 bg-base-200/50">
          <button type="button" id="delete-step" class="btn btn-outline btn-error btn-sm w-full gap-2">
            <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
            </svg>
            Delete Step
          </button>
        </div>
        ` : ''}
      </div>
    `
  },

  renderInputsPanel() {
    // Drawer slides in from the left
    const translateClass = this.showInputsPanel ? 'translate-x-0' : '-translate-x-full'
    const inputNames = Object.keys(this.inputs).sort()

    return `
      <div id="inputs-panel" class="absolute top-0 left-0 bottom-0 w-80 bg-base-100 border-r border-base-300 flex flex-col z-20 transform transition-transform duration-200 ease-out ${translateClass}">
        <div class="flex-none flex items-center justify-between px-4 py-3 border-b border-base-300 bg-base-200">
          <span class="font-medium">Procedure Inputs</span>
          <button type="button" id="close-inputs-panel" class="btn btn-ghost btn-sm btn-square">
            <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/>
            </svg>
          </button>
        </div>

        <div class="flex-1 min-h-0 overflow-y-auto p-4">
          ${inputNames.length === 0 ? `
            <div class="text-center text-base-content/50 py-8">
              <svg class="w-12 h-12 mx-auto mb-3 opacity-30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4 6h16M4 12h16m-7 6h7"/>
              </svg>
              <p class="text-sm">No inputs defined</p>
              <p class="text-xs mt-1">Inputs allow procedures to accept values at runtime</p>
            </div>
          ` : `
            <div class="space-y-2">
              ${inputNames.map(name => this.renderInputItem(name, this.inputs[name])).join('')}
            </div>
          `}
        </div>

        <div class="flex-none p-4 border-t border-base-300 bg-base-200/50">
          <button type="button" id="add-input-btn" class="btn btn-primary btn-sm w-full gap-2">
            <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
            </svg>
            Add Input
          </button>
        </div>
      </div>
    `
  },

  renderInputItem(name, input) {
    const isSelected = this.selectedInput === name
    const typeLabel = INPUT_TYPES.find(t => t.type === input.type)?.label || input.type

    return `
      <div class="border rounded-lg p-3 cursor-pointer transition-colors ${isSelected ? 'border-primary bg-primary/5' : 'border-base-300 hover:border-base-content/30'}"
           data-input="${name}">
        <div class="flex items-start justify-between gap-2">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              <code class="text-sm font-semibold">${escapeHtml(name)}</code>
              ${input.required !== false ? '<span class="badge badge-xs badge-error">required</span>' : ''}
            </div>
            <div class="text-xs text-base-content/60 mt-1">${typeLabel}</div>
            ${input.description ? `<div class="text-xs text-base-content/50 mt-1 truncate">${escapeHtml(input.description)}</div>` : ''}
          </div>
          <button type="button" class="btn btn-ghost btn-xs btn-square delete-input-btn" data-input="${name}">
            <svg class="h-3 w-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
            </svg>
          </button>
        </div>
        ${input.default !== undefined ? `
          <div class="mt-2 text-xs">
            <span class="text-base-content/50">Default:</span>
            <code class="ml-1">${escapeHtml(JSON.stringify(input.default))}</code>
          </div>
        ` : ''}
        ${input.enum ? `
          <div class="mt-2 text-xs">
            <span class="text-base-content/50">Options:</span>
            <span class="ml-1">${input.enum.map(v => `<code>${escapeHtml(v)}</code>`).join(', ')}</span>
          </div>
        ` : ''}
      </div>
    `
  },

  renderAddInputModal() {
    if (!this.showAddInputModal) return ''

    return `
      <div id="add-input-modal-backdrop" class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
        <div id="add-input-modal" class="bg-base-100 rounded-lg shadow-xl w-full max-w-md">
          <div class="flex items-center justify-between px-4 py-3 border-b border-base-300">
            <h3 class="font-semibold">Add Input</h3>
            <button type="button" id="close-add-input-modal" class="btn btn-ghost btn-sm btn-square">
              <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
              </svg>
            </button>
          </div>

          <div class="p-4 space-y-4">
            <div>
              <label class="label py-1"><span class="label-text text-xs font-medium">Name</span></label>
              <input type="text" id="new-input-name" class="input input-bordered input-sm w-full font-mono"
                     placeholder="my_input" pattern="[a-z_][a-z0-9_]*"/>
              <div class="label py-1"><span class="label-text-alt text-xs">Lowercase letters, numbers, and underscores</span></div>
            </div>

            <div>
              <label class="label py-1"><span class="label-text text-xs font-medium">Type</span></label>
              <select id="new-input-type" class="select select-bordered select-sm w-full">
                ${INPUT_TYPES.map(t => `<option value="${t.type}">${t.label}</option>`).join('')}
              </select>
            </div>

            <div>
              <label class="label py-1"><span class="label-text text-xs font-medium">Description</span></label>
              <input type="text" id="new-input-description" class="input input-bordered input-sm w-full"
                     placeholder="What this input is used for"/>
            </div>

            <div class="flex items-center gap-4">
              <label class="label cursor-pointer gap-2">
                <input type="checkbox" id="new-input-required" class="checkbox checkbox-sm" checked/>
                <span class="label-text text-sm">Required</span>
              </label>
            </div>

            <div>
              <label class="label py-1"><span class="label-text text-xs font-medium">Default Value</span></label>
              <input type="text" id="new-input-default" class="input input-bordered input-sm w-full"
                     placeholder="Leave empty for no default"/>
              <div class="label py-1"><span class="label-text-alt text-xs">For non-required inputs or to provide a sensible default</span></div>
            </div>

            <div class="flex justify-end gap-2 pt-2">
              <button type="button" id="cancel-add-input-modal" class="btn btn-ghost">Cancel</button>
              <button type="button" id="confirm-add-input" class="btn btn-primary">Add Input</button>
            </div>
          </div>
        </div>
      </div>
    `
  },

  renderStepConfigFields(step) {
    const type = step.type || 'log'

    switch (type) {
      case 'command':
        return `
          <div>
            <label class="label py-1"><span class="label-text text-xs">Command Name</span></label>
            <input type="text" id="cfg-command-name" value="${escapeHtml(step.name || '')}"
                   class="input input-bordered input-sm w-full font-mono" placeholder="ENABLE_HEATER"/>
          </div>
          <div>
            <label class="label py-1"><span class="label-text text-xs">Arguments (JSON)</span></label>
            <textarea id="cfg-args" class="textarea textarea-bordered textarea-sm w-full font-mono" rows="2"
                      placeholder='{"zone": 1}'>${step.args ? JSON.stringify(step.args) : ''}</textarea>
          </div>
        `

      case 'wait':
        return `
          <div>
            <label class="label py-1"><span class="label-text text-xs">Duration (ms)</span></label>
            <input type="text" id="cfg-duration" value="${escapeHtml(String(step.duration || 1000))}"
                   class="input input-bordered input-sm w-full font-mono" placeholder="1000 or \${input.name}"/>
          </div>
        `

      case 'wait_for':
        return `
          <div>
            <label class="label py-1"><span class="label-text text-xs">Telemetry Item</span></label>
            <input type="text" id="cfg-item" value="${escapeHtml(step.item || '')}"
                   class="input input-bordered input-sm w-full font-mono" placeholder="THERMAL.temp"/>
          </div>
          <div class="grid grid-cols-2 gap-2">
            <div>
              <label class="label py-1"><span class="label-text text-xs">Operator</span></label>
              <select id="cfg-operator" class="select select-bordered select-sm w-full">
                ${['==', '!=', '>', '>=', '<', '<='].map(op => `
                  <option value="${op}" ${step.operator === op ? 'selected' : ''}>${op}</option>
                `).join('')}
              </select>
            </div>
            <div>
              <label class="label py-1"><span class="label-text text-xs">Value</span></label>
              <input type="text" id="cfg-value" value="${escapeHtml(String(step.value || ''))}"
                     class="input input-bordered input-sm w-full"/>
            </div>
          </div>
          <div>
            <label class="label py-1"><span class="label-text text-xs">Timeout (ms)</span></label>
            <input type="text" id="cfg-timeout" value="${escapeHtml(String(step.timeout || 30000))}"
                   class="input input-bordered input-sm w-full font-mono" placeholder="30000 or \${input.name}"/>
          </div>
        `

      case 'check':
        return `
          <div>
            <label class="label py-1"><span class="label-text text-xs">Condition</span></label>
            <input type="text" id="cfg-condition" value="${escapeHtml(step.condition || '')}"
                   class="input input-bordered input-sm w-full font-mono" placeholder="voltage >= 24"/>
          </div>
          <div>
            <label class="label py-1"><span class="label-text text-xs">On Failure</span></label>
            <select id="cfg-on-fail" class="select select-bordered select-sm w-full">
              ${['abort', 'skip', 'warn'].map(v => `
                <option value="${v}" ${step.on_fail === v ? 'selected' : ''}>${v}</option>
              `).join('')}
            </select>
          </div>
          <div>
            <label class="label py-1"><span class="label-text text-xs">Message</span></label>
            <input type="text" id="cfg-message" value="${escapeHtml(step.message || '')}"
                   class="input input-bordered input-sm w-full"/>
          </div>
        `

      case 'assert':
        return `
          <div>
            <label class="label py-1"><span class="label-text text-xs">Condition</span></label>
            <input type="text" id="cfg-condition" value="${escapeHtml(step.condition || '')}"
                   class="input input-bordered input-sm w-full font-mono" placeholder="mode != FAULT"/>
          </div>
          <div>
            <label class="label py-1"><span class="label-text text-xs">Message</span></label>
            <input type="text" id="cfg-message" value="${escapeHtml(step.message || '')}"
                   class="input input-bordered input-sm w-full"/>
          </div>
        `

      case 'log':
        return `
          <div>
            <label class="label py-1"><span class="label-text text-xs">Level</span></label>
            <select id="cfg-level" class="select select-bordered select-sm w-full">
              ${['debug', 'info', 'warn', 'error'].map(v => `
                <option value="${v}" ${(step.level || 'info') === v ? 'selected' : ''}>${v}</option>
              `).join('')}
            </select>
          </div>
          <div>
            <label class="label py-1"><span class="label-text text-xs">Message</span></label>
            <input type="text" id="cfg-message" value="${escapeHtml(step.message || '')}"
                   class="input input-bordered input-sm w-full" placeholder="Starting procedure..."/>
          </div>
        `

      case 'set':
        return `
          <div>
            <label class="label py-1"><span class="label-text text-xs">Variable Name</span></label>
            <input type="text" id="cfg-var-name" value="${escapeHtml(step.name || '')}"
                   class="input input-bordered input-sm w-full" placeholder="result"/>
          </div>
          <div>
            <label class="label py-1"><span class="label-text text-xs">Value</span></label>
            <input type="text" id="cfg-value" value="${escapeHtml(String(step.value || ''))}"
                   class="input input-bordered input-sm w-full" placeholder="telemetry.item"/>
          </div>
        `

      case 'branch':
        return `
          <div>
            <label class="label py-1"><span class="label-text text-xs">Condition</span></label>
            <input type="text" id="cfg-condition" value="${escapeHtml(step.condition || '')}"
                   class="input input-bordered input-sm w-full font-mono" placeholder="status == SAFE"/>
          </div>
          <div>
            <label class="label py-1"><span class="label-text text-xs">Go To (if true)</span></label>
            <input type="text" id="cfg-goto" value="${escapeHtml(step.goto || '')}"
                   class="input input-bordered input-sm w-full" placeholder="step_name"/>
          </div>
          <div>
            <label class="label py-1"><span class="label-text text-xs">Else Go To</span></label>
            <input type="text" id="cfg-else-goto" value="${escapeHtml(step.else_goto || '')}"
                   class="input input-bordered input-sm w-full" placeholder="(optional)"/>
          </div>
        `

      case 'label':
        return `
          <div>
            <label class="label py-1"><span class="label-text text-xs">Label Name</span></label>
            <input type="text" id="cfg-label-name" value="${escapeHtml(step.name || '')}"
                   class="input input-bordered input-sm w-full" placeholder="handler_name"/>
          </div>
        `

      default:
        return '<p class="text-sm text-base-content/50">Unknown step type</p>'
    }
  },

  renderAvailableInputsHint() {
    const inputNames = Object.keys(this.inputs).sort()

    if (inputNames.length === 0) {
      return ''
    }

    return `
      <div class="pt-3 border-t border-base-300">
        <label class="label py-1">
          <span class="label-text text-xs font-medium uppercase tracking-wide text-base-content/60">Available Inputs</span>
        </label>
        <p class="text-xs text-base-content/50 mb-2">
          Use <code class="bg-base-200 px-1 rounded">\${input.name}</code> in text fields
        </p>
        <div class="flex flex-wrap gap-1">
          ${inputNames.map(name => {
            const input = this.inputs[name]
            const typeLabel = INPUT_TYPES.find(t => t.type === input.type)?.label || input.type
            return `
              <button type="button"
                      class="input-ref-btn badge badge-sm badge-outline gap-1 cursor-pointer hover:badge-primary transition-colors"
                      data-input-name="${name}"
                      title="${typeLabel}${input.description ? ': ' + input.description : ''}">
                ${name}
              </button>
            `
          }).join('')}
        </div>
      </div>
    `
  },

  renderToolbar() {
    const hasCustomPositions = Object.keys(this.nodePositions).length > 0
    const inputCount = Object.keys(this.inputs).length

    return `
      <div id="toolbar" class="absolute bottom-6 left-1/2 -translate-x-1/2 flex items-center gap-1 bg-base-100 rounded-lg shadow-lg border border-base-300 p-1 z-30">
        <button type="button" id="add-step-btn" class="btn btn-primary btn-sm">
          <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
          </svg>
          Add
        </button>
        <div class="w-px h-6 bg-base-300 mx-1"></div>
        <button type="button" id="zoom-out-btn" class="btn btn-ghost btn-sm btn-square" ${this.zoom <= 0.25 ? 'disabled' : ''}>
          <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 12H4"/>
          </svg>
        </button>
        <span id="zoom-level" class="text-sm w-12 text-center">${Math.round(this.zoom * 100)}%</span>
        <button type="button" id="zoom-in-btn" class="btn btn-ghost btn-sm btn-square" ${this.zoom >= 2.0 ? 'disabled' : ''}>
          <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
          </svg>
        </button>
        <div class="w-px h-6 bg-base-300 mx-1"></div>
        <button type="button" id="fit-view-btn" class="btn btn-ghost btn-sm btn-square" title="Fit to view">
          <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4"/>
          </svg>
        </button>
        <button type="button" id="auto-layout-btn" class="btn btn-ghost btn-sm btn-square ${hasCustomPositions ? '' : 'btn-disabled'}" title="Reset to auto layout">
          <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
          </svg>
        </button>
        <div class="w-px h-6 bg-base-300 mx-1"></div>
        <button type="button" id="toggle-inputs-btn" class="btn btn-sm ${this.showInputsPanel ? 'btn-active' : 'btn-ghost'}" title="Procedure inputs">
          <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16m-7 6h7"/>
          </svg>
          ${inputCount > 0 ? `<span class="badge badge-sm badge-primary">${inputCount}</span>` : ''}
        </button>
        <button type="button" id="toggle-text-btn" class="btn btn-sm btn-square ${this.showTextEditor ? 'btn-active' : 'btn-ghost'}" title="Toggle YAML editor">
          <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4"/>
          </svg>
        </button>
      </div>
    `
  },

  renderAddModal() {
    if (!this.showAddModal) return ''

    return `
      <div id="add-modal-backdrop" class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
        <div id="add-modal" class="bg-base-100 rounded-lg shadow-xl w-full max-w-md">
          <div class="flex items-center justify-between px-4 py-3 border-b border-base-300">
            <h3 class="font-semibold">Add Step</h3>
            <button type="button" id="close-add-modal" class="btn btn-ghost btn-sm btn-square">
              <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
              </svg>
            </button>
          </div>
          <div class="p-4 space-y-4">
            <div>
              <label class="label py-1"><span class="label-text">Step Name</span></label>
              <input type="text" id="new-step-name" placeholder="${this.generateStepName()}"
                     class="input input-bordered w-full"/>
            </div>
            <div>
              <label class="label py-1"><span class="label-text">Type</span></label>
              <div class="grid grid-cols-3 gap-2">
                ${STEP_TYPES.map((t, i) => `
                  <label class="cursor-pointer">
                    <input type="radio" name="new-step-type" value="${t.type}" class="hidden peer" ${i === 0 ? 'checked' : ''}/>
                    <div class="flex flex-col items-center p-3 rounded-lg border-2 border-base-300 peer-checked:border-primary peer-checked:bg-primary/5 hover:bg-base-200 transition-colors">
                      <span class="text-xl">${t.icon}</span>
                      <span class="text-xs mt-1">${t.label}</span>
                    </div>
                  </label>
                `).join('')}
              </div>
            </div>
            <div class="flex justify-end gap-2 pt-2">
              <button type="button" id="cancel-add-modal" class="btn btn-ghost">Cancel</button>
              <button type="button" id="confirm-add-step" class="btn btn-primary">Add Step</button>
            </div>
          </div>
        </div>
      </div>
    `
  },

  // ==========================================================================
  // Canvas Rendering
  // ==========================================================================

  renderCanvasContent() {
    const nodesGroup = document.getElementById('nodes-group')
    const edgesGroup = document.getElementById('edges-group')
    if (!nodesGroup || !edgesGroup) return

    const stepCount = Object.keys(this.steps).length

    if (stepCount === 0) {
      nodesGroup.innerHTML = this.renderEmptyState()
      edgesGroup.innerHTML = ''
      this.updateTransform()
      return
    }

    // Get node positions (custom positions merged with dagre defaults)
    const positions = this.getAllNodePositions()

    // Render edges - calculate simple straight lines between nodes
    edgesGroup.innerHTML = ''
    Object.entries(this.steps).forEach(([name, step]) => {
      const deps = step.depends_on || []
      deps.forEach(dep => {
        if (positions[dep] && positions[name]) {
          const fromPos = positions[dep]
          const toPos = positions[name]
          // Draw from bottom of source node to top of target node
          const points = [
            { x: fromPos.x, y: fromPos.y + NODE_HEIGHT / 2 },
            { x: toPos.x, y: toPos.y - NODE_HEIGHT / 2 }
          ]
          edgesGroup.innerHTML += this.renderEdge(dep, name, points)
        }
      })
    })

    // Render nodes using positions
    nodesGroup.innerHTML = ''
    Object.keys(this.steps).forEach(name => {
      const pos = positions[name]
      const step = this.steps[name]
      const nodeData = { x: pos.x, y: pos.y, width: NODE_WIDTH, height: NODE_HEIGHT }
      nodesGroup.innerHTML += this.renderNode(name, nodeData, step)
    })

    this.updateTransform()
    this.attachNodeListeners()
  },

  calculateLayout() {
    const g = new dagre.graphlib.Graph()
    g.setGraph({
      rankdir: 'TB',
      nodesep: NODE_MARGIN,
      ranksep: NODE_MARGIN * 1.5,
      marginx: NODE_MARGIN,
      marginy: NODE_MARGIN
    })
    g.setDefaultEdgeLabel(() => ({}))

    Object.keys(this.steps).forEach(name => {
      g.setNode(name, { width: NODE_WIDTH, height: NODE_HEIGHT })
    })

    Object.entries(this.steps).forEach(([name, step]) => {
      const deps = step.depends_on || []
      deps.forEach(dep => {
        if (this.steps[dep]) {
          g.setEdge(dep, name)
        }
      })
    })

    dagre.layout(g)
    return g
  },

  renderEmptyState() {
    return `
      <foreignObject x="0" y="0" width="400" height="200">
        <div xmlns="http://www.w3.org/1999/xhtml" class="flex items-center justify-center h-full text-base-content/50">
          <div class="text-center">
            <svg class="w-16 h-16 mx-auto mb-4 opacity-30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"
                    d="M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM4 13a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H5a1 1 0 01-1-1v-6zM16 13a1 1 0 011-1h2a1 1 0 011 1v6a1 1 0 01-1 1h-2a1 1 0 01-1-1v-6z"/>
            </svg>
            <p class="text-lg">No steps yet</p>
            <p class="text-sm mt-1">Click "Add" to create your first step</p>
          </div>
        </div>
      </foreignObject>
    `
  },

  renderEdge(from, to, points) {
    if (!points || points.length < 2) return ''

    const start = points[0]
    const end = points[points.length - 1]

    // Calculate control points for a smooth bezier curve
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

    const d = `M ${start.x} ${start.y} C ${cp1x} ${cp1y}, ${cp2x} ${cp2y}, ${end.x} ${end.y}`

    return `<path d="${d}" fill="none" stroke="currentColor" stroke-width="2" opacity="0.4" marker-end="url(#arrowhead)" class="transition-opacity hover:opacity-70"/>`
  },

  renderNode(name, node, step) {
    const isSelected = name === this.selectedStep
    const hasErrors = this.validateStep(step).length > 0
    const type = step.type || 'unknown'
    const icon = TYPE_ICONS[type] || '?'

    const x = node.x - NODE_WIDTH / 2
    const y = node.y - NODE_HEIGHT / 2

    let strokeClass = 'stroke-base-content/30'
    let fillClass = 'fill-base-100'
    let filter = ''

    if (hasErrors) {
      strokeClass = 'stroke-error'
      fillClass = 'fill-error/5'
      filter = 'filter: drop-shadow(0 0 6px rgba(239,68,68,0.5));'
    } else if (isSelected) {
      strokeClass = 'stroke-primary'
      fillClass = 'fill-primary/5'
      filter = 'filter: drop-shadow(0 0 6px rgba(99,102,241,0.5));'
    }

    return `
      <g data-node="${name}" class="cursor-grab" style="${filter}">
        <rect x="${x}" y="${y}" width="${NODE_WIDTH}" height="${NODE_HEIGHT}" rx="8"
              class="${fillClass} ${strokeClass}" stroke-width="2"/>
        <text x="${x + 24}" y="${node.y + 5}" text-anchor="middle"
              class="fill-current text-lg pointer-events-none select-none">${icon}</text>
        <text x="${x + 50}" y="${node.y - 8}"
              class="fill-current text-sm font-medium pointer-events-none select-none">${truncate(name, 16)}</text>
        <text x="${x + 50}" y="${node.y + 10}"
              class="fill-current/60 text-xs pointer-events-none select-none">${getStepSummary(step)}</text>
        ${hasErrors ? `
          <circle cx="${x + NODE_WIDTH - 12}" cy="${y + 12}" r="6" class="fill-error"/>
          <text x="${x + NODE_WIDTH - 12}" y="${y + 16}" text-anchor="middle" class="fill-error-content text-xs pointer-events-none">!</text>
        ` : ''}
        <circle cx="${node.x}" cy="${y + NODE_HEIGHT}" r="6"
                class="fill-base-100 stroke-base-content/30 stroke-2 cursor-crosshair hover:fill-primary hover:stroke-primary transition-colors"
                data-handle="${name}"/>
      </g>
    `
  },

  // ==========================================================================
  // Event Handling
  // ==========================================================================

  setupGlobalListeners() {
    const container = document.getElementById('canvas-container')
    if (container) {
      container.addEventListener('mousedown', (e) => this.handleCanvasMouseDown(e))
      container.addEventListener('mousemove', (e) => this.handleCanvasMouseMove(e))
      container.addEventListener('mouseup', (e) => this.handleCanvasMouseUp(e))
      container.addEventListener('mouseleave', (e) => this.handleCanvasMouseUp(e))
      container.addEventListener('wheel', (e) => this.handleWheel(e), { passive: false })
    }
  },

  attachEventListeners() {
    // Header
    this.on('#cancel-btn', 'click', () => this.pushEvent('cancel', {}))
    this.on('#save-btn', 'click', () => this.save())
    this.on('#procedure-name', 'input', (e) => {
      this.procedureName = e.target.value
      this.dirty = true
      this.updateHeader()
    })
    this.on('#on-step-failure', 'change', (e) => {
      this.onStepFailure = e.target.value
      this.dirty = true
      this.updateHeader()
    })

    // Toolbar
    this.on('#add-step-btn', 'click', () => this.openAddModal())
    this.on('#zoom-out-btn', 'click', () => this.setZoom(this.zoom - 0.25))
    this.on('#zoom-in-btn', 'click', () => this.setZoom(this.zoom + 0.25))
    this.on('#fit-view-btn', 'click', () => this.fitToView())
    this.on('#auto-layout-btn', 'click', () => this.resetLayout())
    this.on('#toggle-inputs-btn', 'click', () => this.toggleInputsPanel())
    this.on('#toggle-text-btn', 'click', () => this.toggleTextEditor())

    // Text editor
    this.on('#close-text-editor', 'click', () => this.toggleTextEditor())
    this.on('#apply-yaml', 'click', () => this.applyYaml())
    this.on('#yaml-editor', 'keydown', (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
        e.preventDefault()
        this.applyYaml()
      }
      if (e.key === 'Tab') {
        e.preventDefault()
        const ta = e.target
        const start = ta.selectionStart
        const end = ta.selectionEnd
        ta.value = ta.value.substring(0, start) + '  ' + ta.value.substring(end)
        ta.selectionStart = ta.selectionEnd = start + 2
      }
    })

    // Side panel (initial attachment - also called separately when panel updates)
    this.attachSidePanelListeners()

    // Inputs panel
    this.on('#close-inputs-panel', 'click', () => this.toggleInputsPanel())
    this.on('#add-input-btn', 'click', () => this.openAddInputModal())
    this.attachInputsPanelListeners()

    // Add step modal
    this.on('#add-modal-backdrop', 'click', (e) => {
      if (e.target.id === 'add-modal-backdrop') this.closeAddModal()
    })
    this.on('#close-add-modal', 'click', () => this.closeAddModal())
    this.on('#cancel-add-modal', 'click', () => this.closeAddModal())
    this.on('#confirm-add-step', 'click', () => this.confirmAddStep())

    // Add input modal
    this.on('#add-input-modal-backdrop', 'click', (e) => {
      if (e.target.id === 'add-input-modal-backdrop') this.closeAddInputModal()
    })
    this.on('#close-add-input-modal', 'click', () => this.closeAddInputModal())
    this.on('#cancel-add-input-modal', 'click', () => this.closeAddInputModal())
    this.on('#confirm-add-input', 'click', () => this.confirmAddInput())
  },

  attachInputsPanelListeners() {
    // Delete input buttons
    document.querySelectorAll('.delete-input-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation()
        const name = btn.dataset.input
        if (confirm(`Delete input "${name}"?`)) {
          this.deleteInput(name)
        }
      })
    })

    // Input item selection (for future editing)
    document.querySelectorAll('[data-input]').forEach(item => {
      if (!item.classList.contains('delete-input-btn')) {
        item.addEventListener('click', (e) => {
          if (!e.target.closest('.delete-input-btn')) {
            this.selectedInput = item.dataset.input
            this.updateInputsPanel()
          }
        })
      }
    })
  },

  attachNodeListeners() {
    // Node click/drag is now handled in handleCanvasMouseDown/Up
    // This is kept for any additional node-specific listeners we might need
  },

  on(selector, event, handler) {
    const el = document.querySelector(selector)
    if (el) el.addEventListener(event, handler)
  },

  handleCanvasMouseDown(e) {
    const handle = e.target.closest('[data-handle]')
    const node = e.target.closest('[data-node]')

    if (handle) {
      // Starting to draw an edge from the connection handle
      this.isDrawingEdge = true
      this.edgeStartNode = handle.dataset.handle
      e.preventDefault()
    } else if (node) {
      // Starting to drag a node
      this.isDraggingNode = true
      this.draggedNode = node.dataset.node
      this.lastMouseX = e.clientX
      this.lastMouseY = e.clientY

      // Get current position of this node
      const nodePos = this.getNodePosition(this.draggedNode)
      this.dragStartX = nodePos.x
      this.dragStartY = nodePos.y

      e.currentTarget.style.cursor = 'grabbing'
      e.preventDefault()
    } else {
      // Panning the canvas
      this.isPanning = true
      this.lastMouseX = e.clientX
      this.lastMouseY = e.clientY
      e.currentTarget.style.cursor = 'grabbing'
    }
  },

  handleCanvasMouseMove(e) {
    if (this.isPanning) {
      const dx = e.clientX - this.lastMouseX
      const dy = e.clientY - this.lastMouseY
      this.panX += dx
      this.panY += dy
      this.lastMouseX = e.clientX
      this.lastMouseY = e.clientY
      this.updateTransform()
    } else if (this.isDraggingNode && this.draggedNode) {
      // Calculate delta in screen space, then convert to canvas space
      const dx = (e.clientX - this.lastMouseX) / this.zoom
      const dy = (e.clientY - this.lastMouseY) / this.zoom
      this.lastMouseX = e.clientX
      this.lastMouseY = e.clientY

      // Update the node's custom position
      const currentPos = this.getNodePosition(this.draggedNode)
      this.nodePositions[this.draggedNode] = {
        x: currentPos.x + dx,
        y: currentPos.y + dy
      }

      // Re-render just the nodes and edges (not full render to keep it smooth)
      this.renderCanvasContent()
    } else if (this.isDrawingEdge) {
      this.renderTempEdge(e)
    }
  },

  handleCanvasMouseUp(e) {
    const container = document.getElementById('canvas-container')

    if (this.isPanning) {
      this.isPanning = false
      if (container) container.style.cursor = ''
    }

    if (this.isDraggingNode) {
      // Check if this was a click (no significant movement) vs a drag
      const nodePos = this.getNodePosition(this.draggedNode)
      const dragDistance = Math.abs(nodePos.x - this.dragStartX) + Math.abs(nodePos.y - this.dragStartY)

      if (dragDistance < 5) {
        // This was a click, not a drag - select the node
        this.selectStep(this.draggedNode)
      } else {
        // This was a drag - mark as dirty since positions changed
        this.dirty = true
        this.updateHeader()
      }

      this.isDraggingNode = false
      this.draggedNode = null
      if (container) container.style.cursor = ''
    }

    if (this.isDrawingEdge) {
      // Find which node we're over by checking mouse position against node bounds
      const targetNode = this.findNodeAtPosition(e)
      if (targetNode && targetNode !== this.edgeStartNode) {
        this.addDependency(targetNode, this.edgeStartNode)
      }
      this.isDrawingEdge = false
      this.edgeStartNode = null
      this.clearTempEdge()
    }
  },

  // Find which node (if any) is at the given mouse position
  findNodeAtPosition(e) {
    const svg = document.getElementById('dag-svg')
    if (!svg) return null

    const rect = svg.getBoundingClientRect()
    const mouseX = (e.clientX - rect.left - this.panX) / this.zoom
    const mouseY = (e.clientY - rect.top - this.panY) / this.zoom

    const positions = this.getAllNodePositions()

    for (const [name, pos] of Object.entries(positions)) {
      const left = pos.x - NODE_WIDTH / 2
      const right = pos.x + NODE_WIDTH / 2
      const top = pos.y - NODE_HEIGHT / 2
      const bottom = pos.y + NODE_HEIGHT / 2

      if (mouseX >= left && mouseX <= right && mouseY >= top && mouseY <= bottom) {
        return name
      }
    }

    return null
  },

  handleWheel(e) {
    e.preventDefault()
    const delta = e.deltaY > 0 ? -0.1 : 0.1
    this.setZoom(this.zoom + delta)
  },

  // ==========================================================================
  // Actions
  // ==========================================================================

  setZoom(level) {
    this.zoom = Math.max(0.25, Math.min(2.0, level))
    this.updateTransform()
    this.updateToolbar()
  },

  updateTransform() {
    const g = document.getElementById('canvas-transform')
    if (g) {
      g.setAttribute('transform', `translate(${this.panX}, ${this.panY}) scale(${this.zoom})`)
    }
  },

  fitToView() {
    const svg = document.getElementById('dag-svg')
    const nodesGroup = document.getElementById('nodes-group')
    if (!svg || !nodesGroup) return

    const bbox = nodesGroup.getBBox()
    if (bbox.width === 0 || bbox.height === 0) return

    const containerWidth = svg.clientWidth
    const containerHeight = svg.clientHeight

    const scaleX = (containerWidth - 100) / bbox.width
    const scaleY = (containerHeight - 100) / bbox.height
    const scale = Math.min(scaleX, scaleY, 1.5)

    this.zoom = scale
    this.panX = (containerWidth - bbox.width * scale) / 2 - bbox.x * scale
    this.panY = (containerHeight - bbox.height * scale) / 2 - bbox.y * scale

    this.updateTransform()
    this.updateToolbar()
  },

  toggleTextEditor() {
    // Close the step editor if open when opening YAML editor
    if (!this.showTextEditor && this.selectedStep) {
      this.saveCurrentStepConfig()
      this.selectedStep = null
      this.updateSidePanel()
      this.renderCanvasContent()
    }

    this.showTextEditor = !this.showTextEditor
    const panel = document.getElementById('text-editor-panel')
    if (panel) {
      if (this.showTextEditor) {
        // Update YAML content when opening
        const textarea = document.getElementById('yaml-editor')
        if (textarea) {
          textarea.value = this.stepsToYaml()
        }
        panel.classList.remove('translate-x-full')
        panel.classList.add('translate-x-0')
      } else {
        panel.classList.remove('translate-x-0')
        panel.classList.add('translate-x-full')
      }
    }
    // Update toolbar button state
    const btn = document.getElementById('toggle-text-btn')
    if (btn) {
      btn.classList.toggle('btn-active', this.showTextEditor)
      btn.classList.toggle('btn-ghost', !this.showTextEditor)
    }
  },

  openAddModal() {
    this.showAddModal = true
    this.render()
  },

  closeAddModal() {
    this.showAddModal = false
    this.render()
  },

  // Inputs Panel Actions
  toggleInputsPanel() {
    // Close the step editor if open when opening inputs panel
    if (!this.showInputsPanel && this.selectedStep) {
      this.saveCurrentStepConfig()
      this.selectedStep = null
      this.updateSidePanel()
      this.renderCanvasContent()
    }

    this.showInputsPanel = !this.showInputsPanel
    const panel = document.getElementById('inputs-panel')
    if (panel) {
      if (this.showInputsPanel) {
        panel.classList.remove('-translate-x-full')
        panel.classList.add('translate-x-0')
      } else {
        panel.classList.remove('translate-x-0')
        panel.classList.add('-translate-x-full')
      }
    }
    // Update toolbar button state
    const btn = document.getElementById('toggle-inputs-btn')
    if (btn) {
      btn.classList.toggle('btn-active', this.showInputsPanel)
      btn.classList.toggle('btn-ghost', !this.showInputsPanel)
    }
  },

  openAddInputModal() {
    this.showAddInputModal = true
    this.render()
    // Focus the name input
    setTimeout(() => {
      const nameInput = document.getElementById('new-input-name')
      if (nameInput) nameInput.focus()
    }, 50)
  },

  closeAddInputModal() {
    this.showAddInputModal = false
    this.render()
  },

  confirmAddInput() {
    const nameInput = document.getElementById('new-input-name')
    const typeSelect = document.getElementById('new-input-type')
    const descInput = document.getElementById('new-input-description')
    const requiredCheckbox = document.getElementById('new-input-required')
    const defaultInput = document.getElementById('new-input-default')

    const name = (nameInput?.value || '').trim()
    const type = typeSelect?.value || 'string'
    const description = (descInput?.value || '').trim()
    const required = requiredCheckbox?.checked ?? true
    const defaultValue = (defaultInput?.value || '').trim()

    // Validate name
    if (!name) {
      alert('Please enter an input name')
      return
    }

    if (!/^[a-z_][a-z0-9_]*$/.test(name)) {
      alert('Input name must start with a letter or underscore and contain only lowercase letters, numbers, and underscores')
      return
    }

    if (this.inputs[name]) {
      alert(`An input named "${name}" already exists`)
      return
    }

    // Build the input definition
    const input = { type }
    if (description) input.description = description
    if (!required) input.required = false

    // Parse default value based on type
    if (defaultValue) {
      input.default = this.parseInputValue(defaultValue, type)
    }

    this.inputs[name] = input
    this.dirty = true
    this.showAddInputModal = false
    this.selectedInput = name
    this.render()
  },

  deleteInput(name) {
    delete this.inputs[name]
    if (this.selectedInput === name) {
      this.selectedInput = null
    }
    this.dirty = true
    this.updateInputsPanel()
    this.updateToolbar()
    this.updateHeader()
  },

  updateInputsPanel() {
    const panel = document.getElementById('inputs-panel')
    if (panel) {
      panel.outerHTML = this.renderInputsPanel()
      // Re-attach event listeners
      this.on('#close-inputs-panel', 'click', () => this.toggleInputsPanel())
      this.on('#add-input-btn', 'click', () => this.openAddInputModal())
      this.attachInputsPanelListeners()
    }
  },

  parseInputValue(value, type) {
    switch (type) {
      case 'number':
        return parseFloat(value) || 0
      case 'integer':
      case 'duration':
        return parseInt(value) || 0
      case 'boolean':
        return value.toLowerCase() === 'true'
      default:
        return value
    }
  },

  confirmAddStep() {
    const nameInput = document.getElementById('new-step-name')
    const typeRadio = document.querySelector('input[name="new-step-type"]:checked')

    const name = (nameInput?.value || '').trim() || this.generateStepName()
    const type = typeRadio?.value || 'command'

    this.steps[name] = this.createDefaultStep(type)
    this.dirty = true
    this.selectedStep = name
    this.showAddModal = false

    this.render()
  },

  selectStep(name) {
    // Save current step config first
    if (this.selectedStep) {
      this.saveCurrentStepConfig()
    }

    // Close YAML editor if open when selecting a step
    if (name && this.showTextEditor) {
      this.showTextEditor = false
      const panel = document.getElementById('text-editor-panel')
      if (panel) {
        panel.classList.remove('translate-x-0')
        panel.classList.add('translate-x-full')
      }
      const btn = document.getElementById('toggle-text-btn')
      if (btn) {
        btn.classList.remove('btn-active')
        btn.classList.add('btn-ghost')
      }
    }

    this.selectedStep = name

    // Update the side panel with animation
    this.updateSidePanel()

    // Update canvas to show selection state
    this.renderCanvasContent()
  },

  updateSidePanel() {
    const panel = document.getElementById('side-panel')
    if (!panel) return

    if (this.selectedStep) {
      // Update panel content
      panel.outerHTML = this.renderSidePanel()
      // Re-attach event listeners for the new panel
      this.attachSidePanelListeners()
    } else {
      // Slide out
      panel.classList.remove('translate-x-0')
      panel.classList.add('translate-x-full')
    }
  },

  attachSidePanelListeners() {
    this.on('#close-side-panel', 'click', () => this.selectStep(null))
    this.on('#delete-step', 'click', () => this.deleteSelectedStep())
    this.on('#step-name', 'change', (e) => this.renameSelectedStep(e.target.value))
    this.on('#step-type', 'change', (e) => this.changeStepType(e.target.value))

    // Side panel config fields - use event delegation
    const sidePanel = document.getElementById('side-panel')
    if (sidePanel) {
      sidePanel.addEventListener('change', (e) => this.handleConfigChange(e))
      sidePanel.addEventListener('input', (e) => {
        if (e.target.matches('input, textarea, select')) {
          this.dirty = true
          this.updateHeader()
        }
      })

      // Track last focused text input for input reference insertion
      sidePanel.addEventListener('focus', (e) => {
        if (e.target.matches('input[type="text"], textarea')) {
          this.lastFocusedInput = e.target
        }
      }, true)

      // Input reference badge clicks - insert reference at cursor
      sidePanel.querySelectorAll('.input-ref-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
          e.preventDefault()
          const inputName = btn.dataset.inputName
          const ref = `\${input.${inputName}}`

          if (this.lastFocusedInput) {
            const input = this.lastFocusedInput
            const start = input.selectionStart || 0
            const end = input.selectionEnd || 0
            const value = input.value

            input.value = value.substring(0, start) + ref + value.substring(end)
            input.selectionStart = input.selectionEnd = start + ref.length
            input.focus()

            // Trigger change events
            input.dispatchEvent(new Event('input', { bubbles: true }))
            this.dirty = true
            this.updateHeader()
          }
        })
      })
    }
  },

  saveCurrentStepConfig() {
    if (!this.selectedStep) return

    const step = this.steps[this.selectedStep]
    if (!step) return

    const type = step.type

    switch (type) {
      case 'command':
        step.name = this.getVal('#cfg-command-name') || ''
        try { step.args = JSON.parse(this.getVal('#cfg-args') || '{}') } catch (e) { step.args = {} }
        break
      case 'wait':
        step.duration = this.parseNumericOrRef(this.getVal('#cfg-duration'), 1000)
        break
      case 'wait_for':
        step.item = this.getVal('#cfg-item') || ''
        step.operator = this.getVal('#cfg-operator') || '=='
        step.value = this.parseValueOrRef(this.getVal('#cfg-value'))
        step.timeout = this.parseNumericOrRef(this.getVal('#cfg-timeout'), 30000)
        break
      case 'check':
        step.condition = this.getVal('#cfg-condition') || ''
        step.on_fail = this.getVal('#cfg-on-fail') || 'abort'
        step.message = this.getVal('#cfg-message') || ''
        break
      case 'assert':
        step.condition = this.getVal('#cfg-condition') || ''
        step.message = this.getVal('#cfg-message') || ''
        break
      case 'log':
        step.level = this.getVal('#cfg-level') || 'info'
        step.message = this.getVal('#cfg-message') || ''
        break
      case 'set':
        step.name = this.getVal('#cfg-var-name') || ''
        step.value = this.getVal('#cfg-value') || ''
        break
      case 'branch':
        step.condition = this.getVal('#cfg-condition') || ''
        step.goto = this.getVal('#cfg-goto') || ''
        step.else_goto = this.getVal('#cfg-else-goto') || null
        break
      case 'label':
        step.name = this.getVal('#cfg-label-name') || ''
        break
    }

    // Update dependencies
    const deps = []
    document.querySelectorAll('.step-dep-checkbox:checked').forEach(cb => {
      deps.push(cb.dataset.dep)
    })
    step.depends_on = deps
  },

  getVal(selector) {
    const el = document.querySelector(selector)
    return el ? el.value : ''
  },

  renameSelectedStep(newName) {
    if (!this.selectedStep || !newName || newName === this.selectedStep) return
    if (this.steps[newName]) {
      alert('A step with that name already exists')
      return
    }

    const step = this.steps[this.selectedStep]
    delete this.steps[this.selectedStep]
    this.steps[newName] = step

    // Update references
    Object.values(this.steps).forEach(s => {
      if (s.depends_on) {
        s.depends_on = s.depends_on.map(d => d === this.selectedStep ? newName : d)
      }
    })

    this.selectedStep = newName
    this.dirty = true
    this.render()
  },

  changeStepType(newType) {
    if (!this.selectedStep) return
    const step = this.steps[this.selectedStep]
    const oldDeps = step.depends_on || []
    this.steps[this.selectedStep] = { ...this.createDefaultStep(newType), depends_on: oldDeps }
    this.dirty = true
    this.render()
  },

  deleteSelectedStep() {
    if (!this.selectedStep) return
    if (!confirm('Are you sure you want to delete this step?')) return

    const name = this.selectedStep
    delete this.steps[name]

    // Remove from dependencies
    Object.values(this.steps).forEach(s => {
      if (s.depends_on) {
        s.depends_on = s.depends_on.filter(d => d !== name)
      }
    })

    this.selectedStep = null
    this.dirty = true
    this.render()
  },

  addDependency(stepName, dependsOn) {
    const step = this.steps[stepName]
    if (!step) return

    if (!step.depends_on) step.depends_on = []
    if (!step.depends_on.includes(dependsOn)) {
      step.depends_on.push(dependsOn)
      this.dirty = true
      this.render()
    }
  },

  handleConfigChange(e) {
    this.saveCurrentStepConfig()
    this.dirty = true
    this.renderCanvasContent()
    this.updateHeader()
  },

  applyYaml() {
    const textarea = document.getElementById('yaml-editor')
    if (!textarea) return

    try {
      const steps = this.parseYaml(textarea.value)
      this.steps = steps
      this.dirty = true
      this.selectedStep = null
      this.render()
    } catch (e) {
      alert('YAML parse error: ' + e.message)
    }
  },

  save() {
    // Save any pending changes
    this.saveCurrentStepConfig()

    const name = document.getElementById('procedure-name')?.value || ''
    if (!name.trim()) {
      alert('Please enter a procedure name')
      return
    }

    this.pushEvent('save', {
      name: name.trim(),
      steps: JSON.stringify(this.steps),
      inputs: JSON.stringify(this.inputs),
      on_step_failure: this.onStepFailure
    })
  },

  // ==========================================================================
  // Helpers
  // ==========================================================================

  generateStepName() {
    const existing = Object.keys(this.steps)
    let n = 1
    while (existing.includes(`step_${n}`)) n++
    return `step_${n}`
  },

  createDefaultStep(type) {
    const base = { type }
    switch (type) {
      case 'command': return { ...base, name: '', args: {} }
      case 'wait': return { ...base, duration: 1000 }
      case 'wait_for': return { ...base, item: '', operator: '==', value: '', timeout: 30000 }
      case 'check': return { ...base, condition: '', on_fail: 'abort', message: '' }
      case 'assert': return { ...base, condition: '', message: '' }
      case 'log': return { ...base, level: 'info', message: '' }
      case 'set': return { ...base, name: '', value: '' }
      case 'branch': return { ...base, condition: '', goto: '', else_goto: null }
      case 'label': return { ...base, name: '' }
      default: return base
    }
  },

  validateStep(step) {
    const errors = []
    const type = step.type

    switch (type) {
      case 'command':
        if (!step.name) errors.push('Command name required')
        break
      case 'wait_for':
        if (!step.item) errors.push('Telemetry item required')
        if (step.value === '' || step.value === undefined) errors.push('Value required')
        break
      case 'check':
      case 'assert':
        if (!step.condition) errors.push('Condition required')
        break
      case 'set':
        if (!step.name) errors.push('Variable name required')
        break
      case 'branch':
        if (!step.condition) errors.push('Condition required')
        if (!step.goto) errors.push('Goto target required')
        break
      case 'label':
        if (!step.name) errors.push('Label name required')
        break
    }
    return errors
  },

  // getStepSummary is imported from ../dag/utils.js

  // Get the position of a node, using custom position if set, otherwise from dagre layout
  getNodePosition(name) {
    if (this.nodePositions[name]) {
      return this.nodePositions[name]
    }
    // Calculate from dagre if no custom position
    const g = this.calculateLayout()
    const node = g.node(name)
    return node ? { x: node.x, y: node.y } : { x: 0, y: 0 }
  },

  // Get all node positions, merging custom positions with dagre layout
  getAllNodePositions() {
    const g = this.calculateLayout()
    const positions = {}

    g.nodes().forEach(name => {
      if (this.nodePositions[name]) {
        positions[name] = this.nodePositions[name]
      } else {
        const node = g.node(name)
        positions[name] = { x: node.x, y: node.y }
      }
    })

    return positions
  },

  // Reset all custom positions (re-apply auto layout)
  resetLayout() {
    this.nodePositions = {}
    this.renderCanvasContent()
  },

  // Check if a string contains an input reference
  hasInputRef(str) {
    return typeof str === 'string' && str.includes('${input.')
  },

  // Parse a value that could be a number or an input reference
  // If it's an input reference, keep as string; otherwise parse as number
  parseNumericOrRef(value, defaultValue) {
    if (!value || value === '') return defaultValue
    if (this.hasInputRef(value)) return value
    const num = parseFloat(value)
    return isNaN(num) ? defaultValue : num
  },

  // Parse a value that could be various types or an input reference
  // Tries to preserve the appropriate type
  parseValueOrRef(value) {
    if (value === '' || value === undefined || value === null) return ''
    if (this.hasInputRef(value)) return value
    // Try to parse as number
    if (/^-?\d+$/.test(value)) return parseInt(value)
    if (/^-?\d+\.\d+$/.test(value)) return parseFloat(value)
    // Check for boolean
    if (value === 'true') return true
    if (value === 'false') return false
    // Keep as string
    return value
  },

  stepsToYaml() {
    let yaml = 'steps:\n'
    Object.entries(this.steps).sort().forEach(([name, step]) => {
      yaml += `  ${name}:\n`
      yaml += `    type: ${step.type}\n`
      Object.entries(step).forEach(([k, v]) => {
        if (k === 'type' || k === 'depends_on') return
        if (v === null || v === undefined || v === '') return
        if (typeof v === 'object') {
          yaml += `    ${k}: ${JSON.stringify(v)}\n`
        } else {
          yaml += `    ${k}: ${v}\n`
        }
      })
      if (step.depends_on && step.depends_on.length > 0) {
        yaml += `    depends_on:\n`
        step.depends_on.forEach(d => {
          yaml += `      - ${d}\n`
        })
      }
    })
    return yaml
  },

  parseYaml(yaml) {
    // Simple YAML parser for our format
    const steps = {}
    const lines = yaml.split('\n')
    let currentStep = null
    let inDeps = false

    for (const line of lines) {
      const trimmed = line.trim()
      if (!trimmed || trimmed.startsWith('#')) continue

      if (trimmed === 'steps:') continue

      const stepMatch = line.match(/^  (\w+):$/)
      if (stepMatch) {
        currentStep = stepMatch[1]
        steps[currentStep] = {}
        inDeps = false
        continue
      }

      if (currentStep) {
        const fieldMatch = line.match(/^    (\w+): (.+)$/)
        if (fieldMatch) {
          const [, key, value] = fieldMatch
          if (key === 'depends_on') {
            inDeps = true
            steps[currentStep].depends_on = []
          } else {
            inDeps = false
            // Try to parse as JSON for objects/arrays
            try {
              steps[currentStep][key] = JSON.parse(value)
            } catch (e) {
              // Parse simple values
              if (value === 'true') steps[currentStep][key] = true
              else if (value === 'false') steps[currentStep][key] = false
              else if (value === 'null') steps[currentStep][key] = null
              else if (/^\d+$/.test(value)) steps[currentStep][key] = parseInt(value)
              else steps[currentStep][key] = value
            }
          }
          continue
        }

        if (inDeps) {
          const depMatch = line.match(/^      - (\w+)$/)
          if (depMatch) {
            steps[currentStep].depends_on.push(depMatch[1])
          }
        }
      }
    }
    return steps
  },

  // truncate and escapeHtml are imported from ../dag/utils.js

  updateHeader() {
    const header = this.el.querySelector('header')
    if (header) {
      header.outerHTML = this.renderHeader()
      this.on('#cancel-btn', 'click', () => this.pushEvent('cancel', {}))
      this.on('#save-btn', 'click', () => this.save())
      this.on('#procedure-name', 'input', (e) => {
        this.procedureName = e.target.value
        this.dirty = true
        this.updateHeader()
      })
      this.on('#on-step-failure', 'change', (e) => {
        this.onStepFailure = e.target.value
        this.dirty = true
        this.updateHeader()
      })
    }
  },

  updateToolbar() {
    const zoomLevel = document.getElementById('zoom-level')
    if (zoomLevel) zoomLevel.textContent = `${Math.round(this.zoom * 100)}%`

    const zoomOut = document.getElementById('zoom-out-btn')
    const zoomIn = document.getElementById('zoom-in-btn')
    if (zoomOut) zoomOut.disabled = this.zoom <= 0.25
    if (zoomIn) zoomIn.disabled = this.zoom >= 2.0

    // Update inputs badge
    const inputsBtn = document.getElementById('toggle-inputs-btn')
    if (inputsBtn) {
      const inputCount = Object.keys(this.inputs).length
      const badge = inputsBtn.querySelector('.badge')
      if (inputCount > 0) {
        if (badge) {
          badge.textContent = inputCount
        } else {
          inputsBtn.insertAdjacentHTML('beforeend', `<span class="badge badge-sm badge-primary">${inputCount}</span>`)
        }
      } else if (badge) {
        badge.remove()
      }
    }
  },

  renderTempEdge(e) {
    const tempGroup = document.getElementById('temp-edge-group')
    if (!tempGroup || !this.edgeStartNode) return

    const svg = document.getElementById('dag-svg')
    const rect = svg.getBoundingClientRect()
    const endX = (e.clientX - rect.left - this.panX) / this.zoom
    const endY = (e.clientY - rect.top - this.panY) / this.zoom

    // Get start node position (use custom position if available)
    const startPos = this.getNodePosition(this.edgeStartNode)
    if (!startPos) return

    const startX = startPos.x
    const startY = startPos.y + NODE_HEIGHT / 2

    // Calculate bezier curve for temp edge
    const deltaY = endY - startY
    const deltaX = endX - startX
    const curveStrength = Math.min(Math.abs(deltaY) * 0.5, 80)

    const cp1x = startX + (deltaX * 0.1)
    const cp1y = startY + curveStrength
    const cp2x = endX - (deltaX * 0.1)
    const cp2y = endY - Math.min(curveStrength, 20)

    const d = `M ${startX} ${startY} C ${cp1x} ${cp1y}, ${cp2x} ${cp2y}, ${endX} ${endY}`

    // Highlight potential target node
    const targetNode = this.findNodeAtPosition(e)
    const isValidTarget = targetNode && targetNode !== this.edgeStartNode

    tempGroup.innerHTML = `
      <path d="${d}" fill="none" stroke="${isValidTarget ? 'oklch(var(--p))' : 'currentColor'}"
            stroke-width="2" stroke-dasharray="5,5" opacity="0.6"/>
      ${isValidTarget ? `<circle cx="${endX}" cy="${endY}" r="8" fill="oklch(var(--p))" opacity="0.3"/>` : ''}
    `
  },

  clearTempEdge() {
    const tempGroup = document.getElementById('temp-edge-group')
    if (tempGroup) tempGroup.innerHTML = ''
  }
}
