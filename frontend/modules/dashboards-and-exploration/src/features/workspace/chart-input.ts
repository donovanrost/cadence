import { record } from "@cadence/plugin-sdk/admission";
import type { ChartEnvelope, ChartPoint } from "./chart-points";

export const textValue = (value: unknown): string | null =>
  typeof value === "string" && value ? value : null;
const markerTextFields = [
  "annotation_id",
  "color",
  "contact_id",
  "data_link_target",
  "data_link_target_id",
  "data_source_id",
  "data_view",
  "dataset",
  "dependency_fingerprint",
  "display_mode",
  "freshness_state",
  "geometry",
  "label",
  "layer_id",
  "limit_definition_id",
  "limit_set_name",
  "limit_event_id",
  "link_id",
  "logical_source",
  "marker_id",
  "marker_type",
  "mission_event_id",
  "normalized_state",
  "observable_id",
  "provider_id",
  "realm",
  "replay_run_id",
  "requested_data_source_id",
  "requested_data_view",
  "requested_dataset",
  "requested_realm",
  "requested_source_binding_id",
  "requested_validity_state",
  "revision_state",
  "sample_id",
  "severity",
  "source_binding_id",
  "source_request_id",
  "source_watermark_event_id",
  "status",
  "summary",
  "target",
  "target_id",
  "telemetry_backfill_lifecycle_event_id",
  "telemetry_revision_decision_event_id",
  "text",
  "time_axis",
  "time_mode",
  "title",
  "warning_code",
  "placement_id",
  "series_role",
  "compare_of",
] as const;
const markerNumberFields = [
  "complete_through_ms",
  "ends_at_ms",
  "event_count",
  "limit_definition_version",
  "limit_divergence_count",
  "observed_at_ms",
  "red_high",
  "red_low",
  "starts_at_ms",
  "timestamp_ms",
  "yellow_high",
  "yellow_low",
] as const;
const metadataFields = [
  "realm",
  "data_view",
  "data_source_id",
  "source_binding_id",
  "replay_run_id",
] as const;
/** Render-only projection. Evidence actions still go through the owning runtime port. */
export type ChartMarker = Partial<Record<(typeof markerTextFields)[number], string | null>> &
  Partial<Record<(typeof markerNumberFields)[number], number | null>> & {
    metadata?: Partial<Record<(typeof metadataFields)[number], string | null>>;
    tags?: string[];
    synthetic_limit_analysis?: boolean;
    selected_limit_clock?: unknown;
    selected_limit_definition_intervals?: unknown;
  };
export function readSelection(value: unknown): ChartMarker | null {
  if (!record(value)) return null;
  const marker: ChartMarker = {};
  for (const key of markerTextFields) if (key in value) marker[key] = textValue(value[key]);
  for (const key of markerNumberFields) {
    if (!(key in value)) continue;
    const number = value[key];
    // Native selections may carry numeric timestamps as text. Never coerce null into epoch zero.
    marker[key] =
      number === null || number === "" || number === undefined
        ? null
        : (typeof number === "number" || typeof number === "string") &&
            Number.isFinite(Number(number))
          ? Number(number)
          : null;
  }
  if (record(value.metadata)) {
    const metadata: NonNullable<ChartMarker["metadata"]> = {};
    for (const key of metadataFields)
      if (key in value.metadata) metadata[key] = textValue(value.metadata[key]);
    marker.metadata = metadata;
  }
  if (Array.isArray(value.tags))
    marker.tags = value.tags.filter((tag): tag is string => typeof tag === "string");
  if (typeof value.synthetic_limit_analysis === "boolean")
    marker.synthetic_limit_analysis = value.synthetic_limit_analysis;
  if ("selected_limit_clock" in value) marker.selected_limit_clock = value.selected_limit_clock;
  if ("selected_limit_definition_intervals" in value)
    marker.selected_limit_definition_intervals = value.selected_limit_definition_intervals;
  return marker;
}
export function readMarkers(value: unknown): ChartMarker[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((marker) => {
    const parsed = readSelection(marker);
    return parsed ? [parsed] : [];
  });
}
export type ChartSeries = {
  id: string;
  label: string;
  observable_id: string | null;
  unit: string | null;
  source: unknown;
  frame_id: string | null;
  field: string | null;
  time_axis: string | null;
  sampling: unknown;
  decimation: unknown;
  data_source_id: string | null;
  source_binding_id: string | null;
  role: string;
  compare_of: string | null;
  envelope: ChartEnvelope | null;
  points: ChartPoint[];
};
export type PlotSeries =
  | { kind: "line"; seriesIndex: number }
  | { kind: "envelope_low" | "envelope_high"; seriesIndex: number; values: (number | null)[] };
