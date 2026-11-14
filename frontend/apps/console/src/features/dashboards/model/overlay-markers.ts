import type {
  ContactKind,
  NotStartedReason,
  ContactMarker,
  EventMarker,
  LimitDefinitionMarker,
  LimitEventMarker,
  LimitMarker,
  MissionEventMarker,
} from "../chart/chart-markers.ts";
import type { ReadyPlacement, WorkspaceFrame } from "./snapshot.ts";
import { frameRows, type Row } from "./widget-data.ts";

/**
 * A time-series placement's overlay frames as the chart's marker inputs (Fix 10 (c)). The
 * snapshot already carries them (WidgetRegistry: optional `limits` and `events` overlays);
 * neither viewer drew them before. The chart takes them typed (chart/chart-markers.ts).
 *
 * - limits, definition intervals (active_from/to + red/yellow low/high) → `limit_definition_interval`
 * - limits, events (time + normalized_state/limit_state)                  → `limit_event`, only on
 *   entry into a red or yellow state (ux: marks on entry, not on every violating sample)
 * - events, intervals (starts_at/ends_at: contacts)                        → `contact_interval`
 * - events, the mission timeline (mission_event_id)                       → `mission_event`
 *   The events source also sends source-health, watermark, capability, backfill and revision
 *   frames (same occurred_at columns); they're evidence, not chart marks (a watermark advances
 *   about once a second during a pass: qa's overlay look), so only the mission timeline is read.
 *
 * `link_id` is the marker's own id: the renderers need one, and the console's chart port treats
 * evidence links as no-ops.
 */
export type OverlayMarkers = Readonly<{
  limitMarkers: readonly LimitMarker[];
  eventMarkers: readonly EventMarker[];
}>;

const num = (v: Row[string] | undefined) => (typeof v === "number" ? v : null);
const text = (v: Row[string] | undefined) => (typeof v === "string" && v ? v : null);
const has = (frame: WorkspaceFrame, ...names: string[]) =>
  names.every((n) => frame.fields.some((f) => f.name === n));

function limitInterval(row: Row, key: string): LimitDefinitionMarker | null {
  const from = num(row.active_from);
  if (from === null) return null;
  const id = `limit-definition-${key}`;
  return {
    marker_type: "limit_definition_interval",
    marker_id: id,
    link_id: id,
    starts_at_ms: from,
    ends_at_ms: num(row.active_to),
    limit_definition_id: text(row.limit_definition_id),
    limit_definition_version: num(row.limit_definition_version),
    limit_set_name: text(row.limit_set_name),
    red_low: num(row.red_low),
    yellow_low: num(row.yellow_low),
    yellow_high: num(row.yellow_high),
    red_high: num(row.red_high),
  };
}

function limitEvent(
  row: Row,
  key: string,
  state: LimitEventMarker["limit_state"],
): LimitEventMarker | null {
  const at = num(row.time);
  if (at === null) return null;
  const id = text(row.limit_event_id) ?? text(row.sample_id) ?? `limit-event-${key}`;
  return {
    marker_type: "limit_event",
    marker_id: id,
    link_id: id,
    timestamp_ms: at,
    limit_state: state,
    normalized_state: text(row.normalized_state),
    limit_event_id: text(row.limit_event_id),
    sample_id: text(row.sample_id),
    limit_definition_id: text(row.limit_definition_id),
  };
}

/** An unknown contact kind draws as neither booked nor flown (a plain band), as before. */
function contactKind(value: string | null): ContactKind | null {
  return value === "scheduled_contact" || value === "realized_contact" ? value : null;
}

function contactInterval(row: Row, key: string): ContactMarker | null {
  const from = num(row.starts_at);
  if (from === null) return null;
  const id = text(row.contact_id) ?? `contact-${key}`;
  return {
    marker_type: "contact_interval",
    marker_id: id,
    link_id: id,
    starts_at_ms: from,
    ends_at_ms: num(row.ends_at),
    label: text(row.label),
    status: text(row.status),
    /** scheduled_contact (booked: dashed) vs realized_contact (flown: filled), ux. */
    kind: contactKind(text(row.kind)),
    /** Ground-station code (api 3d4c70d21). */
    station: text(row.station),
    // Never-started contacts (domain): absent until the events source sends them.
    started: typeof row.started === "boolean" ? row.started : null,
    close_reason: notStartedReason(text(row.close_reason)),
  };
}

function notStartedReason(value: string | null): NotStartedReason | null {
  if (value === null) return null;
  return value === "window_ended" || value === "hand_start_expired" ? value : "unrecognized";
}

function pointEvent(row: Row, key: string): MissionEventMarker | null {
  const at = num(row.occurred_at) ?? num(row.time);
  if (at === null) return null;
  const id = text(row.mission_event_id) ?? text(row.event_id) ?? `event-${key}`;
  return {
    marker_type: "mission_event",
    marker_id: id,
    link_id: id,
    timestamp_ms: at,
    title: text(row.title) ?? text(row.label) ?? text(row.kind),
    severity: text(row.severity),
  };
}

/** red/yellow (or critical/caution) entries only: a mark where the state changes into a violation. */
const violation = (row: Row): LimitEventMarker["limit_state"] | null => {
  const state = text(row.limit_state) ?? text(row.normalized_state);
  if (state === "red" || state === "critical") return "red";
  if (state === "yellow" || state === "caution") return "yellow";
  return null;
};
function limitEntries(frame: WorkspaceFrame, f: number): LimitEventMarker[] {
  const rows = frameRows(frame)
    .map((row, r) => ({ row, r }))
    .filter(({ row }) => num(row.time) !== null)
    .sort((a, b) => (num(a.row.time) ?? 0) - (num(b.row.time) ?? 0));
  let previous: string | null = null;
  return rows.flatMap(({ row, r }) => {
    const state = violation(row);
    const entry = state !== null && state !== previous;
    previous = state;
    const marker = entry ? limitEvent(row, `${f}-${r}`, state) : null;
    return marker ? [marker] : [];
  });
}

function collect<M>(
  frames: readonly WorkspaceFrame[],
  pick: (frame: WorkspaceFrame) => ((row: Row, key: string) => M | null) | null,
): M[] {
  return frames.flatMap((frame, f) => {
    const read = pick(frame);
    return read
      ? frameRows(frame).flatMap((row, r) => {
          const marker = read(row, `${f}-${r}`);
          return marker ? [marker] : [];
        })
      : [];
  });
}

export function overlayMarkers(placement: ReadyPlacement): OverlayMarkers {
  const limits = placement.frames.filter((f) => f.role === "limits");
  const events = placement.frames.filter((f) => f.role === "events");
  return {
    limitMarkers: [
      ...collect(limits, (f) => (has(f, "active_from") ? limitInterval : null)),
      ...limits.flatMap((f, i) =>
        !has(f, "active_from") && has(f, "time") ? limitEntries(f, i) : [],
      ),
    ],
    eventMarkers: collect<EventMarker>(events, (f) =>
      has(f, "starts_at") ? contactInterval : has(f, "mission_event_id") ? pointEvent : null,
    ),
  };
}
