/**
 * Panel Layout Manager
 *
 * Custom CSS-based panel layout with snap-to-close behavior.
 * Replaces GoldenLayout for simpler, more controlled panel management.
 *
 * Layout Structure:
 * +--------------------------------------------------+
 * |  Nav    |        Dashboard         |   Context   |
 * |  Panel  |        (center)          |   Panel     |
 * +--------------------------------------------------+
 * |            Quick Access Bar                      |
 * +--------------------------------------------------+
 */

// Panel configuration
const PANEL_CONFIG = {
  navigation: {
    openWidth: 220,
    closedWidth: 48,
    snapThreshold: 120, // If dragged below this, snap closed
    minDragWidth: 48,
    maxDragWidth: 300,
    side: 'left'
  },
  context: {
    openWidth: 260,
    closedWidth: 52,
    snapThreshold: 140,
    minDragWidth: 52,
    maxDragWidth: 400,
    side: 'right'
  },
  quickAccess: {
    openHeight: 52,
    closedHeight: 0,
    snapThreshold: 26
  }
}

/**
 * EventEmitter mixin for panel communication
 */
class EventEmitter {
  constructor() {
    this._events = {}
  }

  on(event, callback) {
    if (!this._events[event]) {
      this._events[event] = []
    }
    this._events[event].push(callback)
    return () => this.off(event, callback)
  }

  off(event, callback) {
    if (!this._events[event]) return
    this._events[event] = this._events[event].filter(cb => cb !== callback)
  }

  emit(event, data) {
    if (!this._events[event]) return
    this._events[event].forEach(cb => cb(data))
  }
}

/**
 * Panel Layout Manager
 */
export class PanelLayoutManager extends EventEmitter {
  constructor(container, options = {}) {
    super()
    this.container = container
    this.options = options
    this.panels = {}
    this.panelStates = {
      navigation: { open: true, width: PANEL_CONFIG.navigation.openWidth },
      context: { open: true, width: PANEL_CONFIG.context.openWidth },
      quickAccess: { open: true }
    }
    this._resizeHandler = null
    this._isDragging = false
    this._dragPanel = null
  }

  /**
   * Initialize the layout
   */
  init() {
    this._createLayout()
    this._bindResizeHandlers()
    this._bindToggleButtons()
    return this
  }

  _createLayout() {
    this.container.innerHTML = `
      <div class="panel-layout">
        <!-- Navigation Panel (Left) -->
        <aside class="panel-nav" id="panel-nav" style="width: ${PANEL_CONFIG.navigation.openWidth}px">
          <div class="panel-content" id="nav-content"></div>
          <div class="panel-resize-handle panel-resize-right" data-panel="navigation"></div>
          <button class="panel-toggle panel-toggle-nav" data-panel="navigation" title="Toggle Navigation">
            <svg class="toggle-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M15 18l-6-6 6-6"/>
            </svg>
          </button>
        </aside>

        <!-- Main Content Area -->
        <main class="panel-main">
          <!-- Dashboard (GridStack container) -->
          <div class="panel-dashboard" id="panel-dashboard">
            <div class="dashboard-toolbar" id="dashboard-toolbar"></div>
            <div class="dashboard-grid-wrapper">
              <div class="grid-stack" id="gridstack-container"></div>
            </div>
          </div>

          <!-- Quick Access Bar -->
          <div class="panel-quick-access" id="panel-quick-access">
            <div class="quick-access-content" id="quick-access-content"></div>
            <button class="panel-toggle panel-toggle-quick" data-panel="quickAccess" title="Toggle Quick Access">
              <svg class="toggle-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M6 9l6 6 6-6"/>
              </svg>
            </button>
          </div>
        </main>

        <!-- Context Panel (Right) -->
        <aside class="panel-context" id="panel-context" style="width: ${PANEL_CONFIG.context.openWidth}px">
          <button class="panel-toggle panel-toggle-context" data-panel="context" title="Toggle Context">
            <svg class="toggle-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M9 18l6-6-6-6"/>
            </svg>
          </button>
          <div class="panel-resize-handle panel-resize-left" data-panel="context"></div>
          <div class="panel-content" id="context-content"></div>
        </aside>
      </div>
    `

    // Store references
    this.elements = {
      layout: this.container.querySelector('.panel-layout'),
      nav: this.container.querySelector('#panel-nav'),
      navContent: this.container.querySelector('#nav-content'),
      main: this.container.querySelector('.panel-main'),
      dashboard: this.container.querySelector('#panel-dashboard'),
      toolbar: this.container.querySelector('#dashboard-toolbar'),
      gridStack: this.container.querySelector('#gridstack-container'),
      quickAccess: this.container.querySelector('#panel-quick-access'),
      quickAccessContent: this.container.querySelector('#quick-access-content'),
      context: this.container.querySelector('#panel-context'),
      contextContent: this.container.querySelector('#context-content')
    }
  }

