import type { ChartAnnotation, EventMarker, LimitMarker } from "./chart-markers.ts";

/** Display options, as the snapshot decodes them (model/snapshot.ts; unknown values are dropped). */
export type ChartLegendMode = "auto" | "always" | "hidden";
export type ChartLineWidth = "thin" | "normal" | "bold";
export type ChartAxisMode = "unit" | "shared";
/** The snapshot's time modes, plus `snapshot` (a live range re-sent whole, without appends). */
export type ChartTimeMode =
  | "live"
  | "range"
  | "archive"
  | "replay_run"
  | "snapshot"
  | "unrecognized"
  | "";

/** Chart input boundary. Series payloads are admitted by the chart model; overlays come typed. */
export interface TelemetryChartProps {
  chart_id: string;
  widget_id: string;
  placement_id: string;
  window_seconds: number;
  correlation_group: string;
  edit_mode?: boolean;
  show_min_max_band?: boolean;
  legend_mode?: ChartLegendMode;
  line_width?: ChartLineWidth;
  fill_opacity?: number;
  span_gaps?: boolean;
  show_points?: boolean;
  axis_mode?: ChartAxisMode;
  shared_tooltip?: boolean;
  label?: string;
  unit?: string;
  backfill?: unknown[] | Record<string, unknown>;
  compare_backfill?: unknown[] | Record<string, unknown>;
  limit_markers?: readonly LimitMarker[];
  event_markers?: readonly EventMarker[];
  annotations?: readonly ChartAnnotation[];
  time_mode?: ChartTimeMode;
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
