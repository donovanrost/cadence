import type { WorkspaceAnnotation } from "../model/snapshot.ts";

/**
 * The chart's overlay inputs (typing audit Fix 10). Built in-process from the snapshot's overlay
 * frames (model/overlay-markers.ts) and annotations (widgets/TimeSeriesWidget.vue), so they arrive
 * typed: the chart never re-parses them. `link_id` is the id a mark's data link carries.
 */
type MarkerIds = { readonly marker_id: string; readonly link_id: string };
/** A span on the time axis; an open end runs to the latest sample. */
export type ChartInterval = { readonly starts_at_ms: number; readonly ends_at_ms: number | null };

export type LimitDefinitionMarker = MarkerIds &
  ChartInterval & {
    readonly marker_type: "limit_definition_interval";
    readonly limit_definition_id: string | null;
    readonly limit_set_name: string | null;
    readonly limit_definition_version: number | null;
    readonly red_low: number | null;
    readonly yellow_low: number | null;
    readonly yellow_high: number | null;
    readonly red_high: number | null;
  };

/** A series entering a violation: red (crit diamond) or yellow (caution triangle). */
export type LimitEventMarker = MarkerIds & {
  readonly marker_type: "limit_event";
  readonly timestamp_ms: number;
  readonly limit_state: "red" | "yellow";
  readonly normalized_state: string | null;
  readonly limit_event_id: string | null;
  readonly sample_id: string | null;
  readonly limit_definition_id: string | null;
};

/** A pass: `scheduled_contact` is booked (dashed), `realized_contact` flown (tinted). */
export type ContactKind = "scheduled_contact" | "realized_contact";
/** Why a realized contact closed without starting (domain); a newer reason reads "unrecognized". */
export type NotStartedReason = "window_ended" | "hand_start_expired" | "unrecognized";
export type ContactMarker = MarkerIds &
  ChartInterval & {
    readonly marker_type: "contact_interval";
    readonly label: string | null;
    readonly status: string | null;
    /** Ground-station code; null when the contact has no transport (the band falls back to label). */
    readonly station: string | null;
    readonly kind: ContactKind | null;
    /**
     * A realized contact: true once active, false when it closed without starting (its span is
     * then the scheduled window it belonged to); null for bookings and not-yet-started contacts.
     */
    readonly started: boolean | null;
    readonly close_reason: NotStartedReason | null;
  };

/** Its `marker_id` is the mission_event_id when the row has one (overlay-markers pointEvent). */
export type MissionEventMarker = MarkerIds & {
  readonly marker_type: "mission_event";
  readonly timestamp_ms: number;
  readonly title: string | null;
  readonly severity: string | null;
};

export type LimitMarker = LimitDefinitionMarker | LimitEventMarker;
export type EventMarker = ContactMarker | MissionEventMarker;

export type ChartAnnotation = ChartInterval & {
  readonly annotation_id: string;
  readonly title: string;
  readonly severity: WorkspaceAnnotation["severity"];
  readonly geometry: "point" | "interval";
};

/** A marker's times on the x axis, in ms (an open interval end has none). */
export function markerTimes(marker: LimitMarker | EventMarker): number[] {
  switch (marker.marker_type) {
    case "limit_definition_interval":
    case "contact_interval":
      return marker.ends_at_ms === null
        ? [marker.starts_at_ms]
        : [marker.starts_at_ms, marker.ends_at_ms];
    case "limit_event":
    case "mission_event":
      return [marker.timestamp_ms];
  }
}
