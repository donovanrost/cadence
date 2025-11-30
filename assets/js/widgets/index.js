/**
 * Widget Index
 *
 * Imports and exports all widget types.
 * This file ensures all widgets are registered with the factory.
 */

// Import widgets (this registers them with the factory)
import "./line_chart_widget"
import "./value_display_widget"
import "./gauge_widget"
import "./table_widget"

// Re-export factory and base class
export { WidgetFactory, BaseWidget, registerWidget } from "../dashboard/widget_factory"

// Export widget classes for direct use
export { LineChartWidget } from "./line_chart_widget"
export { ValueDisplayWidget } from "./value_display_widget"
export { GaugeWidget } from "./gauge_widget"
export { TableWidget } from "./table_widget"