  _bindResizeHandlers() {
    const handles = this.container.querySelectorAll('.panel-resize-handle')

    handles.forEach(handle => {
      handle.addEventListener('mousedown', (e) => this._startDrag(e, handle))
    })

    // Global mouse events for drag
    document.addEventListener('mousemove', (e) => this._onDrag(e))
    document.addEventListener('mouseup', (e) => this._endDrag(e))
  }

  _startDrag(e, handle) {
    e.preventDefault()
    this._isDragging = true
    this._dragPanel = handle.dataset.panel
    this._dragStartX = e.clientX
    this._dragStartWidth = this.panelStates[this._dragPanel].width ||
      (this._dragPanel === 'navigation' ? PANEL_CONFIG.navigation.openWidth : PANEL_CONFIG.context.openWidth)

    document.body.style.cursor = 'col-resize'
    document.body.style.userSelect = 'none'

    // Add dragging class for visual feedback
    this.elements.layout.classList.add('is-dragging')
  }

  _onDrag(e) {
    if (!this._isDragging || !this._dragPanel) return

    const config = PANEL_CONFIG[this._dragPanel]
    const deltaX = e.clientX - this._dragStartX

    let newWidth
    if (config.side === 'left') {
      newWidth = this._dragStartWidth + deltaX
    } else {
      newWidth = this._dragStartWidth - deltaX
    }

    // Clamp to min/max
    newWidth = Math.max(config.minDragWidth, Math.min(config.maxDragWidth, newWidth))

    // Update panel width
    this._setPanelWidth(this._dragPanel, newWidth)

    // Visual feedback for snap zone
    const panelEl = this._dragPanel === 'navigation' ? this.elements.nav : this.elements.context
    panelEl.classList.toggle('in-snap-zone', newWidth < config.snapThreshold)
  }

  _endDrag(e) {
    if (!this._isDragging) return

    const config = PANEL_CONFIG[this._dragPanel]
    const currentWidth = this.panelStates[this._dragPanel].width

    // Check if we should snap
    if (currentWidth < config.snapThreshold) {
      // Snap closed
      this._closePanel(this._dragPanel)
    } else {
      // Keep open at current width (or snap to open width if close to it)
      const distToOpen = Math.abs(currentWidth - config.openWidth)
      if (distToOpen < 30) {
        this._setPanelWidth(this._dragPanel, config.openWidth)
      }
      this.panelStates[this._dragPanel].open = true
    }

    // Clean up
    this._isDragging = false
    this._dragPanel = null
    document.body.style.cursor = ''
    document.body.style.userSelect = ''
    this.elements.layout.classList.remove('is-dragging')

    // Remove snap zone indicator
    this.elements.nav.classList.remove('in-snap-zone')
    this.elements.context.classList.remove('in-snap-zone')

    // Emit state change
    this.emit('layout:changed', this._getLayoutState())
  }

  _setPanelWidth(panelName, width) {
    const panelEl = panelName === 'navigation' ? this.elements.nav : this.elements.context
    panelEl.style.width = `${width}px`
    this.panelStates[panelName].width = width

    // Update collapsed state class
    const config = PANEL_CONFIG[panelName]
    const isCollapsed = width <= config.closedWidth + 10
    panelEl.classList.toggle('collapsed', isCollapsed)
  }

