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
// V2 widgets
import "./command_widget"
import "./procedure_widget"
import "./fleet_health_widget"
import "./alarm_widget"

// Re-export factory and base class
export { WidgetFactory, BaseWidget, registerWidget } from "../dashboard/widget_factory"

// Export widget classes for direct use
export { LineChartWidget } from "./line_chart_widget"
export { ValueDisplayWidget } from "./value_display_widget"
export { GaugeWidget } from "./gauge_widget"
export { TableWidget } from "./table_widget"
// V2 widgets
export { CommandWidget } from "./command_widget"
export { ProcedureWidget } from "./procedure_widget"
export { FleetHealthWidget } from "./fleet_health_widget"
export { AlarmWidget } from "./alarm_widget"
