/** Chart input boundary. External data is admitted by the chart model. */
export interface TelemetryChartProps {
  chart_id: string;
  widget_id: string;
  placement_id: string;
  window_seconds: number;
  correlation_group: string;
  edit_mode?: boolean;
  show_min_max_band?: boolean;
  legend_mode?: string;
  line_width?: string;
  fill_opacity?: number;
  span_gaps?: boolean;
  show_points?: boolean;
  axis_mode?: string;
  shared_tooltip?: boolean;
  label?: string;
  unit?: string;
  backfill?: unknown[] | Record<string, unknown>;
  compare_backfill?: unknown[] | Record<string, unknown>;
  limit_markers?: unknown[];
  event_markers?: unknown[];
  annotations?: unknown[];
  selected_ref?: Record<string, unknown> | null;
  time_mode?: string;
  time_from?: string;
  time_to?: string;
  time_axis?: string;
  replay_run_id?: string;
  data_realm?: string;
  data_view?: string;
  compare_data_view?: string;
  data_source_id?: string;
  source_binding_id?: string;
  data_management_badges?: string;
  compare_data_management_badges?: string;
  engine_backed?: boolean;
}