  _bindToggleButtons() {
    const toggles = this.container.querySelectorAll('.panel-toggle')

    toggles.forEach(btn => {
      btn.addEventListener('click', () => {
        const panel = btn.dataset.panel
        this._togglePanel(panel)
      })
    })
  }

  _togglePanel(panelName) {
    const state = this.panelStates[panelName]

    if (state.open) {
      this._closePanel(panelName)
    } else {
      this._openPanel(panelName)
    }
  }

  _openPanel(panelName) {
    const config = PANEL_CONFIG[panelName]
    const state = this.panelStates[panelName]

    if (panelName === 'quickAccess') {
      this.elements.quickAccess.classList.remove('collapsed')
    } else {
      this._setPanelWidth(panelName, config.openWidth)
      const panelEl = panelName === 'navigation' ? this.elements.nav : this.elements.context
      panelEl.classList.remove('collapsed')
    }

    state.open = true
    this._updateToggleIcon(panelName, true)
    this.emit('panel:opened', { panel: panelName })
    this.emit('layout:changed', this._getLayoutState())
  }

  _closePanel(panelName) {
    const config = PANEL_CONFIG[panelName]
    const state = this.panelStates[panelName]

    if (panelName === 'quickAccess') {
      this.elements.quickAccess.classList.add('collapsed')
    } else {
      this._setPanelWidth(panelName, config.closedWidth)
      const panelEl = panelName === 'navigation' ? this.elements.nav : this.elements.context
      panelEl.classList.add('collapsed')
    }

    state.open = false
    this._updateToggleIcon(panelName, false)
    this.emit('panel:closed', { panel: panelName })
    this.emit('layout:changed', this._getLayoutState())
  }

  _updateToggleIcon(panelName, isOpen) {
    const btn = this.container.querySelector(`.panel-toggle[data-panel="${panelName}"]`)
    if (!btn) return

    const icon = btn.querySelector('.toggle-icon')
    if (icon) {
      // Rotate icon based on state
      if (panelName === 'navigation') {
        icon.style.transform = isOpen ? '' : 'rotate(180deg)'
      } else if (panelName === 'context') {
        icon.style.transform = isOpen ? '' : 'rotate(180deg)'
      } else if (panelName === 'quickAccess') {
        icon.style.transform = isOpen ? '' : 'rotate(180deg)'
      }
    }
  }

  _getLayoutState() {
    return {
      navigation: { ...this.panelStates.navigation },
      context: { ...this.panelStates.context },
      quickAccess: { ...this.panelStates.quickAccess }
    }
  }

  /**
   * Get the GridStack container element
   */
  getGridContainer() {
    return this.elements.gridStack
  }

  /**
   * Get the toolbar container element
   */
  getToolbarContainer() {
    return this.elements.toolbar
  }

  /**
   * Get a panel's content container
   */
  getPanelContent(panelName) {
    switch (panelName) {
      case 'navigation': return this.elements.navContent
      case 'context': return this.elements.contextContent
      case 'quickAccess': return this.elements.quickAccessContent
      default: return null
    }
  }

  /**
   * Load a saved layout state
   */
  loadState(state) {
    if (!state) return

    if (state.navigation) {
      this.panelStates.navigation = { ...this.panelStates.navigation, ...state.navigation }
      if (state.navigation.open === false) {
        this._closePanel('navigation')
      } else if (state.navigation.width) {
        this._setPanelWidth('navigation', state.navigation.width)
      }
    }

    if (state.context) {
      this.panelStates.context = { ...this.panelStates.context, ...state.context }
      if (state.context.open === false) {
        this._closePanel('context')
      } else if (state.context.width) {
        this._setPanelWidth('context', state.context.width)
      }
    }

    if (state.quickAccess) {
      this.panelStates.quickAccess = { ...this.panelStates.quickAccess, ...state.quickAccess }
      if (state.quickAccess.open === false) {
        this._closePanel('quickAccess')
      }
    }
  }

  /**
   * Save current layout state
   */
  saveState() {
    return this._getLayoutState()
  }

  /**
   * Clean up
   */
  destroy() {
    // Remove event listeners would go here
    this.container.innerHTML = ''
  }
}

export function createPanelLayout(container, options) {
  return new PanelLayoutManager(container, options)
}

export default PanelLayoutManager
