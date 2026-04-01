/**
 * Widget Factory
 *
 * Factory for creating dashboard widgets.
 * Provides a registry of widget types and their constructors.
 */

// Widget type registry
const widgetTypes = new Map()

/**
 * Register a widget type.
 *
 * @param {string} type - Widget type name
 * @param {Function} constructor - Widget constructor/class
 */
export function registerWidget(type, constructor) {
  widgetTypes.set(type, constructor)
}

/**
 * Widget Factory class.
 */
export class WidgetFactory {
  /**
   * Create a widget instance.
   *
   * @param {string} type - Widget type
   * @param {Object} options - Widget options
   * @returns {Object} Widget instance
   */
  static create(type, options) {
    const Constructor = widgetTypes.get(type)

    if (!Constructor) {
      console.warn(`[WidgetFactory] Unknown widget type: ${type}, using placeholder`)
      return new PlaceholderWidget(options)
    }

    return new Constructor(options)
  }

  /**
   * Get available widget types.
   *
   * @returns {Array<{type: string, name: string, description: string, icon: string}>}
   */
  static getAvailableTypes() {
    const types = []

    for (const [type, Constructor] of widgetTypes) {
      types.push({
        type,
        name: Constructor.displayName || type,
        description: Constructor.description || "",
        icon: Constructor.icon || "chart"
      })
    }

    return types
  }

  /**
   * Check if a widget type is registered.
   *
   * @param {string} type - Widget type
   * @returns {boolean}
   */
  static hasType(type) {
    return widgetTypes.has(type)
  }
}

/**
 * Base Widget class that all widgets should extend.
 */
export class BaseWidget {
  static displayName = "Widget"
  static description = "A dashboard widget"
  static icon = "square"

  constructor(options) {
    this.id = options.id
    this.container = options.container
    this.config = options.config || {}
    this.manager = options.manager
    this.type = this.constructor.name.replace("Widget", "").toLowerCase()
    this.subscriptions = []
    this.initialized = false
  }

  /**
   * Initialize the widget. Override in subclasses.
   */
  init() {
    this.render()
    this.initialized = true
  }

  /**
   * Render the widget content. Override in subclasses.
   */
  render() {
    this.container.innerHTML = `
      <div class="widget-inner h-full flex flex-col">
        <div class="widget-header flex items-center justify-between p-2 border-b border-base-300">
          <span class="widget-title text-sm font-semibold">${this.config.title || "Widget"}</span>
          <button class="widget-config-btn btn btn-ghost btn-xs" title="Configure">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/>
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/>
            </svg>
          </button>
        </div>
        <div class="widget-content flex-1 overflow-hidden p-2">
          ${this.renderContent()}
        </div>
      </div>
    `

    this._bindConfigButton()
  }

  /**
   * Render the widget content area. Override in subclasses.
   *
   * @returns {string} HTML content
   */
  renderContent() {
    return '<p class="text-base-content/50">No content</p>'
  }

  /**
   * Update the widget configuration.
   *
   * @param {Object} config - New configuration
   */
  updateConfig(config) {
    this.config = { ...this.config, ...config }
    this.render()
  }

  /**
   * Get the current configuration.
   *
   * @returns {Object}
   */
  getConfig() {
    return { ...this.config }
  }

  /**
   * Open the configuration dialog.
   */
  openConfig() {
    // Override in subclasses to show a config modal
    console.log("[Widget] Config dialog not implemented for:", this.type)
  }

  /**
   * Destroy the widget and clean up.
   */
  destroy() {
    // Unsubscribe from all telemetry
    for (const unsub of this.subscriptions) {
      unsub()
    }
    this.subscriptions = []

    // Clear container
    this.container.innerHTML = ""
  }

  // Private methods

  _bindConfigButton() {
    const btn = this.container.querySelector(".widget-config-btn")
    if (btn) {
      btn.addEventListener("click", (e) => {
        e.stopPropagation()
        this.openConfig()
      })
    }
  }
}

/**
 * Placeholder widget for unknown types.
 */
class PlaceholderWidget extends BaseWidget {
  static displayName = "Unknown Widget"
  static description = "Placeholder for unknown widget types"

  renderContent() {
    return `
      <div class="flex items-center justify-center h-full">
        <p class="text-error text-sm">Unknown widget type</p>
      </div>
    `
  }
}

// Register placeholder
registerWidget("placeholder", PlaceholderWidget)

export default {
  WidgetFactory,
  BaseWidget,
  registerWidget
}
